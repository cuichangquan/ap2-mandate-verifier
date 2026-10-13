# frozen_string_literal: true
#
# E06-I A2-1: bounded, isolated Host-owned context CANDIDATE inspection.
# DESIGN IMPLEMENTATION ONLY / NOT RUN / NO FIXTURES / NO CI APPROVAL.
#
# This does NOT establish Host record provenance, nonce uniqueness, live
# revocation or G1 PASS. Never accept a caller-controlled expected_digest
# or the returned Candidate as a proof of authorized trust. It cannot create
# G7 Evidence and must not be wired as a successful G1 in this slice.
#
# Unlike the archived synthetic-e01s policy, it requires individual signer
# trust windows and immutable Challenge/Checkout references. No production
# Host adapter, nonce registry, atomic CAS or signing key exists here.
require "json"
require "digest"
require "base64"
require_relative "../shared/strict_json_research"

module AP2E06IHostSnapshot
  MAX_CONTEXT_BYTES = 16_384
  MAX_CHECKOUT_BYTES = 16_384
  MAX_DEPTH = 24
  MAX_FIELDS = 32
  MAX_ARRAY = 16
  MAX_TIME = 4_102_444_800 # bounded research timestamps (before 2100 UTC)

  FIELDS = %w[
    agent_trust challenge checkout issuer_trust merchant_trust nonce_issuance
    profile_ref
  ].sort.freeze
  TRUST_FIELDS = %w[
    active key_jwk key_not_after key_not_before key_revocation
    policy_active policy_not_after policy_not_before policy_ref
    policy_revocation policy_version subject_ref tenant_id
  ].sort.freeze
  CHALLENGE_FIELDS = %w[
    agent_thumbprint aud buyer_account_ref checkout_ref expires_at
    issued_at nonce ref
  ].sort.freeze
  CHECKOUT_FIELDS = %w[
    amount_minor buyer_account_ref currency expected_status merchant_id
    original_jwt quantity ref sku_id sku_title
  ].sort.freeze
  CHECKOUT_REF_FIELDS = %w[checkout_id checkout_version tenant_id].sort.freeze
  NONCE_FIELDS = %w[
    atomic_uniqueness domain entropy_bits issuance_ref registry_ref unique
  ].sort.freeze
  JWK_FIELDS = %w[crv kty x y].sort.freeze
  # NIST P-256 field prime / b coefficient, for validating supplied PUBLIC
  # coordinates. No private key operations or arbitrary curve selection.
  P256_P = 0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff
  P256_B = 0x5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b

  class Halt < StandardError
    attr_reader :status, :code

    def initialize(status, code)
      @status, @code = status, code
      super(code)
    end
  end

  # An explicitly NON-AUTHORITATIVE value. Callers must not promote it to G1.
  # A Host provenance/registry adapter and its independent review are needed
  # before even a synthetic G1 success path can be implemented.
  class Candidate
    attr_reader :snapshot, :raw_sha256, :verified_at

    def initialize(snapshot:, raw_sha256:, verified_at:)
      @snapshot = snapshot
      @raw_sha256 = raw_sha256.freeze
      @verified_at = verified_at
      freeze
    end

    def status
      "HOLD"
    end

    def reason
      "trusted_host_provenance_and_nonce_registry_unverified"
    end

    def evidence
      nil
    end

    def admissible?
      false
    end
  end

  class << self
    # expected_sha256 and verified_at MUST originate from the independent Host.
    # Comparing a matching digest does not authenticate the source or registry.
    # This method inspects bounded JSON and returns only a HOLD-only Candidate.
    def inspect_candidate!(host_json:, expected_sha256:, verified_at:)
      halt!("REJECT", "invalid_host_input") unless
        host_json.is_a?(String) && host_json.ascii_only? &&
        host_json.bytesize.between?(1, MAX_CONTEXT_BYTES) &&
        expected_sha256.is_a?(String) &&
        expected_sha256.match?(/\A[0-9a-f]{64}\z/) &&
        epoch?(verified_at)

      actual_sha256 = Digest::SHA256.hexdigest(host_json.b)
      halt!("HOLD", "untrusted_host_snapshot_digest") unless
        fixed_equal?(actual_sha256, expected_sha256)

      parsed = AP2StrictJSONResearch.parse!(host_json)
      check_bounds!(parsed)
      exact!(parsed, FIELDS, "invalid_host_fields")
      halt!("REJECT", "unsupported_profile") unless
        parsed.fetch("profile_ref") == "e06i-fixed-issuer-a-v1"

      %w[issuer_trust agent_trust merchant_trust].each do |name|
        validate_trust!(parsed.fetch(name), verified_at: verified_at)
      end
      validate_checkout!(parsed.fetch("checkout"))
      # This fixed one-tenant profile MUST NOT select a Merchant key for
      # another Merchant or tenant. The same tenant also bounds the Issuer
      # and Agent trust scopes in this deliberately closed-world lab.
      checkout = parsed.fetch("checkout")
      tenant_id = checkout.fetch("ref").fetch("tenant_id")
      %w[issuer_trust agent_trust merchant_trust].each do |signer|
        halt!("REJECT", "host_trust_tenant_mismatch") unless
          parsed.fetch(signer).fetch("tenant_id") == tenant_id
      end
      halt!("REJECT", "host_merchant_identity_mismatch") unless
        parsed.fetch("merchant_trust").fetch("subject_ref") ==
        checkout.fetch("merchant_id")
      validate_challenge!(
        parsed.fetch("challenge"), parsed.fetch("checkout"),
        parsed.fetch("agent_trust"), verified_at: verified_at
      )
      validate_nonce_claims!(parsed.fetch("nonce_issuance"))

      # Even a structurally valid record can falsely CLAIM a unique nonce,
      # non-revoked keys or an authentic Host source. This slice cannot confirm
      # any of those assertions from an authoritative external Host registry.
      Candidate.new(
        snapshot: detached_freeze(parsed),
        raw_sha256: actual_sha256,
        verified_at: verified_at
      )
    rescue Halt
      raise
    rescue JSON::ParserError, KeyError, ArgumentError, TypeError, RangeError
      halt!("REJECT", "invalid_or_ambiguous_host_json")
    end

    private

    def halt!(status, code)
      raise Halt.new(status, code)
    end

    def epoch?(value)
      value.is_a?(Integer) && value.between?(1, MAX_TIME)
    end

    def string?(value, max: 256)
      value.is_a?(String) && value.ascii_only? &&
        value.bytesize.between?(1, max)
    end

    def exact!(obj, fields, code)
      halt!("REJECT", code) unless
        obj.is_a?(Hash) && obj.keys.sort == fields
    end

    def window!(first, last, at:)
      halt!("REJECT", "invalid_trust_window") unless
        epoch?(first) && epoch?(last) && first < last &&
        first <= at && at < last
    end

    def validate_trust!(entry, verified_at:)
      exact!(entry, TRUST_FIELDS, "invalid_trust_fields")
      %w[subject_ref policy_ref tenant_id].each do |name|
        halt!("REJECT", "invalid_trust_identity") unless string?(entry[name])
      end
      halt!("REJECT", "invalid_policy_version") unless
        entry["policy_version"].is_a?(Integer) &&
        entry["policy_version"].between?(1, 1_000_000)
      validate_key!(entry.fetch("key_jwk"))
      %w[key_revocation policy_revocation].each do |name|
        case entry.fetch(name)
        when "revoked"
          halt!("REJECT", "revoked_host_signer")
        when "non_revoked"
          # Claim of non-revocation is structurally consistent, NOT proved.
        else
          halt!("HOLD", "unknown_host_revocation_state")
        end
      end
      halt!("REJECT", "inactive_host_signer") unless
        entry["active"] == true && entry["policy_active"] == true
      window!(entry["key_not_before"], entry["key_not_after"], at: verified_at)
      window!(entry["policy_not_before"], entry["policy_not_after"], at: verified_at)
    end

    def validate_key!(jwk)
      exact!(jwk, JWK_FIELDS, "invalid_public_jwk")
      halt!("REJECT", "unsupported_public_jwk") unless
        jwk["kty"] == "EC" && jwk["crv"] == "P-256"
      coordinates = %w[x y].map do |key|
        part = jwk[key]
        halt!("REJECT", "invalid_public_jwk_coordinate") unless
          string?(part, max: 43) && part.bytesize == 43 &&
          part.match?(/\A[A-Za-z0-9_-]{43}\z/)
        bytes = Base64.urlsafe_decode64(part + "=")
        halt!("REJECT", "invalid_public_jwk_coordinate") unless
          bytes.bytesize == 32 &&
          Base64.urlsafe_encode64(bytes, padding: false) == part
        bytes.unpack1("H*").to_i(16)
      end
      x, y = coordinates
      # Check the canonical affine public point lies on secp256r1:
      # y^2 = x^3 - 3x + b (mod p), 0 <= x,y < p. P-256 has cofactor 1.
      # Affine coordinates cannot represent the point at infinity.
      halt!("REJECT", "invalid_public_jwk_point") unless
        x < P256_P && y < P256_P &&
        ((y * y - (x * x * x - 3 * x + P256_B)) % P256_P).zero?
    rescue ArgumentError
      halt!("REJECT", "invalid_public_jwk_coordinate")
    end

    def thumbprint(jwk)
      # RFC 7638 EC thumbprint: lexically ordered required public members.
      ordered = JWK_FIELDS.to_h { |key| [key, jwk.fetch(key)] }
      Base64.urlsafe_encode64(
        Digest::SHA256.digest(JSON.generate(ordered)), padding: false
      )
    end

    def ref!(ref)
      exact!(ref, CHECKOUT_REF_FIELDS, "invalid_checkout_reference")
      halt!("REJECT", "invalid_checkout_reference") unless
        string?(ref["tenant_id"]) && string?(ref["checkout_id"]) &&
        ref["checkout_version"].is_a?(Integer) &&
        ref["checkout_version"].between?(1, 1_000_000)
    end

    def validate_checkout!(checkout)
      exact!(checkout, CHECKOUT_FIELDS, "invalid_checkout_fields")
      ref!(checkout.fetch("ref"))
      %w[buyer_account_ref merchant_id currency expected_status sku_id sku_title].each do |key|
        halt!("REJECT", "invalid_checkout_field") unless string?(checkout[key])
      end
      halt!("REJECT", "unsupported_checkout_status") unless
        checkout["expected_status"] == "ready_for_complete"
      halt!("REJECT", "invalid_checkout_amount") unless
        checkout["amount_minor"].is_a?(Integer) &&
        checkout["amount_minor"].between?(1, 9_007_199_254_740_991)
      halt!("REJECT", "invalid_checkout_quantity") unless
        checkout["quantity"].is_a?(Integer) && checkout["quantity"].between?(1, 16)
      jwt = checkout["original_jwt"]
      halt!("REJECT", "invalid_host_checkout_wire") unless
        string?(jwt, max: MAX_CHECKOUT_BYTES) && jwt.count(".") == 2
      # Merchant JWT is NOT authenticated or parsed by this module; G0/G4.
    end

    def validate_challenge!(challenge, checkout, agent_trust, verified_at:)
      exact!(challenge, CHALLENGE_FIELDS, "invalid_challenge_fields")
      ref!(challenge.fetch("checkout_ref"))
      halt!("REJECT", "challenge_checkout_mismatch") unless
        challenge["checkout_ref"] == checkout["ref"]
      halt!("REJECT", "challenge_buyer_mismatch") unless
        challenge["buyer_account_ref"] == checkout["buyer_account_ref"]
      %w[ref aud buyer_account_ref].each do |name|
        halt!("REJECT", "invalid_challenge_reference") unless string?(challenge[name])
      end
      halt!("REJECT", "challenge_agent_mismatch") unless
        fixed_equal?(challenge["agent_thumbprint"], thumbprint(agent_trust.fetch("key_jwk")))
      halt!("REJECT", "invalid_challenge_ttl") unless
        epoch?(challenge["issued_at"]) && epoch?(challenge["expires_at"]) &&
        challenge["issued_at"] <= verified_at &&
        verified_at < challenge["expires_at"] &&
        challenge["issued_at"] < challenge["expires_at"]
      nonce = challenge["nonce"]
      halt!("REJECT", "invalid_challenge_nonce") unless
        string?(nonce, max: 512) && nonce.match?(/\A[A-Za-z0-9_-]+\z/)
      decoded = Base64.urlsafe_decode64(nonce + ("=" * (-nonce.bytesize % 4)))
      halt!("REJECT", "invalid_challenge_nonce") unless
        decoded.bytesize >= 16 &&
        Base64.urlsafe_encode64(decoded, padding: false) == nonce
      # Entropy and uniqueness cannot be inferred from nonce *length*.
    rescue ArgumentError
      halt!("REJECT", "invalid_challenge_nonce")
    end

    def validate_nonce_claims!(nonce_issuance)
      exact!(nonce_issuance, NONCE_FIELDS, "invalid_nonce_issuance_fields")
      halt!("HOLD", "nonce_issuance_unavailable") unless
        nonce_issuance["domain"] == "host-verifier-wide" &&
        nonce_issuance["unique"] == true &&
        nonce_issuance["atomic_uniqueness"] == true &&
        nonce_issuance["entropy_bits"].is_a?(Integer) &&
        nonce_issuance["entropy_bits"] >= 128 &&
        string?(nonce_issuance["registry_ref"]) &&
        string?(nonce_issuance["issuance_ref"])
      # These are Host CLAIMS only. This research slice has no authoritative
      # durable nonce registry; even a true claim yields Candidate/HOLD.
    end

    def fixed_equal?(a, b)
      return false unless a.is_a?(String) && b.is_a?(String) &&
        a.bytesize == b.bytesize
      mismatch = 0
      a.bytes.zip(b.bytes) { |x, y| mismatch |= x ^ y }
      mismatch.zero?
    end

    def detached_freeze(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, part), acc|
          acc[key.dup.freeze] = detached_freeze(part)
        end.freeze
      when Array
        value.map { |item| detached_freeze(item) }.freeze
      when String
        value.dup.freeze
      else
        value
      end
    end

    def check_bounds!(value, depth = 0)
      halt!("REJECT", "host_resource_limit") if depth > MAX_DEPTH
      case value
      when Hash
        halt!("REJECT", "host_resource_limit") if value.length > MAX_FIELDS
        value.each { |key, child| check_bounds!(key, depth + 1); check_bounds!(child, depth + 1) }
      when Array
        halt!("REJECT", "host_resource_limit") if value.length > MAX_ARRAY
        value.each { |child| check_bounds!(child, depth + 1) }
      when String
        halt!("REJECT", "host_resource_limit") if value.bytesize > MAX_CONTEXT_BYTES
      end
    end
  end
end
