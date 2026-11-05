# Repeated Payment approval: explicit JPY/ON_DEMAND subset (1.6.0 candidate)

This additive profile supports several separately approved Payment occurrences under one signed Open, with finite occurrence and cumulative JPY reservation limits. It is not a scheduler, generic recurring-payment implementation or payment executor. Existing profiles, seven-input Checkout contract, default verifier results and 600-second Mandate lifetime remain unchanged. This bounded profile does not provide long subscriptions. The separate [LongPayment profile](LONG_PAYMENT.md) adds explicit UTC-calendar-month windows and long content with fresh proofs.

## Specification boundary

Official AP2 v0.2.0 is pinned to `b4587ac1d055888a73b4b21750973cffba961793`. Investigated main `e1ea56db72a6385bce3e5c1112b3a56ce60acb43` has identical relevant specification/schema/SDK files. The [recurrence description](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/payment_mandate.md#agent-recurrence) requires frequency separation and a maximum count; calendar/rolling periods, anchors and timezones remain unspecified. The Python evaluator checks count but not frequency. Issue297 remains open. `ON_DEMAND` is the sole supported frequency; calendar frequencies fail closed.

The [budget description](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/payment_mandate.md#budget) requires cumulative approved amounts not to exceed `max`; schema `max:number` does not specify units. Python multiplies by100 regardless of currency. Issue339 and354 and proposed fixes in PR340/368/377 remain open/unmerged at investigation. We do not treat their Decimal/monetary-unit proposals as adopted specifications.

The explicit `ap2.payment.recurring.jpy_on_demand.complete.1` and `.selective.1` profiles accept **JPY integers only**, with one integer yen equal to one JPY minor unit. No float, rounding, fixed100 conversion or reinterpretation of another currency is performed. Thus the common major/minor-unit ambiguity does not require choosing an exchange scale. The Python evaluator's acceptance of2JPY under a1JPY budget is a measured disagreement, not behavior copied into this profile. These explicit profiles are a narrow Gem contract, not official certification or generic AP2 conformance.

Every Open must visibly include exactly one `payment.agent_recurrence` (`frequency: ON_DEMAND`, positive finite `max_occurrences`) and one `payment.budget` (`currency: JPY`, positive integer `max`), alongside the existing payee, instrument, amount range and Checkout reference constraints. Mandatory conditions cannot be hidden. In the selective profile, only registered payee/instrument candidate leaves may be withheld. An old profile never silently gains recurrence support.

## Measured interoperability

The pinned official Python facade fails recurrence issuance with an Enum JSON-serialization error. Its generated Budget model also converts integer600 to600.0, which is outside this integer-only signed profile. The explicit low-level test adapter serializes enums in JSON mode, preserves the original integer JPY budget, and adds the signed profile marker. It does not claim that the unmodified high-level facade supports this profile.

Fresh Ruby/Python keys exercise complete and selective Open/Closed chains in both directions, official schema/typed parsing, eight alternative Success/Error Receipts and fifteen signed negative checks (missing/hidden mandatory constraints, unsupported frequency/count, exact presentation binding and Receipt reference). The official SDK is evaluated at zero historical usage; an independent oracle checks mandatory disclosure and selected-candidate privacy. These are scoped wire/crypto comparisons. Durable aggregate enforcement is exercised separately through the Ruby store/process tests and is not supplied or certified by the official SDK.

## Integration

`RecurringPayment` provides issuance, selection, presentation and stateless verification for the explicit profiles. Stateless verification authenticates each presentation and visible per-payment limits; **it cannot establish historical count or remaining budget**. Applications requiring repeated acceptance use `PaymentAcceptance::Service` with `PaymentAcceptance::RecurringSQLiteStore`, or a separately validated adapter preserving the same transaction contract.

```ruby
m = AP2MandateVerifier
store = m::PaymentAcceptance::RecurringSQLiteStore.create(path: protected_new_path)
service = m::PaymentAcceptance::Service.new(store: store)

# Protected authenticated consent backend; retain the COMPLETE Open confidentially.
store.authorize_series!(tenant_id: "tenant", merchant_id: "shop", approval_id: "consent-42",
  open_sd_jwt: full_open, profile_ref: m::RecurringPayment::PROFILE_REF,
  trusted_provider_public_key_pem: provider_key, expected_agent_public_key_pem: agent_key,
  verified_at: trusted_now)
# Enroll each real occurrence with existing authorize!, its exact Checkout/Payment
# and pinned Receipt context. IDs are stable authenticated Host state, never client UUIDs.
accepted = service.accept(**trusted_occurrence_scope, mode: :conditional, verification_inputs: raw_inputs)
execution = service.start(ticket: accepted.ticket, verification_inputs: fresh_raw_inputs) if accepted.ticket
# Application processor call uses execution.processor_key. This SDK makes no call.
```

`authorize_series!` validates the complete signed Open, Provider signature, authorized Agent key, profile, validity and mandatory constraints. It pins the original issuer JWT reference and immutable full contract. Selected presentations retain that issuer JWT; changing disclosure subsets does not create a new allowance. Re-enrolling the same agreement cannot reset counters or reactivate revocation. A changed signed Open conflicts with the same protected agreement ID. Re-signing and arbitrary new IDs received from a client never justify new consent enrollment.

For each occurrence, existing `authorize!` still pins exact independently approved Checkout/payment semantics and Receipt trust. First reservation checks that active grant and the series, then atomically inserts the attempt **and increments both reserved count and amount in the same BEGIN IMMEDIATE/COMMIT**. An identical retry obtains no second Ticket and incurs no second charge. A conflict, invalid presentation, exceeded limit or failed transaction creates no execution handle. The reference store bounds one series to one merchant; the same tenant/Open or tenant/agreement cannot be re-enrolled under another merchant to multiply its quota.

Reserved, processing, unknown and terminal Success/Error attempts all retain their charged allowance. No timeout, error Receipt, restart, revocation or presumed refund releases it. This deliberately conservative accounting may consume allowance for a payment that never occurred. `usage(tenant_id:, merchant_id:, approval_id:)` reports reservation totals, not settled spending. `revoke_series!` blocks both new reservation and fresh start without deleting history. Receipt reconciliation can finalize original processing/unknown attempts after Mandate expiry, but never grants another Ticket or releases quota.

## Persistence and compatibility

The recurring reference adapter uses an explicit **new schema2 database** with the same optional pinned `sqlite3=2.10.2` driver. Existing1.5 schema1 files remain unchanged and are opened by the original `SQLiteStore`; they reject new recurrence profiles. Neither adapter opens the other's schema or auto-creates, upgrades, repairs, migrates, resets or falls back to memory. Provisioning a new empty ledger is not migration of existing history. Applications with prior repeated-use history must stop and reconcile/import it through their own reviewed process before enrolling a series; starting at zero is unsafe.

One authoritative durable local ledger must serve every worker and occurrence for an agreement. A per-process database, multiple independent stores, rollback/loss, restoring a stale backup or splitting one consent into fresh IDs destroys the protection. Authenticated stable identities, genuine consent, full-Open confidentiality, current order/nonce/revocation CAS, processor idempotency/query and outcome reconciliation remain application duties. Custom adapters must make authorization, quota checks/updates, occurrence reservation and fenced start atomic with current authority. An external precheck followed by an independent database write is insufficient.

No actual Issuer/Host provenance, production durability, external exactly-once settlement, refund semantics, distributed coordination, automatic scheduling, non-JPY budgets or calendar recurrence is claimed. This candidate covers bounded ON_DEMAND repeated use within existing validity; the broader monthly-subscription goal remains deferred pending a precise safe contract.
