# frozen_string_literal: true
#
# Phase 2-A E06-I approval A, isolated research-only stage observer.
# WARNING: G0–G5 conditional synthetic-only; G6/G7 deliberately HOLD.
# G5 is only a staged offline candidate, NOT a Host or Issuer trust proof.
# This is NOT an integrated verifier, not authorization and not a Gem API.
# Never relabel a G0 or G1 reject as proof of signature/SD closure.
require "json"
require "digest"
require "base64"
require_relative "isolated_host_policy"
require_relative "isolated_host_snapshot"
require_relative "isolated_root_closure"
require_relative "isolated_g4_crypto"
# Reuse both pre-existing offline validators; neither provides authorization.
require_relative "schema_gate"
require_relative "isolated_checkout_shape"
require_relative "isolated_stage_context"
# A3-T1 diagnostic needs these distinct Halt classes to preserve REJECT.
# Modules define contracts only; no fixtures, tests or runner are loaded.
require_relative "isolated_host_source"
require_relative "isolated_nonce_issuance_source"

module AP2E06IPartialProbe
  HOST = AP2E06IHostPolicy
  ROOT = AP2E06IRootClosure
  G4 = AP2E06IG4Crypto
  SCHEMA = AP2E06ISchemaGate
  SHAPE = AP2E06ILocalCheckoutShape
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
    # The synthetic-only `verified_at:` is explicit: no unreviewed wall-clock
    # fallback can cause G4 to be recorded complete. It is NOT B1 Host proof.
    def observe(policy_json:, case_data:, policy_digest:, verified_at: nil,
                upstream_root: nil)
      current = STAGES.fetch(0)
      reached = []
      # Dependency semantics are part of the bounded E06-I research profile.
      # Never emit successful G0/G1/G2/G3 stages under unreviewed jwt versions.
      unless ROOT.jwt_supported?
        return {
          "status" => "HOLD", "first_reject_stage" => current,
          "reason" => "verification_unavailable:jwt_version",
          "stage_trace_basis" => "synthetic_conditional_only",
          "completed_stages" => reached.freeze, "evidence" => nil
        }
      end
      # G0: never call keys/values/to_h on a caller-controlled Hash. Even a
      # concurrently growing Hash may only supply these three named members.
      required_case = %w[candidate root terminal]
      raise Halt, "invalid_input" unless case_data.instance_of?(Hash) &&
        case_data.size == 3 && required_case.all? { |key| case_data.key?(key) }
      root_source = case_data.fetch("root")
      terminal_source = case_data.fetch("terminal")
      candidate_source = case_data.fetch("candidate")
      raise Halt, "invalid_input" unless
        policy_json.is_a?(String) && root_source.is_a?(String) &&
        terminal_source.is_a?(String)
      # Precheck, bounded copy, and detach originals BEFORE any parsing.
      root = bounded_wire_snapshot!(root_source, 32_768)
      terminal = bounded_wire_snapshot!(terminal_source, 32_768)
      policy_json = bounded_wire_snapshot!(policy_json, 16_384)

      # Extract exactly four *named* candidate JWK members. No enumeration of
      # a mutable untrusted Hash is allowed, including on failure paths.
      jwk_fields = %w[crv kty x y]
      raise Halt, "resource_limit" unless candidate_source.instance_of?(Hash) &&
        candidate_source.size == 4 &&
        jwk_fields.all? { |key| candidate_source.key?(key) }
      candidate = jwk_fields.to_h do |key|
        [key, bounded_wire_snapshot!(candidate_source.fetch(key), 128)]
      end.freeze
      raise Halt, "resource_limit" unless
        candidate_source.size == 4 &&
        jwk_fields.all? { |key|
          candidate_source.key?(key) &&
            candidate_source.fetch(key) == candidate.fetch(key)
        }
      raise Halt, "invalid_input" unless
        case_data.size == 3 &&
        required_case.all? { |key| case_data.key?(key) } &&
        case_data.fetch("root").equal?(root_source) &&
        case_data.fetch("terminal").equal?(terminal_source) &&
        case_data.fetch("candidate").equal?(candidate_source)
      candidate_bytes = JSON.generate(candidate).bytesize
      raise Halt, "resource_limit" unless
        policy_json.ascii_only? && policy_json.bytesize.between?(1, 16_384) &&
        root.bytesize + terminal.bytesize + policy_json.bytesize + candidate_bytes <= 131_072

      # Digest remains caller-asserted rather than Host-authenticated.
      # It is always bounded before copying and must have a pinned form.
      policy_digest = bounded_wire_snapshot!(policy_digest, 64)
      raise Halt, "invalid_host_context" unless
        policy_digest.match?(/\A[0-9a-f]{64}\z/)
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
      # The instant is caller-asserted and therefore NOT authoritative Host
      # time. No G1 stage completion is recorded for missing/out-of-window
      # claims, and no implicit Time.now fallback is permitted.
      unless verified_at.is_a?(Integer) &&
          verified_at.between?(1, ROOT::MAX_VERIFIED_AT) &&
          policy["not_before"].is_a?(Integer) &&
          policy["not_after"].is_a?(Integer) &&
          policy["not_before"] <= verified_at &&
          verified_at < policy["not_after"]
        return {
          "status" => "HOLD", "first_reject_stage" => nil,
          "blocked_stage" => current,
          "reason" => "synthetic_clock_or_policy_window_unavailable",
          "g1_admissible" => false,
          "stage_trace_basis" => "synthetic_conditional_only",
          "completed_stages" => reached.freeze, "evidence" => nil
        }
      end
      trusted = HOST.verify_candidate_at!(
        policy, candidate, case_policy_digest: policy_digest,
        verified_at: verified_at
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
      verified_open = ROOT.verify_full_root_at!(
        root, trusted_jwk: trusted, verified_at: verified_at
      )
      raise Halt, "unsupported_profile" unless verified_open.is_a?(Hash)
      reached << current

      # Conditional synthetic G4 only: Host policy, clock and issuer
      # enrollment are NOT independently authenticated. G4 never calls
      # P1-2/P1-3's mixed crypto/commerce verify! entrypoints.
      current = STAGES.fetch(4)
      # Pin the exact G1 synthetic policy input, not a reconstructed Hash or
      # caller-supplied "success" marker. An A4 artifact stays private to this
      # single call and is not an authorization/evidence object.
      host_policy_wire_sha256 = Digest::SHA256.hexdigest(policy_json.b).freeze
      g4_result = G4.inspect!(
        root_wire: root, terminal_wire: terminal, verified_open: verified_open,
        expected_agent_jwk: policy.fetch("expected_agent_public_jwk"),
        trusted_merchant_jwk: policy.fetch("trusted_merchant_public_jwk"),
        expected_aud: policy.fetch("expected_aud"),
        expected_nonce: policy.fetch("expected_nonce"),
        host_checkout_jwt: policy.fetch("host_checkout_jwt"),
        verified_at: verified_at, terminal_not_after: policy.fetch("not_after"),
        host_policy_wire_sha256: host_policy_wire_sha256,
        host_policy_digest: policy.fetch("policy_digest")
      )
      # The result must be an internal G4 type bound to these exact original
      # frozen bytes, G3 verified Open, Host policy and single verification
      # instant. Any mismatch is unavailable, never a later-stage PASS.
      unless G4.same_invocation_result?(
        g4_result, root_wire: root, terminal_wire: terminal,
        host_checkout_jwt: policy.fetch("host_checkout_jwt"),
        verified_open: verified_open,
        host_policy_wire_sha256: host_policy_wire_sha256,
        host_policy_digest: policy.fetch("policy_digest"),
        verified_at: verified_at
      )
        raise G4::Unavailable, "g4_authenticated_handoff_unavailable"
      end
      reached << current

      # G5 runs ONLY after the same-invocation private G4 chain passed all
      # original-wire and synthetic Host-context correlation checks above.
      # The caller must EXPLICITLY supply a pre-existing, pinned AP2 source
      # tree. Missing/unsafe path => G5 HOLD, never schema-invalid REJECT.
      current = STAGES.fetch(5)
      unless upstream_root.instance_of?(String) &&
          upstream_root.bytesize.between?(1, 1024) &&
          !upstream_root.include?("\0")
        return {
          "status" => "HOLD", "first_reject_stage" => nil,
          "blocked_stage" => current, "reason" => "verification_unavailable",
          "g1_admissible" => false,
          "stage_trace_basis" => "synthetic_conditional_only",
          "completed_stages" => reached.freeze, "evidence" => nil
        }
      end

      # Gate.new enforces json_schemer=2.5.0, three pinned official schema
      # blobs, exact $id/$schema and a local-only Merchant $ref resolver.
      # No source checkout, dependency installation or network fallback here.
      official_gate = SCHEMA::Gate.new(upstream_root: upstream_root)
      official = official_gate.check!(
        open: g4_result.verified_open, closed: g4_result.verified_closed
      )
      # The official nested Merchant Schema does NOT validate the separate
      # Merchant-signed Checkout JWT JSON. Its strict local shape is mandatory.
      # Pre-existing ShapeOnly is NOT itself a trusted/authenticated marker.
      local = SHAPE::Gate.new.check!(
        verified_checkout_payload: g4_result.verified_checkout_payload
      )
      unless official.instance_of?(Hash) &&
          official["open"] == "VALID" &&
          official["closed"] == "VALID" &&
          official["merchant_ref"] == "LOCAL_PINNED" &&
          local.instance_of?(SHAPE::ShapeOnly) &&
          local.frozen? && local.local_checkout_shape == "VALID" &&
          local.authority == "NONE_SHAPE_ONLY" &&
          !local.authenticated? && local.evidence.nil?
        return {
          "status" => "HOLD", "first_reject_stage" => nil,
          "blocked_stage" => current, "reason" => "g5_gate_result_unavailable",
          "g1_admissible" => false,
          "stage_trace_basis" => "synthetic_conditional_only",
          "completed_stages" => reached.freeze, "evidence" => nil
        }
      end
      # Local report is constructed only here, after BOTH checks succeeded
      # on G4's detached signed data. Never accept a caller-provided G5 flag.
      g5_checks = {
        "official_open" => official.fetch("open"),
        "official_closed" => official.fetch("closed"),
        "official_merchant_ref" => official.fetch("merchant_ref"),
        "local_checkout_shape" => local.local_checkout_shape,
        "original_checkout_wire_sha256" => g4_result.wire_sha256.fetch("checkout"),
        "host_policy_wire_sha256" => host_policy_wire_sha256,
        "pinned_schema_fingerprints" => official_gate.fingerprints
      }.freeze
      reached << current

      # G6 Host identity/cart/constraint/price and G7 evidence remain absent.
      # Even successful G5 is conditional on caller-supplied synthetic trust.
      current = STAGES.fetch(6)
      {
        "status" => "HOLD", "first_reject_stage" => nil,
        "blocked_stage" => current, "reason" => "G6_G7_NOT_WIRED",
        "g1_admissible" => false,
        "stage_trace_basis" => "synthetic_conditional_only",
        "g5_checks" => g5_checks,
        "completed_stages" => reached.freeze, "evidence" => nil
      }
    rescue SCHEMA::Rejected => error
      # Only genuine post-G4 official Schema failures count as G5 negatives.
      # Any missing/wrong library, source, digest or $ref => HOLD at G5.
      invalid = %w[invalid_open_schema invalid_closed_schema].include?(error.code)
      {
        "status" => invalid ? "REJECT" : "HOLD",
        "first_reject_stage" => invalid ? current : nil,
        "blocked_stage" => invalid ? nil : current,
        "reason" => invalid ? error.code : "verification_unavailable",
        "g1_admissible" => false,
        "stage_trace_basis" => "synthetic_conditional_only",
        "completed_stages" => reached.freeze, "evidence" => nil
      }
    rescue SHAPE::Rejected => error
      # Local fixed Checkout structural reject is NOT a business G6 verdict.
      {
        "status" => "REJECT", "first_reject_stage" => current,
        "reason" => "unsupported_checkout_profile",
        "local_shape_code" => error.code,
        "g1_admissible" => false,
        "stage_trace_basis" => "synthetic_conditional_only",
        "completed_stages" => reached.freeze, "evidence" => nil
      }
    rescue G4::Rejected => error
      {
        "status" => "REJECT", "first_reject_stage" => current,
        "reason" => error.code, "stage_trace_basis" => "synthetic_conditional_only",
        "completed_stages" => reached.freeze,
        "evidence" => nil
      }
    rescue G4::Unavailable => error
      {
        "status" => "HOLD", "first_reject_stage" => nil,
        "blocked_stage" => current, "reason" => error.message,
        "stage_trace_basis" => "synthetic_conditional_only",
        "completed_stages" => reached.freeze, "evidence" => nil
      }
    rescue HOST::Rejected => error
      {
        "status" => "REJECT", "first_reject_stage" => current,
        "reason" => error.code, "stage_trace_basis" => "synthetic_conditional_only",
        "completed_stages" => reached.freeze,
        "evidence" => nil
      }
    rescue ROOT::Rejected => error
      {
        "status" => "REJECT", "first_reject_stage" => current,
        "reason" => error.message, "stage_trace_basis" => "synthetic_conditional_only",
        "completed_stages" => reached.freeze,
        "evidence" => nil
      }
    rescue Halt => error
      {
        "status" => "REJECT", "first_reject_stage" => current,
        "reason" => error.code, "stage_trace_basis" => "synthetic_conditional_only",
        "completed_stages" => reached.freeze,
        "evidence" => nil
      }
    rescue JWT::DecodeError, JWT::JWKError
      {
        "status" => "REJECT", "first_reject_stage" => current,
        "reason" => "invalid_issuer_signature", "stage_trace_basis" => "synthetic_conditional_only",
        "completed_stages" => reached.freeze,
        "evidence" => nil
      }
    rescue JSON::ParserError, ArgumentError, TypeError, KeyError
      {
        "status" => "REJECT", "first_reject_stage" => current,
        "reason" => "invalid_input_or_ambiguous_json", "stage_trace_basis" => "synthetic_conditional_only",
        "completed_stages" => reached.freeze,
        "evidence" => nil
      }
    rescue StandardError
      # Other local exceptions must not authorize anything; never emit a
      # successfully verified stage or a serialized exception / sensitive wire.
      {
        "status" => "HOLD", "first_reject_stage" => current,
        "reason" => "unexpected_unverified_failure",
        "stage_trace_basis" => "synthetic_conditional_only",
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

    # Snapshot untrusted inputs WITHOUT ever copying more than max + 1 bytes.
    # Precheck avoids allocations for plainly oversized inputs; the bounded
    # slice and postchecks also fail closed on concurrent source mutation.
    def bounded_wire_snapshot!(source, max)
      raise Halt, "resource_limit" unless source.is_a?(String) &&
        source.bytesize.between?(1, max)
      copy = source.byteslice(0, max + 1)
      raise Halt, "resource_limit" unless copy.is_a?(String) &&
        copy.bytesize.between?(1, max) &&
        copy.bytesize == source.bytesize && copy.ascii_only? &&
        source == copy
      copy.freeze
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
