# frozen_string_literal: true
require_relative "runtime_dependencies"
require_relative "../lib/ap2_mandate_verifier"
module BuyerTest
  B = AP2MandateVerifier::Buyer
  C = AP2MandateVerifier::CheckoutJWT
  R = AP2MandateVerifier::CheckoutReceipt
  def self.assert(value, label)
    raise "buyer: #{label}" unless value
  end
  def self.invalid
    yield
    raise "accepted invalid buyer input"
  rescue B::Invalid, C::Invalid, R::Invalid => e
    assert(e.cause.nil? && !e.message.include?("secret"), "redacted")
  end
  def self.checkout
    totals = [{"type" => "subtotal", "amount" => 100}, {"type" => "total", "amount" => 100}]
    {"id" => "office-1", "merchant" => {"id" => "shop", "name" => "Supplies"},
      "status" => "ready_for_complete", "currency" => "USD", "links" => [], "totals" => totals,
      "line_items" => [{"id" => "line-1", "item" => {"id" => "pen", "title" => "Office pen", "price" => 100},
        "quantity" => 1, "totals" => totals}]}
  end
  merchant = OpenSSL::PKey::EC.generate("prime256v1")
  provider = OpenSSL::PKey::EC.generate("prime256v1")
  wrong = OpenSSL::PKey::EC.generate("prime256v1").public_to_pem
  signed = C.sign(checkout: checkout, signer: C.es256_signer(private_key: merchant), public_key_pem: merchant.public_to_pem)
  checked = C.verify(jwt: signed.jwt, trusted_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop")
  assert(checked.verified? && checked.checkout.frozen? && checked.checkout["line_items"][0].frozen?, "immutable checkout")
  invalid { C.verify(jwt: signed.jwt, trusted_public_key_pem: wrong, expected_merchant_id: "shop") }
  invalid { C.verify(jwt: signed.jwt, trusted_public_key_pem: merchant.public_to_pem, expected_merchant_id: "other") }
  issue = {checkout_jwt: signed.jwt, approved_checkout_jwt: signed.jwt,
    trusted_merchant_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop",
    issued_at: 1_800_000_000, expires_at: 1_800_000_060,
    signer: C.es256_signer(private_key: provider), public_key_pem: provider.public_to_pem}
  issued = B.issue_closed(**issue)
  wire = B.present_closed(closed_sd_jwt: issued.closed_sd_jwt)
  args = {closed_sd_jwt: wire, trusted_provider_public_key_pem: provider.public_to_pem,
    trusted_merchant_public_key_pem: merchant.public_to_pem, expected_checkout_jwt: signed.jwt,
    expected_merchant_id: "shop", verified_at: 1_800_000_000}
  assert(B.verify(**args).verified?, "direct full verification")
  assert(B.verify(**args).checkout == checkout, "checked content")
  invalid { B.issue_closed(**issue.merge(approved_checkout_jwt: "secret")) }
  invalid { B.issue_closed(**issue.merge(expires_at: 1_800_000_601)) }
  invalid { B.issue_closed(**issue.merge(signer: ->(_) { raise "secret" })) }
  invalid { B.issue_closed(**issue.merge(public_key_pem: wrong)) }
  invalid { B.issue_closed(**issue.merge(approved: true)) }
  {trusted_provider_public_key_pem: wrong, trusted_merchant_public_key_pem: wrong,
   expected_checkout_jwt: "secret", expected_merchant_id: "other", verified_at: 1_800_000_060}.each do |field, value|
    result = B.verify(**args.merge(field => value))
    assert(!result.verified? && result.checkout.nil?, "reject #{field}")
  end
  segments = wire.split("~", -1)
  [segments[0] + "~", segments[0..1].join("~") + "~", wire + "extra~", wire.chomp("~"),
   segments.values_at(0,2,1,3).join("~"), wire.sub("~", "~~"), "secret", "x" * 32_769].each do |bad|
    assert(!B.verify(**args.merge(closed_sd_jwt: bad)).verified?, "bad wire")
    invalid { B.present_closed(closed_sd_jwt: bad) }
  end
  # Authentic signature but malformed signed grammar must reject.
  payload = JWT.decode(segments[0], nil, false).first
  [payload.merge("aud" => "shop"), payload.merge("_sd_alg" => "sha-512"),
   payload.merge("delegate_payload" => payload["delegate_payload"] * 2)].each do |bad|
    jwt = JWT.encode(bad, provider, "ES256", {"typ" => "example+sd-jwt"})
    assert(!B.verify(**args.merge(closed_sd_jwt: [jwt, *segments[1..]].join("~"))).verified?, "signed malformed")
  end
  altered = segments.dup
  altered[0] = JWT.encode(payload, merchant, "ES256", {"typ" => "example+sd-jwt"})
  assert(!B.verify(**args.merge(closed_sd_jwt: altered.join("~"))).verified?, "wrong authentic signer")
  assert(!B.verify(**args.merge(verified_at: 1_799_999_999)).verified?, "future")
  ref = Base64.urlsafe_encode64(Digest::SHA256.digest(wire), padding: false)
  assert(R.reference(closed_sd_jwt: wire, profile_ref: B::PROFILE_REF) == ref, "entire SD wire reference")
  invalid { R.reference(closed_sd_jwt: wire) } # Existing profile remains strict.
  %w[Success Error].each do |outcome|
    fields = outcome == "Success" ? {order_id: "office-1"} : {error: "declined", error_description: "Application declined"}
    receipt = R.sign(closed_sd_jwt: wire, profile_ref: B::PROFILE_REF, issuer: "shop", outcome: outcome,
      issued_at: 1_800_000_001, signer: C.es256_signer(private_key: merchant), public_key_pem: merchant.public_to_pem, **fields)
    verify = {jwt: receipt.jwt, closed_sd_jwt: wire, profile_ref: B::PROFILE_REF,
      trusted_public_key_pem: merchant.public_to_pem, expected_issuer: "shop", not_before: 1_800_000_000,
      not_after: 1_800_000_060, verified_at: 1_800_000_002}
    result = R.verify(**verify)
    assert(result.verified? && result.purchase_succeeded? == (outcome == "Success"), "receipt outcome")
    assert(!R.verify(**verify.merge(trusted_public_key_pem: wrong)).verified?, "receipt wrong key")
    assert(!R.verify(**verify.merge(closed_sd_jwt: B.issue_closed(**issue).closed_sd_jwt)).verified?, "receipt different salt")
  end
  puts "PASS Direct buyer issuance, presentation, verification, receipt, redaction and negatives"
end

module BuyerMultiTest
  B = AP2MandateVerifier::Buyer
  C = AP2MandateVerifier::CheckoutJWT
  R = AP2MandateVerifier::CheckoutReceipt
  def self.assert(value) = BuyerTest.assert(value, "multi-item acceptance")
  def self.totals(n) = %w[subtotal total].map { |type| {"type" => type, "amount" => n} }
  def self.model(count)
    lines = Array.new(count) do |i|
      quantity = i + 1
      {"id" => "row#{i}", "item" => {"id" => "product#{i % 2}", "title" => "Office supplies", "price" => 100},
        "quantity" => quantity, "totals" => totals(quantity * 100)}
    end
    BuyerTest.checkout.merge("line_items" => lines, "totals" => totals(lines.sum { |l| l["quantity"] * 100 }))
  end
  merchant, provider = Array.new(2) { OpenSSL::PKey::EC.generate("prime256v1") }
  merchant_signer = C.es256_signer(private_key: merchant)
  issue = {trusted_merchant_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop",
    issued_at: 1_800_000_000, expires_at: 1_800_000_060,
    signer: C.es256_signer(private_key: provider), public_key_pem: provider.public_to_pem}
  verify = {trusted_provider_public_key_pem: provider.public_to_pem,
    trusted_merchant_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop", verified_at: 1_800_000_000}
  [model(3), model(8), model(3).merge("line_items" => model(3)["line_items"].reverse)].each do |checkout|
    signed = C.sign(checkout: checkout, signer: merchant_signer, public_key_pem: merchant.public_to_pem, profile_ref: B::CHECKOUT_PROFILE)
    wire = B.present_closed(closed_sd_jwt: B.issue_closed(**issue, checkout_jwt: signed.jwt, approved_checkout_jwt: signed.jwt).closed_sd_jwt)
    assert(B.verify(**verify, closed_sd_jwt: wire, expected_checkout_jwt: signed.jwt).checkout == checkout)
    %w[Success Error].each do |outcome|
      fields = outcome == "Success" ? {order_id: "office-1"} : {error: "declined", error_description: "No purchase"}
      receipt = R.sign(closed_sd_jwt: wire, profile_ref: B::PROFILE_REF, issuer: "shop", outcome: outcome,
        issued_at: 1_800_000_000, signer: merchant_signer, public_key_pem: merchant.public_to_pem, **fields)
      result = R.verify(jwt: receipt.jwt, closed_sd_jwt: wire, profile_ref: B::PROFILE_REF,
        trusted_public_key_pem: merchant.public_to_pem, expected_issuer: "shop", not_before: 1_800_000_000,
        not_after: 1_800_000_060, verified_at: 1_800_000_000)
      assert(result.verified? && result.purchase_rejected? == (outcome == "Error"))
    end
  end
  malformed = [model(9), model(0)]
  [->(c) { c["line_items"][1]["id"] = "row0" },
   ->(c) { c["line_items"][0]["quantity"] = 0 },
   ->(c) { c["line_items"][0]["quantity"] = 1_000_001 },
   ->(c) { c["line_items"][0]["quantity"] = 1.5 },
   ->(c) { c["line_items"][0]["item"]["price"] = 9_007_199_254_740_992 },
   ->(c) { c["line_items"][0]["totals"] = totals(99) },
   ->(c) { c["totals"] = totals(99) },
   ->(c) { c["currency"] = "XXX" }, ->(c) { c["links"] = [{"url" => "secret"}] }].each do |change|
    value = model(3); change.call(value); malformed << value
  end
  malformed.each do |checkout|
    # Bypass authoring validation to exercise signed hostile inputs at both ends.
    jwt = JWT.encode(checkout, merchant, "ES256", {"typ" => "JWT"})
    BuyerTest.invalid { B.issue_closed(**issue, checkout_jwt: jwt, approved_checkout_jwt: jwt) }
    encode = ->(value) { Base64.urlsafe_encode64(JSON.generate(value), padding: false) }
    digest = ->(value) { Base64.urlsafe_encode64(Digest::SHA256.digest(value), padding: false) }
    leaf = encode.call(["s" * 22, "checkout_jwt", jwt])
    content = encode.call(["t" * 22, {"vct" => "mandate.checkout.1", "checkout_hash" => digest.call(jwt),
      "iat" => 1_800_000_000, "exp" => 1_800_000_060, "_sd" => [digest.call(leaf)]}])
    root = JWT.encode({"delegate_payload" => [{"..." => digest.call(content)}], "_sd_alg" => "sha-256"},
      provider, "ES256", {"typ" => "example+sd-jwt"})
    wire = "#{root}~#{content}~#{leaf}~"
    assert(!B.verify(**verify, closed_sd_jwt: wire, expected_checkout_jwt: jwt).verified?)
    BuyerTest.invalid { R.reference(closed_sd_jwt: wire, profile_ref: B::PROFILE_REF) }
  end
  puts "PASS multi-product/multi-line Direct flow 3/8 lines, repeated products, reordered lines, both receipts and signed malformed inputs"
end
