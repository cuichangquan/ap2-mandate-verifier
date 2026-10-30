# MRI 3.4.12 / 4.0.9 compatibility — published 0.2.1

[0.2.1 is published on RubyGems](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.2.1).
The Owner published the exact prepared Gem; official metadata, distributed bytes
and the retained candidate matched on 2026-10-30. This repository follow-up
records the final observations without changing the packaged documents or
rebuilding/re-uploading the Gem. Real Issuer and Host production/Phase 2-B
HOLDs remain.

## Published artifact and final-source observations

- Published: `2026-10-30T11:51:55.894Z`; readback: `2026-10-30T11:53:55.141693+00:00`.
- Owner `cuichangquan`, platform `ruby`, prerelease false, yanked false.
- Source/[v0.2.1 tag and Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.2.1): `5a02bc3a192e16aa3628cf7899617623b0aed78c`.
- Tree `f4b3617772908dd70d528120dabadae877ebffc4` matches reviewed HEAD
  `704170574493bae8c9382d4db7417c3158563dc1`.
- Gem **34,816 bytes**, SHA256
  `a4ab7e0f6c9bd87355695369374f8e6e2dad104fb673700e9f616053afe6e114`.

The Gem built from that final source was normally installed on **each** MRI
3.4.12 and 4.0.9 in Debian 12/arm64. The same final archive passed all 13
payload/source/installed comparisons, ordinary loading of ten product Ruby
files and 118 installed cases per version. These are final-source observations,
separate from the premerge archive below. Source885 + checkout190 + metadata7
also passed per Ruby; no new source test was run for this publication update.

