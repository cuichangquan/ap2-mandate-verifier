# frozen_string_literal: true
#
# Issue #97 / A3-T2c — independently READ-ONLY PG16 lab oracle.
# APPROVAL A: SOURCE AND STATIC REVIEW ONLY / NOT RUN / NO DB / NO CI.
# No network or PG connection is created on load; connection comes from
# future separately approved B, using a DIFFERENT restricted read-only role.
#
# Observation of a catalog and row does NOT prove authentic Host ownership,
# CSPRNG quality, distributed/global history after restore, G1, G7, or CAS.

module AP2E06IA3T2cNonceLedgerOracle
  READER_ROLE = "a3_t2c_reader"
  WRITER_ROLE = "a3_t2c_writer"
  TABLE = "a3_t2c.nonce_issuance_history"

  # Data is never authoritative evidence. A nonmatching ACL/index means
  # HOLD/STOP. No positive G1 capability is representable.
  class Observation
    attr_reader :status, :reason, :catalog_checked, :event

    def initialize(reason:, catalog_checked: false, event: nil)
      @status = "HOLD".freeze
      @reason = reason.dup.freeze
      @catalog_checked = catalog_checked
      @event = event&.transform_values { |v| v.is_a?(String) ? v.dup.freeze : v }&.freeze
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

  # PG02's transaction wait is NOT uniquely attributable to nonce if
  # *any* fourth UNIQUE index is present (e.g. on aud). Verify the COMPLETE
  # unique-index set against the three immutable schema declarations:
  # issuance_ref PK, challenge_ref UNIQUE and nonce_sha256 UNIQUE.
  # Reject added, partial, expression, invalid, included-column or swapped
  # indexes, even if nonce's own constraint still exists. Also reject
  # any exclusion index (indisexclusion) because it can make the observer
  # see a transaction-ID wait on a non-nonce constraint.
  INDEX_SQL = <<~SQL.freeze
    SELECT COUNT(*) FILTER (WHERE i.indisunique)::integer AS total_unique_indexes,
           COUNT(*) FILTER (WHERE i.indisexclusion)::integer AS exclusion_indexes,
           COUNT(*) FILTER (
             WHERE a.attname = 'nonce_sha256'
               AND a.attnotnull
               AND NOT a.attisdropped
               AND i.indisvalid AND i.indisready
               AND i.indpred IS NULL AND i.indexprs IS NULL
               AND i.indnkeyatts = 1 AND i.indnatts = 1
           )::integer AS matching_indexes,
           COUNT(*) FILTER (
             WHERE a.attname = 'issuance_ref'
               AND a.attnotnull AND NOT a.attisdropped
               AND i.indisvalid AND i.indisready
               AND i.indpred IS NULL AND i.indexprs IS NULL
               AND i.indnkeyatts = 1 AND i.indnatts = 1
           )::integer AS issuance_unique_indexes,
           COUNT(*) FILTER (
             WHERE a.attname = 'challenge_ref'
               AND a.attnotnull AND NOT a.attisdropped
               AND i.indisvalid AND i.indisready
               AND i.indpred IS NULL AND i.indexprs IS NULL
               AND i.indnkeyatts = 1 AND i.indnatts = 1
           )::integer AS challenge_unique_indexes
      FROM pg_catalog.pg_index i
      LEFT JOIN pg_catalog.pg_attribute a
        ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
     WHERE i.indrelid = 'a3_t2c.nonce_issuance_history'::regclass
       AND (i.indisunique OR i.indisexclusion)
  SQL

  # An independent reader checks the actual WRITER role's effective
  # privileges, including membership in table owner and privilege inheritance.
  # The writer session separately asserts current_user == WRITER_ROLE.
  # PG16 has per-membership SET privilege. Reject the *entire reachable*
  # SET ROLE closure, even when one reachable role currently looks harmless:
  # this synthetic lab requires unambiguous fixed, non-escalating roles.
  # Effective/inherited privileges are checked on the base role by catalog.
  ROLE_SQL = <<~SQL.freeze
    WITH RECURSIVE assumable(role_oid) AS (
      SELECT oid FROM pg_catalog.pg_roles WHERE rolname = $1
      UNION
      SELECT m.roleid
        FROM pg_catalog.pg_auth_members m
        JOIN assumable a ON m.member = a.role_oid
       WHERE m.set_option
    )
    SELECT r.rolname AS writer_name, r.rolsuper, r.rolcreaterole,
           r.rolcreatedb, r.rolbypassrls, r.rolreplication, r.rolcanlogin,
           pg_catalog.pg_has_role(r.oid, t.relowner, 'MEMBER') AS owner_member,
           pg_catalog.has_table_privilege(r.oid, t.oid, 'INSERT') AS can_insert,
           pg_catalog.has_table_privilege(r.oid, t.oid, 'SELECT') AS can_select,
           pg_catalog.has_table_privilege(r.oid, t.oid, 'UPDATE') AS can_update,
           pg_catalog.has_table_privilege(r.oid, t.oid, 'DELETE') AS can_delete,
           pg_catalog.has_table_privilege(r.oid, t.oid, 'TRUNCATE') AS can_truncate,
           pg_catalog.has_table_privilege(r.oid, t.oid, 'TRIGGER') AS can_trigger,
           pg_catalog.has_table_privilege(r.oid, t.oid, 'REFERENCES') AS can_reference,
           pg_catalog.has_schema_privilege(r.oid, n.oid, 'CREATE') AS schema_create,
           (SELECT COUNT(*)::integer FROM assumable a
             WHERE a.role_oid <> r.oid) AS settable_other_roles,
           -- Includes admin_option even when set_option and inherit_option
           -- are FALSE. A lab role must have NO memberships whatsoever.
           (SELECT COUNT(*)::integer FROM pg_catalog.pg_auth_members m
             WHERE m.member = r.oid) AS direct_memberships,
           (SELECT COUNT(*)::integer FROM pg_catalog.pg_auth_members m
             WHERE m.member = r.oid AND m.admin_option) AS admin_memberships,
           (SELECT COUNT(*)::integer
              FROM pg_catalog.pg_attribute a
             WHERE a.attrelid = t.oid
               AND a.attnum > 0 AND NOT a.attisdropped
               AND (
                 pg_catalog.has_column_privilege(r.oid, t.oid,
                   a.attnum, 'UPDATE')
                 OR pg_catalog.has_column_privilege(r.oid, t.oid,
                   a.attnum, 'REFERENCES')
                 OR (r.rolname = 'a3_t2c_writer' AND
                     pg_catalog.has_column_privilege(r.oid, t.oid,
                       a.attnum, 'SELECT'))
                 OR (r.rolname = 'a3_t2c_reader' AND
                     pg_catalog.has_column_privilege(r.oid, t.oid,
                       a.attnum, 'INSERT'))
               )
           ) AS forbidden_column_privileges
      FROM pg_catalog.pg_roles r
      CROSS JOIN pg_catalog.pg_class t
      JOIN pg_catalog.pg_namespace n ON t.relnamespace = n.oid
     WHERE r.rolname = $1
       AND n.nspname = 'a3_t2c'
       AND t.relname = 'nonce_issuance_history'
  SQL

  # Digest-only + synthetic references. No raw nonce, JWT or PII is returned.
  EVENT_SQL = <<~SQL.freeze
    SELECT issuance_ref, nonce_sha256::text AS nonce_sha256,
           challenge_ref, host_verifier_domain, aud, agent_thumbprint,
           buyer_account_ref, tenant_id, checkout_id, checkout_version,
           merchant_checkout_sha256::text AS merchant_checkout_sha256,
           checkout_jwt_source_ref, issued_at::text AS issued_at,
           expires_at::text AS expires_at, issuance_xid
      FROM a3_t2c.nonce_issuance_history
     WHERE issuance_ref = $1
  SQL

  # PG02 requires an independently observed PostgreSQL unique-conflict
  # wait, not merely two Ruby threads or two BEGINs. pg_blocking_pids proves
  # who blocks the loser; pg_locks' ungranted transactionid/spectoken lock
  # witnesses the pending index conflict. This is a LOCAL synthetic lab
  # witness only. Not G1/G7, not a proof of multi-primary uniqueness.
  PG02_LOCK_WITNESS_SQL = <<~SQL.freeze
    SELECT (
      $2::integer = ANY(pg_catalog.pg_blocking_pids($1::integer))
      AND EXISTS (
        SELECT 1
          FROM pg_catalog.pg_locks l
         WHERE l.pid = $1::integer
           AND NOT l.granted
           AND l.locktype IN ('transactionid', 'spectoken')
      )
    ) AS unique_lock_wait_observed
  SQL

  class << self
    # Approval B only. The independent read-only session must be a third
    # connection, separate from both writer sessions. This bool is NOT an
    # authoritative Host evidence record and cannot be promoted to G1/G7.
    def pg02_lock_wait_observed_only?(reader:, waiting_pid:, holding_pid:)
      return false unless reader_session?(reader)
      # Even a real transactionid lock wait can be caused by an unrelated
      # UNIQUE index. Only the exact three-key schema makes this a nonce
      # collision witness. No extra index may be present.
      return false unless unique_index_shape?(reader)
      return false unless [waiting_pid, holding_pid].all? { |pid|
        pid.is_a?(Integer) && pid.between?(1, 2_147_483_647)
      } && waiting_pid != holding_pid

      result = reader.exec_params(PG02_LOCK_WITNESS_SQL,
                                  [waiting_pid, holding_pid])
      singleton_row(result) &&
        result[0]["unique_lock_wait_observed"] == "t"
    rescue StandardError
      false
    end

    # Future approval B only: separately supplied, actual reader credential.
    # Positive-looking catalog observations still deliberately status=HOLD.
    # Note: a catalog check alone cannot prove denied mutation under writer
    # credentials; PG03 must *also* attempt it and inspect SQLSTATE 42501.
    def inspect_catalog_only(reader:)
      return hold("reader_role_unverified") unless reader_session?(reader)

      return hold("exact_unique_index_set_unverified") unless
        unique_index_shape?(reader)

      role_result = reader.exec_params(ROLE_SQL, [WRITER_ROLE])
      return hold("writer_acl_unverified") unless singleton_row(role_result)

      row = role_result[0]
      yes = ->(name) { row[name] == "t" }
      no = ->(name) { row[name] == "f" }
      return hold("writer_privilege_escape_or_append_only_not_proven") unless
        row["writer_name"] == WRITER_ROLE &&
        yes.call("rolcanlogin") && yes.call("can_insert") &&
        row["settable_other_roles"] == "0" &&
        row["direct_memberships"] == "0" &&
        row["admin_memberships"] == "0" &&
        row["forbidden_column_privileges"] == "0" &&
        %w[
          rolsuper rolcreaterole rolcreatedb rolbypassrls rolreplication owner_member
          can_select can_update can_delete can_truncate can_trigger
          can_reference schema_create
        ].all? { |k| no.call(k) }

      Observation.new(
        reason: "catalog_acl_shape_observed_but_writer_mutation_test_not_run",
        catalog_checked: true
      )
    rescue StandardError
      hold("catalog_or_reader_unavailable")
    end

    # Future approval B only. The caller should retain 'before' and 'after'
    # snapshots from this read-only role, compare the FULL immutable bindings
    # after denied mutations, and fail if either snapshot was unavailable.
    def inspect_issuance_only(reader:, issuance_ref:)
      return hold("reader_role_unverified") unless reader_session?(reader)
      return hold("invalid_synthetic_issuance_ref") unless
        issuance_ref.is_a?(String) && issuance_ref.ascii_only? &&
        issuance_ref.bytesize.between?(1, 256)

      result = reader.exec_params(EVENT_SQL, [issuance_ref.dup.freeze])
      return hold("issuance_not_uniquely_readable") unless singleton_row(result)
      row = result[0]
      return hold("event_not_bounded") unless row.is_a?(Hash) &&
        row.keys.sort == %w[
          issuance_ref nonce_sha256 challenge_ref host_verifier_domain
          aud agent_thumbprint buyer_account_ref tenant_id checkout_id
          checkout_version merchant_checkout_sha256 checkout_jwt_source_ref
          issued_at expires_at issuance_xid
        ].sort &&
        row.values.all? { |v| v.is_a?(String) && v.bytesize.between?(1, 256) }

      Observation.new(reason: "lab_issuance_row_only_not_host_provenance",
                      event: row)
    rescue StandardError
      hold("reader_issuance_lookup_unavailable")
    end

    # An absence of a row after failure is NOT proof that a commit never
    # happened; disconnected/rolled-back observation is still HOLD.
    def hold(reason)
      Observation.new(reason: reason)
    end

    private

    def unique_index_shape?(reader)
      res = reader.exec(INDEX_SQL)
      singleton_row(res) &&
        res[0]["total_unique_indexes"] == "3" &&
        res[0]["exclusion_indexes"] == "0" &&
        res[0]["matching_indexes"] == "1" &&
        res[0]["issuance_unique_indexes"] == "1" &&
        res[0]["challenge_unique_indexes"] == "1"
    rescue StandardError
      false
    end

    def reader_session?(reader)
      res = reader.exec(<<~SQL)
        SELECT current_user AS role_name, session_user AS login_role,
               pg_is_in_recovery() AS replica,
               has_table_privilege(current_user,
                 'a3_t2c.nonce_issuance_history', 'SELECT') AS may_read,
               has_table_privilege(current_user,
                 'a3_t2c.nonce_issuance_history', 'INSERT') AS may_insert,
               has_table_privilege(current_user,
                 'a3_t2c.nonce_issuance_history', 'UPDATE') AS may_update,
               has_table_privilege(current_user,
                 'a3_t2c.nonce_issuance_history', 'DELETE') AS may_delete,
               has_table_privilege(current_user,
                 'a3_t2c.nonce_issuance_history', 'TRUNCATE') AS may_truncate
      SQL
      return false unless singleton_row(res) &&
        res[0]["role_name"] == READER_ROLE &&
        res[0]["login_role"] == READER_ROLE &&
        res[0]["replica"] == "f" &&
        res[0]["may_read"] == "t" &&
        %w[may_insert may_update may_delete may_truncate].all? {
          |k| res[0][k] == "f"
        }

      # This independent catalog interrogation also checks owner membership,
      # inherited rights and transitive PG16 SET ROLE membership, including
      # a reader that can assume an entirely different privileged identity.
      roles = reader.exec_params(ROLE_SQL, [READER_ROLE])
      return false unless singleton_row(roles)
      acl = roles[0]
      acl["writer_name"] == READER_ROLE &&
        acl["rolcanlogin"] == "t" && acl["can_select"] == "t" &&
        acl["settable_other_roles"] == "0" &&
        acl["direct_memberships"] == "0" &&
        acl["admin_memberships"] == "0" &&
        acl["forbidden_column_privileges"] == "0" &&
        %w[
          rolsuper rolcreaterole rolcreatedb rolbypassrls rolreplication owner_member
          can_insert can_update can_delete can_truncate can_trigger
          can_reference schema_create
        ].all? { |key| acl[key] == "f" }
    rescue StandardError
      false
    end

    def singleton_row(result)
      result.respond_to?(:ntuples) && result.ntuples == 1
    end
  end
end
