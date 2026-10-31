# frozen_string_literal: true
# Run outside checkout; only ordinary RubyGems require may load the candidate.
require "ap2_mandate_verifier"
require "json"
require "digest"

def need(ok, why)
  raise why unless ok
end
def deep_frozen(value)
  value.frozen? && case value
  when Hash then value.all? { |k,v| deep_frozen(k) && deep_frozen(v) }
  when Array then value.all? { |v| deep_frozen(v) }
  else true
  end
end
spec = Gem.loaded_specs.fetch("ap2_mandate_verifier")
need(spec.version.to_s == "0.5.0" && %w[3.4.12 4.0.9].include?(RUBY_VERSION) && RUBY_ENGINE == "ruby", "candidate runtime")
versions = {"json"=>"2.19.9","jwt"=>"3.3.0","base64"=>"0.3.0","openssl"=>"4.0.2","digest"=>"3.2.1"}
need(versions.all? { |k,v| Gem.loaded_specs.fetch(k).version.to_s == v }, "runtime dependencies")
root = File.realpath(spec.full_gem_path)
prohibited = File.realpath(ARGV.fetch(3)) + "/"
need(!root.start_with?(prohibited), "candidate loaded from repository")
loaded = $LOADED_FEATURES.select { |f| f.include?("/ap2_mandate_verifier") && f.end_with?(".rb") }
need(loaded.size == 15 && loaded.all? { |f| File.realpath(f).start_with?(root + "/") }, "ordinary installed entry")
package = JSON.parse(File.read(ARGV.fetch(2)))
need(loaded.all? { |f| rel=File.realpath(f).delete_prefix(root+"/"); Digest::SHA256.file(f).hexdigest == package.fetch("files_sha256").fetch(rel) }, "installed source identity")
input_raw = File.binread(ARGV.fetch(0)); expected_raw = File.binread(ARGV.fetch(1))
need(Digest::SHA256.hexdigest(input_raw) == "41ad845a7ea82a9c7316c9ef11fb8ee5281453afafe2b4932c7217c1936562c1", "public input identity")
need(Digest::SHA256.hexdigest(expected_raw) == "b8de794bc17c1093d070ed0e78a523ffa568c332bce5e89fe5b2503ee8783d7e", "independent expectation identity")
inputs=JSON.parse(input_raw); expected=JSON.parse(expected_raw).fetch("cases")
need(inputs.keys.sort == expected.keys.sort && expected.size==42, "complete42")
rows=[]
checkout_rows=[]
# Each entry gets fresh strings and is checked against the saved oracle.
%i[verify_research verify_checkout].each do |entry|
expected.each do |name,e|
  args=inputs.fetch(name).to_h { |k,v| [k.to_sym, v.instance_of?(String) ? v.dup : v] }
  r=AP2MandateVerifier.public_send(entry, **args)
  good=e.fetch("code")=="scoped_research_verified"
  need([r.code.to_s,r.status.to_s,r.success?,r.evidence&.to_h] == [e["code"],good ? "verified_research" : "rejected",good,e["evidence"]], "installed comparison "+name)
  need(r.frozen? && r.instance_of?(good ? AP2MandateVerifier::ResearchResult : AP2MandateVerifier::Result), "immutable result type")
  if good
    facts=r.evidence.to_h; before=JSON.generate(facts)
    need(deep_frozen(facts) && r.evidence.frozen? && !facts.fetch("verified_challenge").key?("nonce"), "immutable projected evidence")
    args.each_value { |v| v.replace("changed") if v.instance_of?(String) }
    need(JSON.generate(facts)==before && r.evidence.dup.equal?(r.evidence), "input mutation changed Evidence")
  else
    need(r.evidence.nil?, "failure Evidence")
  end
  (entry == :verify_research ? rows : checkout_rows) << {name:name,code:r.code,result:"MATCH"}
end
end
full=inputs.fetch("FULL");host=JSON.parse(full.fetch("host_json"));binding=host.fetch("binding")

# Seven missing keywords plus empty/unknown/mixed/injected keyword boundaries.
# No fabricated trust or wall-clock fallback; all must be unavailable.
full_args=full.transform_keys(&:to_sym)
keyword_cases=full_args.keys.map { |missing| ["missing "+missing.to_s, full_args.reject { |k,_| k==missing }] }
keyword_cases += [
 ["empty", {}], ["unknown", full_args.merge(unknown: true)],
 ["syntax mixed", full_args.merge(presentation_json: "{}")],
 ["syntax only", {presentation_json: "{}"}], ["Evidence injection", full_args.merge(evidence: {})]
]
unavailable_rows=[]
%i[verify_research verify_checkout].each do |entry|
 keyword_cases.each do |name,args|
  r=AP2MandateVerifier.public_send(entry, **args)
  need(r.instance_of?(AP2MandateVerifier::Result) && r.status==:unavailable &&
    r.code==:research_verification_unavailable && !r.success? && r.evidence.nil? && r.frozen?,
    "installed unavailable "+entry.to_s+"/"+name)
  unavailable_rows << {entry:entry,name:name,result:"MATCH"}
 end
