# frozen_string_literal: true
# P1-10t: ONE signed S01 observational test. No change to verifier.
# A workflow success means observation complete, NEVER a security PASS.
require_relative "../p1_3/checkout_binding_research"
require "json"
require "minitest/autorun"

module P110T
  SHA = "b4587ac1d055888a73b4b21750973cffba961793"
  FIXTURE = JSON.parse(File.binread(ENV.fetch("AP2_P110T_FIXTURE")))
  raise "wrong pinned AP2" unless FIXTURE.fetch("ap2_commit") == SHA
  raise "wrong probe" unless FIXTURE.fetch("probe_id") == "S01"
  raise "not upstream-authenticated" unless FIXTURE.fetch("upstream_signatures_verified") == true
  raise "not official schema INVALID" unless FIXTURE.fetch("official_schema_invalid") == true
  raise "wrong schema violation location" unless
    FIXTURE.fetch("schema_error_path") == ["constraints", 0, "items", 0, "id"]
  raise "wrong official schema rule" unless FIXTURE.fetch("schema_error_keyword") == "type"
  REPORT = {}
  FLAGS = { ruby_root_checked: false }
end

class P110TSingleSignedInvalidTypeProbe < Minitest::Test
  def test_s01_official_schema_invalid_but_genuinely_signed_requirement_id
    f = P110T::FIXTURE
    # Actual Ruby signature/disclosure re-verification must PRECEDE an
    # attempt to test final semantic acceptance, so an invalid JWS/SD-JWT
    # cannot count as a successful policy rejection.
    root = AP2RootSDJWTResearch.verify_full_root!(
      f.fetch("root_open_sdjwt"), trusted_jwk: f.fetch("trusted_issuer_public_jwk")
    )
    requirement = root.fetch("constraints").find do |c|
      c["type"] == "checkout.line_items"
    end.fetch("items").first
    assert_equal %w[acceptable_items id quantity], requirement.keys.sort
    assert_equal 123, requirement.fetch("id")
    assert_instance_of Integer, requirement.fetch("id")
    P110T::FLAGS[:ruby_root_checked] = true

    begin
      evidence = AP2CheckoutBindingResearch.verify!(
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
      assert_kind_of Hash, evidence
      assert_equal "checkout-001", evidence.fetch(:checkout_id)
      P110T::REPORT.merge!(
        outcome: "ACCEPT", security: "RED_HOLD",
        meaning: "Unmodified fixed-Issuer Ruby research checker accepts an officially schema-invalid signed requirement id (123), no real exploit claim"
      )
      puts "S01 OBSERVED: ACCEPT — RED/HOLD (signed input, official JSON Schema INVALID)"
    rescue AP2RootSDJWTResearch::Rejected => e
      P110T::REPORT.merge!(
        outcome: "REJECT", security: "LIMITED_REJECTION_ONLY",
        rejection_reason: e.message,
        meaning: "Only this signed schema-invalid fixture was rejected"
      )
      puts "S01 OBSERVED: REJECT — limited fixture, not general conformance"
    end
    assert_includes %w[ACCEPT REJECT], P110T::REPORT.fetch(:outcome)
  end
end

Minitest.after_run do
  path = ENV["AP2_P110T_REPORT"]
  next unless path
  File.binwrite(path, JSON.pretty_generate({
    pinned_official_ap2: P110T::SHA,
    probe_id: "S01",
    case_count: 1,
    upstream_signatures_verified: P110T::FIXTURE["upstream_signatures_verified"],
    upstream_schema_invalid: P110T::FIXTURE["official_schema_invalid"],
    ruby_signed_root_verified: P110T::FLAGS[:ruby_root_checked],
    verified_official_error_path: P110T::FIXTURE["schema_error_path"],
    observed: P110T::REPORT,
    verifier_modified_by_this_step: false,
    production_gem_and_hc06: "HOLD"
  }) + "\n")
end
