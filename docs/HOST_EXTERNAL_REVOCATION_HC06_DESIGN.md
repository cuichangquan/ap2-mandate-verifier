# P1-10b — HC06 外部資格失効とHost COMMIT境界：設計・テスト戦略のみ

**記録日：** 2026-10-11 JST  
**正本テストID：** [HC06](HOST_SECURITY_TEST_PLAN.md)（Verifier成功後・Host DB COMMIT前にIssuer/Agent/Buyerの許可が失効）  
**状態：** **DESIGN ONLY / NOT RUN / HC06 HOLD**。この文書は実装・実証・独立監査ではない。  
**仕様基準：** AP2 v0.2.0 固定Git commit `b4587ac1d055888a73b4b21750973cffba961793`。下記のHost整合性・失効制御は本OSSの提案方針であり、AP2が規定するトランザクション方式ではない。

## 1. 何を防ぐのか

例：12:00:00.000にBuyerのMandate署名検証が成功し、12:00:00.100に外部Identity/ConsentサービスでBuyerの代理購入権限が**取り消された**。Hostがその後の12:00:00.150に旧情報で注文用operationをCOMMITすることを防ぎたい。

[HOST_SECURITY_CONTRACT](HOST_SECURITY_CONTRACT.md)上の `VerifiedEvidence` は**検証時点の署名と委任情報の証拠**であり、後のIssuer鍵失効・Agent使用停止・Buyer同意撤回を保証しない。最終的な取引許可はHostの責務。[HR10の実測](HOST_REPLAY_P110A_EVIDENCE.md)は**同じPostgreSQL**でCheckoutとBuyer policy行を互いにロックできた場合だけであり、外部失効サービスとの整合性を証明していない。

### 時点・用語（混同禁止）

| 記号 | 意味 |
| --- | --- |
| **V** | stateless VerifierがMandateを検証した時刻（購入許可ではない） |
| **Q** | Hostが外部Authorityの許可状態を取得した時刻。応答が示す「いつの状態か」も別途必要 |
| **R** | **Authoritativeな失効が有効になる線形化時点**。ユーザーによる「取り消しボタン押下時刻」と同一とは限らない |
| **C** | Hostがnonce消費＋Checkout予約＋operation/outboxを単一DB transactionで確定した時点 |
| **D** | 外部Providerへoperationを送出・適用する時点（Cとは異なる） |

**目標HC06（理想的な強い契約）：** 正式に有効となったRがCより前なら、Hostは新しいoperationを確定しない（**STOP、nonce未消費、operation/outbox 0**）。RとCが競合する際は、その前後関係を信頼できる機構で一意に決める必要がある。**Vの成功、Hostの時計の比較、単なるQの成功ではRとCの順序を証明できない。**

さらに**RがCの後・Dの前**なら、すでにCOMMITしたoperationは自動的に未確定にはならない。配送前に再確認/一時停止するか、すでに外部送出された操作を補償するかは**別の政策・検証ゲート**。ここで「取消成功＝支払取消完了」とは主張しない。

## 2. 信頼モデル・誰が失効を決めるか

- **Issuer:** 署名に使う鍵とIssuerとしての認定、許容用途、鍵のrotation/revocation。トークン内の自己申告 `kid`/`jku` を失効情報・信頼根拠として採用しない。
- **Agent:** Hostが承認済みのAgent IDと公開鍵、tenant/Buyerとの結び付き、操作権限の停止・委任のscope変更。
- **Buyer:** Hostが信頼できるIdentity/Consent/Account authorityから得た利用資格、同意、Buyer block、代理購入許可・停止。
- **Merchant/Checkout:** 現在の署名済Checkout原文、版、金額・通貨等のHost正本。これはHC04/HR10の別の検証責務と交差するが、HC06の合格に便乗してPASSにしない。

