# 1.6.0 candidate: bounded repeated Payment approval

Unpublished candidate preparation. RubyGems publication, formal tag and GitHub Release require the Owner's explicit GO. No production/payment execution is authorized by candidate tests or merge.

## Proposed notes

Explicit `RecurringPayment` complete/selective profiles support **JPY integer amounts and ON_DEMAND finite recurrence**. One signed Open can serve several separately approved occurrences within the unchanged600second validity. Mandatory recurrence/budget constraints stay visible. Existing1.x default profiles, public verifier meanings, five base dependencies, seven-input Checkout contract and schema1 ledgers remain compatible.

Optional `PaymentAcceptance::RecurringSQLiteStore` provides protected series enrollment, active revocation and durable reservation usage. Count and JPY amount are charged in the same transaction as first occurrence reservation. Re-sign/retry does not create allowance. Unknown outcomes, errors, crashes and authentic Error Receipts never refund capacity or grant a second execution handle. Existing original-wire Receipt reconciliation remains available.

```ruby
accepted = service.accept(**trusted_scope, mode: :conditional, verification_inputs: raw_inputs)
execution = service.start(ticket: accepted.ticket, verification_inputs: fresh_raw_inputs) if accepted.ticket
usage = store.usage(tenant_id: "tenant", merchant_id: "shop", approval_id: "consent-42")
# usage is reserved count/amount, NOT settled spending or permission to execute.
```

[Plain Ruby lifecycle and upper-limit rejection](../examples/recurring_payment.rb), [API/security/migration contract](RECURRING_PAYMENT.md).

## Scope decision and release recommendation boundary

The broader monthly-subscription goal is **deferred/HOLD**: official recurrence calendar semantics and budget monetary units remain underspecified; relevant PRs are unmerged and the Python evaluator is weaker. This candidate must never be presented as completing calendar recurrence, non-JPY budgets or long-lived subscription authorization. A limited1.6.0 publication is a separate Owner decision after reviewing this reduced explicit scope and evidence. Do not turn missing scope into a compatibility or interoperability claim.

The new schema2 adapter is not an automatic migration. Existing usage must not be discarded by opening an empty ledger. One authoritative protected durable store, authenticated stable consent/occurrence IDs, current authority/order/nonce atomicity and processor query/idempotency remain application responsibilities. No scheduling, production durability, external exactly-once settlement or generic official-AP2 conformance is promised.

## Required evidence and publication procedure

Before release: both supportedMRI3.4.12/4.0.9 full regression and same-archive installation; signed positives/negatives and mandatory-disclosure tests; independent multi-process count/budget race, crash/restart and transaction rollback oracles; selective candidate privacy and scope binding; pinned official schema/Python comparisons with observed disagreements; exact-HEAD independent review with no unresolved substantiveP1/P2; Draft-first PRs, greenCI and verified reviewed/merged tree equality; normal demo regression and optional candidate example; reproducible fixed builder and complete source/archive/installed payload comparison.

Candidate bytes/checksum and exact merged source are recorded externally to avoid self-referential package hashes. Only after explicit OwnerGO may the exact candidate be pushed once; inspect registry before any uncertain retry. Download and compare actual registry bytes before formal tag/Release. No workflow may publish or deploy on merge.
