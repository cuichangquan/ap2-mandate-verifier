# frozen_string_literal: true
#
# Issue #97 / A3-T2c additional Approval A2: proposed future B driver.
# SOURCE-ONLY. Never run under Approval A2. No execution on require.
# Not a Host Verifier, Merchant signature check, nonce consumption CAS,
# payment authorization, G1/G7 admission or recovery/PG06 experiment.
#
# B requires independently authorized disposable PG16 scope, actual
# PostgreSQL roles, three already-open dedicated sessions and an operator
# who can quarantine and CLEAN UP that scope. No connections are opened
# here, no files/logs are written, and no real nonce/JWT is published.
require "digest"
require "securerandom"
require "base64"
require "time"
require_relative "a3_t2c_nonce_issuance_worker"
require_relative "a3_t2c_nonce_ledger_oracle"
require_relative "a3_t2c_nonce_scenarios"
require_relative "a3_t2c_b_lab_inputs"
require_relative "a3_t2c_b_lab_supervisor"

module AP2E06IA3T2cBLabDriver
  INPUTS = AP2E06IA3T2cBLabInputs
  WORKER = AP2E06IA3T2cNonceIssuanceWorker
  ORACLE = AP2E06IA3T2cNonceLedgerOracle
  SCENARIOS = AP2E06IA3T2cNonceScenarios
  SUPERVISOR = AP2E06IA3T2cBLabSupervisor

  ROLE_ID_SQL = <<~SQL.freeze
    SELECT pg_catalog.current_database() AS db_name,
           current_user AS effective_role,
           session_user AS login_role,
           pg_catalog.pg_is_in_recovery() AS is_replica,
           pg_catalog.pg_backend_pid() AS backend_pid,
           pg_catalog.pg_postmaster_start_time()::pg_catalog.text AS started_at
  SQL

  COUNT_SQL = <<~SQL.freeze
    SELECT pg_catalog.count(*)::pg_catalog.text AS row_count
      FROM a3_t2c.nonce_issuance_history
     WHERE nonce_sha256 = $1::pg_catalog.bpchar
  SQL

  REF_COUNT_SQL = <<~SQL.freeze
    SELECT pg_catalog.count(*)::pg_catalog.text AS row_count
      FROM a3_t2c.nonce_issuance_history
     WHERE issuance_ref = $1::pg_catalog.text
  SQL

  class << self
    # The approval_b_url held by the supervisor is an unauthenticated
    # operator statement, NEVER proof of Owner approval. A person must
    # verify the GitHub approval, machine/cluster identity and permissions
    # OUTSIDE this Ruby source before invoking this explicit B-time method.
    #
    # The supervisor always returns status HOLD/non-authoritative even if
    # every limited synthetic local observation matches expectations.
    def run_once!(supervisor:, writer_a:, writer_b:, reader:,
                  issued_at:, expires_at:)
      sessions = [writer_a, writer_b, reader]
      begin
        raise "supervisor type mismatch" unless
          supervisor.instance_of?(SUPERVISOR::Session)
        supervisor.begin_once!(writer_a: writer_a, writer_b: writer_b,
                               reader: reader)
        identities = sessions.map.with_index do |conn, i|
          supervisor.bounded!(label: "identity_#{i}",
                              connections: [conn], seconds: 3) do
            identity_only(conn)
          end
        end
        unless same_disposable_primary_claim?(identities)
          supervisor.stop!(reason: "pg16_primary_or_roles_unverified")
        end

        catalog = supervisor.bounded!(label: "initial_catalog",
                                      connections: [reader], seconds: 4) do
          ORACLE.inspect_catalog_only(reader: reader)
        end
        unless catalog.respond_to?(:catalog_checked) && catalog.catalog_checked
          supervisor.stop!(reason: "catalog_unique_acl_shape_unverified")
        end

        pg01 = pg01_only(supervisor, writer_a, reader, issued_at, expires_at)
        pg02_only(supervisor, writer_a, writer_b, reader,
                  issued_at, expires_at)
        pg03_only(supervisor, writer_a, reader, pg01, issued_at, expires_at)
        pg04_only(supervisor, writer_a, reader, issued_at, expires_at)
        pg05_only(supervisor, reader, pg01)

        # No code promotes any case to authenticated/verifier acceptance.
        # The B operator must independently confirm all quiescent sessions,
        # disposable DB/roles/process/credentials deletion and billing.
      rescue StandardError
        # Conservative: an exception can happen after an ACK was lost.
        # Keep ALL session handles for independent supervisor reconciliation.
        supervisor.quarantine!(reason: "driver_stopped_or_unverified",
                               connections: sessions) if
          supervisor.respond_to?(:quarantine!)
      end
      supervisor.finish_report
    end

    private

    def identity_only(connection)
      raise "unknown transaction status" unless
        defined?(PG::PQTRANS_IDLE) &&
        connection.transaction_status == PG::PQTRANS_IDLE
      unless connection.respond_to?(:conninfo_hash) &&
             connection.conninfo_hash.is_a?(Hash)
        raise "unverifiable libpq login credential"
      end
      result = connection.exec(ROLE_ID_SQL)
      raise "role result not unique" unless result.ntuples == 1
      expected = result[0]["effective_role"]
      unless expected == result[0]["login_role"] &&
             connection.conninfo_hash[:user] == expected
        raise "startup authentication cannot be attributed to restricted role"
      end
      result[0]
    end

    def same_disposable_primary_claim?(ids)
      return false unless ids.length == 3 && ids.all? { |r| r.is_a?(Hash) }
      ids.each_with_index do |row, index|
        expected = index == 2 ? "a3_t2c_reader" : "a3_t2c_writer"
        return false unless row["db_name"] == "a3_t2c_b_disposable" &&
          row["effective_role"] == expected &&
          row["login_role"] == expected && row["is_replica"] == "f" &&
          row["backend_pid"].to_s.match?(/\A[0-9]{1,10}\z/) &&
          row["started_at"].is_a?(String) &&
          !row["started_at"].empty?
      end
      ids.map { |r| r["backend_pid"] }.uniq.length == 3 &&
        ids.map { |r| r["started_at"] }.uniq.length == 1
      # A common started_at is only a weak sanity check; NEVER a durable
      # single-primary identity attestation. B operator must prove cluster.
    end

    def pg01_only(supervisor, writer, reader, issued_at, expires_at)
      context = INPUTS.pg01(issued_at: issued_at, expires_at: expires_at)
      wire = INPUTS.unsigned_checkout_wire_for("pg01")
      supervisor.reserve_attempts!
      receipt = supervisor.bounded!(label: "pg01_issue",
                                    connections: [writer], seconds: 8) do
        WORKER.issue!(connection: writer, context: context, checkout_wire: wire)
      end
      unless receipt.respond_to?(:commit_acknowledged?) &&
             receipt.commit_acknowledged? &&
             receipt.nonce.is_a?(String)
        supervisor.stop!(reason: "pg01_positive_commit_ack_unverified")
      end

      event = fetch_event(supervisor, reader, context.fetch("issuance_ref"),
                          "pg01_read")
      unless exact_event_match?(event, context, wire, nonce: receipt.nonce)
        supervisor.stop!(reason: "pg01_row_or_jwt_binding_unverified")
      end
      supervisor.record_case!("PG01", outcome: "LOCAL_OBSERVED",
                              reason: "confirmed_commit_and_reader_row")
      { context: context, wire: wire, nonce: receipt.nonce, event: event }
    end

    def pg02_only(supervisor, left, right, reader, issued_at, expires_at)
      first, second = INPUTS.pg02_pair(issued_at: issued_at,
                                      expires_at: expires_at)
      wire = INPUTS.unsigned_checkout_wire_for("pg02")
      fixed_nonce = INPUTS.pg02_probe_nonce
      supervisor.reserve_attempts!(2)
      observation = supervisor.bounded!(label: "pg02_lock_probe",
        connections: [left, right, reader], seconds: 20) do
        SCENARIOS.pg02_worker_collision_only!(
          left_connection: left, right_connection: right,
          observer_reader: reader, left_context: first,
          right_context: second, checkout_wire: wire,
          probe_nonce: fixed_nonce
        )
      end
      outcome = observation.respond_to?(:outcomes) ? observation.outcomes : {}
      unless outcome["db_unique_lock_witness"] == true &&
             outcome["acknowledged_commits"] == 1 &&
             outcome["attempts"] == 2
        supervisor.stop!(reason: "pg02_lock_or_unique_23505_unverified")
      end

      digest = Digest::SHA256.hexdigest(fixed_nonce.b)
      row_count = count_only(supervisor, reader, COUNT_SQL, digest, "pg02_count")
      unless row_count == 1
        supervisor.stop!(reason: "pg02_exactly_one_committed_row_unverified")
      end
      first_row = fetch_optional_event(supervisor, reader,
                                       first.fetch("issuance_ref"), "pg02_a")
      second_row = fetch_optional_event(supervisor, reader,
                                        second.fetch("issuance_ref"), "pg02_b")
      matches = [
        exact_event_match?(first_row, first, wire, nonce: fixed_nonce),
        exact_event_match?(second_row, second, wire, nonce: fixed_nonce)
      ]
      unless matches.count(true) == 1 &&
             [first_row, second_row].count { |r| !r.nil? } == 1
        supervisor.stop!(reason: "pg02_winner_loser_binding_unverified")
      end
      supervisor.record_case!("PG02", outcome: "LOCAL_OBSERVED",
                              reason: "same_nonce_db_wait_and_one_commit")
    end

    def pg03_only(supervisor, writer, reader, baseline, issued_at, expires_at)
      context = INPUTS.pg03_reissue(issued_at: issued_at,
                                    expires_at: expires_at)
      wire = INPUTS.unsigned_checkout_wire_for("pg03")
      before = fetch_event(supervisor, reader,
                           baseline[:context].fetch("issuance_ref"),
                           "pg03_before")
      supervisor.reserve_attempts!
      collision = supervisor.bounded!(label: "pg03_reuse",
                                      connections: [writer], seconds: 8) do
        WORKER.collision_probe_only!(
          connection: writer, context: context, checkout_wire: wire,
          nonce: baseline[:nonce]
        )
      end
      unless collision.respond_to?(:nonce_conflict_rolled_back?) &&
             collision.nonce_conflict_rolled_back?
        supervisor.stop!(reason: "pg03_reissue_constraint_not_proven")
      end
      denied = supervisor.bounded!(label: "pg03_writer_denial",
        connections: [writer, reader], seconds: 18) do
        SCENARIOS.pg03_writer_append_only_negative!(
          writer: writer, reader: reader,
          issuance_ref: baseline[:context].fetch("issuance_ref")
        )
      end
      unless denied.respond_to?(:outcomes) &&
             denied.outcomes.is_a?(Hash) &&
             denied.outcomes.length == SCENARIOS::PG03_FORBIDDEN_MUTATIONS.length &&
             denied.outcomes.values.all? { |v| v == true }
        supervisor.stop!(reason: "pg03_acl_denials_not_independent")
      end
      after = fetch_event(supervisor, reader,
                          baseline[:context].fetch("issuance_ref"),
                          "pg03_after")
      unless before == after &&
             exact_event_match?(after, baseline[:context], baseline[:wire],
                                nonce: baseline[:nonce])
        supervisor.stop!(reason: "pg03_immutable_row_or_binding_unverified")
      end
      supervisor.record_case!("PG03", outcome: "LOCAL_OBSERVED",
                              reason: "reissue_denied_writer_acl_immutable")
    end

    def pg04_only(supervisor, writer, reader, issued_at, expires_at)
      context = INPUTS.pg04_rollback(issued_at: issued_at,
                                     expires_at: expires_at)
      wire = INPUTS.unsigned_checkout_wire_for("pg04")
      supervisor.reserve_attempts!
      result = supervisor.bounded!(label: "pg04_known_rollback",
                                   connections: [writer], seconds: 8) do
        known_rollback_insert!(writer, context, wire)
      end
      unless result == :rollback_acknowledged &&
             count_only(supervisor, reader, REF_COUNT_SQL,
                        context.fetch("issuance_ref"), "pg04_count") == 0
        supervisor.stop!(reason: "pg04_known_rollback_not_proven")
      end
      # No forced disconnect, simulated ACK loss, DB kill or restore.
      # Unknown-ACK resilience is NOT RUN / HOLD, even when safe ROLLBACK
      # is locally observed. Explicit in the final report.
      supervisor.record_case!("PG04", outcome: "LOCAL_OBSERVED",
                              reason: "known_rollback_only_unknown_ack_unrun")
    end

    def pg05_only(supervisor, reader, baseline)
      original = fetch_event(supervisor, reader,
                             baseline[:context].fetch("issuance_ref"),
                             "pg05_baseline")
      unless exact_event_match?(original, baseline[:context],
                                baseline[:wire], nonce: baseline[:nonce])
        supervisor.stop!(reason: "pg05_positive_binding_missing")
      end
      changes = INPUTS.pg05_mutations(original_context: baseline[:context],
                                      original_wire: baseline[:wire])
      unless changes.length == 5 && changes.all? { |x|
        !exact_event_match?(original, x.fetch("context"), x.fetch("wire"))
      }
        supervisor.stop!(reason: "pg05_mutated_binding_not_rejected")
      end
      after = fetch_event(supervisor, reader,
                          baseline[:context].fetch("issuance_ref"),
                          "pg05_after")
      unless after == original
        supervisor.stop!(reason: "pg05_independent_history_changed")
      end
      supervisor.record_case!("PG05", outcome: "LOCAL_OBSERVED",
                              reason: "synthetic_claim_changes_detected")
    end

    # This explicit PG04 path has NO COMMIT instruction. It must keep the
    # connection quarantined on any unknown BEGIN/INSERT/ROLLBACK ACK. It
    # cannot establish behavior of a genuinely lost COMMIT ACK.
    def known_rollback_insert!(conn, context, wire)
      raise "not idle" unless defined?(PG::PQTRANS_IDLE) &&
        conn.transaction_status == PG::PQTRANS_IDLE
      role = conn.exec("SELECT current_user AS role_name, session_user AS login_role")
      raise "not actual writer" unless role.ntuples == 1 &&
        role[0]["role_name"] == "a3_t2c_writer" &&
        role[0]["login_role"] == "a3_t2c_writer"

      nonce = Base64.urlsafe_encode64(SecureRandom.random_bytes(32),
                                     padding: false)
      args = [
        context.fetch("issuance_ref"), Digest::SHA256.hexdigest(nonce.b),
        context.fetch("challenge_ref"), context.fetch("host_verifier_domain"),
        context.fetch("aud"), context.fetch("agent_thumbprint"),
        context.fetch("buyer_account_ref"), context.fetch("tenant_id"),
        context.fetch("checkout_id"), context.fetch("checkout_version"),
        Digest::SHA256.hexdigest(wire.b), context.fetch("checkout_jwt_source_ref"),
        context.fetch("issued_at"), context.fetch("expires_at")
      ]

      begun = false
      rollback_acknowledged = false
      begin
        begun = true
        start = conn.exec("BEGIN")
        raise "BEGIN ACK missing" unless start.cmd_status == "BEGIN"
        path = conn.exec("SET LOCAL search_path = pg_catalog, pg_temp")
        raise "safe search path unknown" unless path.cmd_status == "SET"
        limit = conn.exec("SET LOCAL statement_timeout = '3000ms'")
        raise "statement timeout unknown" unless limit.cmd_status == "SET"
        lock = conn.exec("SET LOCAL lock_timeout = '2000ms'")
        raise "lock timeout unknown" unless lock.cmd_status == "SET"
        inserted = conn.exec_params(WORKER::INSERT_SQL, args)
        raise "insert row count unknown" unless inserted.cmd_tuples == 1
      ensure
        if begun
          begin
            ack = conn.exec("ROLLBACK")
            rollback_acknowledged = ack.respond_to?(:cmd_status) &&
              ack.cmd_status == "ROLLBACK" &&
              conn.transaction_status == PG::PQTRANS_IDLE
          rescue StandardError
            rollback_acknowledged = false
          end
        end
      end
      raise "rollback ACK uncertain" unless rollback_acknowledged
      :rollback_acknowledged
    end

    # Query only an independently restricted reader session in a fresh READ
    # COMMITTED / READ ONLY transaction. Any exception (including lost ACK)
    # is caught by the B supervisor and quarantines the physical connection.
    def count_only(supervisor, reader, sql, value, label)
      supervisor.bounded!(label: label, connections: [reader], seconds: 4) do
        raise "reader session not idle" unless defined?(PG::PQTRANS_IDLE) &&
          reader.transaction_status == PG::PQTRANS_IDLE
        begun = false
        commit_ack = false
        begin
          begun = true
          ack = reader.exec("BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY")
          raise "reader BEGIN ACK missing" unless ack.cmd_status == "BEGIN"
          path = reader.exec("SET LOCAL search_path = pg_catalog, pg_temp")
          raise "reader SET ACK missing" unless path.cmd_status == "SET"
          result = reader.exec_params(sql, [value])
          raise "count cardinality unknown" unless result.ntuples == 1
          count = result[0].fetch("row_count")
          done = reader.exec("COMMIT")
          commit_ack = done.cmd_status == "COMMIT" &&
            reader.transaction_status == PG::PQTRANS_IDLE
          raise "reader COMMIT ACK unknown" unless commit_ack
          raise "count not finite integer" unless count.match?(/\A[0-9]{1,6}\z/)
          count.to_i
        ensure
          if begun && !commit_ack
            begin
              reader.exec("ROLLBACK")
            rescue StandardError
              nil
            end
          end
        end
      end
    end

    def fetch_optional_event(supervisor, reader, ref, label)
      result = supervisor.bounded!(label: label, connections: [reader],
                                   seconds: 4) do
        ORACLE.inspect_issuance_only(reader: reader, issuance_ref: ref)
      end
      return result.event if result.respond_to?(:event) && result.event
      # The oracle intentionally reports unknown/absent as HOLD. Absence is
      # only usable alongside an independently observed total row count.
      nil
    end

    def fetch_event(supervisor, reader, ref, label)
      event = fetch_optional_event(supervisor, reader, ref, label)
      supervisor.stop!(reason: "independent_#{label}_missing") unless event
      event
    end

    def exact_event_match?(row, context, wire, nonce: nil)
      return false unless row.is_a?(Hash) && context.is_a?(Hash) &&
        wire.is_a?(String)
      %w[
        issuance_ref challenge_ref host_verifier_domain aud
        agent_thumbprint buyer_account_ref tenant_id checkout_id
        checkout_jwt_source_ref
      ].each do |field|
        return false unless row[field] == context[field]
      end
      return false unless row["checkout_version"] ==
        context["checkout_version"].to_s
      return false unless row["merchant_checkout_sha256"] ==
        Digest::SHA256.hexdigest(wire.b)
      return false if nonce && row["nonce_sha256"] !=
        Digest::SHA256.hexdigest(nonce.b)
      return false unless %w[issued_at expires_at].all? { |field|
        Time.parse(row.fetch(field)).to_i == context[field]
      }
      true
    rescue StandardError
      false
    end
  end
end
