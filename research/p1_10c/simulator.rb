# frozen_string_literal: true

# P1-10c / HC06: SYNTHETIC, single-Ruby-process state-machine research ONLY.
# Authority and Host are *logical* components. The Mutex is a deliberately
# impossible-to-assume-across-real-services shared serialization boundary.
# NO AP2 verification, no actual issuer, HTTP, PostgreSQL, payments, or Receipt.
require "thread"

module HC06Synthetic
  Context = Struct.new(:tenant, :subject, :scope, keyword_init: true)

  class Host
    attr_reader :checkout, :nonce, :operations, :outbox

    def initialize
      @checkout = "OPEN"
      @nonce = "ISSUED"
      @operations = []
      @outbox = []
    end

    # Simulated atomic local DB mutation, NOT a real DB transaction.
    def commit_one
      return false unless @checkout == "OPEN" && @nonce == "ISSUED" &&
                          @operations.empty? && @outbox.empty?

      @nonce = "CONSUMED"
      @checkout = "RESERVED"
      @operations << "offline-operation-1"
      @outbox << "offline-operation-1"
      true
    end
  end

  class Authority
    attr_reader :epoch, :trace

    def initialize(context)
      @context = context
      @epoch = 1
      @active = true
      @online = true
      @issued = {} # Unforgeable only inside this Ruby fixture (object identity).
      @used = {}
      @trace = []
      @sequence = 0
      @mutex = Mutex.new
    end

    def online=(value)
      @mutex.synchronize { @online = value }
    end

    def snapshot(context)
      @mutex.synchronize do
        allowed = @online && @active && same_context?(context)
        log("Q", allowed: allowed)
        { allowed: allowed, epoch: @epoch }
      end
    end

    def issue_fence(context)
      @mutex.synchronize do
        return nil unless @online && @active && same_context?(context)
        token = Object.new
        @issued[token] = { context: context, epoch: @epoch }
        log("F", epoch: @epoch)
        token
      end
    end

    def revoke
      @mutex.synchronize do
        @active = false
        @epoch += 1
        log("R", epoch: @epoch)
        true
      end
    end

    # Only this guard+Host.commit_one share ONE synthetic critical section.
    # Implementing this by remote check-then-DB-COMMIT would REINTRODUCE TOCTOU.
    # A token or epoch by itself cannot substitute for this atomicity.
    def commit_with_fence(token, context, host)
      @mutex.synchronize do
        ticket = @issued[token]
        return false unless @online && @active && ticket &&
                            !@used[token] && ticket.fetch(:epoch) == @epoch &&
                            same_context?(context) &&
                            ticket.fetch(:context) == context
        return false unless host.commit_one

        @used[token] = true
        log("C", epoch: @epoch)
        true
      end
    end

    # Deliberately UNSAFE baseline: C happens without the authoritative gate.
    # Recording C afterward does not provide a real cross-system ordering.
    def observe_unguarded_commit
      @mutex.synchronize { log("C_UNGUARDED", epoch: @epoch) }
    end

    private

    def same_context?(context)
      context.is_a?(Context) && context == @context
    end

    def log(event, attrs = {})
      @sequence += 1
      @trace << { sequence: @sequence, event: event }.merge(attrs)
    end
  end
end
