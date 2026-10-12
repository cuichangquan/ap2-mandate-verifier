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

**NOT RUN / candidate gates not yet proven.**
