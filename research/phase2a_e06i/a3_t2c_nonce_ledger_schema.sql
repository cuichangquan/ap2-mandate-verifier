-- A3-T2c / Issue #97 — SOURCE-ONLY PostgreSQL 16 synthetic lab proposal.
-- APPROVAL A: create and statically review this text. NOT APPLIED / NOT RUN.
-- DO NOT execute this SQL without separate Owner approval B, disposable isolated
-- PG16 primary, known billing/cleanup plan and independently verified roles.
--
-- PREREQUISITES (not created here):
--   a3_t2c_writer = LOGIN, not superuser/table owner or member of owner,
--                   no CREATE, UPDATE, DELETE, TRUNCATE, role grant or SET ROLE.
--   a3_t2c_reader = separate LOGIN; only USAGE/SELECT for independent oracle.
--   The schema installer/owner must be an independent restricted lab admin.
--   The script MUST fail rather than silently create permissive credentials.
--
-- This ONE immutable issuance row also stores the Challenge/Checkout bindings.
-- It is the single transaction commit unit, not a detached event+challenge pair.
-- This DB is NOT authenticated Host enrollment, not a CSPRNG proof, not a
-- cross-primary uniqueness proof, not final nonce consumption / payment approval.

BEGIN;
-- Transaction-local trusted function/operator/type resolution for ALL DDL,
-- PL/pgSQL format(), dynamic REVOKE and ACL predicates. pg_temp is
-- explicitly LAST so temporary objects cannot shadow catalog types.
SET LOCAL search_path = pg_catalog, pg_temp;

CREATE SCHEMA a3_t2c;
REVOKE ALL ON SCHEMA a3_t2c FROM PUBLIC;

CREATE TABLE a3_t2c.nonce_issuance_history (
  issuance_ref             text PRIMARY KEY,
  nonce_sha256              char(64) NOT NULL,
  challenge_ref             text NOT NULL UNIQUE,
  host_verifier_domain      text NOT NULL,
  aud                       text NOT NULL,
  agent_thumbprint          text NOT NULL,
  buyer_account_ref         text NOT NULL,
  tenant_id                 text NOT NULL,
  checkout_id               text NOT NULL,
  checkout_version          integer NOT NULL,
  merchant_checkout_sha256  char(64) NOT NULL,
  checkout_jwt_source_ref   text NOT NULL,
  issued_at                 timestamptz NOT NULL,
  expires_at                timestamptz NOT NULL,
  -- Transaction ID is a diagnostic correlation handle, NOT a durable
  -- commit acknowledgment or an authenticated Host audit root.
  issuance_xid              text NOT NULL DEFAULT pg_catalog.pg_current_xact_id()::pg_catalog.text,
  recorded_at               timestamptz NOT NULL DEFAULT pg_catalog.transaction_timestamp(),

  -- Critically, this uniqueness is GLOBAL to the entire table, not
  -- tenant/session/challenge/expiry scoped and not a partial index.
  CONSTRAINT a3_t2c_global_nonce_unique UNIQUE (nonce_sha256),
  CONSTRAINT a3_t2c_nonce_digest_canonical
    CHECK (nonce_sha256::text ~ '^[0-9a-f]{64}$'),
  CONSTRAINT a3_t2c_checkout_digest_canonical
    CHECK (merchant_checkout_sha256::text ~ '^[0-9a-f]{64}$'),
  CONSTRAINT a3_t2c_valid_checkout_version CHECK (checkout_version >= 1),
  CONSTRAINT a3_t2c_valid_issuance_window CHECK (issued_at < expires_at),
  CONSTRAINT a3_t2c_bounded_refs CHECK (
    char_length(issuance_ref) BETWEEN 1 AND 256 AND
    char_length(challenge_ref) BETWEEN 1 AND 256 AND
    char_length(host_verifier_domain) BETWEEN 1 AND 256 AND
    char_length(aud) BETWEEN 1 AND 256 AND
    char_length(agent_thumbprint) BETWEEN 1 AND 256 AND
    char_length(buyer_account_ref) BETWEEN 1 AND 256 AND
    char_length(tenant_id) BETWEEN 1 AND 256 AND
    char_length(checkout_id) BETWEEN 1 AND 256 AND
    char_length(checkout_jwt_source_ref) BETWEEN 1 AND 256
  )
);

