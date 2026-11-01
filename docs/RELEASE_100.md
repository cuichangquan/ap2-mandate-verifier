# 1.0.0 — stable public contract for the AP2 Ruby SDK

**Published on RubyGems, 2026-11-01 08:13:29.733 UTC.**
[Publication and exact artifact](POST_RELEASE_100.md) ·
[GitHub Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v1.0.0) ·
[PR #233](https://github.com/cuichangquan/ap2-mandate-verifier/pull/233).

1.0.0は、Ruby単体で使うAP2 SDKの公開契約を安定させるリリースです。
0.8.0のDirect／条件付き購入委任の発行・提示・検証・Receipt確認を維持し、
公開API・互換性・保守範囲を明記しました。

## Included scope

- Merchant Checkout JWT signing and verification.
- Direct human-approved orders: Provider issuance, Agent presentation and
  complete merchant verification.
- Conditional purchases: Open issuance, Agent Closed issuance/presentation,
  complete verification with independent trust/order/challenge/time inputs.
- Checkout Receipt reference, signing and verification of authentic Success/Error.

Direct and conditional profiles support one merchant and 1–8 Checkout lines.
The existing single-SKU default and all three v1 profile contracts are preserved.
See the stable [public API](PUBLIC_API.md), [Direct contract](BUYER_DIRECT_CHECKOUT.md)
and [conditional contract](CONDITIONAL_CHECKOUT.md).

## Install and run the packaged Ruby example

Use formally supported MRI **3.4.12 or 4.0.9**:

```sh
gem install ap2_mandate_verifier -v 1.0.0
ruby -e 'spec = Gem::Specification.find_by_name("ap2_mandate_verifier", "= 1.0.0"); load File.join(spec.full_gem_path, "examples/conditional_checkout.rb")'
```

The synthetic example runs from the installed Gem and covers approved conditions,
Open → Agent Closed → complete verification → both Receipt outcomes. The existing
[conditional API walkthrough](RELEASE_080.md#short-conditional-purchase-flow)
uses the same public APIs and remains applicable. Start with the
[English](../README.md) or [Japanese](../README.ja.md) guide for business inputs.

## Upgrade from 0.8.0

Documented 0.8.0 API usage needs no application source migration. The product
`lib/`, profile identifiers/defaults, Result/Evidence, saved formats and runtime
pins are unchanged. A constraint such as `~> 0.8.0` excludes 1.0.0; allow 1.x:

```ruby
gem "ap2_mandate_verifier", "~> 1.0"
```

Then run `bundle update ap2_mandate_verifier` and retain the updated lockfile.
Pins remain JSON **2.19.9**, JWT **3.3.0**, base64 **0.3.0**, OpenSSL gem **4.0.2**
and Digest **3.2.1**. The installation interval `>= 3.4.12, < 4.1` is not a
certification of every Ruby version in that range.

## 1.x compatibility and responsibilities

The [maintenance policy](POST_RELEASE_MAINTENANCE.md) covers the latest patch of
the latest 1.x minor series. Patches preserve the documented contract; minors add
compatible capabilities or announce deprecations; incompatible public-contract
changes require a major release. Security acceptance corrections disclose impact.

Applications own identity/consent, keys, revocation, current order state, atomic
nonce consumption and payment execution. Verified evidence and authentic Receipts
do not themselves authorize a purchase or prove payment completion. Payment
Mandates, general AP2 coverage, real Issuer enrollment and Host production approval
remain outside this release's claims. The separate Rails demo still uses 0.8.0;
the installed Ruby example above is the 1.0.0 entry point.