外部Authorityからの信頼済みレスポンスには**発行元の認証、subject/tenant/purpose、権限scope、明示的status、単調なversion/epoch、読み取り整合性を示す根拠、issued/observed_at、有効期限またはlease/fence、request correlation**を要求する設計とする。単なる `allowed: true`、TTLキャッシュ、イベント受信済みフラグ、時刻だけでは「最新」の証明にならない。epochは外部Authorityが定義・保証するものとし、Hostが自分で増分した数字をAuthorityの失効順序として扱わない。

外部照会は**事前登録された信頼先**だけへ実施。提示Mandate由来のURLへ通信しない（SSRF、恣意的Issuer鍵取り込みを避ける）。現在のRepoはこうしたAuthorityクライアントや同期プロトコルを提供**していない**。

## 3. なぜ「COMMIT直前に照会」だけでは足りないか

失敗例（いわゆるTOCTOU）：

```text
Host                           外部資格Authority                 Host DB
  | V: 署名検証成功                    |                                |
  | Q: permitted? ------------------>|                                |
  | <------------------------ ALLOW  |                                |
  |                                    | R: BUYER REVOKED              |
  |                                    |                                |
  | DB nonce CAS + operation/outbox ----------------------------------->|
  | C: COMMIT (旧ALLOWを使用) ---------------------------------------->|
  |                                    |                                |
  ! R < C なのにcommit済み：HC06に違反
```

外部照会QとDBのCOMMIT Cを**別の整合性領域で行う限り**、二つの間にRが割り込める。QをCOMMIT直前へ移してもゼロにはできない。Host DB `SELECT ... FOR UPDATE` は**外部Authority内の更新を停止させない**。Signed JWTの有効期限やキャッシュTTL、polling間隔も「即時失効」の線形化保証を与えない。ネットワーク/Clock skewを無視した`R.timestamp < C.timestamp`の比較も信頼できない。

## 4. 候補方式（安全性と実用性を区別）

| 方式 | 保証可能な範囲 | HC06での判断 |
| --- | --- | --- |
| **A. 毎回のAuthority再照会 + Fail Closed** | レスポンス時点で明らかに失効済みならSTOP。失敗/unknown/staleならSTOP。RがQとCの間にある場合は防げない | **比較用baselineのみ**。即時失効と競合するHC06の強いPASSを主張しない |
| **B. 単一のシリアライズ可能な認可境界** | Authorityの失効とHost最終操作を**同一の正本/ロック/線形化順序に含める**設計なら、同じ権限についてRとCを順序付けられる | **強い保証の参照モデル**。ただし外部Authorityが独立DBなら、単に「SERIALIZABLE」と書くだけでは不十分 |
| **C. Authority発行のfenced authorization/予約lease** | Authorityが認可予約に一意な`epoch + fencing token`を付け、失効と競合する確定操作を**Authority側の原子的手続き**で直列化し、古いfenceの確定を拒否できるなら保証を設計可能 | **将来の厳密実装候補**。全境界でfence強制と失効の有効時点定義が必要。Host DB側だけのfenceでは不十分 |
| **D. 有効期限付きlease中の失効を延期** | 有効lease中の権限を約束し、失効をlease終了または予約解放まで**まだeffectiveにしない**契約により、成立する操作の時間幅を説明できる | **「即時失効」とは異なる業務意味**。ユーザーが取り消しを押しても一定期間取引可能ならその遅延をUI・規約で明示する必要 |
| **E. 非同期イベント/Redisキャッシュ/epochミラー** | 同じ正本に到達したことが**確認できた更新**なら保護できる。伝播未確認、消失、順序逆転時は古い状態 | **単独では不可**。R前後の即時保証はない。欠落を検知できずunknown扱いできなければFAIL |

