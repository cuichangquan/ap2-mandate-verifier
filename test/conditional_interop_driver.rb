# frozen_string_literal: true
# Test-only JSON lines transport; keys never leave process memory.
require_relative "runtime_dependencies"
if ENV["AP2_INSTALLED"] == "1"
  version = ENV.fetch("AP2_GEM_VERSION")
  gem "ap2_mandate_verifier", "= #{version}"
  require "ap2_mandate_verifier"
  spec = Gem.loaded_specs.fetch("ap2_mandate_verifier")
  installed_lib = File.realpath(File.join(spec.full_gem_path, "lib"))
  source_lib = File.realpath(File.join(__dir__, "../lib"))
  loaded_product = $LOADED_FEATURES.select { |path| path.match?(%r{/ap2_mandate_verifier(?:/|\.rb\z)}) }
  abort "installed Gem source overlay" unless spec.version.to_s == version && installed_lib != source_lib &&
    !loaded_product.empty? && loaded_product.all? { |path| File.realpath(path).start_with?(installed_lib + "/") }
else
  require_relative "../lib/ap2_mandate_verifier"
end
M = AP2MandateVerifier
provider, agent, merchant = Array.new(3) { OpenSSL::PKey::EC.generate("prime256v1") }
public_host = public_receipt_policy = verified_closed_wire = nil
STDOUT.sync = true
STDIN.each_line do |line|
  begin
    request = JSON.parse(line)
    args = request.fetch("arguments").transform_keys(&:to_sym)
    result = case request.fetch("operation")
    when "issue_open"
      issued = M::ConditionalCheckout.issue_open(**args, agent_public_key_pem: agent.public_to_pem,
        signer: M::CheckoutJWT.es256_signer(private_key: provider), public_key_pem: provider.public_to_pem)
      {root: issued.root_presentation, provider: provider.public_to_pem, agent: agent.public_to_pem}
    when "issue_closed"
      issued = M::ConditionalCheckout.issue_closed(**args, agent_public_key_pem: agent.public_to_pem,
        signer: M::CheckoutJWT.es256_signer(private_key: agent))
      {root: issued.root_presentation, terminal: issued.terminal_jws, closed: issued.closed_sd_jwt}
    when "verify"
      inputs = args.merge(profile_ref: M::ConditionalCheckout::PROFILE_REF)
      M::ScopedConstraints.check!(**inputs)
      {accepted: true}
    when "prepare_public_host"
      # Separate trusted Host records, never decoded from received JWT claims.
      trust_options = args.fetch(:trust).transform_keys(&:to_sym)
      trust = M::InputBuilder.trust(**trust_options)
      challenge = args.fetch(:challenge).transform_keys(&:to_sym)
      base = {trust: trust, order: args.fetch(:order), root_presentation: args.fetch(:root_presentation),
        host_checkout_jws: args.fetch(:host_checkout_jws)}
      saved = M::InputBuilder.prepare(**base, **challenge)
      public_host = base.merge(saved_challenge: M::InputBuilder.restore(saved_challenge: saved),
        expected_challenge_issuer_id: challenge.fetch(:issuer_id), clock_source_id: "independent-test-clock",
        verified_at: trust_options.fetch(:verified_at)).freeze
      merchant_record = trust_options.fetch(:snapshot).fetch("records").find { |record| record.fetch("role") == "Merchant" }
      public_receipt_policy = {profile_ref: M::ConditionalCheckout::PROFILE_REF,
        trusted_public_key_pem: merchant_record.fetch("public_key_pem"), expected_issuer: args.fetch(:order).fetch("merchant_id"),
        not_before: challenge.fetch(:not_before), not_after: challenge.fetch(:not_after),
        verified_at: trust_options.fetch(:verified_at)}.freeze
      verified_closed_wire = nil
      {prepared: true}
    when "verify_public"
      raise "Host context not prepared" unless public_host
      checked = M::InputBuilder.verify(**public_host, terminal_jws: args.fetch(:terminal_jws))
      evidence = checked.evidence
      # A protected test record of verified bytes, not purchase authorization.
      verified_closed_wire = (args.fetch(:terminal_jws) + "~").freeze if checked.success?
      {success: checked.success?, status: checked.status, code: checked.code, evidence: evidence&.to_h,
        evidence_frozen: !evidence.nil? && evidence.frozen? && evidence.to_h.frozen?}
    when "verify_public_receipt"
      raise "verified presentation not recorded" unless verified_closed_wire && public_receipt_policy
      checked = M::CheckoutReceipt.verify(jwt: args.fetch(:jwt), closed_sd_jwt: verified_closed_wire, **public_receipt_policy)
      {verified: checked.verified?, outcome: checked.outcome, purchase_succeeded: checked.purchase_succeeded?,
        purchase_rejected: checked.purchase_rejected?}
    when "receipt"
      signed = M::CheckoutReceipt.sign(**args, profile_ref: M::ConditionalCheckout::PROFILE_REF,
        signer: M::CheckoutJWT.es256_signer(private_key: merchant), public_key_pem: merchant.public_to_pem)
      {jwt: signed.jwt, reference: signed.reference, key: merchant.public_to_pem}
    when "verify_receipt"
      {verified: M::CheckoutReceipt.verify(**args, profile_ref: M::ConditionalCheckout::PROFILE_REF).verified?}
    else raise "unsupported"
    end
    puts JSON.generate(result)
  rescue M::RootSignature::Rejected => error
    puts JSON.generate(rejected: true, code: error.code)
  rescue StandardError
    puts JSON.generate(rejected: true)
  end
end
