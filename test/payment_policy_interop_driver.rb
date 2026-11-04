# frozen_string_literal: true
# Synthetic JSON-lines transport. Private keys never leave this process.
require_relative "runtime_dependencies"
require "stringio"
if ENV["AP2_INSTALLED"] == "1"
  version = ENV.fetch("AP2_GEM_VERSION")
  gem "ap2_mandate_verifier", "= #{version}"
  require "ap2_mandate_verifier"
  installed = File.realpath(Gem.loaded_specs.fetch("ap2_mandate_verifier").full_gem_path + "/lib")
  source = File.realpath(File.join(__dir__, "../lib"))
  product = $LOADED_FEATURES.select { |f| f.match?(%r{/ap2_mandate_verifier(?:/|\.rb\z)}) }
  raise "source overlay" unless installed != source && !product.empty? && product.all? { |f| File.realpath(f).start_with?(installed + "/") }
else
  $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
  require_relative "../lib/ap2_mandate_verifier"
end
require_relative "../examples/conditional_checkout"
M = AP2MandateVerifier
P = M::Payment
S = M::SelectivePayment
NOW = 1_800_000_000
state = nil
STDOUT.sync = true
STDIN.each_line do |line|
  begin
    request = JSON.parse(line)
    a = request.fetch("arguments", {})
    result = case request.fetch("operation")
    when "fixture"
      mode = a.fetch("mode")
      previous = $stdout
      begin
        $stdout = StringIO.new
        context = ConditionalCheckoutExample.run
      ensure
        $stdout = previous
      end
      provider, agent, merchant = context.fetch(:keys)
      signer = ->(key) { M::CheckoutJWT.es256_signer(private_key: key) }
      profile = mode == "selective" ? M::PaymentPolicy::SELECTIVE_PROFILE_REF : M::PaymentPolicy::PROFILE_REF
      pisp = {"legal_name" => "Synthetic Payment Services Ltd", "brand_name" => "SyntheticPay", "domain_name" => "pisp.example"}
      date = a.fetch("date", "2027-01-15T12:00:00.125Z")
      checkout = context.fetch(:closed).checkout_jwt
      details = P.details(checkout_jwt: checkout, trusted_merchant_public_key_pem: merchant.public_to_pem,
        expected_merchant_id: "shop", payment_instrument: {"id" => "chosen-card", "type" => "card"},
        pisp: pisp, execution_date: date, profile_ref: M::PaymentPolicy::PROFILE_REF)
      constraints = [{"type" => "payment.amount_range", "currency" => "USD", "min" => 100, "max" => 300},
        {"type" => "payment.allowed_payees", "allowed" => [details.fetch("payee")]},
        {"type" => "payment.allowed_payment_instruments", "allowed" => [details.fetch("payment_instrument")]},
        {"type" => "payment.allowed_pisps", "allowed" => [pisp]},
        {"type" => "payment.execution_date", "not_before" => "2027-01-15T12:00:00.125Z", "not_after" => "2027-01-15T12:00:01.125Z"}]
      root = full = nil
      if mode == "direct"
        buyer = M::Buyer.issue_closed(checkout_jwt: checkout, approved_checkout_jwt: checkout,
          trusted_merchant_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop", issued_at: NOW,
          expires_at: NOW+60, signer: signer.call(provider), public_key_pem: provider.public_to_pem)
        raw = {closed_sd_jwt: buyer.closed_sd_jwt, trusted_provider_public_key_pem: provider.public_to_pem,
          trusted_merchant_public_key_pem: merchant.public_to_pem, expected_checkout_jwt: checkout, expected_merchant_id: "shop", verified_at: NOW}
        issued = P.issue_direct(payment: details, approved_payment: details, issued_at: NOW, expires_at: NOW+60,
          signer: signer.call(provider), public_key_pem: provider.public_to_pem, profile_ref: profile)
        verify = {checkout_mode: :direct}
      else
        raw = M::InputBuilder.inputs(**context.fetch(:host_inputs), saved_challenge: context.fetch(:saved),
          terminal_jws: context.fetch(:closed).terminal_jws, expected_challenge_issuer_id: "host", clock_source_id: "interop", verified_at: NOW)
        opening_args = {open_checkout_sd_jwt: context.fetch(:opening).root_presentation, constraints: constraints, fixed: {},
          agent_public_key_pem: agent.public_to_pem, issued_at: NOW, expires_at: NOW+60,
          signer: signer.call(provider), public_key_pem: provider.public_to_pem, profile_ref: profile, candidate_policy: :independent}
        if mode == "selective"
          constraints[1]["allowed"] << {"id" => "private-payee-B", "name" => "Private alternate payee"}
          constraints[2]["allowed"] << {"id" => "private-instrument-B", "type" => "bank"}
          full = S.issue_open(**opening_args, selective: :both, approved_combinations: [[0,0],[0,1],[1,0],[1,1]])
          root = S.select(open_sd_jwt: full, payee_index: 0, instrument_index: 0, profile_ref: profile)
        else
          root = P.issue_open(**opening_args)
        end
        closing = {payment: details, trusted_provider_public_key_pem: provider.public_to_pem, agent_public_key_pem: agent.public_to_pem,
          audience: "provider", nonce: "policy-nonce", verified_at: NOW, signer: signer.call(agent), profile_ref: profile}
        issued = mode == "selective" ? S.issue_closed(**closing, open_presentation: root) : P.issue_closed(**closing, open_sd_jwt: root)
        verify = {expected_agent_public_key_pem: agent.public_to_pem, expected_audience: "provider", expected_nonce: "policy-nonce"}
        verify.merge!(mode == "selective" ? {open_presentation: root} : {open_sd_jwt: root, checkout_mode: :conditional})
      end
      verify.merge!(closed_sd_jwt: issued.closed_sd_jwt, checkout_inputs: raw, expected_payment: details,
        trusted_provider_public_key_pem: provider.public_to_pem, verified_at: NOW, profile_ref: profile, trusted_pisp: pisp, execution_at: date)
      checked = mode == "selective" ? S.verify(**verify) : P.verify(**verify)
      raise "fixture failed" unless checked.verified?
      state = {mode: mode, verify: verify, profile: profile}
      receipts = %w[Success Error].map do |outcome|
        fields = outcome == "Success" ? {psp_confirmation_id: "psp", network_confirmation_id: "network"} : {error: "declined", error_description: "Synthetic"}
        receipt = M::PaymentReceipt.sign(closed_sd_jwt: issued.closed_sd_jwt, issuer: "processor", payment_id: "payment", outcome: outcome,
          issued_at: NOW, signer: signer.call(merchant), public_key_pem: merchant.public_to_pem, profile_ref: profile, **fields)
        {jwt: receipt.jwt, key: merchant.public_to_pem, outcome: outcome}
      end
      {mode: mode, profile: profile, root: root, full: full, closed: issued.closed_sd_jwt, details: details,
        constraints: constraints, provider: provider.public_to_pem, agent: agent.public_to_pem, receipts: receipts,
        open_checkout: context.fetch(:opening).root_presentation, checkout_jwt: checkout,
        runtime: {ruby: RUBY_VERSION, platform: RUBY_PLATFORM, gem: Gem.loaded_specs["ap2_mandate_verifier"]&.version&.to_s}}
    when "verify"
      args = state.fetch(:verify).merge(closed_sd_jwt: a.fetch("closed"), trusted_provider_public_key_pem: a.fetch("provider"))
      if state.fetch(:mode) != "direct"
        args[:expected_agent_public_key_pem] = a.fetch("agent")
        args[state.fetch(:mode) == "selective" ? :open_presentation : :open_sd_jwt] = a.fetch("root")
      end
      args[:expected_payment] = a["expected"] if a.key?("expected")
      args[:trusted_pisp] = a["trusted_pisp"] if a.key?("trusted_pisp")
      args[:execution_at] = a["execution_at"] if a.key?("execution_at")
      checked = state.fetch(:mode) == "selective" ? S.verify(**args) : P.verify(**args)
      {verified: checked.verified?, code: checked.code, payment: checked.payment, inspection: checked.inspect}
    when "receipt"
      checked = M::PaymentReceipt.verify(jwt: a.fetch("jwt"), closed_sd_jwt: a.fetch("closed"), profile_ref: state.fetch(:profile),
        trusted_public_key_pem: a.fetch("key"), expected_issuer: "processor", expected_payment_id: "payment",
        not_before: NOW, not_after: NOW+60, verified_at: NOW)
      {verified: checked.verified?, outcome: checked.outcome}
    else raise "unsupported"
    end
    puts JSON.generate(result)
  rescue StandardError => error
    warn "#{error.class}: #{error.backtrace.first(3).join("\n")}" if ENV["AP2_INTEROP_DEBUG"] == "1"
    puts JSON.generate(rejected: true)
  end
end
