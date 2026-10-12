# frozen_string_literal: true
# Additional genuine issuer-signed DC06 negatives. This traces structural
# rejection; it does NOT claim generic duplicate-digest resolver completeness.
require "json"
require_relative "../phase2a_dc04/fixed_issuer_verifier"

f = JSON.parse(File.binread(ENV.fetch("AP2_DC06_FOLLOWUP_FIXTURE")))
raise "wrong DC06 followup fixture" unless
  f.fetch("case_id") == "DC06-FOLLOWUP" &&
  f.fetch("ap2_commit") == AP2DC04FixedIssuerResearch::PINNED_AP2

context = {
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
cases = f.fetch("roots")
terminals = f.fetch("terminals")
expected = %w[full repeated_signed_root_digest two_signed_open_full two_signed_open_hidden]
raise "incorrect fixture matrix" unless cases.keys.sort == expected.sort &&
  terminals.keys.sort == expected.sort

def observe(ctx, root, terminal)
  exceptions = []
  tracker = TracePoint.new(:raise) do |point|
    e = point.raised_exception
    next unless e.is_a?(AP2RootSDJWTResearch::Rejected)
    exceptions << {
      reason: e.message,
      path: File.basename(point.path),
      method: point.method_id.to_s
    }
  end
  result = begin
    tracker.enable
    AP2DC04FixedIssuerResearch.verify!(**ctx, chain: [root, terminal])
  rescue AP2RootSDJWTResearch::Rejected => e
    e
  ensure
    tracker.disable
  end
  if result.is_a?(AP2RootSDJWTResearch::Rejected)
    origin = exceptions.find { |e| e[:reason] == result.message }
    raise "unattributed exception" unless origin
    { status: "REJECT", reason: result.message, origin: origin }
  else
    raise "not an evidence-only result" unless result.is_a?(Hash) &&
      (result.keys & %i[allow authorized approved payment nonce_consumed]).empty?
    { status: "LIMITED_POSITIVE", checkout_id: result.fetch(:checkout_id) }
  end
end

positive = observe(context, cases.fetch("full"), terminals.fetch("full"))
raise "genuine positive precondition failed" unless
  positive.fetch(:status) == "LIMITED_POSITIVE" &&
  positive.fetch(:checkout_id) == f.fetch("expected_checkout_id")
negatives = {}
(expected - ["full"]).each do |name|
  actual = observe(context, cases.fetch(name), terminals.fetch(name))
  raise "signed negative not structurally rejected: #{name} #{actual}" unless
    actual.fetch(:status) == "REJECT" &&
    actual.fetch(:reason) == "invalid signed Root array" &&
    actual.fetch(:origin).fetch(:path) == "fixed_issuer_verifier.rb" &&
    actual.fetch(:origin).fetch(:method) == "verify_signed_payload!"
  negatives[name] = actual
end

# The two differently presented signed second-Open variants MUST share an
# issuer JWS; the Agent Terminal must bind the exact supplied presentation.
raise "second signed Open JWS mismatch" unless
  cases.fetch("two_signed_open_full").split("~", 2).first ==
  cases.fetch("two_signed_open_hidden").split("~", 2).first
raise "Agent did not re-sign second hidden authority" if
  terminals.fetch("two_signed_open_full") == terminals.fetch("two_signed_open_hidden")

report = {
  case_id: "DC06-FOLLOWUP",
  pinned_ap2_sha: f.fetch("ap2_commit"),
  full: positive,
  signed_negatives: negatives,
  gate: "LIMITED_DC06_FOLLOWUP_STRUCTURAL_REJECT",
  qualifications: [
    "Repeated digest rejected by signed Root cardinality before walking both commitments",
    "Second hidden issuer-signed Open rejected by same early Root cardinality",
    "Does not establish a generic SD-JWT duplicate resolver, issuer profile or authorization",
    "No Phase 2-A or Phase 2-B GO; parent #47 HOLD"
  ]
}
File.binwrite(ENV.fetch("AP2_DC06_FOLLOWUP_REPORT"),
              JSON.pretty_generate(report) + "\n")
puts "DC06 remaining: FULL LIMITED_POSITIVE; 3 genuine signed structural negatives REJECT"
puts "Only bounded structural gate, NOT general SD-JWT authorization"
