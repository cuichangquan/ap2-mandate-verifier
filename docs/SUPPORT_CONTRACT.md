# Fixed-profile AP2 verification — published 0.4.0 / historical releases

Unpublished **0.5.0 candidate** adds separate [Merchant signing and Checkout Receipt APIs](MERCHANT_SIGNING.md). They do not broaden the existing Verifier profile or change Result/Evidence/status/code. Checkout Receipt uses the dedicated Schema and normative final SD-JWT reference; unsupported forms fail closed. No product Mandate issuance, payment, persistence or real key/trust management is included.

Published 0.4.0 adds supplemental safe diagnostics; see [API and troubleshooting](DIAGNOSTICS.md). Existing verdict/Evidence contracts remain unchanged.

[0.4.0 on RubyGems](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.4.0) was registered 2026-10-31 04:25:06.427 UTC and compared at 04:26:15 UTC: owner `cuichangquan`, platform `ruby`, prerelease false, not yanked at comparison; 44,032 bytes, SHA256 `b212db01e7deb18dcef1199414f9d93ef43cb1f74b62baa55306de3955dfe177`. The download matches the saved reviewed artifact and all 17 payload files match source `fc42852f53c615f96d7c165a8de494b24b252519`. RubyGems does not independently attest the source SHA. Formal MRI support and all five runtime pins below are unchanged. [Publication record](PROJECT_STATUS.md#040-publication) and [validation scope](DIAGNOSTICS_VALIDATION.md). Packaged documentation retains its preparation snapshot; repository updates do not replace published bytes.


## Published 0.3.0 input assistance

`InputBuilder` is an additive, Rails-independent conversion layer for explicit authenticated Host business records, versioned challenge preparation/restoration, and independently obtained current state. `verify` enters the unchanged complete `verify_checkout` core; assembly/restore alone never returns Evidence. Existing seven inputs, fixed profile/AP2 source, Result/Evidence v2, MRI 3.4.12/4.0.9 and all five pinned runtime dependencies remain unchanged.

New business Hash/Array graphs are bounded before serialization and require plain built-ins with String keys; unknown fields, formats/profiles, conflicting keys and unsupported shapes fail closed. Persist the original returned challenge String and original signed wires. `restore_trust` validates and preserves exact stored trust/selection Strings. Rebuilding trust from business records creates a new snapshot whose exact bytes may differ; it must not repair old challenge references. Stored B/digests/references are never regenerated from current values. Host authentication, freshness/revocation, storage, issuance/atomic consumption and final authorization remain Host duties. See [input assistance](INPUT_BUILDER.md). Publication does not establish Host production authorization.

[0.3.0 is published on RubyGems](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.3.0): registered 2026-10-31 01:31:40.743 UTC; official metadata fetched at 01:32:40 UTC and final comparison completed at 01:33:27 UTC. Owner `cuichangquan`, platform `ruby`, non-prerelease, not yanked at verification. Metadata, distributed Gem and saved final candidate matched: **37,376 bytes**, SHA256 `b3a31d5a8b0718f1085745dd4d97d85f210ff9a1628798110da9ff382ae546bd`, source `877f59195632f74714a60551b6afb22ac81d93e3`. RubyGems does not independently attest a source commit; the source association is from the retained reviewed candidate, whose bytes match the download. [v0.3.0 tag/Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.3.0) points to that exact source and was published at 01:35:52 UTC.

On Debian 12/arm64, MRI 3.4.12 and 4.0.9 each passed the merged-source existing885 + checkout190 + metadata7 + builder109 suites. The same final Gem passed ordinary installation, 14 source/archive/installed payload matches, 11 normally loaded product files and 134 installed cases per Ruby. Five runtime pins remain JSON2.19.9/JWT3.3.0/base640.3.0/OpenSSL gem4.0.2/Digest3.2.1. Scope and withdrawn-candidate history are in the [publication record](PROJECT_STATUS.md#030公開済み--現在の配布状態); these observations do not validate real Issuers, actual Hosts, performance or production GO.

The earlier archive SHA256 `5de6907cfcf0565ddaba1385b1d38ae113cc5e26d52259d769030237378a48a8` is withdrawn and was not published. [PR219](https://github.com/cuichangquan/ap2-mandate-verifier/pull/219) fixed its unregistered failure Result codes, unavailable classification and selector shape checks. Published failure handling reuses existing registered Result codes and preserves dependency-unavailable typing. The published Gem's README/contract remain the preparation snapshot; this repository update does not rebuild, repush or replace those bytes. GitHub source archives are separate from the RubyGems Gem.

**Fixed-profile verification contract; Evidence is not Host ALLOW or payment permission.**
Distribution availability is determined by the official RubyGems version listing, not by this document. Specific Host production GO remains separate.
Owner adopted the existing verification API and bounded stable-release conditions below. Publication and a specific Host's production operation are separate decisions; this contract does not authorize either.
Published research-only pre3 remains unchanged. Its historical observations below do not certify this new archive.

## Published 0.2.1 compatibility and artifact

[0.2.1 is published on RubyGems](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.2.1). Formal runtime support is exactly MRI 3.4.12 and MRI 4.0.9, with JSON 2.19.9, JWT 3.3.0, base64 0.3.0, OpenSSL gem 4.0.2 and Digest 3.2.1 unchanged. Bundler 4.0.20 is the resolver validation baseline, not a runtime dependency. The installation requirement `>= 3.4.12, < 4.1` is a resolution interval, not certification of other Ruby versions or engines.

Both versions passed source885 + additional checkout190 + metadata7 on Debian 12/arm64 with official Ruby bookworm images. The same final artifact passed ordinary installation, 13 payload-file comparisons, 10 normally loaded product Ruby files and 118 installed cases per Ruby. Actual OS/native-provider identities and evidence are in the [compatibility record](RUBY_3_4_12_COMPATIBILITY.md). These measurements cover their exact recorded configurations; historical macOS/Ubuntu evidence below does not validate 0.2.1 there.

Published 2026-10-30 11:51:55.894 UTC; verified 11:53:55 UTC: owner `cuichangquan`, platform `ruby`, non-prerelease, not yanked at verification. Official metadata, distributed Gem and retained artifact matched: **34,816 bytes**, SHA256 `a4ab7e0f6c9bd87355695369374f8e6e2dad104fb673700e9f616053afe6e114`, source `5a02bc3a192e16aa3628cf7899617623b0aed78c`. The [v0.2.1 GitHub Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.2.1) tag points to that exact source.

Seven inputs, fixed profile, Fail Closed, Result/Evidence v2 and `verify_checkout` / `verify_research` / legacy `verify` meanings remain unchanged; product `lib/` is unchanged. Packaged README/contract retain the preparation snapshot. Repository publication updates do not rebuild or replace those bytes. GitHub source archives differ from the RubyGems Gem. Publication does not establish real Issuer trust, Host production GO or Phase 2-B; existing HOLDs remain.

## Published 0.2.0 API

[0.2.0 is published on RubyGems](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.2.0). The published artifact and final packaging observation are identified below; 0.1.0 and earlier candidate evidence retain their historical identities.

`verify_checkout(**inputs)` delegates directly to `ResearchResult.verify(**inputs)` without input transformation. It requires the same seven inputs listed below (six original Strings and externally supplied integer Unix seconds), fixed profile, bounds and trusted Host preconditions. `verify_research` is retained unchanged without deprecation warnings; `verify(presentation_json:)` remains syntax-only and never produces successful Evidence.

Both full entries preserve Result/ResearchResult, status/code and immutable Evidence v2. Missing or unknown keywords return `:unavailable` / `:research_verification_unavailable`, `success? == false`, `evidence == nil`. Positional arguments or invalid keyword expansion can raise before entry; exceptions and missing results never authorize an operation. Success remains `:verified_research` / `:scoped_research_verified`, checked facts rather than Host ALLOW. No profile, trust, revocation, Host or payment responsibility is broadened.

## Limited prior 0.2.0 candidate observation

[PR #213](https://github.com/cuichangquan/ap2-mandate-verifier/pull/213) records a separately approved build/install/audit at source HEAD `771eebb1094c19931aadafd32feaa70e2caa48f6` (same tree as merged main `9b981be68a1abaf318a7ae78497b3d74d8aefdda`). The retained local candidate was 32,256 bytes, SHA256 `0a126e170e482fea5138865d658f4c21687dc238e595236456f687ceb8aab211`; it is not a published download or this document's new artifact.

The limited Debian 12/arm64 observation used MRI 4.0.9 and the fixed Gem dependencies, OpenSSL library 3.0.22 / OS package `libssl3:arm64 3.0.22-1~deb12u2`. All 13 payload files matched source/archive/installed bytes, ordinary RubyGems require loaded 10 product Ruby files, and 118 logical cases passed: research42 + checkout42 + unavailable24 + legacy7 + input rejection2 + constructor rejection1. Saved inputs/independent expected values were reused; source190/885 were not rerun in this attempt. Earlier auxiliary-diagnostic STOP records remain preserved in PR #213.

This is an additional bounded observation, not adoption of Debian as a supported platform or proof of general runtime security, symbol binding, whole-wire accounting or resource performance. The 0.1.0 baseline and historical evidence below retain their own artifact identities. README.md and this contract are packaged; editing them creates different candidate bytes. The preparation-time NOT_RUN statement applied before the separately approved final observation below; prior candidate results were not reused as validation of the final bytes. Real Issuer trust/revocation, actual Host operation, performance and production GO remain HOLD.

## Published 0.2.0 artifact and final observation

Published 2026-10-30 06:43:10 UTC, verified 06:44:48 UTC: owner `cuichangquan`, version `0.2.0`, platform `ruby`, non-prerelease. Official RubyGems SHA, distributed Gem and retained Gem matched: **33,280 bytes**, SHA256 `9a52e802de5a0564c34d198f4c4ad2c2b60791a8f1eb6e31db14c49e28e91f16`. Source `9b2e28d91fc4886722de7b9c39a5422e966953a9`, tree `a7739f966416bdbc18cfee266efc93223a587407`.

This final candidate separately passed the limited Debian 12/arm64 / MRI 4.0.9 observation: all 13 payload files matched source/archive/installation, 10 product Ruby files loaded through ordinary require, and 118 installed cases passed (42 research +42 checkout +24 unavailable +7 legacy +2 invalid inputs +1 constructor). Fixed dependencies and saved inputs/expected values were reused; source190/885 were NOT_RUN in this packaging step. Final report SHA256 `4348837cc153c65633e36c83c7939540819f164f43588d8140656e5ab50c2ccd`; publication receipt SHA256 `4b8264c5b990b10ad76a3fa3f01fc4ca94e6a828664ab3cefe11e6792c94a139`. These identify retained local records, not public downloads.

Publication does not expand supported-platform guarantees or establish real Issuer trust, revocation, actual Host operation, performance, production GO or Phase 2-B. The published Gem's documents are the pre-publication snapshot. Repository-only follow-up edits do not alter its bytes and require no rebuild; rebuilt artifacts do not inherit its validation. GitHub source archives differ from the RubyGems Gem. See [0.2.0 publication record](PROJECT_STATUS.md#020公開済み--現在の配布状態).

## Verification contract

Preserve `verify_research`, its seven keyword inputs, existing status/code and Evidence v2 identifiers, and legacy APIs' non-success behavior. No API rename, new trust enrollment, remote lookup, DB or payment operation is added. Fixed AP2 commit b4587ac1d055888a73b4b21750973cffba961793 and the exact profile v1 body/hash, seven supported shapes, ES256/P256 and existing bounds remain unchanged.
Gem-owned signature/original-wire/closure, delegation, binding, supplied-trust selection, constraints, time intersection and fail-closed checks remain Gem responsibilities. Unsupported forms are rejected; do not claim generic AP2/full Schema conformance or real-Issuer interoperability.

Host inputs must be authenticated, independent of the token and current: trust/keys/profile/revocation/rollback protection, clock and order/challenge state. Recheck before use; atomically consume nonce with order CAS, reconcile unknown results as PENDING, and decide final ALLOW/payment separately.
Evidence is immutable checked facts in the same trusted Ruby process, not ALLOW or a transport credential. JSON/Hash reconstruction does not authenticate it. Rejection, unavailability, exceptions and no result never authorize an operation. Trusted Ruby is a precondition, not a malicious-Ruby sandbox.

No worst-case CPU/RSS/concurrency or numeric SLA is promised. Host process/time/memory/concurrency limits supplement, not replace, Gem finite input bounds. Issuance, presentation generation, Receipt, Rails adapter, real payments and Host DB operations are outside this verifier.
Supported-input semantics and existing API/status/code/Evidence contracts must not change silently. Security-driven acceptance narrowing requires impact/reason/migration disclosure; breaking required-field/profile/API changes must be explicit. Dependency updates are not automatically compatible.

The published 0.2.0 and historical baseline below is MRI4.0.9 plus JSON2.19.9/JWT3.3.0/base640.3.0/OpenSSL gem4.0.2/Digest3.2.1, with the exact observed MBA arm64-darwin25 and Ubuntu24.04/x86_64 configurations. RubyGems version constraints do not enforce MRI/OS/provider identity. All OS versions, other engines/architectures and arbitrary provider updates are not supported by past observations.
Historical D3 observed MBA component identities and four selected crypto symbol sources; OS dyld hashes/all symbol bindings/global runtime security remain unproved. JSON2.19.9 official IO-buffer fix/tag/source identity is adopted static evidence; inconsistent GHSA patched-version metadata remains recorded. Neither observation is global S3 PASS. The earlier R1 archive subsequently passed Mac/Ubuntu packaging checks. It is a different archive; see the separate release-package record for current bytes and observations.

Initial maintenance contact: Owner cuichangquan via repository Issues for ordinary bugs and private vulnerability reporting for vulnerabilities. No secrets, real Mandates or personal data in reports. Maintain only the latest patch in the selected initial stable series; no prerelease/old-series backport, fixed support years, response/fix/disclosure deadline or 24/7 promise.
Manual dependency/provider review is adopted monthly, on relevant advisories and before releases; no active automatic monitor is implied. Updates/deprecation/end of support must identify affected versions, reason and migration path without inventing a fixed notice period. Known major unaddressed issues or inability to maintain mean HOLD, not a blanket disclaimer.

## Existing API/limits and historical evidence baseline

The API/limit specification below preserves the existing contract. All pre2/pre3/MBA409/R1 observations are historical, not proof of a newly built archive. Historical release source/archive/installed identities and observations are recorded in [release-package evidence](../research/stable010_release_linux_package/README.md); 0.2.1 has its separate compatibility record above. No old result is relabelled.

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

The historical baseline described in this section is MRI Ruby4.0.9 and JSON2.19.9/JWT3.3.0/base640.3.0/
OpenSSL gem4.0.2/Digest3.2.1, all fixed in the gemspec. These versions must be
available through normal RubyGems/Bundler resolution; source-loadpath bypass
or dependency replacement is not a compatibility contract. MBA409-20261023-BUILD02
used official --disable-dtrace and reused the existing task-local OpenSSL3.5.9
library. Loaded provider observations confirmed OpenSSL gem4.0.2/libcrypto3.5.9,
Digest3.2.1/resolv0.7.2/zlib3.2.3/Bundler4.0.20;885 source regressions passed
as MBA409-20261023-VALIDATION01. PACKAGE01 records the original validation snapshot's
package/install checks; PACKAGE02 is the later evidence-reference correction.
Linux4.0.9 was not yet observed at that packaging snapshot; the later pre2 run
39939021098 is identified below as historical pre2 evidence.
The Gem contains no OpenSSL/JSON native binary and performs no dependency
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
the old pre3 NOT_RUN wording was subsequently superseded by run40038620413. Neither earlier archive supplies new-archive evidence.
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
of all dependencies or future download availability. Stable release or further
public distribution, realIssuer/production/Phase2B/Stage16 GO require separate decisions.

## Published pre3 versus historical evidence

The published version is0.1.0.pre.3 under RubyGems owner cuichangquan.
The Owner's completed publication check matched the official API, distributed
archive and MBA original:37888B, SHA256
8ad627818dc69b450d0fba970dafaf368ec42dd64fb51eec631731027de3882c.
MBA409-PRE3PACKAGE02-20261023 observed13 payload/10 loaded/52 installed checks.
The post-release Mac mini audit could not independently refetch RubyGems;
that audit is not a second publication or package-validation observation.
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

