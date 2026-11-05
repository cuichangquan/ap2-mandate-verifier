# frozen_string_literal: true

module AP2MandateVerifier
  # Application-side single-attempt coordination, not a PSP execution engine.
  module PaymentAcceptance
    SCOPE = %w[tenant_id merchant_id operation_id approval_id occurrence_id order_id].freeze
    class Invalid < ArgumentError
      def initialize = super("invalid payment acceptance information")
    end
    class Unavailable < StandardError
      def initialize = super("payment acceptance storage unavailable")
    end
    class Conflict < StandardError; end

    class Ticket
      def initialize(key, fence)
        @key, @fence = key.freeze, fence.freeze
        freeze
      end
      def inspect = "#<AP2MandateVerifier::PaymentAcceptance::Ticket>"
      private
      attr_reader :key, :fence
      private_class_method :new
    end
    class Result
      attr_reader :status, :ticket, :closed_sd_jwt, :reference, :receipt_jwt, :processor_key, :signed_wires
      def initialize(status, record = nil, ticket = nil)
        @status, @ticket = status, ticket
        if record
          @closed_sd_jwt, @reference, @receipt_jwt = record.values_at("closed_sd_jwt", "reference", "receipt_jwt").map { |v| v&.freeze }
          @processor_key = record.fetch("processor_key").freeze
          @signed_wires = ResearchEvidence.send(:copy_frozen, record.fetch("signed_wires"))
        end
        freeze
      end
      def inspect = "#<AP2MandateVerifier::PaymentAcceptance::Result status=#{status}>"
      private_class_method :new
    end
    class Execution
      attr_reader :processor_key, :closed_sd_jwt, :reference, :payment, :valid_until
      def initialize(record)
        @processor_key, @closed_sd_jwt, @reference = record.values_at("processor_key", "closed_sd_jwt", "reference").map(&:freeze)
        @payment = ResearchEvidence.send(:copy_frozen, record.fetch("payment"))
        @valid_until = record.fetch("valid_until")
        freeze
      end
      def inspect = "#<AP2MandateVerifier::PaymentAcceptance::Execution>"
      private_class_method :new
    end

    class Service
      def initialize(**arguments)
        raise Invalid.new, cause: nil unless arguments.keys == [:store]
        @store = arguments.fetch(:store)
      end
      def inspect = "#<AP2MandateVerifier::PaymentAcceptance::Service>"
      # Every call starts from raw verifier inputs, never a caller-made proof.
      def accept(mode:, verification_inputs:, tenant_id:, merchant_id:, operation_id:, approval_id:, occurrence_id:, order_id:)
        scope = PaymentAcceptance.scope!({"tenant_id" => tenant_id, "merchant_id" => merchant_id, "operation_id" => operation_id,
          "approval_id" => approval_id, "occurrence_id" => occurrence_id, "order_id" => order_id})
        record = verified_record(mode, verification_inputs, scope)
        @store.reserve!(scope: scope, instruction: record.fetch("instruction"), record: record)
      rescue Conflict
        Result.send(:new, :conflict)
      rescue Unavailable
        Result.send(:new, :unavailable)
      rescue StandardError, LoadError
        Result.send(:new, :rejected)
      end

      def start(ticket:, verification_inputs:)
        old = @store.ticket_record!(ticket: ticket)
        fresh = verified_record(old.fetch("mode").to_sym, verification_inputs, old.fetch("scope"))
        raise Invalid unless old.fetch("instruction") == fresh.fetch("instruction") && old.fetch("signed_wires") == fresh.fetch("signed_wires")
        record = if LongPayment.profile?(old.fetch("profile_ref"))
          @store.start_long!(ticket: ticket, verified_at: fresh.fetch("accepted_at"),
            instruction: fresh.fetch("instruction"), signed_wires: fresh.fetch("signed_wires"),
            authority_binding: fresh.fetch("authority_binding"))
        else
          @store.start!(ticket: ticket, verified_at: fresh.fetch("accepted_at"),
            instruction: fresh.fetch("instruction"), signed_wires: fresh.fetch("signed_wires"))
        end
        Execution.send(:new, record) if record
      rescue StandardError, LoadError
        nil # An uncertain commit NEVER produces an execution handle.
      end

      private
      def verified_record(mode, verification_inputs, scope)
        args = PaymentAcceptance.copy!(verification_inputs)
        raise Invalid unless args.instance_of?(Hash)
        profile = PaymentAcceptance.profile!(mode, args.fetch(:profile_ref, mode == :selective ? SelectivePayment::PROFILE_REF : Payment::PROFILE_REF))
        result = case mode
        when :direct, :conditional
          raise Invalid unless args[:checkout_mode] == mode
          LongPayment.profile?(profile) ? LongPayment.verify(**args) : Payment.verify(**args)
        when :selective then SelectivePayment.verify(**args)
        else raise Invalid
        end
        raise Invalid unless result.verified?
        checkout_args = args.fetch(:checkout_inputs)
        if mode == :direct
          checkout = Buyer.verify(**checkout_args)
          raise Invalid unless checkout.verified?
          cart = checkout.checkout
          valid_until = [checkout.expires_at, result.expires_at].min
        else
          checkout = AP2MandateVerifier.verify_checkout(**checkout_args)
          raise Invalid unless checkout.success?
          raise Invalid unless checkout.evidence["checkout_binding"].fetch("tenant_id") == scope["tenant_id"]
          cart = Payment.send(:jwt_payload!, checkout_args.fetch(:host_checkout_jws), "JWT")
          valid_until = [checkout.evidence["valid_until"], result.expires_at].min
        end
        raise Invalid unless cart.fetch("id") == scope["order_id"] && cart.fetch("merchant").fetch("id") == scope["merchant_id"]
        payment = result.payment.slice(*PaymentPolicy.fields(profile))
        instruction = PaymentAcceptance.instruction!(mode, profile, cart, payment)
        closed = InputValidator.snapshot!(args.fetch(:closed_sd_jwt), max_bytes: 32_769)
        checkout_wires = if mode == :direct
          checkout_args.slice(:closed_sd_jwt, :expected_checkout_jwt)
        else
          checkout_args.slice(:root_presentation, :terminal_jws, :host_checkout_jws)
        end
        authority = nil
        if LongPayment.profile?(profile)
          authority = LongPayment.authority!(checkout_inputs: checkout_args,
            provider_key: args.fetch(:trusted_provider_public_key_pem), agent_key: args.fetch(:expected_agent_public_key_pem),
            merchant_id: scope.fetch("merchant_id"), verified_at: args.fetch(:verified_at))
          proof = Payment.send(:jwt_payload!, closed.split("~", 2).first, "kb+sd-jwt")
          valid_until = [valid_until, authority.fetch(:valid_until), proof.fetch("iat") + 301].min
        end
        record = {"scope" => scope, "mode" => mode.to_s, "profile_ref" => profile, "instruction" => instruction,
          "payment" => result.payment, "closed_sd_jwt" => closed, "reference" => result.reference,
          "signed_wires" => {"payment" => args.slice(:open_sd_jwt, :open_presentation, :closed_sd_jwt).transform_keys(&:to_s),
            "checkout" => checkout_wires.transform_keys(&:to_s)},
          "accepted_at" => args.fetch(:verified_at), "valid_until" => valid_until}
        record["authority_binding"] = authority.fetch(:authority_binding) if authority
        record
      end
      public

      def finish(ticket:, receipt_jwt:, verified_at:)
        record = @store.ticket_record!(ticket: ticket)
        finalize(record, receipt_jwt, verified_at, ticket)
      rescue Conflict
        Result.send(:new, :conflict)
      rescue Unavailable
        Result.send(:new, :unavailable)
      rescue StandardError, LoadError
        Result.send(:new, :rejected)
      end

      def unknown(ticket:)
        @store.unknown!(ticket: ticket)
      rescue Unavailable
        Result.send(:new, :unavailable)
      rescue StandardError
        Result.send(:new, :rejected)
      end

      # Receipt reconciliation can finalize an uncertain attempt but cannot
      # recover its fence, reserve it again, or grant another execution handle.
      def reconcile(receipt_jwt:, verified_at:, **scope)
        record = @store.lookup_record!(scope: PaymentAcceptance.scope_keywords!(scope))
        raise Invalid unless record
        finalize(record, receipt_jwt, verified_at, nil)
      rescue Conflict
        Result.send(:new, :conflict)
      rescue Unavailable
        Result.send(:new, :unavailable)
      rescue StandardError, LoadError
        Result.send(:new, :rejected)
      end

      def lookup(**scope)
        record = @store.lookup_record!(scope: PaymentAcceptance.scope_keywords!(scope))
        record ? PaymentAcceptance.result(record) : Result.send(:new, :rejected)
      rescue Unavailable
        Result.send(:new, :unavailable)
      rescue StandardError
        Result.send(:new, :rejected)
      end

      private
      def finalize(record, receipt_jwt, verified_at, ticket)
        jwt = InputValidator.snapshot!(receipt_jwt, max_bytes: 16_384)
        context = record.fetch("receipt_context").transform_keys(&:to_sym)
        raise Invalid unless record.key?("started_at")
        context[:not_before] = [context.fetch(:not_before), record.fetch("started_at")].max
        receipt = PaymentReceipt.verify(jwt: jwt, closed_sd_jwt: record.fetch("closed_sd_jwt"),
          profile_ref: record.fetch("profile_ref") == SelectivePayment::PROFILE_REF ? Payment::PROFILE_REF : record.fetch("profile_ref"),
          verified_at: verified_at, **context)
        raise Invalid unless receipt.verified?
        status = receipt.payment_succeeded? ? "receipt_success" : "receipt_error"
        @store.finish!(scope: record.fetch("scope"), ticket: ticket, receipt_jwt: jwt, status: status)
      end

      %i[accept start finish unknown reconcile lookup].each do |name|
        implementation = instance_method(name)
        required = implementation.parameters.filter_map { |kind, key| key if kind == :keyreq }.freeze
        allowed = implementation.parameters.filter_map { |kind, key| key if %i[keyreq key].include?(kind) }.freeze
        rest = implementation.parameters.any? { |kind,_| kind == :keyrest }
        define_method(name) do |**arguments|
          raise Invalid unless (required - arguments.keys).empty? && (rest || (arguments.keys - allowed).empty?)
          implementation.bind_call(self, **arguments)
        rescue StandardError, LoadError
          name == :start ? nil : Result.send(:new, :rejected)
        end
        public name
      end
    end

    def self.scope!(value)
      scope = copy!(value)
      raise Invalid unless scope.instance_of?(Hash) && scope.keys.sort == SCOPE.sort
      scope.each_value { |v| CheckoutReceipt.send(:text!, v, 256) }
      ResearchEvidence.send(:copy_frozen, scope)
    end
    def self.scope_keywords!(value)
      scope!(copy!(value).transform_keys { |key| key.instance_of?(Symbol) ? key.to_s : key })
    end
    def self.profile!(mode, value)
      raise Invalid unless %i[direct conditional selective].include?(mode)
      PaymentPolicy.profile!(value, selective: mode == :selective)
    end
    def self.instruction!(mode, profile, checkout, payment)
      cart = InputBuilder.send(:copy!, checkout)
      ScopedConstraints.multi_checkout!(cart)
      details = Payment.send(:copy_details!, payment, profile_ref: profile)
      terms = details.reject { |k,_| k == "transaction_id" }
      if terms.key?("execution_date")
        instant = PaymentPolicy.instant!(terms["execution_date"])
        terms["execution_date"] = {"numerator" => instant.numerator, "denominator" => instant.denominator}
      end
      canonical({"mode" => mode.to_s, "profile_ref" => profile, "checkout" => cart, "payment" => terms})
    end
    def self.key(scope)
      digest(canonical(scope.slice("tenant_id", "merchant_id", "operation_id")))
    end
    def self.canonical(value)
      require "json"
      raise Unavailable unless JSON::VERSION == InputValidator::JSON_VERSION
      normalized = case value
      when Hash then value.keys.sort.to_h { |k| [k, JSON.parse(canonical(value[k]))] }
      when Array then value.map { |v| JSON.parse(canonical(v)) }
      else value
      end
      JSON.generate(normalized)
    end
    def self.digest(value) = Digest::SHA256.hexdigest(value)
    def self.result(record)
      status = %w[reserved processing].include?(record.fetch("state")) ? :pending : record.fetch("state").to_sym
      Result.send(:new, status, record)
    end
    # Raw verifier keyword graphs include Symbols. Bound/copy without invoking
    # caller coercions or singleton callbacks, before any signature or storage.
    def self.copy!(value, depth = 0, budget = [0, 0])
      raise Invalid if depth > 20 || (budget[0] += 1) > 4096
      raise Invalid unless Object.instance_method(:singleton_methods).bind_call(value, true).empty?
      klass = Object.instance_method(:class).bind_call(value)
      if klass == String
        s = InputValidator.snapshot!(value)
        raise Invalid if (budget[1] += s.bytesize) > 1_048_576
        s
      elsif klass == Hash
        raise Invalid if value.size > 64
        value.to_h do |k,v|
          raise Invalid unless k.instance_of?(Symbol) || k.instance_of?(String)
          [k.instance_of?(String) ? InputValidator.snapshot!(k, max_bytes: 256) : k, copy!(v, depth + 1, budget)]
        end.freeze
      elsif klass == Array
        raise Invalid if value.size > 256
        value.map { |v| copy!(v, depth + 1, budget) }.freeze
      elsif [Integer, Symbol, NilClass, TrueClass, FalseClass].include?(klass)
        value
      else
        raise Invalid
      end
    end
  end
end
