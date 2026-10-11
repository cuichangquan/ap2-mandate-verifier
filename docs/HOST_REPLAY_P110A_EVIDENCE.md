# P1-10a — HR10 Checkout変更・失効・Buyer停止との並列競合（研究用実測）

**日付：** 2026-10-11 JST  
**状態：** **1件の正本HostテストID HR10（4つのMinitestサブケース）を実測PASS。** 本番Host/Gem/API/Receipt/実決済は未実装。  
**公式AP2：** v0.2.0、固定Commit `b4587ac1d055888a73b4b21750973cffba961793`（変更なし）。

## 1. CI・証拠・環境

- [GitHub Actions #38136341199](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38136341199) **SUCCESS**。新HR10は **4 runs / 124 assertions / 0 failures / 0 errors / 0 skips**。同一jobでP1-9aの4/108、P1-9bの2/84、P1-9cの2/149もPASS。**合計12 Minitest runs / 465 assertions / failure・error・skip 0**。
- **Host正本34テストID中9件を実測、25件はNOT RUN**。HR10の4つのケースは**1つの正本ID**であり「4つのHost ID」を達成したものではない。
- 環境：GitHub Actions ubuntu-24.04、Ruby 3.3.12、pg 1.5.9、PostgreSQL 16.9。コンテナdigest `postgres@sha256:ddfe3e8713e3ee5b8f286082cb12512488dfbf3f5a1ecb0b74a42e6055af0a5f`を固定。短時間・単一job、権限`contents: read`。一時PostgreSQL serviceはjob終了時に破棄。
- JSON/Minitestログ/runner環境は [Actions #38136341199](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38136341199) 内の7日保管artifact `p1-9a-postgresql-evidence`、ID **11701063585**。証拠ゲートがHR10正本ID、4つのサブケース、DB lock観測と最終操作件数を確認。秘密鍵/本物のnonce/生JWT/決済データは使用しない。

## 2. 2workerで本当に再現した競合

同一`ap2_research`上で、Hostの認証済session/VerifiedEvidenceに**見立てた合成Checkout**をseed。2つの**独立Ruby OSプロセス・別PG connection**を使い、両者がCheckout → policy行を**同一順序**で`SELECT ... FOR UPDATE`する。片側をテスト専用バリアで停止し、もう片方が`pg_stat_activity.wait_event_type='Lock'`かつ`pg_blocking_pids`により**実際に待機していることを確認してから**先行側を解放。単なる`sleep`による推測ではない。

| HR10サブケース | DBの先行確定状態 | 後行workerと最終DB状態 |
| --- | --- | --- |
| `cancel_first` | Host Checkout policyを**CANCELLED**へ確定 | 古い購入要求は**STOP: checkout_cancelled**。nonce ISSUED、Checkout OPEN、operation/outbox各0 |
| `block_first` | **Buyer利用資格=false**を同DBへ確定 | 購入要求は**STOP: buyer_blocked**。nonce未消費、operation/outbox各0 |
| `edit_first` | Checkout **version 1→2**、fingerprint **v1→v2**を確定 | 以前のversion/fingerprintに対する購入要求は**STOP: checkout_version_mismatch**。nonce未消費、operation/outbox各0 |
| `authorize_first` | nonce消費、Checkout RESERVED、operation/outbox各1件を原子的にcommit | その後の取消は**STOP: too_late_checkout_reserved**。取消が先に間に合ったとは偽らない。nonce CONSUMED、operation/outbox各1件 |

**重要なタイミング解釈：** 「先に取消がコミットされた場合、その後の認可を止める」ことを実証。**すでに注文操作がコミットされた後で取消が発生しても、自動的に過去の注文が取り消されたことにはならない**。返金/後処理/取消APIは別の機能・検証ゲート。

## 3. 実証できない領域と運用上の境界

- 認可workerも変更workerも**同じPostgreSQLにアクセスし、同じ行ロック規約を守る場合**の限定研究。実際のIssuer、Buyer/Agent権限管理、別DB・Redis・外部Revocation Provider、イベント通知遅延、ロックを迂回する経路は再現・保証していない。
- Checkout内の金額/通貨/在庫などの真正署名JWTそのものは検証せず、合成fingerprintとversionの変化だけを検査。**HC04**（価格/在庫/正本の全照合）と**HC06**（外部資格失効/commit境界）、**HC07**（信頼サービス障害）をPASSにしていない。
- 今回は注文**operation＋outbox**のDB確定を対象とし、外部Provider dispatch/Refund/二重課金/成功Receiptは試していない。N17のstateless Verifierの再検証可能性**HOST_BOUNDARYは残る**。
- 他の26 Host計画ケースは未実行。特にHR09のDoS・HT01〜07・HC01〜07・HE01〜10のGateは残る。P1-4 G1〜G6、P1-7 T1〜T5も全面クリアではない。公式Python SDKの中間hop aud/nonce **186 PASS / 2 FAIL**を解消扱いにしない。
- 発火用の`P110_RESEARCH_ONLY=enabled`ガード、接続先DB名`ap2_research`の検査、架空データのみ。既存のapp/db/redisや他OSS・GCPに触れていない。
- このPRレビューはソロメンテナの**自己レビュー**であり、独立セキュリティ監査ではない。

## 4. GO/HOLD と次の1件

**限定したHR10のDB競合実験：PASS/研究GO。** 汎用Ruby Gem/公開APIと本番Host統合は**HOLD**。RubyGems公開・Production/実決済は**NO-GO**。

**次の1件（別途ユーザー明示承認後のみ）：P1-10b。** まず**HC06：外部Issuer/Agent/Buyer資格失効の時点性、DB境界、commit直前の再照会、unknown時Fail Closed**の**設計・テスト戦略だけ**を研究する。外部DB/API/GCPを起動せず、実装範囲と整合性保証の限界を確定してから必要なら別承認で実測する。HC04/HC07/HR09のまとめ実装やReceiptは未承認。
