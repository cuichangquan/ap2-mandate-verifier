# P1-10d — HC06 外部AuthorityとHostの失効・確定協調プロトコル設計

**2026-10-11 JST / DESIGN ONLY / NOT RUN / 実装未承認。** 対象は[HC06の正本](HOST_SECURITY_TEST_PLAN.md)、[P1-10bの設計](HOST_EXTERNAL_REVOCATION_HC06_DESIGN.md)および[P1-10cの合成反例](HOST_EXTERNAL_REVOCATION_P110C_EVIDENCE.md)で生じた**別サービス・別トランザクションの隙間**のみ。外部Authority、Ruby Gem/公開API、決済、Receipt、GCP、CI/testコードは作成しない。AP2公式v0.2.0固定commit `b4587ac1d055888a73b4b21750973cffba961793`。以下の失効予約・fencingは本OSSのHost安全設計案であり**AP2プロトコルの標準機能ではない**。

## 1. 主張する安全性を先に固定する

### 用語と責任者

| 時点・状態 | 決める正本 | 意味 |
| --- | --- | --- |
| `V` | Stateless Verifier | 署名などが検証時点で正しい。業務の購入許可ではない |
| `Q` | 外部Authority | 権限状態の照会・キャッシュ受信。「将来も有効」の証明ではない |
| `P` | 外部Authority | checkout/tenant/主体/scopeに束縛された**排他的または直列化可能な認可予約の確定**。単なるtoken発行と区別 |
| `R_request` | Buyer/Issuer/Agentなど | 失効を**要求**した時点 |
| `R_effective` | 外部Authority | 失効が**正本上で有効になった線形化点**（ボタン押下時刻と同一とは限らない） |
| `C` | Hostの耐久DB | nonce CAS、Checkout予約、operation/outboxの**実COMMIT** |
| `D` | 外部Provider等 | コミット済operationからの外部実行・送出。CとDは別 |

**強いHC06安全条件（目標であり実証していない）：** `R_effective < C` なら新規の`C`は禁止（nonce未消費、operation/outbox 0、Host STOP）。`C < R_effective` でも既存operationの事後取消・返金・外部D停止は**自動ではない**。失効要求 `R_request` 時点から「必ず新規注文禁止」を要求するなら、これはより厳しい別の契約：予約中取引を中断して安全な取り消し完了を確認できるまでは、取消を**完了扱いにできない**。どの契約を顧客に約束するか未決。

以下は`R_request`到着と`R_effective`成立の**遅延を許す**候補も含む。即時取消を約束するプロダクトに、遅延有効化を隠して採用するのは不可。

## 2. 本当の問題：権威の線形化とDB COMMITを別々に行うこと

```text
Host                           External Authority            Host PostgreSQL
  | Q=PERMITTED ------------------>|                              |
  | <--------------------- ALLOW   |                              |
  |                                | R_effective: revoked         |
  | CAS nonce + insert operation ------------------------------->|
  | C: COMMIT -------------------------------------------------->|
  X  R_effective < C なのに確定 → HC06違反
```

`fencing_token`も、検査とCの間に別の状態変更を割り込ませられるなら同じ問題が残る。[P1-10c](HOST_EXTERNAL_REVOCATION_P110C_EVIDENCE.md)の`Mutex`は両者が同一プロセスだったから成立した**人工の排他境界**。実際に離れたAuthorityの`validate_fence`応答を受けた後でHostがCOMMITする方式は、**それだけでは分散トランザクションではない**。

## 3. 比較する協調方式と厳密な前提

| 方式 | 安全性が成り立つ前提 | 代償・判断 |
| --- | --- | --- |
| **A. 再照会＋短命TTL** | Q時点の失効を検出するだけ | QとCのTOCTOUを残す。**即時失効のHC06はNO-GO** |
| **B. 失効の正本とHost確定の共有直列化境界** | どの失効もどのCも**同じ権威的な順序**に入る。同じDB行ロック等を**全経路**が強制 | 強い参照モデルだが、外部Authorityが別DBで独立してRを確定するなら前提が成立しない |
| **C. Authority側の予約＋fence＋失効有効化の保留** | Pで権利を予約。R_requestは競合しても**C結果が耐久的に解決し、以後Cできない状態が確立するまでR_effectiveにしない**。予約の解放・失効の順序がAuthority正本に記録される。Host側にも古いfenceのCを禁止する**強制可能な境界**が必要 | **設計候補（未採用）**。停止中/partition中の予約は解除できずRが保留になり得る。単にlease時間切れとしたり、Authority側だけfenceを更新すると安全性が破れる |
| **D. Coordinator/prepareを伴う分散commit（例：対応参加者の2PC）** | AuthorityとHost DBが対応するprepare・耐久ログ・決定の回復・競合するRのロック保持・解除規則を実装。**R_effectiveをCと順序付けられるまで保留** | デッドロック/長期ブロック、復旧と運用コストが大きい。**外部Identityサービスが2PC等を提供する事実は未確認**。方式名だけでは保証にならない |
| **E. 非同期イベント・ローカルepochミラー** | 伝播を受信・確認した時点以降の制限しか説明できない | 発行元でのR_effectiveとC間のレースが残る。強いHC06の根拠に採用不可 |
| **F. 失効遅延を明示する有限lease契約** | Authorityが権限の効力をlease終端まで明示的に保証し、R_effectiveを契約に従って延期し、Hostも失効後に遅延COMMITできないよう確実に抑止する | 可用性の選択肢だが**ユーザーが取消を要求した瞬間に止まる契約ではない**。時計・expired lease・in-flight commitを扱わない単純TTLは不可 |

