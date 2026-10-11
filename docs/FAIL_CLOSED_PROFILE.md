# Minimal Fail Closed Profile — AP2 v0.2 Checkout (Phase 0 / P0-5b)

**作成日:** 2026-10-11 JST  
**状態:** **設計・非本番PoC用の制限プロフィール案 / NOT IMPLEMENTED / NOT AP2 CONFORMANCE / NOT PRODUCTION READY**。  
**判定との関係:** 本文は「実装してもよい狭い境界」を提案するが、この文書の存在・マージだけでは実装に着手しない。GO/HOLD判断は[RESEARCH_DECISION](RESEARCH_DECISION.md)§9を参照。  
**基準:** AP2 `v0.2.0` commit `b4587ac1d055888a73b4b21750973cffba961793`、[SPEC_BASELINE](SPEC_BASELINE.md)、[VERIFIER_REQUIREMENTS](VERIFIER_REQUIREMENTS.md)、[API_PROPOSAL](API_PROPOSAL.md)、[P0-5a実測](PYTHON_BASELINE_VERIFICATION.md)。

## 1. 最小スコープ — できることより拒否できることを優先

**候補は「Human Not Present / Autonomous、ユーザー署名済Open Checkout → 同一Agent署名済Closed Checkout」のちょうど2段（Root + Terminal）に限定**する。Shopping Agentは1つ、親子の追加中間hopは0。Hostが既に生成・保存している **merchant-signed Checkout JWT** を検証対象とする。Local-only/offline、事前登録したIssuerとMerchant公開鍵だけ使用。Root署名・Disclosure・Holder Key Binding・Checkout hash・Constraintを**すべて**通した時だけ技術的証拠を返す。

```text
 Host (trusted config / state)
   |-- allowlisted Root Issuer verification JWK
   |-- merchant signed Checkout JWT + trusted merchant public key
   |-- merchant ID, expected audience, fresh nonce, clock, bounded TTL
   |-- required disclosures / strict feature & size policy
   v
 UNTRUSTED AP2 presentation (Open SD-JWT ~~ Closed KB-SD-JWT)
   -> exactly 2-hop parse & bounded resources
   -> issuer-signed root + fully inspectable authority-bearing claims
   -> terminal Agent signature bound to verified root cnf.jwk
   -> exact terminal aud/nonce and time policy
   -> Open/Closed unchanged claims + type + constraint check
   -> trusted merchant Checkout JWT signature + exact bytes + checkout_hash
   -> VerifiedEvidence OR Rejection (never ALLOW)
   v
 Host alone: revocation, replay, account, business and payment authorization
   -> Host signs and returns Checkout Receipt; never execute on Rejection
```

### 明示的な非スコープ（入力が来たら例外なく拒否、勝手に迂回しない）

- **Direct/Human PresentのRoot Closedのみ**。後続で別の専用trustモデルを設計する。Openを使う自律経路の前提を無理に流用しない。
- **3段以上の中間delegation/多Agent転委任**。AP2 v0.2はAgent-to-Agent Delegationを本文の現行スコープ外と記述。[AP2 docs/ap2/specification.md L256-260](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L256-L260)
- Payment Mandate、Wallet、Credential Provider、任意VDC、未知の`vct`/暗号`alg`/Constraint、Receipt発行・決済実行。
- 提示JWTの`jku`/`x5u`等の**任意ネットワーク鍵取得**、自己申告`x5c`からの動的Trust確立、未指定rootの黙示受入。
- `issuer_jwt_hash`によって前段Disclosureを変えるモードは初期PoCでは**unsupported**。まず上流SDKで検証済みの`sd_hash`に限定する（**本OSS固有の制限であってAP2 MUSTではない**）。

## 2. 規格義務と本OSSの上乗せ方針を分ける

