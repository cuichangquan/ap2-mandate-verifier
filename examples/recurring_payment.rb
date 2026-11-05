# frozen_string_literal: true
# Installed SDK, optional sqlite3=2.10.2; synthetic keys and temporary ledger only.
require "ap2_mandate_verifier"
require "tmpdir"
require_relative "conditional_checkout"

module RecurringPaymentExample
  M = AP2MandateVerifier
  A = M::PaymentAcceptance
  R = M::RecurringPayment
  NOW = ConditionalCheckoutExample::NOW
  def self.sign(key) = M::CheckoutJWT.es256_signer(private_key: key)
  def self.build(max_occurrences: 2, budget_max: 600)
    state = ConditionalCheckoutExample.run(currency: "JPY")
    provider, agent, merchant = state.fetch(:keys)
    details = M::Payment.details(checkout_jwt: state.fetch(:closed).checkout_jwt,
      trusted_merchant_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop",
      payment_instrument: {"id" => "synthetic-card", "type" => "card"})
    conditions = [
      {"type" => "payment.amount_range", "currency" => "JPY", "min" => 1, "max" => 300},
      {"type" => "payment.allowed_payees", "allowed" => [details.fetch("payee")]},
      {"type" => "payment.allowed_payment_instruments", "allowed" => [details.fetch("payment_instrument")]},
      {"type" => "payment.agent_recurrence", "frequency" => "ON_DEMAND", "max_occurrences" => max_occurrences},
      {"type" => "payment.budget", "currency" => "JPY", "max" => budget_max}]
    opening = R.issue_open(open_checkout_sd_jwt: state.fetch(:opening).root_presentation, constraints: conditions,
      fixed: {}, agent_public_key_pem: agent.public_to_pem, issued_at: NOW, expires_at: NOW + 60,
      signer: sign(provider), public_key_pem: provider.public_to_pem, candidate_policy: :independent)
    {state: state, open: opening, series_scope: {tenant_id: "tenant", merchant_id: "shop", approval_id: "consent-42"}}
  end
  def self.enroll_series(store, fixture)
    provider, agent = fixture.fetch(:state).fetch(:keys)
    store.authorize_series!(**fixture.fetch(:series_scope), open_sd_jwt: fixture.fetch(:open), profile_ref: R::PROFILE_REF,
      trusted_provider_public_key_pem: provider.public_to_pem, expected_agent_public_key_pem: agent.public_to_pem, verified_at: NOW)
  end
  def self.occurrence(fixture, id)
    state = fixture.fetch(:state)
    provider, agent, merchant = state.fetch(:keys)
    cart = state.fetch(:checkout).merge("id" => "order-#{id}")
    checkout = M::CheckoutJWT.sign(checkout: cart, profile_ref: M::ConditionalCheckout::PROFILE_REF,
      signer: sign(merchant), public_key_pem: merchant.public_to_pem)
    host_inputs = state.fetch(:host_inputs).merge(host_checkout_jws: checkout.jwt,
      order: state.fetch(:host_inputs).fetch(:order).merge("order_id" => cart.fetch("id")))
    saved = M::InputBuilder.prepare(**host_inputs, challenge_id: "challenge-#{id}", nonce: "nonce-#{id}",
      issuer_id: "host", not_before: NOW, not_after: NOW + 60)
    closed_checkout = M::ConditionalCheckout.issue_closed(root_presentation: state.fetch(:opening).root_presentation,
      checkout_jwt: checkout.jwt, trusted_issuer_public_key_pem: provider.public_to_pem, agent_public_key_pem: agent.public_to_pem,
      trusted_merchant_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop", audience: "merchant-host",
      nonce: "nonce-#{id}", verified_at: NOW, signer: sign(agent))
    details = M::Payment.details(checkout_jwt: checkout.jwt, trusted_merchant_public_key_pem: merchant.public_to_pem,
      expected_merchant_id: "shop", payment_instrument: {"id" => "synthetic-card", "type" => "card"})
    closed = R.issue_closed(open_sd_jwt: fixture.fetch(:open), payment: details,
      trusted_provider_public_key_pem: provider.public_to_pem, agent_public_key_pem: agent.public_to_pem,
      audience: "processor", nonce: "payment-#{id}", verified_at: NOW, signer: sign(agent))
    inputs = M::InputBuilder.inputs(**host_inputs, saved_challenge: saved, terminal_jws: closed_checkout.terminal_jws,
      expected_challenge_issuer_id: "host", clock_source_id: "synthetic-clock", verified_at: NOW)
    raw = {closed_sd_jwt: closed.closed_sd_jwt, open_sd_jwt: fixture.fetch(:open), profile_ref: R::PROFILE_REF,
      checkout_mode: :conditional, checkout_inputs: inputs, expected_payment: details,
      trusted_provider_public_key_pem: provider.public_to_pem, expected_agent_public_key_pem: agent.public_to_pem,
      expected_audience: "processor", expected_nonce: "payment-#{id}", verified_at: NOW}
    scope = fixture.fetch(:series_scope).merge(operation_id: "operation-#{id}", occurrence_id: "occurrence-#{id}", order_id: cart.fetch("id"))
    receipt_context = {trusted_public_key_pem: merchant.public_to_pem, expected_issuer: "processor", expected_payment_id: "payment-#{id}",
      not_before: NOW, not_after: NOW + 300}
    {scope: scope, raw: raw, authorization: scope.merge(mode: :conditional, profile_ref: R::PROFILE_REF,
      checkout: cart, payment: details, receipt_context: receipt_context)}
  end
  def self.run
    fixture = build
    Dir.mktmpdir("synthetic-recurring-") do |directory|
      store = A::RecurringSQLiteStore.create(path: File.join(directory, "ledger.sqlite3"))
      enroll_series(store, fixture)
      service = A::Service.new(store: store)
      first = nil
      3.times do |index|
        item = occurrence(fixture, index + 1)
        store.authorize!(**item.fetch(:authorization))
        accepted = service.accept(**item.fetch(:scope), mode: :conditional, verification_inputs: item.fetch(:raw))
        raise "unexpected recurring acceptance" unless accepted.status == (index < 2 ? :reserved : :rejected)
        first ||= [item, accepted]
      end
      item, accepted = first
      retry_item = occurrence(fixture, 1) # Fresh signatures, same protected business occurrence.
      retry_result = service.accept(**retry_item.fetch(:scope), mode: :conditional, verification_inputs: retry_item.fetch(:raw))
      raise "retry gained capacity" unless retry_result.status == :pending && retry_result.ticket.nil?
      execution = service.start(ticket: accepted.ticket, verification_inputs: item.fetch(:raw))
      raise "missing first start" unless execution
      service.unknown(ticket: accepted.ticket)
      usage = store.usage(**fixture.fetch(:series_scope))
      raise "quota changed" unless usage[:reserved_occurrences] == 2 && usage[:reserved_amount] == 600
      puts "JPY ON_DEMAND: two authorized occurrences reserved; third exceeds quota and rejects"
      puts "Re-signed retry: no new Ticket; unknown outcome retains count=2 amount=600JPY"
      store.close
      reopened = A::RecurringSQLiteStore.new(path: File.join(directory, "ledger.sqlite3"))
      raise "lost quota" unless reopened.usage(**fixture.fetch(:series_scope)) == usage
      reopened.close
    end
    puts "Synthetic only; no payment performed. Calendar recurrence and non-JPY budgets unsupported."
  end
end
RecurringPaymentExample.run if $PROGRAM_NAME == __FILE__
