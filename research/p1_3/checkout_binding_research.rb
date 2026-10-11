# frozen_string_literal: true
#
# P1-3: deliberately strict offline Checkout JWT/constraint research spike.
# Not a public AP2 verifier, not authorization, and not safe for real payments.
require_relative "../p1_2/two_hop_research"

module AP2CheckoutBindingResearch
  Rejected = AP2RootSDJWTResearch::Rejected

  class << self
    def verify!(chain:, issuer_jwk:, expected_agent_jwk:, expected_aud:, expected_nonce:,
                merchant_jwk:, host_checkout_jwt:, expected_checkout_id:,
                expected_merchant_id:, expected_currency:, expected_total_minor:)
      raise Rejected, "trusted merchant public key required" unless merchant_jwk.is_a?(Hash)
      raise Rejected, "Host signed Checkout JWT required" unless host_checkout_jwt.is_a?(String) &&
        host_checkout_jwt.bytesize.between?(1, 16_384)
      raise Rejected, "Host checkout id required" unless present_string?(expected_checkout_id)
      raise Rejected, "Host merchant id required" unless present_string?(expected_merchant_id)
      raise Rejected, "Host currency required" unless present_string?(expected_currency)
      raise Rejected, "Host expected amount required" unless expected_total_minor.is_a?(Integer) &&
        expected_total_minor.positive?

      result = AP2TwoHopResearch.verify!(
        chain: chain, issuer_jwk: issuer_jwk,
        expected_agent_jwk: expected_agent_jwk, expected_aud: expected_aud,
        expected_nonce: expected_nonce
      )
      open = result.fetch(:verified_open)
      closed = result.fetch(:verified_closed)

      signed_checkout = closed.fetch("checkout_jwt")
      raise Rejected, "Closed Checkout JWT differs from Host original" unless secure_equal?(signed_checkout, host_checkout_jwt)
      digest = Base64.urlsafe_encode64(Digest::SHA256.digest(host_checkout_jwt.b), padding: false)
      raise Rejected, "Closed checkout_hash does not bind Host JWT" unless
        secure_equal?(closed.fetch("checkout_hash"), digest)

      # Parse the original signed JOSE/header and Checkout JSON with strict
      # duplicate-key detection; preserve compact bytes for JWT verification
      # and for the Host/JWT and checkout_hash binding above.
      header, strict_checkout = AP2StrictJSONResearch.validate_signed_jws_json!(host_checkout_jwt)
      raise Rejected, "only merchant ES256 JWT allowed" unless header.is_a?(Hash) &&
        header["alg"] == "ES256"
      raise Rejected, "unsupported Merchant JWT typ" unless header["typ"] == "JWT"
      raise Rejected, "JWT headers cannot choose trust keys" if (%w[jwk jku x5c x5u crit] & header.keys).any?
      merchant_public = JWT::JWK.import(merchant_jwk).public_key
      checkout, = JWT.decode(host_checkout_jwt, merchant_public, true, { algorithms: ["ES256"] })
      raise Rejected, "checkout JSON expected" unless checkout.is_a?(Hash) &&
        checkout == strict_checkout
      # Strict ONE-LINE RESEARCH PROFILE, not a general UCP/AP2 schema:
      # reject unrecognized data instead of accidentally ignoring important
      # monetary/authority semantics hidden in new fields.
      require_exact_keys!(checkout, %w[id merchant line_items status currency totals links])
      raise Rejected, "wrong Host checkout id" unless checkout["id"] == expected_checkout_id
      raise Rejected, "unsupported Checkout status" unless checkout["status"] == "ready_for_complete"
      raise Rejected, "wrong checkout currency" unless checkout["currency"] == expected_currency

      merchant = checkout.fetch("merchant")
      require_exact_keys!(merchant, %w[id name])
      raise Rejected, "wrong checkout merchant" unless merchant.is_a?(Hash) &&
        merchant["id"] == expected_merchant_id && present_string?(merchant["name"])

      # Research-only fixed issuer profile: one allowed Merchant, one required
      # SKU, exactly one cart line. AP2's general max-flow/multi-item constraints
      # are intentionally NOT implemented.
      constraints = open.fetch("constraints")
      raise Rejected, "exactly two constraints required" unless constraints.is_a?(Array) && constraints.size == 2
      allowed = constraints.find { |c| c["type"] == "checkout.allowed_merchants" }
      required = constraints.find { |c| c["type"] == "checkout.line_items" }
      raise Rejected, "missing constraints" unless allowed && required
      # P1-10r: fixed Issuer research profile, not the general AP2 schema.
      # Unknown NESTED signed authority fields cannot be silently ignored.
      # No wildcard/forward compatibility is claimed by this offline spike.
      require_exact_constraint_keys!(allowed, %w[allowed type])
      require_exact_constraint_keys!(required, %w[items type])
      merchant_allow = allowed.fetch("allowed")
      raise Rejected, "unsupported multiple Merchant rules" unless merchant_allow.is_a?(Array) &&
        merchant_allow.length == 1 && merchant_allow.first.is_a?(Hash) &&
        merchant_allow.first["id"] == expected_merchant_id
      require_exact_constraint_keys!(merchant_allow.first, %w[id name])
      requirements = required.fetch("items")
      raise Rejected, "unsupported multiple required lines" unless requirements.is_a?(Array) &&
        requirements.size == 1
      requirement = requirements.first
      require_exact_constraint_keys!(requirement, %w[acceptable_items id quantity])
      accepted = requirement.fetch("acceptable_items")
      raise Rejected, "unsupported multiple SKU alternatives" unless accepted.is_a?(Array) &&
        accepted.size == 1 && accepted.first.is_a?(Hash) &&
        present_string?(accepted.first["id"]) && present_string?(accepted.first["title"])
      require_exact_constraint_keys!(accepted.first, %w[id title])
      expected_quantity = requirement.fetch("quantity")
      raise Rejected, "invalid required quantity" unless expected_quantity.is_a?(Integer) && expected_quantity.positive?

      lines = checkout.fetch("line_items")
      raise Rejected, "only one cart line supported" unless lines.is_a?(Array) && lines.size == 1
      line = lines.first
      require_exact_keys!(line, %w[id item quantity totals])
      product = line.fetch("item")
      require_exact_keys!(product, %w[id title price])
      raise Rejected, "invalid cart product" unless product.is_a?(Hash) &&
        product["id"] == accepted.first["id"] && product["title"] == accepted.first["title"]
      raise Rejected, "cart quantity violates mandate" unless line["quantity"] == expected_quantity
      price = product.fetch("price")
      raise Rejected, "invalid unit price" unless price.is_a?(Integer) && price.positive?
      line_amount = price * expected_quantity
      raise Rejected, "Host expected total mismatch" unless line_amount == expected_total_minor

      # Equal subtotal/total are intentional restrictions for this no-tax,
      # one-item offline fixture; not general AP2 Checkout price semantics.
      validate_totals!(line.fetch("totals"), line_amount)
      validate_totals!(checkout.fetch("totals"), line_amount)

      # Returns checked facts ONLY. No authorization, payment or receipt.
      { checkout_id: checkout.fetch("id"), merchant_id: merchant.fetch("id"),
        checkout_sha256: digest, amount_minor: line_amount }
    rescue JWT::DecodeError, JWT::JWKError, JSON::ParserError, ArgumentError, KeyError,
           TypeError, RangeError => e
      raise Rejected, "invalid Checkout proof or Host context (#{e.class})"
    end

    private

    def present_string?(v)
      v.is_a?(String) && !v.empty?
    end

    def require_exact_constraint_keys!(object, keys)
      raise Rejected, "unsupported or missing signed Constraint profile fields" unless
        object.is_a?(Hash) && object.keys.sort == keys.sort
    end

    def require_exact_keys!(object, keys)
      raise Rejected, "unsupported or missing Checkout profile fields" unless
        object.is_a?(Hash) && object.keys.sort == keys.sort
    end

    def secure_equal?(a, b)
      return false unless a.is_a?(String) && b.is_a?(String) &&
        a.bytesize == b.bytesize
      diff = 0
      a.bytes.zip(b.bytes) { |left, right| diff |= left ^ right }
      diff.zero?
    end

    def validate_totals!(totals, expected)
      raise Rejected, "unsupported Checkout total shape" unless totals.is_a?(Array) &&
        totals.size == 2 && totals.all? { |v| v.is_a?(Hash) }
      totals.each { |t| require_exact_keys!(t, %w[type amount]) }
      by_type = totals.to_h { |t| [t["type"], t["amount"]] }
      raise Rejected, "Checkout subtotal/total inconsistent" unless
        by_type.keys.sort == %w[subtotal total] &&
        by_type.values.all? { |v| v.is_a?(Integer) && v == expected }
    end
  end
end
