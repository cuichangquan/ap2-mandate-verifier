# frozen_string_literal: true
require_relative "runtime_dependencies"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__)) unless ENV["AP2_INSTALLED"] == "1"
require "ap2_mandate_verifier"
require "stringio"
require_relative "../examples/selective_checkout"

module PaymentPolicyTest
  M = AP2MandateVerifier
  P = M::Payment
  S = M::SelectivePayment
  Q = M::PaymentPolicy
  NOW = 1_800_000_000
  @count = 0
  def self.assert(value, label)
    @count += 1
    raise "payment policy: #{label}" unless value
  end
  def self.invalid
    yield
    raise "policy unexpectedly accepted"
  rescue P::Invalid, S::Invalid, M::PaymentReceipt::Invalid => e
    assert(e.cause.nil? && !e.message.include?("SECRET"), "redacted invalid")
  end
  def self.copy(v) = Marshal.load(Marshal.dump(v))
  def self.encode(v) = Base64.urlsafe_encode64(JSON.generate(v), padding: false)
  def self.decode(v) = JSON.parse(Base64.urlsafe_decode64(v))
  def self.hash(v) = Base64.urlsafe_encode64(Digest::SHA256.digest(v), padding: false)
  def self.signer(k) = M::CheckoutJWT.es256_signer(private_key: k)
  def self.resign_root(wire, key)
    parts = wire.split("~", -1)
    outer = decode(parts[0].split(".")[1])
    content_index = parts.index { |d| hash(d) == outer["delegate_payload"][0]["..."] }
    content = decode(parts[content_index])
    yield(content[1], outer)
    parts[content_index] = encode(content)
    outer["delegate_payload"][0]["..."] = hash(parts[content_index])
    parts[0] = JWT.encode(outer, key, "ES256", {"typ" => "example+sd-jwt"})
    parts.join("~")
  end
  previous = $stdout
  begin
    $stdout = StringIO.new
    state = SelectiveCheckoutExample.run
  ensure
    $stdout = previous
  end
  provider, agent, merchant = state.fetch(:keys)
  checkout = state.fetch(:closed).checkout_jwt
  pisp = {"legal_name" => "Registered Provider", "brand_name" => "Brand", "domain_name" => "pisp.example"}
  date = "2028-02-29T12:00:00.123456789Z"
  equivalent = "2028-02-29T13:00:00.123456789+01:00"
  detail_args = {checkout_jwt: checkout, trusted_merchant_public_key_pem: merchant.public_to_pem,
    expected_merchant_id: "shop", payment_instrument: {"id" => "card", "type" => "card"},
    pisp: pisp, execution_date: date, profile_ref: Q::PROFILE_REF}
  details = P.details(**detail_args)
  assert(details.keys.sort == (P::FIELDS + Q::FIELDS).sort && details["pisp"].frozen?, "six immutable details")
  assert(Q.instant!(date) == Q.instant!(equivalent), "offset equivalent exact fraction")
  assert(Q.instant!("2028-02-29T12:00:00.1Z") == Q.instant!("2028-02-29T12:00:00.100000000Z"), "fraction precision equivalence")
  assert(Q.instant!("2028-02-29T12:00:00Z") > Q.instant!("2028-02-29T12:00:00+01:00"), "numeric offset ordering")
  ["2027-02-29T00:00:00Z", "1900-02-29T00:00:00Z", "2028-04-31T00:00:00Z", "0000-01-01T00:00:00Z",
   "2028-01-01T24:00:00Z", "2028-01-01T00:60:00Z", "2028-01-01T00:00:60Z", "2028-01-01T00:00:00-00:00",
   "2028-01-01T00:00:00+24:00", "2028-01-01T00:00:00+00:60", "2028-01-01T00:00:00.1234567890Z",
   "2028-01-01", "2028-01-01T00:00:00", "2028-01-01t00:00:00z", "2028-01-01T00:00:00ZSECRET"].each do |bad|
    invalid { P.details(**detail_args.merge(execution_date: bad)) }
  end
  ["HTTPS://pisp.example", "pisp.example/path", "PISP.example", "pisp.example.", "*.pisp.example", "-pisp.example", "a..b", "a:443"].each do |bad|
    invalid { P.details(**detail_args.merge(pisp: pisp.merge("domain_name" => bad))) }
  end
  invalid { P.details(**detail_args.merge(profile_ref: P::PROFILE_REF)) }
  invalid { P.details(**detail_args.merge(profile_ref: Q::SELECTIVE_PROFILE_REF)) }
  direct_checkout = M::Buyer.issue_closed(checkout_jwt: checkout, approved_checkout_jwt: checkout,
    trusted_merchant_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop", issued_at: NOW,
    expires_at: NOW + 60, signer: signer(provider), public_key_pem: provider.public_to_pem)
  direct_inputs = {closed_sd_jwt: direct_checkout.closed_sd_jwt, trusted_provider_public_key_pem: provider.public_to_pem,
    trusted_merchant_public_key_pem: merchant.public_to_pem, expected_checkout_jwt: checkout, expected_merchant_id: "shop", verified_at: NOW}
  direct_issue = {payment: details, approved_payment: details, issued_at: NOW, expires_at: NOW + 60,
    signer: signer(provider), public_key_pem: provider.public_to_pem, profile_ref: Q::PROFILE_REF}
  direct = P.issue_direct(**direct_issue)
  direct_verify = {closed_sd_jwt: direct.closed_sd_jwt, checkout_mode: :direct, checkout_inputs: direct_inputs,
    expected_payment: details, trusted_provider_public_key_pem: provider.public_to_pem, verified_at: NOW,
    profile_ref: Q::PROFILE_REF, trusted_pisp: pisp, execution_at: equivalent}
  assert(P.verify(**direct_verify).verified?, "new direct with independent trusted plan")
  assert(P.present(closed_sd_jwt: direct.closed_sd_jwt, profile_ref: Q::PROFILE_REF).closed_sd_jwt == direct.closed_sd_jwt, "direct restore exact")
  [direct_verify.reject { |k,_| k == :trusted_pisp }, direct_verify.reject { |k,_| k == :execution_at },
   direct_verify.merge(execution_at: "2028-02-29T12:00:00.123456788Z"),
   direct_verify.merge(trusted_pisp: pisp.merge("legal_name" => "Other")),
   direct_verify.merge(profile_ref: P::PROFILE_REF), direct_verify.merge(profile_ref: Q::SELECTIVE_PROFILE_REF)].each do |a|
    assert(!P.verify(**a).verified?, "direct independent context/profile rejects")
  end
  invalid { P.issue_direct(**direct_issue.merge(approved_payment: details.merge("pisp" => pisp.merge("brand_name" => "Other")))) }
  invalid { P.issue_direct(**direct_issue.merge(profile_ref: P::PROFILE_REF)) }
  raw = M::InputBuilder.inputs(**state.fetch(:host_inputs), terminal_jws: state.fetch(:closed).terminal_jws,
    saved_challenge: state.fetch(:saved), expected_challenge_issuer_id: "host", clock_source_id: "clock", verified_at: NOW)
  base_cs = [{"type" => "payment.amount_range", "currency" => "USD", "max" => 300},
    {"type" => "payment.allowed_payees", "allowed" => [details["payee"], {"id" => "hidden", "name" => "SECRET-PAYEE"}]},
    {"type" => "payment.allowed_payment_instruments", "allowed" => [details["payment_instrument"], {"id" => "SECRET-CARD", "type" => "card"}]}]
  allowed = {"type" => "payment.allowed_pisps", "allowed" => [pisp]}
  window = {"type" => "payment.execution_date", "not_before" => equivalent, "not_after" => date}
  opening_args = {open_checkout_sd_jwt: state.fetch(:opening).root_presentation, checkout_profile_ref: M::SelectiveCheckout::PROFILE_REF,
    constraints: base_cs + [allowed, window], fixed: {"pisp" => pisp, "execution_date" => date},
    agent_public_key_pem: agent.public_to_pem, issued_at: NOW, expires_at: NOW + 60, signer: signer(provider),
    public_key_pem: provider.public_to_pem, candidate_policy: :independent}
  closing = {payment: details, trusted_provider_public_key_pem: provider.public_to_pem, agent_public_key_pem: agent.public_to_pem,
    audience: "host", nonce: "nonce", verified_at: NOW, signer: signer(agent)}
  results = []
  [P, S].each do |api|
    profile = api == P ? Q::PROFILE_REF : Q::SELECTIVE_PROFILE_REF
    extra = api == S ? {approved_combinations: [[0,0],[0,1],[1,0],[1,1]], selective: :both} : {}
    issue = opening_args.merge(extra).merge(profile_ref: profile)
    full = api.issue_open(**issue)
    root = api == S ? api.select(open_sd_jwt: full, payee_index: 0, instrument_index: 0, profile_ref: profile) : full
    open_key = api == S ? :open_presentation : :open_sd_jwt
    closed = api.issue_closed(**closing, open_key => root, profile_ref: profile)
    verify = {open_key => root, closed_sd_jwt: closed.closed_sd_jwt, checkout_inputs: raw, expected_payment: details,
      trusted_provider_public_key_pem: provider.public_to_pem, expected_agent_public_key_pem: agent.public_to_pem,
      expected_audience: "host", expected_nonce: "nonce", verified_at: NOW, profile_ref: profile, trusted_pisp: pisp, execution_at: equivalent}
    verify[:checkout_mode] = :conditional if api == P
    assert(api.verify(**verify).verified?, "#{api} inclusive zero-width equivalent instant window")
    assert(api.present(**{open_key => root, closed_sd_jwt: closed.closed_sd_jwt, profile_ref: profile}).closed_sd_jwt == closed.closed_sd_jwt, "conditional exact restore")
    %w[legal_name brand_name domain_name].each do |field|
      replacement = field == "domain_name" ? "other.example" : "Other"
      assert(!api.verify(**verify.merge(trusted_pisp: pisp.merge(field => replacement))).verified?, "each independent PISP field")
    end
    assert(!api.verify(**verify.merge(execution_at: nil)).verified?, "no implicit immediate date")
    assert(!api.verify(**verify.merge(trusted_pisp: nil)).verified?, "no implicit selected PISP")
    invalid { api.issue_open(**issue.merge(candidate_policy: nil)) }
    invalid { api.issue_open(**issue.merge(candidate_policy: :correlated)) }
    invalid { api.issue_open(**issue.merge(constraints: base_cs)) }
    invalid { api.issue_open(**issue.merge(profile_ref: api::PROFILE_REF)) }
    invalid { api.issue_closed(**closing, open_key => root, profile_ref: api::PROFILE_REF) }
    invalid { api.issue_closed(**closing.merge(payment: details.merge("execution_date" => equivalent)), open_key => root, profile_ref: profile) }
    invalid { api.issue_closed(**closing.merge(payment: details.merge("pisp" => pisp.merge("brand_name" => "Changed"))), open_key => root, profile_ref: profile) }
    invalid { api.issue_open(**issue.merge(constraints: base_cs + [{"type" => "payment.execution_date"}])) }
    invalid { api.issue_open(**issue.merge(constraints: base_cs + [window.merge("not_before" => "2028-03-01T00:00:00Z")])) }
    [allowed, window, window.reject { |k,_| k == "not_before" }, window.reject { |k,_| k == "not_after" }].each do |single|
      assert(api.issue_open(**issue.merge(constraints: base_cs + [single])).frozen?, "new constraints individually / one-sided bounds")
    end
    free_full = api.issue_open(**issue.merge(fixed: {}))
    free_root = api == S ? api.select(open_sd_jwt: free_full, payee_index: 0, instrument_index: 0, profile_ref: profile) : free_full
    # No fixed-date condition can mask the interval rejection in these cases.
    ["2028-02-29T12:00:00.123456788Z", "2028-02-29T12:00:00.123456790Z",
     "2028-02-29T13:00:00.123456789+02:00"].each do |outside|
      invalid { api.issue_closed(**closing.merge(payment: details.merge("execution_date" => outside)), open_key => free_root, profile_ref: profile) }
    end
    invalid { api.issue_closed(**closing.merge(payment: details.merge("pisp" => pisp.merge("brand_name" => "Unapproved"))), open_key => free_root, profile_ref: profile) }
    assert(api.issue_closed(**closing.merge(payment: details.merge("execution_date" => equivalent)), open_key => free_root, profile_ref: profile).frozen?, "unfixed equivalent instant accepted")
    invalid { api.issue_open(**issue.merge(constraints: base_cs + [allowed, allowed])) }
    invalid { api.issue_open(**issue.merge(constraints: base_cs + [window.merge("budget" => 1)])) }
    invalid { api.issue_open(**issue.merge(constraints: base_cs + [allowed.merge("allowed" => [pisp, pisp])])) }
    invalid { api.issue_open(**issue.merge(fixed: {"pisp" => pisp.merge("legal_name" => "Contradiction")})) }
    invalid { api.issue_open(**issue.merge(fixed: {"execution_date" => "2029-01-01T00:00:00Z"})) }
    if api == S
      display = root.split("~").map { |seg| seg.include?(".") ? decode(seg.split(".")[1]) : decode(seg) }.inspect
      assert(!display.include?("SECRET") && display.include?("pisp.example") && display.include?("not_before"), "only payee/card candidates hidden; all policy visible")
    end
    [->(o,_) { o["constraints"] << {"type" => "payment.recurring"} },
     ->(o,_) { o["constraints"].find { |c| c["type"] == "payment.allowed_pisps" }["allowed"] = [{"..." => hash("hidden")} ] },
     ->(o,_) { o["constraints"].find { |c| c["type"] == "payment.execution_date" }["not_before"] = {"..." => hash("hidden")} },
     ->(_,outer) { outer["ap2_profile"] = api::PROFILE_REF }].each do |change|
      bad = resign_root(root, provider, &change)
      invalid { api.issue_closed(**closing, open_key => bad, profile_ref: profile) }
    end
    terminal = decode(closed.closed_sd_jwt.split(".")[1])
    [->(t) { t["delegate_payload"][0].delete("execution_date") },
     ->(t) { t["delegate_payload"][0]["execution_date"] = "2028-02-29T12:00:00.123456788Z" },
     ->(t) { t["delegate_payload"][0]["pisp"]["legal_name"] = "Changed" },
     ->(t) { t["ap2_profile"] = api::PROFILE_REF }].each do |change|
      value = copy(terminal); change.call(value)
      wire = JWT.encode(value, agent, "ES256", {"typ" => "kb+sd-jwt"}) + "~"
      assert(!api.verify(**verify.merge(closed_sd_jwt: wire)).verified?, "signed causal policy/marker negative")
    end
    %w[Success Error].each do |outcome|
      fields = outcome == "Success" ? {psp_confirmation_id: "psp", network_confirmation_id: "network"} : {error: "declined", error_description: "Application decision"}
      receipt = M::PaymentReceipt.sign(closed_sd_jwt: closed.closed_sd_jwt, profile_ref: profile, issuer: "shop", outcome: outcome,
        payment_id: "payment", issued_at: NOW, signer: signer(merchant), public_key_pem: merchant.public_to_pem, **fields)
      args = {jwt: receipt.jwt, closed_sd_jwt: closed.closed_sd_jwt, profile_ref: profile, trusted_public_key_pem: merchant.public_to_pem,
        expected_issuer: "shop", expected_payment_id: "payment", not_before: NOW, not_after: NOW + 60, verified_at: NOW}
      assert(M::PaymentReceipt.verify(**args).verified?, "Receipt #{outcome} with explicit policy profile")
      assert(!M::PaymentReceipt.verify(**args.merge(profile_ref: P::PROFILE_REF)).verified?, "Receipt downgrade rejects")
      assert(!M::PaymentReceipt.verify(**args.merge(closed_sd_jwt: direct.closed_sd_jwt)).verified?, "Receipt different original Closed rejects")
    end
    results << {api: api, profile: profile, full: full, root: root, closed: closed, verify: verify}
  end
  # Trusted values are detached before nested Host cryptography callbacks.
  results.each do |item|
  live = copy(pisp); live_date = equivalent.dup; live_profile = Q::SELECTIVE_PROFILE_REF.dup
  original = M.method(:verify_checkout)
  M.define_singleton_method(:verify_checkout) do |**args|
    live["legal_name"].replace("Changed"); live_date.replace("2029-01-01T00:00:00Z"); live_profile.replace(S::PROFILE_REF)
    original.call(**args)
  end
  begin
    live_profile.replace(item[:profile])
    assert(item[:api].verify(**item[:verify].merge(trusted_pisp: live, execution_at: live_date, profile_ref: live_profile)).verified?, "context/profile detached before Host callback")
  ensure
    M.define_singleton_method(:verify_checkout, original)
  end
  end
  calls = 0
  effect = ->(_) { calls += 1; raise "unexpected signer" }
  invalid { P.issue_open(**opening_args.merge(profile_ref: Q::PROFILE_REF, constraints: base_cs + [window.merge("not_after" => "bad")], signer: effect)) }
  invalid { P.issue_direct(**direct_issue.merge(payment: details.reject { |k,_| k == "pisp" }, signer: effect)) }
  assert(calls == 0, "policy validation before signer")
  large_pisps = Array.new(8) { |i| {"legal_name" => "\0" * 511 + i.to_s, "brand_name" => "\0" * 512, "domain_name" => "p#{i}.example"} }
  invalid { P.issue_open(**opening_args.merge(profile_ref: Q::PROFILE_REF,
    constraints: base_cs + [allowed.merge("allowed" => large_pisps)], fixed: {}, signer: effect)) }
  invalid { S.issue_open(**opening_args.merge(profile_ref: Q::SELECTIVE_PROFILE_REF,
    constraints: base_cs + [allowed.merge("allowed" => large_pisps)], fixed: {}, signer: effect,
    approved_combinations: [[0,0],[0,1],[1,0],[1,1]], selective: :both)) }
  assert(calls == 0, "new-policy aggregate resource bounds before signer")
  puts "payment policy: #{@count} assertions passed"
end
