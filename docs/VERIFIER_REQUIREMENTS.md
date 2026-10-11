# Checkout Mandate Verifier Requirements — Phase 0 / P0-2

**確認日:** 2026-10-11 (JST)  
**状態:** **設計調査完了（実装・試験は未実施）**。ここにある「拒否」は実装済みではない。  
**固定正本:** AP2 v0.2.0 = `b4587ac1d055888a73b4b21750973cffba961793`（[SPEC_BASELINE](SPEC_BASELINE.md)）。SDKの挙動をMUSTの根拠にしない。  
**対象:** Merchant側の **Checkout Mandate** を受信し、証拠を検証する最小のRubyライブラリ（構想）。Payment Mandate / 決済処理 / A2A transport / 一般化したAgent-to-Agent delegationは今回対象外。

## 1. 結論：何を保証するか

```text
UNTRUSTED: Shopping Agent / presented SD-JWT + disclosures / Checkout input
         |
         v
HOST: authoritative Checkout JWT + own merchant keys + trusted issuer policy
         |
         v
VERIFIER (candidate):
  decode+schema+vct -> crypto chain+PoP -> open claims+constraints
  -> checkout_hash vs authenticated exact Checkout JWT -> evidence or failure
         |
         v
HOST: identity/account mapping, risk/business authorization,
      anti-replay/idempotency, state/revocation and payment controls
         |
         v
EXECUTE or STOP, and Merchant signs/returns Checkout Receipt
```

