# frozen_string_literal: true

# P1-10g: two future-plan IDs only; actual separate Ruby OS processes,
# distinct PG16 server instances, no payment, no real Authority.
require "minitest/autorun"
require "pg"
require "json"
require "uri"
require "rbconfig"

P110G_EVIDENCE = []
Minitest.after_run do
  if (file = ENV["P110G_REPORT"])
    File.write(file, JSON.pretty_generate(
      scope: "E-R01/E-R02 synthetic local-only; not distributed HC06 proof",
      canonical_host_ids_newly_proven: 0,
      cases: P110G_EVIDENCE
    ))
  end
end

class IndependentAuthorityHostResearchTest < Minitest::Test
  WORKER = File.join(__dir__, "worker.rb")
  WAIT_SECONDS = 10

  def setup
    assert_equal "enabled", ENV.fetch("P110G_RESEARCH_ONLY")
    auth_url = ENV.fetch("P110G_AUTH_URL")
    host_url = ENV.fetch("P110G_HOST_URL")
    assert_equal "127.0.0.1", URI.parse(auth_url).host
    assert_equal "127.0.0.1", URI.parse(host_url).host
    assert_equal "/ap2g_authority", URI.parse(auth_url).path
    assert_equal "/ap2g_host", URI.parse(host_url).path
    refute_equal URI.parse(auth_url).port, URI.parse(host_url).port

    @auth = PG.connect(auth_url)
    @host = PG.connect(host_url)
    assert_equal "ap2g_authority", @auth.exec("SELECT current_database()").first.values.first
    assert_equal "ap2g_host", @host.exec("SELECT current_database()").first.values.first
    assert_match(/\A16\./, @auth.exec("SHOW server_version").first.values.first)
    assert_match(/\A16\./, @host.exec("SHOW server_version").first.values.first)

    # Each service MUST use an independent PG data directory/postmaster.
    @auth_system_id = @auth.exec("SELECT system_identifier::text AS sid FROM pg_control_system()").first.fetch("sid")
    @host_system_id = @host.exec("SELECT system_identifier::text AS sid FROM pg_control_system()").first.fetch("sid")
    refute_equal @auth_system_id, @host_system_id
    @auth.exec(File.read(File.join(__dir__, "authority_schema.sql")))
    @host.exec(File.read(File.join(__dir__, "host_schema.sql")))
    @auth.exec("TRUNCATE authority_events,authority_reservations RESTART IDENTITY")
    @host.exec("TRUNCATE host_outbox,host_operations,host_events,host_checkouts RESTART IDENTITY")
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
    @auth&.close
    @host&.close
  end

  def seed_host(scenario)
    @host.exec_params(<<~SQL, ["checkout_#{scenario}", "reservation_#{scenario}", "operation_#{scenario}"])
      INSERT INTO host_checkouts (
        checkout_id, tenant_id, reservation_id, operation_id,
        nonce_digest, checkout_version, epoch, status, nonce_state
      ) VALUES ($1,'synthetic_tenant',$2,$3,'synthetic-nonce-digest',1,1,'OPEN','ISSUED')
    SQL
  end

  def start_worker(role, action, scenario, mode = "normal")
    read_in, write_in = IO.pipe
    read_out, write_out = IO.pipe
    pid = Process.spawn(
      { "P110G_RESEARCH_ONLY" => "enabled" },
      RbConfig.ruby, WORKER, role, action, scenario, mode,
      in: read_in, out: write_out, err: $stderr, close_others: true
    )
    read_in.close
    write_out.close
    child = { pid: pid, stdin: write_in, stdout: read_out, reaped: false }
    @children << child
    child
  end

  def event(child, prefix)
    got = IO.select([child.fetch(:stdout)], nil, nil, WAIT_SECONDS)
    assert got, "no #{prefix} within #{WAIT_SECONDS} seconds"
    line = child.fetch(:stdout).gets&.strip
    assert line&.start_with?(prefix), "expected #{prefix}, got #{line.inspect}"
    line.delete_prefix(prefix)
  end

  def finish(child)
    outcome = JSON.parse(event(child, "RESULT:"))
    pid, status = Process.waitpid2(child.fetch(:pid))
    child[:reaped] = true
    assert_equal child.fetch(:pid), pid
    assert status.success?, "worker unexpected exit: #{status.exitstatus}"
    refute_equal "ERROR", outcome.fetch("state")
    outcome
  end

  def perform(role, action, scenario)
    finish(start_worker(role, action, scenario))
  end

  def host_snapshot(scenario)
    @host.exec_params(<<~SQL, ["checkout_#{scenario}"]).first
      SELECT c.status,c.nonce_state,
        (SELECT count(*) FROM host_operations o WHERE o.checkout_id=c.checkout_id) AS operations,
        (SELECT count(*) FROM host_outbox ob JOIN host_operations o USING(operation_id)
         WHERE o.checkout_id=c.checkout_id) AS outbox
      FROM host_checkouts c WHERE c.checkout_id=$1
    SQL
  end

  def authority_snapshot(scenario)
    @auth.exec_params(<<~SQL, ["reservation_#{scenario}"]).first
      SELECT state,revoke_requested,revoke_effective FROM authority_reservations
       WHERE reservation_id=$1
    SQL
  end

  def event_kinds(db, table)
    db.exec("SELECT kind FROM #{table} ORDER BY seq").map { |row| row.fetch("kind") }
  end

  def assert_host_status(scenario, status:, nonce:, operations:, outbox:)
    state = host_snapshot(scenario)
    assert_equal status, state.fetch("status")
    assert_equal nonce, state.fetch("nonce_state")
    assert_equal operations, Integer(state.fetch("operations"))
    assert_equal outbox, Integer(state.fetch("outbox"))
  end

  def test_er01_committed_host_order_precedes_effective_revocation
    scenario = "er01"
    seed_host(scenario)
    assert_equal "RESERVED", perform("authority", "reserve", scenario).fetch("state")
    pending = perform("authority", "request", scenario)
    assert_equal "ACCEPTED_PENDING", pending.fetch("state")
    assert_equal false, pending.fetch("effective")
    assert_equal "f", authority_snapshot(scenario).fetch("revoke_effective")

    assert_equal "COMMITTED", perform("host", "commit", scenario).fetch("state")
    # A separate Host connection observes its own durable C before
    # synthetic coordinator requests Authority finalize. Not a real 2PC.
    assert_host_status(scenario, status: "COMMITTED", nonce: "CONSUMED", operations: 1, outbox: 1)
    assert_equal ["C_DURABLE"], event_kinds(@host, "host_events")

    effective = perform("authority", "finalize_commit", scenario)
    assert_equal true, effective.fetch("effective")
    assert_equal "FINALIZED_COMMIT", effective.fetch("state")
    assert_equal "t", authority_snapshot(scenario).fetch("revoke_effective")
    assert_equal %w[P_DURABLE R_REQUEST_ACCEPTED R_EFFECTIVE_COMMIT],
                 event_kinds(@auth, "authority_events")
    assert_host_status(scenario, status: "COMMITTED", nonce: "CONSUMED", operations: 1, outbox: 1)

    P110G_EVIDENCE << {
      id: "E-R01", result: "PASS", separate_postgres_system_identifiers: true,
      r_request_only_pending: true, durable_host_commit_before_authority_finalize: true,
      effective_after_finalization: true, operation_count: 1, outbox_count: 1,
      limitations: "single synthetic coordinator; not actual cross-service atomicity"
    }
  end

  def test_er02_durable_abort_blocks_stale_worker_after_effective_revocation
    scenario = "er02"
    seed_host(scenario)
    assert_equal "RESERVED", perform("authority", "reserve", scenario).fetch("state")
    assert_equal "ACCEPTED_PENDING", perform("authority", "request", scenario).fetch("state")
    assert_equal "f", authority_snapshot(scenario).fetch("revoke_effective")

    # Worker has a pre-gate stale authorization notion, but no Host DB lock.
    stale = start_worker("host", "commit", scenario, "pause_before_gate")
    assert_equal stale.fetch(:pid), Integer(event(stale, "READY_BEFORE_GATE:"))

    abort_worker = start_worker("host", "abort", scenario, "kill_after_commit")
    assert_equal abort_worker.fetch(:pid), Integer(event(abort_worker, "ABORT_DURABLE_ACK_WITHHELD:"))
    Process.kill("KILL", abort_worker.fetch(:pid))
    _, status = Process.waitpid2(abort_worker.fetch(:pid))
    abort_worker[:reaped] = true
    assert status.signaled?, "must inject actual independent Host SIGKILL"
    assert_equal Signal.list.fetch("KILL"), status.termsig

    # A fresh Host DB session recovers the durable abort despite missing ACK.
    assert_host_status(scenario, status: "ABORTED", nonce: "ISSUED", operations: 0, outbox: 0)
    assert_equal ["ABORT_DURABLE"], event_kinds(@host, "host_events")
    response = perform("authority", "finalize_abort", scenario)
    assert_equal "FINALIZED_ABORT", response.fetch("state")
    assert_equal true, response.fetch("effective")
    assert_equal "t", authority_snapshot(scenario).fetch("revoke_effective")

    # Release stale worker only AFTER the Authority's R_effective durable ACK.
    stale.fetch(:stdin).puts("GO")
    stale.fetch(:stdin).flush
    stopped = finish(stale)
    assert_equal "STOP", stopped.fetch("state")
    assert_equal "abort_durable", stopped.fetch("reason")
    second_attempt = perform("host", "commit", scenario)
    assert_equal "STOP", second_attempt.fetch("state")
    assert_equal "abort_durable", second_attempt.fetch("reason")
    assert_host_status(scenario, status: "ABORTED", nonce: "ISSUED", operations: 0, outbox: 0)
    assert_equal ["ABORT_DURABLE"], event_kinds(@host, "host_events")
    assert_equal %w[P_DURABLE R_REQUEST_ACCEPTED R_EFFECTIVE_ABORT],
                 event_kinds(@auth, "authority_events")

    P110G_EVIDENCE << {
      id: "E-R02", result: "PASS", separate_postgres_system_identifiers: true,
      actual_independent_sigkill: true, durable_abort_recovered_without_ack: true,
      stale_worker_released_after_effective: true, stale_commit_stopped: true,
      retry_stopped: true, nonce_consumed: false, operation_count: 0, outbox_count: 0,
      limitations: "stale worker paused before Host DB txn; no in-flight DB commit race or real Authority"
    }
  end
end
