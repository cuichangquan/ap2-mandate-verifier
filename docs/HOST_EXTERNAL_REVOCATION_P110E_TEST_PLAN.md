# P1-10e — HC06 独立Authority/Host障害注入テスト計画

**日付：2026-10-11 JST / DESIGN ONLY / ALL NOT RUN / 未実装。**
[P1-10d分散協調設計](HOST_EXTERNAL_REVOCATION_P110D_PROTOCOL.md)に残る難ケースを、将来の**独立した架空AuthorityとHost**で検証できる実行計画に落とす。対象は**予約後の失効要求／不明COMMIT／予約timeout**の3系統のみ。Ruby worker、DB、テストコード、CI、実Authority、GCP、Gem/API、外部Provider、実決済、署名Receiptは**今回作らない・実行しない**。

**AP2固定基準：** `v0.2.0` commit `b4587ac1d055888a73b4b21750973cffba961793`。予約・fencing・失効協調は本OSSの研究用Host提案であり**AP2公式プロトコルの機能ではない**。[Host Security Test Plan](HOST_SECURITY_TEST_PLAN.md)の正本`HC06`をさらに分解した計画ID`E-R* / E-U* / E-T*`は、新たな正本Host IDでも合格実績でもない。

## 1. 強い安全条件と現時点の限界

| 時点/状態 | 正本 | 意味 |
| --- | --- | --- |
| `P` | Authority durable store | 対象scope/tenant/operationに紐付く排他的・直列化可能な認可予約の確定（仮説） |
| `R_request` | Authority | 失効要求の**受付**。失効完了ではない |
| `R_effective` | Authority | 失効が正本上**有効になった**線形化点 |
| `C` | Host durable store | nonce CAS、Checkout予約、operation/outboxの原子的COMMIT |
| `D` | 外部Provider | COMMIT後の外部送出。**今回の試験外** |

**目標安全条件（未実証）：** 同じ認可範囲について**権威的に`R_effective < C`なら新しいCは許さない**（nonce未消費、operation/outbox各0、STOP）。`C < R_effective`なら既存operationは最大1件で、後から取消が来ても過去のCやDを自動取消済みにしない。**`R_request`直後から全注文を止める契約は別の、さらに強い要件**。予約中の注文を許す方式で「即時取消完了」と返すのは禁止。

外部`validate_fence`の成功後にHost単独でCするだけでは、間にRが入り得る。[P1-10cの`Mutex`モデル](HOST_EXTERNAL_REVOCATION_P110C_EVIDENCE.md)は単一プロセス限定。**外部AuthorityとHost DB間の共通線形化/中止強制境界はいまだに未選定・未実装**。この前提が無ければテスト結果は`UNPROVEN/HOLD`に留める。

## 2. 将来の隔離検証ハーネス設計（ここでは作らない）

- **プロセスと永続性:** 架空AuthorityとHostを**別OSプロセス、別接続、別耐久ストア/トランザクション**（例：隔離PG16の別DB）に分離し、それぞれ独立SIGKILL/restart可能とする。共通Ruby`Mutex`/単一トランザクション/共有DBロックは独立性の証拠に使わない。
- **Authority最小正本:** `authority_id`、tenant、Issuer/Agent/Buyer、scope/purpose、epoch、reservation ID、operation ID、予約状態、受付済みR_request、R_effective、`finalize/abort`、期限、解放原因。
- **Host最小正本:** Host側信頼済Checkout ID/version/fingerprint、challenge/nonce digest、reservation/epoch、operation IDとidempotency key、nonce/Checkout/operation/outbox、`C`のcommit/rollback、in-flight状態と**以後C不能にする耐久ゲート**（仕組みは未決）。
- **障害を注入するbarrier:** P永続化後、R_request受付前後、Cトランザクション開始・COMMIT前後、C ACK送信前、finalize/abort前後、予約期限到達前後、復旧照会前後。barrierに到着したことを確認してから通信drop/delay/duplicate/reorder、partition、SIGKILL、restart、DB切断を注入。sleepだけに依存しない。
- **順序証拠:** 各ストアのdurable commit ID・局所増加seqに、`operation_id`/`reservation_id`/`request_id`とbarrierのrelease/responseを結びつけて`happens-before`を立証する。**別ホストの壁時計タイムスタンプの大小や単一スケジューラの連番だけでRとCを全順序化しない。** 共通原子的境界の存在を証明できなければ`R_effective < C`の安全性は未証明と判定。
- **Trustと隔離:** Authority/tenant/Buyer/Agent/Issuer/scope、Checkout version/fingerprint、challenge、operation/idempotency ID、epoch/fenceをHost信頼済文脈に束縛。古いepochや別tenant再利用を明示的に拒否する。実Issuer/実Buyer・PII・秘密鍵・実決済は使用しない。
- **プロバイダなし:** Dの実行/決済結果は検証対象外。Host outboxの作成件数のみ測る。

