# frozen_string_literal: true
require "json"
require "ap2_mandate_verifier"
AP2MandateVerifier::RootSignature.send(:dependencies!)
key = OpenSSL::PKey::EC.generate("prime256v1")
STDOUT.sync = true
STDIN.each_line do |line|
  request = JSON.parse(line)
  begin
    response = case request.fetch("operation")
    when "sign_checkout"
      signed = AP2MandateVerifier::CheckoutJWT.sign(checkout: request.fetch("checkout"),
        signer: AP2MandateVerifier::CheckoutJWT.es256_signer(private_key: key), public_key_pem: key.public_to_pem)
      {"jwt" => signed.jwt, "checkout_hash" => signed.checkout_hash, "public_key_pem" => key.public_to_pem}
    when "verify_checkout_signature"
      {"claims" => AP2MandateVerifier::RootSignature.verified_payload!(request.fetch("jwt"),
        request.fetch("public_key_pem"), expected_typ: "JWT")}
    when "sign_receipt"
      signed = AP2MandateVerifier::CheckoutReceipt.sign(**request.fetch("arguments").transform_keys(&:to_sym),
        signer: AP2MandateVerifier::CheckoutJWT.es256_signer(private_key: key), public_key_pem: key.public_to_pem)
      {"jwt" => signed.jwt, "reference" => signed.reference, "public_key_pem" => key.public_to_pem}
    when "verify_receipt"
      result = AP2MandateVerifier::CheckoutReceipt.verify(**request.fetch("arguments").transform_keys(&:to_sym))
      {"verified" => result.verified?, "outcome" => result.outcome,
        "purchase_succeeded" => result.purchase_succeeded?, "purchase_rejected" => result.purchase_rejected?}
    when "receipt_reference"
      {"reference" => AP2MandateVerifier::CheckoutReceipt.reference(closed_sd_jwt: request.fetch("wire"))}
    else
      raise "unsupported operation"
    end
    puts JSON.generate(response)
  rescue StandardError
    puts JSON.generate("rejected" => true)
  end
end
