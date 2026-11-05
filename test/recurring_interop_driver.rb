# frozen_string_literal: true
# Offline public-wire RPC; synthetic private keys stay in RAM.
require_relative "runtime_dependencies"
require "stringio"
if ENV["AP2_INSTALLED"] == "1"
  gem "ap2_mandate_verifier", "= #{ENV.fetch('AP2_GEM_VERSION')}"
  require "ap2_mandate_verifier"
  installed = File.realpath(Gem.loaded_specs.fetch("ap2_mandate_verifier").full_gem_path + "/lib")
  source = File.realpath(File.join(__dir__, "../lib"))
  product = $LOADED_FEATURES.select { |f| f.match?(%r{/ap2_mandate_verifier(?:/|\.rb\z)}) }
  raise "source overlay" unless installed != source && !product.empty? && product.all? { |f| File.realpath(f).start_with?(installed + "/") }
else
  $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
  require "ap2_mandate_verifier"
end
require_relative "../examples/recurring_payment"
M = AP2MandateVerifier
R = M::RecurringPayment
NOW = 1_800_000_000
state = nil
STDOUT.sync = true
STDIN.each_line do |line|
  begin
    request = JSON.parse(line)
    a = request.fetch("arguments", {})
    result = case request.fetch("operation")
    when "fixture"
      old = $stdout
      begin
        $stdout = StringIO.new
        fixture = RecurringPaymentExample.build(max_occurrences: 2, budget_max: 600)
      ensure
        $stdout = old
      end
      item = RecurringPaymentExample.occurrence(fixture, "interop")
      provider, agent, merchant = fixture.fetch(:state).fetch(:keys)
      full = root = fixture.fetch(:open)
      content = JSON.parse(Base64.urlsafe_decode64(full.split("~")[1]))[1]
      constraints = content.fetch("constraints").reject { |c| c["type"] == "payment.reference" }
      profile = R::PROFILE_REF
      raw = item.fetch(:raw)
      if a.fetch("mode") == "selective"
        profile = R::SELECTIVE_PROFILE_REF
        constraints.find { |c| c["type"] == "payment.allowed_payees" }["allowed"] << {"id" => "private-payee-B", "name" => "Private alternate"}
        constraints.find { |c| c["type"] == "payment.allowed_payment_instruments" }["allowed"] << {"id" => "private-card-B", "type" => "bank"}
        full = R.issue_open(open_checkout_sd_jwt: fixture.fetch(:state).fetch(:opening).root_presentation,
          constraints: constraints, fixed: {}, agent_public_key_pem: agent.public_to_pem, issued_at: NOW, expires_at: NOW+60,
          signer: RecurringPaymentExample.sign(provider), public_key_pem: provider.public_to_pem,
          profile_ref: profile, candidate_policy: :independent, selective: :both, approved_combinations: [[0,0],[0,1],[1,0],[1,1]])
        root = R.select(open_sd_jwt: full, payee_index: 0, instrument_index: 0, profile_ref: profile)
        closed = R.issue_closed(open_presentation: root, payment: raw.fetch(:expected_payment), trusted_provider_public_key_pem: provider.public_to_pem,
          agent_public_key_pem: agent.public_to_pem, audience: "processor", nonce: "payment-interop", verified_at: NOW,
          signer: RecurringPaymentExample.sign(agent), profile_ref: profile)
        raw = raw.reject { |k,_| %i[open_sd_jwt checkout_mode].include?(k) }.merge(open_presentation: root,
          closed_sd_jwt: closed.closed_sd_jwt, profile_ref: profile)
      end
      checked = R.verify(**raw)
      raise "fixture failed" unless checked.verified?
      state = {raw: raw, profile: profile}
      receipts = %w[Success Error].map do |outcome|
        fields = outcome == "Success" ? {psp_confirmation_id: "synthetic-psp", network_confirmation_id: "synthetic-net"} : {error: "declined", error_description: "Synthetic decline"}
        receipt = M::PaymentReceipt.sign(closed_sd_jwt: raw.fetch(:closed_sd_jwt), profile_ref: profile,
          issuer: "processor", payment_id: "payment", outcome: outcome, issued_at: NOW,
          signer: RecurringPaymentExample.sign(merchant), public_key_pem: merchant.public_to_pem, **fields)
        {jwt: receipt.jwt, key: merchant.public_to_pem, outcome: outcome}
      end
      {mode: a.fetch("mode"), profile: profile, full: full, root: root, closed: raw.fetch(:closed_sd_jwt),
        details: raw.fetch(:expected_payment), constraints: constraints, provider: provider.public_to_pem, agent: agent.public_to_pem,
        open_checkout: fixture.fetch(:state).fetch(:opening).root_presentation, checkout_jwt: raw.fetch(:checkout_inputs).fetch(:host_checkout_jws),
        receipts: receipts, runtime: {ruby: RUBY_VERSION, platform: RUBY_PLATFORM, gem: Gem.loaded_specs["ap2_mandate_verifier"]&.version&.to_s}}
    when "verify"
      raw = state.fetch(:raw).merge(closed_sd_jwt: a.fetch("closed"), trusted_provider_public_key_pem: a.fetch("provider"),
        expected_agent_public_key_pem: a.fetch("agent"))
      raw[state.fetch(:profile) == R::PROFILE_REF ? :open_sd_jwt : :open_presentation] = a.fetch("root")
      checked = R.verify(**raw)
      {verified: checked.verified?, code: checked.code, inspection: checked.inspect}
    when "receipt"
      checked = M::PaymentReceipt.verify(jwt: a.fetch("jwt"), closed_sd_jwt: a.fetch("closed"), profile_ref: state.fetch(:profile),
        trusted_public_key_pem: a.fetch("key"), expected_issuer: "processor", expected_payment_id: "payment", not_before: NOW, not_after: NOW+60, verified_at: NOW)
      {verified: checked.verified?, outcome: checked.outcome}
    else raise "unknown operation"
    end
    puts JSON.generate(result)
  rescue StandardError => error
    warn "#{error.class}: #{error.backtrace.first(3).join("\n")}" if ENV["AP2_INTEROP_DEBUG"] == "1"
    puts JSON.generate(rejected: true)
  end
end
