# frozen_string_literal: true
#
# P1-2 two-hop *research-only* checker, NOT a reusable AP2 verifier.
# Reuses P1-1 bounded issuer signature and complete-disclosure checking.
# Checkout JWT is a deliberately UNSIGNED dummy: no purchase permission.
require_relative "../p1_1/root_sdjwt_research"

module AP2TwoHopResearch
  Rejected = AP2RootSDJWTResearch::Rejected

  class << self
    def verify!(chain:, issuer_jwk:, expected_agent_jwk:, expected_aud:, expected_nonce:)
      raise Rejected, "expected audience required" unless expected_aud.is_a?(String) && !expected_aud.empty?
      raise Rejected, "expected nonce required" unless expected_nonce.is_a?(String) && !expected_nonce.empty?
      raise Rejected, "Host expected Agent public key required" unless expected_agent_jwk.is_a?(Hash)
      raise Rejected, "exactly two SD-JWT tokens required" unless chain.is_a?(Array) && chain.length == 2

      root_wire, terminal_wire = chain
      root = AP2RootSDJWTResearch.verify_full_root!(root_wire, trusted_jwk: issuer_jwk)
      agent_jwk = root.fetch("cnf").fetch("jwk")
      raise Rejected, "root holder key not trusted expected Agent" unless public_key?(agent_jwk, expected_agent_jwk)

      # Verify terminal with the public key cryptographically endorsed by Root.
      terminal = AP2RootSDJWTResearch.verify_signed_payload!(
        terminal_wire, trusted_jwk: agent_jwk
      )
      header_b64 = terminal_wire.split("~", 2).first.split(".", 2).first
      header = JSON.parse(Base64.urlsafe_decode64(header_b64 + ("=" * (-header_b64.size % 4))))
      raise Rejected, "terminal typ required" unless header["typ"] == "kb+sd-jwt"
      raise Rejected, "issuer_jwt_hash mode disabled" if terminal.key?("issuer_jwt_hash")
      raise Rejected, "missing sd_hash" unless terminal["sd_hash"].is_a?(String)
      binding = Base64.urlsafe_encode64(Digest::SHA256.digest(root_wire.b), padding: false)
      raise Rejected, "incorrect root sd_hash binding" unless secure_equal?(binding, terminal["sd_hash"])
      raise Rejected, "terminal audience mismatch" unless terminal["aud"] == expected_aud
      raise Rejected, "terminal nonce mismatch" unless terminal["nonce"] == expected_nonce
      now = Time.now.to_i
      raise Rejected, "invalid terminal iat" unless terminal["iat"].is_a?(Integer) &&
        (now - terminal["iat"]).between?(0, 300)

      payloads = terminal.fetch("delegate_payload") { raise Rejected, "missing terminal delegated payload" }
      raise Rejected, "exactly one Closed Mandate required" unless payloads.is_a?(Array) &&
        payloads.length == 1 && payloads.first.is_a?(Hash)
      closed = payloads.first
      raise Rejected, "terminal must be Closed Checkout" unless closed["vct"] == "mandate.checkout.1"
      raise Rejected, "terminal must not delegate again" if closed.key?("cnf")
      raise Rejected, "missing checkout information" unless closed["checkout_jwt"].is_a?(String) &&
        !closed["checkout_jwt"].empty? && closed["checkout_hash"].is_a?(String) &&
        !closed["checkout_hash"].empty?

      # The signed root and terminal are cryptographically connected. This
      # success is NOT Checkout authorization: Merchant JWT signature, inventory,
      # amount, receipt, replay and business rules have NOT been verified.
      { verified_root_vct: root.fetch("vct"), verified_terminal_vct: closed.fetch("vct") }
    rescue JWT::DecodeError, JWT::JWKError, JSON::ParserError, ArgumentError, KeyError => e
      raise Rejected, "invalid signed chain or required context (#{e.class})"
    end

    private

    def public_key?(root_key, expected_key)
      keys = %w[kty crv x y]
      keys.all? { |k| root_key[k].is_a?(String) && root_key[k] == expected_key[k] } &&
        root_key["kty"] == "EC" && root_key["crv"] == "P-256" &&
        (root_key.keys & %w[d p q dp dq qi]).empty?
    end

    def secure_equal?(a, b)
      return false unless b.is_a?(String) && a.bytesize == b.bytesize
      left = a.bytes
      right = b.bytes
      mismatch = 0
      left.each_index { |i| mismatch |= left[i] ^ right[i] }
      mismatch.zero?
    end
  end
end

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
