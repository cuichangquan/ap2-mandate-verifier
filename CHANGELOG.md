# Changelog

## 0.4.0 — unreleased

- Adds immutable, input-free `Result#diagnostic` and `InputBuilder::Invalid#diagnostic`, machine stage/field/reason identifiers and English/Japanese hints. Success has no failure diagnostic; diagnostic failure cannot change a verdict.
- Identifies known Builder missing/type/unknown-field/saved-format failures; existing status/code and all verification/Evidence contracts remain unchanged. Adds boundary, dependency, redaction and installed-package coverage plus runnable examples and guides.
- Candidate only; no Gem publication, tag or Release. Published 0.3.0 remains unchanged. Runtime pins, fixed profile and production/real-Issuer/Host/Phase 2-B HOLDs remain.

## 0.3.0 — 2026-10-31

- Corrects candidate InputBuilder.verify failure handling to reuse registered Result codes. Malformed assembly returns rejected/invalid_host_context; unavailable assembly returns unavailable/research_verification_unavailable, with no Evidence. The earlier candidate SHA256 5de6907cfcf0565ddaba1385b1d38ae113cc5e26d52259d769030237378a48a8 is withdrawn and must not be published.

- Adds Rails-independent `InputBuilder` conversion from explicit authenticated trust records and order information, challenge preparation, exact versioned persistence restoration and full verification through the unchanged seven-input core.
- Bounds plain Ruby input graphs before serialization; preserves stored issue-time binding/references and separately constructs current binding. Unknown persisted formats/profiles fail closed. Assembly alone produces no Evidence.
- Adds runnable business-data examples, English/Japanese guidance and Rails mapping. Existing fixed runtime dependencies, supported Rubies, profile and Result/Evidence v2 contracts remain unchanged. Publication does not establish Host production GO.

- Published [0.3.0 on RubyGems](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.3.0) at 01:31:40.743 UTC; metadata fetched 01:32:40 UTC and exact archive comparison completed 01:33:27 UTC. Source `877f59195632f74714a60551b6afb22ac81d93e3`; 37,376 bytes; SHA256 `b3a31d5a8b0718f1085745dd4d97d85f210ff9a1628798110da9ff382ae546bd`. Owner `cuichangquan`, platform `ruby`, non-prerelease, not yanked at verification. [v0.3.0 tag/Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.3.0) targets that exact source (published 01:35:52 UTC).
- Corrected final source passed existing885 + checkout190 + metadata7 + builder109 on each supported Ruby; the same final Gem passed 14 payload matches, 11 ordinary-loaded product files and 134 installed cases per Ruby on Debian12/arm64. See [publication/withdrawal history](docs/PROJECT_STATUS.md#030公開済み--現在の配布状態). Prior124-case observations did not cover the withdrawn candidate's failure handlers.
- Repository-only publication documentation does not rebuild, repush or replace the published archive; packaged documents retain their preparation snapshot. Real Issuer/Host, performance, production GO and Phase 2-B remain HOLD.

## 0.2.1 — 2026-10-30

- Adds formal MRI 3.4.12 support alongside MRI 4.0.9; installation metadata permits `>= 3.4.12, < 4.1`, without claiming every version in that interval is supported.
- Retains JSON 2.19.9, JWT 3.3.0, base64 0.3.0, OpenSSL gem 4.0.2 and Digest 3.2.1; preserves seven inputs, fixed profile, Fail Closed, Result/Evidence v2 and existing API meanings. Product `lib/` is unchanged.
- Both Rubies passed Debian 12/arm64 source885 + additional checkout190 + metadata7. The same final Gem passed ordinary installation, 13 payload / 10 normally loaded product files and 118 installed cases per Ruby. Exact providers and scope are recorded in the [compatibility record](docs/RUBY_3_4_12_COMPATIBILITY.md); historical macOS/Ubuntu findings remain separate.
- Published [0.2.1 on RubyGems](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.2.1) at 11:51:55.894 UTC; verified at 11:53:55 UTC. Source `5a02bc3a192e16aa3628cf7899617623b0aed78c`; 34,816 bytes; SHA256 `a4ab7e0f6c9bd87355695369374f8e6e2dad104fb673700e9f616053afe6e114`. [GitHub Release v0.2.1](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.2.1) and its tag use that exact source.
- Repository publication updates do not rebuild/repush the Gem; packaged README/contract retain their preparation snapshot. GitHub source archives differ from the RubyGems Gem. Real Issuer/Host, production GO and Phase 2-B HOLDs remain.

## 0.2.0 — 2026-10-30

- Adds `verify_checkout(**inputs)` as the recommended full-verification entry, delegating directly to `ResearchResult.verify` without transforming the seven inputs.
- Preserves `verify_research` without deprecation warnings, syntax-only `verify`, fixed profile/bounds, Result/ResearchResult and immutable Evidence v2. Evidence is not Host ALLOW or payment permission.
- Aligns candidate metadata and package/installed-Gem verification source with 0.2.0.
- 2026-10-30 JST follow-up: [PR #213](https://github.com/cuichangquan/ap2-mandate-verifier/pull/213) records a limited Debian 12/arm64 candidate build/install/audit: 13 payload files matched source/archive/installation, 10 product Ruby files loaded normally, and 118 installed cases passed using saved inputs/expected values. This does not expand supported platforms; source190/885 were not rerun in that packaging attempt.
- Published [0.2.0 on RubyGems](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.2.0) at 06:43:10 UTC; official metadata/distribution/retained bytes matched at 06:44:48 UTC. Source `9b2e28d91fc4886722de7b9c39a5422e966953a9`; 33,280 bytes; SHA256 `9a52e802de5a0564c34d198f4c4ad2c2b60791a8f1eb6e31db14c49e28e91f16`.
- This final artifact separately passed Debian 12/arm64 MRI 4.0.9 packaging: 13 payload / 10 ordinary-loaded product files / 118 installed cases. It differs from PR #213's earlier 32,256-byte candidate; source190/885 were not rerun in this packaging step. See [0.2.0 publication record](docs/PROJECT_STATUS.md#020公開済み--現在の配布状態) for evidence and limits.
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
