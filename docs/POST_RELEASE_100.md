# 1.0.0 publication and verification

Owner registered 1.0.0 on RubyGems at **2026-11-01 08:13:29.733 UTC**.
Official metadata and ownership were checked at **08:15:23 UTC**; the downloaded
distribution was compared at **08:16:01 UTC**.
[Publication receipt](evidence/1.0.0_publication.json).

| Identity | Verified value |
| --- | --- |
| Gem / version / platform | `ap2_mandate_verifier` / `1.0.0` / `ruby` |
| Owner | `cuichangquan` |
| Prerelease / yanked at comparison | `false` / `false` |
| Size | 102,912 bytes |
| SHA256 | `a107101b0178c54ba417be7a2bd7e22feb2fd9a07bda089043e8c5ea8e65e12b` |
| Release source | `59e344ad865ed867d0993120456f9411d82bcdec` |
| Release tree | `4d72878e73656733b577d55529acc55cb7af6d5b` |
| Payload comparison | All 33 files match the retained candidate manifest and release tree. |

The official metadata SHA, version-list SHA, downloaded Gem and retained candidate
agree, including byte-for-byte archive equality. The public GitHub commit API
independently confirms the release-source/tree mapping. This establishes source
association through the reviewed candidate and payload comparison, not a RubyGems
source attestation. The comparison performed no rebuild, product tests or push.

## GitHub source and Release

[PR #233](https://github.com/cuichangquan/ap2-mandate-verifier/pull/233) was squash
merged at **2026-11-01 07:59:47 UTC**. The merged tree equals reviewed PR HEAD
`e724e7e4cf2c9f3e54963e41112dc1c8ef5c5f19`.

[GitHub Release v1.0.0](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v1.0.0),
ID `430439416`, is public (`draft: false`, `prerelease: false`). The GitHub API
reports `published_at: 2026-11-01T09:17:57Z`; this is separate from RubyGems'
registration timestamp above. `refs/tags/v1.0.0` resolves directly to commit
`59e344ad865ed867d0993120456f9411d82bcdec`.

## Validation retained for these exact bytes

[Preparation evidence](evidence/1.0.0_preparation.json) records the same archive
installed on MRI 3.4.12 and 4.0.9 in the recorded Ubuntu 24.04 x86_64 environment:

- Each MRI passed 17 source-suite entry points, all 33 source/archive/installed
  payload comparisons, 134 installed cases and 244 diagnostic checks.
- Installed conditional tests passed 8 cases per MRI: 123 assertions on 3.4.12
  and 126 on 4.0.9. Direct, multi-item and conditional examples also passed.
- Pinned official Python SDK/Schema comparisons covered signatures and original
  wire hashes in both directions, external conditional issuance through the full
  public verifier, signed causal negatives and authentic Success/Error Receipts.

Repeated transitive suites are not added into a combined test count. The separate
[PR CI run 41285920612](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/41285920612)
passed both MRI source/package jobs. CI's separately built candidates do not
replace the same-archive local observations. The historical
[preparation document](RELEASE_100_CANDIDATE.md) and its NOT_RUN states remain
snapshots of that earlier checkpoint.

## Current guides and application examples

Repository-only publication updates describe the verified 1.0.0 distribution and
active 1.x contract. Packaged documents retain their preparation snapshot; these
updates do not rebuild or replace published Gem bytes.

The existing published-guide checker is pinned to the official 1.0.0 archive.
Its scope is both README InputBuilder examples, signing/Receipt, multi-item and
Direct examples, the physically installed conditional example, and the unchanged
[conditional walkthrough](RELEASE_080.md#short-conditional-purchase-flow).
The publication checkpoint above covers distribution comparison. Subsequent
published-guide execution uses the [existing workflow](../.github/workflows/merchant-source-package.yml);
each documentation PR records its own CI run and latest reviewed HEAD separately
from the candidate and publication checkpoints.

The separate Rails demo continues to use official 0.8.0. This follow-up changes
neither that repository nor its deployment. [1.0.0 installation and upgrade](RELEASE_100.md)
use plain Ruby. Real Issuer trust, application authorization, persistent replay
protection, real payments and Host production approval remain application duties
or separate decisions; publication does not establish them.
