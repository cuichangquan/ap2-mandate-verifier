# Research Plan — 小さく始める

更新日：2026-10-11。**研究・小さなオフライン技術検証を実施。Ruby Gem/API実装・公開は未実施。**

## Phase 0 — 仕様と競合調査

- [x] AP2 v0.2の公式Commit SHAを固定してCheckout Mandate検証のMUSTを一覧化（[SPEC_BASELINE](SPEC_BASELINE.md) / [VERIFIER_REQUIREMENTS](VERIFIER_REQUIREMENTS.md)）。
- [x] 公式Python SDKの対応範囲、署名・開示・チェーン検証を**ソースとテストで静的照合**（[ECOSYSTEM_RESEARCH](ECOSYSTEM_RESEARCH.md)、実行検証は未実施）。
- [x] RubyGems/GitHubでAP2専用Gem、SD-JWT VC、JWT等を限定調査（[ECOSYSTEM_RESEARCH](ECOSYSTEM_RESEARCH.md)）。競合不存在は断定しない。
- [x] 最小のVerifier API案・スコープ・未保証項目を**設計としてのみ整理**（[API_PROPOSAL](API_PROPOSAL.md)）。公開API未確定、未実装。
- [x] P0-5でGO/HOLD/NO-GOを評価し、**HOLD**を記録（[RESEARCH_DECISION](RESEARCH_DECISION.md)）。Ruby実装は未承認。
- [x] **P0-5a完了（公式pytest 186 PASS / 2 FAIL、実署名負例12 PASS、先行限定11 PASS）**。[実測記録](PYTHON_BASELINE_VERIFICATION.md)。公式uv.lockはprivate registry 401のためpyproject直接依存を公開PyPIから取得。**Gem実装HOLD継続**。
- [x] **P0-5b完了**：[Fail Closed Profile](FAIL_CLOSED_PROFILE.md)でIssuer trust、terminal aud/nonce、required disclosure、Checkout原文・hash、Host認可を限定し、[RESEARCH_DECISION](RESEARCH_DECISION.md) §9で**非本番Ruby PoCだけCONDITIONAL GO**（汎用Gem・本番利用はHOLD/NO-GO）。
- [x] **P1-0完了**：合成Python ES256 JWS fixtureと固定AP2公式Open Checkout Schemaに対するRuby `jwt`・`json_schemer`互換性試験 **14 runs/17 assertions, 0 failures**。([RUBY_FEASIBILITY_SPIKE](RUBY_FEASIBILITY_SPIKE.md)、[CI実測](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38123249933))。Gem実装ではない。
- [x] **P1-1完了**：[RUBY_SDJWT_RESEARCH](RUBY_SDJWT_RESEARCH.md) — 固定AP2 v0.2 Python SDKで実署名Root SD-JWTを生成し、RubyでES256 Root署名＋array disclosure digestの完全開示を検証。Merchant制約の非開示／署名・開示改ざんは拒否。**10 runs/22 assertions、0 failures**（[CI実測](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38123828122)）。研究用Strict Profileのみ、Gem実装ではない。
- [x] **P1-2完了**：[RUBY_DELEGATION_SPIKE](RUBY_DELEGATION_SPIKE.md) — 固定AP2 v0.2公式Python SDK発行・Python検証済みOpen→ClosedをRubyで検証。Root `cnf`、Terminal ES256署名、`sd_hash`、Host `aud`/`nonce`の正負を確認 **15 runs/32 assertions、失敗0**。P1-1回帰 **10 runs/22 assertions、失敗0**（[CI](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38124823804)）。実Checkout JWTはダミー。
- [x] **P1-3完了**：[RUBY_CHECKOUT_BINDING_SPIKE](RUBY_CHECKOUT_BINDING_SPIKE.md) — 公式AP2 v0.2 Open→Closed＋**Merchant ES256署名済Checkout JWT**を生成し、Host JWT正本のバイト一致、SHA-256 hash、店舗/商品/数量/単純合計の厳格評価をRubyで確認。**18 runs/40 assertions、0 failures**、P1-2回帰15 PASS、P1-1回帰10 PASS（[GitHub Actions](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38126247946)）。SDK数量評価との差異を記録。
- [x] **P1-4完了（静的レビューのみ）**：[SECURITY_GAP_REVIEW](SECURITY_GAP_REVIEW.md) — P1-1〜P1-3コードに基づく**12項目のリスク登録＋6つのGem受入れゲート**。公開/汎用Gemの実装は**HOLD**、Production/実決済は**NO-GO**。研究テスト追加に限定したP1-5はGO候補（別途承認）。新CI・新攻撃実証はなし。
- [x] **P1-5完了（テストのみ）**：[SECURITY_NEGATIVE_TESTS](SECURITY_NEGATIVE_TESTS.md)、[Actions #38127279271](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38127279271)。固定AP2 SDK＋Ruby研究コードの署名済負例**18件：GREEN 11（正例1/拒否10）、RED 6（想定外受理）、HOST_BOUNDARY 1、ERROR 0**。既存P1-1/2/3回帰43件はPASS。**汎用Gem/API実装HOLD、公開/本番NO-GO**。既存検証器は変更しない。
- [x] **P1-6完了（研究コード修正のみ）**：[SECURITY_HARDENING_RESEARCH](SECURITY_HARDENING_RESEARCH.md)、[CI #38128152237](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38128152237)。以前の**6 REDをすべてGREEN化**。署名付き観測18件=**17 GREEN / 0 RED / 0 ERROR / 1 Host Boundary**。P1-1〜3回帰**10+15+18=43件成功**。重複JSON/JOSE・Closed内時刻・Merchant JWT typ・未知Checkout fieldを厳格化。**Gem実装/公開・実決済はHOLD/NO-GO**。
- [ ] **P1-7（次・別途明示承認後のみ）**：Host trustとVerifiedEvidence≠ALLOW、nonce一度限り消費・Clock/失効/Receiptの責務を**設計・テスト計画のみ**として文書化。Gem本体・Host DB・GCP/実決済は未実装のまま。

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
