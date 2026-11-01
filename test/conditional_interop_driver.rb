# frozen_string_literal: true
# Test-only JSON lines transport; keys never leave process memory.
require_relative "runtime_dependencies"
require_relative "../lib/ap2_mandate_verifier"
M = AP2MandateVerifier
provider, agent, merchant = Array.new(3) { OpenSSL::PKey::EC.generate("prime256v1") }
STDOUT.sync = true
STDIN.each_line do |line|
  begin
    request = JSON.parse(line)
    args = request.fetch("arguments").transform_keys(&:to_sym)
    result = case request.fetch("operation")
    when "issue_open"
      issued = M::ConditionalCheckout.issue_open(**args, agent_public_key_pem: agent.public_to_pem,
        signer: M::CheckoutJWT.es256_signer(private_key: provider), public_key_pem: provider.public_to_pem)
      {root: issued.root_presentation, provider: provider.public_to_pem, agent: agent.public_to_pem}
    when "issue_closed"
      issued = M::ConditionalCheckout.issue_closed(**args, agent_public_key_pem: agent.public_to_pem,
        signer: M::CheckoutJWT.es256_signer(private_key: agent))
      {root: issued.root_presentation, terminal: issued.terminal_jws, closed: issued.closed_sd_jwt}
    when "verify"
      inputs = args.merge(profile_ref: M::ConditionalCheckout::PROFILE_REF)
      M::ScopedConstraints.check!(**inputs)
      {accepted: true}
    when "receipt"
      signed = M::CheckoutReceipt.sign(**args, profile_ref: M::ConditionalCheckout::PROFILE_REF,
        signer: M::CheckoutJWT.es256_signer(private_key: merchant), public_key_pem: merchant.public_to_pem)
      {jwt: signed.jwt, reference: signed.reference, key: merchant.public_to_pem}
    when "verify_receipt"
      {verified: M::CheckoutReceipt.verify(**args, profile_ref: M::ConditionalCheckout::PROFILE_REF).verified?}
    else raise "unsupported"
    end
    puts JSON.generate(result)
  rescue M::RootSignature::Rejected => error
    puts JSON.generate(rejected: true, code: error.code)
  rescue StandardError
    puts JSON.generate(rejected: true)
  end
end