**推奨する研究順序：** まず方式Aを**明確な不十分なbaseline**として示し、次にB/Cのいずれが現実のAuthorityと実現可能かを調査する。現段階では外部Issuer・Consentプロバイダがfenced reservationや同期commitを提供するか未確認のため、どちらも採用決定しない。**強いHC06はHOLD**。業務的に短い遅延失効を許容するDを選ぶなら**「即時取り消し」ではない**ことをユーザーに明記し、セキュリティ主張を縮小する。

## 5. 将来のHost最終判定API/State設計（擬似契約のみ）

**入力（Host側の信頼済みcontext限定）：** `tenant_id`、`checkout_id/version/fingerprint`、`challenge_id + nonce_digest`、`verified_evidence_ref/verified_at`、`issuer_key_id + authority_scope`、`agent_identity + authorized_scope`、`buyer_account_binding`。提示Mandateに含まれる自称値をHost権限として昇格しない。

**外部Authority返却モデル候補：**
- `PERMITTED` + subject/tenant/scope + authoritative epoch/version + 有効時刻/有効期限 + integrity/issuer provenance + **明文化した整合性保証（ある場合のみ）**
- `REVOKED` / `DENIED`：Host **STOP**、新たなnonce消費・operation/outbox作成を行わない
- `UNKNOWN` / `STALE` / `TIMEOUT` / `UNAVAILABLE` / `EPOCH_ROLLBACK` / `SCOPE_MISMATCH`：Host **STOP/PENDING、成功扱い・自動別nonce使用禁止**

`PERMITTED`を受けた後もそのまま許可へ進めない。**Authorityの保証モデルに応じたfinal gate**（共通の同期境界、あるいはfenceの真正性・競合順序・適用側の受理条件）を満たさなければ**STOP/PENDING**。使用済みnonceを失敗のたびに不可逆消費すべきかは別のDoS安全性判断であり、未決定。

### 原子化・障害時の期待

1. Host DB内では既存[HR10研究](HOST_REPLAY_P110A_EVIDENCE.md)のCheckout → policy lock順序・nonce CAS・unique operation・outbox原子確定を前提とする。
2. **外部Authorityとの線形化点**を明文化できなければ、DB行ロックで代替したとは言わない。DB transaction中の長い外部HTTP待機は避ける。timeout時に「多分許可」を作らない。
3. `C`が不明なら、既存[HR06研究](HOST_REPLAY_P19C_EVIDENCE.md)の原則通り、**同じoperation/keyをDBから照会するまで新しい送出をしない**。`PENDING`を購入成功Receiptへ昇格させない。
4. 失効確定後に既存のCOMMITTED operationや外部Dが見つかった場合は、失効のeffective時点とfence/operation記録に基づき**後続停止・調査・補償**を別のステートとして扱う。二重課金防止はProvider側Idempotencyの別証明が必要。
5. 失効の応答をログに保存する際は**匿名化された参照・Authority ID・epoch/理由コード・相関ID・照会/判定時点**だけ。生Mandate、nonce原文、個人情報、秘密鍵、Authorizationヘッダを保存しない。

## 6. HC06の試験マトリクス（ここではすべて**NOT RUN**）

**将来の2独立Authority/Hostシミュレータ**が、イベントバリアと線形化ログを持ち、RとCの順序を強制する設計が必要。PRで**新規コード・テスト・CIは作成しない**。

