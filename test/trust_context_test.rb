# frozen_string_literal: true
require "json"
require "digest"
require_relative "../lib/ap2_mandate_verifier"

module TrustContextTest
  T = AP2MandateVerifier::TrustContext
  N = 1_800_000_000
  @count = 0
  @inputs = JSON.parse(File.binread(File.expand_path("../O2O5_PUBLIC_CASES.json", __dir__))).fetch("cases").fetch("FULL").transform_keys(&:to_sym)
  @keys = T::ROLES.to_h { |role, key| [role, @inputs.delete(key)] }
  @snapshot = {"id" => "snapshot-1", "policy_version" => "policy-1", "active" => true,
    "not_before" => N - 100, "not_after" => N + 100, "records" => @keys.map do |role, pem|
      {"role" => role, "identity" => role == "Merchant" ? "shop" : role.downcase,
       "tenant_id" => "tenant", "purpose" => "checkout", "key_ref" => role.downcase + "-1",
       "profile_ref" => T::PROFILE_REF, "profile_version" => T::PROFILE_VERSION,
       "public_key_pem" => pem, "key_fingerprint" => Digest::SHA256.hexdigest(pem),
       "algorithm" => "ES256", "active" => true, "not_before" => N - 100, "not_after" => N + 100}
    end}
  def self.copy(x) = Marshal.load(Marshal.dump(x))
  def self.bundle(snapshot = @snapshot)
    body = JSON.generate(snapshot)
    trust = {"snapshot" => {"id" => snapshot["id"], "policy_version" => snapshot["policy_version"],
      "content_hash" => Digest::SHA256.hexdigest(body), "body" => body},
      "profile" => {"profile_ref" => T::PROFILE_REF, "version" => T::PROFILE_VERSION,
        "definition_hash" => T::PROFILE_HASH, "body" => T::PROFILE_BODY}}
    selection = {"trust_snapshot_id" => snapshot["id"], "policy_version" => snapshot["policy_version"],
      "trust_content_hash" => trust["snapshot"]["content_hash"], "profile_ref" => T::PROFILE_REF,
      "profile_version" => T::PROFILE_VERSION, "profile_definition_hash" => T::PROFILE_HASH, "tenant_id" => "tenant"}
    @snapshot["records"].each { |r| selection[r["role"]] = r.slice("identity", "purpose", "key_ref") }
    [trust, selection]
  end
  def self.expect(name, code, snapshot: @snapshot, inputs: @inputs)
    trust, selection = bundle(snapshot)
    yield(trust, selection) if block_given?
    result = AP2MandateVerifier.verify_trusted_scoped_constraints(trust_json: JSON.generate(trust), selection_json: JSON.generate(selection), **inputs)
    raise "#{name}: #{result.status}/#{result.code}, wanted #{code}" unless result.code == code && !result.success? && result.evidence.nil?
    @count += 1
  end
  expect("normal", :scoped_constraints_verified_only)
  expect("key override", :invalid_trust_context, inputs: @inputs.merge(trusted_issuer_public_key_pem: @keys["Issuer"]))
  expect("missing input", :invalid_trust_context, inputs: @inputs.reject { |k, _| k == :expected_nonce })
  ["snapshot", "profile"].each do |envelope|
    expect("body hash #{envelope}", :trust_context_mismatch) { |t, _| t[envelope]["body"] += " " }
    expect("unknown envelope #{envelope}", :invalid_trust_context) { |t, _| t[envelope]["future"] = true }
  end
  %w[trust_snapshot_id policy_version trust_content_hash profile_ref profile_version profile_definition_hash tenant_id].each do |field|
    expected = %w[profile_ref profile_version profile_definition_hash].include?(field) ? :unsupported_trust_profile : (field == "tenant_id" ? :trust_key_not_found : :trust_context_mismatch)
    expect("selected #{field}", expected) { |_, s| s[field] = field.include?("hash") ? "0" * 64 : "other" }
  end
  expect("merchant identity", :trust_context_mismatch) { |_, s| s["Merchant"]["identity"] = "other" }
  expect("unknown profile", :unsupported_trust_profile) do |t, s|
    body = JSON.parse(T::PROFILE_BODY); body["version"] = "2"
    t["profile"].merge!("version" => "2", "body" => JSON.generate(body), "definition_hash" => Digest::SHA256.hexdigest(JSON.generate(body)))
    s.merge!("profile_version" => "2", "profile_definition_hash" => t["profile"]["definition_hash"])
  end
  expect("snapshot revoked", :inactive_trust_snapshot, snapshot: @snapshot.merge("active" => false))
  expect("snapshot start", :scoped_constraints_verified_only, snapshot: @snapshot.merge("not_before" => N))
  expect("snapshot future", :trust_snapshot_time_mismatch, snapshot: @snapshot.merge("not_before" => N + 1))
  expect("snapshot end", :trust_snapshot_time_mismatch, snapshot: @snapshot.merge("not_after" => N))
  expect("snapshot empty interval", :invalid_trust_context, snapshot: @snapshot.merge("not_after" => N - 100))
  %w[Issuer Agent Merchant].each_with_index do |role, index|
    {"identity" => "other", "purpose" => "other", "tenant_id" => "other", "key_ref" => "other",
     "profile_ref" => "other", "profile_version" => "2", "algorithm" => "HS256", "active" => false,
     "not_before" => N + 1, "not_after" => N, "key_fingerprint" => "0" * 64,
     "public_key_pem" => "https://not-a-key.invalid"}.each do |field, value|
      snapshot = copy(@snapshot); snapshot["records"][index][field] = value
      code = case field
      when "profile_ref", "profile_version", "algorithm" then :unsupported_trust_profile
      when "identity", "purpose", "tenant_id", "key_ref" then :trust_key_not_found
      when "active" then :inactive_trust_key
      when "not_before", "not_after" then :trust_key_time_mismatch
      else :invalid_trust_key
      end
      expect("#{role} #{field}", code, snapshot: snapshot)
    end
    snapshot = copy(@snapshot); snapshot["records"] << copy(snapshot["records"][index])
    expect("duplicate #{role}", :ambiguous_trust_key, snapshot: snapshot)
    snapshot["records"].last["active"] = false
    expect("duplicate inactive #{role}", :ambiguous_trust_key, snapshot: snapshot)
    snapshot = copy(@snapshot); snapshot["records"][index]["not_before"] = N
    expect("start #{role}", :scoped_constraints_verified_only, snapshot: snapshot)
    %w[identity tenant_id purpose key_ref profile_ref profile_version key_fingerprint algorithm active not_before not_after public_key_pem role].each do |field|
      snapshot = copy(@snapshot); snapshot["records"][index].delete(field)
      expect("missing #{role} #{field}", :invalid_trust_context, snapshot: snapshot)
    end
  end
  [nil, 1.0, true, "1800000000", -1, 4_102_444_801].each do |time|
    expect("clock #{time.inspect}", :invalid_trust_context, inputs: @inputs.merge(verified_at: time))
  end
  expect("unknown outer", :invalid_trust_context) { |t, _| t["key_url"] = "https://invalid.invalid" }
  expect("duplicate body key", :duplicate_key) do |t, s|
    body = t["snapshot"]["body"].sub('{', '{"id":"shadow",')
    t["snapshot"]["body"] = body
    s["trust_content_hash"] = t["snapshot"]["content_hash"] = Digest::SHA256.hexdigest(body)
  end
  expect("noncanonical profile bytes", :unsupported_trust_profile) do |t, s|
    t["profile"]["body"] += " "
    s["profile_definition_hash"] = t["profile"]["definition_hash"] = Digest::SHA256.hexdigest(t["profile"]["body"])
  end
  expect("too many records", :invalid_trust_context, snapshot: @snapshot.merge("records" => Array.new(17) { @snapshot["records"][0] }))
  expect("missing records", :invalid_trust_context, snapshot: @snapshot.merge("records" => []))
  expect("bad nonce preserved", :nonce_mismatch, inputs: @inputs.merge(expected_nonce: "other"))
  expect("bad total preserved", :amount_mismatch, inputs: @inputs.merge(expected_total_minor: 201))

  # Deterministic mutation during key validation, after identity comparison.
  # The caller's String changes, while the verifier must retain its snapshot.
  mutable = @inputs[:expected_merchant_id].dup
  original = AP2MandateVerifier::RootSignature.method(:public_jwk!)
  AP2MandateVerifier::RootSignature.define_singleton_method(:public_jwk!) do |pem|
    mutable.replace("different-shop")
    original.call(pem)
  end
  begin
    expect("Host snapshot before key validation", :scoped_constraints_verified_only,
      inputs: @inputs.merge(expected_merchant_id: mutable))
    raise "mutation control missing" unless mutable == "different-shop"
  ensure
    AP2MandateVerifier::RootSignature.define_singleton_method(:public_jwk!, original)
  end
  %w[Issuer Agent Merchant].each_with_index do |role, index|
    snapshot = copy(@snapshot)
    snapshot["records"][index]["public_key_pem"] += "\n"
    snapshot["records"][index]["key_fingerprint"] = Digest::SHA256.hexdigest(snapshot["records"][index]["public_key_pem"])
    expect("noncanonical PEM #{role}", :invalid_trust_key, snapshot: snapshot)
  end

  snapshot = copy(@snapshot)
  retired = copy(snapshot["records"][0]); retired.merge!("key_ref" => "retired", "active" => false, "not_after" => N - 1)
  snapshot["records"] << retired
  expect("retired distinct ref does not fallback", :scoped_constraints_verified_only, snapshot: snapshot)
  [nil, "true", 1].each do |active|
    expect("active type #{active.inspect}", :invalid_trust_context, snapshot: @snapshot.merge("active" => active))
  end
  [nil, "1800000000", N.to_f, true].each do |time|
    expect("snapshot time type #{time.inspect}", :invalid_trust_context, snapshot: @snapshot.merge("not_before" => time))
  end
  %w[Issuer Agent Merchant].each_with_index do |role, index|
    snapshot = copy(@snapshot)
    snapshot["records"][index]["key_fingerprint"] = snapshot["records"][index]["key_fingerprint"].upcase
    expect("uppercase fingerprint #{role}", :invalid_trust_context, snapshot: snapshot)
    snapshot = copy(@snapshot)
    other = role == "Agent" ? "Issuer" : "Agent"
    snapshot["records"][index].merge!("public_key_pem" => @keys[other], "key_fingerprint" => Digest::SHA256.hexdigest(@keys[other]))
    expect("signed wrong key #{role}", role == "Agent" ? :agent_key_mismatch : :invalid_root_signature, snapshot: snapshot)
  end
  expect("metadata id contradiction", :trust_context_mismatch) { |t, _| t["snapshot"]["id"] = "other" }
  expect("unknown selector field", :invalid_trust_context) { |_, s| s["Issuer"]["jku"] = "https://invalid.invalid" }
  expect("unknown snapshot field", :invalid_trust_context, snapshot: @snapshot.merge("future" => true))
  expect("empty identity", :invalid_trust_context) { |_, s| s["Issuer"]["identity"] = "" }
  expect("oversize identity", :invalid_trust_context) { |_, s| s["Issuer"]["identity"] = "x" * 257 }
  trust, selection = bundle
  [ ["{", JSON.generate(selection), :invalid_json],
    [JSON.generate(trust), '{"tenant_id":"x","tenant_id":"y"}', :duplicate_key],
    [JSON.generate(trust), "x" * 16_385, :input_too_large],
    ["x" * 131_073, JSON.generate(selection), :input_too_large] ].each do |raw_trust, raw_selection, code|
    result = AP2MandateVerifier.verify_trusted_scoped_constraints(trust_json: raw_trust, selection_json: raw_selection, **@inputs)
    raise "raw boundary #{result.code} wanted #{code}" unless result.code == code && !result.success? && result.evidence.nil?
    @count += 1
  end
  puts "PASS #{@count} trust snapshot/profile/key and integrated non-success cases"
end
