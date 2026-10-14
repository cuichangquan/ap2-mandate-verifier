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
-- Independently verify BEGIN/COMMIT and all effective privileges in PG16.

BEGIN;
SET LOCAL search_path = pg_catalog, pg_temp;

DO $a3_t2c_b_scope$
DECLARE
  db_owner text;
BEGIN
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

  -- The installer must be restricted; otherwise a mistaken privileged
  -- connection could apply the script to a database bearing the same name.
  IF NOT EXISTS (
     SELECT 1 FROM pg_catalog.pg_roles r
      WHERE r.rolname = current_user
        AND r.rolcanlogin AND r.rolcreaterole
        AND NOT r.rolsuper AND NOT r.rolcreatedb
        AND NOT r.rolbypassrls AND NOT r.rolreplication
  ) THEN
    RAISE EXCEPTION 'A3-T2c B installer permissions not restricted; STOP';
  END IF;
END;
$a3_t2c_b_scope$;

-- No password, secret, connection string or broad privilege is committed.
-- PostgreSQL instance authentication is an *independent* Approval B gate.
CREATE ROLE a3_t2c_writer LOGIN NOINHERIT NOSUPERUSER NOCREATEDB
  NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD NULL;
CREATE ROLE a3_t2c_reader LOGIN NOINHERIT NOSUPERUSER NOCREATEDB
  NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD NULL;

-- Dedicated database only; no grant on any existing project database.
-- The separate existing A3-T2c schema file applies its per-schema and
-- per-table INSERT / SELECT grants after these roles exist.
REVOKE CONNECT ON DATABASE a3_t2c_b_disposable FROM PUBLIC;
GRANT CONNECT ON DATABASE a3_t2c_b_disposable
  TO a3_t2c_writer, a3_t2c_reader;

-- Verify roles carry zero membership and no right to switch into owner,
-- including PG16-specific membership options. Recheck again independently
-- under actual credentials in the future approved experiment.
DO $a3_t2c_b_roles$
BEGIN
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
END;
$a3_t2c_b_roles$;

COMMIT;

-- This is NOT a provisioned database or a proof of successful role setup.
-- An independently authorized B operator must check catalog/actual sessions,
-- preserve unknown ACK as HOLD, and later delete ONLY the isolated cluster.
-- NO DROP ROLE, DROP DATABASE, ALTER SYSTEM, trust authentication, or retry.
