# frozen_string_literal: true

# Fail before fixtures execute if the already-installed baseline is unavailable.
# This script never installs dependencies or establishes native-provider identity.
abort "MRI 4.0.9 required; no dependency acquisition" unless RUBY_ENGINE == "ruby" && RUBY_VERSION == "4.0.9"
{"json" => "2.19.9", "jwt" => "3.3.0", "openssl" => "4.0.2",
 "base64" => "0.3.0", "digest" => "3.2.1"}.each { |name, version| gem name, "= #{version}" }

# These standalone suites execute on require; do not count them as new cases.
require_relative "research_evidence_test"

module VerifyCheckoutTest
  INPUTS = %i[trust_json selection_json host_json root_presentation terminal_jws host_checkout_jws verified_at].freeze
  ENTRIES = %i[verify_checkout verify_research].freeze
  @count = 0

  def self.assert(value, label)
    raise "verify_checkout: #{label}" unless value
  end

  def self.result_contract(result, status, code, label)
    assert(result.status == status && result.code == code, "#{label}: status/code")
    assert(result.success? == (status == :verified_research), "#{label}: success")
    assert(result.rejected? == (status == :rejected), "#{label}: rejected")
    assert(result.unverified? == (status == :unverified), "#{label}: unverified")
    assert(result.unavailable? == (status == :unavailable), "#{label}: unavailable")
    expected_class = status == :verified_research ? AP2MandateVerifier::ResearchResult : AP2MandateVerifier::Result
    assert(result.instance_of?(expected_class) && result.frozen?, "#{label}: result type/freeze")
    assert(result.evidence.nil?, "#{label}: no Evidence") unless result.success?
  end

  def self.compare(inputs, status, code, label, model: nil, interval: nil)
    outputs = ENTRIES.map do |entry|
      creations = 0
      trace = TracePoint.new(:call) do |event|
        creations += 1 if event.defined_class == AP2MandateVerifier::ResearchEvidence && event.method_id == :initialize
      end
      result = trace.enable { AP2MandateVerifier.public_send(entry, **inputs) }
      result_contract(result, status, code, "#{label}/#{entry}")
      assert(creations == (status == :verified_research ? 1 : 0), "#{label}: Evidence construction")
      if result.success?
        ResearchEvidenceTest.normal(model, result)
        assert([result.evidence["valid_from"], result.evidence["valid_until"]] == interval, "#{label}: interval") if interval
      end
      result
    end
    assert(outputs[0].evidence&.to_h == outputs[1].evidence&.to_h, "#{label}: Evidence equality")
    @count += 1
    outputs.first
  end

  def self.expect_exception(klass, label)
    begin
      yield
    rescue klass
      @count += 1
      return
    end
    raise "verify_checkout: expected #{klass} for #{label}"
  end

  # Reuse contract-authored expected codes/intervals, not just new/old parity.
  # This is API regression reuse, not a new independent AP2 conformance oracle.
  HostBindingTest.recorded_cases.each do |name, model, code, interval|
    success = code == :host_binding_verified_only
    compare(HostBindingTest.args(model), success ? :verified_research : :rejected,
      success ? :scoped_research_verified : code, name, model: model, interval: interval)
  end

  model = HostBindingTest.fixture
  input = HostBindingTest.args(model)
  assert(input.keys.sort == INPUTS.sort, "exact seven fixture inputs")
  INPUTS.each do |missing|
    compare(input.reject { |key, _| key == missing }, :unavailable, :research_verification_unavailable, "missing #{missing}")
  end
  [{}, input.merge(unknown: true), input.merge(presentation_json: "{}"),
   {presentation_json: "{}"}, input.merge(evidence: {}),
   input.reject { |key, _| key == :host_json }.merge(unknown: true),
   input.transform_keys(&:to_s)].each_with_index do |bad, index|
    compare(bad, :unavailable, :research_verification_unavailable, "keyword boundary #{index}")
  end
  (INPUTS - [:verified_at]).each do |key|
    compare(input.merge(key => nil), :rejected, :invalid_input_type, "nil #{key}")
  end
  compare(input.merge(verified_at: "1800000000"), :rejected, :invalid_host_context, "no time coercion")
  compare(input.merge(host_json: '{"binding":{},"binding":{}}'), :rejected, :duplicate_key, "duplicate Host JSON")
  compare(input.merge(host_json: "x" * 32_769), :rejected, :input_too_large, "Host byte cap")

  # Keyword errors are caught inside the existing factory; invocation errors
  # before entry are not promised to produce Result or any authorization.
  ENTRIES.each do |entry|
    expect_exception(ArgumentError, "#{entry} positional") { AP2MandateVerifier.public_send(entry, input) }
    expect_exception(TypeError, "#{entry} keyword expansion") { AP2MandateVerifier.public_send(entry, **1) }
  end

  # Verify unchanged forwarding and returned object identity independently of
  # pipeline outcomes. The unknown keyword must reach the factory, not disappear.
  factory = AP2MandateVerifier::ResearchResult
  original = factory.method(:verify)
  forwarded = input.merge(unknown: Object.new)
  sentinel = AP2MandateVerifier::Result.new(status: :unavailable, code: :research_verification_unavailable)
  observed = nil
  factory.define_singleton_method(:verify) { |**kwargs| observed = kwargs; sentinel }
  begin
    assert(AP2MandateVerifier.verify_checkout(**forwarded).equal?(sentinel), "factory result identity")
    assert(observed.keys == forwarded.keys && forwarded.all? { |key, value| observed[key].equal?(value) }, "no argument transformation")
    @count += 1
  ensure
    factory.define_singleton_method(:verify, original)
  end

  # Exercise existing dependency/internal failure mappings through both entries.
  target = AP2MandateVerifier::HostBinding
  original = target.method(:verified_binding!)
  [[AP2MandateVerifier::InputValidator::Unavailable.new(:json_dependency_unavailable), :json_dependency_unavailable],
   [AP2MandateVerifier::RootSignature::Unavailable.new(:signature_dependency_unavailable), :signature_dependency_unavailable],
   [LoadError.new("controlled dependency failure"), :signature_dependency_unavailable],
   [RuntimeError.new("controlled internal failure"), :research_verification_unavailable],
   [AP2MandateVerifier::RootSignature::Rejected.new(:unregistered_failure), :research_verification_unavailable]].each do |failure, code|
    target.define_singleton_method(:verified_binding!) { |**_| raise failure }
    begin
      compare(input, :unavailable, code, "controlled failure #{failure.class}/#{code}")
    ensure
      target.define_singleton_method(:verified_binding!, original)
    end
  end

  # Both entries must capture the same originals even if caller strings mutate
  # during key checking; each entry receives fresh mutable input strings.
  ENTRIES.each do |entry|
    mutable = HostBindingTest.args(HostBindingTest.copy(model))
    original = AP2MandateVerifier::RootSignature.method(:public_jwk!)
    AP2MandateVerifier::RootSignature.define_singleton_method(:public_jwk!) do |pem|
      mutable.each_value { |value| value.replace("changed") if value.instance_of?(String) }
      original.call(pem)
    end
    begin
      result = AP2MandateVerifier.public_send(entry, **mutable)
      ResearchEvidenceTest.normal(model, result)
      assert(mutable[:host_json] == "changed", "#{entry}: mutation control")
      @count += 1
    ensure
      AP2MandateVerifier::RootSignature.define_singleton_method(:public_jwk!, original)
    end
  end

  mutable = HostBindingTest.args(HostBindingTest.copy(model))
  result = compare(mutable, :verified_research, :scoped_research_verified, "immutable Evidence", model: model,
    interval: [HostBindingTest::N, HostBindingTest::N + 301])
  before = JSON.generate(result.evidence.to_h)
  mutable.each_value { |value| value.replace("changed") if value.instance_of?(String) }
  assert(JSON.generate(result.evidence.to_h) == before, "post-return input mutation")
  evidence = result.evidence
  expect_exception(FrozenError, "result mutation") { result.instance_variable_set(:@evidence, {}) }
  expect_exception(FrozenError, "Evidence hash") { evidence.to_h["verified_at"] = 0 }
  expect_exception(FrozenError, "nested buyer") { evidence["checkout_binding"]["buyer_account_id"].replace("other") }
  expect_exception(FrozenError, "selected keys") { evidence["selected_keys"].clear }
  expect_exception(FrozenError, "scope") { evidence["verified_scope"] << "Host_ALLOW" }
  assert(!evidence["verified_challenge"].key?("nonce"), "nonce privacy")

  # The original verify remains JSON syntax only, never the checkout alias.
  result_contract(AP2MandateVerifier.verify(presentation_json: "{}"), :unverified, :verification_not_implemented, "legacy JSON")
  result_contract(AP2MandateVerifier.verify(presentation_json: "{"), :rejected, :invalid_json, "legacy bad JSON")
  result_contract(AP2MandateVerifier.verify_host_binding(**input), :unverified, :host_binding_verified_only, "legacy Host")
  @count += 3

  puts "PASS #{@count} checkout API cases; reused Host/Evidence suites reported separately; not Host ALLOW"
end
