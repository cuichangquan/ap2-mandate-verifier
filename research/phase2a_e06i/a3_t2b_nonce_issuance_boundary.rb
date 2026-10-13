# frozen_string_literal: true
#
# E06-I / A3-T2b (Issue #95): proposed Host-wide nonce issuance READ BOUNDARY.
# OWNER APPROVAL A: SOURCE + STATIC REVIEW ONLY; NOT RUN / NO DB / NO CI.
#
# There is no PostgreSQL schema, nonce allocator, CSPRNG audit, issuance
# transaction, historical uniqueness proof, authenticated ledger reader,
# consumption CAS, payment, or G1/G7 success path in this module.
#
# Terminal protects aud/nonce, NOT tenant/session/challenge_ref. A caller
# claiming UNIQUE(tenant_id, nonce_sha256), a digest, or 128 entropy bits
# cannot prove Host-verifier-wide issuance uniqueness.

require_relative "isolated_host_snapshot"
require_relative "isolated_nonce_issuance_source"

module AP2E06IA3T2bNonceIssuanceBoundary
  MAX_CHECKOUT_BYTES = AP2E06IHostSnapshot::MAX_CHECKOUT_BYTES

  # These must eventually be *independently* demonstrated by a Host-owned
  # trusted issuer/ledger path. They are NOT implemented by the A3-H1 claim.
  UNPROVEN_REQUIREMENTS = %w[
    authenticated_host_issuance_reader_and_snapshot_revision
    host_csprng_at_least_128_bits_generation_path
    atomic_durable_host_verifier_wide_unique_nonce_sha256
    complete_never_deleted_cross_tenant_session_history
    issuer_commit_ack_crash_restore_and_rollback_protection
    issuance_challenge_aud_agent_buyer_checkout_version_binding
    original_merchant_signed_checkout_jwt_bytes_digest_in_commit
    trusted_verified_at_and_expiration_policy
  ].map(&:freeze).freeze

  class ClaimObservation
    attr_reader :status, :reason

    def initialize(status:, reason:)
      @status = (status == "REJECT" ? "REJECT" : "HOLD").freeze
      @reason = reason.dup.freeze
      freeze
    end

    def unproven_requirements
      UNPROVEN_REQUIREMENTS
    end

    def authoritative?
      false
    end

    def g1_admissible?
      false
    end

    def g3_authenticated?
      false
    end

    def replay_safe?
      false
    end

    def evidence
      nil
    end

    def valid_until
      nil
    end

    def completed_stages
      [].freeze
    end

    def first_reject_stage
      nil
    end
  end

  class << self
    # Inspects one bounded caller-supplied A3-H1 ledger JSON claim against
    # the same frozen A2 Host candidate. This is NOT a ledger read or replay
    # reservation. The candidate/raw Merchant JWT and expected digest are
    # not authenticated; a matching local string proves no Host provenance.
    #
    # The old A3-H1 event schema does NOT bind the original Checkout JWT
    # SHA into a proven atomic issuance commit. That obligation remains
    # explicitly unproven, even when the local exact-wire comparison matches.
    # No SQL, CSPRNG, network access, nonce generation or mutation.
    def inspect_claim_only(candidate:, ledger_json:, expected_ledger_sha256:,
                           verified_at:, checkout_wire:)
      unless candidate.is_a?(AP2E06IHostSnapshot::Candidate) &&
          candidate.status == "HOLD" && !candidate.admissible?
        return hold("untrusted_host_candidate_unavailable")
      end

      # Missing original Checkout bytes imply HOLD but must not mask a
      # definite, independent contradiction in the nonce issuance claim.
      # Compare bounded immutable original bytes when present, then inspect
      # the alleged ledger event before returning any deferred wire HOLD.
      checkout_missing = checkout_wire.nil?
      unless checkout_missing
        return reject("claim_only_invalid_checkout_wire_type") unless
          checkout_wire.is_a?(String)

        original = checkout_wire.dup.freeze
        return reject("claim_only_checkout_wire_resource_limit") unless
          original.ascii_only? &&
          original.bytesize.between?(1, MAX_CHECKOUT_BYTES)

        claimed_checkout = candidate.snapshot.fetch("checkout").fetch("original_jwt")
        return reject("claim_only_original_checkout_wire_mismatch") unless
          claimed_checkout.is_a?(String) && claimed_checkout == original
      end

      # Let the A3-H1 nonce inspector find clock-independent contradictions
      # first; a malformed or absent clock must never be elevated to a
      # trusted timestamp. Any inconclusive/unknown result remains HOLD.
      result = AP2E06INonceIssuanceSource.inspect_claims!(
        candidate: candidate,
        ledger_json: ledger_json,
        expected_ledger_sha256: expected_ledger_sha256,
        verified_at: verified_at
      )
      return hold("unexpected_nonce_claim_capability") unless
        result.is_a?(AP2E06INonceIssuanceSource::LedgerClaim) &&
        result.status == "HOLD" && !result.authoritative? &&
        !result.admissible? && !result.replay_safe? &&
        result.evidence.nil?

      return hold("original_checkout_wire_unavailable") if checkout_missing

      hold("host_wide_issuance_and_commit_proof_unavailable")
    rescue AP2E06INonceIssuanceSource::Halt => error
      # Local REJECT means only a contradiction in supplied claims.
      ClaimObservation.new(
        status: error.status, reason: "claim_only_#{error.code}"
      )
    rescue StandardError
      hold("nonce_registry_boundary_verification_unavailable")
    end

    private

    def hold(reason)
      ClaimObservation.new(status: "HOLD", reason: reason)
    end

    def reject(reason)
      ClaimObservation.new(status: "REJECT", reason: reason)
    end
  end
end
