# Stage14 — opt-in unified research verification and Evidence

`AP2MandateVerifier.verify_research(**inputs)` accepts exactly the Stage13
verify_host_binding keyword inputs. It runs that entire supported conjunction,
then returns a frozen ResearchResult with status=verified_research,
code=scoped_research_verified, success?=true and a deeply immutable
ResearchEvidence. This success applies only to the registered limited research
profile and authenticated Host input assumptions. Evidence is not Host ALLOW,
payment permission, a production safety declaration or generic AP2 conformance.

Every earlier entry, including verify_host_binding and
verify_trusted_scoped_constraints, still returns the old Result type with
success?=false/evidence=nil. Result has no success state or Evidence injection
argument. The new opt-in entry is the only public verification path that creates
research Evidence; there is no factory accepting caller-supplied status/facts or
JSON, and no deserialize/reconstruct method. Private constructors are ordinary
API discipline, not protection against malicious code/reflection in the same
Ruby process. Trusted code/interpreter and direct in-process return are the
boundary. Exported JSON/Hash/Marshal or remote values must not be treated as an
authentic result; no external transport/signature/attestation contract is added.

## All gates before construction

The unified path reuses Stage13's single checked handoff: strict bounded raw
inputs and JSON, independently selected current Host trust/profile, exactly
one active/time-valid canonical ES256/P256 key per role, Root signature and
original commitment closure, Agent key confirmation and terminal signature,
original Root sd_hash/nonce/audience, Closed original Checkout bytes/hash and
Open/Closed times, Merchant signature and IDs, fixed schema/constraints/amounts,
current Host B/challenge issuer/state/references/binding and validity intersection.
Mere matching Host context, one signature, Schema validity or intermediate
handoff never constructs Evidence. Unsupported shape/profile/constraint,
rejection, dependency loss or unexpected internal/construction failure returns a
non-success Result with evidence=nil. Unrecoverable process failure cannot
produce a result. No extra token/Host authority is inferred from successful input
syntax or a caller's success/status field.

## Immutable Evidence contract

ResearchEvidence#to_h returns a deeply frozen detached Hash; #[] reads a field.
All keys, strings, arrays and nested hashes are frozen. Result and Evidence
ordinary dup/clone preserve the same immutable identity, even clone(freeze:false).
Changes to caller-owned bytes during key work or after verification cannot
replace checked values or modify the returned Evidence.

The exact top-level fields are:

- contract_version = ap2.research-evidence.2; implementation_revision =
  ap2.research-verifier.2; revision_kind = static_identifier_not_runtime_attestation.
- profile_ref/profile_version/profile_definition_hash from the checked fixed
  registration; verified_at and clock_source_id from the checked Host evaluation.
- valid_from=max(all starts), valid_until=min(all exclusive ends). Starts/ends
  include Open/Closed, all selected keys, snapshot, challenge and terminal.iat /
  terminal.iat+301. The fixed profile has no additional period. No Merchant
  expiry/nbf is invented. verified_at is inside that interval, skew0.
- trust_snapshot: id, policy_version, content_hash from the validated raw-body
  registration, not a token claim.
- selected_keys: exactly Issuer/Agent/Merchant checked records, excluding PEM;
  role, identity, tenant_id, purpose, key_ref, profile_ref/profile_version,
  key_fingerprint, algorithm, active, not_before/not_after identify the actual
  selected keys and periods. Fingerprints were checked against canonical PEM
  bytes and those exact keys verified the signatures/Agent cnf.
- checkout_binding: every checked B field, including tenant, Buyer/account,
  order ID/version, approved Agent fingerprint, profile version, original-wire
  digests, Merchant, audience, currency and total.
- verified_challenge: explicit projection of checked challenge ID/issuer, B,
  trust/profile references, not_before/not_after and observed state=issued, plus
  verified_nonce_sha256 (lowercase SHA256 hex of the exact signature-verified
  terminal nonce UTF-8 bytes, after equality with the Host challenge nonce).
  Raw nonce is input-only and is omitted from the Evidence Hash/JSON output.
  This is not a
  claim that the challenge remains issued after return or was atomically used.
- root_presentation_digest, checkout_jwt_digest, terminal_digest: lowercase
  SHA256 hex of exact captured originals; Root includes disclosure order and
  trailing `~`. No decoded/re-encoded substitute or token compact-only digest.
- verified_scope: strict_inputs, host_trust_profile_input_checks,
  issuer_root_signature, original_root_graph_closure, agent_key_confirmation,
  agent_terminal_signature, closed_original_checkout_binding,
  merchant_checkout_signature, fixed_subset_schema_constraints,
  host_challenge_order_binding, validity_intersection.

Buyer/account, order version, tenant, challenge issuer/state and clock identity
remain authenticated Host assertions under the documented Host precondition;
the library does not prove Issuer-signed Buyer identity, authenticate delivery,
read an actual clock or prove nonce uniqueness. Scope names are checks within
this supported profile, not a general Schema engine or real enrollment proof.

## Revision identity without fabricated execution evidence

The Stage10 DESIGN_ONLY sketch listed verifier_code_sha. This explicit research
contract uses a static implementation_revision instead: a semantic implementation
identifier maintained in reviewed source, not self-referential Git HEAD, a source
measurement or an attestation of loaded bytes. It does not claim a40-character
Git SHA that the running library cannot establish. Evidence has no
verifier_code_sha or runtime-integrity claim. Reproducibility links are outside
the Evidence: reviewed PR HEAD/tree, exact source hashes and separately saved
local test manifests. A change to versioned verification behavior requires a
reviewed revision change; a mutable local checkout is not proven by this label.
No new loader, runtime, file-hashing/attestation infrastructure is introduced.

## Host consumption and remaining gates

Required order stays verification -> research Evidence -> Host latest-state
recheck -> atomic nonce consumption plus order CAS. The Host must recheck current
trust/key state and periods, profile generation, tenant/Buyer/approved Agent,
order version/content, challenge unconsumed/unrevoked/one B and current time in
one atomic consumption transition. This code performs none of those persistent
operations or payments; unknown commit results require Host PENDING/reconciliation.

Existing707 regressions remain non-success on old APIs. New tests re-input the
contract-authored Host matrix through the unified path, check complete metadata
and exact intervals, deep mutation/alias boundaries, private constructors,
Evidence injection, JSON non-reconstruction and earlier/construction failures.
They share synthetic fixtures/provider assumptions and are not Stage15 independent
comparison or another-environment/resource attestation. Stage11 historical pins,
originals and reports are preserved. Stage15/16, Stage7 final acceptance, general
Schema/all constraints, the two acquisition measurement defects, real Host trust,
production/distribution/Phase2B remain separate HOLDs. No new dependency,
workflow, database, nonce consumption or deployment is introduced.


## Post-merge nonce privacy correction

PR162 discussion4344985837 identified that the initial v1 copied the whole
issued challenge, exposing its raw nonce through the public Evidence Hash.
This v2 uses an explicit allowlisted projection and a digest computed from the
verified terminal claim, retaining the original signature/Host nonce comparison.
It aligns with PHASE2A_MINIMAL_VERIFIER_DESIGN and the B1 immutable Host snapshot
contract's hashed-nonce output rule. Both contract and implementation revisions
advance to2 because the output shape changed; the raw-nonce v1 is not emitted
for compatibility. Host comparison uses its locally retained nonce digest;
no issuance/consumption is performed. A hash is not a secret or authorization.
Historical v1 results/source pins remain historical evidence and are not replaced.
