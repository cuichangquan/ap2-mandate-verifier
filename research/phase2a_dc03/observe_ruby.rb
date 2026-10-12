# frozen_string_literal: true
# DC03 research-only O5: genuinely signed required line_items constraint omission.
# Do not treat rejection caused by invalid signature/hash/schema as a PASS.
require "json"
require_relative "../p1_3/checkout_binding_research"

f = JSON.parse(File.binread(ENV.fetch("AP2_DC03_FIXTURE")))
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

# Research-only TracePoint proves the exact pre-business rejection site.
# Existing Ruby root resolver runs before business comparison; it DOES NOT
# implement official JSON Schema, so never claim a Phase 2-B schema gate.
raise_sites = []
trace = TracePoint.new(:raise) do |tp|
  error = tp.raised_exception
  if error.is_a?(AP2RootSDJWTResearch::Rejected)
    raise_sites << {method: tp.method_id.to_s, source: File.basename(tp.path),
                    line: tp.lineno, message: error.message}
  end
end
rejection = begin
  trace.enable
  check_variant(f, root: "root_hidden_line_items", terminal: "terminal_hidden")
  raise "SECURITY RED: hidden required line_items constraint incorrectly ACCEPTED"
rescue AP2RootSDJWTResearch::Rejected => e
  e.message
ensure
  trace.disable
end
# A generic rejection isn't proof of disclosure completeness. It must be
# specifically the missing issuer-signed placeholder, before schema/cardinality.
raise "unattributed security rejection: #{rejection}" unless rejection == "missing disclosure"
origin = raise_sites.find do |event|
  event[:message] == "missing disclosure" && event[:method] == "resolve" &&
    event[:source] == "root_sdjwt_research.rb"
end
raise "missing independent TracePoint resolver attribution" unless origin


report = {
  case_id: "DC03",
  o5_ruby_full_control: "LIMITED_POSITIVE",
  o5_ruby_hidden_line_items: "REJECT",
  ruby_gate_order_evidence: {rejected_in: "signed_root_disclosure_resolver",
    ruby_trace: origin, schema_in_legacy_ruby: "NOT_IMPLEMENTED",
    checkout_business_comparison_reached: false},
  o5_rejection_reason: rejection,
  o5_no_business_allow: true,
  note: "Existing Ruby root resolver raised on signed hidden commitment before business checks. Original Ruby research verifier does NOT run the official Schema; Phase 2-B gate order is NOT proven.",
  evidence_boundary: "P1-3 research only; not a Phase 2-B VerifiedEvidence contract or Host ALLOW"
}
File.binwrite(ENV.fetch("AP2_DC03_RUBY_REPORT"), JSON.pretty_generate(report) + "\n")
puts "DC03 Ruby O5: signed complete control POSITIVE; signed hidden line_items REJECT (missing disclosure)"
