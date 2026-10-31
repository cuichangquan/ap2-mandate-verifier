# 現状メモ / Project status

更新：2026-10-31 UTC（0.5.0公開確認）。0.5.0公開元source：
`bf796a53600c189b0cfe66c9cfcd1de8a353c03d`。公開後の文書更新は公開Gemのbytesを変更しません。
以下の旧版・候補段階のNOT_RUN/HOLDや撤回記録は各時点の履歴で、現在の配布状態は直下の0.5.0記録を正本とします。

再開時はまずこの要約を読み、[AGENTS.md](../AGENTS.md)と
[プロセス正本 Issue #101](https://github.com/cuichangquan/ap2-mandate-verifier/issues/101)を確認してください。
このメモは更新日時点の案内で、最新GitHub main／PR／レビュー／ActionsとRubyGems原本の確認を置き換えません。
承認・制限の記載は現状記録であり、新たな権限を付与しません。

<a id="050-publication"></a>

## 0.5.0公開済み — 現在の配布状態

[RubyGems 0.5.0](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.5.0)は登録2026-10-31 **07:26:21.576 UTC**、公式metadata・実配布・保存最終候補のbyte照合完了 **07:29:21.200455 UTC**。owner `cuichangquan`、platform `ruby`、prerelease false、照合時yanked false、**50,688 bytes**、SHA256 `00b0ce0981070864c67a056906c5af204bbc5aaa80d029cb4a64294634367dd8`。全21 payloadを公開元source `bf796a53600c189b0cfe66c9cfcd1de8a353c03d`（tree `c853d5cc26e6cabed5c5c84c296d382dfd81ac8e`）と照合しました。RubyGemsがsource SHAをattestするものではなく、承認候補と配布bytesの一致による対応付けです。最初のversion一覧は古い応答でしたが、fresh queryで0.5.0掲載を確認済みです。

[実装PR225](https://github.com/cuichangquan/ap2-mandate-verifier/pull/225)のreview HEAD `c04dda3f7420fc489676ed05a6451af9fce2b290` と統合treeは一致。最新の集約した独立GitHub Codex手動レビューは07:00:09 UTCに完了・指摘なし、未解決thread0。旧依頼の履歴reactionを独立active jobと推定せず、集約最終レビューreceiptと直前の遅着確認を正本に判定しました。CI [41177543108](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/41177543108) attempt1の両Rubyが成功。統合mainからの新buildを同じbytesでMRI3.4.12／4.0.9へ通常導入し、既存全回帰・Receipt65項目、21payload一致／15製品ファイル通常読込み、導入後134ケース・診断・新署名API・成功／拒否Receiptを確認しました。Ruby↔固定Python SDKの署名・原Schema・実callback期待reference完全一致・公式sd_hash比較も成立。公開確認では再build・再push・重複試験をしていません。

0.5.0はCheckout JWT作成・署名とCheckout Receipt作成・署名・検証を追加します。Receipt真正性と業務成功／拒否は別で、既存Verifier／Evidence／InputBuilder／診断の契約と依存・正式MRIは維持。[完全動作例](../examples/merchant_signing.rb)、[API／責任境界・仕様vsSDK差異](MERCHANT_SIGNING.md)、[Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.5.0)。Checkout専用Schemaのstatusを採用し、規範referenceは最終inline SD-JWTの末尾`~`を含む原文hashです。SDK leaf-helperのJWT単体hashとは同一視しません。

公開元に固定するv0.5.0 tag／Release以後の文書整備は公開Gemのbytesを変更しません。[公開前草案](RELEASE_050_DRAFT.md)は履歴として保持。実Issuer・Host本番・実決済・原子的nonce消費・Phase 2-B等のHOLDは維持します。

<a id="040-publication"></a>

## 0.4.0公開済み — 過去の配布記録

[RubyGems 0.4.0](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.4.0)は登録2026-10-31 04:25:06.427 UTC、metadata取得04:25:53 UTC、実配布との照合完了04:26:15 UTC。owner `cuichangquan`、platform `ruby`、prerelease false、照合時yanked false、**44,032 bytes**、SHA256 `b212db01e7deb18dcef1199414f9d93ef43cb1f74b62baa55306de3955dfe177`。公式metadata・実配布・保存候補がバイト単位で一致し、全17 payloadを公開元source `fc42852f53c615f96d7c165a8de494b24b252519`（tree `b1eedc7c1748b2620e7c9e2a3335cc6f2380d09a`）と照合しました。source対応は保存済みレビュー候補の一致によるもので、RubyGemsのsource attestationではありません。

[実装PR222](https://github.com/cuichangquan/ap2-mandate-verifier/pull/222)の最終review HEAD `c1a82cde9f5cc0c09a5c4b05e2ddd70a5ca8f313` と統合sourceのtreeは一致。最新HEADの独立Codex・GitHub Codexとも指摘なし、未解決thread0を確認して統合しました。両MRI 3.4.12／4.0.9のsource既存885＋checkout190＋metadata7＋Builder109＋診断244チェック、同一候補の通常導入134ケース＋診断244チェック＋7実行例、17 payload一致／12製品ファイルの通常読込みを確認済みです。公開物との完全一致により同一成果物と対応付け、公開確認ターンでは再build・再push・テスト再実行をしていません。[候補時点の検証記録](DIAGNOSTICS_VALIDATION.md)を履歴として保持します。

[v0.4.0 tag／GitHub Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.4.0)はOwner承認下で04:35:43 UTCに公開。tagは正確な公開source fc42852を指し、短いRuby利用例と通貨不足の診断出力を掲載しています。再build・再pushは行いません。

0.4.0は不変の `result.diagnostic`／`InputBuilder::Invalid#diagnostic` と英日ヒントを追加します。工程・安全な既知項目・機械判読理由・次の確認候補を示し、原因不明時は断定しません。既存status/code・API・検証条件・Evidence・固定profile・依存・対応MRIは不変です。診断の失敗が元判定を変えることはありません。[英語](DIAGNOSTICS.md)／[日本語](DIAGNOSTICS.ja.md)。

公開Gem同梱文書は準備時点snapshotであり、GitHub source archiveはRubyGems Gemとは別成果物です。実Issuer・Host本番・決済・性能・原子的nonce消費・Phase 2-BのHOLDは維持します。

<a id="030公開済み--現在の配布状態"></a>

## 0.3.0公開済み — 過去の配布記録

[RubyGems 0.3.0](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.3.0)は登録2026-10-31 01:31:40.743 UTC、公式metadata取得01:32:40 UTC、最終照合01:33:27 UTC。owner `cuichangquan`、platform `ruby`、prerelease false、照合時yanked false、**37,376 bytes**、SHA256 `b3a31d5a8b0718f1085745dd4d97d85f210ff9a1628798110da9ff382ae546bd`です。公式metadata・実配布・保存最終候補が一致し、候補の公開元sourceは `877f59195632f74714a60551b6afb22ac81d93e3` です。RubyGemsがsource SHAを独立証明するものではなく、保存済みレビュー候補とのbytes一致により対応付けています。

[v0.3.0 tag／GitHub Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.3.0)をOwner承認下で01:35:52 UTCに公開し、tagが上記の公開元sourceを指すことを確認しました。公開後の文書追補はGemを再build・再push・置換しません。同梱README／SUPPORT_CONTRACTは準備時点のsnapshotで、GitHub source archiveとRubyGems Gemは別成果物です。

`InputBuilder` は認証済み業務情報からtrust／selection／host JSONとhashを作り、発行前準備→保存→原文のまま復元→独立した現在状態→既存の完全検証を支援します。Rails／DB／通信／決済への責務拡張はなく、7入力API・固定AP2/profile・Result/Evidence v2は維持します。[英語利用案内](INPUT_BUILDER.md)／[日本語利用案内](INPUT_BUILDER.ja.md)にRuby単体例とRails対応付けがあります。

正式対応はMRI 3.4.12と4.0.9、導入範囲 `>= 3.4.12, < 4.1` は範囲内全版や他engineの保証ではありません。JSON2.19.9／JWT3.3.0／base640.3.0／OpenSSL gem4.0.2／Digest3.2.1を維持。Debian 12/arm64の両Rubyで統合後sourceの既存885件・checkout190件・metadata7件・builder109件が合格し、同一最終Gemの通常導入後134ケース、14 payload一致、11製品ファイルの通常読込みを確認しました。builderが再利用するHost149件は新規件数へ重複計上しません。既存署名原文・独立期待値と、異常verify／依存不足／selector型／呼出側変更耐性の追加試験を組み合わせています。これらは限定した構成の機能観測であり、過去のmacOS／Ubuntuや他architectureへの保証拡張ではありません。

### 撤回候補と修正の履歴

旧候補SHA256 `5de6907cfcf0565ddaba1385b1d38ae113cc5e26d52259d769030237378a48a8` は未公開のまま撤回しました。[PR218の遅着指摘](https://github.com/cuichangquan/ap2-mandate-verifier/pull/218#discussion_r4429729387)で、InputBuilder.verifyの未登録Result codeが例外を漏らすことを確認。[修正PR219](https://github.com/cuichangquan/ap2-mandate-verifier/pull/219)は登録済みcodeの再利用、依存失敗と不正入力の区別、selector shape検査を修正し、実際のverify／準備APIの異常経路を追加しました。旧候補の無指摘レビューやinstalled124件は、この欠陥を含む候補の妥当性を証明しません。

修正HEAD `b9b3bc2ea53ccb6352c05d96c2e98e13528ca715` の独立Codexレビューは指摘なし、GitHub Codexも同HEADに01:14:25 UTCで👍、thread0を確認後にSquash Mergeしました。元の指摘は修正内容を回答して解決済みです。修正後mainから再生成した正確な最終bytesで両Rubyのsource／通常導入とデモを再検証し、Owner本人がRubyGems公開を実施しました。[候補準備の履歴](RELEASE_030_CANDIDATE.md)を保持し、過去の候補名・NOT_RUN・HOLDを上書きしません。

EvidenceはHostの購入許可ではありません。実Issuer信頼・失効情報・実Host・原子的nonce消費／注文CAS・決済・性能・本番GO・Phase 2-Bは引き続きHOLDです。ローカルデモのみを扱い、Web公開は行いません。

## 0.2.1公開済み — 過去の配布記録

[RubyGems 0.2.1](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.2.1)は登録2026-10-30 11:51:55.894 UTC、照合11:53:55 UTC。owner `cuichangquan`、platform `ruby`、prerelease false、照合時yanked false、**34,816 bytes**、SHA256 `a4ab7e0f6c9bd87355695369374f8e6e2dad104fb673700e9f616053afe6e114`。公式metadata・実配布・保存最終Gemが一致しました。公開元sourceは `5a02bc3a192e16aa3628cf7899617623b0aed78c`です。

正式対応はMRI 3.4.12と4.0.9の2版、導入metadataは `>= 3.4.12, < 4.1`です。範囲内全版や他engineへの保証ではありません。固定5依存・7入力・固定profile・Fail Closed・Result/Evidence v2・既存APIの意味・製品libは変更していません。

公式Ruby bookworm imageのDebian 12/arm64で、両Rubyにsource885＋追加checkout190＋metadata7、同一最終Gemの通常導入後118ケース・13 payload一致・10製品ファイル通常読込みを確認しました。実provider・最終source／成果物・独立レビューは[互換性記録](RUBY_3_4_12_COMPATIBILITY.md)を参照してください。過去のmacOS／Ubuntu実測を今回の成果物の保証に転記しません。

Ownerの明示承認とRelease草案の独立レビュー後に[v0.2.1 tag／GitHub Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.2.1)を公開し、tagが公開元 `5a02bc3a192e16aa3628cf7899617623b0aed78c` を指すことを読戻し確認しました。公開状態の文書更新は最新HEAD独立レビュー・保護条件充足後にSquash Mergeする範囲です。Gem再build・再push・追加実行はしていません。同梱README／契約は準備時点snapshotを維持し、リポジトリ文書追補とは区別します。GitHub source archiveとRubyGems Gemは別成果物です。実Issuer・実Host・性能・本番GO・Phase 2-Bなど既存HOLDは維持します。

<a id="020公開済み--現在の配布状態"></a>

## 0.2.0公開済み — 過去の配布記録

[RubyGems 0.2.0](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.2.0)をOwner本人のTerminal/passkeyで公開。登録2026-10-30 06:43:10.743 UTC、照合06:44:48 UTC。owner `cuichangquan`、platform `ruby`、prerelease false、**33,280 bytes**、SHA256 `9a52e802de5a0564c34d198f4c4ad2c2b60791a8f1eb6e31db14c49e28e91f16`。公式SHA・配布Gem・MBA保存Gemが一致しました。公開元はmain `9b2e28d91fc4886722de7b9c39a5422e966953a9`、tree `a7739f966416bdbc18cfee266efc93223a587407`です。以前の自動pushの終了不明記録は履歴として保持し、今回の本人公開成功とは区別します。

推奨入口は `verify_checkout(**inputs)`。7入力・固定profile・Result/ResearchResult/Evidence v2を維持し、`verify_research` は非推奨警告なし、旧 `verify` は構文検査・非成功のままです。

最終GemはDebian 12 arm64／MRI 4.0.9で全13 payloadのsource/archive/installed一致、10 libの通常require、118 installedケースPASS（research42＋checkout42＋unavailable24＋legacy7＋入力拒否2＋constructor1）を別途観測。固定依存・保存inputs/expectedを再利用し、190／885 source検査は包装工程ではNOT_RUNです。[PR #213](https://github.com/cuichangquan/ap2-mandate-verifier/pull/213)の旧32,256B候補とは別成果物で、Debianを新たな保証対象へ広げません。最終原REPORT SHA256 `4348837cc153c65633e36c83c7939540819f164f43588d8140656e5ab50c2ccd`、公開照合receipt SHA256 `4b8264c5b990b10ad76a3fa3f01fc4ca94e6a828664ab3cefe11e6792c94a139`。ローカル保持原本の識別子であり、公開ダウンロード先ではありません。

公開Gemの同梱文書は公開前のsnapshotで、候補・NOT_RUNという包装時点の文言を含みます。本リポジトリの追補が現在状態を示し、公開済みbytesは変更しません。今回再build・追加テスト・再公開は不要で実施していません。GitHub source archiveとRubyGems配布Gemは異なります。実Issuer・失効・実Host・性能・本番GO・Phase 2-BはHOLDを維持します。

## 0.1.0公開済み — 歴史的な配布記録

Ownerの対象版・SHAを指定したS7承認後、[RubyGems 0.1.0](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.1.0)を公開。公式登録時刻は2026-10-26 08:35:32 UTC、照合は08:37:27 UTC。所有者`cuichangquan`、安定版`0.1.0`、platform `ruby`、34,304B、SHA256 `37b2a235b6fab2d9d9765ae985dd9db27afd3b2c5407fe263a6b65314550db32`。公式版一覧のSHA・実配布Gem・保持R2が一致し、13 payloadとsource manifest18ファイルも照合済みです。[公開receiptと境界](../research/stable010_release_linux_package/README.md#rubygems-publication-verified)を参照。

初回送信はMFA要求で停止し、Ownerが本人のTerminalとパスキーで公開。その後の照合ではpushを再実行していません。版別APIは初回404だったため、公式版一覧・所有者API・実配布物を根拠としました。S7はこの固定profile検証専用Gemの公開に限って成立し、特定Host本番GO、実Issuer信頼、一般AP2/全Schema、発行・提示生成、Phase2-A全面PASSは成立しません。用途・実Issuer未定と既存の資源/通信・provider証拠の限界を維持します。

リポジトリREADMEは公開後に日英分離・画像表示を整理したため、公開Gem同梱READMEとbyte同一ではありません。公開Gem・原検証証拠・旧R1/pre3は変更せず、再build・追加試験・Actions・RubyGems再公開は行っていません。

## 以前の現在地・検証経緯（各記録時点）

| 項目 | 状態・根拠 |
| --- | --- |
| ㉓ 初回pre-release公開 | 完了。[RubyGems0.1.0.pre.3](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.1.0.pre.3)、研究用途限定 |
| ㉔ 公開後の品質維持方針 | 完了。[PR #178](https://github.com/cuichangquan/ap2-mandate-verifier/pull/178)統合、Private vulnerability reporting有効。詳細は[整備文書](POST_RELEASE_MAINTENANCE.md)／[SECURITY.md](../SECURITY.md) |
| 公開pre3のLinux検証 | 限定合格。[run40038620413](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/40038620413)、attempt1、13 payload／10 loaded／52 installed PASS。本番GOではない |
| ㉕ 研究用検証コアの第一段階 | 完成判断をOwner承認済み。信頼するHost入力・Ruby環境を前提に固定profile・7支持形状・採用済み環境に限定。[完成判断と条件](VERIFIER_CORE_COMPLETION_CRITERIA.md)。元E06全体PASS・Phase2-A全面PASS・本番GOは未成立 |

[準備PR #179](https://github.com/cuichangquan/ap2-mandate-verifier/pull/179)はmain統合済み。
その後Ownerの実行B承認を受け、専用workflowを1回だけ実行しました。**1run枠は消費済み**です。
追加実測・修復・rerun／attempt2は承認されていません。

このpre3記録時点では固定profile `ap2.checkout.single_merchant_sku` version1の研究用途限定・本番利用不可でした。現在の0.1.0公開範囲は上記を参照してください。
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

㉕の研究用検証コア第一段階は、固定profile・認証済みHost入力・信頼するRuby環境・採用済み環境の範囲でOwner完成判断済み。
E06因果subsetに続き、Schema VALIDと固定profileの意味拒否を分ける4入力比較も個別承認下で1batch実施し、各4件一致を観測しました（別々の証拠、下記）。
両比較の実行B枠はそれぞれ消費済みで、追加実行は未承認。初回対応環境・保証範囲は下記の限定範囲をOwner採用済みです。最悪CPU/RSS・並行性能は保証対象外で、利用側が実行制限を設定します。
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
**当該観測保存時点はE06 PARTIAL/OPEN・限定コア完成判断/本番GO未承認。後続の第一段階完成判断は下記、元E06全体と本番GOは引き続き未承認**。
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
**当該観測保存時点はE06 PARTIAL/OPEN・限定コア完成判断/本番GO未承認。後続の第一段階完成判断は下記、元E06全体と本番GOは引き続き未承認**。一般Schema/全制約対応とは称しません。
信頼ハーネス/実行環境、実Host信頼/時計/失効、最悪資源/並行保証と過去の通信会計未証明は残ります。

## E06証拠対応の文書化（実行なし）

[7支持形状の条件→実装→試験→独立期待値→観測/限界](E06_SCOPED_EVIDENCE_MAP.md)を保存しました。
具体的な追加必須試験は今回未特定。旧実測を現環境の再実行と扱わず、885/52/各比較件数を重複加算していません。
静的対応・既存回帰・代表的独立因果観測は、7支持形状・固定profileのE06判断根拠としてOwner採用済みです。E06全体PASSではありません。
元E06全体はPARTIAL/OPEN・本番GO未承認を維持します。限定研究用コア第一段階の後続完成判断は下記。
今回の作業は文書のみ。実装/原証拠/公開Gem不変、追加試験・取得・build・CI・再公開なし。

## 初回対応環境・保証範囲の採用（2026-10-24 UTC）

MRI4.0.9と検証済み固定依存、観測済みMBA/macOS arm64およびUbuntu24.04/x86_64を初回対象としてOwnerが採用しました。
[完成条件の環境表](VERIFIER_CORE_COMPLETION_CRITERIA.md#初回の対応環境保証範囲owner採用済み)の固有記録・providerに限定し、OS/providerの全版や将来更新への保証ではありません。
最悪CPU/RSS・並行性能は保証対象外。実行時間・メモリ・同時実行制限は利用側が設定し、ハーネス期限を製品保証値へ転用しません。
Gemの既存入力上限・署名/開示/Schema/制約・trust/Host binding・時刻/Evidence検査は引き続きGem責務です。
実Hostの真正性/最新性・時計/失効・nonce原子消費/注文CAS・最終ALLOWは別責務/未実証のままです。
採用時点では完成未判定であり、その後の第一段階完成判断は下記に記録。元E06全体PASS・一般AP2対応・本番GO・追加公開は未承認のまま。今回も文書のみで追加実行・再公開なし。

## 研究用検証コア第一段階の完成判断（Owner承認）

2026-10-24 UTC、Ownerは、信頼できる独立Host入力と信頼するRuby実行環境を前提に、
固定AP2 commit `b4587ac1d055888a73b4b21750973cffba961793`、
`ap2.checkout.single_merchant_sku` v1・7支持形状・採用済み環境を対象とする
**研究用検証コアの第一段階を完成と判断**した。
対象sourceの読解・同一性確認基準は `26cc5ce1c9bfc93be32dbba6e637b106d60cc68f`。
これは既存証拠・残余条件を採用した限定判断で、新しい試験結果や全パスの安全性証明ではない。
一般AP2、発行・提示生成、実Host運用、最悪CPU/RSS・並行性能保証、
元E06全体PASS、Phase2-A全面PASS、E10/本番GOは対象外。
歴史的通信会計2件と後続送信header/全通信128MiB遵守の未証明も保持する。
利用側の時間・メモリ・同時実行制限とGem自身の既存境界検査の責任分担は変わらない。
公開Gem・実装・原証拠の変更、追加公開や次段階の実行を承認するものではない。

既存885回帰・独立比較・PR182/183観測・MBA/Linuxの包装/導入証拠の意味と件数は変更しません。
今回の文書記録・静的確認のための追加試験・取得・build・CI・Gem再公開はありません。


## ㉖ 最小契約と㉗ 合成Host handoffの限定観測

[Issuer/Host最小契約](ISSUER_HOST_MINIMUM_CONTRACT.md)と[8シナリオの方法・限界](../research/host_handoff_subset/README.md)を保存。
固有ID **HOST-HANDOFF-MBA-20261024-R1**、上記mainの製品10ソースhashを照合した固定コピーに対して実行しました。
[原結果](../research/host_handoff_subset/results/R1/REPORT.json)、[起動receipt](../research/host_handoff_subset/results/R1/BATCH.json)、
[回収・終了記録](../research/host_handoff_subset/results/R1/SUPERVISION.json)、[由来とhash](../research/host_handoff_subset/results/R1/PROVENANCE.json)を参照。
1batch・Ruby子8回・全8シナリオが事前固定Host遷移表と一致。exit0、全体0.843462秒、所有プロセス群回収済み。
全ケースで実Evidenceを同じ信頼Rubyプロセス内に生成してからHostモデルを判定しました。
正常はMODEL_COMMIT、replayは追加消費拒否、生成後鍵失効/注文変更/旧鍵/rollbackは拒否、trust更新不能はHOLD、消費結果不明はPENDINGを維持。
**MODEL_COMMITは合成状態遷移であり、実決済成功・Host本番ALLOWではありません。**
通信0・追加取得/依存導入/build/CIなし。B枠消費済み、再実行なし。
実DB原子性・並行性・durable rollback防止・実Issuer信頼・実失効運用・本番GOは未証明のままです。
固定profile研究用コア第一段階の既存完成判断は変更せず、元E06/Phase2-A全面PASSには昇格しません。
公開保存では実行コードをbyte不変で保持し、READMEと契約の作成時点NOT_RUNに後続観測を追補。
製品・原証拠・公開Gem不変。この保存・PR作業で比較/構文/試験は再実行していません。



## ㉗ 実Evidence→PostgreSQL transaction限定観測（Docker R3）

[方法・停止履歴・限界](../research/host_db_handoff_subset/README.md)、[原REPORT](../research/host_db_handoff_subset/results/R3/REPORT.json)、[来歴](../research/host_db_handoff_subset/results/R3/PROVENANCE.json)を保存。基準main80ea131…の製品10ソースは不変。保存合成wire・固定合成時計を使う新Linux arm64環境で、5ケース1batch/8workers、exit0、0.820627秒、所有プロセス群回収済み。正常/再使用、同Evidence2接続競合、注文変更先行、消費先行、nonce更新後CAS0全rollbackが独立期待値と一致。競合3件で実ロック待ち、全5件で第三接続全行照合とworker DBセッション終了を観測。COMMITTEDは研究用operation記録で、決済/本番ALLOWではない。

Ruby4.0.9・固定Gem依存、PostgreSQL16.15、pg1.7.0/libpq18.6、修正済みDebianOpenSSL3.5.7-1~deb13u3を確認。JSON native build1回、追加ダウンロード0。R1 provider停止、R2整合性確認停止、DIAG01文書欠落373件の診断は歴史記録として保持し、R3成功で上書きしない。

実行から今回image清掃まで約234秒。専用container/一時DB/network/派生imageは清掃済み。base image・証拠と安全に特定不能な共有build cacheは保持。CPU/RAM設定は合計2/2GiB。**全期間8GiBの厳密な強制と総通信量は未証明のまま実行が進んだため、資源条件全面遵守とは扱わない。** 一般並行性能・耐障害性・不明COMMIT復旧・実Issuer信頼・本番GOも未証明。従来の『実DB未実証』は各過去時点の記録で、今回埋まったのは固定合成入力と一時DBの5制御scheduleだけ。Gem責務・公開pre3・元E06/Phase2A全面PASSの状態は変更しない。この保存作業で追加試験/構文/build/Docker/CI/再公開なし。



## COMMIT結果不明時の限定回復境界（Docker R5）

[方法・原結果と限界](../research/host_commit_reconcile_subset/README.md)、[再利用チェックリスト](../research/host_commit_reconcile_subset/REUSE_CHECKLIST.md)、[失敗履歴](../research/host_commit_reconcile_subset/history/ATTEMPTS.json)を保存。基準main27445daf…、保存済み合成wire・固定時計・同じ信頼Rubyプロセス内の実Evidenceを使用。1batch/4ケース/5workers、exit0、比較0.555096秒、全工程67.033秒。COMMIT後の通知抑止→既存完了照会、COMMIT前終了→元session消失とrollback状態確認後にgeneration2で単発再試行、処理中の空照会→PENDING/再試行なし、同一operation異binding→CONFLICTが固定期待値と一致。第三接続の全行照合と全worker/session回収を確認しました。

[原REPORT](../research/host_commit_reconcile_subset/results/R5/REPORT.json) SHA256 `bb05bb10e2c331ec806a46c458c0627cdbc528df0733b1b5cd274d51626eedf9`、結果29ファイル72775Bと必須ビルド診断をSHA/host読戻し確認後に今回DB/container/networkを削除、残存0を確認。旧停止・欠落原本、base imageと共有cacheは保持。Ruby4.0.9/Linux arm64・PostgreSQL16.15・pg1.7.0/libpq18.6・OpenSSL gem4.0.2/Debian libcrypto3.5.7-1~deb13u3の固定構成です。追加取得/image build/Mac直接導入0、JSON native build1回。CPU/RAM合計2/2GiB、swap0を確認。8GiBはOwner採用の追加使用量の観測停止予算で、VM物理増分のhard quotaや全期間peak保証ではありません。最大観測proxy68935364B、host出力約4.93MB。

R1未着手、R2導入失敗と詳細ログ欠落、R3 noexec事前HOLD、R4 batch exit0だがREPORT回収失敗、D1転送器不具合、D2小ダミー成功は別証拠として保持。R4を合格へ昇格せず、先の実DB handoff R3五ケースとも重複加算しません。今回埋まったのは、**DB内部ACK後にアプリ通知を抑止した4制御scheduleの限定観測**です。実TCP/DB protocol障害・crash耐久性・一般耐障害性・任意の旧writer競合・実Issuer/認証/時計/失効・決済・本番GOは未証明。元E06/Phase2-A全面PASSと既存の限定研究コア完成範囲は変更しません。

保存・静的監査・PR作業では追加試験/構文実行/Docker/build/取得/Actions/再公開なし。再利用手順は新しい実行、exec設定変更、失敗後rerun、費用や本番への包括承認ではありません。

## Issuer登録前の利用者向け整理

[登録前チェックリスト兼記入票](ISSUER_ONBOARDING_CHECKLIST.md)を準備。Issuerは未定で、承認根拠・真正な鍵配布元と主体の紐付け・失効更新の正本/鮮度・Owner判断は未決です。既存Gemの入力項目とHost側の承認/運用メタデータを分離し、新しい登録APIは設けません。鍵の登録だけでは信頼は成立せず、Gemは外部信頼/失効の最新性を独立証明しません。不明時はHost HOLD、EvidenceはALLOWではありません。

この追記と記入票は文書整理のみ。実Issuer未証明・本番HOLD、限定研究コアの既存完成範囲と原証拠は不変。実装変更・追加試験・構文実行・Docker・取得/導入・build・CI・Gem再公開なし。

## 初回本番候補の範囲と残タスク

Ownerは初回候補を既存固定profileの検証専用Gemとする範囲を決定。Host運用・実決済・発行/提示生成は対象外だが、利用側の信頼/最新状態/時計・原子消費・最終ALLOW等の前提は維持する。用途・サービス・Issuerは未定、本番GO・次版公開はHOLD。
[残タスクと完了条件の案](FIRST_PRODUCTION_CANDIDATE_PLAN.md)で、採用済み証拠の再利用、Gem側の対応監査/契約判断、用途/Issuer/Host待ち、候補確定後の公開工程を分離した。最初は本番主張と既存証拠の静的対応監査を推奨し、具体的不足なしに試験を追加しない。E06の既存採用判断を全面PASSにせず、実環境安全性・最悪資源/並行性能・実Issuer信頼・通信会計の未証明を保持する。
今回は文書整理と静的確認のみ。追加試験・Docker・取得/導入・build・Gem再作成・Actions・Gem再公開なし。



## 安定版公開判断基準S1〜S7の採用

2026-10-26 UTC、Ownerは[静的監査のS1〜S7](FIRST_PRODUCTION_STATIC_AUDIT.md#安定版公開gates1s7判断基準owner採用済み)を、初回安定版公開の判断基準として採用した。**基準採用と各Gate合格は別で、全7項目の合格は未判定**。既存API契約は確定済みで再設計/改名を出発点にしない。次版は固定profile検証専用の安定版目標、版/公開GOは未承認、用途/実Issuer未定・本番HOLDを維持する。

[採用後の現状表](FIRST_PRODUCTION_STATIC_AUDIT.md#採用後の現状と次の作業2026-10-26-utc)を現在地の正本とする。S1は保証/互換性条件、S2は候補全体の証拠採用、S3は候補時点環境/依存、S4は安定版保守条件が残る。S5の安定版実体・差分検証、S6の候補最新HEADレビュー、S7の明示公開GOは未了。最初の一件はS1/S2の既存契約・証拠水準の具体的な採用案を整理すること。既存計画の「まず静的監査」はPR #195で文書化済みであり、同じ調査を繰り返さない。

147件は885回帰の内数、独立比較はRuby4.0.1時点で4.0.9再実行ではない。追加必須試験は今回未特定であり、必要性未確定の試験を必須としない。旧結果・原Gate・研究用コア完成判断の範囲は不変。今回の判断基準採用/文書保存はAPI/製品変更、追加試験・Docker・導入/build・Actions・Gem作成/公開を承認せず、今回はいずれも実施しない。


## 0.1.0候補の統合と現状（2026-10-26 UTC）

これ以前の「版未確定・候補未検証・条件採用待ち」は各時点の履歴。現在はOwnerがS1/S2/S4の具体条件を採用し、0.1.0候補を作成・限定検証済みです。**安定版未公開、S7公開GO・特定Host本番GOはHOLD**。用途・実Issuerは未定です。

[候補sourceと結果の正本](../research/stable010_candidate/README.md)に、43,008B / SHA256 `0553645fa6c067dd8d7a7a1a7cdf13799370393e76dc3bc4ba161ab2ca5981b0`、製品10ファイル不変、包装13/ロード10/installed52のMBA・Ubuntu各1回の結果、provider診断D1〜D3と供給工程の限界を記録しました。[Ubuntu run40274002891 attempt1](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/40274002891)は成功。PR197は検証基盤のみであり、今回の候補source統合とは別です。

候補のREADME・SUPPORT_CONTRACT・gemspec・lock・包装検査2件は検証時bytesを保持します。同梱「Ubuntu NOT_RUN」は包装時点snapshotで、後続成功を上記外部記録で追補。再build・885再実行・独立Oracle再生成は行っていません。既存147は885の内数、旧独立比較のruntime差は維持します。

S3は実ロードcomponent/providerの出所・hash・修正版等を限定確認しましたが、OS dyld全hash/全binding・全面安全性は未証明。JSON公式修正履歴/ソース一致の採用とGHSA metadata不整合を併記します。S5の同一archive検証は完了、S6はこの統合PRの最新HEADレビューで判定し、S7とは分けます。追加必須試験を今回新たに特定していません。通信全量・物理容量peak・最悪性能等を保証せず、実Issuer/Host前提は残ります。

次は最新HEADレビューとsource同一性を確認後、正確な候補・配布先・保証範囲・残余を提示してS7判断を求める段階です。本記録・統合自体はGem公開・Tag/Release作成・本番GOを許可しません。今回追加build/試験/Actions/取得/公開なし。



## 公開向け文言整理・新archive R2（2026-10-26 UTC）

0.1.0の公開向けREADME/契約/説明文を整理し、新archive R2を別途build・検証しています。API・依存・製品10件は不変。旧R1の43,008BとそのMac/Ubuntu成功は[旧候補記録](../research/stable010_candidate/README.md)として保持し、R2へ流用しません。

R2は34,304B、SHA256 `37b2a235b6fab2d9d9765ae985dd9db27afd3b2c5407fe263a6b65314550db32`。MBAの新archive13/10/52は各1回PASS、実行約0.627秒、一時導入/展開先はhash読戻し後に削除。追加取得/native buildなし。[R2の検証正本](../research/stable010_release_linux_package/README.md)を参照。準備PR時点ではR2 Ubuntuは未実施で、最新HEADレビュー/統合後に承認済み1runを行います。旧run40274002891はR1です。

公開済みと誤認しないよう導入例は0.1.0の公式掲載後に使用と明記しました。S7公開GO・特定Host本番GOは未承認/HOLD。885/147/旧runtime独立比較の扱いとS3残余は不変です。


## R2 Ubuntu完了の追補（2026-10-26 UTC）

新R2の[run40288305150 attempt1](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/40288305150)は成功。実行mainは `4ab7ceea46f477eb60f7b0d436e3afd434a0ff6c`、準備PR199のレビュー済みtreeと一致します。34,304B / SHA256 `37b2a235b6fab2d9d9765ae985dd9db27afd3b2c5407fe263a6b65314550db32` の同じ新archiveで13包装/10ロード/52件一致、Macとのpayload・依存metadata一致を確認しました。job17秒、候補audit step2秒。原REPORT SHA256 `e16de2c82744184f797f9eb8a769c843a52b559767d9f81f61962eec23a7649c`。

[結果・provider・来歴の正本](../research/stable010_release_linux_package/README.md)を参照。92ファイルをサイズ/SHA/host読戻し確認し、今回の5一時rootとローカル入力JSONを清掃。原本・旧候補・旧停止履歴・新archive/sourceは保持します。計測HTTP49,287,629B、archive本文49,276,761B、task disk sample149,648KiB。setup/checkout/input/DNS/TLSを含む総通信、全期間physical peak、厳密CPU/RAM上限は未証明です。

追加build/Mac再検査/885/独立Oracle再実行なし。最初のreview待ちではUbuntu未着手でHOLDし、同HEADへの承認済み回復依頼1回後に有効な完了receiptを受領。別承認の新40分枠をその後07:49:39 UTCから記録しました。重複Running表示を追加ゲートにせず、完了した正確なHEADレビューと未解決0を確認して準備PRを統合しています。

この結果追補は公開GOではありません。S6は追補の最新HEADレビューで確認し、S7の正確な版/配布先/残余を指定したOwner公開GO・特定Host本番GOは引き続きHOLD。製品10件と包装3ファイルは検証時bytesのままです。
