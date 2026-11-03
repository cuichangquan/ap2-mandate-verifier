# frozen_string_literal: true
# Offline test RPC. All private signing keys stay in this Ruby process memory.
require_relative "runtime_dependencies"
require "stringio"
if ENV["AP2_INSTALLED"] == "1"
  version = ENV.fetch("AP2_GEM_VERSION")
  gem "ap2_mandate_verifier", "= #{version}"
  require "ap2_mandate_verifier"
  spec = Gem.loaded_specs.fetch("ap2_mandate_verifier")
  installed = File.realpath(File.join(spec.full_gem_path, "lib"))
  source = File.realpath(File.join(__dir__, "../lib"))
  product = $LOADED_FEATURES.select { |f| f.match?(%r{/ap2_mandate_verifier(?:/|\.rb\z)}) }
  raise "source overlay" unless spec.version.to_s == version && installed != source &&
    product.all? { |f| File.realpath(f).start_with?(installed + "/") }
else
  $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
  require "ap2_mandate_verifier"
  require_relative "../lib/ap2_mandate_verifier/selective_payment" unless defined?(AP2MandateVerifier::SelectivePayment)
end
require_relative "../examples/conditional_checkout"
M = AP2MandateVerifier
S = M::SelectivePayment
NOW = 1_800_000_000
state = nil
STDOUT.sync = true
STDIN.each_line do |line|
  begin
    request = JSON.parse(line)
    args = request.fetch("arguments", {}).transform_keys(&:to_sym)
    result = case request.fetch("operation")
    when "fixture"
      mode = args.fetch(:mode).to_sym
      original_stdout = $stdout
      begin
        $stdout = StringIO.new
        context = ConditionalCheckoutExample.run
      ensure
        $stdout = original_stdout
      end
      provider, agent, merchant = context.fetch(:keys)
      signer = ->(key) { M::CheckoutJWT.es256_signer(private_key: key) }
      details = M::Payment.details(checkout_jwt: context.fetch(:closed).checkout_jwt,
        trusted_merchant_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop",
        payment_instrument: {"id" => "approved-card-A", "type" => "card", "description" => "Chosen card A"})
      payees = [details.fetch("payee"), {"id" => "unselected-payee-secret-B", "name" => "Private alternate merchant B"}]
      instruments = [details.fetch("payment_instrument"),
        {"id" => "unselected-instrument-secret-B", "type" => "bank", "description" => "Private alternate instrument B"}]
      selected_index = args.fetch(:selected_index, 0)
      raise "test index" unless [0, 1].include?(selected_index)
      if selected_index == 1
        payees.reverse!; instruments.reverse!
      end
      constraints = [{"type" => "payment.amount_range", "currency" => "USD", "min" => 100, "max" => 300},
        {"type" => "payment.allowed_payees", "allowed" => payees},
        {"type" => "payment.allowed_payment_instruments", "allowed" => instruments}]
      open_args = {open_checkout_sd_jwt: context.fetch(:opening).root_presentation, constraints: constraints,
        fixed: {}, approved_combinations: [[0, 0], [0, 1], [1, 0], [1, 1]], selective: mode,
        agent_public_key_pem: agent.public_to_pem, issued_at: NOW, expires_at: NOW+60,
        signer: signer.call(provider), public_key_pem: provider.public_to_pem}
      full = S.issue_open(**open_args)
      selected = S.select(open_sd_jwt: full, payee_index: mode == :instruments ? nil : selected_index, instrument_index: mode == :payees ? nil : selected_index)
      issue_args = {open_presentation: selected, payment: details, trusted_provider_public_key_pem: provider.public_to_pem,
        agent_public_key_pem: agent.public_to_pem, audience: "credential-provider", nonce: "synthetic-payment-nonce",
        verified_at: NOW, signer: signer.call(agent)}
      closed = S.issue_closed(**issue_args)
      raw = M::InputBuilder.inputs(**context.fetch(:host_inputs), saved_challenge: context.fetch(:saved),
        terminal_jws: context.fetch(:closed).terminal_jws, expected_challenge_issuer_id: "host",
        clock_source_id: "independent-interop-clock", verified_at: NOW)
      verify_args = {open_presentation: selected, closed_sd_jwt: closed.closed_sd_jwt,
        checkout_inputs: raw, expected_payment: details, trusted_provider_public_key_pem: provider.public_to_pem,
        expected_agent_public_key_pem: agent.public_to_pem, expected_audience: "credential-provider",
        expected_nonce: "synthetic-payment-nonce", verified_at: NOW}
      checked = S.verify(**verify_args)
      raise "fixture verification failed" unless checked.verified?
      state = {context: context, provider: provider, agent: agent, merchant: merchant, details: details,
        raw: raw, issue: issue_args, verify: verify_args, open: open_args, signer: signer}
      receipts = %w[Success Error].map do |outcome|
        fields = outcome == "Success" ? {psp_confirmation_id: "test-psp", network_confirmation_id: "test-network"} :
          {error: "declined", error_description: "Synthetic rejection"}
        receipt = M::PaymentReceipt.sign(closed_sd_jwt: closed.closed_sd_jwt, issuer: "processor", payment_id: "payment-1",
          outcome: outcome, issued_at: NOW, signer: signer.call(merchant), public_key_pem: merchant.public_to_pem, **fields)
        {jwt: receipt.jwt, outcome: outcome, reference: receipt.reference, key: merchant.public_to_pem}
      end
      {full: full, selected: selected, closed: closed.closed_sd_jwt, provider: provider.public_to_pem,
        agent: agent.public_to_pem, details: details, constraints: constraints, fixed: {},
        open_checkout: context.fetch(:opening).root_presentation, checkout_jwt: context.fetch(:closed).checkout_jwt,
        audience: "credential-provider", nonce: "synthetic-payment-nonce", receipts: receipts,
        result_inspection: checked.inspect}
    when "verify_external"
      raise "fixture not prepared" unless state
      checked = S.verify(**state.fetch(:verify).merge(open_presentation: args.fetch(:open), closed_sd_jwt: args.fetch(:closed),
        trusted_provider_public_key_pem: args.fetch(:provider), expected_agent_public_key_pem: args.fetch(:agent)))
      {verified: checked.verified?, code: checked.code, payment: checked.payment, inspection: checked.inspect}
    when "reclose"
      issued = S.issue_closed(**state.fetch(:issue).merge(open_presentation: args.fetch(:open)))
      {closed: issued.closed_sd_jwt}
    when "alternate_issuance"
      {full: S.issue_open(**state.fetch(:open))}
    when "verify_receipt"
      checked = M::PaymentReceipt.verify(jwt: args.fetch(:jwt), closed_sd_jwt: args.fetch(:closed),
        trusted_public_key_pem: args.fetch(:key), expected_issuer: "processor", expected_payment_id: "payment-1",
        not_before: NOW, not_after: NOW+60, verified_at: NOW)
      {verified: checked.verified?, outcome: checked.outcome, succeeded: checked.payment_succeeded?, rejected: checked.payment_rejected?}
    else raise "unsupported test operation"
    end
    puts JSON.generate(result)
  rescue StandardError, LoadError
    # No hidden candidate content, parser exceptions or key material crosses RPC.
    puts JSON.generate(rejected: true)
  end
end
