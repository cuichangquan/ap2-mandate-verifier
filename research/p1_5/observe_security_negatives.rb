# frozen_string_literal: true
#
# Security-negative observer, NOT production verifier or authorization code.
# Run against genuine signed research fixtures from the fixed AP2 v0.2 SDK.
# RED means a hostile/unsupported input was ACCEPTED by the P1 research code.
# Does not suppress or "fix" RED cases. Unexpected exceptions are ERROR.
#
# Exit 1 for any RED/ERROR, but ALWAYS write machine-readable results; GitHub
# Actions must collect failures as evidence, not turn them into test "PASS".
require_relative "../p1_3/checkout_binding_research"
require "json"

path = ENV.fetch("AP2_P15_FIXTURES")
outfile = ENV.fetch("AP2_P15_RESULTS", "p1-5-security-results.json")
f = JSON.parse(File.binread(path))
raise "unexpected upstream baseline" unless f.fetch("ap2_commit") ==
  "b4587ac1d055888a73b4b21750973cffba961793"

def run_checkout(f, terminal: f.fetch("valid_terminal"),
                 root: f.fetch("root_open_sdjwt"),
                 jwt: f.fetch("checkout_jwts").fetch("valid"),
                 issuer: f.fetch("trusted_issuer_public_jwk"),
                 merchant: f.fetch("trusted_merchant_public_jwk"),
                 nonce: f.fetch("expected_nonce"))
  AP2CheckoutBindingResearch.verify!(
    chain: [root, terminal],
    issuer_jwk: issuer, expected_agent_jwk: f.fetch("expected_agent_public_jwk"),
    expected_aud: f.fetch("expected_aud"), expected_nonce: nonce,
    merchant_jwk: merchant, host_checkout_jwt: jwt,
    expected_checkout_id: f.fetch("expected_checkout_id"),
    expected_merchant_id: f.fetch("expected_merchant_id"),
    expected_currency: f.fetch("expected_currency"),
    expected_total_minor: f.fetch("expected_total_minor")
  )
end

cases = []
def probe(cases, id, group, policy, expected, &block)
  outcome = "ACCEPTED"
  error_class = nil
  begin
    block.call
  rescue AP2RootSDJWTResearch::Rejected => e
    outcome = "REJECTED"
    error_class = e.class.name
  rescue StandardError => e
    outcome = "ERROR"
    error_class = e.class.name
  end
  verdict = if outcome == "ERROR"
    "ERROR"
  elsif expected == "REJECTED"
    outcome == "REJECTED" ? "GREEN" : "RED"
  elsif expected == "ACCEPTED"
    outcome == "ACCEPTED" ? "GREEN" : "ERROR"
  elsif expected == "STATELESS_REPLAY_ACCEPTANCE"
    outcome == "ACCEPTED" ? "HOST_BOUNDARY" : "ERROR"
  else
    "ERROR"
  end
  record = {
    id: id, group: group, policy: policy, expected: expected,
    observed: outcome, verdict: verdict, error_class: error_class
  }
  cases << record
  puts "#{verdict.ljust(13)} #{id.ljust(4)} #{group.ljust(12)} expected=#{expected.ljust(27)} observed=#{outcome}"
end

probe(cases, "N00", "control", "signed legitimate checkout", "ACCEPTED") { run_checkout(f) }
probe(cases, "N01", "parsing", "reject authentically signed duplicate merchant.id", "REJECTED") do
  run_checkout(f, terminal: f.fetch("terminal_variants").fetch("duplicate_merchant_id"),
                jwt: f.fetch("checkout_jwts").fetch("duplicate_merchant_id"))
end
probe(cases, "N02", "jose", "reject signed duplicate protected-header alg", "REJECTED") do
  run_checkout(f, terminal: f.fetch("terminal_variants").fetch("duplicate_header_alg"),
                jwt: f.fetch("checkout_jwts").fetch("duplicate_header_alg"))
