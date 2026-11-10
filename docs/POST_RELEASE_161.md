# 1.6.1 publication and verification

The Owner registered **1.6.1** with MFA on **2026-11-10T15:20:23.005Z**.
Registry metadata reports `yanked=false`. The actual downloaded public archive
is byte-identical to the approved candidate. [Machine-readable record](evidence/1.6.1_publication.json).

| Identity | Verified value |
| --- | --- |
| Gem/platform | ap2_mandate_verifier 1.6.1 / ruby |
| Bytes | 199,680 |
| SHA256 | `97958467a326d5ab6dd4ca2ad45e22799a96d7e4fe181fa660795928a086edeb` |
| Released source | `53a19787734a426c03221d3de7891d1e648751df` |
| Reviewed source | `d24bcb0586b79a59752d2fc638a37c74f1cd97a6` |
| Identical reviewed/merged tree | `5aac4e66cf269cb49da3397c91e46514a96e14bd` |

[RubyGems version](https://rubygems.org/gems/ap2_mandate_verifier/versions/1.6.1)
metadata SHA agrees with actual downloaded bytes. Source association is established
by full payload comparison, not by a registry source attestation.
[Formal Release v1.6.1](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v1.6.1)
is public, non-draft/non-prerelease, published at **2026-11-10T15:30:07Z**.
Annotated tag object `01894d42d4a1a0aaa503a93ddd20dad3a0a2cc4d` peels to the released
source, matching the Release target. An unauthenticated public Release asset download
is byte-identical to RubyGems and the candidate.

The fixed MRI 4.0.9 Docker builder used `SOURCE_DATE_EPOCH=1794319977`.
Repeated candidate builds and the merged-source build matched the original verified
archive byte-for-byte. `git -c tar.umask=0022 archive` preserves canonical 0644 file
modes: the initial default export produced 0664 metadata despite equal file content.
Normalizing the export reproduced the original artifact; no replacement was published.

## Tests and review

[PR #257](https://github.com/cuichangquan/ap2-mandate-verifier/pull/257) received
latest-HEAD independent Codex review with no findings; all ten checks in the
[final source/candidate CI](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/42841209837)
passed. Before publication, source and same-archive installed regressions passed on
MRI 3.4.12 / 4.0.9. All 74 payload files matched source, archive and installation;
the integration suite checked 530 assertions across 93 separate processes per MRI.
These are prepublication results for identical bytes, not newly claimed public-package runs.

After publication, isolated Linux ARM64 Docker checks installed the **actual downloaded
public archive** on both MRIs. All 74 source/archive/installed payload hashes matched,
and the full installed regression runs completed with exit 0. Each MRI's integration
suite passed 530 checks across 93 separate Ruby processes and nine scenarios using
the installed Gem. These public-package runs are distinct from the candidate CI;
repeated transitive checks are not summed.

## Using the release and its limits

The patch packages the Ruby integration CLI, protected-input helper, durable mock
processor and English/Japanese guides. SDK implementation, public APIs, pinned
runtime dependencies and Ruby requirements are unchanged. Use the
[English](RUBY_INTEGRATION.md) or [Japanese](RUBY_INTEGRATION.ja.md) guide to install
public 1.6.1 and optional SQLite 2.10.2 in an isolated Ruby environment and run the
bundled CLI without a checkout or product-source overlay.

The guide's existing Docker image intentionally remains public 1.6.0 plus repository
example source. README minimal quick starts use published 1.6.1; their installed
Checkout and Payment examples passed on both MRIs. The standalone Quick Start guides
and [native platform evidence](PLATFORM_SUPPORT.md) retain the 1.6.0 baseline.
The new CLI's Linux/Docker checks do not certify
native macOS or Windows behavior; no new native-platform run is claimed here.

Crash/restart recovery preserves the original signed wires and processor key;
unknown outcomes, missing results, elapsed time and Error Receipts do not authorize
automatic re-execution or allowance refunds. The durable mock is synthetic and
single-host, not proof of real-processor exactly-once behavior or settlement.
Authenticated consent, current trust/order/nonce authority, PSP idempotency and
query contracts, and production recovery decisions remain application responsibilities.

The Owner performed the Gem push. No agent push, duplicate publication, replacement
of published bytes or direct Mac software installation occurred. Preparation text
inside the archive is a historical snapshot; this follow-up does not rebuild the Gem.
