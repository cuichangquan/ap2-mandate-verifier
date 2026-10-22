# Stage11 retained comparison integration — research only, HOLD

Production remains success=false/evidence=nil. No Host ALLOW, Phase2B,
production, package distribution, new dependency acquisition or Actions.
The previous Stage7 observations are preserved, not replaced by new fixtures.

## Provenance and limits

Integration base main: 027ed4734af47c8289dbcb837373bb6086463ec4;
tree b436d9d7925225e0b6295678179b624382b10990. Necessary repository Git
objects were fetched into a separate complete checkout. The prior local
candidate and original evidence are retained unchanged. Production sources,
existing five tests, Gemfile/gemspec, research Oracle, AGENTS and workflows
remain unchanged; existing ignore rules gain only local output/lock exclusions.
Final offline verification uses separate output paths and does not overwrite
the committed supplementary results. Its reviewed commit identifies this
integration; the manifest retains the earlier local snapshot identity.

Issue101 comment6317426686 pins ten original files. Historical JSON files here
are byte-for-byte copies, including retained original signed public wires.
The original comparison scripts are retained in the original local workspace;
historical report adapter SHA values identify those original versions, not the
modified Stage11 scripts. STAGE11_* files are supplementary fresh results.
The manifest separates historical identities, current sources and fresh outputs.
This is not retrospective immutable-runtime attestation of historical runs.

The old 32-case generator/exporter is deliberately excluded from normal tests
and this candidate. The new stage7_saved_replay_test.rb only replays retained
inputs, creates no keys, never signs, checks the pinned fixture SHA, compares
all three wire SHA values, actual Gem result and TracePoint entries with the
retained expectations, and records its own and production source SHA values.
Output files use O_EXCL. Existing integration16 still generates ephemeral test
keys but only exports with its explicit opt-in; normal runs unset that option.
It does not replace the saved signed fixtures or historical observations.

Python O1/O3 and O2/O5 comparisons require a fresh Gem replay file and record
its SHA. O4 additionally requires the fresh O2/O5 report whose source SHA must
match the loaded binding comparator. Schema identities and local Registry are
unchanged. TracePoint records entries, not per-stage PASS.

## Review repairs and current result identities

The first PR review found that replay source hashes and the O4 prerequisite
report were insufficiently checked. All three adapters now require the exact
current observer and complete verifier source map, exact replay case set and
per-row non-success boundary. O4 additionally requires the complete32-case
O2/O5 result boundary, all expected codes/stages/wire hashes and the exact
same fresh replay digest. Fifty-five positive/negative boundary controls
cover stale observer/source, missing or extra source, missing cases, synthetic
minimal/failed prerequisite, mismatched replay/code/wire/O2 result, complete independent event order,
replay status, prescribed Ruby4.0.1/JSON2.18.0/JWT3.3.0 runtime and Evidence.

STAGE11_R5_* reports identify the repaired adapters; earlier STAGE11_* reports
are preserved initial-candidate observations, not current-adapter evidence.
Initial, R4 and current R5 results retain identical original signed fixture inputs.
The second PR review identified recorded-but-unchecked runtime metadata.
Evidence admission was reassessed as one identity/result boundary: exact
observer, complete verifier source map, fixture/cases, prescribed runtime tuple,
per-row status/non-success, and complete O4 prerequisite/order. This final
local repair is cycle5 of5; any further substantive gap requires STOP/reassessment. For reproduction,
run the boundary controls after producing STAGE11_R5_O2O5_REPORT.json with
the O2/O5 command below (use that NEW report name on its first run).
The boundary controls read that retained current report and never overwrite it:
`"$AP2_PYTHON" -I -B test/stage11_report_boundary_test.py`.

## Local checks

- Existing regression411 = input79 + signature74 + disclosure64 + purchase81
  + scoped97 + integration16, PASS.
- Retained O2/O5 fixture32 and O1/O3 fixture6 Gem replays PASS. All preserve
  original bytes. NORMAL is a historical same-Root alias of FULL, not another
  fresh O1/O3 invocation. Signature alteration/wrong external key controls PASS.
