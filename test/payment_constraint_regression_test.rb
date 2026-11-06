# frozen_string_literal: true
require_relative "runtime_dependencies"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__)) unless ENV["AP2_INSTALLED"] == "1"
require "ap2_mandate_verifier"
require "stringio"
require_relative "../examples/conditional_checkout"
require_relative "../examples/long_payment"

# Independent attack construction: no SDK issuer/parser is used to validate,
# decode, mutate, hash or re-sign the malicious original wire.
module PaymentConstraintRegressionTest
  M = AP2MandateVerifier
  P = M::Payment
  S = M::SelectivePayment
  Q = M::PaymentPolicy
  R = M::RecurringPayment
  L = M::LongPayment
  NOW = ConditionalCheckoutExample::NOW
  SECRET = "SECRET-395-private-input"
  @checks = 0
  def self.assert(value, label)
    @checks += 1
    raise "constraint regression: #{label}" unless value
  end
  def self.copy(value) = Marshal.load(Marshal.dump(value))
  def self.decode(value) = JSON.parse(Base64.urlsafe_decode64(value))
  def self.encode(value) = Base64.urlsafe_encode64(JSON.generate(value), padding: false)
  def self.digest(value) = Base64.urlsafe_encode64(Digest::SHA256.digest(value), padding: false)
  def self.sign(key) = M::CheckoutJWT.es256_signer(private_key: key)
  def self.content(wire)
    parts = wire.split("~", -1)
    outer = decode(parts[0].split(".")[1])
    index = parts.index { |d| digest(d) == outer.fetch("delegate_payload")[0].fetch("...") }
    [parts, outer, index, decode(parts.fetch(index))]
  end
  def self.attack(wire, key)
    parts, outer, index, disclosure = content(wire)
    yield disclosure[1]
    parts[index] = encode(disclosure)
    outer["delegate_payload"][0]["..."] = digest(parts[index])
    parts[0] = JWT.encode(outer, key, "ES256", {"typ" => "example+sd-jwt"})
    # Independent signature and commitment oracle, separate from SDK verdict.
    checked = JWT.decode(parts[0], key, true, algorithms: ["ES256"]).first
    assert(checked["delegate_payload"][0]["..."] == digest(parts[index]), "signed original commitment")
    parts.join("~")
  end
  def self.rebind(closed, opening, key)
    claims = decode(closed.split(".")[1])
    claims["sd_hash"] = digest(opening)
    wire = JWT.encode(claims, key, "ES256", {"typ" => "kb+sd-jwt"})
    assert(JWT.decode(wire, key, true, algorithms: ["ES256"]).first["sd_hash"] == digest(opening), "genuine rebound Agent signature")
    wire + "~"
  end
  def self.invalid
    yield
    raise "malformed constraint accepted"
  rescue P::Invalid, S::Invalid, R::Invalid, L::Invalid
    error = $!
    assert(error.cause.nil? && !error.message.include?(SECRET) && !error.message.include?("eyJ"), "redacted exception")
  end
  class ReservationProbe
    attr_reader :calls, :starts
    def initialize
      @calls = 0
      @starts = 0
    end
    def reserve!(record:, **)
      @calls += 1
      @record = record.merge("processor_key" => "synthetic-probe")
      :reached_reservation
    end
    def ticket_record!(**) = @record
    def start!(**)
      @starts += 1
      @record
    end
    alias start_long! start!
  end
  def self.fixture(profile, selective, state)
    provider, agent, merchant = state.fetch(:keys)
    policy = [Q::PROFILE_REF, Q::SELECTIVE_PROFILE_REF].include?(profile)
    recurring = [R::PROFILE_REF, R::SELECTIVE_PROFILE_REF].include?(profile)
    api = recurring ? R : (selective ? S : P)
    pisp = {"legal_name" => "Synthetic Provider", "brand_name" => "Synthetic", "domain_name" => "pay.example"}
    date = "2028-02-29T12:00:00Z"
    extra = policy ? {pisp: pisp, execution_date: date, profile_ref: Q::PROFILE_REF} : {}
    details = P.details(checkout_jwt: state[:closed].checkout_jwt, trusted_merchant_public_key_pem: merchant.public_to_pem,
      expected_merchant_id: "shop", payment_instrument: {"id" => "synthetic-card", "type" => "card"}, **extra)
    cs = [{"type" => "payment.amount_range", "currency" => "JPY", "max" => 300},
      {"type" => "payment.allowed_payees", "allowed" => [details["payee"]]},
      {"type" => "payment.allowed_payment_instruments", "allowed" => [details["payment_instrument"]]}]
    if selective
      cs[1]["allowed"] << {"id" => "private-shop", "name" => SECRET}
      cs[2]["allowed"] << {"id" => SECRET, "type" => "card"}
    end
    cs += [{"type" => "payment.allowed_pisps", "allowed" => [pisp]},
      {"type" => "payment.execution_date", "not_before" => date, "not_after" => date}] if policy
    cs += [{"type" => "payment.agent_recurrence", "frequency" => "ON_DEMAND", "max_occurrences" => 2},
      {"type" => "payment.budget", "currency" => "JPY", "max" => 600}] if recurring
    issue = {open_checkout_sd_jwt: state[:opening].root_presentation, constraints: cs, fixed: {},
      agent_public_key_pem: agent.public_to_pem, issued_at: NOW, expires_at: NOW + 60,
      signer: sign(provider), public_key_pem: provider.public_to_pem, profile_ref: profile}
    issue[:candidate_policy] = :independent if policy || recurring
    issue.merge!(selective: :both, approved_combinations: [[0, 0], [0, 1], [1, 0], [1, 1]]) if selective
    full = api.issue_open(**issue)
    opening = selective ? api.select(open_sd_jwt: full, payee_index: 0, instrument_index: 0, profile_ref: profile) : full
    if selective
      visible = opening.split("~")[1..].map { |d| decode(d) }
      assert(opening != full && opening.count("~") == full.count("~") - 2 && !JSON.generate(visible).include?(SECRET), "actual withheld candidate disclosures")
    end
    close = {payment: details, trusted_provider_public_key_pem: provider.public_to_pem,
      agent_public_key_pem: agent.public_to_pem, audience: "processor", nonce: "constraint-395",
      verified_at: NOW, signer: sign(agent), profile_ref: profile}
    open_key = selective ? :open_presentation : :open_sd_jwt
    closed = api.issue_closed(**close, open_key => opening).closed_sd_jwt
    inputs = M::InputBuilder.inputs(**state[:host_inputs], saved_challenge: state[:saved], terminal_jws: state[:closed].terminal_jws,
      expected_challenge_issuer_id: "host", clock_source_id: "synthetic-clock", verified_at: NOW)
    args = {open_key => opening, closed_sd_jwt: closed, checkout_inputs: inputs, expected_payment: details,
      trusted_provider_public_key_pem: provider.public_to_pem, expected_agent_public_key_pem: agent.public_to_pem,
      expected_audience: "processor", expected_nonce: "constraint-395", verified_at: NOW, profile_ref: profile}
    args[:checkout_mode] = :conditional unless selective
    args.merge!(trusted_pisp: pisp, execution_at: date) if policy
    {api: api, profile: profile, selective: selective, provider: provider, agent: agent, full: full,
      issue: issue, close: close, args: args, open_key: open_key, tenant: "tenant", order: "office-1"}
  end
  def self.exercise(f)
    api, profile, selective = f.values_at(:api, :profile, :selective)
    base_api = selective ? S : P
    args, open_key = f.values_at(:args, :open_key)
    assert(api.verify(**args).verified? && base_api.verify(**args).verified?, "positive #{profile}")
    resigned = attack(args.fetch(open_key), f[:provider]) { |_| }
    control = args.merge(open_key => resigned, closed_sd_jwt: rebind(args[:closed_sd_jwt], resigned, f[:agent]))
    assert(api.verify(**control).verified? && base_api.verify(**control).verified?, "no-op attack builder positive")
    assert(api.present(**control.slice(open_key, :closed_sd_jwt, :profile_ref)), "no-op presentation positive")
    assert(api.issue_closed(**f[:close], open_key => resigned), "no-op delegation positive")
    mode = selective ? :selective : :conditional
    scope = {tenant_id: f[:tenant], merchant_id: "shop", operation_id: "op", approval_id: "consent", occurrence_id: "one", order_id: f[:order]}
    probe = ReservationProbe.new
    service = M::PaymentAcceptance::Service.new(store: probe)
    assert(service.accept(**scope, mode: mode, verification_inputs: args) == :reached_reservation && probe.calls == 1, "positive reaches protected reservation")
    assert(service.start(ticket: :probe, verification_inputs: args) && probe.starts == 1, "positive reaches protected start")
    malformed = [{"foo" => "bar"}, {"type" => "payment.unknown"}, {}, {"type" => "payment.execution_date"},
      {"type" => "payment.execution_date", "unexpected" => true}, {"foo" => SECRET},
      {"type" => nil}, {"type" => ["payment.amount_range"]}, {"type" => "payment.amount_range", "currency" => "JPY"}]
    changes = malformed.flat_map do |bad|
      [->(o) { o["constraints"] << copy(bad) }, ->(o) { o["constraints"][0] = copy(bad) }]
    end
    # Keep every required constraint, but poison each one's exact field grammar.
    original = content(f[:full])[3][1]["constraints"]
    original.each_index do |index|
      changes << ->(o) { o["constraints"][index]["unexpected"] = SECRET }
      changes << ->(o) { o["constraints"][index].delete("type") }
      changes << ->(o) { o["constraints"][index] = {"type" => o["constraints"][index]["type"]} }
    end
    changes += [->(o) { o["constraints"] = [] }, ->(o) { o.delete("constraints") },
      ->(o) { o["constraints"] = {"foo" => SECRET} }, ->(o) { o["constraints"] << copy(o["constraints"][0]) },
      ->(o) { o["constraints"][0]["_sd"] = ["A" * 43] }]
    changes.each do |change|
      # Issuance rejects before invoking the caller's signer.
      opening_value = {"constraints" => copy(f[:issue][:constraints]) + [copy(original.find { |c| c["type"] == "payment.reference" })]}
      change.call(opening_value)
      cs = opening_value["constraints"]
      reference = original.find { |c| c["type"] == "payment.reference" }
      # The helper adds the genuine reference. Keep a poisoned reference so
      # even attacks on its generated fields cannot be silently discarded.
      cs = cs.reject { |c| c == reference } if cs.instance_of?(Array)
      calls = 0
      invalid { api.issue_open(**f[:issue].merge(constraints: cs, signer: ->(_) { calls += 1; raise SECRET })) }
      assert(calls == 0, "invalid issuance has no signer side effect")
      malicious = attack(args.fetch(open_key), f[:provider], &change)
      bad_args = args.merge(open_key => malicious, closed_sd_jwt: rebind(args[:closed_sd_jwt], malicious, f[:agent]))
      [api, base_api].uniq.each do |verifier|
        result = verifier.verify(**bad_args)
        assert(!result.verified? && result.code == :payment_verification_failed &&
          [result.payment, result.reference, result.expires_at].all?(&:nil?) && !result.inspect.include?(SECRET), "redacted public verification")
      end
      invalid { api.issue_closed(**f[:close], open_key => malicious) }
      invalid { api.present(**bad_args.slice(open_key, :closed_sd_jwt, :profile_ref)) }
      invalid { api.select(open_sd_jwt: attack(f[:full], f[:provider], &change), payee_index: 0, instrument_index: 0, profile_ref: profile) } if selective
      if [R::PROFILE_REF, R::SELECTIVE_PROFILE_REF, L::PROFILE_REF].include?(profile)
        invalid { api.approved_open!(open_sd_jwt: attack(f[:full], f[:provider], &change), profile_ref: profile,
          trusted_provider_public_key_pem: f[:provider].public_to_pem, expected_agent_public_key_pem: f[:agent].public_to_pem, verified_at: args[:verified_at]) }
      end
      if profile == L::PROFILE_REF
        inputs = args[:checkout_inputs]
        invalid { L.approved_pair!(payment_open: malicious, checkout_open: inputs[:root_presentation],
          trust_json: inputs[:trust_json], selection_json: inputs[:selection_json], merchant_id: "shop", verified_at: args[:verified_at]) }
      end
      rejected = service.accept(**scope, mode: mode, verification_inputs: bad_args)
      assert(rejected.status == :rejected && rejected.ticket.nil? && rejected.signed_wires.nil? &&
        rejected.closed_sd_jwt.nil? && probe.calls == 1, "no reservation or sensitive rejection projection")
      assert(service.start(ticket: :probe, verification_inputs: bad_args).nil? && probe.starts == 1, "invalid raw wire cannot reach protected start")
    end
    assert(api.verify(**args).verified?, "positive remains accepted after attacks")
    puts "#{profile}: #{changes.size} signed constraint attacks rejected"
  end

  def self.direct(state, profile)
    f = fixture(profile, false, state)
    provider, _, merchant = state[:keys]
    checkout = state[:closed].checkout_jwt
    consent = M::Buyer.issue_closed(checkout_jwt: checkout, approved_checkout_jwt: checkout,
      trusted_merchant_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop", issued_at: NOW,
      expires_at: NOW + 60, signer: sign(provider), public_key_pem: provider.public_to_pem)
    issue = {payment: f[:args][:expected_payment], approved_payment: f[:args][:expected_payment], issued_at: NOW,
      expires_at: NOW + 60, signer: sign(provider), public_key_pem: provider.public_to_pem, profile_ref: profile}
    closed = P.issue_direct(**issue).closed_sd_jwt
    args = f[:args].reject { |k, _| %i[open_sd_jwt expected_agent_public_key_pem expected_audience expected_nonce].include?(k) }.merge(
      closed_sd_jwt: closed, checkout_mode: :direct, checkout_inputs: {closed_sd_jwt: consent.closed_sd_jwt,
        trusted_provider_public_key_pem: provider.public_to_pem, trusted_merchant_public_key_pem: merchant.public_to_pem,
        expected_checkout_jwt: checkout, expected_merchant_id: "shop", verified_at: NOW})
    assert(P.verify(**args).verified?, "Direct positive #{profile}")
    probe = ReservationProbe.new
    service = M::PaymentAcceptance::Service.new(store: probe)
    scope = {tenant_id: "tenant", merchant_id: "shop", operation_id: "op", approval_id: "consent", occurrence_id: "one", order_id: "office-1"}
    assert(service.accept(**scope, mode: :direct, verification_inputs: args) == :reached_reservation, "Direct reservation positive")
    [{"foo" => "bar"}, {"type" => "payment.unknown"}, {}, {"type" => "payment.execution_date"},
     {"type" => "payment.execution_date", "unexpected" => true}, {"foo" => SECRET}].each do |bad|
      # Direct Closed has no constraints grammar: injected Open conditions must
      # not be accepted as ignored fields in an otherwise genuine mandate.
      malicious = attack(closed, provider) { |o| o["constraints"] = [bad] }
      result = P.verify(**args.merge(closed_sd_jwt: malicious))
      assert(!result.verified? && result.payment.nil? && result.reference.nil? && result.expires_at.nil?, "Direct signed injection rejected")
      invalid { P.present(closed_sd_jwt: malicious, profile_ref: profile) }
      invalid { P.reference(closed_sd_jwt: malicious, profile_ref: profile) }
      calls = 0
      injected = issue[:payment].merge("constraints" => [bad])
      invalid { P.issue_direct(**issue.merge(payment: injected, approved_payment: injected, signer: ->(_) { calls += 1; raise SECRET })) }
      assert(calls == 0, "Direct injection rejected before signer")
      rejected = service.accept(**scope, mode: :direct, verification_inputs: args.merge(closed_sd_jwt: malicious))
      assert(rejected.status == :rejected && rejected.ticket.nil? && probe.calls == 1, "Direct no reservation")
    end
  end

  old = $stdout
  begin
    $stdout = StringIO.new
    state = ConditionalCheckoutExample.run(currency: "JPY")
  ensure
    $stdout = old
  end
  [[P::PROFILE_REF, false], [S::PROFILE_REF, true], [Q::PROFILE_REF, false], [Q::SELECTIVE_PROFILE_REF, true],
   [R::PROFILE_REF, false], [R::SELECTIVE_PROFILE_REF, true]].each { |profile, selective| exercise(fixture(profile, selective, state)) }
  [P::PROFILE_REF, Q::PROFILE_REF].each { |profile| direct(state, profile) }
  long = LongPaymentExample::Fixture.new
  month = long.month("2028-01")
  opening = content(long.payment_open)[3][1]
  exercise(api: L, profile: L::PROFILE_REF, selective: false, provider: long.provider, agent: long.agent,
    full: long.payment_open, args: month[:verify_inputs], open_key: :open_sd_jwt, tenant: "long-tenant", order: "long-2028-01-40000",
    issue: {open_checkout_sd_jwt: long.checkout_open, constraints: opening["constraints"].reject { |c| c["type"] == "payment.reference" }, fixed: {},
      agent_public_key_pem: long.agent.public_to_pem, issued_at: LongPaymentExample::T0, expires_at: LongPaymentExample::EXP,
      signer: sign(long.provider), public_key_pem: long.provider.public_to_pem, candidate_policy: :independent},
    close: {payment: month[:expected_payment], trusted_provider_public_key_pem: long.provider.public_to_pem,
      agent_public_key_pem: long.agent.public_to_pem, audience: "payment-host", nonce: "payment-nonce-2028-01-40000",
      verified_at: month[:now], signer: sign(long.agent)})
  puts "payment constraint regression: #{@checks} assertions passed"
end
