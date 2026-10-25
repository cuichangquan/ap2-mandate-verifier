# Issuer / Host minimum contract — synthetic design only

Status: DESIGN_ONLY / NOT_RUN. Source baseline: `feb3c426365b5bb9d2fe2752a30f0e08f7eee48c`.
The status above is the preparation-time snapshot. Subsequent approved synthetic observation is recorded in [the subset README](../research/host_handoff_subset/README.md) and its R1 report; this is not adoption of a production Host contract or proof of real Issuer trust.
AP2 source remains `b4587ac1d055888a73b4b21750973cffba961793`; only the adopted fixed profile and seven supported shapes apply.

## Authority and registration

The Gem checks supplied trust data; it does not establish who controls an Issuer or fetch a trustworthy registry. A declaration, token `kid`, downloaded PEM, or valid signature alone establishes no authority. Real Issuer provenance remains UNPROVEN. This preparation uses synthetic Issuer / Agent / Merchant records only.

A future Host registry must retain an independently authenticated, out-of-band enrollment decision: authority source, approver, enrollment time, issuer identity, tenant, purpose, profile, algorithm, canonical public-key fingerprint, key reference, validity and revocation policy. This provenance record is outside the Gem's strict input shape. No account creation, contact, network discovery or real key is part of this PoC.

Host policy/snapshot revisions are immutable `(version, content hash)` pairs plus an independently maintained monotonic generation/high-water mark. Version strings are identifiers, not lexically ordered counters. Expired, unknown, contradictory, unavailable or rolled-back data is HOLD/REJECT; do not reuse a stale cache merely because its signatures verify. Update freshness has an explicit deadline and trusted clock. High-water persistence and authorization of updates are Host obligations, not proved by this sequential model.

Rotation selects an explicitly enrolled new key reference and bounded overlap policy. Revoked/inactive/expired old keys cannot authorize new consumption. Unknown keys never fall back to another key, the token's embedded key, or an arbitrary successful signature. Unavailable updates cause HOLD. Real registry authenticity, freshness, rotation and revocation operations remain unproved.

## Existing verifier and proposed handoff

The Gem retains strict parsing and limits, exact profile/trust checks, Issuer / Agent / Merchant signature checks, original graph closure, schema/subset checks, Host challenge/order binding and validity intersection. Its Evidence is not payment authorization or Host ALLOW.

Use the actual immutable `ResearchEvidence` returned by `verify_research` in the same trusted Ruby process. JSON serialization is an observation only; a reconstructed Hash is never authentic Evidence. Private constructors are API discipline, not protection from malicious Ruby code in that process.

Immediately before use, the Host must atomically read/revalidate the current authoritative trust generation/hash/profile/key status and freshness, trusted time, complete order binding/version, challenge identity/nonce hash/issued state and Evidence validity interval. Any change invalidating those facts requires refusal and, when appropriate, a fresh challenge and verification. Evidence may become stale between generation and consumption.

In a real implementation, nonce consumption and order-version CAS must be one authoritative atomic operation including the rechecks above. Separate check-then-write calls are insufficient. An unknown commit outcome is PENDING: reconcile by stable operation identity with the authoritative store, never blindly retry or treat it as successful. Payment execution/idempotency is a separate contract and is not implemented here.

## PoC proposition and limits

The eight fixed transitions in the accompanying README are the independent oracle. They test sequential synthetic Host decision logic after a real Gem Evidence is created. A model verdict `MODEL_COMMIT` means only a synthetic state transition, never payment ALLOW. All scenarios reuse saved public synthetic signed wire; there is no private-key generation or storage.

This does not demonstrate DB atomicity, concurrent exclusion, durable rollback prevention, recovery, actual Issuer trust or real revocation. Existing E06 evidence adoption and first-stage research-core completion are unchanged; whole E06 / Phase 2-A PASS, general AP2, issuance/presentation and production GO remain outside scope. Historical communication-accounting gaps remain.

References: `lib/ap2_mandate_verifier/{trust_context,host_binding,research_result}.rb`, `docs/VERIFIER_CORE_COMPLETION_CRITERIA.md`, `docs/PHASE2A_EXIT_GATE_DECISION_CHECKLIST.md` at the baseline above. This proposal adds no product API or guarantee.


## Proposed operation reconciliation boundary (DESIGN_ONLY / NOT_RUN)

At baseline main27445dafbca5ad9646249b008ce83a99348f9092, R3 observed five controlled transaction schedules; it did not test unknown-COMMIT recovery. The proposed separate subset does not change that evidence or the Gem.

Allocate a stable operation ID before the first attempt and register its immutable tenant, authenticated principal, order/version, challenge/nonce hash and canonical request digest in the authoritative store. A token's claims or a caller-supplied ID does not authorize lookup. Authenticate the caller separately and authorize that exact tenant/principal/operation; mismatch gives HOLD/CONFLICT without another tenant's result. Evidence is still created and used in the same trusted Ruby process, never reconstructed from stored JSON.

An ambiguous response gives PENDING, never inferred success or failure. Query a fresh authoritative primary connection and match the complete registered request identity, operation row and current nonce/order state. A matching committed operation may be reported as an existing local result, never executed twice. A missing row alone is not proof of nonexecution: an original transaction may remain active or invisible. Lock/fence the operation registry; inability to acquire its lock, unavailable primary, inconsistent rows, unknown original-session termination or mismatching binding keeps PENDING/HOLD.

The narrow proposed retry requires the original attempt's termination to be established, registry generation1 under lock, no committed operation and unchanged issued nonce/open order. Authorize generation2 once under that lock; stale generation1 attempts are fenced. The retry creates fresh actual Evidence and rechecks latest trust, clock, order and challenge under the same consuming transaction. Changed prerequisites refuse; no second retry, new operation ID workaround or automatic payment. Durable registration/recovery across process or DB crashes remains unproved.

The source-only experiment models loss of the application result after the worker internally receives the DB COMMIT acknowledgment. It is not actual PostgreSQL protocol-response loss, TCP partition, crash durability, payment idempotency or production recovery. Fixed synthetic caller identity/clock and a trusted controller are test assumptions, not real authentication/freshness proof. See the new subset README; execution remains HOLD.

## Subsequent limited observation — 2026-10-25 UTC

The NOT_RUN and execution HOLD statements above describe preparation time. The separately approved [COMMIT reconciliation subset](../research/host_commit_reconcile_subset/README.md) subsequently ran once in Docker attempt R5: four controlled cases matched, with required results and diagnostics preserved. The source baseline was `27445dafbca5ad9646249b008ce83a99348f9092`. This records a synthetic research contract and observation, not adoption of a production recovery policy. The experiment uses one fixed ordered JSON digest representation, not a new general canonicalization standard. Actual caller authentication, real Issuer provenance, trusted real clock/revocation, arbitrary old-writer schedules, DB protocol acknowledgment loss/TCP faults/crashes/durability and payment idempotency remain UNPROVEN. Verifier Evidence is not ALLOW. Prior failures and missing evidence remain recorded; the result does not amend public Gem or expand the first-stage core completion scope.