- Independent binding/profile32 MATCH; O4 thirteen cases/64 Schema decisions/
  seventeen local references MATCH. Normal is Schema VALID, S01 is INVALID.
- Schema VALID does not imply disclosure/profile validity: EXTRA/UNKNOWN,
  amount/currency/totals mismatches and quantity2.0 remain distinguished.
  DECOY complete control remains NOT_AVAILABLE; no hidden value is filled in.
- All positive Gem results remain unverified; all evidence fields remain nil.

First setup attempt stopped before tests: Bundler frozen mode rejected empty
CHECKSUMS entries in the existing lock. No install or lock repair was attempted.
Execution instead activates existing json2.18.0/jwt3.3.0 directly. An initial
Ruby load wrapper skipped the replay CLI main guard and produced no report;
the explicit program-name wrapper below executed the actual32/6 replays.
These setup attempts are not counted as passed tests. No semantic test failed.

## Offline reproduction

Use only an already approved Ruby4.0.1 and installed fixed gems, existing
Python3.11.15 venv with the two hash locks' dependency closure, and the13
already acquired fixed Schema files. The variables below must point to these
existing local resources; none of these commands acquires or installs them.
Run from repository root and use NEW output names. Existing outputs are never
overwritten. No absolute workstation path belongs in a committed command.

```sh
env -u RUBYOPT -u RUBYLIB -u BUNDLE_GEMFILE -u AP2_STAGE7_EXPORT \
  GEM_HOME="$AP2_GEM_HOME" GEM_PATH="$AP2_GEM_PATH" \
  "$AP2_RUBY" -e 'gem "json", "= 2.18.0"; gem "jwt", "= 3.3.0"; ARGV.each { |p| load p }' \
  test/input_boundary_test.rb test/root_signature_test.rb test/root_disclosures_test.rb \
  test/purchase_binding_test.rb test/scoped_constraints_test.rb test/integration_matrix_test.rb
env -u RUBYOPT -u RUBYLIB -u BUNDLE_GEMFILE \
  GEM_HOME="$AP2_GEM_HOME" GEM_PATH="$AP2_GEM_PATH" \
  "$AP2_RUBY" -e 'gem "json", "= 2.18.0"; gem "jwt", "= 3.3.0"; f=ARGV.shift; $PROGRAM_NAME=f; load f' \
  test/stage7_saved_replay_test.rb O2O5_PUBLIC_CASES.json NEW_REPLAY32.json
env -u RUBYOPT -u RUBYLIB -u BUNDLE_GEMFILE \
  GEM_HOME="$AP2_GEM_HOME" GEM_PATH="$AP2_GEM_PATH" \
  "$AP2_RUBY" -e 'gem "json", "= 2.18.0"; gem "jwt", "= 3.3.0"; f=ARGV.shift; $PROGRAM_NAME=f; load f' \
  test/stage7_saved_replay_test.rb STAGE7_PUBLIC_CASES.json NEW_REPLAY6.json
"$AP2_PYTHON" -I -B test/o1o3_compare.py \
  --oracle research/phase2a_e06i/e03_e04_signed_oracle.py \
  --bundle STAGE7_PUBLIC_CASES.json --policy O1O3_POLICY.json \
  --gem-replay NEW_REPLAY6.json --report NEW_O1O3.json
"$AP2_PYTHON" -I -B test/o2o5_compare.py \
  --oracle research/phase2a_e06i/e03_e04_signed_oracle.py \
  --fixture O2O5_PUBLIC_CASES.json --gem-replay NEW_REPLAY32.json --report NEW_O2O5.json
"$AP2_PYTHON" -I -B test/o4_compare.py \
  --oracle research/phase2a_e06i/e03_e04_signed_oracle.py \
  --fixture O2O5_PUBLIC_CASES.json --schema-dir "$AP2_SCHEMA_DIR" \
  --gem-replay NEW_REPLAY32.json --binding-report NEW_O2O5.json --report NEW_O4.json
```

