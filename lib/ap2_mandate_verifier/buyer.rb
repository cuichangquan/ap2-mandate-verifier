# frozen_string_literal: true

module AP2MandateVerifier
  # Optional Direct/Human Present profile; never an Open -> Closed chain.
  module Buyer
    PROFILE_REF = "ap2.checkout.direct.single_merchant".freeze
    CHECKOUT_PROFILE = ScopedConstraints::MULTI_PROFILE_REF
    MAX_LIFETIME = 600
    class Invalid < ArgumentError
      def initialize = super("invalid direct checkout information")
    end
    class Issued
      attr_reader :closed_sd_jwt
      def initialize(wire)
        @closed_sd_jwt = wire.freeze
        freeze
      end
      private_class_method :new
    end
    class Verification
      attr_reader :code, :checkout, :checkout_hash, :reference, :expires_at
      def initialize(code, parsed = nil)
        @code = code
        if parsed
          @checkout = parsed.fetch(:checkout)
          @checkout_hash = parsed.fetch(:closed).fetch("checkout_hash").freeze
          @expires_at = parsed.fetch(:closed).fetch("exp")
          @reference = Buyer.send(:hash, parsed.fetch(:wire)).freeze
        end
        freeze
      end
      def verified? = code == :direct_checkout_verified
      private_class_method :new
    end

    # Only the authenticated approval backend calls this method. The approved
    # wire comes from its protected approval record, never an Agent boolean.
    # This is an equality contract, not authentication of the approver.
    def self.issue_closed(checkout_jwt:, approved_checkout_jwt:, trusted_merchant_public_key_pem:,
                          expected_merchant_id:, issued_at:, expires_at:, signer:, public_key_pem:)
      wire = InputValidator.snapshot!(checkout_jwt, max_bytes: 16_384)
      approved = InputValidator.snapshot!(approved_checkout_jwt, max_bytes: 16_384)
      raise Invalid unless wire == approved
      epoch!(issued_at); epoch!(expires_at)
      raise Invalid unless expires_at > issued_at && expires_at - issued_at <= MAX_LIFETIME
      checked = CheckoutJWT.verify(jwt: wire, trusted_public_key_pem: trusted_merchant_public_key_pem,
        expected_merchant_id: expected_merchant_id, profile_ref: CHECKOUT_PROFILE)
      require "securerandom"
      disclosure = encode([encode(SecureRandom.random_bytes(16)), "checkout_jwt", checked.jwt])
      closed = {"vct" => "mandate.checkout.1", "checkout_hash" => checked.checkout_hash,
        "iat" => issued_at, "exp" => expires_at, "_sd" => [hash(disclosure)]}
      content = encode([encode(SecureRandom.random_bytes(16)), closed])
      payload = {"delegate_payload" => [{"..." => hash(content)}], "_sd_alg" => "sha-256"}
      jwt = MerchantSignature.sign!(payload, signer, public_key_pem, typ: "example+sd-jwt")
      result = "#{jwt}~#{content}~#{disclosure}~"
      parse!(result)
      Issued.send(:new, result)
    rescue StandardError, LoadError
      raise Invalid.new, cause: nil
    end

    # All two disclosures are required for this profile. No Agent signature,
    # aud, nonce, or KB-JWT is added. Restoration preserves the exact bytes.
    def self.present_closed(closed_sd_jwt:)
      parse!(closed_sd_jwt).fetch(:wire)
    rescue StandardError, LoadError
      raise Invalid.new, cause: nil
    end

    # Merchant supplies independently registered Provider/Merchant keys and
    # the exact current order from its own database. Success is not Host ALLOW.
    def self.verify(closed_sd_jwt:, trusted_provider_public_key_pem:, trusted_merchant_public_key_pem:,
                    expected_checkout_jwt:, expected_merchant_id:, verified_at:)
      epoch!(verified_at)
      parsed = parse!(closed_sd_jwt)
      RootSignature.verified_payload!(parsed.fetch(:jwt), trusted_provider_public_key_pem)
      closed = parsed.fetch(:closed)
      raise Invalid unless closed.fetch("iat") <= verified_at && verified_at < closed.fetch("exp")
      expected = InputValidator.snapshot!(expected_checkout_jwt, max_bytes: 16_384)
      raise Invalid unless closed.fetch("checkout_jwt") == expected
      checked = CheckoutJWT.verify(jwt: expected, trusted_public_key_pem: trusted_merchant_public_key_pem,
        expected_merchant_id: expected_merchant_id, profile_ref: CHECKOUT_PROFILE)
      Verification.send(:new, :direct_checkout_verified, parsed.merge(checkout: checked.checkout))
    rescue StandardError, LoadError
      Verification.send(:new, :direct_checkout_verification_failed)
    end

    # Exact bounded grammar, not a general selective-disclosure resolver.
    # Every commitment is consumed exactly once, without decoys/hidden fields.
    def self.parse!(source)
      RootSignature.send(:dependencies!)
      wire = InputValidator.snapshot!(source, max_bytes: 32_768)
      raise Invalid unless wire.ascii_only?
      jwt, content, disclosure, tail, *extra = wire.split("~", -1)
      raise Invalid unless tail == "" && extra.empty?
      parts = jwt.split(".", -1)
      raise Invalid unless parts.size == 3
      header = InputValidator.parse!(RootSignature.send(:decode!, parts[0], 2_048))
      CheckoutReceipt.send(:header!, header, "example+sd-jwt")
      raise Invalid unless RootSignature.send(:decode!, parts[2], 64).bytesize == 64
      payload = InputValidator.parse!(RootSignature.send(:decode!, parts[1], 2_048))
      exact!(payload, %w[_sd_alg delegate_payload])
      raise Invalid unless payload["_sd_alg"] == "sha-256"
      pointer = ScopedConstraints.send(:one!, payload["delegate_payload"])
      exact!(pointer, ["..."])
      raise Invalid unless pointer["..."] == hash(content)
      revealed = decode_disclosure!(content, 2)
      closed = revealed[1]
      exact!(closed, %w[_sd checkout_hash exp iat vct])
      raise Invalid unless closed["vct"] == "mandate.checkout.1" && closed["_sd"] == [hash(disclosure)]
      epoch!(closed["iat"]); epoch!(closed["exp"])
      raise Invalid unless closed["exp"] > closed["iat"] && closed["exp"] - closed["iat"] <= MAX_LIFETIME
      leaf = decode_disclosure!(disclosure, 3)
      raise Invalid unless leaf[1] == "checkout_jwt"
      checkout = InputValidator.snapshot!(leaf[2], max_bytes: 16_384)
      raise Invalid unless closed["checkout_hash"] == hash(checkout)
      # Parse supported merchant syntax too, without claiming its authenticity.
      checkout_parts = checkout.split(".", -1)
      raise Invalid unless checkout_parts.size == 3
      checkout_header = InputValidator.parse!(RootSignature.send(:decode!, checkout_parts[0], 2_048))
      CheckoutReceipt.send(:header!, checkout_header, "JWT")
      raise Invalid unless RootSignature.send(:decode!, checkout_parts[2], 64).bytesize == 64
      claims = InputValidator.parse!(RootSignature.send(:decode!, checkout_parts[1], 12_000))
      CheckoutJWT.send(:validate!, claims, profile_ref: CHECKOUT_PROFILE)
      {wire: wire, jwt: jwt, closed: closed.merge("checkout_jwt" => checkout)}
    end
    def self.decode_disclosure!(wire, size)
      value = InputValidator.parse!(RootSignature.send(:decode!, wire, 24_576))
      raise Invalid unless value.instance_of?(Array) && value.size == size &&
        value[0].instance_of?(String) && value[0].match?(/\A[A-Za-z0-9_-]{22,128}\z/)
      value
    end
    def self.epoch!(value) = CheckoutReceipt.send(:epoch!, value)
    def self.exact!(value, fields) = PurchaseBinding.send(:exact!, value, fields)
    def self.hash(wire) = Base64.urlsafe_encode64(Digest::SHA256.digest(wire), padding: false)
    def self.encode(value)
      require "json"
      Base64.urlsafe_encode64(value.instance_of?(String) ? value : JSON.generate(value), padding: false)
    end
    %i[issue_closed present_closed verify].each do |name|
      implementation = method(name)
      fields = implementation.parameters.map(&:last).freeze
      define_singleton_method(name) do |**arguments|
        unless (fields - arguments.keys).empty? && (arguments.keys - fields).empty?
          next Verification.send(:new, :direct_checkout_verification_failed) if name == :verify
          raise Invalid.new, cause: nil
        end
        implementation.call(**arguments)
      end
    end
    private_class_method :parse!, :decode_disclosure!, :epoch!, :exact!, :hash, :encode
  end
end
