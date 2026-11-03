# 1.1.0 candidate — publication requires Owner approval

Status: unpublished candidate. Published 1.0.0 remains available and unchanged. The source version 1.1.0 is a proposal for additive Payment APIs under the existing 1.x Checkout contract. Do not tag, publish GitHub Release, push/yank RubyGems, announce or deploy on the basis of this document.

## Proposed GitHub Release body

Adds framework-independent Direct and conditional Payment Mandates, strict payment conditions/Checkout binding, original-wire persistence/reference helpers, and signed Success/Error Payment Receipts. Existing Checkout API defaults/profiles/results remain unchanged. Payment verification authenticates supported facts; applications still own consent/trust, durable atomic one-use state and payment execution.

```ruby
payment = AP2MandateVerifier::Payment.details(
  checkout_jwt: original_checkout_from_trusted_order,
  trusted_merchant_public_key_pem: registered_merchant_key,
  expected_merchant_id: current_merchant_id,
  payment_instrument: selected_instrument_from_application)
# After app authentication and consent: issue_direct(payment: payment,
# approved_payment: protected_consent_record, ...). See examples/payment.rb.
```

Supported: one immediate payment, integer minor units, exact payee/instrument and amount range, optional fixed values, one Agent hop. General selective disclosure, recurrence/budgets, PISP/execution_date/risk_data, live processors and A2A/MCP are outside this profile and reject. See [Payment API and specification decisions](PAYMENT.md).

## Approval checklist and publication procedure

1. Confirm latest reviewed/merged source SHA, package contents/source equality, Gem filename/bytes/SHA256 and immutable evidence record in Issue #235. Verify both supported MRI endpoint tests, installed examples, existing Checkout regression, official pinned SDK/Schema bidirectional interoperability and latest-HEAD independent review. Any unresolved substantive finding or missing required test means HOLD.
2. Owner explicitly chooses version and approves the exact artifact SHA256, tag/Release and publication/announcement separately. Until then stop. If version/source/artifact changes, rebuild once and repeat affected validation/review; do not reuse approval for a different artifact.
3. With separate approval, verify `sha256sum` of the approved Gem and `gem specification ... --local`; push that exact file using Owner-controlled RubyGems credentials. Do not rebuild during publication. Create/push the approved tag on the recorded source SHA and publish the approved Release body only when separately authorized.
4. After approved publication, fetch public RubyGems version metadata and distribution, compare SHA256 and dependency/file metadata, install it into a new isolated environment, run packaged Direct/conditional examples and both Receipt outcomes, check README links/version claims. Record evidence before calling publication verified. Unknown outcomes require reconciliation, never blind retry/yank.

No publication/deployment workflow is added. Existing product CI is a read-only source/package validation workflow. Existing research HOLDs remain independent.

Runtime dependencies remain pinned: json=2.19.9, jwt=3.3.0, base64=0.3.0, openssl=4.0.2, digest=3.2.1. MRI test endpoints remain 3.4.12 and 4.0.9; installation range >=3.4.12,<4.1 is not a claim of formal support for every intermediate Ruby.
