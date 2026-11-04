# frozen_string_literal: true
# Offline JSON-lines test RPC; private keys remain process-local.
require_relative "runtime_dependencies"
if ENV["AP2_INSTALLED"] == "1"
  gem "ap2_mandate_verifier", "= #{ENV.fetch('AP2_GEM_VERSION')}"
  require "ap2_mandate_verifier"
  installed = File.realpath(Gem.loaded_specs.fetch("ap2_mandate_verifier").full_gem_path + "/lib")
  source = File.realpath(File.join(__dir__, "../lib"))
  features = $LOADED_FEATURES.select { |f| f.match?(%r{/ap2_mandate_verifier(?:/|\.rb\z)}) }
  raise "source overlay" unless installed != source && !features.empty? && features.all? { |f| File.realpath(f).start_with?(installed + "/") }
else
  require_relative "../lib/ap2_mandate_verifier"
end
require_relative "support/multi_item_fixture"
M = AP2MandateVerifier
S = M::SelectiveCheckout
NOW = 1_800_000_000
state = nil
STDOUT.sync = true

def verified(state, root, terminal, provider, agent)
  options = Marshal.load(Marshal.dump(state.fetch(:trust_args)))
  options[:profile_ref] = S::PROFILE_REF
  options[:snapshot]["records"].each do |record|
    record["public_key_pem"] = provider if record["role"] == "Issuer"
    record["public_key_pem"] = agent if record["role"] == "Agent"
  end
  trust = M::InputBuilder.trust(**options)
  base = {trust: trust, order: state.fetch(:order), root_presentation: root, host_checkout_jws: state.fetch(:checkout)}
  saved = M::InputBuilder.prepare(**base, challenge_id: "independent-challenge", nonce: "test-nonce",
    issuer_id: "host", not_before: NOW - 10, not_after: NOW + 500)
  args = M::InputBuilder.inputs(**base, saved_challenge: M::InputBuilder.restore(saved_challenge: saved), terminal_jws: terminal,
    expected_challenge_issuer_id: "host", clock_source_id: "independent-test-clock", verified_at: NOW)
  M.verify_checkout(**args)
end

STDIN.each_line do |line|
  begin
    request = JSON.parse(line)
    a = request.fetch("arguments", {})
    result = case request.fetch("operation")
    when "fixture"
      reqs = a.fetch("requirements")
      checkout = a.fetch("checkout")
      model = MultiItemFixture.build(requirements: reqs, checkout: checkout)
      provider, agent, merchant = model.fetch(:keys)
      merchants = [checkout.fetch("merchant"), {"id" => "private-hidden-merchant", "name" => "Private alternate merchant"}]
      signer = ->(key) { M::CheckoutJWT.es256_signer(private_key: key) }
      full = S.issue_open(allowed_merchants: merchants, requirements: reqs, candidate_policy: :independent,
        agent_public_key_pem: agent.public_to_pem, issued_at: NOW-100, expires_at: NOW+600,
        signer: signer.call(provider), public_key_pem: provider.public_to_pem).root_presentation
      reduced = S.select(open_sd_jwt: full, merchant_index: 0, item_indices: a.fetch("selection")).root_presentation
      jwt = model.fetch(:args).fetch(:host_checkout_jws)
      issue = {root_presentation: reduced, checkout_jwt: jwt, trusted_issuer_public_key_pem: provider.public_to_pem,
        agent_public_key_pem: agent.public_to_pem, trusted_merchant_public_key_pem: merchant.public_to_pem,
        expected_merchant_id: "shop", audience: "host", nonce: "test-nonce", verified_at: NOW, signer: signer.call(agent)}
      closed = S.issue_closed(**issue)
      state = {trust_args: model.fetch(:trust_args), order: model.fetch(:args).fetch(:order), checkout: jwt, issue: issue}
      check = verified(state, reduced, closed.terminal_jws, provider.public_to_pem, agent.public_to_pem)
      raise "fixture verification" unless check.success?
      receipts = %w[Success Error].map do |outcome|
        fields = outcome == "Success" ? {order_id: "order"} : {error: "declined", error_description: "Synthetic decline"}
        receipt = M::CheckoutReceipt.sign(closed_sd_jwt: closed.closed_sd_jwt, profile_ref: S::PROFILE_REF,
          issuer: "shop", outcome: outcome, issued_at: NOW, signer: signer.call(merchant), public_key_pem: merchant.public_to_pem, **fields)
        {jwt: receipt.jwt, outcome: outcome, key: merchant.public_to_pem}
      end
      {full: full, selected: reduced, closed: closed.closed_sd_jwt, checkout_jwt: jwt, checkout: checkout,
        requirements: reqs, merchants: merchants, selection: a.fetch("selection"), provider: provider.public_to_pem,
        agent: agent.public_to_pem, merchant: merchant.public_to_pem, receipts: receipts, inspection: check.inspect,
        runtime: {ruby: RUBY_VERSION, platform: RUBY_PLATFORM, gem_version: Gem.loaded_specs["ap2_mandate_verifier"]&.version&.to_s}}
    when "verify_external"
      check = verified(state, a.fetch("open"), a.fetch("closed").delete_suffix("~"), a.fetch("provider"), a.fetch("agent"))
      {verified: check.success?, code: check.code, inspection: check.inspect}
    when "reclose"
      closed = S.issue_closed(**state.fetch(:issue).merge(root_presentation: a.fetch("open")))
      {closed: closed.closed_sd_jwt}
    when "verify_receipt"
      check = M::CheckoutReceipt.verify(jwt: a.fetch("jwt"), closed_sd_jwt: a.fetch("closed"), profile_ref: S::PROFILE_REF,
        trusted_public_key_pem: a.fetch("key"), expected_issuer: "shop", not_before: NOW-1, not_after: NOW+1, verified_at: NOW)
      {verified: check.verified?, outcome: check.outcome}
    else raise "unsupported operation"
    end
    puts JSON.generate(result)
  rescue StandardError => error
    warn "#{error.class}: #{error.backtrace.first(4).join("\n")}" if ENV["AP2_INTEROP_DEBUG"] == "1"
    puts JSON.generate(rejected: true)
  end
end
