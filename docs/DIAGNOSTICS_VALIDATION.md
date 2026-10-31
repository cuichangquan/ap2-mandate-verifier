# Diagnostic candidate validation — 2026-10-31

Scope: additive failure diagnostics for unpublished **0.4.0**, based on main
`a33459e5c90fede86408da06d79eb42b5913939f` and published v0.3.0 source
`877f59195632f74714a60551b6afb22ac81d93e3`. No publication/tag/Release.

## Observed checks

Dedicated Docker Debian 12/arm64 containers, MRI **3.4.12** and **4.0.9**,
Bundler 4.0.20; unchanged runtime pins json 2.19.9, jwt 3.3.0, base64 0.3.0,
openssl 4.0.2, digest 3.2.1. Official Ruby/RubyGems acquisition only; tests ran
with network disabled, read-only source/root filesystem and private temporary
storage. No Mac package installation or existing service/container alteration.

On **each** MRI, final source passed existing 885 regression cases, 190 checkout
API cases, 7 installation-metadata cases, 109 existing Builder cases and 244
new diagnostic assertions. Required Host/Evidence suites print again when
reused by other suites; these are not counted as additional unique cases.

The same **44,032-byte** candidate Gem, SHA256
`b212db01e7deb18dcef1199414f9d93ef43cb1f74b62baa55306de3955dfe177`,
was ordinarily installed on both MRIs outside the checkout. All **17 payload
files** matched source/archive/installation; all **12 loaded product Ruby
files** came from the installed Gem. The saved independent 42-case oracle was
checked through both complete APIs, all 134 existing installed checks passed,
then 244 diagnostic assertions and seven runnable example scenarios passed.
No source load-path substitution was used for installed checks.

Covered: success diagnostic nil and original Evidence equality; malformed
Builder shapes; missing/type/unknown/version cases; every registered Result
code; unknown-code fallback; dependency/provider unavailable subtypes; arbitrary
objects and subclasses; secret values/unknown keys/provider messages; sanitized
Builder exceptions with no parser cause; diagnostic factory faults including
faults during an ArgumentError rescue; frozen diagnostic/projection/dup/clone.
Explicit stdout/stderr capture and malformed-JSON exception-chain checks passed.
Diagnostics contain only catalog identifiers and text and retain no input graph.

Rails demo (separate repo, based on `e103afa9b837036917fde64267cae98d8d8aad2d`):
normal published 0.3.0 path passed 6 tests/122 assertions (one intentional
candidate-only skip); explicit 0.4.0 candidate passed 6 tests/148 assertions.
Real Rails POST/CSRF/Host restrictions and escaped diagnostic output were
checked. A same-size, byte-altered candidate Gem was rejected by SHA256 **before
installation**. Candidate Dockerfile and lock pin the exact checked archive;
the default dependency files remain unchanged.

## Review and limits

Independent Codex working-diff review found and corrected two core/test P2
issues (an accidental test-only base64 version change and an unguarded catalog
call in an exception rescue) and one demo P2 issue (missing pre-install archive
hash verification). Regression/negative coverage was added. Exact committed
HEAD review and GitHub late feedback are recorded in the PR before merge.
No formal Owner Approve is submitted.

Existing Actions are manual or unrelated research-path scoped; no workflow was
changed or dispatched for this task. Docker results are local observations,
not GitHub CI results. No x86_64/Windows/macOS execution, performance/load test,
real Issuer/Host/payment integration, new crypto oracle or general AP2
conformance claim. Existing production/Host authorization/Phase 2-B HOLDs and
historical acquisition/evidence limitations remain. Diagnostics are single
failed-check guidance, not a trace or a root-cause proof; some fields remain
unspecified. Publishing requires a separate Owner decision and final release
preparation from the intended release source.
