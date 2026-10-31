# frozen_string_literal: true
# Test-only RPC: synthetic public inputs; no product Mandate issuance API.
require "json"
require "ap2_mandate_verifier"
AP2MandateVerifier::RootSignature.send(:dependencies!)
M = AP2MandateVerifier
PROFILE = "ap2.checkout.single_merchant_multi_item"
key = OpenSSL::PKey::EC.generate("prime256v1")
STDOUT.sync = true
STDIN.each_line do |line|
  request = JSON.parse(line)
  begin
    response = case request.fetch("operation")
    when "sign_checkout"
      signed = M::CheckoutJWT.sign(checkout: request.fetch("checkout"), profile_ref: PROFILE,
        signer: M::CheckoutJWT.es256_signer(private_key: key), public_key_pem: key.public_to_pem)
      {jwt: signed.jwt, checkout_hash: signed.checkout_hash, public_key_pem: key.public_to_pem}
    when "constraints"
      checkout = request.fetch("checkout")
      M::ScopedConstraints.send(:multi_constraints!, {open: {"constraints" => request.fetch("constraints")}, checkout: checkout},
        checkout.fetch("currency"), checkout.fetch("totals").first.fetch("amount"))
      {accepted: true}
    when "verify_mandate"
      now = request.fetch("now")
      records = %w[Issuer Agent Merchant].map do |role|
        {"role" => role, "identity" => role == "Merchant" ? "shop" : role.downcase,
         "tenant_id" => "tenant", "purpose" => "checkout", "key_ref" => role.downcase,
         "public_key_pem" => request.fetch("public_keys").fetch(role), "active" => true,
         "not_before" => now - 1000, "not_after" => now + 1000}
      end
      snapshot = {"id" => "interop", "policy_version" => "1", "active" => true,
        "not_before" => now - 1000, "not_after" => now + 1000, "records" => records}
      selections = records.to_h { |record| [record["role"].downcase.to_sym, record.slice("identity", "purpose", "key_ref")] }
      trust = M::InputBuilder.trust(snapshot: snapshot, tenant_id: "tenant", verified_at: now,
        profile_ref: PROFILE, **selections)
      order = {"tenant_id" => "tenant", "buyer_account_id" => "buyer", "order_id" => "order",
        "merchant_id" => "shop", "audience" => "host", "order_version" => "1", "currency" => "USD",
        "expected_total" => request.fetch("expected_total")}
      inputs = {trust: trust, order: order, root_presentation: request.fetch("root"),
        host_checkout_jws: request.fetch("checkout_jwt")}
      saved = M::InputBuilder.prepare(**inputs, challenge_id: "interop", nonce: "synthetic-nonce",
        issuer_id: "host-issuer", not_before: now - 100, not_after: now + 100)
      result = M::InputBuilder.verify(**inputs, saved_challenge: M::InputBuilder.restore(saved_challenge: saved),
        terminal_jws: request.fetch("terminal"), expected_challenge_issuer_id: "host-issuer",
        clock_source_id: "independent-test-clock", verified_at: now)
      {status: result.status, code: result.code, success: result.success?, evidence: !result.evidence.nil?}
    when "sign_receipt"
      signed = M::CheckoutReceipt.sign(**request.fetch("arguments").transform_keys(&:to_sym), profile_ref: PROFILE,
        signer: M::CheckoutJWT.es256_signer(private_key: key), public_key_pem: key.public_to_pem)
      {jwt: signed.jwt, reference: signed.reference, public_key_pem: key.public_to_pem}
    when "verify_receipt"
      checked = M::CheckoutReceipt.verify(**request.fetch("arguments").transform_keys(&:to_sym), profile_ref: PROFILE)
      {verified: checked.verified?, outcome: checked.outcome,
       purchase_succeeded: checked.purchase_succeeded?, purchase_rejected: checked.purchase_rejected?}
    when "receipt_reference"
      {reference: M::CheckoutReceipt.reference(closed_sd_jwt: request.fetch("wire"), profile_ref: PROFILE)}
    else
      raise "unsupported test operation"
    end
    puts JSON.generate(response)
  rescue M::RootSignature::Rejected => error
    puts JSON.generate(accepted: false, code: error.code)
  rescue StandardError
    puts JSON.generate(rejected: true)
  end
end
