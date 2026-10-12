# Phase 2-A / E01-S — 合成Issuer信頼境界 3ケース検証計画

**2026-10-13 JST / 親 [Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) / DESIGN ONLY — NOT APPROVED TO RUN / ALL E01-S CASES NOT RUN**

> **結論:** 将来の別承認に向けた最小実験候補を **IP01正常FULL、IP02未登録Issuer鍵、IP03同じIssuer鍵の別発行レイアウト** の3つに固定する。真のIssuer署名・Hostの独立Trust判断・Root原本の開示完全性を区別する。ただし**今あるRuby研究候補にはIssuer identity / policy-version registryの一般的な照合機能がない**ため、`IP02: untrusted_issuer`と`IP03: profile mismatch`が専用Host trust gateに到達したという実測を、本計画から予告・捏造しない。
>
> **許可境界:** 本PRは**文書1件のみ**。コード変更、fixture生成、CI/GCP実行、実Issuer/Host登録、Gem/API、本番Checkout/決済/Receipt、Phase 2-Bは**全て未承認・HOLD**。実験許可が必要なら別Issue/PRでscope、費用、上限、鍵取扱いとオラクルを承認する。レビュー済み文書のmergeはその実行承認ではない。

## 1. 根拠と研究命題

公式AP2 v0.2.0 **`b4587ac1d055888a73b4b21750973cffba961793`**に固定。[E01信頼出所判断](PHASE2A_E01_ISSUER_TRUST_PROVENANCE_DECISION.md)では `E01_REAL_ISSUER=UNPROVEN`、合成Issuerモードは **SYNTHETIC_ONLY_RESEARCH_CANDIDATE**。[Issuer profile受理契約](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md)のT1/T2/T3、[Exit checklist](PHASE2A_EXIT_GATE_DECISION_CHECKLIST.md)のE01/E02/E03/E05/E09、[DC04隔離Ruby候補](PHASE2A_DC04_BOUNDED_RUBY_FOLLOWUP.md)を参照する。

| 原則 | 質問 | 独立に必要な原本 |
| --- | --- | --- |
| **T1 signed bytes** | 提示Rootは、どの合成Issuer鍵で本当に署名されたか | 元JWS bytes・別経路で検証する合成Issuer**公開鍵**・protected JOSE header |
| **T2 signed-root completeness** | 同じRootがcommitした全SD slotは署名原本の許可3位置で一対一解決されるか | 署名済Root graph、Disclosure元bytes/digest、未知・余剰・重複・decoyの全域走査結果 |
| **T3 synthetic Host trust** | 発行者と切り離して凍結したHost役policyがこのIssuer鍵/用途/全closed grammar/versionを受け入れるか | **tokenとは独立した**合成Host policy snapshot、許可鍵thumbprintと有効期限・版、厳格照合の証拠 |
| **O5 Ruby behavior** | Ruby候補が受理/拒否したのはどの検証段階で、何が原因か | 同じ研究実装HEADに対する結果、正確なexception/codeと到達stage。外部オラクルの能力をRubyに帰属させない |

**プロフィール自己申告禁止:** `iss`/`kid`/`policy_version`は提示JWTに書かれていてもHost trustの正本ではない。pinned AP2が本OSSのsigned policy-version claimを標準で提供すると仮定しない。**1件の実際の署名付き発行例はT1/T2の観測であって、Issuer本人が今後のclosed grammar/rotationに従うという認証済みT3の契約ではない。**

## 2. 合成Host trust fixtureの設計（**未作成**）

試験用の `T3_SYNTHETIC` を再現可能にするには、**入力wireより先に**次の正本を固定し、両者の独立性をSHA256/生成順序と監査手順で示す。実際のMerchantへのIssuer登録や実Issuer attestationを作ったと装わない。

