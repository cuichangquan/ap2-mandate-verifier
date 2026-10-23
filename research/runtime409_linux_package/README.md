# LINUX409 preparation — NOT_RUN / execution B not approved

Base main3fbd550141cc4292fa96e3e97a0a2186f7cc9970. Preparation A covers these
five new files, static review, PR/Codex review and conditional merge only.
No download, install, build, test or Actions is performed by preparation.

## One bounded future proposition

On standard public Ubuntu24.04 x64, install the verified official Ruby4.0.9
prebuilt provider, build the unchanged candidate0.1.0.pre.2, fresh offline-install
it and ordinary-require outside checkout. Compare all13 payload bytes and package
metadata against MBA409-PACKAGE02 (33280B, SHA256
e910659bbebda7aa5f00d63fb579f3b56819d59b5ee7d8b1734a6331f01d8de4).
Linux archive SHA/size is a distinct observation: archive timestamps may differ.
Source885 and installed52 are separated:52 = retained42 MBA independent expected
cases +7 legacy APIs +2 JSON rejections +1 constructor rejection. No Oracle
regeneration or Linux Python/Schema comparison. Eight Schema judgments remain MBA
history. Legacy false/nil and opt-in Evidence-not-Host-ALLOW boundaries remain.

Old Stage18/Stage11/Stage15 code, inputs, pins and results are unchanged. Current
manifest fixes captured source/test/input/helper SHA256 and separately includes
MBA payload/spec identities; workflow pins the current manifest SHA. Result ID
LINUX409-PACKAGE01 is new evidence, never a relabelled old Linux result.

## Future execution B — separate explicit approval required

- One workflow_dispatch, exact reviewed/merged main SHA, attempt1. No PR/push/
  schedule trigger. contents:read; no secrets, cache/artifact upload, binary/tag/
  Release/RubyGems publication, LFS/submodule or credential persistence.
- Standard public ubuntu-24.04 x64 only, verify then-current additional cost0yen.
  No larger/self-hosted runner or paid storage. New allowance is required; old
  run allowances are consumed and cannot be reused.
- Official prebuilt provider, no Ruby/OpenSSL source compilation or system package
  installation: https://github.com/ruby/ruby-builder/releases/download/ruby-4.0.9/ruby-4.0.9-ubuntu-24.04-x64.tar.gz
  49100121B, SHA256046d1422e1be5575eadd55323c85c3efbeaee8c8e1c1bfccee343e28619cb3b3.
  Standard curl/tar only; one request chain, normal HTTPS GitHub asset redirects,
  no retries; hash/size before extraction. Official builder layout is x64/ at
  /opt/hostedtoolcache/Ruby/4.0.9. An existing prefix or different toolcache path
  stops; never overwrite/repair an unknown runtime. This replaces setup-ruby's
  implicit/cached download so the exact archive digest is actually checked.
- Before dependency Gem acquisition, run the hash-pinned helper's provider-only
  mode (<=45s). It needs no JSON Gem/parser or new dependency. Require MRI4.0.9,
  loaded default OpenSSL gem4.0.2/Digest3.2.1, Bundler4.0.20,
  resolv0.7.2/zlib3.2.3 and Ubuntu ID=ubuntu/VERSION_ID=24.04/codename=noble.
- The actual Ruby process's /proc/self/maps must contain exactly one mapped
  openssl.so and one each libssl.so.3/libcrypto.so.3. Reject deleted/ambiguous/
  missing mappings. Record canonical paths and SHA256 using bounded regular-file
  reads with metadata checks. The extension must be under the verified official
  Ruby provider prefix; it is not a dpkg file and must not be represented as one.
- Both actual mapped shared libraries must be owned by libssl3t64:amd64 with
  exact installed/source version3.0.13-0ubuntu3.16, source packageopenssl,
  architectureamd64 and statusinstalled. Require dpkg --verify output empty and
  match each actual library's MD5 against that package's installed md5sums file;
  record SHA256 as its independent byte identity. Unknown owner/version/source/
  architecture, missing checksum, mismatch, stderr or command failure => STOP,
  never acquire/upgrade/rebuild a provider to force success. Compile/runtime
  upstream strings must both be3.0.13, but that string alone grants nothing.
