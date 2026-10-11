# frozen_string_literal: true

# P1-10g: isolated, synthetic Authority/Host OS worker. NOT a production API.
# No checkout JWT, payment, provider, receipt, or shared process lock.
require "pg"
require "json"
require "uri"

class ResearchStop < StandardError; end
STDOUT.sync = true

role, action, scenario, mode = ARGV
mode ||= "normal"
abort "P110G_RESEARCH_ONLY is required" unless ENV["P110G_RESEARCH_ONLY"] == "enabled"
abort "unsupported scenario" unless %w[er01 er02].include?(scenario)
abort "unsupported mode" unless %w[normal pause_before_gate kill_after_commit].include?(mode)
allowed = {
  "authority" => %w[reserve request finalize_commit finalize_abort],
  "host" => %w[commit abort]
}
abort "unsupported role/action" unless allowed.fetch(role, []).include?(action)
abort "mode/action mismatch" unless mode == "normal" ||
  (role == "host" && action == "commit" && mode == "pause_before_gate") ||
  (role == "host" && action == "abort" && mode == "kill_after_commit")

url = ENV.fetch(role == "authority" ? "P110G_AUTH_URL" : "P110G_HOST_URL")
uri = URI.parse(url)
database = role == "authority" ? "ap2g_authority" : "ap2g_host"
abort "non-loopback research host" unless uri.host == "127.0.0.1" && uri.path == "/#{database}"
db = PG.connect(url)
begin
  actual_db = db.exec("SELECT current_database() AS name").first.fetch("name")
  pg_version = db.exec("SHOW server_version").first.fetch("server_version")
  abort "refusing non-PG16/non-isolated research database" unless
    actual_db == database && pg_version.start_with?("16.")

  checkout_id = "checkout_#{scenario}"
  reservation_id = "reservation_#{scenario}"
  operation_id = "operation_#{scenario}"
  outcome = nil
  db.exec("BEGIN")
  db.exec("SET LOCAL lock_timeout = '6s'")
  db.exec("SET LOCAL statement_timeout = '9s'")
  if role == "authority"
    case action
    when "reserve"
      db.exec_params(<<~SQL, [reservation_id, operation_id, checkout_id])
        INSERT INTO authority_reservations (
          reservation_id,operation_id,tenant_id,authority_id,subject_id,
          scope,checkout_id,epoch,state
        ) VALUES ($1,$2,'synthetic_tenant','synthetic_authority',
                  'synthetic_buyer','checkout-only',$3,1,'RESERVED')
      SQL
      db.exec_params("INSERT INTO authority_events(reservation_id,kind) VALUES ($1,'P_DURABLE')", [reservation_id])
      outcome = { state: "RESERVED", effective: false }
    when "request"
      row = db.exec_params(<<~SQL, [reservation_id]).first
        UPDATE authority_reservations
           SET revoke_requested=true
         WHERE reservation_id=$1 AND state='RESERVED' AND NOT revoke_effective
         RETURNING reservation_id
      SQL
      raise ResearchStop, "not_reservable" unless row
      db.exec_params("INSERT INTO authority_events(reservation_id,kind) VALUES ($1,'R_REQUEST_ACCEPTED')", [reservation_id])
      outcome = { state: "ACCEPTED_PENDING", effective: false }
    when "finalize_commit", "finalize_abort"
      state = action == "finalize_commit" ? "FINALIZED_COMMIT" : "FINALIZED_ABORT"
      event = action == "finalize_commit" ? "R_EFFECTIVE_COMMIT" : "R_EFFECTIVE_ABORT"
      # Synthetic coordinator supplied a Host durable-state observation.
      # Cross-service atomic evidence is NOT established by this RPC model.
      row = db.exec_params(<<~SQL, [state, reservation_id]).first
        UPDATE authority_reservations
           SET state=$1,revoke_effective=true
         WHERE reservation_id=$2 AND state='RESERVED'
           AND revoke_requested=true AND revoke_effective=false
         RETURNING reservation_id
      SQL
      raise ResearchStop, "not_ready_for_effective" unless row
      db.exec_params("INSERT INTO authority_events(reservation_id,kind) VALUES ($1,$2)", [reservation_id,event])
      outcome = { state: state, effective: true }
    end
  else
    if mode == "pause_before_gate"
      # Simulates a previously observed ALLOW outside the Host DB txn.
      # A resumed worker MUST re-check the durable DB gate.
      db.exec("ROLLBACK")
      puts "READY_BEFORE_GATE:#{Process.pid}"
      raise ResearchStop, "barrier_not_released" unless STDIN.gets&.strip == "GO"
      db.exec("BEGIN")
      db.exec("SET LOCAL lock_timeout = '6s'")
      db.exec("SET LOCAL statement_timeout = '9s'")
    end

    row = db.exec_params(<<~SQL, [checkout_id, reservation_id, operation_id]).first
      SELECT status,nonce_state,tenant_id,epoch,checkout_version
        FROM host_checkouts
       WHERE checkout_id=$1 AND reservation_id=$2 AND operation_id=$3
       FOR UPDATE
    SQL
    raise ResearchStop, "context_missing" unless row &&
      row.fetch("tenant_id") == "synthetic_tenant" &&
      row.fetch("epoch").to_i == 1 && row.fetch("checkout_version").to_i == 1
    raise ResearchStop, "abort_durable" if row.fetch("status") == "ABORTED"
    raise ResearchStop, "already_committed" if row.fetch("status") == "COMMITTED"
    raise ResearchStop, "invalid_nonce" unless row.fetch("nonce_state") == "ISSUED"

    if action == "commit"
      changed = db.exec_params(<<~SQL, [checkout_id]).cmd_tuples
        UPDATE host_checkouts SET status='COMMITTED',nonce_state='CONSUMED'
         WHERE checkout_id=$1 AND status='OPEN' AND nonce_state='ISSUED'
      SQL
      raise ResearchStop, "gate_cas_zero" unless changed == 1
      db.exec_params(<<~SQL, [operation_id, checkout_id])
        INSERT INTO host_operations(operation_id,checkout_id,idempotency_key)
          VALUES ($1,$2,'synthetic-stable-idempotency')
      SQL
      db.exec_params("INSERT INTO host_outbox(operation_id) VALUES($1)", [operation_id])
      db.exec_params(<<~SQL, [reservation_id,operation_id])
        INSERT INTO host_events(reservation_id,operation_id,kind)
        VALUES($1,$2,'C_DURABLE')
      SQL
      outcome = { state: "COMMITTED" }
    else
      changed = db.exec_params(<<~SQL, [checkout_id]).cmd_tuples
        UPDATE host_checkouts SET status='ABORTED'
         WHERE checkout_id=$1 AND status='OPEN' AND nonce_state='ISSUED'
      SQL
      raise ResearchStop, "abort_cas_zero" unless changed == 1
      db.exec_params(<<~SQL, [reservation_id,operation_id])
        INSERT INTO host_events(reservation_id,operation_id,kind)
        VALUES($1,$2,'ABORT_DURABLE')
      SQL
      outcome = { state: "ABORTED" }
    end
  end
  db.exec("COMMIT")

  if mode == "kill_after_commit"
    # A durable Host abort is real, but the caller never receives normal ACK.
    puts "ABORT_DURABLE_ACK_WITHHELD:#{Process.pid}"
    STDIN.gets
    raise ResearchStop, "crash_hook_was_not_killed"
  end
  puts "RESULT:#{JSON.generate(outcome)}"
rescue ResearchStop => e
  db.exec("ROLLBACK") rescue nil
  puts "RESULT:#{JSON.generate(state: 'STOP', reason: e.message)}"
rescue StandardError => e
  db.exec("ROLLBACK") rescue nil
  warn "P110G_WORKER_ERROR:#{e.class}" # no tokens, raw SQL, PII or credentials
  puts "RESULT:#{JSON.generate(state: 'ERROR', class: e.class.name)}"
  exit 2
ensure
  db.close unless db.finished?
end
