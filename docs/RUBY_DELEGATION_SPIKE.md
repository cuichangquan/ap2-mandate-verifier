# Ruby Open→Closed 2-hop Delegation Spike — P1-2

**実行日:** 2026-10-11 JST  
**状態:** **P1-2 PASS（固定AP2 v0.2の狭い2hop署名・binding研究）**。正式Ruby Gem/API、広範なAP2 Mandate Verifier、実決済・本番安全性の検証ではない。  
**公式基準:** AP2 `v0.2.0` 固定Commit `b4587ac1d055888a73b4b21750973cffba961793`（[kb_sd_jwt.create/verify](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/kb_sd_jwt.py#L35-L140)、[common.compute_sd_hash](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/common.py#L165-L221)、[chain.verify_chain](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/chain.py#L121-L180)）。  
**一次証拠:** [GitHub Actions #38124823804](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38124823804) / [生成器](../research/p1_2/generate_two_hop_python.py) / [Ruby研究テスト](../research/p1_2/test_ruby_two_hop.rb) / [Workflow](../.github/workflows/p1-2-two-hop-research.yml)。

## 1. 検証対象と境界

P1-1で検証した**Issuer署名済Open Root SD-JWT**と、同じAgentの秘密鍵によって公式Python SDKが作った**Terminal Closed Checkout KB-SD-JWT**を、Rubyで個別に署名検証し、連結の正しさを確かめる。

```text
[Host input / trusted]
  pinned issuer public JWK + expected agent public JWK
  expected merchant audience + fresh nonce (comparison ONLY)
             |
             v
  Issuer-signed Open Root SD-JWT (exact wire incl disclosures)
     1. Root issuer signature & full disclosed constraints — P1-1 checker
     2. Root "cnf.jwk" exactly matches Host-expected Agent public key
             |
          sd_hash = base64url(SHA-256(raw Root SD-JWT wire bytes))
             |
             v
  Agent-signed Terminal Closed KB-SD-JWT
     3. Terminal ES256 verified against Root-endorsed cnf.jwk
     4. terminal typ=kb+sd-jwt, signed sd_hash exactly matches Root
     5. Host expected aud/nonce (required) match terminal claims
     6. exactly one Closed Checkout Mandate, no intermediate/third hop
             |
             v
  Research result: checked cryptographic binding evidence
  NOT Host ALLOW; Merchant Checkout JWT signature is NOT verified
```

**今回のCheckout JWTは、署名部分が `NOT_A_SIGNATURE` の架空データで、意図的にMerchant署名されていない。** 従って`checkout_hash`の正しさや`CheckoutJWT`のMerchant真正性・注文状態・決済権限の検証が成功したとは言わない。Open→Closed **暗号bindingにのみ焦点を当てた研究**。

**対象範囲:** 1 Root + 1 Terminal の2hopのみ、単一の事前承認Agent、HostからIssuer/Agent公開鍵と期待`aud`/`nonce`を必須提供、ES256/sha-256、Full Disclosureが確認できるstrict Root layout。Direct、3hop以上、中間KB-SD-JWT、unknown `typ`、`issuer_jwt_hash`モード、非対応SD-JWT形状は拒否する。

## 2. 実際に実行した環境

| 項目 | 実測と留保 |
| --- | --- |
| GitHub Actions | [run #38124823804](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38124823804)、GitHub-hosted **Ubuntu 24.04** |
| Ruby | **3.3.12**、`jwt 3.3.0`、Ruby stdlibのDigest/JSON/Base64 |
| Python | **3.11**、固定Git SHA `b4587ac1d055888a73b4b21750973cffba961793` の公式SDKを直接取得 |
| Python依存 | Upstream `pyproject.toml` の直接バージョンピンを公開PyPIから導入。公式`uv.lock`は認証付きレジストリへのHTTP 401が判明しているため**完全な推移的依存のlock再現ではない** |
| 公式Pythonチェーン | `kb_sd_jwt.create` + `verify_chain` による**有効な2hopの発行・検証PASS**（runログに記録）。全公式pytestは今回再実行していない |
| **P1-2 Rubyテスト** | **15 runs / 32 assertions / 0 failures / 0 errors / 0 skips** |
| **P1-1 回帰テスト** | **10 runs / 22 assertions / 0 failures / 0 errors / 0 skips**（Root SD-JWT parserを共有化してから再実行） |
| 研究Fixture | GitHub Actionsランナー内で都度生成する**合成鍵・架空Merchant/Agent/Checkout**。秘密鍵はGitHubのコミットにもArtifactにも保存しない |
| Artifact | [実測ログと直接依存一覧](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38124823804/artifacts/11696831066)（保持期限7日）。固定テスト手順はGitHub上に残す |
| 実行コスト | 自前のGCP/VM/Cloud Runは利用せず。GitHub-hosted runnerと依存取得のみ。初回PR実行後は**手動起動専用**に変更 |

## 3. Rubyの15テスト結果（すべて成功）

| ID | 検証 | 実測した扱い |
| --- | --- | --- |
| 01 | 公式Pythonが署名しPythonでも認証済みのOpen→Closed 2hop | **受理（暗号bindingに限る）**。Root/TerminalのVCT確認 |
| 02 | Terminalの署名者が別Agent鍵 | **拒否**：Rootがendorseした`cnf.jwk`で署名が検証できない |
| 03 | Terminalが**別のRoot**に結び付いた`sd_hash`を持つ | **拒否** |
| 04 | 署名は正しいがTerminalの`aud`がHost期待値と違う | **拒否** |
| 05 | 署名は正しいがTerminalの`nonce`がHost期待値と違う | **拒否** |
| 06 | Hostの期待`aud`が未指定 | **拒否** |
| 07 | Hostの期待`nonce`が未指定 | **拒否** |
| 08 | Hostの期待Agent公開鍵が未指定 | **拒否** |
| 09 | RootがendorseしたAgent鍵とHost事前期待鍵が異なる | **拒否** |
| 10 | `issuer_jwt_hash`を使うTerminal | **拒否**（初期PoCでは未サポート） |
| 11 | `cnf`を持つIntermediate型のTerminal | **拒否** |
| 12 | Terminal署名そのものを改ざん | **拒否** |
| 13 | 正常2hopに3つ目の要素を追加 | **拒否** |
| 14 | Hostの信頼Issuer鍵が違う | **拒否** |
| 15 | RootのMerchant権限制約を隠した後でTerminalを検証 | **拒否**。P1-1のFail Closed条件を維持 |

Rubyの研究コードは`AP2RootSDJWTResearch.verify_full_root!`と署名済SD-JWTの開示digest resolverを**P1-1から再利用**し、P1-2でTerminalを検証する。このリファクタリングの後に**P1-1全10件を回帰実行**している。

**コードの安全上の意味:** 有効な2hop正例をRubyが認証したこと、列挙した限定負例をrejectしたことは実測済み。**すべてのSD-JWT表現・あらゆるAP2認証コンテキストが安全に処理できることの証明ではない**。Hostが発行したnonceを消費する処理やTransaction ID/注文認可は実装されていない。

## 4. 技術的な要点と残る問題

- **Root `cnf.jwk` は署名済みのIssuer委任先鍵:** RubyはまずRootをHostが指定したIssuer鍵で検証し、その後の`cnf.jwk`でTerminal署名を検証した。**Issuerが正しく署名しただけでAgentアカウントが承認されたわけではない**ので、Hostに**期待Agent公開鍵**も指定させて一致させる（この研究の上乗せ方針）。
- **`sd_hash`の基準は元のwire:** Ruby `Digest::SHA256.digest(root_wire.b)` と公式Python `common.compute_sd_hash(parse_token(root))`が一致することを正例で確認。Disclosuresを省略または再直列化して別取引の根拠にしない。P1-2では`issuer_jwt_hash`を一律拒否。
- **`aud`/`nonce`が「ある」だけで成功させない:** Hostの非空の期待値がない場合は先に拒否する。署名済みTerminalに異なる`aud`や`nonce`を含む独立の正規署名負例でも拒否。**再利用防止はHostが原子的に管理する**（今回未検証）。
- **Rootの完全性:** P1-1が許可する`checkout.line_items`＋`checkout.allowed_merchants`の狭いIssuer layoutを継承。RootからMerchantのDisclosureを消した場合は、Root署名が有効でもRejected。未知の権限制約を全般的に発見できる主張ではない。
- **Clock:** RootとTerminalの`iat`/`exp`周りに**研究用の厳格な有限値**を導入。数字は正式AP2共通ルールやHost運用で妥当と確定したものではない。テスト実行後のfixtureの長期保存・リプレイ受理に利用しない。

**未実証項目:** `checkout_jwt`のMerchant署名・保存された正本JWTとの**バイト列完全一致**・`checkout_hash`の独立再計算・AllowedMerchants/LineItemsを**現実の注文内容**で評価すること、Issuer失効・Agent資格・時刻境界/Clock Skew網羅、nonce消費/replay、Receiptの署名、resource limitの包括的セキュリティ検査、上流2件の公式pytest失敗解消、AP2相互運用の広いSDK/Issuer網羅。

## 5. 再現手順

本リポジトリの研究ソースで再実行できる。実際のテスト中に商用Merchantなどへの通信はせず、上流/AP2やPython/Rubyの依存取得時にはネットワークを使用する。固定ソースCommitが再現性の基準。

```bash
git clone https://github.com/google-agentic-commerce/AP2.git /tmp/ap2-p1-2
git -C /tmp/ap2-p1-2 checkout --detach b4587ac1d055888a73b4b21750973cffba961793
test "$(git -C /tmp/ap2-p1-2 rev-parse HEAD)" = "b4587ac1d055888a73b4b21750973cffba961793"

# P1-2 test repoのrootにて (Python3.11とRuby3.3の隔離環境想定)
(cd /tmp/ap2-p1-2 && python -m pip install --index-url https://pypi.org/simple -e .)
gem install jwt -v 3.3.0 --no-document

# Python SDKでIssuer/Agentの鍵をメモリ上に生成し、2hopを署名・Pythonでも認証
python research/p1_2/generate_two_hop_python.py /tmp/ap2-p1-2-fixture.json
python research/p1_1/generate_python_sdjwt.py /tmp/ap2-p1-1-fixture.json

# Root P1-1回帰とTerminal P1-2を別々に実行
AP2_P11_FIXTURES=/tmp/ap2-p1-1-fixture.json ruby research/p1_1/test_ruby_root_sdjwt.rb --verbose
AP2_P12_FIXTURES=/tmp/ap2-p1-2-fixture.json ruby research/p1_2/test_ruby_two_hop.rb --verbose
```

**研究用コードは汎用`AP2::Verifier`ではない。** 不完全な実装をGemやRailsアプリへ移植しないこと。生成したJSON Fixtureは秘密鍵を含まないが、実サービス情報も含まず、`/tmp`上の検証後は消去できる。

## 6. P1-2完了判断と次の1タスク

- [x] 公式Python SDKの署名付き**Open→Closed 2hopを発行・検証**。
- [x] RubyでRoot Issuer署名、Full Disclosure、Root endorsed `cnf.jwk`、Agent Terminal署名、`sd_hash`、Host `aud`/`nonce`を検証。
- [x] wrong agent、wrong root hash、aud/nonce mismatch・missing、3hop/intermediate、制約非開示、署名改ざんを拒否。
- [x] P1-1 Root検証**10/10回帰成功**。
- [ ] **Merchant-signed Checkout JWTの統合信頼・取引制約・replay/Receipt**は未実装・未検証。

**判断：P1-2研究はPASS。非本番Ruby PoCのCONDITIONAL GOを継続、汎用Gem/API/リリースはHOLD、production/実決済はNO-GO。**

**次の1件（別途承認後のみ）：P1-3 — Hostが保持するMerchant署名済みCheckout JWTを、Closed `checkout_jwt` の原文と`checkout_hash`に結び付け、Open `allowed_merchants`/`line_items`と取引を比較するオフラインRuby統合Spike。** Host状態/実決済/nonce消費・Receiptはまだ実装せず、Gem/API公開も行わない。
