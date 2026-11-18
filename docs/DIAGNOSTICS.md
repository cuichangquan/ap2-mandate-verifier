# Diagnostics

Checkout/InputBuilder introduced in 0.4.0; Payment flow added in the published 1.7.0.

Diagnostics help you inspect a failed check without reading gem internals. They
are supplemental: existing calls, status/code, fixed profile, Fail Closed and
non-success `evidence == nil` are unchanged. A successful Checkout/InputBuilder result has
`diagnostic == nil`. A diagnostic failure also returns nil and cannot change a
verification result. Never make a payment/authorization decision from a hint.

## Before / after

```ruby
result = AP2MandateVerifier::InputBuilder.verify(**host_arguments)
# Before (still supported):
puts "#{result.status}/#{result.code}"
# After:
if (diagnostic = result.diagnostic)
  puts diagnostic.to_h(locale: :en) # :ja for Japanese
  # stage: :input_assembly, field: "order.currency",
  # reason: :missing_required_field, hint: "Supply ..."
end
```

`Diagnostic` is immutable, with `stage`, `field`, `reason`, `hint(locale: :en)`
and `to_h(locale: :en)` readers. `diagnostic[:stage]` etc. also work (English
hint). Unsupported locales fall back to English. Machine identifiers are not
translated; applications may translate them themselves. Hints are guidance,
not stable text for matching. New diagnostic detail may be added in later
versions. Continue to use status/code for the verifier outcome.

Pure Builder helpers (`trust`, `restore_trust`, `prepare`, `restore`, `inputs`)
still raise `InputBuilder::Invalid < ArgumentError` for malformed input. Rescue
it and inspect `error.diagnostic`; do not treat an exception as success.
Unavailable dependency errors retain their existing exception types. Do not log
raw inputs, arbitrary provider exception messages, or full exception chains.

## What to check

| Diagnostic | Meaning and next check |
| --- | --- |
| `input_assembly / order.currency / missing_required_field` | Obtain currency from independent current order data. |
| `input_assembly / order.expected_total / invalid_type` | Pass an Integer in minor units, not a formatted price String. |
| `input_assembly / order / unknown_field` | Compare with documented order fields; the unknown name is deliberately withheld. |
| `input_assembly / saved_challenge / unsupported_saved_format` | Check saved format/profile version compatibility. Never edit the saved version to force acceptance. |
| `host_binding / nil / host_binding_mismatch` | Compare saved challenge with independent current order, trust, issuer and original wire digests. The exact mismatching member is not identified. |
| `purchase_binding / nil / invalid_purchase_time` | Check independent clock, signed Open/Closed validity and terminal proof window. The code does not establish which time source is wrong. |
| `verification_unavailable / nil / <existing code>` | Verification could not finish. Check supported dependencies/runtime; do not label business data invalid. |
| `verification / nil / undetermined` | No safe precise diagnosis is available. Inspect the API contract and status/code. |

A stage names a failed check category, not an attested execution trace. In
particular, the legacy `invalid_root_signature` code can arise when checking
Root, Agent or Merchant signatures: `signature_verification` deliberately does
not name a specific signer. No hint identifies a malicious actor or proves a
root cause. Missing fields take precedence over unknown fields. Bounded graph,
parse or lower-level validation failures may have `field == nil` and a generic
reason. Only one diagnostic is returned; later checks may not have run.

The catalog covers every existing Result code: JSON/byte checks, signatures,
Root disclosures, purchase/delegation binding, scoped schema/constraints,
trust selection and Host/challenge checks. Legacy `unverified` results receive
scope guidance, not full-verification success. Diagnostic fields, reasons and
hints come from a closed catalog. No values, arbitrary field names, signed
wires, public/private keys, nonce, PII or stack traces are retained or emitted.
The diagnostic is not Evidence and cannot reconstruct original inputs.

## Try the published release locally

Normally install published 0.4.0 in an environment with supported MRI
(3.4.12 or 4.0.9) and pinned dependencies. Run the examples from a repository checkout:

```sh
gem install ap2_mandate_verifier --version 0.4.0
ruby examples/input_builder.rb valid
ruby examples/input_builder.rb tampered
ruby examples/input_builder.rb expired
ruby examples/input_builder.rb missing_currency
ruby examples/input_builder.rb wrong_total_type
ruby examples/input_builder.rb unknown_order_field
ruby examples/input_builder.rb unsupported_saved_format
```

The successful example returns Evidence, tampered returns
`host_binding_mismatch`, expired returns `invalid_purchase_time`, and the four
assembly examples return `rejected / invalid_host_context` with diagnostic
reasons `missing_required_field`, `invalid_type`, `unknown_field` and
`unsupported_saved_format`. Synthetic fixture clocks are intentional. See
[InputBuilder](INPUT_BUILDER.md) for data mapping and storage responsibilities.
Gem availability does not imply real Issuer interoperability, production
authorization or Phase 2-B GO.

## Payment flow (published 1.7.0)

