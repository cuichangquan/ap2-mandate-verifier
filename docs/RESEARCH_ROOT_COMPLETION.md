# Remaining-root organization — local document batch / relocation-only PASS

Base7b9cc6121956506ef07cfded3ff2337cc0426261. Four documents moved with
identical bytes/SHA; scope notes to research/stage11/scopes and the original
STAGE11_MANIFEST.json to research/stage11. Its internal historical paths,
source pins, result hashes and accounting gaps remain unchanged. Prior
RESEARCH_PATH_MIGRATION.json/doc/test result is a historical snapshot; this
new location table supplements it and does not relabel previous tests.

Only the current relocation test's four protected document locations change;
it still compares exact original Git bytes and requires old paths absent.
One relocation-only test passed; no Verifier/Oracle/CI/acquisition/build has run.

Six active root files remain deliberately unmoved: STAGE7_PUBLIC_CASES.json,
O2O5_PUBLIC_CASES.json,O1O3_POLICY.json,O4_HTTP_ACQUISITION.json,
o1o3-requirements.lock,o4-requirements.lock. Their reader changes alter adapter
source identity: security_json/compare.py fixes OLD_ADAPTER_SHA for
stage15/compare.py; stage15_linux/export_expected.py uses that loader; Python
current_identity records its own source SHA; Stage15/18Linux manifests pin
current test/source paths and bytes. Simply updating all those old pins would
change evidence admission, not merely move files. No such update was made.

The approved relocation test was invoked once at2026-10-23T01:22:44UTC, exit0,
no stderr. It compares all protected originals to fixed Git bytes; the4document
locations are explicit and old paths absent. Its printed10deferred means content
identity of4relocated+6unmoved originals, not that all10stay in root. TestSHA256:
1278b89e772043bb03d9366771d2a8a241ea38b59752cfaff917810d8679f7db.
The earlier transport creation failure produced no receipt and no test start;
recovery retained the same exclusive guard. No test rerun occurred.
To move active6requires an explicit
current-vs-historical comparator/source-manifest plan: preserve old scripts and
manifests as historical, create a separately identified current variant only
if needed, and rerun only the affected path/identity controls under approval.
Do not introduce fallback that silently accepts both identities or claim old
runs validate new code. No new dependency/runtime/downloader is needed.

No standalone research executable file remains in repository root. Dedicated
research/stage15/stage15_linux/stage18_linux_package/security_json/
packaging_candidate directories already contain their scripts/results and are
not folded into this batch. The root research cleanup is incomplete while the
six active files remain. Product lib/gemspec/Gemfile/README/LICENSE and all13
package payloads are unchanged. This is a local candidate, not a published PR.