| 仮ID（HC06の内訳・正本ID追加ではない） | 注入する状況 | 期待結果と合格証拠 |
| --- | --- | --- |
| HC06-A | V成功 → Authority R確定 → Host final check | **STOP**、nonce ISSUED、operation/outbox 0。R有効化時点とHost queryをAuthorityログで観測 |
| HC06-B | V成功 → QでALLOW → **R確定** → C試行 | **STOP**が強い契約の合格条件。単純再照会方式Aは**意図した脆弱性を示すNEGATIVE baseline**。B/Cで実現しない限りHOLD |
| HC06-C | 最終認可/予約が先 → R要求が競合 → C確定 | 権威側が一意の順序を記録。「Cが先に合法確定」なのか「Rが先でSTOP」なのかを**曖昧にしない**。遅れた取消で過去commitが自動取消と主張しない |
| HC06-D | Issuer key revoked, Agent delegation revoked, Buyer consent revoked の**各々** | 全員を対象に主体ID・tenant・scope・epochの取り違えをSTOP（単一Buyerテストを全Identity保証へ拡張しない） |
| HC06-E | Authority timeout/HTTP失敗/unknown/遅延キャッシュ/失効イベント欠落 | **成功応答しない**。新規operation/outbox 0、fail-open 0、再送も許可へ昇格させない。HC07との境界は別途整理 |
| HC06-F | 古いepoch、順序逆転イベント、別tenantのfence、重複/期限切れlease | **STOP**。古い権限スナップショットの再利用不可。revocationが先なのに後からALLOWを受け付けない |
| HC06-G | C確定 → R確定 → 外部D送出待ち／すでにD実行 | `D`の順序と取消処理結果を正しく報告。自動取消や二重課金防止は主張しない。Provider/補償の別Gate |
| HC06-H | Crash/unknown commit/fencing reservation expiry | 曖昧なら**PENDING/STOP**、同一operation再照会、新規送出禁止。失効情報の既定値をALLOWにしない |

**受入れ条件（将来）:** (a) RとCの**権威的な順序**を機械検査できる、(b) R<Cなら全経路で新規 operation 0、nonce消費0、(c) 不明/失敗/不整合ではfail-open 0、(d) 既存operationは二重送出しない、(e) 4つの資格類型とtenant/scopeに跨る境界試験、(f) **実際に実行したCI/run/環境/失敗ログ**のみを証拠として記録。A/Hなどの共通ケースはHC06を8件実行したと数えない。

## 7. 決定事項・未決・GO/HOLD

**設計決定：**
1. **HC06は外部失効Authorityの保証モデルが確定するまで実装GOにしない。** 同一PostgreSQLのHR10 PASSを外部整合性へ外挿しない。
2. Authorityの`ALLOW`は、認証・scope・epoch・一貫性モデル不明なら**UNKNOWN**と扱う。同期失敗時は**STOP/PENDING**。
3. **理想契約 R<C→STOP**と、短命lease等の**失効遅延を認める弱い契約**を混同しない。どの契約を商品/UXが許容するか未決。
4. 静的`VerifiedEvidence`、Hostの最終`ExecutionDecision`、Authorityの可変失効情報、DB operation/outbox/Provider効果を別の責務として扱う。
5. 新規の正本HostテストPASSは**0件**。前Stepまでに正本34件中**9件実測・25件NOT RUN**。**HC06は引き続きNOT RUN**。本PRはdocs-only、ActionsのPG16テストを実行していない。

**未決・別承認事項：** Authorityが提供する線形化・fencing API、失効をeffectiveにする業務時点、leaseによる取消遅延の受容可否、Dispatch時点の追加確認/compensation、クロック・署名済み失効応答の具体的フォーマット、実験fixture作成範囲と費用。各々承認なしに外部接続やデプロイを行わない。

**GO/HOLD:** **P1-10bは設計資料の完成・レビューのみGO**。HC06実測・T1/T2/T3全体の達成は**HOLD**、Gem/public API/Production/実決済/Receipt・RubyGems公開は**NO-GO**。N17 stateless replay HOST_BOUNDARY、P1-4 G1〜G6の未完、公式Python SDK中間hop aud/nonce 186 PASS/2 FAILも継続。

**次の1件（新たなユーザー明示承認後のみ）：P1-10c** — HC06の**方式AのTOCTOU負例**と、**fenceがある場合とない場合の差**を、完全架空の2論理Authority/Hostスケジューラでオフライン実測する**検証計画→最低限の実装**を提案。最初から実Authority/GCP/本番コードには接続しない。実験後も外部プロトコルとの互換・本番安全性は別ゲート。
