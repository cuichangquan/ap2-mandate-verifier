# AP2 Mandate Verifier — Ruby SDK for Checkout and Payment

[日本語](README.ja.md) · **Published stable: 1.6.1** · [Quick Start](docs/QUICK_START.md)

Issue, present and verify supported AP2 Checkout and Payment Mandates in plain Ruby.
Use this Gem when your app needs to check what a buyer approved, what an Agent may
choose, and whether signed Checkout/Payment data stays within those conditions.
No Rails dependency. **Verification success is not purchase or payment success; the SDK never executes payments.**


**Platforms:** MRI 3.4.12 / 4.0.9. Existing native published-Gem checks cover **1.6.0** on Linux ARM64/AMD64, macOS Intel/Apple Silicon and Windows Server 2022 X64, not the new CLI. See [platform evidence and reproduction](docs/PLATFORM_SUPPORT.md) and the separate [1.6.1 Linux publication checks](docs/POST_RELEASE_161.md). Rails demo compatibility is separate.

## Start here

This minimal SDK quick start uses **published 1.6.1**. For its integration CLI, use the [Gem-only integration instructions](docs/RUBY_INTEGRATION.md).

```sh
gem install ap2_mandate_verifier --version 1.6.1
AP2_GEM_DIR="$(ruby -e 'puts Gem::Specification.find_by_name("ap2_mandate_verifier", "1.6.1").full_gem_path')"
ruby "$AP2_GEM_DIR/examples/conditional_checkout.rb"
ruby "$AP2_GEM_DIR/examples/payment.rb"
```

These installed examples create synthetic keys and approvals, issue/present/verify
Mandates, then authenticate alternative Success and Error Receipts. An authentic
Error Receipt reports failure. No account, credentials, database or Rails required.
Allow about ten minutes with a supported Ruby already installed; dependency builds
and Docker's first download can take longer.

