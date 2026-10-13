# frozen_string_literal: true
#
# Issue #97 / A3-T2c — synthetic PG16 scenario definitions and negative
# observation helpers. APPROVAL A = SOURCE + STATIC REVIEW ONLY.
# NOT RUN / NO DB / NO SQL APPLICATION / NO CI. No executable entry point.
# PG06 backup restore/primary failover is EXCLUDED and separately HOLD.
#
# A separate Owner approval B, disposable single-primary PG16, permissions,
# limits, independent observation and cleanup must precede ANY invocation.
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
    attr_reader :status, :reason, :outcomes

    def initialize(reason:, outcomes: {})
      @status = "HOLD".freeze
      @reason = reason.freeze
      @outcomes = outcomes.transform_values { |v| v }.freeze
      freeze
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
    # PG02 helper for separately-approved B. Two DB connections must be
    # distinct sessions on exactly the same independently checked primary.
    # Both tenants use one shared synthetic nonce; the collision probe never
    # exposes a raw nonce as a committed challenge. The result is merely
    # an untrusted worker report until the separate reader/catal og verifies.
    def pg02_worker_collision_only!(left_connection:, right_connection:,
                                    left_context:, right_context:,
                                    checkout_wire:, probe_nonce:)
      return hold("connections_not_independent") if
        left_connection.equal?(right_connection)
      unless left_context.is_a?(Hash) && right_context.is_a?(Hash) &&
          left_context["tenant_id"] != right_context["tenant_id"]
        return hold("cross_tenant_probe_required")
      end

      tasks = [
        [left_connection, left_context], [right_connection, right_context]
      ].map do |conn, context|
        Thread.new do
          AP2E06IA3T2cNonceIssuanceWorker.collision_probe_only!(
            connection: conn, context: context, checkout_wire: checkout_wire,
            nonce: probe_nonce
          )
        end
      end

      # Never kill/retry a thread with an uncertain COMMIT. On timeout
      # supervisor must STOP and independently clean up all DB sessions.
      return hold("worker_join_or_commit_uncertain_stop") unless
        tasks.all? { |thread| thread.join(7) }

      results = tasks.map(&:value)
      return hold("unverified_worker_result") unless results.all? { |x|
        x.is_a?(AP2E06IA3T2cNonceIssuanceWorker::LabObservation)
      }
      commits = results.count(&:commit_acknowledged?)
      return hold("unsafe_multiple_commit_acks_stop") if commits > 1

      # Even 1/2 acknowledged commits does not prove global uniqueness,
      # that the same nonce was committed, or that no Challenge leaked.
      LabObservation.new(
        reason: "worker_outcomes_only_independent_db_oracle_required",
        outcomes: { "acknowledged_commits" => commits, "attempts" => 2 }
      )
    rescue StandardError
      hold("collision_observation_unavailable")
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
        writer_session?(writer)

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

    private

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
