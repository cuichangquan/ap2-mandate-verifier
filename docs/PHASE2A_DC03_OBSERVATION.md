# Phase 2-A / DC03 — 必須 `line_items` の非開示（真正署名負例）

**2026-10-12 JST / [Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) / 合成research-only / 本番・Gem・実決済なし**

> **PR作成時: PREPARED / NOT RUN。** 本PRのGitHub Actions実測・ログとCodexの最新HEADレビューを確認するまでは、DC03の成功を主張しない。Phase 2-B実装、Gem/API公開、Host/外部失効/HC06、実決済は引き続き**HOLD/NO-GO**。

## 実験の主眼

DC02で隠したのはMerchant許可制約だった。今回は公式AP2 v0.2.0 **固定SHA `b4587ac1d055888a73b4b21750973cffba961793`** の `MandateClient.create` を使い、**必須の商品制約 `checkout.line_items` 全体**に対して、発行時の `sd_array_indices=[0]` によりIssuerに真の署名付きcommitmentを作らせる。そのConstraintのDisclosureだけを非提示にする。

Issuer署名済みRoot JWSの原文は**完全提示と非開示提示で同じ**。Agent Terminalは各提示のRootに合わせて**別々にES256署名**し、`sd_hash` / `aud` / `nonce` を独立照合。Merchant JWTは同一の合成署名JWTを使用し、Hash/Host想定値を固定する。

**DC02との最重要差分:** 公式Open JSON Schemaは `constraints.contains` で `checkout.line_items` を必須としている。今回、正しい署名のまま `line_items` を隠した部分提示は**公式Schema INVALIDになる見込み**。そのINVALIDによる拒否だけでは**開示完全性を検証したことにならない**。

## O1〜O5の別々の期待値

| 独立オラクル | 完全開示の対照 | 必須 `line_items` 非開示 |
| --- | --- | --- |
| **O1：Issuer** | 元Root JWS ES256 VALID | 完全提示と**同じ署名済みRoot JWS**でVALID |
| **O2：Agent＋Merchant** | Terminal ES256・`sd_hash`・aud/nonce、Checkout Merchant JWS/hash VALID | **別途真正署名されたTerminal**、Merchant JWS/hashもVALID。公式`verify_chain`は両提示で通ること |
| **O3：元署名wireの完全性** | 全Issuer-signed commitmentの固定path/kind一致、残余0 | `$/delegate_payload/0/disclosed/constraints/0` の**Issuer署名済み商品Constraint**のDisclosureだけが未解決。独立walkが `incomplete_disclosure` |
| **O4：公式Schemaと固定profile** | 公式Schema VALID／固定Issuer profile適合 | **公式Schema INVALID（`constraints.contains`）** とProfile不完全を**別理由として記録** |
| **O5：既存Ruby研究Verifier** | Checkout ID/Merchant/金額の**限定正常Evidence**（ALLOWなし） | Rubyが `missing disclosure` でREJECT。**TracePointがRoot Disclosure resolver内での例外発生位置を記録**し、cart比較に到達しないことを調査 |

重要な限界：**既存Ruby研究Verifierには公式JSON Schema validationそのものが実装されていない**。今回のO5研究トレースから分かるのは「既存Rubyの署名付きDisclosure解析段階で、業務比較より先に拒否した」こと。**将来のPhase 2-Bで実装する完全性GateとSchema Gateの相対順序までを保証するものではない**。公式Schemaの検証は別の独立Python O4による。

## 実施・保存・停止条件

- 合成Issuer／Agent／MerchantのP-256一時秘密鍵はPython生成プロセス外に保存しない。検証用に**公開JWK＋Root JWS／各Disclosure順序／Root SD-JWT／Terminal JWS／Merchant署名JWT／二hop chain**の原文のみ保存する。
- [Python署名生成／O1〜O4検査](../research/phase2a_dc03/generate_and_observe.py)、[Ruby O5＋例外起点計測](../research/phase2a_dc03/observe_ruby.rb)、[専用CI](../.github/workflows/phase2a-dc03-hidden-line-items.yml)を使う。GitHub Actionsはread-onlyかつ実決済/GCP/外部Hostなし。
- `evidence-manifest.json`で全合成署名原文とPython/Ruby実測JSON、依存freeze、上流/HEADのSHA256・サイズを確認する。artifact保持は**7日**であり、恒久的な第三者リプレイ証拠にはならない。公式 `uv.lock` はprivate registry参照のため**推移依存lock完全一致ではない**。
- 完全提示が正常、非開示側もIssuer/Agent/Merchant署名＋`sd_hash` VALID、Issuer-signed `line_items` digest未解決、**実際の部分提示OpenはSchema INVALID**、Rubyの拒否理由が `missing disclosure` かつ起点が `root_sdjwt_research.rb#resolve` という条件が全部観測された場合のみ **`LIMITED_DC03_OBSERVED`** と分類する。
- どれかの前提が不成立、別の障害・署名ミスマッチ・Schema-onlyの拒否しか示せない場合は**BLOCKED/FAIL/HOLD**。何より**Phase 2-BのGate順序の正式証明には数えない**。
- DC04／DC05、未知Root commitmentの本物の署名付き異常負例、Host nonce CAS、失効・HC06・Receipt、本番Merchant／実Issuerは対象外であり、Issue #47を閉じない。

**実測（PR作成時点）：DC03 NOT RUN。** 完了した専用CIのURL・HEAD・結果と限界を、CI後に追記する。
