# Fixed-profile research prerelease candidate — 0.1.0.pre.3

The Owner accepted a fixed-profile research-only prerelease policy. GitHub pre2
is published; this pre3 documentation/package revision is unpublished and requires
separate distribution approval. RubyGems publication is not performed or confirmed. This
is not a stable release, full Phase2-A PASS, production or Phase2B/E10 GO. Evidence is not Host ALLOW, payment authorization or proof of consumption.

## Supported proposition and environment

The sole registered profile is `ap2.checkout.single_merchant_sku` version1,
with the exact `TrustContext::PROFILE_BODY`/hash. Official AP2 source is fixed at
b4587ac1d055888a73b4b21750973cffba961793; its subset-source reference027ed4734...
is historical profile provenance, not runtime code attestation. Root typ is
`example+sd-jwt`, terminal `kb+sd-jwt`, Merchant `JWT`, all ES256/P256.
Root Open1 -> Agent terminal inline Closed1, exactly3 supported array commitment
positions, one Merchant/SKU/cart line, ordered line_items/allowed_merchants
constraints, USD/EUR/JPY and empty links only. Other profiles/forms are rejected,
not accepted through a generic AP2/Schema fallback. This synthetic registered
profile does not establish real Issuer enrollment or general interoperability.

The supported baseline is MRI Ruby4.0.9 and JSON2.19.9/JWT3.3.0/base640.3.0/
OpenSSL gem4.0.2/Digest3.2.1, all fixed in the gemspec. These versions must be
available through normal RubyGems/Bundler resolution; source-loadpath bypass
or dependency replacement is not a compatibility contract. MBA409-20261023-BUILD02
used official --disable-dtrace and reused the existing task-local OpenSSL3.5.9
library. Loaded provider observations confirmed OpenSSL gem4.0.2/libcrypto3.5.9,
Digest3.2.1/resolv0.7.2/zlib3.2.3/Bundler4.0.20;885 source regressions passed
as MBA409-20261023-VALIDATION01. PACKAGE01 records the original validation snapshot's
package/install checks; PACKAGE02 is the later evidence-reference correction.
Linux4.0.9 was not yet observed at that packaging snapshot; the later pre2 run
39939021098 is identified below, separately from this pre3 candidate.
The candidate contains no OpenSSL/JSON native binary and performs no dependency
download/build itself. Missing fixed/native providers must stop an offline
validation rather than trigger extra download/build. Actual native paths/hashes
are environment observations, not proved by gem versions. Bundler4.0.20 is the
resolver baseline, not a runtime dependency. RubyGems' version requirement does
not itself enforce the MRI engine or OS. DTrace/USDT probes are disabled.

Verifier-source observations exist for MBA Darwin arm64 and Ubuntu24.04 x86_64
at base main8d9845ff4b5618b9e57eda86d3a1e447d4124b47. The old pre.2 artifact was subsequently built/installed on Linux in
run39869876461 (885 source checks,52 installed checks,13 payload/10 loaded).
Stage19 records MBA7inputs x3 observations. See the commit-pinned Stage21
supplement below. Those Ruby4.0.1 observations do not validate this Ruby4.0.9
candidate. The later pre2 Linux observation is separately identified below;
this pre3 package has no Linux observation.
Windows, Intel Mac, other Rubies/engines and all OS versions are unverified.
No additional Actions run is authorized.

## Full entry and required inputs

`AP2MandateVerifier.verify_research(trust_json:, selection_json:, host_json:,
root_presentation:, terminal_jws:, host_checkout_jws:, verified_at:)`

All byte inputs are exact Strings; no normalization/coercion. The first three
are strict JSON Strings from authenticated independent Host state, not a token
registration claim. Use the exact supported shapes implemented by
TrustContext and HostBinding; missing/null/extra/duplicate fields fail closed.
`verified_at` is an external integer Unix second, not the token's own clock.

- trust_json has snapshot{id,policy_version,content_hash,body} and
  profile{profile_ref,version,definition_hash,body}. Snapshot body has exactly
  id/policy_version/active/not_before/not_after/records. Each record contains
  role/identity/tenant_id/purpose/key_ref/profile_ref/profile_version/
  public_key_pem/key_fingerprint/algorithm/active/not_before/not_after.
  Body hashes are lowercase SHA256 hex of exact frozen body bytes, outside body.
- selection_json has trust_snapshot_id/policy_version/trust_content_hash/
  profile_ref/profile_version/profile_definition_hash/tenant_id plus
  Issuer,Agent,Merchant selectors, each exactly identity/purpose/key_ref.
