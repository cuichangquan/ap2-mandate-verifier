# Payment APIs — published 1.1.0

Published 1.0.0 established the Checkout-only API contract; [1.1.0 is now published](POST_RELEASE_110.md). These additive APIs do not change its arguments, defaults, profiles, accepted inputs, results, storage or Checkout Receipt references. The Gem is framework independent; Rails is optional.

## Supported profile and specification

`Payment::PROFILE_REF = "ap2.payment.single.complete.1"`: one immediate payment, ES256/P-256, SHA256, one Provider root and at most one Agent hop, full content. Root/terminal accepts inline content or exactly one two-element content disclosure. Issuance uses one content disclosure for root and inline terminal. No other commitments/disclosures, nested SD, hidden claims, decoys, re-delegation or unknown fields are accepted. The profile is selected by these APIs, never by received claims.

Adopted source: [AP2 b4587ac1d055888a73b4b21750973cffba961793](https://github.com/google-agentic-commerce/AP2/tree/b4587ac1d055888a73b4b21750973cffba961793). Upstream e1ea56db72a6385bce3e5c1112b3a56ce60acb43 has the same relevant specification, Schemas and Python SDK. Decisions follow payment_mandate.json, open_payment_mandate.json, payment_receipt.json, types/amount.json and agent_authorization.md, with SDK behavior compared separately.

| Reference | Exact SHA256 input, base64url without padding |
| --- | --- |
| Payment transaction_id | Original Merchant Checkout JWT bytes |
| payment.reference.conditional_transaction_id | Original Open Checkout SD-JWT bytes, including disclosures in original order and terminal `~` |
| Agent sd_hash | Original Open Payment SD-JWT bytes including terminal `~` |
| Payment Receipt reference | Final Closed Payment SD-JWT alone, including disclosures and terminal `~`; excludes Open and `~~` separator |

Do not hash parsed/rebuilt JSON, compact-only JWT or the entire chain. `Presentation.chain` removes the Open's terminal `~`, then joins with `~~`; separate original strings remain authoritative for storage/hashing.

Closed `vct` is `mandate.payment.1`; Open is `mandate.payment.open.1`. Integer `iat` and `exp` are mandatory in this stricter profile, `iat <= verified_at < exp`, maximum lifetime 600 seconds. Conditional terminal iat equals Closed iat, cannot predate Open, cannot be more than 300 seconds old, and Closed exp cannot exceed Open exp. No clock defaults or skew at expiry. Amount is an integer minor unit in the existing supported Checkout currencies (USD/EUR/JPY), within existing scoped amount bounds. Decimal/float/bool values reject. Payee is the exact verified Checkout merchant, including name. Instrument has id/type and optional description; full object equality applies.

Open requires exactly one each of amount_range (currency, max and optional min), allowed_payees, allowed_payment_instruments and payment.reference. The first three are supplied to issuance; reference is calculated from supplied original Open Checkout. Lists allow 1–8 unique entries. Optional fixed payee/payment_amount/payment_instrument must remain completely unchanged. During verification the reference is matched to the Open in the fully verified Checkout chain. Recurrence/budget, PISP, execution_date/risk_data, arbitrary constraints, other algorithms and partial disclosure reject explicitly through the redacted failure contract.

## Public APIs and independent inputs

All methods are under `AP2MandateVerifier`, all parameters are keywords. See [executable plain Ruby example](../examples/payment.rb) for full calls.

| Method | Required inputs and result |
| --- | --- |
| `Payment.details` | checkout_jwt, trusted_merchant_public_key_pem, expected_merchant_id, payment_instrument → immutable four-field payment Hash. Authenticates Merchant JWT and calculates amount/payee/transaction reference; does not authenticate consent or a Checkout Mandate. |
| `Payment.issue_direct` | payment, approved_payment, issued_at, expires_at, signer, public_key_pem → Presentation. Every payment field must equal the app's protected consent record. |
| `Payment.issue_open` | open_checkout_sd_jwt, constraints, fixed, agent_public_key_pem, issued_at, expires_at, signer, public_key_pem → original frozen Open String. App authenticates consent to conditions and the source of Open Checkout. |
| `Payment.issue_closed` | open_sd_jwt, payment, trusted_provider_public_key_pem, agent_public_key_pem, audience, nonce, verified_at, signer → Presentation. Verifies Provider, Agent binding, time and Open constraints. Full Checkout authentication occurs in verify; issuing alone grants no permission. |
| `Payment.present` | closed_sd_jwt, optional open_sd_jwt (default nil) → Presentation. Structural/binding checks only. |
| `Payment.verify` | closed_sd_jwt, checkout_mode (:direct/:conditional), checkout_inputs, expected_payment, trusted_provider_public_key_pem, verified_at; optional open_sd_jwt, expected_agent_public_key_pem, expected_audience, expected_nonce (all default nil) → Verification. Conditional requires all four optionals; Direct forbids them. |
| `Payment.reference` / `PaymentReceipt.reference` | closed_sd_jwt → frozen exact final-wire reference; structural validation, no authentication/authorization. |

Direct checkout_inputs is exactly the six `Buyer.verify` keywords; conditional is exactly the seven raw `verify_checkout` keywords. Both rerun complete existing Checkout verification at the same verified_at. Conditional raw inputs can be prepared using `InputBuilder.inputs`. Inputs are snapshotted before verification. The app must select expected Checkout, amount/currency/payee/instrument, keys, audience/challenge and time independently of received Payment data. Never calculate expectations by decoding received unverified Payment. Direct trusted consent backend may call issue_direct; a boolean from an Agent is not consent authentication.

`Presentation` exposes frozen open_sd_jwt (nil for Direct), closed_sd_jwt and chain. `Verification` exposes verified?, code (:payment_verified or :payment_verification_failed), immutable payment claims, reference and expires_at (nil on failure). It does not mint Checkout Evidence or an execution permit. Constructors are private. All issuance/preparation/presentation/reference failures, including missing/unknown keywords, raise redacted `Payment::Invalid < ArgumentError`, without cause. verify returns a failed Verification for missing/unknown keywords, malformed input, dependency/internal failures. Positional binding errors can raise. No failure distinguishes bad input from unavailable processing. Hold/reconcile uncertain signer outcomes before issuing again.

Wire limit is 32,769 bytes, one final `~` plus at most one content disclosure, decoded JWT body <=24,576 bytes; strict JSON duplicate/size/depth checks are reused. Checkout fields retain their existing bounds. No network/DB operations occur.

## Payment Receipt

`PaymentReceipt.sign` requires closed_sd_jwt, issuer, outcome (Success/Error), payment_id, issued_at, signer and public_key_pem. Success additionally requires psp_confirmation_id/network_confirmation_id; Error requires error/error_description. Opposite outcome fields are forbidden. Optional outcome fields default nil. IDs and issuer are nonempty strings <=512 bytes, error_description <=2,048 bytes. A fixed redacted `PaymentReceipt::Invalid` is raised on failure. Result exposes jwt/reference.

`PaymentReceipt.verify` requires jwt, closed_sd_jwt, trusted_public_key_pem, expected_issuer, expected_payment_id, not_before, not_after and verified_at. It authenticates ES256 JWT, exact outcome-specific fields, issuer/payment ID/reference and explicit time window: not_before <= iat <= verified_at <= not_after. Result exposes verified?, code (:payment_receipt_verified/:payment_receipt_verification_failed), outcome, payment_id, confirmation IDs, error and error_description; `payment_succeeded?` and `payment_rejected?` are both false on verification failure. Failure returns no claims. Receipt authentication does not re-authorize a Mandate or establish actual payment completion; it authenticates the selected issuer's reported outcome.

## Python/Schema differences and limits

- Schema const and normative text use `.1` vct suffix; stale descriptions omit it. Adopt const.
- Schema amounts/ranges are integer minor units; prose decimal examples are not accepted.
- Open reference is required by Schema contains; Python models allow missing reference. Ruby rejects it.
- Python preset payee matching prioritizes id and can ignore changed name/website; Ruby requires exact object. Unsupported preset PISP/risk_data reject instead of being ignored.
- Python admits broader timestamp numeric types/skew, other hashes, disclosure shapes and optional time. This profile intentionally does not.
- Python MandateClient.create always makes the content a disclosure even with empty metadata. Both complete content-disclosure and inline forms are accepted here. Its high-level chain parser fails to restore `~` for a disclosure-free root; when handling an external inline root use official verify_chain with separately parsed original segments. Ruby's issued root has a content disclosure. Interop tests use the official chain verifier, high-level MandateClient.verify for the issued disclosure-bearing root, and typed PaymentMandateChain.verify, not signature checks alone.
- Payment-specific status=Success/Error Schema wins over generic Receipt prose result naming. Ruby enforces mutually exclusive outcome fields. Python Receipt verification only checks reference-store membership; Ruby also requires independent issuer, payment ID and clock window.

## Application responsibilities and persistence

SDK verification is not final execution approval or payment success. User authentication/consent, key storage/enrollment/revocation, current order/trust policy, actual payment, durable one-use identity and atomic reservation/consumption belong to the app. Recheck them immediately before execution. No SDK object prevents replay across calls/processes. Persist original Open/final strings and exact Checkout inputs in protected storage; use present, then reverify with current external inputs. Never deserialize a successful Verification as proof. An authentic Error is not automatic retry permission. Missing/unverifiable Receipt or uncertain processing stays pending and requires reconciliation.

After installing published 1.1.0, run:

```sh
ruby -e 's=Gem::Specification.find_by_name("ap2_mandate_verifier", "1.1.0"); require File.join(s.full_gem_path, "examples/payment.rb"); PaymentExample.run'
```

All example keys/data/outcomes are synthetic. No live processor, Rails, database or network is needed.
