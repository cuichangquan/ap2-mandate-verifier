# v0.2.0 公開検証API 設計・移行計画

状態：**Ownerが方向性を採用済み／P1詳細設計は未確定／実装・テスト・公開は未承認**（2026-10-29 JST）。

この文書は**将来計画**であり、現在のGem 0.1.0に新しいAPIが実装されたことを意味しません。既存の実装契約は [SUPPORT_CONTRACT](SUPPORT_CONTRACT.md)、製品目標は [PRODUCT_VISION](PRODUCT_VISION.md)、開発・承認手続きは [AGENTS.md](../AGENTS.md) と [Issue #101](https://github.com/cuichangquan/ap2-mandate-verifier/issues/101) を正本とします。

## 目的と承認済み設計原則

**AP2が普及したときRuby開発者が最初に選ぶOSS**を目指し、固定AP2 v0.2 Checkout Mandateの検証品質を維持しながら、Ruby/Rails開発者が誤用しにくい公開入口を用意します。

- 公開APIを安定させ、AP2規格に依存する内部の検証処理を必要な箇所で分離する。
- 既存検証コアと7支持形状の証拠を再利用し、署名・委任・制約を再実装しない。
- 未知のprofile・制約・未対応形状を成功にしない（Fail Closed）。
- 具体的な規格差分がない段階で汎用profile登録機構や抽象化を増やさない。
- Gem本体はRails非依存。検証成功・EvidenceとHostによる最終購入許可を分離する。

## P0読み取り専用監査：既知の事実

- 監査基準main：`91308e1d24e2eb823ec7412e23ec7aeaf604f8fa`（2026-10-29のP0結果）。これは以後のHEADを固定する権限ではなく、P1開始時に最新mainを再確認する。
- `AP2MandateVerifier.verify(presentation_json:)` は**JSON構文のみ**の確認入口。有効なJSONでも `status=:unverified`、`code=:verification_not_implemented` を返し、完全検証の成功にはならない。
- `AP2MandateVerifier.verify_research(**inputs)` は `ResearchResult.verify` に委譲する、現行の完全検証入口。
- 完全検証に必要な7入力：`trust_json`、`selection_json`、`host_json`、`root_presentation`、`terminal_jws`、`host_checkout_jws`、`verified_at`。**7入力**と**7支持形状**は異なる数え方。
- 現行の完全検証成功は `ResearchResult`、`status=:verified_research`、`code=:scoped_research_verified`、`success?=true`、不変のEvidence v2。拒否は `Result(status=:rejected)`、依存不足等は `Result(status=:unavailable)`。非成功にEvidenceはない。
- Evidenceは信頼された同一Rubyプロセス内の検査事実であり、Host ALLOW、外部Issuerの真正な登録、失効、nonce原子消費、注文CASや決済を証明しない。
- 規格依存箇所にはTrustContextの固定profile、RootDisclosuresの開示位置、PurchaseBindingの委任/claim/期限、ScopedConstraintsの対応制約、HostBindingの時刻・形状がある。**将来の具体的な変更が出た時に限定的に分離**する。

## 公開API移行の方向性（予定であり未実装）

| バージョン | 方針 | 互換性・条件 |
| --- | --- | --- |
| 0.1.0（公開済み） | `verify` は構文検査、`verify_research` は完全検証 | 現行契約を維持 |
| 0.2.0（計画） | 新しい推奨入口 `verify_checkout` を追加 | 既存 `verify` と `verify_research` の意味・結果・Evidenceを変更しない |
| 0.3.0（候補） | `verify_research` の非推奨化を検討 | 利用状況、移行案内、互換性を確認して別途判断 |
| 1.0.0（候補） | 旧入口の削除可否を判断 | 十分な移行機会と利用実態を確認。削除・公開は自動決定しない |

`verify_checkout` は新しい検証エンジンではなく、**既存の完全検証経路を再利用する薄い公開入口**を第一候補とします。既存の `verify` を上書き・alias化・別意味に多重化する案は、構文のみの旧契約を誤用させるため採用しません。

公開向けREADMEでは実装後に `verify_checkout` を基本例とし、`research` という歴史的名称を初学者に強制しない方向です。ただし、現行の `ResearchResult`・`verified_research`・`scoped_research_verified` を無断変更しません。

## P1で確定する未決事項

1. `verify_checkout` の正確な7 keyword引数契約、型と入力不足・未知keywordの挙動。
2. 新入口が既存Result/ResearchResult/Evidence v2を**そのまま返す**か、利用者向けに安全な表示・アクセサを加えるか。名前の整理が成功意味・保証範囲を広げないこと。
3. 新旧入力の混在・欠落時に構文検査へ暗黙fallbackしないことのテスト設計。
4. 既存 `verify` の非成功、`verify_research` の全経路・7支持形状、拒否・unavailable・Evidence同値を守る互換性テストの一覧。
5. 旧API移行案内と非推奨通知の時期・方法（強制的なwarnや削除は現時点で未決定）。
6. 最小PR分割、README英日・Rails Demoの更新順序、独立レビューと実行承認の具体的なGate。

## 実装・検証・公開の境界

- **現在許可されているのはP1までの読み取り専用設計**。新しいコード、テスト、Docker、Actions、Release/Gem公開、Host本番GOは別の明示承認が必要。
- P2実装候補は入口と必要最小のAPIテスト。P3では既存885回帰と7支持形状の等価性を検証する計画だが、この文書は実行やPASSを宣言しない。
- Codex最新HEAD独立レビュー・未解決重大指摘0、差分と自動CIトリガー監査、Issue #101のR2品質条件を維持する。
- 実Issuer信頼・鍵失効・特定Host本番運用・最悪CPU/RSS/並行性能・一般AP2全対応は引き続き未証明/HOLD。
- P1の詳細設計がOwnerに承認される前に、0.2.0のAPI細部やリリース日を確定させない。

## 新しいChat／dotへの引き継ぎ

1. 最初に [AGENTS.md](../AGENTS.md)、[Issue #101](https://github.com/cuichangquan/ap2-mandate-verifier/issues/101) の本文と最新コメント、[PRODUCT_VISION](PRODUCT_VISION.md)、本書、[SUPPORT_CONTRACT](SUPPORT_CONTRACT.md) を読む。
2. 最新main SHAと関連PR/レビュー、Owner承認範囲、HOLDを再確認する。本書も実装許可ではない。
3. **次のタスク：P1公開APIの設計のみ**。決定事項と未決事項を分け、実装やPRには進まずOwner判断を求める。
