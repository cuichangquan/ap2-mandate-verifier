# Phase 2-A / DC02 — Issuer真正署名のMerchant制約を部分非開示にする独立研究

**2026-10-12 JST / [Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) / research-only / no payments / no production Gem**

> **開始時状態：PREPARED / NOT RUN。** 本文中の「期待値」は新CIの実測で代替せず、Actionsの実行・ログ・CodexレビューとPR HEADを確認するまで安全性PASSを主張しない。DC03–DC05はNOT RUN、Phase 2-B・公開Gem/API・本番Host/失効/実決済/HC06は引き続きHOLD/NO-GO。

## なぜDC02をやるか

[DC01の正常合成署名実測](PHASE2A_DC01_OBSERVATION.md)が成功した一方、**Issuerが署名でcommitした非開示のMerchant制約**を無視してはいけない。今回のDC02では、公式AP2固定 `b4587ac1d055888a73b4b21750973cffba961793` の `MandateClient.create` でIssuer真正署名Rootを作り、**`checkout.allowed_merchants`に対応した一個のDisclosureだけ**を提示から除く。署名済みIssuer JWT原文は両提示で一致させる。

変更後のRootに合わせてAgentが **Terminalを別々に真正署名**し、それぞれの `sd_hash` を検証する。Merchantの署名済みCheckout JWTとHost想定ID/金額は同じデータで固定。署名不正・`sd_hash`不整合・公式Schema INVALIDが原因の拒否を安全性PASSに数えない。

## オラクルと予定する期待値

| 検証器 | 完全提示の対照 | Merchant制約の非開示提示 |
| --- | --- | --- |
| O1 Issuer真正署名 | ES256 PASS | **同じIssuer署名原文でES256 PASS** |
| O2 Agent/Checkout真正署名 | Agent ES256・`sd_hash`・aud/nonce・Merchant JWT/hashすべてPASS | **Agent再署名により全条件PASS** |
| O3 独立signed-wire完全性 | 署名Rootの最上位からcommitmentを全走査、2個マッチ・未解決0 | **`$/delegate_payload/0/disclosed/constraints/1`のdigestだけ未開示、`incomplete_disclosure`で拒否** |
| O4 pinned公式Schemaとローカルprofile | 公式Schema VALID / profile対象2 constraint | **公式SchemaはVALIDになり得るが、固定Issuer profileは権限不完全としてREJECT** |
| O5 Ruby研究Verifier | 限定正常例 `LIMITED_POSITIVE`、業務ALLOWなし | **`missing disclosure` の明確な理由でREJECT** |

ここでいうO3の独立検査は、公式SDKのresolved payloadではなく、**Issuer署名済みRoot JWTの生payloadにあるすべてのcommitmentと、Disclosure原文のSHA256 digest対応**から出す。DC01で設計した許可path/kindの制限も維持する。O4の公式Schemaは提示に見えるConstraintを検査するだけであり、**Schema VALIDでもMerchant権限が完全に可視とは限らない**。

## 実行範囲と証拠

- [独立Python生成＋観測](../research/phase2a_dc02/generate_and_observe.py)、[Ruby既存研究コード比較](../research/phase2a_dc02/observe_ruby.rb)、[read-only専用Actions](../.github/workflows/phase2a-dc02-hidden-merchant.yml)。新たなGem/APIや決済・ネットワークHostは作らない。
- CIでは固定AP2 SHA・Ruby 3.3・`jwt 3.3.0`、固定Python直接依存＋`jsonschema==4.26.0` を使用。`uv.lock`のprivate registry依存により**推移的lock完全再現は未達**。実行依存をfreezeして記録する。
- 完全/隠蔽提示の**Issuer JWS・各Disclosureと順序・Root SD-JWT・Agent Terminal JWS/SD-JWT・Merchant JWT・2hop連結chain**および公開JWK、合成Host期待値、Python/Ruby個別観測、依存freeze・上流/研究SHAを保存。すべて生成後にSHA256/byte_length付きmanifestを作り照合する。**秘密鍵/実Checkout/本物のトークンは保存しない。** Actions artifactは**7日限定**であり恒久の公開リプレイfixtureではない。
- 完全提示が正常成功、非開示の方もO1/O2が**有効な真の署名**、O3が本当にIssuer-signed未解決Merchant digestを特定、O4がSchemaとprofileを区別、Rubyが事前指定した `missing disclosure` でREJECTして初めて**限定DC02 POSITIVE SECURITY OBSERVATION**。例外や他原因で拒否した場合はBLOCKED/FAIL/HOLD。
- DC02実測でIssue #47が全完了にはならない。署名付き未知path負例、DC03〜DC05、Host CAS/Checkout現行性、HC06、汎用Issuerの相互運用は未証明。

**実測欄（PR作成時点）:** DC02 NOT RUN、専用CI/レビュー結果は未確認。実行後は実際のrun URL/HEAD SHA/ログ/残課題を追記する。
