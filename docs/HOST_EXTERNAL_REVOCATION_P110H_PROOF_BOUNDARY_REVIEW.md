# P1-10h — HC06 AuthorityがHostのfinalize報告を信じる境界の安全設計レビュー

**2026-10-11 JST / DESIGN REVIEW ONLY / ALL NEW CASES NOT RUN。** 本Stepは[P1-10g実測](HOST_EXTERNAL_REVOCATION_P110G_EVIDENCE.md)で明らかになった**架空Coordinator→Authorityのfinalize信頼境界**だけをレビューする。**コード、DB、worker、CI、テスト、公開Gem/API、外部Authority/API/GCP、実決済、署名Receiptは追加・実行しない。**

公式AP2の固定基準は**v0.2.0 / `b4587ac1d055888a73b4b21750973cffba961793`**（変更しない）。以下の権限予約・中止証拠・`finalize_abort`は本OSSの**Host研究モデル**であり、AP2公式規格が定めるAPIや署名Receiptではない。

## 1. 確認した実装上の穴（推測ではなくコードに基づく）

[`research/p1_10g/worker.rb`](../research/p1_10g/worker.rb) のAuthority側には以下の分岐がある。

- `role=authority / action=finalize_commit|finalize_abort`はCoordinatorが呼び出した種類を`FINALIZED_COMMIT`または`FINALIZED_ABORT`に読み替える。
- Authority専用PG内で`reservation_id`、`state='RESERVED'`、`revoke_requested=true`、`revoke_effective=false`を満たせば、`state=$1,revoke_effective=true`に更新してイベントをCOMMITする。
- **Hostから取得した証拠の認証、Host側のdurable decisionの独立照会、`abort`に伴う将来C禁止の強制ゲート、Host/Authorityの同一operation・tenant・scope・epoch・Checkout版の照合は、このAuthority分岐では検査されない。**
- [P1-10gテスト](../research/p1_10g/test_independent_hc06_pg.rb)のCoordinatorが別Host接続で`ABORTED`/`COMMITTED`を読み戻し、**正しい順で呼び出す**ため、限定合成2ケースがPASSした。この試験は**Coordinatorが嘘をつく／改ざん・再送する／切断する**場合の証拠ではない。

したがって**現状のAuthority finalizeは安全な失効確定APIとして採用不可（HOLD）**。この事実はP1-10gの2 runs/118 assertions成功と矛盾しない。署名した`"aborted"`文字列を追加するだけでも、発行者・DB耐久結果・未来のC禁止を裏付けるものにはならない。

## 2. 失効が有効になるための安全条件・信頼境界

| 主体 | 信頼できること／**してはならないこと** |
| --- | --- |
| Authorityの耐久状態 | `P`、`R_request accepted`、`R_effective`の**権威的な状態と遷移**。Hostの単なるメッセージからCが不能になったと推定しない |
| Hostの耐久DB/強制gate | `C_DURABLE`（nonce CAS＋Checkout＋operation/outboxが同一トランザクションで確定）、または`ABORT_DURABLE`（以後**同じreservation/operation/scopeの全C経路を必ず止めるgate**が永続確定）を決める正本 |
| Hostの決定発行サービス | 将来候補：**事前登録されたHost service identity**で、上記と同一原子的決定に対応する証拠を公開する。ただし署名・mTLSは**発行者／輸送路の認証**であり、Host自体の故障や虚偽証明、他経路バイパスへの保証ではない |
| Coordinator / queue / retry / 通信経路 | **untrusted relay**として扱う。メッセージの送達・重複排除・並び順だけに最終認可を委ねない。Coordinatorが主張する`finalize_*`を単独で信用しない |
| 本番Issuer/Buyer/Agent等 | 実権限、委任、他の失効源は**今回存在しない**。ローカルHost中止をもって実Issuer権限全体の失効を保証しない |

目標（**未実証**）：権威的に`R_effective < C`なら新規Host Cなし、nonce未消費、operation/outbox各0。`C < R_effective`なら**その既存operationは残る**。`R_request`受付は失効完了ではない。R_effectiveを確定できない場合は**PENDING/STOP/RECOVERY_REQUIRED**にとどめ、期限やACK欠落から`effective`を推測しない。

**重要な不可能性境界：** Authorityから物理・管理的に独立したHostが**悪意ある/破損している**場合、Host自身の署名付き`ABORT_DURABLE`発言だけで「将来Cしない」を証明することはできない。Hostが必ずgateを通るという**信頼前提、強制権限、復旧規則、全C経路の監査**が必要。Hostを信用しない強い脅威モデルなら、同じ直列化権限を持つ正本境界/参加者型分散commit等の**別アーキテクチャ**が必要。方式も外部Authority対応も未選定で、HC06強保証は**HOLD**。

