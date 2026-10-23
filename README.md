# AP2 Mandate Verifier for Ruby

## 固定profile・研究用途限定pre-release候補 — 0.1.0.pre.2

MRI Ruby4.0.8向け、固定profile `ap2.checkout.single_merchant_sku` version1の
stateless verifierです。署名・原Root全域開示・委任・購入原文・Host binding・固定制約・
有効期間がすべて成立したとき、opt-in `verify_research`が不変な研究Evidence v2を返します。
**Evidenceは購入許可・nonce消費・決済完了ではありません。**

候補の対応契約・入力・API・依存・資源境界は[SUPPORT_CONTRACT](docs/SUPPORT_CONTRACT.md)を参照。
Ownerは固定profile・研究用途限定の公開方針に同意済みです。実配布は別の明示承認待ちで、RubyGemsへ公開していません。stable release・本番・Phase2-A全面合格・Phase2B・E10全面GOではありません。

支持範囲はES256/P256、Root Open1→Agent terminal内Closed1、3開示位置、単一Merchant/SKU、
USD/EUR/JPY、空links。一般AP2/全Schema/任意Issuerの互換性は保証しません。
実Issuer/鍵/profile登録・最新性・信頼時計と、最新注文/challenge再照合＋原子的nonce消費・
注文CAS・決済はHost責務です。GemはDB・ネットワーク・支払いを実行しません。

```ruby
require "ap2_mandate_verifier"

result = AP2MandateVerifier.verify_research(**inputs) # authenticated Host inputs + original signed wires
if result.success?
  checked_facts = result.evidence.to_h # deeply frozen; in-process evidence only
  # Host still must recheck latest state/time and atomically consume nonce/order.
else
  # rejected / unavailable: stop; result.evidence is nil
end
```

`inputs`はtrust_json/selection_json/host_json/root_presentation/terminal_jws/
host_checkout_jws/verified_atです。前3つのJSONは認証済みの独立Host入力として渡し、
提示tokenの自己申告から信頼を追加しません。raw nonceは入力専用、EvidenceにはSHA256だけを
投影します。Hash/JSONへ書き出したものを真正なEvidenceとして再入力するAPIはありません。

旧`verify`はJSON構文境界だけで、その他の低レベルverify入口と共にsuccess?=false/
evidence=nilを維持します。呼出し例のsuccess?を旧APIへ流用してはいけません。

## 支持環境・検証結果の区別

