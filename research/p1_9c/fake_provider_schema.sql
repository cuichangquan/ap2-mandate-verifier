-- P1-9c research-only MOCK provider ledger: no network, no payment rails.
-- Physically in isolated ap2_research for reproducibility; NOT an actual provider.
CREATE TABLE IF NOT EXISTS p19c_fake_provider_effects (
  idempotency_key text PRIMARY KEY,
  operation_id text NOT NULL UNIQUE,
  effect_id text NOT NULL UNIQUE,
  attempts integer NOT NULL DEFAULT 1 CHECK (attempts >= 1),
  status text NOT NULL CHECK (status = 'SUCCEEDED')
);
