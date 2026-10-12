# frozen_string_literal: true
# P1-10u: ONE signed S01 type rejection and ONE separately signed positive.
# Offline fixed-Issuer synthetic profile only. No Gem, Host ALLOW, or payment.
require_relative "../p1_3/checkout_binding_research"
require "json"
require "minitest/autorun"

module P110U
  PINNED_AP2 = "b4587ac1d055888a73b4b21750973cffba961793"
  S01 = JSON.parse(File.binread(ENV.fetch("AP2_P110U_S01_FIXTURE")))
  POSITIVE = JSON.parse(File.binread(ENV.fetch("AP2_P110U_VALID_FIXTURE")))
  raise "wrong pinned AP2" unless [S01, POSITIVE].all? { |f| f.fetch("ap2_commit") == PINNED_AP2 }
  raise "not S01" unless S01.fetch("probe_id") == "S01"
  raise "upstream signature verification missing" unless S01.fetch("upstream_signatures_verified") == true
  raise "S01 must be official schema INVALID" unless S01.fetch("official_schema_invalid") == true
  raise "wrong S01 violation" unless S01.fetch("schema_error_path") == ["constraints", 0, "items", 0, "id"] &&
    S01.fetch("schema_error_keyword") == "type"
  RESULTS = {}

  def self.verify(f)
    AP2CheckoutBindingResearch.verify!(
      chain: [f.fetch("root_open_sdjwt"), f.fetch("valid_terminal")],
      issuer_jwk: f.fetch("trusted_issuer_public_jwk"),
      expected_agent_jwk: f.fetch("expected_agent_public_jwk"),
      expected_aud: f.fetch("expected_aud"),
      expected_nonce: f.fetch("expected_nonce"),
      merchant_jwk: f.fetch("trusted_merchant_public_jwk"),
      host_checkout_jwt: f.fetch("host_checkout_jwt"),
      expected_checkout_id: f.fetch("expected_checkout_id"),
      expected_merchant_id: f.fetch("expected_merchant_id"),
      expected_currency: f.fetch("expected_currency"),
      expected_total_minor: f.fetch("expected_total_minor")
    )
  end

  def self.requirement(f)
    root = AP2RootSDJWTResearch.verify_full_root!(
      f.fetch("root_open_sdjwt"), trusted_jwk: f.fetch("trusted_issuer_public_jwk")
    )
    root.fetch("constraints").find { |c| c["type"] == "checkout.line_items" }
      .fetch("items").first
  end
end

class P110USignedS01TypeOnlyRegressionTest < Minitest::Test
  def test_genuinely_signed_s01_integer_id_rejected_at_exact_type_gate
    f = P110U::S01
    signed = P110U.requirement(f)
    assert_equal %w[acceptable_items id quantity], signed.keys.sort
    assert_instance_of Integer, signed.fetch("id")
    assert_equal 123, signed.fetch("id")

    error = assert_raises(AP2RootSDJWTResearch::Rejected) { P110U.verify(f) }
    # A stale terminal or broken Agent/Merchant proof must NOT count as a
    # policy-type rejection. Match the exact new local type-gate reason.
    assert_equal "invalid signed requirement id type", error.message
    P110U::RESULTS["S01"] = {
      outcome: "REJECT", assessment: "LIMITED_S01_TYPE_REGRESSION",
      exact_reason: error.message, former_observation: "P1-10t ACCEPT / SECURITY RED_HOLD"
    }
    puts "P1-10u S01: signed integer requirement ID REJECT at exact type gate"
  end

  def test_separately_signed_known_good_checkout_still_returns_evidence_only
    f = P110U::POSITIVE
    signed = P110U.requirement(f)
    assert_equal "req-1", signed.fetch("id")
    assert_instance_of String, signed.fetch("id")

    evidence = P110U.verify(f)
    assert_equal "checkout-001", evidence.fetch(:checkout_id)
    assert_equal "merchant-allowed", evidence.fetch(:merchant_id)
    assert_equal 2400, evidence.fetch(:amount_minor)
    refute evidence.key?(:allow)
    refute evidence.key?(:receipt)
    P110U::RESULTS["KNOWN_POSITIVE"] = {
      outcome: "ACCEPT_EVIDENCE_ONLY", assessment: "LIMITED_SYNTHETIC_POSITIVE"
    }
    puts "P1-10u known-good: signed Checkout evidence OK (no business ALLOW)"
  end
end

Minitest.after_run do
  report = ENV["AP2_P110U_REPORT"]
  next unless report
  File.binwrite(report, JSON.pretty_generate({
    pinned_official_ap2: P110U::PINNED_AP2,
    scope: "fixed synthetic Issuer S01 requirement id type ONLY",
    results: P110U::RESULTS,
    official_schema_s01_invalid: true,
    other_schema_gaps: "NOT TESTED",
    p110u_signed_case_ci: "NOT RUN",
    existing_ci_regressions: "TRACKED_SEPARATELY",
    general_gem_host_hc06_payment: "HOLD_NO_GO"
  }) + "\n")
end
