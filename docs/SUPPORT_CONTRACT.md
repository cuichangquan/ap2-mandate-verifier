# Unpublished fixed-profile Gem candidate — 0.1.0.pre.2

This is a prerelease candidate, not a stable release or permission to publish/use
in production. Production, RubyGems distribution, Phase2B and Stage16 GO remain
HOLD. Evidence is not Host ALLOW, payment authorization or proof of consumption.

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

The supported baseline is MRI Ruby4.0.1 and JSON2.19.9/JWT3.3.0/base640.3.0/
OpenSSL gem4.0.0/Digest3.2.1, all fixed in the gemspec. These versions must be available
through normal RubyGems/Bundler resolution; source-loadpath bypass or dependency
replacement is not a compatibility contract. MRI4.0.1 supplied OpenSSL4.0.0 as a
default gem in the tested environments, using its existing native binding.
Digest3.2.1 is also a required default gem, used for SHA256 trust/wire identities;
its existing native provider is reused and recorded, never silently substituted.
The candidate contains no OpenSSL/JSON native binary and performs no dependency
download/build itself. If the fixed OpenSSL/default/native provider is missing,
a local offline validation must stop rather than download or rebuild it.
The actual libcrypto and native file hashes are environment observations, not
proved by the gem version. Bundler4.0.3 is a tested resolver, not a runtime gem.
RubyGems' version requirement does not itself enforce the MRI engine or OS.

Verifier-source observations exist for MBA Darwin arm64 and Ubuntu24.04 x86_64
at base main8d9845ff4b5618b9e57eda86d3a1e447d4124b47. The new candidate's local
packaging/install checks are separate; it is not a new Linux packaged-Gem run.
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
extensions are included. Repository research JSON relocation is deferred.
Local candidate installation can reuse existing fixed dependency homes/default
OpenSSL: it proves installed candidate usability, not fresh offline installation
of all dependencies or future download availability. Stable/public release,
realIssuer/production/Phase2B/Stage16 GO require separate decisions.
