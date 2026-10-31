# 0.6.0 candidate — publication requires Owner decision

This compatible feature release adds an explicitly selected bounded multi-item
profile. Published 0.5.0 bytes, tags and Release remain unchanged. Exact final
main SHA, Gem SHA256/size and payload manifest are supplied by the final task
report after integration and both-runtime ordinary-install verification.

## Owner publication checklist

1. Review final main SHA, clean latest-HEAD review, CI, candidate source/payload
   equality and [validation record](MULTI_ITEM_VALIDATION.md). Check the
   [documented SDK differences](MULTI_ITEM_INTEROP.md) and Host responsibilities.
2. Decide whether to publish the exact verified 0.6.0 artifact. Recompute its
   SHA256 and size against the final manifest; avoid rebuilding by accident.
3. Only after explicit publication approval, perform the intended RubyGems push,
   create the public `v0.6.0` tag at that source SHA and publish the GitHub Release.
   Verify registry bytes/version/dependencies and tag source independently.
4. Update the demo's stable version/lock/checksum through its own reviewed change
   after the version is actually available. Candidate-only startup remains useful
   before that point. No public Web deployment is part of this task.

## Future Release text draft (not a created Release)

0.6.0 supports a single merchant/currency with multiple products and differing
quantities through Checkout signing, saved challenge restoration, complete
verification, Evidence, and authentic whole-Mandate Success/Error Receipts.

```ruby
profile = "ap2.checkout.single_merchant_multi_item"
signed = AP2MandateVerifier::CheckoutJWT.sign(
  checkout: checkout, signer: signer, public_key_pem: merchant_public_key,
  profile_ref: profile)
trust = AP2MandateVerifier::InputBuilder.trust(**host_trust, profile_ref: profile)
# Prepare and persist an authenticated challenge before receiving the response.
# verification_inputs includes that saved challenge and independent current order.
result = AP2MandateVerifier::InputBuilder.verify(**verification_inputs)
puts result.success?
```

The complete synthetic [runnable API example](../examples/multi_item_checkout.rb)
prints:

```text
checkout verified=true profile=ap2.checkout.single_merchant_multi_item
receipt Success: verified=true purchase_succeeded=true
receipt Error: verified=true purchase_succeeded=false
```

Existing callers keep `ap2.checkout.single_merchant_sku` v1 by default, with its
original definition/hash and accepted scope. The new profile requires explicit
Host selection and new saved challenges; never repair old saved digests to
migrate. Verification success remains separate from Host ALLOW/payment success.

Details: [new profile](MULTI_ITEM_CHECKOUT.md), [InputBuilder](INPUT_BUILDER.md),
[signing/Receipt](MERCHANT_SIGNING.md), [support contract](SUPPORT_CONTRACT.md),
[validation](MULTI_ITEM_VALIDATION.md), [interop differences](MULTI_ITEM_INTEROP.md).
