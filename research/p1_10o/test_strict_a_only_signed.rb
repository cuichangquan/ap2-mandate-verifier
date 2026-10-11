# frozen_string_literal: true
# P1-10o isolated, synthetic, A-only signed-fixture evidence.
# EXACTLY AN-P01 and AN-N01..N07. No public API, Host ALLOW, payment,
# nonce consumption, durable Authority, Gem or production claims.
require_relative "../p1_3/checkout_binding_research"
require "minitest/autorun"
require "json"

module P110O
  PINNED_AP2 = "b4587ac1d055888a73b4b21750973cffba961793"
  MAIN = JSON.parse(File.binread(ENV.fetch("AP2_P110O_FIXTURES")))
  CHECKOUT = JSON.parse(File.binread(ENV.fetch("AP2_P110O_CHECKOUT_FIXTURES")))
  raise "wrong signed research fixture AP2 SHA" unless
    [MAIN, CHECKOUT].all? { |f| f.fetch("ap2_commit") == PINNED_AP2 }

  RESULTS = []
  class << self
    def record(id, classification, note)
      RESULTS << { id: id, classification: classification, note: note }
    end
  end
end

class AP2StrictAOnlyAcceptanceResearchTest < Minitest::Test
  Rejected = AP2RootSDJWTResearch::Rejected

  def verify(f=P110O::MAIN, root: f.fetch("root_open_sdjwt"),
             terminal: f.fetch("valid_terminal"),
             jwt: f.fetch("checkout_jwts", {}).fetch("valid", f["host_checkout_jwt"]),
             issuer: f.fetch("trusted_issuer_public_jwk"),
             agent: f.fetch("expected_agent_public_jwk"),
             merchant: f.fetch("trusted_merchant_public_jwk"),
             aud: f.fetch("expected_aud"), nonce: f.fetch("expected_nonce"))
    AP2CheckoutBindingResearch.verify!(
      chain: [root, terminal], issuer_jwk: issuer, expected_agent_jwk: agent,
      expected_aud: aud, expected_nonce: nonce,
      merchant_jwk: merchant, host_checkout_jwt: jwt,
      expected_checkout_id: f.fetch("expected_checkout_id"),
      expected_merchant_id: f.fetch("expected_merchant_id"),
      expected_currency: f.fetch("expected_currency"),
      expected_total_minor: f.fetch("expected_total_minor")
    )
  end

  def reject!(*args, **kwargs)
    assert_raises(Rejected) { verify(*args, **kwargs) }
  end

  def p15(name)
    P110O::MAIN.fetch("terminal_variants").fetch(name)
  end

  def test_an_p01_positive_known_issuer_two_hop_fully_disclosed
    result = verify
    assert_equal "checkout-001", result.fetch(:checkout_id)
    assert_equal "merchant-allowed", result.fetch(:merchant_id)
    assert_equal 2400, result.fetch(:amount_minor)
    refute result.key?(:allow), "Verified evidence MUST NOT grant business ALLOW"
    refute result.key?(:payment), "Cryptographic evidence is not payment"
    P110O.record("AN-P01", "LIMITED_POSITIVE", "synthetic fixed-layout signed two-hop evidence; no ALLOW")
  end

  def test_an_n01_hidden_or_extra_issuer_signed_authority
    f = P110O::MAIN
    reject!(root: f.fetch("root_hidden_merchant"))
    reject!(root: f.fetch("hidden_extra_authority_root"))
    reject!(root: f.fetch("extra_authority_root"))
    P110O.record("AN-N01", "REJECTED", "known signed fixture hides Merchant/third constraint, or adds unsupported authority")
  end

  def test_an_n02_wrong_or_untrusted_issuer_and_merchant
    f = P110O::MAIN
    reject!(issuer: f.fetch("wrong_issuer_public_jwk"))
    reject!(issuer: nil)
    reject!(merchant: nil)
    P110O.record("AN-N02", "REJECTED", "untrusted issuer key or absent trusted key cannot become proof")
  end

  def test_an_n03_wrong_agent_unsupported_hash_or_hop
    reject!(terminal: p15("wrong_agent_signature"))
    reject!(terminal: p15("unsupported_hash_mode"))
    f = P110O::MAIN
    # The entry point is deliberately exactly 2hop. Even all-signed supplied
    # extra elements must not be silently collapsed into a supported path.
    assert_raises(Rejected) do
      AP2TwoHopResearch.verify!(
        chain: [f.fetch("root_open_sdjwt"), f.fetch("valid_terminal"), f.fetch("valid_terminal")],
        issuer_jwk: f.fetch("trusted_issuer_public_jwk"),
        expected_agent_jwk: f.fetch("expected_agent_public_jwk"),
        expected_aud: f.fetch("expected_aud"), expected_nonce: f.fetch("expected_nonce")
      )
    end
    P110O.record("AN-N03", "REJECTED", "wrong holder signature, unsupported hash mode, three signed tokens")
  end

  def test_an_n04_challenge_time_and_signed_in_window_claim_drift
    f = P110O::MAIN
    reject!(nonce: "wrong-host-challenge")
    reject!(nonce: "")
    reject!(aud: "wrong-merchant")
    reject!(terminal: p15("expired_closed"))
    reject!(terminal: p15("future_closed_iat"))
    reject!(root: f.fetch("expired_root"))
    # Codex P1 in PR #35: signed Changed Closed exp is still INSIDE Root
    # validity. Mere time-window containment must NOT accept overwritten
    # fixed claims. Assert the exact reason to distinguish from expiry errors.
    err = assert_raises(Rejected) do
      verify(terminal: p15("changed_closed_exp_in_window"))
    end
    assert_match(/Closed changed a fixed Open claim/, err.message)
    # Also reject an Issuer-signed extra Open fixed claim when the Agent
    # omits it from its otherwise valid signed Closed. The source layout
    # itself is unsupported, not merely a mismatch on intersecting keys.
    omitted = assert_raises(Rejected) do
      verify(root: f.fetch("signed_extra_fixed_open_root"),
             terminal: f.fetch("signed_extra_fixed_open_terminal"))
    end
    assert_match(/unsupported signed Open claim layout/, omitted.message)
    P110O.record("AN-N04", "REJECTED", "signed in-window exp alteration AND omitted issuer-fixed Open claim rejected; challenge/time rejects")
  end

  def test_an_n05_strict_jose_json_and_resource_bounds
    f = P110O::MAIN
    %w[duplicate_merchant_id duplicate_header_alg merchant_header_wrong_typ
       merchant_header_jku large_checkout deep_checkout].each do |name|
      reject!(terminal: p15(name), jwt: f.fetch("checkout_jwts").fetch(name))
    end
    reject!(root: f.fetch("oversized_root"))
    P110O.record("AN-N05", "REJECTED", "signed duplicate keys/headers, typ/jku, size and deep JSON rejected")
  end

  def test_an_n06_checkout_jwt_hash_signer_and_strict_cart
    f = P110O::CHECKOUT
    jwt = f.fetch("host_checkout_jwt")
    # Signed terminal and Host JWT from the SAME alternate synthetic issuer.
    reject!(f, terminal: f.fetch("bad_terminals").fetch("incorrect_checkout_hash"),
            jwt: jwt)
    reject!(f, terminal: f.fetch("bad_terminals").fetch("wrong_merchant_signer"),
            jwt: f.fetch("variant_checkout_jwts").fetch("wrong_merchant_signer"))
    reject!(f, jwt: f.fetch("other_signed_checkout_jwt"))
    %w[wrong_quantity disallowed_merchant wrong_sku extra_item wrong_total].each do |name|
      reject!(f, terminal: f.fetch("bad_terminals").fetch(name),
              jwt: f.fetch("variant_checkout_jwts").fetch(name))
    end
    P110O.record("AN-N06", "REJECTED", "signed Checkout hash/signer/wire, merchant/SKU/quantity/totals all checked")
  end

  def test_an_n07_stateless_repeat_is_host_boundary_not_payment
    first = verify
    second = verify
    assert_equal first.fetch(:checkout_sha256), second.fetch(:checkout_sha256)
    assert_equal first, second
    refute first.key?(:allow)
    refute second.key?(:receipt)
    P110O.record("AN-N07", "HOST_BOUNDARY", "same valid signature verifies twice; atomic nonce/ALLOW unimplemented")
  end
end

Minitest.after_run do
  path = ENV["AP2_P110O_RESULTS"]
  next unless path
  report = {
    pinned_ap2: P110O::PINNED_AP2,
    scope: "synthetic two-hop fixed-issuer A-only Ruby lab; no Host/business ALLOW",
    count_recorded: P110O::RESULTS.length,
    cases: P110O::RESULTS.sort_by { |r| r.fetch(:id) },
    evidence_boundary: "AN-N07 is HOST_BOUNDARY, not a replay-defense PASS",
    status: "TEST_OUTCOMES_IN_LOG; NEVER production safety GO"
  }
  File.binwrite(path, JSON.pretty_generate(report) + "\n")
end
