# Phase 2-A / DC02 — Issuer真正署名のMerchant制約を部分非開示にする独立研究

**2026-10-12 JST / [Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) / research-only / no payments / no production Gem**

> **実測判定：LIMITED_DC02_OBSERVED（合成署名・固定Issuerレイアウト限定）。** 専用Actionsが成功し、Issuer/Agent/Merchantの真正署名が両提示で成立、公式Schemaも両提示でVALID、Merchant権限commitmentだけが未解決となり、既存Ruby研究Verifierが`missing disclosure`で拒否することを観測。**Codexレビューと最新HEADのマージ判断は別途必要。**DC03–DC05はNOT RUN、Phase 2-B・公開Gem/API・本番Host/失効/実決済/HC06は引き続きHOLD/NO-GO。

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

## 実測結果（2026-10-12 / 初回HEAD）

- **[GitHub Actions #38256150327](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38256150327)：SUCCESS、1 job成功、初回HEAD `a1128de5b98821ceecddf383d0b11fd6f4b0797c`**。
- Pythonログ：`Issuer, Agent and Merchant signatures VALID for both full and hidden presentations`、`signed Merchant constraint digest OMITTED; independent completeness REJECT`、`official Open Schema VALID for both; local fixed Issuer profile REJECT for hidden`。公式AP2の`verify_chain`も**完全・非開示の両提示**で成立。すなわち**非開示側の拒否はIssuer/Agent署名不正やstale `sd_hash`、Schema INVALIDによるものではない**。
- 既存Ruby研究Verifier `AP2CheckoutBindingResearch.verify!`：完全開示の対照は**限定正常成功**（業務ALLOWなし）、Merchant制約非開示側は **`missing disclosure` によるREJECT**。異なる理由で拒否されてもCIを成功させない設計。CIログのMinitest `0 runs / 0 assertions` はRubyスクリプトの自動runner表示であり、実測は明示的なRubyメソッド呼出と確認文によるもの。
- 署名済みRoot JWS原文は全開示・部分提示で一致。Issuer署名済み`allowed_merchants` disclosureだけ非提示にし、Agent Terminalは各Rootに合わせ真正再署名。O3は元JWT生wireから入れ子placeholderを識別し、Merchant制約の未解決digestを確認。**O4公式Open Schemaは両方VALID**である一方、固定Issuer権限完全性profileは部分提示をREJECT。
- 合成の署名原文・全Disclosureと順序・2hop chain・公開JWK・Host合成期待値・Python/Rubyの観測JSON・依存freeze・AP2 SHAと研究HEADを**生成後の`evidence-manifest.json`でSHA256/バイト長検証**。Artifact名`phase2a-dc02-synthetic-public-replay`、ID `11749877904`、約19.7KB、**2026-10-19 13:30 UTCに期限切れ**。恒久的リプレイ保存は未実施。
- Pythonは固定公式依存の直接pin＋`jsonschema==4.26.0`、Rubyは`jwt==3.3.0`。`uv.lock` private registryにより**transitive full lock再現はしていない**。

**重要な残課題:** これは**既存Ruby研究コードの固定Issuer2hop/1 Merchant/1 SKUに限った負例**。署名付き未知pathの拒否、DC03〜DC05、隠れた権限全一般形・実Issuer・Host nonce/Checkout現行性・HC06/失効/決済は未保証。**Issue #47はOPEN、Phase 2-B/Gem/API/本番はHOLD**。PR #51のCodexレビュー未完了ならマージしない。

