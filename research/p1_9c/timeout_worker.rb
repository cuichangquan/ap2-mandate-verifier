# frozen_string_literal: true

# HR06 real PostgreSQL lock timeout, no order creation, no provider dispatch.
require "pg"
require "json"

tenant, checkout = ARGV
abort "usage: timeout_worker.rb TENANT CHECKOUT" unless
  [tenant, checkout].all? { |v| v && /\A[a-z0-9_-]{1,60}\z/.match?(v) }

db = PG.connect(ENV.fetch("P19A_DATABASE_URL"))
begin
  abort "non_research_database" unless
    db.exec("SELECT current_database() AS db").first.fetch("db") == "ap2_research"
  db.exec("BEGIN")
  db.exec("SET LOCAL lock_timeout = '1400ms'")
  db.exec("SET LOCAL statement_timeout = '3000ms'")
  puts "TRY:#{db.backend_pid}"
  STDOUT.flush
  db.exec_params(
    "SELECT status FROM p19a_checkouts WHERE tenant_id=$1 AND checkout_id=$2 FOR UPDATE",
    [tenant, checkout]
  )
  db.exec("ROLLBACK")
  puts "RESULT:#{JSON.generate(outcome: 'ERROR', reason: 'lock_timeout_not_triggered')}"
  exit 2
rescue PG::LockNotAvailable => e
  db.exec("ROLLBACK") rescue nil
  abort "unexpected_sqlstate" unless e.result&.error_field(PG::Result::PG_DIAG_SQLSTATE) == "55P03"
  puts "RESULT:#{JSON.generate(outcome: 'PENDING', sqlstate: '55P03', reason: 'pg_lock_timeout')}"
rescue StandardError => e
  db.exec("ROLLBACK") rescue nil
  warn "TIMEOUT_WORKER_ERROR:#{e.class}"
  puts "RESULT:#{JSON.generate(outcome: 'ERROR')}"
  exit 2
ensure
  db.close unless db.finished?
end
