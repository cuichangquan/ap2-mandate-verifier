# Input assembly for the fixed checkout profile (0.3.0)

Unreleased 0.4.0 adds supplemental safe diagnostics; see [API and troubleshooting](DIAGNOSTICS.md). Published 0.3.0 and existing verdict/Evidence contracts remain unchanged.

`AP2MandateVerifier::InputBuilder` converts explicit Host business information into
the existing seven verification inputs. It performs no network, database, Rails,
nonce issuance/consumption or payment operation. A built input is not verified
Evidence. `InputBuilder.verify` always invokes the complete `verify_checkout` core.
The original `verify_checkout`, `verify_research` and older APIs remain available.

## Run the complete Ruby example

After ordinary installation of published 0.3.0 (`gem install ap2_mandate_verifier --version 0.3.0`), run these repository examples:

```sh
ruby examples/input_builder.rb valid
ruby examples/input_builder.rb tampered
ruby examples/input_builder.rb expired
ruby examples/input_builder_before.rb
```

The example contains independent synthetic order and public-registration data,
original signed Strings, issue-time preparation, temporary-file persistence,
restoration, fresh current-state reads, verification, and result handling. It does
not read `full.json` or infer trusted keys, prices, identities or nonce from tokens.
No private keys are distributed. See `examples/input_builder/NOTICE.md` for source.
The fixed synthetic clock is intentional: these historical signatures expire.

## Host mapping

All structured input keys are Strings. Exact plain Hash/Array/String/Integer and
boolean values are accepted; do not pass model objects, Symbols, subclasses,
custom coercions or unbounded graphs. Unknown fields are rejected. Pure assembly
methods raise `InputBuilder::Invalid` for malformed business information; a caller
must treat missing results or exceptions as failure, never authorization.

`verify` converts malformed assembly arguments to the existing immutable Result
`:rejected / :invalid_host_context`; dependency or unexpected assembly failures
return `:unavailable / :research_verification_unavailable`. Both are non-success
with no Evidence. Codes produced after entering the complete verifier are retained.

| Business source | Builder argument | Host responsibility |
| --- | --- | --- |
| Authenticated registry snapshot and public PEM keys | `trust(snapshot:, tenant_id:, issuer:, agent:, merchant:, verified_at:)` | Provenance, enrollment, revocation, freshness and explicit selection |
| Current order/account/tenant, merchant, audience, version, currency, total minor units | `order:` | Independent authoritative state; no values inferred from signed claims |
| Original received Root and Checkout Strings | `root_presentation:`, `host_checkout_jws:` | Preserve exact bytes, including Root disclosure order and trailing `~` |
| Host-chosen ID, nonce, issuer and validity | `prepare(...)` | Actual issuance and durable authenticated persistence |
| Saved preparation String | `restore(saved_challenge:)` | Authenticate storage; retain state and references without repair |
| Current trust/order, terminal String and trusted clock | `inputs(...)` / `verify(...)` | Independent reads, currentness and clock provenance |
| Verified Evidence | returned Result | Final authorization; recheck trust/order, atomic nonce consumption and order CAS |

A snapshot has `id`, `policy_version`, `active`, `not_before`, `not_after`, and
`records`. Each record supplies `role`, `identity`, `tenant_id`, `purpose`,
`key_ref`, `public_key_pem`, `active`, `not_before`, `not_after`. Public PEM must
already be canonical P256 SPKI. The builder adds the fixed profile, algorithm and
fingerprint; it preserves and validates every record, including nonselected ones.
Role selectors each contain `identity`, `purpose`, `key_ref`.

An order contains `tenant_id`, `buyer_account_id`, `order_id`, `merchant_id`,
`audience`, `order_version`, `currency`, `expected_total` (integer minor units).
The builder adds selected Agent fingerprint, raw wire digests and fixed profile.
It does not compare current values by overwriting issued values.

## Rails mapping example

Rails is optional. This explicit mapping belongs to the application; the Gem does
not interpret ActiveRecord models or acquire trust. Only use values whose source
and currentness your Host has authenticated:

