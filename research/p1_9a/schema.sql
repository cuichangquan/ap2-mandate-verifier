-- P1-9a temporary research schema only; never run on a production database.
CREATE TABLE IF NOT EXISTS p19a_checkouts (
  tenant_id text NOT NULL,
  checkout_id text NOT NULL,
  version integer NOT NULL DEFAULT 1,
  status text NOT NULL CHECK (status IN ('OPEN', 'RESERVED')),
  PRIMARY KEY (tenant_id, checkout_id)
);

CREATE TABLE IF NOT EXISTS p19a_challenges (
  challenge_id text PRIMARY KEY,
  tenant_id text NOT NULL,
  checkout_id text NOT NULL,
  checkout_version integer NOT NULL,
  nonce_digest text NOT NULL,
  expires_at timestamptz NOT NULL,
  state text NOT NULL CHECK (state IN ('ISSUED', 'CONSUMED')),
  UNIQUE (tenant_id, nonce_digest),
  UNIQUE (tenant_id, checkout_id, challenge_id),
  FOREIGN KEY (tenant_id, checkout_id)
    REFERENCES p19a_checkouts (tenant_id, checkout_id)
);

CREATE TABLE IF NOT EXISTS p19a_operations (
  operation_id text PRIMARY KEY,
  tenant_id text NOT NULL,
  checkout_id text NOT NULL,
  challenge_id text NOT NULL,
  idempotency_key text NOT NULL UNIQUE,
  UNIQUE (tenant_id, checkout_id),
  UNIQUE (challenge_id),
  FOREIGN KEY (tenant_id, checkout_id)
    REFERENCES p19a_checkouts (tenant_id, checkout_id),
  FOREIGN KEY (tenant_id, checkout_id, challenge_id)
    REFERENCES p19a_challenges (tenant_id, checkout_id, challenge_id)
);

CREATE TABLE IF NOT EXISTS p19a_outbox (
  operation_id text PRIMARY KEY REFERENCES p19a_operations (operation_id),
  status text NOT NULL CHECK (status = 'PENDING')
);
