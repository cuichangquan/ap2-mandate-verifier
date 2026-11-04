# frozen_string_literal: true
require_relative "runtime_dependencies"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__)) unless ENV["AP2_INSTALLED"] == "1"
require "ap2_mandate_verifier"
require "openssl"

module SelectiveCheckoutTest
  M = AP2MandateVerifier
  S = M::SelectiveCheckout
  NOW = 1_800_000_000
  @count = 0
  def self.assert(value, label)
    @count += 1
    raise "selective checkout: #{label}" unless value
  end
  def self.invalid
    yield
    raise "selective checkout unexpectedly accepted"
  rescue S::Invalid => e
    assert(e.message == "invalid selective checkout information" && e.cause.nil?, "redacted error")
  end
  def self.copy(v) = Marshal.load(Marshal.dump(v))
  def self.encode(v) = Base64.urlsafe_encode64(JSON.generate(v), padding: false)
  def self.decode(v) = JSON.parse(Base64.urlsafe_decode64(v))
  def self.hash(v) = Base64.urlsafe_encode64(Digest::SHA256.digest(v), padding: false)
  def self.totals(n) = %w[subtotal total].map { |t| {"type" => t, "amount" => n} }
  def self.signer(key) = M::CheckoutJWT.es256_signer(private_key: key)
  def self.resign(wire, key)
    parts = wire.split("~", -1)
    payload = decode(parts.first.split(".")[1])
    i = parts.index { |d| hash(d) == payload["delegate_payload"][0]["..."] }
    content = decode(parts[i])
    yield(content[1], payload)
    parts[i] = encode(content)
    payload["delegate_payload"][0]["..."] = hash(parts[i])
    parts[0] = JWT.encode(payload, key, "ES256", {"typ" => "example+sd-jwt"})
    parts.join("~")
  end

  provider, agent, merchant = Array.new(3) { OpenSSL::PKey::EC.generate("prime256v1") }
  seller = {"id" => "shop", "name" => "Selected Merchant"}
  merchants = [seller, {"id" => "HIDDEN-MERCHANT-ID", "name" => "HIDDEN-MERCHANT-SECRET"}]
  product = ->(id) { {"id" => id, "title" => "Product #{id}"} }
  # A greedy allocator takes A for broad and fails narrow; residual max-flow
  # must instead assign B to broad, and A to narrow.
  requirements = [{"id" => "broad", "quantity" => 1, "acceptable_items" => %w[A B HIDDEN-PRODUCT].map(&product)},
    {"id" => "narrow", "quantity" => 2, "acceptable_items" => [product.call("A"), product.call("HIDDEN-SECOND")]}]
  issue = {allowed_merchants: merchants, requirements: requirements, candidate_policy: :independent,
    agent_public_key_pem: agent.public_to_pem, issued_at: NOW, expires_at: NOW + 600,
    signer: signer(provider), public_key_pem: provider.public_to_pem}
  full = S.issue_open(**issue)
  selected = S.select(open_sd_jwt: full.root_presentation, merchant_index: 0, item_indices: [[0, 1], [0]])
  root = selected.root_presentation
  assert(full.frozen? && root.frozen? && selected.open_sd_jwt == root, "immutable Open")
  assert(root.bytesize < full.root_presentation.bytesize && root.split("~").first == full.root_presentation.split("~").first, "original root preserved")
  visible = root.split("~").map { |p| p.include?(".") ? decode(p.split(".")[1]) : decode(p) }.inspect
  assert(!visible.include?("HIDDEN-"), "all presentation segments private")
  parsed = S.send(:parse!, root, complete: false)
  assert(parsed[:opening]["constraints"][0]["items"].map { |g| [g["id"], g["quantity"]] } == [["broad", 1], ["narrow", 2]], "all mandatory groups")
  assert(parsed[:opening]["constraints"][0]["items"][0]["acceptable_items"].size == 2, "multiple candidates retained")
  lines = %w[A A B].each_with_index.map do |id, i|
    {"id" => "row-#{i}", "quantity" => 1, "item" => product.call(id).merge("price" => 100), "totals" => totals(100)}
  end
  cart = {"id" => "order", "merchant" => seller, "status" => "ready_for_complete", "currency" => "USD",
    "line_items" => lines, "totals" => totals(300), "links" => []}
  checkout = M::CheckoutJWT.sign(checkout: cart, profile_ref: S::PROFILE_REF,
    signer: signer(merchant), public_key_pem: merchant.public_to_pem)
  auto = S.select_for_checkout(open_sd_jwt: full.root_presentation, checkout: cart)
  assert(auto.root_presentation == root, "actual checkout selector retains matching candidates")
  roles = %w[Issuer Agent Merchant]
  records = roles.zip([provider, agent, merchant]).map do |role, key|
    {"role" => role, "identity" => role == "Merchant" ? "shop" : role.downcase, "tenant_id" => "tenant",
      "purpose" => "checkout", "key_ref" => role.downcase, "public_key_pem" => key.public_to_pem,
      "active" => true, "not_before" => NOW - 1, "not_after" => NOW + 1000}
  end
  selectors = records.to_h { |r| [r["role"].downcase.to_sym, r.slice("identity", "purpose", "key_ref")] }
  trust = M::InputBuilder.trust(snapshot: {"id" => "registry", "policy_version" => "1", "active" => true,
    "not_before" => NOW - 1, "not_after" => NOW + 1000, "records" => records}, tenant_id: "tenant",
    verified_at: NOW, profile_ref: S::PROFILE_REF, **selectors)
  host_order = {"tenant_id" => "tenant", "buyer_account_id" => "buyer", "order_id" => "order", "merchant_id" => "shop",
    "audience" => "host", "order_version" => "1", "currency" => "USD", "expected_total" => 300}
  host = {trust: trust, order: host_order, root_presentation: root, host_checkout_jws: checkout.jwt}
  saved = M::InputBuilder.prepare(**host, challenge_id: "challenge", nonce: "nonce", issuer_id: "host",
    not_before: NOW, not_after: NOW + 60)
  closing = {root_presentation: root, checkout_jwt: checkout.jwt, trusted_issuer_public_key_pem: provider.public_to_pem,
    agent_public_key_pem: agent.public_to_pem, trusted_merchant_public_key_pem: merchant.public_to_pem,
    expected_merchant_id: "shop", audience: "host", nonce: "nonce", verified_at: NOW, signer: signer(agent)}
  closed = S.issue_closed(**closing)
  raw = M::InputBuilder.inputs(**host, terminal_jws: closed.terminal_jws, saved_challenge: saved,
    expected_challenge_issuer_id: "host", clock_source_id: "clock", verified_at: NOW)
  verified = M.verify_checkout(**raw)
  assert(verified.success? && !verified.evidence.inspect.include?("HIDDEN-"), "genuine seven-input Host verification")
  restored = S.present(root_presentation: root, terminal_jws: closed.terminal_jws, checkout_jwt: checkout.jwt)
  assert(restored.root_presentation == root && restored.terminal_jws == closed.terminal_jws, "exact restore")
  terminal_claims = decode(closed.terminal_jws.split(".")[1])
  assert(terminal_claims["sd_hash"] == hash(root), "independent exact reduced-wire hash")
  receipt = nil
  %w[Success Error].each do |outcome|
    data = outcome == "Success" ? {order_id: "order"} : {error: "rejected", error_description: "Policy decision"}
    receipt = M::CheckoutReceipt.sign(closed_sd_jwt: closed.closed_sd_jwt, profile_ref: S::PROFILE_REF,
      issuer: "shop", outcome: outcome, issued_at: NOW, **data, signer: signer(merchant), public_key_pem: merchant.public_to_pem)
    result = M::CheckoutReceipt.verify(jwt: receipt.jwt, closed_sd_jwt: closed.closed_sd_jwt,
      profile_ref: S::PROFILE_REF, trusted_public_key_pem: merchant.public_to_pem, expected_issuer: "shop",
      not_before: NOW, not_after: NOW + 60, verified_at: NOW)
    assert(result.verified? && result.outcome == outcome, "receipt #{outcome}")
  end

  # Full old profile remains full: signed new marker never selects Host policy.
  begin
    M::RootDisclosures.verified_root!(root, provider.public_to_pem)
    raise "old profile accepted partial"
  rescue M::RootSignature::Rejected
    assert(true, "old default rejects selective profile")
  end
  invalid { S.issue_closed(**closing.merge(root_presentation: full.root_presentation)) }
  [[[], [0]], [[0], []], [[0,0], [0]], [[-1], [0]], [[3], [0]], [[0.0], [0]], [[0]]].each do |indices|
    invalid { S.select(open_sd_jwt: full.root_presentation, merchant_index: 0, item_indices: indices) }
  end
  [-1, 2, 0.0, nil].each { |n| invalid { S.select(open_sd_jwt: full.root_presentation, merchant_index: n, item_indices: [[0], [0]]) } }
  invalid { S.issue_open(**issue.merge(candidate_policy: :correlated)) }
  invalid { S.issue_open(**issue.reject { |k, _| k == :candidate_policy }) }
  second = S.select_for_checkout(open_sd_jwt: full.root_presentation, checkout: cart.merge("merchant" => merchants[1]))
  assert(S.send(:parse!, second.root_presentation, complete: false)[:opening]["constraints"][1]["allowed"] == [merchants[1]], "independent alternative merchant")
  invalid { S.select_for_checkout(open_sd_jwt: full.root_presentation, checkout: cart.merge("merchant" => {"id" => "unapproved", "name" => "Other"})) }
  # Same grand total is insufficient: narrow demands two A, but checkout has one.
  hall = copy(cart)
  hall["line_items"][1]["item"] = product.call("B").merge("price" => 100)
  invalid { S.select_for_checkout(open_sd_jwt: full.root_presentation, checkout: hall) }
  hall_jwt = M::CheckoutJWT.sign(checkout: hall, profile_ref: S::PROFILE_REF, signer: signer(merchant), public_key_pem: merchant.public_to_pem)
  invalid { S.issue_closed(**closing.merge(checkout_jwt: hall_jwt.jwt)) }
  %i[trusted_issuer_public_key_pem agent_public_key_pem trusted_merchant_public_key_pem].each do |field|
    wrong = OpenSSL::PKey::EC.generate("prime256v1")
    invalid { S.issue_closed(**closing.merge(field => wrong.public_to_pem)) }
  end
  invalid { S.issue_closed(**closing.merge(verified_at: NOW + 600)) }
  invalid { S.issue_closed(**closing.merge(expected_merchant_id: "other")) }
  invalid { S.issue_closed(**closing.merge(nonce: "")) }
  assert(!M.verify_checkout(**raw.merge(verified_at: NOW + 60)).success?, "Host expiry")
  assert(!M.verify_checkout(**raw.merge(root_presentation: full.root_presentation)).success?, "challenge binds exact reduced wire")
  wrong_nonce = copy(terminal_claims); wrong_nonce["nonce"] = "wrong"
  wrong_terminal = JWT.encode(wrong_nonce, agent, "ES256", {"typ" => "kb+sd-jwt"})
  assert(!M.verify_checkout(**raw.merge(terminal_jws: wrong_terminal)).success?, "signed nonce mismatch")
  [->(t) { t["aud"] = "other" }, ->(t) { t["iat"] = NOW + 1 },
   ->(t) { t["delegate_payload"][0]["iat"] += 1 },
   ->(t) { t["delegate_payload"][0]["exp"] += 1 },
   ->(t) { t["sd_hash"] = hash(full.root_presentation) }].each do |mutation|
    claims = copy(terminal_claims); mutation.call(claims)
    terminal = JWT.encode(claims, agent, "ES256", {"typ" => "kb+sd-jwt"})
    assert(!M.verify_checkout(**raw.merge(terminal_jws: terminal)).success?, "signed terminal conditions rejected")
  end
  tamper = ->(jwt) do
    pieces = jwt.split(".")
    signature = Base64.urlsafe_decode64(pieces[2]); signature.setbyte(0, signature.getbyte(0) ^ 1)
    pieces[2] = Base64.urlsafe_encode64(signature, padding: false)
    pieces.join(".")
  end
  invalid { S.issue_closed(**closing.merge(root_presentation: root.sub(root.split("~").first, tamper.call(root.split("~").first)))) }
  invalid { S.issue_closed(**closing.merge(checkout_jwt: tamper.call(checkout.jwt))) }
  assert(!M.verify_checkout(**raw.merge(terminal_jws: tamper.call(closed.terminal_jws))).success?, "Agent signature tamper")
  ds = root.split("~", -1)
  [ds[0...-1].push(ds[1], "").join("~"), ds[0...-2].push("").join("~"), root.sub(/.$/, "")].each do |bad|
    invalid { S.present(root_presentation: bad, terminal_jws: closed.terminal_jws, checkout_jwt: checkout.jwt) }
  end
  mutations = [->(o,_) { o.delete("cnf") }, ->(o,_) { o["constraints"][0]["items"][1].delete("quantity") },
    ->(o,_) { o["constraints"][0]["items"][1] = {"..." => hash("hidden-group")} },
    ->(o,_) { o["constraints"][0]["items"][1]["quantity"] = {"..." => hash("hidden")} },
    ->(o,_) { o["constraints"] << {"type" => "unknown"} },
    ->(o,_) { o["constraints"][0]["items"][0]["unexpected"] = true },
    ->(o,_) { o["constraints"][0]["items"][0]["acceptable_items"][1] = o["constraints"][0]["items"][0]["acceptable_items"][0] },
    ->(_,p) { p["ap2_profile"] = "unknown" }, ->(_,p) { p["_sd_alg"] = "sha-512" },
    ->(o,_) { o["_sd"] = [hash("mandatory")] }]
  mutations.each do |mutation|
    bad = resign(root, provider, &mutation)
    invalid { S.issue_closed(**closing.merge(root_presentation: bad)) }
    result = M.verify_scoped_constraints(root_presentation: bad, terminal_jws: closed.terminal_jws,
      host_checkout_jws: checkout.jwt, trusted_issuer_public_key_pem: provider.public_to_pem,
      expected_agent_public_key_pem: agent.public_to_pem, trusted_merchant_public_key_pem: merchant.public_to_pem,
      expected_aud: "host", expected_nonce: "nonce", verified_at: NOW, expected_checkout_id: "order",
      expected_merchant_id: "shop", expected_currency: "USD", expected_total_minor: 300, profile_ref: S::PROFILE_REF)
    assert(result.status == :rejected, "signed malformed profile is rejected")
  end
  reordered = ([ds.first] + ds[1...-1].reverse + [""]).join("~")
  invalid { S.present(root_presentation: reordered, terminal_jws: closed.terminal_jws, checkout_jwt: checkout.jwt) }
  fresh = S.issue_closed(**closing.merge(root_presentation: reordered))
  assert(decode(fresh.terminal_jws.split(".")[1])["sd_hash"] == hash(reordered), "reordered presentation requires fresh exact binding")
  mismatched_receipt = M::CheckoutReceipt.verify(jwt: receipt.jwt, closed_sd_jwt: fresh.closed_sd_jwt,
    profile_ref: S::PROFILE_REF, trusted_public_key_pem: merchant.public_to_pem, expected_issuer: "shop",
    not_before: NOW, not_after: NOW + 60, verified_at: NOW)
  assert(!mismatched_receipt.verified?, "Receipt binds final Closed exact bytes")
  calls = 0
  effect = ->(_) { calls += 1; raise "should not sign" }
  too_many = copy(requirements); too_many[0]["acceptable_items"] *= 4
  invalid { S.issue_open(**issue.merge(requirements: too_many, signer: effect)) }
  assert(calls == 0, "invalid issuance preflight before signer")
  # Count limits are individually attainable; byte/depth limits also apply.
  max_requirements = Array.new(8) do |i|
    {"id" => "g#{i}", "quantity" => 1, "acceptable_items" => Array.new(8) { |j| product.call("p#{i}-#{j}") }}
  end
  max_merchants = Array.new(8) { |i| {"id" => "m#{i}", "name" => "M#{i}"} }
  max = S.issue_open(**issue.merge(requirements: max_requirements, allowed_merchants: max_merchants))
  assert(max.root_presentation.split("~").size - 1 == 73, "all 73 disclosures supported")
  minimal = S.select(open_sd_jwt: max.root_presentation, merchant_index: 7, item_indices: Array.new(8) { [7] })
  assert(minimal.root_presentation.split("~").size - 1 == 10, "mandatory content plus eight groups and merchant")
  invalid { S.issue_open(**issue.merge(requirements: max_requirements + [requirements[0]], signer: effect)) }
  invalid { S.issue_open(**issue.merge(allowed_merchants: max_merchants + [seller], signer: effect)) }
  large_groups = copy(max_requirements)
  large_groups.each_with_index { |g,i| g["id"] = "\\" * 255 + i.to_s }
  invalid { S.issue_open(**issue.merge(requirements: large_groups, signer: effect)) }
  large_values = copy(max_requirements)
  large_values.each { |g| g["acceptable_items"].each { |c| c["title"] = "\0" * 512 } }
  invalid { S.issue_open(**issue.merge(requirements: large_values, signer: effect)) }
  assert(calls == 0, "all bounds reject before signer")
  invalid { S.select(open_sd_jwt: root, merchant_index: 0, item_indices: [[0], [0]]) }
  invalid { S.issue_closed(**closing.merge(root_presentation: root + "~")) }
  extra = encode(["AAAAAAAAAAAAAAAAAAAAAA", {"id" => "extra", "title" => "hidden"}])
  invalid { S.issue_closed(**closing.merge(root_presentation: root + extra + "~")) }
  aliased = resign(root, provider) do |o,_|
    o["constraints"][1]["allowed"][1] = o["constraints"][0]["items"][0]["acceptable_items"][0]
  end
  invalid { S.issue_closed(**closing.merge(root_presentation: aliased)) }
  wrong_type = resign(root, provider) { |o,_| o["constraints"][0]["items"][0]["quantity"] = 1.0 }
  invalid { S.issue_closed(**closing.merge(root_presentation: wrong_type)) }
  # A supplied disclosure cannot hide SD syntax inside an allowed leaf, and
  # distinct commitments must never reuse the same salt.
  leaf_marker = decode(ds[1])[1]["constraints"][0]["items"][0]["acceptable_items"][0]["..."]
  leaf_index = ds.index { |d| hash(d) == leaf_marker }
  [->(value) { value[1]["_sd"] = [hash("nested")] },
   ->(value) { value[0] = decode(ds[1])[0] }].each do |change|
    value = decode(ds[leaf_index]); change.call(value)
    replacement = encode(value)
    modified = resign(root, provider) do |o,_|
      o["constraints"][0]["items"][0]["acceptable_items"][0]["..."] = hash(replacement)
    end
    modified = modified.split("~", -1).map { |d| hash(d) == leaf_marker ? replacement : d }.join("~")
    invalid { S.issue_closed(**closing.merge(root_presentation: modified)) }
  end
  # Snapshot Agent before both cnf comparison and terminal signer verification.
  mutable_agent = agent.public_to_pem.dup
  other_agent = OpenSSL::PKey::EC.generate("prime256v1")
  original_jwk = M::RootSignature.method(:public_jwk!)
  reached = false
  M::RootSignature.define_singleton_method(:public_jwk!) do |pem|
    jwk = original_jwk.call(pem)
    if pem == agent.public_to_pem
      reached = true
      mutable_agent.replace(other_agent.public_to_pem)
    end
    jwk
  end
  begin
    invalid { S.issue_closed(**closing.merge(agent_public_key_pem: mutable_agent, signer: signer(other_agent))) }
    assert(reached, "key mutation control reaches cnf")
  ensure
    M::RootSignature.define_singleton_method(:public_jwk!, original_jwk)
  end
  again = S.issue_open(**issue)
  assert(again.root_presentation != full.root_presentation, "fresh random salts")
  salts = full.root_presentation.split("~")[1..].map { |d| decode(d)[0] }
  assert(salts.uniq.size == salts.size && salts.all? { |s| Base64.urlsafe_decode64(s).bytesize == 16 }, "unique 128bit salts")

  # Payment must opt into this Checkout profile and reference exact reducedwire.
  details = M::Payment.details(checkout_jwt: checkout.jwt, trusted_merchant_public_key_pem: merchant.public_to_pem,
    expected_merchant_id: "shop", payment_instrument: {"id" => "card", "type" => "card"})
  cs = [{"type" => "payment.amount_range", "currency" => "USD", "max" => 300},
    {"type" => "payment.allowed_payees", "allowed" => [seller]},
    {"type" => "payment.allowed_payment_instruments", "allowed" => [details["payment_instrument"]]}]
  payment_issue = {open_checkout_sd_jwt: root, constraints: cs, fixed: {}, approved_combinations: [[0,0]], selective: :both,
    agent_public_key_pem: agent.public_to_pem, issued_at: NOW, expires_at: NOW + 60,
    signer: signer(provider), public_key_pem: provider.public_to_pem}
  begin
    M::SelectivePayment.issue_open(**payment_issue)
    raise "old default accepted new Checkout"
  rescue M::SelectivePayment::Invalid
    assert(true, "Payment explicit checkout profile required")
  end
  payment_full = M::SelectivePayment.issue_open(**payment_issue, checkout_profile_ref: S::PROFILE_REF)
  payment_root = M::SelectivePayment.select(open_sd_jwt: payment_full, payee_index: 0, instrument_index: 0)
  payment_closed = M::SelectivePayment.issue_closed(open_presentation: payment_root, payment: details,
    trusted_provider_public_key_pem: provider.public_to_pem, agent_public_key_pem: agent.public_to_pem,
    audience: "host", nonce: "nonce", verified_at: NOW, signer: signer(agent))
  payment_result = M::SelectivePayment.verify(open_presentation: payment_root, closed_sd_jwt: payment_closed.closed_sd_jwt,
    checkout_inputs: raw, expected_payment: details, trusted_provider_public_key_pem: provider.public_to_pem,
    expected_agent_public_key_pem: agent.public_to_pem, expected_audience: "host", expected_nonce: "nonce", verified_at: NOW)
  assert(payment_result.verified?, "integrated selective Checkout and Payment genuine Host")
  if ENV["SELECTIVE_CHECKOUT_EXPORT"]
    File.write(ENV.fetch("SELECTIVE_CHECKOUT_EXPORT"), JSON.generate({full: full.root_presentation, root: root,
      terminal: closed.terminal_jws, checkout: checkout.jwt, raw: raw,
      provider: provider.public_to_pem, agent: agent.public_to_pem, merchant: merchant.public_to_pem,
      requirements: requirements, allowed_merchants: merchants, cart: cart}))
  end
  puts "selective checkout: #{@count} assertions passed"
end
