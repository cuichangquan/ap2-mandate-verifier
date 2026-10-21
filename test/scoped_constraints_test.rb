# frozen_string_literal: true
require "json"
require "base64"
require "openssl"
require "digest"
require_relative "../lib/ap2_mandate_verifier"

module ConstraintTest
  @cases = 0
  @issuer, @agent, @merchant = Array.new(3) { OpenSSL::PKey::EC.generate("prime256v1") }
  def self.assert(ok) = (raise "constraint assertion failed" unless ok)
  def self.b64(bytes) = Base64.urlsafe_encode64(bytes, padding: false)
  def self.hash(bytes) = b64(Digest::SHA256.digest(bytes))
  def self.copy(value) = Marshal.load(Marshal.dump(value))
  def self.sign(key, payload, typ)
    input = b64(JSON.generate("alg" => "ES256", "typ" => typ)) + "." + b64(JSON.generate(payload))
    parts = OpenSSL::ASN1.decode(key.sign("SHA256", input)).value
    input + "." + b64(parts.map { |part| part.value.to_s(2).rjust(32, "\x00") }.join)
  end
  def self.oracle(wire, key)
    a, b, c = wire.split(".")
    bytes = Base64.urlsafe_decode64(c)
    signature = OpenSSL::ASN1::Sequence.new([0, 32].map do |i|
      OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(bytes.byteslice(i, 32), 2))
    end).to_der
    OpenSSL::PKey.read(key.public_to_pem).verify("SHA256", signature, a + "." + b)
  end
  def self.totals(amount) = [{"type" => "subtotal", "amount" => amount}, {"type" => "total", "amount" => amount}]
  def self.fixture(requirement, allowed, checkout, types = ["checkout.line_items", "checkout.allowed_merchants"])
    data = copy(requirement)
    sku = b64(JSON.generate(["sku-salt", data["acceptable_items"][0]]))
    merchant = b64(JSON.generate(["merchant-salt", allowed[0]]))
    data["acceptable_items"][0] = {"..." => hash(sku)}
    point = @agent.public_key.to_octet_string(:uncompressed)
    open = {"vct" => "mandate.checkout.open.1", "iat" => 1_799_999_900, "exp" => 1_800_000_100,
      "cnf" => {"jwk" => {"kty" => "EC", "crv" => "P-256", "x" => b64(point.byteslice(1, 32)), "y" => b64(point.byteslice(33, 32))}},
      "constraints" => [{"type" => types[0], "items" => [data]}, {"type" => types[1], "allowed" => [{"..." => hash(merchant)}]}]}
    opening = b64(JSON.generate(["open-salt", open]))
    root_jws = sign(@issuer, {"delegate_payload" => [{"..." => hash(opening)}], "_sd_alg" => "sha-256"}, "example+sd-jwt")
    root_wire = ([root_jws, opening, sku, merchant, ""]).join("~")
    checkout_wire = sign(@merchant, checkout, "JWT")
    closed = {"vct" => "mandate.checkout.1", "iat" => open["iat"], "exp" => open["exp"],
      "checkout_jwt" => checkout_wire, "checkout_hash" => hash(checkout_wire)}
    terminal = sign(@agent, {"iat" => 1_800_000_000, "aud" => "host", "nonce" => "n",
      "sd_hash" => hash(root_wire), "delegate_payload" => [closed]}, "kb+sd-jwt")
    # Every generated negative is genuinely signed; shared provider, not O1-O5.
    assert(oracle(root_jws, @issuer) && oracle(terminal, @agent) && oracle(checkout_wire, @merchant))
    {root_presentation: root_wire, terminal_jws: terminal, host_checkout_jws: checkout_wire,
      trusted_issuer_public_key_pem: @issuer.public_to_pem, expected_agent_public_key_pem: @agent.public_to_pem,
      trusted_merchant_public_key_pem: @merchant.public_to_pem, expected_aud: "host", expected_nonce: "n",
      verified_at: 1_800_000_000, expected_checkout_id: "order", expected_merchant_id: "shop"}
  end
  def self.expect(binding, code = :scoped_constraints_verified_only, status = :unverified,
                  currency: "USD", total: 200, precondition: true)
    if precondition
      prior = AP2MandateVerifier.verify_purchase_binding(**binding)
      assert(prior.status == :unverified && prior.code == :purchase_binding_verified_only)
    end
    result = AP2MandateVerifier.verify_scoped_constraints(**binding,
      expected_currency: currency, expected_total_minor: total)
    raise "case #{@cases + 1}: expected #{status}/#{code}, got #{result.status}/#{result.code}" unless
      result.status == status && result.code == code
    assert(!result.success? && result.evidence.nil? && result.frozen?)
    @cases += 1
  end
  def self.reject(binding, code, **context) = expect(binding, code, :rejected, **context)

  requirement = {"id" => "req", "quantity" => 2, "acceptable_items" => [{"id" => "sku", "title" => "item"}]}
  allowed = [{"id" => "shop", "name" => "store"}]
  checkout = {"id" => "order", "merchant" => {"id" => "shop", "name" => "store"},
    "status" => "ready_for_complete", "currency" => "USD", "links" => [], "totals" => totals(200),
    "line_items" => [{"id" => "line", "item" => {"id" => "sku", "title" => "item", "price" => 100},
      "quantity" => 2, "totals" => totals(200)}]}
  normal = fixture(requirement, allowed, checkout)
  expect(normal)
  %w[EUR JPY].each { |currency| expect(fixture(requirement, allowed, checkout.merge("currency" => currency)), currency: currency) }
  s01 = fixture(requirement.merge("id" => 123), allowed, checkout)
  # Literal official schema rule: line_item_requirements.id type=string.
  decoded_open = JSON.parse(Base64.urlsafe_decode64(s01[:root_presentation].split("~")[1]))[1]
  assert(decoded_open["constraints"][0]["items"][0]["id"] == 123)
  reject(s01, :invalid_scoped_schema)
  puts "S01 signed_root_sha256=#{Digest::SHA256.hexdigest(s01[:root_presentation])} binding=unverified requirement_id=Integer expected_schema_type=string result=invalid_scoped_schema"
  [nil, false, "", 1.0].each { |id| reject(fixture(requirement.merge("id" => id), allowed, checkout), :invalid_scoped_schema) }
  [nil, false, "2", 2.0, 0, -1].each { |q| reject(fixture(requirement.merge("quantity" => q), allowed, checkout), :invalid_scoped_schema) }
  reject(fixture(requirement.merge("quantity" => 1_000_001), allowed, checkout), :constraint_limit_exceeded)
  missing = copy(requirement); missing.delete("id")
  reject(fixture(missing, allowed, checkout), :invalid_scoped_schema)
  reject(fixture(requirement.merge("future" => true), allowed, checkout), :unsupported_scoped_profile)
  reject(fixture(requirement, allowed, checkout, ["checkout.future", "checkout.allowed_merchants"]), :unsupported_constraint)
  reject(fixture(requirement, allowed, checkout, ["checkout.line_items", "checkout.line_items"]), :unsupported_constraint)
  [123, nil, ""].each do |name|
    reject(fixture(requirement, [{"id" => "shop", "name" => name}], checkout), :invalid_scoped_schema)
  end
  reject(fixture(requirement, [{"id" => "other", "name" => "store"}], checkout), :constraint_mismatch)
  reject(fixture(requirement, [{"id" => "shop", "name" => "other"}], checkout), :constraint_mismatch)
  reject(fixture(requirement, [allowed[0].merge("website" => "extra")], checkout), :unsupported_scoped_profile)
  ["id", "title"].each do |field|
    [nil, 123, ""].each do |value|
      req = copy(requirement); req["acceptable_items"][0][field] = value
      reject(fixture(req, allowed, checkout), :invalid_scoped_schema)
    end
  end
  %w[id title].each do |field|
    changed = copy(checkout); changed["line_items"][0]["item"][field] = "other"
    reject(fixture(requirement, allowed, changed), :constraint_mismatch)
  end
  [nil, false, "2", 2.0, 0, -1].each do |q|
    changed = copy(checkout); changed["line_items"][0]["quantity"] = q
    reject(fixture(requirement, allowed, changed), :invalid_scoped_schema)
  end
  changed = copy(checkout); changed["line_items"][0]["quantity"] = 1
  reject(fixture(requirement, allowed, changed), :constraint_mismatch)
  [nil, false, "100", 100.0, -1].each do |price|
    changed = copy(checkout); changed["line_items"][0]["item"]["price"] = price
    reject(fixture(requirement, allowed, changed), :invalid_scoped_schema)
  end
  [nil, 123, "", "usd", "ZZZ"].each do |currency|
    reject(fixture(requirement, allowed, checkout.merge("currency" => currency)),
      currency.instance_of?(String) && !currency.empty? ? :unsupported_scoped_profile : :invalid_scoped_schema)
  end
  reject(fixture(requirement, allowed, checkout.merge("currency" => "JPY")), :currency_mismatch)
  reject(normal, :amount_mismatch, total: 201)
  [nil, {}, [200], [{"type" => "subtotal", "amount" => 200}]].each do |values|
    reject(fixture(requirement, allowed, checkout.merge("totals" => values)),
      values.instance_of?(Array) ? :unsupported_scoped_profile : :invalid_scoped_schema)
  end
  [totals(201), [{"type" => "subtotal", "amount" => 200}, {"type" => "total", "amount" => "200"}],
   [{"type" => "subtotal", "amount" => 200}, {"type" => "subtotal", "amount" => 200}],
   totals(200) + [{"type" => "tax", "amount" => 0}]].zip(
     [:amount_mismatch, :invalid_scoped_schema, :unsupported_scoped_profile, :unsupported_scoped_profile]).each do |values, code|
    reject(fixture(requirement, allowed, checkout.merge("totals" => values)), code)
  end
  changed = copy(checkout); changed["line_items"][0]["totals"] = totals(201)
  reject(fixture(requirement, allowed, changed), :amount_mismatch)
  [nil, {}, [{}]].each do |links|
    reject(fixture(requirement, allowed, checkout.merge("links" => links)), links.instance_of?(Array) ? :unsupported_scoped_profile : :invalid_scoped_schema)
  end
  [nil, {}, [], [checkout["line_items"][0], checkout["line_items"][0]]].each do |lines|
    reject(fixture(requirement, allowed, checkout.merge("line_items" => lines)), lines.instance_of?(Array) ? :unsupported_scoped_profile : :invalid_scoped_schema)
  end
  max = 9_007_199_254_740_991
  [[0, 2, 0], [100, 1_000_000, 100_000_000], [max, 1, max]].each do |price, quantity, total|
    req = requirement.merge("quantity" => quantity)
    changed = copy(checkout); line = changed["line_items"][0]
    line["item"]["price"] = price; line["quantity"] = quantity; line["totals"] = totals(total)
    changed["totals"] = totals(total)
    expect(fixture(req, allowed, changed), total: total)
  end
  [[max + 1, :constraint_limit_exceeded], [max, :constraint_limit_exceeded]].each do |price, code|
    changed = copy(checkout); changed["line_items"][0]["item"]["price"] = price
    reject(fixture(requirement, allowed, changed), code)
  end
  [nil, -1, 1.0, max + 1, true].each { |v| expect(normal, :constraint_context_unavailable, :unavailable, total: v) }
  [nil, "usd", "ZZZ", "USDX", Class.new(String).new("USD")].each { |v| expect(normal, :constraint_context_unavailable, :unavailable, currency: v) }
  # A crypto failure still precedes content checks; no parsing promotes trust.
  bad = normal.merge(trusted_merchant_public_key_pem: @agent.public_to_pem)
  reject(bad, :invalid_root_signature, precondition: false)
  expect(fixture(requirement.merge("id" => "r" * 256), allowed, checkout))
  reject(fixture(requirement.merge("id" => "r" * 257), allowed, checkout), :constraint_limit_exceeded)
  [nil, 123, ""].each do |id|
    changed = copy(checkout); changed["line_items"][0]["id"] = id
    reject(fixture(requirement, allowed, changed), :invalid_scoped_schema)
  end
  changed = copy(checkout); changed["merchant"]["name"] = 123
  reject(fixture(requirement, allowed, changed), :invalid_scoped_schema)
  [{"type" => "total"}, {"type" => "total", "amount" => 200, "display_text" => "extra"}].zip(
      [:invalid_scoped_schema, :unsupported_scoped_profile]).each do |entry, code|
    changed = checkout.merge("totals" => [totals(200)[0], entry])
    reject(fixture(requirement, allowed, changed), code)
  end
  changed = copy(checkout); changed["line_items"][0]["item"].delete("title")
  reject(fixture(requirement, allowed, changed), :invalid_scoped_schema)
  changed = copy(checkout); changed["line_items"][0]["item"]["image_url"] = "extra"
  reject(fixture(requirement, allowed, changed), :unsupported_scoped_profile)
  callbacks = 0
  spoof = +"ZZZ"
  spoof.define_singleton_method(:bytesize) { callbacks += 1; 3 }
  spoof.define_singleton_method(:byteslice) { |*_args| callbacks += 1; "USD" }
  expect(normal, :constraint_context_unavailable, :unavailable, currency: spoof)
  assert(callbacks.zero?)
  original = AP2MandateVerifier::ScopedConstraints.method(:check!)
  [LoadError, RuntimeError].each do |failure|
    begin
      AP2MandateVerifier::ScopedConstraints.define_singleton_method(:check!) { |**_args| raise failure, "hidden detail" }
      expect(normal, failure == LoadError ? :constraint_dependency_unavailable : :constraint_check_unavailable, :unavailable)
    ensure
      AP2MandateVerifier::ScopedConstraints.define_singleton_method(:check!, original)
    end
  end
  puts "PASS #{@cases} scoped constraint cases; fixed subset only; no full Schema/ALLOW/Evidence claim"
end
