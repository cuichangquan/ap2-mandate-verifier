# Phase 2-A — 固定IssuerにおけるSD-JWT権限制約の開示完全性 Gate

**2026-10-12 JST / Issue [#47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) / DESIGN ONLY / REVIEW CANDIDATE / NOT IMPLEMENTED / ALL NEW CASES NOT RUN**

> **判定：候補Aを安全側の暫定設計とする。ただし issuer-layout の第三者的な検証・真の合成署名fixture/相互運用実測は未完了。Phase 2-B PoC GOではない。Gem/API、実決済、本番Host、HC06はHOLD/NO-GO。** この文書のマージだけで「隠し制約が絶対にない」と証明した扱いにはしない。

## 1. 前提：何が不足しているか

[Phase 2-A最小Verifier契約](PHASE2A_MINIMAL_VERIFIER_DESIGN.md) は、署名/SD-JWT digest、2hop Agent鍵、Merchant JWT/hash、Hostが期待する注文・challengeとの結合を**別の条件**として列挙した。しかし、署名が有効なOpenから見えるconstraintだけを評価して `VerifiedEvidence` と返すと、Issuerが署名した**非開示の権限制約**を見落とす可能性がある。

[P0-5aの合成Issuer署名による観測](PYTHON_BASELINE_VERIFICATION.md)では、Openに`line_items`と`allowed_merchants`があっても、Merchant許可制約を非開示にすると、可視側での制約評価だけでは違反0になるケースがあった。**これは一般AP2の脆弱性認定でも、Verifier/Hostが購入ALLOWした証拠でもない。**

必要なのは「署名付きRootが実際にcommitした権限関連データ全体」対「完全に検査できたデータ」の関係の確認である。`constraints`を列挙した結果や`errors=[]`は完全性の証明ではない。

## 2. Pinned公式実装と研究コードで確認できる構造

基準AP2 v0.2.0 SHA **`b4587ac1d055888a73b4b21750973cffba961793`**。後日の最新版へ一般化しない。

| 出所 | 固定時点に確認できる事実 | 本OSSへの意味 |
| --- | --- | --- |
| [Open Checkout JSON Schema](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json) | `constraints`に`checkout.line_items`が少なくとも1件必要。`allowed_merchants`と`acceptable_items`はselectively-disclosableな配列要素を持つ。 | 公式Schemaの**型・`contains`**は、すべての未開示の権限制約の完全性を受信者が証明できる、という意味ではない。 |
| [sdjwt/common.py](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/common.py) | `selectively_disclosable_claims`は`delegate_payload`の要素をSD対象としてwrapする。 | Open全体のcommitmentやdisclosureも元wireから追跡する。解決済みpayloadだけを見ない。 |
| [disclosure_metadata.py](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/disclosure_metadata.py) | `from_model`はschema拡張属性により配列要素等へSDメタデータを付与する。 | `allowed`や`acceptable_items`の一部開示は意図した機構であり、単なるparse errorではない。 |
| [sdjwt/sd_jwt.py](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/sd_jwt.py) | root発行関数は`add_decoy_claims=False`を既定値に持ち、`True`も選べる。 | **default=Falseだから全Issuerがdecoyなし、とは断定できない**。署名元wireで未解決digestを調べ、曖昧なら拒否する。 |
| [sdjwt/chain.py](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/chain.py) | `verify_chain`は検証後のeffective payloadを返す。 | **通常の検証済み返却値だけを完全性オラクルに使わない**。隠されたcommitmentに対し元の保護された表現も検査する。 |
| [Ruby root research](../research/p1_1/root_sdjwt_research.rb) | 研究用resolverはobjectの`_sd`、未処理`...`、missing/unused disclosure、非対応locationをfail closedとしている。 | 限定的な先行研究の参考。正式な一般SD-JWT implementationやissuer-layout適合の証明ではない。 |
| [Fail Closed Profile §3](FAIL_CLOSED_PROFILE.md) | decoyと本物の未開示制約を区別できない場合があることを明記。 | **未解決commitmentは「無害なdecoyかも」で通さない。** |

引用した外部ファイルのSDK挙動は静的確認である。このIssueのための新しい公式Pythonテスト・Ruby署名付き試験・CIは**NOT RUN**。

## 3. 何を証明するか — 4つの独立条件

| 証明対象 | 証拠の原本 | NGの場合 |
| --- | --- | --- |
| **Authenticity**: Issuer署名、agent PoP、disclosure digest、`sd_hash` が一致 | Issuerが署名したJWT原文 + 提示されたdisclosure + Host信頼鍵 | `invalid_signature` / `invalid_chain_binding` |
| **Structure**: Issuer認可scope内の正確なOpen/`constraints`階層・数・型・未知フィールドなし | **署名元wireの構造** + Hostに固定したIssuer Profile / pinned schema | `unsupported_profile` / `invalid_schema_type` |
| **Completeness**: 権限を変更し得るすべてのsigned commitmentが解決されていて、隠れた権限candidateが残らない | **署名元wireのcommitment graph**と検証済みDisclosureの厳格な一対一の消費証拠 | `incomplete_disclosure`。decoyとの区別不能でも同じ |
| **Authorization meaning**: 全ConstraintをCheckoutに対して正しく評価した | 完全性が成立したOpen + Host正本Merchant JWT | `constraint_violation` / `unknown_constraint` |

どれか一つでも満たさない場合、`VerifiedEvidence`を生成しない。**StructureやCompletenessは署名検証の副作用として自動保証されるものではない。**

## 4. 候補A — すべての権限関連commitmentが可視と証明できる固定プロフィール

**提案するSupported subset（設計候補のみ）**: Hostが事前登録した**単一Issuer、固定発行プロファイルのバージョン、Open→Closedの2hop、単一Merchant・単一SKU・単一Checkout**。

- Issuerが署名したOpenの`delegate_payload`は**ちょうど1つのOpen**へ検証可能に解決。隠れた別Open、未知のauth-scope候補、余剰`delegate_payload`は拒否。
- 完全に開示されたOpen内部で`vct`・`cnf.jwk`・`iat`/`exp`、`constraints`の存在・型と、**固定の2種類** `checkout.line_items` / `checkout.allowed_merchants` の**各ちょうど1件**を確認する。公式JSON Schemaの最小要件ではなく、本OSSの追加strict profile。
- `allowed`配列は**Merchant1件**、`items`のRequirementは1件、`acceptable_items`は**SKU1件**。すべての要素に対応するsigned array placeholder／digestは真正なDisclosureで解決したことを元の署名対象構造から追跡する。
- Root側の承認に影響する`delegate_payload` / `constraints` / `allowed` / `items` / `acceptable_items`と上位オブジェクトの**未解決`...` / `_sd`、未知の追加属性、未対応location、曖昧なdigest、余ったDisclosure**を拒否。可視のオブジェクトを単に`Hash`へ正規化して残余commitmentを消す実装は禁止。**デコイの可能性があるものも安全な除外証明がなければ拒否**。
- 認可につながるパスの許可一覧はHostの**version付き固定Issuer Profile**として、署名済み文法・許容Disclosure位置・許可Constraint型・配列要素数・未知フィールドへの対応を明示する。提示JWT中の`iss`や`kid`だけで新しいプロフィールを発見して受け入れない。
- **同じIssuerの別レイアウト、任意Issuer、decoyを認めるレイアウト、未知オブジェクト形式のSelective Disclosureは初期候補Aでは非対応**。正当なAP2表現でも拒否する可能性がある。この限定profileの適合性/プライバシーコストを記録する。
- Openの全権限制約を確認できても、Merchant署名JWT/hash、Host期待Checkout/challenge/Agent/Buyer、nonce CAS、失効、Receiptまで成立したことにはならない。**[Phase 2-A契約](PHASE2A_MINIMAL_VERIFIER_DESIGN.md)の全ゲートは維持**する。

**成立しうる範囲の限定**: Issuer署名元wireの**許可済み文法に現れるすべての権限関連commitment**が正しく開示/評価されたことを検査する設計である。Issuerの実世界での適法な本人確認、別文書に書かれた不可視の業務権限、発行Issuer自身が正当かどうかなど、暗号外の事実は証明しない。

**残る阻害条件:** pinned公式Pythonでの発行・提示・第三者的な署名付きオラクルで、上記の許容文法/decoyなし実署名が現実に成立するか、現時点は**NOT RUN / HOLD**。純粋に設計が一貫することと、公式SDKとの相互運用は別。

## 5. 候補B — Issuer-authenticated commitment manifest

Issuerが`constraints`のID・個数・型・commitment digestやallowed許可要素を**署名で保護した正本manifest**にコミットし、検証者が提示内容をmanifestと一対一照合する方法も設計上は考えられる。しかし:

- manifest自体がIssuerにより**真正に署名・authority-bound**されていること、Hostが固定のissuer+manifest schema/versionを信頼し、内容改変・重複・省略・デコイを独立に見分けるオラクルが必要。
- manifest内に未知/隠れた権限要素を許したり、Verifierが提示Agent由来の自己申告一覧を正本扱いする場合、問題を解決しない。
- **Pinned AP2 v0.2.0が、この独自manifestプロファイルを規格機能として提供するとは確認できない。** AP2の一般MUSTとは書かない。互換性と署名形式を確定するまで**BはHOLD/UNSUPPORTED**。

### 設計比較

| 条件 | A: 権限commitment残余ゼロ | B: Issuer署名manifest |
| --- | --- | --- |
| 最初に検討する範囲 | **極小Issuer/単一商品、decoy曖昧ならREJECT** | 明示的に承認したIssuer拡張のみ |
| Completenessのオラクル | 元signed-wireの許可文法 + 各placeholderの真正開示 + 残余権限候補なし | 固定Issuerの署名manifestとcommitmentsの全量1対1照合 |
| 規格・互換性 | SD-JWTの正当な部分開示を拒否し得る**ローカルprofile** | 標準AP2に追加の発行契約が必要となり得る |
| decoy/不明layout | **失敗** | 仕組みが独立証明するまでは**失敗** |
| 現在の実測 | 新しいAの統合証明: **NOT RUN** | 新しいBの証明: **NOT RUN** |
| 次の判断 | **候補として先に検証方法を詰める** | **後回し、汎用化を急がない** |

## 6. 署名付き負例・独立オラクル計画（今回すべて NOT RUN）

| ID | 真の発行・再署名で準備するもの | オラクル / 期待 |
| --- | --- | --- |
| DC01 | 候補Aの固定2Constraint・全Disclosure・決済なしの合成正常例 | Issuer/Agent/Merchant署名・digest chain・公式Schemaを**独立に**検査。Root signed-wire commitmentから残余なし、profile一致を示した時だけEvidence**候補** |
| DC02 | Issuer署名VALID、`allowed_merchants`全体を隠す or そのconstraint placeholder disclosureを抜く | 可視`line_items`はVALIDでも `incomplete_disclosure` で拒否。可視違反数0は成功ではない |
| DC03 | Issuer署名VALID、`line_items` constraintを非開示にする or 要素を欠落 | `incomplete_disclosure`または公式Schema INVALID + REJECT。Constraint完全性とSchema型を別オラクルで確認 |
| DC04 | `allowed[0]`・`acceptable_items[0]`のdisclosureを1つ隠す。Merchant/Itemの可視集合は残るように工夫 | Hidden array elementを許容集合から黙って落とさずREJECT。権限縮小方向が一般に安全との推測で初期候補Aを緩和しない |
| DC05 | Issuer `add_decoy_claims=True`（生成APIにフラグがある）でdecoyの残余commitmentがあるpresentation | decoyと権限欠落の曖昧さを「無害」とせず `incomplete_disclosure/unsupported_profile`。実現方法・SDK挙動は独立検証が必要 |
| DC06 | 未知Constraint/権限関連ネストキー、`_sd`別path、余剰Root payload、同じdigest複数回、unused Disclosure | 全部REJECT、偽装署名失敗ではなく**真正署名の範囲内での構造拒否**を独立測定 |
| DC07 | 固定Issuerとは異なる有効署名Issuer、同Issuerの異なるprofile version、Host許可レイアウトと異なる発行 | `untrusted_issuer/unsupported_profile`。鍵署名VALIDとHost Profile承認は別 |
| DC08 | `checkout_jwt` / Agent / challenge / Host正本結合を崩した本来のPhase 2-A負例を再利用 | Disclosure完全性が成功してもHost/business/nonce/CASを満たしたことにはならないと示す |
| DC09 | 候補Bのsigned manifestを仮定した不整合（Manifest未署名／別Issuer署名／件数ずれ／未知権限） | Bは実装承認なしの**DESIGN ONLY**。独立のIssuer署名・全量照合が証明できなければHOLD |

**オラクル分離の必須条件:** Issuer/Agent/Merchant署名の真正性、pinned公式Schema VALID/INVALID、署名元wireのcommitmentレイアウト、Host許可Issuer Profileの正本、VerifierのREJECT/Evidence、Host業務ALLOWを**混同しない**。真の合成署名と別の解析実装・CIの実行証拠は**後続の別承認**。秘密署名鍵はcommit禁止。

## 7. Phase 2-Bの前に解決する設計質問

- [ ] Root `delegate_payload` / Open `constraints` / allowed/acceptable配列の**元wire commitment graph**が候補Aの許可文法と一致するか、Issuer profileのsigned layoutとして判定可能か
- [ ] 全Digest・Disclosureを正しく検査し、**未解決の権限commitmentやdecoyの曖昧さで必ずREJECT**できるか
- [ ] `_sd` / `...` の位置・未知権限の型・入れ子・root全体の不可視要素を見落とさない独立オラクルが定義できるか
- [ ] 元の署名済みバイト列の二重キー/曖昧なJOSE表現を拒否する厳格parserが必要という[Phase 2-A契約](PHASE2A_MINIMAL_VERIFIER_DESIGN.md)を保てるか
- [ ] 公式AP2 v0.2固定SDKで**許容normal fixture生成が可能か**を後続の署名付き試験で確認できるか（現在NOT RUN）
- [ ] Bを拡張するならAP2規範外のissuer manifest、プライバシー、鍵ローテーションとVersioningの仕様を独立に承認したか
- [ ] Host nonce/Buyer/Agent/Checkout binding、失効/Receipt/HC06のHOLDを誤って「Verifierが解消」としていないか

**結論：設計候補Aを優先、BはHOLD。Aも独立署名オラクル未成立のため、Phase 2-Bの実装・一般Gem・本番利用に対するGOではない。** このGateをPassとするには後続の別判断が必要。
