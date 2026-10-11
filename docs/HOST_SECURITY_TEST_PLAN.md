# Host Security Test Plan — P1-7（設計のみ・実行ゼロ）

**日付:** 2026-10-11 JST  
**状態:** **提案済み・未実装・未実行**。以下のPass条件は**合格実績ではない**。`docs/HOST_SECURITY_CONTRACT.md`を責務正本とし、本書は唯一のHostテストID正本とする。**汎用Gem/API実装HOLD、Production/実決済NO-GO。**

## 1. 計画の前提・層

- **Scope:** 単一Issuer Profile／信頼済Buyer-Agent-Merchant／単一Agent／Open→Closed 2hop／1 Merchant/1 SKUの**オフライン架空Checkout**。DirectやPayment Mandate、実課金、実ユーザーのPIIは使用しない。
- **Pinned AP2:** `v0.2.0` commit `b4587ac1d055888a73b4b21750973cffba961793`。公式Checkout MandateとMandate Receiptの義務・フィールドについては[specification L302–317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L302-L317)、[Agent Authorization L493–535](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L493-L535)を後続試験時に確認する。
- **L0 Verifier:** 既存P1-1〜P1-6の署名付き研究fixtureを再利用し、`VerifiedEvidence`相当は**現時点で仮の値オブジェクト**としてテスト仕様だけを定義。具体Ruby API/Hostコードはまだない。
- **L1 Host policy:** In-memoryの模擬信頼レジストリ・偽時計で、入力が出所・文脈に合わないとSTOPとする設計。モックだけの成功を実DBのReplay防止証明と誤称しない。
- **L2 Host atomicity:** **一時ローカルDBでの2worker／競合／障害注入が必要な将来試験**。正しいロック・一意制約・DB隔離レベル・トランザクションは別Stepで決定。L2未実行中は**Host Replay GateはHOLD**。
- **L3 execution/Receipt:** 実Paymentを使用しない**Fake Payment Provider（idempotent API模擬）＋署名Receiptの架空鍵**でのみ、将来の状態遷移とReceipt仕様を検証。本番Readyの証明にはならない。

**合格条件全体:** 偽陽性（不正入力や許可前操作が`ALLOW`、二重操作、誤Receiptとして成功）が0件。**Hostが回答不能/結果不明な時はSTOPまたはPENDING**であり、再課金や偽成功へ進まない。すべて負例は実際に該当する判定ゲートへ到達するようfixtureのHost正本を設定する（P1-3で学んだ短絡による偽カバレッジを避ける）。

## 2. Host信頼・ID/鍵の紐付け（L1、将来テスト）

| ID | 入力／障害注入 | Host期待結果 |
| --- | --- | --- |
| **HT01** | Host登録Issuer鍵で署名したRoot、正しいIssuer ID・許可用途・tenant・profile | Verifyは**検証事実のみ**、購入は未許可 |
| **HT02** | 有効署名だが**違うtenantの登録Issuer鍵**／Issuer ID switch | Host policyで**STOP**。トークンから任意鍵を自動信頼しない |
| **HT03** | header `kid`／`x5c`／`jku`が提示する未登録鍵やremote URL | **untrusted**。URL fetch・自動Trustはなし |
| **HT04** | Merchant JWTを**別Merchant IDに登録された有効な鍵**で署名 | 署名自体が成立しても**Merchant ID↔用途/tenant鍵ポリシー不一致でSTOP** |
| **HT05** | Rootの`cnf.jwk`署名は有効だが、Hostが承認したAgent登録鍵とは異なる／Buyer資格解除 | **Agent受理/Buyer業務ALLOWしない** |
| **HT06** | Issuer/Merchant鍵のrotation/失効、解決障害、古い`kid`の再利用 | 有効期間／用途／失効を確認。判断不能・使用不可なら**STOP** |
| **HT07** | 正しいRootだがBuyer/accountをHost側で解決できない | **Buyer特定済みを偽装しない**。Host STOP |

