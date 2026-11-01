# frozen_string_literal: true
require "ap2_mandate_verifier"
require "openssl"

# Runnable synthetic integration. Replace the in-memory records/Mutex with DB
# transactions and UNIQUE(merchant_id, checkout_id), UNIQUE(approval_id).
# Authentication/authorization are application responsibilities, not booleans
# accepted from an Agent. Provider private key exists ONLY in this backend.
class ApprovalBackend
  def initialize(provider, merchant_pem)
    @signer = AP2MandateVerifier::CheckoutJWT.es256_signer(private_key: provider)
    @public_pem, @merchant_pem = provider.public_to_pem, merchant_pem
    @records = {}
  end

  # Called by authenticated Trusted Surface AFTER displaying this verified
  # content and checking the employee's purchasing authority. Synthetic identity
  # here is deliberately separate from the Agent's present-only interface.
  def record_approval(employee_id:, displayed_checkout_jwt:)
    raise "unauthorized" unless employee_id == "synthetic-purchasing-employee"
    checked = AP2MandateVerifier::CheckoutJWT.verify(jwt: displayed_checkout_jwt,
      trusted_public_key_pem: @merchant_pem, expected_merchant_id: "shop",
      profile_ref: AP2MandateVerifier::Buyer::CHECKOUT_PROFILE)
    @records["approval-1"] = checked.jwt
    "approval-1"
  end

  # Trusted Surface backend endpoint, never exposed to the Agent. In a real
  # DB atomically issue once and persist the wire before making it available.
  def issue_for_approval(approval_id:, current_checkout_jwt:, now:)
    AP2MandateVerifier::Buyer.issue_closed(checkout_jwt: current_checkout_jwt,
      approved_checkout_jwt: @records.fetch(approval_id),
      trusted_merchant_public_key_pem: @merchant_pem, expected_merchant_id: "shop",
      issued_at: now, expires_at: now + 60, signer: @signer, public_key_pem: @public_pem)
  end
end

# Illustrates serialized duplicate handling and the unknown-outcome state.
# Memory is not durable; real apps must retain this state across restarts.
class SyntheticMerchant
  attr_reader :applied
  def initialize
    @lock, @orders, @applied = Mutex.new, {}, 0
  end
  def complete(order_id:, verified:, simulate_unknown: false)
    raise "unverified" unless verified.verified?
    @lock.synchronize do
      state = @orders[order_id]
      return state if state # Existing receipt or :unknown, never apply twice.
      @orders[order_id] = :unknown # Reserve BEFORE external side effects.
      return :unknown if simulate_unknown
      @applied += 1 # Synthetic application acceptance, NO payment operation.
      @orders[order_id] = yield
    end
  end
end

c = AP2MandateVerifier::CheckoutJWT
b = AP2MandateVerifier::Buyer
r = AP2MandateVerifier::CheckoutReceipt
merchant = OpenSSL::PKey::EC.generate("prime256v1")
provider = OpenSSL::PKey::EC.generate("prime256v1")
now = 1_800_000_000
totals = [{"type" => "subtotal", "amount" => 100}, {"type" => "total", "amount" => 100}]
checkout = {"id" => "office-1", "merchant" => {"id" => "shop", "name" => "Office supplies"},
  "status" => "ready_for_complete", "currency" => "USD", "links" => [], "totals" => totals,
  "line_items" => [{"id" => "line-1", "item" => {"id" => "pen", "title" => "Office pen", "price" => 100},
    "quantity" => 1, "totals" => totals}]}
signed = c.sign(checkout: checkout, signer: c.es256_signer(private_key: merchant), public_key_pem: merchant.public_to_pem)
# Merchant-signed wire is fetched by Agent. Trusted Surface verifies before
# rendering; authentication, CSRF protection and purchasing policy live here.
backend = ApprovalBackend.new(provider, merchant.public_to_pem)
approval = backend.record_approval(employee_id: "synthetic-purchasing-employee", displayed_checkout_jwt: signed.jwt)
issued = backend.issue_for_approval(approval_id: approval, current_checkout_jwt: signed.jwt, now: now)
# Agent receives only the approved output and public APIs, never backend signer.
wire = b.present_closed(closed_sd_jwt: issued.closed_sd_jwt)
verified = b.verify(closed_sd_jwt: wire, trusted_provider_public_key_pem: provider.public_to_pem,
  trusted_merchant_public_key_pem: merchant.public_to_pem, expected_checkout_jwt: signed.jwt,
  expected_merchant_id: "shop", verified_at: now)
raise "verification failed" unless verified.verified?
app = SyntheticMerchant.new
receipt = nil
2.times do
  receipt = app.complete(order_id: verified.checkout.fetch("id"), verified: verified) do
    r.sign(closed_sd_jwt: wire, profile_ref: b::PROFILE_REF, issuer: "shop", outcome: "Success",
      order_id: "office-1", issued_at: now, signer: c.es256_signer(private_key: merchant), public_key_pem: merchant.public_to_pem)
  end
end
checked = r.verify(jwt: receipt.jwt, closed_sd_jwt: wire, profile_ref: b::PROFILE_REF,
  trusted_public_key_pem: merchant.public_to_pem, expected_issuer: "shop",
  not_before: now, not_after: now + 60, verified_at: now)
raise "receipt failed" unless checked.verified? && checked.purchase_succeeded? && app.applied == 1
uncertain = SyntheticMerchant.new
2.times do
  state = uncertain.complete(order_id: "office-1", verified: verified, simulate_unknown: true) { raise "must not retry" }
  raise "unknown state lost" unless state == :unknown
end
puts "Direct checkout verified; application acceptance receipt verified; applied once=#{app.applied == 1}"
puts "Unknown outcome held for application reconciliation; no payment performed"
