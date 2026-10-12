# frozen_string_literal: true
# DC02 research-only O5: genuinely signed Merchant constraint omission.
# Do not treat rejection caused by invalid signature/hash/schema as a PASS.
require "json"
require_relative "../p1_3/checkout_binding_research"

f = JSON.parse(File.binread(ENV.fetch("AP2_DC02_FIXTURE")))
raise "wrong source SHA" unless f.fetch("ap2_commit") ==
  "b4587ac1d055888a73b4b21750973cffba961793"

def check_variant(f, root:, terminal:)
  AP2CheckoutBindingResearch.verify!(
    chain: [f.fetch(root), f.fetch(terminal)],
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

control = check_variant(f, root: "root_full", terminal: "terminal_full")
raise "bad positive Checkout ID" unless control.fetch(:checkout_id) == f.fetch("expected_checkout_id")
raise "bad positive Merchant" unless control.fetch(:merchant_id) == f.fetch("expected_merchant_id")
raise "bad amount" unless control.fetch(:amount_minor) == f.fetch("expected_total_minor")
raise "positive must not grant business authorization" unless
  (control.keys & %i[allow approved authorized payment nonce_consumed]).empty?

rejection = begin
  check_variant(f, root: "root_hidden_merchant", terminal: "terminal_hidden")
  raise "SECURITY RED: hidden Merchant constraint incorrectly ACCEPTED"
rescue AP2RootSDJWTResearch::Rejected => e
  e.message
end
# A generic rejection isn't proof of disclosure completeness. It must be
# specifically the missing issuer-signed placeholder, before schema/cardinality.
raise "unattributed security rejection: #{rejection}" unless rejection == "missing disclosure"

report = {
  case_id: "DC02",
  o5_ruby_full_control: "LIMITED_POSITIVE",
  o5_ruby_hidden_merchant: "REJECT",
  o5_rejection_reason: rejection,
  o5_no_business_allow: true,
  note: "O5 reason is meaningful ONLY alongside independently verified O1/O2 signatures and valid sd_hash in Python observer",
  evidence_boundary: "P1-3 research only; not a Phase 2-B VerifiedEvidence contract or Host ALLOW"
}
File.binwrite(ENV.fetch("AP2_DC02_RUBY_REPORT"), JSON.pretty_generate(report) + "\n")
puts "DC02 Ruby O5: signed complete control POSITIVE; signed hidden Merchant REJECT (missing disclosure)"
