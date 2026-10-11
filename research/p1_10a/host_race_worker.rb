# frozen_string_literal: true

# P1-10a / HR10 research-only worker: shared-DB checkout/Buyer-state concurrency.
# No AP2 signature claim, no provider, dispatch, payment, network or Receipt.
require "pg"
require "json"
require "securerandom"

class PolicyStop < StandardError; end

STDOUT.sync = true
tenant, checkout_id, challenge_id, action, pause, expected_version, expected_fingerprint = ARGV
abort "usage: host_race_worker.rb TENANT CHECKOUT CHALLENGE ACTION PAUSE VERSION FINGERPRINT" unless
  [tenant, checkout_id, challenge_id, expected_fingerprint].all? { |s| s && /\A[a-z0-9_-]{1,80}\z/.match?(s) } &&
  %w[authorize cancel block edit].include?(action) &&
  %w[hold normal].include?(pause) && expected_version == "1" &&
  ENV["P110_RESEARCH_ONLY"] == "enabled"

db = PG.connect(ENV.fetch("P19A_DATABASE_URL"))
begin
  abort "refusing_non_research_database" unless
    db.exec("SELECT current_database()").first.values.first == "ap2_research"
  db.exec("BEGIN")
  db.exec("SET LOCAL lock_timeout = '9s'")
  db.exec("SET LOCAL statement_timeout = '11s'")
  db.exec("SET TRANSACTION ISOLATION LEVEL READ COMMITTED")

  puts "TRY:#{db.backend_pid}" if pause == "normal"
  # All supported mutation paths must acquire both locks in this exact order.
  checkout = db.exec_params(<<~SQL, [tenant, checkout_id]).first
    SELECT version,status FROM p19a_checkouts
     WHERE tenant_id=$1 AND checkout_id=$2 FOR UPDATE
  SQL
  controls = db.exec_params(<<~SQL, [tenant, checkout_id]).first
    SELECT state,buyer_allowed,checkout_fingerprint
    FROM p110_checkout_controls
    WHERE tenant_id=$1 AND checkout_id=$2 FOR UPDATE
  SQL
  raise PolicyStop, "host_context_missing" unless checkout && controls

  if pause == "hold"
    puts "LOCKED:#{db.backend_pid}"
    raise PolicyStop, "barrier_not_released" unless STDIN.gets&.strip == "GO"
  end

  if action == "authorize"
    # Provenance of expected values is test-only coordinator / seeded Host state.
    # A successfully verified token from the past is NOT a live Host policy.
    raise PolicyStop, "checkout_unavailable" unless checkout.fetch("status") == "OPEN"
    raise PolicyStop, "checkout_cancelled" unless controls.fetch("state") == "ACTIVE"
    raise PolicyStop, "buyer_blocked" unless controls.fetch("buyer_allowed") == "t"
    raise PolicyStop, "checkout_version_mismatch" unless
      checkout.fetch("version").to_i == Integer(expected_version)
    raise PolicyStop, "checkout_fingerprint_mismatch" unless
      controls.fetch("checkout_fingerprint") == expected_fingerprint

    nonce = db.exec_params(<<~SQL, [tenant, checkout_id, challenge_id, expected_version])
      UPDATE p19a_challenges
      SET state='CONSUMED'
      WHERE tenant_id=$1 AND checkout_id=$2 AND challenge_id=$3
        AND checkout_version=$4::integer
        AND state='ISSUED' AND expires_at > clock_timestamp()
      RETURNING challenge_id
    SQL
    raise PolicyStop, "nonce_cas_zero" unless nonce.ntuples == 1

    checkout_changed = db.exec_params(<<~SQL, [tenant, checkout_id, expected_version])
      UPDATE p19a_checkouts SET status='RESERVED'
      WHERE tenant_id=$1 AND checkout_id=$2
        AND version=$3::integer AND status='OPEN'
      RETURNING checkout_id
    SQL
    raise PolicyStop, "checkout_cas_zero" unless checkout_changed.ntuples == 1

    operation_id = SecureRandom.hex(16)
    idempotency_key = "offline-#{tenant}-#{checkout_id}"
    db.exec_params(<<~SQL, [operation_id, tenant, checkout_id, challenge_id, idempotency_key])
      INSERT INTO p19a_operations
        (operation_id, tenant_id, checkout_id, challenge_id, idempotency_key)
      VALUES ($1,$2,$3,$4,$5)
    SQL
    db.exec_params(
      "INSERT INTO p19a_outbox (operation_id,status) VALUES ($1,'PENDING')",
      [operation_id]
    )
    db.exec("COMMIT")
    puts "RESULT:#{JSON.generate(outcome: 'COMMITTED', action: action, operation_id: operation_id)}"
  else
    # Later cancellation/update must not falsely claim it prevented an
    # already committed order. Existing operation must remain visible.
    raise PolicyStop, "too_late_checkout_reserved" unless checkout.fetch("status") == "OPEN"
    raise PolicyStop, "not_active" unless controls.fetch("state") == "ACTIVE" &&
      controls.fetch("buyer_allowed") == "t"

    case action
    when "cancel"
      db.exec_params(
        "UPDATE p110_checkout_controls SET state='CANCELLED' WHERE tenant_id=$1 AND checkout_id=$2",
        [tenant, checkout_id]
      )
    when "block"
      db.exec_params(
        "UPDATE p110_checkout_controls SET buyer_allowed=false WHERE tenant_id=$1 AND checkout_id=$2",
        [tenant, checkout_id]
      )
    when "edit"
      db.exec_params(
        "UPDATE p19a_checkouts SET version=version+1 WHERE tenant_id=$1 AND checkout_id=$2",
        [tenant, checkout_id]
      )
      db.exec_params(<<~SQL, [tenant, checkout_id])
        UPDATE p110_checkout_controls SET checkout_fingerprint='fingerprint_v2'
         WHERE tenant_id=$1 AND checkout_id=$2
      SQL
    end
    db.exec("COMMIT")
    puts "RESULT:#{JSON.generate(outcome: 'MUTATION_COMMITTED', action: action)}"
  end
rescue PolicyStop => e
  db.exec("ROLLBACK") rescue nil
  puts "RESULT:#{JSON.generate(outcome: 'STOP', action: action, reason: e.message)}"
rescue StandardError => e
  db.exec("ROLLBACK") rescue nil
  warn "HR10_WORKER_ERROR:#{e.class}" # no SQL, JWT, credentials or private key
  puts "RESULT:#{JSON.generate(outcome: 'ERROR', action: action, type: e.class.name)}"
  exit 2
ensure
  db.close unless db.finished?
end