## 3. 将来のHost decision evidence契約（提案のみ・未実装）

### 3.1 Authorityが受け取る前の必要条件

1. **Host実体の固定:** Host identity、証拠発行権限、鍵識別子、許可されたAuthority/tenant/scopeをAuthority側の**信頼済設定**から取得。メッセージに書いた`iss`/`kid`/JWK/URLを無条件に信用しない。鍵の失効・交代、権限剥奪、内部侵害時の扱いも契約に含める。
2. **同一操作への束縛:** Host ID／Authority ID、tenant、Issuer/Agent/Buyer（適用する場合）、scope/purpose、trusted Checkout ID+version+fingerprint、challenge/nonce **digest**、`reservation_id`、`operation_id`、stable idempotency key、epoch/fenceを**Authority自身の保存済みP**と完全一致照合。原文のMandate/nonce/秘密鍵は不要。
3. **単一の耐久決定:** Hostが**COMMITかABORTのどちらか一方**をCheckout gateと同じHostトランザクションで確定したこと、COMMITならoperation/outbox一意、ABORTなら**すべての将来C経路でdurable STOP**となる条件を要求。空のDB検索、ACK、lease期限、単なる`fence`更新は決定ではない。
4. **証拠の出所と鮮度:** 将来候補としてHostが署名したdecision envelope、mTLS/固定サービスID、fresh read/nonce-challenge、鍵有効期間とrevocationを設計。ただし**署名検証が成功しても耐久性は自動では立証されない**。真正であっても古いHostバックアップからロールバックした場合を別途防ぐ必要がある。
5. **Authorityの決定は原子的:** 同一Authority durable transaction内の`P`/`R_request`/`R_effective`を明確な条件付き更新・一意性・単調epochで確定し、証拠のdigestと決定種別を**一度だけ**結び付ける。異なる決定の二重提出やABAは**CONFLICT→STOP/調査**。信頼できるdecisionをAuthorityがいつ確定してよいか（特にHost DBとの切断時）は**未実証**。

### 3.2 最小の提案envelopeのフィールド

`evidence_version`、`purpose=host_reservation_decision`、`audience=expected_authority_id`、`host_service_id`、`key_id`、`authority_id`、`tenant_id`、`scope`、`subject_binding`、`checkout_id`/`version`/`fingerprint`、`nonce_digest`、`reservation_id`、`operation_id`、`idempotency_key`、`epoch`、`decision_id`、`decision=COMMITTED|ABORTED`、`host_durable_event_id`、`host_gate_terminal_state`、`evidence_issued_at`、`request_correlation_id`、`signature`（選定は後続）。

- **注意:** これは**草案のデータ項目**で、実Host署名証拠、AP2署名Receipt、公式規格test vectorではない。`host_durable_event_id`やDB LSNの文字列**だけでは正本の第三者証明にならない**。`issued_at`/TTLのみでACK紛失や古いCを解消しない。
- `COMMITTED`証拠は**R_effectiveより前にCが済んだ**ことをHost正本と関連付けられる場合のみ受理。既存注文が取消済みと**誤表示しない**。`ABORTED`証拠は同一reservationで**以後C不能**がHost側で強制される場合のみ受理。
- 同一`decision_id`+同一digestの再送は**状態を変えず冪等に返す**案。digest違い・decision違い・別tenant/epoch・鍵/subject不一致は不正/競合として保留し、過去の`R_effective`を巻き戻さない。

## 4. 通信障害時のFail Closed決定表（すべて**期待値、NOT RUN**）

| 将来計画ID | 状況 | Authorityが返すべき候補結果 | 理由 |
| --- | --- | --- | --- |
| `H01` | CoordinatorがHost結果を確認せず`finalize_abort`を偽造 | **REJECT / R_pending** | Coordinatorの報告は正本証拠ではない |
| `H02` | 署名元/鍵が未知、自己申告JWK、誤`audience`/Host ID | **REJECT / R_pending** | trust anchorの未確立 |
| `H03` | 正しい形式の旧`ABORTED`証拠を別reservation/operation/tenant/scopeに再送 | **REJECT / R_pending** | context完全束縛と再利用防止 |
| `H04` | 同じ`decision_id`・同じdigestを再送、ACKだけ喪失 | **IDEMPOTENT照会/同結果** | 状態変化/重複R_effectiveイベントを作らない |
| `H05` | 同じreservationに`COMMITTED`と`ABORTED`の相反する証拠 | **CONFLICT / STOP・調査** | 勝手に新しい方で上書きしない |
| `H06` | Hostが`ABORTED`を申告したが最終gateがdurableでない・in-flight Cが残る | **UNPROVEN / R_pending** | Host将来C不能の強制境界なし |
| `H07` | Host COMMIT/abort結果不明、ACK欠落、Host照会タイムアウト | **UNKNOWN / R_pending** | 行の不在・時間経過だけで中止を確定できない |
| `H08` | Host decision取得後、Authorityに届く前/後のpartition・両側再起動 | **耐久照会で再同期、曖昧ならPENDING** | ローカル時刻/通信順序だけで全順序化しない |
| `H09` | Hostがバックアップから古いOPENに戻る、古いepochでC再開 | **STOP/UNPROVEN・運用禁止** | anti-rollback・gateの継続強制が必要 |
| `H10` | 正しい署名だがHost自体が虚偽`ABORTED`を発行 | **署名だけでは防げない／HOLD** | Host trusted computing boundaryは未選定 |
| `H11` | `C_DURABLE`を確認した後の`R_effective` | **effectiveでも既存Cを取消済みとしない** | 注文/外部実行の取消・返金は別業務 |
| `H12` | lease/timeout到来、Host未応答、鍵期限切れ | **PENDING/RECOVERY_REQUIRED** | TTL/失効要求だけでgateを閉じない |

