# Phase 2-A — 最小 Merchant Checkout Verifier 契約（設計パッケージ）

**2026-10-12 JST / Issue [#45](https://github.com/cuichangquan/ap2-mandate-verifier/issues/45) / PROPOSED / DESIGN ONLY / NOT IMPLEMENTED / NEW TESTS NOT RUN**

> **Gate:** Phase 1 の [総括と移行判断](PHASE1_RESEARCH_CLOSURE_PHASE2_GATE.md) は、**新Phase 2-A「仕様設計だけ」を CONDITIONAL GO** とした。Phase 2-B の実装、汎用/public Ruby API、Gem公開、本番Merchant、実決済・Receipt、HC06強失効は**別の判断までHOLD/NO-GO**。この資料のレビューやマージだけで承認しない。

## 0. 基準点・既存文書との関係

- AP2 **v0.2.0** pinned commit `b4587ac1d055888a73b4b21750973cffba961793`、[仕様基準](SPEC_BASELINE.md)。上流SDKの後日の変更は自動適用しない。
- [P0-4 API_PROPOSAL](API_PROPOSAL.md) は **過去の未実装・広めの設計案**（Direct を含む）であり、このPhase 2-Aの受理範囲を定義しない。
- [FAIL_CLOSED_PROFILE](FAIL_CLOSED_PROFILE.md)、[HOST_SECURITY_CONTRACT](HOST_SECURITY_CONTRACT.md)、[P1-10s gap](VERIFIER_P110S_CONSTRAINT_SHAPE_TYPE_GAPS.md)、[P1-10u S01限定実測](VERIFIER_P110U_S01_TYPE_FIX_PREPARED_NOT_RUN.md) に基づく。これらの結果は一般AP2準拠の証明ではない。
- 仕様由来の条件と**本OSSだけの厳格化**を区別する。ここで示す型名・reason code・値は**内部契約候補**であり、確定Public APIでも実装済みクラスでもない。

## 1. 想定する受理プロフィール — 1つだけ

| 項目 | Phase 2-A候補 | 性質 |
| --- | --- | --- |
| フロー | **Autonomous / Human Not Present**。Open Root `mandate.checkout.open.1` → Closed Terminal `mandate.checkout.1`、**ちょうど2hop**、中間委任なし | 公式の型値 / hop数は**本OSS限定** |
| Root | Hostが事前に認めた**固定Issuer identity、検証用公開鍵、使用用途、アルゴリズム**、固定のIssuer発行レイアウト | **HostのTrust方針**。Presented `iss`/`kid`/`x5c`/URLから新規信頼しない |
| 暗号・Disclosure | 検証済みIssuer JWS、完全なDisclosure digest、Root署名済み `cnf.jwk` → Terminal Agent署名/PoP、`sd_hash`。当初 ES256/P-256、`sha-256` のみ | 一部公式根拠 + **ローカル限定**。秘密鍵はHostから渡さない |
| 制約 | 認証済みRootで**権限を緩め得る制約がすべて可視・評価可能と証明できる**固定Issuer layout。研究ケースは allowed_merchants 1、line_items 1、各配列1要素、Checkout 1件 | **本OSSの狭い形状制限**。署名が正しいだけで完全性は証明されない |
| Claims | 検証済みOpenの固定claimをClosedに保持。Terminal `aud`/`nonce` はHost事前発行期待値と一致。Rootの `iat`/`exp`、Terminalの `iat` を有限時間方針で検証 | Claim保存は公式根拠、期待チャレンジ等は**本OSS Host方針** |
| Checkout | Hostが保存した**現在のmerchant-signed Checkout JWTの原文**をHost登録Merchant公開鍵で検証。Presented Closedの `checkout_jwt` の原文一致と `checkout_hash` の独立計算照合 | 署名・Hash確認はMerchant側の重要な規格義務。Hostの注文状態判定は別 |
| 非対応 | Direct/Human Present、3hop以上、hidden/unknown権限、未知Issuer/鍵・暗号・Constraint/`vct`、別の `_sd_alg`、`issuer_jwt_hash` モード、複数注文、optional `merchant.website` を含む当該研究形状外入力 | **本OSSの unsupported / REJECT**。正規AP2データの一部も非対応であり仕様違反とは断定しない |

### Disclosure完全性の未解決条件（重大な設計ブロッカー）

未開示SD-JWT digestが残っている／見えない権限制約がある場合に、可視値だけを評価して成功にしてはならない。デコイと未開示権限が区別できず、**Hostに登録した信頼できるIssuerの発行プロフィールから完全性を証明できなければ `Rejection` とする**。単なる「全部開示してもらったつもり」、表示されたconstraint数、またはSigner署名は完全性の証明ではない。

**実装前HOLD:** Issuer profile・commitmentレイアウト・デコイ処理を独立したオラクルで確認できる契約を確立しない限り、Phase 2-Bへ進めない。これはAP2一般のSelective Disclosureが不安全という主張ではない。

## 2. `TrustedInputs`（仮称）と出所

**信頼はデータ自体ではなく、Hostが事前に確定した出所・スコープに付く。** `presentation_wire` だけは常に非信頼。以下のフィールド名/型は概念モデルでありPublic API決定ではない。

| 候補値 | 必須・出所 | 欠落/不確実時 |
| --- | --- | --- |
| `presentation_wire` | **UNTRUSTED** Agentから届いたcompact SD-JWT、Disclosure、委任chainの**元wire表現**。署名/hash基準として再直列化しない | `malformed_presentation` |
| `issuer_trust_profile` | **TRUSTED Host policy**。許可Issuer ID、kid→公開鍵、用途、ES256/P-256、rotation/有効期間（**有限not_after**）、固定発行・Disclosure layout、**不変なpolicy_version**。検証時のactive/非失効をHost正本で確認 | `untrusted_issuer` / `unsupported_profile` / `incomplete_context` |
| `merchant_trust_profile` | **TRUSTED Host policy**。対象Merchant ID・Tenant、Merchant JWT署名の許可鍵/alg/rotation、鍵の**有限not_after**、**不変なpolicy_version**、検証時のactive/非失効状態 | `incomplete_context` / `invalid_checkout_signature` |
| `signed_checkout_jwt_wire`, `checkout_ref` | **同じTRUSTED Host current checkout record正本**から取得。`checkout_ref = (tenant_id, checkout_id, checkout_version)`は必須の不変なsnapshot識別子で、**このrecordに実際に保存された原文JWT**との結合をHostが保証する（単なるAgent/Callerの自己申告IDは不可）。Verifierは元JWTのSHA-256を計算し、challenge recordのtenant/checkout id/versionとの一致を必ず検査。AのJWTとBのchallengeは拒否 | `incomplete_context` / `checkout_context_mismatch` / `checkout_jwt_mismatch` |
| `merchant_id`, `expected_agent_key`, `buyer_account_ref` | **TRUSTED Host** の取引・Agent identity文脈。初期profileでは**全て必須**。`expected_agent_key` はHostが当該Checkoutで承認した公開鍵（または検証済み鍵thumbprint）、`buyer_account_ref`はHostが当該取引に結び付けた**非機密の不変・opaque account参照**。Agent名やpresentation中の自称鍵/Buyerを代用しない。HostのAgent受入policyについても不変`policy_version`、有限`not_after`、検証時active/非失効状態が必要。Buyer/Accountの権利・同意そのものの確認はHostの別責務 | `incomplete_context` / `expected_agent_mismatch` / `buyer_context_mismatch` |
| `challenge_ref`, `challenge_checkout_ref`, `challenge_agent_key_thumbprint`, `challenge_buyer_account_ref`, `expected_audience`, `expected_nonce`, `challenge_expires_at` | **TRUSTED Host-issued immutable challenge正本**。すべて必須。`challenge_ref` は永続レコードに一意・不変に結び付き、**`challenge_checkout_ref = (tenant_id,checkout_id,checkout_version)`**、**発行時に承認したAgent鍵thumbprint**、Host Buyer/Account opaque ref、期待aud/nonce、有効期限を事前解決する。Verifierは**challenge Agent鍵＝Host current `expected_agent_key`＝Issuer署名済Root `cnf.jwk`（鍵同一性）**、challenge Buyer ref＝Host current `buyer_account_ref`＝Checkout正本Buyer ref、challenge Checkout ref＝Host JWT正本Checkout refを全て検査する。Agentの自己申告値は使わない | `incomplete_context` / `checkout_context_mismatch` / `expected_agent_mismatch` / `buyer_context_mismatch` / `invalid_nonce` / `invalid_audience` / `invalid_time` |
| `now`, `ttl_policy`, `resource_limits` | **TRUSTED Host** 時計、有限のroot age/skew、最大wire長・hop・Disclosure数・ネスト深度等 | `incomplete_context` / `invalid_time` / `resource_limit_exceeded` |
| `constraint_policy` | **TRUSTED Host** が固定Issuer layoutに対して適用する許容Constraint型・shapeと評価/完全性ルール | `unsupported_profile` / `incomplete_disclosure` |

- 未定値（具体的なTTL・バイト上限・鍵更新の有効ウィンドウ）は**未決としてHOLD**。無制限・暗黙のデフォルト・ネットワーク鍵自動取得は許可しない。
- `expected_nonce` の**一致**と、Hostでの**一度限り消費**は別の保証。Hostは同一取引の再発行でもchallengeごとに**一意の`challenge_ref`**を使用し、別のnonceへ付け替えない。**Challenge正本とCheckout JWT正本のtenant/checkout/versionを一つのHost信頼snapshotとして関連付け、別々に取得した任意recordを組み合わせない**。関連付けの安全性はHost依存で、Verifierは提供された両正本参照の一致を必ず確認する。
- 前処理の非信頼デコード結果は識別子探索の「候補」にだけ使える。Host登録のTrust policyで検証されるまでIssuer/Agent identityとして出力しない。
- **Agent認可・challenge固定の追加不変条件:** RootのIssuer署名を検証した後、そのRootの`cnf.jwk`とHostが現在承認した`expected_agent_key`と**Hostのchallenge発行時に固定した`challenge_agent_key_thumbprint`**が**同一の暗号鍵**を表すことを、正規化公開鍵パラメータ/検証済みJWK thumbprintで厳密照合する。JWK JSONの生文字列や`kid`/表示名比較は不可。鍵が未設定、別鍵、比較不能なら`Rejection(expected_agent_mismatch/incomplete_context)`。**Host承認Agentが後から変わっても既発行challengeのAgentを勝手に書き換えず、別challengeを発行する。** Issuerが別Agentに発行した有効MandateではHostの当該challengeの承認にならない。`buyer_account_ref`もHost checkout正本とchallengeの間で必ず同一のopaque参照と確認するが、Buyerの実際の同意はHostが別に確認する。

## 3. 出力 — 必ず区別する

次は値の**構造イメージ**。Rubyクラス/APIを実装した事実ではない。

```text
Result = VerifiedEvidence | Rejection

VerifiedEvidence (only after ALL supported gates pass):
  spec_ref              pinned AP2 version + commit
  profile_ref           Hostが受け入れた固定Issuer/Verifier profile ID
  flow                  "autonomous"（このprofileのみ）
  trusted_issuer_ref    Host policyに照合済みの参照
  verified_agent_key_ref Root cnf とTerminal署名に結び付いた鍵の参照
  checkout_binding:     { tenant_id, checkout_id, checkout_version,
                          buyer_account_ref, signed_checkout_jwt_sha256,
                          host_challenge_ref }
                        Host現在注文正本とHost challengeの同一取引対応、
                        実際に検証したHost正本JWT原文digestを束ねる（必須）
  trust_snapshot        { issuer_key_ref, issuer_policy_version,
                          merchant_key_ref, merchant_policy_version,
                          agent_key_ref, agent_policy_version }
                        Hostが登録・検証時点で承認した鍵と方針の不変参照（必須）
  constraints_checked   検証済み・評価済み制約の安全な要約
  verified_challenge:    { host_challenge_ref, verified_audience,
                           verified_nonce_sha256, verified_at,
                           approved_agent_key_thumbprint,
                           buyer_account_ref }
                         Hostで事前解決した一意・不変のchallenge参照と、
                         Terminal署名済みaud/nonceとの検証済み対応を必須出力
  valid_until           Root/Closed/Terminal・challenge・有限TTL・
                        Issuer/Merchant/Agentの信頼鍵/方針not_afterの
                        **最も早い期限**（必須、UTC epoch）

Rejection:
  stage                 format | trust | crypto | disclosure | schema |
                        binding | constraints | context | checkout | internal
  code                  下表の安全な分類
  profile_ref           確定できるときのみ。機密payloadは返さない
```

**不変条件:** `VerifiedEvidence` は署名・構造・制約を通過した**技術的証拠**であり、`approved`、`allow`、`authorized`、`payment_succeeded`、`nonce_consumed`、`not_revoked` を**含めない**。`verified_challenge` は**必須**であり、Hostの事前解決済み一意`challenge_ref`、署名検証済みTerminal `aud`、署名検証済みTerminal `nonce`のSHA-256 digest（公開ログにraw nonceを出さない）、信頼済み`now`由来の`verified_at`、**Host challengeに発行時から固定された承認Agent鍵thumbprintとopaque Buyer/Account参照**を含める。Buyerの同意/本人性をここで証明したことにはならない。**`valid_until`も必須**。Issuer検証済みRootの`exp`、検証済みClosed内部・Terminalの`exp`（存在する場合）、Host challenge期限・Host指定の有限TTL/最大経過時間、**Host承認Issuer・Merchant・Agent鍵/信頼ポリシーの有効終了時刻`not_after`**から算出される**最も早いdeadline**を表す。`trust_snapshot` は、実際に検証に使ったHost承認鍵参照と、issuer/merchant/agentそれぞれの不変なtrust policy versionを必須出力とする。**`checkout_binding`も必須**。同じHost正本由来の`checkout_ref`とchallenge recordの`challenge_checkout_ref`が一致していることを検証した上で、実際に署名検証したJWT原文のSHA-256 digestと`host_challenge_ref`を固定して出力する。Issuer/Agentの自己申告checkout IDをHost IDとして出力しない。期限claimが省略可能ならHostの有限policyで上界を定め、それも不可能なら`Rejection(invalid_time/incomplete_context)`。検証時だけ期限内でも、Host処理時の有効性は保証せず**HostはCASで再判定**する。未認証nonce/Issuer claimや単なる任意文字列のchallenge refをそのまま証拠化しない。裸の `true` や「例外がなければ成功」は使わない。未知・内部障害・可視性不明は `Rejection`（または呼び出し自体HOLD）にする。理由と監査IDはサニタイズし、raw tokens / JWK秘密情報をログ・返却に混ぜない。

## 4. 検証順序とFail Closed decision table

順番（設計案）:
1. **pre-auth / unambiguous signed bytes** wireサイズ・構文/深さ/要素数上限・hop数をチェックし、**Root、Terminal、Merchantの各JWS protected JOSE headerおよび署名済みpayload（ネストしたMerchantオブジェクトも）、SD-JWT disclosuresなど全てのJSONを元の署名対象byte表現から重複キー拒否の厳格parserで解析**する。JSON escape後に同じキーとなる表記も重複として拒否。署名済みpayloadやheaderを再直列化して署名入力を変えない。`alg`重複・`merchant.id`重複・不正UTF-8/JSON/非対応headerがあれば**crypto/Schema成功前に拒否**。JOSEは各署名主体に対するHost許可`alg`/`typ`/鍵種別/曲線/用途を厳格照合し、`none`、未知`crit`、`b64=false`等非対応仕様、自己申告`jwk`/`jku`/`x5u`によるTrust昇格を拒否。**未署名claimに基づくTrustの確立は禁止**。上記は研究時にN01/N02限定修正があったものの、全JOSE/JSONの網羅を実証済みとはしない。
2. **Trust + crypto + Host Agent binding** Hostの許可Issuer鍵でRoot署名、Disclosures digest、Root署名済み`cnf.jwk` とTerminal署名/PoP、`sd_hash` を元wireに対して照合。**Issuer/Merchant/Agentの各Host信頼ポリシーが検証時active・非失効であること、各鍵/方針の有限`not_after`と不変`policy_version`が取得できることを必須**とし、実際に使用した許可鍵とpolicy versionを`trust_snapshot`に記録する。**検証済みRoot `cnf.jwk` とHostの`expected_agent_key`とHost challenge発行時固定`challenge_agent_key_thumbprint`の三者で暗号鍵同一性を必ず比較し、不一致なら `expected_agent_mismatch`で拒否。** Root→TerminalのPoPだけではHostが当該challengeのAgentを許可した証明にならない。root/terminal JWSどちらかだけで成功しない。
3. **Claims + schema + challenge evidence** 認証済みOpen/Closedの `vct`、**Root・Closed内部・Terminal各層の署名済み時刻/有効期限**、Open→Closed保持、Host `aud`/`nonce` を確認。**必須のHost `challenge_ref` がそのCheckoutの永続正本に紐付くことをHost入力契約として要求し、実際に一致確認したTerminal `aud`/`nonce`に基づく`verified_challenge`だけを成功時のEvidenceへ載せる**。さらに認証済み期限、Hostが指定したchallenge/TTL期限、**検証に使ったIssuer/Merchant/Agent trust policyおよび鍵の`not_after`**の**最短値を必須`valid_until`として返す**。Issuer/Merchant/Agent鍵の方針が有効か、有限期限上界やversionが不明ならEvidence禁止。公式 pinned Open/Closed/Merchant JSON Schemaの対応する**全ての必要な型・必須・形状制約**と、より狭い本OSSの形状ポリシーを別々に適用する。
4. **Completeness + constraints** 固定Issuer layoutで権限制約が完全に見えると証明し、全Constraintを意味評価。未知/非開示/型逸脱/数量・商品・Merchant不一致で拒否。
5. **Checkout + Host challenge binding** Host正本JWTのMerchant署名を検証し、Closed内の `checkout_jwt` 原文と一致、`checkout_hash` をJWT**フィールド値**のハッシュとして独立再計算（当初sha-256のみ）。**Hostが正本として提供したJWT recordのtenant/checkout ID/versionと、独立のHost challenge recordが指すtenant/checkout ID/versionが一致しなければ`checkout_context_mismatch`で拒否**（誤って異なる注文の有効JWTを渡しても通さない）。**実際に検証したHost JWT原文SHA-256＋一致したcheckout_id/version＋challenge_refを`checkout_binding`として必須出力**する。Hostがrecord↔JWTの出所対応を示せず曖昧な場合、または**Host challengeのBuyer/Account refとCheckout正本Buyer/Account refが不一致/未確定ならSTOP**。署名確認とhash比較を混同しない。
6. **全ゲート成功**でのみEvidence。これでも最終許可ではない。

| ID | 観測/入力条件 | Verifier結果案 | 根拠・境界 |
| --- | --- | --- | --- |
| D01 | 固定Issuer/2hop/完全開示、全署名・公式Schema・制約・Checkout照合成立、**Host challenge_ref/aud/nonce検証済み対応が保存可能** | `VerifiedEvidence`（**必須verified_challenge付き**）候補のみ | 必要な証拠が全部成立した場合。Phase 2-Aで実行済みではない |
| D01A | **署名VALID**でもRoot/Terminal/Merchant JWS protected headerの`alg`二重定義、Merchant payloadの`merchant.id`二重定義、SD-JWT disclosureのネストJSON重複、不正/非対応JOSE header | `Rejection(ambiguous_signed_json/unsupported_jose_header)` | N01/N02歴史的回帰を維持。署名の正当性は曖昧なJSON受理を正当化しない |
| D02 | Issuer不明、自己申告 `kid`/`x5c` だけ、Key/alg違い | `Rejection(untrusted_issuer/invalid_signature)` | Root trust |
| D03 | Agent PoP・`cnf`・Disclosure digest・`sd_hash` 不整合、3hop | `Rejection(invalid_chain_binding/unsupported_profile)` | 厳格2hop |
| D03A | **Issuer署名とRoot→Terminal PoPがVALID**だが、Root `cnf.jwk`、Host `expected_agent_key`、発行時challenge `challenge_agent_key_thumbprint`のどれかが異なる、またはHost期待鍵がない | `Rejection(expected_agent_mismatch/incomplete_context)` | **challengeで承認したAgent鍵との三者必須一致**。Issuer署名済み別Agentは承認Agentではない |
| D03B | 発行時challengeのBuyer/Account refがHost checkout正本または実行時のHost account refと異なる/不明（署名・nonceはVALID） | `Rejection(buyer_context_mismatch/incomplete_context)` または遅延後なら**Host CAS STOP** | Host Buyer/Accountの取り違えを防止。Buyerの同意・資格判定そのものはHost |
| D04 | Terminal `aud`/`nonce` 欠落・不一致、Root/Closed/Terminal/鍵Trust期限外、または有限の`valid_until`を決められない | `Rejection(invalid_audience/invalid_nonce/invalid_time/incomplete_context)` | Host-issued期待値、Replay消費は別。**署名・Host鍵方針・challenge全ての有効期限を必須化** |
| D05 | **署名VALID**でもRequirement `id:123`（S01）、Merchant `name:123`（S02）、nullや必須欠落 | `Rejection(invalid_schema_type)` | 公式SchemaのString要求。**S01限定修正は実測、S02は未実測** |
| D06 | **署名VALID**でも許可済みConstraint内に `policy_override` 等未知のネストキー（GP01） | `Rejection(unsupported_constraint_shape)` | 本OSS strict keys。GP01限定実測済み |
| D07 | 正規Schemaでも `merchant.website` 等、固定研究profileで非対応の要素 | `Rejection(unsupported_profile)` | **本OSS限定**。公式Schema不正ではない |
| D08 | Hidden Constraint、未開示権限、デコイと実権限の判定不能、固定Issuer layout未証明 | `Rejection(incomplete_disclosure/unsupported_profile)`; **PoC gate HOLD** | 可視Constraintだけで成功禁止 |
| D09 | `line_items` 条件を満たさない、Merchant不一致、未知Constraint、Quantity不正 | `Rejection(constraint_violation/unknown_constraint)` | 公式Constraint意味 + ローカル狭義shape |
| D10 | Host正本Checkout JWT不在・Merchant署名偽・raw JWT差分・hash差分 | `Rejection(invalid_checkout_signature/checkout_jwt_mismatch/checkout_hash_mismatch)` | Host正本の独立検証 |
| D10A | **署名VALID**でもHost JWT正本のtenant/checkout ID/versionとHost challenge正本のtenant/checkout ID/versionが違う、JWT record出所が曖昧、またはEvidenceのJWT digestがHost CASの最新注文正本から変わった | Verifier: `Rejection(checkout_context_mismatch/incomplete_context)`。遅延後なら**Host CAS STOP** | **注文とchallengeの独立cross-binding**。成功Evidenceにcheckout ref/version/署名済JWT digest/challenge refを必須化 |
| D11 | HostのTrust context・**issuer/merchant/agent policy_versionや有限not_after**・永続challenge_ref・resource/TTL上限欠落、内部依存障害、想定外例外 | `Rejection(incomplete_context/verification_unavailable)` | fail closed、鍵Trustの無制限fallbackなし |
| D12 | 同一の正署名presentationを二度検証（N07相当） | Verifier単体では**再びEvidenceになり得る**。Hostは再利用を**STOP** | **HOST_BOUNDARY**。Verifierにanti-replayの偽保証を作らない |
| D13 | 失効未知、Authority応答不能、nonce DB競合、注文内容の最新性不明 | **Host STOP/PENDING**（Verifier結果ではない） | HC06 FULL HOLD、Host正本34件中25件NOT RUN |

**重要:** Schema VALID だけでも安全ではない。一方、Schema INVALID なのに署名VALIDなら**必ず拒否**。 `S02`・`S03–S08`・未知Profileは、研究の未検証範囲を自動的に受理可能とは扱わない。実装で上記拒否を保証するまでは**Phase 2-B HOLD**。

## 5. Merchant Host ↔ Verifier 契約

| Verifier担当（証拠のみ） | Merchant Host担当（別の最終責務） |
| --- | --- |
| Host登録TrustでRoot/Agent/Merchant署名、Disclosureと鍵binding検証 | Trusted Issuer/Agent/Merchant鍵の登録、使用用途、rotation、失効時の入力方針 |
| 公式Schemaと厳格Profile型・完全開示・制約評価、全ての署名付きJSONの重複key・JOSE header厳格拒否 | 認証済みBuyer/Account/Tenant、Agent資格とConsentの成立確認 |
| Host提供aud/nonce/署名済みMandate各層の時刻・期限を評価し、**必須のverified_challengeと`valid_until`を返却** | Challengeの一意・不変な発行/永続管理。Evidenceの`host_challenge_ref`、`verified_audience`、`verified_nonce_sha256`、**`approved_agent_key_thumbprint`、`buyer_account_ref`**が**現行永続challenge正本/tenant/Checkout版/承認Agent鍵/Buyer account**と一致することをHostがCASと同じ安全境界で再確認する。Host current `expected_agent_key`・agent policy・checkout buyer/account refとも再照合し、発行時Agent/Buyerの差し替えならSTOPする。同時に**Hostの信頼時計でCAS現在時刻 `< valid_until`**と最新challenge期限を再判定し、**Issuer/Merchant/Agent全てのtrust_snapshot鍵参照・policy_versionをHost現在の信頼正本へ再解決してactive/非失効/期限内・版一致を確認**する（回転/失効/版変化/Authority不確実ならSTOP・再検証。古いpolicyを自動承認しない）。その上でnonceを**原子的に一度だけ消費**、Checkout状態CAS。古いEvidenceや期限切れEvidenceを使い回してはならない |
| Host正本JWTの署名/原文/hashを照合し、**Host checkout_refとHost challenge_checkout_refの一致、および必須checkout_bindingの作成** | **最新注文正本**の版・在庫・価格・支払方法・リスク・注文実行の判断。Host CASでは**Evidence.checkout_bindingのtenant/checkout ID/version/buyer_account_refを現在の注文とchallengeの両正本に照合し、Evidence中の`signed_checkout_jwt_sha256`を現在保存している署名済JWT原文から再計算したdigestと原子的に比較**する。どれか違えばnonceを消費せずSTOP。JWT差し替え/古い版/別注文を許可しない |
| `VerifiedEvidence` / `Rejection` のサニタイズ返却 | 外部失効Authorityとの別契約、UNKNOWNならSTOP、永続operation/idempotency/outbox/回復 |
| DB/ネットワーク/Payment/Receipt処理は**しない** | Provider実行判断、Receiptの正しい署名/記録/送信、障害時に成功を偽装しない |

VerifierがEvidenceを返してもHost ALLOWは**必ず独立**しており、Hostが取引上の耐久的かつ競合安全な手続きを満たさない場合は停止する。VerifierはHC06の分散強失効の代替物ではない。Hostの保留事項（**9/34ケース実測、25 NOT RUN**、C01–C12未確認）を「Gem外だから完了」と扱わない。

## 6. 設計から派生する最小受入れテスト計画（すべて今回 NOT RUN）

**テスト・Fixture・CIはこの設計PRでは追加/実行しない。** 将来の検証に必要な**オラクル**を先に合意する。S01既存 **2 runs/12 assertions**（限定Docker実測）やGP01既存CIは**別の過去証拠**であり、新規テスト成功数に加算しない。

| Case | 合成・真の再署名を要求する入力 | 期待結果 / 独立オラクル |
| --- | --- | --- |
| A01 | 固定Issuer+Agent+Merchantの3系統署名、有効な1商品Checkout、**Host承認`expected_agent_key`が検証済みRoot `cnf.jwk`と一致** | Profile限定Evidence。Issuer/Agent/Merchant署名VALID、公式Schema VALID と**Host鍵同一性**を**独立**確認 |
| A02 | 同じ正署名profileでIssuer未登録/鍵違い | REJECT untrusted。Host trust入力と署名真正性を独立記録 |
| A03 | Issuer/Agent署名はVALID、S01 `Requirement.id=123` | 公式Open Schema **INVALID**、REJECT `invalid_schema_type`。P1-10t危険受理の回帰 |
| A04 | Issuer/Agent署名はVALID、S02 `Merchant.name=123` | 公式Merchant Schema **INVALID**、REJECT。**S02は新規未実測** |
| A05 | Issuer/Agent署名VALID、未知 `policy_override` | Profile strict keysでREJECT（公式SchemaとローカルPolicyを区別） |
| A06 | Rootの有効署名は維持、隠した `allowed_merchants` / 未解決commitment | `incomplete_disclosure`、見える制約だけでEvidence禁止 |
| A07 | Merchant側で保持するJWTとClosedの値を変えた/正本署名偽/hash偽 | 各々 `checkout_jwt_mismatch` / `invalid_checkout_signature` / `checkout_hash_mismatch` |
| A08 | 有効署名のままaud/nonce、時刻、Root→Terminal `cnf` bindingを壊す | 各理由でREJECT。改変したclaimは必ず再署名し、暗号だけ壊した偽負例と分ける |
| A09 | 3hop、Direct、`website`付きMerchant、未知alg/`vct` | unsupportedとしてREJECT（AP2一般違反とは主張しない） |
| A10 | 同じVALID presentationの再提出 | Verifierのstateless評価と**Host nonce CASによるSTOP**を別のオラクルで測る。Verifierのみではreplay防御PASSにしない。Evidenceに必須challenge bindingを含める |
| A11 | Context/Issuer profile/有限resource上限欠落、未証明issuer disclosure layout | REJECT/HOLD。無制限デフォルト・成功fallback禁止 |
| A12 | **正当な固定Issuerが別Agent鍵で署名したRoot** + その別Agentが正しくTerminal署名。Root/Terminal/Merchant署名、PoP、Disclosure、Schema、aud/nonce、Checkout制約・hashがすべてVALID。ただしHostはA01の元Agent公開鍵を`expected_agent_key`として保持 | **`Rejection(expected_agent_mismatch)`**。Root→Terminal署名だけではHost Agent承認を代替しないことを独立の鍵thumbprint比較で確認。Host期待鍵欠落も`incomplete_context`で拒否 |
| A13 | Host固定キーで**正しく再署名した**Merchant JWT payloadの`merchant.id`重複、およびprotected JOSE headerの`alg`重複（別々のfixture）。Root/Terminal/Merchantいずれにも適用するparse負例を含める | **`Rejection(ambiguous_signed_json)`**。公式Schemaを見る前、**元header/payload byte列**に対する重複検出の独立オラクル。歴史的N01/N02の限定GREENは一般化しない |
| A14 | Checkout/Agent/merchantが同じで**異なる2つのHost-issued challenge_ref + nonce**を発行。各々正署名・PoP/Schema/Constraints/Checkout/hash/aud/nonceがVALIDなTerminalを別々に用意し、古いEvidenceを新challengeのHost CASへ渡す | 各Evidenceの`verified_challenge.host_challenge_ref`と`verified_nonce_sha256`が**異なる**。Hostは不一致の古いEvidenceをSTOP。nonce atomic consume保証とは別にchallengeの取り違え拒否を検証 |
| A15 | Host時刻T0ではRoot/Closed/Terminalとchallengeが期限内の正署名CheckoutをVerifierがEvidence化。**キュー遅延中に最短の有効期限が到来**し、Host CAS時刻T1で`T1 >= valid_until`（またはchallenge期限切れ、**Issuer/Merchant/Agent鍵not_after到来**）となる | Evidenceには署名・challenge・**Host信頼鍵/方針**の最短deadlineに基づく`valid_until`が含まれ、**Host CASはSTOP**。T0でEvidenceが出た事実をT1での認可へ持ち越さない。各鍵not_after境界とMandate期限の独立時計をオラクルにする |
| A16 | T0時点でHost trust policy versionsとIssuer/Merchant/Agent鍵がactiveな正署名CheckoutはEvidenceを返すが、T1のHost CAS前に同じ鍵が失効・ローテーション等でHost正本のpolicy_versionや有効状態が変わった | **Host CASはSTOP/再検証**。Evidence`trust_snapshot`の全鍵ref/versionを現行Host Trust正本に再解決し、同一versionかつactive・非失効・期限内の場合だけ後段業務判定へ進む。期限の未到達だけでは失効の保証にならない |
| A17 | **Hostで別々に正当に署名・保存されたCheckout A/BのJWTを準備**し、Host challengeはBのtenant/id/version/nonceに紐付き、VerifierへはAのcurrent signed JWT recordを渡す。AのJWS/hash/Constraintsは正しく再署名・整合 | **Verifierは`checkout_context_mismatch`でREJECT**。両JWTの署名VALIDでもHost challenge↔JWT record sourceのtenant/id/versionが違うため成功Evidenceは禁止。独立Host正本参照オラクルが必要 |
| A18 | T0で正署名JWTとHost challengeが同一Checkout ID/versionでEvidenceを生成。T1のCAS直前にHostが同一CheckoutのJWT内容/版を更新、または別recordのJWTに差し替えた | **Host CASはSTOP**。`checkout_binding`のchallenge_ref、tenant/id/version、signed JWT digestをHost現行のchallenge/Checkout両正本と**原子的に比較**し、nonce消費前に不一致を拒否。署名自体がVALIDでも古い証拠は無効 |
| A19 | **同じcheckoutにAgent A/B両方が登録**され、challengeは発行時Agent A鍵に固定。Hostの後続`expected_agent_key`がAgent Bへ変わり、IssuerはBの鍵でVALID Rootを再署名、BがClosedを署名。checkout/nonce/時刻/署名/hashは全て整合 | **`Rejection(expected_agent_mismatch)`**。challenge固定Agent Aの鍵thumbprintとHost B鍵/Root `cnf.jwk`が違うため、別Agentの有効署名では旧nonce使用不可。Host CASでもchallenge agent ref照合でSTOP |
| A20 | 発行時challengeはHost Buyer/Account A、現在のHost checkout/実行AccountはBへ変更（別々に署名VALID、同じcheckout ID/versionなどその他は整合） | **`Rejection(buyer_context_mismatch)` またはHost CAS STOP**。challengeのopaque Buyer/Account IDをEvidenceに固定し、Host保存Checkout・現行Accountに一致しなければnonce消費不可。VerifierはBuyer同意の証明を返さない |

必要な最低限の証拠: fixture生成時の**非本番の独立署名真正性**、pinned公式SchemaのVALID/INVALID、Rubyの正確なREJECT/Evidence、negativeの攻撃種別、出力が業務ALLOWでないこと、GitHub Actionsが実行された場合のみ具体的なrun URL。**観測した「危険ACCEPT」によるテストGREENを安全成功と呼ばない。** プライベート署名鍵はcommitしない。

## 7. Review gate / 次に進める条件

- [ ] Root発行profileと**Disclosure完全性を独立判定できる契約**をレビューし、デコイ・未知Issuerと混同しない。
- [ ] `TrustedInputs` の出所・必須性・欠落時拒否と、固定2hop/Direct非対応を承認。特に**challenge発行時Agent鍵＝Host期待Agent鍵＝検証済みRoot `cnf.jwk`の三者一致**、challenge/checkout/Host Buyer Account参照一致、A12/A19/A20の負例を確認。
- [ ] Evidenceにauthorization文言が入らず、失敗に成功fallbackがないこと、**検証したHost challenge_ref/aud/nonce digest/verified_at、全Issuer/Merchant/Agent信頼鍵refとpolicy_version、checkout id/version/JWT digest/challenge refの`checkout_binding`、最短deadlineの`valid_until`が必須**で、別nonce/別注文/JWT変更/鍵失効/版変更/期限切れ時はHost CASが必ずSTOPすることを確認。
- [ ] Root/Terminal/Merchant/Disclosureの全JSONに対する重複キー拒否と、JOSE `alg`/`typ`/`crit`/許可鍵ポリシーのstrict parse/拒否（N01/N02回帰）を確認。
- [ ] 公式JSON Schemaの型/必須とローカルstrictキー制限（S01/S02、GP01、optional `website`）を区別。
- [ ] Host最終ALLOW/nonce CAS/注文・失効/Receiptとの責任境界、およびHC06 HOLDを確認。
- [ ] A01–A20の各オラクル・今後の負例実行範囲、TTL/上限の未定事項を合意.
- [ ] 以上の未解決点を記録した上で、**別の明示的なPhase 2-B PoC GO/HOLD判断**を行う。**設計PRのマージだけでは実装開始しない**。

**今回の判定:** `PROPOSED / DESIGN ONLY`。新たなテストは `NOT RUN`、Ruby Gem/API/本番は `HOLD`、実決済・外部HC06の強い安全保証は `NO-GO`。
