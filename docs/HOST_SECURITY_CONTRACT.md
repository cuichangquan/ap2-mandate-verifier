# Host Security Contract — P1-7 / Design only

**作成日:** 2026-10-11 JST  
**ステータス:** **設計案・テスト計画のみ（未実装）**。公開API/名前/DBスキーマ/数値TTLは固定しない。**汎用Gem/API実装HOLD、RubyGems公開・実決済・本番利用NO-GO**。  
**対象:** AP2 v0.2.0固定Commit `b4587ac1d055888a73b4b21750973cffba961793` の**単一Agent、Open Checkout Root → Closed Terminalの厳格2hop研究Profileのみ**。人間が直接署名するDirect経路、3hop以上、Payment Mandate、任意Issuer・非開示Layoutは受け入れ対象外。

**根拠と位置づけ:** [API_PROPOSAL](API_PROPOSAL.md)（P0-4未実装API案）、[FAIL_CLOSED_PROFILE](FAIL_CLOSED_PROFILE.md)、[SECURITY_GAP_REVIEW](SECURITY_GAP_REVIEW.md)（G1〜G6）、[SECURITY_HARDENING_RESEARCH](SECURITY_HARDENING_RESEARCH.md)（P1-6実測）を前提とする。規格上のMerchantによる検証・Receiptの義務は[AP2 specification L302–317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L302-L317)、[Agent Authorization L493–535](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L493-L535)、Checkout JWT/Hashは[Checkout Mandate L20–33](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L20-L33)。以下の**データベース状態機械、nonce atomic consume、idempotency、独自Host TTL**は、本OSSが提案する安全運用方針であり**AP2がそのDB設計を規定しているわけではない**。

## 1. 二重の判定：検証済み ≠ 購入許可

```text
外部Agent送信（すべて非信頼）：Mandate wire / disclosures / Closed
                                   |
                                   v
      Host（事前のCheckoutセッションを特定、信頼済み情報を解決）
       - tenant / Checkout / Buyer・Account / Agentの資格
       - Issuer鍵の許可範囲、Merchant署名鍵、aud/nonce、Clock、Policy
       - Hostが保持する current signed Checkout JWT原文
                                   |
                         [研究用Verifier候補]
            SD-JWT issuer/Agent/merchant signature + disclosures
            root cnf + sd_hash + aud/nonce/time + checkout_hash
            Open制約/Checkout内容 → VerifiedEvidence or Rejection
                                   |
                                   v
                VerifiedEvidence ≠ ALLOW ≠ PAYMENT SUCCEEDED
                                   |
                       [Host業務/状態トランザクション]
          Buyer/Agent権限、失効、注文正本/価格、nonce未使用
          CASでnonceとCheckout state/order operationを同時確定
                  /             |               \
               REJECT        PENDING          COMMITTED
                  |             |               |
             execution STOP  保留/再照会   一度だけ実行へ委譲
                               |              /
                  Hostが適切な署名Receiptを生成/記録/返却
                 （不明な結果を成功と表現しない）
```

**不変条件 C-01:** Verifierが返すのは検証した**事実**だけ。true/false `allow?`、`authorized: true`、`payment_approved`は返さない。Hostが決済可否の最終責任を持つ。**Verifier失敗・外部依存障害・Hostトランザクション失敗・Receipt署名失敗で自動ALLOWへ進めない。**

**不変条件 C-02:** 署名/Hash/Constraintが正しくても**未使用nonceの証明ではない**。P1-6の[N17](SECURITY_HARDENING_RESEARCH.md)は同じ有効トークンを2回検証できることを観測。原子的な一度限り消費はHost側でなければ保証できない。

## 2. Host ↔ Verifierの入力契約（API名は未確定）

