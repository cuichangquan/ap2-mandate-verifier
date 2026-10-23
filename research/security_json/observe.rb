# frozen_string_literal: true
# Trusted local harness; loaded source is captured and pinned by compare.py.
ENV["BUNDLE_GEMFILE"] = File.expand_path("../../Gemfile", __dir__)
ENV["BUNDLE_FROZEN"] = "true"
ENV["BUNDLE_IGNORE_CONFIG"] = "true"
ENV["BUNDLE_DISABLE_VERSION_CHECK"] = "true"
require "bundler/setup"
require "json"
require "jwt"
require "digest"
require_relative "../../lib/ap2_mandate_verifier"
def frozen_tree(v)
  v.frozen? && case v
  when Hash then v.all? { |k, x| frozen_tree(k) && frozen_tree(x) }
  when Array then v.all? { |x| frozen_tree(x) }
  else true
  end
end
data = STDIN.read(2_097_153)
raise "observer input cap" if data.bytesize > 2_097_152
request = JSON.parse(data)
args = request.fetch("args").transform_keys(&:to_sym)
entries = []
labels = {
  [AP2MandateVerifier::TrustContext.singleton_class, :verified_context!] => "trust",
  [AP2MandateVerifier::RootSignature.singleton_class, :verified_payload!] => "signature",
  [AP2MandateVerifier::RootDisclosures.singleton_class, :verified_root!] => "root_graph",
  [AP2MandateVerifier::PurchaseBinding.singleton_class, :verified_details!] => "purchase",
  [AP2MandateVerifier::ScopedConstraints.singleton_class, :verified_constraints!] => "constraints"
}
trace = TracePoint.new(:call) { |e| label = labels[[e.defined_class, e.method_id]]; entries << label if label }
result = trace.enable { AP2MandateVerifier.verify_research(**args) }
facts = result.evidence&.to_h
stable = true
if facts
  before = JSON.generate(facts)
  args.each_value { |v| v.replace("changed") if v.instance_of?(String) }
  stable = JSON.generate(facts) == before
end
spec = Gem.loaded_specs.fetch("json")
loaded = $LOADED_FEATURES.select { |f| f.start_with?(spec.full_gem_path + "/") }
runtime = {ruby: RUBY_VERSION, json: JSON::VERSION, json_gem_version: spec.version.to_s,
  jwt: JWT::VERSION::STRING, base64: Gem.loaded_specs.fetch("base64").version.to_s,
  openssl: Gem.loaded_specs.fetch("openssl").version.to_s, bundler: Bundler::VERSION,
  resolved_gems: Bundler.locked_gems.specs.to_h { |s| [s.name, s.version.to_s] },
  json_files_sha256: loaded.sort.to_h { |f| [f.delete_prefix(spec.full_gem_path + "/"), Digest::SHA256.file(f).hexdigest] }}
puts JSON.generate(status: result.status, code: result.code, success: result.success?, evidence: facts,
  deeply_frozen: facts ? frozen_tree(facts) : nil, stable_after_input_mutation: stable,
  entries: entries, runtime: runtime)