- **Verified Evidence ≠ user consent confirmed by this library ≠ permission to purchase.** The trusted issuer/provider is assumed to have obtained consent under its trust relationship; a valid cryptographic signature alone does not establish that assurance. [agent_authorization L34–L79](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L34-L79)
- The Merchant **MUST** verify a Checkout Mandate **before completing** checkout. It may delegate the technical verification but not silently omit the Merchant role's obligations. [specification L292–L317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L292-L317)
- **Policy decision (本OSS):** 未確認・不正・未サポート・重要情報欠落は **Fail Closed**。仕様で必須とされる事項と、追加のHostポリシーを混同しない。[security_and_privacy_considerations L3–L8](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/security_and_privacy_considerations.md#L3-L8)

### 分類の読み方

| ラベル | 意味 |
| --- | --- |
| **AP2 MUST** | 上記固定仕様の明示的MUST/REQUIRED、またはそのMUSTが参照する必須の検証ステップ。指定された**役割**にのみ適用。 |
| **AP2 RECOMMENDED / SHOULD** | 上記固定仕様の推奨（強制拒否の根拠ではない）。 |
| **Upstream dependent / 要確定** | AP2が別仕様に委譲、または文書だけでは適用範囲が未確定。断定しない。 |
| **Host policy / Project Fail Closed** | 安全側に倒す本OSSの設計候補・サービス側義務。**AP2 MUSTと誤記しない**。 |

## 2. AP2 v0.2の明示的な規範・データ要件

| ID | 適用/強度 | Verifierが扱う条件・責務 | 固定根拠 |
| --- | --- | --- | --- |
| R01 | **Merchant — AP2 MUST** | Checkout完了前に適切なCheckout Mandateを受け取り、Agent Authorizationの検証・hash照合・該当する全制約を評価する。技術的な検証を委託することは可能。 | [specification L292–L317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L292-L317) |
| R02 | **Mandate — AP2 MUST** | `vct`を**suffix込み完全一致**で識別。Closed = `mandate.checkout.1`、Open = `mandate.checkout.open.1`。接頭辞一致・無印版・v0.1形式は無条件受理しない。 | [specification L136–L143](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L136-L143) / [checkout_mandate L12–L18](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L12-L18) |
| R03 | **Schema — REQUIRED** | Closed の `vct` / `checkout_jwt` / `checkout_hash` は必須。Open の `vct` / `constraints` / `cnf` はスキーマ上必須。さらにOpen schemaの`constraints`には **`checkout.line_items` が少なくとも1件含まれること（`contains`）** が定義されている。型・必須項目・制約schemaを確認する。**Openはclosedの全項目を要求されない**（ただし汎用Agent Authorizationの`constraints` OPTIONALとの関係は§6で留保）。 | [checkout_mandate.json](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/checkout_mandate.json) / [open_checkout_mandate.json](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json) / [agent_authorization L433–L447](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L433-L447) |
| R04 | **Open — AP2 MUST** | Open MandateはAgent公開鍵の `cnf` を含む。署名・Key Binding/Proof-of-Possessionで、その鍵を持つAgentによる特定取引への結合を検証する（鍵の自己宣言は信頼根拠にしない）。Directのユーザー承認済みClosedへ一律にOpenの `cnf` 必須を拡大しない。 | [specification L221–L235](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L221-L235) / [agent_authorization L386–L416](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L386-L416) / [agent_authorization L433–L447](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L433-L447) |
| R05 | **AP2 verification rule (via normative reference)** | 受信した **SD-JWT / Delegate SD-JWT** チェーンの各段を順に検証。原Issuerの署名・SD-JWT disclosure digest・各hopの `cnf`→次の署名鍵の関連・ `sd_hash` または許される `issuer_jwt_hash` の結合を確認。**有効そうな末端だけを見て途中を省略しない**。 | [agent_authorization L455–L465](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L455-L465) / [agent_authorization L539–L544](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L539-L544) / [Delegate SD-JWT (individual draft), pinned snapshot](https://github.com/GarethCOliver/gco-delegate-sd-jwt/blob/e44c0c1db71568877776cb0742b14e8f5325ce90/draft-gco-oauth-delegate-sd-jwt.md#verification) |
| R06 | **AP2 verification rule** | Open Mandate Contentで見える固定claimは、Closed Mandate Contentでも同じ値を保持すること。権限の増幅・値の上書きは不適合。 | [agent_authorization L455–L465](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L455-L465) |
| R07 | **AP2 MUST** | Openが含まれる場合、それぞれのConstraintをClosedに対して評価。**未知のConstraintは失敗**。単なる「違反なし」配列を包括的な認可と扱わない。 | [agent_authorization L455–L465](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L455-L465) / [specification L307–L317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L307-L317) |
| R08 | **Constraint-specific AP2 MUST** | `checkout.allowed_merchants`: 照合するMerchantは**開示された** `allowed` に含まれる必要がある。非一致、または開示されたMerchantが0件なら**無効**。 | [checkout_mandate L35–L69](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L35-L69) |
| R09 | **Constraint evaluation definition** | `checkout.line_items`: 各要件の数量と開示されたacceptable item IDで照合し、同じ要件/Checkout itemを二重使用しない。定義された条件では総量と整合する完全なmatchingが必要。 | [checkout_mandate L71–L110](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L71-L110) |
| R10 | **Merchant — AP2 MUST** | MerchantがShopping Agentへ提供した**merchant-signed Checkout JWT**と、Presented Closed内の `checkout_hash` が一致することを確認。hashは **`checkout_jwt` の値**を対象とし、`_sd_alg` を使用（未指定なら `sha-256`）。第三者が任意に示した期待hashの一致だけでは不十分。 | [specification L117–L131](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L117-L131) / [specification L302–L317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L302-L317) / [checkout_mandate L20–L33](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L20-L33) / [security_and_privacy_considerations L46–L54](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/security_and_privacy_considerations.md#L46-L54) |
| R11 | **Merchant — AP2 MUST** | 検証失敗時は適切なerrorを含む **Checkout Receipt JWT** をShopping Agentへ返す。成功・拒否後のCheckout Receipt発行もMerchantの責務。**ライブラリは結果を返すのみ**で、署名・送信・状態反映はHostが行う。 | [specification L117–L131](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L117-L131) / [specification L302–L317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L302-L317) / [agent_authorization L493–L516](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L493-L516) |
| R12 | **Receipt — schema-required (Host)** | Checkout Receiptは `status` / `iss` / `iat` / `reference` が必須。成功なら `order_id`、失敗なら `error` / `error_description` のスキーマ条件を満たす（generic Mandate Receiptとの差異は§6で保留）。 | [checkout_receipt.json](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/checkout_receipt.json) / [checkout_mandate L145–L149](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L145-L149) |
| R13 | **Security — AP2 MUST (threat model)** | LLM/Agentは攻撃主体と見なす。提示側自身によるclaim選択・チェーン提示は**信頼された入力ではない**。 | [security_and_privacy_considerations L3–L8](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/security_and_privacy_considerations.md#L3-L8) |
| R14 | **Privacy — AP2 MUST (Shopping Agent/Presenter)** | 発行者・Shopping Agentは必要なdisclosureだけを提示する義務を負う。受信Verifierもプライバシー上、余分な生Mandate/機微データを保存・ログ出力しない設計を採用（後半は本OSS方針）。 | [specification L237–L244](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L237-L244) / [agent_authorization L473–L489](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L473-L489) / [security_and_privacy_considerations L116–L143](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/security_and_privacy_considerations.md#L116-L143) |

**重要なscope境界:** `Agent-to-Agent Delegation`（別Shopping AgentへのMandate転委任）はAP2 v0.2本文で**将来の可能性・現仕様スコープ外**。R05の暗号学的委任チェーン検証を根拠に、任意のAgent A→Bの**業務権限転委任が標準化済み**とは扱わない。[specification L256–L260](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L256-L260)。Human Present/Not Presentは区別する。[specification L192–L235](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L192-L235)

## 3. SHOULD / RECOMMENDED（強制とは分離）

| ID | 強度・適用側 | 内容 | 固定根拠 |
| --- | --- | --- | --- |
| S01 | **RECOMMENDED / Openを発行する側** | `exp` をタスク遂行に必要な最短期間に設定。**`exp` 欠落がAP2により一律MUST-rejectとは書かれていない**。Verifier側の期限上限はHost policyで決める。 | [specification L221–L229](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L221-L229) |
| S02 | **RECOMMENDED / OpenID4VPを行う側** | 使用可能な環境でDigital Credentials APIを使う。Merchant Checkout Verifierの必須APIではない。 | [agent_authorization L97–L121](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L97-L121) |
| S03 | **SHOULD / Shopping Agent側** | 有効なMandateと使用中タスクの管理機能を提供する。受信側Gemの状態管理義務ではない。 | [implementation_considerations L129–L139](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/implementation_considerations.md#L129-L139) |

## 4. Trust Boundary：各当事者が責任を持つ情報

| 対象 | Verifierに委託可能な技術検証（候補） | Host／他の当事者が決めること |
| --- | --- | --- |
| 署名Issuerと鍵 | **Hostから与えられる**信頼済みIssuer/key resolverを使ってJWTの署名、VC証明を検証。 | Issuer / Trusted Agent Provider / User Credential Issuerの採否、鍵ローテーション・失効・信頼ポリシー。JWTに入った `iss` / `jwk` を根拠に勝手に信頼しない。[agent_authorization L34–L79](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L34-L79) / [agent_authorization L289–L312](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L289-L312) |
| Agent/Holder | `cnf`・Key Bindingの整合性を検証。 | Agent本人・Hostアカウントへの割当と追加の取引資格。Agent IDをMandate内の文字列だけで判断しない。[agent_authorization L386–L416](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L386-L416) / [implementation_considerations L99–L104](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/implementation_considerations.md#L99-L104) |
| Audience / nonce / 時間 | 確認先・トランザクションの期待値が与えられた場合の整合性とPoPを検証する設計候補。既知の時刻claimがある場合の期限検証。 | fresh nonce生成/消費履歴、受信宛先識別、許容時計ずれ、未設定 `exp` の拒否・TTL、replay防止。**AP2本体で全Mandateにaud/nonce必須と断定しない**（§6参照）。[specification L221–L229](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L221-L229) / [agent_authorization L97–L121](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L97-L121) |
| Mandate制約/開示 | 未知typeは不成立、known typeは可視部分とauthenticityを評価。必須の判断材料が無い場合は **verification incomplete/failure**。 | 非開示項目が元々存在したか分からない場合に必要となる事前のポリシー、予算・注文回数などのstateful control。**「見えない制約は存在しなかった」と仮定しない**。[agent_authorization L433–L465](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L433-L465) |
| Checkout object | Hostの権威ある正確なserialized Checkout JWTを材料として `checkout_hash` を照合。 | MerchantのCheckout JWT生成・署名、署名鍵の正当性、最新Checkoutセッション、価格・通貨・商品・税・送料・在庫・対象Userの業務評価。AP2はCheckout payloadそのものに中立（UCP利用時はUCP Checkout）。[checkout_mandate L20–L33](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L20-L33) / [specification L381–L387](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L381-L387) / [implementation_considerations L8–L32](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/implementation_considerations.md#L8-L32) |
| Replay / 同一Mandate多重使用 | 検証されたMandateハッシュ等の証拠をHostへ渡す契約を今後検討。 | 同一Mandate/注文/決済の再利用・並列実行・失効・receiptとの突合を永続的・原子的に抑止。Shopping Agentは前回拒否Receiptなしの後続presentを禁止されるが、**Merchantがそれに依存して二重課金防止済みとしない**。[specification L237–L244](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L237-L244) / [security_and_privacy_considerations L100–L114](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/security_and_privacy_considerations.md#L100-L114) |
| エラー・業務実行 | 拒否理由・検証済み事実（**NOT ALLOW**）をHostに示す（提案でありAPI確定ではない）。 | fail時Checkout Receipt JWTを署名・返却し、適切なerrorに分類。User consent UX、リスク審査、最終購入・決済・監査。[specification L302–L317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L302-L317) / [agent_authorization L493–L535](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L493-L535) |

**設計前提（追加の安全基準、公式MUSTの引用ではない）:** 入力byte size、ネスト・hop数、disclosure数、計算量、許容alg・鍵サイズ、タイムアウト、JSON/JWTの厳格解析、例外時停止、機微情報のログマスキング等をHost/Verifierで合意してfail closed。これらの具体値はP0-4以降の設計・負例試験で決める。

## 5. Fail Closed：負例テスト観点（**未実行**）

| Test ID | 入力・攻撃 | 期待結果 / 責務 | 根拠 |
| --- | --- | --- | --- |
| N01 | JWT・開示digest・任意hopの署名/結合を改ざん | **拒否**（Verifier）。末端の見た目だけでsuccessにしない。 | [agent_authorization L455–L465](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L455-L465) |
| N02 | 未信頼Issuer・不明な鍵・Mandateに書かれた自己申告JWK | **拒否／信頼未確定**（Host policy + Verifier）。 | [agent_authorization L34–L79](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L34-L79) |
| N03 | `vct` suffixなし、未知suffix、誤ったopen/closed schema | **拒否**（Verifier）。 | [specification L136–L143](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L136-L143) / [checkout_mandate L12–L28](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L12-L28) |
| N04 | Openの `cnf` 欠落・改ざん、別Agentの秘密鍵によるpresent | **拒否**（Verifier、PoP）。Direct Closedとは区別。 | [specification L221–L235](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L221-L235) / [agent_authorization L386–L416](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L386-L416) |
| N05 | 途中のopen claimがclosedで書換え、hash/chainが別の親を指す | **拒否**（Verifier）。 | [agent_authorization L455–L465](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L455-L465) |
| N06 | unknown constraint、型不正、必要な開示がない | **拒否／検証不能**（Verifier）。**元の非開示制約の存在は可視断片から推定不能**。 | [agent_authorization L455–L465](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L455-L465) / [checkout_mandate L35–L58](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L35-L58) |
| N07 | allowed_merchantsにMerchant不在、あるいは開示0件 | **拒否**（Verifier）。 | [checkout_mandate L45–L58](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L45-L58) |
| N08 | line_itemsの数量/ID不一致、重複利用、余分/不足項目 | **拒否**（Verifier）。 | [checkout_mandate L71–L110](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L71-L110) |
| N09 | closed `checkout_hash` はcheckout A、最新の承認対象Checkout JWTはB | **拒否**（Verifier）。Host提示の正しいserialized JWTとhash計算。 | [specification L302–L317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L302-L317) / [security_and_privacy_considerations L46–L54](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/security_and_privacy_considerations.md#L46-L54) |
| N10 | merchant-signed JWTの不正署名・Hostが発行していないCheckout | **拒否**（HostのCheckout同一性・鍵policy）。hash一致だけでは不可。 | [specification L117–L128](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L117-L128) / [implementation_considerations L8–L22](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/implementation_considerations.md#L8-L22) |
| N11 | 有効期限切れ、期待aud/nonceと違う/不足 | **拒否**（存在する時刻・bindingの規範に従う + Host policy）。**規格の全ケースMUSTと一括表現しない**。 | [specification L221–L229](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L221-L229) / [agent_authorization L539–L544](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L539-L544) |
| N12 | 同一Mandateを再提示、並列・二重実行、失効済みMandate | **Hostが実行拒否/重複防止**。暗号的に正しいだけでは状態管理の証明にならない。 | [specification L237–L244](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L237-L244) / [security_and_privacy_considerations L100–L114](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/security_and_privacy_considerations.md#L100-L114) |
| N13 | 破損JSON、巨大token/chain、未サポートalg・危険入力 | **Fail Closed**（本OSS安全要件案）。具体的制限・テスト値は未決定。 | [SECURITY_BOUNDARY](SECURITY_BOUNDARY.md) / [security_and_privacy_considerations L3–L8](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/security_and_privacy_considerations.md#L3-L8) |
| N14 | 失敗MandateをHostが受け取る | **Checkoutを実行せず**、Hostはerror Checkout Receipt JWTを返す。 | [specification L302–L317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L302-L317) |

仕様の規範を追加確認するまで、「受け入れたら絶対安全」「全種類のreplay・失効を防げる」とは主張しない。

## 6. 未確定・競合・上流依存事項

1. **Delegate SD-JWTの参照版と型・binding詳細：** AP2は[個人Internet-Draft](https://github.com/GarethCOliver/gco-delegate-sd-jwt)を規範参照。比較用に `e44c0c1db71568877776cb0742b14e8f5325ce90` をスナップショットとして確認した（**AP2 v0.2採択済みの別tagとみなさない**）。同draftの[Verification](https://github.com/GarethCOliver/gco-delegate-sd-jwt/blob/e44c0c1db71568877776cb0742b14e8f5325ce90/draft-gco-oauth-delegate-sd-jwt.md#verification)と公式Python SDKは、`typ` alias/中間hopの扱い等をP0-3で対照する。RFC 9901とこの**個人draftは標準化状態が違う**。
2. **aud / nonceの規範・存在チェック：** AP2 Checkout schemaにはglobal mandatory aud/nonce がない。一方、KB-SD-JWTやOpenID4VPの提示時規則を確認する必要がある。上流[#319](https://github.com/google-agentic-commerce/AP2/issues/319)（2026-10-11時点Open）はSDKのexpected_aud/expected_nonceが省略可能な問題を報告。Hostから期待値がない場合のreject policyは**未確定**。
3. **Checkout hashの入力表現：** 値は文字列の`checkout_jwt`、`_sd_alg`と同じhash（既定sha-256）。JWTをparse後再serializeしたhashや外部任意のexpected hashではない。具体的なcanonical/test vectorはP0-3で照合。上流[#358](https://github.com/google-agentic-commerce/AP2/issues/358)（Open）を参照。[checkout_mandate L20–L33](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L20-L33)
4. **Selective Disclosureと隠れたConstraint：** 仕様ではunknown constraintはfailだが、*そもそも未開示で検証対象から見えないもの*の検出・期待constraint集合は十分に定義されていない。現行Open Checkout schemaには`checkout.line_items`存在要件があり、汎用Mandateの`constraints` OPTIONALより厳格。どのスキーマ層・Disclosure時点で評価するか要調査。空の評価結果を許可に変換しない。[#339](https://github.com/google-agentic-commerce/AP2/issues/339)（Open）。[agent_authorization L433–L465](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L433-L465)
5. **`vct` 文面の不一致：** スキーマ `const` とSpecification/Type節はsuffix付きだがスキーマdescriptionは旧表記。[#322](https://github.com/google-agentic-commerce/AP2/issues/322)（Open）。正本はsuffix完全一致。[checkout_mandate.json](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/checkout_mandate.json)
6. **Receiptの表現差：** Agent Authorizationの汎用Mandate Receiptは `result: success/error`、Checkout Receipt schemaは `status: Success/Error`。役割別の関係、署名、`reference`の表現は決め打ちしないで照合。[agent_authorization L493–L516](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L493-L516) / [checkout_receipt.json](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/checkout_receipt.json)
7. **期限・失効・replay・二重課金：** `exp` の全体必須条件、replay token/receiptと原子的重複防止、失効情報の取得方式はHost責務との合意が必要。上流[#346](https://github.com/google-agentic-commerce/AP2/issues/346)（Payment Mandate再利用、初期スコープ外、Open）。[security_and_privacy_considerations L100–L114](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/security_and_privacy_considerations.md#L100-L114)
8. **金額・通貨・merchant一致：** AP2 Checkout標準Constraintは `checkout.allowed_merchants` と `checkout.line_items`。**あらゆる価格上限を標準Checkout constraintが規定しているとは主張しない**。その他はCheckout object/UCPの意味づけとHost business policyに依存。[checkout_mandate L35–L43](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L35-L43) / [specification L381–L387](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L381-L387)
9. **仕様上の曖昧さ：** [specification L145–L157](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L145-L157)はPaymentとのCheckout hash連携に関連して非決定的署名方式をMUSTと表現する一方、[security_and_privacy_considerations L139–L148](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/security_and_privacy_considerations.md#L139-L148)は決定的署名なら十分なsaltを持たせる形を述べる。**本タスクで暗号algを決めない**。対象はCheckout検証でありPayment実装は非スコープ。

**上流Issueは報告の存在とOpen状態を確認しただけで、脆弱性・修正・Pythonの再現テストを本OSSで実証したものではない。**

## 7. 完了基準と次の1タスク

- [x] MerchantのMUST、role-specific責務、schema REQUIRED、推奨/未規定/Host policyを分類。
- [x] Open/Closed、Issuer/PoP、SD-JWT chain/Disclosure、Constraint、Checkout JWT/hash、Receiptを根拠付きで整理。
- [x] 想定負例を14ケースに分類し、**実施前の期待値**として明記。
- [x] 未確定仕様・Python SDKとの差異候補、マルチAgent転委任のスコープ外を明記。
- [ ] Python SDKのコード・test vectorを実行照合（P0-3）。Gem/API/CI/適合性検証は未実施。

**次の重要タスク（1件のみ）:** **P0-3 — 公式Python SDKの署名・開示・chain・hash・constraintsの実際の実装/テストと既存Ruby Gemの再利用可能性を照合し、`docs/ECOSYSTEM_RESEARCH.md` にまとめる。** その結果が出るまではGemのAPIや実装を確定しない。
