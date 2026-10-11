# P1-8 — Host Replay / Atomic Nonce オフライン実験環境設計

**日付:** 2026-10-11 JST  
**状態:** **設計・技術選定・将来試験計画のみ。新規Host DB/実装/テスト/CIの実行は0件。**  
**判断:** 限定研究のみ CONDITIONAL GO、汎用Gem/API HOLD、RubyGems公開・本番/実決済 NO-GO。

## 1. 目的・スコープ・証拠の境界

[P1-7 Host Security Contract](HOST_SECURITY_CONTRACT.md)の「Host発行nonceの一度限りの消費、同一Checkoutの二重操作防止」を、後続の隔離DBで検証するための試験設計を確定する。**唯一のテストID正本**は[HOST_SECURITY_TEST_PLAN](HOST_SECURITY_TEST_PLAN.md)であり、HT01〜07、HC01〜07、HR01〜10、HE01〜10の**合計34件は今もすべてNOT RUN**。本書は実験順・環境・測定条件を定め、合格を主張しない。

AP2は公式v0.2.0固定Commit `b4587ac1d055888a73b4b21750973cffba961793`、単一Agent・厳格Open Root→Closed Terminal 2hop/単一Merchant・単一SKUの架空Checkoutに限定。Direct/3hop以上/Payment Mandate/実決済は対象外。Verifierの`VerifiedEvidence`は購入許可ではなく、L2 DB試験ではその証拠を模した**synthetic evidence**を用い、署名検証の成功を捏造しない。

**不変条件:**

1. **I1:** nonceは一度だけ消費可能。署名が有効でもHostによる未使用challenge確認は別。
2. **I2:** nonceが異なっても、**一度限りのCheckoutには新規operation最大1件**。version別uniqueだけでは十分でない。
3. **I3:** nonce消費、Checkout状態更新、operation登録、durable outbox予約を**単一transactionで全commit/全rollback**。
4. **I4:** 同時競合・失効・commit結果不明・DB障害時に新しいoperationを実行しない。必要ならSTOP/PENDING。
5. **I5:** DBの操作一意性と**Providerの論理的な二重課金防止**は異なる。後者は同一idempotency keyを永続的に解釈するProvider側の保証が必要。HTTP配送試行自体は複数あり得る。
6. **I6:** Receipt/Provider不明結果を成功と表現しない。署名Receipt/本番のAP2相互運用は別ゲート。

公式AP2のCheckout検証・Receipt義務：[AP2 specification](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L302-L317)、[Agent Authorization](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L493-L535)。**DBのCAS・outbox・TTL・一意制約は当OSSのHost policy提案で、AP2標準のMUSTではない。**

## 2. SQLiteとPostgreSQLの比較

| 候補 | 長所 | 今回の制約 | 判断 |
| --- | --- | --- | --- |
| SQLite（WALを含む） | 非常に軽く、単体rollback実験に便利 | 書き込みを原則1 writerへ直列化。PostgreSQLのrow lock/複数セッション競合を忠実にモデル化できず、`SQLITE_BUSY`だけで安全性を証明しがち | **主DBに不採用**。補助試験の選択肢 |
| PostgreSQL 16 | 複数接続・row lock、`UPDATE ... WHERE ... RETURNING`によるCAS、unique、isolation、故障注入 | 一時service/volumeの管理が必要。lock timeout/deadlock/不明commitを別々に処理する | **採用候補** |

**選定:** 後続P1-9aでは専用の**PostgreSQL 16**を採用する。ベースは`READ COMMITTED`＋Checkout/nonceの固定lock順序＋条件付きUPDATE＋一意制約。長い外部照会をDB transaction中に実行しない。versionは**PG16系列**までの方針で、具体patchとcontainer digestは実装PR時に固定・記録する。公式AP2の固定Commitは変更しない。

