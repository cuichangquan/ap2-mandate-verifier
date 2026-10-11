# Research Plan — 小さく始める

更新日：2026-10-11。**研究準備のみ。実装・CI・Gem公開は未実施。**

## Phase 0 — 仕様と競合調査

- [x] AP2 v0.2の公式Commit SHAを固定してCheckout Mandate検証のMUSTを一覧化（[SPEC_BASELINE](SPEC_BASELINE.md) / [VERIFIER_REQUIREMENTS](VERIFIER_REQUIREMENTS.md)）。
- [ ] 公式Python SDKの対応範囲、署名・開示・チェーン検証を照合。
- [ ] RubyGems/GitHubでAP2専用Gem、SD-JWT VC、JWT等を再調査。
- [ ] 最小のVerifier API案・スコープ・未保証項目を整理。
- [ ] 実装のGO/NO-GOを記録。必要性が弱ければ現状維持を選ぶ。

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
