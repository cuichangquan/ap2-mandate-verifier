# frozen_string_literal: true

# P1-9a/P1-9b/P1-9c: intentionally isolated research-only transaction worker.
# NO AP2 verifier/API, networking, payment, or real buyer data.
require "pg"
require "json"
require "securerandom"

class HostStop < StandardError; end

STDOUT.sync = true
tenant, checkout_id, challenge_id, mode = ARGV
allowed_modes = %w[hold normal]
allowed_modes.concat(%w[before_commit after_commit]) if ENV["P19B_CRASH_HOOKS"] == "enabled"
allowed_modes << "commit_unobserved" if ENV["P19C_FAULT_HOOKS"] == "enabled"
abort "usage: worker.rb TENANT CHECKOUT_ID CHALLENGE_ID allowed_mode" unless
  [tenant, checkout_id, challenge_id].all? { |v| v && /\A[a-z0-9_-]{1,60}\z/.match?(v) } &&
  allowed_modes.include?(mode)

db = PG.connect(ENV.fetch("P19A_DATABASE_URL"))
# Crash hooks must NEVER operate against an ordinary Host/business database.
if %w[before_commit after_commit commit_unobserved].include?(mode) &&
   db.exec("SELECT current_database() AS db").first.fetch("db") != "ap2_research"
  abort "crash_hook_refuses_non_research_database"
end
begin
  # Coordinator must observe *actual PG lock contention*, not merely a delay.
  puts "TRY:#{db.backend_pid}" if mode == "normal"
  db.exec("BEGIN")
  db.exec("SET LOCAL lock_timeout = '7s'")
  db.exec("SET LOCAL statement_timeout = '10s'")
  db.exec("SET TRANSACTION ISOLATION LEVEL READ COMMITTED")

  checkout = db.exec_params(
    "SELECT version, status FROM p19a_checkouts WHERE tenant_id = $1 AND checkout_id = $2 FOR UPDATE",
    [tenant, checkout_id]
  ).first

  if mode == "hold"
    puts "LOCKED:#{db.backend_pid}"
    raise HostStop, "barrier_not_released" unless STDIN.gets&.strip == "GO"
  end

  raise HostStop, "checkout_unavailable" unless checkout && checkout.fetch("status") == "OPEN"

  # Deliberately exercise UPDATE ... RETURNING 0-row CAS in HR03.
  claimed = db.exec_params(<<~SQL, [tenant, checkout_id, challenge_id, checkout.fetch("version")])
    UPDATE p19a_challenges SET state = 'CONSUMED'
    WHERE tenant_id = $1 AND checkout_id = $2 AND challenge_id = $3
      AND checkout_version = $4::integer
      AND state = 'ISSUED' AND expires_at > clock_timestamp()
    RETURNING challenge_id
  SQL
  raise HostStop, "nonce_cas_zero" unless claimed.ntuples == 1

  changed = db.exec_params(<<~SQL, [tenant, checkout_id, checkout.fetch("version")])
    UPDATE p19a_checkouts SET status = 'RESERVED'
    WHERE tenant_id = $1 AND checkout_id = $2
      AND version = $3::integer AND status = 'OPEN'
    RETURNING checkout_id
  SQL
  raise HostStop, "checkout_cas_zero" unless changed.ntuples == 1

  operation_id = SecureRandom.hex(16)
  # Stable, Host-side operation identity is deliberately tied to one-time Checkout.
  idem_key = "offline-#{tenant}-#{checkout_id}"
  db.exec_params(<<~SQL, [operation_id, tenant, checkout_id, challenge_id, idem_key])
    INSERT INTO p19a_operations
      (operation_id, tenant_id, checkout_id, challenge_id, idempotency_key)
    VALUES ($1, $2, $3, $4, $5)
  SQL
  db.exec_params(
    "INSERT INTO p19a_outbox (operation_id, status) VALUES ($1, 'PENDING')",
    [operation_id]
  )
  if mode == "before_commit"
    # The coordinator must SIGKILL this OS process while all four writes are
    # still UNCOMMITTED. EOF/GO cannot convert the test into a successful commit.
    puts "BEFORE_COMMIT:#{db.backend_pid}"
    STDIN.gets
    raise HostStop, "crash_hook_not_killed"
  end

  if mode == "commit_unobserved"
    # Client submits COMMIT asynchronously; it MUST NOT read libpq's result.
    # Coordinator will SIGKILL while the outcome is unknown to the caller.
    # Independent PG observation determines the server's actual final state.
    submitted = db.send_query("COMMIT")
    raise HostStop, "commit_submission_failed" unless submitted
    puts "COMMIT_SENT_NO_ACK:#{db.backend_pid}"
    STDIN.gets
    raise HostStop, "uncertain_commit_hook_not_killed"
  end

  db.exec("COMMIT")
  if mode == "after_commit"
    # PostgreSQL has ACKed COMMIT. Do not send/execute any external action.
    # The coordinator must SIGKILL this process before a normal return.
    puts "AFTER_COMMIT:#{db.backend_pid}"
    STDIN.gets
    raise HostStop, "crash_hook_not_killed"
  end
  puts "RESULT:#{JSON.generate(outcome: 'COMMITTED', nonce_rows: claimed.ntuples, operation_id: operation_id)}"
rescue HostStop => e
  db.exec("ROLLBACK")
  puts "RESULT:#{JSON.generate(outcome: 'STOP', reason: e.message)}"
rescue PG::UniqueViolation
  db.exec("ROLLBACK")
  puts "RESULT:#{JSON.generate(outcome: 'STOP', reason: 'unique_conflict')}"
rescue StandardError => e
  begin
    db.exec("ROLLBACK")
  rescue PG::Error
    # Keep unknown DB outcomes an ERROR, not an ALLOW or a spurious PASS.
  end
  warn "WORKER_ERROR:#{e.class}" # no raw SQL/JWT/credentials
  puts "RESULT:#{JSON.generate(outcome: 'ERROR', type: e.class.name)}"
  exit 2
ensure
  db.close unless db.finished?
end
