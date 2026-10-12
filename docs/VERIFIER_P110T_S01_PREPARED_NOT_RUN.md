# P1-10t — S01 正署名・公式Schema型不一致のDockerローカル実測：ACCEPT / RED-HOLD

**2026-10-12 JST / FIXED SYNTHETIC ISSUER / LOCAL DOCKER OBSERVED / SECURITY RED-HOLD / CI NOT RUN**

**対象：** [P1-10sで見つけたS01](VERIFIER_P110S_CONSTRAINT_SHAPE_TYPE_GAPS.md)。固定AP2 v0.2.0公式SHA `b4587ac1d055888a73b4b21750973cffba961793`、[公式Open Schema](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json)。Open Checkoutの`checkout.line_items.items[0].id`（Constraint requirement `id`）を**文字列`"req-1"`から数値`123`**にした**合成Issuer署名済みMandate 1件**。公式JSON Schemaでは文字列型必須。この型の未検査は[既存Ruby研究Verifier](../research/p1_3/checkout_binding_research.rb)に限定される。

## 1. ユーザー提供Docker実測（GitHub Actionsではない）

ユーザーがMac（Apple Silicon）から実行したDocker `ruby:3.4-bookworm` コンテナの**実際のターミナルログを受領**した。ChatGPT自身がDocker内部を操作・再実行したログではない。PR #41ブランチ `82e278815537d41252a4e8ac25ee1cb50d0f3ba2` の検証プログラム、公式AP2 `b4587ac1d055888a73b4b21750973cffba961793` に固定して実行した。環境：Ruby **3.4.11**（aarch64-linux）、jwt **3.3.0**、Python **3.11.2**、jsonschema **4.25.1**、jwcrypto **1.5.6**。コードは研究用であり、Gem/API・本番システムではない。

| 判定レイヤー | ローカル実測 | 証拠の意味 |
| --- | --- | --- |
| Issuer署名・SD-JWT Disclosure digest・Agent PoP/チェーン・Merchant Checkout JWS | **VALID** | Python検証生成器が`S01 SIGNATURE VALID: issuer disclosure/commitment, agent PoP and merchant JWS`と出力 |
| 固定公式AP2 Open Checkout JSON Schema Draft 2020-12 | **INVALID** | `S01 SCHEMA INVALID: pinned anyOf/contains errors; nested id type:string violation (integer 123)`と出力。トップレベル`anyOf`/`contains`内のネストした`type:string`違反を検出 |
| Ruby側Issuer Root検証 | **true** | Rubyレポートの`ruby_signed_root_verified: true` |
| 既存の未修正`AP2CheckoutBindingResearch.verify!` | **ACCEPT** | `S01 OBSERVED: ACCEPT — RED/HOLD (signed input, official JSON Schema INVALID)` |
| 専用Ruby Minitest 1件 | **1 run / 7 assertions / failures 0 / errors 0 / skips 0** | **危険なACCEPTの観測に成功**という意味。セキュリティPASSではない |
| Ruby `observed.security` | **RED_HOLD** | ローカル研究コードは型違反の署名済みConstraintを受理 |
| GitHub Actions | **新規0件 / NOT RUN** | CI未実施。ローカル観測と混同しない |

**検証結論：この限定研究用Verifierに対し、正しく署名・開示されたものの公式Schemaに違反する`Requirement.id: 123`を受理する具体的な再現例が成立。P1-10t SECURITY RED/HOLD。** 有効署名はSchema適合を保証しない。合成入力の実測であって、実際の決済悪用・一般的AP2プロファイル・外部Issuerが同じ条件で受理されるとの実証ではない。

## 2. 実行ログの必要部分（秘密鍵・JWT・fixtureは転載しない）

公式コードの取得は次を`git rev-parse HEAD`で確認：
- PR #41 head（ローカル実行時点）：`82e278815537d41252a4e8ac25ee1cb50d0f3ba2`
- 公式 AP2：`b4587ac1d055888a73b4b21750973cffba961793`

