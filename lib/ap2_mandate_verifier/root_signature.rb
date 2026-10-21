# frozen_string_literal: true

module AP2MandateVerifier
  # Crypto-only extraction of isolated_root_closure.rb's original JWS decode.
  # No legacy research parser, test autorun, SD resolver or Host code is loaded.
  module RootSignature
    MAX_WIRE_BYTES = 32_768
    MAX_KEY_BYTES = 1_024
    JWT_VERSION = "3.3.0"

    class Rejected < StandardError
      attr_reader :code
      def initialize(code)
        @code = code
        super(code.to_s)
      end
    end
    class Unavailable < Rejected; end

    def self.check!(source, issuer_pem)
      verified_payload!(source, issuer_pem)
      nil
    end

    # Internal stage handoff: always authenticates this original wire first.
    # Returned claims remain unvalidated for AP2 authority/schema/constraints.
    def self.verified_payload!(source, issuer_pem)
      wire = InputValidator.snapshot!(source, max_bytes: MAX_WIRE_BYTES)
      raise Rejected, :invalid_root_jws unless wire.ascii_only?
      parts = wire.split(".", -1)
      raise Rejected, :invalid_root_jws unless parts.length == 3
      dependencies!
      header = InputValidator.parse!(decode!(parts[0], 2_048))
      payload = InputValidator.parse!(decode!(parts[1], 24_576))
      signature = decode!(parts[2], 64)
      raise Rejected, :invalid_root_jws unless signature.bytesize == 64
      raise Rejected, :unsupported_root_header unless header.instance_of?(Hash) &&
        (header.keys - %w[alg typ kid]).empty? &&
        (!header.key?("kid") || (header["kid"].instance_of?(String) &&
          header["kid"].bytesize.between?(1, 128)))
      raise Rejected, :unsupported_root_algorithm unless header["alg"] == "ES256"
      raise Rejected, :unsupported_root_type unless header["typ"] == "example+sd-jwt"
      raise Rejected, :invalid_root_payload unless payload.instance_of?(Hash)
      key = public_key!(issuer_pem)

      begin
        # Preserve original signed bytes. Nested mandate claims/time, SD
        # completeness and Host constraints belong to later checks, not this
        # crypto-only primitive. Disabling top-level JWT claims grants nothing.
        verified, protected_header = JWT.decode(wire, key, true,
          algorithms: ["ES256"], verify_expiration: false,
          verify_not_before: false, verify_iat: false, verify_iss: false,
          verify_aud: false, verify_jti: false, verify_sub: false,
          required_claims: [], jwks: nil, x5c: nil)
      rescue JWT::DecodeError
        raise Rejected, :invalid_root_signature
      end
      raise Unavailable, :root_signature_check_unavailable unless verified == payload && protected_header == header
      payload
    end

    def self.dependencies!
      raise Unavailable, :signature_dependency_unavailable unless defined?(Gem)
      gem "jwt", "= #{JWT_VERSION}"
      require "jwt"
      require "base64"
      require "openssl"
      raise Unavailable, :signature_dependency_unavailable unless
        Gem.loaded_specs["jwt"]&.version&.to_s == JWT_VERSION
    rescue LoadError
      raise Unavailable, :signature_dependency_unavailable
    end

    def self.decode!(part, limit)
      raise Rejected, :invalid_root_jws unless part.match?(/\A[A-Za-z0-9_-]+\z/)
      raw = Base64.urlsafe_decode64(part + "=" * (-part.bytesize % 4))
      raise Rejected, :invalid_root_jws unless raw.bytesize <= limit &&
        Base64.urlsafe_encode64(raw, padding: false) == part
      raw.freeze
    rescue ArgumentError
      raise Rejected, :invalid_root_jws
    end

    def self.public_key!(source)
      begin
        pem = InputValidator.snapshot!(source, max_bytes: MAX_KEY_BYTES)
      rescue InputValidator::Invalid
        raise Unavailable, :issuer_key_unavailable
      end
      # Accept canonical SPKI public PEM only: no encrypted/private key
      # parsing, filesystem paths, URLs, JWK fetches or token-selected keys.
      raise Unavailable, :issuer_key_unsupported unless pem.ascii_only? &&
        pem.start_with?("-----BEGIN PUBLIC KEY-----\n")
      begin
        key = OpenSSL::PKey.read(pem)
        raise Unavailable, :issuer_key_unsupported unless
          key.instance_of?(OpenSSL::PKey::EC) && !key.private? &&
          key.group.curve_name == "prime256v1" && key.public_to_pem == pem
      rescue OpenSSL::PKey::PKeyError, ArgumentError
        raise Unavailable, :issuer_key_unsupported
      end
      key
    end
    private_class_method :dependencies!, :decode!, :public_key!
  end
end
