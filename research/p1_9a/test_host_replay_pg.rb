# frozen_string_literal: true

# P1-9a: FOUR intentionally narrow Host atomicity experiments, NOT an AP2 test suite.
require "minitest/autorun"
require "pg"
require "json"
require "rbconfig"
require "securerandom"

EVIDENCE = []
Minitest.after_run do
  path = ENV["P19A_REPORT"]
  File.write(path, JSON.pretty_generate({ executed_cases: EVIDENCE, scope: "PG16 isolated DB only", other_host_cases: "NOT RUN" })) if path
end

class HostReplayPgResearchTest < Minitest::Test
  WORKER = File.join(__dir__, "worker.rb")
  READ_TIMEOUT = 9
  RACE_TIMEOUT = 6

  def setup
    @db = PG.connect(ENV.fetch("P19A_DATABASE_URL"))
    # An accidental invocation against any other DB must fail before DDL/TRUNCATE.
    assert_equal "ap2_research", @db.exec("SELECT current_database() AS db").first.fetch("db")
    assert_match(/\A16\./, @db.exec("SHOW server_version").first.fetch("server_version"))
    @db.exec(File.read(File.join(__dir__, "schema.sql")))
    @db.exec("TRUNCATE p19a_outbox, p19a_operations, p19a_challenges, p19a_checkouts")
  end

  def teardown
    @db&.close
  end

  def seed_checkout(case_id, nonce_count: 1, state: "ISSUED")
    tenant = "tenant_#{case_id.downcase}"
    checkout = "checkout_#{case_id.downcase}"
    @db.exec_params(
      "INSERT INTO p19a_checkouts (tenant_id, checkout_id, version, status) VALUES ($1,$2,1,'OPEN')",
      [tenant, checkout]
    )
    challenges = Array.new(nonce_count) do |i|
      id = "challenge_#{case_id.downcase}_#{i + 1}"
      @db.exec_params(<<~SQL, [id, tenant, checkout, "digest_#{case_id}_#{i}", state])
        INSERT INTO p19a_challenges
          (challenge_id, tenant_id, checkout_id, checkout_version, nonce_digest, expires_at, state)
        VALUES ($1,$2,$3,1,$4, now() + interval '15 minutes', $5)
      SQL
      id
    end
    [tenant, checkout, challenges]
  end

  def start_worker(tenant, checkout, challenge, mode)
    from_parent, to_child = IO.pipe
    from_child, to_parent = IO.pipe
    pid = Process.spawn(
      RbConfig.ruby, WORKER, tenant, checkout, challenge, mode,
      in: from_parent, out: to_parent, err: $stderr, close_others: true
    )
    from_parent.close
    to_parent.close
    { pid: pid, input: to_child, output: from_child, reaped: false }
  end

  def event(worker, prefix)
    readable = IO.select([worker.fetch(:output)], nil, nil, READ_TIMEOUT)
    assert readable, "worker event timeout (expected #{prefix})"
    line = worker.fetch(:output).gets&.strip
    assert line&.start_with?(prefix), "worker event mismatch (expected #{prefix}, got #{line.inspect})"
    line.delete_prefix(prefix)
  end

  def finish(worker)
    result = JSON.parse(event(worker, "RESULT:"))
    waited_pid, status = Process.waitpid2(worker.fetch(:pid))
    worker[:reaped] = true
    assert_equal worker.fetch(:pid), waited_pid
    assert status.success?, "worker unexpectedly exited: #{status.exitstatus}"
    assert_includes %w[COMMITTED STOP], result.fetch("outcome"), "unexpected worker outcome"
    result
  end

  def dispose(worker)
    return unless worker
    worker[:input].close unless worker[:input].closed?
    worker[:output].close unless worker[:output].closed?
    return if worker[:reaped]
    begin
      Process.kill("TERM", worker[:pid])
    rescue Errno::ESRCH
      # Already exited.
    end
    begin
      Process.waitpid(worker[:pid])
    rescue Errno::ECHILD
      # Already reaped.
    end
  end

  # Wait for concrete server evidence that B is blocked by A's row lock.
  # Merely starting two Ruby processes or sleeping does NOT establish a race.
  def await_pg_block(a_backend, b_backend)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + RACE_TIMEOUT
    loop do
      row = @db.exec_params(<<~SQL, [b_backend, a_backend]).first
        SELECT wait_event_type, ($2::integer = ANY(pg_blocking_pids(pid))) AS blocked
        FROM pg_stat_activity WHERE pid = $1::integer
      SQL
      return true if row && row["wait_event_type"] == "Lock" && row["blocked"] == "t"
      flunk "No observed PostgreSQL row-lock contention between independent worker sessions" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.025 # only bounded polling after reading the DB's real lock state
    end
  end

  def race(tenant, checkout, challenge_a, challenge_b)
    a = b = nil
    a = start_worker(tenant, checkout, challenge_a, "hold")
    a_pgpid = Integer(event(a, "LOCKED:"))
    b = start_worker(tenant, checkout, challenge_b, "normal")
    b_pgpid = Integer(event(b, "TRY:"))
    refute_equal a_pgpid, b_pgpid
    assert await_pg_block(a_pgpid, b_pgpid)
    a[:input].puts("GO")
    a[:input].flush
    [finish(a), finish(b)]
  ensure
    dispose(a)
    dispose(b)
  end

  def run_once(tenant, checkout, challenge)
    w = start_worker(tenant, checkout, challenge, "normal")
    Integer(event(w, "TRY:"))
    finish(w)
  ensure
    dispose(w)
  end

  def assert_one_operation(tenant, checkout, consumed:, issued:)
    rows = @db.exec_params(<<~SQL, [tenant, checkout]).first
      SELECT
        (SELECT count(*) FROM p19a_operations WHERE tenant_id=$1 AND checkout_id=$2) AS operation_count,
        (SELECT count(*) FROM p19a_outbox o JOIN p19a_operations p USING (operation_id)
         WHERE p.tenant_id=$1 AND p.checkout_id=$2) AS outbox_count,
        (SELECT count(*) FROM p19a_challenges
         WHERE tenant_id=$1 AND checkout_id=$2 AND state='CONSUMED') AS consumed_count,
        (SELECT count(*) FROM p19a_challenges
         WHERE tenant_id=$1 AND checkout_id=$2 AND state='ISSUED') AS issued_count,
        (SELECT status FROM p19a_checkouts WHERE tenant_id=$1 AND checkout_id=$2) AS checkout_status
    SQL
    assert_equal 1, rows.fetch("operation_count").to_i
    assert_equal 1, rows.fetch("outbox_count").to_i
    assert_equal consumed, rows.fetch("consumed_count").to_i
    assert_equal issued, rows.fetch("issued_count").to_i
    assert_equal "RESERVED", rows.fetch("checkout_status")
  end

  def assert_zero_operation(tenant, checkout)
    assert_equal 0, @db.exec_params(
      "SELECT count(*) FROM p19a_operations WHERE tenant_id=$1 AND checkout_id=$2", [tenant, checkout]
    ).first.fetch("count").to_i
    assert_equal 0, @db.exec("SELECT count(*) FROM p19a_outbox").first.fetch("count").to_i
    assert_equal "OPEN", @db.exec_params(
      "SELECT status FROM p19a_checkouts WHERE tenant_id=$1 AND checkout_id=$2", [tenant, checkout]
    ).first.fetch("status")
  end

  def test_hr01_same_nonce_two_real_workers
    tenant, checkout, (challenge) = seed_checkout("HR01")
    first, second = race(tenant, checkout, challenge, challenge)
    assert_equal "COMMITTED", first.fetch("outcome")
    assert_equal 1, first.fetch("nonce_rows")
    assert_equal "STOP", second.fetch("outcome")
    assert_equal "checkout_unavailable", second.fetch("reason")
    assert_one_operation(tenant, checkout, consumed: 1, issued: 0)
    EVIDENCE << { id: "HR01", result: "PASS", pg_lock_wait_observed: true, commits: 1, operations: 1, outbox: 1 }
  end

  def test_hr02_different_nonces_same_checkout
    tenant, checkout, challenges = seed_checkout("HR02", nonce_count: 2)
    first, second = race(tenant, checkout, *challenges)
    assert_equal "COMMITTED", first.fetch("outcome")
    assert_equal "STOP", second.fetch("outcome")
    assert_equal "checkout_unavailable", second.fetch("reason")
    assert_one_operation(tenant, checkout, consumed: 1, issued: 1)

    # Independent DB backstop: a second operation with another challenge is
    # rejected by UNIQUE(tenant_id, checkout_id), not only Ruby status checks.
    @db.exec("BEGIN")
    assert_raises(PG::UniqueViolation) do
      @db.exec_params(<<~SQL, ["extra_#{SecureRandom.hex(8)}", tenant, checkout, challenges.fetch(1)])
        INSERT INTO p19a_operations
          (operation_id, tenant_id, checkout_id, challenge_id, idempotency_key)
        VALUES ($1,$2,$3,$4,'offline-extra-hr02')
      SQL
    end
    @db.exec("ROLLBACK")
    assert_one_operation(tenant, checkout, consumed: 1, issued: 1)
    EVIDENCE << { id: "HR02", result: "PASS", pg_lock_wait_observed: true, unique_conflict_observed: true, commits: 1, operations: 1 }
  ensure
    @db.exec("ROLLBACK") if @db && @db.transaction_status != PG::PQTRANS_IDLE
  end

  def test_hr03_zero_row_nonce_cas_must_stop
    tenant, checkout, (challenge) = seed_checkout("HR03", state: "CONSUMED")
    result = run_once(tenant, checkout, challenge)
    assert_equal "STOP", result.fetch("outcome")
    assert_equal "nonce_cas_zero", result.fetch("reason")
    assert_zero_operation(tenant, checkout)
    EVIDENCE << { id: "HR03", result: "PASS", cas_zero_observed: true, commits: 0, operations: 0 }
  end

  def test_hr08_replay_same_presentation_after_commit
    tenant, checkout, (challenge) = seed_checkout("HR08")
    first = run_once(tenant, checkout, challenge)
    second = run_once(tenant, checkout, challenge)
    assert_equal "COMMITTED", first.fetch("outcome")
    assert_equal "STOP", second.fetch("outcome")
    assert_equal "checkout_unavailable", second.fetch("reason")
    assert_one_operation(tenant, checkout, consumed: 1, issued: 0)
    EVIDENCE << { id: "HR08", result: "PASS", replay_rejected: true, commits: 1, operations: 1 }
  end
end
