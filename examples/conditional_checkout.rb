# frozen_string_literal: true
# Ordinary installed Gem only. No test fixtures, source-path loading or network.
require "ap2_mandate_verifier"
require "openssl"

module ConditionalCheckoutExample
  M = AP2MandateVerifier
  PROFILE = M::ConditionalCheckout::PROFILE_REF
  NOW = 1_800_000_000
  def self.totals(n) = %w[subtotal total].map { |type| {"type" => type, "amount" => n} }
  def self.run(currency: "USD")
    provider, agent, merchant = Array.new(3) { OpenSSL::PKey::EC.generate("prime256v1") }
    seller = {"id" => "shop", "name" => "Office supplies"}
    # This protected record is created AFTER application authentication, display
    # of these conditions and authority/consent checks. No approved flag is proof.
    requirements = [{"id" => "choice", "quantity" => 1,
      "acceptable_items" => %w[A B].map { |id| {"id" => id, "title" => "Product #{id}"} }},
      {"id" => "required", "quantity" => 2, "acceptable_items" => [{"id" => "C", "title" => "Product C"}]}]
    opening = M::ConditionalCheckout.issue_open(merchant: seller, requirements: requirements,
      agent_public_key_pem: agent.public_to_pem, issued_at: NOW, expires_at: NOW + 600,
      signer: M::CheckoutJWT.es256_signer(private_key: provider), public_key_pem: provider.public_to_pem)
    # Merchant Checkout has three rows, including C in two distinct rows.
    lines = %w[B C C].each_with_index.map do |id, i|
      {"id" => "row-#{i}", "item" => {"id" => id, "title" => "Product #{id}", "price" => 100},
        "quantity" => 1, "totals" => totals(100)}
    end
    order = {"id" => "office-1", "merchant" => seller, "status" => "ready_for_complete",
      "currency" => currency, "line_items" => lines, "totals" => totals(300), "links" => []}
    checkout = M::CheckoutJWT.sign(checkout: order, profile_ref: PROFILE,
      signer: M::CheckoutJWT.es256_signer(private_key: merchant), public_key_pem: merchant.public_to_pem)

    # Host enrollment and challenge are synthetic authenticated application data.
    roles = %w[Issuer Agent Merchant]
    records = roles.zip([provider, agent, merchant]).map do |role, key|
      {"role" => role, "identity" => role == "Merchant" ? "shop" : role.downcase,
        "tenant_id" => "tenant", "purpose" => "checkout", "key_ref" => role.downcase,
        "public_key_pem" => key.public_to_pem, "active" => true, "not_before" => NOW - 1, "not_after" => NOW + 1000}
    end
    selectors = records.to_h { |record| [record["role"].downcase.to_sym, record.slice("identity", "purpose", "key_ref")] }
    trust = M::InputBuilder.trust(snapshot: {"id" => "registry", "policy_version" => "1", "active" => true,
      "not_before" => NOW - 1, "not_after" => NOW + 1000, "records" => records},
      tenant_id: "tenant", verified_at: NOW, profile_ref: PROFILE, **selectors)
    host_order = {"tenant_id" => "tenant", "buyer_account_id" => "buyer", "order_id" => "office-1",
      "merchant_id" => "shop", "audience" => "merchant-host", "order_version" => "1", "currency" => currency, "expected_total" => 300}
    host_inputs = {trust: trust, order: host_order, root_presentation: opening.root_presentation, host_checkout_jws: checkout.jwt}
    saved = M::InputBuilder.prepare(**host_inputs, challenge_id: "challenge-1", nonce: "synthetic-one-use-nonce",
      issuer_id: "host", not_before: NOW, not_after: NOW + 60)
    # Agent receives public trust, Open, Checkout, challenge and its own signer.
    # Provider signer/private key is not an input to this operation.
    closed = M::ConditionalCheckout.issue_closed(root_presentation: opening.root_presentation, checkout_jwt: checkout.jwt,
      trusted_issuer_public_key_pem: provider.public_to_pem, agent_public_key_pem: agent.public_to_pem,
      trusted_merchant_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop",
      audience: "merchant-host", nonce: "synthetic-one-use-nonce", verified_at: NOW,
      signer: M::CheckoutJWT.es256_signer(private_key: agent))
    wire = M::ConditionalCheckout.present(root_presentation: closed.root_presentation,
      terminal_jws: closed.terminal_jws, checkout_jwt: closed.checkout_jwt)
    checked = M::InputBuilder.verify(**host_inputs, terminal_jws: wire.terminal_jws,
      saved_challenge: M::InputBuilder.restore(saved_challenge: saved), expected_challenge_issuer_id: "host",
      clock_source_id: "synthetic-clock", verified_at: NOW)
    raise "verification failed" unless checked.success?
    puts "Open -> Agent Closed -> merchant evidence: verified=true; rows=3; requirements=2"
    # These are ALTERNATIVE synthetic application outcomes, never two executions.
    %w[Success Error].each do |outcome|
      fields = outcome == "Success" ? {order_id: "office-1"} : {error: "policy_rejected", error_description: "Application declined"}
      receipt = M::CheckoutReceipt.sign(closed_sd_jwt: wire.closed_sd_jwt, profile_ref: PROFILE,
        issuer: "shop", outcome: outcome, issued_at: NOW, **fields,
        signer: M::CheckoutJWT.es256_signer(private_key: merchant), public_key_pem: merchant.public_to_pem)
      result = M::CheckoutReceipt.verify(jwt: receipt.jwt, closed_sd_jwt: wire.closed_sd_jwt,
        profile_ref: PROFILE, trusted_public_key_pem: merchant.public_to_pem, expected_issuer: "shop",
        not_before: NOW, not_after: NOW + 60, verified_at: NOW)
      raise "receipt failed" unless result.verified? && result.outcome == outcome
      puts "Receipt #{outcome}: authentic=true; purchase_succeeded=#{result.purchase_succeeded?}"
    end
    # Application state, not an SDK purchase permit: durable transaction/CAS in
    # real code must consume approval/challenge/order once and save its receipt.
    states = {"success" => :consumed, "error" => :requires_new_policy_decision, "missing_receipt" => :pending}
    raise "unknown replay" unless states["missing_receipt"] == :pending
    puts "Success=consumed; Error=policy decision; missing Receipt/uncertain commit=pending"
    puts "Synthetic only; evidence and Receipt authenticity are not payment completion."
    {opening: opening, closed: closed, result: checked, host_inputs: host_inputs, saved: saved,
      keys: [provider, agent, merchant], requirements: requirements, checkout: order}
  end
end
ConditionalCheckoutExample.run if $PROGRAM_NAME == __FILE__
