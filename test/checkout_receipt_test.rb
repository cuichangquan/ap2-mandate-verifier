# frozen_string_literal: true
require_relative "checkout_jwt_test"
module CheckoutReceiptTest
  R = AP2MandateVerifier::CheckoutReceipt
  @checks = 0
  def self.assert(ok, label)
    @checks += 1
    raise "receipt: #{label}" unless ok
  end
  def self.invalid
    yield
    raise "receipt accepted invalid input"
  rescue R::Invalid => e
    assert(e.message == "invalid checkout receipt information" && e.cause.nil?, "no input leak")
  end
  model = HostBindingTest.fixture
  wire = model[:inputs][:terminal_jws] + "~" # Explicit SD-JWT serialization.
  key = OpenSSL::PKey::EC.generate("prime256v1")
  signer = AP2MandateVerifier::CheckoutJWT.es256_signer(private_key: key)
  n = HostBindingTest::N
  signing = {closed_sd_jwt: wire, issuer: "shop", issued_at: n, signer: signer, public_key_pem: key.public_to_pem}
  verify = {closed_sd_jwt: wire, trusted_public_key_pem: key.public_to_pem, expected_issuer: "shop",
    not_before: n - 60, not_after: n + 60, verified_at: n}
  reference = Base64.urlsafe_encode64(Digest::SHA256.digest(wire), padding: false)
  assert(R.reference(closed_sd_jwt: wire) == reference, "independent original SD-JWT hash")
  assert(reference != HostBindingTest.sdhash(model[:inputs][:terminal_jws]), "compact JWT hash differs")
  keys = HostBindingTest.instance_variable_get(:@keys)
  terminal_claims = JWT.decode(model[:inputs][:terminal_jws], nil, false).first
  checkout_claims = JWT.decode(model[:inputs][:host_checkout_jws], nil, false).first
  checkout_kid = JWT.encode(checkout_claims, keys[2], "ES256", {"typ" => "JWT", "kid" => "merchant-key"})
  terminal_claims["delegate_payload"][0].merge!("checkout_jwt" => checkout_kid, "checkout_hash" => HostBindingTest.sdhash(checkout_kid))
  terminal_kid = JWT.encode(terminal_claims, keys[1], "ES256", {"typ" => "kb+sd-jwt", "kid" => "agent-key"})
  kid_wire = terminal_kid + "~"
  assert(R.reference(closed_sd_jwt: kid_wire) == HostBindingTest.sdhash(kid_wire), "existing optional kid grammar")
  [JWT.encode(terminal_claims, keys[1], "ES256", {"typ" => "wrong"}) + "~",
   JWT.encode(terminal_claims.merge("_sd_alg" => "sha-512"), keys[1], "ES256", {"typ" => "kb+sd-jwt"}) + "~"].each do |bad|
    invalid { R.reference(closed_sd_jwt: bad) }
  end
  {"Success" => {order_id: "order"}, "Error" => {error: "declined", error_description: "Application declined"}}.each do |outcome, fields|
    signed = R.sign(**signing, outcome: outcome, **fields)
    assert(signed.frozen? && signed.jwt.frozen? && signed.reference == reference, "signed snapshot")
    result = R.verify(**verify, jwt: signed.jwt)
    assert(result.verified? && result.frozen? && result.outcome == outcome, "authentic result")
    assert(result.purchase_succeeded? == (outcome == "Success"), "separate purchase success")
    assert(result.purchase_rejected? == (outcome == "Error"), "authentic rejection")
    claims = JWT.decode(signed.jwt, key, true, algorithms: ["ES256"]).first
    assert(claims["reference"] == reference && claims["status"] == outcome, "independent signature claims")
    [verify.merge(expected_issuer: "other"), verify.merge(trusted_public_key_pem: OpenSSL::PKey::EC.generate("prime256v1").public_to_pem),
     verify.merge(verified_at: n - 1), verify.merge(not_before: n + 1), verify.merge(not_after: n - 1),
     verify.merge(closed_sd_jwt: wire.delete_suffix("~"))].each do |args|
      failed = R.verify(**args, jwt: signed.jwt)
      assert(!failed.verified? && !failed.purchase_succeeded? && !failed.purchase_rejected? && failed.outcome.nil?, "invalid trust/time/wire")
    end
    mutations = [claims.merge("reference" => HostBindingTest.sdhash(model[:inputs][:terminal_jws])),
      claims.merge("reference" => HostBindingTest.sdhash(model[:inputs][:root_presentation] + wire)),
      claims.merge("iss" => "other"), claims.merge("iat" => n + 1), claims.merge("iat" => n - 61),
      claims.merge("status" => "success"), claims.reject { |k, _| k == "iat" },
      claims.reject { |k, _| k == "status" }.merge("result" => "success"),
      claims.merge("unexpected" => "value"), claims.merge(outcome == "Success" ? {"error" => "no"} : {"order_id" => "other"})]
    mutations.each do |payload|
      jwt = HostBindingTest.sign(key, payload, "JWT")
      assert(!R.verify(**verify, jwt: jwt).verified?, "signed semantic negative")
    end
    damaged = signed.jwt.dup; damaged[-2] = damaged[-2] == "A" ? "B" : "A"
    assert(!R.verify(**verify, jwt: damaged).verified?, "tampered signature")
  end
  [wire.delete_suffix("~"), wire + "~", "unparseable~", model[:inputs][:root_presentation] + "~" + wire,
   wire.delete_suffix("~") + "~YWJj~", "x" * 32_770].each { |bad| invalid { R.reference(closed_sd_jwt: bad) } }
  [signing.merge(signer: ->(_) { raise "secret" }), signing.merge(signer: ->(_) { "x" * 64 }),
   signing.merge(public_key_pem: OpenSSL::PKey::EC.generate("prime256v1").public_to_pem)].each do |args|
    invalid { R.sign(**args, outcome: "Success", order_id: "order") }
  end
  invalid { R.sign(**signing, outcome: "Success") }
  invalid { R.sign(**signing, outcome: "Error", error: "no") }
  invalid { R.sign(**signing, outcome: "Success", order_id: "order", error: "no") }
  invalid { R.sign(**signing, outcome: "success", order_id: "order") }
  invalid { R.sign(**signing, outcome: "Success", order_id: "order", issued_at: -1) }
  invalid { R.reference(**{"private-secret-field" => wire}) }
  assert(!R.verify(**{"private-secret-field" => wire}).verified?, "argument shape fail closed")
  puts "PASS #{@checks} CheckoutReceipt reference/signing/authentication/business outcome checks"
end
