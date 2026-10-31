# Multiple-item Checkout profile — 0.6.0 preparation

This is the contract for the additive, explicitly selected
`ap2.checkout.single_merchant_multi_item` version `1`. Published 0.5.0 remains
available with the unchanged `ap2.checkout.single_merchant_sku` v1 default.
Candidate test/CI/review/package completion is recorded separately in
[project status](PROJECT_STATUS.md); this document does not authorize publication.

## Selection and lifecycle

Pass `profile_ref: "ap2.checkout.single_merchant_multi_item"` to:

- `InputBuilder.trust(snapshot:, tenant_id:, issuer:, agent:, merchant:, verified_at:, profile_ref:)`;
- `CheckoutJWT.sign(checkout:, signer:, public_key_pem:, profile_ref:)`;
- `CheckoutReceipt.reference`, `.sign` and `.verify`, alongside their existing arguments.

The complete `InputBuilder.verify` / seven-input `verify_checkout` pipeline
selects the profile from authenticated Host trust, never a token's self-claim.
Other arguments, Result status/code, supplemental diagnostic meaning, immutable
Evidence v2 and responsibility boundaries retain their existing meanings.
Lower-level purchase/constraint APIs accept an explicit `profile_ref:`; omitted
selection retains their old default.

For a complete synthetic preparation → saved challenge → restore → current-state
verification → Success/Error Receipt example, see
[`examples/multi_item_checkout.rb`](../examples/multi_item_checkout.rb).
Its test-only issuer/Agent construction is not a product Mandate issuance API.
The expected successful verifier result remains
`verified_research/scoped_research_verified`; an authentic Error Receipt has
`verified? == true`, `purchase_succeeded? == false`.

Persist the original challenge String and all signed Strings. Restore trust and
challenge bytes without reserializing them. Migration creates a new authenticated
profile selection and a new challenge before presentation; it never relabels or
repairs an old challenge. An old saved envelope remains an old-profile envelope.
Current profile, order, trust and signed-byte differences must remain detectable.

## Product, requirement and line identity

There are three independent identities: requirement `id`, checkout line `id`,
and product `item.id` / candidate `id`. Requirement IDs must be unique within
requirements; line IDs must be unique within checkout lines. They need not match
each other. Candidate product IDs must be unique within each requirement.
Different requirements may contain overlapping candidate IDs.

Repeated product IDs on different checkout lines are supported. Quantity
allocation connects lines to requirements by product ID only for evaluation; it never deletes,
deduplicates, sorts or replaces signed lines. Titles remain bounded strings,
but product matching uses IDs. Price and totals are checked for every line.

An integer maximum-flow allocation must consume both all required quantities
and all ordered quantities. A unit cannot satisfy two requirements. For example,
requirements `{A or B: 1}` and `{A: 1}` accept `A: 1, B: 1`; a greedy allocation
which consumes A for the first requirement is insufficient. Missing units,
extra units and extra products reject. One requirement's quantity may be
distributed across its revealed candidate IDs.

Ordering does not change quantity satisfiability. A separately and correctly
signed checkout in another order has different original bytes and must be bound
by its own Mandate and Host challenge. Reordering an existing signed JWT or
reusing the previous reference is a signature/binding failure.

## Closed subset and limits

These are Gem profile restrictions, not general AP2 requirements.

| Input | New v1 limit / supported form |
| --- | --- |
| Merchant / Checkout / currency | One each; USD, EUR or JPY |
| Checkout lines | 1–8; distinct line IDs |
| Requirements | 1–8; distinct requirement IDs |
| Candidates per requirement | 1–8; distinct product IDs within the requirement |
| Quantity per line / requirement | Integer 1–1,000,000 |
| Unit price / multiplication / summed total | Integer minor units, 0–9,007,199,254,740,991 |
| Line and Checkout totals | Exactly subtotal and total, each equal to its checked amount |
| Constraints | Ordered `checkout.line_items`, then `checkout.allowed_merchants`; no unknown constraints |
| Links / taxes / shipping / discount | Empty links; no tax, shipping or discount engine or extra total types |
| Root disclosures | Every candidate, the Open payload and allowed merchant; at most 66 |
| Disclosure segment / Root input | 8,192 / 131,072 bytes |
| Commitment walk | At most 2,048 visits; container depth 24; array length 16 |
| Checkout JWT / terminal JWS | Existing 16,384 / 32,768 byte limits |

All candidate positions must be array commitments under
`delegate_payload[0].disclosed.constraints[0].items[i].acceptable_items[j]`.
The Open payload and sole allowed merchant retain their existing commitment
positions. Missing, reused or unused disclosures and unsupported positions fail
closed. Bounds apply together: an input below one count cap can still exceed
the segment, wire or traversal cap. Oversized values are rejected, never truncated.
No unmeasured worst-case CPU, memory, concurrency or numeric SLA is promised.

## Normative source and SDK differences

The AP2 source stays pinned to
`b4587ac1d055888a73b4b21750973cffba961793`. The Line Items normative text defines
maximum flow and requires both sides to be fully satisfied. Schema descriptions
and Python helper behavior must be compared independently; see
[the interoperability record](MULTI_ITEM_INTEROP.md) for measured cases and scope.
No generic AP2/full-Schema or real-Issuer conformance claim follows from synthetic
tests. Unrelated latest-spec changes are not adopted by this profile.

Receipt still uses Checkout-specific `status: Success/Error`. Its reference is
the original final closed SD-JWT `<terminal_jws>~`; no per-line receipt or
compact-only alternate hash is introduced. The existing
[Receipt specification/SDK differences](MERCHANT_SIGNING.md) remain applicable.

## Host responsibilities

The Host independently supplies authenticated, current trust/keys/revocation,
clock, expected order/currency/total and saved challenge state. A total extracted
from the received checkout is not an independent expected order. It rechecks
state before acting, atomically consumes the nonce with order CAS, handles
uncertain outcomes and makes the final purchase/payment decision.

Verification success is checked Evidence, not Host ALLOW or payment success.
Receipt authenticity is separate from its explicit business outcome. Multiple
merchants, splitting one Open Mandate across Checkouts, Payment Mandates/Receipts,
product issuance/presentation, real payments and production operation are outside
this task. Formal MRI 3.4.12 / 4.0.9 and all five runtime dependency pins are unchanged.