end
probe(cases, "N03", "time", "reject genuinely signed expired Closed exp", "REJECTED") do
  run_checkout(f, terminal: f.fetch("terminal_variants").fetch("expired_closed"))
end
probe(cases, "N04", "time", "reject future Closed iat", "REJECTED") do
  run_checkout(f, terminal: f.fetch("terminal_variants").fetch("future_closed_iat"))
end
probe(cases, "N05", "jose", "reject unsupported Merchant JWT typ", "REJECTED") do
  run_checkout(f, terminal: f.fetch("terminal_variants").fetch("merchant_header_wrong_typ"),
                jwt: f.fetch("checkout_jwts").fetch("merchant_header_wrong_typ"))
end
probe(cases, "N06", "jose", "reject external key hint jku", "REJECTED") do
  run_checkout(f, terminal: f.fetch("terminal_variants").fetch("merchant_header_jku"),
                jwt: f.fetch("checkout_jwts").fetch("merchant_header_jku"))
end
probe(cases, "N07", "checkout", "reject unrecognized authority-sensitive checkout field in strict profile", "REJECTED") do
  run_checkout(f, terminal: f.fetch("terminal_variants").fetch("unknown_checkout_field"),
                jwt: f.fetch("checkout_jwts").fetch("unknown_checkout_field"))
end
probe(cases, "N08", "resource", "reject over-limit signed Checkout", "REJECTED") do
  run_checkout(f, terminal: f.fetch("terminal_variants").fetch("large_checkout"),
                jwt: f.fetch("checkout_jwts").fetch("large_checkout"))
end
probe(cases, "N09", "trust", "reject issuer public key mismatch", "REJECTED") do
  run_checkout(f, issuer: f.fetch("wrong_issuer_public_jwk"))
end
probe(cases, "N10", "trust", "reject missing trusted Merchant key", "REJECTED") do
  run_checkout(f, merchant: nil)
end
probe(cases, "N11", "disclosure", "reject hidden required Merchant authority", "REJECTED") do
  run_checkout(f, root: f.fetch("root_hidden_merchant"))
end
probe(cases, "N12", "disclosure", "reject fully revealed extra authority constraint", "REJECTED") do
  run_checkout(f, root: f.fetch("extra_authority_root"))
end
probe(cases, "N13", "disclosure", "reject hidden extra signed authority constraint", "REJECTED") do
  run_checkout(f, root: f.fetch("hidden_extra_authority_root"))
end
probe(cases, "N14", "time", "reject expired signed Root", "REJECTED") do
  run_checkout(f, root: f.fetch("expired_root"))
end
probe(cases, "N15", "resource", "reject huge malformed Root", "REJECTED") do
  run_checkout(f, root: f.fetch("oversized_root"))
end
probe(cases, "N16", "context", "reject wrong Host nonce", "REJECTED") do
  run_checkout(f, nonce: "not-the-issued-challenge")
end
probe(cases, "N17", "host-boundary", "no stateful anti-replay implemented: repeated valid token", "STATELESS_REPLAY_ACCEPTANCE") do
  run_checkout(f)
  run_checkout(f)
end

summary = cases.group_by { |row| row.fetch(:verdict) }.transform_values(&:size)
%w[GREEN RED ERROR HOST_BOUNDARY].each { |key| summary[key] ||= 0 }
result = {
  baseline: f.fetch("ap2_commit"),
  scope: "research-only; reject policies stricter than full AP2 may be Host-specific",
  case_count: cases.size,
  summary: summary,
  cases: cases,
  go_hold: "Gem/API/production HOLD: observation does NOT authorize purchase"
}
File.binwrite(outfile, JSON.pretty_generate(result) + "\n")
puts "P1-5 SUMMARY: #{summary.sort.map { |key, value| "#{key}=#{value}" }.join(" ")}"
puts "JSON results: #{outfile}"
exit(summary["RED"].zero? && summary["ERROR"].zero? ? 0 : 1)
