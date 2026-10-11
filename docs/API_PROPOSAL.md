# API Proposal — Minimal Checkout Mandate Verifier (Phase 0 / P0-4)

**作成日:** 2026-10-11 (JST)  
**状態:** **設計案 / PROPOSED / NOT IMPLEMENTED / NOT A STABLE PUBLIC API**。名前、引数、返却型、Gem/namespace/依存Gem/Ruby matrixを**確定しない**。ここに掲載したRubyは契約の例示で、動作・テスト済みのコードではない。  
**対象:** Rubyに依存するHostアプリが外部Shopping Agentから受信した **AP2 v0.2 Checkout Mandate** を検証するだけの小さなRubyライブラリ候補。Rails不要。Payment Mandate、決済実行、Trust Surface、Wallet、A2A/MCP、Receipt送信などは作らない。  
**仕様基準:** AP2 release `v0.2.0` / Git Commit `b4587ac1d055888a73b4b21750973cffba961793`（[SPEC_BASELINE](SPEC_BASELINE.md)、[VERIFIER_REQUIREMENTS](VERIFIER_REQUIREMENTS.md)、[ECOSYSTEM_RESEARCH](ECOSYSTEM_RESEARCH.md)）。

## 1. 判断の中心

**このVerifierの戻り値は「Verified Evidence」または「Rejection」であり、`ALLOW`ではない。** AP2 Merchantの検証義務は規定されているが、技術検証の委託先がMerchantの支払・注文判断を自動許可するわけではない。[specification:292-317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L292-L317) / [implementation_considerations:8-32](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/implementation_considerations.md#L8-L32)。

```text
[untrusted] Shopping Agent / presented Mandate + disclosures
                              |
                              v
[trusted] Host loads exact, current, merchant-signed Checkout JWT
          Host specifies issuer/merchant keys, expected audience & nonce
          Host specifies merchant and (where known) expected agent context
                              |
                              v
     CheckoutVerifier#verify   [pure analysis, NO purchase]
       1. format/version/schema/resource limits
       2. issuer trust + cryptographic SD-JWT chain/disclosures
       3. holder key binding + expected aud/nonce/time
       4. Open vs Closed claims/constraints (fail unknown/incomplete)
       5. EXACT checkout JWT + signed authenticity + checkout_hash
                              |
                +-------------+-------------+
                |                           |
                v                           v
       VerifiedEvidence                 Rejection
       (not authorization)              (never evidence)
                |                           |
                v                           v
[Host] identity / risk / replay /     STOP purchase
       revocation / business rule      issue error receipt
       atomic execute or STOP
       issue signed Checkout Receipt
```

区別すべき三段階：

- **Cryptographically valid:** 署名、chain/disclosure、公開鍵によるPoPが成り立つ。
- **Verified evidence for this checkout:** 上記に加え、Hostのissuer信頼・Merchant/Agent文脈・Open制約・特定Checkout JWTの署名/hashとの結び付きが評価済み。
- **Host ALLOW:** HostがUser/Account対応、注文対象、価格、在庫、支払い・リスク、replay/失効を評価した**別の最終判断**。このAPIからは返さない。

信頼境界の根拠: [agent_authorization:34-79](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L34-L79) / [agent_authorization:386-465](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L386-L465) / [checkout_mandate:20-33](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L20-L33)。

## 2. 小さなPublic API案（説明用Ruby、**未実装**）

最初に公開する入口は **1つだけ** を候補とする。値オブジェクトやコールバック名も仮称。

```ruby
# Proposal ONLY: これらのクラス/メソッドはまだ存在しない
verifier = ProposedAP2::CheckoutVerifier.new(
  issuer_trust: host_issuer_trust,         # Host owns trust anchors / resolver
  merchant_jwt_keys: host_merchant_keys,  # Host owns allowed merchant signing keys
  constraint_policy: host_constraints,    # Required disclosure / extension policy
  resource_limits: host_limits           # Reject oversized / unsupported input
)

result = verifier.verify(
  presentation: incoming_mandate_wire,   # UNTRUSTED exact compact token/chain
  checkout_jwt: checkout_record.signed_jwt, # TRUSTED current exact JWT from Host
  context: {
    merchant_id: current_merchant.id,     # Host-authoritative identity
    expected_audience: challenge.audience, # required for autonomous flow
    expected_nonce: challenge.nonce,       # required for autonomous flow
    expected_agent: host_expected_agent,   # optional ONLY if no specific agent required
    allowed_flows: [:direct, :autonomous],
    now: Time.now.utc                      # trusted clock; tests inject fixed time
  }
)

case result
when ProposedAP2::VerifiedEvidence
  # NOT a permission grant. Host MUST decide independently.
  # Host checks account binding, business rules, revocation and atomic replay guard.
  # Host then executes or stops, and signs/returns its Checkout Receipt.
when ProposedAP2::Rejection
  # No verified evidence. Never execute; Host generates signed error receipt.
end
```

**API最小原則:** 一度の呼び出しは**1件のCheckout評価**。Verifierはネットワーク通信・DB書込み・nonce消費・注文作成・署名Receipt発行をしない。Hostが事前にresolveしたキー・取引文脈を使う。これは**P0-4の設計方針**であり、AP2が上記Rubyクラス名やコンストラクタを要求しているわけではない。

**安全側の限界:** `constraint_policy` だけで『未開示Constraintは存在しない』とは証明できない。信頼できる発行側の完全性根拠や必須開示条件を確立できない場合、この設計は結果を成功にせず **Rejection/HOLD** とする。Ruby側での実現方法は未決定である。

### 入力の境界

| 入力（仮称） | 信頼レベル・必要度 | 契約・Fail Closed |
| --- | --- | --- |
| `presentation` | **UNTRUSTED / 必須** | 受信した**元のcompact SD-JWT / disclosures / delegate-chainバイト列**。Base64再エンコードやJSON再直列化をして署名・digestの基準を変えない。欠落・破損・未サポートtoken/hopは拒否。 |
| `checkout_jwt` | **Host authoritative / 必須** | **このCheckout処理の現在の、merchant-signed compact JWT原文**。提出Agentが提示した値をそのままHost正本扱いにしない。ホストの鍵で署名検証して、提示closed内の `checkout_jwt` と等価性・hashの一致を確認。参照するHashはMandate内の `_sd_alg`（既定sha-256）に従う。[checkout_mandate:20-33](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L20-L33) / [specification:302-317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L302-L317)。 |
| `issuer_trust` | **Host policy / 必須** | Trusted User Credential issuer またはTrusted Agent ProviderをHostが登録。root issuer ID・`kid`・`x5c`だけで自己信頼しない。鍵、許可用途、alg、証明書trust anchor/validity、rotation・失効方針をHostが決定。未登録や解決不能は拒否。[agent_authorization:34-79](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L34-L79) / [agent_authorization:289-312](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L289-L312)。 |
| `merchant_jwt_keys` | **Host policy / 必須** | Merchant自身が信頼するCheckout JWT署名鍵（鍵ID/alg許可を含む）。`checkout_jwt`のpayloadをdecodeするだけでは**署名確認にならない**。Host DBのcheckout ID/状態の整合も後段で別検証。 |
| `context.merchant_id` | **Host authoritative / 必須** | 受け付ける実Merchant識別子。Open `checkout.allowed_merchants`と適切なmerchant identityを比較。取引先はAgent自己申告から選ばない。[checkout_mandate:35-58](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L35-L58)。 |
| `context.expected_audience`, `expected_nonce` | **Host-issued challenge / 自律Open→Closed経路は必須（本OSS案）** | nonceは**この取引文脈用にHostが生成**。terminal PoPが受信先audience/nonceと一致することを確認。欠落・null・不一致を自律フローで拒否。Directのuser-approved Closedでは同一義務を無条件に拡大しない。**AP2全フローに同じMUSTがあるとの主張ではない**。[specification:221-235](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L221-L235) / [sdk/sdjwt/kb_sd_jwt.py:94-140](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/kb_sd_jwt.py#L94-L140)。 |
| `context.expected_agent` | **Host policy / 条件付き** | Hostが特定Agentを期待するときは、その**事前に信頼して特定した**鍵thumbprint/ID等と、検証済み `cnf`→鍵bindingを照合する。任意Agentを受ける取引ではnullを許せても、**Agent同一性の保証は結果に含めない**。 |
| `context.allowed_flows` | **Host policy / 必須** | 許可経路（`:direct` /`:autonomous`）をHostが指定。ただし受信データのmode分類はVerifierが**検証後**の構造から行い、Host指定のmodeでセキュリティ条件を迂回させない。 |
| `constraint_policy` | **Host policy / 必須** | 標準タイプの意味づけ、必要開示情報、未知/非開示拡張の拒否方針。**presentされた可視constraintが0だからALLOW**にしない。Schemaが要求する内容がない場合は不確定とし拒否。[agent_authorization:433-465](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L433-L465) / [open_checkout_mandate.json](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json)。 |
| `resource_limits`、`context.now` | **Host-configured / 必須** | JWTサイズ、チェーン長、disclosure数、JSONネスト、CPU上限、alg許容、時計ずれ等の**安全側の有限値**を要求。具体値はまだ未決・プロファイル化前。処理失敗は拒否し、秘密情報をログに出さない。 |

**補足:** `expected_audience` と `expected_nonce` の**有効性・事前発行・一度限りの消費**はHost管理。Verifierが値の文字列一致を確認しても、nonce replay防止済みとは言えない。

## 3. 受理する最小フロー（2経路・自動判定）

| 経路 | 受け入れ条件案 | 禁止 / 保留 |
| --- | --- | --- |
| **Direct / Human Present** | 信頼済みの発行モデルで**特定Checkoutを人が承認したClosed Mandate**の署名・schema・`vct=mandate.checkout.1`を検証。署名主体・発行者信頼、Checkout JWTの一致/hashを必須。[specification:192-219](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L192-L219)。 | DirectにOpenの `cnf`必須を機械的に追加しない。ただしHosted checkout、署名者の信頼とconsent保証の仕組みが不明なら**拒否**。 |
| **Autonomous / Human Not Present** | Trusted Surface承認済みOpen + Agentが鍵で結び付けたClosed。Openには `vct=mandate.checkout.open.1`、`cnf`、関連制約が必要。全hopの署名・前段key binding・disclosureとclaim保存・constraints・終端aud/nonce・Checkout hashを確認。[specification:221-244](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L221-L244) / [agent_authorization:386-465](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L386-L465)。 | **Open単独をCheckout承認として受理しない**。Agentが自己申告した `cnf` だけで許可しない。署名済みのOpenでも不必要な開示欠落・取引不一致はreject。 |
| **非スコープ** | なし | Payment Mandate、追加の任意Agent転委任、任意の`vct`、未知のVDC形式・未定義Extensionは**初期版で受理しない**。AP2 v0.2のAgent-to-Agent Mandate delegationは本文でスコープ外。[specification:256-260](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L256-L260)。 |

**vctの正確な値:** `mandate.checkout.1` と `mandate.checkout.open.1`。数値suffix込み完全一致がAP2 MUST。[specification:136-143](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L136-L143) / [checkout_mandate:12-18](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L12-L18)。仕様リリース`v0.2.0`とMandate schema suffix `.1`を混同しない。

### 検証順序（提案）

1. 非信頼入力に制限を掛け、破損・unknown algorithm/`vct`/形式・過大入力を拒否。**未署名payloadからのtrust確定は禁止**。
2. Hostにより許可されたIssuer/key/algorithmのみを使ってRoot署名を検証し、各hopのDisclosure digest、`sd_hash` または規定の `issuer_jwt_hash`、前hop `cnf` と署名鍵を検証。[agent_authorization:455-465](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L455-L465)。
3. Direct/Autonomousを**検証した構造で**分類。自律OpenではAgent/Holder PoP、terminal `aud`/`nonce`とHost expectation、各段の時刻を照合（期限未指定と上限はHost policyに従う）。
4. OpenからClosedへの固定claim保持と、**すべての開示され検証すべきConstraint**を評価。非開示で必要な意味情報が欠ける、未知type、`checkout.allowed_merchants`不一致、`checkout.line_items`不一致は拒否。[checkout_mandate:35-110](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L35-L110)。
5. **Host正本JWT**をHostのMerchant keyで署名検証し、Closedの`checkout_jwt`と同一性、Closed `checkout_hash`との**独立digest比較**を行う。正本のJWTがない、署名が偽、値違い、hash違いは拒否。これは公式Python SDKのoptional expected hashに**依存しない**。[specification:302-317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L302-L317) / [sdk/checkout_mandate_chain.py:44-110](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/checkout_mandate_chain.py#L44-L110)。
6. すべて揃った場合のみVerifiedEvidenceを作成。1項目でも不明・失敗ならRejection。Hostはreplay/失効/注文/実行を別途判断し、署名Receiptを返す。

**設計上の停止条件:** 「未開示のConstraintがそもそも存在するのか」「Direct署名主体をどこまで認定できるか」等、**十分な証拠が揃わない**場合は実装判断前にHOLDにするか当該presentationを拒否する。形式だけでsuccessを返さない。上流 [#339](https://github.com/google-agentic-commerce/AP2/issues/339) を参考に、事実確認と将来の負例試験が必要。

## 4. 出力の契約（提案、固定ではない）

**Tagged resultを必ず区別**。例：`VerifiedEvidence` と `Rejection` を異なる型にする。単純 `true/false` や `authorized?`, `allow?`, `approved?` と命名しない。

| 返却データ（仮） | 意味・境界 |
| --- | --- |
| `VerifiedEvidence.specification` | `"AP2 v0.2.0"` と固定Commitを識別し再現性を保持。 |
| `VerifiedEvidence.flow` | 検証済み構造から判明した `direct` / `autonomous`。 |
| `VerifiedEvidence.issuer_ref` | **Host側trusted policyに解決された**Issuer参照。自称`iss`の追認ではない。 |
| `VerifiedEvidence.agent_key_thumbprint` | **自律フローでPoP検証済みの鍵識別子**。User/Agentアカウント同定や同意の証明ではない。Directで根拠がなければnull/未保証と明示。 |
| `VerifiedEvidence.checkout_hash` | Host正本・提示Closedの一致を確認したdigest。alg/取引の同定に使えるが、**anti-replay記録ではない**。 |
| `VerifiedEvidence.checked_constraints` | 評価できたタイプとその結果（安全な要約のみ）。**不可視情報について推定した成功を載せない**。 |
| `VerifiedEvidence.evidence_reference` | 検証された最終presentationの識別子（将来のreceipt reference候補）。**AP2のReceipt `reference`計算仕様と一致することを後続で確認**し、今はAPI確定しない。 |
| `Rejection.code` | **サニタイズ済み**理由コード。原文、signature、鍵、機微disclosure、秘密情報は含めない。 |
| `Rejection.stage` | フォーマット/crypto/trust/claims/constraints/checkout等の分類。内部例外・stacktraceは外へ出さない。 |

**不変条件:** `VerifiedEvidence`は、1回の検証で正しく評価された**事実の記録**に限る。nonceを消費せず、Mandateが未使用・未失効である保証も付けず、`authorized: true`や`payment_approved`を決して含めない。Hostが状況を再評価できる設計が必要。

### 拒否理由コードの草案（名前は未確定）

| Group | 提案するコードと扱い |
| --- | --- |
| Format | `malformed_presentation`, `unsupported_format`, `unsupported_vct`, `resource_limit_exceeded` → fail closed |
| Trust / crypto | `untrusted_issuer`, `invalid_signature`, `invalid_disclosure`, `invalid_chain_binding`, `invalid_holder_proof` → fail closed |
| Context | `invalid_audience`, `invalid_nonce`, `invalid_time`, `expected_agent_mismatch`, `incomplete_context` → fail closed |
| Constraints | `unknown_constraint`, `incomplete_disclosure`, `constraint_violation` → fail closed |
| Checkout | `invalid_checkout_signature`, `checkout_jwt_mismatch`, `checkout_hash_mismatch` → fail closed |
| Execution | `verification_unavailable` → fail closed。内部例外や依存障害で自動成功しない。 |

**Receiptとは別の契約:** ここで挙げたエラーコードは**内部検証結果案**。外部AP2 Checkout Receiptのerror/statusへはHostが公式Schemaと汎用Mandate Receiptの表現差を確認してマッピングし、Host鍵で署名して返す。[specification:117-131](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L117-L131) / [specification:302-317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L302-L317) / [agent_authorization:493-535](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L493-L535) / [checkout_receipt.json](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/checkout_receipt.json)。

## 5. VerifierとHostの責務を取り違えない

| 処理 | Verifier候補 | Host / 他の役割 |
| --- | --- | --- |
| SD-JWT/Delegation cryptographic verification | **担当候補**：固定仕様に従うchain/disclosure/hash/PoP | Hostは信用できるIssuer/鍵、認めるアルゴリズム、必要な明示的policyを提供 |
| Source authentication / issuer admission | 提供された信頼設定で署名を検証し、失敗を返す | **Hostが誰を信用するかを決める**。外部`x5c`やURLの自動trustは禁止 |
| Closed JWT / Checkout hash | 提示JWTとHost正本JWTの署名・原文・digest一致を確認する設計候補 | **Hostが正規Checkout/JWT/鍵を管理**。価格、在庫、税、金額・通貨など商取引の正しさを保証 |
| Open Constraint / disclosure | 正規の制約評価・既知type、必要情報の欠落を判別・拒否 | Hostが必要な開示範囲/独自extensionおよび業務の追加ルールを決定 |
| Agent・User・account mapping | 検証された鍵/Issuer情報を証拠として返す | **Host**がUser/Agent IDと利用資格を解決。同意と信頼はTrusted Surface / Issuer trustに依存 |
| Nonce / audience / expiry | Host期待値・時刻の整合を**検証するのみ** | Hostはnonce発行/一度限りの原子的消費、期待宛先、時計/期限ポリシー、replay対策を管理 |
| Revocation / stateful budgets / duplicate charge | **しない**。不十分な証拠は拒否 | **Host/決済側**で永続的・原子的にチェック、支払い重複実行を防ぐ |
| Final ALLOW / execution / Checkout Receipt | **しない**。成功しても証拠のみ返す | **Host**が業務許可・実行・Checkout Receipt署名/返却。支払いは別コンポーネント |

根拠: [specification:30-57](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L30-L57) / [specification:302-341](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L302-L341) / [security_and_privacy_considerations:100-114](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/security_and_privacy_considerations.md#L100-L114) / [implementation_considerations:8-32](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/implementation_considerations.md#L8-L32)。

## 6. Fail Closedの受入条件（将来のテスト項目、未実行）

| Test ID | 条件 | 期待結果 |
| --- | --- | --- |
| A01 | 署名改ざん/未信頼Issuer/任意`x5c`/不明`kid` | `Rejection`。不明なrootを自動信頼しない |
| A02 | 未知`vct`、suffixなし、Open単独、未対応転委任 | `Rejection` |
| A03 | `cnf`不一致・chain hop変更・`sd_hash`/`issuer_jwt_hash`不一致 | `Rejection` |
| A04 | 自律フローでaudienceまたはnonceが未発行/null/不一致 | `Rejection`。Directでは仕様とHost policyに従い区別 |
| A05 | 期限切れ/future `iat`、未対応claim、Host期限要件不足 | `Rejection` |
| A06 | 未知Constraint、制約の必要情報が未開示、Open schemaの必要制約がない | `Rejection` または規格未解決につき実装GOをHOLD |
| A07 | 商品/数量/merchantの**標準Checkout制約**不一致・Agent鍵ポリシー不一致 | `Rejection`。価格・金額・通貨など標準制約にない業務確認はHostが実施 |
| A08 | 関係ない/偽署名のCheckout JWT、最新Host正本と別JWT | `Rejection` |
| A09 | `checkout_hash`の誤り、Host JWTと違う、期待hash省略を試みる | `Rejection`。hash照合をoptionalにしない |
| A10 | 大きすぎるJWT、深いchain、不正JSON、未知alg、例外/タイムアウト | `Rejection`。失敗時にraw tokenをログへ出さない |
| A11 | 全暗号検証に合格した証拠を、失効済み/既使用MandateとしてHostが検出 | VerifierだけではReplayを**保証しない**。Hostが**実行拒否** |
| A12 | Merchantは受理/拒否したがReceiptを返していない | **Host側未完了**。検証ライブラリがReceiptを生成済みとは言わない |

対応要件と負例は [VERIFIER_REQUIREMENTS](VERIFIER_REQUIREMENTS.md) のR01〜R14/N01〜N14と対応する。これらは**テスト計画**で、まだ実装・実行していない。

## 7. 残る論点と P0-5 Gate

1. **未開示Constraint/必須制約:** 選択的開示されたOpenのschema検証時点と必須開示条件が未確定。公式PythonモデルにはJSON Schema `contains`相当が明示されていない。[ECOSYSTEM_RESEARCH](ECOSYSTEM_RESEARCH.md) / [上流#339](https://github.com/google-agentic-commerce/AP2/issues/339)。
2. **終端`aud`/`nonce`：** 公式Pythonは生成時必須でも検証のexpected省略を許す経路がある。**自律フローのHost必須期待値は本OSSのFail Closed方針案**で、全フローAP2 MUSTと断定しない。[上流#319](https://github.com/google-agentic-commerce/AP2/issues/319)。
3. **Checkout hashとJWT trust:** 正本Checkout JWTのバイト列・署名・hash照合をmandatoryとする（Merchant MUST）。Ruby依存Gemが署名/alg/JWKを十分安全に扱うか、実行で確かめていない。[上流#358](https://github.com/google-agentic-commerce/AP2/issues/358)。
4. **Direct Closedのissuer consentモデル:** User Credential vs Trusted Agent ProviderでHostがどこまで発行者の正当性・ユーザー同意を信じるか追加定義が必要。実装時は不明なモデルを許さない。[agent_authorization:34-79](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L34-L79)。
5. **Crypto/SDK互換:** Delegate SD-JWTはAP2が参照する個人draft依存。tag固定・test vector・key binding・alg制限とRuby SDK依存候補の実験は未実施。[agent_authorization:539-544](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L539-L544)。
6. **状態/receipt:** nonce再使用・Checkoutの更新競合・同一Mandateの二重決済・revocation情報の責務とReceipt `status` vs汎用`result`の差は、Host側契約として追加設計が必要。[VERIFIER_REQUIREMENTS](VERIFIER_REQUIREMENTS.md)。
7. **APIの最終形:** `ProposedAP2::*`、`Context`、`TrustPolicy`や失敗コードは**すべて仮称**。Gem名/Namespace、デフォルト値、Ruby matrix、Gem依存・バージョンとエラーマッピングは決定していない。

**P0-4の完了判断:** 本文が入力/出力と信頼・実行の境界、Direct/Autonomous、Fail Closed、未保証項目を具体的に説明できれば**設計タスクとして完了**。**実装可能性・AP2準拠・本番安全性を実証した意味ではない**。

**次に進める重要事項（1つだけ）:** **P0-5 — `docs/RESEARCH_DECISION.md`で実装GO / HOLD / NO-GOを判断**。仕様不明点、Ruby依存・SDK正負例の未検証、技術需要/保守コスト、狭いPoCの価値を踏まえ、**承認が得られるまで実装を開始しない**。
