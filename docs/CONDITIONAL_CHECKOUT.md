# Conditional Checkout delegation — 0.8.0 candidate design

Adopted AP2 v0.2.0 source remains `b4587ac1d055888a73b4b21750973cffba961793`.
This is an additive Ruby issuance API for the existing explicit
`ap2.checkout.single_merchant_multi_item` v1 profile. It does not relax old
profiles, add a general Schema engine, or establish real Issuer trust.

## Security proposition and responsibilities

An authenticated approval service issues an Open for one registered Agent key,
one merchant and 1–8 requirements, each with 1–8 candidate products and an exact
integer quantity. The Agent can close it only against an authentic merchant
Checkout that completely satisfies those requirements. All signed original
bytes are retained. The existing full verifier independently checks the result
against registered trust, the current order and Host challenge.

The application authenticates the person, obtains informed consent and purchasing
authority, protects the approved conditions and controls the Provider signer.
No boolean approval establishes consent. Provider key material is never passed
to the Agent. Agent and Merchant keys are independently registered, not trusted
because they appear in received tokens. Host owns challenge issuance, trusted
clock, current order, revocation, durable atomic consumption and execution.
SDK verification is evidence, never Host ALLOW or payment completion.

## Public API design

`ConditionalCheckout.issue_open(merchant:, requirements:, agent_public_key_pem:,
issued_at:, expires_at:, signer:, public_key_pem:)` returns immutable
`Open#root_presentation`. Merchant is `{id, name}`; requirements contain
`{id, quantity, acceptable_items: [{id, title}]}` with string keys. Input is a
protected application approval record, not untrusted Agent parameters.

`ConditionalCheckout.issue_closed(root_presentation:, checkout_jwt:,
trusted_issuer_public_key_pem:, agent_public_key_pem:,
trusted_merchant_public_key_pem:, expected_merchant_id:, audience:, nonce:,
verified_at:, signer:)` returns immutable `Closed` with original
`root_presentation`, `terminal_jws`, `closed_sd_jwt` and `checkout_jwt`.
It verifies Open signature, complete disclosure graph, schema subset, Agent
cnf, validity, Merchant signature and all quantity constraints before signing.
The signer receives frozen ASCII ES256 signing input and returns 64 JOSE bytes;
the supplied public key verifies the exact returned signature before success.
Signer network access, timeout and access control belong to the application.

`ConditionalCheckout.present(root_presentation:, terminal_jws:, checkout_jwt:)`
restores detached immutable original strings for transport/storage. It checks
bounded supported syntax and original-byte bindings, not authentication;
Merchant must use `InputBuilder.verify` / `verify_checkout` with independent
trust and Host inputs. The issuance object can be persisted as these three
strings; no claims or disclosures are reserialized during presentation.
Issuance/restoration failures raise a fixed redacted `ConditionalCheckout::Invalid`
without a cause. No partial claims, keys, nonce or raw tokens appear in errors.

## Wire contract, limits and completeness

Open uses ES256 root `example+sd-jwt`, one SD array commitment to Open content,
one to the merchant, and one per candidate. All candidates and constraints are
always disclosed; subset selection is not supported. Salts are random 128-bit
values. No omitted, extra, duplicate, unknown or decoy commitments are accepted.
The profile's original-byte, depth, graph, 8-line/requirement/candidate and amount
limits apply jointly. Quantity matching uses exact integral max flow by product
ID, including same-product separate rows. Unknown constraints fail closed.

Open carries `cnf.jwk`, `iat`, `exp`, two ordered constraints and
`vct: mandate.checkout.open.1`. Lifetime is positive and at most 7200 seconds;
all checks use explicit integer epochs and `iat <= now < exp`. Agent Closed
inherits Open `iat/exp` exactly, as required by this existing profile. Terminal
KB-SD-JWT has `typ: kb+sd-jwt`, `aud`, `nonce`, fresh `iat`, `sd_hash` of the
entire original Open SD-JWT including disclosures and trailing `~`, and one
inline Closed containing the exact merchant JWT and its SHA256 base64url hash.
There are no selective disclosures in this final Closed; its SD-JWT is exactly
`terminal_jws + "~"`. Audience and nonce come from the Host challenge and must
also be independently checked by the Merchant. Proof age is at most 300 seconds.

Receipt `reference` is base64url without padding of SHA256 of **only the final
Closed SD-JWT**, including its trailing `~`. It excludes the preceding Open
chain, includes any disclosure bytes in profiles that have them, and never hashes
compact JWT alone or reconstructed JSON. This profile has zero final disclosures;
reordering Open disclosures changes the Agent's root binding but not that rule.
Existing `CheckoutReceipt.sign/verify` use the explicit multi-item profile.

## Application outcomes and compatibility

After evidence verification, the application reserves/consumes the approval,
challenge and order transactionally and signs its explicit Success/Error outcome.
Authentic Success confirms the merchant's recorded result; authentic Error is
not automatic permission to replay. Retry requires current order/approval/nonce
policy. Missing Receipt, transport errors or uncertain commits remain pending;
reconcile saved operation IDs rather than repeat a purchase blindly.

Direct, old single-product defaults, InputBuilder saved formats, diagnostics,
Result/Evidence and Receipt contracts remain unchanged. No migration is required.
This new API explicitly selects the existing multi-item profile; no token can
select policy. Payment Mandates, budgets, repeated/split/multi-merchant purchases,
User Credentials, Rails and tax/shipping/discount calculation are out of scope.

## Acceptance and independent evidence

Required checks: public-only installed example from conditions through both
Receipt outcomes; 1/8 rows, candidates, varying quantities, repeated product rows;
shortage/excess, wrong merchant/Agent/Open/Checkout, authentic invalid orders;
signature/hash/disclosure tampering, unknown/missing/duplicate fields, bounds,
expiry/future/proof-age boundaries, audience/nonce mismatch, exact receipt hash
scope and wrong key/issuer/time/reference; existing complete regression.
Official Python SDK primitives and unmodified pinned Schemas must independently
verify Ruby output and produce Ruby-accepted signed input. Normative specification,
SDK behavior and stricter local rules are recorded separately; SDK shortage and
empty-candidate differences remain in MULTI_ITEM_INTEROP.md. Latest-HEAD Codex
review and the same candidate Gem installed on both supported Rubies are required.

Status: DESIGN_ONLY until implementation, independent comparison, package tests
and latest-HEAD review are recorded. No RubyGems push, public tag/Release,
production connection or actual payment is authorized by this task.