- `tenant_scope`、`checkout_use_case`、`issuer_ref=synthetic-e01s-issuer-A`、事前許可した公開鍵のthumbprintと `ES256 / P-256`・署名用途、有限`not_before/not_after`、`profile_ref`・不変`policy_version`・policy digest・active status。
- **closed signed-wire grammar**: Root/ClosedとJOSE protected headersを含む全signed field、未知field拒否、Root Open 1、固定2hop、制約2つ（`checkout.line_items`、`checkout.allowed_merchants`の固定順）、Merchant/SKU/Checkout各1、許容SD array commitmentの**正確な3path**:
  - `$/delegate_payload/0`
  - `$/delegate_payload/0/disclosed/constraints/1/allowed/0`
  - `$/delegate_payload/0/disclosed/constraints/0/items/0/acceptable_items/0`
- decoy/unknown object `_sd` / 余剰 `...` /余剰Disclosure/重複digestを許容しない。Agent `cnf.jwk`、Terminal署名と`sd_hash`、Merchant Checkout原文JWT/hash、Host期待 aud/nonce/checkoutを別々に照合する**研究制約**を維持。
- `policy_version`は**Hostに保存された不変の選択値**。Issuer署名に含まれない版の相違をRoot内で検出することはできない。**同じ鍵・同じwireでversion文字列だけ変えても「署名済profile不一致」を実測できたとは数えない**。Host policyを変える実験では、政策選択/曖昧性の拒否を独立のHost policy判定として測る必要がある。
- 資源上限: 現行[DC04 Ruby source](../research/phase2a_dc04/fixed_issuer_verifier.rb)に存在する `Root SD-JWT <= 32,768 bytes`、`1–16 disclosures`、`signed path depth <= 24`、`object fields <= 32`、`array length <= 16`、`Open exp-iat <= 7,200s` を**既存候補の局所上限として参照**。**これだけではE07を満たさない**: 全JWS/Disclosure/総bytes、CPU/wall-clock、信頼時計/skew、全鍵/host policy TTL、runner timeout/費用上限等は未決である。将来の実行は**全項目に具体値・単位・強制箇所を別承認で設定しない限りBLOCKED**。
- 鍵は実験ごとの**一時的な合成鍵**（private materialはcommit・artifact・ログに残さない）。署名原文・合成公開鍵・非秘密Host policy参照・bytes/hash・依存freezeのみ再現証拠として設計する。

**重要な既存Ruby能力境界:** `AP2DC04FixedIssuerResearch.verify_full_root!(wire, trusted_jwk:)` はHostから渡された公開鍵でIssuer JWSを検証するが、**単一Issuerを参照するHost trust registry / `issuer_ref`と鍵・policy版の独立登録照合を提供しない**。この欠落を隠して `untrusted_issuer`という既存実装結果を予告しない。将来、Host policy selectionの**独立した試験オラクル**を置く/補助研究実装するなら、別Issueで新規コードscopeを明示的に承認し、Ruby実装の観測と分離する。

## 3. 3ケース限定 — 実験と合格証拠の設計

