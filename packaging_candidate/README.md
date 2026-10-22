# Unpublished packaging candidate evidence

Current scope: `0.1.0.pre.2`, MRI Ruby 4.0.1, existing fixed JSON 2.19.9 / JWT 3.3.0 /
base64 0.3.0 / OpenSSL default gem 4.0.0 / Digest default gem 3.2.1. Base main:
`8d9845ff4b5618b9e57eda86d3a1e447d4124b47`.
The verifier's ten library files are byte-identical to that baseline.
This record is not a release, distribution permission, production GO or Host ALLOW.

Historical `results/R1/` (pre.1, before explicit Digest pin) contains byte-preserving copies of the successful local packaging
report, actual archive/source/installed-file audit, installed API observations,
existing dependency-provider observations, final audit timings, and 885-regression
stdout. SHA256SUMS authenticates consistency of these copies, not their provenance.
CANDIDATE_REPORT records source hashes, artifact identity and all retained limits.
REGRESSION.txt includes hashes of ephemeral synthetic signed inputs; their keys were
not saved. These generated regression wires are not the saved42 comparison corpus.
No private filesystem paths, secret keys, original raw nonce values, environment
logs, dependency trees or generated `.gem` binaries are included here.

The historical local build/install succeeded once each. Two new helper defects
(shared fixture mutation and missing stdlib fileutils require) were repaired;
failed helper records remain local and are not substituted for final success.
Final 885 regressions and52 installed checks passed.52 means42 comparisons against
existing independent MBA expectations, seven legacy APIs, two JSON rejection cases
and one constructor rejection; it does not mean52 new independent Oracle cases.
The archive contains exactly13 allowed files. All13 match both source and installed
files; all ten loaded verifier features came from the installed package.

## Repeat with pre-provisioned, already validated dependencies only

The following is a command template, not a downloader or dependency installer.
`RUBY`, `GEM_CLI`, `BUNDLE_CLI` identify the existing MRI4.0.1 toolchain;
`FIXED_GEM_PATH` points to existing exact providers, including default OpenSSL4.0.0.
Do not acquire dependencies or build native extensions if a provider is missing.
Use new OUT and FRESH directories, never overwrite historical results.
Each command must be supervised by a300-second timeout. Unset RUBYOPT/RUBYLIB and
unrelated Bundler overrides. Package installation intentionally uses
`--ignore-dependencies`: only this Gem is installed into the fresh home, while
all exact dependency providers are reused read-only. This is not an all-dependency
clean-room install or a proof of an arbitrary machine's installability.

From repository root, with GEM_HOME="$FRESH" and GEM_PATH="$FIXED_GEM_PATH":

```sh
"$RUBY" "$GEM_CLI" build --norc ap2_mandate_verifier.gemspec --output "$OUT/candidate.gem"
"$RUBY" "$GEM_CLI" install --norc --local "$OUT/candidate.gem" --install-dir "$FRESH" --ignore-dependencies --no-document
"$RUBY" -rbundler/setup -Ilib -e 'ARGV.each { |f| require_relative f }' ./test/input_boundary_test.rb ./test/root_signature_test.rb ./test/root_disclosures_test.rb ./test/purchase_binding_test.rb ./test/scoped_constraints_test.rb ./test/integration_matrix_test.rb ./test/trust_context_test.rb ./test/host_binding_test.rb ./test/research_evidence_test.rb
"$RUBY" test/package_contents_audit.rb "$OUT/candidate.gem" "$OUT/extracted" "$FRESH/gems/ap2_mandate_verifier-0.1.0.pre.2" > "$OUT/package.json"
```

For regression resolution use BUNDLE_FROZEN=true and BUNDLE_GEMFILE pointing to
this checkout's Gemfile. For the installed check unset Bundler overrides and run
from an empty directory outside the checkout, with GEM_PATH including FRESH and
the same fixed providers, and all path arguments absolute:

```sh
"$RUBY" "$CHECKOUT/test/packaged_gem_test.rb" "$CHECKOUT/stage15/results/R3/INPUTS.json" "$CHECKOUT/stage15_linux/EXPECTED.json" "$OUT/package.json" "$CHECKOUT" > "$OUT/installed.json"
```

The two saved input/expectation hashes are fixed in packaged_gem_test.rb. No input
regeneration or Python Oracle re-execution occurs in this52-check install replay.
The new packaging candidate was installed on MBA only; the previous Linux885+42
run tested baseline verifier sources, not this archive or metadata. Existing
Stage11/15 source/runtime pins and past results remain historical and unchanged.
Product CPU/RSS/concurrency limits, real trust and clock provisioning, Host atomic
nonce/order transitions and actual payments remain unproved. The two historical
acquisition-measurement gaps and Linux128MiB whole-traffic gap are not repaired by
this record. Production/distribution/Phase2B/Stage16 GO remain HOLD.

`results/R2/` preserves the additional pre-PR confirmation against identical
package/source bytes:885 regressions, the actual archive audit,52 installed
checks and four syntax checks all exit0. No new Gem build/install occurred.
It is a new run, not a replacement of R1 or prior research results.

`results/R3/` records pre.2 after the review-required Digest3.2.1 dependency pin,
new offline build/install,885 regressions and52 installed comparisons. Digest was
already provided by the same MRI default library; no download/native rebuild
occurred. R1/R2 and their pre.1 artifact hashes remain historical, unmodified.

R3 DEPENDENCY_PROVIDERS_CORRECTED.json is authoritative for Digest identity. The
earlier DEPENDENCY_PROVIDERS.json basename-based keys collided with OpenSSL and
SHA2 loader filenames and are retained only as a superseded observation. The
corrected observer uses distinct Ruby stdlib/archlib relative paths, rejects
collisions/missing/extra Digest files and skips builtin features without files.
The exact executed observer is observe_dependency_providers.rb; run via the same
installed Gem environment. Failed helper capture attempts remain local and are
disclosed in CANDIDATE_REPORT; they did not rebuild/install or change the Gem.
