# Conditional Checkout delegation — published 0.8.0

Published 2026-11-01 06:01:31.103 UTC. The official 79,872-byte Gem and all29
payloads match source `5a7394c1b98f000b321423e2c2f80d50b5157808`.
[Publication verification and installed examples](POST_RELEASE_080.md).

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
Agent signing uses the existing terminal limits (24,576 decoded claim bytes and
32,768 compact bytes), accommodating the embedded original Merchant JWT.
Merchant/Direct signing retain 12,000 decoded claim bytes and 16,384 wire bytes;
Checkout text/count limits and all joint effective bounds still apply.

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

Status: published after separate Owner authorization; final review/CI/source and
distribution evidence are linked in POST_RELEASE_080.md. The preparation snapshot
remains in RELEASE_080_CANDIDATE.md. No production or actual payment is performed.

## Official-source comparison and independent results

On 2026-11-01 official main is `e1ea56db72a6385bce3e5c1112b3a56ce60acb43`.
GitHub compare from the adopted commit changes only CHANGELOG, CONTRIBUTING,
README and uv.lock; normative docs, Schemas and SDK code are unchanged. Current
[Checkout](https://ap2-protocol.org/ap2/checkout_mandate/) and
[Agent Authorization](https://ap2-protocol.org/ap2/agent_authorization/) pages
were also read. Adoption stays pinned, with no dependency/source upgrade.

`test/conditional_interop.py` uses the pinned official `sd_jwt.create/verify`,
`kb_sd_jwt.verify`, JWT sign/verify helpers, unmodified Open/Closed/Checkout/Receipt
Schemas, independent commitment traversal and SHA256. Ruby Open/Closed is
verified by Python. Official Python Open issuance plus official JWT helper inline
Closed signing is accepted by Ruby; both Receipt outcomes work in both directions.
Keys remain in memory and no runtime network or remote Schema fallback is used.

The official high-level `kb_sd_jwt.create` always discloses `delegate_payload`
through a commitment and emits `_sd_alg`, even with empty metadata. Its output is
tested unchanged as an unsupported-form rejection. We do not strip signed claims
or weaken the existing inline-terminal profile to accept it. The supported inline
form uses official JWT signing and the same normative claim/hash rules, validated
independently. Choosing a new selective-disclosure terminal profile is future work.
This is bounded interoperability, not all SDK helpers or general AP2 compatibility.

The initial Codex P2 on restoration completeness was fixed by sharing the exact
Root closure walker for structural restoration. Restoration still authenticates
neither Root nor Agent signatures; full merchant verification remains mandatory.
Negative tests sign terminals bound to malformed/missing/duplicate Root disclosures
and require restoration rejection. Package/source results and final review status
are in [release preparation](RELEASE_080_CANDIDATE.md).

## Handling non-success without replay

```ruby
case result.status # from InputBuilder.verify / verify_checkout
when :verified_research
  # Recheck current application authorization/order/trust; atomically reserve.
when :rejected
  # Decline this presentation; do not execute or issue a Success Receipt.
when :unavailable
  # Verification could not establish evidence; hold, diagnose and retry only
  # verification under application policy, without executing the order.
end
# Missing/unverified Receipt after submission: retain operation_id => :pending,
# reconcile the merchant's saved result; do not resubmit a purchase blindly.
```

Issuance `Invalid` similarly never means that an order was executed; a remote
signer error may have an uncertain signing outcome, so reconcile the application's
issuance record before reissuing. SDK operations here perform no payment side effect.
