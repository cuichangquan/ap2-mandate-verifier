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
