# Ruby SD-JWT Root & Disclosure Research — Phase 1 / P1-1

**実行日:** 2026-10-11 JST  
**状態:** **P1-1 PASS（厳格に限定したRoot SD-JWT研究Spike）／Ruby Gem・AP2委任チェーン・本番用Verifierは未実装**。  
**公式ソース:** AP2 `v0.2.0` commit `b4587ac1d055888a73b4b21750973cffba961793`。固定版[MandateClient.create](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/mandate.py#L153-L173)、[sd_jwt.create/verify](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/sd_jwt.py#L23-L88)、[DisclosureMetadata](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/disclosure_metadata.py)。  
**一次証拠:** [GitHub Actions run #38123828122](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38123828122)、[Python実署名fixture生成器](../research/p1_1/generate_python_sdjwt.py)、[Ruby研究テスト](../research/p1_1/test_ruby_root_sdjwt.rb)。

## 1. 目的・成果

P1-0でRubyのES256/JWK・Checkout SHA-256・公式Schemaを限定確認した。P1-1は次の3つを実際の**固定AP2 Python SDK生成SD-JWT**で確かめた。

1. Ruby `jwt`で**Host指定のIssuer公開JWK**を使い、Root JWTのES256署名を検証できること。
2. compact SD-JWTの **array-element disclosure** が、署名済JWT payload中の `{"...": "<digest>"}` に対応しているか、開示文字列のASCIIバイトのSHA-256→base64urlで検証できること。Root `delegate_payload` と入れ子の `constraints` で両方確認。
3. Issuerが`checkout.allowed_merchants`を選択的開示可能にした場合、Agentがその開示要素を取り除いても元署名は有効になりうる。**Ruby側は必要な開示が欠ければRejectionとする**こと。

ここでの **Fail Closed は「この合成Issuerレイアウトと制限プロフィールで必要情報がない場合の拒否」**という意味。**一般のSD-JWTについて隠れたすべての権限制約の不存在を証明できたわけではない**。商用AP2の攻撃成立や安全性全般の主張をしない。

## 2. 実行環境と一次記録

| 項目 | 実測・条件 |
| --- | --- |
| 実行 | [GitHub Actions #38123828122](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38123828122)（GitHub-hosted Ubuntu 24.04） |
| Python | **3.11**。固定上流Commitをcheckout後、upstream `pyproject.toml` の直接依存ピンを使って公開PyPIから `pip install -e .`。公式`uv.lock`にはアクセス不能なprivate registryがあるため**完全lock再現ではない** |
| Ruby | **3.3.12**、`jwt 3.3.0`。標準の `JSON`、`Digest`、`Base64`、`Set`、Minitestを利用 |
| 生成物 | 公式 `MandateClient.create` / `DisclosureMetadata(sd_array_indices=[1])`からIssuer署名付きOpen Checkoutのrootを生成。生成時にはPython公式 `sd_jwt.verify`で「完全開示／Merchant非開示のどちらも署名検証が成立」を予備確認 |
| 実測 | **10 runs / 22 assertions / 0 failures / 0 errors / 0 skips** |
| Test data | **架空Merchant/SKUとその場で生成したP-256秘密鍵**。秘密鍵はRepository/Artifactへ書かない。研究ログはGitHub Artifactに7日保持予定 |
| コスト | GCP/実決済/実サービスの呼出しなし。GitHub Actionsランナー、GitHub clone、公開PyPIとRubyGemsへの依存ダウンロードは発生 |
| トリガー | PRの初回検証後、ワークフローは**手動起動（`workflow_dispatch`）専用**へ変更。普段のpushで再実行しない |

**Rubyの署名検証先は、トークン内で自己申告されたIssuer鍵でなく、fixtureに含むHost trustとして指定したIssuerの公開JWK。** 任意の `x5c`/`kid`/`jku` から信頼を構築していない。

## 3. 10のテスト（すべてRuby実行でPASS）

| ID | 操作 | 研究用の期待動作・実測 |
| --- | --- | --- |
| 01 | 公式Pythonが発行し、RootとMerchantのdisclosureを**すべて開示**したOpen | **受理**。ES256署名、2箇所のarray disclosure digest、2種類のConstraintを確認 |
| 02 | **Merchant制約のdisclosureだけ削除**。署名済JWT本体と残りの開示は変更なし | **拒否**。`missing disclosure`。元Root署名は有効でも権限制約の完全性を認めない |
| 03 | Merchant disclosureのsaltを変更し、開示文字列を再エンコード | **拒否**。署名済`{"...": digest}`と不一致 |
| 04 | Issuer JWTの署名バイトを改ざん | **拒否** |
| 05 | 有効JWTに異なるIssuer公開JWKを渡す | **拒否** |
| 06 | HostのIssuer信頼済みJWKを渡さない | **拒否** |
| 07 | 同じ開示要素を二重追加 | **拒否** |
| 08 | 有効な開示一覧に無関係なDisclosureを追加 | **拒否** |
| 09 | Root `delegate_payload` 自体のDisclosureがない | **拒否** |
| 10 | 不正compact wire | **拒否** |

10 PASSは**元のPython公式SDKが同じ検証機能を全保証することではない**。今回のRuby研究コードが、限られた入力に対して想定どおり受理・拒否したことを意味する。

## 4. Ruby研究コードの安全境界と重大な留保

**実際にしたこと**：Ruby `jwt`でHost公開JWKとES256を明示しJWT署名を検証。JWT payloadから配列要素の`{"...": digest}`を探し、提示されたDisclosure（salt/value）のエンコード文字列をSHA-256で照合。使われない開示、同じdigestの二重使用、欠けた開示、未知場所のarray disclosure、object-level `_sd`を拒否。Open `vct`、Issuer endorsesされた `cnf.jwk`、2種のConstraint、有限の`iat`/`exp`を追加で要求。

**まだできないこと・禁止事項：**

- **SD-JWT RFC全体の実装ではない**。Dictionary claim disclosure、decoy digest、`_sd_alg`がsha-256以外、nested arrayの追加形式、`issuer_jwt_hash` modeや複数Agentのdelegationは**意図的に非対応**。完全なcompact wire canonicalization、未知headerの処理、トークンサイズ／深さ上限、重複JSONキー検出、全ての形式的エラーはまだ未検証。
- **完全性の証明はIssuer layoutに依存する**。研究fixtureは、`delegate_payload`と権限制約配列が元Root署名にcommitし、`checkout.line_items`と`checkout.allowed_merchants`の**両方を必須とする追加Profile**を仮定する。任意のIssuerが別制約を単に省略した場合、それが存在しなかったと暗号的に証明できない。**可視Constraintが満たされたことだけでVerifiedEvidenceや購入許可を与えてはならない**。
- **Holder/Agent Proof-of-PossessionとOpen→Closed bindingは未実装**。`cnf.jwk`が見えるのと、実際にその秘密鍵でTerminalが署名したことの検証は異なる。`sd_hash`、terminal `aud`/`nonce`も未検証。
- **Checkout JWTとHost正本の署名/checkout_hash、制約の実際のMerchant/Item取引照合、Hostの失効・nonce消費・replay・業務判断、Receiptは未実装**。
- 署名とdigest照合後にも、他プロファイルや未サポートレイアウトを受理してよいという結論にはならない。**コードは隔離研究のサンプルでありGem/汎用公開APIとして利用しない**。

なお、P0-5aの公式Python SDK **186 PASS / 2 FAIL**（intermediate aud/nonce）は別の試験結果であり、P1-1の10 PASSと混同しない。[PYTHON_BASELINE_VERIFICATION](PYTHON_BASELINE_VERIFICATION.md)を参照。

## 5. 再現手順（ネットワークは依存の初回取得時のみ）

```bash
# ap2-mandate-verifierリポジトリの作業ディレクトリから
git clone https://github.com/google-agentic-commerce/AP2.git /tmp/ap2-p1-1
git -C /tmp/ap2-p1-1 checkout --detach b4587ac1d055888a73b4b21750973cffba961793
test "$(git -C /tmp/ap2-p1-1 rev-parse HEAD)" = "b4587ac1d055888a73b4b21750973cffba961793"

# Python >=3.11。上流pyprojectの直接依存ピンを使用（uv.lock完全再現ではない）
(cd /tmp/ap2-p1-1 && python -m pip install --index-url https://pypi.org/simple -e .)
gem install jwt -v 3.3.0 --no-document

# 合成の本物のissuer signature付きfixtureを一時フォルダに作成（秘密鍵は保存しない）
python research/p1_1/generate_python_sdjwt.py /tmp/p1-1-root-fixtures.json

AP2_P11_FIXTURES=/tmp/p1-1-root-fixtures.json \
  ruby research/p1_1/test_ruby_root_sdjwt.rb --verbose
```

**一次CI定義**：[p1-1-sdjwt-research.yml](../.github/workflows/p1-1-sdjwt-research.yml)。テストは通常**手動起動**。実行データ自体はその都度新規の合成鍵で署名されるためwire文字列は固定ではないが、**公式AP2 SDKソースCommitと直接依存を固定した再現可能な生成・検証の契約**をテストしている。

## 6. P1-1の結論・次の1件

- [x] **実署名Root**（公式AP2 v0.2 SDK）をRubyで検証。
- [x] `delegate_payload`と`constraints`のSHA-256 Disclosure digestを照合し、完全開示の受理とMerchant制約非開示の拒否を実行確認。
- [x] 改ざん・未信頼Issuer・重複/無関係Disclosure・Root非開示の負例を含む**10件成功**。
- [ ] **Delegated Open→Closedの2hop、Terminal Holder秘密鍵、`sd_hash`、aud/nonce**のRubyでの実行検証は未実施。
- [ ] 隠れた権限制約の一般的完全性証明、他Issuer互換、正式Gem/API、本番安全性は**未実証**。

**判定：狭い研究PoCのCONDITIONAL GOを維持。汎用Gem/API/リリースはHOLD、本番利用はNO-GO。** P1-1で得られたのは署名済RootとDisclosureの部分的互換性のみ。

**次の優先タスク（別途承認後の1件）：P1-2 — Rubyで同一AgentのTerminal KB-SD-JWT署名、前段Root `cnf` との一致、`sd_hash`、Host期待 `aud`/`nonce` を固定SDK生成fixtureで検証するオフライン2-hop Spike。** 2段以外のDelegation、Gem作成・公開・決済は実施しない。
