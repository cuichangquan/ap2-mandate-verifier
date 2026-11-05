# Changelog

## 1.6.0 candidate — bounded repeated Payment approval

- Explicit complete/selective JPY integer / ON_DEMAND finite recurrence/budget profiles.
- Optional new-schema durable series store charges count and amount atomically with occurrence reservation; no retry/unknown/Error allowance refund.
- Preserve1.x defaults, schema1 storage, seven-input contract and600second lifetime. Calendar frequency and non-JPY budgets deferred; see docs/RECURRING_PAYMENT.md.
- Unpublished; Owner release decision required.

## 1.5.0 — Unreleased candidate

- Add opt-in transactional Payment acceptance with protected authorization/occurrence enrollment, stable business-operation identity, atomic reservation and fenced processing transitions.
- Preserve first signed wires, processor idempotency key and Receipt binding across retries/re-signing; unknown outcomes never automatically reopen.
- Add an optional durable SQLite reference adapter, fresh full verification before start, concurrency/crash/restart examples and diagnostics. Existing1.x verifier defaults and base runtime dependencies remain unchanged.
- Publication remains reserved for Owner decision.

## 1.4.0 — Unreleased candidate

- Add explicit complete/selective Payment profiles for allowed PISP and execution-date constraints, with independently trusted provider/execution context.
- Parse execution instants strictly and enforce inclusive bounds without lexical comparison; keep new conditions fully visible.
- Integrate Direct/conditional Payment, selective Checkout/Payment and exact Payment Receipt references while preserving existing1.x defaults.
- Publication remains reserved for Owner judgment after exact candidate verification.

## 1.3.0 — Unreleased candidate

- Add an explicit selective Checkout profile that discloses selected merchant and product candidates while retaining every mandatory requirement and quantity.
- Preserve full Host trust/challenge/order verification and integer maximum-flow quantity coverage.
- Integrate selective Checkout with selective Payment, exact original-wire references and both Receipt lifecycles.
- Preserve existing complete profiles and default APIs; publication remains subject to Owner judgment.

## 1.2.0 — 2026-11-03

- Add explicit conditional `SelectivePayment` candidate-array disclosure with payee-only/instrument-only/both modes, exact reduced-wire delegation, mandatory-condition closure and Cartesian approval guard.
- Add privacy/signed-negative/original-wire tests, honest pinned SDK profile-adapter interoperability, installed Ruby example and candidate preparation. Existing1.1.0 defaults/formats/Receipt references remain unchanged.
- Detach mutable Agent-key inputs and recheck copied Checkout time consistently in Payment verification/issuance; preserve API signatures and safe accepted formats.


## 1.1.0 — 2026-11-03

- Add Direct and one-hop conditional Payment issuance, presentation and complete verification with original Checkout binding and strict amount/payee/instrument/fixed-value checks.
- Add signed Success/Error Payment Receipts, independent issuer/payment ID/time/reference verification, and separate authenticity/outcome predicates.
- Add framework-independent installed Ruby sample, pinned official SDK/Schema interoperability tests, and release preparation. Existing 1.0.0 Checkout contracts remain unchanged.


## 1.0.0 — 2026-11-01

- Defines the supported public API and 1.x compatibility, deprecation and
  maintenance policies for the framework-independent AP2 Ruby SDK. The scope
  includes Merchant Checkout JWTs, Direct and conditional Checkout Mandates,
  complete verification and immutable Evidence, and Success/Error Receipts.
- Preserves the 0.8.0 runtime implementation, existing API/status/error meanings,
  profile identifiers/defaults, saved formats, five dependency pins and formally
  supported MRI 3.4.12 / 4.0.9. No application migration is required for documented
  0.8.0 APIs; the Gem dependency constraint must allow 1.0.0.
- Updates SDK metadata, current security/support/product guidance and candidate
  package checks. Adds independent Python-generated conditional inputs through
  the installed Gem's public complete verification and Receipt APIs.
- Published 08:13:29.733 UTC; official distribution comparison completed 08:16:01
  UTC. The 102,912-byte download SHA256
  `a107101b0178c54ba417be7a2bd7e22feb2fd9a07bda089043e8c5ea8e65e12b`
  matches the retained candidate and all 33 payloads match release source
  `59e344ad865ed867d0993120456f9411d82bcdec`.
  [Release and upgrade](docs/RELEASE_100.md), [publication](docs/POST_RELEASE_100.md).
  The [candidate record](docs/RELEASE_100_CANDIDATE.md) retains its historical scope.

## 0.8.0 — 2026-11-01

- Adds public `ConditionalCheckout.issue_open/issue_closed/present` for one merchant,
  1–8 requirements/candidates/lines, exact quantities, candidate choice and repeated
  product rows under the unchanged multi-item profile. Agent uses its own signer;
  Open completeness, cnf, Merchant signature and conditions are checked first.
- Preserves original Open/terminal/Checkout bytes and normative Receipt reference
  to only the final inline Closed SD-JWT, including its trailing `~`.
- Includes a standalone installed-Gem example through full merchant Evidence and
  both Receipt outcomes, English/Japanese Quick Start and release instructions.
  Existing profiles, Direct, saved formats, Result/Evidence, diagnostic contracts,
  dependency pins and supported Rubies are unchanged.
