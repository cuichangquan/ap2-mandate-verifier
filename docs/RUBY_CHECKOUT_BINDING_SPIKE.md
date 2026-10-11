# Ruby Merchant Checkout Binding Spike — Phase 1 / P1-3

**実行日:** 2026-10-11 JST  
**状態:** **P1-3 PASS（厳格な架空Checkout 1商品/単一店舗に限定した研究Spike）**。**汎用Gem・正式API・本番Verifierは未実装。実決済、nonce消費、Replay防止、Receiptも未実装。**  
**固定版:** [AP2 v0.2.0 `b4587ac1d055888a73b4b21750973cffba961793`](https://github.com/google-agentic-commerce/AP2/tree/b4587ac1d055888a73b4b21750973cffba961793)。公式SDKのRoot/Terminalを実行し、Merchant JWTはPythonの`jwcrypto`で**実際のES256 JWSとして署名**した。  
**実測正本:** [GitHub Actions run #38126247946](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38126247946) / [研究用Ruby verifier](../research/p1_3/checkout_binding_research.rb) / [18ケースのRubyテスト](../research/p1_3/test_checkout_binding.rb) / [公式SDK連携Python生成器](../research/p1_3/generate_merchant_checkout.py) / [CI](../.github/workflows/p1-3-checkout-binding.yml)。

## 1. 今回の狙い

[P1-2](RUBY_DELEGATION_SPIKE.md)でRubyのRoot→Terminal暗号Bindingを実証したが、ClosedのCheckout JWTが**署名部分 `NOT_A_SIGNATURE` のダミー**だった。P1-3では**署名済みの正本Checkout JWT**をHostから受け取り、そのJWTがRootの制約とTerminalの取引に合致するかを狭いRuby研究コードで確認した。

```text
Hostの信頼済み入力:
  trusted Issuer JWK       trusted Agent JWK
  trusted Merchant JWK     signed Checkout JWT原文の正本
  expected Checkout ID     expected Merchant ID
  expected currency/total  expected aud/nonce
                  |
                  v
  Issuer Open Root SD-JWT => Agent Closed Terminal KB-SD-JWT
     [P1-1] Root issuer signature + required disclosures
     [P1-2] Terminal Agent signature + cnf.jwk + sd_hash + aud/nonce
     [P1-3] Closed checkout_jwt == Host正本（バイト比較）
            Closed checkout_hash == SHA256(Host正本JWT文字列) base64url
            Merchant ES256 signature verified by Host's trusted Merchant JWK
            signed Checkout ID / Merchant / Currency / Amount
            Root allowed_merchants / line_items / Quantity
                  |
                  v
          CHECKED RESEARCH FACTS ONLY
            NOT Host purchase ALLOW
```

**本OSSのHost policy（AP2全体のMUSTではない）:** 単一Agent・2-hop・1店舗・1商品行・1許可SKU・数量完全一致・tax/discountなし・subtotal=totalの架空取引だけを許可する。その他は、制約の一般的解釈が未実装なので**拒否する**。

## 2. 実行環境・再現可能性

| 項目 | 証拠・留保 |
| --- | --- |
| 実行場所 | [GitHub Actions #38126247946](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38126247946) / GitHub-hosted Ubuntu 24.04 |
| 実行系 | **Ruby 3.3.12**、`jwt 3.3.0`、Ruby標準のDigest/JSON/Base64。Python **3.11.17** |
| 固定SDK | 公式AP2のSHA `b4587ac1d055888a73b4b21750973cffba961793` をcloneしてHEADをassert。Python `MandateClient.create`/ `kb_sd_jwt.create`、`verify_chain`、公式Checkoutモデル・Constraint evaluatorを使用 |
| Python依存 | 上流`uv.lock`がprivate registryでHTTP 401になるため、`pyproject.toml`の**直接依存version pins**を公開PyPIからインストール。**推移的依存lockの完全再現ではない** |
| Merchant Checkout JWT | Python `jwcrypto.jws.JWS` が**独立したMerchant秘密鍵（P-256）**でCheckout JSONをES256署名。RubyはHost指定Merchant公開JWKで検証 |
| 署名鍵の扱い | Issuer/Agent/Merchant鍵はCI実行中に生成。fixtureには**公開JWKと署名トークンのみ**。Issuer・Agent・Merchant秘密鍵はGitHub Commit/Artifactには保存しない |
| P1-3本体 | **18 runs / 40 assertions / 0 failures / 0 errors / 0 skips** |
| P1-2回帰 | **15 runs / 32 assertions / 0 failures / 0 errors / 0 skips** |
| P1-1回帰 | **10 runs / 22 assertions / 0 failures / 0 errors / 0 skips** |
| Artifact | [CIログ・依存一覧](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38126247946/artifacts/11697257533)（保持期限7日）。テスト/生成器はリポジトリに継続保存 |
| 実行費用 | GCP VM/Cloud Run・実決済なし。GitHub Actionsとソース/依存取得のみ。検証後CIは**手動起動専用**へ変更 |

**実行記録を誇張しない:** P1-3は最初の2回に研究コード/fixtureの前提ミスで失敗し、最終Run #38126247946で全件成功。失敗も次節に記録した。以前の上流公式Python pytest **186 PASS / 2 FAIL**は別の調査結果（[P0-5a](PYTHON_BASELINE_VERIFICATION.md)）であり、今回再実行していない。

## 3. 新規Ruby 18テスト（最終CIで全成功）

| Case | 入力 | 実測判定 |
| --- | --- | --- |
| 01 | RootとTerminalが有効。Host正本のMerchant署名済JWT・Hash・ID・Merchant・SKU・数量・総額一致 | **受理（研究用検証事実のみ）** |
| 02 | Agent署名が正しいClosed内の`checkout_hash`だけ誤り | **拒否** |
| 03 | Agent署名が正しいClosed内の`checkout_hash`欠落（空文字） | **拒否** |
| 04 | Merchant署名は有効、CheckoutのMerchant IDがRootの許可外 | **拒否** |
| 05 | Merchant署名は有効、Checkout SKUがRootの許可外 | **拒否** |
| 06 | Merchant署名は有効、Checkout数量1だがRootの必要数量2 | **拒否**（PoC厳格化） |
| 07 | 必要商品が存在していても、**余計な商品行を追加** | **拒否**（PoCの1商品限定） |
| 08 | 署名済Checkoutの合計金額と商品の価格×数量が一致しない | **拒否** |
| 09 | Checkoutの状態が`completed`（今回の`ready_for_complete`以外） | **拒否** |
| 10 | 正しいCheckoutでも**別のMerchant鍵で署名** | **拒否** |
| 11 | HostがCheckout正本JWTを提供していない | **拒否** |
| 12 | Host正本は**別の正しくMerchant署名されたJWT** | **原文不一致を拒否** |
| 13 | Hostが信頼するMerchant鍵を提供していない | **拒否** |
| 14 | HostがMerchantの別公開鍵を指定 | **拒否** |
| 15 | Hostが期待Checkout IDを間違えて指定 | **拒否** |
| 16 | Hostが期待Merchant IDを間違えて指定 | **拒否** |
| 17 | Hostが期待通貨を間違えて指定 | **拒否** |
| 18 | Hostが期待する取引金額を間違えて指定 | **拒否** |

**負例カバレッジの注意（最終Runで修正済み）:** 不許可Merchant/SKU/数量/追加商品/誤合計/状態と不正Merchant鍵の各fixtureには、**そのClosedが参照する同一のMerchant署名済JWT**をHost正本として渡す。以前は正本JWTの不一致によって先に拒否され、個別の業務ルールまで到達していなかった。修正版[Actions #38126247946](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38126247946)ではその短絡を避け、18件すべてPASSした。

**重要:** 署名が有効なCheckoutだから購入可、にはしない。Host鍵の信頼とaccount/注文status/replayの取り扱いはHost側。Ruby研究コードの戻り値は`checkout_id`、`merchant_id`、`checkout_sha256`、`amount_minor`で、`payment_approved`を意味しない。

## 4. 実行中に明らかになった差分と修正

### A. 公式Python SDKの数量判定は今回の厳格ルールとは異なる

最初のActions [run #38125810324](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38125810324) で、公式`check_checkout_constraints`が**必要数量2に対する購入数量1**のCheckoutに対し**違反なし**を返すことを観測。研究テスト生成器が「必ず違反になる」と仮定したassertionが落ちた。

- 該当ソース：[Checkout制約評価](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/constraints.py#L407-L419) と同ファイル`evaluate_line_items_max_flow`を参照。
- **これだけで公式SDKが仕様違反/脆弱性であるとは断言しない。** 数量`quantity`の解釈（最大/必要・allocationなど）と本OSSの厳格な数量一致は異なる可能性がある。
- 本研究は独立に**Rootの必要数量とCheckout数量が完全一致しない場合は拒否**する。これはAP2全体のMUSTの一般的主張ではない。

### B. 同一内容を2回ES256署名したJWTは同じ文字列とは限らない

2回目のActions [run #38125862595](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38125862595) で、P1-1は10 PASS、P1-2は15 PASS、P1-3は**18 runs / 35 assertions / 0 failures / 1 error**。正常系のJWTを同じCheckout内容から**別々に2回署名**しており、原文JWTのバイト列が異なったため厳密比較でエラーになった。

- 対処：Host正本の **同じ署名済JWT文字列をClosedにそのまま入れる**。payloadのJSONが同一でも「同じJWT」とは判定しない。
- 最新のrunでP1-3 **18 PASS**を確認。この差分は`checkout_hash`が**JWT原文に対するHash**である理由も説明している。

## 5. 未実証・危険な一般化を避ける

- **今回のRoot/Terminalは研究用の厳格な単一Issuer layout、Open→Closedちょうど2-hopのみ**。未知/非開示Constraint、複数Agent、他`typ`/hash-mode、一般的なSD-JWTは対象外。P1-1でMerchant制約非開示を拒否する研究用strict profileを維持。
- **Hostが保持する「信頼できるMerchant JWK」の登録/ローテーション・Merchant IDとの結び付け**は、本研究コードではHostが正しく入力したと仮定。IssuerやCheckoutの自己申告鍵を自動信頼していない。
- **UCP Checkout Schemaの包括検証ではない**。Pythonで生成した架空Checkoutは公式Pydanticモデルに適合するが、Rubyは全UCP Schemaの網羅的評価を実装していない。Checkoutの過剰なJSONフィールド・重複JSONキー、マルチSKU、部分割引、税・送料、価格変更、複雑な合計はPoCで未対応／追加検証が必要。
- **nonce一度限りの原子的消費、replay、Merchant側の価格/在庫正本、Session/Buyer/Agent業務権限、Revocation、署名Receiptの発行**は未実装。取得できたのは局所的な暗号/制約/Hash Bindingだけ。
- Root/Terminalの期限処理、JWSの`crit`やunknown JOSE header、ログの情報漏えい、DoS/サイズ・深さ制限、変形入力は**本番利用前のセキュリティ設計と負例が必要**。
- P0-5aで確認した**公式pytestの中間hop `aud`/`nonce`失敗2件**は未解消。初期研究は中間hopを拒否し、最終/TerminalにHost期待値必須という境界で実験した。

## 6. 再現手順

ローカルでは依存取得時にネットワークが必要、テスト実行中は外部Checkout・決済サービス通信をしない。

```bash
git clone https://github.com/google-agentic-commerce/AP2.git /tmp/ap2-p1-3
git -C /tmp/ap2-p1-3 checkout --detach b4587ac1d055888a73b4b21750973cffba961793
test "$(git -C /tmp/ap2-p1-3 rev-parse HEAD)" = "b4587ac1d055888a73b4b21750973cffba961793"

# ap2-mandate-verifierのrootから。隔離Python 3.11、Ruby 3.3を想定
(cd /tmp/ap2-p1-3 && python -m pip install --index-url https://pypi.org/simple -e .)
gem install jwt -v 3.3.0 --no-document
python research/p1_3/generate_merchant_checkout.py /tmp/p1-3-checkout.json
AP2_P13_FIXTURES=/tmp/p1-3-checkout.json \
  ruby research/p1_3/test_checkout_binding.rb --verbose
```

**公式全テストのPASSを意味しない。** 固定AP2 Python SDKはChain発行・真正署名・Checkout型確認に利用し、Rubyの厳格なCheckout比較コードの結果は自作研究テストのassertionである。

## 7. 次の優先タスクと判定

- [x] **P1-3オフライン研究テスト：18 PASS / 40 assertions、失敗0**。
- [x] P1-1/2の共有ライブラリ化後も **Root 10 PASS、2hop 15 PASS**。
- [x] Merchant署名・Host JWT原文・closed hash・Open Merchant/SKU/数量・価格合計に対する狭い正負が成立。
- [ ] **実注文Host業務認可、nonce replay、revocation、Receipt、Gem本体・公開API・本番安全性**は未検証。

**判断:** 限定研究PoCは**CONDITIONAL GOを継続**。汎用AP2 Ruby Gem/公開API/リリースは**HOLD**、実決済とProductionは**NO-GO**。P1-3が通っただけでは、本番で購入を許可できない。

**次の1件（改めてユーザーが承認した時のみ）:** **P1-4 — 固定済みP1-1〜P1-3研究コードの設計・セキュリティ負債レビューと、Gem開発に進むかのGO/HOLD再判定（文書作成のみ）**。重複JSONキー、SD-JWT未開示制約の一般化、JOSE Header、Expired Terminal、JWT/Checkout max size、Host Trust・nonce atomic replayなどを含め、必要な負例と未達事項を表にして優先順位を付ける。**Gem実装や本番統合には自動的に進まない。**
