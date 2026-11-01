# 0.7.0 — Direct buyer Checkout through Receipt confirmation

Trusted Surface backends can verify a merchant Checkout before human approval,
issue a Provider-signed Closed Mandate, and let the Shopping Agent present it.
Merchants can verify that Direct Closed-only presentation and return an explicit
application outcome Receipt. One merchant, 1–8 lines, multiple products and
quantities are supported end to end. Existing Open→Agent Closed APIs and both
legacy profiles keep their contracts.

## Short buyer-flow sample

Prerequisites: `require "ap2_mandate_verifier"`; `checkout_jwt` is the merchant's
original JWT, `merchant_public_key` and `provider_public_key` are independently
enrolled public keys, `provider_signer` is accessible ONLY to the Trusted Surface
backend, and `merchant_signer` belongs to the merchant. `now` is a trusted epoch.
After authenticating the user, checking purchasing authority and displaying the
verified order, the application stores `approved_checkout_jwt` in its protected
approval record. Never populate that record from an Agent approval boolean.
The merchant independently loads `current_checkout_jwt` from its order database.

```ruby
c = AP2MandateVerifier::CheckoutJWT
b = AP2MandateVerifier::Buyer
r = AP2MandateVerifier::CheckoutReceipt
checked = c.verify(jwt: checkout_jwt, trusted_public_key_pem: merchant_public_key,
  expected_merchant_id: "shop", profile_ref: b::CHECKOUT_PROFILE)
issued = b.issue_closed(checkout_jwt: checked.jwt, approved_checkout_jwt: approved_checkout_jwt,
  trusted_merchant_public_key_pem: merchant_public_key, expected_merchant_id: "shop",
  issued_at: now, expires_at: now + 60, signer: provider_signer, public_key_pem: provider_public_key)
wire = b.present_closed(closed_sd_jwt: issued.closed_sd_jwt)
verified = b.verify(closed_sd_jwt: wire, trusted_provider_public_key_pem: provider_public_key,
  trusted_merchant_public_key_pem: merchant_public_key, expected_checkout_jwt: current_checkout_jwt,
  expected_merchant_id: "shop", verified_at: now)
raise "Stop: Direct verification failed" unless verified.verified?
# The merchant app explicitly declines; verification never implies payment success.
receipt = r.sign(closed_sd_jwt: wire, profile_ref: b::PROFILE_REF, issuer: "shop", outcome: "Error",
  error: "declined", error_description: "Application declined", issued_at: now,
  signer: merchant_signer, public_key_pem: merchant_public_key)
result = r.verify(jwt: receipt.jwt, closed_sd_jwt: wire, profile_ref: b::PROFILE_REF,
  trusted_public_key_pem: merchant_public_key, expected_issuer: "shop",
  not_before: now, not_after: now + 60, verified_at: now)
puts "Direct verified=#{verified.verified?}"
puts "Receipt verified=#{result.verified?} purchase_succeeded=#{result.purchase_succeeded?}"
```

Verified output with synthetic setup and the official installed 0.7.0 Gem:

```text
Direct verified=true
Receipt verified=true purchase_succeeded=false
```

The [complete runnable example](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/examples/direct_checkout.rb)
also demonstrates duplicate approval/order handling and unknown-outcome holds.
Its in-memory records are illustrative; production needs durable transactions.

## Contract, compatibility and verification

- [Buyer APIs, original-wire/disclosure/time limits and responsibility boundaries](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/BUYER_DIRECT_CHECKOUT.md).
- Provider trust, human authentication/authority, protected approval records,
  persistent order uniqueness and atomic state transitions remain app duties.
  Direct does not require an Agent key/aud/nonce. Open→Closed key binding remains separate.
- Receipt references include both original disclosures and terminal `~`; compact-only
  SDK helper hashes differ and are rejected. The fixed SDK high-level chain helper
  requires Open+Closed, so Direct interoperability uses its root SD-JWT primitives.
- MRI 3.4.12/4.0.9, fixed dependencies, legacy Result/Evidence and saved data are
  unchanged. Latest-HEAD independent reviews, full regression, bidirectional official
  Python SD-JWT/Receipt comparisons and 3/8-line acceptance checks passed.
- No generic AP2 conformance, real Issuer trust, purchasing demand or production
  safety is established by synthetic tests. Open issuance/Agent Closed creation,
  real payments and production deployment remain outside this release's supported flow.

Published at **2026-11-01 03:12:46.522 UTC**. Published source:
`9b4b78a7ed9aa95e7d35e01a64efc1281ba95be3`. Gem: **64,000 bytes**, SHA256
`baab8c68355b5e6c9351e7d86a836fab50652cdad662bbc99d1676c5e6134447`.
Tag `v0.7.0` identifies that source, independently of later guide/demo commits.
[Publication and post-release verification](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/POST_RELEASE_070.md).
