# Failure diagnostics (unreleased 0.4.0)

Diagnostics help you inspect a failed check without reading gem internals. They
are supplemental: existing calls, status/code, fixed profile, Fail Closed and
non-success `evidence == nil` are unchanged. A successful result has
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

## Try the candidate locally

Published 0.3.0 remains unchanged. Build and normally install the unpublished
candidate from this checkout in an isolated environment with the supported
MRI (3.4.12 or 4.0.9) and pinned dependencies:

```sh
gem build ap2_mandate_verifier.gemspec
gem install --local --no-document ./ap2_mandate_verifier-0.4.0.gem
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
No publication, real Issuer connection, production authorization or Phase 2-B
GO is implied.