| 種別 | 入力の出所／信頼境界 | 欠けたときのFail Closed |
| --- | --- | --- |
| `presentation_wire` | Agent由来、**UNTRUSTED**。元のSD-JWTとDisclosure/Closed chainの**バイト列を保持**。Issuer `iss`や`kid`は検索ヒントであり信頼根拠ではない | `malformed_presentation`/unsupported→拒否 |
| `checkout_session_ref` / `tenant_id` | **Hostが認証済みの自サービス文脈から取得**（提示Mandateの自称値ではない） | 曖昧・cross-tenant・未登録→Host STOP |
| `issuer_trust_policy` | Host管理の**承認済みIssuer identity→鍵集合/使用用途/署名alg/issuer profile/version/失効状況**。鍵ローテーションの有効期間を含む。`kid`/`x5c`/`jku`を無検証でtrust anchorにしない | 鍵・issuerの不一致/失効/解決失敗→`untrusted_issuer` |
| `merchant_trust_policy` | Hostに登録した**Merchant ID↔Checkout署名鍵**（用途、tenant、`kid`、alg、rotation、失効の制御を含む）。Issuer鍵とは独立 | Merchantが異なる、key用途外、登録なし→拒否 |
| `expected_agent_key` / `expected_agent_id` | Hostが当該Buyer/Checkoutで受け入れる**Agent IDと事前登録公開鍵**。Rootの署名済`cnf.jwk`と一致確認し、Agent名の文字列だけで信用しない | 対象外・不一致・認証関係不明→拒否。初期Profileでは必須 |
| `buyer/account_binding` | Hostが既存セッション/信頼済Issuerポリシーから確立したBuyerの同意・使用資格・アカウント関連。**単なるJWT署名成功でBuyer本人を確定しない** | 未解決・停止・代理資格失効→Host STOP |
| `signed_checkout_jwt` / `checkout_id` / `checkout_version` | Hostが保持する**現在のMerchant署名済JWT原文**とCheckout正本・版。Agentに提示させたJWTを正本扱いにしない | 原文、署名、hash、ID、状態/版不一致→拒否またはHost STOP |
| `expected_audience` / `expected_nonce` | **Hostが対象checkout/session用に発行し、永続stateを持つchallenge**。Root→Terminalに署名済みの値との比較のみVerifier担当 | 未発行/null/期限切れ/異なるtenant・checkout→拒否 |
| `now` / `ttl_policy` / `resource_limits` | Hostの信頼できる時計、上限付きskew/TTL・alg/サイズ/ネスト/claim/Disclosure上限。テストでは時計注入を予定 | 時計/ポリシーなし、期限外/未知format→拒否 |
| `required_disclosure_profile` | HostがIssuer profileに結び付けた権限制約の完全性要件。**開示された範囲だけで権限が足りると推論しない** | 未開示・未知制約、証明不能なIssuer layout→拒否 |

**ホスト入力が本当に信頼できることの実装は未検証。** `issuer_trust_policy`や`merchant_trust_policy`にHashを渡せば自動的に安全になるわけではない。受信トークンが提示するJWK/鍵URLをそのHashへ無条件に移す実装は禁止する。

## 3. 返す事実／返さない許可

未実装の提案でありクラス名は仮称。既存[API_PROPOSAL](API_PROPOSAL.md)に整合。

| 仮の結果 | 記録してよい検証済み事項 | **含めない事項** |
| --- | --- | --- |
| `VerifiedEvidence` | 固定仕様/Issuer profileのID、Host trust policy参照/版、検証済Issuerの鍵thumbprint、`flow=autonomous`、Verified Agent鍵thumbprint、Checkout ID/version/原文SHA-256、`sd_hash`、結果を縛る`aud`/challenge reference、検証済constraintタイプと限定profile、`verified_at`、無害なevidence reference | `allow`/`payment_approved`/`buyer_authenticated`/`nonce_consumed`/`not_revoked_forever`/`receipt_signed`。**口座・同意を暗号署名だけで証明したかのようにしない** |
| `Rejection` | サニタイズ済`code`/`stage`、tracingの内部correlation reference、判定不能/未対応/不一致の分類 | 生JWT、disclosure、署名、秘密鍵、Buyer PII、stacktrace |
| Host独自`ExecutionDecision`（Verifier出力外） | 購入実行の業務判定と失敗時STOP、**競合排除/nonce使用済み確認済み状態**、order operation/idempotency key | これを`VerifiedEvidence`と同じRuby型にしない |

**証拠の時点性:** `VerifiedEvidence`は`verified_at`のチェック結果であり、鍵失効・Checkout取消・価格変更・Buyer利用停止など**その後のHost状態を保証しない**。Execution前にHostが正本と権限を同一の整合性境界で再照合する。検証済み証拠を任意の別Checkout/別nonceに転用しない。

## 4. 状態を持つHostの安全契約（実装なし）

初期Host設計案：**Nonceはcheckout session、tenant、buyer/agent、audience、Checkout ID/version、期限に結び付けて発行**。十分なエントロピーのnonceを生成する（長さ/TTLは将来プロファイルで決める）。`nonce_hash`等のログ/保存形式はPrivacy policyで別決定し、取り違えを避ける。キー・challengeはtrusted Host DBから取得。**一度発行したnonceを別tenantや別Checkoutに付け替えない**。

