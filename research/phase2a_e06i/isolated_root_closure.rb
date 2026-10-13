# frozen_string_literal: true
# IMPORTANT: Forked, frozen-layout research-only extraction to avoid importing
# the original P1-1 dependency which requires minitest/autorun at load time.
# Original implementation under research/phase2a_dc04/fixed_issuer_verifier.rb.
# Deliberately NOT validated by executing Ruby, fixtures, or CI at approval A.
#
# Phase 2-A E06-I/A isolated copy of DC04 fixed-Issuer signed-wire research ONLY.
# Not a general SD-JWT parser, Gem API, checkout authorization, or payment gate.
# Does not change P1-1's deliberately unsupported nested positions.
require "jwt"
require "set"
require "json"
require "base64"
require "digest"
require_relative "../shared/strict_json_research"

module AP2E06IRootClosure
  class Rejected < StandardError; end
  PINNED_AP2 = "b4587ac1d055888a73b4b21750973cffba961793"
  PROFILE = "dc04-v1-exact-three-array-commitments"
  ALLOWED_PATHS = [
    ["delegate_payload", 0],
    ["delegate_payload", 0, "disclosed", "constraints", 1, "allowed", 0],
    ["delegate_payload", 0, "disclosed", "constraints", 0, "items", 0, "acceptable_items", 0]
  ].freeze

  class << self
    def verify_full_root!(wire, trusted_jwk:)
      signed = verify_signed_payload!(wire, trusted_jwk: trusted_jwk)
      mandate = signed.fetch("delegate_payload").fetch(0)
      exact_keys!(mandate, %w[cnf constraints exp iat vct])
      raise Rejected, "unsupported Open mandate type" unless mandate["vct"] == "mandate.checkout.open.1"

      cnf = mandate.fetch("cnf")
      exact_keys!(cnf, %w[jwk])
      agent = cnf.fetch("jwk")
      exact_keys!(agent, %w[crv kty x y])
      raise Rejected, "unsupported Agent public key" unless agent["kty"] == "EC" &&
        agent["crv"] == "P-256" && %w[x y].all? { |k| agent[k].is_a?(String) && !agent[k].empty? }

      now = Time.now.to_i
      iat, exp = mandate.values_at("iat", "exp")
      raise Rejected, "invalid Open validity" unless iat.is_a?(Integer) &&
        exp.is_a?(Integer) && iat <= now && now < exp && exp - iat <= 7200

      constraints = mandate.fetch("constraints")
      raise Rejected, "unsupported constraint order/cardinality" unless
        constraints.is_a?(Array) && constraints.size == 2
      required, allowed = constraints
      exact_keys!(required, %w[items type])
      exact_keys!(allowed, %w[allowed type])
      raise Rejected, "unsupported constraint ordering" unless
        required["type"] == "checkout.line_items" &&
        allowed["type"] == "checkout.allowed_merchants"

      items = required.fetch("items")
      raise Rejected, "unsupported requirement cardinality" unless items.is_a?(Array) && items.size == 1
      requirement = items.fetch(0)
      exact_keys!(requirement, %w[acceptable_items id quantity])
      raise Rejected, "unsupported requirement fields" unless
        requirement["id"].is_a?(String) && !requirement["id"].empty? &&
        requirement["quantity"].is_a?(Integer) && requirement["quantity"].positive?

      sku = requirement.fetch("acceptable_items")
      merchant = allowed.fetch("allowed")
      raise Rejected, "incomplete fixed SKU/Merchant profile" unless
        sku.is_a?(Array) && sku.size == 1 &&
        merchant.is_a?(Array) && merchant.size == 1
      exact_keys!(sku.fetch(0), %w[id title])
      exact_keys!(merchant.fetch(0), %w[id name])
      raise Rejected, "invalid SKU/Merchant values" unless
        [sku[0]["id"], sku[0]["title"], merchant[0]["id"], merchant[0]["name"]].all? do |value|
          value.is_a?(String) && !value.empty?
        end
      mandate
    end

    def verify_signed_payload!(wire, trusted_jwk:)
      raise Rejected, "trusted issuer public key required" unless trusted_jwk.is_a?(Hash)
      raise Rejected, "oversized/non-ASCII SD-JWT" unless
        wire.is_a?(String) && wire.bytesize.between?(1, 32_768) && wire.ascii_only? && wire.end_with?("~")
      parts = wire.split("~", -1)
      raise Rejected, "invalid SD-JWT segmentation" unless parts.size.between?(3, 18) && parts.last == ""
      disclosures = parts[1...-1]
      raise Rejected, "invalid disclosure count" unless disclosures.size.between?(1, 16)

      header, signed_payload = AP2StrictJSONResearch.validate_signed_jws_json!(parts.first)
      exact_keys_subset!(header, %w[alg kid typ])
      raise Rejected, "unsupported issuer signing algorithm" unless header["alg"] == "ES256"
      # Official pinned SDK root is typ=example+sd-jwt, not a Terminal JWT.
      raise Rejected, "unsupported Root JOSE typ" unless header["typ"] == "example+sd-jwt"
      exact_keys_subset!(signed_payload, %w[delegate_payload _sd_alg])
      raise Rejected, "unsupported root hash algorithm" unless [nil, "sha-256"].include?(signed_payload["_sd_alg"])
      raise Rejected, "invalid signed Root array" unless
        signed_payload["delegate_payload"].is_a?(Array) && signed_payload["delegate_payload"].size == 1

      public_key = JWT::JWK.import(trusted_jwk).public_key
      verified, = JWT.decode(parts.first, public_key, true, { algorithms: ["ES256"] })
      raise Rejected, "signed payload mismatch" unless verified == signed_payload

      mapping = {}
      disclosures.each do |part|
        decoded = AP2StrictJSONResearch.parse!(decode64!(part))
        raise Rejected, "unsupported non-array disclosure" unless decoded.is_a?(Array) &&
          decoded.size == 2 && decoded[0].is_a?(String) &&
          decoded[0].bytesize.between?(8, 128) && decoded[1].is_a?(Hash)
        digest = b64url(Digest::SHA256.digest(part.b))
        raise Rejected, "duplicate disclosure" if mapping.key?(digest)
        mapping[digest] = decoded[1]
      end

      used = Set.new
      observed = []
      root = walk!(signed_payload, [], mapping, used, observed)
      raise Rejected, "unsupported signed commitment layout" unless
        observed.size == 3 && observed.sort_by(&:to_s) == ALLOWED_PATHS.sort_by(&:to_s)
      raise Rejected, "unused/decoy disclosure" unless used.size == mapping.size
      root
    rescue JWT::DecodeError, JWT::JWKError, JSON::ParserError, ArgumentError,
           KeyError, TypeError => e
      raise Rejected, "invalid signed fixture (#{e.class})"
    end

    private

    def walk!(value, path, mapping, used, observed)
      raise Rejected, "unsupported signed nesting depth" if path.size > 24
      case value
      when Hash
        raise Rejected, "unsupported object SD/decoy or misplaced marker" if
          value.key?("_sd") || value.key?("...")
        raise Rejected, "oversized signed object" if value.size > 32
        value.to_h { |key, child| [key, walk!(child, path + [key], mapping, used, observed)] }
      when Array
        raise Rejected, "oversized signed array" if value.size > 16
        value.each_with_index.map do |item, index|
          here = path + [index]
          if item.is_a?(Hash) && item.key?("...")
            raise Rejected, "malformed signed array marker" unless item.keys == ["..."]
            raise Rejected, "unsupported signed commitment path" unless ALLOWED_PATHS.include?(here)
            digest = item.fetch("...")
            raise Rejected, "invalid signed commitment digest" unless
              digest.is_a?(String) && digest.match?(/\A[A-Za-z0-9_-]{43}\z/)
            raise Rejected, "incomplete_disclosure: missing disclosure" unless mapping.key?(digest)
            raise Rejected, "repeated signed commitment" if used.include?(digest)
            used.add(digest)
            observed << here
            walk!(mapping.fetch(digest), here + ["disclosed"], mapping, used, observed)
          else
            walk!(item, here, mapping, used, observed)
          end
        end
      else
        value
      end
    end

    def exact_keys!(obj, keys)
      raise Rejected, "unsupported fixed-Issuer signed claim layout" unless
        obj.is_a?(Hash) && obj.keys.sort == keys.sort
    end

    def exact_keys_subset!(obj, allowed)
      raise Rejected, "unsupported signed JOSE/Root claims" unless
        obj.is_a?(Hash) && (obj.keys - allowed).empty?
    end

    def decode64!(part)
      raise Rejected, "invalid disclosure base64url" unless
        part.is_a?(String) && part.match?(/\A[A-Za-z0-9_-]+\z/)
      decoded = Base64.urlsafe_decode64(part + ("=" * (-part.size % 4)))
      raise Rejected, "noncanonical disclosure base64url" unless b64url(decoded) == part
      decoded
    end

    def b64url(bytes)
      Base64.urlsafe_encode64(bytes, padding: false)
    end
  end
end
