# frozen_string_literal: true
#
# Issue #97 / A3-T2c — synthetic PG16 scenario definitions and negative
# observation helpers. APPROVAL A = SOURCE + STATIC REVIEW ONLY.
# NOT RUN / NO DB / NO SQL APPLICATION / NO CI. No executable entry point.
# PG06 backup restore/primary failover is EXCLUDED and separately HOLD.
#
# A separate Owner approval B, disposable single-primary PG16, permissions,
# limits, independent observation and cleanup must precede ANY invocation.
require "thread"
require_relative "a3_t2c_nonce_issuance_worker"
require_relative "a3_t2c_nonce_ledger_oracle"

module AP2E06IA3T2cNonceScenarios
  MAX_WORKERS = 2
  MAX_SYNTHETIC_EVENTS = 100
  MAX_JOB_SECONDS = 600
  MAX_EVIDENCE_BYTES = 1_048_576
  ARTIFACT_RETENTION_DAYS = 7

  SCENARIO_PLAN = {
    "PG01" => "single synthetic commit ack and independent row binding",
    "PG02" => "same nonce in 2 workers / different tenants; <=1 commit",
    "PG03" => "no reuse after expiry and writer UPDATE/DELETE/TRUNCATE denied",
    "PG04" => "known ROLLBACK and unknown commit outcome -> HOLD; no forced kill",
    "PG05" => "detect mutated challenge/agent/buyer/checkout/JWT digest",
    "PG06" => "NOT AUTHORIZED: restore/primary rollback needs separate Owner gate"
  }.transform_values(&:freeze).freeze

  TABLE = "a3_t2c.nonce_issuance_history"

  # Every mutation attempt is within a separate SAVEPOINT and rolled back;
  # a successful mutation attempt is a RED/STOP finding even if the outer
  # transaction is later rolled back. It must NEVER be tested on real data.
  # Source cannot change whether running DB is actually an approved lab.
  # Caller supplied credentials must belong to the actual issuance writer.
  PG03_FORBIDDEN_MUTATIONS = [
    ["update_nonce_digest",
     "UPDATE #{TABLE} SET nonce_sha256 = repeat('0', 64) WHERE issuance_ref = $1"],
    ["update_challenge",
     "UPDATE #{TABLE} SET challenge_ref = 'a3_t2c_changed_ref' WHERE issuance_ref = $1"],
    ["update_checkout",
     "UPDATE #{TABLE} SET checkout_id = 'a3_t2c_changed_checkout' WHERE issuance_ref = $1"],
    ["update_checkout_jwt_digest",
     "UPDATE #{TABLE} SET merchant_checkout_sha256 = repeat('0', 64) WHERE issuance_ref = $1"],
    ["delete_issuance",
     "DELETE FROM #{TABLE} WHERE issuance_ref = $1"],
    ["truncate_history", "TRUNCATE TABLE #{TABLE}"]
  ].map { |name, sql| [name.freeze, sql.freeze].freeze }.freeze

  class LabObservation
    attr_reader :status, :reason, :outcomes, :worker_handles, :connections

    def initialize(reason:, outcomes: {}, worker_handles: [], connections: [])
      @status = "HOLD".freeze
      @reason = reason.freeze
      @outcomes = outcomes.transform_values { |v| v }.freeze
      # If any thread is still alive/unknown at a timeout or an exception,
      # return owned handles AND connections to the B-time supervisor instead
      # of discarding live workers and racing connection teardown.
      @worker_handles = worker_handles.dup.freeze
      @connections = connections.dup.freeze
      freeze
    end

    def pending_worker_cleanup?
      @worker_handles.any?(&:alive?)
    end

    def authoritative?
      false
    end

    def g1_admissible?
      false
    end

    def evidence
      nil
    end
  end

  class << self
    # PG02: verify a genuinely overlapping DB unique constraint conflict.
    # All three connections must be independent sessions to the same
    # pre-approved, isolated PG16 primary. An independent restricted reader
    # witnesses the SECOND INSERT blocked on the FIRST worker's transaction
    # lock BEFORE the winner is allowed to COMMIT.
    #
    # Ruby start synchronisation alone is NOT a database collision oracle.
    # A missing backend pid, failing lock witness or timeout => CANCEL/HOLD.
    def pg02_worker_collision_only!(left_connection:, right_connection:,
                                    observer_reader:, left_context:,
                                    right_context:, checkout_wire:,
                                    probe_nonce:)
      return hold("connections_not_independent") if
        left_connection.equal?(right_connection) ||
        observer_reader.equal?(left_connection) ||
        observer_reader.equal?(right_connection)
      unless left_context.is_a?(Hash) && right_context.is_a?(Hash) &&
          left_context["tenant_id"] != right_context["tenant_id"]
        return hold("cross_tenant_probe_required")
      end

      connections = [left_connection, right_connection, observer_reader]
      tasks = []
      prepared = Queue.new
      inserted = Queue.new
      begin_gates = [Queue.new, Queue.new]
      commit_gates = [Queue.new, Queue.new]

      # Actual libpq session identities are read before any threads start;
      # the independent reader will witness blockers by these exact pids.
      pids = [left_connection, right_connection].map(&:backend_pid)
      unless pids.all? { |pid|
        pid.is_a?(Integer) && pid.between?(1, 2_147_483_647)
      } && pids.uniq.length == 2
        return hold("writer_backend_pids_unverified")
      end

      [
        [left_connection, left_context], [right_connection, right_context]
      ].each_with_index do |(conn, context), i|
        hook = lambda do |stage|
          case stage
          when :before_insert
            # Called with BEGIN and bounded SET LOCAL already in effect.
            prepared << i
            raise "pg02_insert_gate_cancelled" unless begin_gates[i].pop == :go
          when :after_insert_before_commit
            # The successful INSERT still holds its unique constraint lock;
            # COMMIT is forbidden until independent observer witnessed the
            # competing writer blocked on that transaction.
            inserted << i
            raise "pg02_commit_gate_cancelled" unless commit_gates[i].pop == :go
          else
            raise "pg02_unknown_probe_stage"
          end
        end

        tasks << Thread.new do
          AP2E06IA3T2cNonceIssuanceWorker.collision_probe_only!(
            connection: conn, context: context, checkout_wire: checkout_wire,
            nonce: probe_nonce, lab_probe_hook: hook
          )
        end
      end

      # Both transactions MUST reach the hook just before SQL INSERT.
      # If either fails during BEGIN/setup, no INSERT is permitted.
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.0
      while prepared.size < MAX_WORKERS &&
            Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        Thread.pass
      end
      both_inside_tx = tasks.length == MAX_WORKERS &&
                       prepared.size == MAX_WORKERS
      unless both_inside_tx
        return pending_workers("pg02_transaction_barrier_unverified_stop",
                               tasks, connections)
      end
      begin_gates.each { |gate| gate << :go }

      # Exactly one INSERT should succeed while the other waits on the
      # globally unique nonce digest. The winner remains uncommitted.
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.75
      while inserted.empty? &&
            Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        Thread.pass
      end
      return pending_workers("pg02_first_insert_not_observed_stop",
                             tasks, connections) if inserted.empty?
      winner = inserted.pop
      return pending_workers("pg02_invalid_insert_winner_stop",
                             tasks, connections) unless [0, 1].include?(winner)
      loser = 1 - winner

      # Require independently observed PostgreSQL transaction-id or
      # speculative unique-index lock wait by the loser on the winner.
      # Merely logging 'about to insert' is NOT sufficient.
      witnessed = false
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.75
      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        witnessed = AP2E06IA3T2cNonceLedgerOracle.pg02_lock_wait_observed_only?(
          reader: observer_reader, waiting_pid: pids[loser],
          holding_pid: pids[winner]
        )
        break if witnessed

        Thread.pass
      end
      return pending_workers("pg02_unique_conflict_lock_unobserved_stop",
                             tasks, connections) unless witnessed

      # Only the transaction holding the witnessed lock is allowed to
      # COMMIT; any unexpected second successful INSERT is cancelled.
      commit_gates[winner] << :go
      commit_gates[loser] << :cancel

      # Join BOTH workers; timeout does not abandon any connection or imply
      # rollback. Owner/supervisor retains every handle on uncertain outcomes.
      joins = tasks.map { |thread| thread.join(7) }
      return pending_workers("pg02_worker_join_or_commit_uncertain_stop",
                             tasks, connections) if
        joins.any?(&:nil?) || tasks.any?(&:alive?)

      results = tasks.map(&:value)
      return hold("pg02_worker_results_unverified") unless results.all? { |x|
        x.is_a?(AP2E06IA3T2cNonceIssuanceWorker::LabObservation)
      }
      commits = results.count(&:commit_acknowledged?)
      return hold("pg02_unexpected_commit_count_stop") unless commits == 1 &&
        results[winner].commit_acknowledged?

      # Still non-authoritative. B-time independent catalog + row snapshots
      # must show the winner's issuance and no loser Challenge distribution.
      LabObservation.new(
        reason: "synthetic_pg02_lock_witness_only_independent_row_oracle_pending",
        outcomes: {
          "db_unique_lock_witness" => true,
          "acknowledged_commits" => commits,
          "attempts" => MAX_WORKERS
        }
      )
    rescue StandardError
      pending_workers("pg02_concurrent_observation_uncertain_stop",
                      tasks || [], connections || [])
    ensure
      # Never leave a probe inside BEGIN/INSERT waiting on our Ruby gate.
      # Any worker not explicitly allowed to proceed must ROLLBACK/HOLD.
      # Additional CANCEL tickets after a consumed GO are harmless.
      if defined?(begin_gates) && begin_gates
        begin_gates.each { |gate| gate << :cancel }
      end
      if defined?(commit_gates) && commit_gates
        commit_gates.each { |gate| gate << :cancel }
      end
    end

    # PG03: prove (only within disposable lab) that the ACTUAL issuance
    # writer gets SQLSTATE 42501 on every forbidden mutation. Check row
    # content before and after from an independent reader. No grant/ACL
    # assertion from a caller or worker self-report substitutes for this.
    def pg03_writer_append_only_negative!(writer:, reader:, issuance_ref:)
      return hold("invalid_probe_issuance_ref") unless
        issuance_ref.is_a?(String) && issuance_ref.ascii_only? &&
        issuance_ref.bytesize.between?(1, 256)

      catalog = AP2E06IA3T2cNonceLedgerOracle.inspect_catalog_only(reader: reader)
      return hold("catalog_acl_not_proven") unless catalog.catalog_checked

      before = AP2E06IA3T2cNonceLedgerOracle.inspect_issuance_only(
        reader: reader, issuance_ref: issuance_ref
      )
      return hold("pre_mutation_snapshot_unavailable") unless before.event
      return hold("actual_writer_credentials_missing") unless
        writer_session?(writer) && idle_connection?(writer)

      # Every negative mutation is rolled back to a SAVEPOINT, and the
      # outer transaction is ROLLED BACK no matter what happened.
      denied = {}
      began = false
      begin
        writer.exec("BEGIN")
        began = true
        writer.exec("SET LOCAL statement_timeout = '3000ms'")
        writer.exec("SET LOCAL lock_timeout = '2000ms'")

        PG03_FORBIDDEN_MUTATIONS.each do |name, sql|
          writer.exec("SAVEPOINT a3_t2c_negative")
          denied[name] = false
          begin
            if name == "truncate_history"
              writer.exec(sql)
            else
              writer.exec_params(sql, [issuance_ref.dup.freeze])
            end
          rescue StandardError => error
            # Timeout, connectivity, undefined table etc are NOT proven
            # ACL denials. Only PostgreSQL insufficient_privilege 42501
            # counts as a denial. No generic-rescue => false PASS.
            denied[name] = insufficient_privilege?(error)
          ensure
            writer.exec("ROLLBACK TO SAVEPOINT a3_t2c_negative")
            writer.exec("RELEASE SAVEPOINT a3_t2c_negative")
          end
        end
      ensure
        begin
          writer.exec("ROLLBACK") if began
        rescue StandardError
          return hold("rollback_unconfirmed_stop")
        end
      end

      after = AP2E06IA3T2cNonceLedgerOracle.inspect_issuance_only(
        reader: reader, issuance_ref: issuance_ref
      )
      return hold("post_mutation_snapshot_unavailable") unless after.event
      return hold("history_mutated_stop") unless before.event == after.event
      return hold("writer_mutation_not_all_denied_stop") unless
        denied.length == PG03_FORBIDDEN_MUTATIONS.length &&
        denied.values.all?

      LabObservation.new(
        reason: "synthetic_writer_permission_negatives_only_no_restore_proof",
        outcomes: denied
      )
    rescue StandardError
      hold("append_only_negative_inconclusive_stop")
    end

    # PG04 is deliberately NOT an injected disconnect/DB kill. Unknown ACK,
    # rollback failure and restore require the separate authorized B setup.
    # PG05 requires comparison against the independent reader's original row.
    def hold(reason)
      LabObservation.new(reason: reason)
    end

    def pending_workers(reason, threads, connections)
      # The B-time caller receives responsibility for all worker handles,
      # including completed ones. No cleanup/PG close until all are known
      # quiescent; uncertain COMMIT stays HOLD even after a late join.
      LabObservation.new(reason: reason, worker_handles: threads,
                         connections: connections)
    end

    private

    def idle_connection?(connection)
      defined?(PG::PQTRANS_IDLE) &&
        connection.respond_to?(:transaction_status) &&
        connection.transaction_status == PG::PQTRANS_IDLE
    rescue StandardError
      false
    end

    def writer_session?(writer)
      rowset = writer.exec("SELECT current_user AS role_name")
      rowset.respond_to?(:ntuples) && rowset.ntuples == 1 &&
        rowset[0]["role_name"] == "a3_t2c_writer"
    rescue StandardError
      false
    end

    def insufficient_privilege?(error)
      return false unless defined?(PG::Result::PG_DIAG_SQLSTATE)
      return false unless error.respond_to?(:result) && error.result
      error.result.error_field(PG::Result::PG_DIAG_SQLSTATE) == "42501"
    rescue StandardError
      false
    end
  end
end
