# P1-10f — HC06 E-R01/R02 独立オフライン検証環境の採否判断

**判断日：2026-10-11 JST / DESIGN & FEASIBILITY DECISION ONLY / NOT RUN。**

[P1-10eの障害注入計画](HOST_EXTERNAL_REVOCATION_P110E_TEST_PLAN.md)のうち**予約Pの後に失効要求が来るE-R01/E-R02の2ケースのみ**を、将来どの最小環境で検証するか決める。**本Stepではプロセス・DB・コンテナ・テスト・CIを作成/実行しない。** 外部Authority、実Issuer/Agent/Buyer、GCP、実決済、Provider、署名Receipt、Ruby Gem/API、他OSSは範囲外。公式AP2 v0.2.0固定commit：`b4587ac1d055888a73b4b21750973cffba961793`（不変）。本書の`reserve / revoke / finalize / abort`は**提案Host研究モデル**であって公式AP2の必須APIではない。

## 1. 判断：最小研究ハーネスの構築は条件付き推奨、実装は未承認

**採否：CONDITIONAL GO（将来の隔離研究ハーネスを検討・申請する価値はある）／IMPLEMENTATION NOT AUTHORIZED。**

- **作る価値:** [P1-10cの8 runs/94 assertions](HOST_EXTERNAL_REVOCATION_P110C_EVIDENCE.md)は2論理コンポーネントを1プロセスの`Mutex`で保護した人工モデル。[P1-10d](HOST_EXTERNAL_REVOCATION_P110D_PROTOCOL.md)の未証明点である**別プロセスと別DBでのR_effective/Cの競合、失効完了の誤表示、取り消し後の遅延C**を反証する最小実験は既存証拠との増分価値がある。
- **しないこと:** 2ケースの合成研究で強いHC06の全範囲、外部Authorityとの実互換性、分散原子性、本番即時取消、複数Authority、Providerの冪等性、その他10ケースを証明したと主張しない。**本番相当の保証にGOを出さない**。
- **採用前の必須条件:** 将来Cを防ぐ**Hostの耐久的・全C経路で強制されるgate**と、Authorityが`R_effective`を確定してよい条件を、実際に検査可能なものとして記述できること。これができなければ**STOP / UNPROVEN / 研究設計再検討**とし、見かけのPASSを作らない。
- **実装開始:** 別途明示承認が必要。費用/CI/ローカル実行の承認もこの文書で得たことにはしない。

## 2. 比較と選定（概算・設計上の比較であり実測なし）

| 案 | 隔離性・検証力 | 費用・運用 | 判断 |
| --- | --- | --- | --- |
| A. 既存の同一Rubyプロセス／共有`Mutex`・メモリ内状態を拡張 | 独立故障と別DBのCOMMITを実証できない。P1-10cの限界が続く | 最少 | **不採用** |
| B. ローカルでRuby Authority / Hostを**別OSプロセス**として稼働。**別々のPostgreSQL 16インスタンスとデータ領域/接続**を持たせる | 独立SIGKILL/restart、durable失効・C、通信drop/遅延と回復を観測可能。ただし同一物理ホスト・Docker daemon等の共通障害ドメインは残る | 既存開発機での追加クラウド料金なしを目標。ストレージ/CPU/RAM/電力、環境整備負担あり。ローカル実測・費用未確認 | **条件付き第一候補** |
| C. 同じPostgreSQLサーバの別DB／別schemaだけ | トランザクションは分離できるがDBサーバ障害は共有。独立Store故障の証拠として弱い | Bより軽い | **限定代替**。Bと同等の独立性を主張しない |
| D. GCP／公開HTTP／実Authority／外部Provider | 現時点のE-R01/R02研究に過剰。外部APIの予約・失効契約自体未確認 | 課金・認証・漏えい・破棄コスト増 | **不採用・承認範囲外** |

**Bの推奨トポロジー（将来の候補であって作成していない）：**

`test orchestrator`（障害注入と記録だけ。認可の正本・fence判定を持たない）
→ `Ruby Authority worker` ＋ `PG16-A (own instance + volume)`
↔ **実際に故障注入できるローカル専用の通信境界**
↔ `Ruby Host worker` ＋ `PG16-H (own instance + volume)`。

Ruby workerとDBは論理・OSプロセスとして独立に停止/復旧する。コンテナ化は実行時の便宜として後続決定し、必要なDBインスタンス数/ポート/volumes/cleanupを明文化する。**共有SQLite・共有メモリ・共通DB transaction・共有行ロック/MutexでR/Cを原子的に見せかけない。** ローカル共通OS/ホストの単一障害ドメインは残るため、**真の複数物理マシン検証とは呼ばない**。

