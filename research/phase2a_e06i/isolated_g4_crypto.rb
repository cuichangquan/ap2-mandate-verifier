# frozen_string_literal: true
#
# E06-I G4 only: synthetic, source-only cryptographic research boundary.
# REQUIRES prior G2 Issuer signature + G3 original Root closure from the
# caller. Host policy, keys, clock and Checkout wire here are NOT authenticated
# enrollment evidence. This module never authorizes a Checkout or emits G7.
# G5 Schema and G6 commerce semantics MUST follow independently.
require "json"
require "base64"
require "digest"
require_relative "../shared/strict_json_research"
require_relative "isolated_root_closure"

module AP2E06IG4Crypto
  class Rejected < StandardError
    attr_reader :code
    def initialize(code)
      @code = code
      super(code)
    end
  end

  class Unavailable < StandardError; end

  class << self
    # All named trusted_* inputs MUST be selected by an independent Host
    # boundary in a future implementation. The current caller uses only a
    # synthetic, self-consistent Host policy: conditional diagnostics, not G1.
    def inspect!(
      root_wire:, terminal_wire:, verified_open:, expected_agent_jwk:,
      trusted_merchant_jwk:, expected_aud:, expected_nonce:,
      host_checkout_jwt:, verified_at:, terminal_not_after:
    )
      raise Unavailable, "verification_unavailable:jwt_version" unless
        AP2E06IRootClosure.jwt_supported?
      # This instant is caller-asserted in the synthetic observer; it is NOT
      # a Host-authenticated B1 verification clock. Missing time is HOLD.
      raise Unavailable, "g4_verification_clock_unavailable" unless
        verified_at.is_a?(Integer) &&
        verified_at.between?(1, AP2E06IRootClosure::MAX_VERIFIED_AT) &&
        terminal_not_after.is_a?(Integer) &&
        terminal_not_after.between?(1, AP2E06IRootClosure::MAX_VERIFIED_AT)
      raise Rejected, "g4_terminal_host_deadline" unless
        verified_at < terminal_not_after
      raise Rejected, "g4_invalid_wires" unless
        bounded_wire?(root_wire, 32_768) &&
        bounded_wire?(terminal_wire, 32_768) &&
        bounded_wire?(host_checkout_jwt, 16_384) &&
        root_wire.bytesize + terminal_wire.bytesize +
          host_checkout_jwt.bytesize <= 131_072

      # Never substitute a token/header-selected JWK for the Host candidate
      # key. The Root holder key was already protected by G2/G3.
      raise Rejected, "g4_invalid_agent_key" unless
        public_p256?(expected_agent_jwk) &&
        verified_open.is_a?(Hash) &&
        verified_open["cnf"].is_a?(Hash) &&
        verified_open["cnf"].keys == ["jwk"] &&
        verified_open["cnf"]["jwk"] == expected_agent_jwk
      raise Rejected, "g4_invalid_merchant_key" unless public_p256?(trusted_merchant_jwk)
      # Preserve P1-2's strict signed Root/Closed lifetime and immutable
      # shared-claim invariants, even though official G5 follows later.
      raise Rejected, "g4_invalid_signed_root_time" unless
        verified_open["iat"].is_a?(Integer) &&
        verified_open["exp"].is_a?(Integer) &&
        verified_open["iat"] <= verified_at &&
        verified_at < verified_open["exp"] &&
        (verified_open["exp"] - verified_open["iat"]).between?(1, 7200)
      raise Rejected, "g4_invalid_host_challenge" unless
        [expected_aud, expected_nonce].all? { |s|
          s.is_a?(String) && s.ascii_only? && s.bytesize.between?(1, 256)
        }

      # Pinned upstream terminal uses exactly one disclosed Closed object.
      # Never deserialize an unsigned visible Closed value as evidence.
      parts = terminal_wire.split("~", -1)
      raise Rejected, "g4_unsupported_terminal_disclosures" unless
        parts.size == 3 && parts.last == ""
      compact, disclosure = parts.values_at(0, 1)
      signed = checked_jws!(compact, "kb+sd-jwt")
      required = %w[aud delegate_payload iat nonce sd_hash]
      raise Rejected, "g4_unsupported_terminal_claims" unless
        signed.is_a?(Hash) &&
        (signed.keys - (required + ["_sd_alg"])).empty? &&
        (required - signed.keys).empty? &&
        [nil, "sha-256"].include?(signed["_sd_alg"]) &&
        signed["iat"].is_a?(Integer) &&
        (verified_at - signed["iat"]).between?(0, 300) &&
        terminal_not_after > signed["iat"] &&
        (terminal_not_after - signed["iat"]).between?(1, 7200) &&
        signed["aud"] == expected_aud &&
        signed["nonce"] == expected_nonce

      verify_signature!(compact, expected_agent_jwk, signed, "g4_invalid_agent_signature")
      expected_sd_hash = b64(Digest::SHA256.digest(root_wire.b))
      raise Rejected, "g4_invalid_root_sd_hash" unless
        secure_equal?(signed["sd_hash"], expected_sd_hash)

      marker_array = signed["delegate_payload"]
      raise Rejected, "g4_invalid_signed_terminal_envelope" unless
        marker_array.is_a?(Array) && marker_array.size == 1 &&
        marker_array[0].is_a?(Hash) && marker_array[0].keys == ["..."]
      marker_digest = marker_array[0]["..."]
      raise Rejected, "g4_invalid_signed_terminal_digest" unless
        marker_digest.is_a?(String) &&
        marker_digest.match?(/\A[A-Za-z0-9_-]{43}\z/)

      disclosed = AP2StrictJSONResearch.decode_part!(disclosure)
      raise Rejected, "g4_unsupported_closed_disclosure" unless
        disclosed.is_a?(Array) && disclosed.size == 2 &&
        disclosed[0].is_a?(String) &&
        disclosed[0].bytesize.between?(8, 128) &&
        disclosed[1].is_a?(Hash) &&
        secure_equal?(marker_digest, b64(Digest::SHA256.digest(disclosure.b)))
      closed = disclosed[1]
      # Verify all nested disclosure-bearing paths (not merely top-level
      # keys), then keep the original P1-2 signed Closed clock/claim checks.
      reject_sd_markers!(closed)
      raise Rejected, "g4_invalid_closed_carrier" unless
        closed.keys.sort == %w[checkout_hash checkout_jwt exp iat vct] &&
        closed["vct"] == "mandate.checkout.1" &&
        closed["iat"].is_a?(Integer) && closed["exp"].is_a?(Integer) &&
        closed["iat"] == verified_open["iat"] &&
        closed["exp"] == verified_open["exp"] &&
        closed["iat"] <= verified_at && verified_at < closed["exp"] &&
        (closed["exp"] - closed["iat"]).between?(1, 7200)
      raise Rejected, "g4_missing_checkout_binding" unless
        bounded_wire?(closed["checkout_jwt"], 16_384) &&
        closed["checkout_hash"].is_a?(String) &&
        secure_equal?(closed["checkout_jwt"], host_checkout_jwt) &&
        secure_equal?(
          closed["checkout_hash"],
          b64(Digest::SHA256.digest(host_checkout_jwt.b))
        )

      # Verify the Host-supplied original compact Merchant signature, not
      # decoded/re-serialized JSON. The Host wire is not itself trust proof.
      merchant_signed = checked_jws!(host_checkout_jwt, "JWT")
      verify_signature!(
        host_checkout_jwt, trusted_merchant_jwk, merchant_signed,
        "g4_invalid_merchant_signature"
      )
      true # Internal conditional crypto observation; NEVER VerifiedEvidence.
    rescue Rejected, Unavailable
      raise
    rescue JWT::DecodeError, JWT::JWKError, JSON::ParserError,
           ArgumentError, TypeError, KeyError, RangeError
      raise Rejected, "g4_invalid_signed_input"
    rescue StandardError
      raise Unavailable, "g4_verification_unavailable"
    end

    private

    # Signed disclosure JSON only; recursive full-depth SD marker rejection.
    # Every non-supported commitment is ambiguous, not harmless metadata.
    def reject_sd_markers!(obj, depth = 0)
      raise Rejected, "g4_unsupported_nested_disclosure" if depth > 24
      case obj
      when Hash
        raise Rejected, "g4_unsupported_nested_disclosure" if
          obj.size > 32 || obj.key?("_sd") || obj.key?("...") ||
          obj.keys.any? { |key| !key.is_a?(String) }
        obj.each_value { |child| reject_sd_markers!(child, depth + 1) }
      when Array
        raise Rejected, "g4_unsupported_nested_disclosure" if obj.size > 16
        obj.each { |child| reject_sd_markers!(child, depth + 1) }
      end
    end

    def bounded_wire?(s, max)
      s.is_a?(String) && s.ascii_only? && s.bytesize.between?(1, max)
    end

    def public_p256?(jwk)
      return false unless jwk.is_a?(Hash) &&
        jwk.keys.sort == %w[crv kty x y] &&
        jwk["kty"] == "EC" && jwk["crv"] == "P-256"
      %w[x y].all? do |member|
        part = jwk[member]
        next false unless part.is_a?(String) &&
          part.match?(/\A[A-Za-z0-9_-]{43}\z/)
        raw = Base64.urlsafe_decode64(part + "=")
        raw.bytesize == 32 && b64(raw) == part
      end
    rescue ArgumentError
      false
    end

    def checked_jws!(compact, typ)
      raise Rejected, "g4_oversized_jws" unless bounded_wire?(compact, 16_384)
      _, _, signature_part = AP2StrictJSONResearch.jwt_parts!(compact)
      raise Rejected, "g4_noncanonical_es256_signature" unless
        signature_part.match?(/\A[A-Za-z0-9_-]+\z/)
      signature = Base64.urlsafe_decode64(
        signature_part + ("=" * (-signature_part.bytesize % 4))
      )
      raise Rejected, "g4_noncanonical_es256_signature" unless
        signature.bytesize == 64 && b64(signature) == signature_part
      header, payload = AP2StrictJSONResearch.validate_signed_jws_json!(compact)
      raise Rejected, "g4_unsupported_jose" unless
        header.is_a?(Hash) && header["alg"] == "ES256" &&
        header["typ"] == typ &&
        (header.keys - %w[alg kid typ]).empty? &&
        (!header.key?("kid") || header["kid"].is_a?(String))
      raise Rejected, "g4_invalid_signed_json" unless payload.is_a?(Hash)
      payload
    end

    def verify_signature!(compact, jwk, strict_payload, reason)
      decoded, = JWT.decode(
        compact, JWT::JWK.import(jwk).public_key, true,
        {
          algorithms: ["ES256"], verify_expiration: false,
          verify_not_before: false, verify_iat: false,
          verify_iss: false, verify_aud: false, verify_jti: false
        }
      )
      raise Rejected, reason unless decoded == strict_payload
    rescue JWT::DecodeError, JWT::JWKError
      raise Rejected, reason
    end

    def b64(data)
      Base64.urlsafe_encode64(data, padding: false)
    end

    def secure_equal?(a, b)
      return false unless a.is_a?(String) && b.is_a?(String) &&
        a.bytesize == b.bytesize
      difference = 0
      a.bytes.zip(b.bytes) { |x, y| difference |= x ^ y }
      difference.zero?
    end
  end
end