**Next:** [step-by-step Quick Start and expected output (1.6.0 baseline)](docs/QUICK_START.md),
including twelve UTC months and a cumulative JPY budget rejection.
[Docker demo](https://github.com/cuichangquan/ap2-mandate-verifier-demo#readme)
uses published **1.6.0**, with local Checkout screens and Ruby Payment examples.

## Choose a workflow

**Integrating a real application?** Start with the [Ruby integration and restart
recovery guide](docs/RUBY_INTEGRATION.md): protected application inputs, persistent
mock results, separate-process recovery and safe retry decisions. Use this repository
with published 1.6.0, or install **published 1.6.1** for the bundled CLI without a
repository checkout. Public 1.6.0 does not include this CLI. See the
[exact 1.6.1 distribution and verification](docs/POST_RELEASE_161.md).

Checkout describes the order; a Checkout Mandate records approval/delegation for it.
A Payment Mandate adds payment conditions and references the Checkout approval.
Receipts authenticate an application's reported outcome for the original final Mandate;
they do not independently prove settlement.

| Workflow | Use when | API / guide |
| --- | --- | --- |
| Direct | Buyer approves an exact signed order/payment | `Buyer`, `Payment.issue_direct` · [Checkout](docs/BUYER_DIRECT_CHECKOUT.md) / [Payment](docs/PAYMENT.md) |
| Conditional delegation | Buyer approves candidates and limits; registered Agent chooses within them | `ConditionalCheckout`, `Payment.issue_open/issue_closed/present` · [Checkout](docs/CONDITIONAL_CHECKOUT.md) |
| Selective disclosure | Keep the full approved Open private and send selected merchant/product or payee/instrument candidates | `SelectiveCheckout`, `SelectivePayment` · [Checkout](docs/SELECTIVE_CHECKOUT.md) / [Payment](docs/SELECTIVE_PAYMENT.md) |
| Long Open | Reuse one approved Checkout/Payment Open pair across explicit UTC months, with finite count and cumulative JPY budget | `LongPayment`, `PaymentAcceptance::LongSQLiteStore` · [contract](docs/LONG_PAYMENT.md) |

Direct and conditional Checkout support one merchant and up to eight lines with
quantities under the explicit multi-item profile. The default single-SKU profile
retains its one-line contract. Selective profiles retain all mandatory conditions
and quantities; candidate count/order and issuer-JWT linkability are not hidden.
Long Open is a separate complete-disclosure profile (content up to 400 days,
short-lived proofs); it does not compose with selective or PISP/date profiles.
**Its UTC-monthly profile is not full compliance with generic AP2 MONTHLY semantics.**

Other explicit options: [PISP / execution-date constraints](docs/PAYMENT_POLICY.md),
[transactional acceptance and recovery](docs/PAYMENT_ACCEPTANCE.md), and bounded
[ON_DEMAND count / JPY budget profiles](docs/RECURRING_PAYMENT.md).
Existing 1.x API signatures, defaults, profiles and saved formats remain supported.

## Choose your API by role

| Your component | Start with |
| --- | --- |
| Merchant backend | `CheckoutJWT.sign`; `CheckoutReceipt.sign/verify` |
| Trusted approval backend | `CheckoutJWT.verify` before consent; `Buyer.issue_closed` or `ConditionalCheckout.issue_open`; corresponding Payment issuance |
| Registered Agent | `Buyer.present_closed`, or conditional `issue_closed/present`; selective variants for supported disclosure profiles. Provider private keys stay in the approval backend. |
| Merchant / payment verifier | `Buyer.verify` for Direct; `InputBuilder.prepare/restore/verify` for conditional Checkout; `Payment.verify` for Payment plus Checkout binding; explicit selective/long variants |
| Receipt consumer | `CheckoutReceipt.verify`, `PaymentReceipt.verify`; check authenticity **and** reported outcome |
| App managing durable Payment acceptance | `PaymentAcceptance::Service` and the appropriate protected store; [integration contract](docs/PAYMENT_ACCEPTANCE.md) |

`verify_checkout` (also `verify_research`) is the complete seven-input conditional
Checkout entry. `InputBuilder` is the recommended business-record adapter.
Legacy `verify(presentation_json:)` checks syntax only and never returns successful
Evidence. [Exact APIs and result/error conventions](docs/PUBLIC_API.md).

## Install and support

Formal support: **MRI 3.4.12 and 4.0.9**. For this walkthrough use
`gem "ap2_mandate_verifier", "= 1.6.0"` in a Gemfile. Applications following stable
1.x may use `"~> 1.0"` and review lockfile updates. `~> 0.8.0` excludes 1.x;
[upgrade notes](docs/RELEASE_100.md) retain the compatibility details.

Runtime pins: JSON 2.19.9, JWT 3.3.0, base64 0.3.0, OpenSSL gem 4.0.2,
Digest 3.2.1. Installation may download/build native dependencies. Do not loosen
pins to bypass a conflict. The resolution interval does not certify every Ruby,
OS or provider. [Support contract](docs/SUPPORT_CONTRACT.md).

## Responsibilities before using this in your app

The core verifier performs no network or payment operations. Optional acceptance
stores perform local database transactions; SQLite requires a separately installed
driver. **Verification, durable reservation, application authorization and settlement
are separate events.**

Your app owns authentication, consent, protected approval records, independently
trusted current keys/revocation/profile policy, order/challenge state and clock.
It must recheck current authority, durably consume one-use state atomically, handle
uncertain results, and decide whether to call a processor. SDK acceptance and
Receipt authentication do not establish real Issuer trust or processor exactly-once.
Missing/invalid Receipt or unknown effect stays pending for reconciliation; do not
automatically retry or refund allowance on timeout/Error.

Unknown/unsupported forms fail closed. Exceptions, unavailable results and missing
results never authorize an operation. Do not log private keys, raw Mandates/nonces
or treat serialized Evidence as an authenticated credential. General AP2/all-Schema
conformance, real-Issuer interoperability and production GO are not claimed.
[Issuer/Host responsibilities](docs/ISSUER_HOST_MINIMUM_CONTRACT.md),
[security policy](SECURITY.md), [acceptance boundaries](docs/PAYMENT_ACCEPTANCE.md).

## Reference and retained evidence

- [Public API](docs/PUBLIC_API.md), [InputBuilder guide](docs/INPUT_BUILDER.md), [diagnostics](docs/DIAGNOSTICS.md).
- [1.6.0 publication verification](docs/POST_RELEASE_160.md), [changelog](CHANGELOG.md), [project/publication history](docs/PROJECT_STATUS.md), [maintenance policy](docs/POST_RELEASE_MAINTENANCE.md).
- [Merchant signing](docs/MERCHANT_SIGNING.md), [multiple items](docs/MULTI_ITEM_CHECKOUT.md), [Python differences](docs/MULTI_ITEM_INTEROP.md).

Historical release and research documents remain evidence for their recorded
versions, not the current onboarding path. Repository documentation changes do
not rebuild or replace the already published 1.6.0 Gem.

<details>
<summary>Source-checkout InputBuilder walkthrough (advanced)</summary>

## A small InputBuilder example

After installation, use a checkout of this repository. Save the following as `quick_start.rb` in its root and run `ruby quick_start.rb`. The JSON files under [`examples/input_builder/`](examples/input_builder/) contain explicit synthetic order/registration records and original signed Strings; they are not part of the installed Gem. Their fixed clock is intentional because the saved signatures expire. These are test inputs, not real enrollment or current production data.

```ruby
require "ap2_mandate_verifier"
require "json"
require "tmpdir"

builder = AP2MandateVerifier::InputBuilder
fixtures = File.join(__dir__, "examples/input_builder")
read = ->(name) { JSON.parse(File.binread(File.join(fixtures, "#{name}.json"))) }
trust_at = ->(now) do
  builder.trust(snapshot: read.call("trust_snapshot"), tenant_id: "synthetic-tenant",
    issuer: {"identity" => "issuer", "purpose" => "checkout", "key_ref" => "issuer-1"},
    agent: {"identity" => "agent", "purpose" => "checkout", "key_ref" => "agent-1"},
    merchant: {"identity" => "shop", "purpose" => "checkout", "key_ref" => "merchant-1"},
    verified_at: now)
end
wires = read.call("signed_wires").transform_keys(&:to_sym) # Preserve String bytes.

# Before issuance: independent order/trust and Host-chosen challenge information.
prepared = builder.prepare(trust: trust_at.call(1_800_000_000),
  order: read.call("order"), root_presentation: wires.fetch(:root_presentation),
  host_checkout_jws: wires.fetch(:host_checkout_jws),
  challenge_id: "synthetic-challenge", nonce: "n", issuer_id: "synthetic-host",
  not_before: 1_799_998_000, not_after: 1_800_002_000)

Dir.mktmpdir do |directory|
  record = File.join(directory, "challenge.json")
  File.binwrite(record, prepared) # Demo persistence; the Host owns real storage.

  # Later: load the saved bytes, and independently obtain current order/trust.
  now = 1_800_000_000 # Supplied synthetic clock, not a production time source.
  result = builder.verify(trust: trust_at.call(now),
    saved_challenge: builder.restore(saved_challenge: File.binread(record)),
    order: read.call("order"), **wires,
    expected_challenge_issuer_id: "synthetic-host",
    clock_source_id: "fixed-synthetic-clock", verified_at: now)
  puts "#{result.status}/#{result.code}; evidence=#{!result.evidence.nil?}"
  raise "Verification did not succeed; stop" unless result.success?
end
```

Expected for these unchanged synthetic inputs: `verified_research/scoped_research_verified; evidence=true`. This example models preparation, persistence and later verification in one process; it does not implement real issuance or atomic consumption. In an application, map authenticated registry/order records explicitly and preserve the original signed bytes. Structured business inputs use plain Ruby values with String keys, not ActiveRecord objects.

Do not call `prepare` again during verification or update saved hashes/references to match current values. Changed orders, trust or signed bytes must remain detectable. Persisted trust JSON can be loaded with `restore_trust` without reserializing it. The [complete example](examples/input_builder.rb) includes normal/tampered/expired cases; the [input guide](docs/INPUT_BUILDER.md) explains the business fields, exact restoration and Rails model mapping.


</details>