- Published 06:01:31.103 UTC; official comparison 06:03:20 UTC. The 79,872-byte
  download SHA256 `6c07664e4291aa8bc025b152075869322411a0d99861e1267959f1794e99acec`
  and all29 payloads match source `5a7394c1b98f000b321423e2c2f80d50b5157808`.
  [Release](docs/RELEASE_080.md), [publication](docs/POST_RELEASE_080.md).
  Repository-only guide updates do not rebuild or replace the published bytes.

## 0.7.0 — 2026-11-01

- Adds `CheckoutJWT.verify` and optional `Buyer.issue_closed/present_closed/verify` for Trusted Agent Provider / Direct Human Present exact-order approval. Supports one merchant and 1–8 lines with multiple products throughout issuance, presentation, merchant verification and Receipt confirmation.
- Adds explicit Direct Receipt profile preserving both disclosures and terminal `~` in the original-wire reference. Requires independently registered keys, protected app approval bytes, supported commitment closure and explicit time/order checks; failures do not grant authorization.
- Existing two profiles, Result/Evidence, saved inputs, supported MRI and dependencies retain their contracts. Open issuance/Agent Closed generation remain follow-up candidates.
- Published 03:12:46.522 UTC; official verification 03:14:04 UTC. Exact 64,000-byte candidate SHA256 `baab8c68355b5e6c9351e7d86a836fab50652cdad662bbc99d1676c5e6134447` matches source `9b4b78a7ed9aa95e7d35e01a64efc1281ba95be3` across all 24 payloads. [Release](docs/RELEASE_070.md), [publication](docs/PROJECT_STATUS.md#070-publication). Follow-up guides do not rebuild/replace the published Gem.

## 0.6.0 — 2026-10-31

- Adds explicitly selected `ap2.checkout.single_merchant_multi_item` v1 for a single merchant/Checkout/currency with up to eight lines, eight requirements and eight candidates per requirement. Integer maximum flow consumes all requirement and checkout quantities without double allocation; repeated product IDs on distinct lines and overlapping candidates are supported.
- Propagates authenticated profile selection through InputBuilder preparation/restoration/current-state verification, Checkout signing, complete Mandate verification, Evidence and Checkout Success/Error Receipts. Preserves original signed bytes and saved challenge references; every supported candidate disclosure is required.
- Keeps the old single-SKU v1 identifier/body/hash/acceptance range and default APIs, Result/status/code, diagnostic/Evidence semantics, formal MRI versions and runtime pins. Product Mandate issuance, payment and Host authorization remain separate.
- Initial preparation, review, CI and final candidate installation were separate from Owner publication approval. Published at 11:50:18.664 UTC; official distribution comparison completed 11:51:54 UTC. The 56,832-byte Gem, SHA256 `ff669a62717f91b2295b3cea1b68c6c4143c490d98df071fd322ad4b0007195d`, matches source `baee59a603d08123adc0af50e57c8710ea62f4f9` across all 22 payload files. [Publication record](docs/PROJECT_STATUS.md#060-publication). Repository-only follow-up documentation does not replace the published bytes.

## 0.5.0 — 2026-10-31

- Adds Merchant `CheckoutJWT.sign` with an application-owned ES256/P-256 signer, independently checked public key, immutable transmitted JWT and original-wire hash.
- Adds Checkout-specific `CheckoutReceipt.sign`, `.reference` and `.verify`; independently checks trusted key, expected issuer, explicit time policy and exact final inline closed SD-JWT reference. Authentic Success/Error and verification failure are distinct.
- Adopts Checkout Schema status/iat and normative sd_hash reference semantics; documents generic result spelling and SDK leaf-helper differences. Requires explicit `<terminal_jws>~`, rejects unsupported disclosures/hops/algorithms. Existing verifier, Evidence, status/code, InputBuilder, diagnostics and dependency pins are unchanged.
- Initial preparation included synthetic bidirectional official Python SDK signature/Schema/reference tests, original-wire and negative checks, documentation, an unpublished release draft and an opt-in local demo. That preparation did not authorize publication or production; the publication record below supersedes the candidate distribution status.

- Published at 07:26:21.576 UTC; official distribution comparison completed 07:29:21.200455 UTC. 50,688 bytes, SHA256 `00b0ce0981070864c67a056906c5af204bbc5aaa80d029cb4a64294634367dd8`, source `bf796a53600c189b0cfe66c9cfcd1de8a353c03d`. All 21 payload files match the approved source. [Publication record](docs/PROJECT_STATUS.md#050-publication). Post-publication repository documentation does not alter the published Gem.

## 0.4.0 — 2026-10-31

- Adds immutable, input-free `Result#diagnostic` and `InputBuilder::Invalid#diagnostic`, machine stage/field/reason identifiers and English/Japanese hints. Success has no failure diagnostic; diagnostic failure cannot change a verdict.
- Identifies known Builder missing/type/unknown-field/saved-format failures; existing status/code and all verification/Evidence contracts remain unchanged. Adds boundary, dependency, redaction and installed-package coverage plus runnable examples and guides.
- Published on RubyGems at 04:25:06.427 UTC; exact download comparison at 04:26:15 UTC matched the reviewed 44,032-byte candidate, SHA256 `b212db01e7deb18dcef1199414f9d93ef43cb1f74b62baa55306de3955dfe177`, source `fc42852f53c615f96d7c165a8de494b24b252519`. Runtime pins, fixed profile and production/real-Issuer/Host/Phase 2-B HOLDs remain. [Publication record](docs/PROJECT_STATUS.md#040-publication).

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
