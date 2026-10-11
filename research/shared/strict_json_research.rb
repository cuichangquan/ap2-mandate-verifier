# frozen_string_literal: true
#
# P1-6 research-only JSON parser. Checks duplicate keys at every nesting level
# before the already-existing JWT signature verifier consumes claim values.
# Parsing untrusted text here is NOT proof of signature or issuer identity.
require "json"
require "base64"

module AP2StrictJSONResearch
  class UniqueKeyObject < Hash
    def []=(key, value)
      raise JSON::ParserError, "duplicate JSON object key" if key?(key)
      super
    end
  end

  class << self
    def parse!(raw)
      raise JSON::ParserError, "JSON source must be String" unless raw.is_a?(String)
      JSON.parse(raw, object_class: UniqueKeyObject, max_nesting: 40, allow_nan: false)
    end

    def jwt_parts!(compact)
      raise JSON::ParserError, "compact JWS expected" unless compact.is_a?(String)
      parts = compact.split(".", -1)
      raise JSON::ParserError, "exactly three JWS segments required" unless parts.size == 3 &&
        parts.all? { |part| !part.empty? }
      parts
    end

    def decode_part!(part)
      raise JSON::ParserError, "noncanonical base64url JWS part" unless part.is_a?(String) &&
        part.match?(/\A[A-Za-z0-9_-]+\z/)
      bytes = Base64.urlsafe_decode64(part + ("=" * (-part.size % 4)))
      raise JSON::ParserError, "noncanonical base64url JWS part" unless
        Base64.urlsafe_encode64(bytes, padding: false) == part
      parse!(bytes)
    end

    # Check JSON ambiguity in *both* protected JOSE header and signed payload.
    # The original compact bytes are still passed unchanged to JWT.decode.
    def validate_signed_jws_json!(compact)
      header, payload, = jwt_parts!(compact)
      [decode_part!(header), decode_part!(payload)]
    end
  end
end
