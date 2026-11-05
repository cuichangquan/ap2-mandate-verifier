# Long Open Payment: explicit JPY / UTC monthly profile (1.6.0 candidate)

`LongPayment` supports one signed Open Checkout and one signed Open Payment reused across approved UTC calendar months. Every Closed preserves its own Open's content `iat`/`exp`; each outer KB proof is fresh, bound to audience/nonce/original presentation. Content validity and permission to start execution are separate. This is a framework-independent Ruby SDK; no Rails, scheduler or payment processor is required or invoked.

## Scope and official boundary

- Explicit profiles: `LongPayment::CHECKOUT_PROFILE_REF` (`ap2.checkout.long_open.multi_item.1`) and `PROFILE_REF` (`ap2.payment.long_open.jpy_monthly.complete.1`). Complete disclosure, one merchant, integer JPY, mandatory finite occurrence cap and cumulative budget, `MONTHLY` with the Host policy below. All mandatory conditions are visible.
- Content lifetime is bounded to400days by this profile. Old Payment/Buyer profiles retain600seconds, old conditional Checkout7200seconds, old default APIs/results/formats and the seven-input Checkout contract remain unchanged. New signed markers and independently registered Host profile/hash prevent implicit selection or downgrade.
- No long selective disclosure, PISP/execution-date combination, non-JPY budget, generic recurrence, catch-up, refund or automatic execution. Existing selective/PISP/date APIs retain their original support.
- Official source remains pinned toAP2 `b4587ac1d055888a73b4b21750973cffba961793`; checked main `e1ea56db72a6385bce3e5c1112b3a56ce60acb43` has unchanged relevant docs/schema/SDK. Issues297/339/389 and PR340/368/377 remain unresolved/unmerged at investigation. The core specification is now under FIDO's standards process; no new normative monthly/unit resolution was identified in accessible public sources.

The Python SDK independently creates the outer KB `iat`; it does not force it equal to the delegated content `iat`. This profile preserves shared content times and refreshes only the proof. The Ruby verifier additionally enforces maximum proof age300seconds, no future proof, exact original Checkout/Payment reference binding and current Host-selected keys. A year-long content expiry never creates a year-long execution handle.

Python's cadence evaluator does not enforce frequency; its budget evaluator uses`int(max * 100)` regardless of currency. This profile uses the signed integer JPY value directly: one yen is one minor unit, with no float conversion/rounding or silent scaling. A receiver using the unmodified Python evaluator can accept more than this profile allows. Wire/crypto interoperability is not aggregate-policy conformance or an assurance that a remote Python consumer enforces these limits.

## Public lifecycle

`LongPayment.issue_checkout_open/issue_checkout_closed/present_checkout` wrap the explicit Checkout profile. `issue_open/issue_closed/present/verify/details` wrap the matching Payment profile. Their signer/key/Checkout/challenge inputs follow the existing role-separated APIs. Provider private keys do not enter Agent operations. `approved_pair!` is a protected-backend helper authenticating BOTH complete signed Opens, current Issuer/Agent keys, exact Checkout reference and immutable economic terms; it does not enroll consent by itself.

`verify` is stateless: it authenticates this presentation and its visible conditions, **not historical quota or final payment permission**. Use the durable acceptance service for repeated use. [Installed Ruby wire example](../examples/long_payment.rb); [twelve-period acceptance/Receipt example](../examples/long_payment_acceptance.rb).

```ruby
a = AP2MandateVerifier::PaymentAcceptance
store = a::LongSQLiteStore.create(path: protected_new_path) # Explicit offline bootstrap only.
service = a::Service.new(store: store)

# Authenticated consent backend; complete retained Opens stay confidential.
store.authorize_series!(tenant_id: tenant, merchant_id: merchant, approval_id: stable_consent_id,
  payment_open: full_payment_open, checkout_open: full_checkout_open,
  trust_json: current_trust_json, selection_json: current_selection_json, verified_at: trusted_now,
  schedule_policy_id: a::LongSQLiteStore::SCHEDULE_POLICY,
  periods: [{id: "2028-01", not_before: january_start_utc, not_after: february_start_utc}])
# Enroll the exact independently approved occurrence through existing authorize!.
accepted = service.accept(**trusted_scope, mode: :conditional, verification_inputs: raw_inputs)
execution = service.start(ticket: accepted.ticket, verification_inputs: fresh_raw_inputs) if accepted.ticket
# Application invokes its processor using execution.processor_key; SDK makes no call.
```

Both original Opens must remain valid. Payment's reference commits to the exact Open Checkout presentation; replacing a parent Open or changing its disclosure bytes cannot silently preserve that reference. Merchant Checkout/order and Agent proofs are fresh per occurrence; the original signed Opens remain unchanged until authorized replacement.

## UTC calendar-month contract

`SCHEDULE_POLICY` is `host.utc_calendar_month_windows.1`. It is an additional explicit Host/profile contract, **not an assertion that AP2 has settled MONTHLY semantics**.

The authenticated backend enrolls1–24 immutable windows with unique stable IDs, integer Unix epoch bounds and half-open`[not_before,not_after)` semantics. Each window must lie inside one UTC calendar month and the initial agreement interval; at most one window per UTC year/month is allowed. A window may be narrower than the month, but cannot span months or split one month into multiple allowances. Period order is normalized by start time; overlap/duplicate/out-of-range/unknown policy fails closed. Actual verification time selects the period; a caller-chosen ID cannot select another window.

This avoids ambiguous rolling-month, timezone/DST, missing-day/month-end and catch-up behavior. It does not support local-time billing calendars. End-of-January and start-of-February can be close in elapsed time while belonging to different UTC calendar months; this is not a rolling minimum interval. The consent UI must display the actual approved windows, total cap, counts and this calendar rule. SDK enrollment is not authentication, consent acquisition or proof of the trusted surface's display.