- host_json has binding/challenge/expected_challenge_issuer_id/clock_source_id.
  Binding B contains tenant_id/buyer_account_id/order_id/merchant_id/audience/
  profile_ref/order_version/profile_version/approved_agent_key_fingerprint/
  root_presentation_digest/checkout_jwt_digest/currency/expected_total.
  Challenge contains challenge_id/nonce/issuer_id/B/trust_snapshot_id/
  policy_version/trust_content_hash/profile_definition_hash/not_before/not_after/state.
  Only state=issued is accepted, B must match current Host B in every field,
  references must match selected trust, and signed bytes/keys/amounts must bind.

Keys are canonical public SPKI PEM P256, fingerprinted with SHA256 of exact PEM.
Exactly one role/identity/tenant/purpose/key_ref/profile match is selected.
Unknown, ambiguous, inactive, expired, wrong-purpose or unknown profile is rejected.
Host is responsible for authenticating these inputs and supplying current state;
self-consistent hashes do not authenticate provenance or prevent rollback.

## Result and Evidence

Full supported conjunction -> frozen ResearchResult:
status=:verified_research, code=:scoped_research_verified, success?=true,
deeply immutable in-process ResearchEvidence. Failures -> non-success Result,
evidence=nil; invalid/unsupported inputs are rejected, missing dependencies or
unexpected internal failure are unavailable. Process failure may produce no
result and must never be interpreted as success. Ruby API keyword/arity misuse
can raise before some low-level wrappers execute; arbitrary caller misuse is
not guaranteed to be wrapped in a Result.

The old `verify(presentation_json:)` checks JSON syntax only; it still returns
unverified/verification_not_implemented for valid JSON. All older verification
entries retain success?=false/evidence=nil even when their limited stage passes:
verify_root_signature, verify_root_disclosures, verify_purchase_binding,
verify_scoped_constraints, verify_trusted_scoped_constraints, verify_host_binding.
They do not replace the full entry. Internal verified_*! handoffs are not a
supported caller-supplied checked-facts API. Result accepts no Evidence injection.

Evidence contract ap2.research-evidence.2 / implementation revision
ap2.research-verifier.2 identifies checked profile/version/hash, evaluation
clock/time, snapshot, selected keys/fingerprints/periods, complete checked B and
challenge projection, original Root/Checkout/terminal digests, scope and shortest
validity interval. Revision is a static semantic identifier, not Git HEAD/source
measurement/attestation. Raw nonce field is input-only; verified_nonce_sha256 is
computed from the exact signature-verified terminal nonce after Host equality.
This does not detect secret text repeated by a caller in another allowed field.

Evidence.to_h is a detached deep-frozen Hash; strings/arrays/nesting/result are
immutable. No JSON/remote/Marshal reconstruction or authenticity of a transported
Hash is provided. Trusted Ruby process/interpreter is a precondition; private
constructors do not sandbox malicious Ruby/reflection in that same process.

## Parsing, schema and time boundaries

Header/payload parse before signature enforces strict bounded syntax only.
JSON2.19.9 duplicate rejection remains on, including escaped duplicate keys;
BOM/comments/trailing commas/nonfinite numbers are rejected. JOSE is fixed alg/
typ with optional ignored kid1..128B, never a trust enrollment/key URL. JWK URLs,
jku/x5c/crit etc are unsupported. Canonical unpadded base64url is checked.
Root signature precedes full original commitment walk. All3 supported positions
and every supplied disclosure must be consumed exactly once; unknown/duplicate/
extra/unresolved and unsupported object_sd forms stop. Decoy origin is not inferred.
Root wire includes original disclosure order and trailing~. Signed sd_hash and
checkout_hash match original bytes; Host hex digests are not confused with them.

A hand-checked closed subset covers supported Open/Closed/Merchant/Checkout/
line-item/item/total required fields/types/const/positive quantities/price.
Only one line/allowed Merchant/SKU is accepted, quantities1..1000000, price and
amounts0..9007199254740991; multiplication must fit and equal Host total.
Exactly one subtotal/total each, consistent at line and Checkout level.
Schema-optional buyer/messages/website/image_url/parent_id/display_text and
Checkout expiry/continue URL are not supported; nonempty links are rejected.
No required field inside a claimed supported shape may be skipped by labelling
it unsupported. This is not a general Schema engine; static coverage and prior
fixed Schema examples do not prove all official formats.

Open/Closed iat/exp: integer0..4102444800, same values, exp>iat, TTL<=7200,
iat<=t<exp. Terminal iat in max(t-300,Open.iat)..t and <Open.exp, skew0.
All selected key/snapshot/challenge periods must contain t. valid_from=max(all
starts), valid_until=min(all exclusive ends including terminal.iat+301).
Age300 is allowed,301 refused. Sole profile has no extra period; Merchant
exp/nbf is not invented. clock_source_id is a Host assertion, not real-clock proof.

