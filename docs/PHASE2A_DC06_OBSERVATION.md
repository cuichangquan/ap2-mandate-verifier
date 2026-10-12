# Phase 2-A DC06 — genuinely Issuer-signed unknown authority layouts

**Issue [#58](https://github.com/cuichangquan/ap2-mandate-verifier/issues/58) / research only / partial matrix.** Upstream AP2 v0.2.0 pinned commit `b4587ac1d055888a73b4b21750973cffba961793`.

## Why separate from DC05

DC05 showed real issuer-signed decoy digests and fixed-profile fail-closed behavior. It did not prove generic rejection for genuinely signed *unknown authority claims*. Here the official pinned SDK's signer issues signed alternatives rather than editing an Issuer JWT **after** signing. The model-defined control uses `MandateClient.create`. The unknown claims are issuer-signed with pinned `common.selectively_disclosable_claims` and `common.issue_sd_jwt` primitives; they are deliberately **not claimed to be emitted by the unmodified official OpenCheckoutMandate facade**.

## Five signed presentations

| Case | Authenticated change | Expected bounded Ruby |
| --- | --- | --- |
| FULL | Official Open/Root with 3 disclosed array elements | `LIMITED_POSITIVE` |
| Signed Root sibling | Extra `future_root_authority` signed as a JWT root sibling | `unsupported signed JOSE/Root claims` |
| Signed nested unknown | Extra `future_authority_policy` under Merchant Constraint | `unsupported fixed-Issuer signed claim layout` |
| Signed nested object disclosure — FULL | The same extra field as selectable object property, fully disclosed | Reject unknown object `_sd` |
| Signed nested object disclosure — hidden | Withhold only the extra signed property disclosure; re-sign Agent Terminal `sd_hash` | Reject unsupported object `_sd`; independent O3 must separately prove exact signed missing digest |

Independent O1/O2 verify Issuer/Agent/Merchant signatures, original signed bytes, Root presentation exact Terminal `sd_hash`, Host aud/nonce and Checkout JWT original/hash. O3 traverses signed JWS from top-level and checks graph positions plus incomplete unknown nested object digest. O4 runs the official pinned Open JSON Schema on each **actually presented** Open and records VALID/INVALID separately. O5 invokes the isolated Ruby profile only after FULL succeeds and traces explicit rejection origins; Schema-only/invalid signature/incorrect `sd_hash` are not valid passes.

Signed `_sd` visible+hidden share one identical issuer JWS and differ only in provided signed-referenced Disclosure. Even a fully disclosed signed unknown profile remains unsupported. No extra field or decoy is whitelisted.

**Explicitly NOT RUN here:** genuinely signed duplicate/reused identical digest or placeholder and a second, authentically hidden `delegate_payload` authority candidate. These are not to be treated as PASS because signed fixture construction has not been independently established. Their remaining status prevents declaring a complete DC06 matrix.

## Evidence and exit criteria

Scoped GitHub Actions installs pinned direct versions with official source checkout, generates only ephemeral signing keys, saves fully synthetic public-key signed original wire and Disclosure segments + SHA256/byte-length manifest, records HEAD/upstream SHA and runtime dependency freeze, and uploads with seven-day expiry. This is not permanent replay evidence. CI being green indicates **`LIMITED_DC06_PARTIAL_OBSERVED` only**, not a full DC06 or Phase 2-A GO. Failed fixture preconditions or unattributable rejection = RED/HOLD.

Do not merge without latest-HEAD Codex P1/P2 review. Issue #47 remains OPEN; Phase 2-B, public Gem/API, Host nonce-CAS, revocation, HC06, payment, production Checkout and GCP are HOLD.

## Observation

### First signed run

- [CI #38276544290](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38276544290): authentic Python O1–O4 passed, but Ruby test harness expected a later `walk!` rejection for the **fully presented** unsupported object disclosure. The bounded verifier had correctly rejected the genuine object disclosure **earlier** as `unsupported non-array disclosure`; therefore CI FAILED. This was not counted as an accepted gate. The observation expectation was corrected, without modifying the verifier or loosening its profile.
- [CI #38276643000](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38276643000), verified PR HEAD `670780d54bcf8c058288588b72496f80dd5eb7c9`: **SUCCESS**, all steps successful. Pinned official AP2 source + Python SDK, Ruby `jwt=3.3.0`, and Python independent signed-wire and official Schema oracles ran from fresh transient signing keys.
- **O1/O2:** all five Root/Agent Terminal/Merchant Checkout original signed wires and exact Root presentation `sd_hash`, Host aud/nonce, Checkout JWT/hash passed. No post-signature JSON edit substituted for Issuer-signing.
- **O3/O4:** all five actual presented official Open schemas reported **VALID**; unknown Root sibling and nested signed field remained distinctly visible in genuinely signed claims. Withheld unknown object Disclosure had one truly issuer-signed unresolved object commitment at `$/delegate_payload/0/disclosed/constraints/1/_sd`; Python independently produced `incomplete_disclosure: signed commitment not disclosed`. The same Root JWS was used for the fully disclosed and withheld unknown-object variants and Agent Terminal was re-signed to match each.
- **O5:** Ruby fixed-Issuer candidate accepted FULL (`LIMITED_POSITIVE`) and rejected all four authentic signed unknown Root/Constraint/object-Disclosure presentations with attributable guards:
  - Root sibling: `unsupported signed JOSE/Root claims`
  - Visible unknown nested authority: `unsupported fixed-Issuer signed claim layout`
  - Fully disclosed object SD: `unsupported non-array disclosure`
  - Withheld unknown object SD: `unsupported object SD/decoy or misplaced marker`
- **Outcome:** `LIMITED_DC06_PARTIAL_OBSERVED`. The signed duplicate/reused commitment case and the extra hidden authority delegate remain **NOT RUN**. Do not claim broad DC06 or Phase 2-A Gate PASS.
- **Synthetic public-only evidence:** Actions artifact ID `11759486507`, archive SHA256 `e227452a4a1265bbfc8316d1ad29e64ecdb7219d2578f5616bcbd5d21515c976`, expires **2026-10-19T16:20:15Z**. Original signed JWS, disclosures, Terminals, Merchant JWT, Host public JWK snapshots and per-file SHA256/byte-length manifest available for **7 days only**, not permanent replay.

**PR remains unmerged pending current-HEAD Codex security review.** Parent #47 OPEN, Phase 2-B/Gem/public API/production/Host nonce-CAS/HC06/payment HOLD.

### Strengthened signed-chain attribution (latest O1–O5 run)

On [CI #38276862250](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38276862250), research HEAD `a547453ef2189959c92e506bc4433ac92fea2a99`, **SUCCESS** after independent Python oracle strengthening:

- For every one of the five genuine signed presentations, the unique disclosed Open item's raw base64url Disclosure is matched against the **Issuer JWS-signed** `delegate_payload[0]` digest; the disclosed `cnf.jwk` must then match the independently fixed Host Agent public key before counting the Agent Terminal signature as valid.
- For the withheld nested unknown object field, the independent oracle now proves that the *particular* omitted `future_authority_policy` Disclosure digest is present in the signed `constraints[1]._sd` array; an unrelated missing digest is insufficient.
- Existing five actual presented official Schemas remained VALID, FULL Ruby `LIMITED_POSITIVE`, and all four issuer-signed profile negatives were rejected with traced origins.
- Public-only replay artifact ID `11759735483`, archive SHA256 `5bff3c6817a1db82062fa72096b17324a72935f4c2a6e71198a7c4bda12c3903`, expires **2026-10-19T16:22:08Z**. This is temporary rather than durable evidence.

**Status remains `LIMITED_DC06_PARTIAL_OBSERVED`**, not a full DC06 completion. Genuine signed duplicate digest/placeholder and extra hidden delegated authority remain **NOT RUN**; Issue #58 remains OPEN until separately solved. Latest PR HEAD review still required.
