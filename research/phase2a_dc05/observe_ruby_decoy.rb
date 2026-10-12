# frozen_string_literal: true
# Phase 2-A DC05 O5 research-only. No Gem, public API or payment authorization.
require "json"
require_relative "../phase2a_dc04/fixed_issuer_verifier"

f = JSON.parse(File.binread(ENV.fetch("AP2_DC05_FIXTURE")))
raise "unpinned AP2 v0.2" unless f.fetch("ap2_commit") == AP2DC04FixedIssuerResearch::PINNED_AP2
control_root = f.fetch("roots").fetch("full")
control_terminal = f.fetch("terminals").fetch("full")
decoy = f.fetch("additional_signed_negatives").fetch("issuer_decoy")

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

def observe_with_origin(ctx, root, terminal)
  raised = []
  tracer = TracePoint.new(:raise) do |point|
    err = point.raised_exception
    next unless err.is_a?(AP2RootSDJWTResearch::Rejected)
    raised << {
      message: err.message, file: File.basename(point.path),
      method: point.method_id.to_s, line: point.lineno
    }
  end
  result = begin
    tracer.enable
    AP2DC04FixedIssuerResearch.verify!(**ctx, chain: [root, terminal])
  rescue AP2RootSDJWTResearch::Rejected => err
    err
  ensure
    tracer.disable
  end
  if result.is_a?(AP2RootSDJWTResearch::Rejected)
    origin = raised.find { |x| x[:message] == result.message }
    raise "unattributable candidate rejection" unless origin
    { status: "REJECT", reason: result.message, origin: origin }
  else
    raise "candidate returned business ALLOW" unless result.is_a?(Hash) &&
      (result.keys & %i[allow approved authorized payment nonce_consumed]).empty?
    { status: "LIMITED_POSITIVE", checkout_id: result.fetch(:checkout_id) }
  end
end

full = observe_with_origin(ctx, control_root, control_terminal)
raise "DC05 positive prerequisite not met: #{full}" unless
  full[:status] == "LIMITED_POSITIVE" &&
  full[:checkout_id] == f.fetch("expected_checkout_id")

negative = observe_with_origin(ctx, decoy.fetch("root"), decoy.fetch("terminal"))
raise "genuine signed decoy not rejected: #{negative}" unless negative[:status] == "REJECT"
# The candidate explicitly forbids extra object SD commitments / unknown
# signed Root siblings. This is an unsupported-profile denial, not a
# claim that it cryptographically identified the preimage as a decoy.
raise "wrong negative reason: #{negative}" unless negative.fetch(:reason).match?(
  /\Aunsupported (signed JOSE\/Root claims|object SD\/decoy or misplaced marker)\z/
)
raise "incorrect Ruby rejection origin" unless
  negative.fetch(:origin).fetch(:file) == "fixed_issuer_verifier.rb" &&
  %w[verify_signed_payload! walk! exact_keys_subset!].include?(negative.fetch(:origin).fetch(:method))

# The independent Python oracle will establish signing and exact unresolved
# digest paths. This Ruby rejection by itself is NEVER the decoy safety proof.
report = {
  case_id: "DC05",
  fixed_profile: AP2DC04FixedIssuerResearch::PROFILE,
  positive: full,
  issuer_signed_decoy_negative: negative,
  attributable_reason_family: "unsupported_profile",
  gate: "LIMITED_DC05_OBSERVED",
  notes: [
    "Run independent O1-O4 first; do not infer validity from rejection",
    "No general decoy exception, production approval or business ALLOW",
    "Parent Issue #47 and Phase 2-B remain HOLD"
  ]
}
File.binwrite(ENV.fetch("AP2_DC05_RUBY_REPORT"), JSON.pretty_generate(report) + "\n")
puts "DC05 Ruby: FULL LIMITED_POSITIVE / genuine signed decoy REJECT (unsupported fixed-Issuer profile)"
puts "DC05 candidate gate LIMITED_DC05_OBSERVED; generic decoy semantics/Phase 2-B HOLD"
