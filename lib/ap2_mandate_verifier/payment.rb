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
    def self.details(checkout_jwt:, trusted_merchant_public_key_pem:, expected_merchant_id:, payment_instrument:)
      checked = CheckoutJWT.verify(jwt: checkout_jwt, trusted_public_key_pem: trusted_merchant_public_key_pem,
        expected_merchant_id: expected_merchant_id, profile_ref: ScopedConstraints::MULTI_PROFILE_REF)
      instrument = InputBuilder.send(:copy!, payment_instrument)
      instrument!(instrument)
      ResearchEvidence.send(:copy_frozen, {"transaction_id" => checked.checkout_hash,
        "payee" => checked.checkout.fetch("merchant"), "payment_instrument" => instrument,
        "payment_amount" => {"currency" => checked.checkout.fetch("currency"),
          "amount" => ScopedConstraints.multi_checkout!(checked.checkout)}})
    end

    # Protected approval record must cover every payment detail, not just amount.
    def self.issue_direct(payment:, approved_payment:, issued_at:, expires_at:, signer:, public_key_pem:)
      value = copy_details!(payment)
      raise Invalid unless value == copy_details!(approved_payment)
      closed = value.merge("vct" => "mandate.payment.1", "iat" => issued_at, "exp" => expires_at)
      closed!(closed)
      Presentation.send(:new, nil, sign_root!(closed, signer, public_key_pem))
    end

    # Reference is calculated over exact original Open Checkout, never rebuilt JSON.
    # The app authenticates consent to these conditions before invoking this API.
    def self.issue_open(open_checkout_sd_jwt:, constraints:, fixed:, agent_public_key_pem:,
                        issued_at:, expires_at:, signer:, public_key_pem:)
      RootSignature.send(:dependencies!)
      root = checkout_open!(open_checkout_sd_jwt)
      conditions = InputBuilder.send(:copy!, constraints)
      raise Invalid unless conditions.instance_of?(Array)
      conditions << {"type" => "payment.reference", "conditional_transaction_id" => digest(root)}
      value = InputBuilder.send(:copy!, fixed)
      raise Invalid unless value.instance_of?(Hash) && (value.keys - FIELDS.drop(1)).empty?
      opening = value.merge("vct" => "mandate.payment.open.1", "iat" => issued_at, "exp" => expires_at,
        "cnf" => {"jwk" => RootSignature.public_jwk!(agent_public_key_pem)}, "constraints" => conditions)
      open!(opening)
      sign_root!(opening, signer, public_key_pem).freeze
    end

    # Provider signer is deliberately absent. Existing signed Open grants the hop.
    def self.issue_closed(open_sd_jwt:, payment:, trusted_provider_public_key_pem:, agent_public_key_pem:,
                          audience:, nonce:, verified_at:, signer:)
      opening, root = verified_root!(open_sd_jwt, trusted_provider_public_key_pem)
      open!(opening); valid_now!(opening, verified_at)
      raise Invalid unless opening.fetch("cnf") == {"jwk" => RootSignature.public_jwk!(agent_public_key_pem)}
      value = copy_details!(payment).merge("vct" => "mandate.payment.1", "iat" => verified_at, "exp" => opening.fetch("exp"))
      closed!(value); conditions!(opening, value)
      audience = InputValidator.snapshot!(audience, max_bytes: 512)
      nonce = InputValidator.snapshot!(nonce, max_bytes: 512)
      text!(audience, 512); text!(nonce, 512)
      terminal = MerchantSignature.sign!({"delegate_payload" => [value], "iat" => verified_at,
        "aud" => audience, "nonce" => nonce, "sd_hash" => digest(root)}, signer, agent_public_key_pem, typ: "kb+sd-jwt")
      Presentation.send(:new, root, terminal + "~")
    end

    # Original-byte restoration only. All authentication belongs to verify.
    def self.present(closed_sd_jwt:, open_sd_jwt: nil)
      closed, wire = final!(closed_sd_jwt, conditional: !open_sd_jwt.nil?)
      closed!(closed.fetch("delegate_payload").first)
      if open_sd_jwt
        opening, root = root!(open_sd_jwt)
        open!(opening)
        raise Invalid unless closed.fetch("sd_hash") == digest(root)
        conditions!(opening, closed.fetch("delegate_payload").first)
      end
      Presentation.send(:new, open_sd_jwt && root, wire)
    end

    # checkout_inputs are the complete EXISTING public verifier kwargs, supplied
    # by the application, never taken from received Payment claims.
    # Direct uses Buyer.verify; conditional uses verify_checkout's seven inputs.
    def self.verify(closed_sd_jwt:, checkout_mode:, checkout_inputs:, expected_payment:,
                    trusted_provider_public_key_pem:, verified_at:, open_sd_jwt: nil,
                    expected_agent_public_key_pem: nil, expected_audience: nil, expected_nonce: nil)
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
      expected = copy_details!(expected_payment)
      case checkout_mode
      when :direct
        raise Invalid if open_sd_jwt || expected_agent_public_key_pem || expected_audience || expected_nonce
        checked = Buyer.verify(**checkout_inputs)
        raise Invalid unless checked.verified? && expected.fetch("transaction_id") == checked.checkout_hash
        bind_checkout!(expected, checked.checkout)
        claims, wire = verified_root!(closed_sd_jwt, trusted_provider_public_key_pem)
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
        opening, root = verified_root!(open_sd_jwt, trusted_provider_public_key_pem)
        open!(opening); valid_now!(opening, verified_at)
        raise Invalid unless opening.fetch("cnf") == {"jwk" => RootSignature.public_jwk!(expected_agent_public_key_pem)}
        terminal, wire = final!(closed_sd_jwt, conditional: true)
        RootSignature.verified_payload!(wire.split("~", -1).first, expected_agent_public_key_pem,
          expected_typ: "kb+sd-jwt", max_bytes: 32_768)
        expected_audience = InputValidator.snapshot!(expected_audience, max_bytes: 512)
        expected_nonce = InputValidator.snapshot!(expected_nonce, max_bytes: 512)
        text!(expected_audience, 512); text!(expected_nonce, 512)
        raise Invalid unless terminal.fetch("aud") == expected_audience && terminal.fetch("nonce") == expected_nonce &&
          terminal.fetch("sd_hash") == digest(root) && terminal.fetch("iat") <= verified_at &&
          verified_at - terminal.fetch("iat") <= 300
        claims = terminal.fetch("delegate_payload").first
        closed!(claims); valid_now!(claims, verified_at)
        raise Invalid unless terminal.fetch("iat") == claims.fetch("iat") && claims.fetch("iat") >= opening.fetch("iat") &&
          claims.fetch("exp") <= opening.fetch("exp")
        conditions!(opening, claims)
        reference = opening.fetch("constraints").find { |c| c["type"] == "payment.reference" }
        raise Invalid unless reference.fetch("conditional_transaction_id") == digest(checkout_inputs.fetch(:root_presentation))
      else raise Invalid
      end
      closed!(claims); valid_now!(claims, verified_at)
      raise Invalid unless claims.slice(*FIELDS) == expected
      Verification.send(:new, claims, wire)
    rescue StandardError, LoadError
      Verification.send(:new)
    end

    def self.reference(closed_sd_jwt:)
      # No trust or authorization claim: parse either supported final grammar.
      wire = InputValidator.snapshot!(closed_sd_jwt, max_bytes: 32_769)
      payload = jwt_payload!(wire.split("~", -1).first, nil)
      conditional = payload.key?("sd_hash")
      final, original = final!(wire, conditional: conditional)
      closed!(final.fetch("delegate_payload").first)
      digest(original).freeze
    end

    def self.bind_checkout!(value, checkout)
      raise Invalid unless value.fetch("payee") == checkout.fetch("merchant") &&
        value.fetch("payment_amount") == {"currency" => checkout.fetch("currency"),
          "amount" => ScopedConstraints.multi_checkout!(checkout)}
    end
    def self.copy_details!(value)
      value = InputBuilder.send(:copy!, value)
      exact!(value, FIELDS)
      raise Invalid unless value["transaction_id"].instance_of?(String) && value["transaction_id"].match?(/\A[A-Za-z0-9_-]{43}\z/)
      payee!(value["payee"]); amount!(value["payment_amount"]); instrument!(value["payment_instrument"])
      value
    end
    def self.closed!(value)
      exact!(value, FIELDS + %w[vct iat exp])
      raise Invalid unless value["vct"] == "mandate.payment.1"
      copy_details!(value.slice(*FIELDS)); times!(value)
    end
    def self.open!(value)
      raise Invalid unless value.instance_of?(Hash) && (value.keys - FIELDS.drop(1) - %w[vct iat exp cnf constraints]).empty?
      raise Invalid unless value["vct"] == "mandate.payment.open.1"
      times!(value); exact!(value["cnf"], ["jwk"])
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
    def self.conditions!(opening, closed)
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
    def self.times!(v)
      %w[iat exp].each { |f| CheckoutReceipt.send(:epoch!, v[f]) }
      raise Invalid unless v["exp"] > v["iat"] && v["exp"] - v["iat"] <= MAX_LIFETIME
    end
    def self.valid_now!(v, now)
      CheckoutReceipt.send(:epoch!, now)
      raise Invalid unless v.fetch("iat") <= now && now < v.fetch("exp")
    end
    def self.checkout_open!(wire)
      wire = InputValidator.snapshot!(wire)
      opening = RootDisclosures.send(:structural_root!, wire).fetch("delegate_payload").first
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
    def self.final!(source, conditional:)
      wire = InputValidator.snapshot!(source, max_bytes: 32_769)
      raise Invalid unless wire.ascii_only? && wire.end_with?("~") && [1, 2].include?(wire.count("~"))
      compact, *parts = wire.split("~", -1)
      parts.pop
      claims = jwt_payload!(compact, conditional ? "kb+sd-jwt" : "example+sd-jwt")
      fields = conditional ? %w[delegate_payload iat aud nonce sd_hash] : %w[delegate_payload _sd_alg]
      fields += ["_sd_alg"] if conditional && claims.key?("_sd_alg")
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
      [claims, wire]
    end
    def self.root!(source)
      claims, wire = final!(source, conditional: false)
      [claims.fetch("delegate_payload").first, wire]
    end
    def self.verified_root!(source, key)
      value, wire = root!(source)
      RootSignature.verified_payload!(wire.split("~", -1).first, key, max_bytes: 32_768)
      [value, wire]
    end
    def self.sign_root!(value, signer, key)
      RootSignature.send(:dependencies!)
      require "securerandom"
      disclosure = Buyer.send(:encode, [Buyer.send(:encode, SecureRandom.random_bytes(16)), value])
      wire = MerchantSignature.sign!({"delegate_payload" => [{"..." => digest(disclosure)}], "_sd_alg" => "sha-256"}, signer, key,
        typ: "example+sd-jwt") + "~" + disclosure + "~"
      final!(wire, conditional: false)
      wire
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
