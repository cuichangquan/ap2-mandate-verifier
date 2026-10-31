# AP2 Mandate Verifier — 0.4.0

[日本語](README.ja.md)

Verify purchase-delegation data in Ruby using a deliberately fixed AP2 profile. The Gem checks signed data against independently supplied Host trust and order information, then returns immutable Evidence. **Verification success is not purchase or payment permission.**

`InputBuilder` converts business records into verification inputs: it creates the Gem-specific trust/selection/Host JSON, fingerprints and original-wire digests for you. You still choose whom to trust and supply the expected order, challenge state and clock. The Gem is Rails-independent and performs no network, database or payment operations.

## Try the local demo

The [Rails demo](https://github.com/cuichangquan/ap2-mandate-verifier-demo#readme) uses published 0.4.0 and InputBuilder by default. Its Docker instructions require no host Ruby installation. Compare synthetic normal, tampered and expired cases, including actual status/code, diagnostics and Evidence presence. It is local-only; it does not issue real challenges, consume nonces or execute purchases.

## Install

Formal support is **MRI 3.4.12 and MRI 4.0.9**. In your chosen Gem environment:

```sh
gem install ap2_mandate_verifier --version 0.4.0
```

Or add to your Gemfile:

```ruby
gem "ap2_mandate_verifier", "= 0.4.0"
```

Runtime dependencies are pinned to JSON 2.19.9, JWT 3.3.0, base64 0.3.0, OpenSSL gem 4.0.2 and Digest 3.2.1. Normal installation may download/build dependencies; do not relax the pins to work around a conflict. The Ruby resolution interval is not certification of every Ruby version, OS or native provider. See the [support contract](docs/SUPPORT_CONTRACT.md).

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

## Results and responsibility boundaries

| Result | Meaning and next step |
| --- | --- |
| `:verified_research` / `:scoped_research_verified`, `success? == true` | Immutable Evidence contains checked facts for the fixed profile. The Host must still decide whether to authorize the purchase. |
| `:rejected`, `rejected? == true` | No Evidence. Stop and inspect `result.code`. |
| `:unavailable`, `unavailable? == true` | No Evidence. Stop; a dependency or processing failure is not proof of invalid business data. |

On failure, inspect supplemental check candidates. Successful results have no failure diagnostic.

```ruby
if (diagnostic = result.diagnostic)
  puts diagnostic.to_h(locale: :en) # :ja for Japanese
end
```

`stage / field / reason / hint` are guidance; they do not change status/code or the verdict. Unknown fields/causes are not asserted. See the [diagnostic guide](docs/DIAGNOSTICS.md).

Exceptions, process failure and missing results also never authorize an operation. Do not log raw inputs/nonces or treat serialized Evidence as an authenticated credential.

The Gem checks signatures, supported disclosure closure, delegation, purchase/Host bindings, constraints and validity. The Host supplies authenticated, independent and current trust/keys/revocation, order/challenge state and clock. Before acting, it rechecks current state and validity, atomically consumes the nonce with order CAS, handles uncertain outcomes, and makes the final authorization/payment decision. `prepare`/`restore` do not authenticate storage or prove an unused nonce.

Supported scope is the fixed `ap2.checkout.single_merchant_sku` profile v1: ES256/P256, one Merchant/SKU/cart line, USD/EUR/JPY and the documented disclosure shapes. Unknown/unsupported forms fail closed. General AP2/all-Schema support, real Issuer interoperability, signing/Receipt generation, Rails adapters, DB/payment execution and numeric performance guarantees are outside this release. Real Issuer/Host production GO and Phase 2-B remain separate HOLDs.

### Which API should I use?

| Entry | Role |
| --- | --- |
| `InputBuilder.verify(**business_information)` | Recommended business-data path in 0.4.0. Assembles inputs and runs complete verification; preparation and restoration are separate steps shown above. |
| `verify_checkout(**inputs)` | Direct complete verification with the existing seven inputs, including caller-supplied trust/selection/Host JSON. |
| `verify_research(**inputs)` | Retained name for the same seven-input verification pipeline; no deprecation warning. |
| `verify(presentation_json:)` | Legacy JSON syntax check only. Never returns successful Evidence. |

Malformed assembly arguments, including missing keywords, to `InputBuilder.verify` return `:rejected / :invalid_host_context`. Assembly dependency/unexpected failures return `:unavailable / :research_verification_unavailable`; results from the complete core retain their codes. In contrast, missing/unknown keywords to the direct `verify_checkout` / `verify_research` entries return `:unavailable / :research_verification_unavailable`. Every such failure has `success? == false` and `evidence == nil`. See [the exact contract](docs/SUPPORT_CONTRACT.md#full-entry-and-required-inputs) for shapes, bounds and Ruby argument-binding caveats.

## More detail

- [Business-data lifecycle and Rails mapping](docs/INPUT_BUILDER.md), [complete Ruby example](examples/input_builder.rb) and [before/after example](examples/input_builder_before.rb).
- [Supported inputs, limits and Result/Evidence contract](docs/SUPPORT_CONTRACT.md); [Issuer/Host responsibilities](docs/ISSUER_HOST_MINIMUM_CONTRACT.md).
- [Published 0.4.0 release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.4.0), [publication/withdrawal records](docs/PROJECT_STATUS.md) and [changelog](CHANGELOG.md). Repository README changes do not rebuild or replace published Gem bytes.
- [Pinned historical seven-input / saved FULL example](https://github.com/cuichangquan/ap2-mandate-verifier/blob/e0ab9fb21045e89fc58fb06145eeda4855b2dc54/README.md#try-the-saved-synthetic-example), [older artifact/provider evidence](research/stable010_release_linux_package/README.md) and [historical conceptual diagrams](https://github.com/cuichangquan/ap2-mandate-verifier/blob/e0ab9fb21045e89fc58fb06145eeda4855b2dc54/README.md#illustrated-concepts-japanese-diagrams). These records are preserved, not current integration instructions or broader support claims.
- [Security reporting](SECURITY.md), [maintenance policy](docs/POST_RELEASE_MAINTENANCE.md) and [product direction](docs/PRODUCT_VISION.md). Do not include secrets, real Mandates or personal data in reports.

MIT. See [LICENSE](LICENSE).