The budget is cumulative across the agreement, not reset each month. Count and amount are charged when first reservation commits, not when a Success Receipt arrives. reserved/processing/unknown/Success/Error all retain allowance. Retry, timeout, crash, expiry, revocation or presumed refund never releases a slot.

## Current authority and atomic state

`LongSQLiteStore` uses an explicit new **schema3** with the optional existing`sqlite3=2.10.2` driver. Normal startup opens an existing protected database; missing/corrupt/wrong schema has no repair/reset/memory fallback. Schema1/2 stores reject long profiles, and do not auto-upgrade or migrate.

Initial enrollment pins immutable agreement bounds, full Checkout and Payment economic terms, authority principal identities/purposes/tenant, limits and windows. Stable tenant/merchant/consent/period/operation/order IDs come from authenticated business state, never client retry UUIDs or wire hashes. A new client-generated consent ID is not evidence of a new authorization. The same signed Root cannot enroll another merchant/consent in that tenant; alias tombstones survive revocation/replacement.

The ledger has a protected authority binding and monotonic epoch. Raw verification binds Payment Provider and Agent keys to the current Host-selected Checkout registry; it cannot self-select enrollment from a token. Reservation checks the active agreement, current Root, exact current authority binding and actual period, then inserts the attempt and charges quota in the same SQLite transaction. Start re-verifies complete raw inputs, requires the same first signed wires, current binding/accepted epoch and a fenced state transition. Execution validity intersects content, fresh Checkout/Payment proof, registry/key/challenge, period and immutable agreement ends. `Execution.valid_until` exposes that checked deadline. Applications must dispatch promptly and enforce the deadline/current authority at their processor boundary; the SDK cannot revoke an already returned object or atomically commit a remote payment with SQLite.

**An epoch is authoritative only for this ledger.** The application must authenticate the registry/consent/order source and synchronize external changes before making it available for acceptance/start. This SDK supplies no revocation network, freshness oracle, background polling or cross-database atomic transaction. A stale but still time-valid external snapshot is not automatically detected. Registry-source generation, anti-rollback and observation freshness are application guarantees; the ledger epoch does not manufacture those guarantees from a caller-provided snapshot. If the feed is unknown/stale, the protected backend must invalidate authority and stop dispatch. A separate external check followed later by an independent DB write does not establish atomic current authority.

Protected backend operations (not request-facing flags):

| API | Behavior |
| --- | --- |
| `usage(**series_scope)` | Reservation totals, current Root reference/epoch and active flags. Not settled spend or payment permission. |
| `update_authority!(**series_scope, expected_epoch:, trust_json:, selection_json:, verified_at:)` | CAS refresh for the same active Root's Issuer/Agent keys and immutable principals; Merchant key/registry version may change. Identical binding is idempotent. Changed binding increments epoch. |
| `invalidate_authority!(**series_scope, expected_epoch:)` | Holds all new acceptance/start and increments epoch. A trusted fresh update may resume authority; old-epoch Tickets do not revive. |
| `replace_root!(**series_scope, expected_epoch:, expected_root_reference:, payment_open:, checkout_open:, trust_json:, selection_json:, verified_at:)` | Authenticates new full pair/current keys. Preserves full economic contract/principals and original agreement end; retires old alias and increments epoch without resetting quota. |
| `revoke_root!(**series_scope, expected_epoch:)` | Permanently disables that Root alias and holds authority. A different authorized replacement may continue the same still-active agreement/history. |
| `revoke_series!(**series_scope)` | Permanently stops the agreement. Re-enrollment/replacement cannot reactivate it or refund allowance. |

Canonical key fingerprints use the existing SHA256 of canonical public SPKI **PEM bytes**, not arbitrary PEM variants or DER bytes. Root replacement permits new Issuer/Agent keys for the same principals and changed technical parent references/time/cnf, but rejects changed products/quantities/candidates/payee/instrument/currency/fixed terms/budget/count/profile or extended agreement end. New Root signatures do not mean a new budget.

Updating authority or replacing a Root conservatively invalidates old-generation reserved Tickets. No takeover, retry capability recovery or unstarted-attempt refund is supplied; operators must reconcile an uncertain attempt. Existing processing/unknown outcomes retain the original wires, processor key and Receipt trust context. An authentic original Receipt can finalize after expiry/revocation but never grants a new Ticket. Historical key compromise cannot be dated by Receipt.iat alone; trusted processor query/quarantine policy remains an application responsibility.

One authoritative durable local ledger must serve all workers. DB loss/rollback, stale restore, per-worker DBs, split-brain or unreviewed history import can invalidate protection. Original schema1/2 usage cannot be discarded by provisioning an empty schema3; migration/import requires a separately reviewed reconciliation process, and unknown history is HOLD. No external exactly-once/production durability/settlement guarantee is made.

## Evidence and exclusions

Tests cover same Open pair over all12leap-year months, genuine signed negatives, old profile lifetime isolation, independent8process races with count/budget separated, fsynced mock effects, actual SIGKILL, rollback, Root/Issuer/Agent replacement, authority invalidation, revocation and historical Receipt references. These are synthetic tests, not real Issuer provenance, consent or processor execution.

Pinned official Python comparison uses actual SDK KB constructors, facade presentations, chain/typed/Schema verification and independent expected aud/nonce, with explicit JSON-mode Enum/integer-JPY/profile/inline adapters. Its known cadence/JPY/proof-age disagreements are recorded instead of weakened into parity. Unmodified high-level facade support, arbitrary AP2 formats, unknown constraints, other timezones/currencies, selective long profiles and real payment are outside this contract.
