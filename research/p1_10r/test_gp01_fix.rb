# frozen_string_literal: true
# P1-10r ONLY: one formerly ACCEPTED GP01 plus one known-good fixture.
# This is a fixed-Issuer synthetic research profile, not AP2 compatibility,
# Host business ALLOW, anti-replay, or a public Gem/API.
require_relative "../p1_3/checkout_binding_research"
require "json"
require "minitest/autorun"

module P110R
  SHA = "b4587ac1d055888a73b4b21750973cffba961793"
  NEG = JSON.parse(File.binread(ENV.fetch("AP2_P110R_GP01_FIXTURE")))
  POS = JSON.parse(File.binread(ENV.fetch("AP2_P110R_VALID_FIXTURE")))
  raise "upstream AP2 commit mismatch" unless [NEG, POS].all? { |f| f.fetch("ap2_commit") == SHA }
  raise "GP01 upstream signature/disclosure verification missing" unless NEG.fetch("fixture_signature_verified_by_python") == true
  RESULTS = {}

  def self.verify(f, checkout_key:)
    AP2CheckoutBindingResearch.verify!(
      chain: [f.fetch("root_open_sdjwt"), f.fetch("valid_terminal")],
      issuer_jwk: f.fetch("trusted_issuer_public_jwk"),
      expected_agent_jwk: f.fetch("expected_agent_public_jwk"),
      expected_aud: f.fetch("expected_aud"),
      expected_nonce: f.fetch("expected_nonce"),
      merchant_jwk: f.fetch("trusted_merchant_public_jwk"),
      host_checkout_jwt: f.fetch(checkout_key),
      expected_checkout_id: f.fetch("expected_checkout_id"),
      expected_merchant_id: f.fetch("expected_merchant_id"),
      expected_currency: f.fetch("expected_currency"),
      expected_total_minor: f.fetch("expected_total_minor")
    )
  end
end

class P110RFixedSignedNestedConstraintRegressionTest < Minitest::Test
  def test_gp01_signed_unknown_nested_field_now_rejected_at_semantic_constraint_gate
    f = P110R::NEG
    # Authenticate and inspect the original, correctly signed GP01 before
    # the new constraint allowlist is invoked. An invalid signature must
    # cause a test failure rather than a false-positive negative regression.
    root = AP2RootSDJWTResearch.verify_full_root!(
      f.fetch("root_open_sdjwt"), trusted_jwk: f.fetch("trusted_issuer_public_jwk")
    )
    allowed = root.fetch("constraints").find { |v| v["type"] == "checkout.allowed_merchants" }
    refute_nil allowed
    assert_equal %w[allowed policy_override type], allowed.keys.sort
    assert_equal "synthetic-unrecognized-authorization-constraint", allowed.fetch("policy_override")

    error = assert_raises(AP2RootSDJWTResearch::Rejected) do
      P110R.verify(f, checkout_key: "host_checkout_jwt")
    end
    # Must reject specifically at the LOCAL strict nested-Constraint policy.
    # Rejecting because of malformed disclosure/expired proof is not a fix.
    assert_equal "unsupported or missing signed Constraint profile fields", error.message
    P110R::RESULTS["GP01"] = {
      outcome: "REJECT",
      assessment: "LIMITED_REGRESSION_PASS",
      reason: error.message,
      previous_observation: "P1-10q GP01 ACCEPT / SECURITY RED_HOLD"
    }
    puts "P1-10r GP01: REJECT at strict signed Constraint allowlist (previously ACCEPT/RED_HOLD)"
  end

  def test_known_good_signed_checkout_still_returns_evidence_not_allow
    f = P110R::POS
    result = P110R.verify(f, checkout_key: "host_checkout_jwt")
    assert_equal "checkout-001", result.fetch(:checkout_id)
    assert_equal "merchant-allowed", result.fetch(:merchant_id)
    assert_equal 2400, result.fetch(:amount_minor)
    refute result.key?(:allow)
    refute result.key?(:receipt)
    P110R::RESULTS["KNOWN_POSITIVE"] = {
      outcome: "ACCEPT_EVIDENCE_ONLY",
      assessment: "LIMITED_SYNTHETIC_POSITIVE"
    }
    puts "P1-10r known-good: limited signed Checkout evidence OK; no ALLOW"
  end
end

Minitest.after_run do
  file = ENV["AP2_P110R_REPORT"]
  next unless file
  File.binwrite(file, JSON.pretty_generate({
    pinned_ap2: P110R::SHA, scope: "P1-10r fixed synthetic Issuer nested Constraint keys only",
    results: P110R::RESULTS,
    no_general_ap2_conformance_claim: true,
    no_host_allow_or_replay_safety_claim: true,
    production_gem_hc06: "HOLD"
  }) + "\n")
end
