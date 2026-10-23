# 現状メモ / Project status

更新：2026-10-24 08:02 JST。Linux準備はsource-only／実行未承認。確認基準main：
`f7a2dab4775d1af6fbf6d840b2ad84feb991d0d8`（本準備のbase。統合後は最新mainを再確認）。

再開時はまずこの要約を読み、[AGENTS.md](../AGENTS.md)と
[プロセス正本 Issue #101](https://github.com/cuichangquan/ap2-mandate-verifier/issues/101)を確認してください。
このメモは更新日時点の案内で、最新GitHub main／PR／レビュー／ActionsとRubyGems原本の確認を置き換えません。
承認・制限の記載は現状記録であり、新たな権限を付与しません。

## 現在地

| 項目 | 状態・根拠 |
| --- | --- |
| ㉓ 初回pre-release公開 | 完了。[RubyGems0.1.0.pre.3](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.1.0.pre.3)、研究用途限定 |
| ㉔ 公開後の品質維持方針 | 完了。[PR #178](https://github.com/cuichangquan/ap2-mandate-verifier/pull/178)統合、Private vulnerability reporting有効。詳細は[整備文書](POST_RELEASE_MAINTENANCE.md)／[SECURITY.md](../SECURITY.md) |
| ㉕ 本番対応の残存課題解消 | 未着手。公開pre3のLinux検証準備は承認Aのsource-only作業。**実行Bは未承認・Linux NOT_RUN** |

本準備6ファイルのローカル作成・静的自己監査は完了。
2026-10-24 08:01 JSTに対象6ファイルのGitHub反映・PR・Codexレビュー・未解決指摘0での統合を追加承認。
PR／統合状態はGitHub原本で確認してください。実行Bは未承認のままです。

固定profile `ap2.checkout.single_merchant_sku` version1の研究用途限定・本番利用不可です。
一般AP2互換性・Phase2-A全面PASS・E10全面GOは未成立、発行・提示生成・Rails SDKは未完成です。
EvidenceはHost ALLOW・nonce消費・決済許可ではありません。

## 公開済み成果物と未検証事項

- pre3：Owner `cuichangquan`、37888B、
  SHA256 `8ad627818dc69b450d0fba970dafaf368ec42dd64fb51eec631731027de3882c`。
  2026-10-23にOwnerが公式API・実配布物・MBA原本の一致を確認済み。
  今回のMac mini監査ではRubyGemsの閲覧／DNS取得が成立せず、独立再確認は未完了です。
- [PR #177](https://github.com/cuichangquan/ap2-mandate-verifier/pull/177)：
  MBA409-PRE3PACKAGE02-20261023、13 payload／10 loaded／52 installed合格。
  pre3の885 source回帰再実行を意味しません。**pre3 Linux：NOT_RUN。**
- [GitHub Releaseはpre2](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.1.0.pre.2)。
  [pre2 Linux成功run](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/39939021098)をpre3へ付け替えません。
- 公開Gem同梱README／SUPPORT_CONTRACTは包装時点のスナップショットです。
  mainの文書は公開後の追補で同梱文書と異なり、同じ版の再ビルドは公開SHA／包装検証を引き継ぎません。
  公開Gem・タグ・Releaseの上書きや文書だけの再リリースは行いません。
- 実Issuer信頼、Host最新状態・時計・失効・nonce原子消費／注文CAS、
  最悪CPU／RSS／並行安全性、過去の通信量条件は未証明です。[対応契約](SUPPORT_CONTRACT.md)参照。

## 次の作業と承認境界

[公開pre3 Linux準備](../research/pre3_linux_published/README.md)は専用手動workflowと
固定manifest／helper／installed検査を準備し、静的確認・最新HEAD独立レビュー・未解決指摘0で統合する承認Aの対象です。
静的レビューや統合をLinux実測合格とは呼びません。旧pre2 workflow／証拠は保持します。

実行Bは別途承認：レビュー済み統合SHA、公開標準Ubuntu24.04 x64、1run／attempt1／15分、
固定archive本文49314649B、JSON native build1回180秒、cache／artifact uploadなし。
費用0構成の根拠は[公式runner条件](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)と
[ログ／Job Summaryの料金区別](https://docs.github.com/en/billing/concepts/product-billing/github-actions)。
実行直前の公開状態・設定・料金確認は未実施のため、費用0確定や実行承認を先取りしません。

公開GemのSHA／サイズと包装時点20809b0…に基づく13 payload、
導入先10 loaded、保存期待値による52 installedを確認する計画です。
main再ビルド・885 source回帰・独立Oracle再実行は含めません。
未知provider／依存／費用、hash不一致、timeout、検査失敗はSTOP、自動修復／rerunなし。
全通信128MiB遵守は未証明。合格しても限定Linux観測で、本番安全性の証明ではありません。

## このメモの更新タイミング（運用案）

PR統合、検証結果、公開、次作業／未検証事項の変更、作業終了時に内容を確認し、
可能なら関連PR内で更新日・根拠リンクとともに更新します。予定と完了、NOT_RUNと観測結果を分離します。
自動監視・定期実行の稼働やSLAを意味せず、更新／投稿の権限を新たに付与するものでもありません。
