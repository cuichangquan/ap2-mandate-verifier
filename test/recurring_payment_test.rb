# frozen_string_literal: true
require_relative "runtime_dependencies"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__)) unless ENV["AP2_INSTALLED"] == "1"
require "ap2_mandate_verifier"
require "stringio"
require_relative "../examples/conditional_checkout"

module RecurringPaymentTest
  M = AP2MandateVerifier
  R = M::RecurringPayment
  NOW = 1_800_000_000
  @count = 0
  def self.assert(value, label)
    @count += 1
    raise "recurring payment: #{label}" unless value
  end
  def self.invalid
    yield
    raise "recurring wire unexpectedly accepted"
  rescue R::Invalid, M::Payment::Invalid, M::SelectivePayment::Invalid, M::PaymentReceipt::Invalid => e
    assert(e.cause.nil? && !e.message.include?("SECRET"), "redacted invalid")
  end
  def self.copy(v) = Marshal.load(Marshal.dump(v))
  def self.encode(v) = Base64.urlsafe_encode64(JSON.generate(v), padding: false)
  def self.decode(v) = JSON.parse(Base64.urlsafe_decode64(v))
  def self.digest(v) = Base64.urlsafe_encode64(Digest::SHA256.digest(v), padding: false)
  def self.resign(wire, key)
    parts = wire.split("~", -1)
    outer = decode(parts[0].split(".")[1])
    i = parts.index { |d| digest(d) == outer["delegate_payload"][0]["..."] }
    content = decode(parts[i])
    yield(content[1], outer)
    parts[i] = encode(content); outer["delegate_payload"][0]["..."] = digest(parts[i])
    parts[0] = JWT.encode(outer, key, "ES256", {"typ" => "example+sd-jwt"})
    parts.join("~")
  end
  previous = $stdout
  begin
    $stdout = StringIO.new
    state = ConditionalCheckoutExample.run(currency: "JPY")
  ensure
    $stdout = previous
  end
  provider, agent, merchant = state.fetch(:keys)
  sign = ->(key) { M::CheckoutJWT.es256_signer(private_key: key) }
  checkout = state.fetch(:closed).checkout_jwt
  detail_args = {checkout_jwt: checkout, trusted_merchant_public_key_pem: merchant.public_to_pem,
    expected_merchant_id: "shop", payment_instrument: {"id" => "chosen-card", "type" => "card"}}
  details = R.details(**detail_args)
  assert(details["payment_amount"] == {"currency" => "JPY", "amount" => 300}, "JPY exact integer details")
  cs = [{"type" => "payment.amount_range", "currency" => "JPY", "min" => 100, "max" => 500},
    {"type" => "payment.allowed_payees", "allowed" => [details["payee"], {"id" => "hidden", "name" => "SECRET-PAYEE"}]},
    {"type" => "payment.allowed_payment_instruments", "allowed" => [details["payment_instrument"], {"id" => "SECRET-CARD", "type" => "card"}]},
    {"type" => "payment.agent_recurrence", "frequency" => "ON_DEMAND", "max_occurrences" => 2},
    {"type" => "payment.budget", "max" => 600, "currency" => "JPY"}]
  base_issue = {open_checkout_sd_jwt: state.fetch(:opening).root_presentation, constraints: cs, fixed: {},
    agent_public_key_pem: agent.public_to_pem, issued_at: NOW, expires_at: NOW + 120,
    signer: sign.call(provider), public_key_pem: provider.public_to_pem, candidate_policy: :independent}
  base_closed = {payment: details, trusted_provider_public_key_pem: provider.public_to_pem,
    agent_public_key_pem: agent.public_to_pem, audience: "host", nonce: "nonce", verified_at: NOW, signer: sign.call(agent)}
  raw_checkout = M::InputBuilder.inputs(**state.fetch(:host_inputs), saved_challenge: state.fetch(:saved), terminal_jws: state.fetch(:closed).terminal_jws,
    expected_challenge_issuer_id: "host", clock_source_id: "clock", verified_at: NOW)
  roots = []
  [R::PROFILE_REF, R::SELECTIVE_PROFILE_REF].each do |profile|
    selective = profile == R::SELECTIVE_PROFILE_REF
    extra = selective ? {approved_combinations: [[0,0],[0,1],[1,0],[1,1]], selective: :both} : {}
    issue = base_issue.merge(extra).merge(profile_ref: profile)
    full = R.issue_open(**issue)
    presented = selective ? R.select(open_sd_jwt: full, payee_index: 0, instrument_index: 0, profile_ref: profile) : full
    helper = {profile_ref: profile, trusted_provider_public_key_pem: provider.public_to_pem,
      expected_agent_public_key_pem: agent.public_to_pem, verified_at: NOW}
    approved = R.approved_open!(open_sd_jwt: full, **helper)
    assert(approved.frozen? && approved[:opening].frozen? && approved[:opening]["constraints"].frozen?, "immutable protected enrollment")
    assert(approved.values_at(:max_occurrences, :budget_max, :currency) == [2,600,"JPY"], "signed limits projected")
    assert(approved[:root_wire] == full.split("~").first && approved[:reference] == digest(full.split("~").first), "quota reference original JWS only")
    assert(presented.split("~").first == full.split("~").first, "candidate selection preserves root quota identity")
    structural = R.send(:validated_open!, presented, profile_ref: profile, complete: false)
    assert(structural[:reference] == approved[:reference], "selected presentation cannot create another quota reference")
    invalid { R.approved_open!(open_sd_jwt: presented, **helper) } if selective
    open_key = selective ? :open_presentation : :open_sd_jwt
    closed = R.issue_closed(**base_closed, open_key => presented, profile_ref: profile)
    assert(decode(closed.closed_sd_jwt.split(".")[1])["ap2_profile"] == profile, "signed terminal marker")
    assert(R.present(**{open_key => presented, closed_sd_jwt: closed.closed_sd_jwt, profile_ref: profile}).closed_sd_jwt == closed.closed_sd_jwt, "exact restore")
    verify = {open_key => presented, closed_sd_jwt: closed.closed_sd_jwt, checkout_inputs: raw_checkout, expected_payment: details,
      trusted_provider_public_key_pem: provider.public_to_pem, expected_agent_public_key_pem: agent.public_to_pem,
      expected_audience: "host", expected_nonce: "nonce", verified_at: NOW, profile_ref: profile}
    verify[:checkout_mode] = :conditional unless selective
    assert(R.verify(**verify).verified?, "genuine JPY Checkout and recurring wire verification")
    assert(R.verify(**verify).verified?, "stateless wire verification makes no aggregate reservation claim")
    legacy = selective ? M::SelectivePayment : M::Payment
    assert(!legacy.verify(**verify.merge(profile_ref: legacy::PROFILE_REF)).verified?, "legacy profile rejects new signed wire")
    if selective
      visible = presented.split("~").map { |s| s.include?(".") ? decode(s.split(".")[1]) : decode(s) }.inspect
      assert(!visible.include?("SECRET") && visible.include?("ON_DEMAND") && visible.include?("payment.budget"), "only candidate leaves hidden; limits fully visible")
    end
    bad_inputs = [verify.merge(expected_nonce: "other"), verify.merge(verified_at: NOW + 120),
      verify.merge(checkout_inputs: raw_checkout.merge(host_checkout_jws: "invalid")), verify.merge(profile_ref: selective ? R::PROFILE_REF : R::SELECTIVE_PROFILE_REF)]
    bad_inputs.each { |v| assert(!R.verify(**v).verified?, "trust/time/chain/profile negative") }
    invalid { R.issue_open(**issue.merge(candidate_policy: nil)) }
    invalid { R.issue_closed(**base_closed.merge(payment: details.merge("payment_amount" => {"currency" => "USD", "amount" => 300})), open_key => presented, profile_ref: profile) }
    invalid { R.approved_open!(open_sd_jwt: full, **helper.merge(expected_agent_public_key_pem: merchant.public_to_pem)) }
    invalid { R.approved_open!(open_sd_jwt: full, **helper.merge(trusted_provider_public_key_pem: merchant.public_to_pem)) }
    invalid { R.approved_open!(open_sd_jwt: full, **helper.merge(verified_at: NOW + 120)) }
    mutations = [->(o,_) { o["constraints"].reject! { |c| c["type"] == "payment.agent_recurrence" } },
      ->(o,_) { o["constraints"].reject! { |c| c["type"] == "payment.budget" } },
      ->(o,_) { o["constraints"].find { |c| c["type"] == "payment.agent_recurrence" }["frequency"] = "DAILY" },
      ->(o,_) { o["constraints"].find { |c| c["type"] == "payment.agent_recurrence" }["max_occurrences"] = 2.0 },
      ->(o,_) { o["constraints"].find { |c| c["type"] == "payment.agent_recurrence" }["max_occurrences"] = 0 },
      ->(o,_) { o["constraints"].find { |c| c["type"] == "payment.agent_recurrence" }["max_occurrences"] = R::MAX_OCCURRENCES + 1 },
      ->(o,_) { o["constraints"].find { |c| c["type"] == "payment.budget" }["max"] = 600.0 },
      ->(o,_) { o["constraints"].find { |c| c["type"] == "payment.budget" }["max"] = 0 },
      ->(o,_) { o["constraints"].find { |c| c["type"] == "payment.budget" }["max"] = M::ScopedConstraints::MAX_AMOUNT + 1 },
      ->(o,_) { o["constraints"].find { |c| c["type"] == "payment.budget" }["currency"] = "USD" },
      ->(o,_) { o["constraints"][0]["currency"] = "USD" },
      ->(o,_) { o["constraints"][o["constraints"].index { |c| c["type"] == "payment.budget" }] = {"..." => digest("hidden-budget")} },
      ->(o,_) { o["constraints"][o["constraints"].index { |c| c["type"] == "payment.agent_recurrence" }] = {"..." => digest("hidden-recurrence")} },
      ->(o,_) { o["constraints"] << o["constraints"][-1] },
      ->(o,_) { o["constraints"].find { |c| c["type"] == "payment.budget" }["period"] = "month" },
      ->(_,outer) { outer["ap2_profile"] = legacy::PROFILE_REF }]
    mutations.each do |change|
      bad = resign(presented, provider, &change)
      invalid { R.issue_closed(**base_closed, open_key => bad, profile_ref: profile) }
      bad_full = resign(full, provider, &change)
      invalid { R.approved_open!(open_sd_jwt: bad_full, **helper) }
    end
    terminal = decode(closed.closed_sd_jwt.split(".")[1]); terminal["ap2_profile"] = legacy::PROFILE_REF
    wrong_terminal = JWT.encode(terminal, agent, "ES256", {"typ" => "kb+sd-jwt"}) + "~"
    assert(!R.verify(**verify.merge(closed_sd_jwt: wrong_terminal)).verified?, "signed terminal downgrade rejected")
    %w[Success Error].each do |outcome|
      fields = outcome == "Success" ? {psp_confirmation_id: "psp", network_confirmation_id: "network"} : {error: "declined", error_description: "Synthetic decision"}
      receipt = M::PaymentReceipt.sign(closed_sd_jwt: closed.closed_sd_jwt, profile_ref: profile, issuer: "shop", outcome: outcome,
        payment_id: "payment", issued_at: NOW, signer: sign.call(merchant), public_key_pem: merchant.public_to_pem, **fields)
      options = {jwt: receipt.jwt, closed_sd_jwt: closed.closed_sd_jwt, profile_ref: profile, trusted_public_key_pem: merchant.public_to_pem,
        expected_issuer: "shop", expected_payment_id: "payment", not_before: NOW, not_after: NOW + 60, verified_at: NOW}
      assert(M::PaymentReceipt.verify(**options).verified?, "Receipt #{outcome} original Closed")
      assert(!M::PaymentReceipt.verify(**options.merge(profile_ref: M::Payment::PROFILE_REF)).verified?, "Receipt old profile rejects")
    end
    roots << [issue, full, profile]
  end
  calls = 0
  effect = ->(_) { calls += 1; raise "unexpected signer" }
  issue = roots.first.first
  invalid { R.issue_open(**issue.merge(expires_at: NOW + 601, signer: effect)) }
  invalid { R.issue_open(**issue.merge(fixed: {"pisp" => {"legal_name" => "SECRET"}}, signer: effect)) }
  invalid { M::Payment.issue_direct(payment: details, approved_payment: details, issued_at: NOW, expires_at: NOW + 60,
    signer: effect, public_key_pem: provider.public_to_pem, profile_ref: R::PROFILE_REF) }
  assert(calls == 0, "unsupported semantics reject before signer")
  # Enrollment detaches all trusted byte inputs before the crypto callback.
  _, original_full, original_profile = roots.last
  mutable_wire = original_full.dup; mutable_profile = original_profile.dup
  mutable_agent = agent.public_to_pem.dup; mutable_provider = provider.public_to_pem.dup
  original_auth = M::RootSignature.method(:verified_payload!)
  M::RootSignature.define_singleton_method(:verified_payload!) do |source, key, **options|
    mutable_wire.replace("SECRET"); mutable_profile.replace("SECRET")
    mutable_agent.replace(merchant.public_to_pem); mutable_provider.replace(merchant.public_to_pem)
    original_auth.call(source, key, **options)
  end
  begin
    checked = R.approved_open!(open_sd_jwt: mutable_wire, profile_ref: mutable_profile,
      trusted_provider_public_key_pem: mutable_provider, expected_agent_public_key_pem: mutable_agent, verified_at: NOW)
    assert(checked[:reference] == digest(original_full.split("~").first), "enrollment uses detached original wire/profile/keys")
  ensure
    M::RootSignature.define_singleton_method(:verified_payload!, original_auth)
  end
  puts "recurring payment: #{@count} assertions passed"
end