[Public final-package/publication evidence](evidence/0.2.1_publication.json)
records both final-stage artifact hashes and observations, readback checks and
retained-record hashes. [PR #216's final result](https://github.com/cuichangquan/ap2-mandate-verifier/pull/216#issuecomment-6521084431)
identifies the same archive. The earlier premerge Gem had SHA256
`6835eab5ccb5e9659c8a1bdbf6fde97b82a3590150f575fb13e6a9a751f5d445`;
it is not the published Gem. Final build used `SOURCE_DATE_EPOCH=1793357979`.

The published Gem contains the preparation-time README/contract snapshot;
this external record supersedes its pending-publication/packaging wording.
Repository documentation edits do not alter published bytes. GitHub source
ZIP/tar archives are source snapshots, not the RubyGems Gem. Do not rebuild
and reuse this artifact's identity or validation for different bytes.

## Scope and design

Base main: `d13eb28d33594d1b1f185bc857211951842055e5`.
The security proposition is unchanged behavior with ordinary fixed-dependency
resolution on MRI 3.4.12 and 4.0.9. No product library changes were required.
All ten `lib` files remain byte-identical to baseline. Fixed dependencies remain
JSON 2.19.9, JWT 3.3.0, base64 0.3.0, OpenSSL gem 4.0.2 and Digest 3.2.1.
Seven inputs, signed original-wire binding, fixed profile, Fail Closed,
Result/Evidence v2 and all API meanings are unchanged.

The gemspec installation interval is `>= 3.4.12, < 4.1`. Formal supported MRI
versions are exactly 3.4.12 and 4.0.9; intermediate versions/other engines are not
certified. RubyGems combines requirements with AND, so two equality clauses
would incorrectly reject both versions. The metadata test covers seven boundary
and intermediate examples. Installation eligibility is not formal support.

## Fresh source observations — 2026-10-30 UTC

Both runs used Debian 12 (bookworm), Linux/aarch64 in Docker on an arm64 Mac,
2 CPUs and a 2 GiB container memory limit. Dependencies were normally installed
from RubyGems, including native OpenSSL/Digest builds on 3.4.12; no default-Gem
substitution or loadpath dependency bypass was used. Tests ran sequentially in
separate processes with network disabled. No Mac packages were installed.

| Observation | MRI 3.4.12 | MRI 4.0.9 |
| --- | --- | --- |
| Ruby revision | `366f5fdc00` | `3e93b23afc` |
| Fixed five loaded Gem versions | all exact, ordinary RubyGems | all exact, ordinary RubyGems |
| Bundler baseline | 4.0.20 | 4.0.20 |
| OpenSSL compiled / loaded native library | 3.0.22 / 3.0.22 | 3.0.22 / 3.0.22 |
| Existing source cases | 885 PASS | 885 PASS |
| Additional checkout API cases | 190 PASS | 190 PASS |
| Installation metadata cases | 7 PASS | 7 PASS |

885 = boundary79 + signature74 + disclosures64 + purchase81 + constraints97 +
integration16 + trust147 + Host149 + Evidence178. `verify_checkout_test.rb`
automatically runs Host/Evidence; they were counted once. Checkout190 compares
both full entries, saved expected results, missing/extra inputs and legacy
non-success semantics. Signed negatives retain their independent expected
codes/stages; expectations were not weakened. Test-generated private keys remain
only in process memory. Saved synthetic inputs/independent expected values retain
their existing SHA256 checks; Python/schema oracle generation was not rerun.

Reproduce after installing the exact dependencies in an isolated Linux container:
`sh scripts/check_ruby_compatibility.sh /absolute/results`.
The dependency preflight asserts actual `Gem.loaded_specs`; runtime JSON records
Ruby/OS/platform, native extension and mapped libssl/libcrypto paths/SHA256.
[Source logs, runtime JSON and premerge package results](evidence/ruby_3412_409_source_and_premerge_package.json) retain the fresh observations. The same premerge archive passed 13 payload / 10 ordinary-loaded library files / 118 installed cases on both versions. Final source/package readback is a separate release gate.

Official Docker multiarchitecture image digests:

- `ruby:3.4.12-bookworm@sha256:8853c6f24866429483fce3a869e61a6a13916beb2720468c6d95c78f41c0f564`
- `ruby:4.0.9-bookworm@sha256:470eb587e87c42ad9b0062ba9bc362d90d94fb67b09fecd6052b381d897d0777`

Bundler 4.0.20 frozen dependency resolution also passed on both versions. A plain `bundle check` attempted an unchanged lockfile write against the read-only mount; `BUNDLE_FROZEN=true` preserves the lockfile and passes. An initial `gem install --install-dir` did not see the preinstalled dependency repository; standard `GEM_HOME`/`GEM_PATH` isolation resolved it without disabling dependency checks.

## Scoped upstream/provider check

Official fixed-tag gemspec Ruby minima permit both target versions:
[JSON >=2.7](https://github.com/ruby/json/blob/v2.19.9/json.gemspec),
[JWT >=2.5](https://github.com/jwt/ruby-jwt/blob/v3.3.0/ruby-jwt.gemspec),
[base64 >=2.4](https://github.com/ruby/base64/blob/v0.3.0/base64.gemspec),
[OpenSSL gem >=2.7.0](https://github.com/ruby/openssl/blob/v4.0.2/openssl.gemspec),
[Digest >=2.5.0](https://github.com/ruby/digest/blob/v3.2.1/digest.gemspec).

The known JSON advisory metadata discrepancy is preserved: the
[IO-buffer advisory](https://github.com/ruby/json/security/advisories/GHSA-x2f5-4prf-w687)
metadata lacks a patched version, while the fixed-tag changelog/source contains
the 2.19.9 fix. The [format-string advisory](https://github.com/ruby/json/security/advisories/GHSA-3m6g-2423-7cp3)
prose identifies 2.19.2 as fixed despite broad affected metadata. Product code
uses neither IO generation nor ResumableParser. The
[resumable-parser advisory](https://github.com/ruby/json/security/advisories/GHSA-9hj4-r449-hfvc)
affects 2.20.0–2.21.1. [JWT's empty-HMAC-key issue](https://github.com/jwt/ruby-jwt/security/advisories/GHSA-c32j-vqhx-rx3x)
was fixed in 3.2.0. These scoped checks do not establish general vulnerability
absence or resolve upstream metadata inconsistencies.

Both actual providers report `libssl3|3.0.22-1~deb12u2|arm64|install ok installed`
and empty successful `dpkg --verify libssl3`. The
[Debian tracker](https://security-tracker.debian.org/tracker/source-package/openssl)
and [DLA-4859-1](https://security-tracker.debian.org/tracker/DLA-4859-1)
identify that backported revision; the upstream 3.0.22 string alone is insufficient.
The remaining tracker issue [CVE-2025-27587](https://security-tracker.debian.org/tracker/CVE-2025-27587)
concerns PowerPC signing, outside this arm64/P256 observation. OpenSSL Gem 4.0.2
is distinct from the native OpenSSL 3.0 library. Package-database verification
is a trusted-container observation, not an independent runtime attestation.

## Preserved packaging procedure and release boundary

Build one Gem from the final source and run that same archive through ordinary
`gem install --local`, payload audit and detached installed tests on both Rubies:
`sh scripts/check_candidate_package.sh /absolute/results /absolute/candidate.gem`.
The existing installed suite checks 118 logical cases: research42 + checkout42 +
unavailable24 + legacy7 + invalid2 + constructor1. Payload/source/installation
hashes and ordinary loading of all ten product Ruby files are checked separately.
Final source/archive identities and successful packaging/readback are now recorded
above. The procedure describes the completed preparation; this documentation
update did not rerun it. RubyGems publication is complete. The public [tag/Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.2.1)
was created after separate explicit Owner approval and independent review of its
body; its tag target was read back and matched the published source. This
documentation follow-up has separate Owner approval, which does not authorize
real Issuer/Host production operations.

## Primary sources and limits

- [Ruby 3.4.12 release](https://www.ruby-lang.org/en/news/2026/10/23/ruby-3-4-12-released/)
  identifies the regexp compiler fixes shared with 4.0.9. This is a scoped check,
  not a blanket statement that all dependencies/providers are vulnerability-free.
- [RubyGems requirement semantics](https://docs.ruby-lang.org/en/3.4/Gem/Requirement.html#method-i-satisfied_by-3F)
  uses `requirements.all?`.

Historical manifests/harnesses/evidence are unchanged. These runs do not validate
other OS/CPU combinations, all Ruby versions in the install interval, real Issuer
provenance, production authorization, worst-case CPU/RSS/concurrency, total
network traffic or complete native symbol provenance. Container limits are
execution controls, not measured product performance. Historical acquisition
gaps remain unresolved and are not relabelled by this task.
