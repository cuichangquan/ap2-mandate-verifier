# Phase 2-A / E01-S — Minimal synthetic Host trust adapter contract

**2026-10-13 JST — DESIGN ONLY / NO EXECUTION AUTHORIZATION / all IP01–IP03 NOT RUN**

- Parent: [#47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) (OPEN)
- Dedicated scope: [#66](https://github.com/cuichangquan/ap2-mandate-verifier/issues/66) (EXECUTION NOT APPROVED)
- Approved *design record*: [PR #65 E01-S 3-case plan](PHASE2A_E01S_SYNTHETIC_ISSUER_TRUST_PROBE_PLAN.md)
- Official AP2 **v0.2.0 pinned at `b4587ac1d055888a73b4b21750973cffba961793`**
- This document **does not implement or approve** fixtures, code, CI, Host enrollment, Phase 2-B, Gem/API or payments.

## 1. Narrow target, actual repository baseline

An independent synthetic Host policy must distinguish (1) a successfully signed token by a **non-allowlisted** Issuer B, and (2) a genuinely signed alternative Root layout from allowlisted Issuer A. Merely giving Ruby the wrong public key, or observing an early structural rejection, **does not prove a Host trust gate**.

The current `research/phase2a_dc04/fixed_issuer_verifier.rb` exposes `verify_full_root!(wire, trusted_jwk:)` and `verify!(**context)`. It verifies against a *caller-supplied public key* and enforces its hard-coded Root grammar and three allowed SD array paths. **There is no independently enrolled issuer identity, registry, or policy-version comparison**. The `research/p1_3/checkout_binding_research.rb` → `research/p1_2/two_hop_research.rb` route deliberately permits **only the named DC04 Root resolver**, so **do not inject arbitrary resolver modules or change that guard**.

Existing *reuse candidates*, not E01-S observations:
- `research/phase2a_dc04/generate_and_observe.py` generates an SDK-issued A-signed FULL and an **A-signed `unexpected_nested_path`** with an extra signed SD slot at `$/delegate_payload/0/disclosed/constraints/1`. Its independent oracle currently checks that the fully resolved Open has the same contents as FULL, and DC04 calls it a genuine signed layout negative. This is a promising IP03 form, subject to **new per-case signature, official-schema and complete-binding rechecks**.
- `research/phase2a_dc04/observe_fixed_ruby.rb` demonstrates FULL limited-positive and layout rejects, but **cannot stand in for Host trust provenance**.
- `.github/workflows/phase2a-dc04-nested-elements.yml` is a **20-minute**, `ubuntu-24.04` example; it is **not an E01-S workflow** and must not be triggered as a substitute for approval.

## 2. Trust sources (no self-authorization)

| Input | Origin and trust | Allowed use |
| --- | --- | --- |
| `host_policy_snapshot` | **Separate synthetic Host role**; one immutable, read-only snapshot prepared and frozen *before* any Root issuance | Sole authority for allowed A public key thumbprint, scope, immutable `profile_ref`/`policy_version`, closed grammar, activation/expiry and allowed usages |
| `candidate_issuer_public_jwk` | Supplied with synthetic case; **untrusted** | **Only** identify the claimed signing key for comparison and independently verify its real signature; never add the key to Host policy |
| Root SD-JWT, protected JOSE, `iss`/`kid` and any `policy_version` claim | All untrusted pending verification | `kid` and `iss` at most lookup hints; no dynamic registration, version election, JWKS URL or network key download |
| `expected_agent_jwk`, Host aud/nonce, Merchant public JWK, original signed checkout JWT, checkout identity/currency/amount | **Separate fixed Host test context** | Existing DC04/P1-3 2-hop and Checkout binding; no token-originated rewrite |
| Pinned official schema + Ruby source HEAD | Independent pinned source evidence | O4 schema validation and O5 precise stage/reason identification |

**Freeze order required for a later approved harness**:
1. Set immutable source constants: official SHA, `tenant_scope`, `checkout_use_case`, `profile_ref`, `policy_version`, exactly three allowed signed slot paths, key purpose/algorithm, bounds and finite validity.
2. Ephemerally generate A public/private pair **in memory only**; form Host A-only policy **using A's public key**, canonicalize deterministically, record digest; write **one** write-once Host snapshot plus freeze event **before** calling the official issuer for any Root.
3. Ephemerally generate B (or generate it earlier without changing step 2); independently create signed IP01/IP02/IP03 wires. **Never revise** the frozen Host allowlist for B or alternate layout.
4. On each case, read the Host snapshot from a **separate input** and verify the frozen digest and ordering log; do not derive it from any token header, fixture `trusted_issuer_public_jwk`, or parsed claims.

This ordering is reproducible *synthetic evidence*, not a cryptographically certified real Host approval, durable registry, key revocation system or real-Issuer identity proof. A digest by itself **does not** prove the snapshot was approved independently.

**Snapshot digest calculation:** canonicalize the Host record with a fixed UTF-8/sorted-key JSON encoding, **excluding the `policy_digest` field itself**, hash those exact bytes with SHA-256, and separately assert the manifest's recorded bytes and digest match the read-only snapshot. This is only an integrity/replay check; it is not a signature, an external authorization record, or proof of when the snapshot was created. The proposed future harness must record and assert its *actual* freeze event before any issuer signing call.

### Frozen policy shape — a proposal, not a Ruby public API

| Required field | Contract |
| --- | --- |
| `tenant_scope`, `checkout_use_case` | Fixed nonempty exact strings, provided out of band, no implicit defaults |
| `issuer_ref` | `synthetic-e01s-issuer-A`; not inferred from token `iss` |
| `issuer_public_jwk` / `thumbprint` | Public **EC P-256** JWK, ES256 verification use only; reject `d`, private fields, unknown key types, unsupported keys |
| `profile_ref`, `policy_version`, `policy_digest` | **One active Host-selected** closed-grammar policy; immutable. Version is **not claimed to be signed by official AP2** |
| `active`, `not_before`, `not_after` | Finite UTC seconds and trusted-time snapshot; fail closed on absent/stale/revoked/ambiguous selection |
| `signed_root_grammar` | Root/JOSE allowlist, exactly one Open, closed Constraints types/order/cardinality, permitted SD slots, no `_sd`/unknown/decoy/unused/duplicate |
| `limits` | Bounded total input, signed Root, disclosures, signed-depth, elements, time and process resources (see §6) |

To calculate an EC JWK thumbprint, use the **RFC 7638** canonical public members (`crv`, `kty`, `x`, `y`) with a defined encoding and SHA-256; **do not** hash arbitrary JSON serialization or trust a caller-provided thumbprint without recomputation. For active-policy selection there must be **exactly one** matching policy; no fallback to previous versions or hinted keys.

## 3. Minimal proposed interfaces and responsibilities (NOT IMPLEMENTED)

**Only after separately recorded execution authorization in #66**, consider **new files** under `research/phase2a_e01s/`:

| Proposed file | Single responsibility |
| --- | --- |
| `synthetic_host_policy.rb` | Read a *pre-frozen Host snapshot*, strict-parse/validate, compute canonical public-key thumbprint, test scope/time/status and permit A only |
| `trust_probe.rb` | Narrow stage machine: bounded original wire → Host key gate → issuer signature → Host signed-grammar gate → **existing** `AP2DC04FixedIssuerResearch.verify!(**context)` |
| `generate_and_oracle.py` | Pinned SDK genuine signatures for exactly 3 cases and independent O1–O4; never reuse Ruby's resolved payload as independent proof |
| `observe_ruby.rb` | Invoke one fixed adapter for all 3 cases and collect O5 exact stage/cause plus existing verifier result |
| `.github/workflows/phase2a-e01s-trust-probe.yml` | **Only if explicitly approved**: scoped single Linux job, hard timeouts, read-only checkout, narrowly captured public evidence |
| `docs/PHASE2A_E01S_OBSERVATION.md` | Record only *actual, separately authorized* signed outcomes; NEVER prefill PASS |

**Do not edit** `research/phase2a_dc04/fixed_issuer_verifier.rb`, `research/p1_2/two_hop_research.rb`, `research/p1_3/checkout_binding_research.rb`, existing CI workflows, or Gem/public API to add this test. If a truly necessary change arises, **STOP and rescope/reapprove**.

**Time-source limitation to review:** The existing DC04 verifier and `AP2TwoHopResearch.verify!` call `Time.now` internally (including Root, Terminal and Closed checks). A Host adapter's single frozen `trusted_clock_snapshot` **does not freeze these existing Ruby reads**. The future harness must log the Host snapshot and Ruby execution wall-clock interval, generate timestamps with enough validity margin for the full bounded run, fail closed if any boundary/expiry becomes ambiguous, and explicitly state this is **not same-instant/TOCTOU-proof Host time enforcement**. Do not monkey-patch global `Time.now` or claim a single clock covers the existing verifier; if exact clock injection is required for the E01-S claim, STOP and separately approve changing scope.

The adapter's internal input notion (not a public API) is:
- `host_policy_snapshot:` independent immutable Host record and digest.
- `candidate_issuer_public_jwk:` untrusted per-case signer public key; **not** the trusted DC04 issuer key.
- `chain:` original `[root_wire, terminal_wire]` bytes.
- `host_context:` separate pre-fixed Agent/Merchant/Checkout/aud/nonce/buyer/tenant expectations.
- `trusted_clock_snapshot:` fixed timestamp and explicit skew/expiry rules.

The adapter may use an untrusted case-supplied public key to compute a thumbprint and to allow O1 independently to check **B with B's key**. Only **after** matching the Host's A-only policy may it pass the **Host policy's own A JWK** as `issuer_jwk:` into DC04. It may **never promote** the case-supplied B JWK, token embedded JWK or `kid` into DC04's trusted key.

## 4. Observable stage contract

Proposed stage names are **new synthetic adapter labels**, not currently implemented Ruby return codes:

| Stage | Fail-closed precondition | Proven if reached |
| --- | --- | --- |
| `S0_PREAUTH_BOUNDS` | Strict original serialization/JSON duplicate-key/JOSE checks, finite-size limits before expensive work | Only bounded parse; **no signature claim** |
| `S1_HOST_KEY_POLICY` | Host snapshot digest/scope/purpose/time/active single policy; calculate candidate key thumbprint and exact-match frozen A key | Allowed synthetic key selected or `UNTRUSTED_ISSUER`. An IP02 S1 reject must be **paired with independent O1 B-signature VALID** |
| `S2_ISSUER_JWS` | Verify Root **original compact JWS signing input bytes** using the Host A key (ES256) without reserializing | Root signature valid with allowed A |
| `S3_HOST_SIGNED_GRAMMAR` | Parse **the already verified signed Root** plus original Disclosure bytes; enumerate every signed SD path/slot and reject unknown paths, `_sd`, decoy, missing/unused/repeated/ambiguous digest and unknown authority fields against the pre-frozen grammar | IP03 rejection attributable to specific signed path and unchanged A-only policy; **not merely DC04's own earlier reject** |

**Oracle reuse caveat:** `research/phase2a_dc01/independent_positive_oracle.py` has `raw_commitment_graph` support for object `_sd` as a generic SD-JWT feature; that helper **is not** the fixed Host policy that forbids `_sd` anywhere. A new S3/O3 wrapper must first inventory the **entire original signed graph**, explicitly enforce the fixed three-path allowlist (no object `_sd`, decoy, unknown, surplus or duplicate commitments), and cross-check digest consumption. Merely seeing a successfully resolved payload or a helper return value is insufficient. Keep this check demonstrably separate from DC04's own rejection path.
| `S4_DC04_CHAIN_CHECKOUT` | Invoke existing named DC04 resolver via `AP2DC04FixedIssuerResearch.verify!`, with policy-selected A key and fixed Host context | Positive returns **LIMITED_POSITIVE only** after existing Agent/Terminal/Merchant/Checkout binding |
| `S5_RECORD` | Record O1–O5, actual first rejecting stage/reason, raw bytes/digests, HEAD, policy digest | Proven **synthetic stage**, not real Host trust/authorization |

Observations must distinguish `S1`/ `S3` **new adapter** reasons from **existing DC04** exceptions. Raising the same Ruby error text is not sufficient: report actual method/source location/stage, and an independent oracle for changed signed bytes. If any earlier reject bypasses the target stage, mark it **FAIL_TO_PROVE / HOLD** even though fail-closed behavior occurred.

A separate *offline* O1–O4 oracle may validate the whole B-signed Root/Terminal/Checkout even when the real Host adapter rejects B at S1. That diagnostic verifies cryptography; it is **not** permission to run B through the Host as trusted.

## 5. Three cases: outcome matrix and STOP

| Case | Signatures and independent facts | Host adapter expected | Existing Ruby expected | Limits of conclusion |
| --- | --- | --- | --- | --- |
| **IP01 A FULL** | A signs valid SDK Root, all 3 committed slots disclosed, official Schema VALID, Agent Terminal `sd_hash`, Merchant JWT/Checkout binding VALID | S1 A permitted; S2 valid; S3 exact 3 signed paths, no residual | S4 `LIMITED_POSITIVE` | Limited synthetic positive; no business ALLOW |
| **IP02 B FULL** | B genuinely signs a FULL with **B key**; Python O1 explicitly verifies B-key JWS VALID; O2/O3/O4 independently valid; unchanged A-only Host policy | **S1 `UNTRUSTED_ISSUER`** before adopting B as trusted; document actual candidate thumbprint | S4 **NOT REACHED** (expected) | **Not** an A-key `invalid_signature` demonstration |
| **IP03 A other signed SD layout** | Same A key genuinely signs original alternate Root; Agent Terminal is re-signed to bind altered Root; signed graph shows extra `$/delegate_payload/0/disclosed/constraints/1` path, Open content same as FULL; **independently recheck official Schema VALID** | S1 A allowed, S2 VALID; **S3 `UNSUPPORTED_SIGNED_PROFILE`** for signed slot diff | S4 **NOT REACHED** (expected) | New synthetic signed-grammar policy guard only; **not** a signed `policy_version` proof |

**All cases currently NOT RUN.** Reusing old DC04 evidence cannot auto-promote any result to E01-S success. If IP03's actually emitted Root or resolved Open is not valid per pinned SDK/schema, record `BLOCKED_OFFICIAL_SHAPE` and STOP. If IP02 differs in binding, disclosure shape, time or Schema besides the signer key, or IP03 differs in unapproved ways, record **confounded negative / HOLD**. If IP01 fails, **do not score either negative**.

**Synthetic result status vocabulary**:
- `LIMITED_SYNTHETIC_E01S_OBSERVED`: IP01 positive, O1–O4 genuine independent comparisons, both negatives reject at verified target stages under same frozen policy and Ruby candidate; **never a Phase 2-B GO**.
- `FAIL_TO_PROVE / RED-HOLD`: rejected for wrong/unknown stage, poor oracle independence, missing Host trust provenance, incomplete signed bytes, or inconclusive time/scope.
- `BLOCKED_OFFICIAL_SHAPE`: official SDK/schema cannot sustain the intended truly signed comparison.
- `STOP_RESOURCE_OR_COST`: any finite limit exceeded; no paid budget auto-escalation or retry.

## 6. Hard bounds to approve before any run

Existing DC04 local caps are **not** a whole-chain deployment limit. The following are **proposals in #66**, not preexisting implementation, allowed spending or authorization:

| Boundary | Proposal / required enforcement |
| --- | --- |
| Number of cases | **Exactly 3** (IP01, IP02, IP03); positive first; no additional variant executions |
| Whole input | **<= 128 KiB per case**, including Root, Terminal, Merchant JWT, disclosures, Host context; enforce before parse |
| Root | **<= 32,768 bytes**, ASCII/canonical; **1–16** disclosures |
| Signed structure | Depth <=24, object fields <=32, array items <=16; Root Open exactly one and fixed 3 allowed commitment paths |
| Time | Root `exp-iat <=7200 s`, terminal and Closed existing strict windows; proposed policy skew **0 s**, a single trusted-time snapshot and finite policy/key `not_before/not_after` (exact duration/clock source must be specified before execution) |
| CI | Single **standard** GitHub-hosted `ubuntu-24.04` job, max **10 min**; per-verifier-process wall timeout **10 s**, no parallel fan-out or rerun |
| Artifact | Synthetic, **public-only** proof bundle <= **1 MiB**, retention <= **7 days**; never any private key or sensitive real JWT; document persistent replay as public-only regeneration recipe |
| Billing | Public-repository standard runner may avoid charged runner minutes; **do not assume** storage/billing is free. If acceptable charges/limits and exact runner setup cannot be verified, no run |

**Runner design warning:** existing DC04 workflow has a 20-minute timeout and clones+installs SDK dependencies. A 10-minute E01-S bound might fail merely during setup; this is a **STOP/HOLD**, **not** implicit consent to increase caps, add reruns or bypass gates.

## 7. Future review checklist / current status

- [x] Actual DC04 and P1-2/P1-3 entry points reviewed; no registry exists.
- [x] Proposal isolates a Host key gate **before** signature trust and a Host grammar gate **after** A's verified signature, with explicit causal attribution.
- [x] Existing genuine A-signed nested-layout candidate identified (not yet rerun for E01-S).
- [x] No modifications required to the named legacy verifier, old workflows or Gem in this proposed scope.
- [ ] Confirm finite policy/key lifetime and trusted-clock source, immutable snapshot integrity and isolated generator inputs.
- [ ] Validate testable O1–O5 requirements and the exact independent IP02/IP03 counterfactual under the pinned SDK.
- [ ] Approve entire bound/CI/storage/cost envelope, including 10-minute setup feasibility.
- [ ] New explicit **`EXECUTION APPROVED`** from project owner in **#66**, for the exact change set.
- [ ] Only then create *separate code PR*; latest-HEAD review/Codex findings and actual scoped CI must be inspected before any merge.

**Decision today:** **DESIGN REVIEW ONLY**. IP01/IP02/IP03 **NOT RUN**. `E01_REAL_ISSUER=UNPROVEN`; parent #47 **OPEN**; Phase 2-B **HOLD**; no Gem/Host authorization.
