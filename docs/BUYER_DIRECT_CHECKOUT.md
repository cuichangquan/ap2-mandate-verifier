# Direct / Human Present Checkout — 0.7.0 published

This additive optional module implements Trusted Agent Provider approval of a
fixed merchant-signed order. Published at 2026-11-01 03:12:46.522 UTC; [publication record](PROJECT_STATUS.md#070-publication). Adopted source is AP2 v0.2.0,
commit `b4587ac1d055888a73b4b21750973cffba961793`; no source upgrade is made.
The first example is one office supply purchase; **multiple products and lines
are required and supported throughout issuance, presentation, merchant verification
and Receipt verification**. See the [runnable integration](../examples/direct_checkout.rb).

## Scope, roles and flow

1. Shopping Agent obtains the merchant's original Checkout JWT.
2. Trusted Surface backend calls `CheckoutJWT.verify` with an independently
   registered merchant public key and expected merchant identity. It checks
   current order state separately; this Checkout shape has no signed expiry.
3. Application authenticates the purchasing employee, checks purchasing authority,
   displays the verified products, quantities, currency and totals, and stores
   the approved **original JWT** in a protected approval record. Bind the page,
   authenticated session and approval transaction to that same record; protect
   against CSRF, stale orders and concurrent replacement.
4. Only that backend loads the record and calls `Buyer.issue_closed`. Its
   `approved_checkout_jwt` must equal `checkout_jwt` byte for byte. This contract
   detects substitution, but does not itself prove human identity or consent.
   There is no `approved: true` parameter. Never let Agent input populate the
   approval record, select the Provider signer, or call its signing endpoint.
5. Agent receives the approved issuance wire and calls `Buyer.present_closed`.
   It preserves the exact wire and both mandatory disclosures; no signing key
   is needed. Issuance and presentation are separate responsibilities.
6. Merchant calls `Buyer.verify` with independently enrolled Provider and merchant
   keys, exact current Checkout JWT from its order database, identity and clock.
   It rechecks order state and purchase policy, then atomically reserves the order
   before applying any effect. Gem verification is not a purchase permission.
7. Merchant explicitly supplies its application result to `CheckoutReceipt.sign`.
   Buyer calls `CheckoutReceipt.verify` with the same original presented wire and
   independently registered merchant key, issuer and explicit time window.
   Demo Success means synthetic application acceptance, never payment success.

## Public APIs and failures

`CheckoutJWT.verify(jwt:, trusted_public_key_pem:, expected_merchant_id:,
profile_ref: TrustContext::PROFILE_REF)` returns immutable `Verification` with
`verified?`, `jwt`, `checkout_hash`, deeply immutable `checkout`, `profile_ref`.
The default preserves the existing single-SKU shape; pass the existing multi-item
profile for multiple lines. Invalid input raises the existing redacted
`CheckoutJWT::Invalid`; it does not return partial authenticated claims.

`Buyer.issue_closed(checkout_jwt:, approved_checkout_jwt:,
trusted_merchant_public_key_pem:, expected_merchant_id:, issued_at:, expires_at:,
signer:, public_key_pem:)` returns immutable `Issued#closed_sd_jwt`. It rechecks
merchant signature and multi-item Checkout, approval-byte equality, integer epoch
and `0 < expires_at - issued_at <= 600` seconds. `signer.call` receives exact
ASCII JWS signing input and returns 64-byte JOSE ES256. The independently supplied
Provider public SPKI verifies the result before return. Remote signers own access
control, timeout and key lifecycle; Gem does not perform network I/O. Invalid
input, unsupported keys or signer failures raise redacted `Buyer::Invalid`
without a source cause. The same contract applies to `present_closed`.

`Buyer.present_closed(closed_sd_jwt:)` validates supported syntax, commitment
closure and embedded Checkout shape and returns a detached frozen original wire.
It does **not** authenticate signatures. Persist `Issued#closed_sd_jwt` unchanged
and restore by passing it to this API; never rebuild claims/disclosures. The
merchant must always call full `Buyer.verify`.

`Buyer.verify(closed_sd_jwt:, trusted_provider_public_key_pem:,
trusted_merchant_public_key_pem:, expected_checkout_jwt:, expected_merchant_id:,
verified_at:)` returns immutable `Buyer::Verification`. `verified? == true` means
all supported signature, commitment, schema subset, order-byte and time checks
passed. It exposes deeply immutable `checkout`, `checkout_hash`, `reference` and
`expires_at`. Failures return `code: :direct_checkout_verification_failed`, false
and no claims. Success code is `:direct_checkout_verified`. This new type does not
change existing Result/Evidence, their statuses or saved InputBuilder records.
Private Ruby constructors are API discipline, not a hostile-code sandbox.

For Direct wire use `profile_ref: Buyer::PROFILE_REF` with existing
`CheckoutReceipt.reference/sign/verify`. Other arguments, errors, result type,
Success/Error branch exclusivity, expected issuer and time-window checks stay
unchanged. Never infer application Success from a Gem verification result.

## Profile and limits

Direct profile `ap2.checkout.direct.single_merchant` version 1 is selected by the
API/explicit Receipt argument, never by an untrusted profile claim. Merchant
Checkout validation reuses `ap2.checkout.single_merchant_multi_item` v1 **without
changing its contract**. There are 1–8 distinct line IDs, repeated product IDs
are allowed, quantities are integer 1–1,000,000, amounts/products/sums are integer
minor units 0–9,007,199,254,740,991. One merchant and currency (USD/EUR/JPY),
empty links, exactly subtotal/total per line and order, no unsupported fields,
taxes/shipping/discount engine. Every line and arithmetic result is checked.
All existing text and wire limits apply jointly; see [③](MULTI_ITEM_CHECKOUT.md).
Direct has no Open requirements/candidates or max-flow allocation to evaluate:
the entire exact order is approved. Changed rows/quantities require new approval.

ES256/P-256 only. SD-JWT root `typ: example+sd-jwt` (the fixed SDK root type),
exact payload `{delegate_payload: [{"...": digest}], _sd_alg: "sha-256"}`.
A 2-element disclosure reveals one Closed object (`vct`, `checkout_hash`, `iat`,
`exp`, `_sd`), and a 3-element disclosure reveals its `checkout_jwt`. Both are
required, parent then leaf. Issuance generates independent cryptographic 128-bit
salts; input salt strings have 22–128 base64url characters. No decoys, omitted,
extra, duplicated or unknown commitments/claims are accepted. Presentation has
exact form `<root>~<closed disclosure>~<checkout disclosure>~`. No KB-JWT,
`cnf`, Agent signature, aud or nonce is accepted here. These are Open→Closed
binding concerns, not universal Direct requirements. Trusted Provider enrollment
is external; keys embedded in received data never select trust.

In the existing Open→Closed flow, the Provider-signed Open content endorses the
Agent's public key through `cnf.jwk`; that key verifies the terminal Agent
signature and its binding to the preceding original SD-JWT, expected audience
and nonce. Direct instead trusts the Provider signature over the already closed
order itself and needs no Agent key endorsement. In 0.7.0, Open issuance and
Agent signing were future work; published 0.8.0 adds those APIs separately in
[ConditionalCheckout](CONDITIONAL_CHECKOUT.md), preserving this Direct contract.
Choosing fewer disclosures remains unsupported.

Maximum entire wire 32,768 bytes; Checkout JWT 16,384; root payload 2,048;
decoded disclosure 24,576; JSON depth 24. Existing strict JSON/canonical base64url
and finite number checks apply. Limits combine; counts alone do not guarantee
that a wire fits. `iat <= verified_at < exp`, integer epochs in the existing
safe epoch range, maximum lifetime 600 seconds, no implicit clock/skew. Applications
own trustworthy clocks, order validity and shorter approval policy.

## Replay, durable state and receipts

Mandates are bearer authorizations for the exact order. Neither hashes nor nonce
comparison establish single use. Persist approval ID → original Checkout → issued
wire atomically, enforce unique approval issuance, and on merchant side enforce
UNIQUE(merchant, checkout ID) with current order/version and atomic state transition.
Return the saved outcome/Receipt for duplicates; do not repeat the effect. Record
`processing/unknown` before external effects and reconcile uncertain commits via
application order/payment status lookup, keeping them on hold instead of retrying.
The executable example demonstrates serialized duplicate handling and unknown
hold in memory; it is not durable across process restarts and is not production
DB integration. Real applications need transactional persistence and authorization.

Receipt reference is base64url(SHA256(**entire original presented SD-JWT**)),
including both disclosure bytes, order and terminal `~`. Never hash reserialized
claims, only compact JWT, an issuance with a different disclosure order or a
re-issued token with fresh salts. Reference syntax checks do not verify Provider
authority. Verify Mandate first and produce Receipt only for explicit application
outcomes. Receipt authenticity alone proves neither purchase nor payment.

## Compatibility, interoperability and acceptance

Existing two profiles, InputBuilder save/restore, Result/Evidence, old API defaults
and legacy Receipt terminal syntax are unchanged. Direct is a new independent
entry; existing `verify_checkout` continues to handle its prior Open→Agent Closed
contract only. Passing Direct wire to old Receipt/default profile rejects.
No dependency or Ruby support change. Compatible feature version is published 0.7.0.

`test/buyer_interop.py` uses the fixed official `sd_jwt.create/verify`, unmodified
Closed Schema, JWT helpers and independent SHA256/commitment computation.
Ruby issuance is verified by Python; Python issuance by Ruby, including eight
lines, multiple products, differing quantities, receipts in both directions and
wrong-key/substitution/expiry/reference negatives. The SDK issuance disclosure
order may differ; the test selects parent-before-leaf using original disclosure
strings, without reserializing claims or changing signatures, then hashes that
actual presentation. This explicit restricted order is a local profile rule.
The SDK high-level Checkout chain helper requires Open+Closed; it is not a Direct
validator. Our Direct implementation uses its independent root SD-JWT primitives.

Receipt normative `sd_hash` includes disclosures and terminal `~`; SDK
`MandateClient.get_closed_mandate_jwt` extracts compact-only, so its recommended
reference differs. We follow normative original SD-JWT hashing. Checkout Receipt
uses Schema `status: Success/Error`, not generic prose `result: success/error`.
Existing max-flow shortage/empty-candidate SDK disagreements remain documented in
[MULTI_ITEM_INTEROP](MULTI_ITEM_INTEROP.md); Direct has no Open allocation, and
compatibility regression continues to test those profiles. No checks are omitted
to force agreement with SDK.

Acceptance includes approval-to-Receipt example, 3/8-line flows and both outcomes,
repeated products, reordered separately signed orders, rejection of 0/9 lines,
duplicate line IDs, invalid quantities/prices/totals/currency/links, wrong keys,
expiry/future time, missing disclosures, malformed signed combinations and unknown
formats. Existing source and ordinary-install regressions run on MRI 3.4.12/4.0.9.
Latest-HEAD independent review and branch protections are required before merge.

Open issuance and Agent Closed generation/presentation were follow-ups at 0.7.0
and are now available in the separate 0.8.0 module. Selective-disclosure profiles,
User Credentials, multiple merchants, split orders and continuous autonomous buying
remain follow-up candidates. Agent-to-Agent delegation is outside current AP2 scope,
not declared permanently forbidden. Real Issuer trust, actual demand, generic AP2
support and production safety are not established by synthetic test success.
Gem publication and its separately approved tag/Release are recorded in the
publication record. No deployment, real payments or real credentials are exercised.
