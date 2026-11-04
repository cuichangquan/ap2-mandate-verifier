# Selective Checkout Mandates (published 1.3.0)

This explicit profile lets an application retain a confidential complete Open Checkout Mandate and send only the merchant and product candidates needed for a purchase. Every requirement and quantity remains visible and enforced. The existing complete Checkout profiles and their defaults remain available.

## Approval and disclosure boundary

The application authenticates the user, obtains informed approval and stores the complete issuance securely before selecting a presentation. Merchant and per-requirement product lists describe independent allowed sets. They cannot encode “merchant A only sells approved product X, merchant B only approved product Y”, or correlated choices between requirements. Issue separate Opens for correlated policies. Never expand a restricted approval into independent lists.

Only the elements of `checkout.allowed_merchants.allowed` and each `checkout.line_items.items[*].acceptable_items` may be omitted. The signed content disclosure, both constraints, every requirement ID and quantity, delegation key and validity interval are mandatory. At least one candidate per requirement must be disclosed. Unresolved commitments in any other location, unknown conditions and unsupported formats fail closed.

Keep the complete issuance and its unselected leaf disclosures out of network requests, logs, exception reporting and analytics. Selection is data minimization, not anonymity: the issuer JWT, candidate counts, ordering, mandatory requirements and resulting transaction remain observable. Presentations sharing an issuer JWT can be linked.

## Ruby API

```ruby
m = AP2MandateVerifier
full = m::SelectiveCheckout.issue_open(
  allowed_merchants: approved_merchants, requirements: approved_requirements,
  candidate_policy: :independent,
  agent_public_key_pem: agent_public_pem,
  issued_at: now, expires_at: now + 600,
  signer: provider_signer, public_key_pem: provider_public_pem)

# Keep full confidential; original candidate indices are zero based.
selected = m::SelectiveCheckout.select(
  open_sd_jwt: full.root_presentation,
  merchant_index: 0, item_indices: [[1], [0, 2]])
# Alternatively, select all approved candidates matching the actual cart IDs,
# and prove exact quantity coverage before returning the reduced Open:
selected = m::SelectiveCheckout.select_for_checkout(
  open_sd_jwt: full.root_presentation, checkout: checkout_hash)
```

`candidate_policy: :independent` is an explicit contract, not proof of consent. Supply only independently approved candidate sets from protected application state. `item_indices` contains one nonempty index array for every requirement, in original requirement order. The selection API preserves original signed commitment slots. Its immutable `Open` exposes `root_presentation` and alias `open_sd_jwt`; selecting is structural preparation, not issuer authentication.

Use `SelectiveCheckout.issue_closed` with the reduced `root_presentation`, original Merchant `checkout_jwt`, independently selected issuer/Agent/Merchant public keys, expected Merchant ID, audience, nonce, time and Agent signer. Its immutable Closed exposes the existing `root_presentation`, `terminal_jws`, `checkout_jwt` and `closed_sd_jwt` fields. `present` restores those transport fields without claiming verification.

Configure `InputBuilder.trust(..., profile_ref: SelectiveCheckout::PROFILE_REF)` using the application’s authenticated registry, then use the existing `InputBuilder.prepare`, `restore`, `inputs` and `verify` lifecycle with the reduced Open. The new profile is `ap2.checkout.selective_candidates.1`; the presentation cannot select trusted policy for the Host. Checkout signing and Receipt APIs accept this explicit `profile_ref`.

For Payment, pass `checkout_profile_ref: SelectiveCheckout::PROFILE_REF` explicitly to `Payment.issue_open` or `SelectivePayment.issue_open`, and supply the reduced Checkout Open as `open_checkout_sd_jwt`. The default is unchanged. `SelectivePayment.verify` still takes the seven original Checkout verification inputs and rechecks the full Host-bound chain.

Run the installed Gem’s [standalone Checkout example](../examples/selective_checkout.rb) and [combined Checkout/Payment example](../examples/selective_checkout_payment.rb). They generate synthetic keys in memory, compare retained/sent disclosures and authenticate both Success/Error Receipt alternatives without executing a purchase.

