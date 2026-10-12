# frozen_string_literal: true
# DC01 O5 comparison using the EXISTING research verifier, not a Phase 2-B API.
# Requires a fully synthetic current-time fixture from the official pinned AP2.
require "json"
require_relative "../p1_3/checkout_binding_research"

fixture = JSON.parse(File.binread(ENV.fetch("AP2_DC01_FIXTURE")))
raise "wrong AP2 source" unless fixture.fetch("ap2_commit") ==
  "b4587ac1d055888a73b4b21750973cffba961793"

result = AP2CheckoutBindingResearch.verify!(
  chain: [fixture.fetch("root_open_sdjwt"), fixture.fetch("valid_terminal")],
  issuer_jwk: fixture.fetch("trusted_issuer_public_jwk"),
  expected_agent_jwk: fixture.fetch("expected_agent_public_jwk"),
  expected_aud: fixture.fetch("expected_aud"),
  expected_nonce: fixture.fetch("expected_nonce"),
  merchant_jwk: fixture.fetch("trusted_merchant_public_jwk"),
  host_checkout_jwt: fixture.fetch("host_checkout_jwt"),
  expected_checkout_id: fixture.fetch("expected_checkout_id"),
  expected_merchant_id: fixture.fetch("expected_merchant_id"),
  expected_currency: fixture.fetch("expected_currency"),
  expected_total_minor: fixture.fetch("expected_total_minor")
)

raise "wrong checkout id" unless result.fetch(:checkout_id) == fixture.fetch("expected_checkout_id")
raise "wrong merchant" unless result.fetch(:merchant_id) == fixture.fetch("expected_merchant_id")
raise "wrong checkout amount" unless result.fetch(:amount_minor) == fixture.fetch("expected_total_minor")
raise "evidence must not authorize" unless (result.keys & %i[allow authorized approved payment nonce_consumed]).empty?

report = {
  case_id: "DC01",
  o5_legacy_ruby_research: "LIMITED_POSITIVE",
  observed_checkout: {
    checkout_id: result.fetch(:checkout_id),
    merchant_id: result.fetch(:merchant_id),
    amount_minor: result.fetch(:amount_minor)
  },
  evidence_boundary: "Existing P1-3 verifier comparison only; no Phase 2-B contract, Host ALLOW, replay or HC06"
}
File.write(ENV.fetch("AP2_DC01_RUBY_REPORT"), JSON.pretty_generate(report) + "\n")
puts "DC01 O5: limited signed Ruby research positive, no business ALLOW"
