# MRI 3.4.12 / 4.0.9 compatibility — unpublished 0.2.1

Owner authorized implementation, isolated zero-cost testing, independent review,
conditional squash merge and final Gem preparation. RubyGems publication, public
tag and GitHub Release require the next Owner approval. Real Issuer and Host
production/Phase 2-B HOLDs remain.

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

## Candidate packaging and release boundary

Build one Gem from the final source and run that same archive through ordinary
`gem install --local`, payload audit and detached installed tests on both Rubies:
`sh scripts/check_candidate_package.sh /absolute/results /absolute/candidate.gem`.
The existing installed suite checks 118 logical cases: research42 + checkout42 +
unavailable24 + legacy7 + invalid2 + constructor1. Payload/source/installation
hashes and ordinary loading of all ten product Ruby files are checked separately.
Final source SHA, archive bytes/SHA256, fresh packaging results and latest-HEAD
review must be recorded before declaring publication readiness. Until then this
section is a checklist, not a packaging PASS. No publication is performed here.

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