| Host状態（設計案） | 遷移とトリガー | 実行ルール |
| --- | --- | --- |
| `ISSUED` | nonceをHostが作り、Checkout sessionと有効期限・期待contextを永続保存 | 未検証。Agentの署名が有効でもCheckout実行不可 |
| `VALIDATED`（概念上。永続化不要） | Verifierが`VerifiedEvidence`を返す | **まだ実行不可**。Hostトランザクション内で再検査 |
| `CONSUMED_AND_COMMITTED` | Host DBの**単一原子的トランザクション**で、nonce未使用/期限/tenant/checkout version/Agent・Buyer権限/失効等を再検証し、**CASでnonceの使用とCheckout/order-operationの一度限り確定を同時にcommit** | 成功した**一つの操作だけ**が実行候補。二つの同時提示では最大一つだけが勝つ |
| `EXECUTION_PENDING` / `FINALIZED` | commit済operationを**同じidempotency key**で安全な決済/注文担当へ委譲。実結果をHostが確定 | Timeout/結果不明時**再操作しない**。照会/同一キーretryで重複課金を防止 |
| `EXPIRED` / `REVOKED` / `REJECTED` | 期限切れ、失効、Host拒否、検証失敗 | **注文実行禁止**。署名Receipt要件は後述。拒否時に未使用nonceを単純に消費するかはDoS/濫用との調整を要するため未決 |

**原子性・障害時STOP（Host実装の将来受入れ条件）:**

1. HostはVerifierを呼ぶ前に**既存のCheckout sessionと事前発行challenge**をHost側の認証済み文脈で解決。署名検証失敗/未対応なら操作を始めない。
2. `VerifiedEvidence`後も、DB側で**nonce=ISSUED、期限内、同じtenant/Checkout ID/version、Buyer/Agent有効、Merchant/Issuer信頼・失効が現在も有効、Checkout status/商品/総額が正本と一致**を再検証する。検証時刻と実行時刻のTOCTOUを許可に丸めない。
3. そのチェックと**nonce状態更新＋一意なCheckout operation記録／注文状態遷移**を**単一DB transaction/CAS**で処理。失敗・0 rows updated・unique conflict・deadlock・DB timeout・不明なcommit結果では**新しい実行を発行しない**。DB固有の分離レベル/lock設計は未選定。
4. DB commit後の外部決済は別の**durable operation/outbox + idempotency key**を通す提案。障害復旧でoperationの実結果を先に照会し、不明な場合は`PENDING`で人・システムの解決を待つ（`ALLOW`や再課金にフォールバックしない）。
5. 同じpresentationの再送は新しい取引・新しいnonce使用権を与えない。Hostが保持した**同じ操作の結果**を、権限とreceipt状態を確認した後に再提示することはできる（新規実行ではない）。
6. **Receipt署名/保存に失敗**してもトランザクションを無条件に再実行しない。操作結果が不明なら成功Receiptを生成しない。外部に返すHTTPエラー、再送可能性、Receipt保留中の状態は別のHost契約で決定する。

これは**一般のAP2規格がこの状態機械やPayment OutboxをMUSTとしている、という主張ではない**。実決済統合・Payment Mandate自体は本OSSの担当外。

## 5. Clock・Trust Rotation・失効

**時間:** HostがUTCの`now`、許容skew、Root/Terminal/Closed別の`iat`/`exp`とmaxTTLを規定。期限切れClosed・future`iat`は[P1-6](SECURITY_HARDENING_RESEARCH.md)の負例で研究用拒否を実測済みだが、**注入時計・失効タイミング・上限境界は未テスト**。固定300秒/7200秒は以前のPoC値であり公式AP2共通値ではない。Host challenge期限の前後に生じる状態変化を再評価する。

**Issuer・Merchant鍵Rotation:** Host登録済のissuer/merchant IDとkeyID・thumbprint・発行用途・allow algorithms・有効開始/失効/最終許容時刻を管理する。意図せぬ`kid`衝突、署名者が別tenant・別用途の鍵へcross-bindするケースは拒否。**鍵が署名を検証できても現在の利用資格が失効ならHost STOP**。古い署名と撤回済keyの扱いはHostの明示policyと法務/商取引要件で決定。

**失効・正本:** Issuerの資格、Buyerの同意/代理権、Agentの使用許可、Merchant key、Checkout state/version、金額/在庫/残予算、注文の重複をHost（または適切な専門システム）が現在時点で評価する。外部status問い合わせに失敗した場合は`unknown`として停止。**Verifierはライブ失効の完全性を保証しない。**

## 6. Receiptと障害対応（AP2規格義務とHost設計を分離）

AP2 v0.2の[Merchant rules](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L302-L317)はCheckout Mandateの検証および検証失敗時のCheckout Receipt JWTを要求。[Mandate Receipt](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L493-L535)は、Verifierが署名して返し、`iss`、`result=success|error`、`reference`（最終SD-JWTのHash）と、error時の`error`等を規定する。

