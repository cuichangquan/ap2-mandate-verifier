# frozen_string_literal: true
require_relative "host_binding_test"

# Expected verdicts and signed wires come from the pre-existing Host contract,
# not from this builder. The fixture suites above report their own case counts.
module InputBuilderTest
  B = AP2MandateVerifier::InputBuilder
  T = AP2MandateVerifier::TrustContext
  @count = 0
  def self.assert(ok, label)
    raise "input builder: #{label}" unless ok
  end
  def self.invalid(label)
    begin
      yield
    rescue B::Invalid
      @count += 1
      return
    end
    raise "input builder accepted #{label}"
  end
  def self.copy(x) = HostBindingTest.copy(x)
  def self.business(model)
    snapshot = JSON.parse(model[:trust]["snapshot"]["body"])
    snapshot["records"].each do |record|
      %w[profile_ref profile_version algorithm key_fingerprint].each { |field| record.delete(field) }
    end
    {snapshot: snapshot, tenant_id: model[:selection]["tenant_id"],
     issuer: copy(model[:selection]["Issuer"]), agent: copy(model[:selection]["Agent"]),
     merchant: copy(model[:selection]["Merchant"]), verified_at: model[:inputs][:verified_at]}
  end
  def self.order(model)
    model[:host]["binding"].slice("tenant_id", "buyer_account_id", "order_id", "merchant_id",
      "audience", "order_version", "currency", "expected_total")
  end
  def self.setup(model)
    trust = B.trust(**business(model))
    challenge = model[:host]["challenge"]
    saved = B.prepare(trust: trust, order: order(model),
      root_presentation: model[:inputs][:root_presentation], host_checkout_jws: model[:inputs][:host_checkout_jws],
      **challenge.slice("challenge_id", "nonce", "issuer_id", "not_before", "not_after").transform_keys(&:to_sym))
    {trust: trust, saved_challenge: saved, order: order(model), **model[:inputs],
     expected_challenge_issuer_id: model[:host]["expected_challenge_issuer_id"],
     clock_source_id: model[:host]["clock_source_id"]}
  end
  def self.result(args, code, label)
    r = B.verify(**args)
    success = code == :scoped_research_verified
    assert(r.code == code && r.success? == success, "#{label} verdict #{r.code}")
    assert(r.evidence.nil?, "#{label} no Evidence") unless success
    @count += 1
    r
  end
  def self.failure(args, status, code, label)
    r = B.verify(**args)
    assert(r.instance_of?(AP2MandateVerifier::Result) && r.frozen?, "#{label} immutable non-success Result")
    assert([r.status, r.code, r.success?, r.evidence] == [status, code, false, nil], "#{label} #{r.status}/#{r.code}")
    assert(r.rejected? == (status == :rejected) && r.unavailable? == (status == :unavailable) && !r.unverified?, "#{label} flags")
    @count += 1
  end
  def self.typed_failure(klass, code, label)
    begin
      yield
    rescue klass => error
      assert(error.code == code, "#{label} typed failure code") if code
      @count += 1
      return
    end
    raise "input builder expected #{klass} for #{label}"
  end

  model = HostBindingTest.fixture
  args = setup(model)
  assembled = B.inputs(**args)
  assert(assembled.keys.sort == HostBindingTest.args(model).keys.sort, "seven input names")
  %i[root_presentation terminal_jws host_checkout_jws verified_at].each do |name|
    assert(assembled[name] == model[:inputs][name], "original #{name}")
  end
  r = result(args, :scoped_research_verified, "normal")
  old = AP2MandateVerifier.verify_checkout(**assembled)
  assert(r.evidence.to_h == old.evidence.to_h, "complete core Evidence equality")
  # B is specified independently by the old fixture, including exact-wire SHA256.
  assert(r.evidence["checkout_binding"] == model[:host]["binding"], "independent binding oracle")
  assert(r.evidence["contract_version"] == "ap2.research-evidence.2", "unchanged Evidence version")
  assert(r.evidence["valid_until"] == HostBindingTest::N + 301, "independent validity oracle")
  assert(B.restore(saved_challenge: args[:saved_challenge]) == args[:saved_challenge], "restore preserves bytes")
  @count += 1

  # Every current business binding differs from issued B and must stay visible.
  order(model).each_key do |field|
    changed = copy(args[:order]); changed[field] = field == "expected_total" ? 201 : field == "currency" ? "EUR" : "other"
    result(args.merge(order: changed), :host_binding_mismatch, "current #{field} drift")
  end
  shorter = JSON.parse(args[:saved_challenge]); shorter["challenge"]["not_after"] = HostBindingTest::N + 100
  result(args.merge(saved_challenge: JSON.generate(shorter), verified_at: HostBindingTest::N + 100), :challenge_time_mismatch, "expired challenge")
  result(args.merge(expected_challenge_issuer_id: "other"), :host_binding_mismatch, "issuer drift")
  changed = business(model); changed[:snapshot]["policy_version"] = "policy-2"
  result(args.merge(trust: B.trust(**changed)), :challenge_reference_mismatch, "current policy drift")
  changed = business(model); changed[:snapshot]["records"][1]["active"] = false
  invalid("inactive selected key") { B.trust(**changed) }
  changed = business(model); changed[:snapshot]["records"] << copy(changed[:snapshot]["records"][0])
  invalid("ambiguous selected key") { B.trust(**changed) }
  changed[:snapshot]["records"].last["active"] = false
  invalid("ambiguous inactive selected key") { B.trust(**changed) }
  changed = business(model); retired = copy(changed[:snapshot]["records"][0]); retired["key_ref"] = "retired"; retired["public_key_pem"] = "bad"
  changed[:snapshot]["records"] << retired
  invalid("invalid unselected key is not filtered") { B.trust(**changed) }

  tampered = copy(model[:inputs][:terminal_jws]); parts = tampered.split(".")
  raw = Base64.urlsafe_decode64(parts[2]); raw.setbyte(0, raw.getbyte(0) ^ 1)
  result(args.merge(terminal_jws: [parts[0], parts[1], HostBindingTest.b64(raw)].join(".")), :invalid_root_signature, "signature tamper")
  # Altering received originals must not update the issued digests.
  result(args.merge(root_presentation: model[:inputs][:root_presentation] + "~"), :host_binding_mismatch, "Root original changed")
  result(args.merge(host_checkout_jws: model[:inputs][:host_checkout_jws] + " "), :host_binding_mismatch, "Checkout original changed")

  invalid("unknown business field") { B.trust(**business(model).tap { |x| x[:snapshot]["future"] = true }) }
  invalid("fingerprint override") { B.trust(**business(model).tap { |x| x[:snapshot]["records"][0]["key_fingerprint"] = "0" * 64 }) }
  invalid("missing business field") { B.trust(**business(model).tap { |x| x[:snapshot].delete("id") }) }
  invalid("wrong business type") { B.trust(**business(model).merge(snapshot: [])) }
  invalid("Hash subclass") { B.trust(**business(model).merge(snapshot: Class.new(Hash).new)) }
  invalid("Array subclass") { B.trust(**business(model).tap { |x| x[:snapshot]["records"] = Class.new(Array).new }) }
  invalid("String subclass") { B.trust(**business(model).tap { |x| x[:snapshot]["id"] = Class.new(String).new("snapshot") }) }
  invalid("coercible object") { B.trust(**business(model).tap { |x| x[:snapshot]["id"] = Object.new.tap { |o| def o.to_s = "snapshot" } }) }
  invalid("singleton Hash callback") { B.trust(**business(model).tap { |x| x[:snapshot].define_singleton_method(:to_json) { |*| raise "callback invoked" } }) }
  invalid("string/symbol key collision") { B.trust(**business(model).tap { |x| x[:snapshot][:id] = "snapshot" }) }
  invalid("non-string key") { B.trust(**business(model).tap { |x| x[:snapshot][1] = "x" }) }
  invalid("cyclic Hash") { B.trust(**business(model).tap { |x| x[:snapshot]["cycle"] = x[:snapshot] }) }
  invalid("cyclic Array") { B.trust(**business(model).tap { |x| x[:snapshot]["records"] << x[:snapshot]["records"] }) }
  invalid("oversize String") { B.trust(**business(model).tap { |x| x[:snapshot]["id"] = "x" * 131_073 }) }
  invalid("too many records") { B.trust(**business(model).tap { |x| x[:snapshot]["records"] *= 6 }) }
  deep = []; 30.times { deep = [deep] }
  invalid("excess depth before serialization") { B.trust(**business(model).tap { |x| x[:snapshot]["future"] = deep }) }
  invalid("invalid UTF8") { B.trust(**business(model).tap { |x| x[:snapshot]["id"] = "\xff".b }) }
  invalid("Float clock") { B.trust(**business(model).merge(verified_at: HostBindingTest::N.to_f)) }
  invalid("unbounded Integer before serialization") { B.trust(**business(model).tap { |x| x[:snapshot]["not_after"] = 1 << 100_000 }) }
  duplicate_keys = business(model)
  duplicate_keys[:snapshot] = duplicate_keys[:snapshot].dup.compare_by_identity
  duplicate_keys[:snapshot][String.new("id")] = "shadow"
  invalid("identity Hash duplicate equal Strings") { B.trust(**duplicate_keys) }

  # These mutations apply to an independently prepared persisted envelope. No
  # rescue path is allowed to repair its version, references, B or checksum.
  invalid("malformed saved JSON") { B.restore(saved_challenge: "{") }
  invalid("duplicate saved fields") { B.restore(saved_challenge: args[:saved_challenge].sub("{", '{"version":"unknown","version":"unknown",')) }
  invalid("oversize saved JSON") { B.restore(saved_challenge: " " * 131_073) }
  invalid("saved String subclass") { B.restore(saved_challenge: Class.new(String).new(args[:saved_challenge])) }
  %w[format_version profile_ref profile_version].each do |field|
    bad = JSON.parse(args[:saved_challenge]); bad[field] = "future"
    invalid("unknown saved #{field}") { B.restore(saved_challenge: JSON.generate(bad)) }
  end
  bad = JSON.parse(args[:saved_challenge]); bad["challenge"]["B"]["profile_version"] = "2"
  invalid("unknown saved binding profile") { B.restore(saved_challenge: JSON.generate(bad)) }
  # Valid-shaped persisted differences must survive restoration and reach the
  # old verifier, rather than being replaced with today's generated values.
  {"trust_content_hash" => :challenge_reference_mismatch, "profile_definition_hash" => :challenge_reference_mismatch,
   "policy_version" => :challenge_reference_mismatch, "trust_snapshot_id" => :challenge_reference_mismatch,
   "state" => :challenge_state_mismatch}.each do |field, code|
    bad = JSON.parse(args[:saved_challenge]); bad["challenge"][field] = field.include?("hash") ? "0" * 64 : field == "state" ? "consumed" : "other"
    raw = JSON.generate(bad)
    assert(B.restore(saved_challenge: raw) == raw, "preserve stored #{field}")
    result(args.merge(saved_challenge: raw), code, "stored #{field} differs")
  end
  bad = JSON.parse(args[:saved_challenge]); bad["challenge"]["B"]["expected_total"] = 201
  raw = JSON.generate(bad)
  assert(B.restore(saved_challenge: raw) == raw, "preserve issued B")
  result(args.merge(saved_challenge: raw), :host_binding_mismatch, "issued B differs")

  # Retain wire whitespace exactly, including noncanonical saved envelope JSON.
  raw = " \n" + args[:saved_challenge] + "\t"
  assert(B.restore(saved_challenge: raw) == raw, "saved original whitespace")
  result(args.merge(saved_challenge: raw), :scoped_research_verified, "saved whitespace")

  # Replay original signed public wires against a saved independent oracle.
  # Building a new snapshot changes its original-wire content hash legitimately;
  # compare every other Evidence field to the pre-existing oracle unchanged.
  base = File.expand_path("..", __dir__)
  public_raw = File.binread(File.join(base, "research/stage15/results/R3/INPUTS.json"))
  expected_raw = File.binread(File.join(base, "research/stage15_linux/EXPECTED.json"))
  assert(Digest::SHA256.hexdigest(public_raw) == "41ad845a7ea82a9c7316c9ef11fb8ee5281453afafe2b4932c7217c1936562c1", "saved public input identity")
  assert(Digest::SHA256.hexdigest(expected_raw) == "b8de794bc17c1093d070ed0e78a523ffa568c332bce5e89fe5b2503ee8783d7e", "saved independent oracle identity")
  public_input = JSON.parse(public_raw).fetch("FULL")
  public_model = {trust: JSON.parse(public_input.fetch("trust_json")), selection: JSON.parse(public_input.fetch("selection_json")),
    host: JSON.parse(public_input.fetch("host_json")), inputs: public_input.reject { |key, _| %w[trust_json selection_json host_json].include?(key) }.transform_keys(&:to_sym)}
  observed = copy(result(setup(public_model), :scoped_research_verified, "saved independent FULL").evidence.to_h)
  expected = JSON.parse(expected_raw).fetch("cases").fetch("FULL").fetch("evidence")
  [observed, expected].each do |facts|
    facts["trust_snapshot"].delete("content_hash")
    facts["verified_challenge"].delete("trust_content_hash")
  end
  assert(observed == expected, "independent saved Evidence except newly created snapshot hash")

  # Existing authenticated registries may contain a noncanonical snapshot body;
  # exact original Strings and their matching hashes remain authoritative.
  restored = B.restore_trust(trust_json: public_input.fetch("trust_json"), selection_json: public_input.fetch("selection_json"), verified_at: public_input.fetch("verified_at"))
  assert(restored.trust_json == public_input["trust_json"] && restored.selection_json == public_input["selection_json"], "restore trust exact bytes")
  @count += 1
  trust_value = JSON.parse(public_input.fetch("trust_json")); selected = JSON.parse(public_input.fetch("selection_json"))
  trust_value["snapshot"]["body"] += " \n"
  raw_trust = JSON.generate(trust_value)
  invalid("snapshot trailing bytes without new hash") { B.restore_trust(trust_json: raw_trust, selection_json: public_input["selection_json"], verified_at: public_input["verified_at"]) }
  hash = Digest::SHA256.hexdigest(trust_value["snapshot"]["body"])
  trust_value["snapshot"]["content_hash"] = selected["trust_content_hash"] = hash
  raw_trust = JSON.generate(trust_value); raw_selected = JSON.generate(selected)
  restored = B.restore_trust(trust_json: raw_trust, selection_json: raw_selected, verified_at: public_input["verified_at"])
  assert(restored.trust_json == raw_trust && JSON.parse(restored.trust_json)["snapshot"]["body"].end_with?(" \n"), "noncanonical snapshot body stays exact")
  raw_trust.replace("changed"); raw_selected.replace("changed")
  assert(restored.trust_json != raw_trust && restored.selection_json != raw_selected && restored.frozen? && restored.trust_json.frozen?, "restored trust detached immutable")
  @count += 1
  trust_value["profile"]["body"] += " "
  hash = Digest::SHA256.hexdigest(trust_value["profile"]["body"])
  trust_value["profile"]["definition_hash"] = selected["profile_definition_hash"] = hash
  invalid("profile trailing bytes even with matching hash") { B.restore_trust(trust_json: JSON.generate(trust_value), selection_json: JSON.generate(selected), verified_at: public_input["verified_at"]) }
  %w[trust_content_hash trust_snapshot_id policy_version profile_version].each do |field|
    selected = JSON.parse(public_input.fetch("selection_json")); selected[field] = field.include?("hash") ? "0" * 64 : "unknown"
    invalid("restored trust #{field} mismatch") { B.restore_trust(trust_json: public_input["trust_json"], selection_json: JSON.generate(selected), verified_at: public_input["verified_at"]) }
  end

  # Verify rescue branches themselves: helper exceptions cannot prove that the
  # public API returns a registered, immutable non-success Result.
  future_saved = JSON.parse(args[:saved_challenge]); future_saved["format_version"] = "future"
  cyclic_order = copy(args[:order]); cyclic_order["cycle"] = cyclic_order
  malformed_cases = {
    "malformed stored JSON" => args.merge(saved_challenge: "{"),
    "unknown stored version" => args.merge(saved_challenge: JSON.generate(future_saved)),
    "missing order currency" => args.merge(order: args[:order].reject { |key, _| key == "currency" }),
    "unknown order field" => args.merge(order: args[:order].merge("future" => true)),
    "nil order" => args.merge(order: nil),
    "cyclic order" => args.merge(order: cyclic_order),
    "unknown verify keyword" => args.merge(future: true),
    "missing verify keyword" => args.reject { |key, _| key == :terminal_jws },
    "empty verify keywords" => {},
    "nil trust" => args.merge(trust: nil),
    "nonstring saved challenge" => args.merge(saved_challenge: 1),
    "noninteger current clock" => args.merge(verified_at: "1800000000")
  }
  malformed_cases.each do |label, malformed|
    failure(malformed, :rejected, :invalid_host_context, label)
  end

  # Inject at the actual input snapshot dependency, keeping inputs/verify intact.
  validator = AP2MandateVerifier::InputValidator
  original_snapshot = validator.method(:snapshot!)
  [AP2MandateVerifier::InputValidator::Unavailable.new(:json_dependency_unavailable),
   AP2MandateVerifier::RootSignature::Unavailable.new(:signature_dependency_unavailable),
   LoadError.new("controlled missing dependency"), RuntimeError.new("controlled internal fault")].each do |fault|
    reached = false
    validator.define_singleton_method(:snapshot!) do |*_, **_keywords|
      reached = true
      raise fault
    end
    begin
      failure(args, :unavailable, :research_verification_unavailable, "verify rescue #{fault.class}")
      assert(reached, "dependency injection reached actual inputs")
    ensure
      validator.define_singleton_method(:snapshot!, original_snapshot)
    end
  end

  # RootSignature::Unavailable subclasses Rejected. Every pure-conversion
  # rescue must preserve this subtype instead of relabeling provider failure as
  # bad Host data. Inject into actual key processing, not the inputs facade.
  signature = AP2MandateVerifier::RootSignature
  original_key = signature.method(:public_jwk!)
  challenge = model[:host]["challenge"]
  prepare_args = {trust: args[:trust], order: order(model), root_presentation: model[:inputs][:root_presentation],
    host_checkout_jws: model[:inputs][:host_checkout_jws],
    **challenge.slice("challenge_id", "nonce", "issuer_id", "not_before", "not_after").transform_keys(&:to_sym)}
  [AP2MandateVerifier::RootSignature::Unavailable.new(:signature_dependency_unavailable),
   LoadError.new("controlled missing crypto dependency")].each do |fault|
    reached = false
    signature.define_singleton_method(:public_jwk!) { |*| reached = true; raise fault }
    begin
      typed_failure(fault.class, fault.respond_to?(:code) ? fault.code : nil, "trust crypto") { B.trust(**business(model)) }
      typed_failure(fault.class, fault.respond_to?(:code) ? fault.code : nil, "restore trust crypto") do
        B.restore_trust(trust_json: args[:trust].trust_json, selection_json: args[:trust].selection_json, verified_at: HostBindingTest::N)
      end
      typed_failure(fault.class, fault.respond_to?(:code) ? fault.code : nil, "prepare crypto") { B.prepare(**prepare_args) }
      failure(args, :unavailable, :signature_dependency_unavailable, "verify real core crypto #{fault.class}")
      assert(reached, "real crypto dependency path reached")
    ensure
      signature.define_singleton_method(:public_jwk!, original_key)
    end
  end

  original_json_version = JSON::VERSION
  begin
    JSON.send(:remove_const, :VERSION); JSON.const_set(:VERSION, "unsupported-test-version")
    typed_failure(AP2MandateVerifier::InputValidator::Unavailable, :json_dependency_unavailable, "trust JSON dependency mismatch") { B.trust(**business(model)) }
    challenge = model[:host]["challenge"]
    typed_failure(AP2MandateVerifier::InputValidator::Unavailable, :json_dependency_unavailable, "prepare JSON dependency mismatch") do
      B.prepare(trust: args[:trust], order: order(model), root_presentation: model[:inputs][:root_presentation],
        host_checkout_jws: model[:inputs][:host_checkout_jws],
        **challenge.slice("challenge_id", "nonce", "issuer_id", "not_before", "not_after").transform_keys(&:to_sym))
    end
    failure(args, :unavailable, :research_verification_unavailable, "verify JSON dependency mismatch")
  ensure
    JSON.send(:remove_const, :VERSION); JSON.const_set(:VERSION, original_json_version)
  end
  %i[issuer agent merchant].each do |role|
    [nil, false, "selector", [], 1].each do |bad_selector|
      invalid("#{role} selector #{bad_selector.class}") { B.trust(**business(model).merge(role => bad_selector)) }
    end
  end

  mutable_business = business(model)
  captured_trust = B.trust(**mutable_business)
  original_trust = [captured_trust.trust_json.dup, captured_trust.selection_json.dup]
  mutable_business[:snapshot]["records"][0]["public_key_pem"].replace("changed")
  mutable_business[:snapshot]["id"].replace("changed")
  %i[issuer agent merchant].each { |role| mutable_business[role]["identity"].replace("changed") }
  assert([captured_trust.trust_json, captured_trust.selection_json] == original_trust && captured_trust.frozen?, "new trust detached from snapshot/selectors")
  @count += 1

  mutable_prepare = prepare_args.transform_values { |value| value.instance_of?(String) ? value.dup : value }
  mutable_prepare[:order] = copy(prepare_args[:order])
  prepared = B.prepare(**mutable_prepare); original_prepared = prepared.dup
  mutable_prepare.each_value { |value| value.replace("changed") if value.instance_of?(String) }
  mutable_prepare[:order]["expected_total"] = 999
  assert(prepared == original_prepared && prepared.frozen?, "prepared challenge detached from order/wires/nonce/id")
  @count += 1

  mutable_inputs = args.transform_values { |value| value.instance_of?(String) ? value.dup : value }
  mutable_inputs[:order] = copy(args[:order])
  inputs_snapshot = B.inputs(**mutable_inputs)
  before = inputs_snapshot.transform_values { |value| value.instance_of?(String) ? value.dup : value }
  mutable_inputs.each_value { |value| value.replace("changed") if value.instance_of?(String) }
  mutable_inputs[:order]["expected_total"] = 999
  assert(inputs_snapshot == before && inputs_snapshot.frozen? && inputs_snapshot.values.all?(&:frozen?), "seven inputs frozen/detached from caller")
  @count += 1
  puts "PASS #{@count} input builder contract/boundary cases; existing Host suite reported separately; not Host ALLOW"
end