**設計上の結論：** AuthorityのAPIが具体的に提供する`reserve`・`revoke`・`finalize/abort`の直列化保証と、HostのCOMMIT障害回復方法が明らかになるまで、**C/D/Fの方式にGOを出さない**。単なる`epoch`文字列や署名済みALLOWは、原子的な発行・失効・消費規則の代用品ではない。

## 4. 候補Cの協調状態遷移（実装手順ではない）

Authority側の**権利単位**（Issuer key / Agent delegation / Buyer accountと必要なtenant・scope）ごとに、少なくとも次を区別する。

```text
ACTIVE(epoch=e)
   | P: reservation accepted (only while ACTIVE)
   v
RESERVED(e, reservation_id, operation_id, context)
   | R_request arrives -> REVOKE_REQUESTED (NOT yet effective)
   | Host C confirmed durably; future C using reservation impossible
   +-> FINALIZED -> R_effective, if pending
   | Host abort confirmed durably; future C using reservation impossible
   +-> ABORTED   -> R_effective, if pending
   | timeout / crash / unknown C
   +-> UNKNOWN / RECOVERY_REQUIRED (do NOT infer ABORT/REVOKED_EFFECTIVE)
```

これは**リソース予約・失効保留の方向性を示すラベル**であって、Host DBとのアトミック性を実装していない。**R_requestを受理することとR_effectiveを確定させることは別**。未知のCOMMITの間にAuthorityが「タイムアウトだから失効確定済み」と返すと、後着のHost COMMITがR後に成功する恐れがある。

### 実装可能性を判定するための必須条件

1. **全権限の束縛：** Authority ID、tenant、Buyer/Agent/Issuer、scope/purpose、checkout ID/version/fingerprint、challenge参照、operation ID、idempotency key、authority epoch、reservation IDをTrusted Host文脈から相互に結び付ける。token内の自己申告先URLやIssuer自己鍵を信用しない。
2. **権威的な単調順序：** PとR_effectiveに重複・ABA・別tenant再利用のない確定順序があり、Issuer/Agent/Buyerの複数Authorityを使う場合は**全員の許可を同期的に保護する方法**を証明する。1 Authorityのfenceだけでは他Authorityの失効に耐えない。
3. **Host側の耐久性：** 同じ予約へのCOMMITは最大1回。nonce CAS、Checkout state、operation、outbox、reservation referenceを**同一Host DB transaction/unique制約**で記録。既存[P1-9a〜10aの実DB研究](HOST_REPLAY_P110A_EVIDENCE.md)の証明範囲外にあるreservationとの協調は新規研究が必要。
4. **fenceの強制点：** R_effective前にHost Cが起きたこと、またはR_effective以降にHost Cが**必ず不可能**なことを保証できる原子的な決定規則が必要。Authorityからの`ALLOW`を受けてからHostだけでCOMMITする非原子的経路は禁止。
5. **取消要求の応答：** `R_request=accepted`と`R_effective=confirmed`の別ステータスを要求。予約が残るなら「取消完了」「決済停止済み」と表示しない。遅延失効や保留には明確な上限/運用責任/ユーザーへの説明が必要。
6. **外部Provider送出D：** Host C後のDは別フェーズ。R_effectiveがC後/D前に発生した際に停止する必要があるか、誰がどのレースを直列化するかを追加決定する。予約の完了は決済成功/署名Receiptの作成を意味しない。

### 擬似的な合格フロー（**分散原子化の部分は未実装・未決**）

```text
Host: validated evidence (V), no execution ALLOW
  -> trusted Authority set resolved; get durable operation identity
  -> P: obtain reservation(s) with scope/epoch/context binding
  -> [UNKNOWN? STOP/PENDING; REVOKED? STOP]
  -> *** required distributed finalization/serialization boundary ***
  -> C: Host atomically consume nonce and create operation/outbox OR abort
  -> reconcile C outcome from durable Host state (no guess on missing ACK)
  -> Authority finalize/abort; only then may pending R become effective
  -> D: separately controlled dispatch with same idempotency key
```

**このフローをそのまま2つのHTTP呼び出し＋DB COMMITとして実装してはいけない。** `***`の境界の実装と証明が欠けているからである。

## 5. 障害・割り込み・リカバリの判断表（設計上の期待、NOT RUN）

