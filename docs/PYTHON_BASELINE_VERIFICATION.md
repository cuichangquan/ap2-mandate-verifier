# Python Baseline Verification — P0-5a

**実行日:** 2026-10-11 JST  
**状態:** **P0-5aの公式SDK実行まで完了。ただし公式pytestは186 PASS / 2 FAIL、独立した実署名負例は12 PASS**。先行する隔離サブセット11 PASSは別集計。**P0-5のRuby実装判断は引き続きHOLD**。GitHub Actions [実行 #38121818162](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38121818162) に実測ログあり。  
**仕様・ソース固定:** AP2 `v0.2.0` / `b4587ac1d055888a73b4b21750973cffba961793`（[SPEC_BASELINE](SPEC_BASELINE.md)）。Python SDKのpackage versionは`0.1`であり、規格のversionとは別。  
**重要:** §1〜§6は**先行するローカル隔離サブセット（11 PASS、重要依存をstub化）**の履歴である。**§7〜§9はその後の公式Python SDK全体・追加の署名付き負例の実測記録**。両試験は別物であり、テスト件数を合算して『公式合格』とはしない。実決済やRuby Gem実装は行っていない。

## 1. 先行ローカル隔離サブセットの環境（履歴）

| 項目 | 実測値 |
| --- | --- |
| OS / Python | Linux amd64 / Python **3.13.5** |
| pytest | **9.0.2** |
| Pydantic | **2.13.5**（公式固定pyprojectは **2.12.5**。**version一致せず**） |
| jsonschema | **4.26.0**（公式Python SDKの必須依存ではなくこの独立確認に利用） |
| cryptography | **46.0.4**（公式固定pyproject **46.0.5**。今回の対象パスでは暗号実行なし） |
| `jwcrypto` / `sd_jwt` | **インストールなし**。公式 `pyproject.toml` の `jwcrypto==1.5.6` / `sd-jwt==0.10.4` と異なり、**フルSDKテスト不可** |
| GitHubネットワーク | `git ls-remote https://github.com/google-agentic-commerce/AP2.git refs/tags/v0.2.0` → **`Could not resolve host: github.com`**。環境のDNS/外部ネットワーク制約 |
| 公開GitHub連携 | 固定SHAの5個のソースファイルを取得可能。以下のBlob SHAに一致する内容を隔離環境に復元して確認 |
| 外部リソース/費用 | **GCP/VM/VPC/Cloud NAT/外部実サービス/実決済は利用なし**。ネットワーク経由のパッケージインストールなし |

**先行ローカル環境では**公式`uv sync` / 全体pytestを実施できなかった。**その後GitHub Actionsで公式188件を実行し、186 PASS / 2 FAILを実測（§7）**。ここに記したPython 3.13.5や依存不在は先行環境のみを示す。

## 2. 使用した**完全一致**の公式ファイルと範囲

以下のGit Blob SHA（`git hash-object <path>`相当）を実ファイルで計算し、GitHubから取得した各Blob SHAと一致することを確認した。

| 固定ソース | Git Blob SHA |
| --- | --- |
| [generated/open_checkout_mandate.py](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/generated/open_checkout_mandate.py) | `0d85f1b79f6334a5db68b188f50ed2226fb94286` |
| [generated/checkout_mandate.py](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/generated/checkout_mandate.py) | `f78fa665dea404373ae693cc7851d16d42996c8d` |
| [generated/types/merchant.py](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/generated/types/merchant.py) | `0275ea9469d83f1ad658ce080465676fa1775043` |
| [checkout_mandate_chain.py](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/checkout_mandate_chain.py) | `2fb4b0e0dcdca6e05f4f1c980a4778c2bfc9f091` |
| [schemas/open_checkout_mandate.json](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json) | `e3d9cafa7311d90612c7f908ae9b8821ddc8735a` |

**検証の仕組み:** 最初の4ファイルは実際の**改変していない公式Pythonコード**（CheckoutChainとOpen/ClosedのPydantic Model）、5番目は公式JSON Schema。外部ライブラリ不足を回避するため `constraints.check_checkout_constraints`（**空のconstraintsのみ**）、`Checkout`型（`id`のみの最小Pydantic stub）、`_log_event`、`b64url_decode`はテスト用に差し替えた。**署名・信頼・元制約を検証する処理の成功は含めない。**

## 3. 実測結果 — 独立サブセット **11 PASS / 0 FAIL / 0 SKIP**

**再現可能なテストファイル:** [research/p0_5a/test_ap2_checkout_subset.py](../research/p0_5a/test_ap2_checkout_subset.py)。このファイルは本プロジェクトの研究用fixtureであり、公式SDKのtest fileではない。

```text
$ AP2_SOURCE_ROOT=<isolated-pinned-files-dir> python -m pytest \
    research/p0_5a/test_ap2_checkout_subset.py -q --tb=short

...........                                            [100%]
11 passed in 0.89s
```

| ID | 入力 / 対象 | **観察した結果**（この限定パスのみ） |
| --- | --- | --- |
| 00 | 公式5ファイルのGit Blob SHA | 全て一致 |
| 01 | `OpenCheckoutMandate.constraints=[]` → 生成Pydantic | **受理** |
| 02 | 同じOpenデータ → 固定JSON Schema Draft 2020-12 | **拒否**（`contains`条件未充足） |
| 03 | 標準`checkout.line_items`を1件持つOpen | モデルとJSON Schema両方で受理 |
| 04 | suffixなしの不正`vct` → モデル | 拒否 |
| 05 | 署名部が`FAKE_SIGNATURE`のJWT → Checkout helper | **制約stubで違反なし**（helper内は署名検証しない） |
| 06 | 明らかに偽の`checkout_hash`、`expected_checkout_hash`未指定 | **違反なし** |
| 07 | `expected_checkout_hash`を渡し一致しない | **hash mismatchを返す** |
| 08 | Closed Mandate内はCheckout A、helperへ渡したJWTはCheckout B | **違反なし**（helper自身は両JWTの同一性比較なし） |
| 09 | JWTコンパクト形式が3-partでない | 拒否 |
| 10 | Checkout JWT入力なし | 拒否 |

**解釈のポイント:**

- **SDKのCheckout helper単体はMerchantの全MUSTを満たさない。** Hostは、真正なmerchant-signed Checkout JWT、署名検証、Closedの`checkout_jwt`と正本の比較、`checkout_hash`の**独立再計算**を別途必ず確保する設計が必要。https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md（Merchant）／https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/checkout_mandate_chain.py（helper）。
- **Open schema と生成モデルは空constraint時に異なる。** ただし**Selective Disclosure時にどのschemaをどこへ適用するかは未確定**。この結果だけであらゆるOpen Mandateが不正・SDK全体が脆弱とは言わない。https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json。
- 11 PASSは**上記の観察を確認するassertionが全て成立した**という意味であり、Checkout verifierの安全テスト11件を突破した、という意味ではない。

## 4. 先行サブセットでは未検証だった領域（その後§7〜§8で一部解消）

| テーマ | ステータス | 不足している証拠 |
| --- | --- | --- |
| 公式Python SDK全テスト | **BLOCKED** | 固定Git checkout、公式ロック済み依存、pytest正負の実測 |
| SD-JWT / Delegate SD-JWTの真正署名・Disclosure・Chain | **NOT RUN** | `jwcrypto`/`sd-jwt`、holder/issuer keys、chain `sd_hash`等の暗号試験 |
| `aud` /`nonce` | **NOT RUN** | 期待値がない・存在しない・不一致のterminal KB-SD-JWTの負例 |
| Issuer trust /`x5c` | **NOT RUN** | 信頼しないroot／証明書validation／`kid`拒否の署名付きfixture |
| 非開示Constraints | **NOT RUN** | SD-JWTの本物のDisclosure消去、元IssuerがcommitしたConstraintの証明、Hostの期待値と評価 |
| Schema `contains` vs生成モデル | **SUBSET PASS** | 型だけ比較済み。公式SD-JWT発行・表示flow内での適用時点は未確定 |
| Payment / replay / Revocation / Host決済 | **OUT OF SCOPE** | Host責務、今回の検証対象ではない |
| Ruby / Python相互運用 | **NOT RUN** | Ruby Gem未実装・現段階の承認対象外 |

**独立したAP2脆弱性の認定・本番安全性・仕様適合の主張は禁止。** 上流[#319](https://github.com/google-agentic-commerce/AP2/issues/319)、[#358](https://github.com/google-agentic-commerce/AP2/issues/358)、[#339](https://github.com/google-agentic-commerce/AP2/issues/339)は継続観察対象であり、IssueのOpen状態自体は今回の攻撃再現結果ではない。

## 5. 先行サブセットの再実行方法（現在の推奨は§7）

**研究コードを残した目的は、ここから先を確実に再現できること。** 固定ソースはこのリポジトリに複製せず、公式のGitHubから独立した作業フォルダへcheckoutする。

```bash
# クローン先は独立ディレクトリ（ホストにGit/uv/Pythonがある前提）
git clone https://github.com/google-agentic-commerce/AP2.git /tmp/ap2-p0-5a
cd /tmp/ap2-p0-5a
git checkout b4587ac1d055888a73b4b21750973cffba961793
git rev-parse HEAD  # expected: b4587ac1d055888a73b4b21750973cffba961793

# 固定uv.lockにはprivate Artifact Registryの401になる取得URLが含まれるため
# 実際に成功した§7の公開PyPI + upstream pyproject pinsを参照
python -m pip install --index-url https://pypi.org/simple -e .
python -m pytest code/sdk/python/ap2/tests/ -q --tb=short

# これとは別に、当リポジトリの研究サブセットを実行
# /path/to/ap2-mandate-verifier のパスはローカルの配置に読み替える
AP2_SOURCE_ROOT=/tmp/ap2-p0-5a python -m pytest \
  /path/to/ap2-mandate-verifier/research/p0_5a/test_ap2_checkout_subset.py -q
```

初回のCloneやPyPI依存取得にはネットワークが必要。テスト実行中は外部実サービス通信/決済なし。**今回は公式uv.lockが認証付きprivate Artifact Registryを指してHTTP 401となったため使用できず、upstream pyprojectの直接依存バージョン指定で公開PyPIから導入した（§7）。推移的依存の完全ロック再現ではない。** 公式pytestの失敗をPASS扱いしない。

## 6. 先行ローカル試験時点の判断（履歴）

**当時の判定はHOLD。** Checkout Hashと公式Open Model/Schemaの差について固定ソースの限定パスで実測した。その後、公式SDK全体とissuer/aud/nonce/disclosureの実測を行ったため、最新判断は§9を正本とする。

**旧提案は実行済み**。P0-5aの最新結果・次の1件は§7〜§9を参照。


## 7. 固定AP2 v0.2.0の公式SDK全体をGitHub Actionsで実行（後続の実測結果）

**証拠:** [GitHub Actions run #38121818162](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38121818162)（GitHub-hosted Ubuntu 24.04隔離ランナー、2026-10-11 JST）。[実行ワークフロー](../.github/workflows/ap2-python-research.yml)、[追加のフルSDK負例](../research/p0_5a/test_ap2_real_sdk_negatives.py)。[実測ログ一式](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38121818162/artifacts/11695711894)（GitHub Artifact、**7日保持予定**。消失後はrun/jobログを参照）。

| 項目 | 実測と明示的な限界 |
| --- | --- |
| 公式Git checkout | \`git clone\`後、tag対応の厳密なCommit \`b4587ac1d055888a73b4b21750973cffba961793\` へdetach checkout。HEAD一致をCIでassert、**成功** |
| 環境 | \`ubuntu-24.04\`、**CPython 3.11.17** |
| インストール | **最初の\`uv sync --frozen\`は401で失敗**。upstream固定\`uv.lock\`が \`us-python.pkg.dev/artifact-foundry-prod/ah-3p-staging-python\` というprivate registryを参照。2回目以降は**公式\`pyproject.toml\`の直接依存バージョンを保持**して公開PyPIから \`python -m pip install --index-url https://pypi.org/simple -e .\` で成功。**uv.lock完全再現ではない** |
| 公式直接依存 | \`cryptography==46.0.5\`、\`jwcrypto==1.5.6\`、\`pydantic==2.12.5\`、\`sd-jwt==0.10.4\`、\`pytest==9.0.2\` は公式pyprojectの指定に従った。**transitive packageは\`uv.lock\`で固定できていない**（\`pip freeze\`をArtifactに保存） |
| 公式pytest | **188ケース中 186 PASS / 2 FAIL / 0 SKIP**（\`python -m pytest code/sdk/python/ap2/tests/ -q --tb=short\`） |
| 公式失敗1 | \`ap2/tests/kb_sd_jwt_intermediate_tests.py::test_verify_rejects_aud_mismatch\` → \`DID NOT RAISE ValueError\` |
| 公式失敗2 | \`ap2/tests/kb_sd_jwt_intermediate_tests.py::test_verify_rejects_nonce_mismatch\` → \`DID NOT RAISE ValueError\` |
| 追加テスト | **12 PASS / 0 FAIL / 0 SKIP**（実際の\`jwcrypto\`, \`sd-jwt\`, AP2 SDKのsigned token/chain/constraintsを使用。**stubなし**） |
| Github job全体 | ワークフローは**結果収集用**：公式pytestの非ゼロ終了を捕捉して後続負例を実行。**Job成功と公式pytest PASSは別**。ワークフローの最終段で公式失敗をwarning、当リポジトリの追加負例が失敗したらfailureとする |
| 料金・外部サービス | **GCP・実決済・外部商用Checkout/Issuerの呼出しなし**。GitHub Actionsの通常利用枠には依存。GitHubと公開PyPIへの依存取得通信は発生。 |

### なぜ2件失敗したか

**上流のテストと実装の想定が異なる箇所を確認**。固定版\`kb_sd_jwt.verify\`は\`expected_aud\`/\`expected_nonce\`の照合を**terminal hopにのみ実施**する。一方上記の公式2テストは **intermediate hop** が期待値不一致で拒否されることを想定している。したがって「DID NOT RAISE」は観察事実だが、**中間hopごとにaud/nonceをMUSTチェックすることがAP2に必須か、テストまたはコードのどちらが正しいかは未決定**。**現時点で脆弱性と断定しない。** 

## 8. 追加した**実署名・実SD-JWT**の負例と解釈

| 実測 | 対象（12件） | 挙動と意味 |
| --- | --- | --- |
| **3 PASS** | 署名が正しいterminal KB-SD-JWTを作り、\`aud\`、\`nonce\`、両方を削除して**再署名**。期待値を渡さない | いずれも**受理される**。**Hostは必須challengeの期待値を渡す**設計が必要。一般化したAP2 MUSTの主張ではない |
| **2 PASS** | 上記の署名付きtokenに期待\`aud\`／期待\`nonce\`を渡す | 欠落が**不一致として拒否**される |
| **1 PASS** | 有効な自己署名\`x5c\`を、\`trusted_roots=None\`でproviderに提示 | **rootの信頼アンカー未検証で受理**。署名の正しさとIssuer trustは別 |
| **1 PASS** | 同じ型のIssuer certに**無関係なtrusted root**を明示 | **拒否**される |
| **1 PASS** | Checkout helperへ偽\`checkout_hash\`を与え期待hashを省略 | **違反リストは空**。Merchantが独立照合を別途要実装 |
| **1 PASS** | ClosedにCheckout A、helper入力にCheckout B | **違反リストは空**。Host正本JWTとclosedの同一性・署名は別検証が必要 |
| **1 PASS** | Openの生成Pydantic Modelで\`constraints=[]\` | **受理**。公式JSON Schema \`contains\`との差は先行サブセットで実測 |
| **1 PASS** | 可視Constraint配列が空で\`check_checkout_constraints\`を呼出し | 違反0件。ただしゼロ制約評価は**authorizationの根拠でない** |
| **1 PASS** | **IssuerがMerchant制約を選択的開示可能として発行した実署名Open SD-JWT**。その項目だけ非開示、LineItemsは開示し、Root署名とDisclosure整合を検証。非許可MerchantのCheckoutを評価 | 署名は有効。開示されているLineItems制約は満たすため**違反0件**。元の署名付きMandateではMerchant制約があること、全部開示時には違反が出ることを同一テストで確認。**『署名成功+見えるConstraintが満たされた』≠『権限制約が完全に満たされた』** |

**最後のケースは条件付きの実証**：発行IssuerがそのMerchant制約を選択的開示可能にした入力を用いた。これだけで全AP2 Mandateが迂回可能、購入不正が成立する、運用環境に脆弱性がある、と主張しない。HostはIssuerの信頼ポリシー、必要開示ポリシー、特定Checkout正本・Agent鍵の確認、state/replay防止、最終業務認可を独立して行うべきである。

**この12件は『不適切な受理が起こる個別helperの挙動を再現した』テストを含む**。12 PASSはAP2 Verifier全体が安全との意味ではない。

## 9. P0-5a完了判断 / RUBY GO判定

- [x] 固定AP2 Commit取得、実環境・依存・コマンド・ログを記録（ただし\`uv.lock\`はprivate 401、pyproject pins +公開PyPIで代替）。
- [x] 公式pytestの**188件を実行**。**186 PASS / 2 FAIL** を正確に記録し、失敗ケースを特定。
- [x] Signed terminal aud/nonce、x5c trust、Checkout Hash、Checkout差替え、可視Constraint、署名付きSelective Disclosureの追加12テストを**実行**。
- [x] コストが高いGCPや実サービス・実決済を使わず検証。
- [ ] **Ruby/Python相互運用、商用利用の安全性、Hostの要求する全Constraintの完全性証明**は未検証。

**P0-5aの研究テストは完了。ただしP0-5の実装判断はHOLDを維持する。** なぜなら公式pytestが2件失敗し、\`aud\`/\`nonce\`のhop適用範囲、hidden ConstraintのHost必須開示条件、Root Issuerの信頼アンカー、Checkout JWTのmerchant署名/hashを**小さなRuby PoCのAPIとしてどうFail Closedするか**は確定していないからである。これらを明示すれば、上流Issueが残っていても限定非本番PoCへGOできる可能性がある。

**次の1件だけ:** **P0-5b：固定版の実測結果を根拠に、「初期Checkout Verifierで必ず拒否する条件（Issuer trust/aud/nonce/required-disclosure/Checkout hash）」をHost向けの最小Fail Closed Profileとして文書化し、GO/HOLDを再判定する（設計と判断だけ）**。Ruby Gem実装・公開は**別の明示承認まで禁止**。
