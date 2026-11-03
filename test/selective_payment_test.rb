# frozen_string_literal: true
require_relative "runtime_dependencies"
if ENV["AP2_INSTALLED"] == "1"
  require "ap2_mandate_verifier"
else
  $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
  require "ap2_mandate_verifier"
  require_relative "../lib/ap2_mandate_verifier/selective_payment"
end
require "stringio"
require_relative "../examples/conditional_checkout"

module SelectivePaymentTest
  M = AP2MandateVerifier
  S = M::SelectivePayment
  NOW = 1_800_000_000
  @count = 0
  def self.assert(value, label)
    @count += 1
    raise "selective payment: #{label}" unless value
  end
  def self.invalid
    yield
    raise "selective payment unexpectedly accepted"
  rescue S::Invalid => error
    assert(error.cause.nil? && error.message == "invalid selective payment information", "redacted errors")
  end
  def self.decode(value) = JSON.parse(Base64.urlsafe_decode64(value))
  def self.encode(value) = Base64.urlsafe_encode64(JSON.generate(value), padding: false)
  def self.hash(wire) = Base64.urlsafe_encode64(Digest::SHA256.digest(wire), padding: false)
  def self.deep_copy(value) = Marshal.load(Marshal.dump(value))
  def self.root_payload(wire) = JWT.decode(wire.split("~").first, nil, false).first
  def self.resign(wire, key)
    payload = root_payload(wire)
    ds = wire.split("~", -1)[1...-1]
    content_hash = payload["delegate_payload"][0]["..."]
    i = ds.index { |d| hash(d) == content_hash }
    content = decode(ds[i])
    yield(content[1], payload)
    ds[i] = encode(content)
    payload["delegate_payload"][0]["..."] = hash(ds[i])
    [JWT.encode(payload, key, "ES256", {"typ" => "example+sd-jwt"}), *ds, ""].join("~")
  end
  original_out = $stdout
  begin
    $stdout = StringIO.new
    state = ConditionalCheckoutExample.run
  ensure
    $stdout = original_out
  end
  provider, agent, merchant = state.fetch(:keys)
  signer = ->(key) { M::CheckoutJWT.es256_signer(private_key: key) }
  checkout = state.fetch(:closed).checkout_jwt
  details = M::Payment.details(checkout_jwt: checkout, trusted_merchant_public_key_pem: merchant.public_to_pem,
    expected_merchant_id: "shop", payment_instrument: {"id" => "chosen-card", "type" => "card"})
  hidden_payee = {"id" => "hidden-shop", "name" => "UNSELECTED-PAYEE-SECRET"}
  hidden_card = {"id" => "UNSELECTED-CARD-SECRET", "type" => "card", "description" => "UNSELECTED-CARD-DESCRIPTION"}
  cs = [{"type" => "payment.amount_range", "currency" => "USD", "min" => 100, "max" => 300},
    {"type" => "payment.allowed_payees", "allowed" => [details["payee"], hidden_payee]},
    {"type" => "payment.allowed_payment_instruments", "allowed" => [details["payment_instrument"], hidden_card]}]
  issue = {open_checkout_sd_jwt: state.fetch(:opening).root_presentation, constraints: cs, fixed: {},
    approved_combinations: [[0,0],[0,1],[1,0],[1,1]], agent_public_key_pem: agent.public_to_pem,
    issued_at: NOW, expires_at: NOW+60, signer: signer.call(provider), public_key_pem: provider.public_to_pem}
  checkout_inputs = M::InputBuilder.inputs(**state.fetch(:host_inputs), saved_challenge: state.fetch(:saved),
    terminal_jws: state.fetch(:closed).terminal_jws, expected_challenge_issuer_id: "host",
    clock_source_id: "synthetic-clock", verified_at: NOW)
  outputs = []
  %i[payees instruments both].each do |mode|
    full = S.issue_open(**issue, selective: mode)
    choices = {payee_index: mode == :instruments ? nil : 0, instrument_index: mode == :payees ? nil : 0}
    selected = S.select(open_sd_jwt: full, **choices)
    assert(full.frozen? && selected.frozen?, "immutable original strings")
    assert(selected.split("~").first == full.split("~").first && selected.bytesize < full.bytesize, "same JWT smaller presentation")
    secrets = []
    secrets << hidden_payee["name"] if mode != :instruments
    secrets.concat(hidden_card.values_at("id", "description")) if mode != :payees
    # Decode all original wire components so base64 encoding cannot mask leaks.
    observed = [decode(selected.split("~")[0].split(".")[1]), *selected.split("~", -1)[1...-1].map { |d| decode(d) }].inspect
    secrets.each { |secret| assert(!observed.include?(secret), "hidden values absent in mode #{mode}") }
    full_ds = full.split("~", -1)[1...-1]
    selected_ds = selected.split("~", -1)[1...-1]
    full_ds.reject { |d| selected_ds.include?(d) }.each { |d| assert(!selected.include?(d), "unselected disclosure not transported") }
    close_args = {open_presentation: selected, payment: details, trusted_provider_public_key_pem: provider.public_to_pem,
      agent_public_key_pem: agent.public_to_pem, audience: "credential-provider", nonce: "payment-nonce", verified_at: NOW,
      signer: signer.call(agent)}
    closed = S.issue_closed(**close_args)
    restored = S.present(open_presentation: selected, closed_sd_jwt: closed.closed_sd_jwt)
    assert(restored.chain == closed.chain, "exact storage restoration")
    terminal = root_payload(closed.closed_sd_jwt)
    assert(terminal["sd_hash"] == hash(selected) && terminal["sd_hash"] != hash(full), "independent reduced-wire hash")
    args = {open_presentation: restored.open_sd_jwt, closed_sd_jwt: restored.closed_sd_jwt,
      checkout_inputs: checkout_inputs, expected_payment: details, trusted_provider_public_key_pem: provider.public_to_pem,
      expected_agent_public_key_pem: agent.public_to_pem, expected_audience: "credential-provider", expected_nonce: "payment-nonce", verified_at: NOW}
    checked = S.verify(**args)
    assert(checked.verified? && checked.payment.slice(*M::Payment::FIELDS) == details && checked.payment.frozen?, "complete public verification")
    secrets.each { |secret| assert(!checked.inspect.include?(secret) && !checked.payment.inspect.include?(secret), "result privacy") }
    assert(!S.verify(**args.merge(open_presentation: full)).verified?, "full issuance is not a selected presentation")
    assert(!M::Payment.verify(**args.reject { |k,_| k == :open_presentation }.merge(open_sd_jwt: selected, checkout_mode: :conditional)).verified?, "old profile rejects new root")
    %w[Success Error].each do |outcome|
      fields = outcome == "Success" ? {psp_confirmation_id: "psp", network_confirmation_id: "network"} : {error: "declined", error_description: "Synthetic rejection"}
      receipt = M::PaymentReceipt.sign(closed_sd_jwt: closed.closed_sd_jwt, issuer: "processor", outcome: outcome,
        payment_id: "payment", issued_at: NOW, signer: signer.call(merchant), public_key_pem: merchant.public_to_pem, **fields)
      policy = {jwt: receipt.jwt, closed_sd_jwt: closed.closed_sd_jwt, trusted_public_key_pem: merchant.public_to_pem,
        expected_issuer: "processor", expected_payment_id: "payment", not_before: NOW, not_after: NOW+60, verified_at: NOW}
      result = M::PaymentReceipt.verify(**policy)
      assert(result.verified? && result.payment_succeeded? == (outcome == "Success"), "receipt #{outcome}")
      assert(receipt.reference == hash(closed.closed_sd_jwt) && receipt.reference != hash(selected), "final-only receipt reference")
      assert(!M::PaymentReceipt.verify(**policy.merge(expected_payment_id: "other")).verified?, "receipt mismatch")
    end
    outputs << {mode: mode, full: full, selected: selected, closed: closed, args: args, close_args: close_args}
  end
  main = outputs.last
  args = main.fetch(:args); selected = main.fetch(:selected); full = main.fetch(:full)
  wrong = OpenSSL::PKey::EC.generate("prime256v1")
  {trusted_provider_public_key_pem: wrong.public_to_pem, expected_agent_public_key_pem: wrong.public_to_pem,
   expected_audience: "wrong", expected_nonce: "wrong", checkout_inputs: checkout_inputs.merge(host_checkout_jws: "secret"),
   verified_at: NOW+60, unknown: true}.each do |key, value|
    assert(!S.verify(**args.merge(key => value)).verified?, "external mismatch #{key}")
  end
  [nil, false].each { |key| invalid { S.issue_closed(**main[:close_args].merge(trusted_provider_public_key_pem: key)) } }
  called = false
  [[[0,0],[1,1]], [[0,0],[0,1],[1,0],[1,0]], [[0,0],[0,1],[1,0],[2,1]], [[0.0,0],[0,1],[1,0],[1,1]]].each do |pairs|
    invalid { S.issue_open(**issue.merge(approved_combinations: pairs, selective: :both, signer: ->(_) { called = true; raise "secret" })) }
  end
  assert(!called, "correlated or malformed approval rejected before signer")
  invalid { S.select(open_sd_jwt: full, payee_index: 2, instrument_index: 0) }
  invalid { S.select(open_sd_jwt: full, payee_index: 0.0, instrument_index: 0) }
  invalid { S.issue_open(**issue.merge(selective: :unknown)) }
  invalid { S.issue_open(**issue.merge(selective: :both, unknown: true)) }
  # Signed policy changes bind a new authentic root and authentic Agent terminal;
  # failures below are semantic, not just signature/entrypoint failures.
  rebind = lambda do |root, closed_changes = {}|
    terminal = root_payload(main[:closed].closed_sd_jwt)
    terminal["sd_hash"] = hash(root)
    terminal["delegate_payload"][0].merge!(closed_changes)
    signed = JWT.encode(terminal, agent, "ES256", {"typ" => "kb+sd-jwt"}) + "~"
    args.merge(open_presentation: root, closed_sd_jwt: signed)
  end
  [->(o,p) { o["constraints"].find { |c| c["type"] == "payment.amount_range" }["max"] = 299 },
   ->(o,p) { o["constraints"].find { |c| c["type"] == "payment.amount_range" }["currency"] = "EUR" },
   ->(o,p) { o["constraints"].find { |c| c["type"] == "payment.reference" }["conditional_transaction_id"] = "A"*43 },
   ->(o,p) { o["payment_instrument"] = hidden_card },
   ->(o,p) { o["cnf"] = {"jwk" => M::RootSignature.public_jwk!(wrong.public_to_pem)} },
   ->(o,p) { o["exp"] = NOW },
   ->(o,p) { o["constraints"].reject! { |c| c["type"] == "payment.amount_range" } },
   ->(o,p) { o["_sd"] = ["A"*43] },
   ->(o,p) { o["constraints"] << {"type" => "payment.budget", "max" => 300, "currency" => "USD"} },
   ->(o,p) { p["ap2_profile"] = "unknown" },
   ->(o,p) { p["_sd_alg"] = "sha-512" }].each do |change|
    altered = resign(selected, provider, &change)
    assert(!S.verify(**rebind.call(altered)).verified?, "signed policy rejection")
  end
  [{"transaction_id" => "A"*43}, {"payee" => hidden_payee}, {"payment_instrument" => hidden_card},
   {"payment_amount" => {"amount" => 301, "currency" => "USD"}}].each do |change|
    assert(!S.verify(**rebind.call(selected, change)).verified?, "signed closed mismatch")
  end
  ds = selected.split("~", -1)
  [ds[0...-2].join("~") + "~", selected + ds[1] + "~", ds.values_at(0,2,1,3,4).compact.join("~"),
   selected.sub(/~[^~]+~\z/, "~e30~"), "x"*(S::MAX_WIRE+1)].each do |bad|
    assert(!S.verify(**args.merge(open_presentation: bad)).verified?, "wire grammar/hash rejection")
  end
  reordered = [ds[0], *ds[1...-1].reverse, ""].join("~")
  assert(!S.verify(**args.merge(open_presentation: reordered)).verified?, "old terminal fails reordered wire")
  assert(S.verify(**rebind.call(reordered)).verified?, "reordered valid disclosures require fresh binding")
  # Full-issuance random salts and commitment sets differ across independent issues.
  fresh = S.issue_open(**issue, selective: :both)
  assert(fresh != full && root_payload(fresh)["delegate_payload"] != root_payload(full)["delegate_payload"], "fresh salts")
  assert(!S.verify(**args.merge(open_presentation: fresh)).verified?, "unrelated issuance cannot be substituted")
  duplicate = resign(selected, provider) do |o,p|
    ps = o["constraints"].find { |c| c["type"] == "payment.allowed_payees" }["allowed"]
    ps[1] = deep_copy(ps[0])
  end
  assert(!S.verify(**rebind.call(duplicate)).verified?, "signed duplicate commitment")
  other_ds = fresh.split("~", -1)[2]
  assert(!S.verify(**args.merge(open_presentation: selected + other_ds + "~")).verified?, "foreign disclosure rejected")
  # Shared caller state cannot replace Checkout originals after the nested verifier.
  mutable = checkout_inputs.dup
  original_verify = M.method(:verify_checkout)
  M.define_singleton_method(:verify_checkout) do |**inputs|
    result = original_verify.call(**inputs)
    mutable[:host_checkout_jws] = "secret"
    mutable[:root_presentation] = "secret"
    result
  end
  begin
    assert(S.verify(**args.merge(checkout_inputs: mutable)).verified?, "detached complete Checkout input snapshot")
  ensure
    M.define_singleton_method(:verify_checkout, original_verify)
  end
  # Every use of a caller-owned Agent PEM must consume one detached snapshot.
  jwk_method = M::RootSignature.method(:public_jwk!)
  checkout_method = M.method(:verify_checkout)
  live_agent = agent.public_to_pem.dup
  gate = false; mutated = false
  wrong_terminal = JWT.encode(root_payload(main[:closed].closed_sd_jwt), wrong, "ES256", {"typ" => "kb+sd-jwt"})+"~"
  M.define_singleton_method(:verify_checkout) do |**inputs|
    result = checkout_method.call(**inputs)
    gate = true
    result
  end
  M::RootSignature.define_singleton_method(:public_jwk!) do |pem|
    result = jwk_method.call(pem)
    if gate && !mutated && pem == agent.public_to_pem
      live_agent.replace(wrong.public_to_pem)
      mutated = true
    end
    result
  end
  begin
    assert(!S.verify(**args.merge(expected_agent_public_key_pem: live_agent, closed_sd_jwt: wrong_terminal)).verified?,
      "Agent cnf/signature share one PEM snapshot")
    assert(mutated, "Agent verification race control reached cnf")
  ensure
    M.define_singleton_method(:verify_checkout, checkout_method)
    M::RootSignature.define_singleton_method(:public_jwk!, jwk_method)
  end
  live_agent = agent.public_to_pem.dup
  mutated = false
  M::RootSignature.define_singleton_method(:public_jwk!) do |pem|
    result = jwk_method.call(pem)
    if !mutated && pem == agent.public_to_pem
      live_agent.replace(wrong.public_to_pem)
      mutated = true
    end
    result
  end
  begin
    invalid { S.issue_closed(**main[:close_args].merge(agent_public_key_pem: live_agent, signer: signer.call(wrong))) }
    assert(mutated, "Agent issuance race control reached cnf")
  ensure
    M::RootSignature.define_singleton_method(:public_jwk!, jwk_method)
  end
  race_time = checkout_inputs.dup
  race_time.define_singleton_method(:to_h) do |&block|
    self[:verified_at] = NOW+1
    Hash.instance_method(:to_h).bind_call(self, &block)
  end
  assert(!S.verify(**args.merge(checkout_inputs: race_time)).verified?, "detached Checkout clock equals outer verification clock")
  # Candidate selection is by original signed position, not a reconstructed index.
  chosen_b = S.select(open_sd_jwt: full.dup, payee_index: 0, instrument_index: 1)
  details_b = details.merge("payment_instrument" => hidden_card)
  closed_b = S.issue_closed(**main[:close_args].merge(open_presentation: chosen_b, payment: details_b))
  assert(S.verify(**args.merge(open_presentation: chosen_b, closed_sd_jwt: closed_b.closed_sd_jwt,
    expected_payment: details_b)).verified?, "second candidate and original slot remain usable")
  # Fixed candidate fields cannot reveal an unselected alternative through select.
  fixed_full = S.issue_open(**issue.merge(selective: :both, fixed: {"payment_instrument" => details["payment_instrument"]}))
  invalid { S.select(open_sd_jwt: fixed_full, payee_index: 0, instrument_index: 1) }
  # Individually valid candidates can exceed the total issuance bound. Reject
  # before a remote signer observes any request or has an issuance side effect.
  oversized = deep_copy(cs)
  oversized[1]["allowed"] = Array.new(8) { |i| {"id" => i.to_s+"i"*511, "name" => "\u0001"*512, "website" => "\u0001"*512} }
  oversized[2]["allowed"] = Array.new(8) { |i| {"id" => i.to_s+"i"*511, "type" => "\u0001"*512, "description" => "\u0001"*512} }
  pairs = (0...8).flat_map { |p| (0...8).map { |i| [p,i] } }
  called = false
  invalid { S.issue_open(**issue.merge(selective: :both, constraints: oversized, approved_combinations: pairs,
    signer: ->(_) { called = true; raise "secret" })) }
  assert(!called, "full disclosure resource preflight before signer")
  # Terminal's decoded payload may fit yet its compact wire can be too large.
  control = "\u0001"*512
  large_details = details.merge("payee" => {"id" => control, "name" => control, "website" => control},
    "payment_instrument" => {"id" => control, "type" => control, "description" => control})
  one = [cs[0], {"type" => "payment.allowed_payees", "allowed" => [large_details["payee"]]},
    {"type" => "payment.allowed_payment_instruments", "allowed" => [large_details["payment_instrument"]]}]
  one_full = S.issue_open(**issue.merge(selective: :both, constraints: one, approved_combinations: [[0,0]]))
  one_selected = S.select(open_sd_jwt: one_full, payee_index: 0, instrument_index: 0)
  candidate = nil
  (1..512).each do |n|
    claim = {"delegate_payload" => [large_details.merge("vct" => "mandate.payment.1", "iat" => NOW, "exp" => NOW+60)],
      "iat" => NOW, "aud" => control, "nonce" => "\u0001"*n, "sd_hash" => hash(one_selected)}
    body = JSON.generate(claim)
    preview = encode({"alg" => "ES256", "typ" => "kb+sd-jwt"})+"."+Base64.urlsafe_encode64(body,padding:false)+"."+"A"*86
    candidate = "\u0001"*n if body.bytesize <= 24_576 && preview.bytesize > 32_768
    break if candidate
  end
  assert(!candidate.nil?, "independent terminal decoded-valid wire-limit oracle")
  called = false
  invalid { S.issue_closed(**main[:close_args].merge(open_presentation: one_selected, payment: large_details,
    audience: control, nonce: candidate, signer: ->(_) { called = true; raise "secret" })) }
  assert(!called, "terminal wire bound before signer")
  new_selected = S.select(open_sd_jwt: fresh, payee_index: 0, instrument_index: 0)
  assert(!S.verify(**args.merge(open_presentation: new_selected)).verified?, "fresh authentic root requires fresh exact terminal hash")
  tampered = selected.dup
  jwt_parts = tampered.split("~",-1)
  compact_parts = jwt_parts[0].split(".")
  compact_parts[2][0] = compact_parts[2][0] == "A" ? "B" : "A"
  jwt_parts[0] = compact_parts.join(".")
  assert(!S.verify(**args.merge(open_presentation: jwt_parts.join("~"))).verified?, "root signature bit tamper")
  # Unsupported pair constraints are never flattened into independent allowlists.
  bad_pairs = resign(selected, provider) do |o,p|
    o["constraints"] << {"type" => "payment.allowed_combinations", "allowed" => [[0,0],[1,1]]}
  end
  assert(!S.verify(**rebind.call(bad_pairs)).verified?, "signed unsupported correlated constraint rejects")
  # Structural restoration obeys the same compact-root limit as authentication.
  header = encode({"alg" => "ES256", "typ" => "example+sd-jwt"})
  body = Base64.urlsafe_encode64(" "*13_000+JSON.generate(root_payload(selected)), padding: false)
  signing_input = header+"."+body
  oversized_root = signing_input+"."+Base64.urlsafe_encode64(signer.call(provider).call(signing_input), padding: false)
  oversized_root += "~"+selected.split("~",-1)[1..].join("~")
  oversized_terminal = root_payload(main[:closed].closed_sd_jwt).merge("sd_hash" => hash(oversized_root))
  oversized_closed = JWT.encode(oversized_terminal, agent, "ES256", {"typ" => "kb+sd-jwt"})+"~"
  invalid { S.present(open_presentation: oversized_root, closed_sd_jwt: oversized_closed) }
  # Returning no result or leaking the retained universe is never a success.
  hidden = [hidden_payee["name"], hidden_card["id"], hidden_card["description"]]
  sink = StringIO.new; old = $stdout
  begin
    $stdout = sink
    failure = S.verify(**args.merge(expected_nonce: "wrong"))
    begin
      S.select(open_sd_jwt: "bad", payee_index: 0, instrument_index: 0)
    rescue S::Invalid => error
      hidden.each { |s| assert(!error.inspect.include?(s), "exception privacy") }
    end
  ensure
    $stdout = old
  end
  assert(sink.string.empty? && !failure.verified? && failure.payment.nil?, "no logs or failed claims")
  if ENV["SELECTIVE_PAYMENT_EXPORT"]
    File.write(ENV.fetch("SELECTIVE_PAYMENT_EXPORT"), JSON.generate(issue: issue.reject { |k,_| [:signer].include?(k) },
      cases: outputs.map { |v| {mode: v[:mode], full: v[:full], selected: v[:selected], arguments: v[:args]} }))
  end
  puts "selective payment: #{@count} assertions passed"
end
