# frozen_string_literal: true

module AP2MandateVerifier
  # Fixed DC04 Root -> one inline Closed terminal -> Host Merchant JWT only.
  # No dynamic trust lookup, extra hops, constraint evaluation or Evidence.
  module PurchaseBinding
    CORE_INSTANCE_OF = Object.instance_method(:instance_of?)
    MAX_EPOCH = 4_102_444_800
    class Rejected < RootSignature::Rejected; end

    def self.check!(root_presentation:, terminal_jws:, host_checkout_jws:,
                   **context)
      verified_purchase!(root_presentation: root_presentation, terminal_jws: terminal_jws,
                         host_checkout_jws: host_checkout_jws, **context)
      nil
    end

    # Internal handoff after every signature, closure and binding check.
    def self.verified_purchase!(**inputs)
      verified_details!(**inputs).values_at(:open, :checkout)
    end

    # Internal handoff only after all existing signature and binding checks.
    def self.verified_details!(root_presentation:, terminal_jws:, host_checkout_jws:,
                   trusted_issuer_public_key_pem:, expected_agent_public_key_pem:,
                   trusted_merchant_public_key_pem:, expected_aud:, expected_nonce:,
                   verified_at:, expected_checkout_id:, expected_merchant_id:)
      # Snapshot every caller-owned byte string before starting cryptography.
      root_wire = InputValidator.snapshot!(root_presentation)
      terminal_wire = InputValidator.snapshot!(terminal_jws, max_bytes: 32_768)
      checkout_wire = context!(host_checkout_jws, 16_384)
      issuer_pem = context!(trusted_issuer_public_key_pem, 1_024)
      agent_pem = context!(expected_agent_public_key_pem, 1_024)
      merchant_pem = context!(trusted_merchant_public_key_pem, 1_024)
      aud = context!(expected_aud, 512)
      nonce = context!(expected_nonce, 512)
      checkout_id = context!(expected_checkout_id, 256)
      merchant_id = context!(expected_merchant_id, 256)
      raise RootSignature::Unavailable, :purchase_context_unavailable unless integer?(verified_at) &&
        verified_at.between?(0, MAX_EPOCH)

      root = RootDisclosures.verified_root!(root_wire, issuer_pem)
      open = root.fetch("delegate_payload").first
      exact!(open, %w[cnf constraints exp iat vct])
      raise Rejected, :unsupported_purchase_profile unless open["vct"] == "mandate.checkout.open.1"
      times!(open, verified_at)
      exact!(open["cnf"], %w[jwk])
      exact!(open["cnf"]["jwk"], %w[kty crv x y])
      raise Rejected, :agent_key_mismatch unless open["cnf"]["jwk"] == RootSignature.public_jwk!(agent_pem)

      terminal = RootSignature.verified_payload!(terminal_wire, agent_pem, expected_typ: "kb+sd-jwt")
      exact!(terminal, %w[aud delegate_payload iat nonce sd_hash])
      raise Rejected, :root_binding_mismatch unless terminal["sd_hash"] == hash(root_wire)
      raise Rejected, :audience_mismatch unless terminal["aud"] == aud
      raise Rejected, :nonce_mismatch unless terminal["nonce"] == nonce
      raise Rejected, :invalid_purchase_time unless integer?(terminal["iat"]) &&
        terminal["iat"].between?([verified_at - 300, open["iat"]].max, verified_at) &&
        terminal["iat"] < open["exp"]
      payloads = terminal["delegate_payload"]
      raise Rejected, :unsupported_purchase_profile unless payloads.instance_of?(Array) && payloads.size == 1
      closed = payloads.first
      exact!(closed, %w[checkout_hash checkout_jwt exp iat vct])
      raise Rejected, :unsupported_purchase_profile unless closed["vct"] == "mandate.checkout.1"
      times!(closed, verified_at)
      # R06 fixed shared claims: no shortening or extending Issuer iat/exp.
      raise Rejected, :delegation_claim_mismatch unless closed["iat"] == open["iat"] && closed["exp"] == open["exp"]
      raise Rejected, :checkout_binding_mismatch unless closed["checkout_jwt"] == checkout_wire &&
        closed["checkout_hash"] == hash(checkout_wire)

      checkout = RootSignature.verified_payload!(checkout_wire, merchant_pem, expected_typ: "JWT", max_bytes: 16_384)
      exact!(checkout, %w[currency id line_items links merchant status totals])
      exact!(checkout["merchant"], %w[id name])
      raise Rejected, :checkout_identity_mismatch unless checkout["id"] == checkout_id &&
        checkout["merchant"]["id"] == merchant_id
      raise Rejected, :unsupported_purchase_profile unless checkout["status"] == "ready_for_complete"
      # Item/amount/currency/links and Root constraints are stage6, not certified.
      {open: open, closed: closed, terminal: terminal, checkout: checkout}
    end

    def self.context!(source, limit)
      value = InputValidator.snapshot!(source, max_bytes: limit)
      raise RootSignature::Unavailable, :purchase_context_unavailable if value.empty?
      value
    rescue InputValidator::Invalid
      raise RootSignature::Unavailable, :purchase_context_unavailable
    end

    def self.times!(claims, now)
      iat, exp = claims.values_at("iat", "exp")
      raise Rejected, :invalid_purchase_time unless integer?(iat) && integer?(exp) &&
        iat.between?(0, MAX_EPOCH) && exp.between?(0, MAX_EPOCH) &&
        iat <= now && now < exp && exp > iat && exp - iat <= 7_200
    end

    def self.exact!(value, keys)
      raise Rejected, :unsupported_purchase_profile unless value.instance_of?(Hash) && value.keys.sort == keys.sort
    end
    def self.integer?(value) = CORE_INSTANCE_OF.bind_call(value, Integer)
    def self.hash(wire) = Base64.urlsafe_encode64(Digest::SHA256.digest(wire), padding: false)
    private_class_method :context!, :times!, :exact!, :integer?, :hash
    private_constant :CORE_INSTANCE_OF
  end
end
