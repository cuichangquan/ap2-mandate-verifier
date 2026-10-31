# Merchant Checkout signing and Receipt — published 0.5.0

Published [0.5.0](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.5.0) includes these APIs. [Complete runnable synthetic example](../examples/merchant_signing.rb). The example is repository content, not part of the installed Gem.

## Scope and responsibility

This additive API starts from the existing single Merchant / single SKU Checkout
profile, ES256 with a P-256 key. It leaves `Verifier`, `Result`, `Evidence`,
`InputBuilder` and diagnostics unchanged. A merchant signature attests to the
merchant-authored order bytes; it does not create user authorization, establish
merchant enrollment, persist an order, consume a nonce or make a payment.

The adopted AP2 source remains
[`b4587ac1d055888a73b4b21750973cffba961793`](https://github.com/google-agentic-commerce/AP2/tree/b4587ac1d055888a73b4b21750973cffba961793).
Checkout-specific ordering is defined by the existing local fixed profile, not
all UCP shapes. Unsupported fields, multiple items, nonempty links and unsupported
currencies are rejected. Amounts are integer minor units; totals must agree.

## Minimal executable example

Run from this repository with the documented runtime and dependencies:

```ruby
require "ap2_mandate_verifier"
require "openssl"

key = OpenSSL::PKey::EC.generate("prime256v1") # Test only; app owns real keys.
totals = [{"type" => "subtotal", "amount" => 100}, {"type" => "total", "amount" => 100}]
checkout = {
  "id" => "order-1", "merchant" => {"id" => "shop", "name" => "Demo shop"},
  "status" => "ready_for_complete", "currency" => "USD", "links" => [],
  "line_items" => [{"id" => "line-1", "item" => {"id" => "sku", "title" => "Sample", "price" => 100},
                    "quantity" => 1, "totals" => totals}], "totals" => totals
}
signing = AP2MandateVerifier::CheckoutJWT
signed = signing.sign(checkout: checkout, signer: signing.es256_signer(private_key: key),
                      public_key_pem: key.public_to_pem)
puts signed.jwt.split(".").length # 3
puts signed.checkout_hash.length  # 43
```

`signed.jwt` is the frozen original compact JWT to transmit and retain. Supply
that exact String as `host_checkout_jws` to InputBuilder and Verifier; supply
`signed.checkout_hash` when a test or external Agent binds a Closed Mandate.
The Gem does not issue a product Mandate API. Re-encoding claims or signing again
creates different original wire, even when the order is the same.

`signer.call(signing_input)` receives the frozen ASCII `header.payload` and returns
64 binary bytes containing the JOSE ES256 `r || s` signature. An HSM/remote
adapter must implement this interface and handle its own authorization, timeouts
and availability. The Gem itself performs no network operation. The selected
independent canonical public SPKI PEM verifies the final signature before a
`Signed` object is returned. The token cannot choose its own verification key.
`es256_signer` is a convenience closure over an application-owned OpenSSL P-256
private key; it never serializes the private key.

Invalid orders, wrong keys, unsupported keys, failed signer calls and invalid
signer output raise `CheckoutJWT::Invalid` with a fixed message and no original
cause. They never return a signed result. All application key lifecycle and trust
registration remain outside the Gem.

## Checkout Receipt contract and specification discrepancy

Checkout-specific Schema uses `status: Success/Error`, `iss`, `iat`, `reference`;
Success requires `order_id`; Error requires `error` and `error_description`.
The generic authorization prose instead describes `result: success/error`.
Checkout schema and generated model do not strictly forbid fields from the other
branch; a stricter local profile must be documented as such.

Normative authorization/dispute text requires the final closed SD-JWT hash in
the same manner as `sd_hash`. Fixed SDK `sdjwt/common.py` includes the terminal
`~` even without disclosures. `MandateClient.get_closed_mandate_jwt` instead
extracts only compact JWT, discarding disclosures and `~`, and recommends hashing
that. These are distinct hashes even in the existing inline terminal profile.
The adopted contract prioritizes normative `sd_hash`: explicit original
closed SD-JWT input `<terminal_jws>~`, default SHA256/base64url without padding.
This is the existing inline terminal profile serialized as its final SD-JWT.
The caller must supply this exact representation; compact-only input is rejected.
The Gem never adds a missing `~`, extracts a leaf from a chain, or guesses a
reference from unparseable input. Disclosures, extra hops, `_sd_alg` extensions
and unsupported terminal claims are rejected. Bounded `kid` is accepted exactly
as in the existing verifier but never selects a trusted key. The entire input,
including `kid` bytes and terminal `~`, contributes to the hash.

The generic `result` spelling is not accepted. Success permits only `order_id`,
and Error permits only `error` and `error_description` alongside common fields.
This branch exclusivity, nonempty bounded strings and rejection of unknown
fields are explicit local-profile constraints, stronger than the base Schema.
`iat` is an integer epoch. `not_before <= iat <= verified_at <= not_after` is an
explicit application verification window, not an upstream freshness guarantee.
The application owns trusted key enrollment, expected issuer and time policy.

```ruby
receipt = AP2MandateVerifier::CheckoutReceipt
# closed_sd_jwt is the exact received final `<terminal_jws>~` String.
rejection = receipt.sign(closed_sd_jwt: closed_sd_jwt, issuer: "shop",
  outcome: "Error", error: "declined", error_description: "Application declined",
  issued_at: now, signer: signing.es256_signer(private_key: key),
  public_key_pem: key.public_to_pem)
checked = receipt.verify(jwt: rejection.jwt, closed_sd_jwt: closed_sd_jwt,
  trusted_public_key_pem: independently_registered_public_pem, expected_issuer: "shop",
  not_before: now - 60, not_after: now + 60, verified_at: now)
p [checked.verified?, checked.purchase_succeeded?, checked.purchase_rejected?]
# => [true, false, true]
```

A Success call replaces Error fields with `outcome: "Success", order_id: "order-1"`.
`Signed#jwt` is the immutable transmitted receipt wire and `Signed#reference` its
Mandate reference. Invalid creation raises `CheckoutReceipt::Invalid` without
input values or original cause. Verification returns an immutable
`CheckoutReceipt::Verification`: `verified?`, `outcome` (`Success` or `Error`),
`purchase_succeeded?`, `purchase_rejected?`, `order_id`, `error`,
`error_description`, and a `code`. Failure exposes no untrusted claim values and
returns false for all three predicates. It never returns existing Verifier
`Result`/`Evidence` or modifies their status/code meanings.

Reference calculation validates supported syntax and preserves byte identity;
it does not verify the Mandate's authority. Receipt authenticity does not verify
Mandate authorization or evidence of payment/order execution. Obtain authorization
through the existing complete verifier plus Host responsibilities separately.
The application must explicitly provide its final business outcome; no Verifier
success is automatically converted into a Success Receipt.

## Current verification

Dedicated offline Docker checks exercise original-wire hashing, signer failures,
wrong keys, unsupported input and complete existing Verifier/InputBuilder
integration. `test/merchant_interop.py` uses the fixed official Python SDK's
`create_jwt` and `verify_jwt`, compares decoded checkout claims and independently
computes the original JWT SHA256; reverse-direction wrong-key verification must
reject. Synthetic private keys stay in process memory. The scripts do not imply
real issuer provenance or universal AP2 conformance.

The fixed SDK `ReceiptClient.verify_receipt` checks signature/model/callback but
not expected issuer or application time policy. Our interoperability test compares
these separately on the Ruby side and verifies every callback argument against
the independently computed expected reference; a JWT-only hash must fail.
The SDK annotation says cryptography public key, but `jwt_helper.verify_jwt` uses
jwcrypto; the test supplies a public `JWK` adapter without skipping verification.
Success creation uses SDK ReceiptClient with a deterministic test clock; Error
uses the generated CheckoutReceipt model and official signing helper. SDK model
validation is also checked against original JSON Schema. No unconditional
success callback or reference-validation bypass is used.

The pinned Receipt Schema references `types/receipt_status.json`, while the
referenced file declares `$id` `.../schemas/receipt-status.json`. The local
Schema registry explicitly registers the reference URI as an alias for the
unaltered pinned file, plus declared IDs; it performs no network fallback.
This reference-resolution adjustment is recorded by the test output and does
not rewrite Schema conditions or skip validation. Checkout and Closed Mandate
payloads are also validated with the unaltered original JSON Schemas.