## Resource contract and Host execution

Raw Root/trust <=131072B each; terminal <=32768B; Checkout/selection <=16384B
each; host <=32768B. Six original Strings total at most360448B, NOT an RSS quota.
JSON depth24; compact Root <=32768B; decoded header/payload/signature <=2048/
24576/64B; disclosures<=16, encoded segment<=8192B. Root graph visits<=2048,
array<=16/object<=32, container depth24; this node/member budget is not a general
Host JSON limit. Snapshot/profile bodies<=65536/8192B, records1..16, PEM<=1024B.
IDs/versions/Host nonce mostly<=256B; title/name<=512B. Integer digit count has no
separate quota beyond byte caps. These are finite input limits, not time bounds.

There is no library wall-clock deadline, total memory quota, concurrency limiter
or actual-clock acquisition. CI10s probe/300s batches/15min job are harness limits.
Host must enforce its process/time/concurrency policy; no Thread Timeout/native
interrupt guarantee is asserted. Product CPU/RSS/parallel limits remain unproved.
No custom runtime/supervisor is supplied.

Host ordering: freeze Root/Checkout -> issue immutable challenge for current B/
trust/profile -> Agent signs terminal -> verify -> Evidence -> latest-state/time
recheck -> atomic nonce consumption + order CAS. Buyer/tenant/order version are
Host assertions, not Issuer-authenticated Buyer identity. Host must prevent nonce
rebinding/reuse, handle revocation/concurrency and reconcile unknown commits as
PENDING. Enrollment/rollback/DB/CAS/payment/Receipt/transport authority are outside
this Gem; missing Host guarantees mean no production ALLOW.

## Evidence preservation and release boundary

885 means existing regression cases,30 independent MBA contract cases,12 boundary
probes,8 MBA Schema judgments;42 Linux comparisons replay the30+12 same inputs.
Old O4's13cases64judgments are older evidence, not added/relabelled for this package.
Old manifests intentionally do not certify the changed gemspec/version. New
candidate artifact/source/runtime/test reports must be separate. Historical
O1/O3 total10MB, O4 sent-header-inclusive1MiB and Linux128MiB all-traffic compliance
remain unproved; successful logic tests do not repair them.

The package whitelist is lib/**/*.rb, README.md, LICENSE and this document.
No fixtures/research JSON/test code/private keys/vendor/cache/raw logs/native
extensions are included. Repository research data/harnesses are now under
research/; historical evidence bytes and logical pins were preserved.
Local candidate installation can reuse existing fixed dependency homes/default
OpenSSL: it proves installed candidate usability, not fresh offline installation
of all dependencies or future download availability. Stable/public release,
realIssuer/production/Phase2B/Stage16 GO require separate decisions.

## Current candidate versus historical evidence

This unpublished README/package revision uses candidate version0.1.0.pre.3 pending
an external same-version/ownership check; no claim of uploadability is made.
The historical MBA409 VALIDATION01/PACKAGE01/PACKAGE02 records below identify pre2,
not new pre3 execution. Product lib and dependency requirements remain unchanged.
The later pre2 Linux run39939021098 passed885/52 and13/10 at commit
f6d4f83d396b75505256dba5769a54a8f065eeea; it is not a pre3 Linux package run.
Any new pre3 package/install report is separate and does not replace those records.
JSON2.19.9 must override the vulnerable default JSON2.18.0 supplied in Ruby4.0.9.
Measured additional providers are resolv0.7.2 and zlib3.2.3; actual identities,
linked libcrypto, source/archive/installed hashes and test results belong to the
separate new local validation report. Installed version assertions are not
full native-library/runtime security attestation. Historical sources/results/pins
remain unchanged and are not relabelled as this runtime.

Historical validation/limitations supplement:
https://github.com/cuichangquan/ap2-mandate-verifier/blob/c8d81eab49e37a1236a355d42cf667aab552392d/docs/STAGE21_VALIDATION_SUPPLEMENT.md
E06 remains PARTIAL/OPEN; trusted-harness assumptions, genuine Host trust/clock/
revocation, worst-case resource/concurrency guarantees and communication-accounting
gaps remain unproved. Evidence is not Host ALLOW; no generic AP2 claim is made.

## Evidence identifiers for this runtime update

Current namespace: `MBA409-20261023`, separate from all MBA408 and historical
Ruby4.0.1 records below. The original completed VALIDATION01/PACKAGE01 pair
has these immutable identities (local retained files, not public downloads):

