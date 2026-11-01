# frozen_string_literal: true
require_relative "runtime_dependencies"
require_relative "../lib/ap2_mandate_verifier"
B = AP2MandateVerifier::Buyer
C = AP2MandateVerifier::CheckoutJWT
R = AP2MandateVerifier::CheckoutReceipt
provider = OpenSSL::PKey::EC.generate("prime256v1")
STDOUT.sync = true
STDIN.each_line do |line|
  begin
    request = JSON.parse(line)
    args = request.fetch("arguments").transform_keys(&:to_sym)
    result = case request.fetch("operation")
    when "issue"
      issued = B.issue_closed(**args, signer: C.es256_signer(private_key: provider), public_key_pem: provider.public_to_pem)
      {"wire" => issued.closed_sd_jwt, "public_key_pem" => provider.public_to_pem}
    when "verify"
      checked = B.verify(**args)
      {"verified" => checked.verified?, "reference" => checked.reference}
    when "receipt"
      signed = R.sign(**args, signer: C.es256_signer(private_key: provider), public_key_pem: provider.public_to_pem)
      {"jwt" => signed.jwt, "reference" => signed.reference, "public_key_pem" => provider.public_to_pem}
    when "verify_receipt"
      {"verified" => R.verify(**args).verified?}
    else raise "unsupported"
    end
    puts JSON.generate(result)
  rescue StandardError
    puts JSON.generate("rejected" => true)
  end
end