## 3. E-R01/R02の最小プロトコルと実験境界（仮説）

共通の合成ID：`authority_id/tenant/Buyer-Agent-Issuer/scope`、`checkout_id/version/fingerprint`、`challenge/nonce_digest`、`reservation_id`、`operation_id`、`idempotency_key`、`epoch`。Mandate/秘密鍵/PII/決済データなし。

- `P`：Authorityが合成reservationを**耐久保存**し、そのACK後にHostへ予約参照を渡す。
- `R_request`：Authorityは要求を耐久記録し**accepted/pending**を返すだけ。確定済みの`R_effective`と混同しない。
- `C`：Hostの**同一ローカルDB transaction**で最終gateとnonce CAS/Checkout state/operation/outboxを束縛する。検証器の`ALLOW`やAuthorityの`validate_fence`応答のみでCを許してはいけない。
- `abort/close`：Hostが**今後の全C経路を抑止するdurable gate**を原子的に設ける。止めたいworkerがlockを持つ場合は**先に解決/待機**し、gateがdurableになる前にAuthorityへ「中止済み」を送らない。単なる新しいfence番号、ACK、SELECTで行なし、タイムアウトでは条件を満たさない。
- `finalize`：Hostの`C`のdurable結果、または`abort/close`のdurable証拠を同じreservation/operationに対応付け、Authorityに伝える。ACK dropなら**UNKNOWN/PENDING**を維持する。
- `R_effective`：Authorityは上記の**強制可能・回復可能な証拠**と予約解放の順序を確認した場合だけ、失効完了をdurableにする。**別DBでこれをどう連結すれば十分かは未実証**。本Stepで実装方式を採用したとはしない。

### E-R01 — Cが先、失効要求は保留される

1. Authority Pをdurableに保存。
2. R_requestをAuthorityで受理/永続化。`accepted/pending`を記録。**この段階では`R_effective`ではない**。
3. Host Cを独立DBでdurable確定。nonce消費・operation/outbox各1（新規操作は最大1）。
4. Host C証拠→Authority finalize→（必要なら）R_effective。時点の因果関係を確認。

**期待する観測:** R_request後の「取消完了」応答0、`C<R_effective`を主張するのに十分なdurableと通信上の因果証拠、operation/outbox最大1、過去Cの偽取消0。**この方式は「失効要求瞬間にC禁止」の即時取消契約を満たさない。**

### E-R02 — Host中止が先、古いworkerが遅れてCを試みる

1. P後、Hostの既存C workerを**最終gateとの競合点**でpause。AuthorityにR_requestを受け付けさせる。
2. 別Host workerがdurable `abort/close`を進める。既存Cがlockを持つ/commit済みなら、安易に中止成功にせず待ち・解決を記録。
3. **以後C不能がdurableに確定した証拠をAuthorityが確認**した後だけR_effectiveを確定。
4. pauseしたstale workerをresume。古い予約/fenceでCを試させ、**必ず同じHost DB内の強制gateでSTOP**する。

**期待する観測:** `R_effective<C`で新規C 0、nonce ISSUED、operation/outbox各0。古いworkerがpause時のローカル判定を使ってgateを迂回できるなら**FAIL**。失効要求を受けたのにCが先にlock/commitを勝ち取った試行は`E-R01`側へ分類し、架空の`E-R02 PASS`として扱わない。

**意図的な反例control:** `R_request`時に即`revoked_complete`を報告する/Authorityだけfence更新するがHost stale workerのCを阻止しない方式。観測できたら`COUNTEREXAMPLE_OBSERVED`、**安全性PASSには加算しない**。

## 4. 最小障害注入・観測・合否

| 注入点 / 制御方法（将来） | なぜ必要か | 後で採る証拠 |
| --- | --- | --- |
| Authority P durable後のbarrier。Host Cの最終gate前/lock競合時のbarrier | P→R→C、P→R→abort→R→stale Cを**sleepでなく確実に**交錯させる | barrier到達/開放と両サービスのoperation/reservation相関ID |
| R_request ACKを保持/遅延、R_effectiveを別イベントとして観測 | accepted≠effectiveの誤表示を検出 | Authorityのdurable要求/効果ログ、Hostへの応答 |
| Host workerをpause/resume、片方だけSIGKILL/restart | 古い判断でCできるか、耐久gateを再起動後も守れるかを確認 | 同一operationのcommit/rollback/中止履歴、restart後snapshot |
| localhost限定の通信drop/delayとreply replay（最小） | 応答欠落を勝手な成功/abortに変換しない（本研究では全面的な未知COMMITは試さない） | request/response相関IDとdrop指示の証跡 |
| Hostの`abort/close`の確定前後でCを再開 | 取消成立のタイミングとCの原子化を**本当に競争**させる | SQL commit結果・durable gate・nonce/operation/outbox after-state |

