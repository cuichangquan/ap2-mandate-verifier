# Phase 2-A / DC01–DC06 — 実測と権限開示完全性の証明ギャップ監査

**2026-10-13 JST / 親 [Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) / DESIGN-ONLY DECISION RECORD / Phase 2-B HOLD**

> **結論: DC01–DC06の予定済み署名付き合成ケースは限定的に実測済み。しかし親#47の「Issuerの権限開示完全性」の保証は未証明。Phase 2-B、Gem/public API、本番Checkout・決済・ReceiptはNO-GO。**
>
> この文書は過去の計画時点の「NOT RUN」記録を改変せず、後続の実測を別の日付付きで集約する。CI成功はそのCIの**期待した限定観測**の成立であり、汎用SD-JWT受理や業務ALLOWの保証ではない。

## 1. 固定した観測範囲

- 研究 main の確認基点: `5c729d2c6d94f038e3299da3b486a6cb70c06c93`（[PR #60](https://github.com/cuichangquan/ap2-mandate-verifier/pull/60)マージ時）。
- 公式AP2 v0.2.0固定: `b4587ac1d055888a73b4b21750973cffba961793`。各実験は実際の合成Issuer・Agent・Merchant署名と、別経路のPython独立暗号／署名元wire／Schema検査を要求した。
- Rubyは**既存P1研究Verifier**と、DC04以降の**明示的に隔離した固定Issuer研究候補**を区別する。後者を本番API、汎用Gem、旧実装の修正完了と呼ばない。
- 期待する固定形は候補A: Hostが登録する単一Issuer / 固定profile、Open→Closedの2hop、Root Open 1件、必要なMerchant・line-item制約各1件、Merchant 1・SKU 1・Checkout 1。公式AP2が全Issuerに要求する仕様ではない。
- 証拠はpublic-key-onlyの合成署名wire、SHA256/byte-length manifest、依存freeze、実測CI・PRレビューへのリンク。**Actions artifact保存期間は7日**であり、永久に検証可能な第三者fixtureがあるとは主張しない。

## 2. 何が観測済みか（O1–O5を混同しない）

| ケース | 真正署名／独立signed-wireと公式Schema | Ruby観測 | 正しく主張できる範囲 |
| --- | --- | --- | --- |
| **DC01** [#50](https://github.com/cuichangquan/ap2-mandate-verifier/pull/50) | 合成Issuer/Agent/Merchant署名と結合、Open Schema VALID、許可されたRoot commitment 2件が完全解決、残余0 | 既存研究のFULLを限定受理 | **LIMITED_POSITIVE**。Issuerの未知layoutや隠れた別権限の一般不在は証明しない。 |
| **DC02** [#51](https://github.com/cuichangquan/ap2-mandate-verifier/pull/51) | 正常／非開示とも署名・Agent `sd_hash`・公式Open Schema VALID。元署名wire上のMerchant制約commitment 1件が未解決 | FULL限定受理、隠したMerchant制約を `missing disclosure` で拒否 | 既存研究の**特定の署名付きMerchant非開示**の拒否。Schema VALID単独では不十分。 |
| **DC03** [#52](https://github.com/cuichangquan/ap2-mandate-verifier/pull/52) | 本物の署名付きline_items非開示。FULLのSchema VALID、部分提示は `constraints.contains` でINVALID。元signed-wireには未解決digest | 既存Ruby resolverが `missing disclosure`、cart比較より前で拒否 | **限定的な拒否**。既存Rubyは公式Schema verifierを実装していないため、Phase 2-Bにおける「completenessがSchemaに先行」の統合順序は**未証明**。 |
| **DC04** [#53](https://github.com/cuichangquan/ap2-mandate-verifier/pull/53), [#55](https://github.com/cuichangquan/ap2-mandate-verifier/pull/55) | 署名済みMerchant[0]／SKU[0]配列要素のFULL・非開示を独立に識別。いずれも公式Schema VALID | **旧P1-1**はFULLさえ非対応として拒否（RED/HOLD）。**隔離Ruby候補**はFULL限定受理、M0/S0を `incomplete_disclosure` で拒否 | **LIMITED_DC04_OBSERVED**は隔離候補だけ。旧実装のRED/HOLDは消さない。 |
| **DC05** [#57](https://github.com/cuichangquan/ap2-mandate-verifier/pull/57) | 公式署名primitiveで実在のdecoy未解決digestを観測（特定の実行で30件、Root直下を含む）。SDKとOpen SchemaはVALID | 隔離候補はFULL受理、decoy付き署名提示はunsupported fixed profileとして拒否 | **LIMITED_DC05_OBSERVED**。decoyを正しく分類して受理した証拠でも、汎用decoy検出でもない。 |
| **DC06** [#59](https://github.com/cuichangquan/ap2-mandate-verifier/pull/59), [#60](https://github.com/cuichangquan/ap2-mandate-verifier/pull/60) | 署名付き未知Root/Constraint/object-SD 4負例、追加の重複digest・2個目Open（全開示／非開示）3負例で、真正署名・signed-wire性状を別経路で確認 | 隔離候補はFULL限定受理、すべての該当負例を拒否。**#60の3負例は署名検証・digest重複解析より前のRoot配列件数制約で拒否** | **限定的な固定profile構造的Fail Closed**。一般SD-JWTの重複digest／ステルス権限検出の証明ではない。 |

基礎記録: [DC01](PHASE2A_DC01_OBSERVATION.md) / [DC02](PHASE2A_DC02_OBSERVATION.md) / [DC03](PHASE2A_DC03_OBSERVATION.md) / [DC04](PHASE2A_DC04_OBSERVATION.md) / [DC04候補](PHASE2A_DC04_BOUNDED_RUBY_FOLLOWUP.md) / [DC05](PHASE2A_DC05_OBSERVATION.md) / [DC06](PHASE2A_DC06_OBSERVATION.md) / [DC06追加](PHASE2A_DC06_FOLLOWUP_OBSERVATION.md)。

**解釈上の禁止事項:** 「Rubyが拒否」だけでcompleteness成功と呼ばない。署名失敗・Schema不正・配列件数不正等の**先行拒否**と、「正しい署名に残った未解決commitmentをRubyが特定した」ことを区別する。#60の非開示2個目Openは**署名済みの追加Root slotが観測可能**であり、不可視の追加slotを一般検出したわけではない。

## 3. 証明済み／未証明／非対応

| 判定 | 命題・条件 | 根拠と限界 |
| --- | --- | --- |
| **OBSERVED（限定）** | 固定合成正例のIssuer/Agent/Merchant真正署名・SD-JWT binding・公式SchemaとRuby限定受理 | DC01、DC04候補。Trust設定は合成Host入力であって実Issuer契約ではない。 |
| **OBSERVED（限定）** | 元署名済みRootのdigest／配列placeholderをPython別経路で全走査して、部分非開示・未知位置・decoy・追加Root slot等を識別 | DC02–DC06。O3独立オラクルの結果をそのままRubyの全能力に帰属させない。 |
| **OBSERVED（限定）** | 許容していない真正署名付き構造を、狭いRuby研究候補がFail Closedで拒否 | DC04–DC06。旧RubyのFULL受理・全負例・一般入力を含む主張にはならない。 |
| **UNPROVEN / BLOCKER** | Host固定の**Issuer ID + 公開鍵 + profile version + 許可レイアウト + 発行経路/decoy方針**が、検証時の正本と一致し、実Isssuerに適用可能な独立検査可能契約として定義・固定されていること | 合成発行者と暫定Ruby検証器の試験は、**発行者がそのprofileに従うという認証済み保証**を代替しない。Hostの信頼policyとIssuer署名が証明する事実を区別する。 |
| **UNPROVEN / BLOCKER** | Phase 2-Bで署名済みRoot全体の厳格parse、commitment残余の一対一照合、未知・重複・decoyの拒否が、**署名検証・Schema・Constraint意味評価との明示した順序**で統合されること | 現在の隔離Ruby候補は汎用統合実装ではなく、DC03やDC06の先行拒否では統合順序を証明できない。 |
| **UNPROVEN / BLOCKER** | profile変更/署名鍵rotationと失効、固定上限（wire bytes / depth / disclosures / digests / JWT count / 実行時間）、二重JSON key・JOSE曖昧表現等を横断的に保証 | [最小Verifier契約](PHASE2A_MINIMAL_VERIFIER_DESIGN.md)は固定資源値を未決としている。無制限defaultを許可しない。 |
| **UNSUPPORTED（候補A）** | 汎用Issuer・未知/複数Open/Constraint、任意hop、多Merchant/SKU、decoy許容profile、部分的に秘匿した権限、未知nested SD方式 | 正規AP2でも受理しないことがある。候補Aはプライバシーより**曖昧ならSTOP**を優先する。 |
| **UNSUPPORTED/HOLD（候補B）** | Issuer署名済み完全性manifestに基づく拡張 | pinned AP2 v0.2.0の標準機構としての互換性・signed contractは未証明。 |
| **別系統 HOLD** | Host challenge/Agent/Buyer/Checkout正本、nonce-CAS・replay、Authority失効/HC06、Receipt・実決済 | Verifierの証拠をHostの最終ALLOWに変換するには**独立したHost安全性Gate**が必要。 |

## 4. 親Issue #47の核心：証明の出所

1. **Issuer JWS**が証明できるもの：署名対象Rootのバイト列とそこに表現されたdigest commitmentの真正性。Issuerが外部の権限契約を漏れなく発行した事実や、Presenterが任意のDisclosureを全部見せた事実までは署名単独では証明しない。
2. **独立signed-wireオラクル**が証明できるもの：署名済みRootに**存在する**すべてのcommitmentを原本から列挙し、提示Disclosureをdigestで一対一対応付け、未知位置・未解決残余・重複を拒否できたという**観測ケース限定**の事実。
3. **Host固定Issuer profile（候補A）**が補うもの：全権限位置を受理対象の有限文法とし、許可されない署名claimや未解決SD位置があれば拒否する**Host側の事前Trust決定**。これは提示wire中の `iss`/`kid` から自動発見する情報ではない。
4. **なお残る条件**：Trust profileの出所・revision・Issuer鍵とlayoutの認証済み結合、正本としての失効/rotation、未知の拡張に対する厳密拒否、統合時の順序・負例・資源境界。署名対象に**存在しない**外部の権限情報が不存在であることは、digest走査だけでは示せない。

**Candidate Aの言える最大値:** 「Hostが事前に認証・固定した狭いIssuer profileのもとで、署名Rootがコミットした許可文法上の権限制約をすべて検査でき、曖昧な未開示/未知構造はRejectする」という**条件付き**の証明を目指せる。現状ではそのプロファイル契約全体が独立検証・統合されたわけではない。

## 5. 次に行う一件（設計のみ）

親#47を**OPEN/HOLD**に保ち、候補Aの「完全性の信頼根拠」を検証可能な**issuer-profile acceptance contract**として定義・レビューする。最低限、次を同一の設計成果物に明記する。

1. **Trust anchorの出所**：Host事前登録のIssuer identity／公開鍵・有効期間・固定version・発行layout・decoy禁止・profile変更/鍵rotationと再承認ルール。Issuerがsigned Rootで証明する範囲と、Hostが独自に仮定する範囲を別列にする。
2. **決定的な検査順序**：wire/JSON/JWSの曖昧さ・資源上限 → Host登録profile照合 → Issuer/Agent/Merchant署名と `sd_hash` → 元署名Root全域でcommitment graph・digestの一対一解決 → 未知/非開示/decoy拒否 → 公式Schema・業務Constraint → Evidenceのみ。**先行cardinality rejectが署名を確認した証拠ではない**ことを明記し、必要な短絡拒否と真正署名付き安全性実証を区別する。
3. **反証可能な受入れ条件**：FULLが同じRuby候補で限定受理、各署名付きhidden/unknownで原本digestとの因果的な拒否を示す。特にDC03型のSchema INVALID先行、DC06型のRoot件数先行をcompleteness PASSへ読み替えない。すべての未知path/二重digest/余剰Disclosure/decoyはSTOP。
4. **限界と分離**：B（manifest）は独立議論、DC07のIssuer/profile mismatch等は**未実測**として追跡。Host challenge-CAS / HC06 / paymentは別Gate。対応外を安全に拒否することと一般AP2対応を混同しない。

**Phase 2-A exit/Phase 2-B GOの判断:** 上記Contractの出所と暗号保証の線引きを第三者レビュー可能にし、限定プロフィールの独立オラクル・統合上の証明不足を**未証明として明示するか、追加の別途承認済み実験で潰すか**決めるまでは **HOLD**。docs-onlyのPRをマージしてもGOにはしない。Issue #47を自動クローズしない。

関連する設計基準: [開示完全性Gate](PHASE2A_DISCLOSURE_COMPLETENESS_GATE.md) / [最小Verifier契約](PHASE2A_MINIMAL_VERIFIER_DESIGN.md) / [Phase 1→2 gate](PHASE1_RESEARCH_CLOSURE_PHASE2_GATE.md)。
