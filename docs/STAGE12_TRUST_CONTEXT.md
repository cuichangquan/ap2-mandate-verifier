# Stage12 — authenticated Host trust input (limited research)

Security proposition: an authenticated Host selects one current, immutable
snapshot and this supported profile, then exactly one active, time-valid public
key record per Issuer/Agent/Merchant role. Only those keys reach the existing
signature, disclosure, purchase and limited-constraint checks. Normal results
remain `unverified / success? == false / evidence == nil`.

## Additive API and provenance boundary

`AP2MandateVerifier.verify_trusted_scoped_constraints(trust_json:, selection_json:, **inputs)`
accepts original UTF-8 JSON strings for the two Host inputs. `inputs` contains
exactly the existing scoped-check fields except the three PEM keywords:
root_presentation, terminal_jws, host_checkout_jws, expected_aud, expected_nonce,
verified_at, expected_checkout_id, expected_merchant_id, expected_currency,
expected_total_minor. Strings are detached before trust processing. No caller
PEM override is accepted. The older APIs keep their caller-selected-PEM contract;
they do not gain snapshot lifecycle validation implicitly.

Both JSON inputs must originate from authenticated, independent Host state.
Token claims, URLs, kid/JWK headers or presenter-supplied JSON cannot register
trust. Hash consistency does not authenticate the Host or establish currentness.
The library performs no enrollment, network lookup, credential access or I/O.
Issuer and Agent identity are Host assertions, not newly authenticated token
identity claims. Merchant selector identity also equals expected_merchant_id;
the existing signed Checkout check binds that ID to the selected Merchant key.

## Closed input shapes

`trust_json` has exactly `snapshot` and `profile` objects.

- snapshot envelope: id, policy_version, content_hash, body.
- snapshot body JSON string: id, policy_version, active, not_before, not_after,
  records (1..16 records).
- each record: role (`Issuer`, `Agent`, `Merchant`), identity, tenant_id, purpose,
  key_ref, profile_ref, profile_version, public_key_pem, key_fingerprint,
  algorithm (`ES256`), active, not_before, not_after.
- profile envelope: profile_ref, version, definition_hash, body.

`selection_json` has exactly trust_snapshot_id, policy_version,
trust_content_hash, profile_ref, profile_version, profile_definition_hash,
tenant_id and the three role-named objects (`Issuer`, `Agent`, `Merchant`).
Each role selector has exactly identity, purpose, key_ref. These are the Host's
current expected references, compared with the supplied immutable snapshot.
Rotation uses a new immutable key_ref and current snapshot references. Revocation
is active=false; an expired or inactive match never falls back to another key.
Two matching records are ambiguous even if one is inactive. No persistent
rollback detector is claimed: the Host must supply authenticated latest values
and recheck them before any future consumption.

IDs and versions are nonempty strings of at most256 UTF-8 bytes, without
coercion or normalization. Times are integer Unix seconds 0..4102444800;
not_before < not_after and not_before <= verified_at < not_after. Snapshot and
selected keys must be active. Every record has valid shape, canonical public
SPKI PEM, EC P-256, fingerprint and supported profile/algorithm, even if unused.
Only selected records must be currently active/in their window; retired records
with different immutable references may remain in the snapshot.

content_hash and definition_hash are lowercase SHA256 hex of the exact body
string bytes only. Body id/version must match envelope metadata. The hashes
are outside the body; there is no JSON canonicalization. key_fingerprint is
SHA256 of exact ASCII public PEM bytes; private keys, noncanonical PEM, RSA,
other curves and URLs are unsupported. Uniqueness matches role, identity,
tenant, purpose, key_ref and the fixed profile/version. There is no token-driven
key selection or permissive fallback.

## One fixed profile

The supported registered body is the exact frozen UTF-8 string
`AP2MandateVerifier::TrustContext::PROFILE_BODY`; ref is
`ap2.checkout.single_merchant_sku`, version `1`, definition_hash is
`TrustContext::PROFILE_HASH`. It names fixed AP2 commit
b4587ac1d055888a73b4b21750973cffba961793 and the existing limited subset source
027ed4734af47c8289dbcb837373bb6086463ec4, three SD positions, token types,
ES256/P256 key format and the two ordered constraint types. Disclosure positions
use the Root walker's commitment-path notation: the synthetic `disclosed` edge
is inserted after resolving the outer commitment before walking its nested
commitments. It is not a signed claim named `disclosed`, and these are not
post-resolution output paths. Both nested paths therefore include
`delegate_payload[0].disclosed.constraints...`; a regression compares the
registered set with RootDisclosures::PATHS and rejects a consistently rehashed
profile that omits the synthetic edge. Unknown definitions,
versions, additional fields or alternate whitespace bytes are rejected, even
when their self-reported hash is consistent. This is a registered exact subset,
not general Schema/profile support or a configurable claims interpreter.

Existing JSON duplicate-key/depth/encoding checks apply to envelopes and body
strings. Overall trust JSON <=131072 bytes, selection <=16384, snapshot body
<=65536, profile body <=8192; records <=16 and PEM <=1024. Product CPU/total
memory/concurrency guarantees remain unproven.

## Evidence and historical comparisons

The Stage10 logical contract supplied by the Owner has final document SHA256
3d09aef11bdadf92bf8db418ac921658dd3cfb261b5e04fe751173f7a180a63b.
This implementation covers only trust/profile/key input management. Stage13
challenge/order assertions, Stage14 Evidence, nonce atomic consumption/CAS,
real trust provenance and operational rollback prevention remain unimplemented.
The two historical acquisition measurement defects remain unresolved. Research
only; Stage7 final acceptance, production, release and Phase2B remain HOLD.

Stage11 source pins and retained reports are historical evidence and remain
unchanged. Its observer deliberately rejects a changed production inventory.
Historical comparison runs use the unchanged Stage11 tree. New regression and
trust tests run the Stage12 candidate; they are separate evidence, not a rewrite
of earlier comparisons or an independent O1–O5 proof of this new API.

Run the existing six regression files plus test/trust_context_test.rb with
approved Ruby4.0.1 and existing JSON2.18.0/JWT3.3.0, activating those exact gems
as documented in STAGE11_COMPARISON.md. No install or export is required.
The trust tests reuse retained public signed FULL input, construct Host policy
fixtures, and assert independent contract expectations for malformed, revoked,
expired, ambiguous, wrong-purpose/profile and mutation cases. They generate no
private key and never overwrite retained fixtures or reports.