The five-wheel O4 lock supplements the five-wheel O1/O3 lock; existing
typing-extensions is reused. No format extras, SDK installation or source builds.
Schema/vendor/wheels/venv/cache/raw headers/environment logs are excluded from
publication; their identities remain in the historical ledger and new manifest.
This candidate therefore does not claim self-contained dependency reproduction.

## Outstanding gates and acquisition defects

Historical acquisition1: wheel4408169 bytes measured, metadata-inclusive10MB
total unmeasured. Acquisition2: received HTTP body/header596565 bytes measured,
curl size_request0 in18 transfers means sent-header-inclusive total unproven.
Reserved bytes do not repair this. No new fetch was used to change that record.

Synthetic fixture/profile/cryptographic design assumptions are shared despite
different implementations. Real Issuer/Host enrollment, key/profile lifecycle,
challenge/order/Buyer authority, nonce-CAS/replay/revocation, full Schema/all
constraints, resource/time/concurrency guarantees and success Evidence remain
unproven or unimplemented. Stage7 final acceptance and production/distribution/
Phase2B stay HOLD. Stage10 DESIGN_ONLY material is separate, not implemented.

## Additional approved identity-contract repair

The previous five-cycle unit stopped on two further Gate P2 findings.
A separately approved repair unifies the comparison input identity boundary in
`test/stage11_identity.py`; this does not silently extend the former limit.
Initial/R4/R5 results remain immutable; current supplementary reports use
STAGE11_IDENTITY_*. No dependency or external source was acquired.

| Boundary | Trust origin and admission |
| --- | --- |
| Schema ledger | Known original Issue101 SHA256 is compiled into the reviewed contract before parsing; caller hashes cannot authorize the ledger |
| Schema files | Fixed ledger SHA256 plus independently computed Git blob identity, pinned AP2 URL and local Registry closure |
| Public fixtures and policy | Known retained byte SHA256 values, separate from supplied replay fields |
| Oracle | Existing reviewed original source SHA256 before execution |
| Observer/verifier | Current reviewed checkout source hashes; exact replay case set, wire hashes, status and non-success boundary |
| Python/dependencies | Actual CPython3.11.15/Darwin/arm64 plus exact ten installed distribution versions, measured before third-party verifier imports; both lock byte hashes fixed |
| Reports | All three record measured Python identity and contract source SHA; O4 requires the same complete measured identity in its full O2/O5 prerequisite |

The dependency map is the closed ten-package comparison closure. Extra identity
fields/dependencies are rejected; unrelated venv tooling is not claimed absent.
Version metadata/lock identities are not installed-binary attestation, a signed
execution receipt or protection against an attacker modifying the reviewed code
and local interpreter together. No generic immutable-runtime claim is made.

Final additional checks:411 regressions; retained32+6 Gem replays;58 report
boundary controls;57 identity controls; independent binding32; O1/O3 six classes
and signature controls; O4 thirteen cases/64 decisions/17 local refs; Ruby14 and
Python6 syntax. Identity controls include mutually consistent forged ledger
and Schema, altered fixtures/policy, missing/wrong/extra Python/dependency
identity and the actual O4-to-binding module load path.

One integration run failed because the dynamic O4 module loader lacked
__file__; this same-introduction defect was corrected and its real path tested.
No prior result was overwritten. The original historical acquisition defects
and all success/Evidence/Host/production/distribution/Phase2B HOLDs remain.

### Bounded identity input admission

A subsequent review found the new pinned reader had reopened paths with an
unbounded read after its size check. It now reuses the existing Oracle's
same-file pattern: lstat, no-follow/nonblocking open, descriptor metadata match,
one read of at most cap+1, and post-read descriptor/path consistency checks.
The same reader covers pinned fixtures/policy/ledger and local lock/identity
source reads. Symlink/FIFO/oversize, replacement-before-open and growth-during-
read controls reject; the requested read size is checked explicitly.
Current reports are STAGE11_BOUNDED_*; STAGE11_IDENTITY_* remain preserved.
Final report-boundary controls58 and identity controls64 pass with unchanged
411 regressions,38 retained replays and all independent comparisons. This is
the third local cycle within the separately approved identity repair unit.

