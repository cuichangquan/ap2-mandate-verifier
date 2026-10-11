# frozen_string_literal: true

# ONLY a deterministic Ruby state-machine test, not real external revocation.
require "minitest/autorun"
require "json"
require_relative "simulator"

P110C_CASES = []
Minitest.after_run do
  next unless (path = ENV["P110C_REPORT"])

  File.write(path, JSON.pretty_generate(
    canonical_case_id: "HC06",
    status: "PARTIAL_SYNTHETIC_ONLY_NOT_FULL_HC06_PASS",
    prior_real_pg_host_ids: 9,
    canonical_host_ids_newly_proven: 0,
    unrun_canonical_host_ids: 25,
    scenarios: P110C_CASES
  ))
end

class HC06ExternalAuthorityModelTest < Minitest::Test
  def setup
    @context = HC06Synthetic::Context.new(
      tenant: "lab-tenant", subject: "lab-buyer", scope: "offline-checkout"
    )
    @authority = HC06Synthetic::Authority.new(@context)
    @host = HC06Synthetic::Host.new
  end

  def event_names
    @authority.trace.map { |x| x.fetch(:event) }
  end

  def assert_empty_operation
    assert_equal "OPEN", @host.checkout
    assert_equal "ISSUED", @host.nonce
    assert_empty @host.operations
    assert_empty @host.outbox
  end

  def assert_one_operation
    assert_equal "RESERVED", @host.checkout
    assert_equal "CONSUMED", @host.nonce
    assert_equal ["offline-operation-1"], @host.operations
    assert_equal ["offline-operation-1"], @host.outbox
  end

  def record(scenario, classification, **evidence)
    P110C_CASES << {
      id: "HC06", scenario: scenario, result: "PASS",
      classification: classification
    }.merge(evidence)
  end

  def test_naive_requery_then_revocation_then_unprotected_commit_exposes_toctou
    query = @authority.snapshot(@context)
    assert_equal true, query.fetch(:allowed)
    assert_equal 1, query.fetch(:epoch)

    @authority.revoke
    assert @host.commit_one # INTENTIONALLY UNSAFE reference implementation
    @authority.observe_unguarded_commit

    assert_equal %w[Q R C_UNGUARDED], event_names
    assert_operator @authority.trace[1].fetch(:sequence), :<,
                    @authority.trace[2].fetch(:sequence)
    assert_one_operation # Expected VULNERABILITY, not a secure HC06 PASS.
    record("naive_q_r_c", "EXPECTED_UNSAFE_BASELINE",
           r_before_c: true, bad_operation_committed: true,
           model_guarantee: "VIOLATED")
  end

  def test_fencing_token_without_final_guard_is_also_unsafe
    ticket = @authority.issue_fence(@context)
    refute_nil ticket
    @authority.revoke

    assert @host.commit_one # Misuse: fence is merely checked/exposed, not gated
    @authority.observe_unguarded_commit

    assert_equal %w[F R C_UNGUARDED], event_names
    assert_one_operation
    record("fence_not_enforced", "EXPECTED_UNSAFE_BASELINE",
           r_before_c: true, bad_operation_committed: true,
           model_guarantee: "VIOLATED")
  end

  def test_revocation_before_query_fails_closed
    @authority.revoke
    q = @authority.snapshot(@context)
    assert_equal false, q.fetch(:allowed)
    assert_nil @authority.issue_fence(@context)
    assert_equal %w[R Q], event_names
    assert_empty_operation

    record("revoke_before_query", "SAFE_MODEL", stopped: true,
           r_before_c: true, operations: 0)
  end

  def test_fenced_final_gate_rejects_revoked_ticket_before_commit
    ticket = @authority.issue_fence(@context)
    refute_nil ticket
    @authority.revoke

    assert_equal false, @authority.commit_with_fence(ticket, @context, @host)
    assert_equal %w[F R], event_names
    assert_equal 2, @authority.epoch
    assert_empty_operation

    record("fence_r_before_c", "SAFE_MODEL", stopped: true,
           r_before_c: true, operations: 0,
           synchronized_final_gate: true)
  end

  def test_fenced_commit_first_then_revocation_is_not_retroactive_cancellation
    ticket = @authority.issue_fence(@context)
    assert @authority.commit_with_fence(ticket, @context, @host)
    assert_one_operation
    @authority.revoke

    assert_equal %w[F C R], event_names
    assert_operator @authority.trace[1].fetch(:sequence), :<,
                    @authority.trace[2].fetch(:sequence)
    assert_equal false, @authority.commit_with_fence(ticket, @context, @host)
    assert_one_operation

    record("fence_c_before_r", "SAFE_MODEL", c_before_r: true,
           late_revoke_did_not_cancel: true, operations: 1,
           repeated_ticket_stopped: true)
  end

  def test_forged_ticket_and_cross_tenant_scope_subject_must_stop
    good_ticket = @authority.issue_fence(@context)
    refute_nil good_ticket
    assert_equal false, @authority.commit_with_fence(Object.new, @context, @host)

    invalid = [
      HC06Synthetic::Context.new(tenant: "other-tenant", subject: "lab-buyer", scope: "offline-checkout"),
      HC06Synthetic::Context.new(tenant: "lab-tenant", subject: "other-buyer", scope: "offline-checkout"),
      HC06Synthetic::Context.new(tenant: "lab-tenant", subject: "lab-buyer", scope: "refund")
    ]
    invalid.each do |context|
      assert_equal false, @authority.commit_with_fence(good_ticket, context, @host)
      assert_nil @authority.issue_fence(context)
      assert_empty_operation
    end
    assert_equal %w[F], event_names
    record("scope_tenant_subject_and_forgery", "SAFE_MODEL",
           invalid_contexts_stopped: 3, forged_ticket_stopped: true,
           operations: 0)
  end

  def test_authority_unavailable_at_final_gate_stops_without_mutation
    ticket = @authority.issue_fence(@context)
    refute_nil ticket
    @authority.online = false

    assert_equal false, @authority.commit_with_fence(ticket, @context, @host)
    assert_equal false, @authority.snapshot(@context).fetch(:allowed)
    assert_empty_operation

    record("offline_at_final_gate", "SAFE_MODEL",
           unavailable_fail_closed: true, operations: 0)
  end

  def test_replayed_ticket_cannot_create_a_second_order
    ticket = @authority.issue_fence(@context)
    assert @authority.commit_with_fence(ticket, @context, @host)
    assert_one_operation

    assert_equal false, @authority.commit_with_fence(ticket, @context, @host)
    assert_one_operation
    assert_equal %w[F C], event_names

    record("fence_replay", "SAFE_MODEL", replay_stopped: true,
           operations: 1, outbox: 1)
  end
end
