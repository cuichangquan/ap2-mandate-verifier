# P1-9c — Unknown COMMIT ACK / Mock Provider Idempotency オフライン実測

**日付:** 2026-10-11 JST  
**状態:** **限定したPostgreSQL 16研究としてHR06/HR07 PASS**。AP2 v0.2.0固定Commit `b4587ac1d055888a73b4b21750973cffba961793`。**Gem/API・本番/実決済・署名Receipt未実装。**

## 実行結果・証拠

- [GitHub Actions #38135302918](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38135302918) **SUCCESS**。HR06/07 **2 runs / 149 assertions / 0 failures / 0 errors / 0 skips**。同じCIでP1-9aのHR01/02/03/08 **4 runs /108 assertions**、P1-9bのHR04/05 **2 runs /84 assertions**もPASS。合計**8/34 Hostケース、341 assertions、失敗0**。残る**26件NOT RUN**。
- runner `ubuntu-24.04`、Ruby `3.3.12`、`pg 1.5.9`、PostgreSQL **16.9**。image `postgres@sha256:ddfe3e8713e3ee5b8f286082cb12512488dfbf3f5a1ecb0b74a42e6055af0a5f`固定。ログ・各suiteのJSON・環境情報は7日保持のActions artifact `p1-9a-postgresql-evidence`（run #38135302918、artifact ID **11700518021**）。終了後に一時PG service/network破棄。
- 隔離DB名 `ap2_research`以外は拒否、synthetic tenant/Checkoutのみ。GCP・公開ネットワーク・実Provider・支払い資格情報・秘密鍵は利用しない。P1-9cのCOMMIT応答喪失とProvider応答喪失の故障注入は`P19C_FAULT_HOOKS=enabled`時だけ実行可。

## HR06：結果が不明なCOMMITとDBタイムアウト

1. Ruby workerがnonce消費・Checkout更新・operationとoutboxを同一トランザクションに書き込み、libpqで`send_query("COMMIT")`を**非同期送信**。workerは`get_result`を呼ばず、**COMMITの応答結果を受け取らない**。
2. 独立したDB接続がcommit後のoperation/outboxを確認。workerに実OS `SIGKILL`を送信しPG接続が消えることを確認。別プロセスのread-only Recoveryが同じoperation IDとidempotency keyを`PENDING`で回収。既存nonce再送はSTOP、新規operationなし。
3. **別のCheckout**をDB行ロックでブロックし、別Ruby workerに実PostgreSQL `lock_timeout`（SQLSTATE `55P03`）を発生させた。ロック待機を`pg_stat_activity`で観測。Workerは`PENDING`、operation/outbox 0、独立RecoveryはSTOP。確定しない状態で新たな処理を実行しない。

**重要な制限:** COMMITの結果は**元workerからは不明**だが、この試験はDB別接続で**COMMIT成功を確認した一経路**を実測した。COMMIT送信後に実際にrollbackしたケース、TCPプロキシでサーバACKのみ破棄したケース、ネットワーク分断の全パターンを検証したわけではない。

## HR07：Mock Providerでの応答喪失・再試行

1. Host側の**commit済みoperation/outbox**から同一のidempotency keyを取り出す。隔離PG上の別テーブル`p19c_fake_provider_effects`を**架空Providerの永続台帳**とする（物理的な別サービス/HTTPではない）。
2. 最初のProvider workerが台帳へ論理効果1件をcommitした直後に**結果応答を返さず**バリア停止、実SIGKILLでクライアントへの応答喪失を再現。Host側はReceipt成功とせず`PENDING`。
3. 同じoperationとkeyで**再試行を1回**実行。**provider requests=2、mock logical effects=1**、効果IDは同一。DBの`UNIQUE(idempotency_key)`により同じkeyはupsertで既存効果を返す。
4. 改ざんした別のkeyは**STOP**し、効果/attempts件数が増えないことを確認。Hostのnonce再送もSTOP、第二operationなし。

**重要な制限:** これは**ローカルDBを使ったMock ProviderのIdempotency条件下での証拠**。本物の決済Providerによる保証、実ネットワークタイムアウト、API/SLA、料金二重請求の防止を実証していない。DB operation一意性とProvider論理副作用は別の検査対象。署名Receiptは作らない。

## GO / HOLD と次の1件

- **P1-9c:** 上述2件のオフライン研究は**PASS**。P1-7計34件中**8件実測／26件未実行**。Host L0〜L3全体やT1〜T5、P1-4 G1〜G6の全面合格ではない。
- **N17 HOST_BOUNDARY継続:** stateless Verifier自体は有効Mandateを再検証可能であり、nonceの再使用防止はHostの責務。AP2署名/Issuer/Buyer Agent trust/失効/Receipt/本番環境は別ゲート。公式Python SDK中間hopの186 PASS/2 FAILを解消済み扱いにしない。
- **汎用Gem/APIと本番Host統合：HOLD**。RubyGems公開、Production/実決済：**NO-GO**。セキュリティ独立監査未実施。
- **次の1件（別途ユーザー明示承認後のみ）：P1-10a** — **HR10**（Checkout更新・失効とnonce消費/operation作成の並列競合）をまず隔離PG16で設計・実測する限定研究を検討。外部のrevocation sourceをDB lockだけで保護できると主張しない。HC04/HC06/HC07/HR09などはその後の別承認。