## 3. 全ケースの判定不変条件（**全て将来の期待値**）

| ID | 期待する機械判定 |
| --- | --- |
| `I1` | `R_effective`が`C`より先に**権威的に順序付けられる**なら新C 0・nonce ISSUED・operation/outbox 0。順序が判定不能なら**UNPROVEN** |
| `I2` | 同一Checkout/operation/idempotency keyのHost durable operationとoutboxは各最大1。応答欠落から別operationを作らない |
| `I3` | `R_request=accepted`と`R_effective=confirmed`の応答を厳格に分け、未解決予約でC可能なら「失効完了」を返さない |
| `I4` | timeout、partition、unknown commitは`STOP/PENDING`。ACK不在、単なるDB行不在、lease期限、Authority側fence更新だけでは解放しない |
| `I5` | 予約解放には、C結果が耐久的に解決した証拠、または**以後C不可であることを強制・永続化した証拠**が必須。遅延Cがまだ可能なら解放禁止 |
| `I6` | 失効/予約/commit/recoveryの全てでtenant・主体・scope・Checkout版・epoch・IDの対応が一致。ABA、別主体、重複再送で権限昇格なし |

安全に失効確定できない場合、予約を保留し**長期PENDING/人的復旧が必要になり得る**。これは安全性を維持する一方で可用性・UX/SLAを損なうリスク。テスト「成功」のために期限到達で強制解放してはならない。

## 4. 失敗シナリオ R：Pの後に失効要求

| 計画ID | 独立プロセスの実行順・注入 | 期待結果・必要な証拠 |
| --- | --- | --- |
| `E-R01` | `P durable → R_request accepted → [Hostを一時停止] → C durable → finalize → R_effective` | R受付時応答は**accepted/pending**で完了を詐称しない。Cは最大1でC先行の因果ログ、R_effectiveはC解決後。即時取消契約とは**不適合**であることも記録 |
| `E-R02` | `P → R_request → Hostのdurable abort/commit不可確定 → R_effective → stale Cを再開` | stale C拒否、nonce ISSUED・operation/outbox 0。R_effective前に「以後C不可」の**強制境界**を両者で検証 |
| `E-R03` | `P → R_request`を重複送信。受付/取消応答をdropしAuthorityを再起動 | 同じrequestで一意に受付状態を復元。pendingをeffective扱いしない。Authority durable受付/予約ログと応答対応 |
| `E-R04` | `R_effective`後の古い`P`/epochを遅延到着、別tenant/scopeの予約IDも送る | 新P/C拒否、nonce未消費、別主体への流用0。Authorityのepoch/scopeとHost拒否ログ |

**危険なbaseline（想定反例）:** R_request受理時にAuthorityが直ちに`revoked_complete`と返した後でHostがCを許す場合、`I3/I5`違反。「反例を意図どおり再現」は安全性PASSではない。

## 5. 失敗シナリオ U：Host COMMIT結果が不明

| 計画ID | 独立プロセスの実行順・注入 | 期待結果・必要な証拠 |
| --- | --- | --- |
| `E-U01` | `P → C durable → [C ACK drop] → Host調停側crash → R_request` | Host durable C・nonce/outbox/operation各1を**同じoperation ID**で復元。再C/別operation 0。Authorityは照会中pending、finalize整合後のみR有効化 |
| `E-U02` | `P → C開始 → DB rollback/kill → [C ACK不明] → R_request` | Host DB行不在だけでは解放しない。in-flightの消滅と**将来C不能のdurable状態**を証明した場合だけabort→R_effective。nonce未消費・operation/outbox 0 |
| `E-U03` | `P → HostのCをCOMMIT直前にblock → Authority接続をpartition → 予約解放/R_effectiveを試みる` | 未確定の間**解放禁止**、Rはpending。partition復旧後のC結果まで照会。曖昧な判断を成功扱いしない。Host outstanding transactionとAuthority保留ログ |
| `E-U04` | C durable後のfinalize要求/ACKをdrop・duplicate・reorder、両側restart | 同じreservation/operationに収束、finalize冪等、別operation 0、早すぎるabort 0。各耐久ログと照会結果 |

