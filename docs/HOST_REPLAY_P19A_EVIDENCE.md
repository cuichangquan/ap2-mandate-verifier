# P1-9a — PostgreSQL 16 Host Replay Research Evidence

**Date:** 2026-10-11 JST  
**Scope:** Four research-only Host DB experiments. NOT a full AP2 Verifier, public Gem/API, payment, or signed Receipt.  
**Official AP2 v0.2.0:** fixed commit b4587ac1d055888a73b4b21750973cffba961793, unchanged.

## CI history (including failure)

| CI Run | Outcome | Meaning |
| --- | --- | --- |
| [#38133875041](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38133875041) | **FAIL** | Initial Ruby test destructuring had a syntax error; **0 security cases executed**. PostgreSQL/Gem setup succeeded. |
| [#38133951057](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38133951057) | **PASS** | Real PostgreSQL 16.9, **4 runs / 108 assertions / 0 failures / 0 errors / 0 skips**. Structured evidence gate validated four case IDs, two measured database lock waits, checkout uniqueness violation, and zero-row CAS. |
| [#38134040469](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38134040469) | **Follow-up run** | PostgreSQL image pinned to its previously observed registry digest. Inspect outcome before merge; PR #19 is the current overall evidence location. |

**Passing-run environment:** GitHub Actions ubuntu-24.04, Ruby 3.3.12, pg Gem 1.5.9, PostgreSQL 16.9 (Debian 16.9-1.pgdg130+1). Image ID sha256:5d77af46c4cb952e855106b849c6972b8a1ee2a2518159eb1854702fda47542f. Registry digest postgres@sha256:ddfe3e8713e3ee5b8f286082cb12512488dfbf3f5a1ecb0b74a42e6055af0a5f. CI logs and 7-day artifact **p1-9a-postgresql-evidence** contain sanitized result JSON, Minitest output, and versions.

## The four exercised P1-7 cases

[P1-7 Host Security Test Plan](HOST_SECURITY_TEST_PLAN.md) remains the one canonical source for test IDs.

| ID | Actually observed in passing run #38133951057 | Limitation |
| --- | --- | --- |
| **HR01** | Same nonce, two distinct Ruby processes and PG sessions. A held the Checkout row lock, B was observed with wait_event_type Lock and pg_blocking_pids(B) containing A. Only one commit, operation and outbox. Other worker STOP. | Synthetic evidence, no AP2 crypto in this DB experiment |
| **HR02** | Different nonces, same Checkout and real measured row-lock contention. One operation/outbox; one consumed nonce, other untouched. Separate duplicate-order insert raised PG::UniqueViolation. | Single-use Checkout only; no external dispatch |
| **HR03** | Challenge already consumed while Checkout still OPEN. Conditional nonce UPDATE RETURNING updated **0** rows. Worker STOP; no operation/outbox. | Targeted CAS case, not all TTL/clock/revocation conditions |
| **HR08** | Same synthetic challenge replay after first commit was STOP; no new operation/outbox. | No signed Receipt or Provider retry |

**DB research implementation:** PostgreSQL READ COMMITTED, Checkout row SELECT FOR UPDATE, Host nonce CAS, Checkout OPEN-to-RESERVED state transition, unique (tenant_id, checkout_id) on operations, outbox recorded in one transaction. The race coordinator requires **actual database lock wait observation**, not mere simultaneous process starts. The test assertions independently inspect persistent DB state.

**Not tested:** real AP2 signature/Verifier-to-Host integration, transaction crash before or after commit, unknown commit outcome, Provider logical side effects, retry/idempotency over HTTP, revocation changes, payment, Receipt signing, multi-order Checkout or production.

## Accurate security boundary / GO-HOLD

- **4 of 34 planned Host tests are now exercised** in narrow PG16 research; **30 remain NOT RUN** (all other HR/HT/HC/HE). This does not close P1-7 T1–T5 or P1-4 G1–G6.
- N17 **HOST_BOUNDARY still applies to stateless Verifier**: the same valid signed Mandate can be reverified. This research shows only one isolated Host database technique to prevent repeated Checkout operations, not full deployment safety.
- Previous P1-6 observations 17 GREEN/0 RED/1 HOST_BOUNDARY and 43 regressions belong to separate cryptographic tests. Official upstream Python SDK 186 PASS/2 FAIL intermediate hop aud/nonce remains unresolved.
- The test refuses any database not named **ap2_research**, uses synthetic identifiers, no private signing keys / PII / real payment credentials. The temporary PostgreSQL service and network are removed at CI job completion. Artifacts kept 7 days; no GCP/public service.
- **P1-9a decision: limited offline research PASS if the latest pinned-image run and PR review both pass.** Generic Gem/public API **HOLD**; RubyGems publication, production, real payments **NO-GO**.
- **Next candidate P1-9b, separately approved:** HR04/HR05 crash before/after COMMIT, rollback/recovery. HR06/HR07 unknown commit and fake-provider idempotency require additional separately approved scope.

**Release rule:** Never merge merely because #38133951057 is green if the latest head's GitHub Actions run is failing or unknown. Self-maintainer review does not count as independent audit.
