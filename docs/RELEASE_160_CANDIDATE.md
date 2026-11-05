# 1.6.0 candidate: long Open and UTC-monthly JPY acceptance

Historical preparation record. Owner subsequently approved publication; [the publication record](POST_RELEASE_160.md) supersedes the availability status below. No production/payment authority follows from tests, review or merge. The earlier bounded ON_DEMAND candidate is retained separately as historical evidence; it is not replaced in the registry.

## Proposed notes and primary use

New explicit `LongPayment` complete Checkout/Payment profiles reuse one signed Open pair across approved UTC calendar months. Their shared content `iat`/`exp` stays fixed (maximum400days); outer KB proofs, challenge/order/current keys and starts are fresh. Existing defaults, seven-input contract and old600/7200second profiles remain unchanged. The bounded `RecurringPayment` complete/selective profiles remain available.

Optional schema3 `PaymentAcceptance::LongSQLiteStore` atomically checks current protected authority, active Root, period/count/JPY budget and occurrence state. Protected CAS Root/Issuer/Agent replacement preserves complete economic terms, principal identities, original agreement end and accumulated usage. Authority invalidation/revocation blocks starts; old pending Tickets never revive through a generation update. Unknown/Error/crash never refunds capacity, reissues a Ticket or loses the first signed wires/Receipt reference.

```ruby
accepted = service.accept(**trusted_scope, mode: :conditional, verification_inputs: raw_inputs)
execution = service.start(ticket: accepted.ticket, verification_inputs: fresh_raw_inputs) if accepted.ticket
# execution.valid_until is short; the application owns prompt processor dispatch.
usage = store.usage(**trusted_series_scope) # reserved totals/current epoch, not settlement
```

[12-period installed Ruby lifecycle](../examples/long_payment_acceptance.rb), [wire-only lifecycle](../examples/long_payment.rb), [API/security/migration/Python contract](LONG_PAYMENT.md).

## Exact boundary

The additional MONTHLY meaning is an explicit Host/profile policy: one immutable window within each UTC calendar month, no more than one window per month. It is not generic AP2 calendar conformance, rolling intervals, local timezone/DST billing or catch-up. JPY budget uses exact signed integers; the current Python evaluator's100xJPY conversion and missing cadence evaluation are documented disagreements. Actual SDK constructors/facade/chain/Schema comparisons use explicit Enum/profile/integer/inline adapters, not a claim of unmodified high-level compatibility.

External trust/consent/order provenance and freshness, registry synchronization into the ledger, nonce/order CAS, one protected authoritative store, history migration, processor idempotency/query and settlement remain application responsibilities. No built-in external revocation feed, scheduler, payment call, remote exactly-once, auto-refund or automatic schema1/2 migration is supplied. Long selective/PISP/date combinations, other currencies/timezones and arbitrary AP2 formats remain unsupported.

## Release gates

Both supportedMRI3.4.12/4.0.9 full regressions and the same physically installed archive; every payload source/archive/installed byte hash; 12-month leap-year positives, causal signed negatives/current key tests; independent8process same-period/count/budget races, realSIGKILL/restart, fsynced mock effects, rollback, Root/key replacement, revocation and original historical Receipt; installed pinnedPython interop with exactwire disagreements; optional-driver absence; normal demo regression and strict candidate context; independent latest-HEAD review with no unresolved substantiveP1/P2; Draft-first PRs, successful CI, reviewed/merged tree equality; fixed-builder repeat and merged-source byte-identical build.

Source/hash/count evidence is recorded outside its own package. Only an explicit OwnerGO for the final exact archive permits one publication attempt. Verify actual registry bytes before formal tag/Release; inspect uncertain outcomes before retries. No merge/push workflow may publish or deploy.
