# Python Baseline Verification — P0-5a

**実行日:** 2026-10-11 JST  
**状態:** **PARTIAL / BLOCKED（公式pytest全件と暗号負例は未実行）**。固定版の**Checkout関連5ファイルだけを使った隔離サブセット11件は実測PASS**。**P0-5のRuby実装判断は引き続きHOLD**。  
**仕様・ソース固定:** AP2 `v0.2.0` / `b4587ac1d055888a73b4b21750973cffba961793`（[SPEC_BASELINE](SPEC_BASELINE.md)）。Python SDKのpackage versionは`0.1`であり、規格のversionとは別。  
**重要:** この検証は公式AP2のpytest全体を実行したことには**ならない**。Checkout制約の本物のEvaluator、crypto署名検証、SD-JWT chain、Issuerの鍵解決は**明示的なstubに置換/未実行**。`CheckoutMandateChain.verify`の**限定的なコードパス**と生成モデル・公式Schemaの対応だけを測定した。

## 1. 実行環境とアクセス制約

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

公式`uv sync` / `uv run python -m pytest code/sdk/python/ap2/tests/ -v`は、**環境制約により実施できていない**。公式テストのPASS/FAIL/SKIP件数は**UNKNOWN、0件として数えない**。本書の「11 passed」を公式SDK全体の結果と混同しない。

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

## 4. **未検証**の領域と判断への影響

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

## 5. 再実行方法（固定AP2を取得できる隔離マシン向け）

**研究コードを残した目的は、ここから先を確実に再現できること。** 固定ソースはこのリポジトリに複製せず、公式のGitHubから独立した作業フォルダへcheckoutする。

```bash
# クローン先は独立ディレクトリ（ホストにGit/uv/Pythonがある前提）
git clone https://github.com/google-agentic-commerce/AP2.git /tmp/ap2-p0-5a
cd /tmp/ap2-p0-5a
git checkout b4587ac1d055888a73b4b21750973cffba961793
git rev-parse HEAD  # expected: b4587ac1d055888a73b4b21750973cffba961793

# 必須依存が取得できる環境で実行。PyPI通信が必要なら初回のみ許可する
uv sync --frozen
uv run python -m pytest code/sdk/python/ap2/tests/ -v

# これとは別に、当リポジトリの研究サブセットを実行
# /path/to/ap2-mandate-verifier のパスはローカルの配置に読み替える
AP2_SOURCE_ROOT=/tmp/ap2-p0-5a uv run python -m pytest \
  /path/to/ap2-mandate-verifier/research/p0_5a/test_ap2_checkout_subset.py -q
```

初回のCloneやPyPI依存取得にはネットワークが必要。**「オフライン」はテスト実行時の外部実サービス通信/決済を避ける**意味であり、インストール自体が完全にネットワーク不要という主張ではない。固定Commitと依存ロックを維持し、Python version・Gem/Package versionとPass/Fail/Skipログを残す。公式pytestに既知の障害があっても勝手に修正してPASS扱いしない。

## 6. P0-5 の再判定と次の1件

**判定: HOLD 継続。** Checkout Hashと公式Open Model/Schemaの差については、固定ソースの**限定的なコードパス**で実測証拠を得た。しかしOfficial Python SDK全体・Issuer信頼・terminal aud/nonce・disclosureの実行検証が未完了なので、`GO`に必要な証拠が揃っていない。判断基準は[RESEARCH_DECISION](RESEARCH_DECISION.md)で維持する。

**次のタスク（1件だけ）:** **P0-5aの残作業 — ネットワークで依存が取得できる隔離環境（例：ユーザーのmacOS）で固定AP2 SDKの公式pytestと、Issuer/aud/nonce/hidden Constraintの優先負例を実行し、この資料に実測結果を追記する。** **ユーザーから改めて依頼されるまで実行を予定しない**。Ruby Gemの実装・公開には進まない。
