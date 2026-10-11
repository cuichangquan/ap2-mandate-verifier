-- P1-10a: strictly research-only, same-DB Host policy snapshot and its lock.
-- NOT an external revocation provider or production permission source.
CREATE TABLE IF NOT EXISTS p110_checkout_controls (
  tenant_id text NOT NULL,
  checkout_id text NOT NULL,
  checkout_fingerprint text NOT NULL,
  state text NOT NULL CHECK (state IN ('ACTIVE', 'CANCELLED')),
  buyer_allowed boolean NOT NULL,
  PRIMARY KEY (tenant_id, checkout_id),
  FOREIGN KEY (tenant_id, checkout_id)
    REFERENCES p19a_checkouts(tenant_id, checkout_id)
);
