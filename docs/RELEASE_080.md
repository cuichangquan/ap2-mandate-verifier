# 0.8.0 — Conditional purchase delegation through Receipt confirmation

Ruby approval services can issue Open Checkout Mandates for a registered Agent
key, one merchant and approved product choices/quantities. The Agent uses its own
signer to close a matching merchant-signed Checkout, then presents it to the
existing complete verifier. Both Success and Error Receipts can be authenticated.
Supports A/B×1 plus C×2, up to eight lines/requirements/candidates, overlapping
choices and repeated product rows. Provider private keys never enter Agent APIs.

## Short conditional purchase flow

Prerequisites: `require "ap2_mandate_verifier"`; an authenticated approval backend
has protected `approved_merchant` and `approved_requirements` (A/B×1 and C×2).
`provider_signer` stays in that backend; `agent_signer` belongs to the Agent and
`merchant_signer` to the Merchant. Their public keys are independently enrolled.
`checkout_jwt` is the original merchant-signed order. `trust` is the Host's
`InputBuilder.trust` result with the explicit multi-item profile, and `host_order`
is its independent current order. `now`, audience and nonce come from the Host's
trusted clock/challenge, not token claims. Persist approval/challenge/order state
transactionally; the following synthetic excerpt performs no purchase/payment.
`host_nonce` and `challenge_id` are fresh values from that Host, and
`host_audience` is its independently expected audience.

```ruby
m = AP2MandateVerifier
profile = m::ConditionalCheckout::PROFILE_REF
# Approval backend: only after authentication, consent and purchasing authority.
opening = m::ConditionalCheckout.issue_open(merchant: approved_merchant,
  requirements: approved_requirements, agent_public_key_pem: agent_public_key,
  issued_at: now, expires_at: now + 600,
  signer: provider_signer, public_key_pem: provider_public_key)
# Host stores its own current order and challenge, bound to the original Open.
inputs = {trust: trust, order: host_order, root_presentation: opening.root_presentation,
  host_checkout_jws: checkout_jwt}
saved = m::InputBuilder.prepare(**inputs, challenge_id: challenge_id, nonce: host_nonce,
  issuer_id: "host", not_before: now, not_after: now + 60)
# Agent: Provider private key/signer is not an input here.
closed = m::ConditionalCheckout.issue_closed(root_presentation: opening.root_presentation,
  checkout_jwt: checkout_jwt, trusted_issuer_public_key_pem: provider_public_key,
  agent_public_key_pem: agent_public_key, trusted_merchant_public_key_pem: merchant_public_key,
  expected_merchant_id: "shop", audience: host_audience, nonce: host_nonce,
  verified_at: now, signer: agent_signer)
wire = m::ConditionalCheckout.present(root_presentation: closed.root_presentation,
  terminal_jws: closed.terminal_jws, checkout_jwt: closed.checkout_jwt)
verified = m::InputBuilder.verify(**inputs, terminal_jws: wire.terminal_jws,
  saved_challenge: m::InputBuilder.restore(saved_challenge: saved),
  expected_challenge_issuer_id: "host", clock_source_id: "trusted-clock", verified_at: now)
raise "Stop: conditional verification failed" unless verified.success?
# Merchant explicitly declines under its app policy; evidence is not an ALLOW.
receipt = m::CheckoutReceipt.sign(closed_sd_jwt: wire.closed_sd_jwt, profile_ref: profile,
  issuer: "shop", outcome: "Error", error: "declined", error_description: "Application declined",
  issued_at: now, signer: merchant_signer, public_key_pem: merchant_public_key)
result = m::CheckoutReceipt.verify(jwt: receipt.jwt, closed_sd_jwt: wire.closed_sd_jwt,
  profile_ref: profile, trusted_public_key_pem: merchant_public_key, expected_issuer: "shop",
  not_before: now, not_after: now + 60, verified_at: now)
puts "Conditional verified=#{verified.success?}"
puts "Receipt verified=#{result.verified?} purchase_succeeded=#{result.purchase_succeeded?}"
```

Verified output with synthetic setup and the official installed 0.8.0 Gem:

```text
Conditional verified=true
Receipt verified=true purchase_succeeded=false
```

For a complete setup and both Receipt outcomes, run the installed
[standalone Ruby example](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/examples/conditional_checkout.rb):

```sh
gem install ap2_mandate_verifier --version 0.8.0
ruby "$(ruby -e 'puts Gem::Specification.find_by_name("ap2_mandate_verifier", "0.8.0").full_gem_path')/examples/conditional_checkout.rb"
```

## Contract, compatibility and verification

- [Public API, complete-disclosure rules, limits and responsibilities](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/CONDITIONAL_CHECKOUT.md).
- All Open candidates are disclosed; the final Closed uses the existing inline
  terminal profile. Receipt reference hashes only that original final SD-JWT,
  including trailing `~`, not the Open chain or compact JWT alone.
- Existing Direct, both profiles/defaults, saved InputBuilder formats,
  Result/Evidence/diagnostics, MRI 3.4.12/4.0.9 and dependency pins are unchanged.
- Latest-HEAD independent reviews, both MRI full regression/ordinary candidate
  installs and pinned official Python signature/Schema/hash/Receipt comparisons
  passed, including long-ID/title eight-row terminals. SDK high-level Closed
  helper's different SD form is explicitly unsupported; no validation is skipped.
- Authentication, consent, purchasing authority, enrolled trust/key lifecycle,
  durable replay prevention and order/payment execution remain application duties.
  Authentic Error does not automatically permit replay; missing Receipt or an
  uncertain effect stays pending until application reconciliation.
- No general AP2 conformance, real Issuer trust or production safety claim.
  Payment Mandates, recurring budgets, split/multi-merchant orders and User
  Credentials remain outside this profile.

Published **2026-11-01 06:01:31.103 UTC**. Published source:
`5a7394c1b98f000b321423e2c2f80d50b5157808`. Gem: **79,872 bytes**, SHA256
`6c07664e4291aa8bc025b152075869322411a0d99861e1267959f1794e99acec`.
All29 payloads and metadata match the approved artifact/source.
Tag `v0.8.0` identifies the published source, independently of later guide commits.
[Publication and new official-Gem measurements](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/POST_RELEASE_080.md).