## Separately approved Oracle and Ruby fixture read repair

After the prior STOP, Owner explicitly approved the remaining Python Oracle
and Ruby fixture input boundaries. All three Oracle CLI reads now use the
existing reader with a16KiB cap (known source13953B), hash-checking the same
bytes before compilation. Other adapter/observer/verifier hash reads use64KiB
caps. Ruby retained fixture input uses one NOFOLLOW/NONBLOCK descriptor,
cap1MiB, and descriptor/path metadata consistency before and after reading.
No general I/O platform, new dependency, acquisition or production change.

Current results and fresh observer observations use STAGE11_IO_*; every prior
report/replay and original signed fixture remains unchanged. Actual CLI tests
reject FIFO/oversize/symlink Oracle inputs in all three adapters (10 controls),
with replacement/growth behavior covered by the existing shared-reader tests.
Ruby fixture tests cover seven positive/type/size/symlink/FIFO/replacement/
growth-and-read-size controls. No source/fixture full-read bypass remains in
the three adapters or saved replay entry point.

Final:411 regressions,32+6 saved Gem replays,58 report-boundary controls,
64 identity controls,Ruby IO7,Python IO10,independent binding32,O1/O3 six
classes and signature controls,O4 thirteen cases/64 decisions/17 refs;
Ruby syntax15/Python AST7. Controls run using existing fixed local dependencies:
`"$AP2_PYTHON" -I -B test/stage11_io_test.py` and the documented Ruby wrapper
with `test/stage11_io_test.rb`. The report-boundary tests consume the current
STAGE11_IO reports; earlier sections identify retained historical iterations.
All HOLDs and historical acquisition-compliance deficiencies remain unchanged.

## Captured seven-file verifier snapshot (separately approved)

The earlier observation entry required the checkout Gem before hashing its
sources. A startup replacement restored before measurement could therefore
misattribute observations. The current harness no longer loads checkout Gem
code. Its literal seven-file SHA256 allowlist is anchored to reviewed main
027ed4734af47c8289dbcb837373bb6086463ec4, not to the mutable result manifest.

It checks the complete source inventory, captures bounded original bytes and
verifies every pin. Those frozen bytes alone are written to a dedicated
private temporary tree. After verifying the tree, ordinary Ruby require loads
the normal Gem entry and its require_relative dependencies. The seven loaded
paths and temporary-tree hashes are checked, and post-observation tree checks
complete before any result is written. Recorded verifier hashes describe the
captured pinned bytes, not a later reread of the original checkout. Python
adapters require the new source_loading contract and current observer identity.

The trusted boundary includes this harness, the interpreter/dependencies and
the temporary tree with no other writers. It is not malicious-same-user defense,
an immutable environment claim, installed-runtime attestation or a signed
execution receipt. No custom eval loader, dedicated runtime or general I/O
platform is introduced. Temporary files use normal private temp handling.

Fourteen local controls include pin mismatch, missing/extra files/directories,
links, altered captured maps, preload rejection and cleanup. A controlled copy
of the source checkout is destroyed/replaced after capture; the original seven
captured files still load through the standard entry and yield non-success.
The actual checkout/lib and all historical inputs/results are unchanged.
An initial load-path comparison exposed the macOS temporary-path alias; using
the temporary directory's canonical path resolved it without relaxing pins.

Current results use STAGE11_SNAPSHOT_*; all earlier results remain retained.
Final local validation:411 regressions,32+6 saved-wire snapshot replays,
73 report-boundary controls,64 identity controls,Ruby IO7,Python IO10,
snapshot14,independent binding32,O1/O3 six classes and signature controls,
O4 thirteen cases/64 decisions/17 refs; Ruby syntax16/Python AST7.
Use the existing documented Ruby wrapper with test/stage11_snapshot_test.rb
for local snapshot controls. Generic comparison commands accept fresh snapshot
replays; report-boundary controls read the retained current snapshot reports.
All success/Evidence/Host/production/distribution/Phase2B HOLDs and historical
acquisition-compliance deficiencies remain unchanged.
