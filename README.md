# AP2 Mandate Verifier for Ruby

## 開発状況（2026-10-17）

- **目指すもの：** AP2 v0.2 の委任証明を検証し、購入可否を判断するサービス側へ検証結果を渡す、小さな Ruby Gem。
- **現在地：** Phase 2-A の研究・実験環境を準備中です。研究用コードはありますが、Gem 本実装の完成には至っていません。
- **準備できたこと：** 固定した公式 AP2 ソースの照合と、隔離用 Git スナップショットの構築・検査（[U1 #141](https://github.com/cuichangquan/ap2-mandate-verifier/pull/141)／[U2 #142](https://github.com/cuichangquan/ap2-mandate-verifier/pull/142)）を main に統合しました。静的レビューや限定的なローカル検証の結果であり、実行環境全体の安全性を保証するものではありません。
- **次の作業：** [通信処理 U3](https://github.com/cuichangquan/ap2-mandate-verifier/pull/143) と [U2 の後処理修正](https://github.com/cuichangquan/ap2-mandate-verifier/pull/144) のレビューを終え、承認範囲内で実通信・実行環境を確認します。[6 ケース実測の準備 #136](https://github.com/cuichangquan/ap2-mandate-verifier/pull/136) は未マージで、6 ケース実測は HOLD です。

**安全性の最終判定は未完了です。** 署名付き入力・独立した検証結果を揃え、[Phase 2-A の終了条件](docs/PHASE2A_EXIT_GATE_DECISION_CHECKLIST.md)を評価してから、Owner が次段階への移行を判断します。Phase 2-B・Gem 本実装／公開・本番利用は HOLD、実決済は NO-GO です。購入の最終許可や nonce・失効管理はサービス側の別責務です。

> 非公式・独立した研究プロジェクトです。Google、AP2 プロジェクト、FIDO Alliance とは関係ありません。

## AP2を図で理解する / Visual guides

手書きの学習用図解です。概念を理解するための資料であり、仕様の正式な要件は [AP2 v0.2 仕様基準点](docs/SPEC_BASELINE.md) を参照してください。

**まずは全体像**

- [① AP2規格の全体像](docs/assets/ap2-overview.png)
- [② AP2の委任フローと信頼検証](docs/assets/ap2-delegation-trust-flow.png)

**次に内部構造と安全性**

- [③ Mandateの内部構造](docs/assets/mandate-anatomy.png)
- [④ SD-JWTと委任チェーンの仕組み](docs/assets/sd-jwt-delegation-chain.png)
- [⑤ 攻撃パターンとFail Closed](docs/assets/attack-patterns-fail-closed.png)

![AP2規格の全体像（手書き解説）](docs/assets/ap2-overview.png)

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
- Start with a design and security review. No Gem implementation has been approved yet.

## Explicit non-goals

- Building a wallet, user credential issuer, payment processor, trusted consent UI, Personal AI, MCP server, or A2A transport.
- Supporting all AP2 flows or production payments in the first iteration.
- Assuming all unknown issuers or self-asserted permissions are trustworthy.
- Changing ActingFor Core, ActingFor Shopping Demo or a2a-rails.

## Research documentation

- [Project scope and design decisions — Japanese](docs/PROJECT.md)
- [Official AP2 sources and standards watchlist](docs/OFFICIAL_SOURCES.md)
- [AP2 v0.2 frozen specification and Python SDK baseline](docs/SPEC_BASELINE.md)
- [AP2 Checkout Mandate verifier requirements and trust boundaries (P0-2)](docs/VERIFIER_REQUIREMENTS.md)
- [Official Python SDK and Ruby ecosystem research (P0-3)](docs/ECOSYSTEM_RESEARCH.md)
- [Minimal Checkout Verifier public API proposal — design only (P0-4)](docs/API_PROPOSAL.md)
- [Phase 0 research decision — initial HOLD, **P0-5b CONDITIONAL GO for a narrow offline PoC only**](docs/RESEARCH_DECISION.md)
- [Python baseline verification — P0-5a: official pytest 186 PASS / 2 FAIL, signed negative probes 12 PASS (plus earlier isolated 11 PASS)](docs/PYTHON_BASELINE_VERIFICATION.md)
- [Minimal Fail Closed Profile — strict two-hop autonomous Checkout and Host trust gates (P0-5b)](docs/FAIL_CLOSED_PROFILE.md)
- [Ruby interoperability feasibility — P1-0 ES256/JWK + Checkout Hash + official schema: 14 PASS](docs/RUBY_FEASIBILITY_SPIKE.md)
- [Ruby SD-JWT Root & Disclosure — P1-1 pinned Python SDK issuance, hidden constraint fail closed: 10 PASS](docs/RUBY_SDJWT_RESEARCH.md)
- [Ruby two-hop delegation — P1-2 pinned Python signed Open→Closed, cnf/sd_hash/aud/nonce: 15 PASS](docs/RUBY_DELEGATION_SPIKE.md)
- [Ruby Merchant Checkout binding — P1-3 signed Checkout JWT, Host exact bytes, hash, restricted merchant/SKU/quantity/amount: 18 PASS](docs/RUBY_CHECKOUT_BINDING_SPIKE.md)
- [Security Gap Review — P1-4 12 ranked risks, 6 gates, generic Gem implementation HOLD](docs/SECURITY_GAP_REVIEW.md)
- [Signed Security Negative Observations — P1-5 18 probes, **6 RED / 11 GREEN / 1 Host boundary**](docs/SECURITY_NEGATIVE_TESTS.md)
- [Security Hardening Research — P1-6 fixed six prior REDs: **0 RED, 17 GREEN, 43 historical regressions passed**](docs/SECURITY_HARDENING_RESEARCH.md)
- [Host Security Contract — P1-7 Host trust, VerifiedEvidence vs ALLOW, nonce atomicity, revocation and Receipt (design only)](docs/HOST_SECURITY_CONTRACT.md)
- [Host Security Test Plan — P1-7 34 planned race, trust, context and Receipt cases (NOT run)](docs/HOST_SECURITY_TEST_PLAN.md)
- [Host Replay Lab Design — P1-8 PostgreSQL 16, two workers, crash/retry test plan (DESIGN ONLY, NOT RUN)](docs/HOST_REPLAY_LAB_DESIGN.md)
- [Host Replay PG16 Evidence — P1-9a four isolated Host DB cases PASS; remaining 30 NOT RUN](docs/HOST_REPLAY_P19A_EVIDENCE.md)
- [Host Crash Recovery Evidence — P1-9b HR04/HR05 real SIGKILL and durable PG recovery; 6/34 Host cases exercised](docs/HOST_REPLAY_P19B_EVIDENCE.md)
- [Host Unknown COMMIT / Mock Provider Evidence — P1-9c HR06/HR07 offline only, 8/34 Host cases executed](docs/HOST_REPLAY_P19C_EVIDENCE.md)
- [Host Checkout/Revocation Race — P1-10a HR10 four PG16 interleavings PASS; 9/34 Host case IDs (research only)](docs/HOST_REPLAY_P110A_EVIDENCE.md)
- [HC06 External Revocation Design — P1-10b authority consistency, TOCTOU and negative tests (design only, NOT RUN)](docs/HOST_EXTERNAL_REVOCATION_HC06_DESIGN.md)
- [HC06 Offline Synthetic Evidence — P1-10c eight model tests, two expected unsafe counterexamples; not a full HC06 proof](docs/HOST_EXTERNAL_REVOCATION_P110C_EVIDENCE.md)
- [HC06 Cross-Service Protocol Design — P1-10d Authority reservations, durable Host COMMIT, revocation timing and failure matrix (DESIGN ONLY)](docs/HOST_EXTERNAL_REVOCATION_P110D_PROTOCOL.md)
- [HC06 Independent Failure-Injection Test Plan — P1-10e revocation during reservation, unknown COMMIT, reservation timeout (DESIGN ONLY, NOT RUN)](docs/HOST_EXTERNAL_REVOCATION_P110E_TEST_PLAN.md)
- [HC06 Minimal Independent Harness Decision — P1-10f E-R01/R02 local two-process/two-PG16 feasibility assessment (DESIGN ONLY, NOT RUN)](docs/HOST_EXTERNAL_REVOCATION_P110F_HARNESS_DECISION.md)
- [HC06 Independent PG16 Synthetic Evidence — P1-10g E-R01/R02 2 runs / 118 assertions, Host abort SIGKILL; distributed HC06 HOLD](docs/HOST_EXTERNAL_REVOCATION_P110G_EVIDENCE.md)
- [HC06 Authority Finalize Proof-Boundary Review — P1-10h trusted Host decision, forged/replayed reports and PENDING on uncertainty (DESIGN ONLY, NOT RUN)](docs/HOST_EXTERNAL_REVOCATION_P110H_PROOF_BOUNDARY_REVIEW.md)
- [HC06 Synthetic Authority Evidence Negatives — P1-10i H01 unsafe baseline + guarded STOP, H02–H06 limited checks (6 runs / 178 assertions, distributed HC06 HOLD)](docs/HOST_EXTERNAL_REVOCATION_P110I_EVIDENCE.md)
- [HC06 Independent Authority Proof Feasibility Decision — P1-10j no direct Host DB, authenticated durable decision prerequisites, anti-rollback and Fail Closed (DESIGN ONLY)](docs/HOST_EXTERNAL_REVOCATION_P110J_DECISION.md)
- [HC06 Host–Authority Contract Checklist — P1-10k C01–C12 roles, evidence required, hard STOP gates; all OPEN/UNCONFIRMED (DESIGN ONLY)](docs/HOST_EXTERNAL_REVOCATION_P110K_CONTRACT_CHECKLIST.md)
- [AP2 v0.2.0 Official Spec/SDK Mapping — P1-10l C01–C12 vs Mandate, Checkout, Receipt (fixed SHA; SUPPORTED vs NOT SPECIFIED vs UNKNOWN; READ-ONLY)](docs/HOST_EXTERNAL_REVOCATION_P110L_AP2_SPEC_MAPPING.md)
- [Verifier vs Host/Authority Revocation — P1-10m scope and GO/HOLD gates (A: cryptographic evidence; B: strong HC06 revocation; DESIGN ONLY)](docs/VERIFIER_VS_REVOCATION_P110M_SCOPE.md)
- [Strict A-only Offline Ruby PoC GO/HOLD Reassessment — P1-10n G01–G08 and 8 planned acceptance cases, unrun at that step (DESIGN ONLY)](docs/VERIFIER_P110N_OFFLINE_POC_GATE.md)
- [A-only Signed Offline Acceptance — P1-10o AN-P01/AN-N01–N07 (8 runs / 45 assertions, signed claim drift rejected, N07 HOST_BOUNDARY; SYNTHETIC ONLY)](docs/VERIFIER_P110O_EVIDENCE.md)
- [A-only Verifier Residual Gap Review — P1-10p issuer layout, unknown nested Constraint fields and GP01–GP09 priorities (DESIGN ONLY / all new tests NOT RUN at P1-10p)](docs/VERIFIER_P110P_RESIDUAL_GAPS.md)
- [GP01 Signed Unknown Nested Constraint — P1-10q historic pre-fix unexpected ACCEPT / RED-HOLD (1 synthetic run / 8 assertions)](docs/VERIFIER_P110Q_GP01_EVIDENCE.md)
- [GP01 Fixed-Issuer Nested Constraint Allowlist — P1-10r: historic RED to bounded REJECT + signed positive, dedicated 2 runs / 10 assertions (RESEARCH ONLY)](docs/VERIFIER_P110R_GP01_FIX_EVIDENCE.md)
- [Signed Constraint Shape and Value-Type Residual Gaps — P1-10s: S01–S08, including requirement ID and Merchant name types (DESIGN ONLY, all new cases NOT RUN)](docs/VERIFIER_P110S_CONSTRAINT_SHAPE_TYPE_GAPS.md)
- [S01 Signed Requirement ID Type Mismatch — P1-10t: latest corrected observer local Docker signature VALID, official Schema INVALID, Ruby ACCEPT / RED-HOLD (1 run / 6 assertions; earlier 1/7 historical; no CI)](docs/VERIFIER_P110T_S01_PREPARED_NOT_RUN.md)
- [P1-10u signed S01 String type check + separate signed positive regression — PR #42, Mac Docker 2 runs / 12 assertions / 0 failures: signed S01 exact-type REJECT and known-good evidence-only ACCEPT; dedicated CI NOT RUN, general Gem/production HOLD](docs/VERIFIER_P110U_S01_TYPE_FIX_PREPARED_NOT_RUN.md)
- [Research phases and release gates](docs/RESEARCH_PLAN.md)
- [Phase 1研究総括とPhase 2-A設計GO/HOLD判断 — 現在の引き継ぎ先 / Current handoff](docs/PHASE1_RESEARCH_CLOSURE_PHASE2_GATE.md)
- [Phase 2-A 最小Merchant Verifier設計パッケージ — Issue #45 / PROPOSED / DESIGN ONLY / 未実装・新規テストNOT RUN](docs/PHASE2A_MINIMAL_VERIFIER_DESIGN.md)
- [Phase 2-A Issuer/SD-JWT権限制約の開示完全性Gate — Issue #47 / DESIGN ONLY / 未検証・Phase 2-B HOLD](docs/PHASE2A_DISCLOSURE_COMPLETENESS_GATE.md)
- [Phase 2-A DC01–DC05 独立署名オラクル実験計画 — Issue #47 / DESIGN ONLY / 全ケースNOT RUN](docs/PHASE2A_DC01_DC05_SIGNED_ORACLE_PLAN.md)
- [Historical P1-10u signed S01 fixed-observer evidence and completed local Docker 2/12 (merged PR #42)](docs/VERIFIER_P110U_S01_TYPE_FIX_PREPARED_NOT_RUN.md)
- [Historical P1-10t new-chat handoff — proposes P1-10u and is now superseded; do not rerun as current instructions](docs/VERIFIER_P110T_S01_PREPARED_NOT_RUN.md#5-新チャット引き継ぎ次の作業2026-10-12)
- [Historical project-wide handoff — Japanese (P1-10r era; P1-10s next-task text not yet updated)](docs/HANDOFF.md)
- [Trust model and security boundaries](docs/SECURITY_BOUNDARY.md)

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

分身AIが外部サービスに持ち込む**検証可能な委任証明**を、Ruby側でどこまで安全に検証できるかを研究するリポジトリです。AP2 v0.2のCheckout Mandateから調査します。署名確認だけで購入を許可したり、未知の発行者を無条件に信用したりしません。現在は研究段階で、Gemは未実装です。

## License

MIT. See [LICENSE](LICENSE).
