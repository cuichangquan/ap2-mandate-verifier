# v0.2.0 公開検証API 設計・移行計画

状態：**P1公開API設計の下記6項目をOwner承認済み／P2実装・テスト・公開は未承認**（2026-10-29 JST）。

この文書は**将来計画**であり、現在のGem 0.1.0に新しいAPIが実装されたことを意味しません。既存の実装契約は [SUPPORT_CONTRACT](SUPPORT_CONTRACT.md)、製品目標は [PRODUCT_VISION](PRODUCT_VISION.md)、開発・承認手続きは [AGENTS.md](../AGENTS.md) と [Issue #101](https://github.com/cuichangquan/ap2-mandate-verifier/issues/101) を正本とします。

## 目的と承認済み設計原則

**AP2が普及したときRuby開発者が最初に選ぶOSS**を目指し、固定AP2 v0.2 Checkout Mandateの検証品質を維持しながら、Ruby/Rails開発者が誤用しにくい公開入口を用意します。

- 公開APIを安定させ、AP2規格に依存する内部の検証処理を必要な箇所で分離する。
- 既存検証コアと7支持形状の証拠を再利用し、署名・委任・制約を再実装しない。
- 未知のprofile・制約・未対応形状を成功にしない（Fail Closed）。
- 具体的な規格差分がない段階で汎用profile登録機構や抽象化を増やさない。
- Gem本体はRails非依存。検証成功・EvidenceとHostによる最終購入許可を分離する。

## P0読み取り専用監査：既知の事実

- 監査基準main：`91308e1d24e2eb823ec7412e23ec7aeaf604f8fa`（2026-10-29のP0結果）。これは以後のHEADを固定する権限ではなく、次の作業開始時に最新mainを再確認する。
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

`verify_checkout` は新しい検証エンジンではなく、**既存の完全検証経路を再利用する薄い公開入口**として採用します（設計決定であり未実装）。既存の `verify` を上書き・alias化・別意味に多重化する案は、構文のみの旧契約を誤用させるため採用しません。

公開向けREADMEでは実装後に `verify_checkout` を基本例とし、`research` という歴史的名称を初学者に強制しない方向です。ただし、現行の `ResearchResult`・`verified_research`・`scoped_research_verified` を無断変更しません。

## P1のOwner承認済み決定（2026-10-29 JST）

P1の静的確認基準mainは `24a26ef3e22a261d0f4438c37d3f3f117c5c84b8`（[PR #209](https://github.com/cuichangquan/ap2-mandate-verifier/pull/209) 統合後）。以下はOwnerが承認した設計であり、Gem 0.1.0の実装変更やv0.2.0の公開を意味しません。

1. **新しい推奨入口は `verify_checkout(**inputs)`。** 既存の `ResearchResult.verify(**inputs)` に引数を加工せず委譲する。署名・委任・制約の再実装や別の検証エンジンは追加しない。
2. **不足・未知keywordは既存契約と同じ `unavailable`。** 既存factoryの `code=:research_verification_unavailable`、`success?=false`、`evidence=nil` を維持する。未知引数を捨てたり、旧 `verify` の構文検査へfallbackしたりしない。
3. **Result／ResearchResult／Evidence v2をそのまま維持する。** 成功の `verified_research`／`scoped_research_verified`、Evidenceの `ap2.research-evidence.2`／`ap2.research-verifier.2`、検査範囲・不変性・Host責務境界を変更しない。表示用の別結果型に包み直さない。
4. **v0.2.0では `verify_research` の非推奨警告を追加しない。** 非推奨化・削除は将来の検討事項であり、自動的な予定ではない。
5. **既存の `verify` と `verify_research` は変更しない。** `verify(presentation_json:)` は構文検査・非成功のまま、`verify_research(**inputs)` は既存の完全検証入口のままとする。
6. **P2実装は別途Owner承認。** 本設計の採用、文書PR作成、レビュー完了はコード変更・テスト実行・マージ・公開の承認ではない。

### 7入力と例外の境界

新入口も上記の7入力をすべて必要とする。`**inputs` は任意のkeywordを受理・無視する仕様ではなく、既存の完全検証経路へ渡すためのシグネチャである。6つの原文StringとHost提供の整数Unix秒、認証済み・独立したHost入力、固定profileと既存上限は [SUPPORT_CONTRACT](SUPPORT_CONTRACT.md#full-entry-and-required-inputs) に従い、型変換・再JSON化・現在時刻の補完は行わない。

keyword不足・未知・`presentation_json:` 混在・`evidence:` 注入は、既存factory内の引数エラー処理に従って非成功となる。一方、位置引数やkeyword展開自体の誤用は入口到達前に `ArgumentError`／`TypeError` 等となり得るため、**すべての呼出しがResultを返すとは保証しない**。値の不正・依存障害は既存検査順序とstatus/codeを保持し、例外・無結果もHost ALLOWにしない。

## 将来の検討事項・次段階の候補（未承認）

- `verify_research` の将来の非推奨化・通知方法・削除時期。上表の0.3.0／1.0.0は候補であり、削除期限は未決定。
- P2の具体的な変更パス、最小PR分割、README英日・Rails Demoの移行順序。入口と必要最小の互換性テストを第一候補とし、公開済み0.1.0の導入例を未実装APIに置き換えない。
- 検証計画の実行条件。新旧APIの成功・拒否・unavailable・引数不足/混在・Evidence同値、旧APIの非成功を既存期待値と照合する。新旧一致だけを正しさの根拠にしない。既存885回帰・7支持形状の証拠は再利用するが、過去のPASSを新候補の実測へ転記しない。
- 独立レビュー、実行環境・回数・資源・通信・自動CI、マージ、包装・公開の各承認。いずれも本書だけでは実行できない。
- 具体的なAP2仕様差分が生じた際の内部分離。汎用profile登録機構の先行導入は行わない。

## 実装・検証・公開の境界

- **今回の承認は本書へのP1決定の反映、文書専用PR作成、差分監査とCodex独立レビューまで**。Gem実装・テストの変更、Docker・Actionsの手動実行、バージョン変更・Gem公開は行わない。自動CIは事前監査し、未承認の起動が見込まれる場合はSTOP/HOLD。**PRマージは別途Owner承認が必要**。P2実装・検証実行・Host本番GOは許可されていない。
- P2実装候補は入口と必要最小のAPIテスト。P3では既存885回帰と7支持形状の等価性を検証する計画だが、この文書は実行やPASSを宣言しない。
- Codex最新HEAD独立レビュー・未解決重大指摘0、差分と自動CIトリガー監査、Issue #101のR2品質条件を維持する。
- 実Issuer信頼・鍵失効・特定Host本番運用・最悪CPU/RSS/並行性能・一般AP2全対応は引き続き未証明/HOLD。
- 上記6項目は設計として承認済み。追加の契約変更・実行条件・リリース日は未決定であり、承認済み事項と混同しない。重大指摘・未解決事項があればSTOP/HOLDする。

## 新しいChat／dotへの引き継ぎ

1. 最初に [AGENTS.md](../AGENTS.md)、[Issue #101](https://github.com/cuichangquan/ap2-mandate-verifier/issues/101) の本文と最新コメント、[PRODUCT_VISION](PRODUCT_VISION.md)、本書、[SUPPORT_CONTRACT](SUPPORT_CONTRACT.md) を読む。
2. 最新main SHAと関連PR/レビュー、Owner承認範囲、HOLDを再確認する。本書も実装許可ではない。
3. **次は文書PRのレビュー結果とマージ承認を確認し、P2の範囲限定承認を待つ**。P1の上記決定を未決事項へ戻さず、文書PRの統合をP2実装の承認とも解釈しない。
