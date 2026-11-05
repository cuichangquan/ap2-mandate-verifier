# frozen_string_literal: true

module AP2MandateVerifier
  # Additive issuer/Agent APIs for the unchanged complete-disclosure profile.
  module ConditionalCheckout
    PROFILE_REF = ScopedConstraints::MULTI_PROFILE_REF
    class Invalid < ArgumentError
      def initialize = super("invalid conditional checkout information")
    end
    class Open
      attr_reader :root_presentation
      def initialize(wire)
        @root_presentation = wire.freeze
        freeze
      end
      private_class_method :new
    end
    class Closed
      attr_reader :root_presentation, :terminal_jws, :checkout_jwt, :closed_sd_jwt
      def initialize(root, terminal, checkout)
        @root_presentation, @terminal_jws, @checkout_jwt = root.freeze, terminal.freeze, checkout.freeze
        @closed_sd_jwt = (terminal + "~").freeze
        freeze
      end
      private_class_method :new
    end

    def self.issue_open(merchant:, requirements:, agent_public_key_pem:, issued_at:, expires_at:, signer:, public_key_pem:, profile_ref: PROFILE_REF)
      profile_ref = profile!(profile_ref)
      RootSignature.send(:dependencies!)
      merchant = InputBuilder.send(:copy!, merchant)
      requirements = InputBuilder.send(:copy!, requirements)
      constraints = [{"type" => "checkout.line_items", "items" => requirements},
        {"type" => "checkout.allowed_merchants", "allowed" => [merchant]}]
      ScopedConstraints.send(:multi_open!, constraints)
      PurchaseBinding.send(:times!, {"iat" => issued_at, "exp" => expires_at}, issued_at, profile_ref: profile_ref)
      agent = InputValidator.snapshot!(agent_public_key_pem, max_bytes: 1_024)
      provider = InputValidator.snapshot!(public_key_pem, max_bytes: 1_024)
      jwk = RootSignature.public_jwk!(agent)
      disclosures = []
      requirements.each do |requirement|
        requirement["acceptable_items"] = requirement["acceptable_items"].map do |candidate|
          disclose!(candidate, disclosures)
        end
      end
      constraints[1]["allowed"] = [disclose!(merchant, disclosures)]
      opening = {"vct" => "mandate.checkout.open.1", "iat" => issued_at, "exp" => expires_at,
        "cnf" => {"jwk" => jwk}, "constraints" => constraints}
      content = []
      marker = disclose!(opening, content)
      payload = {"delegate_payload" => [marker], "_sd_alg" => "sha-256"}
      if profile_ref == TrustContext::LONG_PROFILE_REF
        payload["ap2_profile"] = profile_ref
        preview = compact_preview(payload, "example+sd-jwt")
        RootDisclosures.send(:structural_root!, ([preview] + content + disclosures + [""]).join("~"), profile_ref: profile_ref)
      end
      jwt = MerchantSignature.sign!(payload, signer, provider,
        typ: "example+sd-jwt")
      wire = ([jwt] + content + disclosures + [""]).join("~")
      open!(wire, provider, agent, issued_at, profile_ref: profile_ref)
      Open.send(:new, wire)
    rescue StandardError, LoadError
      raise Invalid.new, cause: nil
    end

    # Provider private key is deliberately absent from this Agent API.
    def self.issue_closed(root_presentation:, checkout_jwt:, trusted_issuer_public_key_pem:,
                          agent_public_key_pem:, trusted_merchant_public_key_pem:, expected_merchant_id:,
                          audience:, nonce:, verified_at:, signer:, profile_ref: PROFILE_REF)
      profile_ref = profile!(profile_ref)
      root = InputValidator.snapshot!(root_presentation)
      checkout = InputValidator.snapshot!(checkout_jwt, max_bytes: 16_384)
      provider = InputValidator.snapshot!(trusted_issuer_public_key_pem, max_bytes: 1_024)
      agent = InputValidator.snapshot!(agent_public_key_pem, max_bytes: 1_024)
      merchant = InputValidator.snapshot!(trusted_merchant_public_key_pem, max_bytes: 1_024)
      identity = InputValidator.snapshot!(expected_merchant_id, max_bytes: 256)
      aud = InputValidator.snapshot!(audience, max_bytes: 512)
      challenge = InputValidator.snapshot!(nonce, max_bytes: 512)
      raise Invalid if aud.empty? || challenge.empty?
      CheckoutReceipt.send(:epoch!, verified_at)
      opening = open!(root, provider, agent, verified_at, profile_ref: profile_ref)
      checked = CheckoutJWT.verify(jwt: checkout, trusted_public_key_pem: merchant,
        expected_merchant_id: identity, profile_ref: profile_ref)
      ScopedConstraints.send(:multi_constraints!, {open: opening, checkout: checked.checkout},
        checked.checkout.fetch("currency"), ScopedConstraints.multi_checkout!(checked.checkout))
      closed = {"vct" => "mandate.checkout.1", "iat" => opening.fetch("iat"), "exp" => opening.fetch("exp"),
        "checkout_jwt" => checkout, "checkout_hash" => checked.checkout_hash}
      claims = {"aud" => aud, "nonce" => challenge, "iat" => verified_at,
        "sd_hash" => digest(root), "delegate_payload" => [closed]}
      if profile_ref == TrustContext::LONG_PROFILE_REF
        claims["ap2_profile"] = profile_ref
        CheckoutReceipt.reference(closed_sd_jwt: compact_preview(claims, "kb+sd-jwt") + "~", profile_ref: profile_ref)
      end
      terminal = MerchantSignature.sign!(claims, signer, agent, typ: "kb+sd-jwt")
      # Final handoff repeats the complete existing signature/condition path.
      ScopedConstraints.check!(root_presentation: root, terminal_jws: terminal, host_checkout_jws: checkout,
        trusted_issuer_public_key_pem: provider, expected_agent_public_key_pem: agent,
        trusted_merchant_public_key_pem: merchant, expected_aud: aud, expected_nonce: challenge,
        verified_at: verified_at, expected_checkout_id: checked.checkout.fetch("id"), expected_merchant_id: identity,
        expected_currency: checked.checkout.fetch("currency"),
        expected_total_minor: ScopedConstraints.multi_checkout!(checked.checkout), profile_ref: profile_ref)
      Closed.send(:new, root, terminal, checkout)
    rescue StandardError, LoadError
      raise Invalid.new, cause: nil
    end

    # Storage/transport only, never an authentication or authorization result.
    def self.present(root_presentation:, terminal_jws:, checkout_jwt:, profile_ref: PROFILE_REF)
      profile_ref = profile!(profile_ref)
      root = InputValidator.snapshot!(root_presentation)
      terminal = InputValidator.snapshot!(terminal_jws, max_bytes: 32_768)
      checkout = InputValidator.snapshot!(checkout_jwt, max_bytes: 16_384)
      # Exact commitment closure without claiming signature authentication.
      root_claims = profile_ref == TrustContext::LONG_PROFILE_REF ? RootDisclosures.send(:structural_root!, root, profile_ref: profile_ref) : RootDisclosures.send(:structural_root!, root)
      opening = root_claims.fetch("delegate_payload").first
      PurchaseBinding.send(:exact!, opening, %w[cnf constraints exp iat vct])
      raise Invalid unless opening["vct"] == "mandate.checkout.open.1"
      PurchaseBinding.send(:times!, opening, opening["iat"], profile_ref: profile_ref)
      PurchaseBinding.send(:exact!, opening["cnf"], %w[jwk])
      PurchaseBinding.send(:exact!, opening["cnf"]["jwk"], %w[kty crv x y])
      jwk = opening["cnf"]["jwk"]
      raise Invalid unless jwk["kty"] == "EC" && jwk["crv"] == "P-256" &&
        %w[x y].all? { |f| RootSignature.send(:decode!, jwk[f], 32).bytesize == 32 }
      ScopedConstraints.send(:multi_open!, opening["constraints"])
      CheckoutReceipt.reference(closed_sd_jwt: terminal + "~", profile_ref: profile_ref)
      claims = InputValidator.parse!(RootSignature.send(:decode!, terminal.split(".", -1)[1], 24_576))
      raise Invalid unless claims["sd_hash"] == digest(root) &&
        claims.fetch("delegate_payload").first.fetch("checkout_jwt") == checkout &&
        %w[iat exp].all? { |f| claims.fetch("delegate_payload").first[f] == opening[f] }
      Closed.send(:new, root, terminal, checkout)
    rescue StandardError, LoadError
      raise Invalid.new, cause: nil
    end

    def self.open!(wire, provider, agent, now, profile_ref: PROFILE_REF)
      opening = RootDisclosures.verified_root!(wire, provider, profile_ref: profile_ref).fetch("delegate_payload").first
      PurchaseBinding.send(:exact!, opening, %w[cnf constraints exp iat vct])
      raise Invalid unless opening["vct"] == "mandate.checkout.open.1"
      PurchaseBinding.send(:times!, opening, now, profile_ref: profile_ref)
      PurchaseBinding.send(:exact!, opening["cnf"], %w[jwk])
      raise Invalid unless opening["cnf"]["jwk"] == RootSignature.public_jwk!(agent)
      ScopedConstraints.send(:multi_open!, opening["constraints"])
      opening
    end
    def self.digest(wire) = Base64.urlsafe_encode64(Digest::SHA256.digest(wire), padding: false)
    def self.profile!(source)
      value = InputValidator.snapshot!(source, max_bytes: 256)
      raise Invalid unless [PROFILE_REF, TrustContext::LONG_PROFILE_REF].include?(value)
      value
    end
    def self.compact_preview(claims, typ)
      [Buyer.send(:encode, {"alg" => "ES256", "typ" => typ}), Buyer.send(:encode, claims), Buyer.send(:encode, "\0" * 64)].join(".")
    end
    def self.disclose!(value, disclosures)
      require "securerandom"
      salt = Base64.urlsafe_encode64(SecureRandom.random_bytes(16), padding: false)
      wire = Base64.urlsafe_encode64(JSON.generate([salt, value]), padding: false)
      disclosures << wire
      {"..." => digest(wire)}
    end
    %i[issue_open issue_closed present].each do |name|
      implementation = method(name)
      required = implementation.parameters.filter_map { |kind, field| field if kind == :keyreq }.freeze
      fields = implementation.parameters.map(&:last).freeze
      define_singleton_method(name) do |**arguments|
        unless (required - arguments.keys).empty? && (arguments.keys - fields).empty?
          raise Invalid.new, cause: nil
        end
        implementation.call(**arguments)
      end
    end
    private_class_method :open!, :digest, :disclose!, :profile!, :compact_preview
  end
end
