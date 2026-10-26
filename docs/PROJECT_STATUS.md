# 現状メモ / Project status

更新：2026-10-26 UTC（初回本番候補の残タスクを整理）。確認基準main：
`305d0a5ee913bf8122d6ea808d4b8aeed11f8256`（PR #193後、本追記前）。
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
| ㉕ 研究用検証コアの第一段階 | 完成判断をOwner承認済み。信頼するHost入力・Ruby環境を前提に固定profile・7支持形状・採用済み環境に限定。[完成判断と条件](VERIFIER_CORE_COMPLETION_CRITERIA.md)。元E06全体PASS・Phase2-A全面PASS・本番GOは未成立 |

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


