# 0.7.0 publication and post-release verification

Owner published from their Terminal at **2026-11-01 03:12:46.522 UTC**.
Official download verification at **03:14:04 UTC** found exactly 64,000 bytes,
SHA256 `baab8c68355b5e6c9351e7d86a836fab50652cdad662bbc99d1676c5e6134447`,
matching the retained approved candidate byte for byte and source
`9b4b78a7ed9aa95e7d35e01a64efc1281ba95be3` across all 24 payloads.
Five runtime dependencies and Ruby requirements also match.
[Publication receipt](evidence/0.7.0_publication.json).

Owner separately approved exact-source tag/Release, English/Japanese guide and
local demo alignment. This maintenance changes no `lib`, gemspec, dependency
pins or profile contracts. It does not rebuild or re-push the published Gem.
The current docs supersede historical candidate status without rewriting the
published archive's preparation-time documents.

## New official-Gem measurements

The published-guides Dockerfile downloads the official 0.7.0 Gem, verifies
size/hash and installs it normally with pinned dependencies. No source-library
overlay or Gem build is used. On Linux arm64 both formal MRI versions passed:

| MRI | New image SHA256 | Result |
| --- | --- | --- |
| 3.4.12 | `0ad02bd5259df95c2b4503df3556febeaeeccef418596c7a818210f8a8a93751` | PASS |
| 4.0.9 | `85875b37a37c99cceec838a4206e637b5a19b3d8ed829128129bbea530562063` | PASS |

Checks freshly execute both README Quick Starts, merchant signing/Success/Error,
legacy multi-item lifecycle, Direct approval-to-Receipt including duplicate and
unknown-outcome example, and the exact [Release Ruby sample](RELEASE_070.md).
[Logs](evidence/published070-guides/) preserve the outputs. Prior candidate checks
are not counted as these new official-Gem checks.

```sh
docker build --build-arg RUBY_VERSION=3.4.12 -t ap2-published070-guides:3.4.12 \
  -f .github/published-guides.Dockerfile .github
docker run --rm --network=none --cpus=2 --memory=768m --pids-limit=128 \
  -v "$PWD:/src:ro" -w /src ap2-published070-guides:3.4.12 \
  timeout 120 ruby scripts/check_published_guides.rb
```

Repeat with 4.0.9. Existing docs CI uses this same path (two jobs in one run).
Draft PR, latest-HEAD independent Codex review, zero unresolved substantive
threads, relevant CI and branch rules apply before conditional squash merge.
Final PR/review/run identities are recorded in PR comments, avoiding a source
self-reference. No workflow triggers are added or changed.

## Demo and limits

The Rails demo separately pins normal Gemfile/lock and download checksum to
published 0.7.0; the previous single-item/diagnostic/merchant/multi-line scenarios
remain. Its UI demonstrates the existing Open→Agent Closed verifier; it links
the Direct runnable integration and does not claim a real approval UI or Provider
key-management backend. Its fresh build/tests/browser record is in the demo's
`docs/PUBLISHED_070.md` after the separately reviewed update.

Real authentication/purchasing authority, enrolled Issuer trust, production keys,
persistent approval/order uniqueness, atomic execution and uncertain-outcome
reconciliation, real payments, performance/concurrency and production/public Web
operation remain unproved/out of scope. No host installation, extra cost, real
credentials, shared-service cleanup or production deployment is performed.

Pre-edit authorization record: Owner's explicit postpublication approval covers
these two repositories, published-source tag/Release, guides, ordinary install,
local demo build/tests/browser, independent latest-HEAD review and conditional
squash integration. It does not cover a new Gem build/push, real payments or Web
production. Both repositories were clean with no open PR at start; canonical
Issue #101 was rechecked. Proof required is exact official-Gem size/hash, verified
sample outputs, preserved legacy demo cases and latest-HEAD clean review. STOP on
mismatch/denial, substantive unresolved findings, unexpected CI/cost or protections.
