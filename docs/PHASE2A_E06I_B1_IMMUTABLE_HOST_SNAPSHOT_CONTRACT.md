# Phase 2-A / E06-I B1 — Host immutable snapshot and Evidence deadline contract

**2026-10-13 JST · Issue [#75](https://github.com/cuichangquan/ap2-mandate-verifier/issues/75) · `DESIGN_ONLY / NOT_RUN / NO_IMPLEMENTATION_APPROVAL / NO_CI_APPROVAL / PHASE2B_HOLD`**

Parent: [#47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47); authorization record: [#73](https://github.com/cuichangquan/ap2-mandate-verifier/issues/73); initial research candidate: [PR #74](https://github.com/cuichangquan/ap2-mandate-verifier/pull/74), merged at `bcd5685cf096594811a94a3f6b6100e6082e5c31`.

**This is an input/output design proposal, not a Ruby/Host implementation, signed-fixture experiment, G7 PASS or authority to execute anything.** Applies only to the fixed synthetic Issuer A, fixed two-hop, 3 SD-array slots, one Checkout/one Merchant/one SKU research profile; it must not silently become a general AP2 policy. Official v0.2.0 SHA remains `b4587ac1d055888a73b4b21750973cffba961793`.

## 1. Why a new Host contract is necessary

The existing isolated `research/phase2a_e06i/isolated_host_policy.rb` validates a canonical synthetic Host policy, then calls `policy.freeze`. Ruby `Hash#freeze` **does not deep-freeze** the nested JWK/array/string values; passing this policy or its children between G1/G4/G6 cannot itself prove an unmodified context. `verify_candidate!` obtains `Time.now.to_i`; isolated G3 and legacy P1-2 also read time separately.

Current Host fixture has `policy_digest`, `issuer_public_jwk`, `expected_agent_public_jwk`, `trusted_merchant_public_jwk`, `expected_aud`, `expected_nonce`, `host_checkout_jwt`, checkout ID, merchant/currency/amount expectations, and one `not_before/not_after` policy interval. It **does not supply** the complete Host-issued challenge/Checkout transaction/buyer+account/three-key trust lifecycle contract required for a G7 `VerifiedEvidence` under the minimal Verifier design. In particular the following are not proven by that policy:

- Immutable `challenge_ref`, challenge issue-time binding of Agent JWK thumbprint and buyer/account ref, finite `challenge_expires_at`.
- Durable `checkout_ref=(tenant_id,checkout_id,checkout_version)` and a Host assertion that the original signed Checkout JWT is from that exact durable record.
- Cross-referenced `challenge_checkout_ref`, and buyer/account reference equality between challenge/current Checkout/context.
- Separate Issuer **and** Agent **and** Merchant trust policy ID/version, explicitly active **and non-revoked** state (not merely revocation-known), and finite `not_after` for **each selected signer key and policy**.
- A single Host-supplied verification clock + reviewed expiry/skew/TTL limits; a stable snapshot across the whole invocation.

**Do not fabricate these fields from token claims, `policy_digest`, `freeze_epoch`, `Time.now`, or a successful signature.** Old E01-S evidence neither proves these fields nor transfers to new unexecuted isolated copies.

## 2. Proposed trusted input `G1Context` (internal, not a public Ruby API)

The Host prepares **one logical immutable transaction snapshot** before verification; all subrecords are from trusted Host storage, not supplied or selected by the Agent or an Issuer claim.

| Record (conceptual) | Required content and origin | Failure if incomplete |
| --- | --- | --- |
| `issuer_trust` | Host-enrolled Issuer identity/provenance, approved fixed `profile_ref`/version/scope/alg/ES256 public JWK and immutable key ID/thumbprint, explicitly active and **non-revoked at `verified_at`** for selected key **and** policy, policy ID/version, finite `not_before/not_after` | G1 `untrusted_issuer` / `incomplete_context` |
| `agent_trust` | Host-current approved Agent key/thumbprint, scope, policy version, explicitly active and **non-revoked at `verified_at`** for selected key **and** policy, finite key/policy expiry | G1 `incomplete_context` |
| `merchant_trust` | Host-approved Merchant key/thumbprint and Merchant ID/tenant/scope, policy version, **selected Merchant key AND policy each explicitly active and non-revoked at the shared `verified_at`**, finite key/policy expiry | G1 known-revoked: `REJECT/untrusted_signer`; unknown/stale: `HOLD/incomplete_context` |
| `challenge_record` | Host-persisted unique non-reusable `challenge_ref`, `expected_aud`, **CSPRNG-generated unpredictable `expected_nonce` (at least 128 bits of entropy; durable **Host-verifier-wide uniqueness across every tenant, session and challenge sharing the Terminal signed-verification domain**, including reissues and past/consumed/expired challenges)**, authorized Agent key thumbprint **frozen at issuance**, opaque `buyer_account_ref`, `challenge_checkout_ref`, finite `challenge_expires_at` | G1 `incomplete_context` (or G4 `expected_agent_mismatch` once genuine Root is authenticated) |
| `checkout_record` | Host-persisted `checkout_ref=(tenant_id,checkout_id,checkout_version)`, original Merchant-signed JWT bytes, same durable buyer/account ref, Merchant ID/status/currency/SKU/quantity/totals/amount expected facts, known provenance of JWT-to-record association | G1 `incomplete_context`, G6 `checkout_context_mismatch` |
| `clock_policy` | **One trusted `verified_at`** in epoch seconds and a reviewed finite time/skew/max-age/TTL policy; time evidence must not be sampled independently per stage | `invalid_time` / `incomplete_context` |
| `snapshot_identity` | Stable `host_snapshot_digest` and immutable record IDs/versions for issuer, agent, merchant, challenge and checkout | `incomplete_context` |

### Challenge nonce issuance and anti-relabeling (mandatory Host contract)

**Scope invariant:** The simplest safe candidate is **one never-reused nonce within the full Host-verifier verification domain** across all tenants and sessions; narrower scoping is allowed **only when the differentiating scope is cryptographically authenticated by the Terminal and verified as part of the frozen challenge binding**. The current fixed Terminal profile signs `aud`/`nonce`, **not** `challenge_ref`, tenant or session, so a tenant/session-only uniqueness claim is insufficient. Do not invent a Terminal extension; until its compatibility and crypto binding are separately approved, require the conservative Host-verifier-wide rule.

- **Uniqueness and entropy are separate requirements**: issue each challenge with a CSPRNG-generated nonce containing at least 128 bits of unpredictable entropy, then enforce a durable **Host-verifier-wide uniqueness constraint on the nonce independent of tenant or session** across *every* challenge that this Verifier could accept under the same Terminal signed-verification domain (`aud`, acceptable Agent signing keys, Root/Checkout binding) — including all issued, consumed, expired and reissued challenges for the entire replay-relevant history. **At least as broad as the signed verification domain**, since Terminal does NOT sign `challenge_ref`, tenant or session. Using `(tenant, session, nonce)` or `(challenge_ref, nonce)` as the sole uniqueness index is explicitly FORBIDDEN. Use an atomic global (or equivalent globally coordinated per-verifier-domain) uniqueness check to prevent concurrent challenge issuers from allocating the same nonce; on collision, regenerate before issuance, and never recycle the nonce when reissuing a challenge for the same Checkout **or for any other session or tenant**. If global coordination or a sufficiently broad durable issued-nonce registry is missing, `HOLD/incomplete_context`; the random collision probability alone is not a substitute for the required uniqueness contract. A unique `challenge_ref` by itself does **not** make a reused Terminal distinguishable.
- Persist an immutable binding among `challenge_ref`, `expected_nonce`, `expected_aud`, issuance-time Agent key thumbprint, `challenge_checkout_ref`, `buyer_account_ref` and expiry. G4 must check the Agent-signed Terminal's exact `aud` and `nonce` against that frozen record, and G6 must bind the record to the Host checkout/version. A previously signed Terminal matching a **different** challenge due to cross-session or cross-tenant nonce reuse must not be re-labeled as new evidence; if ambiguous, return `REJECT/ambiguous_challenge` or `HOLD/incomplete_context`, never success.
- **Host boundary**: consuming a unique nonce still requires durable atomic one-time challenge/nonce CAS and checkout-current-state rechecks. This contract defines the generation/uniqueness obligation; it does not claim the Ruby Verifier has implemented Host CAS or replay prevention.

### Selection and immutability

1. G1 selects **exactly one** applicable Host-approved Issuer profile and keys. Untrusted `kid`, `iss`, `jwk`, `jku`, `x5u`, token-supplied policy labels and presentation candidate key are **not** registration/selection authority. **Before G2/G4, require every selected Issuer, Agent and Merchant signing key AND its trust policy to be active, explicitly non-revoked and within its finite validity interval at the same `verified_at`.** Host-known revoked state => G1 `REJECT/untrusted_issuer` (Issuer) or signer-specific `REJECT/untrusted_signer`; unknown, stale, or unreachable revocation state => `HOLD/incomplete_context`/`verification_unavailable`. `active=true` or `revocation-known` does not establish **non-revocation**. The Host must supply the resolved revocation state, authoritative source and valid observation scope. Never postpone known revocation to the later Host CAS.
2. Take a **deep, detached** read-only copy (or equivalent immutable serialized form) of the entire approved context, including nested hashes, arrays, strings and key coordinates. Outer `freeze` alone is insufficient. If mutation or snapshot substitution can be observed, **HOLD**.
3. Bind `snapshot_identity` to all stage inputs, returned artifacts, raw Checkout JWT digest, and stage ledger. Keep a stable canonicalization definition for the Host record and digest, and reject ambiguous/duplicate-key inputs; a digest does **not** attest the Host record's provenance.
4. Require `challenge_checkout_ref == checkout_ref` as an exact tenant+ID+version tuple and challenge Buyer/Account ref equals Checkout and Host-current account ref. The signed Checkout JWT `id` must equal the trusted `checkout_ref.checkout_id` after merchant signature verification, at G6; Host must assert the JWT bytes belong to that record.
5. Require `Issuer-signed Root cnf.jwk == Agent host-accepted key == challenge-issued Agent thumbprint` using normalized EC P-256 public key material/thumbprints. The Host must not silently rewrite an old challenge when the Agent approval changes.
6. Record which finite `not_after` applies to **each** actual signer/key/policy; a general Host policy expiration alone is **not** proof that the Merchant or Agent trust entries remain valid.
7. Do not refresh or replace some subrecords mid-invocation. If coherent read/atomic snapshot semantics are not established, **STOP**; the Host later performs separate current-state CAS rechecks.

### Synthetic fixture strategy: requires later authorization

Keep the existing `synthetic-e01s` policy and prior tests **unchanged**. A later bounded E06-I implementation may propose a **separate, explicit** synthetic Host fixture with the new trust/challenge/checkout metadata and a documented versioned relationship between them. This must be reviewed for provenance and never passed off as real Issuer/Host enrollment or a production proof.

**Choice required before approving integration code:** either (A) build/review a coherent new E06-I synthetic Host snapshot capable of the full G7 contract, or (B) keep an intentionally partial observer that returns G1 `HOLD/incomplete_context` (or another correctly attributed partial status) without EVER emitting evidence. Do **not** stage a fake G7 positive from missing data. The one-run approval B cannot establish FULL positive until option A actually meets the contract.

## 3. Time and `valid_until` (G7 evidence-only)

Proposed earliest finite deadline (not a chosen duration):

```text
valid_until <= min(
  Issuer-signed Open exp,
  Agent-signed Terminal exp or reviewed finite Host bound,
  Agent-signed Closed exp,
  Host-issued challenge_expires_at,
  issuer_trust/key not_after,
  agent_trust/key not_after,
  merchant_trust/key not_after,
  Host policy/TTL cutoff,
  any other applicable signed/trusted finite limit
)
```

Every input cutoff must be validated for source, consistency, policy window and units. If Terminal exp is absent, require an **explicit Host-configured finite substitute** consistent with the signed iat and challenge; missing finite upper bound => `HOLD/incomplete_context`. A nominal `now + 1200`, E01-S `freeze_epoch`, or policy-only `not_after` cannot replace the missing deadlines.

- `verified_at` and reviewed skew are applied consistently to every stage. Signed `iat/exp` checks are not delegated to unrelated `JWT.decode` defaults without explicit policy; log the stage that actually made the decision.
- G7 must never claim `authorized`, `allow`, `payment_succeeded`, `nonce_consumed` or `not_revoked`. It can return **Evidence-only** only after all G0–G6 results are grounded and expiry is demonstrably finite.
- Expected evidence fields: `profile_ref`, immutable signer `trust_snapshot` keys and policy versions, `verified_challenge` with `challenge_ref`, Agent thumbprint, opaque Buyer/Account ref, audience and **hashed** nonce, `checkout_binding` with exact Checkout tenant/ID/version and original Merchant JWT SHA-256, bounded `valid_until`, checked-facts summary, and stage ledger. Do not emit raw nonce or private signing keys in public artifacts.
- When Host receives Evidence, it **must** independently recheck current trust/revocation/expiry, Buyer/context, challenge and Checkout version/JWT digest under atomic nonce and checkout CAS **before any purchase authorization**; verifier-only proof is never final Host authorization.

## 4. Static-review stop conditions and next approval gate

| Gate | Required to lift HOLD | Present status |
| --- | --- | --- |
| Host record completeness | A separately designed E06-I trusted fixture/source with **Host-verifier-wide** challenge nonce uniqueness/entropy across signed verification domains (including reissues and different tenants/sessions), tenant/checkout/version, account ref, and every signer key/policy's explicit non-revoked state and finite trust window | **UNPROVEN** |
| Immutability | Detached deep immutable context and unambiguous snapshot/hash derivation; no reloading/re-sampling between G1/G7 | **UNIMPLEMENTED** |
| Clock/finite TTL | Single `verified_at`, signed/trusted bound policy and explicit shortest deadline | **UNDECIDED / E07 HOLD** |
| G7 | Full G0–G6 run on same snapshot, all required evidence fields, and Host responsibilities explicitly separated | **HOLD** |

Code modifications to old `p1_1/p1_2/p1_3/E01-S/DC04/shared`, existing workflows, Host infrastructure, fixtures, tests, or any verification runs require **independent explicit scope approval**. Issue #75 and this design PR are **not** that approval.

## References

- [E06-I proposed integration order](PHASE2A_E06_INTEGRATED_VERIFICATION_ORDER_CONTRACT.md)
- [E06-I bounded Ruby Schema plan](PHASE2A_E06I_BOUNDED_RUBY_SCHEMA_INTEGRATION_PLAN.md)
- [Minimal Verifier trust/challenge/Evidence contract](PHASE2A_MINIMAL_VERIFIER_DESIGN.md)
- [Issuer fixed-profile trust acceptance](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md)
- [Current isolated synthetic Host policy](../research/phase2a_e06i/isolated_host_policy.rb)
