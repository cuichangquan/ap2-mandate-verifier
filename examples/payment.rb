# frozen_string_literal: true
# Installed Gem only; every payment/processor result is synthetic.
require "ap2_mandate_verifier"
require_relative "conditional_checkout"
module PaymentExample
  M = AP2MandateVerifier
  NOW = ConditionalCheckoutExample::NOW
  def self.run
    state = ConditionalCheckoutExample.run
    provider, agent, merchant = state.fetch(:keys)
    sign = ->(key) { M::CheckoutJWT.es256_signer(private_key: key) }
    checkout = state.fetch(:closed).checkout_jwt
    # External application selects the instrument and independently trusts order/key.
    details = M::Payment.details(checkout_jwt: checkout, trusted_merchant_public_key_pem: merchant.public_to_pem,
      expected_merchant_id: "shop", payment_instrument: {"id" => "synthetic-card", "type" => "card"})
    direct_checkout = M::Buyer.issue_closed(checkout_jwt: checkout, approved_checkout_jwt: checkout,
      trusted_merchant_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop",
      issued_at: NOW, expires_at: NOW+60, signer: sign.call(provider), public_key_pem: provider.public_to_pem)
    direct_inputs = {closed_sd_jwt: direct_checkout.closed_sd_jwt, expected_checkout_jwt: checkout,
      trusted_provider_public_key_pem: provider.public_to_pem, trusted_merchant_public_key_pem: merchant.public_to_pem,
      expected_merchant_id: "shop", verified_at: NOW}
    # In a real application approved_payment is read from its protected consent record.
    direct = M::Payment.issue_direct(payment: details, approved_payment: details, issued_at: NOW,
      expires_at: NOW+60, signer: sign.call(provider), public_key_pem: provider.public_to_pem)
    base = {expected_payment: details, trusted_provider_public_key_pem: provider.public_to_pem, verified_at: NOW}
    direct_check = M::Payment.verify(**base, closed_sd_jwt: direct.closed_sd_jwt, checkout_mode: :direct, checkout_inputs: direct_inputs)
    raise "Direct failed" unless direct_check.verified?

    conditions = [{"type" => "payment.amount_range", "currency" => "USD", "max" => 300},
      {"type" => "payment.allowed_payees", "allowed" => [details.fetch("payee")]},
      {"type" => "payment.allowed_payment_instruments", "allowed" => [details.fetch("payment_instrument")]}]
    opening = M::Payment.issue_open(open_checkout_sd_jwt: state.fetch(:opening).root_presentation,
      constraints: conditions, fixed: {"payment_instrument" => details.fetch("payment_instrument")},
      agent_public_key_pem: agent.public_to_pem, issued_at: NOW, expires_at: NOW+60,
      signer: sign.call(provider), public_key_pem: provider.public_to_pem)
    closed = M::Payment.issue_closed(open_sd_jwt: opening, payment: details,
      trusted_provider_public_key_pem: provider.public_to_pem, agent_public_key_pem: agent.public_to_pem,
      audience: "credential-provider", nonce: "synthetic-payment-nonce", verified_at: NOW, signer: sign.call(agent))
    restored = M::Payment.present(open_sd_jwt: opening, closed_sd_jwt: closed.closed_sd_jwt)
    # Reuse existing complete Checkout input preparation; no facts from Payment claims.
    raw = M::InputBuilder.inputs(**state.fetch(:host_inputs), saved_challenge: state.fetch(:saved),
      terminal_jws: state.fetch(:closed).terminal_jws, expected_challenge_issuer_id: "host",
      clock_source_id: "synthetic-clock", verified_at: NOW)
    checked = M::Payment.verify(**base, closed_sd_jwt: restored.closed_sd_jwt, open_sd_jwt: restored.open_sd_jwt,
      checkout_mode: :conditional, checkout_inputs: raw, expected_agent_public_key_pem: agent.public_to_pem,
      expected_audience: "credential-provider", expected_nonce: "synthetic-payment-nonce")
    raise "Conditional failed" unless checked.verified?
    puts "Direct and conditional Payment: verified; no execution permission granted"
    [direct, restored].each do |payment|
      # Alternative simulated outcomes, never two actual executions.
      %w[Success Error].each do |outcome|
        fields = outcome == "Success" ? {psp_confirmation_id: "synthetic-psp", network_confirmation_id: "synthetic-network"} :
          {error: "declined", error_description: "Simulated rejection"}
        receipt = M::PaymentReceipt.sign(closed_sd_jwt: payment.closed_sd_jwt, issuer: "processor",
          payment_id: "synthetic-payment", outcome: outcome, issued_at: NOW, **fields,
          signer: sign.call(merchant), public_key_pem: merchant.public_to_pem)
        result = M::PaymentReceipt.verify(jwt: receipt.jwt, closed_sd_jwt: payment.closed_sd_jwt,
          trusted_public_key_pem: merchant.public_to_pem, expected_issuer: "processor", expected_payment_id: "synthetic-payment",
          not_before: NOW, not_after: NOW+60, verified_at: NOW)
        raise "Receipt failed" unless result.verified? && result.outcome == outcome
        puts "Payment Receipt #{outcome}: authentic=#{result.verified?}; reported_success=#{result.payment_succeeded?}"
      end
    end
    puts "Synthetic only. Persist one-use state atomically. Missing/invalid Receipt = pending; no automatic retry."
  end
end
PaymentExample.run if $PROGRAM_NAME == __FILE__
