# Stage18 Linux actual-package preparation — NOT_RUN

Prepared against main015b0a867690a89229fe5718f48127d92eabf8ae and unpublished
ap2_mandate_verifier0.1.0.pre.2. This change authorizes no execution or merge.
Current Owner scope is source/workflow preparation, static review and draft PR /
latest-HEAD Codex review only. Actions dispatch, downloads, installation, native
build, merge, Tag/Release/RubyGems distribution and production remain unapproved.

## One future proof proposition

On standard Ubuntu24.04 x64 / MRI4.0.1, build the real candidate Gem, install it
into a new GEM_HOME with pre-provisioned exact dependencies, and load it through
ordinary RubyGems require from an empty directory outside checkout. Audit all13
allowed package/source/installed files and all ten loaded verifier library
identities. Separately check885 source regressions and52 installed checks:
42 saved independent MBA expectations,7 legacy APIs,2 JSON rejections and1
constructor rejection. Source regressions use source requires; they are not
reported as885 installed-Gem checks.

MANIFEST fixes source/test/input SHA256 and copies captured bytes into a private
temporary tree. It includes unchanged product package13 files, metadata, nine
existing regression tests, their saved public fixture, existing42 input/expected
files, reviewed package-audit helper and the two new helpers. It does not mutate
the checkout or reuse/relax old Stage11/15 Darwin/runtime manifests. The installed
test is a copy of reviewed test/packaged_gem_test.rb, changing only Linux platform
identity and result scope. Original test and historical results remain unchanged.
No Python Oracle execution, expectation regeneration, new Schema or generic AP2
research is involved. The eight Schema judgments remain prior MBA evidence.

This assumes trusted GitHub checkout/workflow, the harness, temporary tree and
MRI/default libraries. File capture detects ordinary changes, not malicious
same-user/runtime replacement; hashes are identities, not runtime attestation.
The product and Host trust boundaries are unchanged. Evidence is not Host ALLOW.

## Proposed execution approval, NOT granted by this PR

- One manual workflow_dispatch, attempt1, exact reviewed-and-merged main SHA.
  Branch/head/ref must match the input; PR/other-ref execution is rejected.
  contents:read only, no secrets, checkout credentials not persisted, no LFS or
  submodules, no cache/artifact upload, no binary publishing. No automatic event.
- Standard public-repository ubuntu-24.04 x64 runner, additional cost0yen only;
  verify the then-current free-runner conditions before dispatch. No larger or
  self-hosted runner. Previous Stage15 one-run allowance is already consumed;
  this requires a new explicit run allowance, not a rerun of that old run.
  GitHub's current standard/public-runner policy is documented at
  https://docs.github.com/actions/github-hosted-runners ; this repo was read as
  public during preparation. This does not approve or initiate a run.
- Existing reviewed checkout SHA11d5960a326750d5838078e36cf38b85af677262 and
  ruby/setup-ruby SHAe1bd6146574da5e0795075b5319b300edb30c5b0 are reused.
  Ruby binary/Action/setup/runner management traffic sizes are unknown here.
  Prior estimate about80MiB and128MiB planning budget are NOT a measured whole-
  traffic total, HTTP-inclusive hard cap, or proof of earlier budget compliance.
- Ruby4.0.1, existing default OpenSSL4.0.0 and Digest3.2.1 and available
  Bundler4.0.3 are required before archive download; absence/version mismatch
  stops. Do not acquire/rebuild these providers or add dependencies to proceed.
- Exactly three official RubyGems archives below, HTTPS direct/no redirect
  following/no retries/no index/dependency resolution. Verify exact body size
  andSHA256 before install. curl reports each body/request-header/response-header
  count. DNS/TLS/checkout/setup/control-plane traffic is outside those counts;
  unknown stays unknown. No new downloader or runtime infrastructure.

| Official URL | Body bytes | SHA256 |
|---|---:|---|
| https://rubygems.org/gems/json-2.19.9.gem |107008|9b9025b7cdddafa38d316eca0b2358488e42d417045c1b90d216a9fefe46b79a|
| https://rubygems.org/gems/jwt-3.3.0.gem |57856|44cc34fbc341c148233cf66641522b4bce0dfb1ce55e8073f05c56f44f4ee546|
| https://rubygems.org/gems/base64-0.3.0.gem |11776|27337aeabad6ffae05c265c450490628ef3ebd4b67be58257393227588f5a97b|

Total archive bodies176640B. These sizes/hashes are reused from reviewed prior
acquisition records; no archive has been downloaded for this preparation.
Install them with --local --ignore-dependencies --no-document into runner-local
dependency GEM_HOME. Exactly one JSON C-extension build, at most180s, no retry;
JWT/base64 are pure Ruby. No native extensions in the candidate's own.gem.
The fresh candidate GEM_HOME reuses those exact providers read-only. This is
candidate installability with fixed prepared dependencies, not a proof that
arbitrary machines can freshly resolve every dependency offline.

Job maximum15min; Ruby setup3min; dependency step5min (JSON native build180s);
validation step11min with outer630s process-group deadline. Inside it package
build/install each60s, package audit30s, source885300s and installed52batch300s.
These are ceilings, not additive promised durations; the job/outer deadline wins.
Output stdout/stderr caps are131072/16384B per child; timeout/exit/output/identity
failure stops with no retry. Batch limits do not prove product per-input latency,
CPU/RSS/concurrency budgets or native-interrupt guarantees. No new stress tests.

## New evidence and stop conditions

Successful future output is STAGE18_LINUX_ACTUAL_PACKAGE_NOT_HOST_ALLOW JSON in
public log/Job Summary: exact dispatch SHA, manifest/helper/input/expected hashes,
actual package SHA/size and13 payload hashes,885 source count, installed52 results,
versions/default flags/libcrypto and ordinary loaded-entry identity. The archive
is temporary and never uploaded. Do not require the MBA archive SHA: timestamp/
RubyGems container metadata may differ; payload/spec identity must match exactly.
Save future log/summary with run/attempt/SHA/provenance separately; no previous
record is replaced. Currently there is no Stage18 run or result.

Stop on missing provider/unknown dependency, hash/size/identity mismatch, source
or installed-check failure, unexpected acquisition/volume/cost, CI, timeout, or
request to broaden support. Failure gets read-only diagnosis; no automatic run2.
No automatic merge or dispatch belongs to this preparation approval.
Production/distribution/Phase2B/Stage16GO/Host atomic nonce+order/payment remain
HOLD. Historical O1/O3 total10MB and O4 sent-header-inclusive1MiB accounting gaps,
and Stage15 Linux128MiB whole-traffic gap, remain unresolved and are not repaired
by a future passing package test. Root research JSON relocation remains deferred.
