# frozen_string_literal: true
#
# Issue #97 / A3-T2c additional Approval A2: SOURCE-ONLY lab supervisor.
# NO database, SQL, network, files, thread, container or process is started
# by loading this file. Separate Owner Approval B is required for ANY run.
#
# This module does not authenticate GitHub approval, Host, PG cluster owner or
# credentials. An approved human operator MUST separately verify them.
# It never closes an uncertain connection, issues a retry, kills a thread,
# drops a DB, grants a role, publishes a JWT/nonce or declares G1/G7 PASS.
require "json"

module AP2E06IA3T2cBLabSupervisor
  MAX_WORKERS = 2
  MAX_EVENTS = 100
  MAX_JOB_SECONDS = 600
  MAX_REPORT_BYTES = 1_048_576
  RETENTION_DAYS = 7
  EXPECTED_REPO_SHA = "1ab189c77f65677f4cb8eedcc1b187c7114f9a8f"
  CASES = %w[PG01 PG02 PG03 PG04 PG05].freeze
  ALLOWED_OUTCOMES = %w[HOLD LOCAL_OBSERVED RED_STOP NOT_RUN].freeze

  class Stop < StandardError; end

  class Session
    attr_reader :quarantined_threads, :quarantined_connections

    # Scope identifiers and approval URL are *claims* supplied by an operator,
    # NOT authenticated authority. Verify the actual B approval externally.
    def initialize(approval_b_url:, operator_ref:, lab_scope_ref:,
                   repo_sha: EXPECTED_REPO_SHA)
      unless approval_b_url.is_a?(String) &&
             approval_b_url.match?(/\Ahttps:\/\/github\.com\/cuichangquan\/ap2-mandate-verifier\/issues\/97#issuecomment-\d+\z/) &&
             operator_ref.is_a?(String) &&
             operator_ref.match?(/\A[a-zA-Z0-9_-]{1,64}\z/) &&
             lab_scope_ref.is_a?(String) &&
             lab_scope_ref.match?(/\A[a-zA-Z0-9_-]{1,64}\z/) &&
             repo_sha == EXPECTED_REPO_SHA
        raise Stop, "B approval claim / scope / fixed SHA missing; STOP"
      end
      @approval_b_url = approval_b_url.dup.freeze
      @operator_ref = operator_ref.dup.freeze
      @scope_ref = lab_scope_ref.dup.freeze
      @repo_sha = repo_sha.freeze
      @start_time = nil
      @events = 0
      @case_results = {}
      @registered_connections = []
      @quarantined_threads = []
      @quarantined_connections = []
      @stop_reason = nil
      @completed = false
    end

    # The B-time driver supplies already-open independent PG::Connection
    # instances; never connect or install dependencies automatically.
    def begin_once!(writer_a:, writer_b:, reader:)
      raise Stop, "supervisor already started; no retry" if @start_time
      connections = [writer_a, writer_b, reader]
      unless defined?(PG::Connection) &&
             connections.all? { |c| c.instance_of?(PG::Connection) } &&
             connections.map(&:object_id).uniq.length == 3
        raise Stop, "actual three independent libpq handles not verified"
      end
      @registered_connections = connections.dup
      @start_time = monotonic
      true
    end

    def assert_ready!
      raise Stop, "run not armed" unless @start_time
      raise Stop, "run already completed" if @completed
      raise Stop, "previous HOLD/RED, no further activity" if @stop_reason
      raise Stop, "job timeout / cleanup budget exhausted" if remaining < 45
      true
    end

    # Counts *attempts*, including a failed INSERT or a collision. Never
    # treat a rejected attempt as available again. The driver reserves a
    # count BEFORE calling a worker; hidden retry paths are prohibited.
    def reserve_attempts!(count = 1)
      assert_ready!
      raise Stop, "invalid attempt count" unless count.is_a?(Integer) &&
        count.between?(1, MAX_WORKERS)
      raise Stop, "100 attempted events exceeded" if @events + count > MAX_EVENTS
      @events += count
    end

    # A blocking libpq call runs on a RETAINED thread, even if BEGIN or role
    # inspection hangs. Timeout records every connection as quarantined.
    # The caller must never reuse/close those connections without B operator
    # reconciling the independent DB transaction/commit state.
    def bounded!(label:, connections:, seconds:)
      assert_ready!
      unless label.is_a?(String) && label.match?(/\A[a-z0-9_]{1,48}\z/) &&
             connections.is_a?(Array) &&
             connections.all? { |c| @registered_connections.include?(c) } &&
             seconds.is_a?(Numeric) && seconds > 0
        raise Stop, "invalid bounded operation"
      end

      worker = Thread.new { yield }
      wait_seconds = [seconds, remaining - 45].min
      if wait_seconds <= 0 || !worker.join(wait_seconds)
        quarantine!(reason: "operation_timeout_#{label}",
                    threads: [worker], connections: connections)
        raise Stop, @stop_reason
      end
      result = worker.value
      if result.respond_to?(:pending_worker_cleanup?) &&
         result.pending_worker_cleanup?
        handles = result.respond_to?(:worker_handles) ? result.worker_handles : []
        extra_connections = result.respond_to?(:connections) ? result.connections : []
        quarantine!(reason: "uncertain_connection_#{label}",
                    threads: [worker] + handles,
                    connections: connections + extra_connections)
        raise Stop, @stop_reason
      end
      result
    rescue Stop
      quarantine!(reason: "bounded_stop_#{label}",
                  threads: [worker].compact, connections: connections)
      raise
    rescue StandardError
      quarantine!(reason: "operation_exception_#{label}",
                  threads: [worker].compact,
                  connections: connections)
      raise Stop, @stop_reason
    end

    def record_case!(case_id, outcome:, reason:)
      raise Stop, "case already recorded" if @case_results.key?(case_id)
      unless CASES.include?(case_id) && ALLOWED_OUTCOMES.include?(outcome) &&
             reason.is_a?(String) &&
             reason.match?(/\A[a-z0-9_]{1,80}\z/)
        raise Stop, "invalid sanitized case result"
      end
      @case_results[case_id] = { "outcome" => outcome,
                                 "reason" => reason }.freeze
      if %w[HOLD RED_STOP].include?(outcome)
        @stop_reason ||= "case_#{case_id.downcase}_#{reason}"
      end
    end

    def stop!(reason:)
      quarantine!(reason: reason, connections: @registered_connections)
      raise Stop, @stop_reason
    end

    # Closing a thread handle is not proof its transaction was quiescent.
    # No automatic ROLLBACK, DROP, service stop, credential removal or
    # "cleanup successful" bit is provided by this research class.
    def quarantine!(reason:, threads: [], connections: [])
      @stop_reason ||= safe_reason(reason)
      @quarantined_threads.concat(threads.compact).uniq!
      @quarantined_connections.concat(connections.compact).uniq!
      @stop_reason
    end

    def finish_report
      @completed = true
      elapsed = @start_time ? (monotonic - @start_time).ceil : nil
      results = CASES.each_with_object({}) do |key, result|
        result[key] = @case_results.fetch(key, {
          "outcome" => "NOT_RUN", "reason" => "not_executed"
        })
      end
      report = {
        "issue" => 97,
        "approval" => "B_OPERATOR_ASSERTION_NOT_AUTHENTICATED",
        "approval_reference" => @approval_b_url,
        "repository_sha" => @repo_sha,
        "operator_ref" => @operator_ref,
        "scope_ref" => @scope_ref,
        "status" => "HOLD",
        "authoritative" => false,
        "g1_g7_admissible" => false,
        "phase2b" => "HOLD",
        "elapsed_seconds_rounded_up" => elapsed,
        "synthetic_insert_attempts_reserved" => @events,
        "cases" => results,
        "stop_reason" => @stop_reason,
        "quarantined_thread_count" => @quarantined_threads.length,
        "quarantined_connection_count" => @quarantined_connections.length,
        "cleanup" => "PENDING_INDEPENDENT_OPERATOR_CONFIRMATION",
        "pg06" => "EXCLUDED",
        "maximum_external_artifact_bytes" => MAX_REPORT_BYTES,
        "maximum_external_retention_days" => RETENTION_DAYS
      }
      unless JSON.generate(report).bytesize <= MAX_REPORT_BYTES
        raise Stop, "sanitized report exceeds approved bound"
      end
      report.freeze
    end

    private

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def remaining
      MAX_JOB_SECONDS - (monotonic - @start_time)
    end

    def safe_reason(value)
      string = value.to_s
      return string if string.match?(/\A[a-z0-9_]{1,80}\z/)
      "unknown_or_sensitive_failure"
    end
  end
end
