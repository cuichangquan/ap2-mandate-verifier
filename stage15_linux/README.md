# Limited Linux replay — Stage15, not Stage16 GO

Purpose: one Ubuntu24.04 x64 standard public-repository Actions run of the current
Gem: 885 regression cases and the same42 public synthetic inputs (30 independent
contract cases +12 authored boundary expectations). This is MBA independently
computed expectations replayed on Linux, not Python Oracle re-execution on Linux.
The eight official fixed-Schema judgments remain MBA evidence. Host execution,
real trust/clock, atomic consume/orderCAS, payments, product CPU/RSS/concurrency,
production/distribution/Phase2B and Stage16 GO remain HOLD. Earlier two acquisition
measurement gaps are unchanged. Old Stage11/15/Darwin evidence is not edited.

`export_expected.py` runs only in the existing approved MBA Python environment.
It validates the old Oracle/adapter/input hashes, uses independent signature,
graph, binding and contract predicates, and writes EXPECTED.json with exclusive
creation. It never invokes Ruby or reads Gem result reports. Raw original input
bytes stay at `stage15/results/R3/INPUTS.json`, pinned by SHA256. Expected Evidence
is assembled by the Python model, including nonce SHA256 projection. The normal
Gem result is never used to author the expected values.

The reviewed Workflow fixes the MANIFEST.json hash. That manifest fixes source,
resolver, nine regression tests, the public regression fixture, input and expected
hashes. `replay.rb` captures regular/no-follow/bounded/stable files into a private
tree and uses the ordinary Gem entry with frozen Bundler. It checks all885 counts,
all42 exact status/code/Evidence/entered-wrapper results and mutation/freeze facts.
Entered wrappers are not per-stage PASS. Each Ruby probe has10s, regression and
comparison batches300s each. Dependencies must be Ruby4.0.1/JSON2.19.9/JWT3.3.0/
base640.3.0/OpenSSLgem4.0.0/Bundler4.0.3 and the exact resolved gem set. New Linux
native hashes are observed separately from the MBA build; they are not compared
to Darwin binaries or called environment attestation. The harness, runner image,
interpreter, installed dependencies and temporary tree are trusted boundaries.

`PREFLIGHT_MBA.json` is only local preflight, not a Linux result. The live Linux
result will be printed to the run log and Job Summary, with source/input/expected
hashes and native runtime identity. No artifact or cache is uploaded. No private
keys, real nonce, personal paths, raw environment/network logs or binaries are
published. Existing saved inputs contain public synthetic nonce values only.

## One manual run and bounded plan

Only workflow_dispatch is enabled. contents:read, no secrets, immutable checkout
and setup-ruby Action SHAs, no credentials persisted, no submodules/LFS, no
bundler cache or implicit dependency installation. expected_sha must equal the
40-hex dispatched commit, actual checkout, and approved merged ref. Job and shell
gates require refs/heads/main, so selecting a feature branch cannot start setup. The attempt
must be1. The one-run authorization is managed by the operator as well: this
workflow does not implement a persistent lifetime run counter. Never rerun a
failed run automatically. A failure permits read-only diagnosis only.

15min whole job; setup3min; JSON native build exactly one attempt, timeout180s;
pure Ruby JWT/base64 installs30s each. Per-probe and batch timeouts do not imply
product-level hard CPU/RSS limits. Child CPU user/system values are observations.
Ruby/setup-ruby installs the standard prebuilt distribution; no custom runtime,
OS package installation or supervisor is introduced.

Estimated acquisition80MiB, planning budget128MiB, not a global HTTP hard cap.
Official Ruby4.0.1 Ubuntu24.04 x64 asset metadata:49098324B, SHA256
`d3193107484f9607a665f10fedcc9e0738046eb572a0aef2267c36719382fa16`.
The standard Action manages that transport; neither its HTTP headers nor the
runner/checkout/Action control traffic are included in the gem curl counters.
The image/runtime cache state is not assumed. Three official RubyGems archives
have exact body total176640B and SHA256 checks, no index/redirect/retry or dependency
resolution. curl reports sent/received header and body counters; a zero/missing
sent-header counter is unknown, not evidence of zero traffic. Do not add these
limited observations and claim all network traffic measured. Unexpected large
acquisition, dependency or plan-budget deviation is STOP. No Linux Python wheel,
SDK/schema clone or second interpreter download is needed.

The repo is public and the standard ubuntu-24.04 runner is free under the checked
GitHub policy: https://docs.github.com/actions/using-jobs/choosing-the-runner-for-a-job .
No paid larger runner, artifact/cache storage or fees are authorized. Ephemeral
working space is estimated below1GiB; public result summary/log is below64KiB,
with no additional artifact storage. Standard checkout/setup transport sizes and
actual CPU/disk remain observations, not certified advance bounds.
