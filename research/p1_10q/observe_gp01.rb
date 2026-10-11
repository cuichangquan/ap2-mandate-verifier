# frozen_string_literal: true
# P1-10q: exactly ONE observational GP01 synthetic signed negative.
# NEVER alter p1_1/p1_2/p1_3 to make the probe "pass". Unexpected ACCEPT
# is recorded as RED/HOLD, not reclassified as safe or rejected silently.
require_relative "../p1_3/checkout_binding_research"
require "json"
require "minitest/autorun"

module P110Q
  FIXED_AP2 = "b4587ac1d055888a73b4b21750973cffba961793"
  FIXTURE = JSON.parse(File.binread(ENV.fetch("AP2_P110Q_FIXTURE")))
  raise "wrong AP2 baseline" unless FIXTURE.fetch("ap2_commit") == FIXED_AP2
  raise "missing upstream signature verification" unless
    FIXTURE.fetch("fixture_signature_verified_by_python") == true
  raise "wrong probe" unless FIXTURE.fetch("probe_id") == "GP01"
  RESULT = {}
  ROOT_REVERIFIED = { completed: false }
end

class P110QNestedConstraintProbeTest < Minitest::Test
  def test_gp01_single_signed_unknown_nested_authority_field
    f = P110Q::FIXTURE
    # Independent Ruby authentication of the full Issuer-signed disclosure
    # chain. This must succeed before observing the full A-only verifier.
    root = AP2RootSDJWTResearch.verify_full_root!(
      f.fetch("root_open_sdjwt"),
      trusted_jwk: f.fetch("trusted_issuer_public_jwk")
    )
    matching = root.fetch("constraints").select do |c|
      c["type"] == "checkout.allowed_merchants"
    end
    assert_equal 1, matching.length
    assert_equal "synthetic-unrecognized-authorization-constraint",
                 matching.first.fetch("policy_override")
    assert_equal %w[allowed policy_override type], matching.first.keys.sort
    assert_equal "merchant-allowed", matching.first.fetch("allowed").first.fetch("id")
    # Mark only after both signed Root parsing and expected disclosed field checks.
    P110Q::ROOT_REVERIFIED[:completed] = true

    begin
      proof = AP2CheckoutBindingResearch.verify!(
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
      assert_kind_of Hash, proof
      assert_equal "checkout-001", proof.fetch(:checkout_id)
      P110Q::RESULT.merge!(
        outcome: "ACCEPT",
        security_assessment: "RED_HOLD",
        note: "Unexpected acceptance of correctly signed unknown nested Constraint field by strict research profile; NOT AP2-wide exploit proof."
      )
      puts "GP01 OBSERVED: ACCEPT — RED/HOLD (unsupported nested authorization field ignored)"
    rescue AP2RootSDJWTResearch::Rejected => e
      P110Q::RESULT.merge!(
        outcome: "REJECT",
        security_assessment: "BOUNDED_REJECTION_ONLY",
        note: "Ruby rejected signed unknown nested Constraint; no general disclosure-completeness proof.",
        rejection_reason: e.message
      )
      puts "GP01 OBSERVED: REJECT — limited fixture only (#{e.class})"
    end
    # Either observation is valid data for this one-case study. CI success
    # means that the experiment completed; it NEVER means policy is safe.
    assert_includes %w[ACCEPT REJECT], P110Q::RESULT.fetch(:outcome)
  end
end

Minitest.after_run do
  path = ENV["AP2_P110Q_REPORT"]
  next unless path
  out = {
    fixed_ap2_sha: P110Q::FIXED_AP2,
    probe: "GP01",
    count: 1,
    fixture_issuer_agent_merchant_signatures_checked: P110Q::FIXTURE["fixture_signature_verified_by_python"],
    root_disclosures_reverified_by_ruby: P110Q::ROOT_REVERIFIED[:completed],
    result: P110Q::RESULT,
    scope: "isolated research observation, not a security certification or Host checkout ALLOW",
    observation_script_does_not_modify_verifier: true
  }
  File.binwrite(path, JSON.pretty_generate(out) + "\n")
end
