# frozen_string_literal: true
#
# E06-I A3-H1: claimed Host-wide nonce issuance source, NO genuine ledger.
# SOURCE-ONLY RESEARCH / NOT RUN / NO FIXTURES / NO CI / NEVER G1 PASS.
#
# A one-event JSON record, a checksum, 'CSPRNG' text and uniqueness flags
# cannot prove entropy, Host-wide durable atomic uniqueness, global replay
# history or Host one-time consumption. No nonce is generated, reserved,
# consumed, or checked against a real external durable registry here.
require "json"
require "digest"
require_relative "../shared/strict_json_research"
require_relative "isolated_host_snapshot"

module AP2E06INonceIssuanceSource
  MAX_SOURCE_BYTES = 8_192
  MAX_DEPTH = 24
  ROOT_KEYS = %w[event ledger_claim record_version source_ref].sort.freeze
  LEDGER_KEYS = %w[
    all_history atomic_uniqueness domain durable entropy_bits
    origin registry_ref
  ].sort.freeze
  EVENT_KEYS = %w[
    agent_thumbprint aud buyer_account_ref challenge_ref checkout_ref
    expires_at issued_at issuance_ref nonce_sha256
  ].sort.freeze
  CHECKOUT_REF_KEYS = %w[checkout_id checkout_version tenant_id].sort.freeze
  PINNED_SOURCE = "e06i-synthetic-nonce-ledger-v1"
  DOMAIN = "host-verifier-wide"
  MAX_TIME = AP2E06IHostSnapshot::MAX_TIME

  class Halt < StandardError
    attr_reader :status, :code

    def initialize(status, code)
      @status, @code = status, code
      super(code)
    end
  end

  # Diagnostic of internally consistent untrusted *claims*. Not a trusted
  # Host nonce allocation record, not a bearer G1/G7 authorization.
  class LedgerClaim
    attr_reader :source_wire_sha256, :candidate_wire_sha256, :verified_at

    def initialize(source_wire_sha256:, candidate_wire_sha256:, verified_at:)
      @source_wire_sha256 = source_wire_sha256.freeze
      @candidate_wire_sha256 = candidate_wire_sha256.freeze
      @verified_at = verified_at
      freeze
    end

    def status
      "HOLD"
    end

    def reason
      "host_wide_durable_nonce_registry_proof_unavailable"
    end

    def authoritative?
      false
    end

    def replay_safe?
      false
    end

    def admissible?
      false
    end

    def evidence
      nil
    end
  end

  class << self
    # A separate JSON purportedly describing a Host nonce issuance event
    # is compared against the A2 G1 Host snapshot candidate. Both are
    # caller-provided material and do not attest a Host source/ledger.
    def inspect_claims!(candidate:, ledger_json:, expected_ledger_sha256:,
                        verified_at:)
      halt!("HOLD", "nonce_ledger_source_missing") if
        ledger_json.nil? || expected_ledger_sha256.nil?
      halt!("HOLD", "host_snapshot_candidate_missing") unless
        candidate.is_a?(AP2E06IHostSnapshot::Candidate) &&
        candidate.status == "HOLD" && !candidate.admissible?
      halt!("REJECT", "invalid_nonce_ledger_source_type") unless
        ledger_json.is_a?(String) && expected_ledger_sha256.is_a?(String)

      # Only validate/hash/parse detached frozen buffers, never caller-owned
      # mutable strings that may change in another thread.
      wire = ledger_json.dup.freeze
      expected_digest = expected_ledger_sha256.dup.freeze
      halt!("REJECT", "nonce_ledger_resource_limit") unless
        wire.ascii_only? && wire.bytesize.between?(1, MAX_SOURCE_BYTES)
      halt!("REJECT", "invalid_nonce_ledger_digest") unless
        expected_digest.match?(/\A[0-9a-f]{64}\z/)
      halt!("HOLD", "nonce_ledger_digest_mismatch") unless
        constant_hex_equal?(Digest::SHA256.hexdigest(wire.b), expected_digest)
      # Defer the untrusted/unknown verification clock until AFTER every
      # clock-independent profile/binding/type check. An unknown clock must
      # not mask a known-mismatched challenge, digest, Checkout or scope.
      clock_available =
        verified_at.is_a?(Integer) && verified_at.between?(1, MAX_TIME) &&
        verified_at == candidate.verified_at

      record = AP2StrictJSONResearch.parse!(wire)
      check_bounds!(record)
      exact!(record, ROOT_KEYS, "unsupported_nonce_source")
      halt!("REJECT", "unsupported_nonce_source_profile") unless
        record["source_ref"] == PINNED_SOURCE &&
        record["record_version"] == 1

      snap = candidate.snapshot
      halt!("REJECT", "invalid_host_snapshot_claim") unless snap.is_a?(Hash)
      challenge = snap.fetch("challenge")
      checkout = snap.fetch("checkout")
      original = snap.fetch("nonce_issuance")
      halt!("REJECT", "invalid_claimed_host_context") unless
        challenge.is_a?(Hash) && checkout.is_a?(Hash) &&
        original.is_a?(Hash)

      event = record.fetch("event")
      exact!(event, EVENT_KEYS, "unsupported_nonce_event")
      exact!(event["checkout_ref"], CHECKOUT_REF_KEYS, "invalid_nonce_checkout_ref")
      checkout_ref = checkout.fetch("ref")
      halt!("REJECT", "nonce_checkout_context_mismatch") unless
        checkout_ref.is_a?(Hash) &&
        checkout_ref["tenant_id"] == "synthetic-e01s" &&
        event["checkout_ref"] == checkout_ref &&
        challenge.fetch("checkout_ref") == checkout_ref &&
        event["buyer_account_ref"] == checkout["buyer_account_ref"] &&
        event["buyer_account_ref"] == challenge["buyer_account_ref"]

      # A Terminal signs aud/nonce, NOT checkout/session/tenant/challenge_ref.
      # Therefore nonce uniqueness can never be scoped only to session/tenant.
      # Compare the alleged issuance against the exact frozen challenge and
      # A2 issuance claim; it still remains an UNATTESTED comparison.
      halt!("REJECT", "nonce_event_challenge_mismatch") unless
        equal_string?(event["challenge_ref"], challenge["ref"]) &&
        equal_string?(event["issuance_ref"], original["issuance_ref"]) &&
        equal_string?(event["aud"], challenge["aud"]) &&
        equal_string?(event["agent_thumbprint"], challenge["agent_thumbprint"]) &&
        equal_string?(event["nonce_sha256"], original["nonce_sha256"]) &&
        constant_hex_equal?(event["nonce_sha256"],
                            Digest::SHA256.hexdigest(challenge.fetch("nonce").b)) &&
        event["issued_at"] == challenge["issued_at"] &&
        event["expires_at"] == challenge["expires_at"]
      halt!("REJECT", "invalid_nonce_event_interval") unless
        epoch?(event["issued_at"]) && epoch?(event["expires_at"]) &&
        event["issued_at"] < event["expires_at"]

      ledger = record.fetch("ledger_claim")
      exact!(ledger, LEDGER_KEYS, "unsupported_nonce_ledger_claim")
      # Malformed PRESENT claims are definitive invalid input, not missing
      # evidence. Missing genuine registry authority remains a HOLD.
      halt!("REJECT", "malformed_nonce_ledger_assertions") unless
        ledger["origin"].is_a?(String) &&
        ledger["entropy_bits"].is_a?(Integer) &&
        ledger["entropy_bits"].between?(0, 65_536) &&
        ledger["registry_ref"].is_a?(String) &&
        ledger["registry_ref"].ascii_only? &&
        ledger["registry_ref"].bytesize.between?(1, 256) &&
        %w[durable atomic_uniqueness all_history].all? { |name|
          ledger[name] == true || ledger[name] == false
        }
      # A known narrower domain is REJECT, even if "unique" is true.
      halt!("REJECT", "unsafe_nonce_uniqueness_domain") unless
        ledger["domain"] == DOMAIN &&
        original["domain"] == DOMAIN
      halt!("REJECT", "nonce_registry_identity_mismatch") unless
        equal_string?(ledger["registry_ref"], original["registry_ref"])
      # Definitive event temporal invalidity is checked only when the input
      # clock is well-formed; earlier independent mismatches take precedence.
      halt!("HOLD", "nonce_ledger_clock_unavailable") unless clock_available
      halt!("REJECT", "nonce_event_expired_or_future") unless
        event["issued_at"] <= verified_at && verified_at < event["expires_at"]

      # A syntactically valid but insufficient registry claim is not proof.
      # A durable global registry is not implemented in this research slice.
      halt!("HOLD", "nonce_source_entropy_or_atomicity_unverified") unless
        ledger["origin"] == "csprng" &&
        ledger["entropy_bits"].is_a?(Integer) &&
        ledger["entropy_bits"] >= 128 &&
        ledger["entropy_bits"] == original["entropy_bits"] &&
        ledger["durable"] == true && ledger["atomic_uniqueness"] == true &&
        ledger["all_history"] == true &&
        original["unique"] == true && original["atomic_uniqueness"] == true

      # The "history" and random origin above remain only claimed fields.
      # A single matching source event cannot check never-reused issuance or
      # challenge consumption across all sessions, tenants and history.
      LedgerClaim.new(
        source_wire_sha256: Digest::SHA256.hexdigest(wire.b),
        candidate_wire_sha256: candidate.raw_sha256,
        verified_at: verified_at
      )
    rescue Halt
      raise
    rescue JSON::ParserError, TypeError, ArgumentError, KeyError, NoMethodError
      halt!("REJECT", "invalid_nonce_issuance_source")
    end

    private

    def halt!(status, code)
      raise Halt.new(status, code)
    end

    def exact!(obj, allowed, code)
      halt!("REJECT", code) unless
        obj.is_a?(Hash) && obj.keys.all? { |k| k.is_a?(String) } &&
        obj.keys.sort == allowed
    end

    def epoch?(value)
      value.is_a?(Integer) && value.between?(1, MAX_TIME)
    end

    def equal_string?(a, b)
      a.is_a?(String) && b.is_a?(String) && !a.empty? && a == b
    end

    def constant_hex_equal?(a, b)
      return false unless a.is_a?(String) && b.is_a?(String) &&
        a.bytesize == 64 && b.bytesize == 64 &&
        a.match?(/\A[0-9a-f]{64}\z/) && b.match?(/\A[0-9a-f]{64}\z/)
      acc = 0
      a.bytes.zip(b.bytes) { |x, y| acc |= x ^ y }
      acc.zero?
    end

    def check_bounds!(value, depth = 0)
      halt!("REJECT", "nonce_ledger_resource_limit") if depth > MAX_DEPTH
      case value
      when Hash
        halt!("REJECT", "nonce_ledger_resource_limit") if value.size > 32
        value.each do |key, v|
          check_bounds!(key, depth + 1)
          check_bounds!(v, depth + 1)
        end
      when Array
        halt!("REJECT", "nonce_ledger_resource_limit") if value.size > 16
        value.each { |v| check_bounds!(v, depth + 1) }
      when String
        halt!("REJECT", "nonce_ledger_resource_limit") if
          value.bytesize > MAX_SOURCE_BYTES
      end
    end
  end
end
