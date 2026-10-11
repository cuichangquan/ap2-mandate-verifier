# frozen_string_literal: true
require_relative "root_sdjwt_research"

class P11RootSDJWTResearchTest < Minitest::Test
  FIXTURES = ENV.fetch("AP2_P11_FIXTURES") do
    File.expand_path("python_root_sdjwt.json", __dir__)
  end

  def setup
    @f = JSON.parse(File.binread(FIXTURES))
    assert_equal "b4587ac1d055888a73b4b21750973cffba961793", @f.fetch("ap2_commit")
  end

  def root(value, key = @f.fetch("trusted_issuer_public_jwk"))
    AP2RootSDJWTResearch.verify_full_root!(value, trusted_jwk: key)
  end

  def test_01_python_issued_root_with_full_disclosures_is_verified
    mandate = root(@f.fetch("full_sd_jwt"))
    assert_equal "mandate.checkout.open.1", mandate["vct"]
    assert_equal 2, mandate.fetch("constraints").size
    assert_equal @f.fetch("expected_constraint_types").sort,
                 mandate.fetch("constraints").map { |c| c.fetch("type") }.sort
  end

  def test_02_hidden_signed_merchant_constraint_is_rejected
    assert_raises(AP2RootSDJWTResearch::Rejected) { root(@f.fetch("hidden_merchant_sd_jwt")) }
  end

  def test_03_tampered_disclosure_is_rejected
    assert_raises(AP2RootSDJWTResearch::Rejected) { root(@f.fetch("tampered_disclosure_sd_jwt")) }
  end

  def test_04_tampered_signature_is_rejected
    assert_raises(AP2RootSDJWTResearch::Rejected) { root(@f.fetch("tampered_signature_sd_jwt")) }
  end

  def test_05_untrusted_issuer_public_key_is_rejected
    assert_raises(AP2RootSDJWTResearch::Rejected) do
      root(@f.fetch("full_sd_jwt"), @f.fetch("wrong_issuer_public_jwk"))
    end
  end

  def test_06_missing_trusted_issuer_is_rejected
    assert_raises(AP2RootSDJWTResearch::Rejected) { root(@f.fetch("full_sd_jwt"), nil) }
  end

  def test_07_duplicate_disclosure_is_rejected
    assert_raises(AP2RootSDJWTResearch::Rejected) { root(@f.fetch("duplicate_disclosure_sd_jwt")) }
  end

  def test_08_unexpected_disclosure_is_rejected
    assert_raises(AP2RootSDJWTResearch::Rejected) { root(@f.fetch("unsolicited_disclosure_sd_jwt")) }
  end

  def test_09_missing_root_delegate_disclosure_is_rejected
    first = @f.fetch("full_sd_jwt").split("~").first
    assert_raises(AP2RootSDJWTResearch::Rejected) { root(first + "~") }
  end

  def test_10_bad_wire_format_is_rejected
    assert_raises(AP2RootSDJWTResearch::Rejected) { root("not-a-jwt") }
  end
end