| 検証条件 | 根拠の分類 | 今回のPoCでの受入条件 |
| --- | --- | --- |
| RootのAP2 Mandate Type | **AP2 MUST** | Openは`mandate.checkout.open.1`、Closedは`mandate.checkout.1`に完全一致。prefix一致は拒否。[AP2 docs/ap2/checkout_mandate.md L12-18](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L12-L18) |
| 自律OpenのHolder鍵 | **AP2 MUST** | Rootに`cnf.jwk`があり、Hostの信頼Issuer署名で保護された値であること。Closedは当該秘密鍵を持つAgentの署名であることを検証。[AP2 docs/ap2/specification.md L221-235](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L221-L235) / [AP2 docs/ap2/agent_authorization.md L386-416](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L386-L416) |
| Delegated SD-JWTの検証 | **AP2規範からの参照** | Root signature、Disclosure digest、Root→Terminal鍵binding、terminalの`sd_hash`を送信されたOpenの**元のwire表現**に対して確認。無検証のpayloadを正本化しない。[AP2 docs/ap2/agent_authorization.md L455-465](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L455-L465) |
| SchemaとConstraint | **AP2/Mandate型固有** | Openの`constraints`に`checkout.line_items`があること（JSON Schemaの`contains`）、全ての**適用対象で開示された**Constraintを評価。未知のtypeは拒否。[AP2 code/sdk/schemas/ap2/open_checkout_mandate.json L19-35](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json#L19-L35) / [AP2 docs/ap2/agent_authorization.md L455-465](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L455-L465) |
| Checkout Hash | **MerchantのAP2 MUST** | Host正本`checkout_jwt`をmerchantの公開鍵で署名検証し、Closed中の`checkout_jwt`と原文一致。その値の**UTF-8文字列に対するHashのbase64url（paddingなし）**を計算しClosed`checkout_hash`に一致。初期版は`sha-256`のみ。他`_sd_alg`は拒否。[AP2 docs/ap2/checkout_mandate.md L20-33](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#L20-L33) / [AP2 docs/ap2/specification.md L302-317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L302-L317) |
| 任意中間hopのaud/nonce | **AP2と実装の適用範囲が未解決** | 中間hopを**認めない**。固定版の公式pytestは中間hop`aud`/`nonce`の2件が失敗したが、それを本OSSの全AP2仕様違反と断定しない。[P0-5a](PYTHON_BASELINE_VERIFICATION.md) |
| Terminalのaud/nonce | **本OSSのHost必須ポリシー（全AP2フローMUSTと主張しない）** | Hostが発行した非空の期待`aud`と`nonce`を必須入力とし、Terminal上の両claimが存在かつ一致すること。期待値のない検証は拒否。Python検証器で省略時に欠落が許されるケースを実署名負例で再現済み。 |
| Rootの`exp` | **AP2はOpenの短い期限設定をRECOMMENDED。本OSSでは追加必須** | Root`iat`と`exp`、Terminal`iat`を必須。Hostが必ず有限の`max_age`、未来時刻の許容ずれ、現在時刻を供給。期限のないOpen/長すぎるOpenは拒否。数値はまだ採用未決。[AP2 docs/ap2/specification.md L221-229](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L221-L229) |
| 未開示の制約 | **AP2は必要なDisclosureに絞る（privacy）／本OSSは追加安全条件** | 初期版は**正規Rootがcommitした権限制約について完全性を証明できる場合だけ評価**。配列レベルなど未開示のConstraint候補があれば拒否。証明不能な場合は`incomplete_disclosure`、unsupported issuer layout、またはPoC実装HOLD。本文§3参照。 |
| 失効、再利用、receipt | **Host側業務とAP2 Merchant規定** | Verifierは実行許可を出さない。Hostはnonceを原子的に使い切り、Checkout最新性/在庫/価格/権限/失効/replayをチェックし、失敗時の署名Checkout Receiptを返す。[AP2 docs/ap2/specification.md L302-317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L302-L317) |

**指定する暗号ポリシー:** プロトタイプは単一の許可署名アルゴリズム（候補: ES256）と適切な鍵曲線をHostのallowlistで固定する。未サポート・`alg=none`・headerの`jwk`/URLの自己申告は拒否。**JS/Ruby/SDKの正式な相互運用やSECP256R1 JWS署名検証の実測はPhase 1 PoCのテスト課題**であり、ここで保証したとは書かない。

## 3. Selective Disclosureの「見えない制約」の扱い

[P0-5aの実署名負例](PYTHON_BASELINE_VERIFICATION.md)で次を観測:

1. IssuerがOpenに **LineItems + AllowedMerchants** を入れ、AllowedMerchantsをSelective Disclosureできる形で署名する。
2. AgentがAllowedMerchantsを**非開示**としたwire presentationを作る。
3. Root署名・開示digestは有効なまま、受信側の可視Constraint評価が**LineItemsのみ**になり、不許可Merchantでも違反0件となる。

**この挙動の結果だけで、通常のAP2が常に脆弱、または取引を勝手に許可した、という意味にはならない。** 制約自体の非開示ができるIssuer layoutであり、Hostの取引許可は未評価。だが、`constraints`を単に列挙して`errors=[]`なら安全とするVerifier APIは危険である。

**PoCの安全側ルール（プライバシー/互換性より狭い）：**

- Root署名・Disclosuresの**検証済み構造**に、制約を含むpayload／配列／`_sd` commitがあるのに、**それが何をcommitしたか確認できない**場合は、`VerifiedEvidence`を生成しない。
- **Rootの権限制約一覧が完全に提示されたこと**をIssuerの固定プロフィールと照合して証明する。現段階は少なくとも `constraints` 全要素（`checkout.allowed_merchants`を含む）の存在・型・評価可能性を要求。**未開示Constraintが存在しないと判定する方法が成立しないIssuer形式はPoC非対応**。
- 個別の`allowed`要素や`acceptable_items`の非開示は、明示された制約の許可集合を狭くするだけならAP2のPrivacyに適う余地がある。しかし初期PoCでは無差別に許さず、**緩和方向にならないと証明した種類のみ**後続でallowlist化。証明まで`incomplete_disclosure`で拒否。
- **デコイdigestと本物の未開示要素を区別できない可能性**がある。『残った`_sd` digestがない』等の単純判定を安全性証明として確定しない。**発行時のIssuerプロファイル/commitment構造で完全性が識別できなければHOLD**。
- **全て公開せよ、がAP2 MUSTという主張ではない**。この制限はRuby PoCの小さなsupported subsetを明示するための追加Host policyであり、AP2の必要最小開示というプライバシー理念とのトレードオフを明記する。

## 4. Hostから明示的に渡される最低入力とFail Closed

| Host提供必須情報 | ない時 | 技術検証での責務 |
| --- | --- | --- |
| `issuer_verification_key` とIssuer identity/trust policy | `untrusted_issuer` | Root署名が**Hostが承認したIssuer**の鍵に対応するか。固定JWK以外の鍵取得、root不明を拒否。 |
| `merchant_verification_key` / 正本の`signed_checkout_jwt` | `incomplete_context` | JWTのMerchant署名、原文、保存中のCheckoutが現行セッションの取引かの同一性。 |
| `expected_audience` / `expected_nonce` | `incomplete_context` | Terminalの一致・未記載拒否。Hostが発行しnonceを管理するが、Verifierでは**一度限り消費まで保証しない**。 |
| `merchant_id` / `expected_agent_key`または同等の信頼文脈 | `incomplete_context` | Hostの受入Merchant、事前承認AgentとRootでendorsedされた`cnf`鍵の対応を評価する。Agent文字列だけでは同定しない。 |
| `required_disclosure_profile` / issuer authorization-bound layout | `incomplete_disclosure`または`unsupported_profile` | **可視のみ評価**による成功を避け、隠された権限制約を扱える形で拒否する。 |
| `now` / `max_age` / 最大skew / 署名`alg` allowlist、サイズ/深さ上限 | `incomplete_context`または`unsupported_format` | `exp`と`iat`の範囲・Resource Exhaustionを検証。デフォルト無制限は使わない。 |

入力は[API_PROPOSAL](API_PROPOSAL.md)の仮インターフェイスに対応。**公開Ruby API名の確定、依存Gem選定は未実施**。`expected_agent_key`はHostのAgent受け入れ制約の例であり、AP2全Merchantに特定Agent登録がMUSTという主張ではない。

## 5. 拒否ゲート（将来の負例テスト計画、Ruby未実行）

| Gate | 拒否条件（少なくとも1つ該当すればSTOP） | 証拠 |
| --- | --- | --- |
| G01 Root trust | Root署名NG、Issuer keyがHost登録外、`x5c`を自己信頼、unknown `kid` | P0-5a：trusted rootなし`x5c` helperの受理／異なるroot指定で拒否を実測 |
| G02 Chain form | Open→Closed以外、3hop以上、root`cnf.jwk`欠落、PoP不一致、未知`typ` | AP2 agent_authorization §verification、PoC上乗せ |
| G03 Claims binding | `sd_hash`不一致、未サポート`issuer_jwt_hash`、`vct`不一致、Open固定claimの変更 | AP2/Delegate SD-JWT規範、固定SDKの解析 |
| G04 Challenge / time | expected `aud`/`nonce`がない、Terminal上で欠落・不一致、root `exp`なし・期限外/長すぎる | P0-5a：署名付きterminal欠落は期待値なしなら受理／期待値ありなら拒否 |
| G05 Disclosure completeness | 未開示のConstraint型/個数/意味を認証された形で証明できない、必要Disclosure欠落、デコイ等で区別不能 | P0-5a：署名付きMerchant制約を隠すと可視評価は0件 |
| G06 Constraint | `checkout.line_items`欠落、未知type、MerchantまたはItem数量/IDの制約不一致 | AP2 Checkout schema/type/evaluatorのMUST |
| G07 Checkout authenticity | Host正本JWTなし、merchant署名偽、別のCheckout JWT、timestamp/Checkout ID不一致、`checkout_hash`不一致/期待hash省略 | P0-5a：helper単体では別Checkout・偽hashを拒否しない |
| G08 Error/final approval | 依存失敗、例外、リソース超過、Replay/失効や業務拒否をHostが検出 | Verifierは`Rejection`、Hostは**購入STOP**と署名付きerror receipt。ReplayはHostの原子的判断 |

**API不変条件:** `VerifiedEvidence`は正しく満たした検証事実の記録であり、`ALLOW`/`authorized?`/`payment_approved`を返すものではない。Callerがこの区別を破った場合、Verifier成功でも安全な業務実行は保証されない。

## 6. GO / HOLD / NO-GO の判断に必要な残課題

**根拠は研究として十分に揃ってきたが、Ruby PoCの実装方法と境界条件を全て実証したわけではない。** [AP2 docs/ap2/agent_authorization.md L455-465](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L455-L465) / [P0-5a](PYTHON_BASELINE_VERIFICATION.md)。

- **VerifiedEvidenceの出力契約:** どの項目が保証されたか（Issuer/holder、Checkout JWT原文Hash、constraint completeness、challenge）を証拠レベル別に明記する。
- **非開示Constraintの完全性判断:** 今の標準的なDisclosureだけで未知の制約存在を否定できない場合、**Issuerプロファイル限定/Full Disclosure限定**を実装で厳格に達成できるか。達成できなければHOLDに戻す。
- **最小Ruby依存・アルゴリズム相互運用:** `jwt`／`json_schemer`／`OpenSSL`で正負の固定fixtureを扱えるか、Phase 1で最初に試験する。**独自暗号実装や署名の省略で妥協しない**。
- **Openの期限とbusiness rules:** root expiryをPoCで必須とすることが実Issuerで利用可能か。Merchant同一性、Checkout状態、nonceの原子的消費、ReceiptはHost側の統合テスト課題。
- **プライバシーと利用可能性の制限:** 完全開示しか受け付けない初期版はAP2の広いプライバシー／相互運用を実現した製品とは呼ばない。

**P0-5bの目標は「狭い範囲で安全にPoCできるなら明示し、できない場合はHOLDを続ける」こと。** すべての上流Issue解消やSDK公式188/188をPoCの開始条件とするのではなく、どこまで受け取らないかを曖昧にしない。最終の再判定は[RESEARCH_DECISION](RESEARCH_DECISION.md)を参照。
