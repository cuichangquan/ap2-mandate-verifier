# frozen_string_literal: true
#
# Issue #97 / A3-T2c additional Approval A2: SOURCE-ONLY synthetic lab inputs.
# Not executable evidence, not a signed AP2 JWT, not an authority enrollment.
# No files, sockets, environment variables, clocks or credentials are read.
# Nothing is written to stdout, fixtures, CI artifacts or an external system.
#
# B (DB/SQL/Ruby execution) is NOT approved by the existence of this source.
require "base64"

module AP2E06IA3T2cBLabInputs
  MAX_EPOCH = 4_102_444_800
  REF_PATTERN = /\A[a-z0-9_-]{1,48}\z/

  class << self
    # Each caller supplies bounded synthetic timestamps explicitly. Neither
    # wall clock nor caller fields can establish trusted Host time/identity.
    def context_for(label:, tenant:, checkout:, issued_at:, expires_at:,
                    checkout_version: 1)
      [label, tenant, checkout].each { |s| validate_label!(s) }
      unless issued_at.is_a?(Integer) && expires_at.is_a?(Integer) &&
             issued_at.between?(1, MAX_EPOCH) &&
             expires_at.between?(1, MAX_EPOCH) && issued_at < expires_at
        raise ArgumentError, "invalid synthetic issuance interval"
      end
      unless checkout_version.is_a?(Integer) &&
             checkout_version.between?(1, 1_000_000)
        raise ArgumentError, "invalid synthetic checkout version"
      end

      {
        "issuance_ref" => "lab_issue_#{label}",
        "challenge_ref" => "lab_challenge_#{label}",
        "host_verifier_domain" => "isolated_synthetic_host",
        "aud" => "isolated_synthetic_audience",
        "agent_thumbprint" => "lab_agent_thumbprint",
        "buyer_account_ref" => "lab_opaque_buyer",
        "tenant_id" => "lab_tenant_#{tenant}",
        "checkout_id" => "lab_checkout_#{checkout}",
        "checkout_jwt_source_ref" => "lab_received_wire_#{label}",
        "checkout_version" => checkout_version,
        "issued_at" => issued_at,
        "expires_at" => expires_at
      }.transform_values { |v| v.is_a?(String) ? v.freeze : v }.freeze
    end

    # Syntactically three components for the *worker's lab-only* wire bounds.
    # No private key, signature algorithm or authentic Merchant assertion.
    # NEVER use as an Issuer/Merchant signed positive test vector.
    def unsigned_checkout_wire_for(label:)
      validate_label!(label)
      head = Base64.urlsafe_encode64("LAB-NOT-A-JWT-HEADER", padding: false)
      body = Base64.urlsafe_encode64("NOT-SIGNED-#{label}", padding: false)
      signature = Base64.urlsafe_encode64("NOT-A-SIGNATURE", padding: false)
      [head, body, signature].join(".").freeze
    end

    def pg01(issued_at:, expires_at:)
      context_for(label: "pg01", tenant: "first", checkout: "first",
                  issued_at: issued_at, expires_at: expires_at)
    end

    # Different issuance_ref, challenge_ref, tenant and checkout: the only
    # common index key in PG02 should be the nonce digest.
    def pg02_pair(issued_at:, expires_at:)
      [
        context_for(label: "pg02_left", tenant: "left", checkout: "left",
                    issued_at: issued_at, expires_at: expires_at),
        context_for(label: "pg02_right", tenant: "right", checkout: "right",
                    issued_at: issued_at, expires_at: expires_at)
      ].freeze
    end

    # Deterministic collision input is strictly negative-only. It must NEVER
    # be passed to issue! as an ordinary CSPRNG-generated challenge.
    # This is not an entropy sample or a secret.
    def pg02_probe_nonce
      Base64.urlsafe_encode64(Array.new(32, 0x5a).pack("C*"),
                              padding: false).freeze
    end

    def pg03_reissue(issued_at:, expires_at:)
      context_for(label: "pg03_reuse", tenant: "after_expiry",
                  checkout: "different", issued_at: issued_at,
                  expires_at: expires_at)
    end

    def pg04_rollback(issued_at:, expires_at:)
      context_for(label: "pg04_rollback", tenant: "rollback",
                  checkout: "rollback", issued_at: issued_at,
                  expires_at: expires_at)
    end

    # PG05 uses the original reader row as its immutable reference and
    # changes exactly one *claimed* field at a time. Nothing writes to DB.
    # Results require a separate independent reader comparison.
    def pg05_mutations(original_context:, original_wire:)
      validate_original!(original_context, original_wire)
      changes = {
        "challenge_ref" => "lab_challenge_tampered",
        "agent_thumbprint" => "lab_agent_tampered",
        "buyer_account_ref" => "lab_buyer_tampered",
        "checkout_version" => original_context.fetch("checkout_version") + 1
      }
      mutations = changes.map do |field, replacement|
        changed = original_context.merge(field => replacement).freeze
        { "name" => field.freeze, "context" => changed,
          "wire" => original_wire.dup.freeze }.freeze
      end
      changed_wire = (original_wire + "X").freeze
      mutations << {
        "name" => "merchant_checkout_sha256".freeze,
        "context" => original_context,
        "wire" => changed_wire
      }.freeze
      mutations.freeze
    end

    private

    def validate_original!(context, wire)
      raise ArgumentError, "invalid context" unless context.is_a?(Hash) &&
        context.keys.all? { |k| k.is_a?(String) } &&
        context["checkout_version"].is_a?(Integer) &&
        context["checkout_version"] < 1_000_000
      raise ArgumentError, "invalid wire" unless wire.is_a?(String) &&
        wire.ascii_only? && wire.bytesize.between?(1, 16_384) &&
        wire.count(".") == 2
    end

    def validate_label!(label)
      return if label.is_a?(String) &&
        label.match?(REF_PATTERN)
      raise ArgumentError, "invalid synthetic label"
    end
  end
end
