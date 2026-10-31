# frozen_string_literal: true

module AP2MandateVerifier
  # Checkout-specific pinned Schema; independent of Verifier Result/Evidence.
  module CheckoutReceipt
    class Invalid < ArgumentError
      def initialize = super("invalid checkout receipt information")
    end
    class Signed
      attr_reader :jwt, :reference
      def initialize(jwt, reference)
        @jwt, @reference = jwt.freeze, reference.freeze
        freeze
      end
      private_class_method :new
    end
    class Verification
      attr_reader :code, :outcome, :order_id, :error, :error_description
      def initialize(code, claims = nil)
        @code = code
        if claims
          @outcome = claims.fetch("status").freeze
          @order_id, @error, @error_description = claims.values_at("order_id", "error", "error_description").map { |v| v&.freeze }
        end
        freeze
      end
      def verified? = code == :receipt_verified
      def purchase_succeeded? = verified? && outcome == "Success"
      def purchase_rejected? = verified? && outcome == "Error"
      private_class_method :new
    end

    # Exact received final closed SD-JWT, no disclosures or additional hop.
    # A terminal compact JWS alone is intentionally not accepted or repaired.
    def self.reference(closed_sd_jwt:, profile_ref: TrustContext::PROFILE_REF)
      wire = InputValidator.snapshot!(closed_sd_jwt, max_bytes: 32_769)
      raise Invalid unless wire.ascii_only? && wire.end_with?("~") && wire.count("~") == 1
      compact = wire.byteslice(0, wire.bytesize - 1)
      parts = compact.split(".", -1)
      raise Invalid unless parts.size == 3
      RootSignature.send(:dependencies!)
      header = InputValidator.parse!(RootSignature.send(:decode!, parts[0], 2_048))
      claims = InputValidator.parse!(RootSignature.send(:decode!, parts[1], 24_576))
      signature = RootSignature.send(:decode!, parts[2], 64)
      header!(header, "kb+sd-jwt")
      raise Invalid unless signature.bytesize == 64
      # Existing inline terminal grammar only, never general SD resolution.
      PurchaseBinding.send(:exact!, claims, %w[aud delegate_payload iat nonce sd_hash])
      %w[aud nonce sd_hash].each { |field| text!(claims[field], 512) }
      epoch!(claims["iat"])
      raise Invalid unless claims["sd_hash"].match?(/\A[A-Za-z0-9_-]{43}\z/)
      closed = ScopedConstraints.send(:one!, claims["delegate_payload"])
      PurchaseBinding.send(:exact!, closed, %w[checkout_hash checkout_jwt exp iat vct])
      raise Invalid unless closed["vct"] == "mandate.checkout.1"
      epoch!(closed["iat"]); epoch!(closed["exp"])
      raise Invalid unless closed["exp"] > closed["iat"] && closed["checkout_hash"].instance_of?(String) &&
        closed["checkout_hash"].match?(/\A[A-Za-z0-9_-]{43}\z/)
      checkout = InputValidator.snapshot!(closed["checkout_jwt"], max_bytes: 16_384)
      raise Invalid unless checkout.ascii_only? && checkout.split(".", -1).size == 3 &&
        checkout.split(".", -1).all? { |part| part.match?(/\A[A-Za-z0-9_-]+\z/) }
      checkout_parts = checkout.split(".", -1)
      checkout_header = InputValidator.parse!(RootSignature.send(:decode!, checkout_parts[0], 2_048))
      header!(checkout_header, "JWT")
      raise Invalid unless RootSignature.send(:decode!, checkout_parts[2], 64).bytesize == 64
      CheckoutJWT.send(:validate!, InputValidator.parse!(RootSignature.send(:decode!, checkout_parts[1], 12_000)), profile_ref: profile_ref)
      raise Invalid unless closed["checkout_hash"] == hash(checkout)
      hash(wire).freeze
    rescue StandardError, LoadError
      raise Invalid.new, cause: nil
    end

    def self.sign(closed_sd_jwt:, issuer:, outcome:, issued_at:, signer:, public_key_pem:, order_id: nil, error: nil, error_description: nil,
                  profile_ref: TrustContext::PROFILE_REF)
      ref = reference(closed_sd_jwt: closed_sd_jwt, profile_ref: profile_ref)
      claims = {"iss" => issuer, "status" => outcome, "iat" => issued_at, "reference" => ref}
      claims["order_id"] = order_id unless order_id.nil?
      claims["error"] = error unless error.nil?
      claims["error_description"] = error_description unless error_description.nil?
      claims = InputBuilder.send(:copy!, claims)
      validate!(claims)
      jwt = MerchantSignature.sign!(claims, signer, public_key_pem)
      Signed.send(:new, jwt, ref)
    rescue StandardError, LoadError
      raise Invalid.new, cause: nil
    end

    # The Host supplies trusted enrollment key, expected signer and explicit time
    # window independently. JWT iss/kid are never used to choose trust.
    # Reference authenticates byte identity, not Mandate authorization/validity.
    def self.verify(jwt:, closed_sd_jwt:, trusted_public_key_pem:, expected_issuer:, not_before:, not_after:, verified_at:,
                    profile_ref: TrustContext::PROFILE_REF)
      expected = InputValidator.snapshot!(expected_issuer, max_bytes: 512)
      text!(expected, 512)
      [not_before, not_after, verified_at].each { |t| epoch!(t) }
      raise Invalid unless not_before <= verified_at && verified_at <= not_after
      ref = reference(closed_sd_jwt: closed_sd_jwt, profile_ref: profile_ref)
      claims = RootSignature.verified_payload!(jwt, trusted_public_key_pem, expected_typ: "JWT", max_bytes: 16_384)
      validate!(claims)
      return Verification.send(:new, :receipt_issuer_mismatch) unless claims["iss"] == expected
      return Verification.send(:new, :receipt_reference_mismatch) unless claims["reference"] == ref
      return Verification.send(:new, :receipt_time_mismatch) unless claims["iat"].between?(not_before, verified_at)
      Verification.send(:new, :receipt_verified, claims)
    rescue StandardError, LoadError
      Verification.send(:new, :receipt_verification_failed)
    end

    def self.validate!(claims)
      raise Invalid unless claims.instance_of?(Hash)
      fields = case claims["status"]
      when "Success" then %w[iss status iat reference order_id]
      when "Error" then %w[iss status iat reference error error_description]
      else raise Invalid
      end
      raise Invalid unless claims.keys.sort == fields.sort
      epoch!(claims["iat"])
      (fields - %w[iat]).each { |field| text!(claims[field], field == "error_description" ? 2_048 : 512) }
      raise Invalid unless claims["reference"].match?(/\A[A-Za-z0-9_-]{43}\z/)
    end
    def self.text!(value, max)
      raise Invalid unless value.instance_of?(String) && value.bytesize.between?(1, max)
    end
    def self.epoch!(value)
      raise Invalid unless Object.instance_method(:instance_of?).bind_call(value, Integer) && value.between?(0, PurchaseBinding::MAX_EPOCH)
    end
    def self.header!(header, typ)
      raise Invalid unless header.instance_of?(Hash) && (header.keys - %w[alg typ kid]).empty? &&
        header["alg"] == "ES256" && header["typ"] == typ
      text!(header["kid"], 128) if header.key?("kid")
    end
    def self.hash(wire) = Base64.urlsafe_encode64(Digest::SHA256.digest(wire), padding: false)
    %i[reference sign verify].each do |name|
      implementation = method(name)
      required = implementation.parameters.filter_map { |kind, field| field if kind == :keyreq }.freeze
      fields = implementation.parameters.filter_map { |kind, field| field if %i[key keyreq].include?(kind) }.freeze
      define_singleton_method(name) do |**arguments|
        unless (required - arguments.keys).empty? && (arguments.keys - fields).empty?
          next Verification.send(:new, :receipt_verification_failed) if name == :verify
          raise Invalid.new, cause: nil
        end
        implementation.call(**arguments)
      end
    end
    private_class_method :validate!, :text!, :epoch!, :header!, :hash
  end
end