-- The entire issuance history is APPEND ONLY for the actual worker.
-- Expiry/consumption state must be stored separately; never rewrite or purge
-- issuance rows, nonce hashes, challenge or Checkout/JWT bindings.
-- PostgreSQL table owner, superuser and backup restore remain beyond
-- this restricted-writer guarantee (separate failure/rollback investigation).
-- Explicitly erase any per-role table grants automatically populated by
-- ALTER DEFAULT PRIVILEGES. Revoking PUBLIC alone cannot remove named grants.
-- Effective grants inherited through other roles cannot be revoked here;
-- the fail-closed catalog assertion below must reject those configurations.
REVOKE ALL ON TABLE a3_t2c.nonce_issuance_history
  FROM PUBLIC, a3_t2c_writer, a3_t2c_reader;

-- PostgreSQL column ACLs survive a table-level REVOKE. Explicitly drop
-- all column-level SELECT/INSERT/UPDATE/REFERENCES grants from PUBLIC and
-- both lab identities. Inherited column grants must fail the catalog
-- assertions below; an owner/superuser must not be a lab identity.
DO $a3_t2c_columns$
DECLARE
  col record;
BEGIN
  FOR col IN
    SELECT attname
      FROM pg_catalog.pg_attribute
     WHERE attrelid = 'a3_t2c.nonce_issuance_history'::regclass
       AND attnum > 0 AND NOT attisdropped
  LOOP
    EXECUTE pg_catalog.format(
      'REVOKE SELECT (%1$I), INSERT (%1$I), UPDATE (%1$I), REFERENCES (%1$I) ' ||
      'ON TABLE a3_t2c.nonce_issuance_history ' ||
      'FROM PUBLIC, a3_t2c_writer, a3_t2c_reader',
      col.attname
    );
  END LOOP;
END;
$a3_t2c_columns$;

REVOKE ALL ON SCHEMA a3_t2c FROM a3_t2c_writer, a3_t2c_reader;
GRANT USAGE ON SCHEMA a3_t2c TO a3_t2c_writer, a3_t2c_reader;
GRANT INSERT ON TABLE a3_t2c.nonce_issuance_history TO a3_t2c_writer;
GRANT SELECT ON TABLE a3_t2c.nonce_issuance_history TO a3_t2c_reader;

-- Fail the whole DDL transaction if either effective role is privileged,
-- owns the table via membership, or can SET ROLE to a dangerous role.
-- PG16 pg_auth_members.set_option is traversed transitively. Inherited
-- grants are caught by has_table_privilege on the effective role, even when
-- SET ROLE is not available. All SET ROLE paths are prohibited. A subsequent role grant/privilege change
-- requires an independent B-time recheck under actual credentials.
DO $a3_t2c_acl$
DECLARE
  lab_role text;
  should_insert boolean;
  should_select boolean;