**最低合否の前提:** 2つの異なるPG16インスタンス・別durableログ・別Ruby workerと独立crashを証明できる。`E-R01`は失効要求ACKと失効実効の明確な分離、`E-R02`は**Hostの全C経路で強制された耐久中止gate**とstale Cの拒否が必要。**両者を結ぶ順序**を自サービスの壁時計/メモリ連番で代用しない。回復後の同一ID再照会も必要。成功時でも限定合成テスト`PASS`であって強いHC06全体のPASSではない。

**結果分類:** `PASS` / `FAIL` / `UNPROVEN`（順序/独立性/耐久強制の証拠不足） / `COUNTEREXAMPLE_OBSERVED`（意図的脆弱baseline）。fail-open 0、誤`revoked_complete` 0、同じCheckoutで二重operation/outbox 0を目標とするが**今回いずれも実測していない**。

## 5. 費用・可用性・セキュリティ・cleanup（見積りであり実測なし）

- **費用案:** ローカル既存Mac/隔離環境で実行する場合、追加GCP費用は発生しない設計。CPU/RAM/ディスク/電力/管理時間は消費する。PG16インスタンス2つと隔離volumeは単一PGより重い。**現在実機の空き容量・リソースは未測定**。
- **CI:** 本Stepでは新CIなし。将来GitHub Actionsを実施する場合、利用枠/実行時間・2PGインスタンス対応・artifact保持日数・秘密情報不要性を事前確認。**無償や無制限とは断定しない**。まずローカル限定を推奨。
- **外向き通信:** 実Authority/API、クラウド、公開HTTP、署名鍵・個人情報・実決済を扱わず、ローカル・内部接続のみを前提とする。Docker/PGパッケージ取得が必要なら、通常の依存取得も**後続の明示承認に含めて**計画する。
- **異常時:** Authority応答不可、abort中断、Host状態不明なら`PENDING/STOP`（失効完了や注文成功にしない）。**安全側の長期ブロック**は想定し、実験のtimeoutで強制`R_effective`にしない。利用者向けUX/SLAの許容値は未決。
- **cleanup:** 将来の隔離volumes・process・ポート・temp logsを実行後に列挙し、他PJに影響しない形で破棄。開始前に削除対象を固定し、共有Docker/PGや既存DBを削除しない。クラウドresource作成は一切対象外。

### 将来の着手前ゲート（今回は未通過）

1. **安全ゲート:** Durable abort gateが実際に**全Cコード経路を抑止**できるトランザクション規則と、AuthorityがC/abortをいつ確定とみなすかについて、研究用の有限状態機械と負例を確定する。証明不能ならハーネス実装を保留して設計を修正。
2. **環境ゲート:** 実機容量、PG16を2つの独立インスタンスとして隔離、worker SIGKILL/restart、local-only接続、確実なbarrier/cleanupが可能か確認。
3. **承認ゲート:** 対象`E-R01/E-R02`の最小研究コードだけを**別途ユーザーが明示承認**する。GCP・実API・本番・Gem/API・Receiptは無断実装しない。

## 6. 決定記録・限界・次のおすすめ1件

**P1-10fは実装採否の文書評価のみ完了。実行0件、CI/テスト/DB/外部サービス新規作成0。** 推奨は「必要ゲートを満たすならBのローカル独立Ruby worker/PG16×2で、まずE-R01/R02だけを**将来の別承認で**実験」。本Stepから実装GO・本番GOは出さない。共通物理ホストの障害ドメイン、外部AuthorityのAPI保証の不存在/不明、R/C線形化の未証明、Provider D/その他10計画IDが最大の限界。

**歴史的証拠:** Host正本34件中9件実測・25 NOT RUN（12 runs/465 assertions、[過去のPG16 CI](HOST_REPLAY_P110A_EVIDENCE.md)）。P1-10cの8 runs/94 assertionsは単一Rubyプロセスの別証拠。**HC06分散安全性HOLD、N17 stateless replay HOST_BOUNDARY、P1-4 G1〜G6/P1-7 T1〜T5、公式Python SDK中間hop 186 PASS/2 FAILは未解決。Gem/API・本番Host統合HOLD、RubyGems公開・Production/実決済・署名Receipt NO-GO。** 自己レビューは独立したセキュリティ監査でない。

**次のおすすめ1件（別途承認後のみ）：P1-10g** — 本決定の3つの着手ゲートを先に満たし、**E-R01/R02だけ**の隔離オフラインハーネスと独立した耐久ログ/障害注入を最小限実装して実測する。ゲート未達なら安全なabort設計へ戻り、コードを増やさない。
