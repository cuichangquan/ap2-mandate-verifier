# frozen_string_literal: true
# Installed Gem only; optional sqlite3=2.10.2. All keys/orders/effects synthetic.
require "ap2_mandate_verifier"
require "tmpdir"
require_relative "long_payment"

module LongPaymentAcceptanceExample
  M = AP2MandateVerifier
  A = M::PaymentAcceptance
  L = M::LongPayment
  W = LongPaymentExample
  def self.build(max_occurrences: 12, budget_max: 100000, amount: 40000, **wire_options)
    wire = W::Fixture.new(max_occurrences: max_occurrences, budget: budget_max, amount: amount, **wire_options)
    {wire: wire, series_scope: {tenant_id: "long-tenant", merchant_id: "shop", approval_id: "long-consent-1"}, amount: amount}
  end
  def self.periods
    W::PERIODS.map { |id,(first,last)| {id: id, not_before: first, not_after: last} }
  end
  def self.pair_arguments(fixture, period)
    raw = fixture.fetch(:wire).month(period).fetch(:verify_inputs)
    {payment_open: fixture.fetch(:wire).payment_open, checkout_open: fixture.fetch(:wire).checkout_open,
      trust_json: raw.fetch(:checkout_inputs).fetch(:trust_json), selection_json: raw.fetch(:checkout_inputs).fetch(:selection_json),
      verified_at: raw.fetch(:verified_at)}
  end
  def self.enroll_series(store, fixture)
    first = W::PERIODS.keys.find { |period| fixture.fetch(:wire).issued_at <= W.now(period) }
    store.authorize_series!(**fixture.fetch(:series_scope), **pair_arguments(fixture, first),
      periods: periods, schedule_policy_id: A::LongSQLiteStore::SCHEDULE_POLICY)
  end
  def self.refresh_authority(store, fixture, period)
    data = pair_arguments(fixture, period).slice(:trust_json, :selection_json, :verified_at)
    store.update_authority!(**fixture.fetch(:series_scope), expected_epoch: store.usage(**fixture.fetch(:series_scope)).fetch(:epoch), **data)
  end
  def self.occurrence(fixture, period:, id: "one", amount: nil, now: nil)
    item = fixture.fetch(:wire).month(period, amount || fixture.fetch(:amount))
    raw = item.fetch(:verify_inputs)
    if now
      raw = Marshal.load(Marshal.dump(raw))
      raw[:verified_at] = now
      raw[:checkout_inputs][:verified_at] = now
    end
    scope = fixture.fetch(:series_scope).merge(operation_id: "operation-#{period}-#{id}", occurrence_id: period,
      order_id: item.fetch(:cart).fetch("id"))
    merchant = fixture.fetch(:wire).merchant
    context = {trusted_public_key_pem: merchant.public_to_pem, expected_issuer: "processor",
      expected_payment_id: "payment-#{period}", not_before: W::PERIODS.fetch(period)[0], not_after: W::EXP + 86400}
    error = M::PaymentReceipt.sign(closed_sd_jwt: raw.fetch(:closed_sd_jwt), profile_ref: L::PROFILE_REF,
      issuer: "processor", payment_id: "payment-#{period}", outcome: "Error", issued_at: raw.fetch(:verified_at),
      error: "synthetic", error_description: "No automatic allowance refund", signer: W.signer(merchant), public_key_pem: merchant.public_to_pem)
    {scope: scope, raw: raw, authorization: scope.merge(mode: :conditional, profile_ref: L::PROFILE_REF,
      checkout: item.fetch(:cart), payment: item.fetch(:expected_payment), receipt_context: context),
      error_receipt: error.jwt, payment_receipt: item.fetch(:receipts).find { |receipt| receipt[:kind] == "payment" }.fetch(:jwt),
      checkout: item.fetch(:cart)}
  end
  def self.replace_root(store, fixture, replacement, period)
    current = store.usage(**fixture.fetch(:series_scope))
    store.replace_root!(**fixture.fetch(:series_scope), expected_epoch: current.fetch(:epoch),
      expected_root_reference: current.fetch(:root_reference), **pair_arguments(replacement, period))
  end
  def self.run
    fixture = build(amount: 8000) # Twelve approved uses, total96000JPY within100000.
    Dir.mktmpdir("synthetic-long-payment-") do |directory|
      store = A::LongSQLiteStore.create(path: File.join(directory, "ledger.sqlite3"))
      enroll_series(store, fixture)
      service = A::Service.new(store: store)
      dispatches = 0
      W::PERIODS.each_key do |period|
        refresh_authority(store, fixture, period)
        item = occurrence(fixture, period: period)
        store.authorize!(**item.fetch(:authorization))
        result = service.accept(**item.fetch(:scope), mode: :conditional, verification_inputs: item.fetch(:raw))
        raise "long reservation failed" unless result.status == :reserved && result.ticket
        execution = service.start(ticket: result.ticket, verification_inputs: item.fetch(:raw))
        raise "fresh start failed" unless execution
        dispatches += 1 # Synthetic in-process mock, NOT an external payment.
        service.unknown(ticket: result.ticket)
        recovered = service.reconcile(**item.fetch(:scope), receipt_jwt: item.fetch(:payment_receipt), verified_at: item.fetch(:raw).fetch(:verified_at))
        raise "original Receipt failed" unless recovered.status == :receipt_success && recovered.ticket.nil?
      end
      usage = store.usage(**fixture.fetch(:series_scope))
      raise "bad long totals" unless dispatches == 12 && usage[:reserved_occurrences] == 12 && usage[:reserved_amount] == 96000
      puts "Same long Open pair: 12 explicit leap-year periods, 12 mock starts, reserved96000JPY within100000JPY"
      puts "Fresh proof/current authority checked before each start; original Receipts reconciled without new Tickets"
      store.close
    end
    puts "Synthetic only; no payment/settlement. Host windows are an explicit local profile, not generic AP2 MONTHLY semantics."
  end
end
LongPaymentAcceptanceExample.run if $PROGRAM_NAME == __FILE__
