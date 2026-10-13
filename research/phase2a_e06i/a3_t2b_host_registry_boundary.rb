# frozen_string_literal: true
#
# E06-I / A3-T2b (Issue #95): proposed Host registry READ BOUNDARY only.
# OWNER APPROVAL A: SOURCE + STATIC REVIEW ONLY; NOT RUN / NO DB / NO CI.
#
# The Host operator's independently approved signer enrollments, management
# ACLs, revocation history and authenticated read channel DO NOT EXIST in this
# research module. This adapter observes caller-supplied A3-H1 *claims* only.
# It cannot turn a matching JSON/SHA or valid JWT signature into trusted G1.
#
# This is an isolated diagnostic; DO NOT plug it into G1/G7 or production.
# A future integrated verifier must first pass original-wire G0 strict bounds,
# then obtain a genuinely authenticated, coherent Host revision at G1.

require_relative "isolated_host_snapshot"
require_relative "isolated_host_source"

module AP2E06IA3T2bHostRegistryBoundary
  MAX_CHECKOUT_BYTES = AP2E06IHostSnapshot::MAX_CHECKOUT_BYTES

  # Missing independent evidence cannot be filled by extra caller fields or
  # flags named "authoritative", "trusted", "unique", "signed", etc.
  UNPROVEN_REQUIREMENTS = %w[
    out_of_band_host_operator_and_enrollment_approval
    reader_identity_acl_and_authenticated_host_channel
    independent_issuer_agent_merchant_key_thumbprints_and_policies
    key_policy_revocation_rotation_and_bounded_freshness
    coherent_host_revision_and_trusted_verified_at
    immutable_checkout_challenge_buyer_agent_and_original_jwt_provenance
  ].map(&:freeze).freeze

  class ClaimObservation
    attr_reader :status, :reason

    def initialize(status:, reason:)
      # A3-T2b deliberately has NO positive status/result capability.
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
    # The A2 candidate, the source JSON/digest and the clock are *all*
    # caller-controlled diagnostic material, NOT an authenticated Host source.
    # checkout_wire is the *exact original* Merchant-signed JWT byte string:
    # comparing it to a Host *claim* does not establish Merchant signature or
    # actual Host provenance. Do not parse/re-serialize it for this comparison.
    #
    # The result is always non-authoritative and lacks a stage capability.
    # REJECT describes a locally contradictory/malformed CLAIM only.
    def inspect_claim_only(candidate:, source_json:, expected_source_sha256:,
                           verified_at:, checkout_wire:)
      unless candidate.is_a?(AP2E06IHostSnapshot::Candidate) &&
          candidate.status == "HOLD" && !candidate.admissible?
        return hold("untrusted_host_candidate_unavailable")
      end

      unless verified_at.is_a?(Integer) &&
          verified_at.between?(1, AP2E06IHostSnapshot::MAX_TIME) &&
          candidate.verified_at == verified_at
        return hold("host_clock_provenance_unavailable")
      end

      return hold("original_checkout_wire_unavailable") if checkout_wire.nil?
      return reject("claim_only_invalid_checkout_wire_type") unless
        checkout_wire.is_a?(String)

      # Detach first, then validate and compare one immutable copy. No I/O.
      original = checkout_wire.dup.freeze
      return reject("claim_only_checkout_wire_resource_limit") unless
        original.ascii_only? &&
        original.bytesize.between?(1, MAX_CHECKOUT_BYTES)

      claimed_checkout = candidate.snapshot.fetch("checkout").fetch("original_jwt")
      return reject("claim_only_original_checkout_wire_mismatch") unless
        claimed_checkout.is_a?(String) && claimed_checkout == original

      result = AP2E06IHostSource.inspect_claims!(
        candidate: candidate,
        source_json: source_json,
        expected_source_sha256: expected_source_sha256,
        verified_at: verified_at
      )
      # This must be an A3-H1 HOLD-only claim, never a claimed G1 capability.
      return hold("unexpected_host_claim_capability") unless
        result.is_a?(AP2E06IHostSource::SourceClaim) &&
        result.status == "HOLD" && !result.authoritative? &&
        !result.admissible? && result.evidence.nil?

      hold("independent_host_registry_and_reader_proof_unavailable")
    rescue AP2E06IHostSource::Halt => error
      # Local REJECT is not an authenticated Host registration decision.
      ClaimObservation.new(
        status: error.status, reason: "claim_only_#{error.code}"
      )
    rescue StandardError
      # No exception or unavailable dependency may become a positive result.
      hold("host_registry_boundary_verification_unavailable")
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