**対象は新規12個の設計レビュー用ID（`H01〜H12`）のみ。全件NOT RUN。** 既存[P1-10eのE-R/E-U/E-T計画](HOST_EXTERNAL_REVOCATION_P110E_TEST_PLAN.md)や正本Host 34 IDに加算しない。実際に通信partition・偽署名・backups・鍵rotationの故障を注入した**事実はない**。

## 5. 比較した候補と採否

| 候補 | 利点 | 欠落・採否 |
| --- | --- | --- |
| A. `finalize_abort`というCoordinator文字列のみ | P1-10gで合成テストを容易にした | **NO-GO（強い失効確定の根拠にならない）** |
| B. Host側のdurable terminal gate＋Host trust anchorに束縛したdecision envelope＋Authorityの一意性/因果検証 | Hostが信頼できる**失敗停止型**であれば安全な研究対象を具体化できる | **研究設計候補（未採用・未実装）**。Envelopeと署名だけではdurable・anti-rollback・全C経路の強制を証明できない |
| C. AuthorityとHostを同一の強制直列化正本に結ぶ/prepare-coordinator方式 | 強いR/C順序の参照設計 | 実Issuer/外部Authorityの参加・持続ロック・復旧・可用性・費用が未検証。**GO不可** |
| D. 非同期イベント、再照会、失効cache、TTL、単なるfencing token | 実装容易 | Q/R/C間レースが残る。**強いHC06にはNO-GO** |

**当面の判断:** AuthorityがCoordinatorを**無条件に信用する実装は不可**。Bは信頼するHostの耐久決定が**本当に検証できる条件**を洗い出すための設計候補であり、強い外部Authority整合性を採用できたわけではない。Cも参照上の選択肢に留める。データ真正性を確立できても**強い`R_effective < C`の線形化証明とは別の課題**である。

## 6. 引き継ぐゲート・実測数・次の一件

**本Stepの成果は脅威モデル、必要な証拠項目、H01〜H12の期待Fail Closed、候補比較という**文書のみ**。新コード/テスト/CI/DB/外部API/リソースは作成・実行していない。**R_effectiveの安全な発行条件は未証明、HC06 FULL HOLD。**

**これまでの実測（混算禁止）:** Host正本**9/34件・25 NOT RUN、12 runs/465 assertions**（[P1-10a](HOST_REPLAY_P110A_EVIDENCE.md)）。P1-10c共有Mutexモデル**8 runs/94 assertions**。P1-10g別OS worker＋PG16インスタンス2個の合成実験**2 runs/118 assertions**（[Actions #38143454171](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38143454171)）；成功はE-R01/R02限定。N17 stateless replay HOST_BOUNDARY、P1-4 G1〜G6/P1-7 T1〜T5、公式Python SDK中間hop**186 PASS/2 FAIL**未解決。

**GO/HOLD:** P1-10h文書レビューのみ完了。**Authority結果証拠の本番採用・HC06・汎用Gem/API・本番Host統合HOLD。RubyGems公開、Production、実決済、署名ReceiptはNO-GO。** 自己レビューは独立安全監査ではない。

**次のおすすめ1件（ユーザーの別途明示承認後のみ）：P1-10i** — `H01〜H06`の**合成・隔離オフライン負例**について、既存P1-10gの盲信経路で危険なfinalizeを再現し、候補の検証条件が偽造/誤束縛/重複/矛盾を**どう止めるべきか**を限定的に実験する。実装前にHostの信頼/永続gateについて試験可能な前提を明記。実Issuer/GCP/決済/Gem/API/Receiptは引き続き別承認とする。
