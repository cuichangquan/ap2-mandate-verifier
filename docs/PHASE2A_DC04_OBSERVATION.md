# Phase 2-A DC04 — 個別 Merchant / SKU 配列要素の署名付き非開示検証

**2026-10-12 JST / [Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) / RESEARCH ONLY / 合成公開鍵fixture / Phase 2-B HOLD**

> **実測結果：O1–O4 限定成功 / O5 Ruby制限でRED/HOLD（DC04未合格）**。DC04の合格には**Issuerが署名した全開示の正常例をRuby研究Verifierが受け入れ**、かつ同じRoot JWSから**単一配列要素だけを隠した真正署名付き2ケースを `missing disclosure` の理由で拒否**することが必須。完全開示も拒否するなら、異常例を拒否していても **DC04 RED/HOLD** とする。

## 検証対象と設計上の要点

公式AP2 v0.2.0 commit `b4587ac1d055888a73b4b21750973cffba961793` の `DisclosureMetadata.array_children` と `sd_array_indices=[0]` を用いて、全体のConstraintではなく**配列要素だけ**をIssuerに署名してもらう。Openに`checkout.line_items` 1件（要件`items[0]`、`acceptable_items[0]`のみ）と `checkout.allowed_merchants` 1件（`allowed[0]`のみ）を含め、署名済みRoot JWS原文を共通化する。

| 提示 | 元のIssuer署名JWS | 開示内容 | 正常性の期待 |
| --- | --- | --- | --- |
| **FULL** | 同一 | Root SD wrapper、Merchant[0]、SKU[0]をすべて開示 | 署名・Schema・固定profile・Ruby既存研究正常例がすべて成功 |
| **M0** | 同一 | Merchantの`allowed[0]`だけ省き、SKU[0]は開示 | Issuer/Agent/Merchant署名VALID、元のRoot上で`allowed/0`未解決、Ruby`missing disclosure` |
| **S0** | 同一 | SKUの`acceptable_items[0]`だけ省き、Merchant[0]は開示 | 同様に`acceptable_items/0`未解決を独立検出、Ruby`missing disclosure` |

**厳密なsigned-wire path:** FULLで3コミットメントだけ許可：`$/delegate_payload/0`、`$/delegate_payload/0/disclosed/constraints/1/allowed/0`、`$/delegate_payload/0/disclosed/constraints/0/items/0/acceptable_items/0`（全部`array`）。Root署名済みpayloadの**最上位から全path・nestedを走査**し、未知の `_sd` 等は拒否。Issuer / Agent / Merchantの署名は公開JWKで独立検証し、Terminalは各Root提示に合わせて**3種類別々に真正署名**、各 `sd_hash` / aud / nonce / Checkout JWT/hash照合を義務化する。

## O1–O5とゲートを明確に分ける

- **O1**：全3提示のIssuer公開鍵署名を検証、原署名JWSの一致を確認。
- **O2**：全3提示のAgent Terminalの独立署名とrootごとの`sd_hash`、固定aud/nonce、Merchant Checkout JWS、公式AP2 `verify_chain`を確認。
- **O3**：公式SDKのresolved dictに依存せずIssuer-signed raw graphからFULL残余0とM0/S0それぞれ**未解決1件だけ**を確認。無関係な制約を削除したり別のDisclosureを壊したfixtureはINVALIDとして中止。
- **O4**：**実際の各提示で解決されたOpen**をpinned公式JSON Schemaに別々に入力し、VALID/INVALIDとエラーvalidator/pathを保存。固定profileではM0/S0の単一Merchant/SKU要件に不一致なので拒否。**Schema/Cardinalityが原因の拒否のみなら完全性PASSではない**。
- **O5**：既存 `AP2CheckoutBindingResearch.verify!` にFULL/M0/S0を入力し結果・拒否理由・例外発生元をRuby `TracePoint` で記録。固定プロフィールでは**FULLがLIMITED_POSITIVEであることを先に要求**。正例を含め`unsupported array disclosure location`で拒否するなら、**安全ゲートはRED/HOLD**。これは仕様未対応の証拠であり、負例安全合格ではない。

### CIの「成功」と安全Gateは異なる

