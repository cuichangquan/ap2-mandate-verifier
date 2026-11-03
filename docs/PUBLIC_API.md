# Ruby SDK public API — 1.x

**Status: published 1.1.0; the original 1.0.0 Checkout contract below is preserved.**
This document defines the 1.x contract for the existing Checkout APIs.
The 1.0.0 release preserves the 0.8.0 runtime behavior, API names and accepted
formats. Exact distribution identity and validation are in
[the publication record](POST_RELEASE_100.md); the earlier
[preparation record](RELEASE_100_CANDIDATE.md) retains its historical status.

The SDK supports human-approved Direct orders and conditional Open → Agent Closed
delegation for the documented profiles. It runs in plain Ruby. Payment Mandates,
general AP2/Schema compatibility, real Issuer enrollment and application payment
execution are outside this contract. The adopted AP2 source remains
`b4587ac1d055888a73b4b21750973cffba961793`.

## Supported entry points

All names below are under `AP2MandateVerifier`. Require the Gem with
`require "ap2_mandate_verifier"`. Arguments are keywords unless shown otherwise;
the linked contracts specify their complete fields, exact Ruby types and limits.
No implicit coercion, trust discovery or default current clock is provided.

| Entry | Role and returned value | Detailed contract |
| --- | --- | --- |
| `ConditionalCheckout.issue_open` | Sign approved merchant/product/quantity conditions for one registered Agent; return `ConditionalCheckout::Open`. | [Conditional API](CONDITIONAL_CHECKOUT.md#public-api-design) |
| `ConditionalCheckout.issue_closed` | Check Open, Agent binding, Merchant Checkout and conditions; sign and return `ConditionalCheckout::Closed`. | [Conditional API](CONDITIONAL_CHECKOUT.md#public-api-design) |
| `ConditionalCheckout.present` | Restore original Open, terminal and Checkout strings with structural/binding checks; return `ConditionalCheckout::Closed`. This is not signature authentication. | [Conditional API](CONDITIONAL_CHECKOUT.md#public-api-design) |
| `Buyer.issue_closed` | Sign a Direct order whose original Checkout equals the app's approved original; return `Buyer::Issued`. | [Direct API](BUYER_DIRECT_CHECKOUT.md#public-apis-and-failures) |
| `Buyer.present_closed` | Preserve the Direct wire after structural checks; return a frozen String. This is not signature authentication. | [Direct API](BUYER_DIRECT_CHECKOUT.md#public-apis-and-failures) |
| `Buyer.verify` | Verify the supported Direct presentation against independently supplied keys, expected Checkout and time; return `Buyer::Verification`. | [Direct API](BUYER_DIRECT_CHECKOUT.md#public-apis-and-failures) |
| `CheckoutJWT.sign` / `.verify` | Sign a supported merchant-authored Checkout / authenticate it against an independent merchant key and identity; return `CheckoutJWT::Signed` / `CheckoutJWT::Verification`. | [Signing](MERCHANT_SIGNING.md#minimal-executable-example), [verification](BUYER_DIRECT_CHECKOUT.md#public-apis-and-failures) |
| `CheckoutJWT.es256_signer(private_key:)` | Return a signing callable over an application-owned OpenSSL P-256 private key. | [Signer contract](MERCHANT_SIGNING.md#minimal-executable-example) |
| `CheckoutReceipt.reference` / `.sign` / `.verify` | Calculate the exact final-Mandate reference / sign an explicit app outcome / authenticate a Receipt; return a frozen String / `CheckoutReceipt::Signed` / `CheckoutReceipt::Verification`. | [Receipt contract](MERCHANT_SIGNING.md#checkout-receipt-contract-and-specification-discrepancy) |

### Full Open → Agent Closed verification and input preparation

| Entry | Role and returned value |
| --- | --- |
| `InputBuilder.trust` / `.restore_trust` | Assemble a selected trust snapshot / restore original trust and selection strings; return `InputBuilder::Trust`. The app authenticates provenance and currentness. |
| `InputBuilder.prepare` / `.restore` | Prepare a versioned challenge record / validate and preserve its original bytes; return a frozen String. Neither operation issues or consumes a nonce. |
| `InputBuilder.inputs` | Assemble the seven complete-verification keyword inputs as a frozen Hash. It does not produce Evidence. |
| `InputBuilder.verify` | Assemble business inputs and run complete Open → Agent Closed verification; return `ResearchResult` or non-success `Result`. |
| `verify_checkout` / `verify_research` | Run the same complete Open → Agent Closed pipeline with the seven raw inputs below. `verify_research` remains supported without a deprecation warning. |
| `ResearchResult.verify` | Retained factory for that same pipeline and input contract. Prefer the module-level or InputBuilder entry for new integrations. |

The seven raw keywords are `trust_json:`, `selection_json:`, `host_json:`,
`root_presentation:`, `terminal_jws:`, `host_checkout_jws:` and `verified_at:`.
The first six are original Strings; `verified_at` is an independently supplied
integer Unix timestamp. These entries do not accept the separate Direct format.
See [business inputs and restoration](INPUT_BUILDER.md) and
[raw input fields](SUPPORT_CONTRACT.md#full-entry-and-required-inputs).

### Preserved partial-verification APIs

These published entries remain supported; they are not reclassified as private.
All return non-success `Result` values with `success? == false` and `evidence == nil`,
including when their limited check passes. They do not replace either complete
verification entry.

| Entry | Maximum meaning of a passing check |
| --- | --- |
| `verify(presentation_json:)` | JSON syntax only: `:unverified / :verification_not_implemented`. |
| `verify_root_signature(root_jws:, trusted_issuer_public_key_pem:)` | One Root signature, not disclosure closure or authority. |
| `verify_root_disclosures(presentation:, trusted_issuer_public_key_pem:)` | The existing single-product Root disclosure profile and signature. |
| `verify_purchase_binding(**inputs)` | The documented Root/Agent/Merchant purchase binding checks. |
| `verify_scoped_constraints(**inputs)` | The selected supported purchase constraints. |
| `verify_trusted_scoped_constraints(trust_json:, selection_json:, **inputs)` | Supplied trust selection plus scoped constraints; not the full Host challenge/order contract. |
| `verify_host_binding(**inputs)` | The supported Host binding checks, without minting successful Evidence through this legacy wrapper. |

Existing keyword sets, defaults and partial-pass codes are preserved. See the
[module entry definitions](../lib/ap2_mandate_verifier.rb) and the
[Result/Evidence contract](SUPPORT_CONTRACT.md#result-and-evidence).

## Result, object and failure contracts

Each API keeps its existing result convention. Do not call `success?` on every
returned object or infer authorization from an object merely being present.

| API family | Success | Non-success |
| --- | --- | --- |
| Complete Open → Closed verification | `ResearchResult`: `status == :verified_research`, `code == :scoped_research_verified`, `success? == true`, immutable Evidence. | `Result`: rejected or unavailable, `success? == false`, no Evidence. |
| `InputBuilder.verify` assembly | Enters the complete verifier. | Malformed assembly, including missing/unknown keywords: `:rejected / :invalid_host_context`. Dependency/unexpected assembly failure: `:unavailable / :research_verification_unavailable`. Core results keep their codes. |
| Other InputBuilder calls | Trust, String or input Hash as listed above. | Checked malformed business input raises `InputBuilder::Invalid`; argument-binding, dependency and unexpected exceptions can propagate. These methods do not promise a Result wrapper. |
| `Buyer.verify` | `verified? == true`, `code == :direct_checkout_verified`, checked claims. | `verified? == false`, `code == :direct_checkout_verification_failed`, no claims. Dependency/internal failures use this same code. |
| `CheckoutJWT.sign` / `.verify` / `.es256_signer` | The listed object or callable. | Redacted `CheckoutJWT::Invalid`. Verification does not return a false Verification object. |
| Buyer issuance/presentation; Conditional issuance/presentation | The listed object or original wire. | Redacted `Buyer::Invalid` or `ConditionalCheckout::Invalid`. |
| Receipt reference/signing | The listed String or Signed object. | Redacted `CheckoutReceipt::Invalid`. |
| Receipt verification | `verified? == true`; separately inspect `outcome`, `purchase_succeeded?` or `purchase_rejected?`. | `verified? == false` and both purchase predicates false; no claims. Codes: `:receipt_verification_failed`, `:receipt_issuer_mismatch`, `:receipt_reference_mismatch`, `:receipt_time_mismatch`. |

The four signing/presentation `Invalid` classes above inherit `ArgumentError` and
use fixed redacted messages without the original cause. A generic `Invalid` or
verification-failed code does **not** distinguish invalid data from unavailable
signing/dependency processing. Hold the operation; diagnose through protected app
observability. A remote signer may have completed signing before a transport
failure: reconcile the app's issuance record before issuing again.

Missing/unknown keywords to `verify_checkout`, `verify_research` and
`ResearchResult.verify` return `:unavailable / :research_verification_unavailable`.
Ruby positional-argument errors or invalid keyword expansion can raise before an
entry executes. Exceptions, process failure and missing results never authorize
an operation. Existing status/code meanings are preserved; human-readable error
or diagnostic wording is not a machine interface.

### Supported returned objects and constructors

| Type | Supported reads |
| --- | --- |
| `Result`, `ResearchResult` | `status`, `code`, `success?`, `rejected?`, `unverified?`, `unavailable?`, `evidence`, `diagnostic`. |
| `ResearchEvidence` | `[](field)` and `to_h`: the existing immutable Evidence v2 facts, including contract/profile identities and checked bindings. |
| `InputBuilder::Trust` | `trust_json`, `selection_json`. |
| `CheckoutJWT::Signed` | `jwt`, `checkout_hash`. |
| `CheckoutJWT::Verification` | `verified?`, `jwt`, `checkout_hash`, `checkout`, `profile_ref`. |
| `Buyer::Issued` | `closed_sd_jwt`. |
| `Buyer::Verification` | `verified?`, `code`, `checkout`, `checkout_hash`, `reference`, `expires_at`. |
| `ConditionalCheckout::Open` | `root_presentation`. |
| `ConditionalCheckout::Closed` | `root_presentation`, `terminal_jws`, `checkout_jwt`, `closed_sd_jwt`. |
| `CheckoutReceipt::Signed` | `jwt`, `reference`. |
| `CheckoutReceipt::Verification` | `verified?`, `code`, `outcome`, `purchase_succeeded?`, `purchase_rejected?`, `order_id`, `error`, `error_description`. |
| `Diagnostic` | `stage`, `field`, `reason`, `hint(locale: :en)`, `to_h(locale: :en)`, `[](key)`; `:ja` provides Japanese hints. |
| `InputBuilder::Invalid` | `diagnostic`, which may be nil if diagnostic construction fails. |

`Result.new(status:, code:, diagnostic: nil)` is retained. It accepts only
registered non-success status/code pairs and raises `ArgumentError` for unsupported
pairs. It cannot construct successful Evidence. Result/Evidence-producing object
constructors other than this non-success constructor are private: obtain those
objects from their listed factories, not `.new`, reflection or deserialization.
Exception classes are rescue targets, not proof objects. No exception message,
backtrace or mutable Ruby object identity authenticates a check.
These objects assume a trusted Ruby process; private construction is API
discipline, not a sandbox against hostile Ruby code or reflection.

Diagnostics are optional guidance. Success has no failure diagnostic; diagnostic
failure cannot change a verdict. Existing machine identifiers retain their meaning;
wording/translations and internal lookup-table layout are not frozen.
See [diagnostic semantics](DIAGNOSTICS.md).

## Profiles and defaults

Profile version and Gem version are separate. All three profiles below remain v1.

| Profile identifier | Selection and supported lifecycle |
| --- | --- |
| `ap2.checkout.single_merchant_sku` | Default for optional `profile_ref:` on InputBuilder trust, CheckoutJWT and CheckoutReceipt. Existing one-product Open → Agent Closed verification. |
| `ap2.checkout.single_merchant_multi_item` | Explicit selection for those APIs; implicit fixed choice of ConditionalCheckout. One merchant/currency, 1–8 lines, all candidate disclosures and exact quantity allocation. |
| `ap2.checkout.direct.single_merchant` | Fixed Buyer API profile; pass `Buyer::PROFILE_REF` explicitly to Receipt APIs. One merchant/currency and 1–8 exact-order lines. |

Supported profile constants include `TrustContext::PROFILE_REF`, `PROFILE_VERSION`,
`PROFILE_BODY` and `PROFILE_HASH`, and its corresponding `MULTI_PROFILE_REF`,
`MULTI_PROFILE_VERSION`, `MULTI_PROFILE_BODY` and `MULTI_PROFILE_HASH` constants.
`ConditionalCheckout::PROFILE_REF`, `Buyer::PROFILE_REF` and `Buyer::CHECKOUT_PROFILE`
are supported as well. Their names and existing v1 values remain stable, including
the constants used by the documented raw-input example. Profile definitions/hashes,
accepted shapes, bounds, original-wire reference rules and defaults are
compatibility-sensitive even when implemented by other internal constants.
See [multi-item limits](MULTI_ITEM_CHECKOUT.md) and
[Direct limits](BUYER_DIRECT_CHECKOUT.md#profile-and-limits).
No received claim selects trusted policy; unknown profiles and constraints fail closed.

## Persistence and trust boundaries

- Persist exact signed JWT/SD-JWT and disclosure strings. `ConditionalCheckout.present`
  restores its three original strings; `Buyer.present_closed` restores its one
  original wire. Neither authenticates a restored presentation.
- Persist InputBuilder preparation format `"1"` and original trust/selection JSON.
  Use `restore` / `restore_trust`; do not regenerate hashes or issue-time references
  to make changed state match. Restoration does not authenticate storage, establish
  freshness or prove an unused nonce.
- Receipt reference covers only the final original Closed SD-JWT: `terminal_jws + "~"`
  for the existing conditional profile, or the entire disclosed Direct wire with
  its terminal `~`. It is not the Open chain hash, compact-only JWT or rebuilt JSON.
- `ResearchEvidence#to_h` is an immutable inspection view, not a signed transport
  credential. There is no JSON/Hash/Marshal reconstruction API for authenticated
  Evidence, results, Trust or other checked objects. Persisted original wires must
  be verified again against current independent inputs.
- Signing callbacks receive frozen ASCII JWS signing input and return 64 binary
  JOSE ES256 signature bytes. The SDK verifies the returned signature with the
  independently supplied public key. The app owns signer access, timeouts, key
  custody and lifecycle; Provider signing material never enters the Agent API.
- The app authenticates users, consent, registry/keys/revocation, current orders
  and time. It rechecks authorization, atomically consumes/reserves state, handles
  duplicates and reconciles uncertain outcomes. The SDK performs no network, DB
  or payment operation. An authentic Error Receipt is not permission to retry;
  a missing or unverifiable Receipt leaves the application outcome unknown.

## Compatibility and internal boundary

The 1.x [versioning, maintenance and deprecation policy](POST_RELEASE_MAINTENANCE.md)
applies to these calls, types, machine meanings, profiles and persistence contracts.
The `research` names and syntax-only `verify` keep their current meanings.
Documented 0.8.0 API use needs no source migration. Dependency constraints must
allow 1.0.0; see [upgrading from 0.8.0](../README.md#upgrading-from-080).

Internal `verified_*!` handoffs are not supported ways to inject checked facts;
[the existing support contract](SUPPORT_CONTRACT.md#result-and-evidence) already
excludes them. Private helpers, unlisted validator/factory helpers, diagnostic
catalogs, internal constant layouts and research/test scripts are implementation
details, not extension hooks. Ruby visibility alone does not make them an SDK API.
This does not remove the published partial-verification entries above, their
observable error behavior, or the documented profile identities and bounds.

## Additive published 1.1.0 Payment APIs

The preceding 1.0.0 Checkout contract remains unchanged. New `Payment` and `PaymentReceipt` APIs have a separate [Payment contract](PAYMENT.md); they are available in 1.1.0 and later, not in 1.0.0.
