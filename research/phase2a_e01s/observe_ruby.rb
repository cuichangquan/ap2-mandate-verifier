# frozen_string_literal: true
# E01-S actual O5 only, AFTER independent Python O1-O4 on genuinely signed wires.
# No production Host issuer registration, Gem API, payment or Phase 2-B GO.
require "json"
require "timeout"
require "time"
require "digest"
require_relative "trust_probe"

fixture_path = ENV.fetch("AP2_E01S_FIXTURE")
policy_path = ENV.fetch("AP2_E01S_POLICY")
report_path = ENV.fetch("AP2_E01S_RUBY_REPORT")
raise "oversized fixture file" unless File.size(fixture_path).between?(1, 512_000)
raise "Host policy not frozen before fixture" unless
  File.mtime(policy_path) <= File.mtime(fixture_path)

policy = AP2E01SHostPolicy.load!(File.binread(policy_path))
fixture = AP2StrictJSONResearch.parse!(File.binread(fixture_path))
raise "wrong pinned AP2" unless fixture.fetch("ap2_commit") ==
  AP2DC04FixedIssuerResearch::PINNED_AP2
raise "wrong E01-S fixture type" unless fixture.fetch("case_id") == "E01-S"
raise "Host digest mismatch" unless fixture.fetch("policy_digest") ==
  policy.fetch("policy_digest")

ids = %w[IP01 IP02 IP03]
roots = fixture.fetch("roots")
terminals = fixture.fetch("terminals")
candidate_keys = fixture.fetch("candidate_issuer_public_jwks")
candidate_thumbs = fixture.fetch("candidate_issuer_thumbprints")
raise "unapproved extra experiment variant" unless
  roots.keys.sort == ids && terminals.keys.sort == ids &&
  candidate_keys.keys.sort == ids && candidate_thumbs.keys.sort == ids

outcomes = {}
ids.each do |id|
  root, terminal, key = roots.fetch(id), terminals.fetch(id), candidate_keys.fetch(id)
  raise "candidate thumbprint mismatch" unless
    AP2E01SHostPolicy.thumbprint(key) == candidate_thumbs.fetch(id)
  begin
    outcomes[id] = Timeout.timeout(10) do
      AP2E01STrustProbe.verify!(
        policy: policy,
        case_data: { "root" => root, "terminal" => terminal, "candidate" => key },
        policy_digest: fixture.fetch("policy_digest")
      )
    end
  rescue Timeout::Error
    outcomes[id] = { "status" => "STOP", "reason" => "VERIFIER_TIMEOUT_10S",
                     "first_reject_stage" => "RESOURCE_WALL_CLOCK" }
  end
  puts "E01-S #{id} #{outcomes.fetch(id).inspect}"
  # Without a successful control, don't count negatives as trust proof.
  break unless id != "IP01" || outcomes.fetch("IP01").fetch("status") == "LIMITED_POSITIVE"
end

control = outcomes["IP01"] || {}
b = outcomes["IP02"] || {}
other = outcomes["IP03"] || {}
passed = control["status"] == "LIMITED_POSITIVE" &&
  control["last_stage"] == "S4_DC04_CHAIN_CHECKOUT" &&
  b["status"] == "REJECT" &&
  b["first_reject_stage"] == "S1_HOST_KEY_POLICY" &&
  b["reason"] == "UNTRUSTED_ISSUER" &&
  other["status"] == "REJECT" &&
  other["first_reject_stage"] == "S3_HOST_SIGNED_GRAMMAR" &&
  other["reason"] == "UNSUPPORTED_SIGNED_PROFILE"

report = {
  "case_id" => "E01-S",
  "pinned_ap2_sha" => fixture.fetch("ap2_commit"),
  "ruby_head_sha" => IO.popen(%w[git rev-parse HEAD], &:read).strip,
  "policy_digest" => policy.fetch("policy_digest"),
  "observed_at_utc" => Time.now.utc.iso8601,
  "oracles_O5" => outcomes,
  "gate" => passed ? "LIMITED_SYNTHETIC_E01S_OBSERVED" : "RED_HOLD",
  "limitations" => "Synthetic Host adapter stages only. Not issuer enrollment, key rotation, official AP2 generic conformance, actual payments or Phase 2-B approval."
}
File.binwrite(report_path, JSON.pretty_generate(report) + "\n")
puts "E01-S gate: #{report.fetch('gate')} (NOT Phase 2-B GO)"
abort "E01-S RED/HOLD: target stages not proven" unless passed
