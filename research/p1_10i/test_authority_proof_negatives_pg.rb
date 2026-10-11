# frozen_string_literal: true

# P1-10i: exactly six DESIGN negative IDs H01..H06; not canonical Host IDs.
# Independent PG16 Authority + Host instances, synthetic values only.
require "minitest/autorun"
require "pg"
require "json"
require "uri"
require "open3"
require "rbconfig"

P110I_EVIDENCE = []
Minitest.after_run do
  if (path = ENV["P110I_REPORT"])
    File.write(path, JSON.pretty_generate({
      scope: "H01-H06 research-only negatives / not distributed safety proof",
      canonical_host_ids_newly_proven: 0,
      cases: P110I_EVIDENCE
    }))
  end
end

class AuthorityEvidenceNegativeResearchTest < Minitest::Test
  GUARD = File.join(__dir__, "authority_guard.rb")
  OLD_WORKER = File.expand_path("../p1_10g/worker.rb", __dir__)
  AUTH_SCHEMA = File.expand_path("../p1_10g/authority_schema.sql", __dir__)
  HOST_SCHEMA = File.expand_path("../p1_10g/host_schema.sql", __dir__)

  def setup
    assert_equal "enabled", ENV.fetch("P110I_RESEARCH_ONLY")
    @auth_url = ENV.fetch("P110G_AUTH_URL")
    @host_url = ENV.fetch("P110G_HOST_URL")
    [[@auth_url, "ap2g_authority"], [@host_url, "ap2g_host"]].each do |url, name|
      uri = URI.parse(url)
      assert_equal "127.0.0.1", uri.host
      assert_equal "/#{name}", uri.path
    end
    refute_equal URI.parse(@auth_url).port, URI.parse(@host_url).port
    @auth = PG.connect(@auth_url)
    @host = PG.connect(@host_url)
    [[@auth, "ap2g_authority"], [@host, "ap2g_host"]].each do |db, name|
      assert_equal name, db.exec("SELECT current_database()").first.values.first
      assert_match(/\A16\./, db.exec("SHOW server_version").first.values.first)
    end
    @auth_system_id = @auth.exec("SELECT system_identifier::text FROM pg_control_system()").first.values.first
    @host_system_id = @host.exec("SELECT system_identifier::text FROM pg_control_system()").first.values.first
    refute_equal @auth_system_id, @host_system_id

    @auth.exec(File.read(AUTH_SCHEMA))
    @host.exec(File.read(HOST_SCHEMA))
    @auth.exec(File.read(File.join(__dir__, "schema.sql")))
    reset_tables
  end

  def teardown
    @auth&.close
    @host&.close
  end

  def reset_tables
    @auth.exec("TRUNCATE authority_proof_receipts,authority_events,authority_reservations RESTART IDENTITY")
    @host.exec("TRUNCATE host_outbox,host_operations,host_events,host_checkouts RESTART IDENTITY")
  end

  def seed(scenario)
    @auth.exec_params(<<~SQL, ["reservation_#{scenario}", "operation_#{scenario}", "checkout_#{scenario}"])
      INSERT INTO authority_reservations (
        reservation_id,operation_id,tenant_id,authority_id,subject_id,scope,
        checkout_id,epoch,state,revoke_requested,revoke_effective
      ) VALUES($1,$2,'synthetic_tenant','synthetic_authority','synthetic_buyer',
        'checkout-only',$3,1,'RESERVED',true,false)
    SQL
    @auth.exec_params("INSERT INTO authority_events(reservation_id,kind) VALUES($1,'P_DURABLE'),($1,'R_REQUEST_ACCEPTED')", ["reservation_#{scenario}"])
    @host.exec_params(<<~SQL, ["checkout_#{scenario}", "reservation_#{scenario}", "operation_#{scenario}"])
      INSERT INTO host_checkouts(
        checkout_id,tenant_id,reservation_id,operation_id,nonce_digest,
        checkout_version,epoch,status,nonce_state
      ) VALUES($1,'synthetic_tenant',$2,$3,'synthetic-nonce-digest',
        1,1,'OPEN','ISSUED')
    SQL
  end

  def claimed(scenario, overrides = {})
    {
      "host_service_id" => "trusted_synthetic_host",
      "audience" => "synthetic_authority",
      "authority_id" => "synthetic_authority",
      "tenant_id" => "synthetic_tenant",
      "scope" => "checkout-only",
      "reservation_id" => "reservation_#{scenario}",
      "operation_id" => "operation_#{scenario}",
      "checkout_id" => "checkout_#{scenario}",
      "epoch" => 1,
      "nonce_digest" => "synthetic-nonce-digest",
      "decision_id" => "decision_#{scenario}_1",
      "decision" => "ABORTED"
    }.merge(overrides)
  end

  def child_env
    { "P110I_RESEARCH_ONLY" => "enabled", "P110G_RESEARCH_ONLY" => "enabled" }
  end

  def invoke(path, args, json_input: nil)
    stdout, stderr, status = Open3.capture3(child_env, RbConfig.ruby, path, *args,
                                           stdin_data: json_input ? JSON.generate(json_input) : "")
    assert status.success?, "research child exited unexpectedly: #{status.exitstatus}; #{stderr.lines.last&.slice(0,100)}"
    assert_equal "", stderr, "unexpected worker stderr"
    line = stdout.lines.last&.strip || "{}"
    line = line.delete_prefix("RESULT:") if path == OLD_WORKER
    result = JSON.parse(line)
    refute_equal "ERROR", result["outcome"] || result["state"]
    result
  end

  def guard(scenario, proof = claimed(scenario))
    invoke(GUARD, [scenario], json_input: proof)
  end

  def old_worker(role, action, scenario)
    invoke(OLD_WORKER, [role, action, scenario, "normal"])
  end

  def host_terminal_abort(scenario)
    checkout = "checkout_#{scenario}"
    reservation = "reservation_#{scenario}"
    operation = "operation_#{scenario}"
    @host.exec("BEGIN")
    begin
      row = @host.exec_params("SELECT status,nonce_state FROM host_checkouts WHERE checkout_id=$1 FOR UPDATE", [checkout]).first
      assert_equal "OPEN", row.fetch("status")
      assert_equal "ISSUED", row.fetch("nonce_state")
      changed = @host.exec_params(<<~SQL, [checkout])
        UPDATE host_checkouts SET status='ABORTED'
        WHERE checkout_id=$1 AND status='OPEN' AND nonce_state='ISSUED' RETURNING checkout_id
      SQL
      assert_equal 1, changed.ntuples
      @host.exec_params(<<~SQL, [reservation,operation])
        INSERT INTO host_events(reservation_id,operation_id,kind)
        VALUES ($1,$2,'ABORT_DURABLE')
      SQL
      @host.exec("COMMIT")
    rescue StandardError
      @host.exec("ROLLBACK") rescue nil
      raise
    end
  end

  def effective?(scenario)
    @auth.exec_params("SELECT revoke_effective FROM authority_reservations WHERE reservation_id=$1",
                      ["reservation_#{scenario}"]).first.fetch("revoke_effective") == "t"
  end

  def count_rows(db, table)
    Integer(db.exec("SELECT count(*) AS n FROM #{table}").first.fetch("n"))
  end

  def assert_still_pending(scenario)
    refute effective?(scenario)
    assert_equal "RESERVED", @auth.exec_params(
      "SELECT state FROM authority_reservations WHERE reservation_id=$1",
      ["reservation_#{scenario}"]
    ).first.fetch("state")
    assert_equal 0, count_rows(@auth, "authority_proof_receipts")
    assert_equal 0, @auth.exec_params(
      "SELECT count(*) AS n FROM authority_events WHERE reservation_id=$1 AND kind LIKE 'R_EFFECTIVE%'",
      ["reservation_#{scenario}"]
    ).first.fetch("n").to_i
  end

  def evidence(id, classification, **details)
    P110I_EVIDENCE << {
      id: id, classification: classification,
      independent_pg_system_identifiers: true,
      source: "two isolated local PG16 instances, synthetic claim only",
      **details
    }
  end

  def test_h01_legacy_coordinator_false_abort_is_a_counterexample_guard_stops
    # Reproduce actual P1-10g blind finalize path, then demonstrate C can still
    # commit AFTER claimed effective. This is NOT a safety PASS.
    seed("er02")
    legacy = old_worker("authority", "finalize_abort", "er02")
    assert_equal true, legacy.fetch("effective")
    assert_equal "FINALIZED_ABORT", legacy.fetch("state")
    assert effective?("er02")
    committed_after_effective = old_worker("host", "commit", "er02")
    assert_equal "COMMITTED", committed_after_effective.fetch("state")
    assert_equal 1, count_rows(@host, "host_operations")
    reset_tables

    seed("h01")
    result = guard("h01") # Host is still OPEN, no durable event
    assert_equal "UNPROVEN", result.fetch("outcome")
    assert_still_pending("h01")
    evidence("H01", "COUNTEREXAMPLE_OBSERVED", legacy_effective_before_host_commit: true,
             legacy_host_commit_after_effective: true, guarded_status: "UNPROVEN",
             guarded_safety_pass: true)
  end

  def test_h02_unknown_host_identity_and_wrong_audience_are_rejected
    seed("h02")
    host_terminal_abort("h02")
    wrong_host = guard("h02", claimed("h02", "host_service_id" => "untrusted_host"))
    wrong_aud = guard("h02", claimed("h02", "audience" => "wrong_authority"))
    assert_equal "REJECT", wrong_host.fetch("outcome")
    assert_equal "REJECT", wrong_aud.fetch("outcome")
    assert_still_pending("h02")
    evidence("H02", "PASS", wrong_host_rejected: true, wrong_audience_rejected: true,
             model_only_metadata_allowlist: true, no_signature_auth_claim: true)
  end

  def test_h03_cross_context_replay_and_misbound_claims_are_rejected
    seed("h03")
    host_terminal_abort("h03")
    changes = [
      { "tenant_id" => "other_tenant" }, { "scope" => "unrelated_scope" },
      { "operation_id" => "operation_other" }, { "reservation_id" => "reservation_other" }
    ]
    changes.each do |change|
      assert_equal "REJECT", guard("h03", claimed("h03", change)).fetch("outcome")
    end
    assert_still_pending("h03")
    evidence("H03", "PASS", wrong_tenant_scope_operation_reservation_rejected: true)
  end

  def test_h04_same_receipt_replay_after_lost_ack_is_idempotent
    seed("h04")
    host_terminal_abort("h04")
    first = guard("h04")
    assert_equal "EFFECTIVE", first.fetch("outcome")
    assert effective?("h04")
    assert_equal 1, count_rows(@auth, "authority_proof_receipts")
    assert_equal 1, @auth.exec("SELECT count(*) AS n FROM authority_events WHERE kind='R_EFFECTIVE_ABORT'").first.fetch("n").to_i
    replay = guard("h04")
    assert_equal "IDEMPOTENT", replay.fetch("outcome")
    assert_equal 1, count_rows(@auth, "authority_proof_receipts")
    assert_equal 1, @auth.exec("SELECT count(*) AS n FROM authority_events WHERE kind='R_EFFECTIVE_ABORT'").first.fetch("n").to_i
    evidence("H04", "PASS", same_digest_replay_idempotent: true,
             duplicate_effective_events: 0, host_terminal_abort_precondition: true)
  end

  def test_h05_conflicting_commit_after_abort_decision_is_not_applied
    seed("h05")
    host_terminal_abort("h05")
    assert_equal "EFFECTIVE", guard("h05").fetch("outcome")
    conflict = guard("h05", claimed("h05", "decision" => "COMMITTED"))
    assert_equal "CONFLICT", conflict.fetch("outcome")
    assert effective?("h05")
    assert_equal 1, count_rows(@auth, "authority_proof_receipts")
    assert_equal "FINALIZED_ABORT", @auth.exec("SELECT state FROM authority_reservations").first.fetch("state")
    assert_equal 0, @auth.exec("SELECT count(*) AS n FROM authority_events WHERE kind='R_EFFECTIVE_COMMIT'").first.fetch("n").to_i
    evidence("H05", "PASS", contradictory_second_decision_stopped: true,
             original_abort_preserved: true, no_second_effective_event: true)
  end

  def test_h06_forged_durable_event_without_closed_host_gate_is_unproven
    seed("h06")
    # Control: fake Host event without atomic OPEN->ABORTED durable gate.
    @host.exec_params(<<~SQL, ["reservation_h06", "operation_h06"])
      INSERT INTO host_events(reservation_id,operation_id,kind)
      VALUES ($1,$2,'ABORT_DURABLE')
    SQL
    result = guard("h06")
    assert_equal "UNPROVEN", result.fetch("outcome")
    assert_still_pending("h06")
    assert_equal "OPEN", @host.exec("SELECT status FROM host_checkouts").first.fetch("status")
    assert_equal "ISSUED", @host.exec("SELECT nonce_state FROM host_checkouts").first.fetch("nonce_state")
    assert_equal 0, count_rows(@host, "host_operations")
    assert_equal 0, count_rows(@host, "host_outbox")
    evidence("H06", "PASS", fake_event_without_host_gate_stopped: true,
             host_still_open: true, nonce_unconsumed: true)
  end
end
