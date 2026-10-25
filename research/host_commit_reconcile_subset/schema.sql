-- NOT_RUN: new dedicated research DB only; existing schema means STOP.
BEGIN;
CREATE SCHEMA hcr;
REVOKE ALL ON SCHEMA hcr FROM PUBLIC;
CREATE TABLE hcr.policy (
  case_id text PRIMARY KEY,
  generation integer NOT NULL CHECK (generation > 0),
  high_water integer NOT NULL CHECK (high_water > 0),
  available boolean NOT NULL,
  test_now bigint NOT NULL,
  facts jsonb NOT NULL
);
CREATE TABLE hcr.orders (
  case_id text PRIMARY KEY REFERENCES hcr.policy(case_id),
  binding jsonb NOT NULL,
  version text NOT NULL,
  state text NOT NULL CHECK (state IN ('OPEN','RESERVED'))
);
CREATE TABLE hcr.challenges (
  case_id text PRIMARY KEY REFERENCES hcr.orders(case_id),
  facts jsonb NOT NULL,
  state text NOT NULL CHECK (state IN ('ISSUED','CONSUMED'))
);
CREATE TABLE hcr.requests (
  operation_id text PRIMARY KEY,
  case_id text NOT NULL UNIQUE REFERENCES hcr.challenges(case_id),
  tenant_id text NOT NULL,
  principal_id text NOT NULL,
  descriptor jsonb NOT NULL,
  request_digest text NOT NULL CHECK (length(request_digest)=64),
  generation integer NOT NULL CHECK (generation IN (1,2)),
  state text NOT NULL CHECK (state IN ('REGISTERED','DONE')),
  CHECK (operation_id='synthetic-' || case_id)
);
CREATE TABLE hcr.operations (
  operation_id text PRIMARY KEY REFERENCES hcr.requests(operation_id),
  request_digest text NOT NULL CHECK (length(request_digest)=64)
);
COMMIT;
