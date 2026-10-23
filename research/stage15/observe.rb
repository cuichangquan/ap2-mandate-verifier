# frozen_string_literal: true
# Trusted local harness; loaded source is captured and pinned by compare.py.
require "json"
require "jwt"
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
puts JSON.generate(status: result.status, code: result.code, success: result.success?, evidence: facts,
  deeply_frozen: facts ? frozen_tree(facts) : nil, stable_after_input_mutation: stable,
  entries: entries, runtime: {ruby: RUBY_VERSION, json: JSON::VERSION, jwt: JWT::VERSION::STRING})
