# frozen_string_literal: true
# Installed SDK only. Confidential issuance stays local; simulated payments only.
require "ap2_mandate_verifier"
require_relative "selective_checkout"
module SelectiveCheckoutPaymentExample
  M = AP2MandateVerifier
  NOW = SelectiveCheckoutExample::NOW
  def self.run
    state = SelectiveCheckoutExample.run
    provider, agent, merchant = state.fetch(:keys)
    signer = ->(key) { M::CheckoutJWT.es256_signer(private_key: key) }
    checkout = state.fetch(:closed).checkout_jwt
    chosen_instrument = {"id" => "synthetic-card-A", "type" => "card"}
    details = M::Payment.details(checkout_jwt: checkout, trusted_merchant_public_key_pem: merchant.public_to_pem,
      expected_merchant_id: "shop", payment_instrument: chosen_instrument)
    payees = [details.fetch("payee"), {"id" => "another-shop", "name" => "Private alternative payee"}]
    instruments = [chosen_instrument, {"id" => "private-alternative-B", "type" => "card"}]
    conditions = [{"type" => "payment.amount_range", "currency" => "USD", "min" => 100, "max" => 300},
      {"type" => "payment.allowed_payees", "allowed" => payees},
      {"type" => "payment.allowed_payment_instruments", "allowed" => instruments}]
    # This list comes from the app's PROTECTED approval record: every crossproduct
    # combination is expressly approved. Do not expand a correlated subset here.
    approved_combinations = [[0, 0], [0, 1], [1, 0], [1, 1]]
    full = M::SelectivePayment.issue_open(open_checkout_sd_jwt: state.fetch(:opening).root_presentation,
      checkout_profile_ref: M::SelectiveCheckout::PROFILE_REF,
      constraints: conditions, fixed: {}, approved_combinations: approved_combinations, selective: :both,
      agent_public_key_pem: agent.public_to_pem, issued_at: NOW, expires_at: NOW+60,
      signer: signer.call(provider), public_key_pem: provider.public_to_pem)
    reduced = M::SelectivePayment.select(open_sd_jwt: full, payee_index: 0, instrument_index: 0)
    transmitted_disclosures = reduced.split("~", -1)[1...-1]
    visible = transmitted_disclosures.map { |wire| JSON.parse(Base64.urlsafe_decode64(wire)) }
    hidden_leaves = full.split("~", -1)[1...-1].select do |wire|
      value = JSON.parse(Base64.urlsafe_decode64(wire))[1]
      value == payees[1] || value == instruments[1]
    end
    raise "privacy boundary failed" unless (hidden_leaves & transmitted_disclosures).empty? &&
      !JSON.generate(visible).include?("Private alternative") && !JSON.generate(visible).include?("private-alternative-B")
    # Keep full confidential issuance in protected storage; send only reduced.
    # No original unselected disclosure or confidential full wire is printed.
    puts "Retained locally: payees=2; instruments=2; disclosures=#{full.count('~')-1}; bytes=#{full.bytesize}"
    puts "Sent: chosen payee=shop; chosen instrument=synthetic-card-A; disclosures=#{reduced.count('~')-1}; bytes=#{reduced.bytesize}"
    puts "Issuer JWT unchanged=#{full.split('~').first == reduced.split('~').first}; presentation bytes changed=#{full != reduced}"
    closed = M::SelectivePayment.issue_closed(open_presentation: reduced, payment: details,
      trusted_provider_public_key_pem: provider.public_to_pem, agent_public_key_pem: agent.public_to_pem,
      audience: "credential-provider", nonce: "synthetic-selective-payment-nonce", verified_at: NOW,
      signer: signer.call(agent))
    restored = M::SelectivePayment.present(open_presentation: reduced, closed_sd_jwt: closed.closed_sd_jwt)
    checkout_inputs = M::InputBuilder.inputs(**state.fetch(:host_inputs), saved_challenge: state.fetch(:saved),
      terminal_jws: state.fetch(:closed).terminal_jws, expected_challenge_issuer_id: "host",
      clock_source_id: "synthetic-clock", verified_at: NOW)
    verified = M::SelectivePayment.verify(open_presentation: restored.open_sd_jwt, closed_sd_jwt: restored.closed_sd_jwt,
      checkout_inputs: checkout_inputs, expected_payment: details, trusted_provider_public_key_pem: provider.public_to_pem,
      expected_agent_public_key_pem: agent.public_to_pem, expected_audience: "credential-provider",
      expected_nonce: "synthetic-selective-payment-nonce", verified_at: NOW)
    raise "selective verification failed" unless verified.verified?
    puts "Selected Payment verified=true; unselected candidate values/disclosures were not sent"
    %w[Success Error].each do |outcome|
      fields = outcome == "Success" ? {psp_confirmation_id: "synthetic-psp", network_confirmation_id: "synthetic-network"} :
        {error: "declined", error_description: "Simulated rejection"}
      receipt = M::PaymentReceipt.sign(closed_sd_jwt: restored.closed_sd_jwt, issuer: "processor",
        payment_id: "synthetic-selective-payment", outcome: outcome, issued_at: NOW, **fields,
        signer: signer.call(merchant), public_key_pem: merchant.public_to_pem)
      checked = M::PaymentReceipt.verify(jwt: receipt.jwt, closed_sd_jwt: restored.closed_sd_jwt,
        trusted_public_key_pem: merchant.public_to_pem, expected_issuer: "processor", expected_payment_id: "synthetic-selective-payment",
        not_before: NOW, not_after: NOW+60, verified_at: NOW)
      raise "receipt failed" unless checked.verified? && checked.outcome == outcome
      puts "Payment Receipt #{outcome}: authentic=#{checked.verified?}; reported_success=#{checked.payment_succeeded?}"
    end
    puts "Synthetic only. Verification is not execution permission; one-use atomic state belongs to the app; unknown outcome remains pending."
  end
end
SelectiveCheckoutPaymentExample.run if $PROGRAM_NAME == __FILE__
