# P1-5 Security Negative Research — Signed Input Observations

**検証日:** 2026-10-11 JST  
**状態:** **P1-5の初回オフライン負例観測完了：18 cases = GREEN 11 / RED 6 / HOST_BOUNDARY 1 / ERROR 0**。6件のREDは、**現行研究用検証器が本プロジェクトの厳格な受理方針では拒否すべき署名済み入力を受理した**結果。**修正コード未実装、汎用Gem/APIの実装はHOLD、RubyGems公開・本番/実決済はNO-GO。**  
**一次証拠:** [GitHub Actions #38127279271](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38127279271) / [観測Artifact（7日間の保持）](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38127279271/artifacts/11697393751) / [Ruby観測器](../research/p1_5/observe_security_negatives.rb) / [Python署名付きfixture生成器](../research/p1_5/generate_signed_negatives.py) / [CI](../.github/workflows/p1-5-security-negative.yml)。

## 1. 何を実行したか

P1-4の[SECURITY_GAP_REVIEW](SECURITY_GAP_REVIEW.md) S01〜S12を受け、**既存の`research/p1_1`〜`p1_3`のRuby verifier実装ファイルには手を触れず**、新しい観測コード/fixtureだけを作成した。

- AP2固定ソース：公式 `v0.2.0` commit `b4587ac1d055888a73b4b21750973cffba961793`。Python 3.11＋公開PyPIから上流の直接依存version pinsを取得（**公式`uv.lock`のprivate indexまでの完全再現ではない**）。
- 署名者：実行時に生成した**架空Issuer・単一Agent・MerchantのP-256秘密鍵**を利用し、固定版AP2 Python SDKで実際にOpen/Closedを署名。Checkout JWTも `jwcrypto`で実際にMerchant ES256署名。秘密鍵をGitに登録・Artifactに保存しない。
- Ruby：GitHub-hosted Ubuntu 24.04、Ruby 3.3系、`jwt 3.3.0`、既存研究用の`AP2CheckoutBindingResearch.verify!`とRoot/2-hop検証器。
- 実行：既存P1-1（**10 runs / 22 assertions**）、P1-2（**15 / 32**）、P1-3（**18 / 40**）はいずれも**0 failures / 0 errors**。**P1-5は独立の18観測**で、以前の43回帰テストと合算して「61個すべてPASS」とは言わない。
- 独立の研究用プロファイル：単一Merchant/単一Line、exact Issuer・Agent・Merchant公開鍵、Root Open→Terminal Closedの2段、Host期待aud/nonce、必須開示の完全性。**AP2 v0.2全体の一般的な受理ポリシーではない**。

### 観測ラベルの厳密な意味

| ラベル | 意味 |
| --- | --- |
| **GREEN** | 正常系がACCEPTED、または厳格プロフィールが拒否すべき入力が`AP2RootSDJWTResearch::Rejected`でREJECTED |
| **RED** | **期待REJECTEDなのに、検証器が例外なくACCEPTED**。署名検証器の入力処理・ポリシーに実測済みのギャップ |
| **ERROR** | 想定外のRuby例外などで検証が正常に終了しない。今回0。ERRORでもHostは取引停止を要する |
| **HOST_BOUNDARY** | Stateless研究コードに依存するreplay防止/nonce原子的消費が**実装されていないことを観測**。これは「Gem単独がreplayを防ぐ」という主張への反証で、直接の取引攻撃成功ではない |

**CI表示に注意：** P1-5 Ruby observerはRED/ERRORが1件でもあれば**exit 1**し、GitHub Actionsの当該stepに失敗が表示される。ワークフローは実測結果を保存するためそのstepに`continue-on-error: true`を使用し、次のstepでRED一覧を**BLOCKERと明示**してArtifactをアップロードする。したがって**ワークフロー全体のsuccessは「セキュリティ負例が全部GREEN」の意味ではない**。マージ後は手動起動専用。

## 2. 18観測の実測一覧（初回run、結果は再現可能な合成fixture）

| Case | セキュリティ境界 | Host側/Strict Profileの期待 | 観測 | 判定 |
| --- | --- | --- | --- | --- |
| N00 | 正常なIssuer→Agent→Merchant署名と取引制約 | 正例受理 | ACCEPTED | **GREEN** |
| N01 | **ES256 Merchant署名済Checkout JSONに`merchant.id`が2回**（先に不許可、後に許可） | 重複キー拒否 | **ACCEPTED** | **RED** |
| N02 | **署名済Merchant JWTのprotected JOSE headerに`alg`が重複**（`none`、`ES256`） | 曖昧header拒否 | **ACCEPTED** | **RED** |
| N03 | 正規Agent署名だが**Closed Mandate内部`exp`が過去** | 期限切れを拒否 | **ACCEPTED** | **RED** |
| N04 | Terminal JWTの`iat`は現在だが**Closed Mandate内部`iat`が未来** | 将来のClosedを拒否 | **ACCEPTED** | **RED** |
| N05 | 有効Merchant署名だがCheckout JWTの`typ=unexpected+jwt` | 初期Strict Profile外を拒否 | **ACCEPTED** | **RED** |
| N06 | Merchant JWT headerのリモート鍵選択ヒント`jku` | 信頼外header拒否 | REJECTED | **GREEN** |
| N07 | 有効なMerchant署名Checkoutに**未知の権限を示唆するフィールド**を追加 | 本PoCの厳格な1商品/既知フィールドprofile外を拒否 | **ACCEPTED** | **RED** |
| N08 | 署名済Merchant Checkout JWTが指定16KiB上限超過 | 過大入力拒否 | REJECTED | **GREEN** |
| N09 | 正しいIssuer署名だがHostが**別Issuer公開鍵**を提供 | Issuer不信を拒否 | REJECTED | **GREEN** |
| N10 | Hostの信頼Merchant公開鍵が欠落 | Merchant trust欠落拒否 | REJECTED | **GREEN** |
| N11 | Rootの署名済**必須Merchant制約の開示欠落** | 必須開示不足拒否 | REJECTED | **GREEN** |
| N12 | Issuerが**第3の権限制約も署名・全部開示** | 初期2制約profile外を拒否 | REJECTED | **GREEN** |
| N13 | Issuerが第3の制約も署名、**その開示だけ抜いた** | 未開示の追加authorityを拒否 | REJECTED | **GREEN** |
| N14 | 署名済Rootが期限切れ | Root期限拒否 | REJECTED | **GREEN** |
| N15 | Root wireが32KiB上限超過の形式 | 上限超過拒否 | REJECTED | **GREEN** |
| N16 | Host期待nonceがPresented Terminalと異なる | challenge不一致拒否 | REJECTED | **GREEN** |
| N17 | 同一の有効署名チェーンと期待nonceを**2回独立にverify** | Statelessでは再度受理、Hostは別途原子的消費が必要 | ACCEPTED×2 | **HOST_BOUNDARY** |

合計 **18ケース**。**GREEN 11（正例1＋拒否10）/ RED 6 / HOST_BOUNDARY 1 / ERROR 0**。

### RED 6件の意味を一般化しない

- **N01/N02:** 署名が正しいトークンであっても、JSONの**重複キーが存在すると解釈が曖昧**。現在のRuby検証器はこの形式をRejectしなかった。別コンポーネントが先勝ちパーサで解釈した場合の実被害は今回未実証。攻撃者が**信頼Merchant/Issuerの秘密鍵を持たずに**不正なCheckoutを新規署名できたとの主張ではない。
- **N03/N04:** **Root期限・Terminal outer `iat` の一部チェックでは、Closed内部`exp`/`iat`の保証にならない**。今回のSigned Closedの例では期待に反して受理した。規格上の全フローで一律同じtime policyがMUSTだとは主張せず、今回のHost Strict ProfileでのRelease Blockerとする。
- **N05:** Signed JWTの`typ`はMerchant JWTについて初期Profileが検査していなかった。一般AP2のすべてのCheckout JWTで`typ=JWT`がMUSTという主張ではない。**Strict Profileサポート範囲を固定するまでHOLD**。
- **N07:** 署名済Checkoutの**未知追加fieldの許容/拒否は本OSS固有の保守的方針**。AP2全体やUCPがあらゆる追加fieldを禁止しているという意味ではない。権限や金額への影響を検証できない未知fieldを、狭いPoCで明示的にrejectする必要がある。
- **N17:** 有効な署名とnonce値の一致だけを繰り返しても同じ結果になることはstateless verifierでは正常。**nonceの一度限り消費、replay/多重注文防止はHostで別の原子的処理が必須**。今回Host実装を作らない。

**安全性判断：** この研究結果は、**Rubyの限定PoCに実測できた拒否不足がある**ことを示すが、**実商用サービスの脆弱性/CVE・AP2標準の仕様違反・実決済の突破**を示すものではない。

## 3. P1-4ゲートへの影響

| Gate | P1-5で得た証拠 | 判定 |
| --- | --- | --- |
| **G1 Parsing/JOSE** | N01/N02重複キー**RED**、N05`typ` **RED**、N06`jku` GREEN。未検証: ほかのJOSE header/深い重複JSON | **未達** |
| **G2 Disclosure/Authority** | N11〜N13は**GREEN**。Issuer layout/decoy/unknown claimの一般的完全性は依然未実証 | **限定profileのみ部分確認** |
| **G3 Time/Trust Context** | Closed内部exp/iat **N03/N04 RED**。Root期限・wrong issuer・wrong nonceはGREEN。Issuer ID/鍵ローテーション未設計 | **未達** |
| **G4 Resource/Fault** | 16KiB Merchant JWTと32KiB Root超過は拒否。Deep nesting/無効Unicode/無制限再帰・例外到達は未検証 | **部分確認** |
| **G5 Evidence/Host** | N17の2回検証は両方ACCEPTED。Hostのatomic nonce consumeは未実装、VerifiedEvidenceが本番ALLOWでないという契約は未固定 | **未達** |
| **G6 Public/Production** | 失効、Receipt/署名、実Checkout/Buyer状態、セキュリティ保証/相互運用は未検証 | **NO-GO** |

## 4. 次の1件：P1-6 — RED負例の最小研究修正（別途承認必須）

**推奨する最小修正順序（P1-5自身では実装しない）:**

1. **B0 / JSON-JOSE：** 複数キーがあるheader/Checkoutを確実に拒否するstrict parser（署名検証・元JWTバイト保持は継続）、`typ`のサポート範囲を固定。N01/N02/N05をGREEN化。**署名未検証のデコード結果は採用しない**。
2. **B1 / 時間：** Root、Terminal外側、Closed Mandate内側の`iat`/`exp`をHostが供給する時計・許容ずれ・短いTTLでチェックし、N03/N04をGREEN化。
3. **B1 / Checkout:** 既知field/profile以外のCheckoutを拒否するか、受理してよいfieldを仕様根拠・Hostポリシーでallowlist化。N07をGREEN化（意味論を検証できないfieldはunknownとして拒否）。
4. **回帰:** 既存P1-1〜P1-3の43件と今回P1-5全18件を署名済fixtureで再実行。**期待REDを正しい拒否へ変えるまでは汎用GemのGOを出さない**。
5. **後続Gap:** Host key-ID identity association、深いJSON/fault、Issuer profileの一般化、replay/nonce atomic consume、revocation、Receiptは**別スコープ**。P1-6が完了しても自動でGem公開GOにはならない。

## 5. 再現方法と情報の保護

研究ソース[Python生成器](../research/p1_5/generate_signed_negatives.py)と[Ruby観測器](../research/p1_5/observe_security_negatives.rb)を利用。最小のGitHub Actions手順は[workflow](../.github/workflows/p1-5-security-negative.yml)に保存。P1-3〜P1-1の回帰も同一CIで実施。通常は**手動起動専用**で、不要な繰り返しrunner/依存ダウンロードをしない。

CIで検証時に生成した証明書/秘密鍵は出力せず、公開JWKと署名トークンを研究用fixtureに保存。結果はJSON + ログを7日間Artifact保持する（短期間でリンクは失効し得る）。**利用者の決済情報や生きたMerchant APIを使用しない**。

**P1-5終了時のGO/HOLD:** **研究負例の実測のみ完了、汎用Ruby Gem/API実装はHOLD、RubyGems公開・本番・実決済NO-GO。** 本書のREDを隠したり、CIワークフローの全体successを「セキュリティ検証PASS」と解釈してはならない。