技術根拠：[PostgreSQL transaction isolation](https://www.postgresql.org/docs/16/transaction-iso.html)、[SELECT FOR UPDATE](https://www.postgresql.org/docs/16/sql-select.html)、[SQLite isolation](https://www.sqlite.org/isolation.html)。

## 3. 最小隔離環境（これから作る場合の案・今回は作らない）

```text
   Hostが事前発行した架空Checkout/nonce + synthetic evidence
                                |
                  test coordinator / barrier
                  /                         \
      Ruby worker A                      Ruby worker B
      別process / 別PG session           別process / 別PG session
                  \                         /
                    PostgreSQL 16 (isolated)
                Checkout + Challenge + Operation + Outbox
                                |
                 fake provider persistent ledger
                    同一idempotency key -> 実効果1回
                   (public network/実決済なし)
```

- **ローカル:** 手元の既存Dockerを再利用してよいが、他の`app/db/redis`を変更せず、独立compose project（例：`ap2-p19-lab`）と**専用volume**のみ使う。DBをpublic interfaceに公開しない。必要な接続だけloopback/内部networkに限定。
- **GitHub Actions（将来）:** 既存`research/`＋Minitest資産と`actions/checkout`、`ruby/setup-ruby`、少ない権限/短いArtifact保管を参考にする。一時`services.postgres`（PG16）、`ubuntu-24.04`、`timeout-minutes: 10`を候補とし、**まずworkflow_dispatchの単一job**。既存P1-6 security workflowを変更しない。新workflowも現時点では作らない。
- **実装候補:** 小さなRuby Minitest＋`pg`ライブラリと独立したworker子プロセス。DBサービス/依存の正確なversion/image digest、`Ruby -v`、lock timeout、isolation、test seedは実装時に固定。初回L2 race研究のためにPython SDKを毎回install/署名fixtureを再生成しない。L0との署名統合は別ゲート。
- **安全:** Fake Providerは完全オフライン、合成tenant/Buyerのみ。実鍵・本物のMandate/PII/決済資格情報/ネットワーク呼出しを持ち込まない。

## 4. 概念データ模型（DDL・API未承認）

| 概念 | 最小フィールドとDB制約の案 |
| --- | --- |
| `checkouts` | Host管理`tenant_id, checkout_id, version, status`、正本checkout_hash・価格、取消/失効状態。単一回Checkout |
| `challenges` | `tenant_id, checkout_id, version, nonce_digest, audience, buyer_agent_binding, expires_at, state`。`UNIQUE(tenant_id, nonce_digest)`。nonce原文はログに残さない |
| `operations` | `operation_id, tenant_id, checkout_id, challenge_id, idempotency_key, status`。`UNIQUE(tenant_id, checkout_id)`で**versionを超えた二重注文を防止**。operation_id/keyもunique |
| `outbox` | operation FK、配送状態・retry・結果不明状態、同一operationを二重enqueueしないunique制約 |

**将来の候補transaction:**

1. Agent提示値ではなく**認証済Host session**からtenant/Checkout/challengeを解決。Verifierは署名・制約等の検証事実のみ提供。
2. DB transactionで**Checkout→Challengeの固定順に行lock**。`READ COMMITTED`での再読込み時点に注意し、checkout current version/金額/status、nonce未使用・期限、tenantとBuyer/Agent/Issuer/Merchant許可・失効をチェック。外部providerにしか存在しないrevocationの一貫した判定が不能ならSTOP。
3. `UPDATE challenges SET state='CONSUMED' WHERE ... state='ISSUED' AND ... RETURNING ...`で**更新1件だけ**許す。同一transaction内でCheckout状態更新/operation unique insert/outbox記録。CASが0行、unique違反、deadlock、lock timeoutなら**全rollback/STOP**。
4. **COMMIT完了まではdispatch禁止**。COMMIT送信後の通信切断はrollbackとは限らない。結果不明ならDBを再照会し、確定するまではPENDING/STOP、新しいoperation/idempotency keyを作らない。
5. commit済operationからのみFake Providerへstable keyで配送。timeout/遅延成功のときも同一operationを照会し、Providerがidempotency未対応なら重複副作用ゼロを証明できないためHOLD。
6. Receipt署名・保管が失敗しても**新注文の実行は禁止**。Receiptの正式JWT schema/署名/error mappingは別L3テスト。

**未決定:** Host live revocationが外部サービス由来ならPG row lockだけで一貫した失効snapshotを保証できない。Hostが共有DB状態/epochで管理するか、決定直前/dispatch前に再確認するかは後続に検討。multi-order Checkoutは対象外で、再購入は別Checkout IDを要するという**研究用の追加Host policy**。

## 5. 2worker・クラッシュ・Retry試験の順序（すべてNOT RUN）

コーディネータが2つの**独立OSプロセス**と別DB接続を生成。pipe/barrierで同時開始、worker Aがlock取得後の**test-only hook**で停止→worker Bが競合操作を開始→Aを解放するなど、scheduleを制御する。単なる`sleep`で「raceを再現」と主張しない。各試験は別tenant/Checkoutをseedし、別connectionから最終状態を検査。障害条件を狙ったgateまで先に進めてからfaultを注入する（早期拒否による偽カバレッジを防ぐ）。

| 順序 | P1-7 Test ID | 再現と期待不変条件（**未実測**） |
| --- | --- | --- |
| **P1-9a：最初の小タスク** | **HR01, HR02, HR03, HR08** | 同nonce 2worker、別nonce/同Checkout、CAS 0行、使用済nonce再送。**成功commit/operation/outboxは最大1、追加注文0**。重複側STOPまたは同一operation結果 |
| P1-9b候補（別承認） | **HR04, HR05** | commit**前**にprocessをkill→nonce/operation/outbox全rollback。commit**後**dispatch前kill→元operationを再開、nonce二重消費0 |
| P1-9c候補（別承認） | **HR06, HR07** | commit ACK不明、DB接続切断、lock/deadlock、Fake Provider timeout後遅延成功とretry。**新operation/keyを発行せず**、Fake Providerの**論理副作用最大1** |
| 次の境界検証 | **HR10, HC04, HC06, HC07** | Checkout更新・revocationと認可の競合、DB/信頼情報障害。古い正本・失効資格で実行しない。保証できなければSTOP |
| 後続HOLD | **HR09** | 無効入力の大量到達/Rate limit/DoS。最低限のrace初回合格には含めないが、最終Host受入れでは未解決のままにしない |
| 別L3 | **HE06, HE07** | Receipt署名/保存失敗、Provider不明結果とAP2 protocol上の応答。Fake Providerの結果だけで正式ReceiptをPASSにしない |

**重要な検証区別:** commit前crashでのrollbackと、commit**後**の再開、さらにcommit**結果不明**は別シナリオ。外部送信の**HTTP回数**が1とは限らないため、計測は`dispatch_attempts`と`provider_side_effects`を別々に持つ。raceテストの合格だけでPayment安全性を宣言しない。

## 6. 証拠・費用・cleanup

- **計測形式（後続）:** 各caseのID、seed、Git SHA、OS/Ruby/pg/PG versionとimage digest、isolation、worker別接続、barrierイベント、fault位置、CAS updated row count、transaction commit成功/不明、nonce/Checkout/operation/outbox最終行数、delivery attempts/side effects、STOP/PENDING、失敗ログ・exit codeをJSONとMinitestログに残す。**新しいPASS数は実測後に記録**。
- **GO判定:** 各実装対象caseの負例が狙った競合/SQL gateに到達し、二番目のsuccessful commit、二番目のoperation、二度目のProvider論理副作用、誤ALLOW、成功Receiptの捏造がすべて0。flaky race/意味不明なtimeout/中途半端な状態はHOLD。
- **費用:** 既存Mac＋専用Dockerを必要時だけ起動。公開OSSの標準GitHub-hosted runnerは原則無料（[GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)）、ただしlarge runner/Artifact storageの条件や現行課金設定はCI実行前に確認。**単一短時間job、manual-only、成果物7日目安**。GCP・有料DB・Cloud Run・実決済なし。
- **Cleanup:** 専用projectが正しいと確認後、ローカルは`docker compose -p ap2-p19-lab down -v`（その専用volumeのみ）を候補とする。global prune・他OSS/Docker state削除は禁止。GitHubサービスコンテナはjob終了時に破棄される。ログはnonce原文/生JWT/PII/秘密鍵/接続資格情報を含めずsanitize。
- **将来のPR/CI:** Research専用の狭い変更、image/依存pin、故障時の最終DBの証拠、runner conclusionのレビューまで確認後にマージ。CI「緑」だけでは不変条件を証明しない。

## 7. GO/HOLDと次の1件

| 範囲 | P1-8結果 |
| --- | --- |
| DB選定・最小実験環境・Case優先順位・費用/cleanupの**設計** | **DESIGN COMPLETE**。本Stepの成果 |
| Host DB・2worker・nonce消費・Crash/Retryの**実装/実行** | **NOT STARTED / NOT RUN**。34 Host計画テストはすべて0実行。N17 `HOST_BOUNDARY`継続 |
| **P1-9a：PG16 + 2workerでHR01/02/03/08** | **CONDITIONAL GO候補**。別のユーザー明示承認が必要 |
| Crash/unknown commit、Provider、Receipt、全34件 | **HOLD**。小Stepごとに独立承認と証拠を必要とする |
| 汎用Ruby Gem/API | **HOLD**（P1-4 G1〜G6が全面完了していない） |
| RubyGems公開、本番、実決済 | **NO-GO** |

**次の1件:** **P1-9a** — *隔離PostgreSQL 16とRuby 2workerに限ったHR01/02/03/08のオフライン実験*。ユーザーが改めてOKするまで、新DB/CI/Host codeを実装しない。P1-6の過去18観測（17 GREEN、0 RED、1 HOST_BOUNDARY）/43回帰PASSをHostのPASS扱いしない。公式Python SDK中間hop `aud/nonce` 186 PASS / 2 FAILも解消扱いしない。
