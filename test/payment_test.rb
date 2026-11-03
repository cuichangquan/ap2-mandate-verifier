# frozen_string_literal: true
require_relative "runtime_dependencies"
if ENV["AP2_INSTALLED"] == "1"
  require "ap2_mandate_verifier"
else
  $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
  require_relative "../lib/ap2_mandate_verifier"
end
require_relative "../examples/conditional_checkout"
module PaymentTest
  M = AP2MandateVerifier
  P = M::Payment
  R = M::PaymentReceipt
  NOW = 1_800_000_000
  @count = 0
  def self.assert(value, label)
    @count += 1
    raise "payment: #{label}" unless value
  end
  def self.invalid
    yield
    raise "payment accepted invalid issuance"
  rescue P::Invalid, R::Invalid => e
    assert(e.cause.nil? && !e.message.include?("secret"), "redacted")
  end
  def self.sign_claims(claims, key, typ)
    JWT.encode(claims, key, "ES256", {"typ" => typ}) + "~"
  end
  def self.payload(wire)
    jwt, disclosure = wire.split("~", -1)
    claims = JWT.decode(jwt, nil, false).first
    unless disclosure.empty?
      content = JSON.parse(Base64.urlsafe_decode64(disclosure))
      claims = claims.merge("delegate_payload" => [content[1]])
    end
    claims
  end
  state = ConditionalCheckoutExample.run
  provider, agent, merchant = state.fetch(:keys)
  signer = ->(key) { M::CheckoutJWT.es256_signer(private_key: key) }
  checkout = state.fetch(:closed).checkout_jwt
  details = P.details(checkout_jwt: checkout, trusted_merchant_public_key_pem: merchant.public_to_pem,
    expected_merchant_id: "shop", payment_instrument: {"id" => "synthetic-card", "type" => "card"})
  assert(details.frozen? && details["payment_amount"].frozen?, "immutable details")
  assert(details["transaction_id"] == Base64.urlsafe_encode64(Digest::SHA256.digest(checkout), padding: false), "independent transaction hash")
  direct_checkout = M::Buyer.issue_closed(checkout_jwt: checkout, approved_checkout_jwt: checkout,
    trusted_merchant_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop",
    issued_at: NOW, expires_at: NOW + 60, signer: signer.call(provider), public_key_pem: provider.public_to_pem)
  direct_inputs = {closed_sd_jwt: direct_checkout.closed_sd_jwt, trusted_provider_public_key_pem: provider.public_to_pem,
    trusted_merchant_public_key_pem: merchant.public_to_pem, expected_checkout_jwt: checkout,
    expected_merchant_id: "shop", verified_at: NOW}
  issued = P.issue_direct(payment: details, approved_payment: details, issued_at: NOW, expires_at: NOW + 60,
    signer: signer.call(provider), public_key_pem: provider.public_to_pem)
  direct_args = {closed_sd_jwt: issued.closed_sd_jwt, checkout_mode: :direct, checkout_inputs: direct_inputs,
    expected_payment: details, trusted_provider_public_key_pem: provider.public_to_pem, verified_at: NOW}
  assert(P.verify(**direct_args).verified?, "direct public lifecycle")
  assert(P.present(closed_sd_jwt: issued.closed_sd_jwt).closed_sd_jwt == issued.closed_sd_jwt, "restore direct")
  wrong = OpenSSL::PKey::EC.generate("prime256v1")
  [direct_args.merge(trusted_provider_public_key_pem: wrong.public_to_pem),
   direct_args.merge(checkout_inputs: direct_inputs.merge(trusted_merchant_public_key_pem: wrong.public_to_pem)),
   direct_args.merge(checkout_inputs: direct_inputs.merge(expected_checkout_jwt: "secret")),
   direct_args.merge(verified_at: NOW + 60, checkout_inputs: direct_inputs.merge(verified_at: NOW + 60)),
   direct_args.merge(verified_at: NOW - 1, checkout_inputs: direct_inputs.merge(verified_at: NOW - 1)),
   direct_args.merge(closed_sd_jwt: "x" * 32_770), direct_args.merge(unknown: true),
   direct_args.merge(open_sd_jwt: issued.closed_sd_jwt)].each { |args| assert(!P.verify(**args).verified?, "direct rejects") }
  invalid { P.issue_direct(payment: details, approved_payment: details.merge("payment_instrument" => {"id" => "other", "type" => "card"}),
    issued_at: NOW, expires_at: NOW+60, signer: signer.call(provider), public_key_pem: provider.public_to_pem) }
  # Correct signatures over wrong details must reach and fail business checks.
  original = payload(issued.closed_sd_jwt)
  bad_payments = [details.merge("transaction_id" => "A" * 43),
    details.merge("payee" => {"id" => "other", "name" => "Office supplies"}),
    details.merge("payment_amount" => {"amount" => 301, "currency" => "USD"}),
    details.merge("payment_amount" => {"amount" => 300, "currency" => "EUR"}),
    details.merge("payment_instrument" => {"id" => "other", "type" => "card"})]
  bad_payments.each do |value|
    claims = original.merge("delegate_payload" => [original["delegate_payload"][0].merge(value)])
    wire = sign_claims(claims, provider, "example+sd-jwt")
    assert(!P.verify(**direct_args.merge(closed_sd_jwt: wire)).verified?, "signed direct business mismatch")
  end
  bad_shapes = [original.merge("unknown" => true), original.merge("_sd_alg" => "sha-512")]
  closed_content = original.fetch("delegate_payload").first
  [closed_content.merge("vct" => "mandate.payment"), closed_content.merge("risk_data" => {}),
   closed_content.merge("iat" => NOW.to_f), closed_content.merge("exp" => NOW),
   closed_content.merge("payment_amount" => {"amount" => 300.0, "currency" => "USD"}),
   closed_content.merge("payment_amount" => {"amount" => true, "currency" => "USD"}),
   closed_content.merge("payment_amount" => {"amount" => -1, "currency" => "USD"}),
   closed_content.merge("payment_amount" => {"amount" => 9_007_199_254_740_992, "currency" => "USD"})].each do |v|
    bad_shapes << original.merge("delegate_payload" => [v])
  end
  bad_shapes.each do |v|
    assert(!P.verify(**direct_args.merge(closed_sd_jwt: sign_claims(v, provider, "example+sd-jwt"))).verified?, "signed unsupported closed shape")
  end
  wire = issued.closed_sd_jwt
  [wire.chomp("~"), wire + "extra~", wire.sub("~", "~~"), wire.sub(/~[^~]+~\z/, "~e30~")].each do |v|
    assert(!P.verify(**direct_args.merge(closed_sd_jwt: v)).verified?, "disclosure wire rejection")
  end
  attacker = sign_claims(original, wrong, "example+sd-jwt")
  [nil, false].each { |v| assert(!P.verify(**direct_args.merge(closed_sd_jwt: attacker, trusted_provider_public_key_pem: v)).verified?, "attacker root never bypasses missing trust") }
  conditions = [{"type" => "payment.amount_range", "currency" => "USD", "min" => 100, "max" => 300},
    {"type" => "payment.allowed_payees", "allowed" => [details["payee"]]},
    {"type" => "payment.allowed_payment_instruments", "allowed" => [details["payment_instrument"]]}]
  open_args = {open_checkout_sd_jwt: state.fetch(:opening).root_presentation, constraints: conditions,
    fixed: {"payment_instrument" => details["payment_instrument"]}, agent_public_key_pem: agent.public_to_pem,
    issued_at: NOW, expires_at: NOW + 60, signer: signer.call(provider), public_key_pem: provider.public_to_pem}
  opening = P.issue_open(**open_args)
  close_args = {open_sd_jwt: opening, payment: details, trusted_provider_public_key_pem: provider.public_to_pem,
    agent_public_key_pem: agent.public_to_pem, audience: "credential-provider", nonce: "payment-nonce",
    verified_at: NOW, signer: signer.call(agent)}
  closed = P.issue_closed(**close_args)
  raw = M::InputBuilder.inputs(**state.fetch(:host_inputs), saved_challenge: state.fetch(:saved),
    terminal_jws: state.fetch(:closed).terminal_jws, expected_challenge_issuer_id: "host",
    clock_source_id: "synthetic-clock", verified_at: NOW)
  args = {closed_sd_jwt: closed.closed_sd_jwt, open_sd_jwt: opening, checkout_mode: :conditional,
    checkout_inputs: raw, expected_payment: details, trusted_provider_public_key_pem: provider.public_to_pem,
    expected_agent_public_key_pem: agent.public_to_pem, expected_audience: "credential-provider",
    expected_nonce: "payment-nonce", verified_at: NOW}
  assert(P.verify(**args).verified?, "conditional public lifecycle")
  [nil, false].each do |missing|
    assert(!P.verify(**direct_args.merge(trusted_provider_public_key_pem: missing)).verified?, "missing direct trust key")
    assert(!P.verify(**args.merge(trusted_provider_public_key_pem: missing)).verified?, "missing conditional trust key")
    invalid { P.issue_closed(**close_args.merge(trusted_provider_public_key_pem: missing)) }
  end
  mutable = raw.dup
  original_verify = M.method(:verify_checkout)
  M.define_singleton_method(:verify_checkout) do |**inputs|
    result = original_verify.call(**inputs)
    mutable[:host_checkout_jws] = "secret"
    mutable[:root_presentation] = "secret"
    result
  end
  begin
    assert(P.verify(**args.merge(checkout_inputs: mutable)).verified?, "snapshot survives caller hash mutation after nested verification")
  ensure
    M.define_singleton_method(:verify_checkout, original_verify)
  end
  assert(P.present(closed_sd_jwt: closed.closed_sd_jwt, open_sd_jwt: opening).chain == closed.chain, "restore chain")
  terminal = payload(closed.closed_sd_jwt)
  {expected_agent_public_key_pem: wrong.public_to_pem, expected_audience: "wrong", expected_nonce: "wrong",
   trusted_provider_public_key_pem: wrong.public_to_pem,
   checkout_inputs: raw.merge(host_checkout_jws: "secret")}.each do |k, v|
    assert(!P.verify(**args.merge(k => v)).verified?, "conditional #{k}")
  end
  bad_payments.each do |value|
    wire = sign_claims(terminal.merge("delegate_payload" => [terminal["delegate_payload"][0].merge(value)]), agent, "kb+sd-jwt")
    assert(!P.verify(**args.merge(closed_sd_jwt: wire)).verified?, "signed conditional business mismatch")
  end
  # Re-sign both hops after mutating Open policy; isolate each constraint/fixed-field check.
  mutate_open = lambda do |content|
    new_open = sign_claims({"delegate_payload" => [content], "_sd_alg" => "sha-256"}, provider, "example+sd-jwt")
    bound = terminal.merge("sd_hash" => Base64.urlsafe_encode64(Digest::SHA256.digest(new_open), padding: false))
    [new_open, sign_claims(bound, agent, "kb+sd-jwt")]
  end
  content = payload(opening)["delegate_payload"][0]
  changes = [content.merge("payment_amount" => {"amount" => 301, "currency" => "USD"}),
    content.merge("payee" => details["payee"].merge("name" => "Other")),
    content.merge("payment_instrument" => {"id" => "other", "type" => "card"})]
  %w[payment.amount_range payment.allowed_payees payment.allowed_payment_instruments payment.reference].each do |type|
    copy = Marshal.load(Marshal.dump(content))
    c = copy["constraints"].find { |v| v["type"] == type }
    case type
    when "payment.amount_range" then c["max"] = 299
    when "payment.allowed_payees" then c["allowed"][0]["id"] = "other"
    when "payment.allowed_payment_instruments" then c["allowed"][0]["id"] = "other"
    when "payment.reference" then c["conditional_transaction_id"] = "A" * 43
    end
    changes << copy
  end
  changes.each do |value|
    new_open, new_closed = mutate_open.call(value)
    assert(!P.verify(**args.merge(open_sd_jwt: new_open, closed_sd_jwt: new_closed)).verified?, "signed policy rejection")
  end
  [{"iat" => NOW+1}, {"iat" => NOW-301}, {"sd_hash" => "A"*43}, {"aud" => "wrong"},
   {"nonce" => "wrong"}, {"_sd_alg" => "sha-512"}].each do |change|
    forged = sign_claims(terminal.merge(change), agent, "kb+sd-jwt")
    assert(!P.verify(**args.merge(closed_sd_jwt: forged)).verified?, "signed Agent time/binding check")
  end
  [content.merge("constraints" => content["constraints"] + [{"type" => "payment.budget", "currency" => "USD", "max" => 500}]),
   content.merge("risk_data" => {}), content.merge("pisp" => {}), content.merge("execution_date" => "2026-01-01"),
   content.merge("cnf" => {"jwk" => M::RootSignature.public_jwk!(wrong.public_to_pem)})].each do |value|
    new_open, new_closed = mutate_open.call(value)
    assert(!P.verify(**args.merge(open_sd_jwt: new_open, closed_sd_jwt: new_closed)).verified?, "signed unsupported form")
  end
  invalid { P.issue_open(**open_args.merge(constraints: [])) }
  oversized = Marshal.load(Marshal.dump(conditions))
  oversized[1]["allowed"] = Array.new(8) { |i| {"id" => i.to_s + "i"*511, "name" => "n"*512, "website" => "w"*512} }
  oversized[2]["allowed"] = Array.new(8) { |i| {"id" => i.to_s + "i"*511, "type" => "t"*512, "description" => "d"*512} }
  called = false
  invalid { P.issue_open(**open_args.merge(constraints: oversized, signer: ->(_) { called = true; raise "secret" })) }
  assert(!called, "oversize rejection occurs before signer side effects")
  invalid { P.issue_open(**open_args.merge(fixed: {"unknown" => "secret"})) }
  invalid { P.issue_closed(**close_args.merge(agent_public_key_pem: wrong.public_to_pem, signer: signer.call(wrong))) }
  receipts = []
  [issued, closed].each do |presentation|
    ref = Base64.urlsafe_encode64(Digest::SHA256.digest(presentation.closed_sd_jwt), padding: false)
    assert(R.reference(closed_sd_jwt: presentation.closed_sd_jwt) == ref, "independent final-only receipt hash")
    %w[Success Error].each do |outcome|
      result_fields = outcome == "Success" ? {psp_confirmation_id: "psp-1", network_confirmation_id: "network-1"} :
        {error: "declined", error_description: "Synthetic rejection"}
      receipt = R.sign(closed_sd_jwt: presentation.closed_sd_jwt, issuer: "processor", outcome: outcome,
        payment_id: "payment-1", issued_at: NOW, signer: signer.call(merchant), public_key_pem: merchant.public_to_pem, **result_fields)
      rargs = {jwt: receipt.jwt, closed_sd_jwt: presentation.closed_sd_jwt, trusted_public_key_pem: merchant.public_to_pem,
        expected_issuer: "processor", expected_payment_id: "payment-1", not_before: NOW, not_after: NOW + 60, verified_at: NOW}
      checked = R.verify(**rargs)
      receipts << rargs
      assert(checked.verified? && checked.payment_succeeded? == (outcome == "Success") && checked.payment_rejected? == (outcome == "Error"), "receipt outcome #{outcome}")
      {expected_issuer: "other", expected_payment_id: "other", trusted_public_key_pem: wrong.public_to_pem,
       verified_at: NOW - 1, closed_sd_jwt: presentation.closed_sd_jwt + "~", unknown: true}.each do |k, v|
        r = R.verify(**rargs.merge(k => v))
        assert(!r.verified? && !r.payment_succeeded? && !r.payment_rejected?, "receipt rejects #{k}")
      end
      bad_receipt = JWT.decode(receipt.jwt, nil, false).first.merge("reference" => "A" * 43)
      assert(!R.verify(**rargs.merge(jwt: JWT.encode(bad_receipt, merchant, "ES256", {"typ" => "JWT"}))).verified?, "signed wrong receipt reference")
    end
  end
  if ENV["PAYMENT_EXPORT"]
    File.write(ENV.fetch("PAYMENT_EXPORT"), JSON.generate(direct: direct_args, conditional: args,
      open_content: content, receipts: receipts))
  end
  puts "payment: #{@count} assertions passed"
end
