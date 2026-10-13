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
  issuance_xid              text NOT NULL DEFAULT pg_current_xact_id()::text,
  recorded_at               timestamptz NOT NULL DEFAULT transaction_timestamp(),

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
REVOKE ALL ON TABLE a3_t2c.nonce_issuance_history FROM PUBLIC;
REVOKE ALL ON SCHEMA a3_t2c FROM a3_t2c_writer, a3_t2c_reader;
GRANT USAGE ON SCHEMA a3_t2c TO a3_t2c_writer, a3_t2c_reader;
GRANT INSERT ON TABLE a3_t2c.nonce_issuance_history TO a3_t2c_writer;
GRANT SELECT ON TABLE a3_t2c.nonce_issuance_history TO a3_t2c_reader;

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
