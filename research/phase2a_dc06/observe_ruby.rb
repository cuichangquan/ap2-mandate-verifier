# frozen_string_literal: true
# DC06 fixed-Issuer research candidate: genuine signed unknown-layout negative
# matrix. No arbitrary issuer discovery, generic API, authorization or payment.
require "json"
require_relative "../phase2a_dc04/fixed_issuer_verifier"

f = JSON.parse(File.binread(ENV.fetch("AP2_DC06_FIXTURE")))
raise "wrong signed fixture" unless f.fetch("case_id") == "DC06" &&
  f.fetch("ap2_commit") == AP2DC04FixedIssuerResearch::PINNED_AP2

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

def observe(context, root, terminal)
  raises = []
  trace = TracePoint.new(:raise) do |point|
    error = point.raised_exception
    next unless error.is_a?(AP2RootSDJWTResearch::Rejected)
    raises << {
      message: error.message,
      file: File.basename(point.path),
      method: point.method_id.to_s,
      line: point.lineno
    }
  end
  result = begin
    trace.enable
    AP2DC04FixedIssuerResearch.verify!(**context, chain: [root, terminal])
  rescue AP2RootSDJWTResearch::Rejected => error
    error
  ensure
    trace.disable
  end
  if result.is_a?(AP2RootSDJWTResearch::Rejected)
    origin = raises.find { |x| x[:message] == result.message }
    raise "could not establish rejection origin" unless origin
    { status: "REJECT", reason: result.message, origin: origin }
  else
    raise "unexpected business authorization" unless result.is_a?(Hash) &&
      (result.keys & %i[allow authorized approved payment nonce_consumed]).empty?
    { status: "LIMITED_POSITIVE", checkout_id: result.fetch(:checkout_id) }
  end
end

roots = f.fetch("roots")
terminals = f.fetch("terminals")
expected = {
  "signed_root_sibling" => ["unsupported signed JOSE/Root claims", "exact_keys_subset!"],
  "signed_nested_unknown" => ["unsupported fixed-Issuer signed claim layout", "exact_keys!"],
  "signed_nested_sd_full" => ["unsupported non-array disclosure", "verify_signed_payload!"],
  "signed_nested_sd_hidden" => ["unsupported object SD/decoy or misplaced marker", "walk!"]
}
raise "DC06 fixture variants mismatch" unless roots.keys.sort ==
  (["full"] + expected.keys).sort && terminals.keys.sort == roots.keys.sort

full = observe(ctx, roots.fetch("full"), terminals.fetch("full"))
raise "DC06 genuine FULL positive prerequisite failed" unless full.fetch(:status) ==
  "LIMITED_POSITIVE" && full.fetch(:checkout_id) == f.fetch("expected_checkout_id")

rejected = {}
expected.each do |name, (reason, method)|
  actual = observe(ctx, roots.fetch(name), terminals.fetch(name))
  raise "DC06 signed variant accepted or rejected for wrong reason: #{name} #{actual}" unless
    actual.fetch(:status) == "REJECT" && actual.fetch(:reason) == reason
  origin = actual.fetch(:origin)
  raise "DC06 rejection not attributable to fixed-Issuer candidate: #{name} #{origin}" unless
    origin.fetch(:file) == "fixed_issuer_verifier.rb" &&
    origin.fetch(:method) == method
  rejected[name] = actual
end

# The two nested-selective variants have the SAME genuine issuer JWS and
# differ in disclosure presentation. Agent must re-sign its sd_hash for each.
jws_full = roots.fetch("signed_nested_sd_full").split("~", 2).first
jws_hidden = roots.fetch("signed_nested_sd_hidden").split("~", 2).first
raise "nested hidden negative is not issuer-signed" unless jws_full == jws_hidden
raise "same nested SD wire, not a distinct presentation" if
  roots.fetch("signed_nested_sd_full") == roots.fetch("signed_nested_sd_hidden")
raise "Agent Terminal reused after changing signed disclosure presentation" if
  terminals.fetch("signed_nested_sd_full") == terminals.fetch("signed_nested_sd_hidden")

report = {
  case_id: "DC06",
  pinned_ap2_sha: f.fetch("ap2_commit"),
  candidate_full: full,
  signed_unknown_negatives: rejected,
  gate: "LIMITED_DC06_PARTIAL_OBSERVED",
  unexecuted: [
    "signed duplicate/reused commitment",
    "second hidden delegate_payload authority candidate"
  ],
  warnings: [
    "All negatives genuinely signed by temporary fixture Issuer",
    "Unknown claims are REJECT, never whitelisted",
    "Subset research observation; remaining DC06 subcases NOT RUN",
    "Parent Issue #47, Phase 2-B, Gem, production and payments HOLD"
  ]
}
File.binwrite(ENV.fetch("AP2_DC06_RUBY_REPORT"), JSON.pretty_generate(report) + "\n")
puts "DC06 Ruby: signed FULL LIMITED_POSITIVE; Root sibling / nested unknown / nested object SD visible+hidden all REJECT"
puts "DC06 candidate gate LIMITED_DC06_PARTIAL_OBSERVED; remaining subcases NOT RUN"
