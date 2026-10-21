# frozen_string_literal: true
require "json"
require "base64"
require "openssl"
require "digest"
require_relative "../lib/ap2_mandate_verifier"

module PurchaseTest
  @cases = 0
  def self.assert(ok) = (raise "purchase assertion failed" unless ok)
  def self.b64(bytes) = Base64.urlsafe_encode64(bytes, padding: false)
  def self.hash(bytes) = b64(Digest::SHA256.digest(bytes))
  def self.copy(value) = Marshal.load(Marshal.dump(value))
  def self.sign(key, value, typ, header = {})
    encoded = b64(JSON.generate({"alg" => "ES256", "typ" => typ}.merge(header))) + "." +
      b64(value.instance_of?(String) ? value : JSON.generate(value))
    numbers = OpenSSL::ASN1.decode(key.sign("SHA256", encoded)).value
    encoded + "." + b64(numbers.map { |n| n.value.to_s(2).rjust(32, "\x00") }.join)
  end
  def self.jwk(key)
    point = key.public_key.to_octet_string(:uncompressed)
    {"kty" => "EC", "crv" => "P-256", "x" => b64(point.byteslice(1, 32)), "y" => b64(point.byteslice(33, 32))}
  end
  def self.root(key, open)
    sku = b64(JSON.generate(["sku-salt", {"id" => "sku", "title" => "item"}]))
    merchant = b64(JSON.generate(["merchant-salt", {"id" => "merchant", "name" => "shop"}]))
    data = copy(open).merge("constraints" => [
      {"type" => "checkout.line_items", "items" => [{"id" => "req", "quantity" => 1, "acceptable_items" => [{"..." => hash(sku)}]}]},
      {"type" => "checkout.allowed_merchants", "allowed" => [{"..." => hash(merchant)}]}
    ])
    opening = b64(JSON.generate(["open-salt", data]))
    sign(key, {"delegate_payload" => [{"..." => hash(opening)}], "_sd_alg" => "sha-256"}, "example+sd-jwt") +
      "~" + [opening, sku, merchant].join("~") + "~"
  end
  def self.expect(inputs, code = :purchase_binding_verified_only, status = :unverified)
    result = AP2MandateVerifier.verify_purchase_binding(**inputs)
    raise "case #{@cases + 1}: expected #{status}/#{code}, got #{result.status}/#{result.code}" unless
      result.status == status && result.code == code
    assert(!result.success? && result.evidence.nil? && result.frozen?)
    @cases += 1
  end
  def self.reject(inputs, code) = expect(inputs, code, :rejected)
  def self.oracle(jws, key)
    a, b, c = jws.split(".")
    sig = Base64.urlsafe_decode64(c)
    asn = OpenSSL::ASN1::Sequence.new([0, 32].map { |i| OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(sig.byteslice(i, 32), 2)) }).to_der
    OpenSSL::PKey.read(key.public_to_pem).verify("SHA256", asn, a + "." + b)
  end
  def self.damage(jws)
    a, b, c = jws.split(".")
    sig = Base64.urlsafe_decode64(c); sig.setbyte(0, sig.getbyte(0) ^ 1)
    a + "." + b + "." + b64(sig)
  end

  # Fresh in-memory private keys only, no secret files/output/network.
  issuer, agent, merchant, other = Array.new(4) { OpenSSL::PKey::EC.generate("prime256v1") }
  now = 1_800_000_000
  open = {"vct" => "mandate.checkout.open.1", "iat" => now - 100, "exp" => now + 100,
          "cnf" => {"jwk" => jwk(agent)}}
  root_wire = root(issuer, open)
  checkout = {"id" => "order1", "merchant" => {"id" => "merchant", "name" => "shop"},
              "line_items" => [{"id" => "line1"}], "currency" => "USD", "totals" => [],
              "links" => [], "status" => "ready_for_complete"}
  checkout_wire = sign(merchant, checkout, "JWT")
  closed = {"vct" => "mandate.checkout.1", "iat" => open["iat"], "exp" => open["exp"],
            "checkout_jwt" => checkout_wire, "checkout_hash" => hash(checkout_wire)}
  terminal = {"iat" => now, "aud" => "host", "nonce" => "challenge1", "sd_hash" => hash(root_wire),
              "delegate_payload" => [closed]}
  terminal_wire = sign(agent, terminal, "kb+sd-jwt")
  inputs = {root_presentation: root_wire, terminal_jws: terminal_wire, host_checkout_jws: checkout_wire,
            trusted_issuer_public_key_pem: issuer.public_to_pem, expected_agent_public_key_pem: agent.public_to_pem,
            trusted_merchant_public_key_pem: merchant.public_to_pem, expected_aud: "host", expected_nonce: "challenge1",
            verified_at: now, expected_checkout_id: "order1", expected_merchant_id: "merchant"}
  [root_wire.split("~").first, terminal_wire, checkout_wire].zip([issuer, agent, merchant]).each do |wire, key|
    assert(oracle(wire, key) && !oracle(wire, other))
  end
  expect(inputs)
  puts "PURCHASE root_sha256=#{Digest::SHA256.hexdigest(root_wire)} terminal_sha256=#{Digest::SHA256.hexdigest(terminal_wire)} checkout_sha256=#{Digest::SHA256.hexdigest(checkout_wire)}"
  reject(inputs.merge(expected_agent_public_key_pem: other.public_to_pem), :agent_key_mismatch)
  reject(inputs.merge(terminal_jws: sign(other, terminal, "kb+sd-jwt")), :invalid_root_signature)
  reject(inputs.merge(trusted_issuer_public_key_pem: other.public_to_pem), :invalid_root_signature)
  reject(inputs.merge(trusted_merchant_public_key_pem: other.public_to_pem), :invalid_root_signature)
  reject(inputs.merge(terminal_jws: damage(terminal_wire)), :invalid_root_signature)
  a, _b, c = terminal_wire.split(".")
  tampered_terminal = a + "." + b64(JSON.generate(terminal.merge("aud" => "other"))) + "." + c
  assert(!oracle(tampered_terminal, agent))
  reject(inputs.merge(terminal_jws: tampered_terminal), :invalid_root_signature)
  # Authenticated reuse against a different Host transaction or purchaser.
  reject(inputs.merge(expected_aud: "other-host"), :audience_mismatch)
  reject(inputs.merge(expected_nonce: "challenge2"), :nonce_mismatch)
  reject(inputs.merge(expected_checkout_id: "order2"), :checkout_identity_mismatch)
  reject(inputs.merge(expected_merchant_id: "other-merchant"), :checkout_identity_mismatch)
  new_checkout = sign(merchant, checkout.merge("id" => "order2"), "JWT")
  reject(inputs.merge(host_checkout_jws: new_checkout), :checkout_binding_mismatch)
  new_root = root(issuer, open.merge("exp" => now + 101))
  reject(inputs.merge(root_presentation: new_root), :root_binding_mismatch)
  ["sd_hash", "aud", "nonce"].zip(["bad", "other-host", "challenge2"]).each do |claim, value|
    signed = sign(agent, terminal.merge(claim => value), "kb+sd-jwt")
    assert(oracle(signed, agent))
    reject(inputs.merge(terminal_jws: signed), {"sd_hash" => :root_binding_mismatch, "aud" => :audience_mismatch, "nonce" => :nonce_mismatch}.fetch(claim))
  end
  [now + 1, now - 301, "1800000000", 1.5, nil].each do |iat|
    reject(inputs.merge(terminal_jws: sign(agent, terminal.merge("iat" => iat), "kb+sd-jwt")), :invalid_purchase_time)
  end
  [[now + 1, now + 100], [now - 100, now], [now - 8000, now + 1], [0.0, now + 1]].each do |iat, exp|
    reject(inputs.merge(root_presentation: root(issuer, open.merge("iat" => iat, "exp" => exp))), :invalid_purchase_time)
  end
  [closed.merge("exp" => now + 99), closed.merge("iat" => now - 99)].each do |value|
    reject(inputs.merge(terminal_jws: sign(agent, terminal.merge("delegate_payload" => [value]), "kb+sd-jwt")), :delegation_claim_mismatch)
  end
  [closed.merge("exp" => now), closed.merge("iat" => "old")].each do |value|
    reject(inputs.merge(terminal_jws: sign(agent, terminal.merge("delegate_payload" => [value]), "kb+sd-jwt")), :invalid_purchase_time)
  end
  [closed.merge("checkout_hash" => "wrong"), closed.merge("checkout_jwt" => checkout_wire + " ")].each do |value|
    reject(inputs.merge(terminal_jws: sign(agent, terminal.merge("delegate_payload" => [value]), "kb+sd-jwt")), :checkout_binding_mismatch)
  end
  [[], [closed, closed], [closed.merge("cnf" => {"jwk" => jwk(other)})],
   [closed.merge("vct" => "unknown")], [closed.merge("unknown" => true)]].each do |items|
    reject(inputs.merge(terminal_jws: sign(agent, terminal.merge("delegate_payload" => items), "kb+sd-jwt")), :unsupported_purchase_profile)
  end
  [terminal.merge("issuer_jwt_hash" => "alternate"), terminal.merge("extra" => true)].each do |value|
    reject(inputs.merge(terminal_jws: sign(agent, value, "kb+sd-jwt")), :unsupported_purchase_profile)
  end
  reject(inputs.merge(terminal_jws: sign(agent, terminal, "kb+sd-jwt+kb")), :unsupported_root_type)
  reject(inputs.merge(terminal_jws: terminal_wire + "~"), :invalid_root_jws)
  [open.merge("vct" => "unknown"), open.merge("extra" => true),
   open.merge("cnf" => {"jwk" => jwk(agent).merge("d" => "secret")})].each do |value|
    reject(inputs.merge(root_presentation: root(issuer, value)), :unsupported_purchase_profile)
  end
  reject(inputs.merge(root_presentation: root(issuer, open.merge("cnf" => {"jwk" => jwk(other)}))), :agent_key_mismatch)
  # Signed merchant variants are rebound by Agent; policy rejects after crypto.
  [[checkout.merge("id" => "order2"), :checkout_identity_mismatch],
   [checkout.merge("merchant" => {"id" => "other", "name" => "other"}), :checkout_identity_mismatch],
   [checkout.merge("status" => "completed"), :unsupported_purchase_profile],
   [checkout.merge("extra" => true), :unsupported_purchase_profile]].each do |value, code|
    wire = sign(merchant, value, "JWT")
    c = closed.merge("checkout_jwt" => wire, "checkout_hash" => hash(wire))
    signed = sign(agent, terminal.merge("delegate_payload" => [c]), "kb+sd-jwt")
    assert(oracle(wire, merchant) && oracle(signed, agent))
    reject(inputs.merge(host_checkout_jws: wire, terminal_jws: signed), code)
  end
  [sign(other, checkout, "JWT"), damage(checkout_wire), sign(merchant, checkout, "unknown"),
   sign(merchant, checkout, "JWT", "jwk" => jwk(other))].zip([:invalid_root_signature, :invalid_root_signature, :unsupported_root_type, :unsupported_root_header]).each do |wire, code|
    c = closed.merge("checkout_jwt" => wire, "checkout_hash" => hash(wire))
    reject(inputs.merge(host_checkout_jws: wire, terminal_jws: sign(agent, terminal.merge("delegate_payload" => [c]), "kb+sd-jwt")), code)
  end
  duplicate_json = JSON.generate(terminal).sub('"aud":"host"', '"aud":"host","\\u0061ud":"host"')
  reject(inputs.merge(terminal_jws: sign(agent, duplicate_json, "kb+sd-jwt")), :duplicate_key)
  reject(inputs.merge(terminal_jws: sign(agent, terminal, "kb+sd-jwt", "jku" => "https://example.invalid")), :unsupported_root_header)
  [:expected_nonce, :expected_aud, :expected_checkout_id, :expected_merchant_id, :host_checkout_jws,
   :trusted_issuer_public_key_pem, :expected_agent_public_key_pem, :trusted_merchant_public_key_pem].each do |name|
    expect(inputs.merge(name => nil), :purchase_context_unavailable, :unavailable)
  end
  [-1, 4_102_444_801, "now", nil].each { |now_value| expect(inputs.merge(verified_at: now_value), :purchase_context_unavailable, :unavailable) }
  reject(inputs.merge(root_presentation: "x" * 131_073), :input_too_large)
  reject(inputs.merge(terminal_jws: "x" * 32_769), :input_too_large)
  expect(inputs.merge(host_checkout_jws: "x" * 16_385), :purchase_context_unavailable, :unavailable)
  expect(inputs.merge(expected_nonce: "x" * 513), :purchase_context_unavailable, :unavailable)
  # Terminal freshness boundary and strict 7200-second Open/Closed validity.
  [[now - 500, now + 100, now - 300, nil],
   [now - 500, now + 100, now - 301, :invalid_purchase_time],
   [now - 100, now + 7100, now, nil],
   [now - 100, now + 7101, now, :invalid_purchase_time]].each do |iat, exp, terminal_iat, rejection|
    r = root(issuer, open.merge("iat" => iat, "exp" => exp))
    t = terminal.merge("iat" => terminal_iat, "sd_hash" => hash(r),
      "delegate_payload" => [closed.merge("iat" => iat, "exp" => exp)])
    modified = inputs.merge(root_presentation: r, terminal_jws: sign(agent, t, "kb+sd-jwt"))
    rejection ? reject(modified, rejection) : expect(modified)
  end
  a, _b, c = checkout_wire.split(".")
  tampered_checkout = a + "." + b64(JSON.generate(checkout.merge("id" => "order2"))) + "." + c
  assert(!oracle(tampered_checkout, merchant))
  rebound = closed.merge("checkout_jwt" => tampered_checkout, "checkout_hash" => hash(tampered_checkout))
  reject(inputs.merge(host_checkout_jws: tampered_checkout,
    terminal_jws: sign(agent, terminal.merge("delegate_payload" => [rebound]), "kb+sd-jwt")), :invalid_root_signature)
  # Exact duplicate-key bytes in Merchant JWT fail after Agent binding succeeds.
  malformed = sign(merchant, JSON.generate(checkout).sub('"id":"order1"', '"id":"order1","id":"order1"'), "JWT")
  rebound = closed.merge("checkout_jwt" => malformed, "checkout_hash" => hash(malformed))
  reject(inputs.merge(host_checkout_jws: malformed,
    terminal_jws: sign(agent, terminal.merge("delegate_payload" => [rebound]), "kb+sd-jwt")), :duplicate_key)
  original_root_check = AP2MandateVerifier::RootDisclosures.method(:verified_root!)
  mutable_nonce = +"challenge1"
  mutable_checkout = checkout_wire.dup
  begin
    AP2MandateVerifier::RootDisclosures.define_singleton_method(:verified_root!) do |*args|
      mutable_nonce.replace("replaced")
      mutable_checkout.replace("replaced")
      original_root_check.call(*args)
    end
    expect(inputs.merge(expected_nonce: mutable_nonce, host_checkout_jws: mutable_checkout))
  ensure
    AP2MandateVerifier::RootDisclosures.define_singleton_method(:verified_root!, original_root_check)
  end
  callbacks = 0
  spoof = +"wrong"
  spoof.define_singleton_method(:bytesize) { callbacks += 1; 10 }
  spoof.define_singleton_method(:byteslice) { |*_args| callbacks += 1; "challenge1" }
  reject(inputs.merge(expected_nonce: spoof), :nonce_mismatch)
  assert(callbacks.zero?)
  original_check = AP2MandateVerifier::PurchaseBinding.method(:check!)
  [LoadError, RuntimeError].each do |failure|
    begin
      AP2MandateVerifier::PurchaseBinding.define_singleton_method(:check!) { |**_args| raise failure, "hidden detail" }
      expect(inputs, failure == LoadError ? :purchase_dependency_unavailable : :purchase_check_unavailable, :unavailable)
    ensure
      AP2MandateVerifier::PurchaseBinding.define_singleton_method(:check!, original_check)
    end
  end
  # Explicitly demonstrate stage6 is still required: monetary semantics ignored.
  untouched = copy(inputs)
  expect(inputs)
  assert(inputs == untouched)
  puts "PASS #{@cases} purchase binding cases; no Schema/constraints/Host ALLOW/Evidence claim"
end
