# frozen_string_literal: true
# Source-checkout supplement to published 1.6.0; no SDK source overlay.
# All orders, approvals, keys and clocks are synthetic. No payment is performed.
gem "ap2_mandate_verifier", "= 1.6.0"
spec = Gem::Specification.find_by_name("ap2_mandate_verifier", "1.6.0")
require File.join(spec.full_gem_path, "examples/long_payment_acceptance.rb")

module LongPaymentLimitsExample
  E = LongPaymentAcceptanceExample
  A = AP2MandateVerifier::PaymentAcceptance

  def self.run
    puts "=== 12 months: 8,000 JPY/month, 100,000 JPY budget ==="
    E.run
    puts "=== Separate approval: 40,000 JPY/month, 100,000 JPY budget ==="
    fixture = E.build(amount: 40000, max_occurrences: 3, budget_max: 100000)
    Dir.mktmpdir("synthetic-budget-") do |directory|
      store = A::LongSQLiteStore.create(path: File.join(directory, "ledger.sqlite3"))
      begin
        E.enroll_series(store, fixture)
        service = A::Service.new(store: store)
        %w[2028-01 2028-02 2028-03].each_with_index do |period, index|
          E.refresh_authority(store, fixture, period)
          item = E.occurrence(fixture, period: period)
          # Independent stateless control: this month's signed Mandate is valid.
          raise "wire control failed" unless AP2MandateVerifier::LongPayment.verify(**item.fetch(:raw)).verified?
          store.authorize!(**item.fetch(:authorization))
          result = service.accept(**item.fetch(:scope), mode: :conditional, verification_inputs: item.fetch(:raw))
          usage = store.usage(**fixture.fetch(:series_scope))
          expected = index < 2 ? :reserved : :rejected
          expected_amount = [40000, 80000, 80000].fetch(index)
          raise "budget oracle failed" unless result.status == expected &&
            !!result.ticket == (index < 2) && usage.fetch(:reserved_amount) == expected_amount &&
            usage.fetch(:reserved_occurrences) == [1, 2, 2].fetch(index)
          puts "#{period}: wire_valid=true; acceptance=#{result.status}; reserved=#{usage.fetch(:reserved_amount)} JPY; ticket=#{!result.ticket.nil?}"
        end
        puts "March would total 120000 > 100000 JPY: rejected, no Ticket, reservation remains 80000 JPY."
        puts "Reservations are not settlement; this comparison never starts a processor."
      ensure
        store.close
      end
    end
  end
end
LongPaymentLimitsExample.run if $PROGRAM_NAME == __FILE__
