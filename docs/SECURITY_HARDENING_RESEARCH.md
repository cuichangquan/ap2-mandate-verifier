# Security Hardening Research — P1-6: six signed RED cases closed

**実測日:** 2026-10-11 JST  
**結論:** 固定AP2 v0.2の**厳格な非本番・研究用サブセット**において、[P1-5](SECURITY_NEGATIVE_TESTS.md)で観測した**6件の想定外受理（RED）をすべて拒否へ変更**し、既存43件の回帰を維持した。**正式AP2 Verifier/Gem/APIではない。公開・Production・実決済はNO-GO、汎用Gem実装もHOLD継続。**  
**一次証拠:** [Actions #38128152237](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38128152237) / [Artifact（7日間）](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38128152237/artifacts/11698235534) / [署名付きPython負例fixture生成器](../research/p1_5/generate_signed_negatives.py) / [Ruby負例観測器](../research/p1_5/observe_security_negatives.rb) / [CI](../.github/workflows/p1-6-hardening.yml)。

## 1. 同じ18ケースで再実測した結果

| 分類 | P1-5（修正前） | **P1-6（修正後）** |
| --- | ---: | ---: |
| **GREEN（期待動作）** | 11（正例1＋拒否10） | **17（正例1＋拒否16）** |
| **RED（想定外ACCEPTED）** | **6** | **0** |
| **HOST_BOUNDARY（nonce再利用はHost責務）** | 1 | **1（未実装のまま）** |
| **ERROR（想定外例外）** | 0 | **0** |
| 計 | 18 | **18** |

全18ケースのうち、N00は**正常な署名付き架空取引の受理**、N01〜N16は**拒否**、N17は**同じ有効な署名/nonceを2回独立検証すると2回受理する**というstateless研究コードの責務境界。**N17はReplay対策PASSではない**。

**回帰テスト:** P1-1 **10 runs/22 assertions**、P1-2 **15 runs/32 assertions**、P1-3 **18 runs/40 assertions**、全て**0 failures / 0 errors / 0 skips**。合計43件。**6 REDを修正後も正規のRoot/Terminal/Merchant署名が検証できること**を確認した。

## 2. 6 REDの最小修正と検証した境界

| ID | P1-5の想定外受理 | P1-6修正箇所・確認 | 最新判定 |
| --- | --- | --- | --- |
| N01 | ES256 Merchant署名済JSONで`merchant.id`の重複 | [厳格JSON Parser](../research/shared/strict_json_research.rb)を導入し、Merchant JWS **元payloadバイト**からネストした重複objectキーを検出。JWT署名自体もこれまでどおりHost信頼鍵で検証 | **GREEN / REJECTED** |
| N02 | Merchant JWTの署名済protected headerで`alg`が二重指定 | 同じParserで**元JOSE headerバイト**のキー重複を拒否。署名対象のcompact JWS文字列を変更せずES256 allowlistを継続 | **GREEN / REJECTED** |
| N03 | 期限切れ**Closed Mandate内部**`exp`（Outer terminalは現在） | [Two-hop研究コード](../research/p1_2/two_hop_research.rb)でClosed内部`iat`/`exp`を別途検証。Host現在時刻とRoot期限内、研究用TTL上限を要求 | **GREEN / REJECTED** |
| N04 | **Closed内部**`iat`が未来 | 同じClosed時刻検査で、outer`iat`の新鮮さとは独立に未来`iat`を拒否 | **GREEN / REJECTED** |
| N05 | Merchant JWT header `typ=unexpected+jwt` | [Checkout研究コード](../research/p1_3/checkout_binding_research.rb)で**研究用Strict Profileの`typ=JWT`のみ受理**。これは全AP2実装の一般規則を主張しない | **GREEN / REJECTED** |
| N07 | 正しいMerchant署名のCheckoutに未知の権限関連フィールド追加 | 1店舗/1SKU/税なしの**研究用既知JSON fieldsをallowlist**。Checkout・Merchant・商品行・Item・Totalsで追加/欠落フィールドをReject（一般UCP Schemaを実装したのではない） | **GREEN / REJECTED** |

**影響範囲:** 研究コード`research/p1_1/root_sdjwt_research.rb`、`research/p1_2/two_hop_research.rb`、`research/p1_3/checkout_binding_research.rb`と新規`research/shared/strict_json_research.rb`のみ。**Gem雛形/公開API/Hostアプリは作成していない。**

**署名と原文:** JWT payloadを正規化・書き換えて署名検証する方法ではなく、**元の署名されたcompact JWSのheader/payloadを曖昧さ検査**し、元のcompact bytesをJWT署名検証・Host正本照合・Closedの`checkout_hash`比較に使用した。Issuer Root、Agent Terminal、Merchant JWTそれぞれ既存のHost指定JWK/署名検証を継続。

## 3. 実行環境・手動再現

| 項目 | 実測 |
| --- | --- |
| GitHub Actions | [run #38128152237](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38128152237) / Ubuntu 24.04 |
| Ruby | **3.3.12**, `jwt 3.3.0`; Ruby JSON/Base64/Digest標準ライブラリ |
| Python | 3.11 / 公式AP2 `v0.2.0`固定Commit `b4587ac1d055888a73b4b21750973cffba961793` + jwcrypto |
| Python dependencies | 公式`pyproject.toml`の直接依存pinsを公開PyPIから導入。プライベートindexに依存する上流`uv.lock`の**完全再現ではない** |
| 秘密鍵 | 架空Issuer/Agent/Merchant用に実行時だけP-256鍵を生成。Git/Artifactに秘密鍵を保存しない |
| CI | **17 GREEN / 0 RED / 0 ERROR / 1 HOST_BOUNDARY**と**過去43テスト成功**が同一Runで確定 |
| Runner費用 | GCP/Cloud Run/実決済なし。GitHub-hosted CIとSDK/依存ダウンロードのみ。成功確認後は**workflow_dispatch手動起動専用**に変更 |

再実行は上記[CIワークフロー](../.github/workflows/p1-6-hardening.yml)を手動実行する。署名済テストFixtureはランナー内で都度生成され、Private Keysは実行外へ持ち出さないため、**wireが毎回固定になるわけではない**。固定なのは公式SDKのcommitとテスト判定条件。

## 4. 残っている安全上の阻害条件

今回のGREENは、P1-5で選んだ18ケースの**狭い実行範囲に限る**。次の要件は依然未証明・未実装。

1. **Host信頼登録:** Issuer ID、Merchant ID、Buyer/Agent IDと公開鍵の現実の対応付け、鍵ローテーション・失効・正本Checkout/価格/在庫の維持。
2. **Nonce再利用防止:** N17は両方ACCEPTED。Hostによる一度限り・**原子的consume**、Checkout session、重複注文抑止、Idempotencyは別責務。**検証器の署名照合成功だけでは購入ALLOWにしない**。
3. **SD-JWT一般化:** Object disclosure、decoy digest、別Issuerレイアウト、未知Authority、複雑な商品制約や3hop以上は非対応・未検証。Issuerが単に必要権限を発行しなかったかまで推論できない。
4. **Parsingの広い脅威面:** 重複JSONキー/非canonical Base64の一部を厳格化したが、深いJSON/極端な巨大内部構造・Unicode・異常HTTP data、全JOSE header/全部のJWK形式/curve、例外を含むHostのfail-closed契約は**未網羅**。
5. **Timeの広い脅威面:** Root/Terminal/Closedの時刻を研究用に検証しても、**Host時計注入/clock skew/境界・期限切れのトランザクション正本・失効**は未設計。固定300秒/7200秒はAP2一般MUSTではなく、研究用policy。
6. **Receipt・最終認可:** Signed Checkout Receipt、revoke、取引前業務許可、実決済、監査／プライバシー運用はまだない。ProductionはNO-GO。

参考：[P1-4ゲート](SECURITY_GAP_REVIEW.md) G1〜G6。**G1〜G5すべてを満たしたと主張しない**。修正済み6 REDの存在と未実装責務は異なる状態である。

## 5. GO / HOLD判定と次の1件

| 範囲 | P1-6後の判断 |
| --- | --- |
| 固定AP2 Python SDK / Rubyの限定オフライン研究 | **CONDITIONAL GO**。ただしサポート済みサブセットのみ |
| P1-5の**6 RED再発防止** | **今回の18ケースではGREEN化実証済み** |
| 汎用AP2 Ruby Gem/公開APIの実装 | **HOLD継続**：Host trust契約、G1〜G5の未証明事項あり |
| RubyGems公開・実決済・Production | **NO-GO継続** |
| Host replay・Receipt・業務認可 | **未実装**。Gemが安全性を代行したと主張しない |

**次のおすすめ1件（ユーザーから別途明示依頼後のみ）：P1-7 — Host Trust/Nonce/VerifiedEvidence責務を中心に、安全境界の契約を具体化する「設計・テスト計画のみ」のStep。** Issuer/Buyer/Agent/MerchantのHost信頼入力の必須性、nonce atomic consumeの責務と障害時STOP、VerifiedEvidence ≠ ALLOW、Clock injected policy、失効とCheckout正本/Receiptを切り分けた設計。**Gem実装やHost永続状態・実決済の実装、GCPへの展開は行わない。**
