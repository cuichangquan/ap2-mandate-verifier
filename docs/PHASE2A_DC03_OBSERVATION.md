# Phase 2-A / DC03 — 必須 `line_items` の非開示（真正署名負例）

**2026-10-12 JST / [Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) / 合成research-only / 本番・Gem・実決済なし**

> **現在の判定：LIMITED_DC03_OBSERVED（合成Issuer/Agent/Merchant真正署名と研究用Ruby Resolver段階の拒否に限定）。** 初回CIは集計キーの誤りでFAIL、その後修正したCIで実測を確認。最新HEADのCodexレビュー・PRマージは別途確認。Phase 2-B実装、Gem/API公開、Host/外部失効/HC06、実決済は引き続き**HOLD/NO-GO**。

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

## 実測結果（2026-10-12 JST）

- **初回CI [#38258138466](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38258138466)：FAIL。** 根拠となるPython O1〜O4とRuby O5の観測は実行されたが、最終検証スクリプトにDC02由来の古い出力key `o5_ruby_hidden_merchant` が残り `KeyError` を発生。**初回CIはGREENではない**。結果の手動成功判定に読み替えず修正した。
- **修正版CI [#38258273193](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38258273193)：SUCCESS、HEAD `f890398b84311b50974f7c4a585dda00c63c5940`**。Issuer ES256 JWS原文は対照と隠蔽提示で同一・署名VALID、Agent Terminalは提示ごとに別署名し各`sd_hash`・aud/nonce VALID、Merchant JWS・Checkout hashもVALID。公式上流`verify_chain`も両提示でVALID。
- **O3:** Issuer署名済みRootの元signed-wireから入れ子 `$/delegate_payload/0/disclosed/constraints/0` にある**必須`checkout.line_items`のdigestを特定**。対照は全commitment開示済みで残余0。非開示提示はこのdigestだけが欠けるため `incomplete_disclosure: signed commitment not disclosed`、Issuer署名不正やAgent`sd_hash`違反ではない。
- **O4:** 実際の非開示提示から得たOpenをpinned公式JSON Schemaで評価すると **INVALID（`constraints.contains`）**。完全開示対照はVALID。**このSchema INVALIDだけで安全性PASSとはしない**。
- **O5:** 既存Ruby研究Verifierは完全開示の限定正常Checkoutを成功させ、隠蔽提示では `missing disclosure` でREJECT。Ruby `TracePoint(:raise)` の検証により、拒否が **`root_sdjwt_research.rb` の `resolve` メソッド内**で起きたことを記録し、cart比較に到達しない。Ruby出力中のMinitest `0 runs / 0 assertions` は自動runnerの副作用であり、O5の検証は直接メソッド呼び出し＋明示的なassertionで行った。
- 合成JWS/Disclosureのバイト列・2hop Chain・公開JWK、Python/Rubyの結果JSON、依存freeze、公式AP2 SHAと研究HEADの各ファイルを最終SHA256/byte-length manifestで照合。Actions artifact `phase2a-dc03-synthetic-public-replay` ID `11751730749`、約20 KB、**2026-10-19 13:48 UTC期限**。短期保存のため恒久的な第三者リプレイ保証は未達。上流 `uv.lock` にprivate registryがありPython推移依存の完全lock再現も未達。

**残る重要な境界:** 既存Ruby研究Verifierは公式Schema検証を実装しておらず、`TracePoint`は**研究用Root Resolverが業務比較より先に例外を発生させる**ことだけを実証する。**Phase 2-B実装での開示完全性GateとSchema Gateの順序・安全性を実証したわけではない**。真正署名付き未知path負例、DC04/DC05、Host nonce CAS/強失効HC06/Receipt、Gem/API/実決済も依然HOLD/NOT RUN。Issue #47はOPEN。

