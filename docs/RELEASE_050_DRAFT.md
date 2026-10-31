# 0.5.0 Release notes — unpublished draft

Publication remains a separate Owner decision. This file is not a published
Release or a final release-readiness declaration.

## Changes

Ruby merchants can now sign a Checkout JWT and return a signed Checkout Receipt
for an explicit application Success or Error. Receipt receivers can authenticate
the trusted signer and exact target Mandate, without confusing an authentic
rejection with a completed purchase. Includes the published 0.4.0 diagnostics.

## Short real API example and output

With application-owned `key`, `checkout`, explicit `closed_sd_jwt` original wire
and independently registered `trusted_public_pem`:

```ruby
signing = AP2MandateVerifier::CheckoutJWT
signed = signing.sign(checkout: checkout, signer: signing.es256_signer(private_key: key),
                      public_key_pem: key.public_to_pem)
# Retain signed.jwt unchanged for InputBuilder / the recipient.
receipts = AP2MandateVerifier::CheckoutReceipt
receipt = receipts.sign(closed_sd_jwt: closed_sd_jwt, issuer: "shop", outcome: "Error",
  error: "declined", error_description: "Application declined", issued_at: now,
  signer: signing.es256_signer(private_key: key), public_key_pem: key.public_to_pem)
checked = receipts.verify(jwt: receipt.jwt, closed_sd_jwt: closed_sd_jwt,
  trusted_public_key_pem: trusted_public_pem, expected_issuer: "shop",
  not_before: now - 60, not_after: now + 60, verified_at: now)
p [checked.verified?, checked.purchase_succeeded?, checked.purchase_rejected?]
```

```text
[true, false, true]
```

## Compatibility and cautions

Existing APIs, status/code, Evidence, InputBuilder and diagnostics remain intact.
Formal MRI 3.4.12 / 4.0.9 and all five dependency pins stay unchanged.
The first version supports ES256/P-256, a single Merchant/SKU and the existing
inline terminal profile. Receipt input is the explicit final closed SD-JWT
`<terminal_jws>~`; missing `~`, disclosures, extra hops or unsupported forms fail
closed. Reference uses normative sd_hash semantics, not the SDK leaf-JWT helper.
Checkout Schema `status` is adopted; generic Receipt `result` is not accepted.
Application time policy and branch exclusivity are explicit local constraints.
The application owns trust enrollment, keys, final business outcome and payment.

## Details

- [Complete API examples, supported shape and SDK differences](MERCHANT_SIGNING.md)
- [Support contract](SUPPORT_CONTRACT.md)
- [Changelog](../CHANGELOG.md)
- [Local opt-in Rails demo](https://github.com/cuichangquan/ap2-mandate-verifier-demo#readme)

## Owner publication procedure (do not execute without approval)

After final main merge and latest-source tests, build one Gem, record source/tree,
version, size and SHA256, and perform ordinary installation of the same bytes on
both supported Rubies. Confirm all required CI/reviews/threads/protections and
candidate identifiers before requesting publication. Obtain explicit approval
for RubyGems push, public tag and GitHub Release. Publish the exact approved
bytes, compare the downloaded distribution, then create the tag/Release at the
approved source using the notes above. Public Web deployment remains separate.
