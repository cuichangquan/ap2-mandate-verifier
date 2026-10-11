# Ruby Feasibility Spike — P1-0 (ES256/JWK, Checkout Hash, JSON Schema)

**検証日:** 2026-10-11 JST  
**状態:** **P1-0 PASS（オフライン互換性の限定実証）**。Ruby Gem、AP2 Mandate Verifier、public APIは**未実装**。本番利用・決済・全AP2適合性を保証しない。  
**固定仕様:** [AP2 v0.2.0 @ `b4587ac1d055888a73b4b21750973cffba961793`](https://github.com/google-agentic-commerce/AP2/tree/b4587ac1d055888a73b4b21750973cffba961793)。上流の[Open Checkout公式JSON Schema](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json) を使用。  
**一次記録:** [GitHub Actions #38123249933](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38123249933)、[研究テスト](../research/p1_0/test_ruby_feasibility.rb)、[合成Python fixture](../research/p1_0/python_es256_checkout_fixtures.json)。実行ログArtifactはGitHubの保持期限（7日）の対象。

## 1. 今回何を確かめたか

P0-5bの[狭いFail Closed Profile](FAIL_CLOSED_PROFILE.md)を実装する前に、Rubyの既存ライブラリで以下の部品が利用できるかだけを確認した。

- **署名**：Python `cryptography`のP-256/ES256で生成したcompact JWTを、Ruby `jwt`のJWKで署名検証できるか。異なる鍵・payload改ざん・署名改ざん・`alg=none`・信頼鍵欠落を拒否できるか。
- **Checkout Hash**：Pythonで計算した **SHA-256(compact Checkout JWTの原文バイト列)** のbase64url（paddingなし）とRuby `Digest::SHA256`が一致するか。別Checkoutでhashが変わるか。
- **Schema**：固定AP2 Open Checkout JSON Schemaの `contains`、`required`、`const`、数量の`exclusiveMinimum`をRuby `json_schemer`で評価できるか。

**重要な区別:** 署名・JWTとSchemaの検証はAP2 Mandateの一部だけ。今回のsynthetic JWTは**AP2公式テストベクトルではない**。AP2のSD-JWT発行/開示/Delegation chain、Agent PoP、Trust policy、Merchant認可、Receiptを実装・検証したわけではない。

## 2. 実際のテスト環境と証拠

| 項目 | 実測 / 取得方法 |
| --- | --- |
| CI | GitHub Actions [run #38123249933](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38123249933) — Ubuntu 24.04、**Ruby 3.3.12** |
| Ruby dependency | **`jwt 3.3.0`、`json_schemer 2.5.0`** を公開RubyGemsからversion指定でインストール。将来のGem依存採用を確定したものではない |
| Fixtureの出所 | **Python 3.13.5 / cryptography 46.0.4** で生成した研究用P-256 JWS。公開JWK、署名JWT、hash、無効な改ざんベクトルのみ保存。**秘密鍵はCommitに含めない**。 |
| 公式AP2 Schema | GitHub Actionsが固定SHA `b4587ac1d055888a73b4b21750973cffba961793` をcheckoutし、`open_checkout_mandate.json`を読込 |
| SchemaのGit Blob SHA | `e3d9cafa7311d90612c7f908ae9b8821ddc8735a` に一致（検証用テストでassert） |
| CIテスト | **14 runs / 17 assertions / 0 failures / 0 errors / 0 skips** |
| ローカル予備確認 | Ruby **3.3.8**標準`OpenSSL`が、同じPython生成ES256署名を検証し、同じCheckout Hashを算出できた（RubyGemsが未導入の環境での独立確認）。 |
| コスト | GitHub-hosted runnerを利用。**GCP、実決済、外部Issuer / Checkout APIは呼ばない**。ソース取得とgem導入のネットワーク通信は発生。 |

### テストケース（いずれもCIでPASS）

| ID | 対象 | 判定 |
| --- | --- | --- |
| 01 | AP2 Protocol固定Commitをfixtureで照合 + 公式JSON Schema Blob SHA | 一致 |
| 02 | Python署名のES256 compact JWTをRuby JWKで検証 | **受理** |
| 03 | 署名を変えずにpayloadだけ改ざん | **拒否** |
| 04 | 署名バイトを改ざん | **拒否** |
| 05 | 有効JWTに別Issuer/不一致のP-256公開鍵 | **拒否** |
| 06 | Hostの信頼済み公開鍵が欠落 | **拒否**（研究用Host guard） |
| 07 | JWT Headerを`alg=none`へ改ざん、許可algはES256のみ | **拒否** |
| 08 | PythonのCheckout HashとRubyで独立計算したSHA-256 base64url | **一致** |
| 09 | 別Checkout（改ざんpayload）のJWT原文Hash | 元hashと**不一致** |
| 10 | `checkout.line_items`を持つOpen Checkout | Schemaで**受理** |
| 11 | `constraints=[]` のOpen Checkout | **拒否**（`contains`） |
| 12 | 必須商品Quantityが0 | **拒否**（数量条件） |
| 13 | `vct`末尾 `.1` がないOpen Checkout | **拒否**（`const`） |
| 14 | Open Checkoutの`cnf`なし | **拒否**（`required`） |

**位置づけ:** 不正ベクトルが拒否されたことで分かったのは、**この固定fixtureについて既存Rubyライブラリを使った最低限の部品互換性がある**こと。JWTに実際のMerchant Checkoutに必要な業務情報・許可条件が揃っているとは意味しない。また、IssuerはHostが登録した鍵に限り、`JWK`という文字列が提示されたから自動信頼する実装ではない。

## 3. 再現手順

このリポジトリの研究コードだけで、Gem/アプリを作成せずCIと同等の確認が可能。Ruby 3.3系が必要。**GitHubとRubyGemsへの初回取得通信は発生**し、実テスト中は外部APIへ通信しない。

```bash
# リポジトリの作業ディレクトリから（研究用）
gem install jwt -v 3.3.0 --no-document
gem install json_schemer -v 2.5.0 --no-document

git clone https://github.com/google-agentic-commerce/AP2.git /tmp/ap2-p1-0
git -C /tmp/ap2-p1-0 checkout --detach b4587ac1d055888a73b4b21750973cffba961793
test "$(git -C /tmp/ap2-p1-0 rev-parse HEAD)" = "b4587ac1d055888a73b4b21750973cffba961793"

AP2_OPEN_CHECKOUT_SCHEMA=/tmp/ap2-p1-0/code/sdk/schemas/ap2/open_checkout_mandate.json \
  ruby research/p1_0/test_ruby_feasibility.rb --verbose
```

CI実行の正本: [`.github/workflows/p1-0-ruby-spike.yml`](../.github/workflows/p1-0-ruby-spike.yml)。初回結果取得のためPRでテストを実行し、検証後は**手動起動専用**とする（普段のpushでGemや外部SDKを再インストールしない）。

**留保:** Rubyの直接Gemはversion指定だが、推移的依存の完全lock/Hashを管理した検証ではない。Test vectorも合成1鍵・小数ケースであり、複数曲線/負荷/証明書chain/悪意あるJSON全文法までは測定していない。

## 4. 何をまだ実証していないか

| 項目 | ステータス・制限 |
| --- | --- |
| AP2 Root SD-JWT VC署名 | **未実装**。JWT署名の成功だけでRoot SD-JWTのSD-claim digestを認めない |
| Disclosure内容と完全性 | **未実装**。特に未開示の権限制約は[P0-5a](PYTHON_BASELINE_VERIFICATION.md)の実署名試験で問題として確認。不可視Constraintが不存在との推定禁止 |
| Open→Closedの2hop Binding | **未実装**。Holder `cnf`、terminal `sd_hash`、`aud`/`nonce`、`iat`/`exp`は今後の負例が必要 |
| Checkout JWTのIssuer/Merchant trust | **簡単な固定鍵の署名チェックのみ**。Host DBのCheckout正本やIssuerの信頼Anchorの証明・revocation未実装 |
| `checkout_hash` | **原文バイトHash計算だけを確認**。Closed中HashとHost正本、Merchant署名の統合検証は未実装 |
| JSON Schema/制約 | **Open Checkout構造の基本4条件を実測**。allowed_merchantsのremote `$ref`、SD-JWT後のDisclosure段階、未知/非開示Constraint、Line Items数量マッチングの包括的評価は未実装 |
| Rubygems/リリース | **未承認**。API/Gem/CI Matrix/Production安全性を主張しない |

## 5. 判定と次の1つ

**P1-0：限定的なRuby技術互換性の実証はPASS。** `jwt` / `json_schemer` を小さく再利用できそうであり、Ruby JWS/JWK、Hash、Open Schemaの基礎実行にブロッカーは見られなかった。この結論は単一のfixture/依存versionの観測であり、AP2 Verifier完成や一般的なセキュリティ保証ではない。

**GO/HOLDの線引き:** [RESEARCH_DECISION](RESEARCH_DECISION.md) §9の**狭い非本番研究PoCだけCONDITIONAL GO**を維持。汎用Gem・public API固定・リリース・本番利用は **HOLD/NO-GO**。

**次の1件（別途明示承認後のみ）:** **P1-1 — RubyのSD-JWT Root署名・Disclosure digest / required-constraint completeness のオフライン最小Spike**。まず固定AP2 Pythonの署名付き正負fixtureを使い、**本物のSD-JWT wire / `_sd` / disclosure検証だけ**をRubyで比較する。Hidden Merchant Constraintを見逃す成功は絶対に受け入れない。PoCとして成立しないならHOLDに戻す。**Gem実装・公開・実決済・GCP利用は引き続き禁止**。
