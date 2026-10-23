# Published pre3 Linux verification — PREPARATION ONLY / NOT_RUN

Approval A covers these five new preparation files plus docs/PROJECT_STATUS.md,
static review, PR/Codex review and conditional integration. **No execution B is
granted.** No archive acquisition, Ruby/syntax check, build, install, test or
Actions has been performed for this preparation.

## One proposition

Verify the already published RubyGems0.1.0.pre.3 in standard public Ubuntu24.04
x64: exact37888B / SHA256
8ad627818dc69b450d0fba970dafaf368ec42dd64fb51eec631731027de3882c,
13 payload identities,10 ordinarily loaded installed libraries and52 installed
checks. No Gem build,885 source regressions or independent Oracle rerun.

CURRENT_MANIFEST.json pins the published artifact and the13 payload SHA256/Git
blob identities read from packaging commit20809b057c75d4145eff13e5c183d616c19ef696.
[PR177](https://github.com/cuichangquan/ap2-mandate-verifier/pull/177) identifies
MBA409-PRE3PACKAGE02-20261023 and the mapped422-file snapshot. Owner separately
confirmed official API/distributed archive/MBA equality on2026-10-23.
Preparation did not refetch the Gem. These references are not a manifest derived
only from the archive being tested. Current main's README/SUPPORT_CONTRACT are
later supplements and intentionally differ; they must not be the payload oracle.
Old pre2 workflows/manifests/results and public artifacts/tags remain unchanged.

## Future execution B (separate approval)

- One workflow_dispatch, main only, exact reviewed/merged SHA, attempt1,
  public standard ubuntu-24.04 x64; both approval_b_confirmed and
  zero_cost_confirmed must be true. Inputs are operator attestations, not an
  authorization source or a fresh proof of cost. No automatic PR/push/schedule,
  secrets, cache, artifact upload, credentials persistence, LFS or submodules.
- Reuse the old Linux409 provider checks in the new guarded helper. Official
  Ruby4.0.9 archive49100121B /
  SHA256046d1422e1be5575eadd55323c85c3efbeaee8c8e1c1bfccee343e28619cb3b3.
  Check size/hash before extraction. Existing provider prefix means STOP.
  No Ruby/OpenSSL compilation, apt or runtime repair.
- Preflight before Gem acquisition: MRI4.0.9, default OpenSSL gem4.0.2/Digest3.2.1,
  Bundler4.0.20/resolv0.7.2/zlib3.2.3. Actual mapped openssl.so under the verified
  Ruby prefix; exactly one libssl.so.3/libcrypto.so.3, no missing/deleted/ambiguous
  mapping. Require libssl3t64:amd64/source openssl3.0.13-0ubuntu3.16, dpkg ownership,
  empty dpkg --verify, package MD5 consistency and observed SHA256. Bare3.0.13
  is insufficient. This policy follows
  [USN-8847-1](https://ubuntu.com/security/notices/USN-8847-1).
  Later/unknown package revisions stop for read-only assessment, not auto-upgrade.
- Direct HTTPS/no redirects/no retries/no index: json2.19.9(107008B),
  jwt3.3.0(57856B),base640.3.0(11776B) and published pre3(37888B);
  exact archive hashes are in the workflow. JSON C build once<=180s, JWT/base64
  pure Ruby. OpenSSL/Digest remain fixed defaults. Install dependencies --local
  --ignore-dependencies; no implicit resolver acquisition.
- Published archive size/hash and Gem metadata/whitelist are checked before
  install. Extracted13 match the pinned packaging reference; offline-install
  that same archive into a new Gem home and recheck13 installed hashes.
  No source-loadpath substitution. Installed test is run outside checkout.
-52 =42 replays of saved MBA independent expectations +7 legacy API checks
  +2 input rejections +1 constructor rejection. Preserve nil/false legacy results
  and immutable research Evidence. Inputs and expectations retain their existing
  fixed hashes. Do not regenerate fixtures or relabel Linux replay as an Oracle.
- The installed subprocess itself repeats actual Ruby/OpenSSL provider checks
  and identifies JSON2.19.9 native parser/generator paths and SHA256 from the
  fixed Gem installation. Parent and child provider observations must match.
  These are trusted-runner observations, not hostile-same-user/runtime attestation.

## Bounds, output and STOP

Job15min; Ruby acquisition3min, dependency/product archive preparation5min,
final harness7min (outer timeout420s). Preflight45s, JSON build180s once,
JWT/base64 installs30s each, product install60s, installed52 batch300s.
The job-wide deadline wins; limits are not additive completion guarantees.
Helper subprocesses have stdout131072B/stderr16384B caps and owned process-group
cleanup; runner job timeout remains the outside bound. No generic supervisor
or product CPU/RSS/concurrency guarantee is introduced.

Five fixed archive bodies total49314649B. Ruby asset redirects are limited to2;
the four RubyGems archive requests permit none. Curl reports body/request-header/
response-header counters; raw headers may contain signed redirect URLs and stay
only in ephemeral runner files. Checkout/action/runner/DNS/TLS traffic and all
redirect-hop request accounting remain unknown.128MiB all-network compliance and
historical acquisition-accounting gaps are **UNPROVEN**, never repaired by PASS.

Output is bounded stdout/Job Summary only: exact source/run/attempt, manifest,
artifact SHA/size, independent payload reference,13 hashes, actual providers,
10 loaded identities and52 results; source885 NOT_RUN/Oracle NOT_RERUN/HOLDs.
No archive, fixture, private key or raw header upload. No payment or Host mutation.

Hash/metadata/provider mismatch, unknown dependency/cost, command error, timeout
or failed check => STOP, read-only diagnosis only. No automatic repair, retry,
rerun/attempt2, new download or later-provider substitution. Existing run slots
are consumed and cannot be reused. Any further execution needs new approval.

## Cost and meaning

[Official public standard-runner terms](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
make this runner eligible for free execution;
[logs/Job Summary do not count toward artifact storage](https://docs.github.com/en/billing/concepts/product-billing/github-actions).
No paid runner, cache/artifact storage or external paid service is requested.
Reconfirm repository visibility, workflow/runner and current terms immediately
before B; unknown incremental cost means STOP. Preparation is not a promise of
future billing or approval to spend.

A successful future run establishes only the stated published-artifact Linux
observation. Fixed-profile research only, not general AP2 interoperability,
Phase2-A full PASS, E10/Phase2B/production GO, real Issuer enrollment, Host ALLOW,
atomic nonce/order/payment or worst-case resource/concurrency safety.
See [current status](../../docs/PROJECT_STATUS.md) and
[support contract](../../docs/SUPPORT_CONTRACT.md).
