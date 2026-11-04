# Payment acceptance and idempotency support (published1.5.0)

[Verified public distribution](POST_RELEASE_150.md).

This opt-in application-side coordinator separates three events: cryptographic verification, durable reservation of an approved business occurrence, and an external payment processor’s outcome. Existing1.x verifiers and their result meanings remain unchanged. The SDK does not call a processor, transfer funds or promise distributed exactly-once execution.

## Stable identity and protected approval

A Checkout JWT hash (`transaction_id`), final Mandate hash or Receipt reference changes when an otherwise identical instruction is re-signed. None is sufficient as the business idempotency key. Use independently authenticated Host identifiers: `tenant_id`, `merchant_id` (the actual authority/account namespace), stable `operation_id`, `approval_id`, approved `occurrence_id` and `order_id`. Never allocate a fresh random operation/occurrence for each request or retry.

A protected Host approval backend must enroll the exact Checkout/payment semantics and pinned Receipt trust context before acceptance. `accept` cannot enroll or change authority from a received `approved: true` or arbitrary occurrence. The reference adapter enforces uniqueness of the business operation and of the approved occurrence. A secondary final-Closed-reference guard prevents dispatching the exact same final instruction under another occurrence. Wire hashes remain audit/Receipt bindings, not the sole replay key.

Canonical terms include the complete supported Checkout payload and payment fields. Only the technical Checkout-JWT hash is excluded from payment terms; parsed execution dates are normalized to exact instants. Changed amounts, products, provider/instrument or other terms conflict rather than create a new slot. JSON object key order is normalized; array order remains significant, so reordered business payload arrays can conservatively conflict. The original signed wires, Receipt reference and processor idempotency key stay pinned to the first reservation.

## Minimal integration

The optional SQLite reference adapter uses the separately installed `sqlite3 = 2.10.2` driver. It is not a new base-Gem runtime dependency. The ordinary verifier entry loads without SQLite. Missing driver/storage returns unavailable; there is no in-memory fallback.

```ruby
m = AP2MandateVerifier::PaymentAcceptance
# Protected one-time offline bootstrap only. Fails if the file already exists.
store = m::SQLiteStore.create(path: "/srv/app/payment_acceptance.sqlite3")
# Normal startup opens an EXISTING database; a lost file must never reset a ledger.
store = m::SQLiteStore.new(path: "/srv/app/payment_acceptance.sqlite3")
service = m::Service.new(store: store)

# All six IDs come from authenticated current application state.
scope = {tenant_id: "tenant-A", merchant_id: "shop", operation_id: "order-42/payment-1",
         approval_id: "consent-99", occurrence_id: "payment-1", order_id: "order-42"}
# Call this only in the protected approval backend, never a request-driven flag.
store.authorize!(**scope, mode: :direct,
  profile_ref: AP2MandateVerifier::Payment::PROFILE_REF,
  checkout: approved_checkout, payment: approved_payment,
  receipt_context: {trusted_public_key_pem: processor_public_key,
    expected_issuer: "processor", expected_payment_id: "payment-42",
    not_before: receipt_window_start, not_after: receipt_window_end})

accepted = service.accept(**scope, mode: :direct, verification_inputs: raw_payment_verify_inputs)
if accepted.ticket
  # Fresh authenticated Host/trust/order/challenge/clock inputs; first wires unchanged.
  dispatch = service.start(ticket: accepted.ticket, verification_inputs: fresh_verify_inputs)
  if dispatch
    # Application-owned processor call MUST reuse dispatch.processor_key.
    # The SDK itself performs no network request or payment.
  end
end
```

`mode` is `:direct`, `:conditional` or `:selective`. `verification_inputs` is the complete raw keyword hash of the corresponding existing `Payment.verify` or `SelectivePayment.verify`, including1.4 profile/context options where applicable. A caller-created verification result is not accepted as evidence. Current supported forms are fully verified; unsupported recurrence/budget formats remain rejected.

Enrollment, active authorization/occurrence checks, semantic comparison and reservation occur atomically in the reference DB. An immutable grant cannot be silently replaced; `revoke!` disables it without releasing an existing attempt. `start` reruns the full existing verification pipeline with fresh trusted inputs and requires every original signed Checkout/Payment wire to match. Payment expiry alone is insufficient: Checkout, trust and challenge can expire earlier. Grant/current-order/nonce checks in a production adapter must share its authoritative transaction with reservation/start CAS. A check in one DB followed by a CAS in another leaves a race; the reference grant is not a live connection to an external order or revocation service.

## States, retries and uncertain outcomes

| Observation | Meaning and permitted next step |
| --- | --- |
| `reserved` with opaque Ticket | First committed claim only; not purchase permission. Fresh `start` may yield one dispatch-coordination handle. |
| `pending` | Existing reservation/processing; no new Ticket or start rights. Read its stored original outcome/key. |
| `unknown` | Execution outcome uncertain; never automatically release, expire or take over. Query/reconcile using the original processor key. |
| `receipt_success` / `receipt_error` | Authentic reported Receipt outcome; no independent settlement or no-charge proof. No automatic re-execution. |
| `conflict` | Same operation/grant with different terms, scope or original instruction usage. No fresh slot. |
| `rejected` / `unavailable` | No capability. Unknown DB commit outcomes must not be treated as permission or retried as a new operation. |

