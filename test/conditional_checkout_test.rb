# frozen_string_literal: true
require "minitest/autorun"
if ENV["AP2_INSTALLED"] == "1"
  require "ap2_mandate_verifier"
  spec = Gem.loaded_specs.fetch("ap2_mandate_verifier")
  raise "source accidentally loaded" unless spec.version.to_s == "1.0.0" &&
    !File.realpath(spec.full_gem_path).start_with?(File.realpath(File.join(__dir__, "..")) + "/")
else
  require_relative "../lib/ap2_mandate_verifier"
end
require_relative "support/multi_item_fixture"

class ConditionalCheckoutTest < Minitest::Test
  M = AP2MandateVerifier
  C = M::ConditionalCheckout
  F = MultiItemFixture
  def setup
    @keys = Array.new(3) { OpenSSL::PKey::EC.generate("prime256v1") }
    @provider, @agent, @merchant = @keys
    @opening = issue_open
    @checkout = sign_checkout(F.checkout)
  end
  def issue_open(**changes)
    C.issue_open(**{merchant: F.checkout["merchant"], requirements: F.requirements,
      agent_public_key_pem: @agent.public_to_pem, issued_at: F::NOW, expires_at: F::NOW + 600,
      signer: M::CheckoutJWT.es256_signer(private_key: @provider), public_key_pem: @provider.public_to_pem}.merge(changes))
  end
  def sign_checkout(value) = M::CheckoutJWT.sign(checkout: value, profile_ref: C::PROFILE_REF,
    signer: M::CheckoutJWT.es256_signer(private_key: @merchant), public_key_pem: @merchant.public_to_pem).jwt
  def args
    {root_presentation: @opening.root_presentation, checkout_jwt: @checkout,
      trusted_issuer_public_key_pem: @provider.public_to_pem, agent_public_key_pem: @agent.public_to_pem,
      trusted_merchant_public_key_pem: @merchant.public_to_pem, expected_merchant_id: "shop", audience: "host",
      nonce: "nonce", verified_at: F::NOW, signer: M::CheckoutJWT.es256_signer(private_key: @agent)}
  end
  def reject(**changes)
    error = assert_raises(C::Invalid) { C.issue_closed(**args.merge(changes)) }
    assert_equal "invalid conditional checkout information", error.message
    assert_nil error.cause
  end
  def test_public_flow_and_original_receipt_scope
    closed = C.issue_closed(**args)
    restored = C.present(root_presentation: closed.root_presentation.dup,
      terminal_jws: closed.terminal_jws.dup, checkout_jwt: @checkout.dup)
    assert_equal closed.root_presentation, restored.root_presentation
    assert_equal closed.terminal_jws + "~", restored.closed_sd_jwt
    assert restored.frozen? && restored.root_presentation.frozen? && restored.terminal_jws.frozen?
    ref = M::CheckoutReceipt.reference(closed_sd_jwt: restored.closed_sd_jwt, profile_ref: C::PROFILE_REF)
    assert_equal F.hash(closed.terminal_jws + "~"), ref
    refute_equal F.hash(closed.terminal_jws), ref
    refute_equal F.hash(closed.root_presentation + closed.terminal_jws + "~"), ref
    %w[Success Error].each do |status|
      fields = status == "Success" ? {order_id: "order"} : {error: "declined", error_description: "Policy"}
      signed = M::CheckoutReceipt.sign(closed_sd_jwt: restored.closed_sd_jwt, profile_ref: C::PROFILE_REF,
        issuer: "shop", outcome: status, issued_at: F::NOW, **fields,
        signer: M::CheckoutJWT.es256_signer(private_key: @merchant), public_key_pem: @merchant.public_to_pem)
      base = {jwt: signed.jwt, closed_sd_jwt: restored.closed_sd_jwt, profile_ref: C::PROFILE_REF,
        trusted_public_key_pem: @merchant.public_to_pem, expected_issuer: "shop",
        not_before: F::NOW, not_after: F::NOW + 600, verified_at: F::NOW}
      assert M::CheckoutReceipt.verify(**base).verified?
      [{trusted_public_key_pem: @agent.public_to_pem}, {expected_issuer: "other"},
       {not_before: F::NOW + 1}, {closed_sd_jwt: C.issue_closed(**args).closed_sd_jwt}].each do |change|
        # ES256 signatures are randomized, so another issuance is a different reference.
        refute M::CheckoutReceipt.verify(**base.merge(change)).verified?
      end
    end
  end
  def test_authentic_invalid_orders_do_not_reach_agent_signer
    [F.checkout([F.line("x", "A", 1)]), F.checkout([F.line("x", "A", 4)]),
     F.checkout([F.line("x", "Z", 3)]), F.checkout.merge("merchant" => {"id" => "other", "name" => "Other"})].each do |order|
      calls = 0
      reject(checkout_jwt: sign_checkout(order), signer: ->(_) { calls += 1; raise "secret" })
      assert_equal 0, calls
    end
  end
  def test_keys_time_audience_nonce_and_signer
    other = OpenSSL::PKey::EC.generate("prime256v1")
    [{trusted_issuer_public_key_pem: other.public_to_pem}, {agent_public_key_pem: other.public_to_pem},
     {trusted_merchant_public_key_pem: other.public_to_pem}, {expected_merchant_id: "other"},
     {verified_at: F::NOW - 1}, {verified_at: F::NOW + 600}, {verified_at: 1.5},
     {audience: ""}, {nonce: ""}, {signer: M::CheckoutJWT.es256_signer(private_key: other)},
     {signer: ->(_) { raise "secret key nonce raw mandate" }}, {signer: ->(_) { "x" * 64 }}].each { |v| reject(**v) }
    assert C.issue_closed(**args.merge(verified_at: F::NOW + 599))
  end
  def test_open_input_grammar_limits_and_signature
    bad = [[], Array.new(9) { |i| F.requirement("r#{i}", 1, %w[A]) },
      [F.requirement("r", 0, %w[A])], [F.requirement("r", 1_000_001, %w[A])],
      [F.requirement("r", 1, [])], [F.requirement("r", 1, %w[A A])],
      [F.requirement("r", 1, (1..9).map(&:to_s))],
      [F.requirement("r", 1, %w[A]).merge("unknown" => true)],
      [F.requirement("r", 1, %w[A]), F.requirement("r", 1, %w[B])]]
    bad.each { |requirements| assert_raises(C::Invalid) { issue_open(requirements: requirements) } }
    [F::NOW, F::NOW - 1, F::NOW + 7201, 1.0].each do |exp|
      assert_raises(C::Invalid) { issue_open(expires_at: exp) }
    end
    assert issue_open(expires_at: F::NOW + 7200)
    assert_raises(C::Invalid) { issue_open(merchant: {"id" => "shop", "name" => "Shop", "unknown" => 1}) }
    assert_raises(C::Invalid) { issue_open(signer: ->(_) { "x" * 64 }) }
    assert_raises(C::Invalid) { C.issue_open(unknown: "secret") }
    assert_raises(C::Invalid) { C.issue_closed(**args.merge(unknown: true)) }
    assert_raises(C::Invalid) { C.present(unknown: "secret") }
  end
  def test_disclosure_completeness_and_other_open
    parts = @opening.root_presentation.split("~", -1)
    [parts[0...-2].join("~") + "~", (parts[0...-1] + [parts[2], ""]).join("~"),
     @opening.root_presentation.sub(parts[2], parts[2] + "x"), @opening.root_presentation + "x"].each do |wire|
      reject(root_presentation: wire)
    end
    closed = C.issue_closed(**args)
    other = issue_open.root_presentation
    assert_raises(C::Invalid) { C.present(root_presentation: other, terminal_jws: closed.terminal_jws, checkout_jwt: @checkout) }
    assert_raises(C::Invalid) { C.present(root_presentation: closed.root_presentation, terminal_jws: closed.terminal_jws, checkout_jwt: @checkout + "x") }
    # Review regression: a syntactically signed terminal must not turn a bogus
    # Root or an incomplete commitment graph into a restorable presentation.
    ["a~b~c~d~", parts[0...-2].join("~") + "~", (parts[0...-1] + [parts[2], ""]).join("~")].each do |bad_root|
      claims = JSON.parse(Base64.urlsafe_decode64(closed.terminal_jws.split(".")[1]))
      claims["sd_hash"] = F.hash(bad_root)
      terminal = F.sign(@agent, claims, "kb+sd-jwt")
      assert_raises(C::Invalid) { C.present(root_presentation: bad_root, terminal_jws: terminal, checkout_jwt: @checkout) }
    end
  end
  def test_single_and_upper_bound_and_repeated_product_rows
    [[F.requirement("r", 1, %w[A])], (1..8).map { |i| F.requirement("r#{i}", 1, (1..8).map { |j| "p#{j}" }) }].each do |requirements|
      count = requirements.length
      @opening = issue_open(requirements: requirements)
      @checkout = sign_checkout(F.checkout((1..count).map { |i| F.line("l#{i}", count == 1 ? "A" : "p1", 1) }))
      assert C.issue_closed(**args)
    end
    @opening = issue_open(requirements: [F.requirement("r", 1_000_000, %w[A])])
    @checkout = sign_checkout(F.checkout([F.line("max", "A", 1_000_000)]))
    assert C.issue_closed(**args)
  end
  def test_independent_full_verifier_rejects_host_mismatches
    # Existing synthetic issuer supplies independent signed inputs and Host registry.
    model = F.build
    @provider, @agent, @merchant = model[:keys]
    @opening = issue_open(issued_at: F::NOW - 100)
    @checkout = model[:args][:host_checkout_jws]
    closed = C.issue_closed(**args.merge(nonce: "test-nonce"))
    host_inputs = model[:args].merge(root_presentation: closed.root_presentation, terminal_jws: closed.terminal_jws)
    base = host_inputs.slice(:trust, :order, :root_presentation, :host_checkout_jws)
    saved = M::InputBuilder.prepare(**base, challenge_id: "new", nonce: "test-nonce", issuer_id: "host-issuer",
      not_before: F::NOW - 10, not_after: F::NOW + 500)
    host_inputs[:saved_challenge] = saved
    assert M::InputBuilder.verify(**host_inputs).success?
    [args.merge(nonce: "other"), args.merge(audience: "other")].each do |changed|
      wrong = C.issue_closed(**changed)
      refute M::InputBuilder.verify(**host_inputs.merge(terminal_jws: wrong.terminal_jws)).success?
    end
    refute M::InputBuilder.verify(**host_inputs.merge(verified_at: F::NOW + 301)).success?
  end

  def test_large_supported_checkout_uses_terminal_specific_limits
    product = "p" * 256
    requirements = [F.requirement("large", 8, [product])]
    @opening = issue_open(requirements: requirements)
    lines = (1..8).map do |i|
      line = F.line("#{i}" + "r" * 255, product, 1)
      line["item"]["title"] = "t" * 512
      line
    end
    @checkout = sign_checkout(F.checkout(lines))
    assert_operator @checkout.bytesize, :<, 16_384
    closed = C.issue_closed(**args)
    assert_operator closed.terminal_jws.bytesize, :>, 16_384
    assert_operator closed.terminal_jws.bytesize, :<=, 32_768
    assert_equal F.hash(closed.closed_sd_jwt), M::CheckoutReceipt.reference(
      closed_sd_jwt: closed.closed_sd_jwt, profile_ref: C::PROFILE_REF)
    restored = C.present(root_presentation: closed.root_presentation,
      terminal_jws: closed.terminal_jws, checkout_jwt: @checkout)
    assert_equal closed.closed_sd_jwt, restored.closed_sd_jwt
    # Explicit helper bounds controls: never widen JWT/Direct while fixing KB.
    {"JWT" => 12_000, "example+sd-jwt" => 12_000, "kb+sd-jwt" => 24_576}.each do |typ, limit|
      calls = 0
      assert_raises(M::InputValidator::Invalid) do
        M::MerchantSignature.sign!({"data" => "x" * limit},
          ->(_) { calls += 1; raise "should not sign" }, @merchant.public_to_pem, typ: typ)
      end
      assert_equal 0, calls
    end
  end
end