**危険なbaseline:** ACK喪失やHost `SELECT`で0件だったことだけで「C失敗」として予約解放し、あとからin-flight Cが成功するなら`I1/I5`違反。[旧HR06](HOST_REPLAY_P19C_EVIDENCE.md)はHost内部のみで外部Authority整合性の証明ではない。

## 6. 失敗シナリオ T：予約タイムアウトと遅延C

| 計画ID | 独立プロセスの実行順・注入 | 期待結果・必要な証拠 |
| --- | --- | --- |
| `E-T01` | `P → CをDB COMMIT直前pause → lease期限到達 → R_request → Authority解放試行 → C再開` | 時間切れだけで解放しない。C先行なら既存C最大1でRを後に有効化。R先行ならHostの**耐久的commit禁止境界を通った上で**遅延C拒否。どちらも`R_effective < C`を許さない |
| `E-T02` | 両側のテスト時計を別々に前後skew、期限前後に古い応答/再送 | 時計/TTLだけで認可/失効完了を判断しない。強制fence条件が不明ならUNKNOWN/PENDING |
| `E-T03` | timeout中のepoch更新、古いfenceの再送、重複P、別tenant Checkout転用 | 古いepoch・不一致scope/tenant拒否。同一予約/operationは一意。復旧でABAなし |
| `E-T04` | timeout + 長期partition + 独立restart、C結果不明のまま回復不能にする | 強制解放せず**BLOCKED/PENDING・要調査**を永続記録。可用性低下とSLA/手動解決が未決である証拠 |

**危険なbaseline:** `timeout → release → R_effective → delayed C durable` を許す設計は不合格。単に「遅延Cは来ない」と前提する単一スケジューラでは合格にならない。

## 7. 将来の実行手順・証拠・合否

1. 各計画IDごとに**架空データ**を新規作成、2つの独立ストアを初期化。コードSHA、DB版、worker/接続識別子、シナリオID/seed、固定Checkout・主体・scope・operation・予約・epochを保存。
2. `P→C→finalize`と`R_effective→P拒否`の基準系を先に測る。各barrier到達を**両側で確認**してから通信障害・SIGKILL・restartを注入。時計だけで実行順序を作らない。
3. 各Storeの**durable event/commit/rollback/in-flight end**、snapshot(before/after)、ACK喪失・再送・barrier releaseの相関IDを採取。両側のdurable stateを読み直し、回復後に遅延C/古いepoch/同一operationを再試行する。
4. `I1〜I6`と各シナリオ期待結果を照合。安全な正例は`PASS`、矛盾は`FAIL`、共通の順序/ゲートの証拠不足は`UNPROVEN`、意図的な脆弱baselineは`COUNTEREXAMPLE_OBSERVED`で分ける。**脆弱baselineを安全性PASSに集計しない**。
5. 証拠セットはrun URL/ログ・出力digest・匿名化された権威ログ/Host DB state・理由コード・可用性コスト・未確認前提。生Mandate、private key、nonce原文、PII、Authorization header、実決済情報を保存しない。保存期限/費用は後続で別判断。

**将来実行の合格ゲート:** 全12計画IDにおいて注入と復旧が実行され、該当するI1〜I6が十分な**分散かつ耐久的な証拠**で説明され、未知を成功に格上げせず、二重operation/outbox・誤失効完了・R_effective後のCが0であること。根本的な線形化境界が無い/立証不能な場合は**HC06 HOLD継続**。モデルが通過しても実Authority/本番互換・Availability/Providerの保証は別。

## 8. 現在の判断・次の一件

- **P1-10eは設計文書完成のみ。12計画IDは全てNOT RUN。新テスト、CI、実DB、実Authority、Provider呼出し、GCP、Gem実装なし。**
- 正本Host実PG16は過去の**9/34件、25件NOT RUN、12 runs/465 assertions PASS**のまま。P1-10cの**8 runs/94 assertions**は単一Rubyプロセスの合成モデル。HC06フルは**HOLD**。N17 stateless replay HOST_BOUNDARY、P1-4 G1〜G6/P1-7 T1〜T5、公式Python SDK中間hop **186 PASS/2 FAIL**も未解決。
- **限定的な研究計画のみCONDITIONAL GO。** Gem/API・本番Host統合は**HOLD**、RubyGems公開・Production/実決済・署名Receiptは**NO-GO**。一人の自己レビューは独立セキュリティ監査でない。
- **次のおすすめ1件（別途明示承認後）：P1-10f** — `E-R01/E-R02`に絞り、独立プロセス・独立永続ストアのオフライン検証環境を作るか、barrier/通信障害注入方法と費用・運用上の制約を**先に採否判断する**。承認までは実装しない。