| ID / 対象 | 正しく構成する比較 | T1/T2/T3独立オラクル | Ruby候補で言えること・**未実証の目標** |
| --- | --- | --- | --- |
| **IP01 / control FULL** | Host policyが事前固定したIssuer Aの真正署名Root、完全開示されたMerchant[0]/SKU[0]、同じAgent/Checkout/aud/nonceでpinned Open Schema VALID | **O1:** A公開鍵でES256/JWS VALID、**O2:** Agent Terminal `sd_hash`/PoPおよびMerchant JWT/hash VALID、**O3:** 許可3path・残余0・digest一対一、**O4:** 公式Schema VALID + 合成Host trust policy一致 | 同一候補Rubyの **LIMITED_POSITIVE** を確認する想定（DC04と類似でもE01-Sとしては**NOT RUN**）。Host ALLOW/本物のIssuer登録ではない |
| **IP02 / wrong unregistered Issuer B** | **発行者B自身の鍵で真正に再署名**したFULL（Agent/Checkout bindingも必要に応じ真正に再署名）。Host policyは変えず **Aだけ許可**。Bのpublic keyを別経路で検証、提示Header `kid`でHost allowlistにBを追加しない | **O1:** B公開鍵でJWS VALID、**O2/O3/O4:** 正常shape・binding・Schemaをそれぞれ独立確認、**T3:** A-only policyではB鍵が未登録、署名が暗号的にVALIDでもHost trust不一致 | 現行RubyにAの `trusted_jwk` を渡せば**署名検証エラーが先行し得る**。これは新しい `untrusted_issuer`判定が機能した証明ではない。**必要なゴール:** Host trust gateを明示した実装が別承認され、拒否の到達stageを独立追跡。これがない限り`E05 PASS`を主張せずHOLD |
| **IP03 / same-key other grammar** | **Issuer Aの同一真正鍵**で、Host policy A-v1とは異なる**有効な署名済みRoot claim/constraint layout**を発行する（変更位置と公式Schema VALID/INVALIDは事前宣言）。Host policy/key/A-v1は不変のまま。署名/JWSを後から書き換えない | **O1:** 同じA鍵でVALID、**O2:** Agent/Checkout bindingを維持、**O3:** 変更したsigned field/pathを原文から独立記録、**O4:** Host closed grammarとの不一致と公式Schemaの成否を別記 | 固定Ruby候補は未知shapeを既存ルールでREJECTし得る。ただしRoot件数等の先行拒否を「Host `policy_version`検証成功」と呼ばない。**同じwireでHost版だけ変えるvariantは別のpolicy-selection実験**であり、本IP03署名検証から自動証明不可 |

**IP03成立上のストッパー:** 有効署名の別レイアウトが公式pinned SDKで生成できない、または正常OpenのSchema VALIDという比較条件を保てない場合は、**`BLOCKED_OFFICIAL_SHAPE`/O4結果を記録して止める**。公式Schema INVALIDでのRuby REJECTをProfile mismatch guard PASSと書き換えない。Unknown allowed path、decoy、double Openの既存DC05/DC06 early rejectsをIP03成功の代用品にしない。

## 4. 将来の独立検証マトリクス（O1–O5）

| オラクル | 正本 | case毎の必須記録 | よくある偽陽性とSTOP |
| --- | --- | --- | --- |
| **O1: Issuer crypto** | JWS元bytesと**許可/非許可双方の合成公開鍵** | 検証した実際の署名者鍵thumbprint、JWS bytes digest、header、検証結果。「B鍵でVALID」と「Host A鍵では未承認」を分ける | AでB署名をINVALIDと判定しただけでE01不正Issuer guard PASS扱い禁止 |
| **O2: binding** | genuine Agent Terminal、公開鍵・Host aud/nonce、Merchant署名JWT原文/hash | PoP・`sd_hash`・時間・Checkout整合の独立結果。negativeの変更が別レイヤーに影響しないこと | `invalid_chain_binding`/時刻切れだけの拒否ならIP02/IP03プロフィール検証PASSにしない |
| **O3: original Root graph** | Root signed JWS payload + 元Disclosure base64urlセグメント | 全slotと許容3path・unused/missing/double digest、decoy/unknown、原文SHA256とbytes | Rubyのresolved payloadの可視制約だけで完全性主張禁止 |
| **O4: SchemaとHost policy** | 公式Open Schema pinned v0.2、**presentationと独立に凍結した**Host A-only policy | Schema VALID/INVALID、Issuer鍵・profile/layout候補比較、version downgrade/複数policy選択なし、完全path集合の差分 | Host policyをIssuer JWTから自動発見したらBLOCKED。不明な `profile_version` から署名済束縛を捏造禁止 |
| **O5: Ruby result / trace** | 同じ固定Ruby候補HEADと必要な別途承認済みHost trust判定実装 | FULL限定受理、負例拒否メッセージ・段階（format/trust/crypto/disclosure/schema）、実際に到達したguard。完全性早期拒否との区別 | 期待と違うguardでSTOPしたなら**安全側のREJECT観測だけ**。目標のtrust guardは未実証/RED-HOLD |

