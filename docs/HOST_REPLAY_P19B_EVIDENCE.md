# P1-9b — PostgreSQL 16 Host Crash / Recovery 実測

**2026-10-11 JST / 限定オフライン研究のみ**。AP2 v0.2.0固定Commit `b4587ac1d055888a73b4b21750973cffba961793`。Gem/API/本番/実決済/Receiptは未実装。

## 実行したCIと環境

[GitHub Actions #38134591784](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38134591784) **SUCCESS**。新しい**HR04/HR05：2 runs / 84 assertions / 0 failures / 0 errors / 0 skips**。同一Runの既存P1-9a回帰**HR01/02/03/08：4 runs / 108 assertions / 0 failures / 0 errors / 0 skips**。累計**6 / 34 Hostケース**実行・**192 assertions成功**。残り**28件はNOT RUN**。

環境はGitHub Actions ubuntu-24.04、Ruby 3.3系、`pg 1.5.9`、PostgreSQL 16.9。Postgres imageは[P1-9aの実測digest](HOST_REPLAY_P19A_EVIDENCE.md) `postgres@sha256:ddfe3e8713e3ee5b8f286082cb12512488dfbf3f5a1ecb0b74a42e6055af0a5f`固定。JSON・テストログ・環境はActionsの`p1-9a-postgresql-evidence` artifact（保持7日）へ保存。GCP/外部決済/公開サービスなし。

## 実際に観測した2つの失敗経路

| テスト | 強制終了点とDB独立観測 | 結果 |
| --- | --- | --- |
| **HR04** | 独立Ruby workerがnonce更新・Checkout予約・operation作成・outbox記録まで実行し、**COMMIT送信前**にバリアで停止。別PG接続からは未確定変更が不可視で、workerは`idle in transaction`。**実OS SIGKILL**を送信し、PG backend消滅を確認 | Checkout OPEN、nonce ISSUED、operation/outboxとも0への全Rollback。別プロセスの読み取り専用復旧はSTOP。その後新たな正当workerが状態を**再評価して1件だけcommit** |
| **HR05** | `db.exec("COMMIT")`が正常応答した**後**のバリアで停止。別PG接続から既にCheckout RESERVED、nonce CONSUMED、operation/outbox各1件を確認。**実OS SIGKILL**・PG backend消滅 | Commit済み状態は消えず、別Rubyプロセスの**読み取り専用Recovery**が同じoperation ID・idempotency keyを`PENDING`で再取得。再取得を繰り返しても同一。旧nonce再送はSTOP、二重operationなし |

SIGKILLの実シグナル・workerプロセス終了、PostgreSQL接続消滅、DB最終行数/状態のMinitestアサーションを確認した。Crash modeは研究用環境変数`P19B_CRASH_HOOKS=enabled`のみで有効、接続DB名が`ap2_research`でなければ拒否。既存P1-9a通常worker動作は回帰4件で検証。**Recoveryはread-only/PENDING参照のみ。Providerへの送信やReceipt生成を行わない。**

## 証明していないこと・今後のGO/HOLD

- **HR06は未実行:** COMMITの送信後、成功/失敗のACKが失われ**結果不明**になるケースはHR05（ACK確認済み）と違う。
- **HR07は未実行:** Fake/実Providerのtimeout、後着成功、同一idempotency keyでの論理副作用一度限り保証は未実装。**DBでoperationが1件だから二重課金が発生しない、と一般化しない**。
- AP2署名・SD-JWT/Agent/BuyerのHost信頼・失効・鍵rotations・Receiptは本ケースのテスト対象外。stateless Verifierの**N17 HOST_BOUNDARY**は継続。従来公式Python SDK **186 PASS / 2 FAIL**（中間hop aud/nonce）も未解決。
- [HOST_SECURITY_TEST_PLAN](HOST_SECURITY_TEST_PLAN.md)の**34件中6件のみ実測**。P1-4 G1〜G6/P1-7 T1〜T5の全達成ではない。独立したセキュリティ監査でもない。
- **限定研究：GO（HR04/05成功範囲）**。汎用Gem/公開API・本番Host統合**HOLD**、RubyGems公開・実決済/Production**NO-GO**。

**次の1件（別途ユーザー明示承認後のみ）：P1-9c** — HR06（unknown commit/DB timeout）とHR07（Fake Provider timeout/idempotency）を架空オフラインで切り分けて実証。新Gem、署名Receipt、実決済、GCP、他OSSは変更しない。
