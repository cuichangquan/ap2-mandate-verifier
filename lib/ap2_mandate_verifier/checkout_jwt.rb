# frozen_string_literal: true

module AP2MandateVerifier
  # Merchant-authored checkout, not a Mandate or authorization decision.
  module CheckoutJWT
    class Invalid < ArgumentError
      def initialize = super("invalid checkout signing information")
    end

    class Signed
      attr_reader :jwt, :checkout_hash
      def initialize(jwt)
        @jwt = jwt.freeze
        @checkout_hash = Base64.urlsafe_encode64(Digest::SHA256.digest(jwt), padding: false).freeze
        freeze
      end
      private_class_method :new
    end

    class Verification
      attr_reader :jwt, :checkout_hash, :checkout, :profile_ref
      def initialize(jwt, checkout, profile_ref)
        @jwt, @profile_ref = jwt, profile_ref
        @checkout_hash = Base64.urlsafe_encode64(Digest::SHA256.digest(jwt), padding: false).freeze
        @checkout = ResearchEvidence.send(:copy_frozen, checkout)
        freeze
      end
      def verified? = true
      private_class_method :new
    end

    # Merchant trust is selected by the application, never by received claims.
    # Checkout has no signed expiry: the app must check current order state.
    def self.verify(jwt:, trusted_public_key_pem:, expected_merchant_id:, profile_ref: TrustContext::PROFILE_REF)
      wire = InputValidator.snapshot!(jwt, max_bytes: 16_384)
      profile = InputValidator.snapshot!(profile_ref, max_bytes: 256)
      merchant = InputValidator.snapshot!(expected_merchant_id, max_bytes: 512)
      claims = RootSignature.verified_payload!(wire, trusted_public_key_pem, expected_typ: "JWT", max_bytes: 16_384)
      validate!(claims, profile_ref: profile)
      raise Invalid unless claims.fetch("merchant").fetch("id") == merchant
      Verification.send(:new, wire, claims, profile)
    rescue StandardError, LoadError
      raise Invalid.new, cause: nil
    end

    # signer.call receives the exact ASCII JWS signing input and must return a
    # 64-byte JOSE ES256 signature. The supplied independent public key verifies
    # the result before any signed object is returned (including remote signers).
    def self.sign(checkout:, signer:, public_key_pem:, profile_ref: TrustContext::PROFILE_REF)
      RootSignature.send(:dependencies!)
      value = InputBuilder.send(:copy!, checkout)
      validate!(value, profile_ref: profile_ref)
      jwt = MerchantSignature.sign!(value, signer, public_key_pem)
      Signed.send(:new, jwt)
    rescue StandardError, LoadError
      raise Invalid.new, cause: nil
    end

    # No key serialization, storage, lookup or logging. The application owns the
    # lifetime of this key/closure. Remote signers can implement the same call.
    def self.es256_signer(private_key:)
      RootSignature.send(:dependencies!)
      raise Invalid unless private_key.instance_of?(OpenSSL::PKey::EC) &&
        private_key.private? && private_key.group.curve_name == "prime256v1"
      lambda do |input|
        der = private_key.dsa_sign_asn1(Digest::SHA256.digest(input))
        OpenSSL::ASN1.decode(der).value.map { |n| n.value.to_s(2).rjust(32, "\0") }.join
      end
    rescue StandardError, LoadError
      raise Invalid.new, cause: nil
    end

    def self.validate!(checkout, profile_ref: TrustContext::PROFILE_REF)
      profile_ref = InputValidator.snapshot!(profile_ref, max_bytes: 256)
      if profile_ref == ScopedConstraints::MULTI_PROFILE_REF
        ScopedConstraints.multi_checkout!(checkout)
        return nil
      end
      raise Invalid unless profile_ref == TrustContext::PROFILE_REF
      c = ScopedConstraints
      c.send(:exact!, checkout, %w[currency id line_items links merchant status totals])
      c.send(:text!, checkout["id"])
      raise Invalid unless checkout["status"] == "ready_for_complete" &&
        c::CURRENCIES.include?(checkout["currency"]) && checkout["links"] == []
      c.send(:exact!, checkout["merchant"], %w[id name])
      c.send(:text!, checkout["merchant"]["id"])
      c.send(:text!, checkout["merchant"]["name"], 512)
      line = c.send(:one!, checkout["line_items"])
      c.send(:exact!, line, %w[id item quantity totals])
      c.send(:text!, line["id"])
      c.send(:quantity!, line["quantity"])
      item = line["item"]
      c.send(:exact!, item, %w[id price title])
      c.send(:text!, item["id"])
      c.send(:text!, item["title"], 512)
      c.send(:amount!, item["price"])
      total = item["price"] * line["quantity"]
      c.send(:amount!, total)
      c.send(:totals!, line["totals"], total)
      c.send(:totals!, checkout["totals"], total)
      nil
    end
    %i[sign es256_signer verify].each do |name|
      implementation = method(name)
      fields = implementation.parameters.filter_map { |kind, field| field if kind == :keyreq }.freeze
      optional = implementation.parameters.filter_map { |kind, field| field if kind == :key }.freeze
      define_singleton_method(name) do |**arguments|
        raise Invalid.new, cause: nil unless (fields - arguments.keys).empty? && (arguments.keys - fields - optional).empty?
        implementation.call(**arguments)
      end
    end
    private_class_method :validate!
  end
end
