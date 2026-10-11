-- P1-10g: isolated fictitious Authority PostgreSQL 16 instance ONLY.
CREATE TABLE authority_reservations (
  reservation_id text PRIMARY KEY,
  operation_id text NOT NULL UNIQUE,
  tenant_id text NOT NULL,
  authority_id text NOT NULL,
  subject_id text NOT NULL,
  scope text NOT NULL,
  checkout_id text NOT NULL,
  epoch integer NOT NULL CHECK(epoch = 1),
  state text NOT NULL CHECK(state IN ('RESERVED','FINALIZED_COMMIT','FINALIZED_ABORT')),
  revoke_requested boolean NOT NULL DEFAULT false,
  revoke_effective boolean NOT NULL DEFAULT false
);
CREATE TABLE authority_events (
  seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  reservation_id text NOT NULL REFERENCES authority_reservations(reservation_id),
  kind text NOT NULL CHECK(kind IN ('P_DURABLE','R_REQUEST_ACCEPTED','R_EFFECTIVE_COMMIT','R_EFFECTIVE_ABORT'))
);