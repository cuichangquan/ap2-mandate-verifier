# frozen_string_literal: true
#
# E06-I A2-3: standalone cryptographic original-wire binding CANDIDATE.
# NOT RUN. RESEARCH ONLY. NO APPROVAL B / NO TESTS / NO CI.
#
# This code cannot establish that its caller-selected public keys, G3 Open
# claims, Host Checkout JWT or challenge are from an authoritative immutable
# G1 context. Consequently every well-formed observation returns HOLD, never
# G4_SUCCESS, G5_SUCCESS, VerifiedEvidence, Host ALLOW or payment authority.
#
# The mandatory future boundary is opaque successful G1 and G3 provenance,
# then an integrated verified G4 result, before G5 schema or G6 business facts.
# Never call the old p1_1/p1_2/p1_3 modules (minitest/autorun side effects).
require "json"
require "base64"
require "digest"
require_relative "../shared/strict_json_research"

module AP2E06IAgentMerchantCrypto
  MAX_WIRE = 32_768
  MAX_CHECKOUT = 16_384
  ROOT_OPEN_KEYS = %w[cnf constraints exp iat vct].freeze
  CLOSED_KEYS = %w[checkout_hash checkout_jwt exp iat vct].freeze
  AGENT_KEY_FIELDS = %w[crv kty x y].freeze

  class Rejected < StandardError
    attr_reader :code
    def initialize(code)
      @code = code
      super(code)
    end
  end

  class Unavailable < StandardError; end

  # An observation only: never a success token for G4 or a bearer capability.
  # No decoded checkout payload, signed authorization claim or mutable keys
  # are exported to an untrusted caller by this result.
  class CryptoCandidate
    attr_reader :root_wire_sha256, :terminal_wire_sha256,
      :merchant_wire_sha256

    def initialize(root_wire:, terminal_wire:, merchant_wire:)
      @root_wire_sha256 = Digest::SHA256.hexdigest(root_wire).freeze
      @terminal_wire_sha256 = Digest::SHA256.hexdigest(terminal_wire).freeze
      @merchant_wire_sha256 = Digest::SHA256.hexdigest(merchant_wire).freeze
      freeze
    end

    def status
      "HOLD"
    end

    def reason
      "authenticated_host_g1_and_root_g3_artifacts_unavailable"
    end

    def g4_success?
      false
    end

    def evidence
      nil
    end
  end

  class Gate
    # All host_* arguments are untrusted OBSERVER INPUTS until an independent
    # Host source and opaque immutable G1/G3 artifacts are implemented. Do NOT
    # use a successful return as authenticated G4, even with correct signatures.
    #
    # verified_at is a single proposed Host clock; no Time.now is sampled.
    def inspect_candidate!(root_wire:, terminal_wire:, open_claims:,
                           host_agent_jwk:, host_merchant_jwk:,
                           host_aud:, host_nonce:, host_checkout_jwt:,
                           challenge_agent_thumbprint:, verified_at:)
      require_exact_jwt!
      root = copy_wire!(root_wire, MAX_WIRE)
      terminal = copy_wire!(terminal_wire, MAX_WIRE)
      host_checkout = copy_wire!(host_checkout_jwt, MAX_CHECKOUT)
      aud = copy_nonempty!(host_aud)
      nonce = copy_nonempty!(host_nonce, max: 512)
      reject!("invalid_verification_clock") unless
        verified_at.is_a?(Integer) && verified_at.between?(1, 4_102_444_800)

      # These objects and the apparent 'verified_open' are ALL caller-origin
      # material in this isolated slice. Deep-detach to keep this operation
      # internally coherent, but never upgrade it to Host/G3 provenance.
      agent = detached!(host_agent_jwk)
      merchant = detached!(host_merchant_jwk)
      open = detached!(open_claims)
      pin_public!(agent)
      pin_public!(merchant)
      exact!(open, ROOT_OPEN_KEYS, "unsupported_open_claim_layout")
      reject!("unsupported_open_type") unless
        open["vct"] == "mandate.checkout.open.1"
      cnf = open["cnf"]
      exact!(cnf, %w[jwk], "unsupported_open_holder_binding")
      root_agent = cnf.fetch("jwk")
      pin_public!(root_agent)
      reject!("open_agent_key_differs_from_host") unless
        equal_public!(root_agent, agent)
      reject!("challenge_agent_key_differs_from_open") unless
        fixed_equal!(challenge_agent_thumbprint, thumbprint(agent))

      terminal_signed, closed = resolve_one_terminal_disclosure!(
        terminal, agent, expected_aud: aud, expected_nonce: nonce,
        expected_sd_hash: urlsha(root), verified_at: verified_at
      )
      check_closed_claims!(closed, open, at: verified_at)
      reject!("terminal_cannot_redelegate") if closed.key?("cnf")
      reject!("checkout_jwt_not_host_original") unless
        fixed_equal!(closed.fetch("checkout_jwt"), host_checkout)
      reject!("checkout_hash_not_host_original") unless
        fixed_equal!(closed.fetch("checkout_hash"), urlsha(host_checkout))

      # The Checkout JWT's compact SIGNATURE is verified independently with
      # caller-provided merchant public key. Its signed JSON is also parsed
      # strictly from those same original bytes. No cart/merchant ID/status/
      # SKU/quantity/totals/price business comparisons are performed here.
      header, strict_payload = strict_jws!(host_checkout, "JWT")
      reject!("unsupported_merchant_header") unless
        header["alg"] == "ES256" && header["typ"] == "JWT"
      decoded_checkout = decode_es256!(host_checkout, merchant)
      reject!("merchant_signed_json_disagreement") unless
        decoded_checkout == strict_payload && decoded_checkout.is_a?(Hash)

      # No unauthenticated keys, nested claims or caller-supplied successful
      # stage labels can create a trusted G4 result. The later orchestrator
      # must receive genuine G1/G3 opaque success values and replay-safe Host
      # provenance before exposing any authenticated Checkout to G5.
      CryptoCandidate.new(
        root_wire: root, terminal_wire: terminal,
        merchant_wire: host_checkout
      )
    rescue Rejected, Unavailable
      raise
    rescue JSON::ParserError, KeyError, TypeError, ArgumentError, RangeError
      raise Rejected, "invalid_signed_chain_or_host_candidate"
    rescue StandardError
      raise Unavailable, "verification_unavailable"
    end

    private

    def require_exact_jwt!
      gem "jwt", "= 3.3.0"
      require "jwt"
      spec = Gem.loaded_specs["jwt"]
      raise Unavailable, "verification_unavailable:jwt_version" unless
        spec && spec.version.to_s == "3.3.0"
    rescue Gem::LoadError, LoadError
      raise Unavailable, "verification_unavailable:jwt_version"
    end

    def reject!(code)
      raise Rejected, code
    end

    def copy_wire!(input, max)
      reject!("invalid_wire_bounds") unless input.is_a?(String)
      wire = input.dup.freeze
      reject!("invalid_wire_bounds") unless
        wire.ascii_only? && wire.bytesize.between?(1, max)
      wire
    end

    def copy_nonempty!(input, max: 256)
      reject!("invalid_host_candidate") unless input.is_a?(String)
      copy = input.dup.freeze
      reject!("invalid_host_candidate") unless
        copy.ascii_only? && copy.bytesize.between?(1, max)
      copy
    end

    def detached!(item, depth = 0)
      reject!("host_candidate_resource_limit") if depth > 24
      case item
      when Hash
        reject!("host_candidate_resource_limit") if item.size > 32
        item.each_with_object({}) do |(key, val), obj|
          reject!("invalid_host_candidate_keys") unless key.is_a?(String)
          obj[key.dup.freeze] = detached!(val, depth + 1)
        end.freeze
      when Array
        reject!("host_candidate_resource_limit") if item.size > 16
        item.map { |v| detached!(v, depth + 1) }.freeze
      when String
        copy = item.dup.freeze
        reject!("host_candidate_resource_limit") if copy.bytesize > MAX_WIRE
        copy
      when Integer, NilClass, TrueClass, FalseClass
        item
      else
        reject!("unsupported_host_candidate_type")
      end
    end

    def exact!(hash, keys, code)
      reject!(code) unless hash.is_a?(Hash) && hash.keys.sort == keys.sort
    end

    def pin_public!(jwk)
      exact!(jwk, AGENT_KEY_FIELDS, "unsupported_public_key")
      reject!("unsupported_public_key") unless
        jwk["kty"] == "EC" && jwk["crv"] == "P-256"
      %w[x y].each do |coord|
        part = jwk[coord]
        reject!("invalid_public_coordinate") unless
          part.is_a?(String) &&
          part.match?(/\A[A-Za-z0-9_-]{43}\z/) &&
          decode64!(part).bytesize == 32
      end
      # JWT::JWK.import, at the actual signature step, must reject invalid
      #/off-curve public points; do not infer Host key enrollment from import.
    end

    def equal_public!(a, b)
      AGENT_KEY_FIELDS.all? { |k| a[k] == b[k] }
    end

    def thumbprint(jwk)
      sorted = AGENT_KEY_FIELDS.sort.to_h { |k| [k, jwk.fetch(k)] }
      Base64.urlsafe_encode64(
        Digest::SHA256.digest(JSON.generate(sorted)), padding: false
      )
    end

    def decode64!(part)
      reject!("noncanonical_base64url") unless
        part.is_a?(String) && part.match?(/\A[A-Za-z0-9_-]+\z/)
      out = Base64.urlsafe_decode64(part + ("=" * (-part.bytesize % 4)))
      reject!("noncanonical_base64url") unless
        Base64.urlsafe_encode64(out, padding: false) == part
      out
    rescue ArgumentError
      reject!("noncanonical_base64url")
    end

    def urlsha(raw)
      Base64.urlsafe_encode64(Digest::SHA256.digest(raw.b), padding: false)
    end

    def fixed_equal!(a, b)
      return false unless a.is_a?(String) && b.is_a?(String) &&
        a.bytesize == b.bytesize
      mismatch = 0
      a.bytes.zip(b.bytes) { |x, y| mismatch |= x ^ y }
      mismatch.zero?
    end

    def strict_jws!(compact, typ)
      # G0 is the normative pre-auth parser in a later integrated run.
      # This isolated crypto helper independently demands canonical ES256
      # signature encoding instead of relying on JWT.decode leniency.
      _header_seg, _payload_seg, signature_seg =
        AP2StrictJSONResearch.jwt_parts!(compact)
      reject!("invalid_es256_signature_encoding") unless
        decode64!(signature_seg).bytesize == 64
      header, payload = AP2StrictJSONResearch.validate_signed_jws_json!(compact)
      reject!("unsupported_signed_header") unless
        header.is_a?(Hash) && header["alg"] == "ES256" &&
        header["typ"] == typ &&
        (header.keys - %w[alg kid typ]).empty? &&
        (!header.key?("kid") || header["kid"].is_a?(String))
      reject!("invalid_signed_payload") unless payload.is_a?(Hash)
      [header, payload]
    end

    def decode_es256!(wire, public_jwk)
      key = JWT::JWK.import(public_jwk).public_key
      decoded, = JWT.decode(
        wire, key, true,
        {
          algorithms: ["ES256"],
          verify_expiration: false, verify_not_before: false,
          verify_iat: false, verify_iss: false,
          verify_aud: false, verify_jti: false
        }
      )
      decoded
    rescue JWT::DecodeError, JWT::JWKError
      reject!("invalid_agent_or_merchant_signature")
    end

    def resolve_one_terminal_disclosure!(wire, agent, expected_aud:,
                                         expected_nonce:, expected_sd_hash:,
                                         verified_at:)
      parts = wire.split("~", -1)
      reject!("unsupported_terminal_disclosure_count") unless
        parts.size == 3 && parts.last == "" && !parts[1].empty?
      _header, strict_signed = strict_jws!(parts.first, "kb+sd-jwt")
      reject!("terminal_signed_json_disagreement") unless
        decode_es256!(parts.first, agent) == strict_signed
      reject!("unsupported_terminal_claim_fields") unless
        (strict_signed.keys - %w[_sd_alg aud delegate_payload iat nonce sd_hash]).empty? &&
        [nil, "sha-256"].include?(strict_signed["_sd_alg"])
      reject!("unsupported_terminal_hash_mode") if strict_signed.key?("issuer_jwt_hash")
      reject!("invalid_terminal_sd_hash") unless
        fixed_equal!(strict_signed["sd_hash"], expected_sd_hash)
      reject!("invalid_terminal_audience") unless
        fixed_equal!(strict_signed["aud"], expected_aud)
      reject!("invalid_terminal_nonce") unless
        fixed_equal!(strict_signed["nonce"], expected_nonce)
      t0 = strict_signed["iat"]
      reject!("invalid_terminal_issued_at") unless
        t0.is_a?(Integer) && (verified_at - t0).between?(0, 300)
      disclosure = AP2StrictJSONResearch.parse!(decode64!(parts[1]))
      reject!("unsupported_terminal_disclosure") unless
        disclosure.is_a?(Array) && disclosure.size == 2 &&
        disclosure[0].is_a?(String) &&
        disclosure[0].bytesize.between?(8, 128) &&
        disclosure[1].is_a?(Hash)
      expected_disclosure_digest = urlsha(parts[1])
      reject!("unsupported_terminal_commitment") unless
        strict_signed["delegate_payload"] == [{ "..." => expected_disclosure_digest }]
      # A single exactly resolved signed Closed object, no hidden/extra
      # commitments, unknown decoded authority fields or nested SD markers.
      closed = disclosure[1]
      reject!("unsupported_closed_structure") unless
        closed.keys.sort == CLOSED_KEYS &&
        !closed.values.any? { |v| v.is_a?(Hash) && (v.key?("_sd") || v.key?("...")) }
      [strict_signed, closed]
    end

    def check_closed_claims!(closed, open, at:)
      reject!("invalid_closed_type") unless closed["vct"] == "mandate.checkout.1"
      open_iat, open_exp = open.values_at("iat", "exp")
      iat, exp = closed.values_at("iat", "exp")
      reject!("invalid_open_or_closed_clock") unless
        [open_iat, open_exp, iat, exp].all? { |x| x.is_a?(Integer) } &&
        open_iat <= at && at < open_exp && iat <= at && at < exp &&
        exp > iat && exp - iat <= 7200
      reject!("closed_modified_issuer_fixed_time_claim") unless
        iat == open_iat && exp == open_exp
      reject!("closed_modified_shared_claim") unless
        ((open.keys & closed.keys) - %w[vct iat exp]).all? do |key|
          open[key] == closed[key]
        end
      reject!("missing_checkout_bytes") unless
        closed["checkout_jwt"].is_a?(String) &&
        !closed["checkout_jwt"].empty? &&
        closed["checkout_hash"].is_a?(String) &&
        !closed["checkout_hash"].empty?
    end
  end
end
