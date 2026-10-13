# Phase 2-A / E06-I B2 — G4 crypto-only → G5 official Schema → G6 Host semantics split

**2026-10-13 JST · [Issue #75](https://github.com/cuichangquan/ap2-mandate-verifier/issues/75) · `DESIGN_ONLY / NOT_RUN / NO_IMPLEMENTATION_APPROVAL / NO_CI_APPROVAL / PHASE2B_HOLD`**

Companion B1: [Host immutable snapshot and Evidence cutoff](PHASE2A_E06I_B1_IMMUTABLE_HOST_SNAPSHOT_CONTRACT.md). Parent: [#47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47); E06-I approval ledger: [#73](https://github.com/cuichangquan/ap2-mandate-verifier/issues/73). Current main at design start: `bcd5685cf096594811a94a3f6b6100e6082e5c31`.

**Design-only proposal.** Applies to the pinned AP2 v0.2.0 `b4587ac1d055888a73b4b21750973cffba961793` and existing fixed synthetic Issuer A / 2-hop / exactly 3 allowed SD array slots, fixed one-line Checkout laboratory profile. The official Open/Closed/Merchant schemas and the laboratory Checkout JWT payload shape are **distinct**. The plan does **not** implement a generic SD-JWT/AP2 verifier or authorize purchases.

## 1. Why existing P1-2 / P1-3 cannot just be called at G4

| Existing source | Current one-method behavior | Strict integration consequence |
| --- | --- | --- |
| `research/p1_2/two_hop_research.rb` `verify!` | Calls Root `verify_full_root!`, compares issuer `cnf.jwk`/Host Agent key, verifies signed Terminal/`sd_hash`/aud/nonce, then Closed cardinality, exact keys, signed time and immutable Open→Closed shared claims | Mixed cryptographic and stricter local shape/time; calling it as one block before G5 can produce **early G4 rejection**, not G5 official-schema causal proof |
| `research/p1_3/checkout_binding_research.rb` `verify!` | Calls P1-2, validates original Checkout JWT/hash/merchant ES256, then exact JWT Checkout layout, status, merchant/Host ID, currency, SKU, quantity, price, subtotal/total | G6 business semantics execute **before** G5 if invoked at G4, violating the integration order |
| `research/phase2a_e06i/isolated_root_closure.rb` | Fixed Issuer Root-only signature+original commitment closure; root typ `example+sd-jwt`, fixed 3 slots, strict Open shape, `Time.now` | Must **not** be used as a Terminal verifier: Terminal `typ=kb+sd-jwt` and signed form/commitments have a different boundary |
| `research/phase2a_e06i/schema_gate.rb` | Pinned Git-blob Open/Closed/nested Merchant `json_schemer=2.5.0` validation; offline allowlisted `$ref` only | Does not authenticate signatures or Host purchase semantics. `check!` success **alone cannot** create Evidence |
| `research/phase2a_e06i/integrated_probe.rb` | G0 canonical JWS/base64/strict JSON bounds; G1 Host synthetic candidate; G2 Root ES256; G3 Root closure; always G4 HOLD | Snapshot code remains **NOT RUN**; no G4–G7 success exists |

Old P1-1 `root_sdjwt_research.rb` imports `minitest/autorun` when required. **Do not load P1-2/P1-3 (directly or transitively) into the non-test orchestrator.** No old sources may be changed under this design PR. Extracting/copied security code entails separate parity review and does not inherit historic PASS.

## 2. Proposed internal stage dependency types (not implemented)

The stage names are conceptual opaque *trusted result types*, not arbitrary Hash inputs the user can manufacture. An implementation must keep them internal, construct only after the preceding stage succeeds, reject forgeries/mismatches and deeply protect nested data from mutation.

```text
raw case_data + independent Host material
  └─ G0 ParsedUntrustedWires (original bytes + strict parse/bounds only)
     └─ G1 ImmutableHostSnapshot (B1, single verified_at + coherent refs)
        └─ G2 AuthenticatedRootJWS (Issuer Host key, original compact JWS)
           └─ G3 CompleteRoot (original Root entire SD graph, verified Open)
              └─ G4 AuthenticatedCheckoutChain
                 (Agent Terminal signature, Root wire sd_hash,
                  Holder/Host/challenge key match, Merchant signature,
                  Closed-to-Host original Checkout JWT and checkout_hash)
                 └─ G5 ValidatedOpenClosedAndLocalProfile
                    (pinned official Open+Closed+nested Merchant schemas;
                     separate strict local Checkout JWT shape)
                    └─ G6 BoundCheckoutFacts (Host id/tenant/version/buyer,
                       Merchant/SKU/quantity/amount/status/currency/total)
                       └─ G7 Evidence-only or HOLD (B1 earliest finite TTL)
```

**The G5 success artifact has TWO mandatory producers**: pinned `AP2E06ISchemaGate::Gate#check!(open:,closed:)` for official Open/Closed/nested Merchant Schema **AND** a separately defined **research-only** `AP2E06ILocalCheckoutShape::Gate#check!(verified_checkout_payload:)` for the already Merchant-authenticated Checkout JWT payload. The latter is a **proposed internal API, not an implemented class**. Both must return their own validated results on the SAME immutable G4 artifact and Host snapshot before `G5Result` can exist. An unchecked payload, absent shape checker, or a caller-created `local_profile=VALID` => `HOLD/verification_unavailable` or `REJECT/unsupported_profile`, never G5 success.

**No stage may consume partially authenticated tokens and claim later-stage success.** A failure at G0/G1/G3 must leave downstream stages uncompleted. Never mark `G5_SUCCESS` merely because an unrelated Python oracle validated the visible JSON or `json_schemer` accepted unauthenticated data.

### Inputs and outputs: conceptual internal contract

| Stage | Mandatory input/provenance | Success artifact and excluded responsibilities |
| --- | --- | --- |
| G4 | G0 original Root/Terminal/Checkout signed bytes, G1 deep immutable snapshot and allowed JWKs, G2 signed Root, G3 fully disclosed `Open`, verified `cnf.jwk` | `AuthenticatedCheckoutChain{snapshot_id, root_wire_sha256, terminal_wire_sha256, merchant_jwt_wire_sha256, verified_open, signed_terminal, verified_closed, verified_checkout_payload, authenticated_key_fingerprints, signed_expiries}`. **No cart/Merchant ID/amount Host business judgment** |
| G5 | **G4 successful artifact** plus pinned Open+Closed+nested Merchant schema originals, SHA/blob and mandatory isolated Checkout JWT payload shape checker (see §4) | `ValidatedOpenClosedAndLocalProfile{same_snapshot_id, same_authenticated_artifact_id, open_schema=VALID, closed_schema=VALID, merchant_ref=LOCAL_PINNED, local_profile=VALID}`. **Not checkout authorization** |
| G6 | **G5 success** + G4 signed Checkout payload + G3 full constraints + **same** G1 Host checkout/challenge/trust snapshot | `BoundCheckoutFacts{same_snapshot_id, verified_checkout_id, tenant, checkout_version, merchant_id, allowed_sku, required_quantity, checked_total, checkout_jwt_raw_sha256, verified_challenge_ref}`. **No Host nonce consumption or payment** |
| G7 | G0–G6 checked ledger, same context/digests and B1 finite deadlines | Bounded `VerifiedEvidence` **only if all B1 required fields are present**; otherwise `HOLD/incomplete_context`, `evidence=nil` |

`G4Result` and `G5Result` must not be public bearer authorizations or writable serialized structs. A string `stage=G5` or caller-supplied hash is not proof that the verifier actually performed G5.

## 3. G4 exact crypto-and-binding obligations

The reviewed new candidate will need a **dedicated isolated Terminal/Merchant crypto implementation**, not a direct call to old P1-2/3:

1. **Root key → Agent key**: use only G3-completely-resolved *Issuer authenticated* `cnf.jwk`; compare normalized P-256 `kty/crv/x/y` against G1 Host-approved Agent and Host challenge issuance-time approved thumbprint. Any missing Host challenge bound => `HOLD/incomplete_context` (not a silent two-party shortcut).
2. **Terminal original JWS**: validate exactly the supported `kb+sd-jwt` wire/JOSE and unambiguous original signed JSON, verify ES256 using Root-endorsed Agent public key and compare decoded claims to strict parse. Never infer Terminal issuer or agent from presentation `kid` or embedded `jwk`. Unknown/extra terminal disclosures/decoys or nested commitments are **fail closed** until a fixed Terminal profile is specified and reviewed; do not ignore.
3. **Root raw binding**: compute `sd_hash = base64url(SHA256(original Root SD-JWT wire bytes))` including original disclosure ordering and delimiters; compare to the Agent-signed Terminal `sd_hash` using fixed-length safe comparison. Never substitute a reserialized Open JSON, compact JWS-only hash, or visible claims hash.
4. **Agent challenge & time**: require signed Terminal `aud`/`nonce` to match *frozen* G1 Host challenge, and enforce the defined, finite signed `iat/exp` policy using B1 `verified_at`; same for signed Open/Closed lifetimes and Root→Closed shared claims. Avoid reliance on Ruby JWT default top-level `exp/iat` behavior to pick stages implicitly. A cryptographically verified early mandatory claim/shape/time reject is still **G4**, not automatically G5.
5. **One signed Closed**: require exactly one unambiguous Agent-signed Closed in the supported Terminal payload; preserve its full signed content for G5. Check Open→Closed immutable claims, no extra hop, forbidden unknown authority fields and immediate structural prerequisites as explicitly mapped below; never silently drop fields to make official Schema pass.
6. **Merchant signed Checkout**: compare Closed `checkout_jwt` with **Host-record original compact JWT string** byte-for-byte and Closed `checkout_hash` to base64url SHA-256 of **those raw JWT bytes**. Separately validate original signed JSON and verify Merchant ES256 with G1 Host-approved Merchant key, not JWT header hints, prior to claiming Merchant authenticity. The correct digest is not proof of Merchant signature validity. Keep verified Checkout payload separately for G5 local profile and G6.
7. **No G6 calls**: Checkout `id`, status, Merchant ID, currency, SKU, quantity, price, subtotal, total or Host expected amount comparisons belong **only to G6 after G5**. The minimum structural requirements for cryptographic binding (e.g. `checkout_jwt` as bytes, `sd_hash` as string) can fail earlier, but their stage attribution must be recorded and cannot count as G5 causality.

A conceptual G4 implementation MUST preserve JWS original bytes, fail on signed JSON duplicate keys, reject noncanonical ES256 segments and unsupported JOSE, and pin `jwt=3.3.0`. Cross-library `JWT.decode` default options and thrown exceptions should be explicitly normalized to signature/authenticity vs unavailable dependency; no exception can produce a success artifact.

## 4. G5 official schema and local shape — precise ordering

- Mandatory **same-invocation** use of `AP2E06ISchemaGate::Gate#check!(open:,closed:)` on G3/G4 authenticated complete Open and Agent-signed Closed. Loader must verify the fixed 3 official schema blob digests, IDs and draft-2020-12; only the allowlisted preloaded Merchant URI can resolve, no HTTP.
- Open's nested `types/merchant.json` governs Merchant **objects inside Open**, **not** the external Merchant-signed Checkout JWT payload. The latter MUST be passed from G4 to the separate G5 lab-only shape checker `AP2E06ILocalCheckoutShape::Gate#check!(verified_checkout_payload:)` (conceptual, unimplemented), then combined with the official checker in the internal orchestrator. Do not claim the official `checkout_mandate.json` validates merchant UCP cart internals.
### Mandatory separate G5 Checkout JWT shape checker — explicit P1-3 predicate inventory

**Contract only; the entrypoint does not exist yet.** After G4 has verified the Merchant signature against the original compact Host JWT, the orchestrator calls an isolated, internal `AP2E06ILocalCheckoutShape::Gate#check!(verified_checkout_payload:)`. Only G4's authenticated, deeply immutable Checkout payload is accepted. It **MUST run in the same invocation before G5 is complete**; `SchemaGate#check!` by itself has no claim to `local_profile=VALID`. The local gate must fail closed on unknown keys/unsupported structure and return a typed immutable `LocalCheckoutShapeValidated` result, tied to the same G4 artifact fingerprint. Missing/checker unavailable => `HOLD/verification_unavailable`.

| Old P1-3 shape predicate | Mandatory G5 local checker | Deferred to G6 (not G5) |
| --- | --- | --- |
| `require_exact_keys!(checkout, %w[id merchant line_items status currency totals links])` | Checkout JSON **Hash** with exactly these 7 keys; reject additional/missing fields; preserve the original `links` member without granting authority to links or silently widening its permitted meaning | Checkout `id` equals Host checkout ID, `status == ready_for_complete`, and currency equals Host |
| `require_exact_keys!(merchant, %w[id name])`; merchant `name` present | Merchant Hash, exactly `id`/`name`; `name` a nonempty String, with ID present; no unrecognized merchant authority fields | Merchant `id` equals Host expected and Issuer allowed Merchant ID |
| `lines.is_a?(Array) && lines.size == 1`, `require_exact_keys!(line, %w[id item quantity totals])` | Exactly one `line_items` entry; line Hash with exactly 4 specified keys | Line quantity equals required issuer quantity; Host cart association |
| `require_exact_keys!(product, %w[id title price])` | Product Hash exactly `id`/`title`/`price` | Product `id/title` match Issuer permitted SKU, `price` is positive integer, and amount calculation |
| `validate_totals!` on line AND Checkout: arrays of two Hashes, each exact `%w[type amount]`, names `subtotal` and `total`, integer amount values | **Both** totals arrays must have exactly two objects, each keys exactly `type`/`amount`, a unique `subtotal` and a unique `total`, with Integer amount types (reject duplicate labels, unknown types, noninteger) | Each subtotal and total must equal computed `price * quantity` and Host expected amount |
| P1-3 requires strict additional Issuer constraint shape/Requirement `id` type | Retain original signed fixed-authority constraints in G3 and any independent local Open checks, without weakening signed structure to reach G5 | Full authorized Merchant/Requirement/SKU/quantity comparisons against Host record |

**Predicate conservation rule:** G5 must preserve all previous *structural* predicates, G6 all previous *equality, monetary and constraint-meaning* predicates. The split may add reviewed stricter field-type checks but must not silently widen acceptance or misrepresent new checks as old-P1-3 parity. P1-3 did **not** assign independent semantics to `links` or some `line.id` values; any newly meaningful use requires its own review/STOP rather than pretending these are validated authorities. G5 local-INVALID is `unsupported_checkout_profile`; any prior G3/G4 shape failure is recorded there, not as a G5 causal observation. `G5Result.local_profile=VALID` is **impossible** without independently completing the shape checker and recording its exact result.

- Preserve stricter fixed Issuer authority grammar/unknown keys, Agent Terminal/Closed minimum contract and local Checkout payload shape **as independent predicates**. Record `official_open`, `official_closed`, `local_shape` separately. Reject invalid official schemas regardless of local profile decisions; where an earlier mandatory safety condition has already rejected, record the actual earlier stage rather than fabricating a G5 failure.
- `verification_unavailable` for missing/mismatched `json_schemer=2.5.0`, damaged original schema, unknown `$ref` or no pinned upstream directory is **HOLD**, not `invalid_open_schema` or a signature rejection.
- G5 output binds the same Host snapshot and G4 authenticated artifact fingerprint. Mutating authenticated `Open/Closed` objects between G4 and G5 must invalidate results/STOP.

## 5. G6 fixed Checkout semantics — move (not remove) checks

**After and only after G5 success**, G6 evaluates these checks presently interwoven with `AP2CheckoutBindingResearch.verify!`:

| Old P1-3 logic | Target G6 check | Required Host source |
| --- | --- | --- |
| `checkout["id"] == expected_checkout_id` | Signed Checkout payload ID equals Host `checkout_ref.checkout_id`; tuple `(tenant,id,version)` equals challenge Checkout ref | Same immutable Checkout + challenge records (B1) |
| `status == ready_for_complete` | Fixed profile status with reviewed Host current status policy | Host current Checkout snapshot |
| `currency == expected_currency` | Compare signed Checkout currency to Host expected currency | Host Checkout snapshot |
| `merchant.id == expected_merchant_id` | Compare signed Merchant ID to Host Merchant allowlist and issuer-allowed resolved Merchant | Host Merchant trust/profile + G3 Open |
| Exact 2 constraint types; one Merchant/Requirement/SKU | Enforce **entire** resolved issuer authority, no unknown signed constraint or relaxation; fixed allowed Merchant/SKU and required quantity | G3 closure artifact and Host fixed profile |
| Checkout one line, product `id/title`, unit price, line quantity | **After G5 has checked exact Checkout/line/item shape**, match allowed SKU/quantity, verify positive integer price and Host expected facts | G3 fully resolved authority + Host checkout record |
| `line_amount == expected_total_minor`, two totals entries | **After G5 totals shape/type validation**, perform checked safe amount arithmetic and compare both subtotal/total values to computed amount and Host expected total; overflow/non-integer unsupported | Signed checkout + Host expected amount |
| Host checkout JWT raw equality/hash | **Already proved at G4**; G6 checks same authenticated artifact/snapshot digest, never selects new Host JWT | G4 immutable result |

Current synthetic Host policy lacks durable `checkout_version`, challenge binding/Buyer ref and separate signer trust timestamps. **Until B1 is solved, G6/ G7 full success cannot be claimed**. Never quietly replace missing information with IDs from the signed payload itself.

## 6. First reject ledger and causal evidence (B3 carry-over)

Record for each invocation: `status` (REJECT/HOLD or evidence-only success), `first_reject_stage`, sanitized stable `reason`, `completed_stages` ordered prefix, original signed wire SHA-256, pinned schema fingerprints (if actually loaded), Host snapshot digest, signer-key references, fixed `verified_at`, and **which independent O1–O5 claims were actually established**. No raw keys/nonce or full wire in public logs.

| Scenario | Mandatory independent preconditions | Expected attribution / avoid false claims |
| --- | --- | --- |
| FULL positive | Signed synthetic A Root, exact 3 disclosure closure, valid Terminal/Merchant signatures, G1 complete snapshot, authentic Open+Closed official Schema-valid, G6 Host facts valid | Must reach G0–G6 on **same Ruby invocation** and G7 evidence-only. Otherwise `E06_INTEGRATED_UNPROVEN` |
| N1 / N2 | Issuer genuine signed original Root + independent graph & Schema oracle (N2 requires resolved Open official-VALID) | G3 incomplete/unsupported signed graph, **not** schema inferred from visible Open |
| N3O / N3C | All G0–G4 preconditions genuinely satisfied and independently Schema-invalid Open or Closed | **Only a real G5 `invalid_open_schema` / `invalid_closed_schema`** is an integrated causal G5 negative. G3/G4 prior fixed-shape reject => `G5_CAUSAL_NEGATIVE_NOT_PROVEN` |
| N4 | Valid signatures/closure AND Ruby G5 both official schemas VALID | G6 ID/merchant/cart/amount/constraint mismatch |
| N5A / N5M | Root genuine & complete; distinct proper Agent or Merchant failure evidence | G4 bad `sd_hash`/Agent/merchant signature; never claim G5/G6 |
| N6 | Untrusted B has independently valid B signature or Host policy expired with A signed input | G1 trust failure, not failed Issuer signature |
| N7J / N7R / N7S | G0 escaped duplicate signed JSON key; explicit cap excess; or pinned Schema unavailable | G0 ambiguous/resource reject; G5 unavailable only if actually reached G5 |

**Critical tension:** G3's isolated Root `verify_full_root!` already validates requirement `id` type and other narrow shapes before G5. It may therefore reject an independently Schema-invalid Open at **G3**. This is safe early failure, but **NOT proof of G5 causal coverage**. Do **not** weaken the fixed acceptance profile or relabel the failure to get an artificial N3 PASS. If no G5-reachable validly signed/schema-invalid variant fits the fixed research profile, report `E06_INTEGRATED_PARTIAL / CAUSAL_NEGATIVE_UNPROVEN` and retain RED/HOLD.

## 7. Proposed future small diff (not authorized by this document)

1. **New** `research/phase2a_e06i/isolated_agent_merchant_crypto.rb` — standalone explicit crypto-and-binding G4; no legacy import; namespaced, audited equivalence to intended P1-2/3 predicates.
2. **New** `research/phase2a_e06i/isolated_checkout_shape.rb` — dedicated G5 local-only shape checker with the explicit strict Checkout JWT payload schema in §4; requires authenticated immutable G4 Checkout payload and returns a verifiable typed result.
3. **New** `research/phase2a_e06i/isolated_checkout_semantics.rb` — standalone G6, accepts ONLY immutable G5 success and G1 Host snapshot. Preserve all fixed P1-3 accept/reject invariants.
4. **Existing research-only** `research/phase2a_e06i/integrated_probe.rb` — wire G4→G5 official pinned gate + local Checkout shape gate→G6, ensure no success/evidence from missing B1; immutable typed outputs and first-reject ledger.
5. **Separate review/approval before implementation** for Host synthetic fixture enrichment, new tests/generators/CI, change to `schema_gate.rb`, or legacy source changes. Paths are **proposals** only, not scope grants. No Gem/public API, GCP, payment/receipt, or real Issuer enrollment.

### Required review checklist before any code authorization

- [ ] B1 coherent Host immutable snapshot, Issuer+Agent+Merchant finite trust and challenge, checkout version/Buyer bound; missing information cannot lead to G7.
- [ ] Standalone Terminal ES256 and Merchant ES256 entrypoints never call legacy P1-2/P1-3 or import `minitest/autorun`; original signed bytes unchanged.
- [ ] Complete mapping of every old P1-2/P1-3 security predicate into G4/G5/G6; gaps result in STOP, not silent removal.
- [ ] G4 `sd_hash` binds exact Root wire; Merchant `checkout_hash` binds Host original Checkout JWT bytes, and Merchant JWT signature verifies independently.
- [ ] Same Host context and single `verified_at` carried by opaque immutable artifacts; signature, schema, Host semantics remain separate.
- [ ] G5 loads pinned Open/Closed/nested Merchant Schema offline **and independently runs the §4 dedicated strict Checkout payload shape checker**; both results are mandatory before G5 success/G6. G5 causal negative unproven if prior stages reject.
- [ ] No new automatic CI; any signed-fixture / Ruby/Python execution and one-run manually dispatched CI require distinct **explicit approval B under #73**.
- [ ] Current #47/Phase 2-A exit/Phase 2-B remain HOLD even if this design PR is merged.

### References

- [B1 Host snapshot design](PHASE2A_E06I_B1_IMMUTABLE_HOST_SNAPSHOT_CONTRACT.md)
- [E06 G0–G7 order](PHASE2A_E06_INTEGRATED_VERIFICATION_ORDER_CONTRACT.md)
- [E06-I bounded test/oracle plan](PHASE2A_E06I_BOUNDED_RUBY_SCHEMA_INTEGRATION_PLAN.md)
- [Original P1-2 implementation](../research/p1_2/two_hop_research.rb)
- [Original P1-3 implementation](../research/p1_3/checkout_binding_research.rb)
- [Unexecuted E06-I isolated probe](../research/phase2a_e06i/integrated_probe.rb)
- [Pinned schema-only loader candidate](../research/phase2a_e06i/schema_gate.rb)