| 事象 | Host側の処理案 | 外部へ知らせる結果 |
| --- | --- | --- |
| 署名・開示・制約・Checkout hash不正 | **実行STOP**、安全な`invalid_credential`/`invalid_mandate`/`unresolved_constraint`等へ適切にマップ | Host/Verifier責務として**署名済みerror Receipt**を適切なプロトコルで返す計画。未署名成功結果禁止 |
| Nonce期限切れ/再利用、Issuer・Buyer失効、注文正本不一致 | Hostトランザクションで拒否。別のnonceへ自動振替しない | **実行せず、署名済みの失敗結果**を返す設計候補。AP2 error/schemaへの正確なマッピングは後続で検証 |
| 正常な認可だが外部注文/決済が`PENDING` / timeout | 同じidempotent operationを追跡。**結果不明をsuccessと見なさず、二重送信しない** | 解決まで成功Receiptを捏造しない。保留/再送表現は後続でAP2 Schemaと照合 |
| DB commit済、Receipt署名に失敗 | **もう一度購入を実行しない**。Receipt再生成/配信を既存operationに結び付ける | Receiptの状態を記録し、再照会/再配信に対応（方式未決） |
| 確定済みの同一operationを再送 | 未使用nonceとして二度扱わず、正当な同一Clientに既存結果を返す方針を検討 | 新たな`result=success`を独立で発行しない。Receipt `reference`とexecutionの関連を保全 |

**実装前の確認事項:** AP2 `Checkout Receipt JWT`と共通`Mandate Receipt`のマッピング、Hostの署名者と公開鍵、失敗コード、Checkout Receiptの`reference`計算（最終SD-JWTの元wire Hashと`_sd_alg`）、Receipt生成不可時のプロトコル動作、再送/再実行との差。今回**署名Receiptは発行していない**。

## 7. エラー、Privacy、障害時の基本契約

- **安全停止:** Trust解決不能、部分開示/unknown constraint、署名検証・hash失敗、非対応Profile、Clock・Host DB・Issuer revocation service故障、nonce競合、決済状態不明、Receipt署名不能で**成功応答を返さない**。例外・未知を正常に丸めず、HostのexecutionはSTOP/PENDING。
- **最小ログ:** Transactionのランダムcorrelation ID、検証stage、sanitized rejection code、採用profile/version、idempotency operation reference、時刻・障害種別。**生Mandate/Checkout JWT、Disclosure、署名、Buyer属性、秘密鍵、nonce原文**をログへ出さない。匿名化/Retention方針は未決。
- **通信境界:** Hostがtrusted keyを解決する手段は将来別設計。受信Tokenに書かれた`jku`/外部URLへそのまま通信しない（SSRF/任意鍵受理を避ける）。信頼鍵を自動import・許可しない。
- **コンカレンシー:** 2worker/2リクエスト/DB deadlock/タイムアウト時の**最大1つの権限消費と注文実行**をテスト可能な契約として明記。永続DBなしではこの性質を実証できない。
- **事実と期待:** ここまで全て**提案・要求するHost契約**。P1-6の18件と43回帰は暗号/strict-profileに関する過去のオフライン実測のみで、Host業務トランザクションの合格結果ではない。

## 8. 受入れテスト計画と実装前ゲート

新規テストは**未実装・未実行**。設計したケース、障害注入箇所、合格条件と責務は[HOST_SECURITY_TEST_PLAN](HOST_SECURITY_TEST_PLAN.md)に分離。そちらを唯一のテストID正本とし、ここに合格件数を重複記載しない。

**P1-7の完了条件（設計資料のみ）:** Host入力の信頼根拠と出所、Verifierの証拠とHostのALLOWの区別、Host nonce state/atomicity、crash/retry/idempotency、期限・失効/Checkout原文、Receipt署名/失敗、ログ最小化、**未来の負例ID/期待結果・GO/HOLD**が資料で追跡可能になること。**本設計に合格した＝テスト・本番が安全という意味ではない。**

## 9. 最新のGO/HOLDと次の一件

| 範囲 | P1-7判断 |
| --- | --- |
| Host信頼境界の文書設計・テスト計画 | **このStepで完了（レビュー後）** |
| 限定研究PoCの継続 | **CONDITIONAL GO（実決済なし）** |
| Host state・nonce永続化・Receiptの実装 | **未承認／未実装** |
| 汎用Ruby Gem/API実装 | **HOLD継続**（Host contractのテスト・Interopを未実証） |
| RubyGems公開・Production/実決済 | **NO-GO継続** |

**次の1件（別の明示承認後のみ）：P1-8 — 本設計のHost側Fail Closed/Atomic Replayを実証するための最小テスト環境・試験実施判断（まず設計/採用DBの選定と実装範囲の承認を得る）。** 自動的にHost DB、Gem公開API、本番コード、クラウド環境を作成しない。
