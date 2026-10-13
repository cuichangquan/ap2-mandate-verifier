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
      # Even completed threads may leave an unknown PostgreSQL transaction:
      # quarantined connection handles are a cleanup obligation until the
      # separately authorized supervisor proves the DB session quiescent.
      @worker_handles.any?(&:alive?) || !@connections.empty?
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
      return hold("synthetic_probe_contexts_required") unless
        left_context.is_a?(Hash) && right_context.is_a?(Hash)

      # Copy all caller-owned strings BEFORE checking uniqueness or giving
      # contexts to threads, avoiding a different issuance_ref/challenge_ref
      # appearing between this check and the actual SQL bindings.
      left_context = detached_probe_context(left_context)
      right_context = detached_probe_context(right_context)
      return hold("cross_tenant_probe_required") unless
        left_context["tenant_id"].is_a?(String) &&
        right_context["tenant_id"].is_a?(String) &&
        left_context["tenant_id"] != right_context["tenant_id"]

      # PG02 must conflict ONLY on UNIQUE(nonce_sha256). Both other unique
      # keys (issuance_ref PRIMARY KEY, challenge_ref UNIQUE) must differ,
      # otherwise a witnessed PostgreSQL transaction wait could arise from
      # the wrong index and be falsely credited to nonce uniqueness.
      return hold("pg02_non_nonce_unique_keys_not_distinct") unless
        %w[issuance_ref challenge_ref].all? { |field|
          a = left_context[field]
          z = right_context[field]
          a.is_a?(String) && z.is_a?(String) &&
            !a.empty? && !z.empty? && a != z
        }

      connections = [left_connection, right_connection, observer_reader]
      tasks = []
      observer_thread = nil
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
      #
      # IMPORTANT: pg connection queries are synchronous and can hang on
      # the wire before the Ruby deadline can be checked again. The entire
      # reader_session?/catalog/lock-query path therefore runs inside an
      # owned OBSERVER THREAD with a bounded parent join. Any timed-out
      # reader thread is returned with the workers and ALL DB connections;
      # never close/reuse its connection until the approved B supervisor
      # establishes quiescence. B may additionally set libpq network timeout.
      observer_thread = Thread.new do
        observed = false
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.75
        while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          observed = AP2E06IA3T2cNonceLedgerOracle.pg02_lock_wait_observed_only?(
            reader: observer_reader, waiting_pid: pids[loser],
            holding_pid: pids[winner]
          )
          break if observed

          Thread.pass
        end
        observed
      end
      return pending_workers("pg02_observer_query_timeout_stop",
                             tasks + [observer_thread], connections) unless
        observer_thread.join(1.5)
      return pending_workers("pg02_unique_conflict_lock_unobserved_stop",
                             tasks + [observer_thread], connections) unless
        observer_thread.value == true

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
      # Even an exception while inspecting observer_thread.value must not
      # drop a live SQL observer or one of the two pending INSERT workers.
      handles = (tasks || []).dup
      handles << observer_thread if defined?(observer_thread) && observer_thread
      pending_workers("pg02_concurrent_observation_uncertain_stop",
                      handles, connections || [])
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

      # PG03 catalog and row reads can stall on libpq network I/O.
      # Run EACH read in a retained observer Thread and bound parent join;
      # never silently discard a live reader or close its connection.
      catalog = bounded_pg03_read_only(
        reader: reader, writer: writer, phase: "catalog"
      ) do
        AP2E06IA3T2cNonceLedgerOracle.inspect_catalog_only(reader: reader)
      end
      return catalog if catalog.is_a?(LabObservation)
      return hold("catalog_acl_not_proven") unless catalog.catalog_checked

      before = bounded_pg03_read_only(
        reader: reader, writer: writer, phase: "before_snapshot"
      ) do
        AP2E06IA3T2cNonceLedgerOracle.inspect_issuance_only(
          reader: reader, issuance_ref: issuance_ref
        )
      end
      return before if before.is_a?(LabObservation)
      return hold("pre_mutation_snapshot_unavailable") unless before.event
      # The complete writer phase (credential inspection, BEGIN,
      # all negative mutations, SAVEPOINT cleanup, final ROLLBACK) can block
      # on the PostgreSQL socket. Run it under a retained bounded Thread,
      # just like the independent reader queries. No unbounded direct
      # writer call is permitted from this supervisor method.
      denied = bounded_pg03_writer_only(
        writer: writer, reader: reader, issuance_ref: issuance_ref
      )
      return denied if denied.is_a?(LabObservation)
      return hold("pg03_mutation_results_unverified_stop") unless
        denied.is_a?(Hash)

      after = bounded_pg03_read_only(
        reader: reader, writer: writer, phase: "after_snapshot"
      ) do
        AP2E06IA3T2cNonceLedgerOracle.inspect_issuance_only(
          reader: reader, issuance_ref: issuance_ref
        )
      end
      return after if after.is_a?(LabObservation)
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

    # Every synchronous catalog/ACL/row query is offloaded to its own
    # retained observer thread. A stalled reader cannot prevent the parent
    # from returning HOLD with both connection handles for supervised
    # quiescence/cleanup. No Thread.kill, no reconnect, no retry; results
    # are synthetic observations and never authoritative G1/G7 evidence.
    # PG03 must bound the entire writer lifecycle, not only the reader.
    # A lost libpq socket can stall authentication/status, BEGIN, SQL
    # mutations, SAVEPOINT cleanup or ROLLBACK. Return a retained thread
    # AND both connections if any phase does not finish promptly.
    def bounded_pg03_writer_only(writer:, reader:, issuance_ref:)
      writer_thread = Thread.new do
        pg03_writer_mutations_only(writer: writer, issuance_ref: issuance_ref)
      end
      return pending_workers("pg03_writer_phase_timeout_stop",
                             [writer_thread], [writer, reader]) unless
        writer_thread.join(4.0)

      observation = writer_thread.value
      # Any writer-side uncertain BEGIN, failed ROLLBACK or unexpected
      # HOLD keeps the socket quarantined even after its Ruby Thread exits.
      return pending_workers("pg03_writer_uncertain_result_quarantine_stop",
                             [writer_thread], [writer, reader]) if
        observation.is_a?(LabObservation)
      observation
    rescue StandardError
      pending_workers("pg03_writer_phase_unavailable_stop",
                      [writer_thread].compact, [writer, reader])
    end

    def pg03_writer_mutations_only(writer:, issuance_ref:)
      return hold("actual_writer_credentials_missing") unless
        writer_session?(writer) && idle_connection?(writer)

      denied = {}
      # BEGIN can reach PostgreSQL while its acknowledgment is lost. Set
      # attempted BEFORE the wire call, and never interpret a missing
      # acknowledgment as a known rollback/no active transaction.
      begin_attempted = false
      begin_acknowledged = false
      uncertain = false
      rollback_verified = false
      begin
        begin_attempted = true
        begin_result = writer.exec("BEGIN")
        begin_acknowledged = begin_result.respond_to?(:cmd_status) &&
                             begin_result.cmd_status == "BEGIN"
        raise "pg03_begin_acknowledgment_unknown" unless begin_acknowledged
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
            # Only real SQLSTATE 42501 counts as a negative ACL result.
            denied[name] = insufficient_privilege?(error)
          ensure
            writer.exec("ROLLBACK TO SAVEPOINT a3_t2c_negative")
            writer.exec("RELEASE SAVEPOINT a3_t2c_negative")
          end
        end
      rescue StandardError
        uncertain = true
      ensure
        if begin_attempted
          begin
            rollback_result = writer.exec("ROLLBACK")
            rollback_verified = rollback_result.respond_to?(:cmd_status) &&
                                rollback_result.cmd_status == "ROLLBACK"
            uncertain = true unless rollback_verified
          rescue StandardError
            uncertain = true
          end
        end
      end

      # If BEGIN acknowledgment was ever unknown, even a later ROLLBACK
      # response does NOT prove the complete history of the socket.
      # The wrapper retains both DB connections for B-time quarantine.
      return hold("pg03_writer_transaction_or_rollback_uncertain_stop") if
        uncertain || !begin_acknowledged || !rollback_verified
      return hold("writer_mutation_not_all_denied_stop") unless
        denied.length == PG03_FORBIDDEN_MUTATIONS.length && denied.values.all?

      denied
    rescue StandardError
      hold("pg03_writer_mutations_unavailable_stop")
    end

    def bounded_pg03_read_only(reader:, writer:, phase:)
      observer_thread = Thread.new { yield }
      unless observer_thread.join(1.5)
        return pending_workers("pg03_#{phase}_observer_timeout_stop",
                               [observer_thread], [writer, reader])
      end

      observer_thread.value
    rescue StandardError
      pending_workers("pg03_#{phase}_observer_unavailable_stop",
                      [observer_thread].compact, [writer, reader])
    end

    def detached_probe_context(context)
      context.each_with_object({}) do |(key, value), result|
        frozen_key = key.is_a?(String) ? key.dup.freeze : key
        frozen_value = value.is_a?(String) ? value.dup.freeze : value
        result[frozen_key] = frozen_value
      end.freeze
    end

    def idle_connection?(connection)
      defined?(PG::PQTRANS_IDLE) &&
        connection.respond_to?(:transaction_status) &&
        connection.transaction_status == PG::PQTRANS_IDLE
    rescue StandardError
      false
    end

    def writer_session?(writer)
      rowset = writer.exec(
        "SELECT current_user AS role_name, session_user AS login_role"
      )
      rowset.respond_to?(:ntuples) && rowset.ntuples == 1 &&
        rowset[0]["role_name"] == "a3_t2c_writer" &&
        rowset[0]["login_role"] == "a3_t2c_writer" &&
        authenticated_connection_user?(writer, "a3_t2c_writer")
    rescue StandardError
      false
    end

    def authenticated_connection_user?(connection, expected)
      return false unless defined?(PG::Connection) &&
        connection.instance_of?(PG::Connection) &&
        connection.respond_to?(:conninfo_hash)

      info = connection.conninfo_hash
      info.is_a?(Hash) && info[:user].is_a?(String) &&
        info[:user] == expected
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
