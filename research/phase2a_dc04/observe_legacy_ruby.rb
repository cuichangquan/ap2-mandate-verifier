# frozen_string_literal: true
# DC04 research-only O5 diagnostic. The old P1-1 resolver intentionally does
# not support nested SD array positions. A rejection of BOTH the fully
# disclosed positive and withheld negatives is NOT evidence of safe disclosure.
require "json"
require_relative "../p1_3/checkout_binding_research"

f = JSON.parse(File.binread(ENV.fetch("AP2_DC04_FIXTURE")))
raise "wrong AP2 source" unless f.fetch("ap2_commit") ==
  "b4587ac1d055888a73b4b21750973cffba961793"
keys = %w[full hidden_merchant_element hidden_sku_element]
outcomes = {}
keys.each do |variant|
  raised = []
  trace = TracePoint.new(:raise) do |tp|
    error = tp.raised_exception
    if error.is_a?(AP2RootSDJWTResearch::Rejected)
      raised << { message: error.message, method: tp.method_id.to_s,
                  file: File.basename(tp.path), line: tp.lineno }
    end
  end
  result = begin
    trace.enable
    AP2CheckoutBindingResearch.verify!(
      chain: [f.fetch("roots").fetch(variant), f.fetch("terminals").fetch(variant)],
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
  rescue AP2RootSDJWTResearch::Rejected => e
    e
  ensure
    trace.disable
  end
  if result.is_a?(AP2RootSDJWTResearch::Rejected)
    origin = raised.find { |e| e[:message] == result.message }
    raise "could not trace Ruby rejection" unless origin
    outcomes[variant] = {
      status: "REJECT", reason: result.message, origin: origin
    }
  elsif result.is_a?(Hash)
    raise "unexpected business ALLOW" unless (result.keys & %i[allow approved authorized payment nonce_consumed]).empty?
    raise "wrong Host checkout" unless result.fetch(:checkout_id) == f.fetch("expected_checkout_id")
    outcomes[variant] = { status: "LIMITED_POSITIVE", reason: nil }
  else
    raise "unknown result class"
  end
end

control = outcomes.fetch("full")
merchant = outcomes.fetch("hidden_merchant_element")
sku = outcomes.fetch("hidden_sku_element")
# A fully disclosed control must succeed BEFORE either missing-element case
# can count as a successful disclosure-completeness negative.
limited_dc04_pass = control.fetch(:status) == "LIMITED_POSITIVE" &&
  merchant.fetch(:status) == "REJECT" && merchant.fetch(:reason) == "missing disclosure" &&
  sku.fetch(:status) == "REJECT" && sku.fetch(:reason) == "missing disclosure"
gate = limited_dc04_pass ? "LIMITED_DC04_OBSERVED" : "RED_HOLD"
report = {
  case_id: "DC04", legacy_ruby_observations: outcomes,
  positive_precondition_met: control.fetch(:status) == "LIMITED_POSITIVE",
  dc04_gate: gate,
  limitation: "No official Schema implementation in legacy Ruby. A generic unsupported-position rejection is NOT incomplete_disclosure proof. Phase 2-B remains HOLD."
}
File.binwrite(ENV.fetch("AP2_DC04_RUBY_REPORT"), JSON.pretty_generate(report) + "\n")
puts "DC04 O5: full=#{control.fetch(:status)}(#{control[:reason]}), " \
     "Merchant0=#{merchant.fetch(:status)}(#{merchant[:reason]}), " \
     "SKU0=#{sku.fetch(:status)}(#{sku[:reason]})"
puts "DC04 Gate: #{gate} — NOT a business ALLOW"
