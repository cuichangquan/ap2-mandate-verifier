# frozen_string_literal: true
# IMPORTANT: Forked, frozen-layout research-only extraction to avoid importing
# the original P1-1 dependency which requires minitest/autorun at load time.
# Original implementation under research/phase2a_e01s/synthetic_host_policy.rb.
# Deliberately NOT validated by executing Ruby, fixtures, or CI at approval A.
# E06-I/A isolated snapshot of the E01-S synthetic Host policy. NOT production enrollment / authority system.
# Policy is a separately frozen Host-side test input, never derived from Root.
require "json"
require "digest"
require "base64"
require_relative "../shared/strict_json_research"

module AP2E06IHostPolicy
  class Rejected < StandardError
    attr_reader :stage, :code

    def initialize(stage, code)
      @stage, @code = stage, code
      super("#{stage}: #{code}")
    end
  end

  PINNED_PATHS = [
    "$/delegate_payload/0",
    "$/delegate_payload/0/disclosed/constraints/1/allowed/0",
    "$/delegate_payload/0/disclosed/constraints/0/items/0/acceptable_items/0"
  ].sort.freeze
  FIELDS = %w[
    active alg allowed_sd_paths checkout_use_case expected_agent_public_jwk
    expected_aud expected_checkout_id expected_currency expected_merchant_id
    expected_nonce expected_total_minor freeze_epoch host_checkout_jwt
    issuer_public_jwk issuer_ref issuer_thumbprint not_after not_before
    policy_digest policy_version profile_ref tenant_scope
    trusted_merchant_public_jwk
  ].sort.freeze

  class << self
    def reject!(stage, code)
      raise Rejected.new(stage, code)
    end

    def sort_values(value)
      case value
      when Hash
        value.keys.sort.to_h { |key| [key, sort_values(value.fetch(key))] }
      when Array
        value.map { |child| sort_values(child) }
      else
        value
      end
    end

    def canonical(value)
      JSON.generate(sort_values(value))
    end

    def digest(value)
      Digest::SHA256.hexdigest(canonical(value))
    end

    def thumbprint(jwk)
      reject!("S1_HOST_KEY_POLICY", "UNSUPPORTED_PUBLIC_JWK") unless
        jwk.is_a?(Hash) && jwk.keys.sort == %w[crv kty x y] &&
        jwk["kty"] == "EC" && jwk["crv"] == "P-256" &&
        %w[x y].all? { |key| jwk[key].is_a?(String) && !jwk[key].empty? }
      members = %w[crv kty x y].to_h { |key| [key, jwk.fetch(key)] }
      Base64.urlsafe_encode64(Digest::SHA256.digest(canonical(members)), padding: false)
    end

    def load!(raw)
      stage = "S1_HOST_KEY_POLICY"
      reject!(stage, "OVERSIZED_POLICY") unless raw.is_a?(String) &&
        raw.bytesize.between?(1, 16_384) && raw.ascii_only?
      policy = AP2StrictJSONResearch.parse!(raw)
      reject!(stage, "INVALID_POLICY_FIELDS") unless
        policy.is_a?(Hash) && policy.keys.sort == FIELDS
      reject!(stage, "NONCANONICAL_POLICY") unless
        raw.strip == canonical(policy)
      expected = digest(policy.reject { |key, _| key == "policy_digest" })
      reject!(stage, "UNFROZEN_POLICY_DIGEST") unless
        policy.fetch("policy_digest") == expected
      reject!(stage, "AMBIGUOUS_POLICY") unless
        policy["tenant_scope"] == "synthetic-e01s" &&
        policy["checkout_use_case"] == "checkout-research" &&
        policy["issuer_ref"] == "synthetic-e01s-issuer-A" &&
        policy["profile_ref"] == "e01s-fixed-a-v1" &&
        policy["policy_version"] == 1 && policy["active"] == true &&
        policy["alg"] == "ES256" &&
        policy["allowed_sd_paths"] == PINNED_PATHS
      issuer = policy.fetch("issuer_public_jwk")
      reject!(stage, "HOST_KEY_THUMBPRINT_MISMATCH") unless
        thumbprint(issuer) == policy.fetch("issuer_thumbprint")
      %w[expected_agent_public_jwk trusted_merchant_public_jwk].each do |name|
        thumbprint(policy.fetch(name))
      end
      t0 = policy.fetch("freeze_epoch")
      reject!(stage, "INVALID_POLICY_VALIDITY") unless
        t0.is_a?(Integer) && policy["not_before"] == t0 - 60 &&
        policy["not_after"] == t0 + 1200
      reject!(stage, "INVALID_HOST_CONTEXT") unless
        %w[expected_aud expected_nonce expected_checkout_id
           expected_merchant_id expected_currency].all? do |key|
          policy[key].is_a?(String) && !policy[key].empty?
        end &&
        policy["expected_total_minor"].is_a?(Integer) &&
        policy["expected_total_minor"].positive? &&
        policy["host_checkout_jwt"].is_a?(String) &&
        policy["host_checkout_jwt"].bytesize.between?(1, 16_384)
      policy.freeze
    rescue JSON::ParserError, KeyError, ArgumentError, TypeError => e
      reject!("S1_HOST_KEY_POLICY", "INVALID_HOST_POLICY_#{e.class.name.split('::').last}")
    end

    def verify_candidate!(policy, candidate, case_policy_digest:)
      stage = "S1_HOST_KEY_POLICY"
      reject!(stage, "POLICY_SNAPSHOT_MISMATCH") unless
        policy["policy_digest"] == case_policy_digest
      now = Time.now.to_i # A second clock, NOT the older DC04's clock injection.
      reject!(stage, "EXPIRED_OR_INACTIVE_POLICY") unless
        policy["active"] && policy["not_before"] <= now &&
        now < policy["not_after"]
      actual = thumbprint(candidate)
      reject!(stage, "UNTRUSTED_ISSUER") unless
        actual == policy.fetch("issuer_thumbprint")
      # Only the *frozen Host policy's* JWK may be passed to DC04.
      policy.fetch("issuer_public_jwk")
    end

    # A3 synthetic-only clock-consistent variant. Do not use as evidence of
    # independently enrolled Host keys, challenge issuance, or trusted time.
    # Preserve verify_candidate! for historical callers without altering it.
    def verify_candidate_at!(policy, candidate, case_policy_digest:, verified_at:)
      stage = "S1_HOST_KEY_POLICY"
      reject!(stage, "POLICY_SNAPSHOT_MISMATCH") unless
        policy.is_a?(Hash) && policy["policy_digest"] == case_policy_digest
      reject!(stage, "VERIFICATION_CLOCK_UNAVAILABLE") unless
        verified_at.is_a?(Integer) && verified_at.between?(1, 4_102_444_800)
      reject!(stage, "EXPIRED_OR_INACTIVE_POLICY") unless
        policy["active"] &&
        policy["not_before"].is_a?(Integer) &&
        policy["not_after"].is_a?(Integer) &&
        policy["not_before"] <= verified_at && verified_at < policy["not_after"]
      actual = thumbprint(candidate)
      reject!(stage, "UNTRUSTED_ISSUER") unless
        actual == policy.fetch("issuer_thumbprint")
      policy.fetch("issuer_public_jwk")
    end

    def checkout_context(policy)
      {
        issuer_jwk: policy.fetch("issuer_public_jwk"),
        expected_agent_jwk: policy.fetch("expected_agent_public_jwk"),
        expected_aud: policy.fetch("expected_aud"),
        expected_nonce: policy.fetch("expected_nonce"),
        merchant_jwk: policy.fetch("trusted_merchant_public_jwk"),
        host_checkout_jwt: policy.fetch("host_checkout_jwt"),
        expected_checkout_id: policy.fetch("expected_checkout_id"),
        expected_merchant_id: policy.fetch("expected_merchant_id"),
        expected_currency: policy.fetch("expected_currency"),
        expected_total_minor: policy.fetch("expected_total_minor")
      }
    end
  end
end
