# frozen_string_literal: true
# Installed SDK; optional sqlite3=2.10.2. Synthetic temporary DB/mock processor.
# Production uses a protected persistent existing DB, never per-request temp storage.
require "ap2_mandate_verifier"
require "tmpdir"
require_relative "selective_checkout"
module PaymentAcceptanceExample
  M = AP2MandateVerifier
  A = M::PaymentAcceptance
  NOW = SelectiveCheckoutExample::NOW
  def self.run
    state = SelectiveCheckoutExample.run
    provider, agent, merchant = state.fetch(:keys)
    signer = ->(key) { M::CheckoutJWT.es256_signer(private_key: key) }
    checkout = state.fetch(:closed).checkout_jwt
    details = M::Payment.details(checkout_jwt: checkout, trusted_merchant_public_key_pem: merchant.public_to_pem,
      expected_merchant_id: "shop", payment_instrument: {"id" => "synthetic-card", "type" => "card"})
    buyer = M::Buyer.issue_closed(checkout_jwt: checkout, approved_checkout_jwt: checkout,
      trusted_merchant_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop", issued_at: NOW,
      expires_at: NOW + 60, signer: signer.call(provider), public_key_pem: provider.public_to_pem)
    payment_args = {payment: details, approved_payment: details, issued_at: NOW, expires_at: NOW + 60,
      signer: signer.call(provider), public_key_pem: provider.public_to_pem}
    payment = M::Payment.issue_direct(**payment_args)
    raw = {closed_sd_jwt: payment.closed_sd_jwt, checkout_mode: :direct, checkout_inputs: {
      closed_sd_jwt: buyer.closed_sd_jwt, trusted_provider_public_key_pem: provider.public_to_pem,
      trusted_merchant_public_key_pem: merchant.public_to_pem, expected_checkout_jwt: checkout,
      expected_merchant_id: "shop", verified_at: NOW}, expected_payment: details,
      trusted_provider_public_key_pem: provider.public_to_pem, verified_at: NOW}
    # These identifiers/terms are protected authenticated Host approval state,
    # never request-generated retry UUIDs or values copied from received claims.
    scope = {tenant_id: "tenant", merchant_id: "shop", operation_id: "office-1/payment-1",
      approval_id: "synthetic-consent-1", occurrence_id: "payment-1", order_id: "office-1"}
    Dir.mktmpdir("ap2-acceptance-example") do |directory|
      path = File.join(directory, "acceptance.sqlite3")
      store = A::SQLiteStore.create(path: path) # Explicit ONE-TIME bootstrap only.
      store.authorize!(**scope, mode: :direct, profile_ref: M::Payment::PROFILE_REF,
        checkout: state.fetch(:checkout), payment: details, receipt_context: {
          trusted_public_key_pem: merchant.public_to_pem, expected_issuer: "processor-A",
          expected_payment_id: "synthetic-payment-1", not_before: NOW, not_after: NOW + 1000})
      service = A::Service.new(store: store)
      first = service.accept(**scope, mode: :direct, verification_inputs: raw)
      raise "first reservation failed" unless first.status == :reserved && first.ticket
      # New salt/signature changes original bytes, but not the approved business operation.
      resigned = M::Payment.issue_direct(**payment_args)
      replay = service.accept(**scope, mode: :direct, verification_inputs: raw.merge(closed_sd_jwt: resigned.closed_sd_jwt))
      raise "retry issued another ticket" unless replay.status == :pending && replay.ticket.nil? &&
        replay.closed_sd_jwt == payment.closed_sd_jwt && replay.processor_key == first.processor_key
      puts "First=reserved; re-signed retry=pending; no second Ticket; first wire retained"
      # Production supplies FRESH authenticated Host/trust/order/clock inputs here.
      execution = service.start(ticket: first.ticket, verification_inputs: raw)
      raise "start failed" unless execution && !service.start(ticket: first.ticket, verification_inputs: raw)
      mock_processor = {} # This counter is a demo side effect, not real money.
      mock_processor[execution.processor_key] ||= "synthetic-processor-result"
      service.unknown(ticket: first.ticket) # Simulated response loss after dispatch.
      store.close
      # New process/service opens the SAME existing ledger. No create/reset fallback.
      reopened = A::SQLiteStore.new(path: path)
      recovered = A::Service.new(store: reopened)
      pending = recovered.lookup(**scope)
      raise "unknown attempt reopened" unless pending.status == :unknown && pending.ticket.nil? &&
        pending.processor_key == execution.processor_key
      puts "After reopen=unknown; original processor key available for QUERY; mock dispatches=#{mock_processor.size}"
      # Delayed authentic Receipt can resolve an unknown attempt after Mandate expiry.
      receipt = M::PaymentReceipt.sign(closed_sd_jwt: execution.closed_sd_jwt, issuer: "processor-A",
        payment_id: "synthetic-payment-1", outcome: "Success", issued_at: NOW + 120,
        psp_confirmation_id: "synthetic-psp", network_confirmation_id: "synthetic-network",
        signer: signer.call(merchant), public_key_pem: merchant.public_to_pem)
      final = recovered.reconcile(**scope, receipt_jwt: receipt.jwt, verified_at: NOW + 120)
      raise "Receipt recovery failed" unless final.status == :receipt_success && final.ticket.nil? &&
        final.reference == first.reference
      puts "Delayed original-wire Receipt=receipt_success; reconciliation grants no Ticket"
      reopened.close
    end
    puts "Synthetic temporary demo only. Durable reservation is not settlement or external exactly-once; no payment performed."
  end
end
PaymentAcceptanceExample.run if $PROGRAM_NAME == __FILE__