end
need(keyword_cases.size==12 && unavailable_rows.size==24, "keyword case accounting")

records=JSON.parse(JSON.parse(full.fetch("trust_json")).fetch("snapshot").fetch("body")).fetch("records")
key=->(role) { records.find { |v| v["role"]==role }.fetch("public_key_pem") }
common={root_presentation:full.fetch("root_presentation"),terminal_jws:full.fetch("terminal_jws"),host_checkout_jws:full.fetch("host_checkout_jws"),trusted_issuer_public_key_pem:key.call("Issuer"),expected_agent_public_key_pem:key.call("Agent"),trusted_merchant_public_key_pem:key.call("Merchant"),expected_aud:binding.fetch("audience"),expected_nonce:host.fetch("challenge").fetch("nonce"),verified_at:full.fetch("verified_at"),expected_checkout_id:binding.fetch("order_id"),expected_merchant_id:binding.fetch("merchant_id")}
scoped=common.merge(expected_currency:binding.fetch("currency"),expected_total_minor:binding.fetch("expected_total"))
trusted=scoped.reject { |k,_| [:trusted_issuer_public_key_pem,:expected_agent_public_key_pem,:trusted_merchant_public_key_pem].include?(k) }.merge(trust_json:full.fetch("trust_json"),selection_json:full.fetch("selection_json"))
legacy=[[:verify,{presentation_json:"{}"},:verification_not_implemented],
 [:verify_root_signature,{root_jws:full.fetch("root_presentation").split("~").first,trusted_issuer_public_key_pem:key.call("Issuer")},:root_signature_verified_only],
 [:verify_root_disclosures,{presentation:full.fetch("root_presentation"),trusted_issuer_public_key_pem:key.call("Issuer")},:root_disclosures_verified_only],
 [:verify_purchase_binding,common,:purchase_binding_verified_only],[:verify_scoped_constraints,scoped,:scoped_constraints_verified_only],
 [:verify_trusted_scoped_constraints,trusted,:scoped_constraints_verified_only],[:verify_host_binding,full.transform_keys(&:to_sym),:host_binding_verified_only]]
legacy.each do |method,args,code|
 r=AP2MandateVerifier.public_send(method,**args)
 need(r.status==:unverified && r.code==code && !r.success? && r.evidence.nil? && r.frozen?, "legacy "+method.to_s)
end
[["{",:invalid_json],['{"a":1,"a":2}',:duplicate_key]].each do |wire,code|
 r=AP2MandateVerifier.verify(presentation_json:wire)
 need(r.rejected? && r.code==code && !r.success? && r.evidence.nil?, "installed input rejection")
end
begin
 AP2MandateVerifier::Result.new(status: :verified_research,code: :scoped_research_verified)
 raise "non-success constructor bypass"
rescue ArgumentError
end
# Exercise the new business path through the ordinarily installed product. Only
# synthetic JSON fixture files are read from source; no source Ruby is required.
builder = AP2MandateVerifier::InputBuilder
fixture_dir = File.join(ARGV.fetch(3), "examples/input_builder")
read_fixture = ->(name) { JSON.parse(File.binread(File.join(fixture_dir, name + ".json"))) }
order = read_fixture.call("order")
wires = read_fixture.call("signed_wires").transform_keys(&:to_sym)
snapshot = read_fixture.call("trust_snapshot")
trust = builder.trust(snapshot: snapshot, tenant_id: order.fetch("tenant_id"), verified_at: 1_800_000_000,
  issuer: {"identity"=>"issuer","purpose"=>"checkout","key_ref"=>"issuer-1"},
  agent: {"identity"=>"agent","purpose"=>"checkout","key_ref"=>"agent-1"},
  merchant: {"identity"=>"shop","purpose"=>"checkout","key_ref"=>"merchant-1"})
saved = builder.prepare(trust: trust, order: order, root_presentation: wires.fetch(:root_presentation),
  host_checkout_jws: wires.fetch(:host_checkout_jws), challenge_id: "synthetic-challenge", nonce: "n",
  issuer_id: "synthetic-host", not_before: 1_799_998_000, not_after: 1_800_002_000)