## Verification and quantities

A new registered Host profile must be selected independently from the presentation. Verification follows the existing Host trust, issuer signature, complete commitment graph inspection, Agent key/signature/delegation, audience/nonce/time, Merchant signature and original Checkout binding, constraints and Host order/challenge verification path. A signature or a structurally restored presentation alone is insufficient.

For this profile, the existing Evidence field `original_root_graph_closure` means every signed commitment and every supplied disclosure was accounted for, with unresolved leaves allowed only at the registered candidate positions. It does not mean hidden candidate values were reconstructed or validated. A verifier cannot establish the schema, identity or uniqueness of an undisclosed preimage. The issuance API checks the complete approved candidate universe; presentation verification certifies the disclosed subset and every mandatory condition. These facts do not prove the application’s consent provenance.

All mandatory quantities participate in integer max-flow matching. Total required quantity must equal total purchased quantity and the maximum assignable flow. Matching uses product IDs; product titles are descriptive, as in the existing multi-item profile. Duplicate line IDs and requirement IDs are rejected. Multiple lines for the same product and overlapping candidate sets are supported. Hidden candidates do not add edges to the quantity graph.

The Agent signs the exact reduced Open bytes, including disclosure order and terminal `~`. The Host challenge and Payment reference must bind those same bytes. A confidential complete Open cannot be substituted after selection. Checkout Receipt references remain tied to the exact final Closed wire.

## Supported bounds

The explicit profile supports at most eight merchant candidates, eight mandatory requirements, eight product candidates per requirement and eight purchased lines. A reduced presentation contains exactly one merchant disclosure and a nonempty subset for every requirement. A complete issuance can contain up to 73 disclosures including its content disclosure. Each encoded disclosure is limited to 8,192 bytes, the compact issuer token to 16,384 bytes and the complete original Open wire to 131,072 bytes. JSON parsing retains the existing bounded depth policy. These are joint limits: long identifiers/values can exhaust a byte budget before a count limit is reached. Issuance checks the final representation before calling a signer.

## Compatibility and responsibility

Opt in explicitly when issuing a selective Checkout and configuring its Host trust profile. Existing complete profiles retain their missing-disclosure rejection. Existing saved records are not silently migrated. Payment issuance must explicitly identify the new Checkout profile when using its reduced Open; Payment verification still re-verifies the complete Checkout chain with independent Host inputs.

Verification establishes scoped checked facts; it does not authorize a purchase, execute payment or establish issuer provenance. The application owns consent, key enrollment/custody, revocation, current order state, atomic nonce consumption, replay prevention and uncertain outcome recovery. Receipt authenticity is distinct from independent settlement confirmation.

## Official source and interoperability

The adopted AP2 source remains pinned to `b4587ac1d055888a73b4b21750973cffba961793`. [Its Open Checkout Schema](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json) marks merchant and acceptable-item array values as selectively disclosable while retaining mandatory line requirement structure. The explicit registered profile, strict limits and subset acceptance policy are this SDK’s supported contract, not a claim of general AP2 conformance.

The pinned Python SDK high-level presentation helper does not expose this candidate selection/profile flow. Interoperability must distinguish official low-level signatures/chain/typed Schema checks from the strict subset adapter. In particular, its max-flow helper may accept an empty candidate list as a wildcard or accept underfilled demand; this SDK requires nonempty disclosed candidates and exact quantity coverage. Official SDK acceptance alone is not a strict quantity oracle.

Source interoperability observed two Checkout scenarios in each direction, eight Success/Error Receipt checks and 28 negative controls under Ruby 3.4.12 / Python 3.11.2. The Python terminal adapter uses the official JWT primitive plus an exact reduced-wire `sd_hash`, because the SDK’s generic key-binding creator discloses its final payload while this supported Checkout grammar requires an inline final Closed payload. Source and installed-candidate evidence, final review and CI are recorded separately in the release preparation report; these limited synthetic observations do not establish production trust.

[Verified public artifact, tag and Release](POST_RELEASE_130.md). The original candidate preparation remains historical in [release preparation](RELEASE_130_CANDIDATE.md).
