# Phase 2-A / DC01 — 独立署名付き正常例の実測準備

**2026-10-12 JST / Issue [#47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) / RESEARCH ONLY / NOT A GEM / GO NOT GRANTED**

> **初期判定: PREPARED / NOT RUN。** 本ブランチのCI結果を確認するまでDC01成功を主張しない。DC02–DC05は全件NOT RUN、Phase 2-B実装・公開Gem/API・本番Host・決済・HC06は引き続きHOLD/NO-GO。

## 狙い・対象

[PR #49で確定したDC01–DC05の独立オラクル実験計画](PHASE2A_DC01_DC05_SIGNED_ORACLE_PLAN.md)に基づき、**最初の署名付き正常例 DC01だけ**に対象を限定する。公式 AP2 v0.2.0固定commit `b4587ac1d055888a73b4b21750973cffba961793` と既存の[合成fixture発行器](../research/p1_3/generate_merchant_checkout.py)を使用する。Issuer・Agent・Merchantの**鍵は一時メモリ生成**、Hostは合成値、決済なし。既存のRuby研究コードを改造して受理範囲を広げない。

| オラクル | DC01の新しい試験内容 | 範囲 |
| --- | --- | --- |
| O1 | 独立 `jwcrypto` で**元Root JWS**のES256署名・Host固定Issuer公開鍵・strict JOSE JSON | 正しい署名だけでは隠し権限制約の不存在は証明できない |
| O2 | Rootの`cnf.jwk`で**Terminal JWS**を署名検証、`sd_hash`・期待aud/nonceとHost Merchant JWS原文/hash照合 | Agent/Checkoutの限定技術確認。Host nonce CASや決済ALLOWはしない |
| O3 | 署名済みRootの**最上位JWT payloadから**`_sd`／配列placeholderを独立・非破壊に全走査、Disclosure digestの一対一消費と残余0を確認 | SDK resolved payloadやRuby resolverを根拠に流用しない。今回の合成レイアウトだけ |
| O4 | pinned公式Open JSON Schema（`types/merchant.json`含む）＋Host側単一Issuer/2constraint/単一Merchant・SKU profile検証 | 公式Schema VALIDとローカル制限を区別 |
| O5 | **既存** `AP2CheckoutBindingResearch.verify!` を署名済み同一fixtureで実行、Checkout ID/Merchant/金額とEvidence-onlyを確認 | Phase 2-Bの正式契約ではない。O3の内部実装保証はしない |

## CIとリプレイ手順（計画）

1. [専用Workflow](../.github/workflows/phase2a-dc01-signed-feasibility.yml) が読み取り権限のみで固定AP2 SHAをCheckoutし、公式PyPIの直接依存＋`jsonschema==4.26.0`、Ruby `jwt==3.3.0` を使用。上流 `uv.lock` はprivate registry依存があるため**推移的依存の完全固定ではない**。
2. [独立Pythonオラクル](../research/phase2a_dc01/independent_positive_oracle.py) がO1–O4を、[Ruby比較器](../research/phase2a_dc01/compare_existing_ruby.rb) がO5を観測し、報告JSONへ分離記録。どちらも既存の研究Verifierを汎用・安全な新APIとみなさない。
3. 一時的なCI artifactへ**合成signed-wireの正確な原文**（Issuer JWS、全開示原文・順序、Root SD-JWT、Terminal JWS、Merchant JWS、2hop連結chain）、公開JWK、Host合成期待値、manifest内SHA256/サイズ、出力と依存バージョンを保存。秘密鍵・実情報は保存・コミット禁止。artifact保持は**7日間**なので、これだけでは恒久的独立再検証証拠にならない。必要ならレビュー後に合成の公開鍵専用fixtureを別PRで固定する。
4. CI・Codexレビュー・issueとHEADの整合を確認。緑色のCIは**限定DC01の正常署名観測**であり、隠し制約拒否（DC02–DC05）、Host業務許可、実Issuer適合、Phase 2-B GOを意味しない。

## 判定基準

- Python O1–O4のどれかが失敗、公式SDKでサポート可能なDC01正例の形を生成できない、Ruby O5が失敗、証拠が不足すれば **RED/BLOCKED/HOLD** を記録。ツール失敗・インストール失敗をセキュリティPASSと呼ばない。
- 真正署名と全signed-wire commitment消費、公式Schema＋単一profile、Ruby限定Evidence-onlyがすべて実行された場合のみ `LIMITED_DC01_OBSERVED` 候補。**CI artifactの短い有効期限を明記**し、恒久証拠と区別する。
- Issuer profileの現実世界の信頼認可、nonce再利用、失効、Receipt、実決済を扱わず、**Issue #47はDC02–DC05を含む独立検証までOPEN**。

**現時点の実測:** DC01は **NOT RUN（PR作成時点）**。結果が得られたら固定SHA・CI URL・出力・未達事項を追記する。
