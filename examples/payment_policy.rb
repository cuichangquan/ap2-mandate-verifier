# frozen_string_literal: true
# Installed SDK only. Synthetic registry, approval and keys; no actual payment.
require "ap2_mandate_verifier"
require "time"
require_relative "selective_checkout"
module PaymentPolicyExample
  M = AP2MandateVerifier
  NOW = SelectiveCheckoutExample::NOW
  def self.run
    state = SelectiveCheckoutExample.run
    provider, agent, merchant = state.fetch(:keys)
    signer = ->(key) { M::CheckoutJWT.es256_signer(private_key: key) }
    # These synthetic registry entries represent independently authenticated app
    # state. Production code validates enrollment/channel/QWAC/revocation itself.
    registry = {"processor-A" => {"legal_name" => "Example Payment Services Ltd.",
      "brand_name" => "ExamplePay", "domain_name" => "pay.example"}}
    trusted_pisp = registry.fetch("processor-A")
    planned = Time.at(NOW + 3600).utc
    date = planned.iso8601(3)
    execution_at = planned.getlocal("+09:00").iso8601(3) # Same instant, different representation.
    profile = M::PaymentPolicy::PROFILE_REF
    selective_profile = M::PaymentPolicy::SELECTIVE_PROFILE_REF
    checkout = state.fetch(:closed).checkout_jwt
    details = M::Payment.details(checkout_jwt: checkout, trusted_merchant_public_key_pem: merchant.public_to_pem,
      expected_merchant_id: "shop", payment_instrument: {"id" => "synthetic-card-A", "type" => "card"},
      pisp: trusted_pisp, execution_date: date, profile_ref: profile)
    direct_checkout = M::Buyer.issue_closed(checkout_jwt: checkout, approved_checkout_jwt: checkout,
      trusted_merchant_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop", issued_at: NOW,
      expires_at: NOW + 60, signer: signer.call(provider), public_key_pem: provider.public_to_pem)
    direct_inputs = {closed_sd_jwt: direct_checkout.closed_sd_jwt, expected_checkout_jwt: checkout,
      trusted_provider_public_key_pem: provider.public_to_pem, trusted_merchant_public_key_pem: merchant.public_to_pem,
      expected_merchant_id: "shop", verified_at: NOW}
    direct = M::Payment.issue_direct(payment: details, approved_payment: details, issued_at: NOW,
      expires_at: NOW + 60, signer: signer.call(provider), public_key_pem: provider.public_to_pem, profile_ref: profile)
    base = {expected_payment: details, trusted_provider_public_key_pem: provider.public_to_pem,
      trusted_pisp: trusted_pisp, execution_at: execution_at, verified_at: NOW, profile_ref: profile}
    direct_args = base.merge(closed_sd_jwt: direct.closed_sd_jwt, checkout_mode: :direct, checkout_inputs: direct_inputs)
    raise "Direct policy verification failed" unless M::Payment.verify(**direct_args).verified?
    wrong_pisp = trusted_pisp.merge("brand_name" => "Unapproved brand")
    raise "PISP context mismatch accepted" if M::Payment.verify(**direct_args.merge(trusted_pisp: wrong_pisp)).verified?
    raise "execution context mismatch accepted" if M::Payment.verify(**direct_args.merge(execution_at: (planned + 1).iso8601(3))).verified?
    puts "Direct: approved PISP/date verified; wrong independent PISP/time rejected"

    payees = [details.fetch("payee"), {"id" => "private-alternative", "name" => "Private alternative payee"}]
    instruments = [details.fetch("payment_instrument"), {"id" => "private-card", "type" => "card"}]
    conditions = [{"type" => "payment.amount_range", "currency" => "USD", "max" => 300},
      {"type" => "payment.allowed_payees", "allowed" => payees},
      {"type" => "payment.allowed_payment_instruments", "allowed" => instruments},
      {"type" => "payment.allowed_pisps", "allowed" => [trusted_pisp]},
      {"type" => "payment.execution_date", "not_before" => (planned - 1).iso8601(3), "not_after" => (planned + 1).iso8601(3)}]
    open_args = {open_checkout_sd_jwt: state.fetch(:opening).root_presentation, constraints: conditions, fixed: {},
      agent_public_key_pem: agent.public_to_pem, issued_at: NOW, expires_at: NOW + 60,
      signer: signer.call(provider), public_key_pem: provider.public_to_pem,
      checkout_profile_ref: M::SelectiveCheckout::PROFILE_REF, candidate_policy: :independent}
    open = M::Payment.issue_open(**open_args, profile_ref: profile)
    close_args = {payment: details, trusted_provider_public_key_pem: provider.public_to_pem,
      agent_public_key_pem: agent.public_to_pem, audience: "credential-provider", nonce: "synthetic-policy-nonce",
      verified_at: NOW, signer: signer.call(agent)}
    closed = M::Payment.issue_closed(**close_args, open_sd_jwt: open, profile_ref: profile)
    restored = M::Payment.present(open_sd_jwt: open, closed_sd_jwt: closed.closed_sd_jwt, profile_ref: profile)
    raw = M::InputBuilder.inputs(**state.fetch(:host_inputs), saved_challenge: state.fetch(:saved),
      terminal_jws: state.fetch(:closed).terminal_jws, expected_challenge_issuer_id: "host", clock_source_id: "synthetic-clock", verified_at: NOW)
    expected_agent = {expected_agent_public_key_pem: agent.public_to_pem, expected_audience: "credential-provider", expected_nonce: "synthetic-policy-nonce"}
    checked = M::Payment.verify(**base, **expected_agent, closed_sd_jwt: restored.closed_sd_jwt,
      open_sd_jwt: restored.open_sd_jwt, checkout_mode: :conditional, checkout_inputs: raw)
    raise "conditional policy verification failed" unless checked.verified?
    begin
      M::Payment.issue_closed(**close_args.merge(payment: details.merge("execution_date" => (planned + 2).iso8601(3))), open_sd_jwt: open, profile_ref: profile)
      raise "outside execution window accepted"
    rescue M::Payment::Invalid
      puts "Conditional: allowed PISP/inclusive window verified; outside window rejected"
    end
    full = M::SelectivePayment.issue_open(**open_args, profile_ref: selective_profile,
      approved_combinations: [[0,0],[0,1],[1,0],[1,1]], selective: :both)
    reduced = M::SelectivePayment.select(open_sd_jwt: full, payee_index: 0, instrument_index: 0, profile_ref: selective_profile)
    selective_closed = M::SelectivePayment.issue_closed(**close_args, open_presentation: reduced, profile_ref: selective_profile)
    selective = M::SelectivePayment.present(open_presentation: reduced, closed_sd_jwt: selective_closed.closed_sd_jwt, profile_ref: selective_profile)
    result = M::SelectivePayment.verify(**base.merge(profile_ref: selective_profile), **expected_agent,
      open_presentation: reduced, closed_sd_jwt: selective.closed_sd_jwt, checkout_inputs: raw)
    raise "selective policy verification failed" unless result.verified?
    visible = reduced.split("~", -1)[1...-1].map { |s| JSON.parse(Base64.urlsafe_decode64(s)) }
    raise "hidden candidate leaked" if JSON.generate(visible).include?("private-alternative") || JSON.generate(visible).include?("private-card")
    puts "Selective: Checkout and Payment verified; unselected payee/instrument hidden; PISP/date conditions fully visible"
    [[direct, profile], [restored, profile], [selective, selective_profile]].each do |payment, ref|
      %w[Success Error].each do |outcome|
        fields = outcome == "Success" ? {psp_confirmation_id: "synthetic-psp", network_confirmation_id: "synthetic-network"} :
          {error: "declined", error_description: "Simulated refusal"}
        receipt = M::PaymentReceipt.sign(closed_sd_jwt: payment.closed_sd_jwt, profile_ref: ref, issuer: "processor-A",
          payment_id: "synthetic-policy-payment", outcome: outcome, issued_at: NOW, **fields,
          signer: signer.call(merchant), public_key_pem: merchant.public_to_pem)
        verified = M::PaymentReceipt.verify(jwt: receipt.jwt, closed_sd_jwt: payment.closed_sd_jwt, profile_ref: ref,
          trusted_public_key_pem: merchant.public_to_pem, expected_issuer: "processor-A", expected_payment_id: "synthetic-policy-payment",
          not_before: NOW, not_after: NOW + 60, verified_at: NOW)
        raise "policy Receipt failed" unless verified.verified? && verified.outcome == outcome
      end
    end
    puts "Success/Error Payment Receipts authenticated for all three modes"
    puts "Synthetic plan only: no QWAC provenance, scheduling, execution permission or settlement is established."
  end
end
PaymentPolicyExample.run if $PROGRAM_NAME == __FILE__
