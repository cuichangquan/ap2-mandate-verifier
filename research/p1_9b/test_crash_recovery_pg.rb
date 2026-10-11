# frozen_string_literal: true

# P1-9b: HR04/HR05 only. Actual SIGKILL of independent Ruby worker processes.
# Separate PostgreSQL sessions prove rollback or durable post-COMMIT recovery.
require "minitest/autorun"
require "pg"
require "json"
require "rbconfig"

P19B_EVIDENCE = []
Minitest.after_run do
  path = ENV["P19B_REPORT"]
  if path
    File.write(path, JSON.pretty_generate(
      executed_cases: P19B_EVIDENCE,
      scope: "Research-only PostgreSQL process crashes, no external dispatch",
      all_other_host_cases: "NOT RUN in P1-9b"
    ))
  end
end

class HostCrashRecoveryResearchTest < Minitest::Test
  WORKER = File.expand_path("../p1_9a/worker.rb", __dir__)
  RECOVERY = File.join(__dir__, "recovery_worker.rb")
  TIMEOUT = 7

  def setup
    @db = PG.connect(ENV.fetch("P19A_DATABASE_URL"))
    # Fail before any DDL/TRUNCATE in the wrong database.
    assert_equal "ap2_research", @db.exec("SELECT current_database() AS db").first.fetch("db")
    assert_match(/\A16\./, @db.exec("SHOW server_version").first.fetch("server_version"))
    @db.exec(File.read(File.expand_path("../p1_9a/schema.sql", __dir__)))
    @db.exec("TRUNCATE p19a_outbox, p19a_operations, p19a_challenges, p19a_checkouts")
    @children = []
  end

  def teardown
    @children&.each do |child|
      child[:stdin].close unless child[:stdin].closed?
      child[:stdout].close unless child[:stdout].closed?
      next if child[:reaped]
      Process.kill("KILL", child[:pid]) rescue nil
      Process.waitpid(child[:pid]) rescue nil
    end
    @db&.close
  end

  def seed(id)
    tenant = "tenant_#{id.downcase}"
    checkout = "checkout_#{id.downcase}"
    challenge = "challenge_#{id.downcase}_1"
    @db.exec_params(
      "INSERT INTO p19a_checkouts (tenant_id,checkout_id,version,status) VALUES ($1,$2,1,'OPEN')",
      [tenant, checkout]
    )
    @db.exec_params(<<~SQL, [challenge, tenant, checkout, "digest_#{id}"])
      INSERT INTO p19a_challenges
        (challenge_id,tenant_id,checkout_id,checkout_version,nonce_digest,expires_at,state)
      VALUES ($1,$2,$3,1,$4,now() + interval '15 minutes','ISSUED')
    SQL
    [tenant, checkout, challenge]
  end

  def spawn_child(script, *args, crash_hooks: false)
    from_parent, child_stdin = IO.pipe
    child_stdout, to_parent = IO.pipe
    env = { "P19B_CRASH_HOOKS" => crash_hooks ? "enabled" : nil }
    pid = Process.spawn(env, RbConfig.ruby, script, *args,
                        in: from_parent, out: to_parent, err: $stderr, close_others: true)
    from_parent.close
    to_parent.close
    child = { pid: pid, stdin: child_stdin, stdout: child_stdout, reaped: false }
    @children << child
    child
  end

  def receive(child, prefix)
    readable = IO.select([child.fetch(:stdout)], nil, nil, TIMEOUT)
    assert readable, "child failed to reach #{prefix} barrier"
    line = child.fetch(:stdout).gets&.strip
    assert line&.start_with?(prefix), "expected #{prefix}; got #{line.inspect}"
    line.delete_prefix(prefix)
  end

  def finish(child)
    result = JSON.parse(receive(child, "RESULT:"))
    _pid, status = Process.waitpid2(child.fetch(:pid))
    child[:reaped] = true
    assert status.success?, "child unexpectedly exited: #{status.exitstatus}"
    result
  end

  def kill_at_barrier(child)
    sent = Process.kill("KILL", child.fetch(:pid))
    assert_equal 1, sent, "worker already exited before actual crash injection"
    _pid, status = Process.waitpid2(child.fetch(:pid))
    child[:reaped] = true
    assert status.signaled?, "worker exited normally instead of being killed"
    assert_equal Signal.list.fetch("KILL"), status.termsig
  end

  def wait_for_pg_disconnect(backend_pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT
    loop do
      count = @db.exec_params(
        "SELECT count(*) FROM pg_stat_activity WHERE pid = $1::integer",
        [backend_pid]
      ).first.fetch("count").to_i
      return if count.zero?
      flunk "worker's PostgreSQL connection did not disappear after SIGKILL" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.02
    end
  end

  def assert_pg_idle_state(backend_pid, expected)
    row = @db.exec_params(
      "SELECT state FROM pg_stat_activity WHERE pid = $1::integer",
      [backend_pid]
    ).first
    refute_nil row, "worker's PG backend disappeared before signal"
    assert_equal expected, row.fetch("state")
  end

  def snapshot(tenant, checkout, challenge)
    @db.exec_params(<<~SQL, [tenant, checkout, challenge]).first
      SELECT
        (SELECT status FROM p19a_checkouts WHERE tenant_id=$1 AND checkout_id=$2) AS checkout_status,
        (SELECT state FROM p19a_challenges WHERE challenge_id=$3 AND tenant_id=$1 AND checkout_id=$2) AS nonce_state,
        (SELECT count(*) FROM p19a_operations WHERE tenant_id=$1 AND checkout_id=$2) AS operations,
        (SELECT count(*) FROM p19a_outbox o JOIN p19a_operations p USING(operation_id)
         WHERE p.tenant_id=$1 AND p.checkout_id=$2) AS outbox_count,
        (SELECT operation_id FROM p19a_operations WHERE tenant_id=$1 AND checkout_id=$2) AS operation_id,
        (SELECT idempotency_key FROM p19a_operations WHERE tenant_id=$1 AND checkout_id=$2) AS idempotency_key
    SQL
  end

  def assert_uncommitted(tenant, checkout, challenge)
    row = snapshot(tenant, checkout, challenge)
    assert_equal "OPEN", row.fetch("checkout_status")
    assert_equal "ISSUED", row.fetch("nonce_state")
    assert_equal 0, row.fetch("operations").to_i
    assert_equal 0, row.fetch("outbox_count").to_i
    assert_nil row.fetch("operation_id")
  end

  def assert_committed(tenant, checkout, challenge)
    row = snapshot(tenant, checkout, challenge)
    assert_equal "RESERVED", row.fetch("checkout_status")
    assert_equal "CONSUMED", row.fetch("nonce_state")
    assert_equal 1, row.fetch("operations").to_i
    assert_equal 1, row.fetch("outbox_count").to_i
    refute_nil row.fetch("operation_id")
    assert_equal "offline-#{tenant}-#{checkout}", row.fetch("idempotency_key")
    row
  end

  def run_worker(tenant, checkout, challenge)
    child = spawn_child(WORKER, tenant, checkout, challenge, "normal")
    Integer(receive(child, "TRY:"))
    finish(child)
  end

  def recover(tenant, checkout, challenge)
    child = spawn_child(RECOVERY, tenant, checkout, challenge)
    finish(child)
  end

  def test_hr04_kill_uncommitted_process_rolls_back_every_write
    tenant, checkout, challenge = seed("HR04")
    child = spawn_child(WORKER, tenant, checkout, challenge, "before_commit", crash_hooks: true)
    backend_pid = Integer(receive(child, "BEFORE_COMMIT:"))

    # The worker has made all 4 writes but has not sent COMMIT.
    assert_pg_idle_state(backend_pid, "idle in transaction")
    assert_uncommitted(tenant, checkout, challenge) # separate connection sees none

    kill_at_barrier(child) # real OS SIGKILL, not a simulated Ruby exception
    wait_for_pg_disconnect(backend_pid)
    assert_uncommitted(tenant, checkout, challenge)
    absent = recover(tenant, checkout, challenge)
    assert_equal "STOP", absent.fetch("outcome") # no phantom committed operation

    # Retry is a NEW full trusted-context check, not reuse of a prior ALLOW.
    attempted = run_worker(tenant, checkout, challenge)
    assert_equal "COMMITTED", attempted.fetch("outcome")
    assert_committed(tenant, checkout, challenge)
    P19B_EVIDENCE << { id: "HR04", result: "PASS", actual_sigkill: true,
                       pg_session_closed: true, pre_commit_rollback: true,
                       recovery_before_retry: "STOP", retry_after_fresh_check: "COMMITTED" }
  end

  def test_hr05_kill_after_acknowledged_commit_recovers_original_operation
    tenant, checkout, challenge = seed("HR05")
    child = spawn_child(WORKER, tenant, checkout, challenge, "after_commit", crash_hooks: true)
    backend_pid = Integer(receive(child, "AFTER_COMMIT:"))

    # Message emitted only AFTER db.exec("COMMIT") returned successfully.
    assert_pg_idle_state(backend_pid, "idle")
    original = assert_committed(tenant, checkout, challenge) # committed before kill
    kill_at_barrier(child)
    wait_for_pg_disconnect(backend_pid)
    assert_equal original, assert_committed(tenant, checkout, challenge)

    restored = recover(tenant, checkout, challenge) # separate OS process, read-only
    assert_equal "PENDING", restored.fetch("outcome")
    assert_equal "PENDING", restored.fetch("outbox_status")
    assert_equal original.fetch("operation_id"), restored.fetch("operation_id")
    assert_equal original.fetch("idempotency_key"), restored.fetch("idempotency_key")
    again = recover(tenant, checkout, challenge)
    assert_equal restored, again

    replay = run_worker(tenant, checkout, challenge)
    assert_equal "STOP", replay.fetch("outcome")
    assert_equal "checkout_unavailable", replay.fetch("reason")
    assert_equal original, assert_committed(tenant, checkout, challenge)
    P19B_EVIDENCE << { id: "HR05", result: "PASS", actual_sigkill: true,
                       pg_session_closed: true, commit_ack_observed: true,
                       stable_operation_recovered: true, stable_idempotency_key: true,
                       no_second_operation: true, recovery_state: "PENDING" }
  end
end
