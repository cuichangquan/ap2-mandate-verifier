# 0.6.0 — Multiple items and quantities

## Changes

A single merchant Checkout can now contain multiple products and differing
quantities through input preparation/save/restore/current-state verification,
Checkout signing, Evidence and whole-Mandate Success/Error Receipts.
Explicitly select `ap2.checkout.single_merchant_multi_item` v1. Its bounded
integer max-flow matching consumes every required and ordered unit exactly
once, including overlapping candidates and the same product on distinct lines.
A shortage in a later line is rejected with no Evidence.

## Short API example

Prerequisites: `require "ap2_mandate_verifier"`; `checkout` is a supported
multi-line order Hash, `signer` is the application's ES256 signing callback,
and `public_key_pem` is its independently supplied P-256 public key.
This excerpt signs the Checkout only. It does not issue a Mandate or grant a purchase.

```ruby
profile_ref = "ap2.checkout.single_merchant_multi_item"
signed = AP2MandateVerifier::CheckoutJWT.sign(
  checkout: checkout, signer: signer, public_key_pem: public_key_pem,
  profile_ref: profile_ref)
puts "checkout_segments=#{signed.jwt.split('.').length}"
```

Expected output:

```text
checkout_segments=3
```

The [complete runnable synthetic lifecycle](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/examples/multi_item_checkout.rb)
also constructs trust/challenges, saves/restores, verifies and checks genuine
Success/Error Receipts. Run it from a repository checkout with the published
0.6.0 Gem installed. Its first three output lines are:

```text
checkout verified=true profile=ap2.checkout.single_merchant_multi_item
receipt Success: verified=true purchase_succeeded=true
receipt Error: verified=true purchase_succeeded=false
```

## Compatibility and responsibilities

The default `ap2.checkout.single_merchant_sku` v1 keeps its original identifier,
definition, hash and one-line acceptance range. New-profile selection is explicit
when constructing trust, signing Checkouts and using Receipt APIs. Do not repair
old saved digests to migrate. Evidence is verification evidence, not Host purchase
permission or payment success; an authentic Error Receipt is still an Error.

New profile limits: eight lines, eight requirements and eight candidates per
requirement; one merchant/currency; integer minor-unit amounts; no tax/shipping/
discount engine. Formal MRI 3.4.12/4.0.9 and fixed runtime dependencies are unchanged.

## Details and measured differences

- [Profile, limits and migration](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/MULTI_ITEM_CHECKOUT.md)
- [InputBuilder](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/INPUT_BUILDER.md) and [signing/Receipt contract](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/MERCHANT_SIGNING.md)
- [Independent Python comparison](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/MULTI_ITEM_INTEROP.md): the fixed SDK can accept underfilled requirements or empty-candidate wildcards, and its compact-only Receipt helper differs from the adopted original terminal-plus-`~` reference. These differences are explicit; agreement is not manufactured by skipping checks.
- [Validation record](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/MULTI_ITEM_VALIDATION.md) and [support contract](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/SUPPORT_CONTRACT.md)

Published source: `baee59a603d08123adc0af50e57c8710ea62f4f9`.
Gem: 56,832 bytes, SHA256
`ff669a62717f91b2295b3cea1b68c6c4143c490d98df071fd322ad4b0007195d`.
