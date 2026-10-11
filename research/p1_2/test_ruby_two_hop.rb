# frozen_string_literal: true
require_relative "two_hop_research"

class P12TwoHopResearchTest < Minitest::Test
  FIXTURES = ENV.fetch("AP2_P12_FIXTURES") { File.expand_path("two_hop_generated.json", __dir__) }

  def setup
    @f = JSON.parse(File.binread(FIXTURES))
    assert_equal "b4587ac1d055888a73b4b21750973cffba961793", @f.fetch("ap2_commit")
  end

  def chain(root: @f.fetch("root_open_sdjwt"), terminal: @f.fetch("terminal_closed_sdjwt"),
            issuer: @f.fetch("trusted_issuer_public_jwk"),
            agent: @f.fetch("expected_agent_public_jwk"),
            aud: @f.fetch("expected_aud"), nonce: @f.fetch("expected_nonce"))
    AP2TwoHopResearch.verify!(
      chain: [root, terminal], issuer_jwk: issuer, expected_agent_jwk: agent,
      expected_aud: aud, expected_nonce: nonce
    )
  end

  def test_01_genuine_open_to_closed_is_cryptographically_bound
    result = chain
    assert_equal "mandate.checkout.open.1", result.fetch(:verified_root_vct)
    assert_equal "mandate.checkout.1", result.fetch(:verified_terminal_vct)
  end

  def test_02_wrong_agent_signer_rejected
    assert_raises(AP2TwoHopResearch::Rejected) { chain(terminal: @f.fetch("wrong_holder_terminal")) }
  end

  def test_03_terminal_bound_to_different_root_rejected
    assert_raises(AP2TwoHopResearch::Rejected) { chain(terminal: @f.fetch("wrong_root_binding_terminal")) }
  end

  def test_04_wrong_terminal_audience_rejected
    assert_raises(AP2TwoHopResearch::Rejected) { chain(terminal: @f.fetch("wrong_aud_terminal")) }
  end

  def test_05_wrong_terminal_nonce_rejected
    assert_raises(AP2TwoHopResearch::Rejected) { chain(terminal: @f.fetch("wrong_nonce_terminal")) }
  end

  def test_06_missing_expected_audience_rejected
    assert_raises(AP2TwoHopResearch::Rejected) { chain(aud: nil) }
  end

  def test_07_missing_expected_nonce_rejected
    assert_raises(AP2TwoHopResearch::Rejected) { chain(nonce: nil) }
  end

  def test_08_missing_expected_agent_key_rejected
    assert_raises(AP2TwoHopResearch::Rejected) { chain(agent: nil) }
  end

  def test_09_wrong_host_agent_key_rejected
    assert_raises(AP2TwoHopResearch::Rejected) { chain(agent: @f.fetch("wrong_agent_public_jwk")) }
  end

  def test_10_issuer_jwt_hash_mode_not_supported
    assert_raises(AP2TwoHopResearch::Rejected) { chain(terminal: @f.fetch("issuer_jwt_hash_terminal")) }
  end

  def test_11_intermediate_hop_not_allowed
    assert_raises(AP2TwoHopResearch::Rejected) { chain(terminal: @f.fetch("intermediate_terminal")) }
  end

  def test_12_tampered_agent_signature_rejected
    assert_raises(AP2TwoHopResearch::Rejected) { chain(terminal: @f.fetch("tampered_terminal_signature")) }
  end

  def test_13_three_hops_rejected_even_with_valid_pair_prefix
    f = @f
    assert_raises(AP2TwoHopResearch::Rejected) do
      AP2TwoHopResearch.verify!(
        chain: [f.fetch("root_open_sdjwt"), f.fetch("terminal_closed_sdjwt"), f.fetch("terminal_closed_sdjwt")],
        issuer_jwk: f.fetch("trusted_issuer_public_jwk"),
        expected_agent_jwk: f.fetch("expected_agent_public_jwk"),
        expected_aud: f.fetch("expected_aud"), expected_nonce: f.fetch("expected_nonce")
      )
    end
  end

  def test_14_root_issuer_wrong_rejected
    assert_raises(AP2TwoHopResearch::Rejected) { chain(issuer: @f.fetch("wrong_agent_public_jwk")) }
  end

  def test_15_missing_root_merchant_disclosure_rejected
    root = @f.fetch("root_open_sdjwt")
    segments = root.split("~")
    candidates = segments[1..].reject(&:empty?)
    merchant = candidates.find do |v|
      decoded = JSON.parse(Base64.urlsafe_decode64(v + ("=" * (-v.size % 4))))
      decoded.is_a?(Array) && decoded.size == 2 && decoded[1].is_a?(Hash) &&
        decoded[1]["type"] == "checkout.allowed_merchants"
    end
    refute_nil merchant
    stripped = ([segments.first] + candidates.reject { |v| v == merchant } + [""]).join("~")
    assert_raises(AP2TwoHopResearch::Rejected) { chain(root: stripped) }
  end
end