ユーザー実行コマンド：

```bash
export AP2_P110T_UPSTREAM_ROOT=/work/AP2
python /work/verifier/research/p1_10t/generate_s01.py /work/s01.json

export AP2_P110T_FIXTURE=/work/s01.json
export AP2_P110T_REPORT=/work/s01-report.json
ruby /work/verifier/research/p1_10t/observe_s01.rb --verbose
```

生成スクリプト実際の出力（抜粋）：

```text
S01 SIGNATURE VALID: issuer disclosure/commitment, agent PoP and merchant JWS
S01 SCHEMA INVALID: pinned anyOf/contains errors; nested id type:string violation (integer 123)
S01: synthetic ephemeral signing keys never written/uploaded
```

Ruby実際の出力（抜粋）：

```text
S01 OBSERVED: ACCEPT — RED/HOLD (signed input, official JSON Schema INVALID)
Finished in 0.006583s, 151.9045 runs/s, 1063.3316 assertions/s.
1 runs, 7 assertions, 0 failures, 0 errors, 0 skips
Ruby署名検証: True
Ruby判定: ACCEPT
Security: RED_HOLD
```

この`1 runs ... 0 failures`は意図した**観測テストの成功**であって**拒否テスト合格ではない**。ユーザーが実行した生のログに対する記録であり、署名済みfixture JSONや秘密鍵はPRに含めていない。生成器はRAMで一時署名鍵を生成し、JSONには合成署名済みトークンと公開JWKのみを出力する。

## 3. 観測前の1件の検証器スクリプト不具合と修正

ローカル初回の`generate_s01.py`は**`jwcrypto.JWK.from_json(public_jwk)`にPython dictを渡し、`InvalidJWKValue`で停止**。Issuerの改変RootおよびSchema検証は通過していたが、その時点ではMerchant署名・2hopチェーンの完成を主張できなかった。

P1-10t観測**生成器だけ**を次のように1行修正して再実行：
`JWK.from_json(json.dumps(public_jwk))`（PR head `82e2788`）。再実行後に上記の**署名VALID＋Schema INVALID＋Ruby ACCEPT**まで確認。**既存Ruby Verifier実装への修正は0件**。また`anyOf`/`contains`の合成Schemaエラーを1件と取り違えないための観測生成器修正も含む。

## 4. 次の判断と境界

**P1-10t観測はローカル実測でRED/HOLD。** 原因に対するVerifierの修正・正常署名回帰・別署名負例は**本PRの承認範囲外**。GP01とは別の**S01型検証の反例**として記録し、S02その他の未検証リスクにGOは出さない。

- [P1-10q修正前GP01 RED](VERIFIER_P110Q_GP01_EVIDENCE.md)は歴史的事実として維持。[P1-10rのGP01限定対策と正常signed正例](VERIFIER_P110R_GP01_FIX_EVIDENCE.md)：**2 runs / 10 assertions、0 failures**（別CI）。
- P1-10o：**8 runs / 45 assertions**（別CI、AN-N07は**HOST_BOUNDARY**でありリプレイ防止PASSでない）。
- Host正本 **9/34実測・25 NOT RUN**、外部Authority→Host契約C01〜C12 OPEN/UNCONFIRMED、強い失効HC06 **HOLD**。
- 汎用Gem/Public API/本番利用 **HOLD**、RubyGems公開・実決済・署名Receipt **NO-GO**。
- GitHub Actionsの新規workflow追加は前にプラットフォーム安全性チェックでブロックされており**迂回せず**。**CIは未実行**。PRをどの条件でReady/mergeするかはレビューと証拠の追加判断で決める。
- **次のおすすめ1件（別途ユーザー承認後のみ）：P1-10u**、固定Issuer研究用Verifierで`line_item_requirements.id`の型をFail Closedにする小さな修正を設計し、同じ正署名S01の**REJECT**と別の正署名正常Checkoutの非退行を検証する。S02/汎用Issuer/Gem/本番まで自動拡張しない。
