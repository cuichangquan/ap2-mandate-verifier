# frozen_string_literal: true
#
# Issue #97 A3-T2c — synthetic PostgreSQL 16 nonce issuance worker.
# APPROVAL A: SOURCE + STATIC REVIEW ONLY. NOT RUN / NO DB / NO CI.
# NOT a Host enrollment authority, a G1/G7 result, a nonce consume CAS,
# or an adapter wired into existing verifier or payment code.
#
# This file does not open a network connection or create a DB on load.
# A disposable isolated PG16 connection may only be supplied after
# separate approval B and independent owner/ACL/cleanup review.
require "digest"
require "securerandom"
require "base64"

module AP2E06IA3T2cNonceIssuanceWorker
  MAX_TIME = 4_102_444_800
  MAX_CHECKOUT_WIRE = 16_384
  LAB_WRITER_ROLE = "a3_t2c_writer"
  REF_FIELDS = %w[
    issuance_ref challenge_ref host_verifier_domain aud agent_thumbprint
    buyer_account_ref tenant_id checkout_id checkout_jwt_source_ref
  ].freeze
  REQUIRED_FIELDS = (REF_FIELDS + %w[checkout_version issued_at expires_at]).sort.freeze

  # Same DB row contains issuance and immutable Challenge/Checkout binding.
  # No untrusted string interpolation enters SQL. Original JWT is hashed as
  # *received bytes*, NEVER parsed/re-serialized or logged.
  INSERT_SQL = <<~SQL.freeze
    INSERT INTO a3_t2c.nonce_issuance_history (
      issuance_ref, nonce_sha256, challenge_ref, host_verifier_domain,
      aud, agent_thumbprint, buyer_account_ref, tenant_id, checkout_id,
      checkout_version, merchant_checkout_sha256, checkout_jwt_source_ref,
      issued_at, expires_at
    ) VALUES (
      $1, $2, $3, $4, $5, $6, $7, $8, $9,
      $10, $11, $12, to_timestamp($13::double precision),
      to_timestamp($14::double precision)
    )
  SQL

  class LabObservation
    attr_reader :status, :reason, :outcome, :nonce, :worker_handles, :connections

    def initialize(reason:, outcome:, nonce: nil, worker_handles: [],
                   connections: [])
      @status = "HOLD".freeze
      @reason = reason.freeze
      @outcome = outcome
      # Expose the lab-only nonce exclusively after a positively observed
      # local COMMIT acknowledgement. This is NOT authenticated Host issuance.
      @nonce = nonce&.dup&.freeze
      # Uncertain/blocked libpq calls must return live handles to the
      # separately approved B supervisor. Never close/reuse these sockets
      # until their actual SQL transaction state is established.
      @worker_handles = worker_handles.dup.freeze
      @connections = connections.dup.freeze
      freeze
    end

    def pending_worker_cleanup?
      @worker_handles.any?(&:alive?) || !@connections.empty?
    end

    def commit_acknowledged?
      @outcome == :local_commit_acknowledged
    end

    def authoritative?
      false
    end

    def g1_admissible?
      false
    end

    def replay_safe?
      false
    end

    def evidence
      nil
    end
  end

  class << self
    # Approved B only: synthetic context, nonce from Ruby's OS-backed secure
    # random API (32 bytes), INSERT then confirmed COMMIT before returning
    # challenge nonce. Never send nonce to a Terminal before this returns.
    # Code review alone cannot prove the runtime's entropy source.
    def issue!(connection:, context:, checkout_wire:)
      # Public synthetic issuance can also stall on ANY libpq call, including
      # pre-BEGIN role inspection and COMMIT. The entire lifecycle runs in a
      # retained worker thread, never on an unbounded caller stack.
      # This never sends a nonce to the Terminal; an uncertain completion
      # returns HOLD with worker+connection handles for quarantine.
      runner = Thread.new do
        raw = SecureRandom.random_bytes(32)
        nonce = Base64.urlsafe_encode64(raw, padding: false).freeze
        insert_synthetic_lab!(
          connection: connection, context: context, checkout_wire: checkout_wire,
          nonce: nonce, disclose_after_commit: true
        )
      end
      return hold("issuance_socket_timeout_quarantine_stop",
                  worker_handles: [runner], connections: [connection]) unless
        runner.join(6)

      observation = runner.value
      return hold("issuance_result_unverified", connections: [connection]) unless
        observation.is_a?(LabObservation)
      # An exception can complete a worker Thread while PostgreSQL keeps
      # an open transaction. Never drop the quarantine handle merely
      # because Thread#alive? is false.
      observation
    rescue StandardError
      hold("csprng_or_issuance_unavailable_quarantine",
           worker_handles: [runner].compact, connections: [connection])
    end

    # PG02/PG03 negative-only input: duplicate a deliberately fixed synthetic
    # nonce across two different tenant/Checkout contexts. DO NOT use this
    # for ordinary issuance or treat it as evidence of CSPRNG quality.
    # Even when INSERT commits, NO nonce is exposed through this method.
    def collision_probe_only!(connection:, context:, checkout_wire:, nonce:,
                              lab_probe_hook: nil)
      return hold("invalid_collision_probe_nonce") unless nonce.is_a?(String)
      frozen_nonce = nonce.dup.freeze
      return hold("invalid_collision_probe_nonce") unless
        frozen_nonce.ascii_only? &&
        frozen_nonce.match?(/\A[A-Za-z0-9_-]{43}\z/)
      insert_synthetic_lab!(
        connection: connection, context: context, checkout_wire: checkout_wire,
        nonce: frozen_nonce, disclose_after_commit: false,
        lab_probe_hook: lab_probe_hook
      )
    rescue StandardError
      hold("collision_probe_unavailable")
    end

    private

    def insert_synthetic_lab!(connection:, context:, checkout_wire:,
                              nonce:, disclose_after_commit:,
                              lab_probe_hook: nil)
      return hold("synthetic_context_invalid") unless context.is_a?(Hash)
      # Detach the whole caller-owned mapping and every nested String before
      # reading/checking it. Passing a Hash#dup with shared mutable values
      # creates a time-of-check/time-of-use window across the DB transaction.
      claimed = context.each_with_object({}) do |(key, value), detached|
        k = key.is_a?(String) ? key.dup.freeze : key
        v = value.is_a?(String) ? value.dup.freeze : value
        detached[k] = v
      end.freeze
      return hold("synthetic_context_invalid") unless valid_context?(claimed)
      return hold("original_checkout_wire_invalid") unless checkout_wire.is_a?(String)

      wire = checkout_wire.dup.freeze
      return hold("original_checkout_wire_bounds") unless
        wire.ascii_only? && wire.bytesize.between?(1, MAX_CHECKOUT_WIRE) &&
        wire.count(".") == 2
      # PG treats BEGIN inside a caller transaction as a warning/no-op.
      # Refuse an externally owned transaction instead of COMMITting any
      # unrelated caller work. The injected connection must be exclusively
      # owned by this invocation; shared/simultaneous use is out of scope.
      return hold("transaction_not_idle_or_unverifiable") unless
        idle_connection?(connection)
      return hold("synthetic_writer_role_or_primary_unverified") unless
        restricted_lab_writer?(connection)
      return hold("transaction_not_idle_or_unverifiable") unless
        idle_connection?(connection)

      digest = Digest::SHA256.hexdigest(nonce.b)
      jwt_digest = Digest::SHA256.hexdigest(wire.b)
      args = [
        claimed.fetch("issuance_ref"), digest, claimed.fetch("challenge_ref"),
        claimed.fetch("host_verifier_domain"), claimed.fetch("aud"),
        claimed.fetch("agent_thumbprint"), claimed.fetch("buyer_account_ref"),
        claimed.fetch("tenant_id"), claimed.fetch("checkout_id"),
        claimed.fetch("checkout_version"), jwt_digest,
        claimed.fetch("checkout_jwt_source_ref"),
        claimed.fetch("issued_at"), claimed.fetch("expires_at")
      ]

      # Under an uncertain INSERT/COMMIT outcome, do not reuse or disclose
      # the nonce; never turn an unknown ACK into a known rollback or retry.
      # No external side effects, retries or terminal delivery in this class.
      begin_attempted = false
      begin_acknowledged = false
      commit_attempted = false
      begin
        # The DB may accept BEGIN and lose its wire acknowledgement.
        # Mark uncertainty *before* issuing libpq. Any exception returns
        # the socket handle for B-time quarantine even if this Thread exits.
        begin_attempted = true
        begin_result = connection.exec("BEGIN")
        begin_acknowledged = begin_result.respond_to?(:cmd_status) &&
                             begin_result.cmd_status == "BEGIN"
        raise "issuance_begin_ack_unknown" unless begin_acknowledged
        connection.exec("SET LOCAL statement_timeout = '3000ms'")
        connection.exec("SET LOCAL lock_timeout = '2000ms'")

        # PG02 negative-probe only. Synchronize AFTER both BEGINs and
        # immediately BEFORE the actual INSERT. A separate post-INSERT
        # hook can keep the winning unique-index lock uncommitted while
        # the other worker attempts its conflicting INSERT. A hook
        # failure or CANCEL must raise -> ROLLBACK/HOLD, never commit.
        lab_probe_hook.call(:before_insert) if lab_probe_hook && !disclose_after_commit
        insert = connection.exec_params(INSERT_SQL, args)
        return hold_with_rollback(connection, "insert_rowcount_unknown") unless
          insert.cmd_tuples == 1

        lab_probe_hook.call(:after_insert_before_commit) if
          lab_probe_hook && !disclose_after_commit
        # A lost COMMIT ACK means the nonce may already exist. Do not
        # retry, recycle or issue a second nonce for this Checkout.
        commit_attempted = true
        ack = connection.exec("COMMIT")
        return hold("commit_acknowledgment_unknown_quarantine_stop",
                    connections: [connection]) unless
          ack.respond_to?(:cmd_status) && ack.cmd_status == "COMMIT"

        LabObservation.new(
          reason: "synthetic_pg_commit_ack_only_no_host_authority",
          outcome: :local_commit_acknowledged,
          nonce: (disclose_after_commit ? nonce : nil)
        )
      rescue StandardError
        # An attempted BEGIN can be active even with NO ACK. A later
        # ROLLBACK attempt cannot rescue uncertainty about a sent COMMIT.
        # Always return the injected socket to the supervisor for explicit
        # quarantine instead of returning an ordinary hold with no handle.
        if begin_attempted && !commit_attempted
          begin
            connection.exec("ROLLBACK")
          rescue StandardError
            nil
          end
        end
        hold("transaction_or_commit_outcome_uncertain_quarantine_stop",
             connections: [connection])
      end
    end

    def valid_context?(context)
      return false unless context.is_a?(Hash) &&
        context.keys.all? { |k| k.is_a?(String) } &&
        context.keys.sort == REQUIRED_FIELDS

      return false unless REF_FIELDS.all? { |name|
        v = context[name]
        v.is_a?(String) && v.ascii_only? &&
          v.bytesize.between?(1, 256) && v.match?(/\A[!-~]+\z/)
      }

      a = context["issued_at"]
      b = context["expires_at"]
      context["checkout_version"].is_a?(Integer) &&
        context["checkout_version"].between?(1, 1_000_000) &&
        a.is_a?(Integer) && b.is_a?(Integer) &&
        a.between?(1, MAX_TIME) && b.between?(1, MAX_TIME) && a < b
    end

    # A reader must still independently inspect actual role memberships,
    # owner inheritance and ACLs. Checking this *connection* is a defensive
    # local guard, not an authorization provenance proof.
    # Requires the actual libpq transaction status constant, never a
    # caller-supplied :idle flag or a BEGIN warning interpreted as success.
    def idle_connection?(connection)
      defined?(PG::PQTRANS_IDLE) &&
        connection.respond_to?(:transaction_status) &&
        connection.transaction_status == PG::PQTRANS_IDLE
    rescue StandardError
      false
    end

    def restricted_lab_writer?(connection)
      rows = connection.exec(<<~SQL)
        SELECT current_user AS role_name, session_user AS login_role,
               pg_is_in_recovery() AS replica,
               has_table_privilege(current_user,
                 'a3_t2c.nonce_issuance_history', 'INSERT') AS may_insert,
               has_table_privilege(current_user,
                 'a3_t2c.nonce_issuance_history', 'UPDATE') AS may_update,
               has_table_privilege(current_user,
                 'a3_t2c.nonce_issuance_history', 'DELETE') AS may_delete,
               has_table_privilege(current_user,
                 'a3_t2c.nonce_issuance_history', 'TRUNCATE') AS may_truncate
      SQL
      return false unless rows.respond_to?(:ntuples) && rows.ntuples == 1
      row = rows[0]
      row["role_name"] == LAB_WRITER_ROLE &&
        row["login_role"] == LAB_WRITER_ROLE &&
        authenticated_connection_user?(connection, LAB_WRITER_ROLE) &&
        row["replica"] == "f" &&
        row["may_insert"] == "t" &&
        %w[may_update may_delete may_truncate].all? { |k| row[k] == "f" }
    rescue StandardError
      false
    end

    def authenticated_connection_user?(connection, expected)
      return false unless defined?(PG::Connection) &&
        connection.instance_of?(PG::Connection) &&
        connection.respond_to?(:conninfo_hash)

      info = connection.conninfo_hash
      info.is_a?(Hash) && info[:user].is_a?(String) &&
        info[:user] == expected
    rescue StandardError
      false
    end

    def hold(reason, worker_handles: [], connections: [])
      LabObservation.new(reason: reason, outcome: :unverified,
                         worker_handles: worker_handles,
                         connections: connections)
    end

    def hold_with_rollback(connection, reason)
      # SQL may already be in flight or ROLLBACK's ACK may be lost. A
      # non-one-row INSERT cannot safely authorize connection reuse.
      begin
        connection.exec("ROLLBACK")
      rescue StandardError
        nil
      end
      hold("#{reason}_quarantine_stop", connections: [connection])
    end
  end
end