| 挿入点・故障 | 避けたい誤動作 | Host / Authority の安全側期待 |
| --- | --- | --- |
| R_effectiveがP前 | 古いALLOWで新予約 | AuthorityがPをSTOP。新nonce消費とoperation/outbox 0 |
| Pが先、R_requestがC前 | 取消要求を即時完了と嘘表示 | R_effectiveを保留する設計なら**pending**として表示。即時停止を要求するならCを確実に禁止してからR確定（未設計） |
| P成功のACK喪失 | 予約の二重発行・消去 | 同じ`reservation_id/operation_id`をAuthority正本から再照会。unknownならSTOP/PENDING |
| Host C前の障害 | 未確定の許可を処理済みにする | Host DB照会で確定が無ければ安全な中止・fence無効化を証明してからabort。未解決はPENDING |
| HostがCOMMIT送信、ACK喪失（HR06） | Hostが勝手に新operationを発行 / Authorityが早すぎるR確定 | Host durable stateとin-flight COMMITの消滅/最終結果を照合。未確定なら予約解放禁止・D禁止 |
| C成功、finalize前のHost crash | 予約を期限で消去して過去Cを見失う | Cの同一operation/outboxを読み戻し、finalizeをidempotent再試行。Cは1件、Receipt成功は未確定 |
| Authority切断/応答未知 | optimistic ALLOW / 失効を無視 | 新C/Dを発行せずPENDING。事後にAuthorityの権威ログを照会 |
| 予約期限切れと遅延Cが競合 | R_effective後の遅延COMMIT | **Hostで遅延C不可能がdurableに証明されるまで**期限切れのみで予約解放しない。できなければHC06 HOLD |
| 二重worker、重複予約、古いepoch | 旧fenceで再購入・cross-tenant権限昇格 | unique operation、単調epoch、主体・tenant/scopeのバインド、予約消費の一回限り |
| 別Authorityの一つだけ失効 | 残りの許可で購入 | all-required trust setを保持。1つでもREVOKED/UNKNOWNならSTOP/PENDING。分散一貫性は未実証 |
| C後・D前のR_effective | 注文を消去した／外部送出が止まったと誤報告 | Cはdurableのまま。Dの停止/取消・期限・補償は別状態機械/別実測 |
| Dのtimeout/結果不明（HR07） | 二重課金・虚偽成功Receipt | 同じoperation/idempotency keyとProvider結果の照会。新operation/新chargeを推測で発行しない |
| 誤った時計/古いキャッシュ/署名だけ成功 | stale snapshotをfinal ALLOW | Authorityの線形化/真正性を保証できない場合STOP。時計/TTLだけをfence扱いしない |

## 6. 選択前に外部Authorityへ確認する契約項目

- **APIの実在と提供保証:** どのIssuer/Identity/Consentサービスが予約P、失効R_effective、finalize/abort、fence検証、繰り返し照会を提供するのか。**この調査では未確認**。
- **失効のUXと順序:** ユーザーが取消要求を送った瞬間と、権威が失効を有効にする時点の差を、どの契約が許容するか。既存operation Cおよび外部実行Dの中断/補償可否は別。
- **atomicityと障害耐性:** Host PostgreSQLのdurable COMMITとAuthorityのRの関係を、独立したOS crash/partition/restartでも検査できるか。timeoutで永久保留する可能性と人的解決の責任。
- **鍵と権限:** trust anchor、署名/認証、rotation、tenant/purpose/scope、epoch ABA、issuer変更、ユーザー同意変更をどう識別し誤用をSTOPするか。
- **コスト/運用:** 予約保持・長期ブロックと手動reconciliationの費用、Provider送出停止のSLA、証拠の保存/最小ログ/削除方針、保持期限。
- **テストの独立性:** 次の検証では二つの独立した故障可能プロセス/永続ストア、トランザクション障壁、AuthorityとHostの確定ログを観測する。単一`Mutex`や疑似時計だけで本番相当と主張しない。

## 7. 研究判断・次の1件

**P1-10d：文書設計の完了だけGO。HC06の強い外部失効同期はHOLD。** 自己レビューは独立したセキュリティ監査ではない。未実装/未実測であるため、本PRに新しいCI実行・実DBテスト・公開API変更を要求しない。既存の[Host実PG16研究](HOST_REPLAY_P110A_EVIDENCE.md)は正本34件中9件実測、25件NOT RUN、12 runs/465 assertions PASS（過去のCIに基づく）。[P1-10c](HOST_EXTERNAL_REVOCATION_P110C_EVIDENCE.md)の8 runs/94 assertionsは**合成モデルのみ**で正本HC06全体をPASSにしない。

N17 stateless Verifier HOST_BOUNDARY、P1-4 G1〜G6/P1-7 T1〜T5、公式Python SDK中間hop 186 PASS/2 FAILは未解消。**汎用Gem/API、Host本番連携HOLD、RubyGems公開・Production/実決済・署名Receipt NO-GO**。

**次の1件（別途明示承認後のみ）：P1-10e。** まず本書の判断表から**Pが先でR_requestが来る／COMMIT ACKが不明／timeoutで予約解放したい**という3つの難ケースを選び、**独立した合成Authority/Hostの状態遷移テスト設計だけ**を行う。実DBや外部Authorityを起動するかどうかは新しい承認が必要。Gem/API/実決済/GCPには触れない。
