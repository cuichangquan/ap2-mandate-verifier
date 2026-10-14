# frozen_string_literal: true
#
# E06-I A7: E01-S IP01/IP02/IP03 signed reachability observer, SOURCE ONLY.
# NOT RUN; no Approval B / no CI / no genuine Host authority or nonce CAS.
# Existing E06-I G0-G5 observer stays read-only. Synthetic outcomes are not
# VerifiedEvidence, Host ALLOW, production payment or Phase 2-B proof.
require "json"
require "digest"
require "optparse"
require "open3"
require "timeout"
require_relative "../shared/strict_json_research"
require_relative "integrated_probe"

module AP2E06IA7SignedReachability
  PINNED_AP2 = "b4587ac1d055888a73b4b21750973cffba961793"
  IDS = %w[IP01 IP02 IP03].freeze
  ROOT_FIELDS = %w[case_id ap2_commit policy_digest
                   candidate_issuer_public_jwks candidate_issuer_thumbprints
                   issuer_b_public_jwk roots terminals].sort.freeze
  STAGES = AP2E06IPartialProbe::STAGES

  class Stop < StandardError; end

  class << self
    def stop!(code)
      raise Stop, code
    end

    # Bound *the opened regular file*, not a pathname-stat followed by an
    # unbounded File.binread. Symlink swaps, FIFOs and size/mtime changes
    # cannot silently be promoted to valid fixture or independent evidence.
    def safe_read!(path, cap)
      stop!("invalid_path") unless path.instance_of?(String) &&
        path.bytesize.between?(1, 1024) && !path.include?("\0")
      stop!("safe_file_flags_unavailable") unless
        File.const_defined?(:NOFOLLOW) && File.const_defined?(:NONBLOCK)
      actual = File.realpath(path)
      before_path = File.lstat(path)
      stop!("unsafe_file") unless
        before_path.file? && before_path.size.between?(1, cap)
      flags = File::RDONLY | File::NOFOLLOW | File::NONBLOCK
      File.open(path, flags) do |file|
        file.binmode
        before_fd = file.stat
        stop!("input_changed") unless
          same_file?(before_path, before_fd) && File.realpath(path) == actual
        data = file.read(cap + 1)
        after_fd = file.stat
        stop!("input_changed") unless
          data.instance_of?(String) && data.bytesize.between?(1, cap) &&
          data.bytesize == before_fd.size &&
          same_file?(before_fd, after_fd) &&
          same_file?(after_fd, File.lstat(path)) &&
          File.realpath(path) == actual
        data.freeze
      end
    end

    def same_file?(a, b)
      a.file? && b.file? &&
        %i[dev ino mode nlink uid gid size mtime ctime].all? do |part|
          a.public_send(part) == b.public_send(part)
        end
    end

    def parse!(raw)
      obj = AP2StrictJSONResearch.parse!(raw)
      stop!("nonobject_input") unless obj.instance_of?(Hash)
      obj
    end

    def keys!(obj, fields)
      stop!("unsupported_fields") unless
        obj.instance_of?(Hash) && obj.keys.sort == fields.sort
    end

    def sha(raw)
      Digest::SHA256.hexdigest(raw.b)
    end

    # Git is queried read-only, without a shell or network. The caller must
    # separately approve execution under B and impose OS process time limits.
    # Never accept a caller-typed HEAD SHA as proof of tested source.
    def git_head!(path)
      stop!("invalid_repo_path") unless path.instance_of?(String) &&
        path.bytesize.between?(1, 1024) && !path.include?("\0")
      stdout, _stderr, status = Timeout.timeout(2) do
        Open3.capture3("git", "-C", File.realpath(path), "rev-parse", "HEAD")
      end
      stop!("git_head_unavailable") unless
        status.success? && stdout.strip.match?(/\A[0-9a-f]{40}\z/)
      stdout.strip.freeze
    rescue Timeout::Error
      stop!("git_head_unavailable")
    end

    def checked_observation(result)
      stop!("invalid_observer_result") unless result.instance_of?(Hash)
      status = result["status"]
      stop!("unauthorized_observer_status") unless %w[REJECT HOLD].include?(status)
      stop!("observer_authority_mismatch") unless
        result["evidence"].nil? &&
        result["stage_trace_basis"] == "synthetic_conditional_only" &&
        result["g1_admissible"] != true
      reached = result["completed_stages"]
      stop!("invalid_stage_trace") unless reached.instance_of?(Array) &&
        reached == STAGES.take(reached.size) && reached.size <= 6
      actual_reject = result["first_reject_stage"]
      blocked = result["blocked_stage"]
      stop!("invalid_first_stage") unless
        [actual_reject, blocked].all? { |stage| stage.nil? || STAGES.include?(stage) }
      reason = result["reason"]
      # Never copy raw tokens/nonce or exception text into a public report.
      safe_reason = reason.is_a?(String) &&
        reason.match?(/\A[a-zA-Z0-9_.:-]{1,96}\z/) ? reason : "redacted"
      {
        "status" => status,
        "first_reject_stage" => actual_reject,
        "blocked_stage" => blocked,
        "reason" => safe_reason,
        "completed_stages" => reached.dup.freeze,
        "stage_trace_basis" => "synthetic_conditional_only",
        "g1_admissible" => false,
        "evidence" => nil
      }
    end

    def run!(paths)
      expected_flags = %w[fixture policy e01_report independent_oracle
                          upstream_root report]
      keys!(paths, expected_flags)
      fixture_raw = safe_read!(paths.fetch("fixture"), 512_000)
      policy_raw = safe_read!(paths.fetch("policy"), 16_384)
      e01_raw = safe_read!(paths.fetch("e01_report"), 256_000)
      oracle_raw = safe_read!(paths.fetch("independent_oracle"), 128_000)
      fixture = parse!(fixture_raw)
      e01 = parse!(e01_raw)
      oracle = parse!(oracle_raw)
      keys!(fixture, ROOT_FIELDS)
      stop!("wrong_upstream_fixture") unless fixture["case_id"] == "E01-S" &&
        fixture["ap2_commit"] == PINNED_AP2 &&
        e01["case_id"] == "E01-S" && e01["pinned_ap2_sha"] == PINNED_AP2
      stop!("unverified_external_oracle") unless
        oracle["case_id"] == "E06I_A7_INDEPENDENT_CLOSED_SCHEMA" &&
        oracle["pinned_ap2_sha"] == PINNED_AP2 &&
        oracle["source_fixture_sha256"] == sha(fixture_raw) &&
        oracle["source_policy_sha256"] == sha(policy_raw) &&
        oracle["source_e01_report_sha256"] == sha(e01_raw) &&
        oracle["host_authority"] == "NONE_SYNTHETIC_ONLY" &&
        oracle["ruby_stage_result"] == "NOT_RUN" &&
        oracle["conclusion"] == "O1_O4_SYNTHETIC_ONLY_NOT_E06_GATE_PASS"
      policy = AP2E06IHostPolicy.load!(policy_raw)
      stop!("host_policy_is_only_synthetic") unless
        policy["tenant_scope"] == "synthetic-e01s" &&
        policy["profile_ref"] == "e01s-fixed-a-v1" &&
        fixture["policy_digest"] == policy["policy_digest"] &&
        e01["policy_digest"] == policy["policy_digest"]

      clock = policy.fetch("freeze_epoch")
      stop!("invalid_fixed_lab_clock") unless
        clock.is_a?(Integer) && clock.between?(1, 4_102_444_800)
      root_repo = File.expand_path("../..", __dir__)
      tested_head = git_head!(root_repo)
      pinned_tree_sha = git_head!(paths.fetch("upstream_root"))
      stop!("unpinned_ap2_checkout") unless pinned_tree_sha == PINNED_AP2

      %w[roots terminals candidate_issuer_public_jwks
         candidate_issuer_thumbprints].each do |name|
        stop!("invalid_case_set") unless
          fixture[name].instance_of?(Hash) && fixture[name].keys.sort == IDS
      end
      stop!("oracle_case_set_mismatch") unless
        oracle["cases"].instance_of?(Hash) &&
        oracle["cases"].keys.sort == IDS &&
        e01["oracles"].instance_of?(Hash) &&
        e01["oracles"].keys.sort == IDS
      fingerprints = oracle["schema_fingerprints"]
      stop!("missing_schema_fingerprints") unless
        fingerprints.instance_of?(Hash) &&
        fingerprints.keys.sort == %w[closed merchant open]
      per_case = {}
      IDS.each do |case_id|
        root = fixture.fetch("roots").fetch(case_id)
        terminal = fixture.fetch("terminals").fetch(case_id)
        signer = fixture.fetch("candidate_issuer_public_jwks").fetch(case_id)
        expected = oracle.fetch("cases").fetch(case_id)
        stop!("invalid_signed_case") unless
          root.instance_of?(String) && terminal.instance_of?(String) &&
          root.ascii_only? && terminal.ascii_only? &&
          root.bytesize.between?(1, 32_768) &&
          terminal.bytesize.between?(1, 32_768)
        stop!("independent_wire_mismatch") unless
          expected.instance_of?(Hash) &&
          expected["root_wire_sha256"] == sha(root) &&
          expected["terminal_wire_sha256"] == sha(terminal) &&
          expected["checkout_wire_sha256"] ==
            sha(policy.fetch("host_checkout_jwt")) &&
          expected["issuer_signed_root"] == "VALID_WITH_CASE_SIGNER" &&
          expected["agent_signed_terminal"] == "VALID" &&
          expected["merchant_signed_checkout"] == "VALID" &&
          expected["original_root_graph"] == "FULLY_DISCLOSED" &&
          expected["official_open_schema"] == "VALID" &&
          expected["official_closed_schema"] == "VALID" &&
          expected["nested_merchant_schema"] == "VALID"

        stop!("invalid_case_signer") unless
          signer.instance_of?(Hash) && signer.keys.sort == %w[crv kty x y] &&
          (case_id == "IP02" ?
            signer == fixture.fetch("issuer_b_public_jwk") :
            signer == policy.fetch("issuer_public_jwk")) &&
          AP2E06IHostPolicy.thumbprint(signer) ==
            fixture.fetch("candidate_issuer_thumbprints").fetch(case_id)
        result = AP2E06IPartialProbe.observe(
          policy_json: policy_raw,
          case_data: {
            "candidate" => signer, "root" => root, "terminal" => terminal
          },
          policy_digest: policy.fetch("policy_digest"),
          verified_at: clock,
          upstream_root: paths.fetch("upstream_root")
        )
        checked = checked_observation(result)
        case_expected = if case_id == "IP01"
          checked["status"] == "HOLD" &&
            checked["blocked_stage"] == STAGES.fetch(6) &&
            checked["reason"] == "G6_G7_NOT_WIRED" &&
            checked["completed_stages"] == STAGES.take(6) &&
            result["g5_checks"].instance_of?(Hash) &&
            result["g5_checks"]["original_checkout_wire_sha256"] ==
              expected["checkout_wire_sha256"] &&
            result["g5_checks"]["pinned_schema_fingerprints"] == fingerprints
        elsif case_id == "IP02"
          checked["status"] == "REJECT" &&
            checked["first_reject_stage"] == STAGES.fetch(1) &&
            checked["completed_stages"] == STAGES.take(1)
        else
          checked["status"] == "REJECT" &&
            checked["first_reject_stage"] == STAGES.fetch(3) &&
            checked["completed_stages"] == STAGES.take(3)
        end
        checked["matched_predeclared_stage"] = case_expected
        checked["root_wire_sha256"] = sha(root)
        checked["terminal_wire_sha256"] = sha(terminal)
        checked["checkout_wire_sha256"] = expected["checkout_wire_sha256"]
        per_case[case_id] = checked
      end
      control = per_case.fetch("IP01")
      matched = per_case.values.all? { |x| x["matched_predeclared_stage"] }
      report = {
        "case_id" => "E06I_A7_SIGNED_G5_REACHABILITY",
        "status" => matched ? "LIMITED_SYNTHETIC_G5_OBSERVED" : "RED_HOLD",
        "gate" => "PHASE2A_E03_E04_E06_UNPROVEN",
        "pinned_ap2_sha" => PINNED_AP2,
        "upstream_checked_head" => pinned_tree_sha,
        "verifier_tested_head" => tested_head,
        "source_fixture_sha256" => sha(fixture_raw),
        "source_policy_sha256" => sha(policy_raw),
        "source_e01_report_sha256" => sha(e01_raw),
        "source_independent_oracle_sha256" => sha(oracle_raw),
        "schema_fingerprints" => fingerprints,
        "verified_at_basis" => "untrusted_synthetic_policy_freeze_epoch",
        "g1_authority" => "NOT_ESTABLISHED",
        "g6_g7" => "HOLD_NOT_WIRED",
        "case_results" => per_case,
        "conclusion" => "NOT_A_PAYMENT_OR_PHASE2B_AUTHORIZATION"
      }
      # Do not mistake a case report or a matching stage label for G7 proof.
      stop!("unauthorized_evidence") unless
        control["evidence"].nil? && report["g6_g7"] == "HOLD_NOT_WIRED"
      write_report_exclusive!(paths.fetch("report"), report)
      matched
    end

    def write_report_exclusive!(path, report)
      stop!("invalid_report_path") unless
        path.instance_of?(String) && path.bytesize.between?(1, 1024) &&
        !path.include?("\0") && File.const_defined?(:NOFOLLOW)
      raw = JSON.generate(report) + "\n"
      stop!("report_resource_limit") unless raw.bytesize.between?(1, 65_536)
      flags = File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW
      File.open(path, flags, 0o600) do |file|
        file.write(raw)
        file.flush
        file.fsync
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    options = {}
    parser = OptionParser.new do |args|
      %w[fixture policy e01_report independent_oracle upstream_root report].each do |name|
        args.on("--#{name.tr('_', '-')} FILE") { |value| options[name] = value }
      end
    end
    parser.parse!(ARGV)
    raise AP2E06IA7SignedReachability::Stop, "unexpected_arguments" unless
      ARGV.empty?
    success = AP2E06IA7SignedReachability.run!(options)
    puts(success ? "E06-I A7: LIMITED SYNTHETIC STAGE OBSERVATION ONLY" :
                   "E06-I A7: RED/HOLD; actual stages preserved")
    exit(success ? 0 : 1)
  rescue StandardError
    # Fail closed without printing private/wire contents or local filesystem
    # details. Without a complete report, no independent proof is admitted.
    warn "E06-I A7: RED/HOLD; incomplete signed observation"
    exit 1
  end
end