## 3. Context、Clock、Checkout正本（L1→L2）

| ID | 入力／障害注入 | Host期待結果 |
| --- | --- | --- |
| **HC01** | Host発行済`nonce`・`aud`とCheckout ID/version、tenant、Buyer/Agent bindingがすべて一致 | Verifierは一致事実を返すのみ。Hostはさらに状態・権限を判断 |
| **HC02** | Client申告のsession ID／checkout IDで別tenantのchallengeを参照 | **既存Host authenticated sessionのscope外としてSTOP** |
| **HC03** | Challengeが未発行/欠落/失効/Checkout versionと不一致、`aud`か`nonce`不一致 | Host STOP、別nonceへ自動切替しない |
| **HC04** | 検証時は正しいがHost決定前に価格・在庫・通貨・Checkout版/状態が変更 | **最新Host正本との比較でSTOP**。過去の検証成功を再利用しない |
| **HC05** | Root/Terminal/Closed `iat`/`exp`境界、注入時計±skew、Host TTL超過 | 段階ごとの時刻規則を一貫評価。期限外/未来/不明は拒否 |
| **HC06** | 検証後・DB commit直前にIssuer/Agent/Buyerの許可が失効 | **時点性を踏まえてHost STOP**。可視性/ロック/整合性の方式を検証 |
| **HC07** | Verifier例外、Host trusted clock/DB/鍵/Revocation providerが利用不可 | **Fail Closed**。依存障害を成功にマップしない |

## 4. Atomic nonce/replay、二重課金防止（L2、将来DBが必要）

| ID | 同時/クラッシュ条件 | Host期待結果 |
| --- | --- | --- |
| **HR01** | 同じ有効なMandate/nonceを**2workerへ同時提示** | **一方だけがnonce消費＋Order Operation登録に成功**。他方は重複拒否/同一operation結果の返却。**注文実行は最大1回** |
| **HR02** | 異なるnonceだが**同一Checkout version/order**を並列提示 | 一意制約・Checkout state遷移により**独立操作の二重登録不可** |
| **HR03** | nonceが検証済みでも、CAS条件が`ISSUED`から変わる | CAS更新0件なら**STOP**。署名成功は再実行権ではない |
| **HR04** | DB commit**前**にプロセス/DB障害でrollback | nonce＋order operationは**両方未確定**。次の正当な試行も改めて全Context確認 |
| **HR05** | DB commit**後**、外部処理/receiptの前にプロセスクラッシュ | **commit済みidempotency operationを再開**し、nonceを二重消費・二重課金しない |
| **HR06** | DB timeout/commit結果が不明、deadlock/retry | **実行を新規送信しない**。DBを照会し同じoperation keyと状態を復元するまでPENDING/STOP |
| **HR07** | Fake Payment Providerがtimeout後に遅れて成功、その間同じCheckoutをretry | 同じidempotency keyの実結果を取得。**二度目のcharge/別operation IDを作成しない** |
| **HR08** | 既に消費済nonceで署名が有効な同じMandateを再送 | 一度しか許可しない。既存operationの結果を返しても**新規実行・新しいnonceは付与しない** |
| **HR09** | 非常に多数の無効Mandate提示が同じnonceへ到達 | DoSのrate limit/回数制限を検討。**無効署名を購入許可に昇格させず**、正規ユーザーのchallenge stateの破壊に注意 |
| **HR10** | Checkout取消・失効・Buyer blockがnonce検証とDB transactionの間に発生 | 状態競合で**取引拒否**。衝突時の再検証方針/トランザクション境界を固定 |

**L2合格ライン案:** 同一session/Checkoutに対する重複した`operation_id`、二つ目の成功commit、二度目の外部dispatchが**0**。**永続DBを使った試験を未実行の現段階では、Replay抑止の達成度は0/未判定であり、P1-6のN17 HOST_BOUNDARYは残る。**

## 5. Evidence/Receipt、障害時の安全結果（L1〜L3）