本候補はMRI Ruby4.0.8、JSON2.19.9、JWT3.3.0、base640.3.0、OpenSSL gem4.0.2、Digest3.2.1を固定。
MBAの新RubyでOpenSSLとDigestのdefault gem、libcrypto3.5.9、resolv0.7.2、zlib3.2.3をロード確認し、ソース回帰885件が合格しました。JSON2.19.9を別導入して同梱JSON2.18.0を使用しません。この候補はnative binaryを同梱しません。
Rubyの任意DTrace/USDT診断プローブは公式--disable-dtrace構成で無効です。新環境の記録は`MBA408-20261023-BUILD01`（DTrace拒否）、`BUILD02`（監視停止・終了結果未確定）、`BUILD03`（導入成功）として区別します。旧包装のR1/R2/R3ではありません。対応する`MBA408-20261023-VALIDATION01`と文書修正後の`PACKAGE02`のsource/report参照は[契約文書の証拠識別表](docs/SUPPORT_CONTRACT.md#evidence-identifiers-for-this-runtime-update)を参照してください。Linuxでの新版検証は未実施です。
新候補の解決環境は同梱Bundler4.0.20です。Gemの追加runtime依存ではありません。Ruby4.0.1/Bundler4.0.3の保存観測は歴史証拠です。
ライブラリのwall-clock/RSS/並行数上限はなく、Hostが運用上の制限を設ける必要があります。

基準main `8d9845ff4b5618b9e57eda86d3a1e447d4124b47`では、MBA Darwin arm64と
Ubuntu24.04 x86_64で885回帰・42固定入力の再現を観測しました。
[Linux run39774818984](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/39774818984)は
MBA独立期待値30＋境界12のGem再入力であり、Linux Oracle再実行ではありません。
8Schema対照はMBA根拠です。この未公開0.1.0.pre.2の包装/導入結果とは別の観測で、
旧manifest/pin/結果は更新していません。候補の新結果はローカル別保存、配布物には含めません。

これまでの取得量未証明2件とLinux全通信128MiB未証明を保持します。追加Actionsは不許可。
研究資料はresearch/配下へ整理済みです。独自runtime/supervisorの開発へ戻りません。

旧0.1.0.pre.2の実パッケージは[Stage18 run39869876461](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/39869876461)で885回帰・installed52・13payload/10loadedを観測しました。[Stage21追補](https://github.com/cuichangquan/ap2-mandate-verifier/blob/c8d81eab49e37a1236a355d42cf667aab552392d/docs/STAGE21_VALIDATION_SUPPLEMENT.md)はMBAの7入力×3観測と既知の限界を記録しています。これらはRuby4.0.1での歴史観測で、新runtime候補のLinux実証ではありません。新候補のローカル報告は別保存し、旧artifactと同じSHAとは主張しません。

## 研究資料（履歴）

以下の図・研究文書の状態欄やNOT_RUNは各作成時点の記録です。現在の候補契約に優先せず、
配布Gemには研究コード・fixture・図・過去結果を含めません。リンク先はリポジトリ上の資料です。

> 非公式・独立した研究プロジェクトです。Google、AP2 プロジェクト、FIDO Alliance とは関係ありません。

## AP2を図で理解する / Visual guides

手書きの学習用図解です。概念を理解するための資料であり、仕様の正式な要件は [AP2 v0.2 仕様基準点](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/SPEC_BASELINE.md) を参照してください。

**まずは全体像**

- [① AP2規格の全体像](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/assets/ap2-overview.png)
- [② AP2の委任フローと信頼検証](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/assets/ap2-delegation-trust-flow.png)

**次に内部構造と安全性**

- [③ Mandateの内部構造](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/assets/mandate-anatomy.png)
- [④ SD-JWTと委任チェーンの仕組み](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/assets/sd-jwt-delegation-chain.png)
- [⑤ 攻撃パターンとFail Closed](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/assets/attack-patterns-fail-closed.png)

![AP2規格の全体像（手書き解説）](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/assets/ap2-overview.png)

## Why?

A future personal AI could arrive at a web service carrying evidence of authority granted by a person, without that person pre-configuring every service. **A self-declared permission is not proof of authority.** The service needs verifiable evidence, an explicit trust policy, and its own final authorization decision.

This project explores **AP2 v0.2 Checkout Mandate verification in Ruby**, initially on the merchant/verifier side, to see whether a small reusable Ruby Gem is justified.

```text
Human user -- trusted consent/mandate --> Personal AI
                                            |
                                            | presents external mandate
                                            v
                                        Ruby service
                                            |
                                [AP2 Mandate Verifier]
                                            |
                         verified evidence / verification failure
                                            |
                         Service's own authorization and controls
                                            |
                                   Business action or STOP
```

A valid digital signature does **not** by itself establish that this Agent is authorized for this specific user, operation, merchant, price, or moment.

## Proposed initial scope

- Study AP2 **v0.2** Agent Authorization and Checkout Mandate; do not mix in the earlier v0.1 model.
- Explore cryptographic verification, trusted issuer/keys, holder/Agent binding, transaction binding, Open/Closed mandate constraints, audience, time, and failure cases.
- Compare behavior and test vectors with the official AP2 Python implementation before claiming interoperability.
- Expose verified evidence to the **host**; do not replace the host's authorization or payment controls.
- The fixed-profile implementation exists; this prerelease candidate is unpublished and production/distribution remain HOLD.

## Explicit non-goals

- Building a wallet, user credential issuer, payment processor, trusted consent UI, Personal AI, MCP server, or A2A transport.
- Supporting all AP2 flows or production payments in the first iteration.
- Assuming all unknown issuers or self-asserted permissions are trustworthy.
- Changing ActingFor Core, ActingFor Shopping Demo or a2a-rails.

## Research documentation

- [Project scope and design decisions — Japanese](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/PROJECT.md)
- [Official AP2 sources and standards watchlist](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/OFFICIAL_SOURCES.md)
- [AP2 v0.2 frozen specification and Python SDK baseline](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/SPEC_BASELINE.md)
- [AP2 Checkout Mandate verifier requirements and trust boundaries (P0-2)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/VERIFIER_REQUIREMENTS.md)
- [Official Python SDK and Ruby ecosystem research (P0-3)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/ECOSYSTEM_RESEARCH.md)
- [Minimal Checkout Verifier public API proposal — design only (P0-4)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/API_PROPOSAL.md)
- [Phase 0 research decision — initial HOLD, **P0-5b CONDITIONAL GO for a narrow offline PoC only**](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/RESEARCH_DECISION.md)
- [Python baseline verification — P0-5a: official pytest 186 PASS / 2 FAIL, signed negative probes 12 PASS (plus earlier isolated 11 PASS)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/PYTHON_BASELINE_VERIFICATION.md)
- [Minimal Fail Closed Profile — strict two-hop autonomous Checkout and Host trust gates (P0-5b)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/FAIL_CLOSED_PROFILE.md)
- [Ruby interoperability feasibility — P1-0 ES256/JWK + Checkout Hash + official schema: 14 PASS](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/RUBY_FEASIBILITY_SPIKE.md)
- [Ruby SD-JWT Root & Disclosure — P1-1 pinned Python SDK issuance, hidden constraint fail closed: 10 PASS](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/RUBY_SDJWT_RESEARCH.md)
- [Ruby two-hop delegation — P1-2 pinned Python signed Open→Closed, cnf/sd_hash/aud/nonce: 15 PASS](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/RUBY_DELEGATION_SPIKE.md)
- [Ruby Merchant Checkout binding — P1-3 signed Checkout JWT, Host exact bytes, hash, restricted merchant/SKU/quantity/amount: 18 PASS](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/RUBY_CHECKOUT_BINDING_SPIKE.md)
- [Security Gap Review — P1-4 12 ranked risks, 6 gates, generic Gem implementation HOLD](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/SECURITY_GAP_REVIEW.md)
- [Signed Security Negative Observations — P1-5 18 probes, **6 RED / 11 GREEN / 1 Host boundary**](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/SECURITY_NEGATIVE_TESTS.md)
- [Security Hardening Research — P1-6 fixed six prior REDs: **0 RED, 17 GREEN, 43 historical regressions passed**](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/SECURITY_HARDENING_RESEARCH.md)
- [Host Security Contract — P1-7 Host trust, VerifiedEvidence vs ALLOW, nonce atomicity, revocation and Receipt (design only)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_SECURITY_CONTRACT.md)
- [Host Security Test Plan — P1-7 34 planned race, trust, context and Receipt cases (NOT run)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_SECURITY_TEST_PLAN.md)
- [Host Replay Lab Design — P1-8 PostgreSQL 16, two workers, crash/retry test plan (DESIGN ONLY, NOT RUN)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_REPLAY_LAB_DESIGN.md)
- [Host Replay PG16 Evidence — P1-9a four isolated Host DB cases PASS; remaining 30 NOT RUN](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_REPLAY_P19A_EVIDENCE.md)
- [Host Crash Recovery Evidence — P1-9b HR04/HR05 real SIGKILL and durable PG recovery; 6/34 Host cases exercised](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_REPLAY_P19B_EVIDENCE.md)
- [Host Unknown COMMIT / Mock Provider Evidence — P1-9c HR06/HR07 offline only, 8/34 Host cases executed](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_REPLAY_P19C_EVIDENCE.md)
- [Host Checkout/Revocation Race — P1-10a HR10 four PG16 interleavings PASS; 9/34 Host case IDs (research only)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_REPLAY_P110A_EVIDENCE.md)
- [HC06 External Revocation Design — P1-10b authority consistency, TOCTOU and negative tests (design only, NOT RUN)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_EXTERNAL_REVOCATION_HC06_DESIGN.md)
- [HC06 Offline Synthetic Evidence — P1-10c eight model tests, two expected unsafe counterexamples; not a full HC06 proof](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_EXTERNAL_REVOCATION_P110C_EVIDENCE.md)
- [HC06 Cross-Service Protocol Design — P1-10d Authority reservations, durable Host COMMIT, revocation timing and failure matrix (DESIGN ONLY)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_EXTERNAL_REVOCATION_P110D_PROTOCOL.md)
- [HC06 Independent Failure-Injection Test Plan — P1-10e revocation during reservation, unknown COMMIT, reservation timeout (DESIGN ONLY, NOT RUN)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_EXTERNAL_REVOCATION_P110E_TEST_PLAN.md)
- [HC06 Minimal Independent Harness Decision — P1-10f E-R01/R02 local two-process/two-PG16 feasibility assessment (DESIGN ONLY, NOT RUN)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_EXTERNAL_REVOCATION_P110F_HARNESS_DECISION.md)
- [HC06 Independent PG16 Synthetic Evidence — P1-10g E-R01/R02 2 runs / 118 assertions, Host abort SIGKILL; distributed HC06 HOLD](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_EXTERNAL_REVOCATION_P110G_EVIDENCE.md)
- [HC06 Authority Finalize Proof-Boundary Review — P1-10h trusted Host decision, forged/replayed reports and PENDING on uncertainty (DESIGN ONLY, NOT RUN)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_EXTERNAL_REVOCATION_P110H_PROOF_BOUNDARY_REVIEW.md)
- [HC06 Synthetic Authority Evidence Negatives — P1-10i H01 unsafe baseline + guarded STOP, H02–H06 limited checks (6 runs / 178 assertions, distributed HC06 HOLD)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_EXTERNAL_REVOCATION_P110I_EVIDENCE.md)
- [HC06 Independent Authority Proof Feasibility Decision — P1-10j no direct Host DB, authenticated durable decision prerequisites, anti-rollback and Fail Closed (DESIGN ONLY)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_EXTERNAL_REVOCATION_P110J_DECISION.md)
- [HC06 Host–Authority Contract Checklist — P1-10k C01–C12 roles, evidence required, hard STOP gates; all OPEN/UNCONFIRMED (DESIGN ONLY)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_EXTERNAL_REVOCATION_P110K_CONTRACT_CHECKLIST.md)
- [AP2 v0.2.0 Official Spec/SDK Mapping — P1-10l C01–C12 vs Mandate, Checkout, Receipt (fixed SHA; SUPPORTED vs NOT SPECIFIED vs UNKNOWN; READ-ONLY)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HOST_EXTERNAL_REVOCATION_P110L_AP2_SPEC_MAPPING.md)
- [Verifier vs Host/Authority Revocation — P1-10m scope and GO/HOLD gates (A: cryptographic evidence; B: strong HC06 revocation; DESIGN ONLY)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/VERIFIER_VS_REVOCATION_P110M_SCOPE.md)
- [Strict A-only Offline Ruby PoC GO/HOLD Reassessment — P1-10n G01–G08 and 8 planned acceptance cases, unrun at that step (DESIGN ONLY)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/VERIFIER_P110N_OFFLINE_POC_GATE.md)
- [A-only Signed Offline Acceptance — P1-10o AN-P01/AN-N01–N07 (8 runs / 45 assertions, signed claim drift rejected, N07 HOST_BOUNDARY; SYNTHETIC ONLY)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/VERIFIER_P110O_EVIDENCE.md)
- [A-only Verifier Residual Gap Review — P1-10p issuer layout, unknown nested Constraint fields and GP01–GP09 priorities (DESIGN ONLY / all new tests NOT RUN at P1-10p)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/VERIFIER_P110P_RESIDUAL_GAPS.md)
- [GP01 Signed Unknown Nested Constraint — P1-10q historic pre-fix unexpected ACCEPT / RED-HOLD (1 synthetic run / 8 assertions)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/VERIFIER_P110Q_GP01_EVIDENCE.md)
- [GP01 Fixed-Issuer Nested Constraint Allowlist — P1-10r: historic RED to bounded REJECT + signed positive, dedicated 2 runs / 10 assertions (RESEARCH ONLY)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/VERIFIER_P110R_GP01_FIX_EVIDENCE.md)
- [Signed Constraint Shape and Value-Type Residual Gaps — P1-10s: S01–S08, including requirement ID and Merchant name types (DESIGN ONLY, all new cases NOT RUN)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/VERIFIER_P110S_CONSTRAINT_SHAPE_TYPE_GAPS.md)
- [S01 Signed Requirement ID Type Mismatch — P1-10t: latest corrected observer local Docker signature VALID, official Schema INVALID, Ruby ACCEPT / RED-HOLD (1 run / 6 assertions; earlier 1/7 historical; no CI)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/VERIFIER_P110T_S01_PREPARED_NOT_RUN.md)
- [P1-10u signed S01 String type check + separate signed positive regression — PR #42, Mac Docker 2 runs / 12 assertions / 0 failures: signed S01 exact-type REJECT and known-good evidence-only ACCEPT; dedicated CI NOT RUN, general Gem/production HOLD](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/VERIFIER_P110U_S01_TYPE_FIX_PREPARED_NOT_RUN.md)
- [Research phases and release gates](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/RESEARCH_PLAN.md)
- [Phase 1研究総括とPhase 2-A設計GO/HOLD判断 — 当時の引き継ぎ記録 / Historical handoff](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/PHASE1_RESEARCH_CLOSURE_PHASE2_GATE.md)
- [Phase 2-A 最小Merchant Verifier設計パッケージ — Issue #45 / PROPOSED / DESIGN ONLY / 未実装・新規テストNOT RUN](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/PHASE2A_MINIMAL_VERIFIER_DESIGN.md)
- [Phase 2-A Issuer/SD-JWT権限制約の開示完全性Gate — Issue #47 / DESIGN ONLY / 未検証・Phase 2-B HOLD](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/PHASE2A_DISCLOSURE_COMPLETENESS_GATE.md)
- [Phase 2-A DC01–DC05 独立署名オラクル実験計画 — Issue #47 / DESIGN ONLY / 全ケースNOT RUN](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/PHASE2A_DC01_DC05_SIGNED_ORACLE_PLAN.md)
- [Historical P1-10u signed S01 fixed-observer evidence and completed local Docker 2/12 (merged PR #42)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/VERIFIER_P110U_S01_TYPE_FIX_PREPARED_NOT_RUN.md)
- [Historical P1-10t new-chat handoff — proposes P1-10u and is now superseded; do not rerun as current instructions](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/VERIFIER_P110T_S01_PREPARED_NOT_RUN.md#5-新チャット引き継ぎ次の作業2026-10-12)
- [Historical project-wide handoff — Japanese (P1-10r era; P1-10s next-task text not yet updated)](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/HANDOFF.md)
- [Trust model and security boundaries](https://github.com/cuichangquan/ap2-mandate-verifier/blob/8d9845ff4b5618b9e57eda86d3a1e447d4124b47/docs/SECURITY_BOUNDARY.md)

## Primary official references

- [AP2 Specification](https://ap2-protocol.org/ap2/specification/)
- [AP2 Agent Authorization](https://ap2-protocol.org/ap2/agent_authorization/)
- [AP2 Checkout Mandate](https://ap2-protocol.org/ap2/checkout_mandate/)
- [AP2 official source / Python SDK](https://github.com/google-agentic-commerce/AP2)
- [FIDO Alliance Agentic AI initiative](https://fidoalliance.org/fido-alliance-agentic-ai/)

## Relationship to other OSS

- [ActingFor](https://github.com/cuichangquan/acting_for): Rails-native delegated authorization using host-resolved identities and locally stored delegations.
- [a2a-rails](https://github.com/cuichangquan/a2a-rails): A2A protocol integration for Rails. It does not verify AP2 Mandates.

Both are **separate projects**. Integration comes after the verification contract is proven.

## 日本語

分身AIが外部サービスに持ち込む**検証可能な委任証明**を、Ruby側でどこまで安全に検証できるかを研究するリポジトリです。AP2 v0.2のCheckout Mandateから調査します。署名確認だけで購入を許可したり、未知の発行者を無条件に信用したりしません。固定profileの限定Gem候補をローカル検証中です。配布・本番利用・Phase2BはHOLDです。

## License

MIT. See [LICENSE](LICENSE).
