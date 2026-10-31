# frozen_string_literal: true
# Synthetic test issuance only. This is not a production Mandate-issuance API.
require "json"
require "openssl"
require "base64"
require "digest"
require_relative "../../lib/ap2_mandate_verifier" unless defined?(AP2MandateVerifier::InputBuilder)

module MultiItemFixture
  PROFILE = "ap2.checkout.single_merchant_multi_item"
  NOW = 1_800_000_000
  def self.copy(value) = Marshal.load(Marshal.dump(value))
  def self.b64(value) = Base64.urlsafe_encode64(value, padding: false)
  def self.hash(value) = b64(Digest::SHA256.digest(value))
  def self.totals(value) = [{"type" => "subtotal", "amount" => value}, {"type" => "total", "amount" => value}]
  def self.item(id) = {"id" => id, "title" => "Product #{id}"}
  def self.requirement(id, quantity, candidates) = {"id" => id, "quantity" => quantity, "acceptable_items" => candidates.map { |id| item(id) }}
  def self.line(id, product, quantity, price = 100)
    {"id" => id, "item" => item(product).merge("price" => price), "quantity" => quantity, "totals" => totals(quantity * price)}
  end
  def self.requirements = [requirement("requirement-AB", 1, %w[A B]), requirement("requirement-A", 2, %w[A])]
  def self.checkout(lines = [line("line-A", "A", 2), line("line-B", "B", 1, 250)])
    {"id" => "order", "merchant" => {"id" => "shop", "name" => "Store"}, "currency" => "USD",
     "status" => "ready_for_complete", "links" => [], "line_items" => lines,
     "totals" => totals(lines.sum { |entry| entry["totals"][0]["amount"] })}
  end
  def self.sign(key, value, typ)
    wire = b64(JSON.generate("alg" => "ES256", "typ" => typ)) + "." + b64(JSON.generate(value))
    nodes = OpenSSL::ASN1.decode(key.sign("SHA256", wire)).value
    signature = nodes.map { |node| node.value.to_s(2).rjust(32, "\0") }.join
    # Provider signature control independent of the Gem's signature parser.
    raise "synthetic signature control failed" unless key.verify("SHA256", OpenSSL::ASN1::Sequence.new(nodes).to_der, wire)
    wire + "." + b64(signature)
  end
  def self.disclose(value, salt)
    b64(JSON.generate(["multi-item-test-#{salt}", value]))
  end
  def self.marker(value) = {"..." => hash(value)}

  # Re-sign mutations intentionally for causal semantic negatives. The supplied
  # independent order remains a Host input; it is never read from received JWTs.
  def self.build(requirements: self.requirements, checkout: self.checkout, profile: PROFILE,
                 root_transform: nil, checkout_wire_transform: nil, open_transform: nil, raw_checkout: false)
    keys = Array.new(3) { OpenSSL::PKey::EC.generate("prime256v1") }
    issuer, agent, merchant = keys
    disclosed = []
    requested = copy(requirements)
    requested.each_with_index do |req, i|
      req["acceptable_items"] = req["acceptable_items"].each_with_index.map do |candidate, j|
        wire = disclose(candidate, "candidate-#{i}-#{j}")
        disclosed << wire
        marker(wire)
      end
    end
    allowed = disclose(checkout["merchant"], "merchant")
    point = agent.public_key.to_octet_string(:uncompressed)
    opening = {"vct" => "mandate.checkout.open.1", "iat" => NOW - 100, "exp" => NOW + 600,
      "cnf" => {"jwk" => {"kty" => "EC", "crv" => "P-256", "x" => b64(point.byteslice(1, 32)), "y" => b64(point.byteslice(33, 32))}},
      "constraints" => [{"type" => "checkout.line_items", "items" => requested},
        {"type" => "checkout.allowed_merchants", "allowed" => [marker(allowed)]}]}
    open_transform&.call(opening)
    opening_wire = disclose(opening, "opening")
    root = ([sign(issuer, {"_sd_alg" => "sha-256", "delegate_payload" => [marker(opening_wire)]}, "example+sd-jwt"), opening_wire] + disclosed + [allowed, ""]).join("~")
    root = root_transform.call(root) if root_transform
    original_checkout_wire = if raw_checkout
      sign(merchant, checkout, "JWT")
    else
      AP2MandateVerifier::CheckoutJWT.sign(checkout: checkout, profile_ref: profile,
        signer: AP2MandateVerifier::CheckoutJWT.es256_signer(private_key: merchant), public_key_pem: merchant.public_to_pem).jwt
    end
    checkout_wire = checkout_wire_transform ? checkout_wire_transform.call(original_checkout_wire) : original_checkout_wire
    closed = {"vct" => "mandate.checkout.1", "iat" => NOW - 100, "exp" => NOW + 600,
      "checkout_jwt" => checkout_wire, "checkout_hash" => hash(checkout_wire)}
    terminal = sign(agent, {"aud" => "host", "nonce" => "test-nonce", "iat" => NOW,
      "sd_hash" => hash(root), "delegate_payload" => [closed]}, "kb+sd-jwt")
    snapshot = {"id" => "snapshot", "policy_version" => "policy-1", "active" => true,
      "not_before" => NOW - 1_000, "not_after" => NOW + 1_000,
      "records" => %w[Issuer Agent Merchant].each_with_index.map do |role, i|
        {"role" => role, "identity" => role == "Merchant" ? "shop" : role.downcase,
         "tenant_id" => "tenant", "purpose" => "checkout", "key_ref" => "#{role.downcase}-1",
         "public_key_pem" => keys[i].public_to_pem, "active" => true, "not_before" => NOW - 1_000, "not_after" => NOW + 1_000}
      end}
    selectors = %w[Issuer Agent Merchant].to_h { |role| [role.downcase.to_sym, {"identity" => role == "Merchant" ? "shop" : role.downcase, "purpose" => "checkout", "key_ref" => "#{role.downcase}-1"}] }
    trust_args = {snapshot: snapshot, tenant_id: "tenant", verified_at: NOW, profile_ref: profile, **selectors}
    trust = AP2MandateVerifier::InputBuilder.trust(**trust_args)
    order = {"tenant_id" => "tenant", "buyer_account_id" => "buyer", "order_id" => "order", "merchant_id" => "shop",
      "audience" => "host", "order_version" => "order-v1", "currency" => "USD", "expected_total" => checkout["totals"][0]["amount"]}
    challenge = AP2MandateVerifier::InputBuilder.prepare(trust: trust, order: order, root_presentation: root,
      host_checkout_jws: checkout_wire, challenge_id: "challenge-1", nonce: "test-nonce", issuer_id: "host-issuer",
      not_before: NOW - 10, not_after: NOW + 500)
    args = {trust: trust, order: order, saved_challenge: challenge, root_presentation: root, terminal_jws: terminal,
      host_checkout_jws: checkout_wire, expected_challenge_issuer_id: "host-issuer", clock_source_id: "test-clock", verified_at: NOW}
    {args: args, keys: keys, checkout: checkout, requirements: requirements, trust_args: trust_args}
  end
end
