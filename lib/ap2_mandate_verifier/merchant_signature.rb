# frozen_string_literal: true

module AP2MandateVerifier
  # Internal ES256 primitive. Callers must validate the payload's own profile.
  module MerchantSignature
    def self.sign!(claims, signer, public_key_pem)
      RootSignature.send(:dependencies!)
      payload = InputBuilder.send(:json!, claims, 12_000)
      pem = InputValidator.snapshot!(public_key_pem, max_bytes: 1_024)
      RootSignature.public_jwk!(pem)
      header = Base64.urlsafe_encode64('{"alg":"ES256","typ":"JWT"}', padding: false)
      input = "#{header}.#{Base64.urlsafe_encode64(payload, padding: false)}".freeze
      raw = signer.call(input)
      raise ArgumentError unless Object.instance_method(:instance_of?).bind_call(raw, String) &&
        String.instance_method(:bytesize).bind_call(raw) == 64
      signature = String.instance_method(:byteslice).bind_call(raw, 0, 64)
      jwt = "#{input}.#{Base64.urlsafe_encode64(signature, padding: false)}"
      raise ArgumentError unless RootSignature.verified_payload!(jwt, pem, expected_typ: "JWT", max_bytes: 16_384) == claims
      jwt.freeze
    end
  end
end
