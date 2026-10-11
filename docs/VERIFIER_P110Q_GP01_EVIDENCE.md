# P1-10q — GP01: 正署名の未知ネストConstraintの想定外受理（RED/HOLD）

**2026-10-12 JST / ONE SYNTHETIC NEGATIVE OBSERVED / SECURITY RESULT RED/HOLD / NO REMEDIATION IMPLEMENTED**

[P1-10p残余リスク](VERIFIER_P110P_RESIDUAL_GAPS.md)のGP01を、**Issuer/Agent/Merchantの署名・Disclosure digestがすべて有効な**合成負例1件で調査。固定公式AP2 v0.2.0 commit `b4587ac1d055888a73b4b21750973cffba961793`。既存`research/p1_1`／`p1_2`／`p1_3`／`shared`の研究Verifierは変更していない。**このStepでは修正していない。**

## 1. 観測結果と再現性の証拠

| 項目 | 実測 |
| --- | --- |
| **Actions** | [#38183751071](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38183751071)、head `c0d794142efcde7822a6ff8558f8bdab7dabe5a5`。Workflow `SUCCESS`は**1件を正しく観測し証拠を保存できた**ことだけを意味する。**安全性PASSではない** |
| **Ruby** | **1 run / 8 assertions / 0 failures / 0 errors / 0 skips**。出力：`GP01 OBSERVED: ACCEPT — RED/HOLD (unsupported nested authorization field ignored)` |
| **真正性確認** | 固定公式Python SDKでIssuer JWS、更新後の2つのDisclosure SHA-256 digestとSigned Root、Agent PoPとClosed `sd_hash` / challenge、Merchant ES256 Checkout JWTを検証。Ruby側でも信頼済Issuer JWKで署名とResolved Root disclosureを再検証し、未知属性が存在することをassertしてから、変更前の`AP2CheckoutBindingResearch.verify!`に渡した |
| **追加した未知属性** | 既知`checkout.allowed_merchants` Constraint内部の`"policy_override": "synthetic-unrecognized-authorization-constraint"`。Constraintの2つのtype、Merchant ID、商品、数量、期限、aud/nonce、Checkout正本は既存の正常fixtureと同様 |
| **既存Rubyの挙動** | **ACCEPT**、Checkout IDなどのverified evidence Hashを返した。`root_sdjwt_research.rb`はConstraint種別を照合、`checkout_binding_research.rb`は既知のMerchant/商品/数量を確認するが、ネストしたConstraintの**全キー集合**は確認していない |
| **安全性判断** | **UNEXPECTED_ACCEPT / RED_HOLD**。`ACCEPT`であってもテストハーネスは観測成功として完走し、CIに`warning`と証拠JSONへ`RED_HOLD`を明示する。Workflowの緑色はセキュリティGREENを意味しない |
| **証拠Artifact** | [#11718614484](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38183751071/artifacts/11718614484)、7日保管、`gp01-report.json`／`gp01-observation.log`／`p110q-packages.txt`。秘密署名鍵、生成した署名fixture全体はアップロードしない |
| **環境** | ubuntu-24.04、Ruby 3.3＋`jwt` 3.3.0、Python 3.11。公式SDKの直接依存は公開PyPIから導入（Private Registry付き`uv.lock` transitive完全再現ではない） |

**重要:** Issuer署名が破損したために検証が失敗したわけではない。署名・開示が真正であることを独立検査し、Rubyが**その未知属性を無視して受理する**挙動を観測した。ただし「攻撃者がIssuerの秘密鍵を取得できる」「商用決済で権限昇格できる」といった現実的攻撃条件や実害を実証したものではない。

## 2. 公式AP2との区別とリスクの意味

- 固定[公式Open Checkout JSON Schema](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json)には、当該Constraint内部の`additionalProperties: false`がない。**未知のプロパティだけで公式Schema違反やAP2本体の脆弱性と断定しない**。
- [公式のMandate verification規則](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L454-L467)は**未知Constraint**の評価失敗を規定するが、**既知Constraint内部の未知フィールド**とは同一の意味ではない。今回の`policy_override`は実在AP2の正式属性ではなく**研究用の架空属性**。
- [P0-5b Fail Closed設計](FAIL_CLOSED_PROFILE.md)と[P1-10p GP01](VERIFIER_P110P_RESIDUAL_GAPS.md)で掲げた**固定Issuer研究プロファイルの未知権限関連属性への安全側対応**は、現状のRuby研究Verifierでは達成されていないと判断する。**公的な脆弱性/CVEやAP2プロトコル全体の失敗を意味しない**。

## 3. 過去の成果とHOLDの境界（混算禁止）

- **本Step：GP01 1 run / 8 assertions、1件の想定外受理でRED/HOLD。** 「GP01 1件安全PASS」ではない。
- 以前の[P1-10o最終8-case CI #38155050010](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38155050010) **8 runs / 45 assertions、0 failures/errors**は**別実験**であり、うちAN-N07の同一有効署名2回verifyは**HOST_BOUNDARY**。**今回を足して9ケース全部安全PASSとしない**。
- Host canonical **9/34実測、25 NOT RUN（以前の12 runs/465 assertions）**。N17のHost nonce原子的消費/replay防止は未解決。
- Host/外部Authorityの強い失効**HC06 HOLD**。P1-10i H01の旧Authorityでは`R_effective`後もHost COMMITの**危険反例**があり、C01〜C12外部契約は全件OPEN/UNCONFIRMED、H07〜H12 NOT RUN。
- 未開示Constraintの一般完全性、Issuer実信頼、Direct/中間hop、公式Python SDK intermediate hop**186 PASS / 2 FAIL**未解決。**汎用Gem/public API・本番Host統合HOLD、RubyGems公開・Production・実決済/署名Receipt NO-GO**。

**変更したもの：** 新規`research/p1_10q/generate_gp01.py`、`observe_gp01.rb`、専用GitHub Actions workflow、および研究証拠文書。**既存Verifier・他OSS・Gem/public API・GCP・実Issuer/Host/Authority・決済・Receiptは変更なし。** 今回の実験は既存の研究コードを自動的に修正しない設計。修正後の新しいPASSを装わない。

## 4. 次の1件（ユーザーの別途明示承認後のみ）

**P1-10r — GP01に限定した研究用Fail Closed対策と回帰検証。** まず固定Issuerプロファイルで`checkout.allowed_merchants`の許容内部キー・ネスト型、同種の`line_items`や商品/数量まで**意味に関わる未知属性をどう拒否するか**を定義。今回`ACCEPT`した正署名GP01 fixtureを**修正前RED→修正後REJECT**とする専用回帰を実行し、既知正常fixtureを壊さないことを確認する。新しい汎用Gem/APIや本番決済は対象外。

**P1-10qではP1-10rの対策実装をしていない。現在のGP01判定はRED/HOLDのまま。**
