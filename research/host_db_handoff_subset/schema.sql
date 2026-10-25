-- NOT_RUN: new dedicated research DB only; existing schema means STOP.
BEGIN;
CREATE SCHEMA hdb;
REVOKE ALL ON SCHEMA hdb FROM PUBLIC;
CREATE TABLE hdb.policy (
  case_id text PRIMARY KEY,
  generation integer NOT NULL CHECK (generation > 0),
  high_water integer NOT NULL CHECK (high_water > 0),
  available boolean NOT NULL,
  test_now bigint NOT NULL,
  facts jsonb NOT NULL
);
CREATE TABLE hdb.orders (
  case_id text PRIMARY KEY REFERENCES hdb.policy(case_id),
  binding jsonb NOT NULL,
  version text NOT NULL,
  state text NOT NULL CHECK (state IN ('OPEN','RESERVED'))
);
CREATE TABLE hdb.challenges (
  case_id text PRIMARY KEY REFERENCES hdb.orders(case_id),
  facts jsonb NOT NULL,
  state text NOT NULL CHECK (state IN ('ISSUED','CONSUMED'))
);
CREATE TABLE hdb.operations (
  case_id text PRIMARY KEY REFERENCES hdb.challenges(case_id),
  operation_id text NOT NULL UNIQUE,
  CHECK (operation_id = 'synthetic-' || case_id)
);
COMMIT;