Only the first successful fenced `reserved → processing` CAS returns an `Execution` handle. A crash after that commit but before a processor call can leave zero executions and a pending record. A crash after the call can leave one execution and the same pending record. The SDK cannot distinguish those cases by timeout. It intentionally provides no lease takeover, automatic release or re-execution API. Processor idempotency/lookup semantics and application reconciliation are necessary; database atomicity alone cannot cover an external side effect.

For an expired original presentation, use authenticated `lookup(**scope)` to retrieve existing state; it does not bypass fresh verification to create a new claim. Retrying with a re-signed equivalent presentation returns the first record without a Ticket. Never attach its old Receipt to a replacement Closed/Open wire. Returned first signed wires/reference describe the original attempt; no hidden candidate universe is reconstructed.

## Receipt and recovery

`finish(ticket:, receipt_jwt:, verified_at:)` authenticates a Receipt against the grant’s pinned issuer/key/payment ID/window and the first exact Closed bytes. Receipt time cannot predate successful start. `unknown(ticket:)` preserves an uncertain processing record. After a worker restart, `reconcile(**scope, receipt_jwt:, verified_at:)` may finalize processing/unknown with the same checks, but cannot return a Ticket or start again. `lookup(**scope)` is read-only.

A Receipt may arrive after the Mandate expires; its independently pinned Receipt window is distinct. Conflicting Receipt bytes/outcomes do not overwrite a completed record. Error Receipt, missing Receipt or response loss never frees the operation. Key rotation or changed Receipt trust after enrollment needs an explicit application recovery policy; the reference adapter does not silently replace trust.

## Reuse and new transactions

This API does not consume every Open Mandate globally. A reusable supported Open can lead to fresh Closed instructions for separately authorized new business occurrences. Those occurrences must be independently approved/enrolled and use their own stable operation identity. Arbitrary retry UUIDs are not new authority. The exact same final Closed cannot be dispatched twice under this local acceptance policy. Official recurrence/budget enforcement is not added by this release; applications must not infer reusable authority from an unsupported wire format.

## Persistence and adapter contract

SQLite is a local single-host reference using transactions, strict supported schema/index/FK checks, unique constraints, fencing and synchronous durable commits. Explicit initialization creates a private file; reopening requires the existing expected database. Missing/corrupt/unsupported schema is unavailable, with no repair/reset/migration or memory fallback. Use a protected local filesystem, one authoritative ledger for all workers and separate connections after fork. Do not create one ledger per worker or request.

Database deletion, rollback to an old backup, split-brain copies, broken filesystem locking/fsync, adversarial DB edits, NFS/multi-host replication or operator re-enrollment can invalidate protection. Restore must stop dispatch and reconcile against the processor. SQLite is not a distributed consensus service or a replacement for disaster recovery. Stored Checkout/payment terms and first wires may contain sensitive information; apply application access controls, retention and at-rest protection. Do not log Tickets/fences or raw payloads.

Custom adapters may integrate existing DB/Redis infrastructure but must implement atomic protected enrollment/uniqueness, read-and-claim, active-grant/order/occurrence CAS, no capability before durable commit, first-wire/processor-key retention, and monotonic fenced finalization. No check-then-insert, timeout reset or guessed success on I/O/commit error. They need their own independent concurrency/crash/durability tests; this SDK cannot attest an adapter’s persistence guarantees.

## Official evidence and guarantees

Adopted AP2 pin remains `b4587ac1d055888a73b4b21750973cffba961793`. Relevant docs/schema/SDK are byte-identical to observed official main `e1ea56db72a6385bce3e5c1112b3a56ce60acb43`; current changes there are outside those paths. [Issue346](https://github.com/google-agentic-commerce/AP2/issues/346), [Issue328](https://github.com/google-agentic-commerce/AP2/issues/328) and [Issue339](https://github.com/google-agentic-commerce/AP2/issues/339) remain discussions, not adopted requirements. [PR347](https://github.com/google-agentic-commerce/AP2/pull/347) adds sample reservations but does not establish stable business identity, terms binding and Receipt persistence as normative protocol behavior.

The [re-signing discussion](https://github.com/google-agentic-commerce/AP2/issues/346#issuecomment-6614173999) motivates stable merchant-scoped occurrences. AP2 still defines transaction_id from the Checkout JWT and Receipt reference from exact Closed bytes. Official SDK optional expected-Checkout bindings and hidden-constraint discussions do not relax this SDK’s existing strict verification. This local helper is application coordination around those cryptographic facts, not a new AP2 protocol or generic conformance/external exactly-once claim.
