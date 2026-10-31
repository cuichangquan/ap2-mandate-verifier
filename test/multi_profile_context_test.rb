# frozen_string_literal: true
require_relative "host_binding_test"

# Trust/challenge expectations use the existing independently signed Host
# fixture. Multi-line signed fixtures are covered by the multi-item suite.
module MultiProfileContextTest
  B = AP2MandateVerifier::InputBuilder
  T = AP2MandateVerifier::TrustContext
  @count = 0
  def self.assert(value, label)
    raise "multi profile context: #{label}" unless value
    @count += 1
  end
  def self.invalid(label)
    begin
      yield
    rescue B::Invalid
      @count += 1
      return
    end
    raise "multi profile context accepted #{label}"
  end
  model = HostBindingTest.fixture
  snapshot = JSON.parse(model[:trust]["snapshot"]["body"])
  snapshot["records"].each do |record|
    %w[profile_ref profile_version algorithm key_fingerprint].each { |field| record.delete(field) }
  end
  business = {snapshot: snapshot, tenant_id: "tenant", verified_at: HostBindingTest::N,
    issuer: model[:selection]["Issuer"], agent: model[:selection]["Agent"], merchant: model[:selection]["Merchant"]}
  old = B.trust(**business)
  multi = B.trust(**business, profile_ref: T::MULTI_PROFILE_REF)
  assert(JSON.parse(old.selection_json)["profile_ref"] == T::PROFILE_REF, "old remains default")
  assert(JSON.parse(old.trust_json)["profile"]["body"] == T::PROFILE_BODY, "old original profile bytes")
  assert(Digest::SHA256.hexdigest(T::PROFILE_BODY) == T::PROFILE_HASH, "old hash unchanged")
  selected = JSON.parse(multi.selection_json)
  assert(selected.values_at("profile_ref", "profile_version", "profile_definition_hash") ==
    [T::MULTI_PROFILE_REF, "1", T::MULTI_PROFILE_HASH], "explicit new profile")
  rebuilt = B.restore_trust(trust_json: multi.trust_json, selection_json: multi.selection_json, verified_at: HostBindingTest::N)
  assert(rebuilt.trust_json == multi.trust_json && rebuilt.selection_json == multi.selection_json, "restore original trust bytes")
  invalid("unknown explicit profile") { B.trust(**business, profile_ref: "unknown") }
  invalid("nil explicit profile") { B.trust(**business, profile_ref: nil) }
  invalid("new body old selection") { B.restore_trust(trust_json: multi.trust_json, selection_json: old.selection_json, verified_at: HostBindingTest::N) }
  invalid("old body new selection") { B.restore_trust(trust_json: old.trust_json, selection_json: multi.selection_json, verified_at: HostBindingTest::N) }
  order = model[:host]["binding"].slice(*B::ORDER_FIELDS)
  challenge = model[:host]["challenge"]
  prepare = {order: order, root_presentation: model[:inputs][:root_presentation], host_checkout_jws: model[:inputs][:host_checkout_jws],
    **challenge.slice("challenge_id", "nonce", "issuer_id", "not_before", "not_after").transform_keys(&:to_sym)}
  saved_old = B.prepare(trust: old, **prepare)
  saved = B.prepare(trust: multi, **prepare)
  parsed = JSON.parse(saved)
  assert(parsed["profile_ref"] == T::MULTI_PROFILE_REF, "new saved wrapper")
  assert(parsed["challenge"]["B"]["profile_ref"] == T::MULTI_PROFILE_REF, "new saved binding")
  assert(parsed["challenge"]["profile_definition_hash"] == T::MULTI_PROFILE_HASH, "new saved hash")
  assert(B.restore(saved_challenge: saved) == saved && B.restore(saved_challenge: saved_old) == saved_old, "both formats preserve original")
  %w[profile_ref profile_version].each do |field|
    changed = JSON.parse(saved)
    changed[field] = field == "profile_ref" ? T::PROFILE_REF : "2"
    invalid("wrapper/binding #{field} disagreement") { B.restore(saved_challenge: JSON.generate(changed)) }
  end
  tampered = JSON.parse(saved)
  tampered["challenge"]["B"]["checkout_jwt_digest"] = "0" * 64
  tampered_wire = JSON.generate(tampered)
  assert(B.restore(saved_challenge: tampered_wire) == tampered_wire, "restore does not repair digest")
  inputs = {order: order, root_presentation: model[:inputs][:root_presentation], host_checkout_jws: model[:inputs][:host_checkout_jws],
    terminal_jws: model[:inputs][:terminal_jws], expected_challenge_issuer_id: "host-issuer", clock_source_id: "test-clock", verified_at: HostBindingTest::N}
  verified = B.verify(trust: multi, saved_challenge: saved, **inputs)
  assert(verified.success? && verified.evidence["profile_ref"] == T::MULTI_PROFILE_REF &&
    verified.evidence["profile_definition_hash"] == T::MULTI_PROFILE_HASH, "new profile reaches complete core Evidence")
  trusted_result = AP2MandateVerifier.verify_trusted_scoped_constraints(trust_json: multi.trust_json,
    selection_json: multi.selection_json, **model[:inputs], expected_aud: "host", expected_nonce: "nonce",
    expected_checkout_id: "order", expected_merchant_id: "shop", expected_currency: "USD", expected_total_minor: 200)
  assert(trusted_result.code == :scoped_constraints_verified_only && !trusted_result.success?, "trusted lower API propagates selected new profile")
  mismatch = B.verify(trust: multi, saved_challenge: saved_old, **inputs)
  assert(mismatch.rejected? && mismatch.code == :host_binding_mismatch && mismatch.evidence.nil?, "old saved challenge with new trust rejects")
  mismatch = B.verify(trust: old, saved_challenge: saved, **inputs)
  assert(mismatch.rejected? && mismatch.code == :host_binding_mismatch && mismatch.evidence.nil?, "new saved challenge with old trust rejects")
  changed_inputs = B.inputs(trust: multi, saved_challenge: tampered_wire, **inputs)
  assert(JSON.parse(changed_inputs[:host_json])["challenge"]["B"]["checkout_jwt_digest"] == "0" * 64, "input conversion retains corrupted saved digest")
  puts "PASS #{@count} explicit multi-profile trust/challenge compatibility cases"
end