- Ubuntu USN-8847-1 (2026-09-29) identifies noble libssl3t64
  3.0.13-0ubuntu3.16 as the fixed package:
  https://ubuntu.com/security/notices/USN-8847-1
  Earlier USN-8678-1 identifies3.0.13-0ubuntu3.15, demonstrating backported fixes
  retain upstream3.0.13. The current exact policy does not automatically accept
  later/unknown revisions. A changed revision needs read-only assessment/review.
  The old runner image's libssl-dev listing is supporting context only and is
  never substituted for actual mapped-library/dpkg evidence.
- These checks trust the official runner/Ruby archive and installed dpkg database.
  MD5 is used for dpkg consistency, not publisher authentication or cryptographic
  provenance; SHA256 records observed bytes, not independent package signatures.
  Malicious root/same-user/runtime attestation is outside the scoped proposition.
- Only three official Gem archives, direct HTTPS/no redirects/no retries/no index:

| URL | bytes | SHA256 |
| --- | ---: | --- |
| https://rubygems.org/gems/json-2.19.9.gem |107008|9b9025b7cdddafa38d316eca0b2358488e42d417045c1b90d216a9fefe46b79a|
| https://rubygems.org/gems/jwt-3.3.0.gem |57856|44cc34fbc341c148233cf66641522b4bce0dfb1ce55e8073f05c56f44f4ee546|
| https://rubygems.org/gems/base64-0.3.0.gem |11776|27337aeabad6ffae05c265c450490628ef3ebd4b67be58257393227588f5a97b|

  Gem bodies176640B; with Ruby provider49276761B (about47MiB). Verify each hash/
  size and install --local --ignore-dependencies, no automatic dependency fetch.
  JSON2.19.9 C build once<=180s overrides default2.18.0; JWT/base64 pure Ruby.
  No additional dependency/native build. Candidate package contains no native code.
- Job<=15min; provider<=3min, dependencies<=5min, JSON<=180s, package build/install
  <=60s each, audit<=30s, source885<=300s, installed52<=300s, whole harness<=630s.
  Job/outer deadline wins; ceilings are not additive promises. Child stdout/
  stderr caps131072/16384B. No stress/CPU/RSS/concurrency guarantees are added.

## Communication, evidence and residual assumptions

curl prints body/request-header/response-header metrics; raw headers stay only in
runner temporary storage and may contain signed redirect URLs, never artifacts.
Redirect-hop request accounting, checkout, runner/control traffic, DNS/TLS and
all-network totals remain unknown. 128MiB is a planning budget, not an enforced
or measured whole-traffic guarantee. HTTP1.1 avoids repeating the known HTTP2
size_request=0 observation, but does not retrospectively prove prior accounting.
Unexpectedly large acquisition, unknown dependencies/cost, hash/version mismatch,
failed test/timeout/unresolved native linkage => STOP, read-only diagnosis only,
no automatic second run. No substitutions/downloads to force a pass.

Successful future log/Job Summary records run attempt/SHA, provider archive,
manifest/helper/input/expected hashes, actual runtime/native identities, package
SHA/size/spec and all13 payloads, source885 and installed52/loaded10 separately.
Save as new evidence; no archive upload. This trusts reviewed workflow/harness,
GitHub runner/interpreter and private temp tree; hashes are not native/runtime
attestation or protection from malicious same-user code. Capture bounds remain
those of the reused reviewed Stage18 harness; no generic resolver/runtime exists.

Historical O1/O3 total10MB, O4 sent-header-inclusive1MiB, Linux all-traffic128MiB
and MBA409 sent-header/HTTP-total gaps remain unproved. E06PARTIAL/OPEN,
production/distribution/Phase2B/E10GO, genuine Host trust/clock/revocation,
Host atomic nonce/order/payment and worst-case resources/concurrency remain HOLD.
Preparation/merge is not execution B or public Gem distribution approval.

## Preserved failed run and current preparation status

Run39934310448 attempt1, SHA0a4dd69e51cd4317ab45a985d187d0924d0fc753,
failed the earlier upstream-only version allowlist after official Ruby archive
verification. OpenSSL reported3.0.13; actual library paths/package revisions were
not collected. That is not proof of a vulnerable library. Three Gem downloads,
JSON build,885/52,13/10 verification were skipped. The run slot is consumed and
no rerun is authorized by this policy-preparation change. Old logs/results and
communication caveats remain immutable. New execution requires a new explicit
one-run approval; this PR/source review does not dispatch anything.
