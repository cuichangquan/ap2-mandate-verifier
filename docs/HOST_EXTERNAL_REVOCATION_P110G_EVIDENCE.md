# P1-10g — HC06 E-R01/R02：独立した架空Authority/Host PG16研究の実測

**日付：2026-10-11 JST / OFFLINE SYNTHETIC RESEARCH / 2 limited scenarios PASS / HC06 FULL HOLD。**

**基準：** [P1-10f採否判断](HOST_EXTERNAL_REVOCATION_P110F_HARNESS_DECISION.md)、[P1-10e試験計画](HOST_EXTERNAL_REVOCATION_P110E_TEST_PLAN.md)。公式AP2 v0.2.0固定commit `b4587ac1d055888a73b4b21750973cffba961793`を変更していない。Authority予約・失効協調は**本OSSの架空Host研究モデルでありAP2の公式標準機能ではない**。Gem/public API、外部Authority/API、GCP、実決済、外部Provider、Receipt、署名鍵、PIIは利用していない。

## 1. 実施内容・CI一次証拠

- **初回専用CI：** [Actions #38143039035](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38143039035)、PR #28、検証head `8b59ee25ae8c1d1f3674aecbfa33e69c0210f6a9`。**SUCCESS**、Minitest **2 runs / 118 assertions / 0 failures / 0 errors / 0 skips**。Ruby 3.3、pg 1.5.9、ubuntu-24.04。実行後のドキュメント更新等はこのCIの検証範囲外。**最終headのCIはマージ前に別途確認する。**
- **2独立PG16.9インスタンス：** 同一digest固定のPostgreSQL 16.9コンテナを**2つ別々に起動**、Authorityは`ap2g_authority`（port 5432）、Hostは`ap2g_host`（port 5433）。`pg_control_system()`の`system_identifier`が**異なる**ことをログ・テストの両方で実測（Authority `7695400623862755366`、Host `7695400625983741990`）。異なるPostgreSQLサーバ/データディレクトリ・別transactionであり、単なる別schemaではない。
- **Worker独立性：** Authority操作とHost操作は個別Ruby OS子プロセスで実行し、DBごとに固有接続。E-R02ではHost workerを**実際にSIGKILL**してから新しい接続でdurable ABORTを読み戻した。
- **証拠artifact：** [p1-10g-hc06-isolated-evidence（ID 11704100622）](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38143039035/artifacts/11704100622) に`p110g-run.log`、`p110g-report.json`、`p110g-environment.txt`を7日保持。CIでID/結果/隔離/中止/nonce/outboxを機械的に検査している。秘密鍵・実Mandate・生nonce・決済情報を保存しない。
- **隔離・終了:** scoped Github Actions jobの一時サービスのみ。CIログで2コンテナをSTOP/remove済み。**GCPリソース・外部ネットワークサービスは作成していない**。

## 2. E-R01 — Pが先、失効要求後にCが先に耐久確定

| 観測点 | CIで実行したこと |
| --- | --- |
| `P` | Authority専用PGに予約を`RESERVED`としてCOMMIT |
| `R_request` | 取消要求を`ACCEPTED_PENDING`としてCOMMIT。失効`effective=false`を確認 |
| `C` | Host別PGでcheckout行の`SELECT FOR UPDATE`後、nonce/Checkout/operation/outboxを**同一Host transaction**でCOMMIT。operation/outbox各1、nonce CONSUMED |
| `R_effective` | **独立Host接続でdurable Cを読み戻した後**に架空CoordinatorがAuthorityにfinalizeを要求。Authority専用PGの`R_EFFECTIVE_COMMIT`を観測 |

**判定：限定`E-R01 PASS`。** 失効要求を受けた瞬間に「取消完了」と表示せず、`C`が先だったことを記録できた。ただし**取消要求後でもCを許す契約**であり、即時取消契約には不適合。Authority自身がHostの署名済証拠を認証したのではなく、**架空Coordinatorを信頼**しているため本番安全性を証明しない。

## 3. E-R02 — Host durable abort先行・Host ACK喪失・遅延worker拒否

| 観測点 | CIで実行したこと |
| --- | --- |
| `P→R_request` | Authority予約確定と`ACCEPTED_PENDING`を耐久化。`effective=false`のまま |
| 旧Worker barrier | 予約時の古いALLOWを想定するHost commit workerを**Host DB transaction開始前**に一時停止 |
| Host abort | 別Host workerがCheckout行`FOR UPDATE`→`ABORTED`と`ABORT_DURABLE`イベントを**Host DBにCOMMIT** |
| ACK喪失と復旧 | abort workerは通常の結果ACK前に`SIGKILL`。別Host接続で`ABORTED`、nonce ISSUED、operation/outbox各0を読み戻した |
| `R_effective` | その耐久状態を確認してから架空CoordinatorがAuthorityの`R_EFFECTIVE_ABORT`を確定 |
| 遅延C | **R_effective確定後**に古いHost commit workerをbarrierから解放。全COMMIT経路のHost DBゲートで`STOP: abort_durable`。別workerでの追加retryも`STOP`、operation/outbox各0 |

**判定：限定`E-R02 PASS`。** 実SIGKILLを伴うdurable abort復旧と、**再評価時点がR_effective後**の古いworker拒否を観測。**重要な制限：** 停止したcommit workerはHost DB transaction開始前であり、`C`がDB COMMIT中の競合、未解決のin-flight COMMIT、期限切れlease、通信partition全パターンを試していない。これらを本結果の保証に含めない。

## 4. 実装・安全性ゲートと未証明点

- **適用したローカルgate:** この研究の**唯一のHost COMMIT経路**は、Host checkout行`FOR UPDATE`→status/nonce再検査→nonce消費・operation/outboxを単一DB transactionでCOMMIT。Host abortも同じ行で`FOR UPDATE`→durable`ABORTED`。実測した`ABORTED`後のcommit/再送はSTOP。ただし**将来の他Hostコード経路や悪意あるDB直書きまで強制した証明ではない**。
- **Authority側の重大制限:** 研究用Authorityの`finalize_commit/abort`は、架空Coordinatorの伝えた結果を受け取りDBを更新しているだけで、別DB Hostのdurable証拠を**Authority内部で原子的・真正に検査していない**。Coordinatorが嘘をつく/順序を誤る/切断する場合の`R_effective < C`安全保証は**ない**。P1-10dで要求した共通の権威的な線形化境界を実装したとは主張しない。
- **環境の限界:** 2 PostgreSQLインスタンスは別だが同じGitHub Actionsホスト/CIネットワーク上にあり、物理ホスト障害は独立していない。実Authority/署名通信/プロセス間APIの相互認証/複数Issuer/Agent/Buyer/tenant間の競合/Provider Dは未検証。
- **観測方法の限界:** barrierとDB commit/snapshotで決まった**試験内の因果順序**を確認。独立Authority/Host間のすべての実行順序の線形化可能性を証明していない。E-R02のstale workerをHost DB lockで実際にblockしたraceではない。
- **障害・可用性:** Authority ACK喪失/COMMIT結果UNKNOWN/予約timeout長期保留/lease RACE/外部Provider等は[P1-10eの残り計画](HOST_EXTERNAL_REVOCATION_P110E_TEST_PLAN.md)の対象で、**NOT RUN**。本実験で実際に失われたのはHostの**abort ACKだけ**。
- **実測分類:** 計画`E-R01/E-R02`の限定条件のみPASS。HC06 canonical Host IDを**新たにPASSしたとは数えない**。合成研究を独立したセキュリティ監査、本番安全性、AP2全体への準拠証明と呼ばない。

## 5. 正本34件への影響・GO/HOLD・次の一件

**正本Hostテストの進捗は34件中9件実測・25件NOT RUNのまま。** 過去のPG16結果は**12 runs / 465 assertions**（[P1-10a](HOST_REPLAY_P110A_EVIDENCE.md)）、P1-10c単一プロセスモデルは**8 runs / 94 assertions**。P1-10gの**2 runs / 118 assertions**は**別枠の独立DB合成研究**であり、過去の数値に足してHost正本「11/34」などと主張しない。N17 stateless replay HOST_BOUNDARY、P1-4 G1〜G6/P1-7 T1〜T5、公式Python SDK中間hop`186 PASS/2 FAIL`は引き続き未解決。

**判断：P1-10gの隔離合成2ケースのみ研究PASS／HC06の強い外部失効保証HOLD。汎用Gem/API・本番Host統合HOLD、RubyGems公開・Production/実決済・署名Receipt NO-GO。** 自己レビューは独立した安全監査ではない。

**次のおすすめ1件（別途明示承認後）：P1-10h — 研究用Authorityが任意の`finalize_abort`を信用できてしまう問題に絞り、Host中止の耐久証拠の真正性・再実行不能性と、どの切断時に失効確定を保留すべきかを先に設計レビューする。** テスト/実装/外部Authority/GCP/決済は次の別承認とする。
