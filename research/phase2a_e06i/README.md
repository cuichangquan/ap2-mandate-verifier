# Phase 2-A E06-I/A — isolated Ruby research, incomplete by design

Status: **CODE WRITTEN / NOT RUN / G4–G7 HOLD / NO CI APPROVAL / PHASE2-B HOLD**.

## A3-H1 approved research scope: claimed synthetic Host enrollment source

`isolated_host_source.rb` compares a **separately submitted, strict/bounded
synthetic enrollment-source JSON claim** (Issuer A, Agent, Merchant individual
key/policy records, fixed tenant) with the existing A2 G1 Host snapshot
candidate. It rejects unsupported identities, policy mismatches, inactive or
known-revoked trust records and source/snapshot inconsistency; indeterminate
revocation state does not override a definitive reject. Source and claimed
digest are both caller-controlled, so **matching SHA and enrollment data are
NOT independent provenance**. The return value is a `SourceClaim` with
`status=HOLD`, `authoritative?=false`, `admissible?=false`,
`evidence=nil`, even when all submitted fields match. No real pinned Host
registry is available, no key thumbprint was independently enrolled, and
no source material comes from a signed JWT as accepted Host authority.

A3-H1 is **source creation + static code review only**, separately approved
under [Issue #83](https://github.com/cuichangquan/ap2-mandate-verifier/issues/83).
It is not A3-T and does not grant approval B for Ruby/Python, testing, signed
fixtures or CI. The original `integrated_probe.rb` is unchanged; no
new successful G1→G7 stage is wired. This source interface is **NOT RUN**.

## A3-H1 nonce issuance source — globally scoped requirement, NOT a ledger

`isolated_nonce_issuance_source.rb` inspects a **separately supplied
synthetic ledger JSON claim** against the previously checked A2 Host
snapshot candidate. It binds claimed issuance to challenge reference,
signed Terminal audience/nonce digest and frozen Agent thumbprint,
Checkout tenant/id/version, opaque Buyer/Account, issuance time and
expiry. It **rejects a known narrower scope** than Host-verifier-wide:
the Terminal signs `aud` and `nonce` but not tenant, session or
`challenge_ref`. It requires the claimed source to describe a CSPRNG
origin of at least 128 entropy bits, durable atomic uniqueness and
complete cross-tenant/session/issued/consumed/expired/reissued history.

**Claims are not proof.** No durable issuance registry, random generator,
atomic uniqueness index or consumption CAS exists in this module.
Even a consistent claim is `LedgerClaim(status=HOLD,
replay_safe?=false,authoritative?=false,admissible?=false,evidence=nil)`.
The ledger JSON and its matching SHA remain caller controlled; a single
event cannot establish global history or prevent challenge re-labelling.
This new source is deliberately **NOT** an integrated G1→G7 success path.
It is A3-H1 source-only, NOT RUN, with A3-T and execution approval B HOLD.

## A3-H1 source/nonce claim composition (still never trusted G1)

The existing `isolated_host_snapshot.rb` now also provides
`inspect_untrusted_sources_only!(...)` as a **separate diagnostic**.
It checks the A2 Host snapshot candidate once, then feeds **the same frozen
candidate and Host `verified_at`** to both A3-H1 Host enrollment and nonce
issuance source claim inspectors. Source/ledger mismatches are rejected (or
unavailable records held) by the respective narrow inspector; there is
**no authenticated Host root, durable Host-wide issuance history or CAS**.
When every *self-reported* record agrees, the result is still
`CombinedClaim(status=HOLD,g1_admissible?=false,
authoritative?=false,evidence=nil)` with only wire SHA digests.
Neither this method nor its input claims are trusted/G1 result types;
the existing `integrated_probe.rb` is **unchanged** and never consumes it.
It does not run G0/G2–G7, sign/verify a JWT, perform an atomic nonce check,
assert actual CSPRNG entropy or allow a payment. It is **NOT RUN**.

## A2-5 preflight wiring: trusted G1 entrypoint STILL BLOCKED

`integrated_probe.rb` now also exposes an internal
`inspect_a2_host_candidate(host_json:, expected_host_sha256:, verified_at:)`
for the already merged A2-1 Host snapshot candidate. This is a **Host-only
preflight**, not an integrated G0→G1 verifier: it performs no G0 signed-wire
checks, does not claim any completed G0–G7 stages and never calls G2/G3/G4/G5/
G6/G7. The result always has `g1_admissible=false`, `evidence=nil`; a
structurally consistent candidate produces `HOLD`, while malformed/revoked
Host assertions may produce `REJECT`. Its `first_reject_stage=nil` states
that the integrated G0–G7 ledger has **not** been executed, rather than
mislabeling an independent Host input check as an integrated stage proof.

The shared `isolated_host_snapshot.rb` inspector also now defers unknown
revocation-state HOLD until every selected Issuer/Agent/Merchant **key and
policy** was checked for an explicit known `revoked` state, and evaluates
known nonce↔Challenge binding mismatches before incomplete registry HOLD.
Thus definitive known-invalid Host claims cause REJECT even when a different
claim is unknown. This is a conservative static code fix, **not executed**.

**No successful Host provenance/trust/nonce registry adapter exists.** The
original `observe(policy_json:,case_data:,policy_digest:)` behavior is
unchanged and still stops at G4. Independent isolated G4/G5/G6 modules do
not accept this preflight as a trusted G1 success. No execution/CI approval B
has been granted; do not infer G1/G4/G5/G6/G7 success from this new method.

## A2-1 scoped new Host-context candidate (approval recorded in Issue #75)

`isolated_host_snapshot.rb` is a **new isolated research candidate** that
requires a separate Issuer/Agent/Merchant key+policy trust entry (active,
explicitly non-revoked, each finitely valid at one Host `verified_at`), P-256
**on-curve** public-key coordinates, each trust tenant equal to Checkout tenant,
Merchant signer subject equal to the Checkout Merchant ID, a
Host Challenge/Checkout tuple and Buyer reference, Host-verifier-wide
nonce uniqueness/entropy *claims*, exact Host JWT wire, and deep detached
immutability. It checks bounded strict JSON and out-of-band expected raw
SHA-256 but **never treats claims or a matching digest as Host provenance**.
Every successful call returns `Candidate(status=HOLD, admissible?=false,
evidence=nil)`. An independent Host registry/provenance adapter and
atomic nonce issuance/consumption are **NOT implemented or inferred**. This
candidate is **NOT wired into `integrated_probe.rb`**; the earlier G0–G3
research remains unchanged. No usable G1/G4/G5/G6/G7 success can be claimed.

A2 grants only **file creation and static PR review**; no Ruby/Python/test
execution, fixture generation, CI, workflow or legacy files may be changed.
Any attempt to promote the candidate directly to G1 success is a STOP gate.


**Dependency runtime guard:** `integrated_probe.rb` returns `HOLD` before
G0 if pinned Ruby `jwt 3.3.0` is missing or a different version is already
activated. The isolated Root closure lazily activates exactly `jwt 3.3.0`;
its direct entrypoint also rejects absent/unsupported versions. The Schema-only
gate loads exactly `json_schemer 2.5.0` **in its constructor** and returns
`verification_unavailable` if missing or a mismatched version is activated.
Neither implementation loads optional gems at module-import time. Thus
missing/mismatched libraries are **verification unavailable**, not a
signed-wire signature-invalid verdict. These behaviors are **NOT RUN**.


This directory is the first **approval A only** implementation slice for
[Issue #73](https://github.com/cuichangquan/ap2-mandate-verifier/issues/73).
It is NOT a usable AP2 verifier, Gem, merchant checkout gate or evidence of
passing the E00–E10 exit checklist.

## Files and precise boundary

- `schema_gate.rb`: fixed AP2 v0.2.0 original Open/Closed/nested Merchant
  JSON Schemas using Git blob SHA checks, strict local merchant URI resolver
  and `json_schemer 2.5.0`. `Gate#check!` is **Schema-only** and must NOT be
  called on unauthenticated/fractionally disclosed claims to infer authority.
  It does not verify signatures or decide Host ALLOW.
- `isolated_host_snapshot.rb`: A2-1 new, standalone Host context CANDIDATE
  inspector. It always produces HOLD-only candidate records even on structurally
  well-formed Host assertions; no provenance/nonce registry/real enrollment.
- `isolated_host_policy.rb`: research-only source snapshot of the E01-S
  synthetic Host policy with a direct import of only strict JSON code. No
  `minitest/autorun`, legacy verifier, or external service is loaded.
- `isolated_root_closure.rb`: research-only source snapshot of DC04's
  fixed-3-commitment Root validator with direct strict JSON/JWT imports.
  Duplicated security code is intentional **temporary review debt**, not a
  general SDK; original DC04 is unchanged. G3 mixes Root closure with local
  fixed shape/time and therefore is NOT independent proof of every E03 case.
- `integrated_probe.rb`: isolated G0 parsing/bounds, G1 synthetic Host policy,
  G2 Issuer signature **without JWT claim expiry/iat/issuer/audience policy**
  and G3 **isolated DC04 snapshot** signed Root closure/local fixed shape.
  **It always returns HOLD at G4 even on a G0–G3 positive** because existing
  P1-2/P1-3 code mixes Agent/Merchant crypto and Host checkout semantics.
  It NEVER runs G5, G6, or G7 and NEVER emits VerifiedEvidence or payment ALLOW.
  G0 checks all JWS signature segments for canonical ES256 encoding and
  recursively caps every JWS JSON, Disclosure, and untrusted Host policy at
  depth 24, object 32 fields, array 16 entries. These checks remain **unrun**.
- `test_schema_gate.rb`: proposed **unexecuted** unit assertions, including
  unsigned/malformed G0-only JWS signature and over-limit nested JSON cases.
  These cases prove neither Issuer signature nor SD closure. The tests using
  `AP2_E06I_UPSTREAM_ROOT` require an independently pinned official AP2
  checkout and must not be mislabeled E06 signed tests. No fixtures or CI
  were produced by adding tests.

**No Ruby execution, test suite, Python generator, signed fixture, CI run,
workflow change, or external infrastructure is authorized by this PR.**

## Next code review and STOP gate

1. Review original signed Root closure attribution and the untrusted G0
   strict parser separately from G2 signature proof; negative early reject
   never proves G3. The root fixed profile intentionally excludes some
   official schema-valid shapes.
2. **No legacy Minitest dependency remains in the non-test probe**:
   it imports the above two namespaced, direct-dependency snapshots instead
   of importing original E01-S/DC04 and their transitive P1-1 autorun hook.
   New snapshots are **NOT RUN** and require exact parity/diff review against
   the original pinned repository source before any stronger claim. Copying
   validation code does not automatically transfer DC04/E01-S test evidence.
3. Obtain a separate review of a **safe crypto-only G4 extraction**. Never
   call the existing `AP2CheckoutBindingResearch.verify!` before G5, since it
   also performs G6 Host total/cart/merchant semantic comparisons.
4. After reviewed G4, make the pinned `schema_gate.rb` mandatory for the
   *same* Ruby invocation's authentic Open and Closed; only then consider G6.
5. An eventual G7 needs bounded, authenticated Host challenge expiry and
   shortest signed Root/Terminal/Closed/trust TTL, plus a verified Host snapshot;
   if unavailable, return HOLD instead of inventing `valid_until`.
6. A future 13-scenario signed O1–O5 execution and its one-job CI are
   **approval B**, requiring separate explicit owner authorization and a
   latest-HEAD review. The positive must first reach G7 before negatives
   can be counted as integrated safety evidence. No automatic expansion.

Official AP2 source SHA:
`b4587ac1d055888a73b4b21750973cffba961793`.
Full canonical design:
[docs/PHASE2A_E06I_BOUNDED_RUBY_SCHEMA_INTEGRATION_PLAN.md](../../docs/PHASE2A_E06I_BOUNDED_RUBY_SCHEMA_INTEGRATION_PLAN.md).
