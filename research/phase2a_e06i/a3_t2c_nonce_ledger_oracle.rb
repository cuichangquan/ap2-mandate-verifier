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
    attr_reader :status, :reason, :catalog_checked, :event, :connections

    def initialize(reason:, catalog_checked: false, event: nil, connections: [])
      @status = "HOLD".freeze
      @reason = reason.dup.freeze
      @catalog_checked = catalog_checked
      @event = event&.transform_values { |v| v.is_a?(String) ? v.dup.freeze : v }&.freeze
      # Preserve a physical session on any uncertain SQL transaction ACK.
      @connections = connections.dup.freeze
      freeze
    end

    def pending_worker_cleanup?
      !@connections.empty?
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
    WITH observed AS (
      SELECT a.attname, ci.relname AS index_name,
             co.conname AS constraint_name, co.contype,
             i.indisprimary, i.indisunique,
             (
               i.indisunique AND NOT i.indisexclusion
               AND i.indisvalid AND i.indisready AND i.indimmediate
               AND NOT i.indisnullsnotdistinct
               AND i.indpred IS NULL AND i.indexprs IS NULL
               AND i.indnkeyatts = 1 AND i.indnatts = 1
               AND i.indoption[0] = 0
               AND a.attnotnull AND NOT a.attisdropped
               AND ci.relkind = 'i' AND ci.relpersistence = 'p'
               AND am.amname = 'btree'
               AND oc.opcmethod = ci.relam
               AND ons.nspname = 'pg_catalog'
               AND cl.collname = 'default'
               AND cl.collisdeterministic
               AND cns.nspname = 'pg_catalog'
               AND i.indcollation[0] = a.attcollation
               AND co.condeferrable = false AND co.condeferred = false
               AND co.convalidated = true
               AND (
                 (a.attname = 'nonce_sha256' AND oc.opcname = 'bpchar_ops')
                 OR
                 (a.attname IN ('issuance_ref', 'challenge_ref')
                  AND oc.opcname = 'text_ops')
               )
             ) AS safe_builtin_btree
        FROM pg_catalog.pg_index i
        LEFT JOIN pg_catalog.pg_class ci ON ci.oid = i.indexrelid
        LEFT JOIN pg_catalog.pg_am am ON am.oid = ci.relam
        LEFT JOIN pg_catalog.pg_attribute a
          ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
        LEFT JOIN pg_catalog.pg_opclass oc ON oc.oid = i.indclass[0]
        LEFT JOIN pg_catalog.pg_namespace ons ON ons.oid = oc.opcnamespace
        LEFT JOIN pg_catalog.pg_collation cl ON cl.oid = i.indcollation[0]
        LEFT JOIN pg_catalog.pg_namespace cns ON cns.oid = cl.collnamespace
        LEFT JOIN pg_catalog.pg_constraint co
          ON co.conindid = i.indexrelid AND co.conrelid = i.indrelid
       WHERE i.indrelid = 'a3_t2c.nonce_issuance_history'::regclass
    )
    SELECT COUNT(*)::integer AS total_indexes,
           COUNT(*) FILTER (
             WHERE safe_builtin_btree
               AND attname = 'nonce_sha256'
               AND index_name = 'a3_t2c_global_nonce_unique'
               AND constraint_name = 'a3_t2c_global_nonce_unique'
               AND contype = 'u' AND NOT indisprimary
           )::integer AS matching_indexes,
           COUNT(*) FILTER (
             WHERE safe_builtin_btree
               AND attname = 'issuance_ref'
               AND index_name = 'nonce_issuance_history_pkey'
               AND constraint_name = 'nonce_issuance_history_pkey'
               AND contype = 'p' AND indisprimary
           )::integer AS issuance_unique_indexes,
           COUNT(*) FILTER (
             WHERE safe_builtin_btree
               AND attname = 'challenge_ref'
               AND index_name = 'nonce_issuance_history_challenge_ref_key'
               AND constraint_name = 'nonce_issuance_history_challenge_ref_key'
               AND contype = 'u' AND NOT indisprimary
           )::integer AS challenge_unique_indexes
      FROM observed
  SQL

  # PG02 requires exactly three *total* indexes, each backed by its
  # expected non-deferrable constraint and built-in B-tree opclass, database
  # default deterministic comparator semantics, and exact index name.
  # An extra non-unique expression index is also forbidden: it could call
  # owner-controlled code and cause an unrelated transaction-ID wait.
  # Any catalog mismatch is HOLD pending PostgreSQL 16 runtime validation.

  # A broad transactionid lock witness is unsafe if an owner installs
  # INSERT triggers, rules, foreign keys, RLS or partitioning. Any added
  # write side effect can create an unrelated transaction wait. The approved
  # lab only accepts a plain single-primary physical heap with no triggers,
  # rewrite rules, foreign keys, RLS or inheritance/partition children.
  PG02_WRITE_SHAPE_SQL = <<~SQL.freeze
    SELECT (
      t.relkind = 'r'
      AND t.relam = (
        SELECT am.oid FROM pg_catalog.pg_am am
         WHERE am.amname = 'heap' AND am.amtype = 't'
           AND am.amhandler =
             'pg_catalog.heap_tableam_handler'::regproc
      )
      AND t.relpersistence = 'p'
      AND NOT t.relispartition
      AND NOT t.relrowsecurity
      AND NOT t.relforcerowsecurity
      AND NOT t.relhassubclass
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger tr
         WHERE tr.tgrelid = t.oid
      )
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_rewrite rw
         WHERE rw.ev_class = t.oid
      )
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint co
         WHERE co.conrelid = t.oid
           AND co.contype NOT IN ('p', 'u', 'c')
      )
      -- The schema defines exactly FIVE CHECK constraints. Extra CHECKs
      -- can invoke user-defined SECURITY DEFINER functions and cause
      -- transaction-ID locks in auxiliary tables. Names are necessary
      -- but not sufficient: reject all non-catalog function/operator
      -- dependencies of ANY CHECK constraint, too.
      AND (
        SELECT COUNT(*)
          FROM pg_catalog.pg_constraint co
         WHERE co.conrelid = t.oid AND co.contype = 'c'
      ) = 5
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint co
         WHERE co.conrelid = t.oid AND co.contype = 'c'
           AND co.conname NOT IN (
             'a3_t2c_nonce_digest_canonical',
             'a3_t2c_checkout_digest_canonical',
             'a3_t2c_valid_checkout_version',
             'a3_t2c_valid_issuance_window',
             'a3_t2c_bounded_refs'
           )
      )
      AND NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_constraint co
          JOIN pg_catalog.pg_depend dep
            ON dep.classid = 'pg_catalog.pg_constraint'::regclass
           AND dep.objid = co.oid
          JOIN pg_catalog.pg_proc proc
            ON dep.refclassid = 'pg_catalog.pg_proc'::regclass
           AND dep.refobjid = proc.oid
          JOIN pg_catalog.pg_namespace ns
            ON ns.oid = proc.pronamespace
         WHERE co.conrelid = t.oid AND co.contype = 'c'
           AND ns.nspname <> 'pg_catalog'
      )
      AND NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_constraint co
          JOIN pg_catalog.pg_depend dep
            ON dep.classid = 'pg_catalog.pg_constraint'::regclass
           AND dep.objid = co.oid
          JOIN pg_catalog.pg_operator op
            ON dep.refclassid = 'pg_catalog.pg_operator'::regclass
           AND dep.refobjid = op.oid
          JOIN pg_catalog.pg_namespace ns
            ON ns.oid = op.oprnamespace
         WHERE co.conrelid = t.oid AND co.contype = 'c'
           AND ns.nspname <> 'pg_catalog'
      )
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_inherits inh
         WHERE inh.inhparent = t.oid OR inh.inhrelid = t.oid
      )
    ) AS no_conflicting_side_effects
      FROM pg_catalog.pg_class t
     WHERE t.oid = 'a3_t2c.nonce_issuance_history'::regclass
  SQL

  # Fully pin the five approved CHECK expressions. Testing only their
  # names or membership in pg_catalog is unsafe: volatile catalog builtins
  # can cause unrelated transaction waits. The deparsed CHECK text is
  # conservatively token-matched to the exact approved source expressions;
  # unmatched PG16 formatting must FAIL CLOSED (future B verification).
  CHECK_EXPR_SQL = <<~SQL.freeze
    SELECT conname, pg_catalog.pg_get_expr(conbin, conrelid) AS expression
      FROM pg_catalog.pg_constraint
     WHERE conrelid = 'a3_t2c.nonce_issuance_history'::regclass
       AND contype = 'c' AND convalidated
       AND conislocal AND coninhcount = 0 AND NOT connoinherit
     ORDER BY conname
  SQL

  CHECK_BOUND_REF_COLUMNS = %w[
    issuance_ref challenge_ref host_verifier_domain aud agent_thumbprint
    buyer_account_ref tenant_id checkout_id checkout_jwt_source_ref
  ].freeze

  # The normalizer strips ONLY syntactic grouping parentheses and outside
  # whitespace. It preserves quoted literal contents and all operators,
  # casts, names, operands and conjunction order. Every approved expression
  # uses only AND with fixed ranges; changing parentheses cannot add a
  # function or change its evaluation via OR.
  CHECK_BOUNDS_COMPARISON = CHECK_BOUND_REF_COLUMNS.map { |name|
    "char_length#{name}>=1ANDchar_length#{name}<=256"
  }.join("AND").freeze
  CHECK_BOUNDS_BETWEEN = CHECK_BOUND_REF_COLUMNS.map { |name|
    "char_length#{name}BETWEEN1AND256"
  }.join("AND").freeze

  APPROVED_CHECK_TOKENS = {
    "a3_t2c_nonce_digest_canonical" => [
      "nonce_sha256::text~'^[0-9a-f]{64}$'::text",
      "nonce_sha256::text~'^[0-9a-f]{64}$'"
    ].freeze,
    "a3_t2c_checkout_digest_canonical" => [
      "merchant_checkout_sha256::text~'^[0-9a-f]{64}$'::text",
      "merchant_checkout_sha256::text~'^[0-9a-f]{64}$'"
    ].freeze,
    "a3_t2c_valid_checkout_version" => ["checkout_version>=1"].freeze,
    "a3_t2c_valid_issuance_window" => ["issued_at<expires_at"].freeze,
    "a3_t2c_bounded_refs" => [
      CHECK_BOUNDS_COMPARISON, CHECK_BOUNDS_BETWEEN
    ].freeze
  }.freeze

  # PG02 must not credit transaction-ID waits created by arbitrary
  # omitted-column defaults or generated expressions. The worker supplies
  # every approved column explicitly; reject ANY extra/reordered/dropped
  # column, changed type, identity/generated column, or default on a field
  # that the approved source declared without one. Existing approved defaults
  # for fields 15/16 are never evaluated by the explicit worker INSERT.
  PG02_INSERT_COLUMNS_SQL = <<~SQL.freeze
    WITH expected(attnum, attname, formatted_type) AS (
      VALUES
        (1, 'issuance_ref', 'text'),
        (2, 'nonce_sha256', 'character(64)'),
        (3, 'challenge_ref', 'text'),
        (4, 'host_verifier_domain', 'text'),
        (5, 'aud', 'text'),
        (6, 'agent_thumbprint', 'text'),
        (7, 'buyer_account_ref', 'text'),
        (8, 'tenant_id', 'text'),
        (9, 'checkout_id', 'text'),
        (10, 'checkout_version', 'integer'),
        (11, 'merchant_checkout_sha256', 'character(64)'),
        (12, 'checkout_jwt_source_ref', 'text'),
        (13, 'issued_at', 'timestamp with time zone'),
        (14, 'expires_at', 'timestamp with time zone'),
        (15, 'issuance_xid', 'text'),
        (16, 'recorded_at', 'timestamp with time zone')
    )
    SELECT (
      (SELECT COUNT(*)
         FROM pg_catalog.pg_attribute a
        WHERE a.attrelid = 'a3_t2c.nonce_issuance_history'::regclass
          AND a.attnum > 0
      ) = 16
      AND NOT EXISTS (
        SELECT 1 FROM expected e
        LEFT JOIN pg_catalog.pg_attribute a
          ON a.attrelid = 'a3_t2c.nonce_issuance_history'::regclass
         AND a.attnum = e.attnum
        WHERE a.attname IS DISTINCT FROM e.attname
           OR pg_catalog.format_type(a.atttypid, a.atttypmod)
                IS DISTINCT FROM e.formatted_type
           OR a.attnotnull IS DISTINCT FROM true
           OR a.attisdropped IS DISTINCT FROM false
           OR a.attgenerated IS DISTINCT FROM ''
           OR a.attidentity IS DISTINCT FROM ''
           OR a.atthasdef IS DISTINCT FROM (e.attnum IN (15, 16))
      )
    ) AS exact_explicit_insert_columns
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
      # Never inherit a REPEATABLE READ snapshot established by a caller:
      # stale catalogs can falsely credit a current unrelated lock wait.
      return false unless idle_reader_connection?(reader)
      return false unless reader_session?(reader) == true
      return false unless idle_reader_connection?(reader)
      return false unless [waiting_pid, holding_pid].all? { |pid|
        pid.is_a?(Integer) && pid.between?(1, 2_147_483_647)
      } && waiting_pid != holding_pid

      # Own a fresh READ COMMITTED, READ ONLY scope. Every failed or
      # uncertain BEGIN/COMMIT returns false; PG02 supervisor preserves
      # the observer connection for quarantine when proof is unavailable.
      begin_attempted = false
      commit_acknowledged = false
      begin
        begin_attempted = true
        began = reader.exec("BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY")
        return false unless began.respond_to?(:cmd_status) &&
          began.cmd_status == "BEGIN"
        path_ack = reader.exec("SET LOCAL search_path = pg_catalog, pg_temp")
        return false unless path_ack.respond_to?(:cmd_status) &&
          path_ack.cmd_status == "SET"

        # Even a real transactionid wait can come from a different index
        # or executable column expression. All shapes must match.
        shape_ok = unique_index_shape?(reader) &&
                   pg02_write_shape?(reader) &&
                   pg02_check_expressions_shape?(reader) &&
                   pg02_insert_columns_shape?(reader)
        observed = false
        if shape_ok
          result = reader.exec_params(PG02_LOCK_WITNESS_SQL,
                                      [waiting_pid, holding_pid])
          observed = singleton_row(result) &&
                     result[0]["unique_lock_wait_observed"] == "t"
          # READ COMMITTED observes fresh snapshots per statement; reject
          # a schema that changed while the lock was being witnessed.
          observed &&= unique_index_shape?(reader) &&
                      pg02_write_shape?(reader) &&
                      pg02_check_expressions_shape?(reader) &&
                      pg02_insert_columns_shape?(reader)
        end
        ack = reader.exec("COMMIT")
        commit_acknowledged = ack.respond_to?(:cmd_status) &&
                              ack.cmd_status == "COMMIT"
        observed && commit_acknowledged && idle_reader_connection?(reader)
      ensure
        # No Thread.kill, connection.close or blind reuse on unknown ACK.
        # The caller's retained connection is a B-time cleanup obligation.
        if begin_attempted && !commit_acknowledged
          begin
            reader.exec("ROLLBACK")
          rescue StandardError
            nil
          end
        end
      end
    rescue StandardError
      false
    end

    # Future approval B only: separately supplied, actual reader credential.
    # Positive-looking catalog observations still deliberately status=HOLD.
    # Note: a catalog check alone cannot prove denied mutation under writer
    # credentials; PG03 must *also* attempt it and inspect SQLSTATE 42501.
    def inspect_catalog_only(reader:)
      session = reader_session?(reader)
      return session if session.is_a?(Observation)
      return hold("reader_role_unverified") unless session == true

      scoped = with_safe_reader_transaction(reader) do
        next hold("exact_unique_index_set_unverified") unless
          unique_index_shape?(reader)
        next hold("pg02_write_side_effects_unverified") unless
          pg02_write_shape?(reader)
        next hold("approved_check_expressions_unverified") unless
          pg02_check_expressions_shape?(reader)
        next hold("approved_insert_column_shape_unverified") unless
          pg02_insert_columns_shape?(reader)

        role_result = reader.exec_params(ROLE_SQL, [WRITER_ROLE])
        next hold("writer_acl_unverified") unless singleton_row(role_result)

        row = role_result[0]
        yes = ->(name) { row[name] == "t" }
        no = ->(name) { row[name] == "f" }
        next hold("writer_privilege_escape_or_append_only_not_proven") unless
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
      end
      scoped || hold("reader_catalog_safe_scope_or_commit_unverified")
    rescue StandardError
      hold("catalog_or_reader_unavailable")
    end

    # Future approval B only. The caller should retain 'before' and 'after'
    # snapshots from this read-only role, compare the FULL immutable bindings
    # after denied mutations, and fail if either snapshot was unavailable.
    def inspect_issuance_only(reader:, issuance_ref:)
      session = reader_session?(reader)
      return session if session.is_a?(Observation)
      return hold("reader_role_unverified") unless session == true
      scoped = with_safe_reader_transaction(reader) do
        next hold("invalid_synthetic_issuance_ref") unless
          issuance_ref.is_a?(String) && issuance_ref.ascii_only? &&
          issuance_ref.bytesize.between?(1, 256)

        result = reader.exec_params(EVENT_SQL, [issuance_ref.dup.freeze])
        next hold("issuance_not_uniquely_readable") unless singleton_row(result)
        row = result[0]
        next hold("event_not_bounded") unless row.is_a?(Hash) &&
          row.keys.sort == %w[
            issuance_ref nonce_sha256 challenge_ref host_verifier_domain
            aud agent_thumbprint buyer_account_ref tenant_id checkout_id
            checkout_version merchant_checkout_sha256 checkout_jwt_source_ref
            issued_at expires_at issuance_xid
          ].sort &&
          row.values.all? { |v| v.is_a?(String) && v.bytesize.between?(1, 256) }

        Observation.new(reason: "lab_issuance_row_only_not_host_provenance",
                        event: row)
      end
      scoped || hold("reader_issuance_safe_scope_or_commit_unverified")
    rescue StandardError
      hold("reader_issuance_lookup_unavailable")
    end

    # An absence of a row after failure is NOT proof that a commit never
    # happened; disconnected/rolled-back observation is still HOLD.
    def hold(reason)
      Observation.new(reason: reason)
    end

    private

    def pg02_write_shape?(reader)
      result = reader.exec(PG02_WRITE_SHAPE_SQL)
      singleton_row(result) &&
        result[0]["no_conflicting_side_effects"] == "t"
    rescue StandardError
      false
    end

    def pg02_check_expressions_shape?(reader)
      result = reader.exec(CHECK_EXPR_SQL)
      return false unless result.respond_to?(:ntuples) &&
        result.ntuples == APPROVED_CHECK_TOKENS.length

      observed = {}
      result.ntuples.times do |index|
        row = result[index]
        return false unless row.is_a?(Hash) &&
          row["conname"].is_a?(String) && row["expression"].is_a?(String)
        name = row["conname"]
        allowed = APPROVED_CHECK_TOKENS[name]
        return false if !allowed || observed.key?(name)
        shape = check_expression_tokens(row["expression"])
        return false unless shape && allowed.include?(shape)
        observed[name] = true
      end
      observed.keys.sort == APPROVED_CHECK_TOKENS.keys.sort
    rescue StandardError
      false
    end

    # PG16's pg_get_expr deparser qualifies *built-in* function/operator
    # names when the reader search_path shadows them. Only remove explicit
    # pg_catalog qualification for the EXACT safe built-ins used in the
    # approved five CHECKs. Never strip arbitrary schema qualifiers:
    # custom functions, volatile built-ins (e.g. lo_create) and rewritten
    # constraints must remain visible and FAIL CLOSED.
    def canonical_approved_catalog_tokens(unquoted)
      # Normalize with syntax boundaries still present. Removing "("
      # prematurely joins char_length and its first argument, causing a
      # correct pg_catalog.char_length(arg) to be rejected as a new name.
      normalized = unquoted
        .gsub(/(?<![A-Za-z0-9_])pg_catalog\.char_length(?=[[:space:]]*\()/,
              "char_length")
        .gsub(/(?<![A-Za-z0-9_])pg_catalog\.text(?![A-Za-z0-9_])/,
              "text")
        .gsub(/(?<![A-Za-z0-9_])OPERATOR[[:space:]]*\([[:space:]]*pg_catalog\.[[:space:]]*(>=|<=|<>|~|=|<|>)[[:space:]]*\)/) {
          Regexp.last_match(1)
        }
      # Drop only formatting/grouping AFTER exact catalog token matching.
      normalized.gsub(/[()]|[[:space:]]/, "")
    end

    # Preserve EVERYTHING inside quoted literals and quoted identifiers.
    # Outside quotes ignore only grouping parentheses/format whitespace;
    # canonicalize a tiny explicit allowlist of pg_catalog spellings above.
    # A user-schema shadow (e.g. evil.char_length) never normalizes.
    def check_expression_tokens(expression)
      return nil unless expression.is_a?(String) &&
        expression.ascii_only? && expression.bytesize.between?(1, 8192)
      output = +""
      unquoted = +""
      quote = nil
      index = 0
      while index < expression.length
        char = expression[index]
        if quote
          output << char
          if char == quote
            if expression[index + 1] == quote
              index += 1
              output << expression[index]
            else
              quote = nil
            end
          end
        elsif char == "'" || char == '"'
          output << canonical_approved_catalog_tokens(unquoted)
          unquoted.clear
          quote = char
          output << char
        else
          # Keep delimiters until canonical_approved_catalog_tokens has
          # matched the function-call/operator boundary.
          unquoted << char
        end
        index += 1
      end
      return nil unless quote.nil?

      output << canonical_approved_catalog_tokens(unquoted)
      output
    rescue StandardError
      nil
    end

    def pg02_insert_columns_shape?(reader)
      res = reader.exec(PG02_INSERT_COLUMNS_SQL)
      singleton_row(res) &&
        res[0]["exact_explicit_insert_columns"] == "t"
    rescue StandardError
      false
    end

    def unique_index_shape?(reader)
      res = reader.exec(INDEX_SQL)
      singleton_row(res) &&
        res[0]["total_indexes"] == "3" &&
        res[0]["matching_indexes"] == "1" &&
        res[0]["issuance_unique_indexes"] == "1" &&
        res[0]["challenge_unique_indexes"] == "1"
    rescue StandardError
      false
    end

    def idle_reader_connection?(reader)
      defined?(PG::PQTRANS_IDLE) &&
        reader.respond_to?(:transaction_status) &&
        reader.transaction_status == PG::PQTRANS_IDLE
    rescue StandardError
      false
    end

    # An independent reader observation owns a fresh, trusted-path READ
    # ONLY transaction. An uncertain BEGIN/SET/COMMIT (including failed or
    # unacknowledged cleanup ROLLBACK) *retains the actual reader socket*.
    # Ordinary negative observations and quarantined sockets are distinct.
    def with_safe_reader_transaction(reader)
      return quarantine_reader(reader, "reader_prior_transaction_unverified_stop") unless
        idle_reader_connection?(reader)

      begun = false
      committed = false
      begin
        begun = true
        ack = reader.exec("BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY")
        if ack.respond_to?(:cmd_status) && ack.cmd_status == "BEGIN"
          safe_path = reader.exec("SET LOCAL search_path = pg_catalog, pg_temp")
          if safe_path.respond_to?(:cmd_status) && safe_path.cmd_status == "SET"
            value = yield
            finish = reader.exec("COMMIT")
            committed = finish.respond_to?(:cmd_status) &&
                        finish.cmd_status == "COMMIT" &&
                        idle_reader_connection?(reader)
            return value if committed
          end
        end
      rescue StandardError
        # Never mask an unfinished connection as an ordinary negative.
        nil
      ensure
        if begun && !committed
          begin
            reader.exec("ROLLBACK")
          rescue StandardError
            nil
          end
        end
      end
      quarantine_reader(reader, "reader_transaction_or_commit_ack_unverified_stop")
    end

    def quarantine_reader(reader, reason)
      Observation.new(reason: reason, connections: [reader])
    end

    def reader_session?(reader)
      # Outside an oracle-owned transaction only. An existing transaction
      # can retain a stale snapshot even when the apparent catalog is safe.
      # Even before BEGIN, a non-idle/unqueryable reader may own an
      # externally started transaction. Do not lose its cleanup obligation
      # by reducing this state to a plain negative boolean.
      return quarantine_reader(reader, "reader_preexisting_or_unverified_transaction_stop") unless
        idle_reader_connection?(reader)
      observed = with_safe_reader_transaction(reader) do
        res = reader.exec(<<~SQL)
          SELECT current_user AS role_name, session_user AS login_role,
                 pg_catalog.pg_is_in_recovery() AS replica,
                 pg_catalog.has_table_privilege(current_user,
                   'a3_t2c.nonce_issuance_history', 'SELECT') AS may_read,
                 pg_catalog.has_table_privilege(current_user,
                   'a3_t2c.nonce_issuance_history', 'INSERT') AS may_insert,
                 pg_catalog.has_table_privilege(current_user,
                   'a3_t2c.nonce_issuance_history', 'UPDATE') AS may_update,
                 pg_catalog.has_table_privilege(current_user,
                   'a3_t2c.nonce_issuance_history', 'DELETE') AS may_delete,
                 pg_catalog.has_table_privilege(current_user,
                   'a3_t2c.nonce_issuance_history', 'TRUNCATE') AS may_truncate
        SQL
        next false unless singleton_row(res) &&
          res[0]["role_name"] == READER_ROLE &&
          res[0]["login_role"] == READER_ROLE &&
          authenticated_connection_user?(reader, READER_ROLE) &&
          res[0]["replica"] == "f" &&
          res[0]["may_read"] == "t" &&
          %w[may_insert may_update may_delete may_truncate].all? {
            |k| res[0][k] == "f"
          }

        # This independent catalog interrogation also checks owner membership,
        # inherited rights and transitive PG16 SET ROLE membership, including
        # a reader that can assume an entirely different privileged identity.
        roles = reader.exec_params(ROLE_SQL, [READER_ROLE])
        next false unless singleton_row(roles)
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
          ].all? { |key| acl[key] == "f" } &&
          defined?(PG::PQTRANS_INTRANS) &&
          reader.transaction_status == PG::PQTRANS_INTRANS
      end
      # Propagate *quarantined* sessions to public read-only entrypoints,
      # rather than erasing the reader handle via Observation == true.
      observed.is_a?(Observation) ? observed : observed == true
    rescue StandardError
      # A failure of transaction-state/reader inspection can be an
      # unacknowledged command, not a proven completed negative result.
      quarantine_reader(reader, "reader_session_observation_uncertain_stop")
    end

    # libpq startup user is stored in connection options before SQL. Unlike
    # current_user and session_user this is not replaced by the SQL command
    # SET SESSION AUTHORIZATION. Require a real PG::Connection and exact
    # startup user; missing/ambiguous values are HOLD, never trusted.
    def authenticated_connection_user?(connection, expected)
      return false unless defined?(PG::Connection) &&
        connection.instance_of?(PG::Connection) &&
        connection.respond_to?(:conninfo_hash)

      info = connection.conninfo_hash
      return false unless info.is_a?(Hash)
      user = info[:user]
      user.is_a?(String) && user == expected
    rescue StandardError
      false
    end

    def singleton_row(result)
      result.respond_to?(:ntuples) && result.ntuples == 1
    end
  end
end
