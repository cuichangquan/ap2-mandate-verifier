# Phase 2-A E06-I — A2 source-only exit ledger and proposed A3 Host trust decision

**2026-10-13 JST · Issue [#75](https://github.com/cuichangquan/ap2-mandate-verifier/issues/75) · Owner A2 = code writing/static review only · Owner B = NOT APPROVED · NOT RUN · Phase 2-B HOLD**

Parent [#47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47); authorization ledger [#73](https://github.com/cuichangquan/ap2-mandate-verifier/issues/73). Pinned official AP2 v0.2.0: `b4587ac1d055888a73b4b21750973cffba961793`. Audited main: `50f4992dee524d6082b9b8148980ed7536e57acd`. All claims below are **static source observations only**, not runtime/CI, a production Host, a Gem, or a payment verification result.

## 1. Exactly what the merged A2 source does — and does NOT prove

| Source / merged PR | Code present | Actual success state / missing proof |
| --- | --- | --- |
| `research/phase2a_e06i/integrated_probe.rb` / [#74](https://github.com/cuichangquan/ap2-mandate-verifier/pull/74) and [#81](https://github.com/cuichangquan/ap2-mandate-verifier/pull/81) | Original research-only observer stages G0→G3; separate `inspect_a2_host_candidate` diagnostic added without changing `observe` | **Unrun**. Original observer always G4 HOLD on an otherwise surviving G0→G3 input. Host-only preflight does not perform G0 and has `completed_stages=[]`, `g1_admissible=false`, `evidence=nil` |
| `isolated_host_snapshot.rb` / [#77](https://github.com/cuichangquan/ap2-mandate-verifier/pull/77), [#81](https://github.com/cuichangquan/ap2-mandate-verifier/pull/81) | Strict bounded detached Host JSON; synthetic fixed Issuer A and tenant; explicit key+policy state for Issuer/Agent/Merchant; checkout/challenge/claimed nonce registry binding; known revoked REJECT before unknown HOLD | Every structurally valid candidate is still **HOLD**, `admissible?=false`. Digest + strings + `non_revoked` / `unique` claims do **not** prove a Host issuer registry, authentic revocation, durable CSPRNG issuance, or atomic uniqueness |
| `isolated_root_closure.rb` / [#74](https://github.com/cuichangquan/ap2-mandate-verifier/pull/74) | Isolated fixed-three-disclosure Root signed closure and local Open profile | Uses its own `Time.now.to_i`. No single authoritative `verified_at` across G1, G3, G4, G7. Code import/parity and clock changes require fresh review; **not in the previous A2 file-edit whitelist** |
| `isolated_agent_merchant_crypto.rb` / [#79](https://github.com/cuichangquan/ap2-mandate-verifier/pull/79) | Independent original-wire Terminal/Agent signature, Root `sd_hash`, aud/nonce, Closed/Checkout raw digest and Merchant ES256 checks | Takes caller-provided Open, Agent/Merchant keys, challenge and Host Checkout; signs/verifies **under supplied keys**, not trusted G1/G3 opaque results. Always `CryptoCandidate(HOLD,g4_success?=false,evidence=nil)`; compatibility/parity **not measured** |
| `schema_gate.rb` / [#74](https://github.com/cuichangquan/ap2-mandate-verifier/pull/74), `isolated_checkout_shape.rb` / [#78](https://github.com/cuichangquan/ap2-mandate-verifier/pull/78) | Separate pinned official Open/Closed + nested Merchant JSON Schema loader and separate exact Checkout JWT local-shape checker | No single Ruby invocation connects both checkers to one authenticated G4 output; shape-only `VALID` is not official Schema or G5 result |
| `isolated_checkout_semantics.rb` / [#80](https://github.com/cuichangquan/ap2-mandate-verifier/pull/80) | Checks fixed Issuer Merchant/SKU/quantity constraints and Host Checkout amount/status/currency/checkout tuple, challenge and Buyer equality | Inputs are candidate Hashes, not G5 success + same authoritative G1 snapshot. Always `SemanticsCandidate(HOLD,g6_success?=false,evidence=nil)`. No signed Checkout version claim is assumed; Host must bind version to **its own** original JWT-record association |
| G7 evidence-only | B1/B2 design exists | **No integrated evidence producer.** `valid_until` cannot be invented from a policy timestamp or from independently sampled clocks. Verifier Evidence would **never** be Host final ALLOW, nonce CAS, charge, inventory lock or receipt |

The PRs are **reviewed and merged**, but there has been **no Ruby or Python execution, no signed-fixture generation, no O1–O5 independent oracle run, no bounded CI, and no genuine G0→G7 positive** under A2.

## 2. Trust-boundary gap and stage ordering (must not be crossed with a caller-provided Hash)

```text
Independent Host source + enrollment / key-policy revocation / clock
  + durable challenge nonce issuance and frozen Checkout+Buyer binding
     │   [MISSING: provenance, replay domain / atomic uniqueness contract]
     ▼
G0 untrusted wire checks → G1 genuine immutable trusted Host snapshot
                             │ [CURRENT: A2 Host-only Candidate ⇒ HOLD]
                             ▼
G2 original Issuer signature → G3 complete original Root SD-closure
                             │ [CURRENT: isolated G3 still reads Time.now]
                             ▼
G4 original Agent Terminal+Merchant Checkout crypto
                             │ [CURRENT: caller-supplied keys ⇒ HOLD]
                             ▼
G5 pinned official Open+Closed+Merchant Schema AND
   independent authenticated Checkout local shape (SAME invocation)
                             │ [CURRENT: two unrelated standalone checks]
                             ▼
G6 Host current Checkout/Issuer constraints (same snapshot)
                             │ [CURRENT: candidate Hashes ⇒ HOLD]
                             ▼
G7 minimum finite valid_until, evidence-only or HOLD
                             │ [CURRENT: no authentic integrated result]
                             ▼
Host independently RECHECKS trust, Buyer, Checkout and one-time nonce CAS
  before deciding any authorization. This final Host operation is NOT
  supplied or authorized by the Ruby research Verifier.
```

**Forbidden shortcuts:** (i) promote self-reported Host key/policy or caller-supplied digest to G1; (ii) use `CryptoCandidate` as a G4 SUCCESS token; (iii) call old P1-3 monolithic Checkout verifier at G4 (it executes G6 comparisons before G5); (iv) declare official G5 VALID from Checkout local shape alone; (v) use `Time.now` in individual stages as a coherent Host verification clock; (vi) turn early G3/G4 profile rejects into G5 schema causal negatives; (vii) call a standalone `HOLD` result an integrated positive.

## 3. Proposed **future A3 scope**, explicitly NOT authorized by A2 or this document

Before new code or fixtures, the Owner must **separately decide and authorize** which bounded source/clock/hand-off adapters are in scope. Proposed independent authorization slices:

### A3-H — Authoritative research Host source and nonce evidence (request, not permission)

1. Identify an **independent Host-side synthetic issuer enrollment source** with pinned Issuer A key/thumbprint/provenance/profile/tenant and separately pinned Agent and Merchant trust; issuer-supplied `jwk`, `kid`, `iss`, presentation keys or the signed Root must not select Host trust. Declare where keys, policy IDs/versions and revocation *observation* came from; do not imply real issuer identity or actual live rotation support.
2. Define one atomic **frozen Host Checkout and challenge record** with tenant/id/version, original Merchant JWT raw bytes and durable association to that exact Checkout version; Buyer/account reference; challenge id, approved Agent at issuance, signed Terminal audience+nonce, finite issuance and expiry, and a single injected Host `verified_at`. Do not treat a Checkout JWT ID as a signed checkout version; the Host-origin association must be independently evidenced.
3. A synthetic **Host-verifier-wide nonce ledger / issuance-source contract** covering all tenants, sessions, past/consumed/expired/reissued challenges for the whole Terminal signed verification domain. Require CSPRNG ≥128-bit unpredictable nonce, durable atomic uniqueness and issuance binding; the signed Terminal currently does **not** authenticate tenant/session/challenge-ref, so per-session uniqueness is inadequate. A mere `unique=true` JSON field, SHA digest match, or plausible nonce length is not evidence. Reuse => REJECT; missing ledger/provenance => HOLD.
4. Distinguish **fixture-generated assertions**, actually independently checked Host-side evidence, and real production guarantees. A synthetic Host registry can prove only the bounded laboratory model; it cannot prove real-world key enrollment/revocation, bank accounts, merchant inventory, Buyer identity or replay prevention at a production Host.
5. Define a source/adapter and precisely enumerated new paths before coding. The Owner's A2 authorization is **not** an authorization to implement a new Host registry, fixture generator, persistence, global nonce CAS or to add files outside A2.

### A3-T — Single clock and immutable trusted stage artifacts (request, not permission)

1. Review explicitly whether `research/phase2a_e06i/isolated_root_closure.rb` may be changed to accept only an injected bounded `verified_at` (currently out of A2 whitelist); preserve complete Root disclosure closure and signed-time predicate parity. Do not weaken fixed profile to get the positive through.
2. Design non-forgeable, deeply immutable **internal stage result types** for G1/G2/G3/G4/G5/G6, bound to *the same* Host snapshot identity, original root/terminal/checkout wire digests, issued challenge and `verified_at`. A caller-created Hash labeled `VALID` must never satisfy a stage dependency.
3. Stage G4 crypto before G5 official Open/Closed/nested Merchant schema **and** separate local Checkout JWT shape; then G6 Host semantics. Each later stage must consume only the preceding genuinely authenticated result. Keep `first_reject_stage` a real causal stage, not a promise that downstream stages were visited.
4. G7 requires a reviewed finite `valid_until = min(`Issuer Open signed exp, Agent/Closed finite deadline or reviewed Host substitute, challenge expiry, all selected signer key/policy expiries, Host policy/TTL cutoff`)` using the **same** injected clock. No required deadline => `HOLD/evidence=nil`; no purchase `ALLOW`, nonce consumed, payment, Receipt or real Issuer identity claim.

### Suggested A3 authorization and review stop gates

- **NOT NOW:** code changes beyond A2, specifically any new Host source/nonce registry/fixtures or modification of `isolated_root_closure.rb`, must wait for **explicit new Owner A3 approval** naming exact paths and boundaries. Merely replying `OK`, merging this design doc, or receiving a Codex review is not that approval.
- **A3 if approved:** research Ruby/source-only edits plus static review initially, with prior legacy `p1_1/p1_2/p1_3`, `shared/**`, CI/workflow, production API, Gem, payment, real cloud excluded. If new paths or a fixture/runner become necessary, obtain an additional scope decision **before** creating/executing them.
- **Independent B:** [Issue #73](https://github.com/cuichangquan/ap2-mandate-verifier/issues/73) requires a **separate Owner approval B**, only after reviewed A-implementation. At most 13 agreed synthetic cases, one manually dispatched job (≤10min) on ubuntu-24.04, each process OS hard timeout 10s, size/depth limits and O1–O5 oracles. **Even tests run locally require separately scoped execution approval**; none is implicitly allowed by A2 or this document.
- **Evidence standard:** only a *performed* same-invocation G0–G6 synthetic positive plus correct G7 Evidence and independently checked representative first-reject stages, **after B**, can lift the specific integrated-research HOLD. It does not prove general AP2 or production safety, and never silently lifts parent #47 / Phase 2-B.

## 4. Decision needed

**Conservative recommendation:** keep A2 component source merged and **STOP before promoting any stage to SUCCESS**. Choose an independently pinned synthetic Host source and clock adapter under a newly scoped owner authorization **before** attempting a G1→G7 success path. Until then: `A2_SOURCE_MERGED / NOT_RUN / G1_PROVENANCE_UNPROVEN / G4_G6_NOT_WIRED / G7_NO_EVIDENCE / B_NOT_APPROVED / PHASE2B_HOLD`.

This document itself is **design-only** and asks for no execution, test, signer keys, fixture generation, workflow/CI, Gem/public API, GCP, payment or security-gate GO.
