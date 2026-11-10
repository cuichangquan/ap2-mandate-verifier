# frozen_string_literal: true

require "ap2_mandate_verifier"
require "openssl"

module RubyIntegration
  # Synthetic application storage, NOT enrollment or consent authentication.
  # In production these records come from independently authenticated services.
  # Never populate trust, order or approval from the received Payment Mandate.
  module Inputs
    M = AP2MandateVerifier
    CHECKOUT_PROFILE = M::ConditionalCheckout::PROFILE_REF
    module_function

    def totals(amount)
      %w[subtotal total].map { |type| {"type" => type, "amount" => amount} }
    end

    def signer(key) = M::CheckoutJWT.es256_signer(private_key: key)

    def bootstrap(now:)
      provider, agent, merchant = Array.new(3) { OpenSSL::PKey::EC.generate("prime256v1") }
      seller = {"id" => "shop", "name" => "Synthetic office supplies"}
      item = {"id" => "paper", "title" => "Synthetic paper"}
      instrument = {"id" => "synthetic-card", "type" => "card"}
      # Retain what the authenticated owner approved BEFORE issuing either Open.
      # These local conditions are never reconstructed from an incoming Mandate.
      approval = {"payment_instrument" => instrument,
        "checkout_requirements" => [{"id" => "paper-choice", "quantity" => 1, "acceptable_items" => [item]}],
        "payment_constraints" => [{"type" => "payment.amount_range", "currency" => "USD", "max" => 300},
          {"type" => "payment.allowed_payees", "allowed" => [seller]},
          {"type" => "payment.allowed_payment_instruments", "allowed" => [instrument]}]}
      checkout = {"id" => "office-1", "merchant" => seller, "status" => "ready_for_complete",
        "currency" => "USD", "line_items" => [{"id" => "row-1", "item" => item.merge("price" => 300),
          "quantity" => 1, "totals" => totals(300)}], "totals" => totals(300), "links" => []}
      opening = M::ConditionalCheckout.issue_open(merchant: seller,
        requirements: approval.fetch("checkout_requirements"),
        agent_public_key_pem: agent.public_to_pem, issued_at: now, expires_at: now + 60,
        signer: signer(provider), public_key_pem: provider.public_to_pem)
      checkout_jwt = M::CheckoutJWT.sign(checkout: checkout, profile_ref: CHECKOUT_PROFILE,
        signer: signer(merchant), public_key_pem: merchant.public_to_pem).jwt

      # Fixed IDs describe ONE protected state directory and ONE approved attempt.
      # A new occurrence must get a separate authenticated application approval.
      records = %w[Issuer Agent Merchant].zip([provider, agent, merchant]).map do |role, key|
        {"role" => role, "identity" => role == "Merchant" ? "shop" : role.downcase,
          "tenant_id" => "tenant", "purpose" => "checkout", "key_ref" => role.downcase,
          "public_key_pem" => key.public_to_pem, "active" => true,
          "not_before" => now - 1, "not_after" => now + 1000}
      end
      data = {
        "now" => now,
        "checkout" => checkout,
        "order" => {"tenant_id" => "tenant", "buyer_account_id" => "buyer", "order_id" => "office-1",
          "merchant_id" => "shop", "audience" => "merchant-host", "order_version" => "1",
          "currency" => "USD", "expected_total" => 300},
        "approval" => approval,
        "trust_snapshot" => {"id" => "registry", "policy_version" => "1", "active" => true,
          "not_before" => now - 1, "not_after" => now + 1000, "records" => records},
        "selectors" => records.to_h do |record|
          [record.fetch("role").downcase, record.slice("identity", "purpose", "key_ref")]
        end,
        "nonce" => "synthetic-one-use-nonce",
        "challenge_issuer" => "host",
        "scope" => {"tenant_id" => "tenant", "merchant_id" => "shop", "operation_id" => "operation-1",
          "approval_id" => "approval-1", "occurrence_id" => "one", "order_id" => "office-1"},
        "receipt_context" => {"trusted_public_key_pem" => merchant.public_to_pem,
          "expected_issuer" => "shop", "expected_payment_id" => "payment-1",
          "not_before" => now, "not_after" => now + 1000},
        "wires" => {"checkout_open" => opening.root_presentation, "checkout_jwt" => checkout_jwt},
        # Mock processor uses the synthetic merchant key. Provider private key
        # is discarded; only these two mock actors need to sign after restart.
        "mock_private_keys" => {"merchant" => merchant.private_to_pem, "agent" => agent.private_to_pem}
      }
      data["saved_challenge"] = M::InputBuilder.prepare(**host_inputs(data, now: now),
        challenge_id: "challenge-1", nonce: data.fetch("nonce"), issuer_id: data.fetch("challenge_issuer"),
        not_before: now, not_after: now + 60)
      closed = M::ConditionalCheckout.issue_closed(root_presentation: opening.root_presentation,
        checkout_jwt: checkout_jwt, trusted_issuer_public_key_pem: provider.public_to_pem,
        agent_public_key_pem: agent.public_to_pem, trusted_merchant_public_key_pem: merchant.public_to_pem,
        expected_merchant_id: "shop", audience: "merchant-host", nonce: data.fetch("nonce"),
        verified_at: now, signer: signer(agent))
      data.fetch("wires")["checkout_terminal"] = closed.terminal_jws
      data.fetch("wires")["checkout_closed"] = M::ConditionalCheckout.present(
        root_presentation: closed.root_presentation, terminal_jws: closed.terminal_jws,
        checkout_jwt: closed.checkout_jwt).closed_sd_jwt
      payment = expected_payment(data)
      data["expected_payment"] = payment
      data.fetch("wires")["payment_open"] = M::Payment.issue_open(
        open_checkout_sd_jwt: opening.root_presentation,
        constraints: data.fetch("approval").fetch("payment_constraints"), fixed: {},
        agent_public_key_pem: agent.public_to_pem, issued_at: now, expires_at: now + 60,
        signer: signer(provider), public_key_pem: provider.public_to_pem)
      data.fetch("wires")["payment_closed"] = resign(data, now: now)
      data
    end

    # Select from the CURRENT protected registry, never from JWT headers/claims.
    def public_key(data, role)
      selector = data.fetch("selectors").fetch(role)
      records = data.fetch("trust_snapshot").fetch("records").select do |entry|
        entry.fetch("role").downcase == role &&
          entry.fetch("tenant_id") == data.fetch("order").fetch("tenant_id") &&
          selector.all? { |field, value| entry.fetch(field) == value }
      end
      raise ArgumentError, "missing or ambiguous protected trust record" unless records.length == 1
      records.first.fetch("public_key_pem")
    end

    def host_inputs(data, now:)
      selectors = data.fetch("selectors").transform_keys(&:to_sym)
      trust = M::InputBuilder.trust(snapshot: data.fetch("trust_snapshot"),
        tenant_id: data.fetch("order").fetch("tenant_id"), verified_at: now,
        profile_ref: CHECKOUT_PROFILE, **selectors)
      {trust: trust, order: data.fetch("order"), root_presentation: data.fetch("wires").fetch("checkout_open"),
        host_checkout_jws: data.fetch("wires").fetch("checkout_jwt")}
    end

    # Derive from our signed Checkout and separately approved instrument, not
    # from the Payment being verified. Reconstruct on each accept/start call.
    def expected_payment(data)
      M::Payment.details(checkout_jwt: data.fetch("wires").fetch("checkout_jwt"),
        trusted_merchant_public_key_pem: public_key(data, "merchant"),
        expected_merchant_id: data.fetch("order").fetch("merchant_id"),
        payment_instrument: data.fetch("approval").fetch("payment_instrument"))
    end

    def verification(data, now:)
      checkout_inputs = M::InputBuilder.inputs(**host_inputs(data, now: now),
        saved_challenge: M::InputBuilder.restore(saved_challenge: data.fetch("saved_challenge")),
        terminal_jws: data.fetch("wires").fetch("checkout_terminal"),
        expected_challenge_issuer_id: data.fetch("challenge_issuer"),
        clock_source_id: "synthetic-clock", verified_at: now)
      {open_sd_jwt: data.fetch("wires").fetch("payment_open"),
        closed_sd_jwt: data.fetch("wires").fetch("payment_closed"), checkout_mode: :conditional,
        checkout_inputs: checkout_inputs, expected_payment: expected_payment(data),
        trusted_provider_public_key_pem: public_key(data, "issuer"),
        expected_agent_public_key_pem: public_key(data, "agent"),
        expected_audience: data.fetch("order").fetch("audience"), expected_nonce: data.fetch("nonce"),
        verified_at: now}
    end

    # Return alternate bytes without ever replacing the first persisted wire.
    def resign(data, now:)
      key = OpenSSL::PKey.read(data.fetch("mock_private_keys").fetch("agent"))
      M::Payment.issue_closed(open_sd_jwt: data.fetch("wires").fetch("payment_open"),
        payment: expected_payment(data), trusted_provider_public_key_pem: public_key(data, "issuer"),
        agent_public_key_pem: public_key(data, "agent"), audience: data.fetch("order").fetch("audience"),
        nonce: data.fetch("nonce"), verified_at: now, signer: signer(key)).closed_sd_jwt
    end

    # A signed mock outcome proves authenticity/binding, not real settlement.
    def receipt(data, wire:, outcome:, now:)
      fields = case outcome
      when "Success" then {psp_confirmation_id: "synthetic-psp", network_confirmation_id: "synthetic-network"}
      when "Error" then {error: "declined", error_description: "Synthetic processor declined"}
      else raise ArgumentError, "unsupported mock outcome"
      end
      context = data.fetch("receipt_context")
      key = OpenSSL::PKey.read(data.fetch("mock_private_keys").fetch("merchant"))
      M::PaymentReceipt.sign(closed_sd_jwt: wire, issuer: context.fetch("expected_issuer"),
        payment_id: context.fetch("expected_payment_id"), outcome: outcome, issued_at: now,
        signer: signer(key), public_key_pem: context.fetch("trusted_public_key_pem"), **fields).jwt
    end
  end
end
