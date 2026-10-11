# frozen_string_literal: true
require_relative "checkout_binding_research"

class P13CheckoutBindingResearchTest < Minitest::Test
  PATH = ENV.fetch("AP2_P13_FIXTURES") { File.expand_path("merchant_checkout.json", __dir__) }

  def setup
    @f = JSON.parse(File.binread(PATH))
    assert_equal "b4587ac1d055888a73b4b21750973cffba961793", @f.fetch("ap2_commit")
  end

  def verify(terminal: @f.fetch("valid_terminal"),
             host_jwt: @f.fetch("host_checkout_jwt"),
             merchant_key: @f.fetch("trusted_merchant_public_jwk"),
             merchant_id: @f.fetch("expected_merchant_id"),
             checkout_id: @f.fetch("expected_checkout_id"),
             currency: @f.fetch("expected_currency"),
             total_minor: @f.fetch("expected_total_minor"))
    AP2CheckoutBindingResearch.verify!(
      chain: [@f.fetch("root_open_sdjwt"), terminal],
      issuer_jwk: @f.fetch("trusted_issuer_public_jwk"),
      expected_agent_jwk: @f.fetch("expected_agent_public_jwk"),
      expected_aud: @f.fetch("expected_aud"),
      expected_nonce: @f.fetch("expected_nonce"),
      merchant_jwk: merchant_key, host_checkout_jwt: host_jwt,
      expected_checkout_id: checkout_id, expected_merchant_id: merchant_id,
      expected_currency: currency, expected_total_minor: total_minor
    )
  end

  def rejection(terminal)
    assert_raises(AP2CheckoutBindingResearch::Rejected) { verify(terminal: terminal) }
  end

  def business_rejection(name)
    # Using the same Merchant-signed JWT as Closed avoids short-circuiting at
    # Host JWT byte inequality: check the actual authenticated business rule.
    assert_raises(AP2CheckoutBindingResearch::Rejected) do
      verify(terminal: @f.fetch("bad_terminals").fetch(name),
             host_jwt: @f.fetch("variant_checkout_jwts").fetch(name))
    end
  end

  def test_01_genuine_merchant_jwt_and_signed_2hop_is_valid_under_strict_profile
    result = verify
    assert_equal "checkout-001", result.fetch(:checkout_id)
    assert_equal "merchant-allowed", result.fetch(:merchant_id)
    assert_equal 2400, result.fetch(:amount_minor)
    assert_match(/\A[A-Za-z0-9_-]{43}\z/, result.fetch(:checkout_sha256))
  end

  def test_02_agent_signed_closed_but_wrong_checkout_hash_rejected
    rejection(@f.fetch("bad_terminals").fetch("incorrect_checkout_hash"))
  end

  def test_03_agent_signed_closed_missing_checkout_hash_rejected
    rejection(@f.fetch("bad_terminals").fetch("missing_checkout_hash"))
  end

  def test_04_signed_wrong_merchant_checkout_rejected
    business_rejection("disallowed_merchant")
  end

  def test_05_signed_wrong_sku_rejected
    business_rejection("wrong_sku")
  end

  def test_06_signed_wrong_quantity_rejected
    business_rejection("wrong_quantity")
  end

  def test_07_extra_cart_item_rejected_even_if_required_item_present
    business_rejection("extra_item")
  end

  def test_08_mismatched_totals_rejected
    business_rejection("wrong_total")
  end

  def test_09_completed_checkout_status_rejected
    business_rejection("wrong_status")
  end

  def test_10_checkout_signed_by_untrusted_merchant_key_rejected
    business_rejection("wrong_merchant_signer")
  end

  def test_11_host_original_jwt_is_missing
    assert_raises(AP2CheckoutBindingResearch::Rejected) { verify(host_jwt: nil) }
  end

  def test_12_host_original_jwt_is_a_different_valid_signed_checkout
    assert_raises(AP2CheckoutBindingResearch::Rejected) do
      verify(host_jwt: @f.fetch("other_signed_checkout_jwt"))
    end
  end

  def test_13_missing_merchant_trust_key_rejected
    assert_raises(AP2CheckoutBindingResearch::Rejected) { verify(merchant_key: nil) }
  end

  def test_14_wrong_merchant_public_key_rejected
    assert_raises(AP2CheckoutBindingResearch::Rejected) do
      verify(merchant_key: @f.fetch("untrusted_merchant_public_jwk"))
    end
  end

  def test_15_wrong_expected_checkout_id_rejected
    assert_raises(AP2CheckoutBindingResearch::Rejected) { verify(checkout_id: "different-checkout") }
  end

  def test_16_wrong_expected_merchant_id_rejected
    assert_raises(AP2CheckoutBindingResearch::Rejected) { verify(merchant_id: "merchant-denied") }
  end

  def test_17_wrong_expected_currency_rejected
    assert_raises(AP2CheckoutBindingResearch::Rejected) { verify(currency: "JPY") }
  end

  def test_18_wrong_expected_total_rejected
    assert_raises(AP2CheckoutBindingResearch::Rejected) { verify(total_minor: 2399) }
  end
end
