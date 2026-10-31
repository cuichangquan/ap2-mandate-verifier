# frozen_string_literal: true
# Run with the installed published 0.5.0 Gem; no source load-path substitution.
require "ap2_mandate_verifier"
require "openssl"
require "jwt"

key = OpenSSL::PKey::EC.generate("prime256v1") # Synthetic, in memory only.
agent = OpenSSL::PKey::EC.generate("prime256v1")
now = 1_800_000_000
public_pem = key.public_to_pem # Synthetic enrollment; real apps use independent registration.
signing = AP2MandateVerifier::CheckoutJWT
signer = signing.es256_signer(private_key: key)
totals = [{"type" => "subtotal", "amount" => 100}, {"type" => "total", "amount" => 100}]
checkout = {"id" => "order-1", "merchant" => {"id" => "shop", "name" => "Demo shop"},
  "status" => "ready_for_complete", "currency" => "USD", "links" => [], "totals" => totals,
  "line_items" => [{"id" => "line-1", "item" => {"id" => "sku", "title" => "Sample", "price" => 100},
    "quantity" => 1, "totals" => totals}]}
signed = signing.sign(checkout: checkout, signer: signer, public_key_pem: public_pem)
puts "checkout_segments=#{signed.jwt.split('.').length} checkout_hash_length=#{signed.checkout_hash.length}"

# Test-only inline envelope, not a product Mandate issuance/authorization API.
# Real applications receive and independently verify their original Mandate.
closed = {"vct" => "mandate.checkout.1", "iat" => now, "exp" => now + 60,
  "checkout_jwt" => signed.jwt, "checkout_hash" => signed.checkout_hash}
terminal = JWT.encode({"aud" => "demo", "nonce" => "synthetic", "iat" => now,
  "sd_hash" => Base64.urlsafe_encode64(Digest::SHA256.digest("synthetic-root~"), padding: false),
  "delegate_payload" => [closed]}, agent, "ES256", {"typ" => "kb+sd-jwt"})
closed_sd_jwt = terminal + "~" # Explicit final SD-JWT serialization, not inferred by the Gem.
receipts = AP2MandateVerifier::CheckoutReceipt
%w[Success Error].each do |outcome|
  fields = outcome == "Success" ? {order_id: "order-1"} : {error: "declined", error_description: "Application declined"}
  receipt = receipts.sign(closed_sd_jwt: closed_sd_jwt, issuer: "shop", outcome: outcome,
    issued_at: now, signer: signer, public_key_pem: public_pem, **fields)
  checked = receipts.verify(jwt: receipt.jwt, closed_sd_jwt: closed_sd_jwt,
    trusted_public_key_pem: public_pem, expected_issuer: "shop",
    not_before: now - 60, not_after: now + 60, verified_at: now)
  raise "Unexpected synthetic result" unless checked.verified? && checked.purchase_succeeded? == (outcome == "Success") && checked.purchase_rejected? == (outcome == "Error")
  puts "#{outcome}: verified=#{checked.verified?} purchase_succeeded=#{checked.purchase_succeeded?} purchase_rejected=#{checked.purchase_rejected?}"
end