trust = builder.restore_trust(trust_json: trust.trust_json, selection_json: trust.selection_json, verified_at: 1_800_000_000)
saved = builder.restore(saved_challenge: saved)
business_args = {trust: trust, saved_challenge: saved, order: order, **wires,
  expected_challenge_issuer_id: "synthetic-host", clock_source_id: "fixed-synthetic-clock", verified_at: 1_800_000_000}
builder_rows = []
check_builder = lambda do |name, arguments, code|
  result = builder.verify(**arguments)
  success = code == :scoped_research_verified
  need(result.code == code && result.success? == success && (success || result.evidence.nil?), "installed builder " + name)
  unless success
    status = code == :research_verification_unavailable ? :unavailable : :rejected
    need(result.instance_of?(AP2MandateVerifier::Result) && result.frozen? && result.status == status,
      "installed builder immutable registered failure " + name)
  end
  builder_rows << {name: name, code: result.code, result: "MATCH"}
  result
end
result = check_builder.call("business FULL", business_args, :scoped_research_verified)
need(result.evidence["checkout_binding"].slice(*order.keys) == order && result.evidence["valid_until"] == 1_800_000_100,
  "installed independently specified business binding/expiry")
need(result.evidence.to_h == AP2MandateVerifier.verify_checkout(**builder.inputs(**business_args)).evidence.to_h,
  "installed builder/core complete Evidence parity")
check_builder.call("current order tamper", business_args.merge(order: order.merge("expected_total"=>999)), :host_binding_mismatch)
check_builder.call("signed mandate expiry", business_args.merge(verified_at: 1_800_000_101), :invalid_purchase_time)
stored = JSON.parse(saved); stored["challenge"]["trust_content_hash"] = "0" * 64
check_builder.call("saved hash unchanged", business_args.merge(saved_challenge: JSON.generate(stored)), :challenge_reference_mismatch)
stored = JSON.parse(saved); stored["challenge"]["state"] = "consumed"
check_builder.call("saved consumed", business_args.merge(saved_challenge: JSON.generate(stored)), :challenge_state_mismatch)
begin
  stored = JSON.parse(saved); stored["format_version"] = "future"
  builder.restore(saved_challenge: JSON.generate(stored))
  raise "installed builder accepted future storage version"
rescue AP2MandateVerifier::InputBuilder::Invalid
  builder_rows << {name: "future saved version", result: "REJECTED"}
end
stored = JSON.parse(saved); stored["format_version"] = "future"
cyclic_order = order.dup; cyclic_order["cycle"] = cyclic_order
{
 "verify malformed JSON"=>business_args.merge(saved_challenge: "{"),
 "verify future version"=>business_args.merge(saved_challenge: JSON.generate(stored)),
 "verify missing order field"=>business_args.merge(order: order.reject { |key,_| key == "currency" }),
 "verify unknown keyword"=>business_args.merge(future: true),
 "verify missing keyword"=>business_args.reject { |key,_| key == :terminal_jws },
 "verify cyclic order"=>business_args.merge(order: cyclic_order)
}.each { |name, arguments| check_builder.call(name, arguments, :invalid_host_context) }
validator = AP2MandateVerifier::InputValidator
original_snapshot = validator.method(:snapshot!)
[AP2MandateVerifier::InputValidator::Unavailable.new(:json_dependency_unavailable),
 AP2MandateVerifier::RootSignature::Unavailable.new(:signature_dependency_unavailable),
 LoadError.new("controlled dependency failure"), RuntimeError.new("controlled internal fault")].each do |fault|
  reached = false
  validator.define_singleton_method(:snapshot!) { |*_, **_keywords| reached = true; raise fault }
  begin
    check_builder.call("verify controlled #{fault.class}", business_args, :research_verification_unavailable)
    need(reached, "installed fault reached real input path")
  ensure
    validator.define_singleton_method(:snapshot!, original_snapshot)
  end
end
need(builder_rows.size == 16, "installed builder case accounting")
puts JSON.pretty_generate(scope:"UNRELEASED040_CANDIDATE_NOT_HOST_ALLOW",candidate_version:spec.version.to_s,
 ruby:RUBY_VERSION,ruby_platform:RUBY_PLATFORM,dependencies:versions,openssl_default:Gem.loaded_specs.fetch("openssl").default_gem?,
 digest_default:Gem.loaded_specs.fetch("digest").default_gem?,libcrypto:OpenSSL::OPENSSL_LIBRARY_VERSION,installed_lib_files:loaded.size,ordinary_entry:true,
 independent_research_comparisons:rows,independent_checkout_comparisons:checkout_rows,unavailable_comparisons:unavailable_rows,legacy_api_checks:legacy.size,input_rejections:2,constructor_rejections:1,builder_checks:builder_rows,total_cases:134,
 holds:"production/distribution/Phase2B/Hostatomic/Stage16; old acquisition gaps and Linuxalltraffic unproved")