**実行成功の意味:** O1–O4が負例の真正性を証明し、O5で**当該信頼境界が因果的に実行されたこと**を示せたケースだけ、`LIMITED_SYNTHETIC_E01S_OBSERVED`の候補にする。両負例が単にREJECTでも `E01_REAL_ISSUER`、`E03/E06`統合完全性、`E05`一般版・rotation、Phase 2-Bは**PASSにしない**。

## 5. 実行前の別Issue承認ゲート（**未承認**）

- [ ] **新しいscope Issue**を作成し、この計画へのリンクと **IP01/IP02/IP03のみ** の署名付き合成fixture・研究コード変更が必要かを明示。親#47のdesign-only権限でコードやCIを走らせない。
- [ ] 合成Host policyのfreeze主体・生成順序・不変参照・issuer keys A/Bを公開鍵のみで検証可能にする。**Host policyとissuer-signed Rootを同じ入力から自己正当化する偽オラクルは禁止**。
- [ ] 既存RubyにIssuer registry/policy-version gateが**ない**と認め、IP02/IP03をO5で厳密に判定できる**最小補助コード/観測方法を別承認**する。未承認の改変禁止、ログだけで誤認させない。
- [ ] 入力全体のbytes、JWS/Disclosure/claim/SD slot数、再帰深さ、execution CPU/wall timeout、依存/Runner/CI時間と費用、clock skew・TTL・keys policy期限を**具体的な有限値**で別途設定。既存Rubyの局所上限をプロダクション上限と呼ばない。
- [ ] official pinned SDKの生成能力とES256 actual JWS、independent `jwcrypto`等での暗号原本検査、O1–O5、同じRuby HEADでFULL正例→負例、元署名wireのhash/bytesを合意する。
- [ ] 禁止: private keys保存、public unsafe endpoints、GCP、実Issuer/Authority、実payment/Receipt、Gem/public API、汎用SD-JWT化。Exit gate: 有効署名負例がHost trust guardに到達しないなら**FAIL_TO_PROVE/HOLD**と記録。
- [ ] 発行再現用7日期限のActions artifactでは永続再現性がないため、公開鍵のみの再生成手順/manifest/official SHAと依存freezeを別設計。原文JWTに機密やprivate JWKを含めない。
- [ ] 最新PR HEADのP1/P2 Codexレビューとscope CIが走った場合のみ対象runを確認し、**独立証拠なしにGreenを安全PASSへ昇格させない**。

**実験費用・時間・依存について実際の確定値はまだなく、このPRの承認で予算/CI分を暗黙に確保しない。** 有限実行上限とHost policy原本オラクルを決められなければ`E01S_PLAN_BLOCKED`のまま停止する。

## 6. 計画レビューのExitと現時点の判定

| 判定 | 条件 | 現状 |
| --- | --- | --- |
| **DESIGN_RECORD_REVIEWABLE** | 3ケース・T1/T2/T3分離、現Rubyのギャップ、原本・到達stage・有限値の未決をレビュー可能 | **PROPOSED, docs-only** |
| **E01-S EXECUTION APPROVED** | 別scope Issueで実行内容・費用/上限・鍵取扱い・実装差分・O1–O5・STOPを明示承認 | **NO** |
| **E01-S TEST PASS** | 真の署名付き3ケースの独立原本証拠・同一候補の因果的負例が実際に成功 | **NOT RUN / NO** |
| **REAL_ISSUER_TRUST / E01 / Phase 2-B GO** | [E01 R01–R06](PHASE2A_E01_ISSUER_TRUST_PROVENANCE_DECISION.md)と[Exit gate E00–E10](PHASE2A_EXIT_GATE_DECISION_CHECKLIST.md)の別判断 | **UNPROVEN / HOLD / NO-GO** |

**最終条件:** 本計画をマージしても研究実行、Phase 2-B、Gem/API、本番・Host challenge-CAS/HC06/決済/Receiptの承認を意味しない。Issuer signed Rootに現れない外部権限が実在しないと保証したわけでも、正規AP2の任意Issuer/profile/decoyに対応したわけでもない。親Issue #47を自動クローズしない。
