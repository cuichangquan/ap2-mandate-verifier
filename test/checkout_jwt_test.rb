# frozen_string_literal: true
require_relative "input_builder_test"
module CheckoutJWTTest
  C = AP2MandateVerifier::CheckoutJWT
  def self.assert(ok, label)
    raise "checkout jwt: #{label}" unless ok
  end
  def self.invalid
    yield
    raise "checkout jwt accepted invalid input"
  rescue C::Invalid => e
    assert(e.message == "invalid checkout signing information" && e.cause.nil?, "no input leak")
  end
  model = HostBindingTest.fixture
  claims = JWT.decode(model[:inputs][:host_checkout_jws], nil, false).first
  key = OpenSSL::PKey::EC.generate("prime256v1")
  public_pem = key.public_to_pem
  signer = C.es256_signer(private_key: key)
  signed = C.sign(checkout: claims, signer: signer, public_key_pem: public_pem)
  assert(signed.frozen? && signed.jwt.frozen? && signed.checkout_hash.frozen?, "immutable")
  assert(JWT.decode(signed.jwt, key, true, algorithms: ["ES256"]).first == claims, "independent decode")
  assert(signed.checkout_hash == Base64.urlsafe_encode64(Digest::SHA256.digest(signed.jwt), padding: false), "original wire hash")
  claims["id"] = "later change"
  assert(JWT.decode(signed.jwt, key, true, algorithms: ["ES256"]).first["id"] == "order", "snapshot")
  claims["id"] = "order"
  [nil, {}, claims.merge("extra" => true), claims.merge("line_items" => []),
   claims.merge("status" => "completed"), claims.merge("totals" => [])].each do |value|
    invalid { C.sign(checkout: value, signer: signer, public_key_pem: public_pem) }
  end
  [->(_input) { "x" * 64 }, ->(_input) { raise "secret" }, ->(_input) { "x" * 65 }].each do |bad|
    invalid { C.sign(checkout: claims, signer: bad, public_key_pem: public_pem) }
  end
  invalid { C.sign(checkout: claims, signer: signer, public_key_pem: OpenSSL::PKey::EC.generate("prime256v1").public_to_pem) }
  invalid { C.es256_signer(private_key: OpenSSL::PKey::EC.generate("secp384r1")) }
  # Connect the new merchant wire through the pre-existing complete verifier.
  keys = HostBindingTest.instance_variable_get(:@keys)
  generated = C.sign(checkout: claims, signer: C.es256_signer(private_key: keys[2]), public_key_pem: keys[2].public_to_pem)
  terminal = JWT.decode(model[:inputs][:terminal_jws], nil, false).first
  terminal["delegate_payload"][0].merge!("checkout_jwt" => generated.jwt, "checkout_hash" => generated.checkout_hash)
  model[:inputs].merge!(host_checkout_jws: generated.jwt,
    terminal_jws: HostBindingTest.sign(keys[1], terminal, "kb+sd-jwt"))
  digest = Digest::SHA256.hexdigest(generated.jwt)
  model[:host]["binding"]["checkout_jwt_digest"] = digest
  model[:host]["challenge"]["B"]["checkout_jwt_digest"] = digest
  result = AP2MandateVerifier.verify_checkout(**HostBindingTest.args(model))
  assert(result.success?, "new checkout through complete existing verifier")
  builder = InputBuilderTest.setup(model)
  assert(AP2MandateVerifier::InputBuilder.verify(**builder).success?, "existing InputBuilder verifies generated checkout")
  puts "PASS CheckoutJWT signing, immutable original wire, negative inputs and existing Verifier/InputBuilder integration"
end
