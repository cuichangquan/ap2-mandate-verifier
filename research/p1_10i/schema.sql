-- P1-10i: Authority-only synthetic receipt for the research guard.
-- Applied ONLY to the independent ap2g_authority PostgreSQL 16 service.
CREATE TABLE IF NOT EXISTS authority_proof_receipts (
  reservation_id text PRIMARY KEY REFERENCES authority_reservations(reservation_id),
  decision_id text NOT NULL UNIQUE,
  proof_digest text NOT NULL,
  decision text NOT NULL CHECK(decision IN ('ABORTED','COMMITTED'))
);