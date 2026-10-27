# Agent collaboration rules — ap2-mandate-verifier

> Applies to repository work by Codex and other agents that read this file.
> **Canonical, current process policy:** [Issue #101 — 開発高速化・品質維持ルール](https://github.com/cuichangquan/ap2-mandate-verifier/issues/101).
> This file is a compact entry point, **not** a second policy source or an authorization.

## On every new task or chat

1. Read Issue #101 (including current decisions/comments) **and** the relevant task Issue/PR. Re-check actual main/PR HEAD, current review threads, execution gates and approval scope; earlier chat summaries may be stale.
2. Briefly state the task's goal, permitted paths/actions, proof required, STOP conditions, and current HOLDs before proposing a change.
3. If Issue #101 or relevant approvals cannot be fetched, do not guess that permissions exist. State the blocker, retain all previously documented HOLDs and ask for the specific missing approval only when action is needed.

## Optimize the critical path, never the security threshold

- Objective: minimize lead time to a trustworthy, **scoped Merchant-side Ruby AP2 verifier**; do not optimize for number of research PRs.
- Prioritize the Phase 2-A [E00–E10 exit gates](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/PHASE2A_EXIT_GATE_DECISION_CHECKLIST.md) under [Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47), initially **E03/E04/E06**: original signed Root commitment-graph completeness, causal signed negatives with independent oracles, and an integrated G0–G7 verification order. Treat E01/E05/E07/E08/E09 and Phase 2-B decisions independently.
- Keep **Verifier evidence** separate from **Host final ALLOW**. Persistent nonce issuance/consumption, checkout current state, external authority revocation, payments, and receipts are not proved by the verifier. A missing trusted Host input is HOLD/REJECT, not an invitation to self-attest.
- Preserve the official AP2 v0.2.0 pinned source SHA `b4587ac1d055888a73b4b21750973cffba961793` unless separately approved. Never claim generic AP2 conformance or real-Issuer provenance from synthetic findings.

## Review workflow for each approved change

1. **Before editing:** define one reviewable security proposition, scope, touched paths, positive and negative cases, independent oracle, trust boundaries, and what would make the work STOP.
2. Prefer one responsibility per PR, a small diff (roughly 200–400 added lines as a reviewability *guide*, never at the cost of safety), and reuse of already reviewed components. Reassess architecture instead of accumulating patches after repeated same-root-cause feedback.
3. **Before Codex review:** conduct a source-level security self-audit appropriate to the approved scope. Search for sibling instances of known failures, untrusted input promotion, signed-wire/schema gaps, database permissions, concurrency/unknown commits, nondisclosure, side effects, resource bounds and cleanup.
4. **Independent review:** fix substantive P1/P2 issues, including their shared root causes, and obtain latest-HEAD Codex review with zero unresolved substantive review threads before merge. Two cycles of repeated same-cause comments trigger **design reassessment**, not a review bypass. Do not auto-merge.
5. Distinguish DESIGN_ONLY, NOT_RUN, LIMITED_OBSERVED, REJECT, HOLD, and supported PASS. Codex no-findings or green CI alone never proves correctness. Record code SHA, signed original-wire evidence, independent expected stage/oracles, and residual risk where applicable.
6. Measure review cycles, new P1/P2 findings, PR lead time and scope violations across the next 3–5 PRs; improve process without dropping coverage.

## Hard approval and execution boundaries

- **This AGENTS.md and Issue #101 do not grant execution or implementation approval.** Follow each issue-specific explicit Owner gate; generic "OK", a PR merge or static review is not Approval B.
- Do **not** run Ruby/Python/SQL, tests, CI/Actions, containers, DB, GCP, network-dependent tooling, incur cost, access real payments/keys/PII, or change workflows unless the relevant Owner approval explicitly covers the operation.
- Do not expand approved files, project scope, or operational budget implicitly. If a requested change would trigger automatic CI, STOP and re-scope before opening that PR.
- [Issue #97](https://github.com/cuichangquan/ap2-mandate-verifier/issues/97) A3-T2c Approval B and [Issue #73](https://github.com/cuichangquan/ap2-mandate-verifier/issues/73) E06-I execution retain their issue-specific restrictions. Real Issuer trust, specific Host production GO and Phase 2-B remain HOLD unless separately and explicitly changed.
- Exact-artifact stable `0.1.0` publication on RubyGems is completed under its separate Owner S7 approval: 34,304 bytes, SHA256 `37b2a235b6fab2d9d9765ae985dd9db27afd3b2c5407fe263a6b65314550db32`. See the [verified publication record](research/stable010_release_linux_package/README.md#rubygems-publication-verified) and [current project status](docs/PROJECT_STATUS.md). This records that completed action only; it grants no authority for a new Gem publication, rebuild, execution, release/tag change or merge. New actions remain subject to their own explicit approval and all rules above.

If canonical guidance conflicts with safety, exact approved scope or independently verified evidence, **STOP**; explain the conflict instead of broadening authority.
