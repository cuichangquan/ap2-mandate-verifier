# frozen_string_literal: true
# Ordinary installed require only; synthetic signed fixture Strings are data.
require "ap2_mandate_verifier"
require "json"
AP2MandateVerifier::RootSignature.send(:dependencies!)
raise "source accidentally loaded" unless Gem.loaded_specs.fetch("ap2_mandate_verifier").version.to_s == "0.5.0"
wires = JSON.parse(File.binread(ARGV.fetch(0)))
key = OpenSSL::PKey::EC.generate("prime256v1")
c = AP2MandateVerifier::CheckoutJWT
r = AP2MandateVerifier::CheckoutReceipt
signer = c.es256_signer(private_key: key)
checkout = JWT.decode(wires.fetch("host_checkout_jws"), nil, false).first
signed = c.sign(checkout: checkout, signer: signer, public_key_pem: key.public_to_pem)
raise "checkout claims" unless JWT.decode(signed.jwt, key, true, algorithms: ["ES256"]).first == checkout
raise "checkout original" unless signed.checkout_hash == Base64.urlsafe_encode64(Digest::SHA256.digest(signed.jwt), padding: false)
wire = wires.fetch("terminal_jws") + "~"
now = 1_800_000_000
%w[Success Error].each do |outcome|
  fields = outcome == "Success" ? {order_id: "order"} : {error: "declined", error_description: "Application declined"}
  receipt = r.sign(closed_sd_jwt: wire, issuer: "shop", outcome: outcome, issued_at: now,
    signer: signer, public_key_pem: key.public_to_pem, **fields)
  inputs = {jwt: receipt.jwt, closed_sd_jwt: wire, trusted_public_key_pem: key.public_to_pem,
    expected_issuer: "shop", not_before: now - 60, not_after: now + 60, verified_at: now}
  checked = r.verify(**inputs)
  raise "receipt business separation" unless checked.verified? && checked.purchase_succeeded? == (outcome == "Success") &&
    checked.purchase_rejected? == (outcome == "Error")
  raise "issuer fail closed" if r.verify(**inputs.merge(expected_issuer: "other")).verified?
  raise "wire fail closed" if r.verify(**inputs.merge(closed_sd_jwt: wires.fetch("terminal_jws"))).verified?
end
puts JSON.generate(installed_merchant_signing_and_both_receipt_outcomes: true, ordinary_require: true,
  ruby: RUBY_VERSION, gem_version: Gem.loaded_specs.fetch("ap2_mandate_verifier").version.to_s)