```ruby
order_information = {
  "tenant_id" => order.tenant.external_id,
  "buyer_account_id" => order.buyer.external_id,
  "order_id" => order.external_id,
  "merchant_id" => order.merchant.external_id,
  "audience" => configured_checkout_audience,
  "order_version" => order.lock_version.to_s,
  "currency" => order.currency,
  "expected_total" => order.total_minor
}
# registry_snapshot and role selectors use the same explicit plain-value mapping.
# Save prepare(...) bytes in a protected challenge record before handing out nonce.
# Later load that record unchanged and independently reread current order/trust.
inputs = AP2MandateVerifier::InputBuilder.inputs(
  trust: current_trust, saved_challenge: challenge.preparation_bytes,
  order: order_information, root_presentation: received_root,
  terminal_jws: received_terminal, host_checkout_jws: original_checkout,
  expected_challenge_issuer_id: configured_host_id,
  clock_source_id: trusted_clock_id, verified_at: trusted_clock_unix_seconds)
result = AP2MandateVerifier.verify_checkout(**inputs)
# success? is checked evidence, not a purchase/payment permission.
```

Do not call `prepare` again during verification. Changes in order, selected Agent,
raw signed bytes, trust snapshot/policy or saved references must remain observable.
Restoration validates the storage envelope and does not authenticate its contents.
Changing a stored digest to match current data defeats the Host trust boundary.
Persist state changes separately under authenticated atomic Host operations; do
not replace an already-used challenge with a new issued preparation.

## Before/after measurement

The checked-in runnable examples are the measurement material, rather than a
one-line call that hides initial setup or persistence. Count nonblank,
noncomment Ruby lines with:

```sh
awk 'NF && $0 !~ /^[[:space:]]*#/ {n++} END {print n}' examples/input_builder_before.rb
awk 'NF && $0 !~ /^[[:space:]]*#/ {n++} END {print n}' examples/input_builder.rb
```

Current source counts are **64 before / 42 after**. Both include initial mapping,
issue preparation, save/read, current-state construction and result handling.
The after example additionally selects three scenarios; this is a small synthetic
example, not a general application-effort benchmark or performance claim.

| Burden | Before | Recommended path |
| --- | --- | --- |
| Initial business mapping | Required | Required, explicit and source-owned |
| Trust/profile envelopes and selection references | Handwritten nested shapes | Gem-generated |
| Public-key fingerprint, snapshot-body hash, Root/Checkout digest | 4 caller-side SHA256 call sites | 0 |
| Challenge B and trust-reference transcription | Caller constructs and copies | Gem-generated at preparation |
| Daily verification | Assemble current B, host JSON, seven arguments | Restore saved bytes, map current state, call builder |
| Storage, trust authenticity, nonce state, final business decision | Host-owned | Host-owned |

The improvement removes mechanical transformations and repeated profile/reference
knowledge. It does not remove the first-time work of identifying authoritative
business data, registration policy or atomic Host operations.

## Versions and migration

Gem version `0.3.0`, AP2 source
`b4587ac1d055888a73b4b21750973cffba961793`, fixed profile
`ap2.checkout.single_merchant_sku` version `1`, and preparation format `1` are
separate identifiers. Unknown preparation/profile versions fail closed. There is
no generic future-profile fallback. New protocol requirements can require new
application data and an explicit migration or reissuance.

Keep existing seven-input integrations unchanged while adopting the builder for
new preparations. Existing raw Host JSON is not automatically upgraded into a
new issued challenge. Retain original signed bytes and authenticated saved
references. Reissue through the Host's normal authorization process when a stored
format cannot be supported; do not repair its digests or reinterpret its version.
See [SUPPORT_CONTRACT](SUPPORT_CONTRACT.md) for the unchanged verification scope.

### Restoring an existing trust snapshot

`trust(...)` creates a **new** snapshot body from business records. When your Host
persists an existing authenticated snapshot, keep `trust.trust_json` and
`trust.selection_json` as original Strings and reload them with:

```ruby
current_trust = AP2MandateVerifier::InputBuilder.restore_trust(
  trust_json: authenticated_registry.trust_bytes,
  selection_json: authenticated_registry.selection_bytes,
  verified_at: trusted_clock_unix_seconds)
```

This preserves exact snapshot/profile body Strings and their existing digests.
Do not parse and regenerate a persisted trust body to suppress reference drift.
A restored snapshot must still be independently authenticated and current; loading
an older snapshot does not establish freshness or prevent rollback.
