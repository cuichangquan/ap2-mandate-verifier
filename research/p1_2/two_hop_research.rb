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
      # The outer KB-SD-JWT iat does NOT establish validity of the nested
      # Agent-signed Closed Mandate. Check its own signed iat/exp separately.
      closed_iat, closed_exp = closed.values_at("iat", "exp")
      raise Rejected, "Closed iat/exp required" unless
        closed_iat.is_a?(Integer) && closed_exp.is_a?(Integer)
      raise Rejected, "Closed not currently valid" unless
        closed_iat <= now && now < closed_exp && closed_exp > closed_iat
      raise Rejected, "Closed exceeds research time window" unless
        closed_exp - closed_iat <= 7200
      raise Rejected, "Closed outside issuer Root validity" unless
        closed_iat >= root.fetch("iat") && closed_exp <= root.fetch("exp")
      # AP2 R06: Claims shared by Open and Closed (other than type/vct) must
      # retain their signed values. A shorter but valid Closed exp is NOT
      # a license to override the Issuer's originally authorized claims.
      # Strict research profile: equality of root iat/exp is required; no
      # arbitrary extension fields or extra hops are supported here.
      %w[iat exp].each do |claim|
        raise Rejected, "Closed changed a fixed Open claim" unless
          closed.fetch(claim) == root.fetch(claim)
      end
      other_shared = (root.keys & closed.keys) - %w[vct iat exp]
      raise Rejected, "Closed overwrote a signed Open claim" unless
        other_shared.all? { |claim| root[claim] == closed[claim] }
      raise Rejected, "terminal must not delegate again" if closed.key?("cnf")
      raise Rejected, "missing checkout information" unless closed["checkout_jwt"].is_a?(String) &&
        !closed["checkout_jwt"].empty? && closed["checkout_hash"].is_a?(String) &&
        !closed["checkout_hash"].empty?

      # The signed root and terminal are cryptographically connected. This
      # success is NOT Checkout authorization: Merchant JWT signature, inventory,
      # amount, receipt, replay and business rules have NOT been verified.
      { verified_root_vct: root.fetch("vct"), verified_terminal_vct: closed.fetch("vct"),
        verified_open: root, verified_closed: closed }
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

