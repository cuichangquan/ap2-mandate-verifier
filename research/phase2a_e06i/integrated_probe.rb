# frozen_string_literal: true
#
# Phase 2-A E06-I approval A, isolated research-only stage observer.
# WARNING: only G0–G3 are wired. G4–G7 deliberately FAIL CLOSED.
# This is NOT an integrated verifier, not authorization and not a Gem API.
# Never relabel a G0 or G1 reject as proof of signature/SD closure.
require "json"
require "digest"
require "base64"
require "jwt"
require_relative "../phase2a_e01s/synthetic_host_policy"
require_relative "../phase2a_dc04/fixed_issuer_verifier"
require_relative "schema_gate"

module AP2E06IPartialProbe
  HOST = AP2E01SHostPolicy
  ROOT = AP2DC04FixedIssuerResearch
  STAGES = %w[
    G0_PREAUTH_BOUNDS G1_HOST_TRUST_SNAPSHOT G2_ISSUER_ROOT_AUTHENTICITY
    G3_ROOT_ORIGINAL_SD_CLOSURE G4_AGENT_AND_MERCHANT_CRYPTO_BINDING
    G5_OFFICIAL_SCHEMA_AND_LOCAL_SHAPE G6_FULL_CONSTRAINT_CHECKOUT_HOST_BINDING
    G7_EVIDENCE_ONLY
  ].freeze

  class Halt < StandardError
    attr_reader :code
    def initialize(code)
      @code = code
      super(code)
    end
  end

  class << self
    # Synthetic fixture inputs are NOT a Host authorization decision.
    # policy_json MUST come from the independent Host fixture, not a token.
    def observe(policy_json:, case_data:, policy_digest:)
      current = STAGES.fetch(0)
      reached = []
      raise Halt, "invalid_input" unless case_data.is_a?(Hash) &&
        case_data.keys.sort == %w[candidate root terminal]
      root, terminal, candidate = case_data.values_at("root", "terminal", "candidate")
      raise Halt, "resource_limit" unless [root, terminal].all? do |wire|
        wire.is_a?(String) && wire.ascii_only? && wire.bytesize.between?(1, 32_768)
      end
      raise Halt, "resource_limit" unless policy_json.is_a?(String) &&
        policy_json.ascii_only? && policy_json.bytesize.between?(1, 16_384) &&
        root.bytesize + terminal.bytesize + policy_json.bytesize <= 131_072

      untrusted_policy = AP2StrictJSONResearch.parse!(policy_json)
      raise Halt, "invalid_host_context" unless untrusted_policy.is_a?(Hash)
      checkout_jwt = untrusted_policy["host_checkout_jwt"]
      raise Halt, "resource_limit" unless checkout_jwt.is_a?(String) &&
        checkout_jwt.ascii_only? && checkout_jwt.bytesize.between?(1, 16_384)

      root_jws = inspect_sd_wire!(root, typ: "example+sd-jwt")
      inspect_sd_wire!(terminal, typ: "kb+sd-jwt")
      check_jws!(checkout_jwt, typ: "JWT")
      reached << current

      current = STAGES.fetch(1)
      policy = HOST.load!(policy_json)
      trusted = HOST.verify_candidate!(
        policy, candidate, case_policy_digest: policy_digest
      )
      reached << current

      current = STAGES.fetch(2)
      _header, signed_root = AP2StrictJSONResearch.validate_signed_jws_json!(root_jws)
      decoded, = JWT.decode(
        root_jws, JWT::JWK.import(trusted).public_key, true,
        { algorithms: ["ES256"] }
      )
      raise Halt, "invalid_issuer_signature" unless signed_root == decoded
      reached << current

      current = STAGES.fetch(3)
      # DC04 repeats G2 with the same Host key while performing original
      # signed Root whole-graph closure and its fixed local Open shape.
      # "reached G3" is marked only when THIS call succeeds.
      verified_open = ROOT.verify_full_root!(root, trusted_jwk: trusted)
      raise Halt, "unsupported_profile" unless verified_open.is_a?(Hash)
      reached << current

      # G4/G6 currently mix crypto and semantics inside old P1-2/P1-3.
      # Calling old checkout verify! now, then applying Schema, would
      # violate G5-before-G6. DO NOT do so or return success.
      current = STAGES.fetch(4)
      {
        "status" => "HOLD", "first_reject_stage" => current,
        "reason" => "G4_G6_SAFE_EXTRACTION_NOT_IMPLEMENTED",
        "completed_stages" => reached.freeze,
        "evidence" => nil
      }
    rescue HOST::Rejected => error
      {
        "status" => "REJECT", "first_reject_stage" => current,
        "reason" => error.code, "completed_stages" => reached.freeze,
        "evidence" => nil
      }
    rescue AP2RootSDJWTResearch::Rejected => error
      {
        "status" => "REJECT", "first_reject_stage" => current,
        "reason" => error.message, "completed_stages" => reached.freeze,
        "evidence" => nil
      }
    rescue Halt => error
      {
        "status" => "REJECT", "first_reject_stage" => current,
        "reason" => error.code, "completed_stages" => reached.freeze,
        "evidence" => nil
      }
    rescue JWT::DecodeError, JWT::JWKError
      {
        "status" => "REJECT", "first_reject_stage" => current,
        "reason" => "invalid_issuer_signature", "completed_stages" => reached.freeze,
        "evidence" => nil
      }
    rescue JSON::ParserError, ArgumentError, TypeError, KeyError
      {
        "status" => "REJECT", "first_reject_stage" => current,
        "reason" => "invalid_input_or_ambiguous_json", "completed_stages" => reached.freeze,
        "evidence" => nil
      }
    rescue StandardError
      # Other local exceptions must not authorize anything; never emit a
      # successfully verified stage or a serialized exception / sensitive wire.
      {
        "status" => "HOLD", "first_reject_stage" => current,
        "reason" => "unexpected_unverified_failure",
        "completed_stages" => reached.freeze, "evidence" => nil
      }
    end

    private

    # G0 structural/strict parse ONLY; the returned original JWS is untrusted.
    def inspect_sd_wire!(wire, typ:)
      parts = wire.split("~", -1)
      raise Halt, "invalid_sd_segments" unless parts.length.between?(3, 18) &&
        parts.last == "" && parts[1...-1].length.between?(1, 16)
      check_jws!(parts.first, typ: typ)
      parts[1...-1].each do |part|
        AP2StrictJSONResearch.decode_part!(part)
      end
      parts.first
    end

    def check_jws!(compact, typ:)
      header, = AP2StrictJSONResearch.validate_signed_jws_json!(compact)
      raise Halt, "unsupported_jose_header" unless header.is_a?(Hash) &&
        header["alg"] == "ES256" && header["typ"] == typ &&
        (header.keys - %w[alg kid typ]).empty? &&
        (header["kid"].nil? || header["kid"].is_a?(String))
      compact
    end
  end
end
