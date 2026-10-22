# frozen_string_literal: true
require_relative "host_binding_test" unless defined?(HostBindingTest)

module ResearchEvidenceTest
  @count = 0
  def self.assert(value) = (raise "research evidence assertion" unless value)
  def self.expect_exception(klass)
    begin
      yield
    rescue klass
      @count += 1
      return
    end
    raise "expected #{klass}"
  end
  def self.deep_frozen(value)
    return false unless value.frozen?
    case value
    when Hash then value.all? { |key, child| deep_frozen(key) && deep_frozen(child) }
    when Array then value.all? { |child| deep_frozen(child) }
    else true
    end
  end
  def self.normal(model, result)
    assert(result.instance_of?(AP2MandateVerifier::ResearchResult) && result.success? &&
      result.status == :verified_research && result.code == :scoped_research_verified)
    evidence = result.evidence
    assert(evidence.instance_of?(AP2MandateVerifier::ResearchEvidence))
    values = evidence.to_h
    assert(values.keys.sort == %w[contract_version implementation_revision revision_kind verified_scope
      profile_ref profile_version profile_definition_hash verified_at clock_source_id valid_from valid_until
      trust_snapshot selected_keys checkout_binding verified_challenge root_presentation_digest checkout_jwt_digest terminal_digest].sort)
    assert(values["contract_version"] == "ap2.research-evidence.2" && values["implementation_revision"] == "ap2.research-verifier.2" &&
      values["revision_kind"] == "static_identifier_not_runtime_attestation" && !values.key?("verifier_code_sha"))
    host = model[:host]; snapshot = JSON.parse(model[:trust]["snapshot"]["body"])
    assert(values["checkout_binding"] == host["binding"] && values["verified_challenge"] == host["challenge"].reject { |field, _| field == "nonce" }.merge("verified_nonce_sha256" => Digest::SHA256.hexdigest(host["challenge"]["nonce"])))
    assert(values["trust_snapshot"] == model[:trust]["snapshot"].slice("id", "policy_version", "content_hash"))
    assert(values["profile_ref"] == AP2MandateVerifier::TrustContext::PROFILE_REF &&
      values["profile_version"] == AP2MandateVerifier::TrustContext::PROFILE_VERSION &&
      values["profile_definition_hash"] == AP2MandateVerifier::TrustContext::PROFILE_HASH)
    assert(values["selected_keys"] == snapshot["records"].map { |r| r.reject { |field, _| field == "public_key_pem" } })
    assert(values["selected_keys"].map { |r| r["role"] } == %w[Issuer Agent Merchant])
    %w[root_presentation_digest checkout_jwt_digest terminal_digest].zip(%i[root_presentation host_checkout_jws terminal_jws]).each do |field, input|
      assert(values[field] == Digest::SHA256.hexdigest(model[:inputs][input]))
    end
    assert(values["verified_at"] == model[:inputs][:verified_at] && values["clock_source_id"] == host["clock_source_id"])
    assert(values["valid_from"] <= values["verified_at"] && values["verified_at"] < values["valid_until"])
    assert(values["verified_scope"] == %w[strict_inputs host_trust_profile_input_checks issuer_root_signature
      original_root_graph_closure agent_key_confirmation agent_terminal_signature closed_original_checkout_binding
      merchant_checkout_signature fixed_subset_schema_constraints host_challenge_order_binding validity_intersection])
    assert(deep_frozen(result) && deep_frozen(values) && evidence.frozen?)
    assert(result.dup.equal?(result) && result.clone(freeze: false).equal?(result) &&
      evidence.dup.equal?(evidence) && evidence.clone(freeze: false).equal?(evidence))
  end
  # Re-input the original contract-authored Host cases through the NEW entry.
  # This is regression reuse, not the independent Stage15 oracle.
  HostBindingTest.recorded_cases.each do |name, model, code, interval|
    creations = 0
    trace = TracePoint.new(:call) { |e| creations += 1 if e.defined_class == AP2MandateVerifier::ResearchEvidence && e.method_id == :initialize }
    result = trace.enable { AP2MandateVerifier.verify_research(**HostBindingTest.args(model)) }
    if code == :host_binding_verified_only
      normal(model, result)
      assert(creations == 1)
      assert([result.evidence["valid_from"], result.evidence["valid_until"]] == interval) if interval
    else
      assert(result.code == code && !result.success? && result.evidence.nil? && creations == 0)
    end
    @count += 1
  end
  model = HostBindingTest.fixture
  input = HostBindingTest.args(HostBindingTest.copy(model))
  result = AP2MandateVerifier.verify_research(**input)
  before = JSON.generate(result.evidence.to_h)
  input.each_value { |value| value.replace("changed") if value.instance_of?(String) }
  assert(JSON.generate(result.evidence.to_h) == before)
  @count += 1
  evidence = result.evidence
  expect_exception(FrozenError) { result.instance_variable_set(:@evidence, {}) }
  expect_exception(FrozenError) { evidence.instance_variable_set(:@data, {}) }
  expect_exception(FrozenError) { evidence.to_h["verified_at"] = 0 }
  expect_exception(FrozenError) { evidence["checkout_binding"]["buyer_account_id"].replace("other") }
  expect_exception(FrozenError) { evidence["verified_challenge"]["B"]["expected_total"] = 0 }
  expect_exception(FrozenError) { evidence["selected_keys"].clear }
  expect_exception(FrozenError) { evidence["selected_keys"][0]["key_fingerprint"].replace("0" * 64) }
  expect_exception(FrozenError) { evidence["verified_scope"] << "Host_ALLOW" }
  expect_exception(NoMethodError) { AP2MandateVerifier::ResearchEvidence.new({}) }
  expect_exception(NoMethodError) { AP2MandateVerifier::ResearchEvidence.allocate }
  expect_exception(NoMethodError) { AP2MandateVerifier::ResearchResult.new(evidence) }
  expect_exception(NoMethodError) { AP2MandateVerifier::ResearchResult.allocate }
  expect_exception(ArgumentError) { AP2MandateVerifier::Result.new(status: :verified_research, code: :scoped_research_verified) }
  expect_exception(ArgumentError) { AP2MandateVerifier::Result.new(status: :unverified, code: :host_binding_verified_only, evidence: evidence) }
  decoded = JSON.parse(JSON.generate(evidence.to_h))
  assert(decoded.instance_of?(Hash) && !decoded.instance_of?(AP2MandateVerifier::ResearchEvidence))
  injected = AP2MandateVerifier.verify_research(**HostBindingTest.args(model).merge(evidence: decoded))
  assert(!injected.success? && injected.evidence.nil? && injected.code == :research_verification_unavailable)
  @count += 1
  # Legacy entry never mints Evidence, despite normal complete inputs.
  legacy = AP2MandateVerifier.verify_host_binding(**HostBindingTest.args(model))
  assert(!legacy.success? && legacy.evidence.nil? && legacy.code == :host_binding_verified_only)
  @count += 1
  # All original caller-owned strings can change during key checking; checked
  # captures and Evidence must still represent the originals, not later copies.
  input = HostBindingTest.args(HostBindingTest.copy(model)); expected = HostBindingTest.copy(model)
  original = AP2MandateVerifier::RootSignature.method(:public_jwk!)
  AP2MandateVerifier::RootSignature.define_singleton_method(:public_jwk!) do |pem|
    input.each_value { |value| value.replace("changed") if value.instance_of?(String) }
    original.call(pem)
  end
  begin
    captured = AP2MandateVerifier.verify_research(**input)
    normal(expected, captured)
    assert(input[:host_json] == "changed")
    @count += 1
  ensure
    AP2MandateVerifier::RootSignature.define_singleton_method(:public_jwk!, original)
  end
  # Failure at ANY earlier dependency/internal stage must never create output.
  failure_targets = [[AP2MandateVerifier::TrustContext, :verified_context!],
    [AP2MandateVerifier::RootDisclosures, :verified_root!],
    [AP2MandateVerifier::PurchaseBinding, :verified_details!],
    [AP2MandateVerifier::ScopedConstraints, :verified_constraints!]]
  failure_targets.each do |target, method|
    original = target.method(method)
    target.define_singleton_method(method) { |*args, **kwargs| raise "controlled internal failure" }
    begin
      result = AP2MandateVerifier.verify_research(**HostBindingTest.args(model))
      assert(!result.success? && result.evidence.nil? && result.unavailable? && result.code == :research_verification_unavailable)
      @count += 1
    ensure
      target.define_singleton_method(method, original)
    end
  end
  original = AP2MandateVerifier::HostBinding.method(:verified_binding!)
  [AP2MandateVerifier::RootSignature::Unavailable.new(:signature_dependency_unavailable),
   AP2MandateVerifier::RootSignature::Rejected.new(:unregistered_failure), LoadError.new("controlled")].each do |failure|
    AP2MandateVerifier::HostBinding.define_singleton_method(:verified_binding!) { |**_| raise failure }
    begin
      result = AP2MandateVerifier.verify_research(**HostBindingTest.args(model))
      assert(!result.success? && result.evidence.nil? && result.unavailable?)
      @count += 1
    ensure
      AP2MandateVerifier::HostBinding.define_singleton_method(:verified_binding!, original)
    end
  end
  original = AP2MandateVerifier::ResearchEvidence.method(:copy_frozen)
  AP2MandateVerifier::ResearchEvidence.define_singleton_method(:copy_frozen) { |_| raise "controlled construction failure" }
  begin
    result = AP2MandateVerifier.verify_research(**HostBindingTest.args(model))
    assert(!result.success? && result.evidence.nil? && result.code == :research_verification_unavailable)
    @count += 1
  ensure
    AP2MandateVerifier::ResearchEvidence.define_singleton_method(:copy_frozen, original)
    AP2MandateVerifier::ResearchEvidence.private_class_method(:copy_frozen)
  end

  ["PRIVACY_NONCE_SENTINEL_14B_9f4d", "nonce-多言語"].each do |nonce|
    model = HostBindingTest.fixture(nonce: nonce)
    output = AP2MandateVerifier.verify_research(**HostBindingTest.args(model))
    normal(model, output)
    challenge = output.evidence["verified_challenge"]
    assert(challenge["verified_nonce_sha256"] == Digest::SHA256.hexdigest(nonce) && !challenge.key?("nonce"))
    assert(!output.evidence.to_h.inspect.include?(nonce) && !JSON.generate(output.evidence.to_h).include?(nonce))
    @count += 1
    expect_exception(FrozenError) { challenge["verified_nonce_sha256"].replace("0" * 64) }
    model[:host]["challenge"]["nonce"] = "different-signed-nonce"
    rejected = AP2MandateVerifier.verify_research(**HostBindingTest.args(model))
    assert(!rejected.success? && rejected.evidence.nil? && rejected.code == :nonce_mismatch)
    @count += 1
  end
  puts "PASS #{@count} unified research/Evidence cases; immutable in-process facts, not Host ALLOW"
end
