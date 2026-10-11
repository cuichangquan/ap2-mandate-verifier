# frozen_string_literal: true

# HR07 mock payment Provider: isolated PostgreSQL effect ledger, NO network or money.
# Response loss is injected AFTER the mock's effect has durably committed.
require "pg"
require "json"

class ProviderStop < StandardError; end
STDOUT.sync = true

tenant, checkout, challenge, supplied_key, mode = ARGV
abort "usage: fake_provider.rb TENANT CHECKOUT CHALLENGE KEY normal|lose_response" unless
  [tenant, checkout, challenge, supplied_key].all? { |v| v && /\A[a-z0-9_-]{1,100}\z/.match?(v) } &&
  %w[normal lose_response].include?(mode)
abort "fault_hook_not_enabled" if mode == "lose_response" && ENV["P19C_FAULT_HOOKS"] != "enabled"

db = PG.connect(ENV.fetch("P19A_DATABASE_URL"))
begin
  abort "non_research_database" unless
    db.exec("SELECT current_database() AS db").first.fetch("db") == "ap2_research"

  db.exec("BEGIN")
  db.exec("SET LOCAL lock_timeout='3s'")
  # This mock accepts only the durable Host operation and its exact stable key.
  row = db.exec_params(<<~SQL, [tenant, checkout, challenge]).first
    SELECT o.operation_id, o.idempotency_key
    FROM p19a_operations o
    JOIN p19a_outbox x ON x.operation_id=o.operation_id AND x.status='PENDING'
    JOIN p19a_checkouts c ON c.tenant_id=o.tenant_id
     AND c.checkout_id=o.checkout_id AND c.status='RESERVED'
    JOIN p19a_challenges ch ON ch.challenge_id=o.challenge_id
     AND ch.tenant_id=o.tenant_id AND ch.checkout_id=o.checkout_id
     AND ch.state='CONSUMED'
    WHERE o.tenant_id=$1 AND o.checkout_id=$2 AND o.challenge_id=$3
  SQL
  raise ProviderStop, "durable_operation_missing" unless row
  raise ProviderStop, "idempotency_key_mismatch" unless row.fetch("idempotency_key") == supplied_key

  operation_id = row.fetch("operation_id")
  effect_id = "fake_effect_#{operation_id}"
  result = db.exec_params(<<~SQL, [supplied_key, operation_id, effect_id])
    INSERT INTO p19c_fake_provider_effects
      (idempotency_key, operation_id, effect_id, attempts, status)
    VALUES ($1,$2,$3,1,'SUCCEEDED')
    ON CONFLICT (idempotency_key)
      DO UPDATE SET attempts=p19c_fake_provider_effects.attempts+1
      WHERE p19c_fake_provider_effects.operation_id=EXCLUDED.operation_id
    RETURNING idempotency_key,operation_id,effect_id,attempts,status
  SQL
  raise ProviderStop, "provider_key_collision" unless result.ntuples == 1
  value = result.first
  db.exec("COMMIT")

  if mode == "lose_response"
    # The mock side effect is *already* committed. The Host never receives a
    # success response. Coordinator simulates a transport timeout by killing
    # this process rather than treating the missing response as permission.
    puts "EFFECT_COMMITTED_NO_RESPONSE:#{db.backend_pid}"
    STDIN.gets
    abort "response_loss_hook_not_killed"
  end

  puts "RESULT:#{JSON.generate(outcome: 'SUCCEEDED',
    operation_id: value.fetch('operation_id'), idempotency_key: value.fetch('idempotency_key'),
    effect_id: value.fetch('effect_id'), attempts: value.fetch('attempts').to_i)}"
rescue ProviderStop => e
  db.exec("ROLLBACK") rescue nil
  puts "RESULT:#{JSON.generate(outcome: 'STOP', reason: e.message)}"
rescue PG::UniqueViolation
  db.exec("ROLLBACK") rescue nil
  puts "RESULT:#{JSON.generate(outcome: 'STOP', reason: 'provider_unique_conflict')}"
rescue StandardError => e
  db.exec("ROLLBACK") rescue nil
  warn "MOCK_PROVIDER_ERROR:#{e.class}"
  puts "RESULT:#{JSON.generate(outcome: 'ERROR')}"
  exit 2
ensure
  db.close unless db.finished?
end
