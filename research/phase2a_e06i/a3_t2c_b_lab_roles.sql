-- Issue #97 / A3-T2c additional Approval A2: SOURCE ONLY, NOT APPLIED.
-- A proposed bootstrap for an independently verified, disposable PG16 cluster.
-- NO DATABASE OR ROLE IS CREATED OR MODIFIED BY THIS FILE UNTIL APPROVAL B.
-- Never use against an existing/shared cluster, production DB, or CI service.
--
-- Prerequisites for separately authorized Approval B:
-- * A supervisor independently identifies the disposable cluster and its
--   sole intended database a3_t2c_b_disposable BEFORE executing any DDL.
-- * An out-of-band, disposable installer LOGIN named a3_t2c_b_installer owns
--   the disposable database and has tightly controlled CREATEROLE rights.
-- * Local socket or loopback authentication is configured out of band.
-- * This file contains no password. Roles with PASSWORD NULL cannot use
--   password-based login; a separately approved secure auth mechanism is
--   REQUIRED before any writer/reader session can open.
-- * Existing cluster-level owner/DBA powers and restore rollback are OUT
--   OF SCOPE. SQL identifiers/DB names are safeguards, not proof of isolation.
-- * This script MUST NOT silently reuse existing lab roles.
--
-- Do not use psql's ON_ERROR_STOP alone as evidence of applied permissions.
-- Independently verify the top-level DO COMMIT and actual PG16 privileges.

-- Single top-level DO is intentionally the entire bootstrap transaction.
-- Its final PL/pgSQL COMMIT is legal only for a top-level DO, NOT inside any
-- pre-existing explicit transaction (including psql --single-transaction).
-- If the caller already owns a transaction, COMMIT raises and PostgreSQL
-- aborts/rolls back these uncommitted role and ACL changes. Never replace
-- this with a bare SQL BEGIN/COMMIT pair or an error-ignoring wrapper.
-- Execute as ONE top-level statement on a fresh, verified session, with
-- client error-stop enabled; no arbitrary multi-statement batching.
DO $a3_t2c_b_bootstrap$
DECLARE
  db_owner text;
BEGIN
  PERFORM pg_catalog.set_config('search_path', 'pg_catalog, pg_temp', true);

  -- The lab is explicitly PG16-only. Check *before* cluster-wide DDL.
  IF pg_catalog.current_setting('server_version_num')::integer NOT BETWEEN
     160000 AND 169999 THEN
    RAISE EXCEPTION 'A3-T2c B requires PostgreSQL 16; STOP';
  END IF;

  IF pg_catalog.current_database() <> 'a3_t2c_b_disposable' OR
     current_user <> 'a3_t2c_b_installer' OR
     session_user <> 'a3_t2c_b_installer' OR
     pg_catalog.pg_is_in_recovery() THEN
    RAISE EXCEPTION 'A3-T2c B lab context mismatch; STOP';
  END IF;

  SELECT pg_catalog.pg_get_userbyid(d.datdba) INTO db_owner
    FROM pg_catalog.pg_database d
   WHERE d.datname = pg_catalog.current_database();
  IF db_owner IS DISTINCT FROM current_user THEN
    RAISE EXCEPTION 'A3-T2c B installer is not lab database owner; STOP';
  END IF;

  IF EXISTS (
      SELECT 1 FROM pg_catalog.pg_namespace n WHERE n.nspname = 'a3_t2c'
     ) OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_roles r
       WHERE r.rolname IN ('a3_t2c_writer', 'a3_t2c_reader')
     ) THEN
    RAISE EXCEPTION 'A3-T2c B schema or role already exists; STOP';
  END IF;

  -- A privileged or shared installer would defeat disposable scope.
  IF NOT EXISTS (
     SELECT 1 FROM pg_catalog.pg_roles r
      WHERE r.rolname = current_user
        AND r.rolcanlogin AND r.rolcreaterole
        AND NOT r.rolsuper AND NOT r.rolcreatedb
        AND NOT r.rolbypassrls AND NOT r.rolreplication
  ) THEN
    RAISE EXCEPTION 'A3-T2c B installer permissions not restricted; STOP';
  END IF;

  -- Fixed SQL strings only; no user-supplied SQL interpolation.
  -- Passwords and external authentication are NOT provisioned.
  EXECUTE 'CREATE ROLE a3_t2c_writer LOGIN NOINHERIT NOSUPERUSER NOCREATEDB
    NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD NULL';
  EXECUTE 'CREATE ROLE a3_t2c_reader LOGIN NOINHERIT NOSUPERUSER NOCREATEDB
    NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD NULL';

  -- Grants are restricted to the independently verified disposable database.
  -- Existing A3-T2c schema SQL must grant narrowly scoped table rights later.
  EXECUTE 'REVOKE CONNECT ON DATABASE a3_t2c_b_disposable FROM PUBLIC';
  EXECUTE 'GRANT CONNECT ON DATABASE a3_t2c_b_disposable
    TO a3_t2c_writer, a3_t2c_reader';

  -- Zero role membership, no owner switch and no elevated privileges.
  -- Verify this *again* with independent catalog/credential observations in B.
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_auth_members m
    JOIN pg_catalog.pg_roles r ON r.oid = m.member
    WHERE r.rolname IN ('a3_t2c_writer', 'a3_t2c_reader')
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles r
    WHERE r.rolname IN ('a3_t2c_writer', 'a3_t2c_reader')
      AND (r.rolsuper OR r.rolcreaterole OR r.rolcreatedb
        OR r.rolbypassrls OR r.rolreplication
        OR NOT r.rolcanlogin)
  ) THEN
    RAISE EXCEPTION 'A3-T2c B new role privilege escape; STOP';
  END IF;

  -- Critical fail-closed transaction fence: a pre-existing caller
  -- transaction CANNOT be committed by this script. In that context,
  -- PostgreSQL raises invalid transaction termination and rolls back DDL.
  -- As always, lost COMMIT acknowledgment remains HOLD until checked.
  COMMIT;
END;
$a3_t2c_b_bootstrap$;

-- SOURCE ONLY. No PostgreSQL or roles have been provisioned.
-- An independently approved B operator must confirm actual commit,
-- catalog/ACL/cluster identity, role authentication and manual cleanup.
-- SQL identifiers, observed version and a successful COMMIT are NOT
-- independent proof of cluster isolation or Host authenticity.
-- NO DROP ROLE, DROP DATABASE, ALTER SYSTEM, trust auth, or retry.
