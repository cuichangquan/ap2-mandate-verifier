# frozen_string_literal: true

module AP2MandateVerifier
  # Complete content disclosure profile, one payment and at most one Agent hop.
  # No network, consent authentication, replay ledger or execution permission.
  module Payment
    PROFILE_REF = "ap2.payment.single.complete.1".freeze
    FIELDS = %w[transaction_id payee payment_amount payment_instrument].freeze
    MAX_LIFETIME = 600
    class Invalid < ArgumentError
      def initialize = super("invalid payment information")
    end
    class Presentation
      attr_reader :open_sd_jwt, :closed_sd_jwt
      def initialize(opening, closed)
        @open_sd_jwt, @closed_sd_jwt = opening&.freeze, closed.freeze
        freeze
      end
      def chain = open_sd_jwt ? open_sd_jwt.chomp("~") + "~~" + closed_sd_jwt : closed_sd_jwt
      private_class_method :new
    end
    class Verification
      attr_reader :code, :payment, :reference, :expires_at
      def initialize(payment = nil, wire = nil)
        @code = payment ? :payment_verified : :payment_verification_failed
        if payment
          @payment = ResearchEvidence.send(:copy_frozen, payment)
          @reference = Payment.send(:digest, wire).freeze
          @expires_at = payment.fetch("exp")
        end
        freeze
      end
      def verified? = code == :payment_verified
      private_class_method :new
    end

    # Checkout JWT and key must be from independently trusted application state.
    # This prepares data, not consent or a verified Checkout Mandate.
    def self.details(checkout_jwt:, trusted_merchant_public_key_pem:, expected_merchant_id:, payment_instrument:,
                     profile_ref: PROFILE_REF, pisp: nil, execution_date: nil)
      profile = PaymentPolicy.profile!(profile_ref)
      if PaymentPolicy.enabled?(profile)
        planned = InputBuilder.send(:copy!, {"pisp" => pisp, "execution_date" => execution_date})
        PaymentPolicy.details!(planned)
      else
        raise Invalid unless pisp.nil? && execution_date.nil?
      end
      checked = CheckoutJWT.verify(jwt: checkout_jwt, trusted_public_key_pem: trusted_merchant_public_key_pem,
        expected_merchant_id: expected_merchant_id, profile_ref: ScopedConstraints::MULTI_PROFILE_REF)
      instrument = InputBuilder.send(:copy!, payment_instrument)
      instrument!(instrument)
      value = {"transaction_id" => checked.checkout_hash,
        "payee" => checked.checkout.fetch("merchant"), "payment_instrument" => instrument,
        "payment_amount" => {"currency" => checked.checkout.fetch("currency"),
          "amount" => ScopedConstraints.multi_checkout!(checked.checkout)}}
      if PaymentPolicy.enabled?(profile)
        value.merge!(planned)
      end
      ResearchEvidence.send(:copy_frozen, copy_details!(value, profile_ref: profile))
    end

    # Protected approval record must cover every payment detail, not just amount.
    def self.issue_direct(payment:, approved_payment:, issued_at:, expires_at:, signer:, public_key_pem:, profile_ref: PROFILE_REF)
      profile_ref = PaymentPolicy.profile!(profile_ref)
      raise Invalid if PaymentPolicy.recurring?(profile_ref) || PaymentPolicy.long?(profile_ref)
      value = copy_details!(payment, profile_ref: profile_ref)
      raise Invalid unless value == copy_details!(approved_payment, profile_ref: profile_ref)
      closed = value.merge("vct" => "mandate.payment.1", "iat" => issued_at, "exp" => expires_at)
      closed!(closed, profile_ref: profile_ref)
      Presentation.send(:new, nil, sign_root!(closed, signer, public_key_pem, profile_ref: profile_ref))
    end

    # Reference is calculated over exact original Open Checkout, never rebuilt JSON.
    # The app authenticates consent to these conditions before invoking this API.
    def self.issue_open(open_checkout_sd_jwt:, constraints:, fixed:, agent_public_key_pem:,
                        issued_at:, expires_at:, signer:, public_key_pem:, checkout_profile_ref: ScopedConstraints::MULTI_PROFILE_REF,
                        profile_ref: PROFILE_REF, candidate_policy: nil)
      profile_ref = PaymentPolicy.profile!(profile_ref)
      PaymentPolicy.candidate_policy!(profile_ref, candidate_policy)
      raise Invalid if PaymentPolicy.long?(profile_ref) && checkout_profile_ref != LongPayment::CHECKOUT_PROFILE_REF
      RootSignature.send(:dependencies!)
      root = checkout_open!(open_checkout_sd_jwt, profile_ref: checkout_profile_ref)
      conditions = InputBuilder.send(:copy!, constraints)
      raise Invalid unless conditions.instance_of?(Array)
      conditions << {"type" => "payment.reference", "conditional_transaction_id" => digest(root)}
      value = InputBuilder.send(:copy!, fixed)
      raise Invalid unless value.instance_of?(Hash) && (value.keys - PaymentPolicy.fields(profile_ref).drop(1)).empty?
      opening = value.merge("vct" => "mandate.payment.open.1", "iat" => issued_at, "exp" => expires_at,
        "cnf" => {"jwk" => RootSignature.public_jwk!(agent_public_key_pem)}, "constraints" => conditions)
      open!(opening, profile_ref: profile_ref)
      sign_root!(opening, signer, public_key_pem, profile_ref: profile_ref).freeze
    end

    # Provider signer is deliberately absent. Existing signed Open grants the hop.
    def self.issue_closed(open_sd_jwt:, payment:, trusted_provider_public_key_pem:, agent_public_key_pem:,
                          audience:, nonce:, verified_at:, signer:, profile_ref: PROFILE_REF)
      profile_ref = PaymentPolicy.profile!(profile_ref)
      agent_public_key_pem = InputValidator.snapshot!(agent_public_key_pem, max_bytes: 1_024)
      opening, root = verified_root!(open_sd_jwt, trusted_provider_public_key_pem, profile_ref: profile_ref)
      open!(opening, profile_ref: profile_ref); valid_now!(opening, verified_at)
      raise Invalid unless opening.fetch("cnf") == {"jwk" => RootSignature.public_jwk!(agent_public_key_pem)}
      value = copy_details!(payment, profile_ref: profile_ref).merge("vct" => "mandate.payment.1",
        "iat" => PaymentPolicy.long?(profile_ref) ? opening.fetch("iat") : verified_at, "exp" => opening.fetch("exp"))
      closed!(value, profile_ref: profile_ref); conditions!(opening, value, profile_ref: profile_ref)
      audience = InputValidator.snapshot!(audience, max_bytes: 512)
      nonce = InputValidator.snapshot!(nonce, max_bytes: 512)
      text!(audience, 512); text!(nonce, 512)
      claims = {"delegate_payload" => [value], "iat" => verified_at,
        "aud" => audience, "nonce" => nonce, "sd_hash" => digest(root)}
      claims["ap2_profile"] = profile_ref if PaymentPolicy.marked?(profile_ref)
      preflight!(claims, "kb+sd-jwt", profile_ref: profile_ref)
      terminal = MerchantSignature.sign!(claims, signer, agent_public_key_pem, typ: "kb+sd-jwt")
      Presentation.send(:new, root, terminal + "~")
    end

    # Original-byte restoration only. All authentication belongs to verify.
    def self.present(closed_sd_jwt:, open_sd_jwt: nil, profile_ref: PROFILE_REF)
      profile_ref = PaymentPolicy.profile!(profile_ref)
      closed, wire = final!(closed_sd_jwt, conditional: !open_sd_jwt.nil?, profile_ref: profile_ref)
      closed!(closed.fetch("delegate_payload").first, profile_ref: profile_ref)
      if open_sd_jwt
        opening, root = root!(open_sd_jwt, profile_ref: profile_ref)
        open!(opening, profile_ref: profile_ref)
        raise Invalid unless closed.fetch("sd_hash") == digest(root)
        if PaymentPolicy.long?(profile_ref)
          raise Invalid unless %w[iat exp].all? { |f| closed.fetch("delegate_payload").first.fetch(f) == opening.fetch(f) }
        end
        conditions!(opening, closed.fetch("delegate_payload").first, profile_ref: profile_ref)
      end
      Presentation.send(:new, open_sd_jwt && root, wire)
    end

    # checkout_inputs are the complete EXISTING public verifier kwargs, supplied
    # by the application, never taken from received Payment claims.
    # Direct uses Buyer.verify; conditional uses verify_checkout's seven inputs.
    def self.verify(closed_sd_jwt:, checkout_mode:, checkout_inputs:, expected_payment:,
                    trusted_provider_public_key_pem:, verified_at:, open_sd_jwt: nil,
                    expected_agent_public_key_pem: nil, expected_audience: nil, expected_nonce: nil,
                    profile_ref: PROFILE_REF, trusted_pisp: nil, execution_at: nil)
      profile_ref = PaymentPolicy.profile!(profile_ref)
      context = PaymentPolicy.context!(profile_ref, trusted_pisp, execution_at)
      raise Invalid if checkout_mode == :direct && (PaymentPolicy.recurring?(profile_ref) || PaymentPolicy.long?(profile_ref))
      trusted_provider_public_key_pem = InputValidator.snapshot!(trusted_provider_public_key_pem, max_bytes: 1_024)
      if checkout_mode == :conditional
        expected_agent_public_key_pem = InputValidator.snapshot!(expected_agent_public_key_pem, max_bytes: 1_024)
        expected_audience = InputValidator.snapshot!(expected_audience, max_bytes: 512)
        expected_nonce = InputValidator.snapshot!(expected_nonce, max_bytes: 512)
      end
      CheckoutReceipt.send(:epoch!, verified_at)
      raise Invalid unless checkout_inputs.instance_of?(Hash) && checkout_inputs[:verified_at] == verified_at
      fields = case checkout_mode
      when :direct then %i[closed_sd_jwt trusted_provider_public_key_pem trusted_merchant_public_key_pem expected_checkout_jwt expected_merchant_id verified_at]
      when :conditional then %i[trust_json selection_json host_json root_presentation terminal_jws host_checkout_jws verified_at]
      else raise Invalid
      end
      raise Invalid unless checkout_inputs.size == fields.size && fields.all? { |f| checkout_inputs.key?(f) }
      limits = {closed_sd_jwt: 32_768, trusted_provider_public_key_pem: 1_024,
        trusted_merchant_public_key_pem: 1_024, expected_checkout_jwt: 16_384, expected_merchant_id: 512,
        host_json: 32_768, terminal_jws: 32_768, host_checkout_jws: 16_384}
      checkout_inputs = checkout_inputs.to_h do |key, value|
        [key, key == :verified_at ? value : InputValidator.snapshot!(value, max_bytes: limits.fetch(key, 131_072))]
      end.freeze
      raise Invalid unless checkout_inputs[:verified_at] == verified_at
      if PaymentPolicy.long?(profile_ref)
        host = InputValidator.parse!(checkout_inputs.fetch(:host_json))
        LongPayment.authority!(checkout_inputs: checkout_inputs, provider_key: trusted_provider_public_key_pem,
          agent_key: expected_agent_public_key_pem, merchant_id: host.fetch("binding").fetch("merchant_id"), verified_at: verified_at)
      end
      if checkout_mode == :conditional
        expected_agent_public_key_pem = InputValidator.snapshot!(expected_agent_public_key_pem, max_bytes: 1_024)
      end
      expected = copy_details!(expected_payment, profile_ref: profile_ref)
      case checkout_mode
      when :direct
        raise Invalid if open_sd_jwt || expected_agent_public_key_pem || expected_audience || expected_nonce
        checked = Buyer.verify(**checkout_inputs)
        raise Invalid unless checked.verified? && expected.fetch("transaction_id") == checked.checkout_hash
        bind_checkout!(expected, checked.checkout)
        claims, wire = verified_root!(closed_sd_jwt, trusted_provider_public_key_pem, profile_ref: profile_ref)
      when :conditional
        checked = AP2MandateVerifier.verify_checkout(**checkout_inputs)
        raise Invalid unless checked.success?
        checkout = checkout_inputs.fetch(:host_checkout_jws)
        raise Invalid unless expected.fetch("transaction_id") == digest(checkout)
        # Fully verified Host evidence binds independent Merchant order state.
        binding = checked.evidence["checkout_binding"]
        amount = expected.fetch("payment_amount")
        raise Invalid unless expected.fetch("payee").fetch("id") == binding.fetch("merchant_id") &&
          amount.fetch("currency") == binding.fetch("currency") && amount.fetch("amount") == binding.fetch("expected_total")
        # Full Checkout verifier already authenticated these exact JWT bytes.
        payload = jwt_payload!(checkout, "JWT")
        bind_checkout!(expected, payload)
        opening, root = verified_root!(open_sd_jwt, trusted_provider_public_key_pem, profile_ref: profile_ref)
        open!(opening, profile_ref: profile_ref); valid_now!(opening, verified_at)
        raise Invalid unless opening.fetch("cnf") == {"jwk" => RootSignature.public_jwk!(expected_agent_public_key_pem)}
        terminal, wire = final!(closed_sd_jwt, conditional: true, profile_ref: profile_ref)
        RootSignature.verified_payload!(wire.split("~", -1).first, expected_agent_public_key_pem,
          expected_typ: "kb+sd-jwt", max_bytes: 32_768)
        expected_audience = InputValidator.snapshot!(expected_audience, max_bytes: 512)
        expected_nonce = InputValidator.snapshot!(expected_nonce, max_bytes: 512)
        text!(expected_audience, 512); text!(expected_nonce, 512)
        raise Invalid unless terminal.fetch("aud") == expected_audience && terminal.fetch("nonce") == expected_nonce &&
          terminal.fetch("sd_hash") == digest(root) && terminal.fetch("iat") <= verified_at &&
          verified_at - terminal.fetch("iat") <= 300
        claims = terminal.fetch("delegate_payload").first
        closed!(claims, profile_ref: profile_ref); valid_now!(claims, verified_at)
        if PaymentPolicy.long?(profile_ref)
          raise Invalid unless %w[iat exp].all? { |f| claims.fetch(f) == opening.fetch(f) }
        else
          raise Invalid unless terminal.fetch("iat") == claims.fetch("iat") && claims.fetch("iat") >= opening.fetch("iat") &&
            claims.fetch("exp") <= opening.fetch("exp")
        end
        conditions!(opening, claims, profile_ref: profile_ref)
        reference = opening.fetch("constraints").find { |c| c["type"] == "payment.reference" }
        raise Invalid unless reference.fetch("conditional_transaction_id") == digest(checkout_inputs.fetch(:root_presentation))
      else raise Invalid
      end
      closed!(claims, profile_ref: profile_ref); valid_now!(claims, verified_at)
      PaymentPolicy.bind_context!(claims, context) if context
      raise Invalid unless claims.slice(*PaymentPolicy.fields(profile_ref)) == expected
      Verification.send(:new, claims, wire)
    rescue StandardError, LoadError
      Verification.send(:new)
    end

    def self.reference(closed_sd_jwt:, profile_ref: PROFILE_REF)
      profile_ref = InputValidator.snapshot!(profile_ref, max_bytes: 256)
      raise Invalid unless profile_ref == PROFILE_REF || PaymentPolicy.marked?(profile_ref)
      # No trust or authorization claim: parse either supported final grammar.
      wire = InputValidator.snapshot!(closed_sd_jwt, max_bytes: 32_769)
      payload = jwt_payload!(wire.split("~", -1).first, nil)
      conditional = payload.key?("sd_hash")
      final, original = final!(wire, conditional: conditional, profile_ref: profile_ref)
      closed!(final.fetch("delegate_payload").first, profile_ref: profile_ref)
      digest(original).freeze
    end

    def self.bind_checkout!(value, checkout)
      raise Invalid unless value.fetch("payee") == checkout.fetch("merchant") &&
        value.fetch("payment_amount") == {"currency" => checkout.fetch("currency"),
          "amount" => ScopedConstraints.multi_checkout!(checkout)}
    end
    def self.copy_details!(value, profile_ref: PROFILE_REF)
      value = InputBuilder.send(:copy!, value)
      exact!(value, PaymentPolicy.fields(profile_ref))
      raise Invalid unless value["transaction_id"].instance_of?(String) && value["transaction_id"].match?(/\A[A-Za-z0-9_-]{43}\z/)
      payee!(value["payee"]); amount!(value["payment_amount"]); instrument!(value["payment_instrument"])
      raise Invalid if (PaymentPolicy.recurring?(profile_ref) || PaymentPolicy.long?(profile_ref)) && value["payment_amount"]["currency"] != "JPY"
      PaymentPolicy.details!(value) if PaymentPolicy.enabled?(profile_ref)
      value
    end
    def self.closed!(value, profile_ref: PROFILE_REF)
      exact!(value, PaymentPolicy.fields(profile_ref) + %w[vct iat exp])
      raise Invalid unless value["vct"] == "mandate.payment.1"
      copy_details!(value.slice(*PaymentPolicy.fields(profile_ref)), profile_ref: profile_ref); times!(value, profile_ref: profile_ref)
    end
    def self.open!(value, profile_ref: PROFILE_REF, base_constraints: false)
      if PaymentPolicy.long?(profile_ref) && !base_constraints
        open!(LongPayment.send(:constraints!, value), profile_ref: profile_ref, base_constraints: true)
        return nil
      end
      if PaymentPolicy.recurring?(profile_ref)
        open!(RecurringPayment.send(:constraints!, value))
        return nil
      end
      if PaymentPolicy.enabled?(profile_ref)
        base = PaymentPolicy.constraints!(value)
        open!(base)
        return nil
      end
      raise Invalid unless value.instance_of?(Hash) && (value.keys - FIELDS.drop(1) - %w[vct iat exp cnf constraints]).empty?
      raise Invalid unless value["vct"] == "mandate.payment.open.1"
      times!(value, profile_ref: profile_ref); exact!(value["cnf"], ["jwk"])
      jwk = value["cnf"]["jwk"]
      exact!(jwk, %w[kty crv x y])
      raise Invalid unless jwk["kty"] == "EC" && jwk["crv"] == "P-256" &&
        %w[x y].all? { |f| RootSignature.send(:decode!, jwk[f], 32).bytesize == 32 }
      payee!(value["payee"]) if value.key?("payee")
      amount!(value["payment_amount"]) if value.key?("payment_amount")
      instrument!(value["payment_instrument"]) if value.key?("payment_instrument")
      cs = value["constraints"]
      raise Invalid unless cs.instance_of?(Array) && cs.size == 4 && cs.all? { |c| c.instance_of?(Hash) }
      raise Invalid unless cs.map { |c| c["type"] }.sort == %w[payment.allowed_payees payment.allowed_payment_instruments payment.amount_range payment.reference].sort
      cs.each do |c|
        case c["type"]
        when "payment.reference"
          exact!(c, %w[type conditional_transaction_id])
          raise Invalid unless c["conditional_transaction_id"].instance_of?(String) && c["conditional_transaction_id"].match?(/\A[A-Za-z0-9_-]{43}\z/)
        when "payment.amount_range"
          raise Invalid unless c.keys.sort == %w[currency max min type].sort || c.keys.sort == %w[currency max type].sort
          amount!({"amount" => c["max"], "currency" => c["currency"]})
          amount!({"amount" => c.fetch("min", 0), "currency" => c["currency"]})
          raise Invalid unless c.fetch("min", 0) <= c["max"]
        else
          exact!(c, %w[type allowed])
          raise Invalid unless c["allowed"].instance_of?(Array) && c["allowed"].size.between?(1, 8) && c["allowed"].uniq.size == c["allowed"].size
          c["allowed"].each { |item| c["type"] == "payment.allowed_payees" ? payee!(item) : instrument!(item) }
        end
      end
    end
    def self.conditions!(opening, closed, profile_ref: PROFILE_REF)
      if PaymentPolicy.long?(profile_ref)
        LongPayment.send(:conditions!, opening, closed)
        return nil
      end
      if PaymentPolicy.recurring?(profile_ref)
        RecurringPayment.send(:conditions!, opening, closed)
        return nil
      end
      if PaymentPolicy.enabled?(profile_ref)
        PaymentPolicy.conditions!(opening, closed)
        base = PaymentPolicy.constraints!(opening)
        conditions!(base, closed)
        return nil
      end
      FIELDS.drop(1).each { |f| raise Invalid if opening.key?(f) && opening[f] != closed[f] }
      opening.fetch("constraints").each do |c|
        case c["type"]
        when "payment.allowed_payees" then raise Invalid unless c["allowed"].include?(closed["payee"])
        when "payment.allowed_payment_instruments" then raise Invalid unless c["allowed"].include?(closed["payment_instrument"])
        when "payment.amount_range"
          a = closed.fetch("payment_amount")
          raise Invalid unless a["currency"] == c["currency"] && a["amount"].between?(c.fetch("min", 0), c["max"])
        when "payment.reference" # Checked against the verified Checkout chain in verify.
        else raise Invalid
        end
      end
    end
    def self.payee!(v)
      raise Invalid unless v.instance_of?(Hash) && [%w[id name], %w[id name website]].include?(v.keys.sort)
      v.each_value { |s| text!(s, 512) }
    end
    def self.instrument!(v)
      raise Invalid unless v.instance_of?(Hash) && [%w[id type], %w[description id type]].include?(v.keys.sort)
      v.each_value { |s| text!(s, 512) }
    end
    def self.amount!(v)
      exact!(v, %w[amount currency])
      ScopedConstraints.send(:amount!, v["amount"])
      raise Invalid unless ScopedConstraints::CURRENCIES.include?(v["currency"])
    end
    def self.times!(v, profile_ref: PROFILE_REF)
      %w[iat exp].each { |f| CheckoutReceipt.send(:epoch!, v[f]) }
      limit = PaymentPolicy.long?(profile_ref) ? LongPayment::MAX_CONTENT_LIFETIME : MAX_LIFETIME
      raise Invalid unless v["exp"] > v["iat"] && v["exp"] - v["iat"] <= limit
    end
    def self.valid_now!(v, now)
      CheckoutReceipt.send(:epoch!, now)
      raise Invalid unless v.fetch("iat") <= now && now < v.fetch("exp")
    end
    def self.checkout_open!(wire, profile_ref: ScopedConstraints::MULTI_PROFILE_REF)
      wire = InputValidator.snapshot!(wire)
      profile = InputValidator.snapshot!(profile_ref, max_bytes: 256)
      opening = if profile == TrustContext::SELECTIVE_PROFILE_REF
        SelectiveCheckout.send(:parse!, wire, complete: false).fetch(:opening)
      elsif defined?(LongPayment) && profile == LongPayment::CHECKOUT_PROFILE_REF
        RootDisclosures.send(:structural_root!, wire, profile_ref: profile).fetch("delegate_payload").first
      else
        raise Invalid unless profile == ScopedConstraints::MULTI_PROFILE_REF
        RootDisclosures.send(:structural_root!, wire).fetch("delegate_payload").first
      end
      raise Invalid unless opening.fetch("vct") == "mandate.checkout.open.1"
      wire
    end
    def self.jwt_payload!(jwt, typ)
      RootSignature.send(:dependencies!)
      parts = jwt.split(".", -1)
      raise Invalid unless parts.size == 3
      h = InputValidator.parse!(RootSignature.send(:decode!, parts[0], 2_048))
      CheckoutReceipt.send(:header!, h, typ || h["typ"])
      raise Invalid unless RootSignature.send(:decode!, parts[2], 64).bytesize == 64
      InputValidator.parse!(RootSignature.send(:decode!, parts[1], 24_576))
    end
    def self.final!(source, conditional:, profile_ref: PROFILE_REF)
      wire = InputValidator.snapshot!(source, max_bytes: 32_769)
      raise Invalid unless wire.ascii_only? && wire.end_with?("~") && [1, 2].include?(wire.count("~"))
      compact, *parts = wire.split("~", -1)
      parts.pop
      claims = jwt_payload!(compact, conditional ? "kb+sd-jwt" : "example+sd-jwt")
      fields = conditional ? %w[delegate_payload iat aud nonce sd_hash] : %w[delegate_payload _sd_alg]
      fields += ["_sd_alg"] if conditional && claims.key?("_sd_alg")
      if PaymentPolicy.marked?(profile_ref)
        fields += ["ap2_profile"]
        raise Invalid unless claims["ap2_profile"] == profile_ref
      end
      exact!(claims, fields)
      raise Invalid if claims.key?("_sd_alg") && claims["_sd_alg"] != "sha-256"
      if conditional
        text!(claims["aud"], 512); text!(claims["nonce"], 512)
        CheckoutReceipt.send(:epoch!, claims["iat"])
        raise Invalid unless claims["sd_hash"].instance_of?(String) && claims["sd_hash"].match?(/\A[A-Za-z0-9_-]{43}\z/)
      else
        raise Invalid unless claims["_sd_alg"] == "sha-256"
      end
      raise Invalid unless claims["delegate_payload"].instance_of?(Array) && claims["delegate_payload"].size == 1
      unless parts.empty?
        disclosure = parts.fetch(0)
        pointer = claims["delegate_payload"].first
        exact!(pointer, ["..."])
        raise Invalid unless pointer["..."] == digest(disclosure)
        value = Buyer.send(:decode_disclosure!, disclosure, 2)
        claims = claims.merge("delegate_payload" => [value[1]])
      end
      if (PaymentPolicy.recurring?(profile_ref) || PaymentPolicy.long?(profile_ref)) && !conditional
        raise Invalid unless claims.fetch("delegate_payload").first.instance_of?(Hash) &&
          claims.fetch("delegate_payload").first["vct"] == "mandate.payment.open.1"
      end
      [claims, wire]
    end
    def self.root!(source, profile_ref: PROFILE_REF)
      claims, wire = final!(source, conditional: false, profile_ref: profile_ref)
      [claims.fetch("delegate_payload").first, wire]
    end
    def self.verified_root!(source, key, profile_ref: PROFILE_REF)
      value, wire = root!(source, profile_ref: profile_ref)
      RootSignature.verified_payload!(wire.split("~", -1).first, key, max_bytes: 32_768)
      [value, wire]
    end
    def self.sign_root!(value, signer, key, profile_ref: PROFILE_REF)
      RootSignature.send(:dependencies!)
      require "securerandom"
      disclosure = Buyer.send(:encode, [Buyer.send(:encode, SecureRandom.random_bytes(16)), value])
      claims = {"delegate_payload" => [{"..." => digest(disclosure)}], "_sd_alg" => "sha-256"}
      claims["ap2_profile"] = profile_ref if PaymentPolicy.marked?(profile_ref)
      preflight!(claims, "example+sd-jwt", disclosure, profile_ref: profile_ref)
      wire = MerchantSignature.sign!(claims, signer, key,
        typ: "example+sd-jwt") + "~" + disclosure + "~"
      final!(wire, conditional: false, profile_ref: profile_ref)
      wire
    end
    def self.preflight!(claims, typ, disclosure = nil, profile_ref: PROFILE_REF)
      # Bound every new Mandate signature before remote signer effects. ES256
      # signatures have a fixed 64-byte width; this performs no cryptography.
      compact = [Buyer.send(:encode, {"alg" => "ES256", "typ" => typ}),
        Buyer.send(:encode, claims), Buyer.send(:encode, "\0" * 64)].join(".")
      wire = compact + "~" + (disclosure ? disclosure + "~" : "")
      final!(wire, conditional: typ == "kb+sd-jwt", profile_ref: profile_ref)
    end
    def self.digest(wire) = Base64.urlsafe_encode64(Digest::SHA256.digest(wire), padding: false)
    def self.exact!(v, fields) = PurchaseBinding.send(:exact!, v, fields)
    def self.text!(v, max) = CheckoutReceipt.send(:text!, v, max)

    # Fixed redacted exceptions and keyword rejection on every new entry.
    %i[details issue_direct issue_open issue_closed present reference verify].each do |name|
      implementation = method(name)
      required = implementation.parameters.filter_map { |kind, field| field if kind == :keyreq }.freeze
      fields = implementation.parameters.map(&:last).freeze
      define_singleton_method(name) do |**args|
        unless (required - args.keys).empty? && (args.keys - fields).empty?
          next Verification.send(:new) if name == :verify
          raise Invalid
        end
        implementation.call(**args)
      rescue StandardError, LoadError
        raise Invalid.new, cause: nil
      end
    end
    singleton_methods(false).reject { |n| %i[details issue_direct issue_open issue_closed present verify reference].include?(n) }.each { |n| private_class_method n }
  end
end