| ID | 入力／障害 | 期待結果 |
| --- | --- | --- |
| **HE01** | Verifierが署名/開示/Checkoutをすべて満たす | `VerifiedEvidence`に**購入許可/nonce消費/payment approvedは含まれない** |
| **HE02** | 署名失敗、未開示Constraint、未登録Issuer、Host policy不一致 | Sanitized `Rejection`＋Host execution STOP。**署名済みerror Receipt**の仕様マッピングをテスト |
| **HE03** | Nonce conflict/Checkout state不一致、Host業務拒否 | Verifierの過去成功とは無関係にHost STOP。Receiptの`result=error`、`error`を適切に生成 |
| **HE04** | Signed Mandate Receiptの`reference`を生成 | **最終SD-JWT元wire**の指定digestに一致し、RootだけをHashしない。Checkout `checkout_hash`と混同しない |
| **HE05** | Error codeと`result=success|error`、`iss`、signed JWT | 固定AP2仕様に照合し、不明な結果をsuccessとしない。Receipt発行者/登録鍵をHostが管理 |
| **HE06** | commit済operationのReceipt署名/保管/配信に失敗 | **二度目の注文実行をしない**。同一operationを使いReceipt retry/PENDINGを管理 |
| **HE07** | Provider不明状態のままReceipt要求 | **successful payment receiptを捏造しない**。Status未確定はPENDING/保留として扱い、正式プロトコルでの通知方法を後続検討 |
| **HE08** | Debug/exception logging、未知Issuer・Buyer PII・nonce/JWT | **生Token/秘密鍵/PII/nonce原文をログに出さず**、sanitized code/内部Correlation IDのみ |
| **HE09** | 一度`VerifiedEvidence`でsuccessとなった後のIssuer/Agent/Checkout失効 | 証拠は**過去時点の事実**。Host final ALLOWへ自動流用しない |
| **HE10** | Trust registryに見つからない入力、外部鍵URI/Network timeout | **Verifier/HostはFail Closed**、任意URLに自動アクセスせず本番Checkout実行を起こさない |

## 6. 設計レビュー・証拠の保存条件

| Gate | 設計または実装後に必要な証拠 | 現時点 |
| --- | --- | --- |
| **T1 Trust/Identity** | HT01〜HT07のHost入力出所、Issuer/Merchant/Agent ID↔鍵/tenant/purpose/失効の固定スキーマ、検証済みテスト | **設計のみ** |
| **T2 Context/Clock** | HC01〜HC07のchallenge/session/order version、有限TTL、注入時計、TOCTOU対策と負例 | **設計のみ** |
| **T3 Atomic Replay** | HR01〜HR10の**永続DBでのCAS/unique/race/recovery**。同一nonce二重利用・二重注文成功0 | **未実装／未試験、HOLD** |
| **T4 Evidence/Receipt** | HE01〜HE10のEvidence↔ALLOW型分離、署名Receipt reference、error/PENDING、PIIログと故障復旧 | **設計のみ** |
| **T5 Resource/Interop** | P1-4 G1〜G6、公式SDKとの固定互換・未知/深いJSON、SD-JWT disclose全体/鍵rotationsの追加確認 | **未達** |

### 今回のP1-7で「PASS」としてよい項目

**文書に必要な観点とIDが揃い、既存資料と整合していることだけ。** HT/HC/HR/HEの実行・CI/DB同時実行・本番実験は**一度も行っていない**。受入れ表の「設計のみ」は、すべて今後の負例試験が**未実施**であることを示す。

**次の1件（ユーザーが別途明示承認した場合のみ）：P1-8。** L0〜L3のうち優先する**T3/HR01〜HR08（nonce競合/クラッシュ/Idempotency）**について、**ローカル仮想DBまたは一時PostgreSQLで実際にどこまで試すか、実装範囲と採用DB/runner費用を合意するための設計判断**を先に実施。実装する場合でも**Gem/公開API/本番決済やGCP利用は別の承認**を要する。
