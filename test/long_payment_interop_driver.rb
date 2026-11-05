# frozen_string_literal: true
# Public JSONL test RPC. Synthetic signing keys live only in process RAM.
require_relative "runtime_dependencies"
if ENV["AP2_INSTALLED"] == "1"
  gem "ap2_mandate_verifier", "= #{ENV.fetch('AP2_GEM_VERSION')}"
  require "ap2_mandate_verifier"
  installed = File.realpath(Gem.loaded_specs.fetch("ap2_mandate_verifier").full_gem_path + "/lib")
  source = File.realpath(File.join(__dir__, "../lib"))
  features = $LOADED_FEATURES.select { |f| f.match?(%r{/ap2_mandate_verifier(?:/|\.rb\z)}) }
  raise "source overlay" unless installed != source && !features.empty? && features.all? { |f| File.realpath(f).start_with?(installed + "/") }
else
  $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
  require "ap2_mandate_verifier"
end
require_relative "../examples/long_payment"
require_relative "../examples/long_payment_acceptance"
M = AP2MandateVerifier
L = M::LongPayment
STDOUT.sync = true
fixture = nil
cache = nil
STDIN.each_line do |line|
  begin
    request = JSON.parse(line)
    args = request.fetch("arguments", {})
    result = case request.fetch("operation")
    when "fixture"
      fixture ||= LongPaymentExample::Fixture.new
      cache ||= fixture.public_fixture.merge(runtime: {ruby: RUBY_VERSION, platform: RUBY_PLATFORM,
        gem: Gem.loaded_specs["ap2_mandate_verifier"]&.version&.to_s})
    when "verify_external"
      raise "unsupported context override" unless (args.keys - %w[period checkout_open payment_open checkout_jwt checkout_closed payment_closed provider agent merchant amount]).empty?
      inputs = LongPaymentExample.inputs(**args.transform_keys(&:to_sym))
      checked = L.verify(**inputs)
      {verified: checked.verified?, code: checked.code}
    when "host_budget_control"
      raise "fixture first" unless fixture && cache
      result = nil
      Dir.mktmpdir("long-interop-budget-") do |directory|
        store = M::PaymentAcceptance::LongSQLiteStore.create(path: File.join(directory, "ledger.sqlite3"))
        host = {wire: fixture, amount: 40000,
          series_scope: {tenant_id: "long-tenant", merchant_id: "shop", approval_id: "interop-agreement"}}
        LongPaymentAcceptanceExample.enroll_series(store, host)
        service = M::PaymentAcceptance::Service.new(store: store)
        LongPaymentExample::PERIODS.keys.first(11).each_with_index do |period, index|
          item = LongPaymentAcceptanceExample.occurrence(host, period: period, id: "prior", amount: index == 10 ? 60001 : 40000)
          store.authorize!(**item.fetch(:authorization))
          accepted = service.accept(**item.fetch(:scope), mode: :conditional, verification_inputs: item.fetch(:raw))
          raise "prior control failed" unless accepted.ticket && service.start(ticket: accepted.ticket, verification_inputs: item.fetch(:raw))
          service.unknown(ticket: accepted.ticket)
        end
        target = cache.fetch(:months).last
        last = LongPaymentAcceptanceExample.occurrence(host, period: "2028-12", id: "last")
        authorization = last.fetch(:authorization).merge(checkout: target.fetch(:cart), payment: target.fetch(:expected_payment))
        store.authorize!(**authorization)
        accepted = service.accept(**last.fetch(:scope), mode: :conditional, verification_inputs: target.fetch(:verify_inputs))
        usage = store.usage(**host.fetch(:series_scope))
        result = {status: accepted.status, ticket: !accepted.ticket.nil?, count: usage.fetch(:reserved_occurrences),
          spent: usage.fetch(:reserved_amount), root_sha256: Digest::SHA256.hexdigest(fixture.payment_open),
          closed_sha256: Digest::SHA256.hexdigest(target.fetch(:payment_closed)),
          prior_starts: 11, effect_scope: "in-process capability control; no payment effect performed"}
        store.close
      end
      result
    when "receipt_verify"
      at = LongPaymentExample.now(args.fetch("period"))
      common = {jwt: args.fetch("jwt"), closed_sd_jwt: args.fetch("closed"), trusted_public_key_pem: args.fetch("key"),
        expected_issuer: "processor", not_before: at - 1, not_after: at + 120, verified_at: at}
      checked = if args.fetch("kind") == "checkout"
        M::CheckoutReceipt.verify(**common, profile_ref: L::CHECKOUT_PROFILE_REF)
      else
        M::PaymentReceipt.verify(**common, profile_ref: L::PROFILE_REF, expected_payment_id: "payment-#{args.fetch('period')}")
      end
      {verified: checked.verified?}
    else raise "unknown LONG interoperability operation"
    end
    puts JSON.generate(result)
  rescue StandardError => error
    warn "#{error.class}: #{error.backtrace.first(3).join('\n')}" if ENV["AP2_INTEROP_DEBUG"] == "1"
    puts JSON.generate(verified: false, rejected: true)
  end
end
