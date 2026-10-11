# frozen_string_literal: true
#
# P1-1 OFFLINE RESEARCH SPIKE ONLY. Not a reusable SD-JWT verifier or a Gem.
# Deliberately rejects all unsupported SD-JWT layout features and partial
# disclosure; in particular never infers permission from visible constraints.
#
# Requires Ruby 3.3+, jwt (= 3.3.0), stdlib.
require "jwt"
require "json"
require "base64"
require "openssl"
require "digest"
require "set"
require "minitest/autorun"

module AP2RootSDJWTResearch
  class Rejected < StandardError; end

  class << self
    def verify_full_root!(wire, trusted_jwk:)
      raise Rejected, "trusted issuer key required" unless trusted_jwk.is_a?(Hash)
      raise Rejected, "oversized token" unless wire.is_a?(String) && wire.bytesize.between?(1, 32_768)
      raise Rejected, "non ASCII token" unless wire.ascii_only?
      raise Rejected, "missing SD-JWT delimiter" unless wire.end_with?("~")

      parts = wire.split("~", -1)
      raise Rejected, "bad SD-JWT segments" if parts.size < 3 || parts.last != ""
      disclosures = parts[1...-1]
      raise Rejected, "invalid disclosure count" unless disclosures.size.between?(1, 16)
      raise Rejected, "empty disclosure" if disclosures.any?(&:empty?)

      # The caller supplies an already-trusted issuer key. Never import a key
      # supplied by a JWT header or trust its 'kid' / 'x5c' / remote URLs.
      key = JWT::JWK.import(trusted_jwk)
      header_untrusted = JSON.parse(b64_json(parts.first.split(".").first))
      raise Rejected, "non ES256 algorithm" unless header_untrusted["alg"] == "ES256"
      raise Rejected, "untrusted JOSE header parameter" if (%w[jwk jku x5c x5u crit] & header_untrusted.keys).any?
      payload, = JWT.decode(parts.first, key.public_key, true, { algorithms: ["ES256"] })
      raise Rejected, "unsupported SD algorithm" unless [nil, "sha-256"].include?(payload["_sd_alg"])

      digest_to_value = {}
      disclosures.each do |segment|
        raise Rejected, "invalid encoded disclosure" unless segment.match?(/\A[A-Za-z0-9_-]+\z/)
        decoded = JSON.parse(b64_json(segment))
        raise Rejected, "unsupported object disclosure" unless decoded.is_a?(Array) &&
          decoded.size == 2 && decoded[0].is_a?(String) && decoded[0].size >= 8 &&
          decoded[1].is_a?(Hash)
        digest = b64url(Digest::SHA256.digest(segment.b))
        raise Rejected, "duplicate digest" if digest_to_value.key?(digest)
        digest_to_value[digest] = decoded[1]
      end

      used = Set.new
      resolved = resolve(payload, [], digest_to_value, used)
      raise Rejected, "unused disclosure" unless used.size == digest_to_value.size
      root_array = resolved.fetch("delegate_payload") { raise Rejected, "no delegate_payload" }
      raise Rejected, "ambiguous authority payload" unless root_array.is_a?(Array) &&
        root_array.size == 1 && root_array[0].is_a?(Hash)
      mandate = root_array[0]
      raise Rejected, "not a Checkout Open mandate" unless mandate["vct"] == "mandate.checkout.open.1"
      cnf = mandate["cnf"]
      raise Rejected, "missing holder public key" unless cnf.is_a?(Hash) && cnf["jwk"].is_a?(Hash)
      constraints = mandate["constraints"]
      raise Rejected, "incomplete constraints" unless constraints.is_a?(Array)
      types = constraints.map { |c| c.is_a?(Hash) ? c["type"] : nil }
      # THIS IS A DEMONSTRATION OF A NARROW, HOST-CONFIGURED PROFILE:
      # requiring exactly these 2 constraints does NOT prove arbitrary hidden
      # constraints cannot exist in other issuer layouts.
      required = %w[checkout.allowed_merchants checkout.line_items]
      raise Rejected, "unsupported or missing authority constraints" unless types.sort == required.sort
      raise Rejected, "root expiry required" unless mandate["exp"].is_a?(Integer) &&
        mandate["iat"].is_a?(Integer) && mandate["iat"] <= Time.now.to_i &&
        Time.now.to_i < mandate["exp"] && mandate["exp"] - mandate["iat"] <= 7200
      mandate
    rescue JWT::DecodeError, JWT::JWKError, JSON::ParserError, ArgumentError, KeyError => e
      raise Rejected, "invalid signature, disclosure or issuer input (#{e.class})"
    end

    private

    def resolve(value, path, digest_to_value, used)
      case value
      when Hash
        raise Rejected, "unsupported selectively disclosed object" if value.key?("_sd")
        raise Rejected, "unhandled placeholder" if value.key?("...")
        value.to_h { |k, v| [k, resolve(v, path + [k], digest_to_value, used)] }
      when Array
        value.map do |item|
          if item.is_a?(Hash) && item.keys == ["..."]
            raise Rejected, "unsupported array disclosure location" unless
              path == ["delegate_payload"] || path == ["delegate_payload", "constraints"]
            digest = item["..."]
            raise Rejected, "invalid disclosure marker" unless digest.is_a?(String)
            raise Rejected, "missing disclosure" unless digest_to_value.key?(digest)
            raise Rejected, "duplicate placeholder" if used.include?(digest)
            used.add(digest)
            resolve(digest_to_value.fetch(digest), path + ["*"], digest_to_value, used)
          else
            resolve(item, path + ["*"], digest_to_value, used)
          end
        end
      else
        value
      end
    end

    def b64_json(str)
      raise Rejected, "invalid base64url" unless str.is_a?(String) &&
        str.match?(/\A[A-Za-z0-9_-]+\z/)
      Base64.urlsafe_decode64(str + ("=" * ((-str.length) % 4)))
    end

    def b64url(data)
      Base64.urlsafe_encode64(data, padding: false)
    end
  end
end

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