BEGIN
  FOR lab_role IN SELECT unnest(ARRAY['a3_t2c_writer', 'a3_t2c_reader'])
  LOOP
    should_insert := lab_role = 'a3_t2c_writer';
    should_select := lab_role = 'a3_t2c_reader';

    -- PG16 ADMIN OPTION allows delegation even with SET FALSE and
    -- INHERIT FALSE. The tiny lab has NO legitimate membership requirement:
    -- prohibit ANY membership for either lab role, regardless of option.
    IF EXISTS (
      SELECT 1 FROM pg_catalog.pg_auth_members m
       WHERE m.member = (SELECT oid FROM pg_catalog.pg_roles
                          WHERE rolname = lab_role)
    ) THEN
      RAISE EXCEPTION 'A3-T2c lab role has membership/admin-option escape: %',
        lab_role;
    END IF;

    IF EXISTS (
      WITH RECURSIVE assumable(oid) AS (
        SELECT oid FROM pg_catalog.pg_roles WHERE rolname = lab_role
        UNION
        SELECT m.roleid FROM pg_catalog.pg_auth_members m
          JOIN assumable a ON m.member = a.oid
         WHERE m.set_option
      )
      SELECT 1 FROM assumable a
        JOIN pg_catalog.pg_roles role ON role.oid = a.oid
        JOIN pg_catalog.pg_class t
          ON t.oid = 'a3_t2c.nonce_issuance_history'::regclass
        JOIN pg_catalog.pg_namespace ns ON ns.oid = t.relnamespace
       WHERE a.oid <> (SELECT oid FROM pg_catalog.pg_roles
                        WHERE rolname = lab_role)
          OR role.rolsuper OR role.rolcreaterole OR role.rolcreatedb
          OR role.rolbypassrls OR role.rolreplication
          OR NOT role.rolcanlogin AND a.oid =
            (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = lab_role)
          OR pg_catalog.pg_has_role(a.oid, t.relowner, 'MEMBER')
          OR pg_catalog.has_schema_privilege(a.oid, ns.oid, 'CREATE')
          OR pg_catalog.has_table_privilege(a.oid, t.oid, 'UPDATE')
          OR pg_catalog.has_table_privilege(a.oid, t.oid, 'DELETE')
          OR pg_catalog.has_table_privilege(a.oid, t.oid, 'TRUNCATE')
          OR pg_catalog.has_table_privilege(a.oid, t.oid, 'TRIGGER')
          OR pg_catalog.has_table_privilege(a.oid, t.oid, 'REFERENCES')
    ) THEN
      RAISE EXCEPTION 'A3-T2c unsafe effective/assumable % role', lab_role;
    END IF;

    -- Per-column ACLs are independent of has_table_privilege. Verify
    -- actual *effective* privileges for every immutable binding column,
    -- including inherited grants. Writer must never SELECT/UPDATE/
    -- REFERENCES any column; reader must never INSERT/UPDATE/REFERENCES.
    IF EXISTS (
      SELECT 1
        FROM pg_catalog.pg_attribute a
       WHERE a.attrelid = 'a3_t2c.nonce_issuance_history'::regclass
         AND a.attnum > 0 AND NOT a.attisdropped
         AND (
           pg_catalog.has_column_privilege(lab_role,
             'a3_t2c.nonce_issuance_history', a.attname, 'UPDATE')
           OR pg_catalog.has_column_privilege(lab_role,
             'a3_t2c.nonce_issuance_history', a.attname, 'REFERENCES')
           OR (should_insert AND pg_catalog.has_column_privilege(lab_role,
             'a3_t2c.nonce_issuance_history', a.attname, 'SELECT'))
           OR (should_select AND pg_catalog.has_column_privilege(lab_role,
             'a3_t2c.nonce_issuance_history', a.attname, 'INSERT'))
         )
    ) THEN
      RAISE EXCEPTION 'A3-T2c unsafe column privileges for %', lab_role;
    END IF;

    IF pg_catalog.has_table_privilege(lab_role,
         'a3_t2c.nonce_issuance_history', 'INSERT') IS DISTINCT FROM should_insert
       OR pg_catalog.has_table_privilege(lab_role,
         'a3_t2c.nonce_issuance_history', 'SELECT') IS DISTINCT FROM should_select
       OR pg_catalog.has_schema_privilege(lab_role, 'a3_t2c', 'CREATE')
       OR NOT pg_catalog.has_schema_privilege(lab_role, 'a3_t2c', 'USAGE')
       OR NOT (SELECT rolcanlogin FROM pg_catalog.pg_roles WHERE rolname = lab_role)
    THEN
      RAISE EXCEPTION 'A3-T2c role ACL shape invalid: %', lab_role;
    END IF;
  END LOOP;
END;
$a3_t2c_acl$;

COMMENT ON TABLE a3_t2c.nonce_issuance_history IS
  'Issue #97 synthetic Host-wide nonce issuance lab; untrusted for G1/G7; NEVER DELETE/UPDATE/TRUNCATE history';

COMMIT;

-- REQUIRED for separately approved B, not fulfilled by this SQL text:
-- 1. Verify effective writer role and inherited/membership privileges: cannot
--    ALTER schema/table, GRANT, SET ROLE owner, UPDATE/DELETE/TRUNCATE rows.
-- 2. Under *actual* issuance writer credentials negatively attempt UPDATE
--    (nonce_sha256, Challenge, Checkout/JWT digest), DELETE and TRUNCATE;
--    each must FAIL, independently check original row remains untouched.
-- 3. Inspect pg_catalog for one full-table unique index on nonce_sha256,
--    no partial predicate; ensure all tenant workers use this very primary.
-- 4. A separate immutable audit source is required for restore/DBA rollback;
--    PG06 and Host root/clock/G1/G7 are NOT proven here.
