# Research path migration — Batch1 / relocation-only validation passed

Historical Stage11 report/replay JSON files and three original Stage7 report
files move from repository root to research/stage11/archive without byte changes.
See RESEARCH_PATH_MIGRATION.json for every old/new path, size and SHA256.
These are original retained observations, not regenerated/current-pass evidence.
Old filenames, code pins and manifests inside historical bytes stay untouched.
Use this location map when reading old report/docs references.

Only two current report-boundary/I/O test paths are updated. No Oracle adapter,
identity pins, product library/gemspec/Gemfile/README/LICENSE/packaging whitelist
or workflow changes. No symbolic-link/duplicate-root compatibility path.

Root has no standalone research executable script in the audited main. Scripts
are already under test/research/stage-specific directories. This bounded first
batch handles saved results; active fixture/policy/ledger/locks/manifest/scope
files and stage directories remain inventoried for a coordinated next batch.
Those active files must not be moved by blanket glob: independent pin names,
manifest paths and original source identities must remain meaningful.

Original preparation snapshot (before execution approval): pending minimal validation updated Python report-boundary and
I/O controls with original fixed Stage11 environment/dependencies; inspect their
existing provider/source prerequisites first, do not rewrite history to make
old reports pass. Current-product885 source regressions for trust fixture users
need not be expanded solely for archived locations, but a future integrated PR
may approve existing885 as bounded regression. At that preparation point, static bytes/path/package audit was complete and no
syntax/test/API/CI or dependency activity had run. See later execution below.

The approved PR contains only moves, this mapping, two reference updates and
one relocation-only test. Packaging13 and gemspec bytes remain identical, so
this reorganization alone does not need a new Gem build. Merge/Actions/Gem
distribution remain unapproved.

## Approved local validation update —2026-10-23UTC

Existing fixed Python venv, one invocation each, no acquisition/network/CI:
`test/stage11_io_test.py`: PASS10 read-boundary controls.
`test/stage11_report_boundary_test.py`: stopped at initial historical replay
source/result identity validation. The moved replay records7verifier files at
027ed4734.../JSON2.18.0; current main has10files and changed sources. Observer
identity matches, and path reads succeeded. This is not a path-migration failure
or a reason to rewrite history pins. No rerun, adapter change or pin relaxation.
A separate historical-vs-current validation design needs scoped approval.
At that point PR publication/review was paused; independent static audit found
no migration-introduced issue, all30renames byte-identical, package unchanged.

## Relocation-only test —2026-10-23T00:54:28UTC

`/opt/homebrew/bin/python3.11 -I -B test/research_path_migration_test.py`
was invoked exactly once and passed (exit0, no stderr). It uses only existing
local Git objects at fixed base c8d81eab49e37a1236a355d42cf667aab552392d:
30original blobs equal destination bytes/SHA/size with old paths absent;
6exact path-only substitutions;13payloads+gemspec and10deferred files unchanged.
Test SHA256:5f16b8059dc3b7583aa74afd56b981a969e3bab28cbb2a9dc67affc1978ce831.
No old/current verifier or Oracle is executed by this test. The historical
report-boundary identity failure above remains preserved, not waived or fixed.
The I/O test's earlier PASS10 remains a separate result, not a new rerun.
PR publication and static Codex review are now authorized; no merge/CI/build.