The original 0.4.0 sections above describe Checkout/InputBuilder diagnostics and
historical evidence, not the version to install for this addition. Payment and
Receipt `code`, predicates and exception contracts are unchanged. Direct,
conditional, selective and Long verification expose `result.diagnostic`;
successful Payment verification has nil. Authentic matching Error Receipts are
**verified**, with `payment_rejected? == true`, `payment_succeeded? == false`,
and an explanatory `reported_error` diagnostic. This is not retry permission.

```ruby
payment = AP2MandateVerifier::Payment.verify(**payment_inputs)
puts payment.code # still :payment_verification_failed on every failure
puts payment.diagnostic&.to_h(locale: :en)
# e.g. {stage: :payment_verification, field: nil,
#       reason: :payment_time_mismatch, hint: "..."}

# Choose ONE start entry point per attempt, never both for diagnosis.
observation = service.start_with_diagnostic(ticket: ticket,
  verification_inputs: fresh_inputs)
execution = observation.execution # Execution or nil
puts observation.diagnostic&.to_h(locale: :en)
# Existing service.start(...) still returns exactly Execution or nil.
# Do not dispatch when execution is nil. Nil proves neither non-execution
# nor that repeating start/payment is safe.

receipt = AP2MandateVerifier::PaymentReceipt.verify(**receipt_inputs)
if receipt.verified?
  puts receipt.payment_rejected? # true for an authentic Error Receipt
else
  puts receipt.code # :payment_receipt_verification_failed
end
puts receipt.diagnostic&.to_h(locale: :en)
```

`payment_inputs`, `fresh_inputs`, `receipt_inputs`, `service` and `ticket` above
come from the [Ruby integration example](RUBY_INTEGRATION.md), not received hints.
The application supplies independent trust, clock, order, protected approval and
persistent storage. The excerpt omits those inputs and all processor operations.
No diagnostic getter repeats verification, reservation, start, settlement or reads
additional storage. An absent diagnostic is supported (old versions, success or
failed diagnostic generation); it never turns failure into success.

### Stages, facts and limits

| Stage | Representative reason | Fact established |
| --- | --- | --- |
| `payment_verification` | `checkout_not_verified` | Nested Checkout verification did not succeed, not proof of its cause |
| `payment_verification` | `checkout_binding_mismatch` | An existing Checkout/payment binding comparison failed |
| `payment_verification` | `payment_time_mismatch` | Existing Payment content validity comparison failed |
| `payment_verification` | `payment_conditions_mismatch` | An existing complete-profile payment condition failed |
| `payment_verification` | `payment_binding_mismatch` | Expected payment or proof binding comparison failed |
| `payment_receipt_verification` | `receipt_reference_mismatch` | Existing issuer/payment-ID/original Payment reference comparison failed |
| `payment_receipt_verification` | `receipt_time_mismatch` | Existing Receipt or independent time window comparison failed |
| `payment_receipt_verification` | `reported_error` | Authentic matching Receipt reported Error, not verified settlement success |
| `payment_acceptance` | `pending`, `unknown`, `receipt_error` | Existing result status only, no extra state lookup |
| `payment_acceptance` | `conflict`, `unavailable` | Store reported that class of error, not a specific cause or commit state |
| `payment_execution` | `saved_binding_mismatch` | Fresh instruction or original signed wires differ from saved state |
| `payment_execution` | `undetermined` | No execution handle; cannot distinguish expiry, competing start or uncertain commit |

`invalid_arguments` identifies rejected keyword shape on Payment/Receipt/Selective
verify. `signed_input_rejected` describes a typed signed-input rejection, **not
necessarily a cryptographic signature failure**. `verification_unavailable`
describes an explicitly unavailable dependency/check. Other exceptions use
`undetermined`, never exception-message matching. Diagnostics do not disclose raw
Mandates, keys, nonce, candidate sets, payment data or exception text.

The same Payment checks feed Direct/conditional, policy, recurring and Long
profiles, but **coverage is deliberately not exhaustive**: malformed shapes,
selective disclosure checks, detailed PISP/date policies, Long authority and
period policies can remain `undetermined`. A store's rejected quota reservation
does not distinguish exhausted budget/count from missing/revoked approval or
other invalid protected state. Inspect protected approval, current period/quota
and stored attempts according to the store guide, without assuming any one cause.
Receipt validation does not establish real processor settlement. Unknown results,
timeouts and authentic Error never authorize automatic retries or quota release.

### Persistence and concurrency

`StartResult` is immutable and call-local; there is no `last_diagnostic` on a
service and no shared thread/fiber diagnostic slot. `Result#diagnostic` on
acceptance also covers finish, reconcile, lookup and unknown results. Existing
store interfaces and persisted formats are unchanged. Custom adapters returning
nonstandard result objects need not expose diagnostics; applications may use
`respond_to?(:diagnostic)` and handle nil.

Persist catalog identifiers only. `Diagnostic.payment_flow(stage, reason)`
returns a trusted immutable catalog entry or nil for an unknown pair. Its field
is always nil. Validate the stored triple against that result; do not render
arbitrary stored hints, translate unknown values into a cause, or automatically
start recovery while reading diagnostics. Identifiers may gain detail in later
minor versions; keep an unknown/nil fallback and use existing status/code for
control flow. Do not use hints or diagnostic presence as authorization.
