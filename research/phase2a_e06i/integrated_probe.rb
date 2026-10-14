# frozen_string_literal: true
#
# Phase 2-A E06-I approval A, isolated research-only stage observer.
# WARNING: G0–G4 synthetic-local only. G5–G7 deliberately FAIL CLOSED.
# This is NOT an integrated verifier, not authorization and not a Gem API.
# Never relabel a G0 or G1 reject as proof of signature/SD closure.
require "json"
require "digest"
require "base64"
require_relative "isolated_host_policy"
require_relative "isolated_host_snapshot"
require_relative "isolated_root_closure"
require_relative "isolated_g4_crypto"
require_relative "isolated_stage_context"
# A3-T1 diagnostic needs these distinct Halt classes to preserve REJECT.
# Modules define contracts only; no fixtures, tests or runner are loaded.
require_relative "isolated_host_source"
require_relative "isolated_nonce_issuance_source"

module AP2E06IPartialProbe
  HOST = AP2E06IHostPolicy
  ROOT = AP2E06IRootClosure
  G4 = AP2E06IG4Crypto
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
    # A2-5 Host candidate-only preflight. This is NOT the G0→G1 pipeline:
    # there is no presentation/G0, no authenticated Host source, and no
    # acceptable G1Context. Never count this outcome as G1 completion.
    #
    # The separate A2-1 candidate inspector checks only alleged Host facts.
    # Even an internally consistent snapshot MUST stop before G2/G3/G4/G7,
    # since no provenance, live trust enrollment or nonce issuance registry
    # is authenticated. This path cannot emit VerifiedEvidence or Host ALLOW.
    #
    # It intentionally DOES NOT change the original observe() implementation
    # or wire untrusted candidates to standalone G4/G5/G6 observers.
    def inspect_a2_host_candidate(host_json:, expected_host_sha256:, verified_at:)
      candidate = AP2E06IHostSnapshot.inspect_candidate!(
        host_json: host_json,
        expected_sha256: expected_host_sha256,
        verified_at: verified_at
      )
      {
        "status" => "HOLD",
        "checked_component" => "G1_HOST_CANDIDATE_ONLY",
        "reason" => candidate.reason,
        "g1_admissible" => false,
        "first_reject_stage" => nil,
        "completed_stages" => [].freeze,
        "evidence" => nil
      }
    rescue AP2E06IHostSnapshot::Halt => error
      {
        "status" => error.status,
        "checked_component" => "G1_HOST_CANDIDATE_ONLY",
        "reason" => error.code,
        "g1_admissible" => false,
        "first_reject_stage" => nil,
        "completed_stages" => [].freeze,
        "evidence" => nil
      }
    rescue StandardError
      {
        "status" => "HOLD",
        "checked_component" => "G1_HOST_CANDIDATE_ONLY",
        "reason" => "host_candidate_verification_unavailable",
        "g1_admissible" => false,
        "first_reject_stage" => nil,
        "completed_stages" => [].freeze,
        "evidence" => nil
      }
    end


    # A3-T1 independent diagnostic ONLY; not observe(), not the actual G0→G7
    # verifier. Only comparison of untrusted Host source claims with the same
    # injected bounded instant used for signed Root iat/exp. In particular,
    # a signature valid under a caller-claimed JWK is NOT G2 authenticity.
    # This path never reports completed G0/G1/G2/G3, a trusted context or G7.
    def inspect_a3_t1_clock_claim_only(
      root_wire:, terminal_wire:, checkout_wire:, verified_at:,
      host_json:, expected_host_sha256:, host_source_json:,
      expected_host_source_sha256:, nonce_source_json:,
      expected_nonce_source_sha256:
    )
      checked = []
      # The diagnostic does not share an invocation with the historic
      # observe(); first_reject_stage is always nil, even on bad inputs.
      raise Halt, "invalid_original_wire_type" unless
        [root_wire, terminal_wire, checkout_wire, host_json].all? { |v|
          v.is_a?(String)
        }
      root = root_wire.dup.freeze
      terminal = terminal_wire.dup.freeze
      checkout = checkout_wire.dup.freeze
      host = host_json.dup.freeze
      raise Halt, "resource_limit" unless
        [root, terminal].all? { |v|
          v.ascii_only? && v.bytesize.between?(1, 32_768)
        } && checkout.ascii_only? && checkout.bytesize.between?(1, 16_384) &&
        host.ascii_only? && host.bytesize.between?(1, 16_384) &&
        root.bytesize + terminal.bytesize + checkout.bytesize +
          host.bytesize <= 131_072

      # Standalone G0-like wire syntax screening, NOT recorded as completion
      # of integrated G0: no Host provenance or verified stage predecessor.
      inspect_sd_wire!(root, typ: "example+sd-jwt")
      inspect_sd_wire!(terminal, typ: "kb+sd-jwt")
      check_jws!(checkout, typ: "JWT")
      checked << "original_wire_syntax_only"

      # Host clock must be independent of signed claim timestamps; currently
      # it is supplied by the caller, so it remains UNAUTHENTICATED.
      unless verified_at.is_a?(Integer) &&
          verified_at.between?(1, AP2E06IHostSnapshot::MAX_TIME)
        return a3_t1_diagnostic_result("HOLD", "host_clock_provenance_unavailable", checked)
      end

      # Existing A3-H1 composite rejects any known-invalid source over an
      # unrelated source HOLD; no claim can prove Host enrollment or CAS.
      # The exact frozen Host wire is reused for both inspections.
      combined = AP2E06IHostSnapshot.inspect_untrusted_sources_only!(
        host_json: host, expected_sha256: expected_host_sha256,
        verified_at: verified_at, host_source_json: host_source_json,
        expected_host_source_sha256: expected_host_source_sha256,
        nonce_source_json: nonce_source_json,
        expected_nonce_source_sha256: expected_nonce_source_sha256
      )
      checked << "untrusted_host_and_nonce_source_claims_only"
      candidate = AP2E06IHostSnapshot.inspect_candidate!(
        host_json: host, expected_sha256: expected_host_sha256,
        verified_at: verified_at
      )
      context = AP2E06IStageContext.build_claim_only!(
        candidate: candidate, combined_claim: combined, root_wire: root,
        terminal_wire: terminal, checkout_wire: checkout, verified_at: verified_at
      )
      checked << "immutable_original_wire_identity_only"

      unless ROOT.jwt_supported?
        return a3_t1_diagnostic_result("HOLD", "verification_unavailable:jwt_version", checked)
      end
      # This key and verified_at are only from an inspected but UNTRUSTED
      # Host candidate. This is a signed-Root clock/closure diagnostic, never
      # an authenticated Issuer/G3 stage or permission to run G4 onwards.
      root_claim = ROOT.verify_full_root_at!(
        root, trusted_jwk: candidate.snapshot.fetch("issuer_trust").fetch("key_jwk"),
        verified_at: context.verified_at
      )
      checked << "signed_root_claimed_key_clock_only"
      unless root_claim.fetch("cnf").fetch("jwk") ==
          candidate.snapshot.fetch("agent_trust").fetch("key_jwk")
        return a3_t1_diagnostic_result(
          "REJECT", "root_agent_host_claim_mismatch", checked
        )
      end

      # Even fully matching signed Root time/profile, Host-source labels and
      # nonce assertions do not authenticate G1 or ensure replay safety.
      a3_t1_diagnostic_result(
        "HOLD", "host_provenance_and_durable_nonce_ledger_unproven", checked,
        context: context
      )
    rescue Halt => error
      a3_t1_diagnostic_result("REJECT", error.code, checked)
    # The A3-H1 composite may propagate the ORIGINAL source-specific Halt.
    # Do not turn definitive Host enrollment/nonce REJECT into generic HOLD.
    rescue AP2E06IHostSnapshot::Halt, AP2E06IStageContext::Halt,
           AP2E06IHostSource::Halt, AP2E06INonceIssuanceSource::Halt => error
      a3_t1_diagnostic_result(error.status, error.code, checked)
    rescue ROOT::Rejected => error
      reason = error.message
      status = reason.start_with?("verification_unavailable:") ||
        reason == "verification_clock_unavailable" ? "HOLD" : "REJECT"
      a3_t1_diagnostic_result(status, reason, checked)
    rescue JSON::ParserError, ArgumentError, TypeError, KeyError
      a3_t1_diagnostic_result("REJECT", "invalid_diagnostic_input", checked)
    rescue StandardError
      a3_t1_diagnostic_result("HOLD", "diagnostic_verification_unavailable", checked)
    end

    # Synthetic fixture inputs are NOT a Host authorization decision.
    # policy_json MUST come from the independent Host fixture, not a token.
    def observe(policy_json:, case_data:, policy_digest:)
      current = STAGES.fetch(0)
      reached = []
      # Dependency semantics are part of the bounded E06-I research profile.
      # Never emit successful G0/G1/G2/G3 stages under unreviewed jwt versions.
      unless ROOT.jwt_supported?
        return {
          "status" => "HOLD", "first_reject_stage" => current,
          "reason" => "verification_unavailable:jwt_version",
          "completed_stages" => reached.freeze, "evidence" => nil
        }
      end
      raise Halt, "invalid_input" unless case_data.is_a?(Hash) &&
        case_data.keys.sort == %w[candidate root terminal]
      root, terminal, candidate = case_data.values_at("root", "terminal", "candidate")
      raise Halt, "resource_limit" unless [root, terminal].all? do |wire|
        wire.is_a?(String) && wire.ascii_only? && wire.bytesize.between?(1, 32_768)
      end
      # Bound the untrusted presentation key before Host policy comparison.
      # Key material is never used as a trust source; G1 chooses Host's key.
      raise Halt, "resource_limit" unless candidate.is_a?(Hash) &&
        candidate.size == 4 && candidate.keys.all? { |k| k.is_a?(String) } &&
        candidate.keys.sort == %w[crv kty x y] &&
        candidate.values.all? { |v| v.is_a?(String) && v.ascii_only? && v.bytesize.between?(1, 128) }
      candidate_bytes = JSON.generate(candidate).bytesize
      raise Halt, "resource_limit" unless policy_json.is_a?(String) &&
        policy_json.ascii_only? && policy_json.bytesize.between?(1, 16_384) &&
        root.bytesize + terminal.bytesize + policy_json.bytesize + candidate_bytes <= 131_072

      untrusted_policy = AP2StrictJSONResearch.parse!(policy_json)
      check_tree_bounds!(untrusted_policy)
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
        {
          algorithms: ["ES256"],
          # A valid G2 signature cannot be downgraded by JWT claim checks.
          # Claims/profile semantics are evaluated in the following stages.
          verify_expiration: false,
          verify_not_before: false,
          verify_iat: false,
          verify_iss: false,
          verify_aud: false,
          verify_jti: false
        }
      )
      raise Halt, "invalid_issuer_signature" unless signed_root == decoded
      reached << current

      current = STAGES.fetch(3)
      # Isolated snapshot of the DC04 Root code repeats G2 with the Host key
      # and performs original signed Root whole-graph closure / local shape.
      # This copy avoids loading minitest/autorun through old P1-1.
      # "reached G3" is marked only when THIS call succeeds.
      verified_open = ROOT.verify_full_root!(root, trusted_jwk: trusted)
      raise Halt, "unsupported_profile" unless verified_open.is_a?(Hash)
      reached << current

      # Conditional synthetic G4 only: Host policy, clock and issuer
      # enrollment are NOT independently authenticated. G4 never calls
      # P1-2/P1-3's mixed crypto/commerce verify! entrypoints.
      current = STAGES.fetch(4)
      G4.inspect!(
        root_wire: root, terminal_wire: terminal, verified_open: verified_open,
        expected_agent_jwk: policy.fetch("expected_agent_public_jwk"),
        trusted_merchant_jwk: policy.fetch("trusted_merchant_public_jwk"),
        expected_aud: policy.fetch("expected_aud"),
        expected_nonce: policy.fetch("expected_nonce"),
        host_checkout_jwt: policy.fetch("host_checkout_jwt")
      )
      reached << current

      # Neither Schema (G5) nor commerce/Host semantics (G6) runs here.
      # This is a blocked NEXT stage, NOT a G5 reject or VerifiedEvidence.
      current = STAGES.fetch(5)
      {
        "status" => "HOLD", "first_reject_stage" => nil,
        "blocked_stage" => current, "reason" => "G5_G6_G7_NOT_WIRED",
        "g1_admissible" => false,
        "completed_stages" => reached.freeze, "evidence" => nil
      }
    rescue G4::Rejected => error
      {
        "status" => "REJECT", "first_reject_stage" => current,
        "reason" => error.code, "completed_stages" => reached.freeze,
        "evidence" => nil
      }
    rescue G4::Unavailable => error
      {
        "status" => "HOLD", "first_reject_stage" => nil,
        "blocked_stage" => current, "reason" => error.message,
        "completed_stages" => reached.freeze, "evidence" => nil
      }
    rescue HOST::Rejected => error
      {
        "status" => "REJECT", "first_reject_stage" => current,
        "reason" => error.code, "completed_stages" => reached.freeze,
        "evidence" => nil
      }
    rescue ROOT::Rejected => error
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


    # All outputs are diagnostics, NOT source-authenticated stage records.
    # A REJECT here is local negative evidence only; the integrated G0–G7
    # state machine was never invoked, so first_reject_stage stays nil.
    def a3_t1_diagnostic_result(status, reason, checked, context: nil)
      {
        "status" => status,
        "reason" => reason,
        "checked_components" => checked.freeze,
        "completed_stages" => [].freeze,
        "first_reject_stage" => nil,
        "g1_admissible" => false,
        "g3_authenticated" => false,
        "evidence" => nil,
        "original_wire_sha256" => context && {
          "root" => context.root_wire_sha256,
          "terminal" => context.terminal_wire_sha256,
          "checkout" => context.checkout_wire_sha256
        }.freeze
      }.freeze
    end

    # G0 structural/strict parse ONLY; the returned original JWS is untrusted.
    def inspect_sd_wire!(wire, typ:)
      parts = wire.split("~", -1)
      raise Halt, "invalid_sd_segments" unless parts.length.between?(3, 18) &&
        parts.last == "" && parts[1...-1].length.between?(1, 16)
      check_jws!(parts.first, typ: typ)
      parts[1...-1].each do |part|
        parsed = AP2StrictJSONResearch.decode_part!(part)
        check_tree_bounds!(parsed)
      end
      parts.first
    end

    def check_jws!(compact, typ:)
      header_part, payload_part, signature_part =
        AP2StrictJSONResearch.jwt_parts!(compact)
      # The shared strict parser checks header/payload; G0 also verifies
      # the third segment is nonempty, canonical base64url and ES256 length.
      raise Halt, "invalid_jws_signature_encoding" unless
        signature_part.match?(/\A[A-Za-z0-9_-]+\z/)
      signature = Base64.urlsafe_decode64(
        signature_part + ("=" * (-signature_part.bytesize % 4))
      )
      raise Halt, "invalid_jws_signature_encoding" unless
        signature.bytesize == 64 &&
        Base64.urlsafe_encode64(signature, padding: false) == signature_part

      header = AP2StrictJSONResearch.decode_part!(header_part)
      payload = AP2StrictJSONResearch.decode_part!(payload_part)
      check_tree_bounds!(header)
      check_tree_bounds!(payload)
      raise Halt, "unsupported_jose_header" unless header.is_a?(Hash) &&
        header["alg"] == "ES256" && header["typ"] == typ &&
        (header.keys - %w[alg kid typ]).empty? &&
        (header["kid"].nil? || header["kid"].is_a?(String))
      compact
    rescue JSON::ParserError => error
      # Signature/body JSON ambiguity belongs to G0, not a generic failure
      # and certainly not proof of G2 signature verification.
      code = if error.message.include?("duplicate JSON object key")
        "ambiguous_signed_json"
      else
        "invalid_signed_json"
      end
      raise Halt, code
    end

    # Recursive capped research shape; no authorization semantics.
    # The untrusted Host policy, all signed JWS JSON, and each disclosure
    # are checked BEFORE G0 can be recorded as completed.
    def check_tree_bounds!(value, depth = 0)
      raise Halt, "resource_limit" if depth > 24
      case value
      when Hash
        raise Halt, "resource_limit" if value.size > 32
        value.each_value { |child| check_tree_bounds!(child, depth + 1) }
      when Array
        raise Halt, "resource_limit" if value.size > 16
        value.each { |child| check_tree_bounds!(child, depth + 1) }
      end
      value
    end
  end
end
