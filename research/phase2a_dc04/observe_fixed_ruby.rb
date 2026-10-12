# frozen_string_literal: true
# DC04 independent Ruby *candidate* O5, distinct from legacy diagnostic O5.
# Research only. Every acceptance here is a checked fact, NOT business ALLOW.
require "json"
require "base64"
require_relative "fixed_issuer_verifier"

f = JSON.parse(File.binread(ENV.fetch("AP2_DC04_FIXTURE")))
raise "unpinned upstream" unless f.fetch("ap2_commit") == AP2DC04FixedIssuerResearch::PINNED_AP2

ctx = {
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
}
roots = f.fetch("roots")
terminals = f.fetch("terminals")

def observe(context, root, terminal)
  result = AP2DC04FixedIssuerResearch.verify!(**context, chain: [root, terminal])
  raise "candidate emitted authorization" unless
    (result.keys & %i[allow approved authorized payment nonce_consumed]).empty?
  { status: "LIMITED_POSITIVE", checkout_id: result.fetch(:checkout_id) }
rescue AP2RootSDJWTResearch::Rejected => e
  { status: "REJECT", reason: e.message }
end

def must_reject!(context, root, terminal, expected:)
  result = observe(context, root, terminal)
  raise "unexpected negative result: #{result.inspect}; expected #{expected}" unless
    result.fetch(:status) == "REJECT" && result.fetch(:reason).match?(expected)
  result
end

positive = observe(ctx, roots.fetch("full"), terminals.fetch("full"))
raise "DC04 FULL signed positive failed: #{positive}" unless
  positive.fetch(:status) == "LIMITED_POSITIVE" &&
  positive.fetch(:checkout_id) == f.fetch("expected_checkout_id")
negative = {}
%w[hidden_merchant_element hidden_sku_element].each do |variant|
  negative[variant] = must_reject!(
    ctx, roots.fetch(variant), terminals.fetch(variant),
    expected: /\Aincomplete_disclosure: missing disclosure\z/
  )
end

extra = {}
f.fetch("additional_signed_negatives").each do |name, pair|
  expected = name == "unexpected_nested_path" ?
    /unsupported signed commitment path/ : /unsupported/
  extra[name] = must_reject!(
    ctx, pair.fetch("root"), pair.fetch("terminal"), expected: expected
  )
end
raise "missing independent signed negative" unless extra.keys.sort ==
  %w[issuer_decoy unexpected_nested_path]

# Fail-closed mutation regression. Each starts from a genuinely signed Root;
# tampering must not be counted as an authentic hidden-element oracle.
full = roots.fetch("full")
terminal = terminals.fetch("full")
parts = full.split("~", -1)
raise "bad FULL segments" unless parts.size >= 4 && parts.last == ""
jws = parts.first
disclosures = parts[1...-1]

mutated_disclosure = disclosures.dup
mutated_disclosure[1] = mutated_disclosure[2]
mutated_root = ([jws] + mutated_disclosure + [""]).join("~")
must_reject!(ctx, mutated_root, terminal, expected: /duplicate disclosure/)

empty_root = ([jws, "", *disclosures, ""]).join("~")
must_reject!(ctx, empty_root, terminal, expected: /invalid SD-JWT segmentation|invalid disclosure/)

tampered_jws = jws.dup
tampered_jws[-1] = tampered_jws[-1] == "A" ? "B" : "A"
must_reject!(ctx, ([tampered_jws, *disclosures, ""]).join("~"), terminal,
             expected: /invalid signed fixture/)

# A legitimate different disclosure order is not an attack. Confusing the
# required indexed content with a *different* disclosure digest is rejected.
swapped = disclosures.dup
swapped[1], swapped[2] = swapped[2], swapped[1]
reordered = ([jws, *swapped, ""]).join("~")
reordered_observation = observe(ctx, reordered, terminal)
# New Root bytes require a new Agent Terminal sd_hash, so the original
# Terminal MUST fail even though the issuer's disclosures remain authentic.
raise "Terminal failed to bind exact disclosure presentation" unless
  reordered_observation.fetch(:status) == "REJECT" &&
  reordered_observation.fetch(:reason).include?("sd_hash")

must_reject!(ctx, full, terminals.fetch("hidden_sku_element"),
             expected: /sd_hash/)

wrong_issuer = ctx.merge(issuer_jwk: ctx.fetch(:expected_agent_jwk))
must_reject!(wrong_issuer, full, terminal, expected: /invalid signed fixture/)
wrong_agent = ctx.merge(expected_agent_jwk: ctx.fetch(:trusted_merchant_public_jwk))
must_reject!(wrong_agent, full, terminal, expected: /Agent public key/)
wrong_host_jwt = ctx.merge(host_checkout_jwt: "not-the-host-signed-JWT")
must_reject!(wrong_host_jwt, full, terminal, expected: /Closed Checkout JWT differs/)

# Legacy default MUST stay strict and reject nested FULL. The new resolver
# is an explicit research-only opt-in; arbitrary injected modules forbidden.
legacy = begin
  AP2CheckoutBindingResearch.verify!(**ctx, chain: [full, terminal])
  raise "legacy resolver unexpectedly broadened"
rescue AP2RootSDJWTResearch::Rejected => e
  raise "wrong legacy failure: #{e.message}" unless
    e.message == "unsupported array disclosure location"
  e.message
end
fake_resolver = Module.new do
  def self.verify_full_root!(**)
    raise "should never be called"
  end
end
must_reject!(ctx.merge(root_research: fake_resolver), full, terminal,
             expected: /unsupported Root research resolver/)

report = {
  case_id: "DC04",
  profile: AP2DC04FixedIssuerResearch::PROFILE,
  pinned_ap2_sha: f.fetch("ap2_commit"),
  candidate_full: positive,
  candidate_hidden: negative,
  candidate_signed_layout_negatives: extra,
  mutation_negative_count: 9,
  legacy_full_reason: legacy,
  candidate_gate: "LIMITED_DC04_OBSERVED",
  warnings: ["synthetic signed research only", "independent oracles and latest HEAD Codex review required",
             "Phase 2-B / Gem / Host payment remains HOLD"]
}
File.binwrite(ENV.fetch("AP2_DC04_FIXED_RUBY_REPORT"), JSON.pretty_generate(report) + "\n")
puts "DC04 fixed-Issuer Ruby candidate: FULL limited-positive, M0/S0 incomplete_disclosure, signed unknown/decoy REJECT"
puts "DC04 candidate gate LIMITED_DC04_OBSERVED (NOT production approval)"
