# frozen_string_literal: true
#
# P1-0 research only; NOT a production verifier.
# Requires: jwt (=3.3.0), json_schemer (=2.5.0), Ruby 3.3+, stdlib.
# Official AP2 v0.2 schema is fetched separately at the pinned commit and
# authenticated with the exact Git blob SHA. No network occurs during tests.
require "minitest/autorun"
require "jwt"
require "json_schemer"
require "json"
require "openssl"
require "digest"
require "base64"

class AP2RubyFeasibilitySpikeTest < Minitest::Test
  BASELINE = "b4587ac1d055888a73b4b21750973cffba961793"
  SCHEMA_BLOB_SHA = "e3d9cafa7311d90612c7f908ae9b8821ddc8735a"
  FIXTURES_PATH = File.expand_path("python_es256_checkout_fixtures.json", __dir__)

  def setup
    @fixture = JSON.parse(File.binread(FIXTURES_PATH))
    @schema_path = ENV.fetch("AP2_OPEN_CHECKOUT_SCHEMA") do
      raise "Set AP2_OPEN_CHECKOUT_SCHEMA to the pinned official open_checkout_mandate.json"
    end
  end

  def test_01_baseline_and_official_schema_blob
    assert_equal BASELINE, @fixture.fetch("ap2_protocol_commit")
    raw = File.binread(@schema_path)
    sha = Digest::SHA1.hexdigest("blob #{raw.bytesize}\0".b + raw)
    assert_equal SCHEMA_BLOB_SHA, sha
  end

  def test_02_python_es256_signature_verified_by_ruby_jwt
    payload, header = verified(@fixture.fetch("checkout_jwt"), @fixture.fetch("p256_public_jwk"))
    assert_equal "ES256", header.fetch("alg")
    assert_equal "research-checkout-001", payload.fetch("checkout_id")
    assert_equal "research-store", payload.fetch("merchant_id")
  end

  def test_03_tampered_payload_is_rejected
    assert_raises(JWT::DecodeError) do
      verified(@fixture.fetch("altered_checkout_jwt_same_signature"), @fixture.fetch("p256_public_jwk"))
    end
  end

  def test_04_tampered_signature_is_rejected
    assert_raises(JWT::DecodeError) do
      verified(@fixture.fetch("altered_signature_checkout_jwt"), @fixture.fetch("p256_public_jwk"))
    end
  end

  def test_05_unknown_issuer_public_key_is_rejected
    assert_raises(JWT::DecodeError) do
      verified(@fixture.fetch("checkout_jwt"), @fixture.fetch("wrong_p256_public_jwk"))
    end
  end

  def test_06_missing_trusted_key_is_rejected_by_host_spike_contract
    assert_raises(ArgumentError) { verified(@fixture.fetch("checkout_jwt"), nil) }
  end

  def test_07_none_algorithm_cannot_bypass_es256_allowlist
    compact = @fixture.fetch("checkout_jwt").split(".")
    header = Base64.urlsafe_encode64(JSON.generate({"alg" => "none", "typ" => "JWT"}), padding: false)
    attack = [header, compact[1], compact[2]].join(".")
    assert_raises(JWT::DecodeError) { verified(attack, @fixture.fetch("p256_public_jwk")) }
  end

  def test_08_sha256_checkout_hash_matches_python
    actual = Base64.urlsafe_encode64(Digest::SHA256.digest(@fixture.fetch("checkout_jwt").b), padding: false)
    assert_equal @fixture.fetch("checkout_hash_sha256_b64url"), actual
  end

  def test_09_checkout_hash_rejects_other_transaction
    changed = @fixture.fetch("altered_checkout_jwt_same_signature")
    refute_equal @fixture.fetch("checkout_hash_sha256_b64url"), Base64.urlsafe_encode64(Digest::SHA256.digest(changed.b), padding: false)
  end

  def test_10_open_checkout_schema_accepts_valid_line_items
    assert valid_schema?(@fixture.fetch("valid_open_checkout"))
  end

  def test_11_schema_rejects_empty_constraints_without_line_items
    refute valid_schema?(@fixture.fetch("invalid_open_checkout_empty_constraints"))
  end

  def test_12_schema_rejects_nonpositive_quantity
    refute valid_schema?(@fixture.fetch("invalid_open_checkout_quantity_zero"))
  end

  def test_13_schema_rejects_incorrect_vct_suffix
    refute valid_schema?(@fixture.fetch("invalid_open_checkout_vct"))
  end

  def test_14_schema_rejects_missing_cnf
    doc = Marshal.load(Marshal.dump(@fixture.fetch("valid_open_checkout")))
    doc.delete("cnf")
    refute valid_schema?(doc)
  end

  private

  def verified(compact, jwk_hash)
    # Reject missing Host-trusted key before handing the token to a JWT library.
    raise ArgumentError, "Host trusted JWK required" unless jwk_hash
    jwk = JWT::JWK.import(jwk_hash)
    JWT.decode(compact, jwk.public_key, true, {algorithms: ["ES256"]})
  end

  def valid_schema?(doc)
    schema = JSON.parse(File.binread(@schema_path))
    JSONSchemer.schema(schema).valid?(doc)
  end
end
