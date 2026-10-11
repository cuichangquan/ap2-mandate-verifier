# frozen_string_literal: true

# P1-9b research-only recovery: READ ONLY, no dispatch, payment or Receipt.
require "pg"
require "json"

tenant, checkout_id, challenge_id = ARGV
abort "usage: recovery_worker.rb TENANT CHECKOUT_ID CHALLENGE_ID" unless
  [tenant, checkout_id, challenge_id].all? { |v| v && /\A[a-z0-9_-]{1,60}\z/.match?(v) }

db = PG.connect(ENV.fetch("P19A_DATABASE_URL"))
begin
  abort "non_research_database" unless
    db.exec("SELECT current_database() AS db").first.fetch("db") == "ap2_research"

  db.exec("BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
  rows = db.exec_params(<<~SQL, [tenant, checkout_id, challenge_id])
    SELECT o.operation_id, o.idempotency_key, x.status AS outbox_status
    FROM p19a_operations o
    JOIN p19a_outbox x ON x.operation_id = o.operation_id
    JOIN p19a_checkouts c
      ON c.tenant_id = o.tenant_id AND c.checkout_id = o.checkout_id
    JOIN p19a_challenges ch
      ON ch.challenge_id = o.challenge_id AND ch.tenant_id = o.tenant_id
         AND ch.checkout_id = o.checkout_id
    WHERE o.tenant_id = $1 AND o.checkout_id = $2 AND o.challenge_id = $3
      AND c.status = 'RESERVED' AND ch.state = 'CONSUMED'
      AND ch.checkout_version = c.version AND x.status = 'PENDING'
  SQL
  result = if rows.ntuples == 1
             row = rows.first
             { outcome: "PENDING", operation_id: row.fetch("operation_id"),
               idempotency_key: row.fetch("idempotency_key"),
               outbox_status: row.fetch("outbox_status") }
           else
             { outcome: "STOP", reason: "durable_operation_unavailable" }
           end
  db.exec("COMMIT")
  puts "RESULT:#{JSON.generate(result)}"
rescue StandardError => e
  db.exec("ROLLBACK") rescue nil
  warn "RECOVERY_ERROR:#{e.class}" # never log SQL, credentials or buyer data
  puts "RESULT:#{JSON.generate(outcome: 'ERROR')}"
  exit 2
ensure
  db.close unless db.finished?
end