| Evidence | SHA256 / matching source |
| --- | --- |
| REPORT_MBA409_VALIDATION01.json | a329a990fca351380674639181ea487a7f2cc61f52af013f8b474727dd4bf8a4 |
| CANDIDATE_SOURCE_MANIFEST.json (417 files) | d5288db5c24827fc9a7b40e3c768f75afd7bda18177a124ef500f69b9037e6e6 |
| Matching original tested source commit | 7822fc2b11b6cb2df4c5b5495d747c0d730083bc |
| Matching original tested source tree | dd3e65e85502e47188bfc64b7fd974e97e8aba78 |
| Original PACKAGE01 Gem (32768B) | 13a5042fb0b16010ee16ede106ed4503874208da03fa09e6ba39ffc15b0137b6 |

The report binds provider identities, original input/expectation hashes and
package SHA/size to that complete manifest. The commit/tree was assigned after
local validation and all417 blobs matched; original local-only report text is
preserved. Product lib remains byte-identical to base main
d6778f54cb4f00bfbcbc99feadbb1b1ae1ea0c70. These immutable identities establish
the original observation, not automatic validation of subsequent edits.

- ACQUIRE01: official Ruby4.0.9 archive size/SHA matched; HTTP/2 sent-header
  count is unproved. Original STOP record is immutable; a separate continuation
  decision allowed reuse without redownload. Total HTTP/128MiB compliance is
  unproved, independently of product test results.
- BUILD01: capacity scan raced configure's temporary conftest.dSYM deletion;
  STOP with owned group reclaimed. No install success is attributed to it.
- BUILD02: one new build/install completed using the bounded, exact-transient
  du recheck; unrelated errors or repeated uncertainty still STOP.
- VALIDATION01: new Ruby4.0.9/provider observation and885 source regressions.
- PACKAGE01: original validation snapshot's package build/fresh offline install,
  source/archive/installed13 and ordinary loaded10/installed52 verification;
  only the completed matching local report establishes those results.

- PACKAGE02: this documentation-only identity correction is a distinct package;
  source/archive/installed13, loaded10 and installed52 are checked again once.
  Its final source commit/tree, report/manifest hashes and new artifact SHA/size
  are recorded together in the PR174 public evidence summary. The immutable
  VALIDATION01/PACKAGE01 pair above is not replaced;885 is not rerun.

Public non-secret extraction and later PACKAGE02 identity mapping:
https://github.com/cuichangquan/ap2-mandate-verifier/pull/174
No local path is a public download. Missing, failed or mismatched report/source
pairs are not success. Hashes identify bytes, not runtime/Host attestation.

### Historical Ruby4.0.8 records (unchanged observation identities)

The namespace `MBA408-20261023` identifies this Ruby4.0.8 work only. It must
not be resolved against `research/packaging_candidate/results/R1`, `R2` or `R3`,
which retain their original Ruby4.0.1/OpenSSL4.0.0 observations unchanged.

| Unique evidence ID | Observation and report binding |
| --- | --- |
| MBA408-20261023-BUILD01 | Ruby build stopped at DTrace access denial; preserved failure, not PASS. |
| MBA408-20261023-BUILD02 | Capacity monitor exception; original completion remains unknown. Later scoped process absence does not establish success. |
| MBA408-20261023-BUILD03 | Official disable-dtrace Ruby build/install completed in145.4s; OpenSSL gem4.0.2 linked libcrypto3.5.9. |
| MBA408-20261023-VALIDATION01 | Original885 source regressions and52 installed checks; original new-runtime package31232B, SHA2563252c9ce71f4ff91870d52004283b2b2fad09e38c71fa93447dfe232d2b7d716. |
| MBA408-20261023-PACKAGE02 | Documentation-only evidence-reference correction; its final source/tree SHA, new package SHA/size and repeated13-file/52-installed results are recorded together in the PR173 evidence summary. It is a separate artifact and does not rerun885 or replace VALIDATION01. |

VALIDATION01's retained local report (`REPORT_R3.json`, not a public download)
has SHA256a4923bb132e709568251b8bd15d574893ca88ea36d0274a03d0326436c27dc81.
Its complete source snapshot was subsequently recorded, byte-identically, as
commit96351b8d4a0ae5d9566599ccb92b6fa1da5d7986,
treecd72fe7b9353ffc0270a068e14c2bc34c5b64e2a. Product verifier sources are
unchanged from base49f4de5e88c6611dfe04b8e595acc7764247a359; historical
profile-source pins are provenance and do not identify this runtime run.
Public non-secret report summary and PACKAGE02 source/artifact identities:
https://github.com/cuichangquan/ap2-mandate-verifier/pull/173
The summary must explicitly identify the completed observation; a missing,
failed or mismatched report is not success. No local path is a public evidence
URL. Raw local environment logs are not published by this package.
