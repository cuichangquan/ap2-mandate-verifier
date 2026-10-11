# Research Plan — 小さく始める

更新日：2026-10-11。**研究準備のみ。実装・CI・Gem公開は未実施。**

## Phase 0 — 仕様と競合調査

- [x] AP2 v0.2の公式Commit SHAを固定してCheckout Mandate検証のMUSTを一覧化（[SPEC_BASELINE](SPEC_BASELINE.md) / [VERIFIER_REQUIREMENTS](VERIFIER_REQUIREMENTS.md)）。
- [x] 公式Python SDKの対応範囲、署名・開示・チェーン検証を**ソースとテストで静的照合**（[ECOSYSTEM_RESEARCH](ECOSYSTEM_RESEARCH.md)、実行検証は未実施）。
- [x] RubyGems/GitHubでAP2専用Gem、SD-JWT VC、JWT等を限定調査（[ECOSYSTEM_RESEARCH](ECOSYSTEM_RESEARCH.md)）。競合不存在は断定しない。
- [x] 最小のVerifier API案・スコープ・未保証項目を**設計としてのみ整理**（[API_PROPOSAL](API_PROPOSAL.md)）。公開API未確定、未実装。
- [x] P0-5でGO/HOLD/NO-GOを評価し、**HOLD**を記録（[RESEARCH_DECISION](RESEARCH_DECISION.md)）。Ruby実装は未承認。
- [x] **P0-5a完了（公式pytest 186 PASS / 2 FAIL、実署名負例12 PASS、先行限定11 PASS）**。[実測記録](PYTHON_BASELINE_VERIFICATION.md)。公式uv.lockはprivate registry 401のためpyproject直接依存を公開PyPIから取得。**Gem実装HOLD継続**。
- [ ] **P0-5b（次）**：実測結果に基づきIssuer trust、aud/nonce、必須開示、Checkout JWT/hash、Host認可の**最小Fail Closed Profileを設計**し、GO/HOLD再判定。Ruby Gem実装は別途承認後。

## Phase 1 — Checkout Mandate PoC（GO後）

- [ ] 正しいMandate形式・バージョン（vct）・Open/Closedの扱い。
- [ ] SD-JWT署名、開示、Agent鍵・Proof-of-Possession、aud/nonce/期限など仕様が要求する確認。
- [ ] Hostが指定するIssuer信頼ポリシー。Mandate内のJWK/issを無条件に信頼しない。
- [ ] 委任チェーン、Mandate制約、merchant-signed checkoutとhashの照合。
- [ ] Verifier結果は「Verified Evidence」であって最終ALLOWではない。

## Phase 2 — セキュリティ負例（GO後）

- [ ] 改ざん、誤った鍵・Issuer、不正アルゴリズム、期限外、別Agentへの転用。
- [ ] Audience/Nonce不一致、key binding欠落、未開示/未知の必須Constraint。
- [ ] Checkout/金額/通貨/取引先不一致、委任範囲の拡大、replay対策の責務。
- [ ] 巨大Payload/長いチェーンのリソース制限と、情報漏えい防止。

## Phase 3 — 相互運用と公開判断（GO後）

- [ ] 公式Python実装と同じ正例・負例をRubyでも検証。
- [ ] 仕様との差分があればテスト証拠を残し、必要に応じupstreamへ報告。
- [ ] Ruby/Railsサポートmatrix、依存関係、ライセンス、セキュリティ窓口を確定。
- [ ] 監査とCIが整うまでは**production ready**や**AP2 compliant**を主張しない。

## 研究の成功条件

単にMandateのJSONを解析できることではない。発行元・Agent・委任範囲・提示先・Checkoutの結び付きを正しく検証し、**不正な証明を拒否できること**が必要。
