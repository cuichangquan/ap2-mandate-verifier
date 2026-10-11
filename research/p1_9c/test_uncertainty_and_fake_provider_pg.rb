# frozen_string_literal: true

# P1-9c: HR06 and HR07 ONLY. Real PG16, synthetic Host rows, NO money/network.
require "minitest/autorun"
require "pg"
require "json"
require "rbconfig"

P19C_EVIDENCE = []
Minitest.after_run do
  if (path = ENV["P19C_REPORT"])
    File.write(path, JSON.pretty_generate(
      executed_cases: P19C_EVIDENCE, untested_cases: "26 other Host cases NOT RUN",
      scope: "ACK uncertainty + isolated mock provider only; no real HTTP/payment"
    ))
  end
end

class UnknownCommitAndMockProviderResearchTest < Minitest::Test
  WORKER = File.expand_path("../p1_9a/worker.rb", __dir__)
  RECOVERY = File.expand_path("../p1_9b/recovery_worker.rb", __dir__)
  TIMEOUT_WORKER = File.join(__dir__, "timeout_worker.rb")
  MOCK_PROVIDER = File.join(__dir__, "fake_provider.rb")
  DEADLINE = 8

  def setup
    @db = PG.connect(ENV.fetch("P19A_DATABASE_URL"))
    assert_equal "ap2_research", @db.exec("SELECT current_database()").first.values.first
    assert_match(/\A16\./, @db.exec("SHOW server_version").first.values.first)
    @db.exec(File.read(File.expand_path("../p1_9a/schema.sql", __dir__)))
    @db.exec(File.read(File.join(__dir__, "fake_provider_schema.sql")))
    @db.exec("TRUNCATE p19c_fake_provider_effects, p19a_outbox, p19a_operations, p19a_challenges, p19a_checkouts")
    @children = []
  end

  def teardown
    @db.exec("ROLLBACK") if @db && @db.transaction_status != PG::PQTRANS_IDLE
    @children&.each do |c|
      c[:stdin].close unless c[:stdin].closed?
      c[:stdout].close unless c[:stdout].closed?
      next if c[:reaped]
      Process.kill("KILL", c[:pid]) rescue nil
      Process.waitpid(c[:pid]) rescue nil
    end
    @db&.close
  end

  def seed(id)
    tenant, checkout, challenge = "tenant_#{id.downcase}", "checkout_#{id.downcase}", "challenge_#{id.downcase}"
    @db.exec_params(
      "INSERT INTO p19a_checkouts (tenant_id, checkout_id, version, status) VALUES ($1,$2,1,'OPEN')",
      [tenant, checkout]
    )
    @db.exec_params(<<~SQL, [challenge, tenant, checkout, "digest_#{id}"])
      INSERT INTO p19a_challenges
        (challenge_id, tenant_id, checkout_id, checkout_version, nonce_digest, expires_at, state)
      VALUES ($1,$2,$3,1,$4,now()+interval '15 minutes','ISSUED')
    SQL
    [tenant, checkout, challenge]
  end

  def start(script, *args, hook: false)
    input_read, input_write = IO.pipe
    output_read, output_write = IO.pipe
    env = { "P19C_FAULT_HOOKS" => hook ? "enabled" : nil }
    pid = Process.spawn(env, RbConfig.ruby, script, *args,
                        in: input_read, out: output_write, err: $stderr, close_others: true)
    input_read.close
    output_write.close
    child = { pid: pid, stdin: input_write, stdout: output_read, reaped: false }
    @children << child
    child
  end

  def event(child, prefix)
    selected = IO.select([child.fetch(:stdout)], nil, nil, DEADLINE)
    assert selected, "no #{prefix} event within bounded deadline"
    line = child.fetch(:stdout).gets&.strip
    assert line&.start_with?(prefix), "expected #{prefix} got #{line.inspect}"
    line.delete_prefix(prefix)
  end

  def finish(child)
    result = JSON.parse(event(child, "RESULT:"))
    pid, status = Process.waitpid2(child.fetch(:pid))
    child[:reaped] = true
    assert_equal child.fetch(:pid), pid
    assert status.success?, "unexpected child exit: #{status.exitstatus}"
    result
  end

  def kill_actual(child)
    assert_equal 1, Process.kill("KILL", child.fetch(:pid))
    pid, status = Process.waitpid2(child.fetch(:pid))
    child[:reaped] = true
    assert_equal child.fetch(:pid), pid
    assert status.signaled?
    assert_equal Signal.list.fetch("KILL"), status.termsig
  end

  def await_session_closed(pg_pid)
    poll do
      @db.exec_params("SELECT count(*) FROM pg_stat_activity WHERE pid=$1::integer", [pg_pid])
        .first.fetch("count").to_i.zero?
    end
    true
  end

  def poll
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DEADLINE
    loop do
      return true if yield
      flunk "timed out waiting for independently observable PostgreSQL state" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.015
    end
  end

  def persisted(tenant, checkout, challenge)
    @db.exec_params(<<~SQL, [tenant, checkout, challenge]).first
      SELECT
        (SELECT status FROM p19a_checkouts WHERE tenant_id=$1 AND checkout_id=$2) AS checkout_state,
        (SELECT state FROM p19a_challenges WHERE challenge_id=$3) AS nonce_state,
        (SELECT count(*) FROM p19a_operations WHERE tenant_id=$1 AND checkout_id=$2) AS operation_count,
        (SELECT count(*) FROM p19a_outbox x JOIN p19a_operations o USING(operation_id)
          WHERE o.tenant_id=$1 AND o.checkout_id=$2) AS outbox_count,
        (SELECT operation_id FROM p19a_operations WHERE tenant_id=$1 AND checkout_id=$2) AS operation_id,
        (SELECT idempotency_key FROM p19a_operations WHERE tenant_id=$1 AND checkout_id=$2) AS key
    SQL
  end

  def assert_committed(tenant, checkout, challenge)
    state = persisted(tenant, checkout, challenge)
    assert_equal "RESERVED", state.fetch("checkout_state")
    assert_equal "CONSUMED", state.fetch("nonce_state")
    assert_equal 1, state.fetch("operation_count").to_i
    assert_equal 1, state.fetch("outbox_count").to_i
    refute_nil state.fetch("operation_id")
    refute_nil state.fetch("key")
    state
  end

  def recover(tenant, checkout, challenge)
    finish(start(RECOVERY, tenant, checkout, challenge))
  end

  def normal_host_attempt(tenant, checkout, challenge)
    child = start(WORKER, tenant, checkout, challenge, "normal")
    Integer(event(child, "TRY:"))
    finish(child)
  end

  def test_hr06_unknown_client_commit_ack_and_actual_db_lock_timeout
    tenant, checkout, challenge = seed("HR06")
    worker = start(WORKER, tenant, checkout, challenge, "commit_unobserved", hook: true)
    pg_pid = Integer(event(worker, "COMMIT_SENT_NO_ACK:"))
    # The application does not consume the COMMIT result (no get_result call).
    # Inspect actual DB outcome from a separate PG connection.
    assert poll { persisted(tenant, checkout, challenge).fetch("operation_count").to_i == 1 }
    committed = assert_committed(tenant, checkout, challenge)
    kill_actual(worker)
    assert await_session_closed(pg_pid)
    assert_equal committed, assert_committed(tenant, checkout, challenge)

    outcome = recover(tenant, checkout, challenge)
    assert_equal "PENDING", outcome.fetch("outcome")
    assert_equal committed.fetch("operation_id"), outcome.fetch("operation_id")
    assert_equal committed.fetch("key"), outcome.fetch("idempotency_key")
    assert_equal outcome, recover(tenant, checkout, challenge)

    replay = normal_host_attempt(tenant, checkout, challenge)
    assert_equal "STOP", replay.fetch("outcome")
    assert_equal "checkout_unavailable", replay.fetch("reason")
    assert_equal committed, assert_committed(tenant, checkout, challenge)

    # Separate lock_timeout branch: a blocked Host must NOT invent a new op.
    other_tenant, other_checkout, other_challenge = seed("HR06_timeout")
    @db.exec("BEGIN")
    @db.exec_params(
      "SELECT status FROM p19a_checkouts WHERE tenant_id=$1 AND checkout_id=$2 FOR UPDATE",
      [other_tenant, other_checkout]
    )
    timeout_child = start(TIMEOUT_WORKER, other_tenant, other_checkout)
    timeout_pid = Integer(event(timeout_child, "TRY:"))
    assert poll {
      @db.exec_params(
        "SELECT wait_event_type, pg_blocking_pids(pid) AS blockers FROM pg_stat_activity WHERE pid=$1::integer",
        [timeout_pid]
      ).first&.fetch("wait_event_type", nil) == "Lock"
    }
    timeout_result = finish(timeout_child)
    assert_equal "PENDING", timeout_result.fetch("outcome")
    assert_equal "55P03", timeout_result.fetch("sqlstate")
    @db.exec("ROLLBACK")
    blank = persisted(other_tenant, other_checkout, other_challenge)
    assert_equal "OPEN", blank.fetch("checkout_state")
    assert_equal "ISSUED", blank.fetch("nonce_state")
    assert_equal 0, blank.fetch("operation_count").to_i
    assert_equal 0, blank.fetch("outbox_count").to_i
    assert_equal "STOP", recover(other_tenant, other_checkout, other_challenge).fetch("outcome")

    P19C_EVIDENCE << { id: "HR06", result: "PASS", async_commit_sent_without_result: true,
      actual_sigkill: true, committed_operation_recovered: true, key_reused: true,
      replay_stopped: true, real_pg_timeout_sqlstate: "55P03", blocked_wait_observed: true,
      no_new_operation_during_timeout: true, fake_provider_effects: 0 }
  end

  def fake_request(tenant, checkout, challenge, key, mode = "normal", hook: false)
    child = start(MOCK_PROVIDER, tenant, checkout, challenge, key, mode, hook: hook)
    finish(child)
  end

  def ledger(key)
    @db.exec_params(
      "SELECT operation_id,effect_id,attempts,status FROM p19c_fake_provider_effects WHERE idempotency_key=$1",
      [key]
    ).first
  end

  def test_hr07_lost_fake_provider_response_stable_key_one_logical_effect
    tenant, checkout, challenge = seed("HR07")
    created = normal_host_attempt(tenant, checkout, challenge)
    assert_equal "COMMITTED", created.fetch("outcome")
    durable = assert_committed(tenant, checkout, challenge)
    assert_equal created.fetch("operation_id"), durable.fetch("operation_id")
    pending = recover(tenant, checkout, challenge)
    assert_equal "PENDING", pending.fetch("outcome")
    key = pending.fetch("idempotency_key")
    assert_equal durable.fetch("key"), key

    # The fake Provider commits an effect, but the Host receives NO response.
    provider = start(MOCK_PROVIDER, tenant, checkout, challenge, key, "lose_response", hook: true)
    provider_pid = Integer(event(provider, "EFFECT_COMMITTED_NO_RESPONSE:"))
    first = ledger(key)
    refute_nil first
    assert_equal durable.fetch("operation_id"), first.fetch("operation_id")
    assert_equal "SUCCEEDED", first.fetch("status")
    assert_equal 1, first.fetch("attempts").to_i
    kill_actual(provider)
    assert await_session_closed(provider_pid)
    assert_equal first, ledger(key)

    # Missing response is NOT a success Receipt; Host keeps PENDING.
    assert_equal pending, recover(tenant, checkout, challenge)
    replay = normal_host_attempt(tenant, checkout, challenge)
    assert_equal "STOP", replay.fetch("outcome")
    assert_equal durable, assert_committed(tenant, checkout, challenge)

    # Retry with exact same stable key: two dispatch attempts, one effect.
    retried = fake_request(tenant, checkout, challenge, key)
    assert_equal "SUCCEEDED", retried.fetch("outcome")
    assert_equal durable.fetch("operation_id"), retried.fetch("operation_id")
    assert_equal key, retried.fetch("idempotency_key")
    assert_equal first.fetch("effect_id"), retried.fetch("effect_id")
    assert_equal 2, retried.fetch("attempts")
    assert_equal 2, ledger(key).fetch("attempts").to_i
    assert_equal 1, @db.exec("SELECT count(*) FROM p19c_fake_provider_effects").first.fetch("count").to_i
    assert_equal durable, assert_committed(tenant, checkout, challenge)

    # A *different* key cannot silently create a second logical effect.
    tampered = fake_request(tenant, checkout, challenge, "fake_wrong_key")
    assert_equal "STOP", tampered.fetch("outcome")
    assert_equal "idempotency_key_mismatch", tampered.fetch("reason")
    assert_equal 2, ledger(key).fetch("attempts").to_i
    assert_equal 1, @db.exec("SELECT count(*) FROM p19c_fake_provider_effects").first.fetch("count").to_i

    P19C_EVIDENCE << { id: "HR07", result: "PASS", response_lost_after_durable_effect: true,
      actual_sigkill: true, replay_stopped: true, stable_operation_and_key: true,
      mock_provider_requests: 2, mock_logical_effects: 1, mismatched_key_stopped: true,
      receipt_not_claimed: true }
  end
end
