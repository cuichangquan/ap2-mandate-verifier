# frozen_string_literal: true
#
# E06-I A3-H1 research-only proposed Host enrollment source interface.
# SOURCE ONLY / NOT RUN / NO TEST OR CI AUTHORIZATION / NO G1 SUCCESS.
#
# A separately supplied "enrollment" JSON and its digest are BOTH untrusted
# assertions in this slice. Matching a fixed synthetic profile or an A2 Host
# candidate is not an authentic independent Host registry. In particular,
# JWS kid/iss/jwk, source_ref and digest strings are NOT a trust anchor.
#
# The owner has NOT approved creation of actual Host enrollment/registry
# fixtures or any test execution. No signing/private keys, network or CAS.
require "json"
require "digest"
require_relative "../shared/strict_json_research"
require_relative "isolated_host_snapshot"

module AP2E06IHostSource
  MAX_SOURCE_BYTES = 16_384
  MAX_DEPTH = 24
  SOURCE_KEYS = %w[
    profile_ref record_version source_ref tenant_id trust
  ].sort.freeze
  TRUST_NAMES = %w[agent_trust issuer_trust merchant_trust].sort.freeze
  PINNED_PROFILE = "e06i-fixed-issuer-a-v1"
  PINNED_TENANT = "synthetic-e01s"
  PINNED_SOURCE_REF = "e06i-synthetic-enrollment-v1"
  PINNED_ISSUER = "synthetic-e01s-issuer-A"
  PINNED_ISSUER_POLICY = "e06i-issuer-a-host-policy-v1"

  class Halt < StandardError
    attr_reader :status, :code

    def initialize(status, code)
      @status, @code = status, code
      super(code)
    end
  end

  # A non-authoritative diagnostic, never an authorized Host enrollment or a
  # G1 stage result; even self-consistent inputs cannot clear a trust gate.
  class SourceClaim
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
      "independent_host_enrollment_provenance_unavailable"
    end

    def authoritative?
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
    # candidate: the already inspected A2 Host snapshot *claim*, not a trusted
    # G1 success. source_json: proposed independent Host enrollment record,
    # whose out-of-band source authentication is NOT implemented here.
    #
    # verified_at and expected_source_sha256 are caller-supplied; a matching
    # checksum is merely an integrity comparison, never authentic provenance.
    def inspect_claims!(candidate:, source_json:, expected_source_sha256:,
                        verified_at:)
      halt!("HOLD", "host_enrollment_source_missing") if
        source_json.nil? || expected_source_sha256.nil?
      halt!("HOLD", "host_snapshot_candidate_missing") unless
        candidate.is_a?(AP2E06IHostSnapshot::Candidate) &&
        candidate.status == "HOLD" && !candidate.admissible?
      halt!("REJECT", "invalid_host_enrollment_source_type") unless
        source_json.is_a?(String) && expected_source_sha256.is_a?(String)

      # Detach BOTH caller-owned strings before bounds, digest or parsing.
      wire = source_json.dup.freeze
      expected_digest = expected_source_sha256.dup.freeze
      halt!("REJECT", "host_enrollment_source_resource_limit") unless
        wire.ascii_only? && wire.bytesize.between?(1, MAX_SOURCE_BYTES)
      halt!("REJECT", "invalid_host_enrollment_source_digest") unless
        expected_digest.match?(/\A[0-9a-f]{64}\z/)
      halt!("HOLD", "host_enrollment_source_digest_mismatch") unless
        equal_hex?(Digest::SHA256.hexdigest(wire.b), expected_digest)
      halt!("HOLD", "verification_clock_unavailable") unless
        verified_at.is_a?(Integer) &&
        verified_at.between?(1, AP2E06IHostSnapshot::MAX_TIME) &&
        verified_at == candidate.verified_at

      source = AP2StrictJSONResearch.parse!(wire)
      bounded_tree!(source)
      exact!(source, SOURCE_KEYS, "invalid_enrollment_source_fields")
      halt!("REJECT", "unsupported_enrollment_source_profile") unless
        source["profile_ref"] == PINNED_PROFILE &&
        source["tenant_id"] == PINNED_TENANT &&
        source["source_ref"] == PINNED_SOURCE_REF &&
        source["record_version"] == 1

      proposed = candidate.snapshot
      halt!("REJECT", "invalid_host_snapshot_claim") unless
        proposed.is_a?(Hash) &&
        proposed["profile_ref"] == PINNED_PROFILE &&
        proposed.dig("checkout", "ref", "tenant_id") == PINNED_TENANT

      anchors = source.fetch("trust")
      exact!(anchors, TRUST_NAMES, "invalid_source_trust_selectors")
      TRUST_NAMES.each do |signer|
        entry = anchors.fetch(signer)
        exact!(entry, AP2E06IHostSnapshot::TRUST_FIELDS,
               "invalid_enrollment_trust_fields")
        # Complete source-vs-candidate field equality, not selective key id,
        # token kid, issuer text, or signer-supplied thumbprint matching.
        halt!("REJECT", "host_enrollment_trust_mismatch") unless
          entry == proposed.fetch(signer) &&
          entry["tenant_id"] == PINNED_TENANT
        %w[key_revocation policy_revocation].each do |k|
          halt!("REJECT", "host_enrollment_revoked") if entry[k] == "revoked"
          halt!("HOLD", "host_enrollment_revocation_unknown") unless
            entry[k] == "non_revoked"
        end
        halt!("REJECT", "host_enrollment_signer_inactive") unless
          entry["active"] == true && entry["policy_active"] == true
        %w[key_not_before policy_not_before].each do |k|
          halt!("REJECT", "host_enrollment_window_invalid") unless
            entry[k].is_a?(Integer) && entry[k] <= verified_at
        end
        %w[key_not_after policy_not_after].each do |k|
          halt!("REJECT", "host_enrollment_window_invalid") unless
            entry[k].is_a?(Integer) && verified_at < entry[k]
        end
      end

      issuer = anchors.fetch("issuer_trust")
      halt!("REJECT", "fixed_issuer_enrollment_mismatch") unless
        issuer["subject_ref"] == PINNED_ISSUER &&
        issuer["policy_ref"] == PINNED_ISSUER_POLICY &&
        issuer["policy_version"] == 1
      halt!("REJECT", "merchant_enrollment_checkout_mismatch") unless
        anchors.fetch("merchant_trust")["subject_ref"] ==
        proposed.fetch("checkout").fetch("merchant_id")

      # Every assertion above may still be attacker-written in BOTH records.
      # Until a pinned actual independent Host root + key lifecycle evidence
      # exists, the only possible successful shape result is HOLD.
      SourceClaim.new(
        source_wire_sha256: Digest::SHA256.hexdigest(wire.b),
        candidate_wire_sha256: candidate.raw_sha256,
        verified_at: verified_at
      )
    rescue Halt
      raise
    rescue JSON::ParserError, KeyError, TypeError, ArgumentError, NoMethodError
      halt!("REJECT", "invalid_host_enrollment_source")
    end

    private

    def halt!(status, code)
      raise Halt.new(status, code)
    end

    def exact!(value, allowed, code)
      halt!("REJECT", code) unless
        value.is_a?(Hash) &&
        value.keys.all? { |key| key.is_a?(String) } &&
        value.keys.sort == allowed
    end

    def bounded_tree!(value, depth = 0)
      halt!("REJECT", "host_enrollment_source_resource_limit") if
        depth > MAX_DEPTH
      case value
      when Hash
        halt!("REJECT", "host_enrollment_source_resource_limit") if
          value.length > 32
        value.each do |key, part|
          bounded_tree!(key, depth + 1)
          bounded_tree!(part, depth + 1)
        end
      when Array
        halt!("REJECT", "host_enrollment_source_resource_limit") if
          value.length > 16
        value.each { |part| bounded_tree!(part, depth + 1) }
      when String
        halt!("REJECT", "host_enrollment_source_resource_limit") if
          value.bytesize > MAX_SOURCE_BYTES
      end
    end

    def equal_hex?(a, b)
      return false unless a.is_a?(String) && b.is_a?(String) &&
        a.bytesize == b.bytesize
      difference = 0
      a.bytes.zip(b.bytes) { |x, y| difference |= x ^ y }
      difference.zero?
    end
  end
end
