# 1.6 recurrence / budget research — 2026-11-05 UTC

Status: source research and one isolated synthetic SDK probe completed. No product edits, pin changes, publication, real payment or settlement test.

## Source identity and current proposals

`gh api repos/google-agentic-commerce/AP2/commits/main` returned `e1ea56db72a6385bce3e5c1112b3a56ce60acb43`. The approved execution pin remains `b4587ac1d055888a73b4b21750973cffba961793`. Read-only Git comparison found no differences under `docs/ap2`, `code/sdk/schemas/ap2`, or `code/sdk/python/ap2/sdk`; both constraints files have Git blob `48aed7981972745a9bd27b1af811c9edbab01901`.

Full issue bodies/comments and PR bodies/comments/reviews/inline review comments/file patches were fetched with the existing authenticated CLI into task-local evidence. These are observations of proposals, not adopted requirements:

| Item | Observed state / HEAD | Meaning |
| --- | --- | --- |
| [Issue 339](https://github.com/google-agentic-commerce/AP2/issues/339) | open | Missing-disclosure enforcement and budget unit ambiguity; two comments explain that hiding both budget and recurrence removes their presence checks. |
| [Issue 354](https://github.com/google-agentic-commerce/AP2/issues/354) | open | Enum serialization prevents ordinary recurrence issuance. |
| [PR 340](https://github.com/google-agentic-commerce/AP2/pull/340) | open, unmerged, `3620641788d600a3a99cfa84db0ddafeed291fb6` | Documentation proposal identifying budget as major units; does not change evaluator arithmetic. |
| [PR 368](https://github.com/google-agentic-commerce/AP2/pull/368) | open, unmerged, `5961068266d7d4e9be65f1275838a990480727bd` | Decimal conversion and currency exponent proposal, flooring excess precision. |
| [PR 377](https://github.com/google-agentic-commerce/AP2/pull/377) | open, unmerged, `273d769836bb11465ca511407a1ea58b2c1f53f8` | Overlapping Decimal/ISO exponent proposal; author acknowledges PR 368. |

All three requested PRs have zero submitted reviews and zero inline review comments at retrieval. Existing discussion/CI comments were read; green checks or contributor claims do not resolve specification meaning.

## Normative document and schema scope

The document describes reuse with cadence separation and an occurrence limit. Budget evaluation combines the current amount with previously closed amounts and updates accumulated usage after approval. It does not define calendar versus rolling periods, a reference event, timezone, DST, month-end rules, reset intervals or retry accounting. [Pinned payment document, lines 47–62 and 192–208](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/payment_mandate.md#L47-L62).

The schema requires recurrence type/frequency; `max_occurrences` is an optional integer without a positivity bound. Its enum includes ON_DEMAND, DAILY, WEEKLY, BIWEEKLY, MONTHLY, QUARTERLY and ANNUALLY. Budget requires type/max/currency, with `max` a JSON number whose description does not state monetary units. Neither constraint has candidate-array selective-disclosure annotation. These weak schema conditions are insufficient for an operational acceptance policy. [Pinned schema, lines 165–199 and 245–268](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_payment_mandate.json#L165-L199).

## Actual pinned/current Python behavior

`AgentRecurrenceEvaluator` compares prior `total_uses` against `max_occurrences`; it ignores frequency and `last_used_date`. The unused period helper uses local calendar conversions and falls back to zero for BIWEEKLY/QUARTERLY. Budget checks currency and context, adds minor-unit amounts, and computes the cap using `int(max * 100)`. This causes binary-float boundary loss and wrong conversion for zero-/three-decimal currencies. Recurrence presence requires amount-range/budget presence, but removing recurrence removes that trigger; the evaluator loops only over presented constraints. The SDK does not atomically acquire persistent usage reservations. [Pinned constraints, lines 172–229, 278–313, 514–539](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/constraints.py#L172-L229).

[Issue 297](https://github.com/google-agentic-commerce/AP2/issues/297) independently identifies the missing time semantics. A source test accepts DAILY usage even with `last_used_date` set to the current time; that is not cadence evidence. [Pinned test, lines 65–81](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/tests/agent_recurrence_tests.py#L65-L81).

Ordinary `MandateClient.create` fails on the generated `Frequency` Enum. [PR 355](https://github.com/google-agentic-commerce/AP2/pull/355), open/unmerged at `3bfa15719544002a6bf5eefd89ee091dfdf2ab32`, proposes JSON-mode model serialization; it does not implement cadence or persistence. [Pinned serializer, lines 225–229](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/common.py#L225-L229).

## Executed boundary probe

Offline existing `ap2-merchant-interop:task3`, Python 3.11.2, read-only pinned SDK, RAM-only generated keys: ordinary facade issuance raised the expected Frequency `TypeError`; an explicit JSON-mode adapter using unchanged official low-level signing primitives produced a signed Open that verified. The official evaluator accepted a 2-JPY payment under a 1-JPY budget because it scales that budget to 100. The chosen local integer-JPY profile must reject this case. Evidence: `research160-sdk-probe.json`; stderr contains only optional SDK logging failure against its read-only `.logs` directory. No generic facade PASS is claimed.

## Safe implementation boundary selected for this candidate

Implement only a separately named profile with ON_DEMAND, finite positive occurrence cap, integer JPY budget, and mandatory fully visible recurrence/budget/amount-range conditions. JPY major and minor units coincide; the local cap uses the raw integer, avoiding float conversion and rounding. This is an explicit narrower contract, not a claim that upstream budget ambiguity is resolved.

Bind a protected stable agreement and each independently authorized occurrence to the signed Open and exact terms. Reserve occurrence count and amount in the same durable claim transaction; retries must not reserve twice. Unknown outcomes, Error receipts and crashes retain conservative reservations. Caller-supplied aggregate counters or a generic successful SDK result cannot authorize another occurrence.

Calendar frequencies and non-JPY budgets remain rejected/deferred. A monthly scheduling goal is therefore not fulfilled by this subset. Supporting it later requires an explicit signed schedule contract and independently trusted clock/anchor rules or an adopted authoritative definition. Keep original-wire hashes, profile selection and existing 600-second lifetime limits unchanged. No automatic scheduling, payment execution or production exactly-once guarantee follows from these checks.
