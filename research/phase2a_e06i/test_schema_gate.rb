# frozen_string_literal: true
#
# E06-I/A proposed unit assertions. NO CI/fixture execution is authorized
# by adding this file. Signed O1–O5 integration cases are NOT implemented.
require "minitest/autorun"
require_relative "schema_gate"
require_relative "integrated_probe"

class E06ISchemaOnlyProposedTest < Minitest::Test
  def test_01_missing_upstream_must_fail_closed
    error = assert_raises(AP2E06ISchemaGate::Rejected) do
      AP2E06ISchemaGate::Gate.new(upstream_root: "/__nonexistent_e06i_upstream__")
    end
    assert_equal "verification_unavailable", error.code
  end

  def test_02_preauth_rejection_never_returns_evidence
    result = AP2E06IPartialProbe.observe(
      policy_json: "{}", policy_digest: "ignored",
      case_data: { "candidate" => {}, "root" => "not-a-signed-root", "terminal" => "" }
    )
    assert_equal "REJECT", result.fetch("status")
    assert_equal "G0_PREAUTH_BOUNDS", result.fetch("first_reject_stage")
    assert_nil result.fetch("evidence")
    assert_empty result.fetch("completed_stages")
  end

  def test_03_bad_case_shape_never_returns_evidence
    result = AP2E06IPartialProbe.observe(
      policy_json: "{}", policy_digest: "ignored", case_data: {}
    )
    assert_equal "REJECT", result.fetch("status")
    assert_equal "G0_PREAUTH_BOUNDS", result.fetch("first_reject_stage")
    assert_nil result.fetch("evidence")
  end

  # G0-only *unsigned* format negatives: these cannot prove G2/G3,
  # nor can they stand in for approval B's authentic signed O1–O5 cases.
  def test_04_bad_terminal_signature_encoding_is_g0_only
    result = observe_g0(
      terminal: fake_sd_jwt("kb+sd-jwt", "!")
    )
    assert_equal "REJECT", result.fetch("status")
    assert_equal "G0_PREAUTH_BOUNDS", result.fetch("first_reject_stage")
    assert_equal "invalid_jws_signature_encoding", result.fetch("reason")
    assert_empty result.fetch("completed_stages")
  end

  def test_05_nested_terminal_array_exceeds_g0_limit
    terminal = fake_sd_jwt(
      "kb+sd-jwt", Base64.urlsafe_encode64("\0" * 64, padding: false),
      { "delegation" => { "many" => Array.new(17, 0) } }
    )
    result = observe_g0(terminal: terminal)
    assert_equal "REJECT", result.fetch("status")
    assert_equal "G0_PREAUTH_BOUNDS", result.fetch("first_reject_stage")
    assert_equal "resource_limit", result.fetch("reason")
    assert_empty result.fetch("completed_stages")
  end

  def test_06_nested_terminal_object_exceeds_g0_limit
    terminal = fake_sd_jwt(
      "kb+sd-jwt", Base64.urlsafe_encode64("\0" * 64, padding: false),
      { "delegation" => (0...33).to_h { |i| ["field-#{i}", i] } }
    )
    result = observe_g0(terminal: terminal)
    assert_equal "REJECT", result.fetch("status")
    assert_equal "G0_PREAUTH_BOUNDS", result.fetch("first_reject_stage")
    assert_equal "resource_limit", result.fetch("reason")
    assert_empty result.fetch("completed_stages")
  end

  def test_07_escaped_duplicate_signed_root_key_rejects_at_g0
    signature = Base64.urlsafe_encode64("\0" * 64, padding: false)
    # Two identical "delegate_payload" names after JSON unescaping.
    raw = %q({"delegate_payload":[],"\u0064elegate_payload":[]})
    root = fake_sd_jwt("example+sd-jwt", signature, raw)
    result = observe_g0(
      root: root, terminal: fake_sd_jwt("kb+sd-jwt", signature)
    )
    assert_equal "REJECT", result.fetch("status")
    assert_equal "G0_PREAUTH_BOUNDS", result.fetch("first_reject_stage")
    assert_equal "ambiguous_signed_json", result.fetch("reason")
    assert_empty result.fetch("completed_stages")
  end

  # This uses only an in-process fake loaded-spec entry and restores it.
  # It is NOT a signed Root experiment and does not execute CI.
  def test_08_unpinned_jwt_gem_stops_before_g0
    original = Gem.loaded_specs.fetch("jwt")
    fake = original.dup
    fake.version = Gem::Version.new("99.0.0")
    begin
      Gem.loaded_specs["jwt"] = fake
      result = AP2E06IPartialProbe.observe(
        policy_json: "{}", policy_digest: "ignored", case_data: {}
      )
      assert_equal "HOLD", result.fetch("status")
      assert_equal "G0_PREAUTH_BOUNDS", result.fetch("first_reject_stage")
      assert_equal "verification_unavailable:jwt_version", result.fetch("reason")
      assert_empty result.fetch("completed_stages")
      assert_nil result.fetch("evidence")
    ensure
      Gem.loaded_specs["jwt"] = original
    end
  end

  # Only when an *independently pinned* AP2 source tree is supplied.
  # This is a Schema mechanism test, NOT an O1–O5 signed-root experiment.
  def test_09_pinned_open_closed_merchant_schema_mechanism
    source = ENV["AP2_E06I_UPSTREAM_ROOT"]
    skip "No pinned upstream: Schema mechanism test NOT RUN" if source.nil? || source.empty?
    gate = AP2E06ISchemaGate::Gate.new(upstream_root: source)

    good_open = {
      "vct" => "mandate.checkout.open.1", "cnf" => {},
      "constraints" => [
        { "type" => "checkout.line_items", "items" => [
          { "id" => "requirement-1", "quantity" => 1,
            "acceptable_items" => [{ "id" => "sku-1", "title" => "Item" }] }
        ] },
        { "type" => "checkout.allowed_merchants", "allowed" => [
          { "id" => "merchant-1", "name" => "Merchant" }
        ] }
      ]
    }
    good_closed = {
      "vct" => "mandate.checkout.1", "checkout_jwt" => "synthetic-only",
      "checkout_hash" => "synthetic-only"
    }

    assert_equal "VALID", gate.check!(open: good_open, closed: good_closed)["open"]
    assert_equal "LOCAL_PINNED", gate.check!(open: good_open, closed: good_closed)["merchant_ref"]
    refute_empty gate.fingerprints.fetch("merchant").fetch("sha256")

    invalid_open = Marshal.load(Marshal.dump(good_open))
    invalid_open["constraints"][0]["items"][0]["id"] = 123
    assert_equal "invalid_open_schema", assert_raises(AP2E06ISchemaGate::Rejected) {
      gate.check!(open: invalid_open, closed: good_closed)
    }.code

    invalid_merchant = Marshal.load(Marshal.dump(good_open))
    invalid_merchant["constraints"][1]["allowed"][0]["name"] = 123
    assert_equal "invalid_open_schema", assert_raises(AP2E06ISchemaGate::Rejected) {
      gate.check!(open: invalid_merchant, closed: good_closed)
    }.code

    invalid_closed = good_closed.reject { |key, _| key == "checkout_hash" }
    assert_equal "invalid_closed_schema", assert_raises(AP2E06ISchemaGate::Rejected) {
      gate.check!(open: good_open, closed: invalid_closed)
    }.code
  end

  private

  def observe_g0(terminal:, root: nil)
    sig = Base64.urlsafe_encode64("\0" * 64, padding: false)
    root ||= fake_sd_jwt("example+sd-jwt", sig)
    checkout_jwt = fake_jws("JWT", sig, { "id" => "fake" })
    AP2E06IPartialProbe.observe(
      policy_json: JSON.generate({ "host_checkout_jwt" => checkout_jwt }),
      policy_digest: "unsigned-unit-only",
      case_data: {
        "candidate" => { "kty" => "EC", "crv" => "P-256", "x" => "a", "y" => "b" },
        "root" => root, "terminal" => terminal
      }
    )
  end

  def fake_sd_jwt(typ, signature, payload = { "delegate_payload" => [] })
    disclosure = Base64.urlsafe_encode64(
      JSON.generate(["saltsaltsalt", { "synthetic" => 1 }]), padding: false
    )
    "#{fake_jws(typ, signature, payload)}~#{disclosure}~"
  end

  def fake_jws(typ, signature, payload)
    protected = Base64.urlsafe_encode64(
      JSON.generate({ "alg" => "ES256", "typ" => typ }), padding: false
    )
    body = Base64.urlsafe_encode64(
      payload.is_a?(String) ? payload : JSON.generate(payload), padding: false
    )
    "#{protected}.#{body}.#{signature}"
  end
end
