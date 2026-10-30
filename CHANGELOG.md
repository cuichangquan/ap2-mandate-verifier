# Changelog

## 0.2.1 — Unreleased

- Adds MRI 3.4.12 as a candidate supported runtime alongside MRI 4.0.9; installation metadata permits `>= 3.4.12, < 4.1`, without claiming every version in that interval is supported.
- Retains JSON 2.19.9, JWT 3.3.0, base64 0.3.0, OpenSSL gem 4.0.2 and Digest 3.2.1; preserves seven inputs, fixed profile, Fail Closed, Result/Evidence v2 and existing API meanings.
- Fresh source regressions passed on both versions in Debian 12/arm64 with official Ruby bookworm images. Ordinary installation, actual loaded providers and exact candidate artifact identity are tracked separately in the [compatibility record](docs/RUBY_3_4_12_COMPATIBILITY.md); prior PASS results are historical.
- RubyGems publication, public tag and GitHub Release remain pending separate Owner approval.

## 0.2.0 — 2026-10-30

- Adds `verify_checkout(**inputs)` as the recommended full-verification entry, delegating directly to `ResearchResult.verify` without transforming the seven inputs.
- Preserves `verify_research` without deprecation warnings, syntax-only `verify`, fixed profile/bounds, Result/ResearchResult and immutable Evidence v2. Evidence is not Host ALLOW or payment permission.
- Aligns candidate metadata and package/installed-Gem verification source with 0.2.0.
- 2026-10-30 JST follow-up: [PR #213](https://github.com/cuichangquan/ap2-mandate-verifier/pull/213) records a limited Debian 12/arm64 candidate build/install/audit: 13 payload files matched source/archive/installation, 10 product Ruby files loaded normally, and 118 installed cases passed using saved inputs/expected values. This does not expand supported platforms; source190/885 were not rerun in that packaging attempt.
- Published [0.2.0 on RubyGems](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.2.0) at 06:43:10 UTC; official metadata/distribution/retained bytes matched at 06:44:48 UTC. Source `9b2e28d91fc4886722de7b9c39a5422e966953a9`; 33,280 bytes; SHA256 `9a52e802de5a0564c34d198f4c4ad2c2b60791a8f1eb6e31db14c49e28e91f16`.
- This final artifact separately passed Debian 12/arm64 MRI 4.0.9 packaging: 13 payload / 10 ordinary-loaded product files / 118 installed cases. It differs from PR #213's earlier 32,256-byte candidate; source190/885 were not rerun in this packaging step. See [publication status](docs/PROJECT_STATUS.md#020公開済み--現在の配布状態) for evidence and limits.
- Post-publication repository documentation supersedes its preparation wording; packaged documents retain their original bytes. No rebuild/republication or platform-guarantee expansion. Real Issuer/revocation/Host, performance, production GO and Phase 2-B HOLDs remain.

## 0.1.0 — 2026-10-26

- Published the fixed-profile, verifier-only stable Gem on [RubyGems](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.1.0).
- Retains `verify_research`, existing result names, immutable in-process Evidence v2 and fixed dependencies. Evidence is not Host ALLOW or payment authorization.
- The exact R2 archive passed 13 payload / 10 loaded product file / 52 installed-package checks on the observed MRI 4.0.9 macOS arm64 and Ubuntu 24.04 x86_64 configurations. Historical regressions and independent comparisons are reused only within their recorded limits.
- Distribution: 34,304 bytes; SHA256 `37b2a235b6fab2d9d9765ae985dd9db27afd3b2c5407fe263a6b65314550db32`. See [validation and publication evidence](research/stable010_release_linux_package/README.md).
- General AP2/full Schema, issuance/presentation generation, actual Host operation, real Issuer trust, payments and worst-resource/concurrency guarantees remain outside this release's scope.

### Post-release repository documentation

English root README and Japanese README are separate, with shared existing conceptual illustrations and explicit scope caveats. The obsolete development-progress image was removed. These documentation changes do not rebuild or replace the published Gem; repository source snapshots differ from the packaged archive.

## Earlier research releases

[0.1.0.pre.3](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.1.0.pre.3) is a separate research-only archive. [Pre2 GitHub Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.1.0.pre.2) and earlier records retain their historical scope and evidence.
