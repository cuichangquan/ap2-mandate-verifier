# frozen_string_literal: true
require_relative "runtime_dependencies"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__)) unless ENV["AP2_INSTALLED"] == "1"
require "ap2_mandate_verifier"
require "stringio"
require_relative "../examples/recurring_payment"

module RecurringAcceptanceTest
  E = RecurringPaymentExample
  M = AP2MandateVerifier
  A = M::PaymentAcceptance
  R = M::RecurringPayment
  @checks = 0
  def self.assert(value, label)
    @checks += 1
    raise "recurring acceptance: #{label}" unless value
  end
  def self.raises(type)
    yield
    raise "expected fixed exception"
  rescue type => error
    assert(error.cause.nil? && !error.message.include?("eyJ"), "fixed exception has no signed data/cause")
  end
  def self.fixture(**args)
    original = $stdout
    $stdout = StringIO.new
    E.build(**args)
  ensure
    $stdout = original
  end
  def self.enroll(store, fixture, id)
    item = E.occurrence(fixture, id)
    store.authorize!(**item.fetch(:authorization))
    item
  end
  def self.accept(service, item) = service.accept(**item.fetch(:scope), mode: :conditional, verification_inputs: item.fetch(:raw))
  Dir.mktmpdir do |dir|
    path = File.join(dir, "ledger")
    f = fixture(max_occurrences: 2, budget_max: 900)
    store = A::RecurringSQLiteStore.create(path: path)
    assert(E.enroll_series(store, f), "protected full Open enrollment")
    assert(E.enroll_series(store, f), "enrollment idempotent")
    one, two, three = (1..3).map { |id| enroll(store, f, id) }
    service = A::Service.new(store: store)
    first = accept(service, one)
    assert(first.status == :reserved && first.ticket, "first capability")
    retry_one = E.occurrence(f, 1)
    assert(retry_one[:raw][:closed_sd_jwt] != one[:raw][:closed_sd_jwt], "retry uses freshly signed wires")
    retry_result = accept(service, retry_one)
    assert(retry_result.status == :pending && retry_result.ticket.nil? && retry_result.closed_sd_jwt == first.closed_sd_jwt, "retry retains first projection")
    assert(store.usage(**f[:series_scope])[:reserved_occurrences] == 1, "retry not charged")
    second = accept(service, two)
    assert(second.status == :reserved && second.ticket, "distinct authorized next occurrence")
    assert(accept(service, three).status == :rejected, "count max rejects even with budget remaining")
    assert(store.usage(**f[:series_scope])[:reserved_amount] == 600, "count failure does not charge")
    execution = service.start(ticket: first.ticket, verification_inputs: one[:raw])
    assert(execution && service.start(ticket: first.ticket, verification_inputs: one[:raw]).nil?, "one fenced start")
    assert(service.unknown(ticket: first.ticket).status == :unknown, "unknown retained")
    provider, agent, merchant = f[:state][:keys]
    receipt = M::PaymentReceipt.sign(closed_sd_jwt: execution.closed_sd_jwt, profile_ref: R::PROFILE_REF,
      issuer: "processor", payment_id: "payment-1", outcome: "Error", issued_at: E::NOW + 120,
      error: "synthetic", error_description: "No automatic refund", signer: E.sign(merchant), public_key_pem: merchant.public_to_pem)
    assert(service.reconcile(**one[:scope], receipt_jwt: receipt.jwt, verified_at: E::NOW + 120).status == :receipt_error, "late original Error reconciles")
    assert(accept(service, three).status == :rejected && store.usage(**f[:series_scope])[:reserved_amount] == 600, "Error never refunds allowance")
    store.revoke_series!(**f[:series_scope])
    assert(service.start(ticket: second.ticket, verification_inputs: two[:raw]).nil?, "revocation stops reserved start")
    E.enroll_series(store, f)
    assert(!store.usage(**f[:series_scope])[:active], "reenroll never reactivates")
    assert(!store.inspect.include?(f[:open]) && !first.inspect.include?(f[:open]), "inspection redacted")
    store.close
    store = A::RecurringSQLiteStore.new(path: path)
    usage = store.usage(**f[:series_scope])
    assert(usage[:reserved_occurrences] == 2 && usage[:reserved_amount] == 600 && !usage[:active], "restart preserves count amount revocation")
    raises(A::Unavailable) { A::SQLiteStore.new(path: path) }
    raises(A::Unavailable) { A::RecurringSQLiteStore.create(path: path) }
    raises(A::Invalid) { store.usage(**f[:series_scope].merge(tenant_id: "other")) }
    # Same signed Open cannot multiply its quota by merchant or consent aliases.
    [f[:series_scope].merge(merchant_id: "other"), f[:series_scope].merge(approval_id: "alias")].each do |ids|
      raises(A::Conflict) do
        store.authorize_series!(**ids, open_sd_jwt: f[:open], profile_ref: R::PROFILE_REF,
          trusted_provider_public_key_pem: provider.public_to_pem, expected_agent_public_key_pem: agent.public_to_pem, verified_at: E::NOW)
      end
    end
    store.close
    old_path = File.join(dir, "old")
    old = A::SQLiteStore.create(path: old_path)
    raises(A::Invalid) { old.authorize!(**one[:authorization]) }
    assert(accept(A::Service.new(store: old), one).status == :rejected, "schema1 cannot bypass recurring quota")
    old.close
    raises(A::Unavailable) { A::RecurringSQLiteStore.new(path: old_path) }
    raises(A::Unavailable) { A::RecurringSQLiteStore.new(path: File.join(dir, "missing")) }

    f2 = fixture(max_occurrences: 5, budget_max: 500)
    budget_store = A::RecurringSQLiteStore.create(path: File.join(dir, "budget"))
    E.enroll_series(budget_store, f2)
    s2 = A::Service.new(store: budget_store)
    a, b = [1,2].map { |id| enroll(budget_store, f2, id) }
    assert(accept(s2, a).status == :reserved && accept(s2, b).status == :rejected, "cumulative budget separate from count")
    assert(budget_store.usage(**f2[:series_scope])[:reserved_occurrences] == 1, "overbudget does not consume count")
    budget_store.close

    # Failure AFTER quota update but BEFORE occurrence insert must roll back BOTH.
    faulty_class = Class.new(A::RecurringSQLiteStore) do
      private
      def charge_reservation!(scope, record)
        super
        raise A::Unavailable
      end
    end
    faulty = faulty_class.create(path: File.join(dir, "fault"))
    E.enroll_series(faulty, f2)
    fault_item = enroll(faulty, f2, 1)
    assert(accept(A::Service.new(store: faulty), fault_item).status == :unavailable, "fault yields no capability")
    assert(faulty.usage(**f2[:series_scope])[:reserved_occurrences] == 0 && faulty.usage(**f2[:series_scope])[:reserved_amount] == 0, "atomic rollback restores both quota values")
    faulty.close
    recovered = A::RecurringSQLiteStore.new(path: File.join(dir, "fault"))
    assert(accept(A::Service.new(store: recovered), fault_item).status == :reserved, "known rolled-back operation can reserve once")
    recovered.close
  end
  puts "recurring acceptance: #{@checks} assertions passed"
end
