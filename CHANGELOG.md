# Changelog

## 0.2.0 — Unreleased

- Adds `verify_checkout(**inputs)` as the recommended full-verification entry, delegating directly to `ResearchResult.verify` without transforming the seven inputs.
- Preserves `verify_research` without deprecation warnings, syntax-only `verify`, fixed profile/bounds, Result/ResearchResult and immutable Evidence v2. Evidence is not Host ALLOW or payment permission.
- Aligns candidate metadata and package/installed-Gem verification source with 0.2.0.
- 2026-10-30 JST follow-up: [PR #213](https://github.com/cuichangquan/ap2-mandate-verifier/pull/213) records a limited Debian 12/arm64 candidate build/install/audit: 13 payload files matched source/archive/installation, 10 product Ruby files loaded normally, and 118 installed cases passed using saved inputs/expected values. This does not expand supported platforms; source190/885 were not rerun in that packaging attempt.
- Release-document changes affect packaged bytes. The final candidate needs separately approved rebuild/install and 13-payload/10-loaded/118-case validation (NOT_RUN); prior candidate and 0.1.0 results do not validate new bytes. Dependency/provider advisory review and exact-artifact publication approval remain pending. This version remains Unreleased.

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
