# frozen_string_literal: true

# P1-10a: four controlled subscenarios for ONE Host canonical ID HR10.
# Uses two real OS processes and two PostgreSQL backend sessions in each race.
require "minitest/autorun"
require "pg"
require "json"
require "rbconfig"

P110_EVIDENCE = []
Minitest.after_run do
  if (path = ENV["P110_REPORT"])
    File.write(path, JSON.pretty_generate(
      canonical_case_ids: ["HR10"],
      subscenarios: P110_EVIDENCE,
      scope: "Only same-PostgreSQL checkout and Buyer policy rows",
      remaining_host_case_ids_not_run: 25
    ))
  end
end

class HostCheckoutRevocationRaceResearchTest < Minitest::Test
  WORKER = File.join(__dir__, "host_race_worker.rb")
  EVENT_TIMEOUT = 8
  LOCK_WAIT_TIMEOUT = 6

  def setup
    @db = PG.connect(ENV.fetch("P19A_DATABASE_URL"))
    assert_equal "ap2_research", @db.exec("SELECT current_database()").first.values.first
    assert_match(/\A16\./, @db.exec("SHOW server_version").first.values.first)
    @db.exec(File.read(File.expand_path("../p1_9a/schema.sql", __dir__)))
    @db.exec(File.read(File.join(__dir__, "schema.sql")))
    @db.exec(<<~SQL)
      TRUNCATE p110_checkout_controls, p19a_outbox, p19a_operations,
               p19a_challenges, p19a_checkouts
    SQL
    @children = []
  end

  def teardown
    @children&.each do |c|
      c[:stdin].close unless c[:stdin].closed?
      c[:stdout].close unless c[:stdout].closed?
      next if c[:reaped]
      Process.kill("KILL", c[:pid]) rescue nil
      Process.waitpid(c[:pid]) rescue nil
    end
    @db&.close
  end

  def seed(scenario)
    tenant = "tenant_#{scenario}"
    checkout = "checkout_#{scenario}"
    challenge = "challenge_#{scenario}"
    @db.exec_params(
      "INSERT INTO p19a_checkouts(tenant_id,checkout_id,version,status) VALUES ($1,$2,1,'OPEN')",
      [tenant, checkout]
    )
    @db.exec_params(<<~SQL, [challenge, tenant, checkout, "digest_#{scenario}"])
      INSERT INTO p19a_challenges(challenge_id,tenant_id,checkout_id,
        checkout_version,nonce_digest,expires_at,state)
      VALUES($1,$2,$3,1,$4,now()+interval '15 minutes','ISSUED')
    SQL
    @db.exec_params(<<~SQL, [tenant, checkout])
      INSERT INTO p110_checkout_controls
        (tenant_id,checkout_id,checkout_fingerprint,state,buyer_allowed)
      VALUES($1,$2,'fingerprint_v1','ACTIVE',true)
    SQL
    [tenant, checkout, challenge]
  end

  def start_worker(tenant, checkout, challenge, action, pause)
    input_read, input_write = IO.pipe
    output_read, output_write = IO.pipe
    pid = Process.spawn(
      { "P110_RESEARCH_ONLY" => "enabled" }, RbConfig.ruby,
      WORKER, tenant, checkout, challenge, action, pause, "1", "fingerprint_v1",
      in: input_read, out: output_write, err: $stderr, close_others: true
    )
    input_read.close
    output_write.close
    child = { pid: pid, stdin: input_write, stdout: output_read, reaped: false }
    @children << child
    child
  end

  def event(child, prefix)
    selected = IO.select([child.fetch(:stdout)], nil, nil, EVENT_TIMEOUT)
    assert selected, "missing #{prefix} barrier within #{EVENT_TIMEOUT}s"
    line = child.fetch(:stdout).gets&.strip
    assert line&.start_with?(prefix), "expected #{prefix}, got #{line.inspect}"
    line.delete_prefix(prefix)
  end

  def finish(child)
    result = JSON.parse(event(child, "RESULT:"))
    pid, status = Process.waitpid2(child.fetch(:pid))
    child[:reaped] = true
    assert_equal child.fetch(:pid), pid
    assert status.success?, "worker exited unexpectedly: #{status.exitstatus}"
    refute_equal "ERROR", result.fetch("outcome")
    result
  end

  def assert_actual_pg_lock_wait(blocker_pid, blocked_pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + LOCK_WAIT_TIMEOUT
    loop do
      row = @db.exec_params(<<~SQL, [blocked_pid, blocker_pid]).first
        SELECT wait_event_type, $2::integer = ANY(pg_blocking_pids(pid)) AS blocked
        FROM pg_stat_activity WHERE pid=$1::integer
      SQL
      return true if row && row.fetch("wait_event_type") == "Lock" && row.fetch("blocked") == "t"
      flunk "no actual PostgreSQL blocker/blocked relationship observed" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.025
    end
  end

  def race(scenario, first_action:, second_action:)
    tenant, checkout, challenge = seed(scenario)
    a = start_worker(tenant, checkout, challenge, first_action, "hold")
    a_pid = Integer(event(a, "LOCKED:"))
    b = start_worker(tenant, checkout, challenge, second_action, "normal")
    b_pid = Integer(event(b, "TRY:"))
    refute_equal a_pid, b_pid
    assert assert_actual_pg_lock_wait(a_pid, b_pid)
    a.fetch(:stdin).puts("GO")
    a.fetch(:stdin).flush
    [tenant, checkout, challenge, finish(a), finish(b)]
  end

  def snapshot(tenant, checkout, challenge)
    @db.exec_params(<<~SQL, [tenant, checkout, challenge]).first
      SELECT c.status AS checkout_status, c.version AS version,
             p.state AS policy_state,p.buyer_allowed AS buyer_allowed,
             p.checkout_fingerprint AS fingerprint,
             ch.state AS nonce_state,
        (SELECT count(*) FROM p19a_operations o
         WHERE o.tenant_id=$1 AND o.checkout_id=$2) AS operations,
        (SELECT count(*) FROM p19a_outbox x JOIN p19a_operations o USING(operation_id)
         WHERE o.tenant_id=$1 AND o.checkout_id=$2) AS outbox
      FROM p19a_checkouts c
      JOIN p110_checkout_controls p USING(tenant_id,checkout_id)
      JOIN p19a_challenges ch ON ch.tenant_id=c.tenant_id
        AND ch.checkout_id=c.checkout_id AND ch.challenge_id=$3
      WHERE c.tenant_id=$1 AND c.checkout_id=$2
    SQL
  end

  def assert_mutation_wins(action, scenario, expected_reason:, expected_version: 1,
                           expected_policy: "ACTIVE", expected_buyer: "t",
                           expected_fingerprint: "fingerprint_v1")
    tenant, checkout, challenge, mutated, denied =
      race(scenario, first_action: action, second_action: "authorize")
    assert_equal "MUTATION_COMMITTED", mutated.fetch("outcome")
    assert_equal action, mutated.fetch("action")
    assert_equal "STOP", denied.fetch("outcome")
    assert_equal expected_reason, denied.fetch("reason")
    state = snapshot(tenant, checkout, challenge)
    assert_equal "OPEN", state.fetch("checkout_status")
    assert_equal expected_version, state.fetch("version").to_i
    assert_equal expected_policy, state.fetch("policy_state")
    assert_equal expected_buyer, state.fetch("buyer_allowed")
    assert_equal expected_fingerprint, state.fetch("fingerprint")
    assert_equal "ISSUED", state.fetch("nonce_state")
    assert_equal 0, state.fetch("operations").to_i
    assert_equal 0, state.fetch("outbox").to_i
    P110_EVIDENCE << { id: "HR10", subcase: scenario, result: "PASS",
      postgres_lock_contention_observed: true, winner: "mutation",
      reason: expected_reason, committed_operations: 0,
      nonce_consumed: false, outbox_rows: 0 }
  end

  def test_hr10_cancel_commits_first_and_stale_authorization_stops
    assert_mutation_wins("cancel", "cancel_first", expected_reason: "checkout_cancelled",
                         expected_policy: "CANCELLED")
  end

  def test_hr10_buyer_block_commits_first_and_stale_authorization_stops
    assert_mutation_wins("block", "block_first", expected_reason: "buyer_blocked",
                         expected_buyer: "f")
  end

  def test_hr10_checkout_version_and_fingerprint_update_precedes_authorization
    assert_mutation_wins("edit", "edit_first", expected_reason: "checkout_version_mismatch",
                         expected_version: 2, expected_fingerprint: "fingerprint_v2")
  end

  def test_hr10_order_commits_first_and_late_cancellation_cannot_claim_success
    tenant, checkout, challenge, booked, too_late =
      race("authorize_first", first_action: "authorize", second_action: "cancel")
    assert_equal "COMMITTED", booked.fetch("outcome")
    assert_equal "authorize", booked.fetch("action")
    assert_equal "STOP", too_late.fetch("outcome")
    assert_equal "too_late_checkout_reserved", too_late.fetch("reason")
    state = snapshot(tenant, checkout, challenge)
    assert_equal "RESERVED", state.fetch("checkout_status")
    assert_equal "ACTIVE", state.fetch("policy_state")
    assert_equal "t", state.fetch("buyer_allowed")
    assert_equal "fingerprint_v1", state.fetch("fingerprint")
    assert_equal 1, state.fetch("version").to_i
    assert_equal "CONSUMED", state.fetch("nonce_state")
    assert_equal 1, state.fetch("operations").to_i
    assert_equal 1, state.fetch("outbox").to_i
    P110_EVIDENCE << { id: "HR10", subcase: "authorize_first", result: "PASS",
      postgres_lock_contention_observed: true, winner: "authorize",
      late_mutation_refused: true, committed_operations: 1,
      nonce_consumed: true, outbox_rows: 1 }
  end
end
