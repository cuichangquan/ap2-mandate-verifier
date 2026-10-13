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

  # This query sees the *real catalog*, not declarations from the worker or
  # an untrusted fixture. Verifies a unique full-table index on exactly one
  # non-null nonce_sha256 column, with no WHERE predicate or expressions.
  INDEX_SQL = <<~SQL.freeze
    SELECT COUNT(*)::integer AS matching_indexes
      FROM pg_catalog.pg_index i
      JOIN pg_catalog.pg_class t ON t.oid = i.indrelid
      JOIN pg_catalog.pg_namespace n ON n.oid = t.relnamespace
      JOIN pg_catalog.pg_attribute a ON a.attrelid = t.oid
     WHERE n.nspname = 'a3_t2c'
       AND t.relname = 'nonce_issuance_history'
       AND a.attname = 'nonce_sha256'
       AND a.attnotnull
       AND NOT a.attisdropped
       AND i.indisunique
       AND i.indisvalid
       AND i.indisready
       AND i.indpred IS NULL
       AND i.indexprs IS NULL
       AND i.indnkeyatts = 1
       AND i.indkey[0] = a.attnum
  SQL

  # An independent reader checks the actual WRITER role's effective
  # privileges, including membership in table owner and privilege inheritance.
  # The writer session separately asserts current_user == WRITER_ROLE.
  ROLE_SQL = <<~SQL.freeze
    SELECT r.rolname AS writer_name, r.rolsuper, r.rolcreaterole,
           r.rolcreatedb, r.rolbypassrls, r.rolcanlogin,
           pg_catalog.pg_has_role(r.oid, t.relowner, 'MEMBER') AS owner_member,
           pg_catalog.has_table_privilege(r.oid, t.oid, 'INSERT') AS can_insert,
           pg_catalog.has_table_privilege(r.oid, t.oid, 'UPDATE') AS can_update,
           pg_catalog.has_table_privilege(r.oid, t.oid, 'DELETE') AS can_delete,
           pg_catalog.has_table_privilege(r.oid, t.oid, 'TRUNCATE') AS can_truncate,
           pg_catalog.has_schema_privilege(r.oid, n.oid, 'CREATE') AS schema_create
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

  class << self
    # Future approval B only: separately supplied, actual reader credential.
    # Positive-looking catalog observations still deliberately status=HOLD.
    # Note: a catalog check alone cannot prove denied mutation under writer
    # credentials; PG03 must *also* attempt it and inspect SQLSTATE 42501.
    def inspect_catalog_only(reader:)
      return hold("reader_role_unverified") unless reader_session?(reader)

      index_result = reader.exec(INDEX_SQL)
      return hold("global_unique_index_unverified") unless
        singleton_row(index_result) &&
        index_result[0]["matching_indexes"].to_i == 1

      role_result = reader.exec_params(ROLE_SQL, [WRITER_ROLE])
      return hold("writer_acl_unverified") unless singleton_row(role_result)

      row = role_result[0]
      yes = ->(name) { row[name] == "t" }
      no = ->(name) { row[name] == "f" }
      return hold("writer_privilege_escape_or_append_only_not_proven") unless
        row["writer_name"] == WRITER_ROLE &&
        yes.call("rolcanlogin") && yes.call("can_insert") &&
        %w[
          rolsuper rolcreaterole rolcreatedb rolbypassrls owner_member
          can_update can_delete can_truncate schema_create
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

    def reader_session?(reader)
      res = reader.exec(<<~SQL)
        SELECT current_user AS role_name, pg_is_in_recovery() AS replica,
               has_table_privilege(current_user,
                 'a3_t2c.nonce_issuance_history', 'SELECT') AS may_read,
               has_table_privilege(current_user,
                 'a3_t2c.nonce_issuance_history', 'INSERT') AS may_insert,
               has_table_privilege(current_user,
                 'a3_t2c.nonce_issuance_history', 'UPDATE') AS may_update,
               has_table_privilege(current_user,
                 'a3_t2c.nonce_issuance_history', 'DELETE') AS may_delete
      SQL
      singleton_row(res) &&
        res[0]["role_name"] == READER_ROLE &&
        res[0]["replica"] == "f" &&
        res[0]["may_read"] == "t" &&
        %w[may_insert may_update may_delete].all? { |k| res[0][k] == "f" }
    rescue StandardError
      false
    end

    def singleton_row(result)
      result.respond_to?(:ntuples) && result.ntuples == 1
    end
  end
end
