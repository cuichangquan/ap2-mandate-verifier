# 現状メモ / Project status

更新：2026-10-24 UTC（E06意味比較の限定結果保存）。確認基準main：
`b858d2b37b529527307957335b722b88481d7fe7`（本追記前。最新mainは再確認）。
Linux実行SHA：`d34dbfa3a87a75360fb4bb14d535da8bc5e8cdc4`。

再開時はまずこの要約を読み、[AGENTS.md](../AGENTS.md)と
[プロセス正本 Issue #101](https://github.com/cuichangquan/ap2-mandate-verifier/issues/101)を確認してください。
このメモは更新日時点の案内で、最新GitHub main／PR／レビュー／ActionsとRubyGems原本の確認を置き換えません。
承認・制限の記載は現状記録であり、新たな権限を付与しません。

## 現在地

| 項目 | 状態・根拠 |
| --- | --- |
| ㉓ 初回pre-release公開 | 完了。[RubyGems0.1.0.pre.3](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.1.0.pre.3)、研究用途限定 |
| ㉔ 公開後の品質維持方針 | 完了。[PR #178](https://github.com/cuichangquan/ap2-mandate-verifier/pull/178)統合、Private vulnerability reporting有効。詳細は[整備文書](POST_RELEASE_MAINTENANCE.md)／[SECURITY.md](../SECURITY.md) |
| 公開pre3のLinux検証 | 限定合格。[run40038620413](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/40038620413)、attempt1、13 payload／10 loaded／52 installed PASS。本番GOではない |
| ㉕ 本番対応の残存課題解消 | 固定profile限定コアを当面の完成対象とする方針はOwner承認済み。[完成条件の判断案](VERIFIER_CORE_COMPLETION_CRITERIA.md)を整理。コア完成・Phase2-A全面PASS・本番GOは未成立 |

[準備PR #179](https://github.com/cuichangquan/ap2-mandate-verifier/pull/179)はmain統合済み。
その後Ownerの実行B承認を受け、専用workflowを1回だけ実行しました。**1run枠は消費済み**です。
追加実測・修復・rerun／attempt2は承認されていません。

固定profile `ap2.checkout.single_merchant_sku` version1の研究用途限定・本番利用不可です。
一般AP2互換性・Phase2-A全面PASS・E10全面GOは未成立、発行・提示生成・Rails SDKは未完成です。
EvidenceはHost ALLOW・nonce消費・決済許可ではありません。

## 公開済み成果物と検証の区別

- pre3：Owner `cuichangquan`、**37888 bytes**、
  SHA256 `8ad627818dc69b450d0fba970dafaf368ec42dd64fb51eec631731027de3882c`。
  2026-10-23にOwnerが公式API・実配布物・MBA原本の一致を確認済み。
  初回Mac mini監査の閲覧／DNS取得不能はその時点の記録です。
  後続Linux runは実配布archiveの取得・同一性を確認したもので、公式API再照会ではありません。
- [PR #177](https://github.com/cuichangquan/ap2-mandate-verifier/pull/177)：
  MBA409-PRE3PACKAGE02-20261023、13 payload／10 loaded／52 installed合格。
- **pre3 Linux限定合格**：2026-10-24 08:15 JST、
  [run40038620413 attempt1](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/40038620413)はsuccess。
  実行SHAは上記`d34dbfa…`。公開archiveのSHA／サイズ、包装時点`20809b057c75d4145eff13e5c183d616c19ef696`の独立参照に対する13 payload、
  checkout外の導入先10 loaded、52 installed（保存MBA期待値42＋旧API7＋入力拒否2＋constructor拒否1）が一致しました。
  MRI4.0.9／JSON2.19.9／JWT3.3.0／base640.3.0／OpenSSL gem4.0.2／Digest3.2.1を確認。
  実ロードRuby・OpenSSL／JSON拡張とlibssl／libcryptoの経路／hash、Ubuntu
  `libssl3t64:amd64 3.0.13-0ubuntu3.16`の所有権・整合性、親／installedプロセスの一致も確認しました。
  固定archive本文は49314649 bytes。JSON native build1回、15分以内完了、artifactなし。
  公開標準runner・cache／artifact保存なしの費用0条件を直前確認して実行しました。
  **885 source回帰・独立Linux Oracle再実行・Gem再ビルド／再公開は未実施**です。
- [GitHub Releaseはpre2](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.1.0.pre.2)。
  [pre2 Linux成功run](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/39939021098)は別の歴史証拠です。
- 公開Gem同梱README／SUPPORT_CONTRACTは包装時点のスナップショットです。
  mainの文書は公開後の追補で同梱文書と異なり、同じ版の再ビルドは公開SHA／包装検証を引き継ぎません。
  公開Gem・タグ・Releaseの上書きや文書だけの再リリースは行いません。
  他文書のNOT_RUNは各作成時点の記録で、現在の限定Linux結果は本メモとrunを参照してください。

## 次の作業と未証明事項

㉕は固定profile・認証済みHost入力・信頼するRuby環境を前提とする限定検証コアの完成条件を整理中。
E06因果subsetに続き、Schema VALIDと固定profileの意味拒否を分ける4入力比較も個別承認下で1batch実施し、各4件一致を観測しました（別々の証拠、下記）。
両比較の実行B枠はそれぞれ消費済みで、追加実行は未承認。将来サポート環境とCPU/RSS/並列予算はOwner未決定です。
実Issuer信頼、Host最新状態・時計・失効・nonce原子消費／注文CAS、本番安全性、
最悪CPU／RSS／並行安全性、過去の取得量・**全通信128MiB遵守は未証明**です。
今回の固定profile／保存入力の限定合格をHost ALLOW・全面本番GOへ昇格させません。
詳細は[対応契約](SUPPORT_CONTRACT.md)と[Linux検証の対象・境界](../research/pre3_linux_published/README.md)を参照。
追加実行・コード／依存／provider変更・再公開には対象を具体化した別承認が必要です。

## このメモの更新タイミング（運用案）

PR統合、検証結果、公開、次作業／未検証事項の変更、作業終了時に内容を確認し、
可能なら関連PR内で更新日・根拠リンクとともに更新します。予定と完了、NOT_RUNと観測結果を分離します。
自動監視・定期実行の稼働やSLAを意味せず、更新／投稿の権限を新たに付与するものでもありません。

## E06因果subsetの限定観測（MBA、1batchのみ）

固有ID **E06-CAUSAL-MBA-20261024-R1**、対象source基準 `53370a3c6e85ec7850166550e740f163122afafe`。
[比較器・方法と境界](../research/e06_causal_subset/README.md)、
[結果](../research/e06_causal_subset/results/R1/REPORT.json)、
[完了receipt](../research/e06_causal_subset/results/R1/BATCH.json)、
[原本hash・公開projection](../research/e06_causal_subset/results/R1/PROVENANCE.json)を保存。
4入力・Ruby子各1回、全4件が独立期待値と一致。終了code0、全体0.797秒、所有子グループ回収済み。

- FULL：3署名とbinding・内容検査が正常復帰し、研究Evidence全字段が独立期待値と一致。
- S01：Openの `constraints[0].items[0].id` 型違反。3署名とbinding正常復帰後、実内容checkに到達し `text!` で `invalid_scoped_schema`、Evidenceなし。
- PRICE_STRING：Checkout Item.price文字列、全署名/Closed/Host hash整合。3署名とbinding正常復帰後、`amount!` で同拒否、Evidenceなし。
- S01_BAD_AGENT：独立判定ではIssuer/Merchant署名有効・Agent署名無効。RubyはIssuer復帰後Agentで `invalid_root_signature`、Merchant/実内容check未到達、Evidenceなし。

公式固定13Schema閉包を使う独立判断と実観測を分離し、前段拒否を内容検査の因果性合格には数えません。
署名は新規合成鍵によるもので、保存署名byte再生・実Issuer/Host出所の証明ではありません。
秘密鍵は一時メモリのみ、通信0、追加取得/依存導入/build/CIなし。
この追補の保存・静的確認では比較器/構文/試験を再実行していません。
製品lib・歴史的Stage15証拠・公開Gem不変。Bの1batch枠は消費済みで再実行不可。
**E06 PARTIAL/OPEN、限定コア完成判断・本番GO未承認**を維持します。
信頼するハーネス/実行環境の前提、terminal300/301比較の対象外、Host/資源/通信会計の未証明も残ります。

## E06意味subsetの限定観測（MBA、別の1batch）

固有ID **E06-SEMANTIC-MBA-20261024-R1**、対象source基準 `b858d2b37b529527307957335b722b88481d7fe7`。
[方法・固定入力](../research/e06_semantic_subset/README.md)、
[実測結果](../research/e06_semantic_subset/results/R1/REPORT.json)、
[完了receipt](../research/e06_semantic_subset/results/R1/BATCH.json)、
[原本hash・公開版の区別](../research/e06_semantic_subset/results/R1/PROVENANCE.json)を保存。

| ケース | 独立期待値＝実測 | Evidenceと因果観測 |
| --- | --- | --- |
| FULL | scoped_research_verified | 3署名・graph/binding・内容検査が正常復帰し、独立期待Evidence全字段と一致 |
| QUANTITY_FLOAT | invalid_scoped_schema | 保存quantity2.0は公式Schema VALID。3署名・binding正常復帰後、quantity! line93で厳格Integer違反として拒否、Evidenceなし |
| TOTALS_ONLY | amount_mismatch | Checkout totalのみ201、積算/Host/line totalsは200。3署名・binding正常復帰後、totals! line109で拒否、Evidenceなし |
| BAD_MERCHANT_BEFORE_TOTALS | invalid_root_signature | TOTALSと同じ署名wire、別の保存Merchant検証鍵。Issuer/Agent正常復帰後Merchantで例外、binding正常復帰・実内容checkなし、Evidenceなし |

全4件MATCH、各ケースの独立5形状Schema判断はVALID。署名負例のSchema VALIDを真正性と混同しません。
1batch・Ruby子4回・exit0、全体0.703秒、所有グループ回収済み。各子10秒/全体300秒の上限内。
実測はMRI4.0.9 Darwin arm64、JSON2.19.9/JWT3.3.0/base640.3.0/OpenSSL gem4.0.2/Digest3.2.1/libcrypto3.5.9。
保存済み公開合成wireをbyte不変で再生。新規署名・秘密鍵使用/生成はなく、比較実行の通信0・追加取得/導入/build/CIなし。
原REPORTは保持し、公開版から不要なworker PIDだけを除去。保存作業で比較/構文/試験を再実行していません。
前節の新規合成署名による因果subsetと、今回の保存wire再生、歴史的Stage11/15の実測は別証拠です。
製品lib・旧pin/原本・公開Gemは不変。今回のB枠も消費済みで再実行不可。
**E06 PARTIAL/OPEN、限定コア完成判断・本番GO未承認**を維持し、一般Schema/全制約対応とは称しません。
信頼ハーネス/実行環境、実Host信頼/時計/失効、最悪資源/並行保証と過去の通信会計未証明は残ります。
