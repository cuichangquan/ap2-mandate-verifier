-- P1-10g: isolated fictitious Host PostgreSQL 16 instance ONLY.
CREATE TABLE IF NOT EXISTS host_checkouts (
  checkout_id text PRIMARY KEY,
  tenant_id text NOT NULL,
  reservation_id text NOT NULL UNIQUE,
  operation_id text NOT NULL UNIQUE,
  nonce_digest text NOT NULL,
  checkout_version integer NOT NULL CHECK(checkout_version=1),
  epoch integer NOT NULL CHECK(epoch=1),
  status text NOT NULL CHECK(status IN ('OPEN','COMMITTED','ABORTED')),
  nonce_state text NOT NULL CHECK(nonce_state IN ('ISSUED','CONSUMED'))
);
CREATE TABLE IF NOT EXISTS host_operations (
  operation_id text PRIMARY KEY,
  checkout_id text NOT NULL UNIQUE REFERENCES host_checkouts(checkout_id),
  idempotency_key text NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS host_outbox (
  operation_id text PRIMARY KEY REFERENCES host_operations(operation_id)
);
CREATE TABLE IF NOT EXISTS host_events (
  seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  reservation_id text NOT NULL,
  operation_id text NOT NULL,
  kind text NOT NULL CHECK(kind IN ('C_DURABLE','ABORT_DURABLE'))
);