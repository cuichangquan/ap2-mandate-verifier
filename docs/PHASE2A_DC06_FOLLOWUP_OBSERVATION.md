# Phase 2-A DC06 follow-up — two remaining signed ambiguity shapes

**Research-only.** This experiment extends the partial [DC06 case](PHASE2A_DC06_OBSERVATION.md) tracked in [Issue #58](https://github.com/cuichangquan/ap2-mandate-verifier/issues/58). The official AP2 source is pinned to v0.2.0 commit `b4587ac1d055888a73b4b21750973cffba961793`; no production Gem, API, Issuer registry, Host CAS or payment implementation.

## Independent proof and scope

Two previously NOT RUN signed shapes are now issued by the official **pinned signing primitive** `common.issue_sd_jwt`, with an independent `jwcrypto` verifier checking the reissued original Root JWS signed bytes and the Host-fixed Issuer public key:

1. **Repeated Issuer-signed Root commitment:** Start with a fully issued AP2 Open Root from the official `MandateClient.create`. Take the immutable original first Open Disclosure and its SHA256 digest, build a raw signed claim graph containing *two* `delegate_payload` placeholders referencing this same genuine digest, and have the pinned `common.issue_sd_jwt` sign that new graph. Append the original unmodified SD-JWT Disclosure segments. Prove both signed paths reference the same authentic Disclosure and an independent whole-graph walk flags `repeated signed commitment`. This is a *synthetic low-level issuer-signed counterexample*, **not a claim that ordinary MandateClient emits duplicate digests**, nor that Ruby's repeated-digest guard was reached.
2. **Second Issuer-signed hidden Open authority:** Build two separate signed Open payloads with the same Agent `cnf.jwk` but different `allowed_merchants`. `DisclosureMetadata` and the pinned SDK issuer produce two different Root array digests, with recursively signed SKU/Merchant nested Disclosures. A full control includes *both* complete subtrees; the reduced presentation omits the second Open and all nested Disclosures associated with that second signed commitment, keeping the exact original Issuer JWS and complete first subtree. Independently confirm the second signed digest remains in the Root and cannot be resolved by the reduced presentation.

Each Root presentation gets its **own freshly signed Agent Terminal**, bound to the exact Root serialization with `sd_hash`, Host `aud` and `nonce`; the original Merchant Checkout JWT and hash are also checked. No private JWKs are serialized. The independent oracle proves the fully disclosed first Open schema VALID in all cases, and both Open schemas VALID where they are actually disclosed. The second hidden Open is `UNAVAILABLE_UNDISCLOSED`, *not* claimed Schema VALID.

## Bounded Ruby result gate

| Presented signed wire | Expected Ruby fixed-Issuer result | Interpretation |
| --- | --- | --- |
| Original FULL single Open | `LIMITED_POSITIVE` | Positive precondition |
| Root with same signed digest in two slots | `REJECT: invalid signed Root array` | Exact Root cardinality detects surplus **before** disclosure walk |
| Two fully disclosed signed Open authorities | `REJECT: invalid signed Root array` | Exactly one Open authority required |
| Same two signed Opens, second undisclosed | `REJECT: invalid signed Root array` | Hidden second authority remains signed, fails cardinality |

These are **earlier structural guards**, not evidence of a generic SD-JWT duplicate resolver or of Ruby having verified the signature *before* rejecting the malformed shape. Independent Python separately verifies cryptographic authenticity of the original signed Root bytes, public-key trust, Agent/Checkout binding and raw commitment structure. Do not conflate these two observations.

## Gates and limits

- Separate scoped CI must prove exact signed-wire and Disclosure digest provenance with `jwcrypto`, independent complete/incomplete/repetition classification, explicit official **presented** schema observations, Ruby FULL positive and attributable fixed-profile Root-cardinality negatives.
- 7-day artifact contains only synthetic public JWKs and signed wires, file SHA256/byte-count manifest, upstream/PR SHAs and dependency freeze. No persisted private signing keys.
- If official signer cannot produce an authentic signed negative or an oracle fails, record **BLOCKED/RED/HOLD** rather than asserting success.
- Even with all named DC06 synthetic variants observed, this **does not by itself prove Phase 2-A completeness**. The parent design-only [Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) still lacks an independent issuer-authenticated commitment-completeness policy for general AP2 issuers and new unknown authority paths. Phase 2-B, public Gem/API, production/payments, Host nonce-CAS, revocation and Receipt remain HOLD.
- Latest-HEAD Codex P1/P2 review and exact HEAD CI success are required before merging any follow-up PR.

## Observations

**NOT RUN / outcome unverified until real scoped CI.**
