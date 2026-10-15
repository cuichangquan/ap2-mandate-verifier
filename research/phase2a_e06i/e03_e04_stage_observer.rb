# frozen_string_literal: true
#
# Issue #73 A-E03/E04. SOURCE ONLY / NOT RUN / NO APPROVAL B.
# Compares actual same-invocation G3 reject stages against a SEPARATELY
# executed original Root O1/O3 oracle. Never treats a caller-provided oracle
# JSON as source attestation, Host enrollment, or an authorization capability.
# Existing observe_integrated.rb and integrated_probe.rb remain unchanged.
require "json"
require "digest"
require "optparse"
require_relative "observe_integrated"

module AP2E06IE03E04StageObserver
  A7 = AP2E06IA7SignedReachability
  PROBE = AP2E06IPartialProbe
  HOST = AP2E06IHostPolicy
  PINNED_AP2 = "b4587ac1d055888a73b4b21750973cffba961793"
  IDS = %w[FULL HIDDEN UNKNOWN DUPLICATE EXTRA DECOY].freeze
  CLASSES = {
    "FULL" => "FULL",
    "HIDDEN" => "MISSING",
    "UNKNOWN" => "UNKNOWN_SLOT",
    "DUPLICATE" => "DUPLICATE",
    "EXTRA" => "UNUSED",
    "DECOY" => "MISSING"
  }.freeze
  # These are literal reasons from the pre-existing isolated_root_closure.rb.
  # Never relax these to a broad "REJECT anywhere" predicate.
  G3_REASONS = {
    "HIDDEN" => ["incomplete_disclosure: missing disclosure"],
    "UNKNOWN" => [
      "unsupported signed commitment path",
      "unsupported object SD/decoy or misplaced marker"
    ],
    "DUPLICATE" => ["repeated signed commitment"],
    "EXTRA" => ["unused/decoy disclosure"],
    "DECOY" => ["incomplete_disclosure: missing disclosure"]
  }.freeze

  class Stop < StandardError; end

  class << self
    def demand!(condition, reason)
      raise Stop, reason unless condition
    end

    def sha(bytes)
      Digest::SHA256.hexdigest(bytes.b)
    end

    def exact_keys!(obj, keys)
      demand!(obj.instance_of?(Hash) && obj.keys.sort == keys.sort,
              "unexpected_input_shape")
    end

    def read_json!(path, cap)
      raw = A7.safe_read!(path, cap)
      [A7.parse!(raw), raw]
    end

    def observe!(fixture_path:, policy_path:, oracle_path:, upstream_root:,
                 report_path:)
      fixture, fixture_raw = read_json!(fixture_path, 262_144)
      policy_candidate, policy_raw = read_json!(policy_path, 16_384)
      oracle, oracle_raw = read_json!(oracle_path, 65_536)

      exact_keys!(fixture, %w[ap2_commit cases])
      demand!(fixture["ap2_commit"] == PINNED_AP2, "upstream_mismatch")
      exact_keys!(fixture["cases"], IDS)
      exact_keys!(oracle, %w[
        case_id pinned_ap2_sha fixture_sha256 policy_sha256 cases oracle_scope
        o2_agent_merchant o4_schema o5_ruby_stage host_authority
        e03_e04_exit_gate conclusion
      ])
      exact_keys!(oracle.fetch("cases"), IDS)
      demand!(
        oracle["case_id"] == "E03E04_A_SOURCE_ONLY_ORACLE" &&
        oracle["pinned_ap2_sha"] == PINNED_AP2 &&
        oracle["fixture_sha256"] == sha(fixture_raw) &&
        oracle["policy_sha256"] == sha(policy_raw) &&
        oracle["oracle_scope"] == "O1_ISSUER_ONLY_O3_ORIGINAL_ROOT_GRAPH" &&
        oracle["o2_agent_merchant"] == "NOT_CHECKED" &&
        oracle["o4_schema"] == "NOT_CHECKED" &&
        oracle["o5_ruby_stage"] == "NOT_RUN" &&
        oracle["host_authority"] == "NOT_ESTABLISHED" &&
        oracle["e03_e04_exit_gate"] == "UNPROVEN" &&
        oracle["conclusion"] == "HOLD_NO_PHASE2B_OR_PAYMENT_AUTHORIZATION",
        "untrusted_oracle_claim"
      )

      # Host policy is a synthetic test CLAIM, not an authenticated G1 source.
      # The independent oracle's signature check uses its issuer public key,
      # but this by itself says nothing about real Issuer onboarding.
      HOST.load!(policy_raw)
      demand!(
        policy_candidate["tenant_scope"] == "synthetic-e01s" &&
        policy_candidate["profile_ref"] == "e01s-fixed-a-v1" &&
        policy_candidate["issuer_public_jwk"].instance_of?(Hash) &&
        policy_candidate["policy_digest"].instance_of?(String) &&
        policy_candidate["freeze_epoch"].instance_of?(Integer),
        "host_authority_unproven"
      )
      clock = policy_candidate.fetch("freeze_epoch")
      demand!(clock.between?(1, AP2E06IRootClosure::MAX_VERIFIED_AT),
              "invalid_synthetic_clock")

      # G0→G3 use the pre-existing Ruby candidate; no alternate parser is
      # accepted as a substitute for actual stage arrival and first rejection.
      per_case = {}
      IDS.each do |id|
        case_data = fixture.fetch("cases").fetch(id)
        oracle_case = oracle.fetch("cases").fetch(id)
        exact_keys!(case_data, %w[root terminal])
        exact_keys!(oracle_case, %w[
          issuer_signature root_wire_sha256 terminal_wire_sha256
          graph_class expected_g3 g1_authority
        ])
        root = case_data.fetch("root")
        terminal = case_data.fetch("terminal")
        demand!(root.instance_of?(String) && terminal.instance_of?(String) &&
                root.ascii_only? && terminal.ascii_only? &&
                root.bytesize.between?(1, 32_768) &&
                terminal.bytesize.between?(1, 32_768),
                "invalid_signed_wire")
        demand!(
          oracle_case["issuer_signature"] ==
            "VALID_UNDER_SYNTHETIC_POLICY_KEY" &&
          oracle_case["root_wire_sha256"] == sha(root) &&
          oracle_case["terminal_wire_sha256"] == sha(terminal) &&
          oracle_case["graph_class"] == CLASSES.fetch(id) &&
          oracle_case["expected_g3"] ==
            (id == "FULL" ? "PASS_CONDITIONAL" : "REJECT") &&
          oracle_case["g1_authority"] == "NOT_ESTABLISHED",
          "oracle_case_mismatch"
        )

        result = PROBE.observe(
          policy_json: policy_raw,
          case_data: {
            "candidate" => policy_candidate.fetch("issuer_public_jwk"),
            "root" => root,
            "terminal" => terminal
          },
          policy_digest: policy_candidate.fetch("policy_digest"),
          verified_at: clock,
          upstream_root: upstream_root
        )
        demand!(result.instance_of?(Hash) && result["evidence"].nil? &&
                result["stage_trace_basis"] == "synthetic_conditional_only" &&
                result["g1_admissible"] != true,
                "unauthorized_stage_evidence")

        stages = result["completed_stages"]
        demand!(stages.instance_of?(Array) &&
                stages == PROBE::STAGES.take(stages.size) &&
                stages.size <= 6, "invalid_stage_trace")
        # FULL needs genuine G3 and G4/G5 stage arrival in this SAME call;
        # downstream Host semantics and VerifiedEvidence deliberately HOLD.
        matched = if id == "FULL"
          result["status"] == "HOLD" &&
            result["blocked_stage"] == PROBE::STAGES.fetch(6) &&
            result["first_reject_stage"].nil? &&
            result["reason"] == "G6_G7_NOT_WIRED" &&
            stages == PROBE::STAGES.take(6)
        else
          result["status"] == "REJECT" &&
            result["first_reject_stage"] == PROBE::STAGES.fetch(3) &&
            stages == PROBE::STAGES.take(3) &&
            G3_REASONS.fetch(id).include?(result["reason"])
        end
        # Fixed labels prevent tokens, exception strings or Host PII in output.
        per_case[id] = {
          "status" => result["status"] == "REJECT" ? "REJECT" : "HOLD",
          "first_reject_stage" =>
            PROBE::STAGES.include?(result["first_reject_stage"]) ?
              result["first_reject_stage"] : nil,
          "completed_stages" => stages.dup,
          "reason_class" => matched ? "EXPECTED_STAGE" : "STAGE_MISMATCH",
          "matched_causal_stage" => matched,
          "root_wire_sha256" => sha(root)
        }
      end

      all_matched = per_case.values.all? { |v| v["matched_causal_stage"] }
      report = {
        "case_id" => "E03E04_A_RUBY_G3_STAGE_OBSERVER",
        "status" => "HOLD",
        "stage_expectations_match" => all_matched,
        "source_provenance" => "UNVERIFIED_EXTERNAL_RUNNER",
        "host_g1_authority" => "NOT_ESTABLISHED",
        "o1_o3_oracle_source" => "EXTERNAL_UNATTESTED_CLAIM",
        "o2_o4_independent" => "NOT_CHECKED",
        "g6_g7" => "HOLD_NOT_WIRED",
        "pinned_ap2_sha" => PINNED_AP2,
        "fixture_sha256" => sha(fixture_raw),
        "policy_sha256" => sha(policy_raw),
        "oracle_sha256" => sha(oracle_raw),
        "cases" => per_case,
        "e03_e04_exit_gate" => "UNPROVEN",
        "conclusion" => "NOT_A_PAYMENT_OR_PHASE2B_AUTHORIZATION"
      }
      A7.write_report_exclusive!(report_path, report)
      false # Always HOLD: code existence or stage matching is not Gate PASS.
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    options = {}
    parser = OptionParser.new do |args|
      %w[fixture policy oracle upstream_root report].each do |name|
        args.on("--#{name.tr('_', '-')} FILE") { |value| options[name] = value }
      end
    end
    parser.parse!(ARGV)
    raise AP2E06IE03E04StageObserver::Stop, "unexpected_arguments" unless
      ARGV.empty? && options.keys.sort ==
        %w[fixture policy oracle upstream_root report].sort
    AP2E06IE03E04StageObserver.observe!(
      fixture_path: options.fetch("fixture"),
      policy_path: options.fetch("policy"),
      oracle_path: options.fetch("oracle"),
      upstream_root: options.fetch("upstream_root"),
      report_path: options.fetch("report")
    )
    puts "E03/E04 G3: HOLD; source, Host, O2/O4 and G6/G7 unverified"
    exit 1
  rescue StandardError
    warn "E03/E04 G3: RED/HOLD; unverified causal stage"
    exit 1
  end
end
