# frozen_string_literal: true
# Run with the candidate Gem installed. The source checkout supplies synthetic
# buyer/Issuer fixture data only; no production Mandate-issuance API is added.
require "ap2_mandate_verifier"
require_relative "../test/support/multi_item_fixture"

model = MultiItemFixture.build
inputs = model.fetch(:args)
saved = AP2MandateVerifier::InputBuilder.restore(saved_challenge: inputs.fetch(:saved_challenge))
result = AP2MandateVerifier::InputBuilder.verify(**inputs.merge(saved_challenge: saved))
puts "checkout verified=#{result.success?} profile=#{result.evidence&.[]("profile_ref")}"
abort "synthetic Checkout failed" unless result.success?

%w[Success Error].each do |outcome|
  fields = outcome == "Success" ? {order_id: "order"} : {error: "host_rejected", error_description: "Host policy rejected order"}
  signed = AP2MandateVerifier::CheckoutReceipt.sign(
    closed_sd_jwt: inputs.fetch(:terminal_jws) + "~", profile_ref: MultiItemFixture::PROFILE,
    issuer: "shop", outcome: outcome, issued_at: MultiItemFixture::NOW,
    signer: AP2MandateVerifier::CheckoutJWT.es256_signer(private_key: model.fetch(:keys)[2]),
    public_key_pem: model.fetch(:keys)[2].public_to_pem, **fields)
  receipt = AP2MandateVerifier::CheckoutReceipt.verify(jwt: signed.jwt,
    closed_sd_jwt: inputs.fetch(:terminal_jws) + "~", profile_ref: MultiItemFixture::PROFILE,
    trusted_public_key_pem: model.fetch(:keys)[2].public_to_pem, expected_issuer: "shop",
    not_before: MultiItemFixture::NOW - 1, not_after: MultiItemFixture::NOW + 1, verified_at: MultiItemFixture::NOW)
  puts "receipt #{outcome}: verified=#{receipt.verified?} purchase_succeeded=#{receipt.purchase_succeeded?}"
end
puts "Synthetic demonstration only. Host authorization, atomic nonce consumption and payment remain application responsibilities."
