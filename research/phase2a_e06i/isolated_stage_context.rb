# frozen_string_literal: true
#
# E06-I A3-T1: PRIVATE INTERNAL candidate for inspecting untrusted claims.
# SOURCE ONLY / NOT RUN / NO G1/G3 SUCCESS / NO PAYMENT / NO CI.
#
# Exact full Root, Terminal and Checkout wire identities are hashes of the
# detached ORIGINAL buffers, not reconstructed JSON or disclosure subsets.
# Immutable structure is not a Host authority, issuance registry or evidence.
require "digest"
require_relative "isolated_host_snapshot"

module AP2E06IStageContext
  MAX_CLOCK = AP2E06IHostSnapshot::MAX_TIME

  class Halt < StandardError
    attr_reader :status, :code

    def initialize(status, code)
      @status = status
      @code = code
      super(code)
    end
  end

  # Intentionally not a public value type or security capability. Even a
  # caller fabricating this instance gains no success token or trusted stage.
  class ContextCandidate
    attr_reader :verified_at, :root_wire_sha256, :terminal_wire_sha256,
                :checkout_wire_sha256, :host_wire_sha256, :source_labels,
                :challenge, :checkout_ref

    def initialize(verified_at:, root_wire_sha256:, terminal_wire_sha256:,
                   checkout_wire_sha256:, host_wire_sha256:, source_labels:,
                   challenge:, checkout_ref:)
      @verified_at = verified_at
      @root_wire_sha256 = root_wire_sha256.freeze
      @terminal_wire_sha256 = terminal_wire_sha256.freeze
      @checkout_wire_sha256 = checkout_wire_sha256.freeze
      @host_wire_sha256 = host_wire_sha256.freeze
      @source_labels = AP2E06IStageContext.deep_detach_freeze(source_labels)
      @challenge = AP2E06IStageContext.deep_detach_freeze(challenge)
      @checkout_ref = AP2E06IStageContext.deep_detach_freeze(checkout_ref)
      freeze
    end

    def status
      "HOLD"
    end

    def authoritative?
      false
    end

    def g1_admissible?
      false
    end

    def g3_authenticated?
      false
    end

    def evidence
      nil
    end
  end
  private_constant :ContextCandidate

  class << self
    # Bounded input is supplied only after the independent diagnostic's G0
    # lexical checks and A3-H1 claim comparisons. Those comparisons are NOT
    # proof of Host ownership, signer enrollment or durable nonce issuance.
    def build_claim_only!(candidate:, combined_claim:, root_wire:,
                          terminal_wire:, checkout_wire:, verified_at:)
      unless candidate.is_a?(AP2E06IHostSnapshot::Candidate) &&
          combined_claim.is_a?(AP2E06IHostSnapshot::CombinedClaim) &&
          candidate.status == "HOLD" && !candidate.admissible? &&
          combined_claim.status == "HOLD" &&
          !combined_claim.g1_admissible? &&
          !combined_claim.authoritative?
        raise Halt.new("HOLD", "unauthenticated_stage_context_source")
      end

      unless verified_at.is_a?(Integer) && verified_at.between?(1, MAX_CLOCK) &&
          candidate.verified_at == verified_at &&
          combined_claim.verified_at == verified_at &&
          combined_claim.candidate_sha256 == candidate.raw_sha256
        raise Halt.new("HOLD", "stage_context_clock_or_host_mismatch")
      end

      wires = [root_wire, terminal_wire, checkout_wire]
      unless wires.all? { |wire| wire.is_a?(String) }
        raise Halt.new("REJECT", "invalid_original_wire_type")
      end
      # Fresh detached copies defeat mutation between bytesize, comparison and
      # digest. Do not accept a reconstructed JWT or normalized SD-JWT.
      root, terminal, checkout = wires.map { |wire| wire.dup.freeze }
      unless [root, terminal].all? { |wire|
          wire.ascii_only? && wire.bytesize.between?(1, 32_768)
        } && checkout.ascii_only? && checkout.bytesize.between?(1, 16_384)
        raise Halt.new("REJECT", "original_wire_resource_limit")
      end

      snap = candidate.snapshot
      unless snap.is_a?(Hash) && snap.fetch("checkout").fetch("original_jwt") == checkout
        raise Halt.new("REJECT", "host_checkout_original_wire_mismatch")
      end
      ref = snap.fetch("checkout").fetch("ref")
      challenge = snap.fetch("challenge")
      unless ref.is_a?(Hash) && ref.keys.sort == AP2E06IHostSnapshot::CHECKOUT_REF_FIELDS &&
          ref["tenant_id"] == "synthetic-e01s" &&
          challenge.is_a?(Hash) && challenge.fetch("checkout_ref") == ref
        raise Halt.new("REJECT", "stage_context_checkout_challenge_mismatch")
      end

      labels = %w[issuer_trust agent_trust merchant_trust].to_h do |kind|
        entry = snap.fetch(kind)
        [kind, {
          "subject_ref" => entry.fetch("subject_ref"),
          "policy_ref" => entry.fetch("policy_ref"),
          "tenant_id" => entry.fetch("tenant_id")
        }]
      end
      labels["claimed_host_enrollment_sha256"] = combined_claim.source_sha256
      labels["claimed_nonce_ledger_sha256"] = combined_claim.nonce_sha256

      ContextCandidate.new(
        verified_at: verified_at,
        root_wire_sha256: Digest::SHA256.hexdigest(root.b),
        terminal_wire_sha256: Digest::SHA256.hexdigest(terminal.b),
        checkout_wire_sha256: Digest::SHA256.hexdigest(checkout.b),
        host_wire_sha256: candidate.raw_sha256,
        source_labels: labels, challenge: challenge, checkout_ref: ref
      )
    rescue Halt
      raise
    rescue KeyError, TypeError, ArgumentError, NoMethodError
      raise Halt.new("REJECT", "invalid_stage_context_claim")
    end

    # The candidate contains only bounded Hash/Array/String/primitive values
    # from the already strict Host source inspection. Keep detached nested
    # objects entirely immutable; there is no user-settable context clock.
    def deep_detach_freeze(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, part), out|
          out[key.dup.freeze] = deep_detach_freeze(part)
        end.freeze
      when Array
        value.map { |part| deep_detach_freeze(part) }.freeze
      when String
        value.dup.freeze
      else
        value
      end
    end
  end
end
