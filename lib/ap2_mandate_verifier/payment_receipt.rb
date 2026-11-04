# frozen_string_literal: true

module AP2MandateVerifier
  # Authenticity and reported outcome are separate. No automatic success/retry.
  module PaymentReceipt
    class Invalid < ArgumentError
      def initialize = super("invalid payment receipt information")
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
      attr_reader :code, :outcome, :payment_id, :psp_confirmation_id, :network_confirmation_id, :error, :error_description
      def initialize(claims = nil)
        @code = claims ? :payment_receipt_verified : :payment_receipt_verification_failed
        if claims
          @outcome, @payment_id, @psp_confirmation_id, @network_confirmation_id, @error, @error_description =
            claims.values_at("status", "payment_id", "psp_confirmation_id", "network_confirmation_id", "error", "error_description").map { |s| s&.freeze }
        end
        freeze
      end
      def verified? = code == :payment_receipt_verified
      def payment_succeeded? = verified? && outcome == "Success"
      def payment_rejected? = verified? && outcome == "Error"
      private_class_method :new
    end
    def self.reference(closed_sd_jwt:, profile_ref: Payment::PROFILE_REF) = Payment.reference(closed_sd_jwt: closed_sd_jwt, profile_ref: profile_ref)
    def self.sign(closed_sd_jwt:, issuer:, outcome:, payment_id:, issued_at:, signer:, public_key_pem:,
                  psp_confirmation_id: nil, network_confirmation_id: nil, error: nil, error_description: nil,
                  profile_ref: Payment::PROFILE_REF)
      ref = reference(closed_sd_jwt: closed_sd_jwt, profile_ref: profile_ref)
      claims = {"iss" => issuer, "status" => outcome, "payment_id" => payment_id, "iat" => issued_at, "reference" => ref}
      {"psp_confirmation_id" => psp_confirmation_id, "network_confirmation_id" => network_confirmation_id,
       "error" => error, "error_description" => error_description}.each { |k, v| claims[k] = v unless v.nil? }
      claims = InputBuilder.send(:copy!, claims)
      validate!(claims)
      Signed.send(:new, MerchantSignature.sign!(claims, signer, public_key_pem), ref)
    end
    def self.verify(jwt:, closed_sd_jwt:, trusted_public_key_pem:, expected_issuer:, expected_payment_id:,
                    not_before:, not_after:, verified_at:, profile_ref: Payment::PROFILE_REF)
      [not_before, not_after, verified_at].each { |t| CheckoutReceipt.send(:epoch!, t) }
      raise Invalid unless not_before <= verified_at && verified_at <= not_after
      expected = InputValidator.snapshot!(expected_issuer, max_bytes: 512)
      id = InputValidator.snapshot!(expected_payment_id, max_bytes: 512)
      text!(expected, 512); text!(id, 512)
      ref = reference(closed_sd_jwt: closed_sd_jwt, profile_ref: profile_ref)
      claims = RootSignature.verified_payload!(jwt, trusted_public_key_pem, expected_typ: "JWT", max_bytes: 16_384)
      validate!(claims)
      raise Invalid unless claims["iss"] == expected && claims["payment_id"] == id && claims["reference"] == ref &&
        claims["iat"].between?(not_before, verified_at)
      Verification.send(:new, claims)
    rescue StandardError, LoadError
      Verification.send(:new)
    end
    def self.validate!(claims)
      fields = %w[iss status iat reference payment_id] + case claims["status"]
      when "Success" then %w[psp_confirmation_id network_confirmation_id]
      when "Error" then %w[error error_description]
      else raise Invalid
      end
      PurchaseBinding.send(:exact!, claims, fields)
      CheckoutReceipt.send(:epoch!, claims["iat"])
      (fields - ["iat"]).each { |f| text!(claims[f], f == "error_description" ? 2_048 : 512) }
      raise Invalid unless claims["reference"].match?(/\A[A-Za-z0-9_-]{43}\z/)
    end
    def self.text!(v, max) = CheckoutReceipt.send(:text!, v, max)
    %i[reference sign verify].each do |name|
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
    private_class_method :validate!, :text!
  end
end
