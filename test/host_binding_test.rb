# frozen_string_literal: true
require "json"
require "openssl"
require "base64"
require "digest"
require_relative "../lib/ap2_mandate_verifier"

module HostBindingTest
  T = AP2MandateVerifier::TrustContext
  N = 1_800_000_000
  @count = 0
  @keys = Array.new(3) { OpenSSL::PKey::EC.generate("prime256v1") }
  def self.copy(value) = Marshal.load(Marshal.dump(value))
  def self.b64(value) = Base64.urlsafe_encode64(value, padding: false)
  def self.digest(value) = Digest::SHA256.hexdigest(value)
  def self.sdhash(value) = b64(Digest::SHA256.digest(value))
  def self.sign(key, payload, typ)
    wire = b64(JSON.generate("alg" => "ES256", "typ" => typ)) + "." + b64(JSON.generate(payload))
    values = OpenSSL::ASN1.decode(key.sign("SHA256", wire)).value
    result = wire + "." + b64(values.map { |v| v.value.to_s(2).rjust(32, "\x00") }.join)
    # Independent provider-level signature control, not an O1-O5/full AP2 claim.
    a, b, c = result.split("."); bytes = Base64.urlsafe_decode64(c)
    der = OpenSSL::ASN1::Sequence.new([0, 32].map { |i| OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(bytes.byteslice(i, 32), 2)) }).to_der
    raise "signature control" unless OpenSSL::PKey.read(key.public_to_pem).verify("SHA256", der, a + "." + b)
    result
  end
  def self.totals(n) = [{"type" => "subtotal", "amount" => n}, {"type" => "total", "amount" => n}]
  def self.disclosure(x) = b64(JSON.generate(["host-binding-salt", x]))
  def self.marker(x) = {"..." => sdhash(x)}
  def self.fixture(open_iat: N - 1_000, open_exp: N + 1_000, terminal_iat: N, closed_exp: open_exp)
    issuer, agent, merchant = @keys
    point = agent.public_key.to_octet_string(:uncompressed)
    item = {"id" => "sku", "title" => "item"}; shop = {"id" => "shop", "name" => "store"}
    sku = disclosure(item); allowed = disclosure(shop)
    open = {"vct" => "mandate.checkout.open.1", "iat" => open_iat, "exp" => open_exp,
      "cnf" => {"jwk" => {"kty" => "EC", "crv" => "P-256", "x" => b64(point.byteslice(1, 32)), "y" => b64(point.byteslice(33, 32))}},
      "constraints" => [{"type" => "checkout.line_items", "items" => [{"id" => "req", "quantity" => 2, "acceptable_items" => [marker(sku)]}]},
        {"type" => "checkout.allowed_merchants", "allowed" => [marker(allowed)]}]}
    opening = disclosure(open)
    root = [sign(issuer, {"delegate_payload" => [marker(opening)], "_sd_alg" => "sha-256"}, "example+sd-jwt"), opening, sku, allowed, ""].join("~")
    checkout = sign(merchant, {"currency" => "USD", "id" => "order", "merchant" => shop, "status" => "ready_for_complete", "links" => [],
      "line_items" => [{"id" => "line", "item" => item.merge("price" => 100), "quantity" => 2, "totals" => totals(200)}], "totals" => totals(200)}, "JWT")
    closed = {"vct" => "mandate.checkout.1", "iat" => open_iat, "exp" => closed_exp, "checkout_jwt" => checkout, "checkout_hash" => sdhash(checkout)}
    terminal = sign(agent, {"aud" => "host", "nonce" => "nonce", "iat" => terminal_iat, "sd_hash" => sdhash(root), "delegate_payload" => [closed]}, "kb+sd-jwt")
    snapshot = {"id" => "snapshot", "policy_version" => "policy-1", "active" => true, "not_before" => N - 2_000, "not_after" => N + 2_000,
      "records" => %w[Issuer Agent Merchant].each_with_index.map do |role, i|
        pem = @keys[i].public_to_pem
        {"role" => role, "identity" => role == "Merchant" ? "shop" : role.downcase, "tenant_id" => "tenant", "purpose" => "checkout", "key_ref" => role.downcase + "-1",
         "profile_ref" => T::PROFILE_REF, "profile_version" => T::PROFILE_VERSION, "public_key_pem" => pem, "key_fingerprint" => digest(pem),
         "algorithm" => "ES256", "active" => true, "not_before" => N - 2_000, "not_after" => N + 2_000}
      end}
    body = JSON.generate(snapshot)
    selection = {"trust_snapshot_id" => "snapshot", "policy_version" => "policy-1", "trust_content_hash" => digest(body), "profile_ref" => T::PROFILE_REF,
      "profile_version" => T::PROFILE_VERSION, "profile_definition_hash" => T::PROFILE_HASH, "tenant_id" => "tenant"}
    snapshot["records"].each { |r| selection[r["role"]] = r.slice("identity", "purpose", "key_ref") }
    trust = {"snapshot" => {"id" => "snapshot", "policy_version" => "policy-1", "content_hash" => digest(body), "body" => body},
      "profile" => {"profile_ref" => T::PROFILE_REF, "version" => T::PROFILE_VERSION, "definition_hash" => T::PROFILE_HASH, "body" => T::PROFILE_BODY}}
    binding = {"tenant_id" => "tenant", "buyer_account_id" => "buyer", "order_id" => "order", "merchant_id" => "shop", "audience" => "host",
      "profile_ref" => T::PROFILE_REF, "order_version" => "order-v1", "profile_version" => T::PROFILE_VERSION,
      "approved_agent_key_fingerprint" => digest(agent.public_to_pem), "root_presentation_digest" => digest(root), "checkout_jwt_digest" => digest(checkout),
      "currency" => "USD", "expected_total" => 200}
    challenge = {"challenge_id" => "challenge-1", "nonce" => "nonce", "issuer_id" => "host-issuer", "B" => copy(binding),
      "trust_snapshot_id" => "snapshot", "policy_version" => "policy-1", "trust_content_hash" => digest(body), "profile_definition_hash" => T::PROFILE_HASH,
      "not_before" => N - 2_000, "not_after" => N + 2_000, "state" => "issued"}
    {trust: trust, selection: selection, host: {"binding" => binding, "challenge" => challenge, "expected_challenge_issuer_id" => "host-issuer", "clock_source_id" => "host-fixed-test-clock"},
      inputs: {root_presentation: root, terminal_jws: terminal, host_checkout_jws: checkout, verified_at: N}}
  end
  def self.args(model)
    model[:inputs].merge(trust_json: JSON.generate(model[:trust]), selection_json: JSON.generate(model[:selection]), host_json: JSON.generate(model[:host]))
  end
  def self.update_snapshot(model)
    snapshot = JSON.parse(model[:trust]["snapshot"]["body"]); yield snapshot
    wire = JSON.generate(snapshot)
    model[:trust]["snapshot"].merge!("body" => wire, "content_hash" => digest(wire))
    model[:selection]["trust_content_hash"] = model[:host]["challenge"]["trust_content_hash"] = digest(wire)
  end
  @normal = fixture
  def self.recorded_cases = @recorded_cases || []
  def self.expect(name, code, model = copy(@normal), interval: nil)
    yield model if block_given?
    (@recorded_cases ||= []) << [name, copy(model), code, interval]
    observed = nil
    trace = TracePoint.new(:return) do |event|
      if event.defined_class == AP2MandateVerifier::HostBinding.singleton_class && event.method_id == :verified_binding! && event.binding.local_variable_defined?(:starts)
        starts = event.binding.local_variable_get(:starts); ends = event.binding.local_variable_get(:ends)
        observed = [starts.max, ends.min] if starts && ends
      end
    end
    result = trace.enable { AP2MandateVerifier.verify_host_binding(**args(model)) }
    raise "#{name}: #{result.status}/#{result.code} expected #{code}" unless result.code == code && !result.success? && result.evidence.nil?
    raise "#{name}: interval #{observed.inspect} != #{interval.inspect}" if interval && observed != interval
    @count += 1
  end
  expect("normal aggregate", :host_binding_verified_only, interval: [N, N + 301])
  AP2MandateVerifier::HostBinding::B_FIELDS.each do |field|
    expect("Host-only change #{field}", :host_binding_mismatch) do |m|
      m[:host]["binding"][field] = field == "expected_total" ? 201 : (AP2MandateVerifier::HostBinding::B_HASHES.include?(field) ? "0" * 64 : field == "currency" ? "EUR" : "other")
    end
    expect("missing current #{field}", :invalid_host_context) { |m| m[:host]["binding"].delete(field) }
    expect("missing challenge B #{field}", :invalid_host_context) { |m| m[:host]["challenge"]["B"].delete(field) }
    expect("null B #{field}", :invalid_host_context) { |m| m[:host]["binding"][field] = nil }
  end
  AP2MandateVerifier::HostBinding::CHALLENGE_FIELDS.each do |field|
    expect("missing challenge #{field}", :invalid_host_context) { |m| m[:host]["challenge"].delete(field) }
  end
  %w[consumed revoked unknown].each { |state| expect("state #{state}", :challenge_state_mismatch) { |m| m[:host]["challenge"]["state"] = state } }
  expect("issuer mismatch", :host_binding_mismatch) { |m| m[:host]["challenge"]["issuer_id"] = "other" }
  expect("nonce signature binding", :nonce_mismatch) { |m| m[:host]["challenge"]["nonce"] = "other" }
  AP2MandateVerifier::HostBinding::REFERENCES.each do |field|
    expect("challenge ref #{field}", :challenge_reference_mismatch) { |m| m[:host]["challenge"][field] = field.include?("hash") ? "0" * 64 : "other" }
  end
  {"tenant_id" => :host_binding_mismatch, "profile_ref" => :host_binding_mismatch, "profile_version" => :host_binding_mismatch,
   "approved_agent_key_fingerprint" => :host_binding_mismatch, "root_presentation_digest" => :host_binding_mismatch,
   "checkout_jwt_digest" => :host_binding_mismatch, "order_id" => :checkout_identity_mismatch,
   "merchant_id" => :trust_context_mismatch, "audience" => :audience_mismatch, "currency" => :currency_mismatch,
   "expected_total" => :amount_mismatch}.each do |field, code|
    expect("symmetric context still needs proof #{field}", code) do |m|
      m[:host]["binding"][field] = field == "expected_total" ? 201 : (AP2MandateVerifier::HostBinding::B_HASHES.include?(field) ? "0" * 64 : field == "currency" ? "EUR" : "other")
      m[:host]["challenge"]["B"] = copy(m[:host]["binding"])
    end
  end
  expect("compact Root digest insufficient", :host_binding_mismatch) do |m|
    m[:host]["binding"]["root_presentation_digest"] = digest(m[:inputs][:root_presentation].split("~").first)
    m[:host]["challenge"]["B"] = copy(m[:host]["binding"])
  end
  expect("reordered disclosures old terminal", :root_binding_mismatch) do |m|
    parts = m[:inputs][:root_presentation].split("~", -1); parts[2], parts[3] = parts[3], parts[2]
    m[:inputs][:root_presentation] = parts.join("~")
    m[:host]["binding"]["root_presentation_digest"] = digest(m[:inputs][:root_presentation])
    m[:host]["challenge"]["B"] = copy(m[:host]["binding"])
  end
  expect("terminal signature alteration", :invalid_root_signature) do |m|
    a, b, c = m[:inputs][:terminal_jws].split("."); raw = Base64.urlsafe_decode64(c); raw.setbyte(0, raw.getbyte(0) ^ 1)
    m[:inputs][:terminal_jws] = [a, b, b64(raw)].join(".")
  end
  expect("challenge start inclusive", :host_binding_verified_only) { |m| m[:host]["challenge"]["not_before"] = N }
  expect("challenge future", :challenge_time_mismatch) { |m| m[:host]["challenge"]["not_before"] = N + 1 }
  expect("challenge expiry exclusive", :challenge_time_mismatch) { |m| m[:host]["challenge"]["not_after"] = N }
  expect("challenge empty interval", :invalid_host_context) { |m| m[:host]["challenge"]["not_after"] = m[:host]["challenge"]["not_before"] }
  expect("short challenge", :host_binding_verified_only, interval: [N, N + 1]) { |m| m[:host]["challenge"]["not_after"] = N + 1 }
  expect("terminal age300", :host_binding_verified_only, fixture(terminal_iat: N - 300), interval: [N - 300, N + 1])
  expect("terminal age301", :invalid_purchase_time, fixture(terminal_iat: N - 301))
  expect("terminal future", :invalid_purchase_time, fixture(terminal_iat: N + 1))
  expect("Open start inclusive", :host_binding_verified_only, fixture(open_iat: N))
  expect("Open expired", :invalid_purchase_time, fixture(open_exp: N))
  expect("Closed differs", :delegation_claim_mismatch, fixture(closed_exp: N + 999))
  %w[not_before not_after].each do |field|
    [nil, true, 1.0, "1800000000", -1, 4_102_444_801].each do |value|
      expect("challenge #{field} type #{value.inspect}", :invalid_host_context) { |m| m[:host]["challenge"][field] = value }
    end
  end
  %w[Issuer Agent Merchant].each_with_index do |role, index|
    expect("#{role} key expiry", :trust_key_time_mismatch) { |m| update_snapshot(m) { |s| s["records"][index]["not_after"] = N } }
    expect("#{role} key min expiry", :host_binding_verified_only, interval: [N, N + 2]) { |m| update_snapshot(m) { |s| s["records"][index]["not_after"] = N + 2 } }
    model = fixture(terminal_iat: N - 100)
    expect("#{role} key latest start", :host_binding_verified_only, model, interval: [N - 1, N + 201]) { |m| update_snapshot(m) { |s| s["records"][index]["not_before"] = N - 1 } }
  end
  expect("snapshot expiry", :trust_snapshot_time_mismatch) { |m| update_snapshot(m) { |s| s["not_after"] = N } }
  expect("snapshot minimum expiry", :host_binding_verified_only, interval: [N, N + 3]) { |m| update_snapshot(m) { |s| s["not_after"] = N + 3 } }
  expect("snapshot latest start", :host_binding_verified_only, fixture(terminal_iat: N - 100), interval: [N - 2, N + 201]) { |m| update_snapshot(m) { |s| s["not_before"] = N - 2 } }
  expect("challenge latest start", :host_binding_verified_only, fixture(terminal_iat: N - 100), interval: [N - 3, N + 201]) { |m| m[:host]["challenge"]["not_before"] = N - 3 }
  [nil, true, 1.0, "1800000000", -1, 4_102_444_801].each { |t| expect("evaluation type #{t.inspect}", :invalid_host_context) { |m| m[:inputs][:verified_at] = t } }
  expect("extra Host field", :invalid_host_context) { |m| m[:host]["allow"] = true }
  expect("extra B field", :invalid_host_context) { |m| m[:host]["binding"]["future"] = true }
  expect("extra challenge field", :invalid_host_context) { |m| m[:host]["challenge"]["evidence"] = {} }
  %w[root_presentation_digest checkout_jwt_digest approved_agent_key_fingerprint].each do |field|
    expect("noncanonical digest #{field}", :invalid_host_context) { |m| m[:host]["binding"][field] = "A" * 64 }
  end
  input = args(copy(@normal))
  ["x" * 32_769, '{"binding":{},"binding":{}}'].each_with_index do |wire, i|
    result = AP2MandateVerifier.verify_host_binding(**input.merge(host_json: wire))
    raise "Host JSON boundary" unless result.code == (i == 0 ? :input_too_large : :duplicate_key) && !result.success? && result.evidence.nil?
    @count += 1
  end
  # Caller mutation during public-key checking cannot change captured Host/wire.
  input = args(copy(@normal)); original_host = input[:host_json]; original_root = input[:root_presentation]
  original = AP2MandateVerifier::RootSignature.method(:public_jwk!)
  AP2MandateVerifier::RootSignature.define_singleton_method(:public_jwk!) do |pem|
    original_host.replace("{}"); original_root.replace("changed")
    original.call(pem)
  end
  begin
    result = AP2MandateVerifier.verify_host_binding(**input)
    raise "Host/wire snapshot" unless result.code == :host_binding_verified_only && !result.success? && result.evidence.nil? && original_host == "{}" && original_root == "changed"
    @count += 1
  ensure
    AP2MandateVerifier::RootSignature.define_singleton_method(:public_jwk!, original)
  end

  %w[binding challenge expected_challenge_issuer_id clock_source_id].each do |field|
    expect("missing Host #{field}", :invalid_host_context) { |m| m[:host].delete(field) }
  end
  [nil, false, 123, "", "x" * 257].each do |value|
    expect("clock identity #{value.inspect[0, 40]}", :invalid_host_context) { |m| m[:host]["clock_source_id"] = value }
  end
  expect("revoked challenge before bad signature", :challenge_state_mismatch) do |m|
    m[:host]["challenge"]["state"] = "revoked"; m[:inputs][:terminal_jws] = "not-a-token"
  end
  expect("host B change before bad signature", :host_binding_mismatch) do |m|
    m[:host]["binding"]["buyer_account_id"] = "other"; m[:inputs][:terminal_jws] = "not-a-token"
  end
  puts "PASS #{@count} Host binding/challenge/aggregate interval cases; no consumption/Evidence/ALLOW"
end
