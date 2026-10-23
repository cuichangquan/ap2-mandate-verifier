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
need(spec.version.to_s == "0.1.0.pre.2" && RUBY_VERSION == "4.0.8" && RUBY_ENGINE == "ruby", "candidate runtime")
versions = {"json"=>"2.19.9","jwt"=>"3.3.0","base64"=>"0.3.0","openssl"=>"4.0.2","digest"=>"3.2.1"}
need(versions.all? { |k,v| Gem.loaded_specs.fetch(k).version.to_s == v }, "runtime dependencies")
root = File.realpath(spec.full_gem_path)
prohibited = File.realpath(ARGV.fetch(3)) + "/"
need(!root.start_with?(prohibited), "candidate loaded from repository")
loaded = $LOADED_FEATURES.select { |f| f.include?("/ap2_mandate_verifier") && f.end_with?(".rb") }
need(loaded.size == 10 && loaded.all? { |f| File.realpath(f).start_with?(root + "/") }, "ordinary installed entry")
package = JSON.parse(File.read(ARGV.fetch(2)))
need(loaded.all? { |f| rel=File.realpath(f).delete_prefix(root+"/"); Digest::SHA256.file(f).hexdigest == package.fetch("files_sha256").fetch(rel) }, "installed source identity")
input_raw = File.binread(ARGV.fetch(0)); expected_raw = File.binread(ARGV.fetch(1))
need(Digest::SHA256.hexdigest(input_raw) == "41ad845a7ea82a9c7316c9ef11fb8ee5281453afafe2b4932c7217c1936562c1", "public input identity")
need(Digest::SHA256.hexdigest(expected_raw) == "b8de794bc17c1093d070ed0e78a523ffa568c332bce5e89fe5b2503ee8783d7e", "independent expectation identity")
inputs=JSON.parse(input_raw); expected=JSON.parse(expected_raw).fetch("cases")
need(inputs.keys.sort == expected.keys.sort && expected.size==42, "complete42")
rows=[]
expected.each do |name,e|
  args=inputs.fetch(name).to_h { |k,v| [k.to_sym, v.instance_of?(String) ? v.dup : v] }
  r=AP2MandateVerifier.verify_research(**args)
  good=e.fetch("code")=="scoped_research_verified"
  need([r.code.to_s,r.status.to_s,r.success?,r.evidence&.to_h] == [e["code"],good ? "verified_research" : "rejected",good,e["evidence"]], "installed comparison "+name)
  need(r.frozen?, "immutable result")
  if good
    facts=r.evidence.to_h; before=JSON.generate(facts)
    need(deep_frozen(facts) && r.evidence.frozen? && !facts.fetch("verified_challenge").key?("nonce"), "immutable projected evidence")
    args.each_value { |v| v.replace("changed") if v.instance_of?(String) }
    need(JSON.generate(facts)==before && r.evidence.dup.equal?(r.evidence), "input mutation changed Evidence")
  else
    need(r.evidence.nil?, "failure Evidence")
  end
  rows << {name:name,code:r.code,result:"MATCH"}
end
full=inputs.fetch("FULL");host=JSON.parse(full.fetch("host_json"));binding=host.fetch("binding")
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
puts JSON.pretty_generate(scope:"INSTALLED_PRERELEASE_MBA_ONLY_NOT_HOST_ALLOW",candidate_version:spec.version.to_s,
 ruby:RUBY_VERSION,ruby_platform:RUBY_PLATFORM,dependencies:versions,openssl_default:Gem.loaded_specs.fetch("openssl").default_gem?,
 digest_default:Gem.loaded_specs.fetch("digest").default_gem?,libcrypto:OpenSSL::OPENSSL_LIBRARY_VERSION,installed_lib_files:loaded.size,ordinary_entry:true,
 independent_research_comparisons:rows,legacy_api_checks:legacy.size,input_rejections:2,constructor_rejections:1,total_cases:52,
 holds:"production/distribution/Phase2B/Hostatomic/Stage16; old acquisition gaps and Linuxalltraffic unproved")
