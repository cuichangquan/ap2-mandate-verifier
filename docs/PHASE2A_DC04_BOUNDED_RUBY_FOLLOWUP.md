# Phase 2-A DC04 — bounded fixed-Issuer Ruby candidate (Issue #54)

**Research only; AP2 v0.2.0 pinned at `b4587ac1d055888a73b4b21750973cffba961793`.**
**Phase 2-B / Gem / production Checkout / Host challenge CAS / receipt / payment: HOLD.**

## Why a separate resolver exists

DC04 [PR #53](https://github.com/cuichangquan/ap2-mandate-verifier/pull/53) produced three genuine,
independently checked signed presentations. The *legacy* P1-1 verifier rejected even
FULL with `unsupported array disclosure location`. The legacy RED/HOLD is real,
not a successful hidden-constraint negative.

This change introduces `research/phase2a_dc04/fixed_issuer_verifier.rb`, an
**opt-in exact-shape experiment**. P1-1 remains unchanged. The P1-2 / P1-3
offline verification modules accept *only* the original P1-1 resolver or the
named DC04 candidate, never arbitrary injected resolvers. They continue to
check holder key, Terminal signature / `sd_hash` / aud / nonce / time and
signed Merchant Checkout JWT / Host amount, while the DC04 candidate checks
the issuer's Root signature and disclosure graph.

## Strict signed wire profile

The Root JWS is signature-verified against the fixture's separately trusted
Issuer public JWK; header key selection is forbidden. Its accepted commitment
locations, all array-item disclosures, are **exactly**:

1. `$/delegate_payload/0`
2. `$/delegate_payload/0/disclosed/constraints/1/allowed/0`
3. `$/delegate_payload/0/disclosed/constraints/0/items/0/acceptable_items/0`

Root contains exactly one Open mandate with precisely two **ordered**, directly
visible constraint containers, one Merchant and one required SKU, exactly one
nested selective array item at each allowed location. Disclosures are bound to
each signed digest (SHA-256 over original base64url disclosure bytes). No
unknown object `_sd`, other placeholder path, object disclosure, unconsumed
disclosure, decoy, duplicates, or unbounded nesting. Unknown signed values in
the resolved mandate are rejected against the exact fixed-issuer claim shape.

Signature failure, profile mismatch, incomplete disclosure, malformed
serialization and external Host binding failure are distinct reject reasons.
Incomplete signed Merchant[0]/SKU[0] specifically raises
`incomplete_disclosure: missing disclosure`; it cannot be mistaken for
schema cardinality failure or `unsupported array disclosure location`.

## Signed independent negative controls

The generator uses **ephemeral** Issuer/Agent/Merchant private keys in CI only,
never persists them. Existing FULL/M0/S0 maintain the same signed Root JWS and
differ in signed-referenced disclosure presentation and matching genuine Agent
Terminal signatures. The follow-up also produces:

- An **issuer-signed unexpected nested commitment location** by making
  `constraints[1]` selective while retaining the nested Merchant[0] element;
  fully disclosed Open claims remain identical.
- A **genuinely signed issuer decoy** with the pinned official SDK's
  `add_decoy_claims=True` option. The candidate must not ignore it.
- Locally mutated duplicate/empty/tampered disclosures and JWS, wrong Issuer,
  Agent, `sd_hash` presentation and Host checkout; these are **not** counted
  as genuine signed missing-constraint evidence.

O1–O4 independent Python crypto, raw signed-graph and exact official Open Schema
remain separate from O5 legacy observations and O6 candidate Ruby gate. A green
diagnostic CI alone is not Phase 2-B approval; the Ruby FULL positive must succeed
before M0/S0 count as disclosure-completeness negatives.

## Exit conditions and recorded boundaries

This PR initially provides **candidate code, not a claim of measured success**.
Only after scoped GitHub Actions runs on the current PR HEAD, the resulting
public-only content-addressed evidence is examined, and latest-HEAD Codex review
is completed without P1/P2 can Issue #54's narrow experiment be considered done.

The 7-day artifact is not durable issuer replay evidence. This verifies only
synthetic fixed-Issuer signed examples and not generic AP2, arbitrary SD-JWT,
multiple merchants/SKUs, issuer discovery, revocation, Host nonce-CAS,
HC06/receipt or real payment authorization. Parent Issue #47 and Phase 2-B stay
OPEN/HOLD until separately justified.
