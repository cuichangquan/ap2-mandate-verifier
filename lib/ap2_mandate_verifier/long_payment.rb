# frozen_string_literal: true

module AP2MandateVerifier
  # Explicit long-content, fresh-proof profile. MONTHLY is enforced by a
  # protected Host period policy at acceptance, never by this wire verifier.
  module LongPayment
    CHECKOUT_PROFILE_REF = "ap2.checkout.long_open.multi_item.1".freeze
    PROFILE_REF = "ap2.payment.long_open.jpy_monthly.complete.1".freeze
    MAX_CONTENT_LIFETIME = 400 * 86_400
    MAX_OCCURRENCES = 1_000_000
    TYPES = %w[payment.agent_recurrence payment.budget].freeze
    class Invalid < ArgumentError
      def initialize = super("invalid long payment information")
    end
    def self.profile?(value) = value == PROFILE_REF
    def self.checkout_profile?(value) = value == CHECKOUT_PROFILE_REF

    def self.constraints!(opening)
      raise Invalid unless opening.instance_of?(Hash)
      cs = opening.fetch("constraints")
      raise Invalid unless cs.instance_of?(Array) && cs.size == 6 && cs.all? { |c| c.instance_of?(Hash) }
      recurrence = cs.select { |c| c["type"] == TYPES[0] }
      budget = cs.select { |c| c["type"] == TYPES[1] }
      raise Invalid unless recurrence.size == 1 && budget.size == 1
      recurrence, budget = recurrence.first, budget.first
      Payment.send(:exact!, recurrence, %w[type frequency max_occurrences])
      Payment.send(:exact!, budget, %w[type max currency])
      raise Invalid unless recurrence["frequency"] == "MONTHLY" && recurrence["max_occurrences"].instance_of?(Integer) &&
        recurrence["max_occurrences"].between?(1, MAX_OCCURRENCES) && budget["currency"] == "JPY" &&
        budget["max"].instance_of?(Integer) && budget["max"].between?(1, ScopedConstraints::MAX_AMOUNT)
      amount = cs.select { |c| c["type"] == "payment.amount_range" }
      raise Invalid unless amount.size == 1 && amount.first["currency"] == "JPY"
      raise Invalid if amount.first.fetch("min", 0).instance_of?(Integer) && amount.first.fetch("min", 0) > budget["max"]
      if opening.key?("payment_amount")
        Payment.send(:amount!, opening["payment_amount"])
        raise Invalid unless opening["payment_amount"]["currency"] == "JPY" && opening["payment_amount"]["amount"] <= budget["max"]
      end
      opening.merge("constraints" => cs.reject { |c| TYPES.include?(c["type"]) })
    end
    def self.conditions!(opening, closed)
      base = constraints!(opening)
      budget = opening.fetch("constraints").find { |c| c["type"] == TYPES[1] }
      raise Invalid unless closed.fetch("payment_amount").fetch("currency") == "JPY" && closed["payment_amount"]["amount"] <= budget.fetch("max")
      Payment.send(:conditions!, base, closed)
    end

    def self.snapshot_checkout!(source, verified_at)
      CheckoutReceipt.send(:epoch!, verified_at)
      fields = %i[trust_json selection_json host_json root_presentation terminal_jws host_checkout_jws verified_at]
      raise Invalid unless Object.instance_method(:instance_of?).bind_call(source, Hash) &&
        Object.instance_method(:singleton_methods).bind_call(source, true).empty? && source.size == fields.size && fields.all? { |f| source.key?(f) }
      limits = {selection_json: 16_384, host_json: 32_768, terminal_jws: 32_768, host_checkout_jws: 16_384}
      value = fields.to_h { |f| [f, f == :verified_at ? source[f] : InputValidator.snapshot!(source[f], max_bytes: limits.fetch(f, 131_072))] }.freeze
      CheckoutReceipt.send(:epoch!, value[:verified_at])
      raise Invalid unless value[:verified_at] == verified_at
      value
    end
    def self.current_context!(trust_json, selection_json, merchant_id, verified_at)
      CheckoutReceipt.send(:epoch!, verified_at)
      trust = InputValidator.snapshot!(trust_json)
      selection = InputValidator.snapshot!(selection_json, max_bytes: 16_384)
      identity = InputValidator.snapshot!(merchant_id, max_bytes: 256)
      context = TrustContext.verified_context!(trust_json: trust, selection_json: selection,
        expected_merchant_id: identity, verified_at: verified_at)
      raise Invalid unless context.fetch(:references).fetch("profile_ref") == CHECKOUT_PROFILE_REF
      context
    end
    def self.authority_projection(context)
      binding = context.fetch(:references).merge("selected_keys" => context.fetch(:selected_keys))
      keys = context.fetch(:keys)
      principals = context.fetch(:selected_keys).to_h { |record| [record.fetch("role"), record.slice("identity", "purpose", "tenant_id")] }
      fingerprints = {"issuer" => Digest::SHA256.hexdigest(keys.fetch(:trusted_issuer_public_key_pem)),
        "agent" => Digest::SHA256.hexdigest(keys.fetch(:expected_agent_public_key_pem))}
      {authority_binding: ResearchEvidence.send(:copy_frozen, binding), root_key_fingerprints: ResearchEvidence.send(:copy_frozen, fingerprints),
        authority_principals: ResearchEvidence.send(:copy_frozen, principals),
        tenant_id: context.fetch(:references).fetch("tenant_id"), valid_until: context.fetch(:valid_until)}.freeze
    end
    def self.current_authority!(trust_json:, selection_json:, merchant_id:, verified_at:)
      authority_projection(current_context!(trust_json, selection_json, merchant_id, verified_at))
    rescue StandardError, LoadError
      raise Invalid.new, cause: nil
    end
    def self.authority!(checkout_inputs:, provider_key:, agent_key:, merchant_id:, verified_at:)
      provider = InputValidator.snapshot!(provider_key, max_bytes: 1024)
      agent = InputValidator.snapshot!(agent_key, max_bytes: 1024)
      identity = InputValidator.snapshot!(merchant_id, max_bytes: 256)
      inputs = snapshot_checkout!(checkout_inputs, verified_at)
      host = InputValidator.parse!(inputs.fetch(:host_json))
      raise Invalid unless host.fetch("binding").fetch("merchant_id") == identity
      context = current_context!(inputs.fetch(:trust_json), inputs.fetch(:selection_json), identity, verified_at)
      keys = context.fetch(:keys)
      raise Invalid unless RootSignature.public_jwk!(provider) == RootSignature.public_jwk!(keys.fetch(:trusted_issuer_public_key_pem)) &&
        RootSignature.public_jwk!(agent) == RootSignature.public_jwk!(keys.fetch(:expected_agent_public_key_pem))
      authority_projection(context)
    rescue StandardError, LoadError
      raise Invalid.new, cause: nil
    end

    def self.validated_open!(source)
      opening, wire = Payment.send(:root!, source, profile_ref: PROFILE_REF)
      Payment.send(:open!, opening, profile_ref: PROFILE_REF)
      recurrence = opening.fetch("constraints").find { |c| c["type"] == TYPES[0] }
      budget = opening.fetch("constraints").find { |c| c["type"] == TYPES[1] }
      root = wire.split("~", 2).first.freeze
      {opening: ResearchEvidence.send(:copy_frozen, opening), root_wire: root, presentation_wire: wire,
        reference: Payment.send(:digest, root).freeze, currency: "JPY".freeze, frequency: "MONTHLY".freeze,
        max_occurrences: recurrence.fetch("max_occurrences"), budget_max: budget.fetch("max"), profile_ref: PROFILE_REF}.freeze
    end
    def self.approved_open!(open_sd_jwt:, trusted_provider_public_key_pem:, expected_agent_public_key_pem:, verified_at:, profile_ref: PROFILE_REF)
      raise Invalid unless InputValidator.snapshot!(profile_ref, max_bytes: 256) == PROFILE_REF
      wire = InputValidator.snapshot!(open_sd_jwt, max_bytes: 32_769)
      provider = InputValidator.snapshot!(trusted_provider_public_key_pem, max_bytes: 1024)
      agent = InputValidator.snapshot!(expected_agent_public_key_pem, max_bytes: 1024)
      CheckoutReceipt.send(:epoch!, verified_at)
      RootSignature.verified_payload!(wire.split("~", 2).first, provider)
      checked = validated_open!(wire)
      Payment.send(:valid_now!, checked.fetch(:opening), verified_at)
      raise Invalid unless checked.fetch(:opening).fetch("cnf") == {"jwk" => RootSignature.public_jwk!(agent)}
      checked
    rescue StandardError, LoadError
      raise Invalid.new, cause: nil
    end
    def self.approved_pair!(payment_open:, checkout_open:, trust_json:, selection_json:, merchant_id:, verified_at:)
      payment_wire = InputValidator.snapshot!(payment_open, max_bytes: 32_769)
      checkout_wire = InputValidator.snapshot!(checkout_open)
      identity = InputValidator.snapshot!(merchant_id, max_bytes: 256)
      context = current_context!(trust_json, selection_json, identity, verified_at)
      keys = context.fetch(:keys)
      checkout = ConditionalCheckout.send(:open!, checkout_wire, keys.fetch(:trusted_issuer_public_key_pem),
        keys.fetch(:expected_agent_public_key_pem), verified_at, profile_ref: CHECKOUT_PROFILE_REF)
      merchant, = ScopedConstraints.send(:multi_open!, checkout.fetch("constraints"))
      raise Invalid unless merchant.fetch("id") == identity
      checked = approved_open!(open_sd_jwt: payment_wire, trusted_provider_public_key_pem: keys.fetch(:trusted_issuer_public_key_pem),
        expected_agent_public_key_pem: keys.fetch(:expected_agent_public_key_pem), verified_at: verified_at)
      opening = checked.fetch(:opening)
      reference = opening.fetch("constraints").find { |c| c["type"] == "payment.reference" }
      raise Invalid unless reference.fetch("conditional_transaction_id") == Payment.send(:digest, checkout_wire)
      economic_payment = opening.reject { |k,_| %w[iat exp cnf].include?(k) }.merge(
        "constraints" => opening.fetch("constraints").reject { |c| c["type"] == "payment.reference" })
      economic_checkout = checkout.reject { |k,_| %w[iat exp cnf].include?(k) }
      economics = canonical({"payment_profile" => PROFILE_REF, "checkout_profile" => CHECKOUT_PROFILE_REF,
        "checkout" => economic_checkout, "payment" => economic_payment})
      projected = authority_projection(context)
      checked.merge(checkout_opening: ResearchEvidence.send(:copy_frozen, checkout), checkout_reference: Payment.send(:digest, checkout_wire).freeze,
        economic_contract: economics.freeze, not_before: [opening.fetch("iat"),checkout.fetch("iat")].max,
        not_after: [opening.fetch("exp"),checkout.fetch("exp")].min, authority_binding: projected.fetch(:authority_binding),
        root_key_fingerprints: projected.fetch(:root_key_fingerprints), tenant_id: projected.fetch(:tenant_id),
        authority_principals: projected.fetch(:authority_principals),
        authority_valid_until: projected.fetch(:valid_until)).freeze
    rescue StandardError, LoadError
      raise Invalid.new, cause: nil
    end
    def self.canonical(value)
      normalized = case value
      when Hash then value.keys.sort.to_h { |k| [k, JSON.parse(canonical(value[k]))] }
      when Array then value.map { |v| JSON.parse(canonical(v)) }
      else value
      end
      JSON.generate(normalized)
    end

    %i[issue_open issue_closed present verify details].each do |name|
      define_singleton_method(name) do |**arguments|
        if arguments.key?(:profile_ref)
          raise Invalid unless InputValidator.snapshot!(arguments.delete(:profile_ref), max_bytes: 256) == PROFILE_REF
        end
        if arguments.key?(:checkout_profile_ref)
          raise Invalid unless name == :issue_open && InputValidator.snapshot!(arguments.delete(:checkout_profile_ref), max_bytes: 256) == CHECKOUT_PROFILE_REF
        end
        arguments[:checkout_profile_ref] = CHECKOUT_PROFILE_REF if name == :issue_open
        arguments[:checkout_mode] = :conditional if name == :verify && !arguments.key?(:checkout_mode)
        Payment.public_send(name, **arguments, profile_ref: PROFILE_REF)
      rescue StandardError, LoadError
        next Payment::Verification.send(:new) if name == :verify
        raise Invalid.new, cause: nil
      end
    end
    {issue_checkout_open: :issue_open, issue_checkout_closed: :issue_closed, present_checkout: :present}.each do |name,target|
      define_singleton_method(name) do |**arguments|
        if arguments.key?(:profile_ref)
          raise Invalid unless InputValidator.snapshot!(arguments.delete(:profile_ref), max_bytes: 256) == CHECKOUT_PROFILE_REF
        end
        ConditionalCheckout.public_send(target, **arguments, profile_ref: CHECKOUT_PROFILE_REF)
      rescue StandardError, LoadError
        raise Invalid.new, cause: nil
      end
    end
    %i[current_authority! authority! approved_open! approved_pair!].each do |name|
      implementation = method(name)
      required = implementation.parameters.filter_map { |kind,key| key if kind == :keyreq }.freeze
      fields = implementation.parameters.map(&:last).freeze
      define_singleton_method(name) do |**arguments|
        raise Invalid unless (required - arguments.keys).empty? && (arguments.keys - fields).empty?
        implementation.call(**arguments)
      rescue StandardError, LoadError
        raise Invalid.new, cause: nil
      end
    end
    private_class_method :constraints!, :conditions!, :snapshot_checkout!, :current_context!, :authority_projection, :validated_open!, :canonical
  end
end