[専用GitHub Actions](../.github/workflows/phase2a-dc04-nested-elements.yml)は**観測を正確に報告できたか**を検証する研究用CI。3提示の合成署名原文・Disclosure順序・Terminals・Checkout JWS・Python/Ruby観測JSON・上流/実行HEAD・依存freezeのSHA256/サイズを`evidence-manifest.json`で記録する。**CIがGREENでも O5がRED/HOLDなら DC04は未完了**。

既存Ruby研究コードはRoot/Constraints階層のselective-disclosed arrayを想定しているが、`allowed[0]`/ `acceptable_items[0]` のネストされた配列Disclosureを許可しているとはまだ立証していない。**既存runtimeを本PRで拡張しない**。全開示が通らなければ、固定Issuer文法とRuby実装の対応付けを改めて設計・レビューする。

**制約:** 合成一時秘密鍵をgit/CI artifacts/ログへ絶対に置かない。実際の支払い・本物の認証/Checkout・GCP/有料Hostなし。公開JWKと真の合成署名原文だけをActions artifact（7日保持）に保存するため、恒久的な外部リプレイ証拠は別課題。公式SDK推移依存の全lock再現は未達。依存の実行時freezeを保存。DC05/追加の真正署名付き未知path負例/Host CAS/HC06未実行。

## 実測結果（2026-10-12 JST）

- **[専用GitHub Actions #38260583063](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38260583063)：研究ハーネスSUCCESS**、当初のPR HEAD `ca00138d65963747b8cf49bb275a6691898bbcd3`。これは**DC04のGate合格ではない**。
- O1/O2：Issuer/Agent/Merchant真正署名、各Root提示に再署名したTerminalの`sd_hash`、aud/nonce、Merchant JWT/hash、公式AP2 `verify_chain`が**FULL・M0・S0の3提示すべてVALID**。Root JWSは3提示で**同一**。Issuer/Agent/Merchant鍵は生成時の一時秘密鍵で、artifactには公開JWKと合成署名原文だけが残る。
- O3：Issuer署名済みRootの**最上位から**生wire commitmentを走査。FULLは期待したpath/kindの**3 commitmentを解決、残余0**。M0は `allowed/0`、S0は `acceptable_items/0` の**正確に1 digestだけ**非提示。両方独立walkが `incomplete_disclosure: signed commitment not disclosed` で拒否。
- O4：公式pinned Open JSON Schemaの検査結果は **FULL VALID / M0 VALID / S0 VALID**。Schemaは両要素の非開示による空配列を必ずしも拒否しないため、これは完全性の証拠にならない。
- O5：既存 `AP2CheckoutBindingResearch.verify!` を3提示へ実行すると **FULL / M0 / S0 すべて `unsupported array disclosure location` によるREJECT**。Ruby `TracePoint` による拒否起点もartifactに保存。**FULLの正常例まで拒否されたためDC04 Gate = `RED_HOLD`**。M0/S0の`missing disclosure`による適切な拒否は、このRuby実装に対してはまだ実証していない。
- 合成の完全なsigned-wire原文・Disclosure順序・公開JWK・Host合成期待値・Python/Ruby観測JSON・上流/実行HEAD・依存freezeを含むSHA256/byte-length manifest生成・照合は成功。Actions artifact `phase2a-dc04-nested-element-signed-probe` ID `11752635062`（約28.6 KB）、**2026-10-19 14:07 UTCに期限切れ**。恒久リプレイ証拠は未達。

**解消すべき課題:** `research/p1_1/root_sdjwt_research.rb` は署名済みRoot wrapperと`constraints`配列Disclosureだけを許し、`allowed[0]` / `acceptable_items[0]` の入れ子を非対応として拒否する。候補となる次の作業は**独立したresearch-only Ruby固定Issuerプロフィール用resolver**を別レビュー付きで設計・実装し、完全開示正常例のPASSとM0/S0の`missing disclosure`の区別を示すこと。ただし広いSD-JWT解釈へ安易に緩和しない。署名済み未知path・デコイ・別Issuer/multi-hop・公式Schemaとの順序・Host challenge CAS/失効/HC06も未実証。

**判定と運用:** 専用CIのGREENは**研究観測の再現に成功しただけ**。DC04 RED/HOLD、Issue #47 OPEN、DC05 NOT RUN、Phase 2-B/Gem/API/production/payments HOLD/NO-GO。Codexの最新HEADレビュー完了と未解決指摘の解決前にPRをマージしない。
