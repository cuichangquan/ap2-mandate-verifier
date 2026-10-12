# Phase 2-A — DC01–DC05 独立署名オラクル実験計画

**2026-10-12 JST / [Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) / DESIGN ONLY / NOT IMPLEMENTED / DC01–DC05 NOT RUN**

> **判定: 実験計画のみ。候補Aの開示完全性は未証明。** この文書のレビュー・マージは署名fixture生成、Rubyテスト実行、Phase 2-B実装、Gem/API、本番Host、実決済、HC06の承認ではない。すべて **HOLD / NO-GO** のまま。詳細な受理プロフィールは[開示完全性Gate](PHASE2A_DISCLOSURE_COMPLETENESS_GATE.md)、Hostの境界は[最小Verifier契約](PHASE2A_MINIMAL_VERIFIER_DESIGN.md)に従う。

## 1. 検証したい命題と停止条件

狭い **固定Issuer・固定profile version・Open Root → Closed Terminalの2hop・Merchant1・SKU1・Checkout1** に限り、Issuerが署名でcommitした権限制約に未開示／未解決の候補が残る間は **`VerifiedEvidence`相当を絶対に発行しない**、というCandidate Aの成立可能性を検査する。

- **原本:** Issuer署名済みRoot JWTの**未解決のsigned-wire JSON**（`_sd`と配列`{"...":digest}`の位置を含む）、保持されたDisclosureの**原文**、Agent署名済みTerminalの原文、Hostに固定したIssuer公開鍵・Agent受入鍵・署名用Merchant公開鍵・profile version。
- **成功の誤認を避ける:** 公式SDKの `verify_chain()` が返す**解決済みpayload**だけ、公式JSON Schema VALIDだけ、Rubyの`errors=[]`だけでは完全性を認定しない。署名が無効で拒否した負例は「開示完全性による拒否」に数えない。
- **構成不能なら未実施:** 公式SDKの生成機能で当該署名構造を生成できない、または独立に確認できないケースは **BLOCKED/NOT RUN → HOLD**。独自の無署名JSON操作やHostでの事後制約注入で「署名付き」の代替をしない。
- **範囲制限:** 公式AP2全般の適合性や「隠れた権限が現実世界に一切ない」証明ではない。Issuerの外部実在性、ユーザー本人の同意、Host nonce-CAS/Checkout現行性/失効/Receipt/HC06は対象外。VerifierのEvidenceとMerchantの業務ALLOWを分離。

## 2. 固定したソース／テスト器具（このPRでは実行しない）

| 項目 | 将来の実験で固定・保存する根拠 |
| --- | --- |
| 公式AP2 | **v0.2.0 commit `b4587ac1d055888a73b4b21750973cffba961793`** の[Open Checkout JSON Schema](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json)。`constraints`の`line_items`を必須にするSchemaと、`allowed`/`acceptable_items`のselectively-disclosable配列要素を個別確認。 |
| 公式発行 | [`sdjwt/sd_jwt.py`](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/sd_jwt.py) の `create(..., sd=..., add_decoy_claims=...)`、[`disclosure_metadata.py`](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/disclosure_metadata.py) のモデル由来／明示指定SD metadata。生成できるという**静的API上の候補**であり、DC01–DC05用生成の成功は未確認。 |
| 公式提示・検証 | [`sdjwt/common.py`](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/common.py) の `parse_token` / `compute_disclosure_digest` / `compute_sd_hash` / `verify_binding` と[`sdjwt/chain.py`](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/chain.py) の鍵の連鎖。これは**暗号確認の一方の観測器**で、独立の完全性判定ではない。 |
| 既存の研究 | [`research/p1_1/generate_python_sdjwt.py`](../research/p1_1/generate_python_sdjwt.py) と[`research/p1_10o/test_strict_a_only_signed.rb`](../research/p1_10o/test_strict_a_only_signed.rb) を参考にする。過去の実測は**新DC01–DC05のPASSに読み替えない**。 |
| 実験実行 | 将来の**別途承認済み**隔離環境で一時鍵を生成。Ruby/Python依存を固定し、公式ソースSHA、Ruby候補HEAD、fixture digest、実行コマンド、出口コード、観測器の別々の結果を報告。現時点 **CI なし、実行なし**。 |

## 3. 独立オラクル — 少なくとも5本を分けて観測する

| オラクル | 何を独立に確認するか | 成功の意味と非意味 |
| --- | --- | --- |
| **O1 Issuer** | Host固定のIssuer **公開鍵**でRoot JWS（ES256/P-256）を検証。JWT header/payloadの重複キー・未知algなど曖昧なsigned bytesをreject。鍵を提示`kid`等から自動信頼しない。 | Rootが署名されていること。**全constraintが可視**とはいえない。 |
| **O2 Terminal+Merchant** | Root署名済み`cnf.jwk`から許容済みAgent鍵へ結合し、Terminalの真正署名、`sd_hash`の**提示されたRoot + Disclosure原文**への結合、Host期待`aud`/`nonce`を別々に照合。Merchant署名Checkout JWT・Host正本JWT原文/hashも独立検証。 | 有効な2hopとCheckout結合。**購入ALLOWや再生防止**ではない。 |
| **O3 SD signed-wire** | Rootの署名対象JWTを構文解析して、`delegate_payload`を起点にすべての許容/未知`_sd`・`{"...":digest}`を**入れ子／位置込み**で列挙。各Disclosure原文digestとsigned placeholderの**一対一対応、完全消費、重複・未解決・余剰・未知位置なし**を調べ、正規化の前後でcommitment数が保存されたか監査。署名の真正性はO1前提。 | **ローカル固定文法の範囲の完全性**。署名アルゴリズム自体を再実装しない。SDKのresolved dictだけをoracleにしない。 |
| **O4 Profile+Schema** | O3解決済みの完全Openへ**pinned公式JSON Schema**検証を独立実施した上で、別途Host固定Issuer-profile（許容path/型/未知キー/constraints厳密2種類各1/merchant1/requirement1/SKU1）を評価。 | **公式VALIDとローカルprofile適合を分けて記録**。公式JSON Schemaだけではhidden候補を認識できない。 |
| **O5 Ruby under test** | 先のO1–O4から独立してRuby研究Verifierの結果・拒否reason・Evidence生成有無を観測。**事前に宣言した期待値と照合**し、期待reasonの代わりに署名不正・空配列・例外・Schema不正で落ちた場合は完全性テストPASSにしない。 | Ruby候補の限定された挙動でありHost最終ALLOWではない。Ruby実装に完全性Gateが未実装なら **RED/HOLD**。 |

**独立性条件:** O3はSDKの`get_verified_payload()`/Rubyの同一resolverから未解決digestリストを逆算しない。固定された署名対象生wireに対し、**別経路の非破壊構文走査**でグラフを復元する。O1/O2は公知の検証済み暗号実装でよいが、O3の成功を「O1署名PASS」で代用しない。比較器と被検証Verifierで同じ“見えるConstraintだけを列挙する”ロジックを共用しない。

## 4. DC01–DC05 — 正負fixtureの施工・判定表（すべてNOT RUN）

**共通の合成正例:** Issuer P-256鍵でRoot SD-JWTを真に署名、Hostが信頼するAgent P-256鍵をRootの`cnf.jwk`として発行する。Openに `checkout.allowed_merchants` 1件（`allowed[0]`のみ）と `checkout.line_items` 1件（`items[0].acceptable_items[0]`のみ）、Merchantが署名した一致するCheckout JWTを用意する。RootのSD metadata／Disclosureは固定Issuer profileの明示許可位置だけ使用。AgentがTerminalを**独立に署名**して`aud`/`nonce`/`sd_hash`を合わせる。Host正本は合成・決済機能なし。**公式Issuerでこの完全正常形を実際に作れること自体をDC01で確かめる**。

| ID | 比較する真正署名付き提示 | 独立オラクルの必須観測 | 判定（予定） |
| --- | --- | --- | --- |
| **DC01** | 正例: Root／必要Disclosure全件／Agent Terminal／Merchant JWTをそろえる。 | O1・O2で真の署名と結合OK、O3で`_sd`/`...`残余0、O4で**公式Schema VALIDかつローカル固定profile適合**。O5の限定正例Evidenceのみ観測。 | 全条件が満たせたら **LAB_POSITIVE**（**NOT ALLOW**）。どれか未成立ならBLOCKED/HOLD。 |
| **DC02** | 同じIssuer発行権限内容を保ち`allowed_merchants` **constraint全体**をSD可能な別の**真正Issuer署名済みRoot構造**にする。正常提示と、**そのconstraintのDisclosureだけ非提示**の2種類を対照。Terminalは両提示それぞれに合う`sd_hash`で真正再署名。 | O1/O2 PASS、O3でIssuer-signed constraintの未解決commitmentが1つ以上あることを**生wireで特定**、他の信頼/暗号NGは除外。O4は必要なら公式Schema別記。 | 未解決constraint由来の **`incomplete_disclosure` REJECT** 以外は合格にしない。公式SDKがconstraint全体をSDにできなければ **BLOCKED/HOLD**。 |
| **DC03** | DC02と別のIssuer真正署名Rootで`line_items` constraint全体（または該当signed array element）を隠す; 対照は完全提示。Terminalは各提示に合わせて再署名。 | O1/O2 PASS、O3の隠れた権限commitment、O4の公式Schema **VALID/INVALID** を別々に報告。 | **完全性REJECT** が証明できる場合のみ同GateをPASS。公式Schema INVALIDによる拒否**だけ**なら完全性テストは未立証/HOLD。 |
| **DC04** | 署名構造と他要素は変えず、`allowed[0]`の**唯一の**配列要素Disclosureを除外した提示、および`acceptable_items[0]`の唯一の要素Disclosureを除外した提示を**別々に**準備。各々Terminalを有効に再署名。完全開示の対照を保持。 | O1/O2 PASS、O3で`{"...": digest}`の**正確な入れ子pathが未解決**。O4固定1要素profileは欠落を認識するが、先にO3の残余を観測・reasonを区別。 | 二つとも**`incomplete_disclosure` REJECT**。空配列/cardinality failureや`sd_hash` mismatchのみでのREJECTは**FAIL/HOLD**。 |
| **DC05** | 公式の`add_decoy_claims=True`で**実在する未解決decoy digest**をIssuerが署名した合成Rootと、decoyなし全Disclosure対照。Agent Terminalを各presentationに正しく署名。 | O1/O2 PASS、O3で**decoyが本当に元signed-wireに存在し未解決である位置**を記録。実際にdecoyが生じないならテスト作成失敗。権限candidateと区別不能な残余は無害認定しない。 | `incomplete_disclosure` / `unsupported_profile` REJECT。**decoyが発行できない場合はNOT RUN（PASSにしない）**。 |

**負例を作るときの必須分岐:** 提示Disclosureだけを間引けばIssuer JWSはそのまま有効だが、既存Terminalの`sd_hash`は変わり得るので**Agent鍵で再署名**する。Constraint全体をSDにする場合は**発行時に**Issuer鍵・正式SD metadataで正しくcommitする（JWT bodyを事後改変しない）。発行APIが狙いの権限commitmentを生成できなければ構成可能性を**不明**として別の研究課題に戻す。

## 5. 実施順序・報告スキーマ（将来の別承認後のみ）

1. **事前凍結:** pinned SDK worktreeの実SHA、依存lock/バージョン、合成Host Profile正本、許可アルゴリズム・path、期待拒否reason、resource limit、Oracle O1–O5の実装担当とコード差分を先にレビュー。事後に有利な期待値へ書き換えない。
2. **DC01 feasibility first:** 公式SDKの発行・Disclosure・Agent Terminal・Merchant JWTとO1–O4がすべて成立するか確認。正常な署名付き正例がないなら、以降の負例の「真の署名付き」証拠は不成立で**STOP**。
3. **DC02/03 issuer variants:** 発行前SD metadata変更→Issuer真正署名→正例提示と部分提示→各Terminal再署名→O1/O2 PASSを先に確定→O3/O4/O5の結果を独立比較。SDK互換なconstraint全体の選択的開示を作れない場合はBLOCKED。
4. **DC04 two subcases、DC05:** 各ケースで元wireのplaceholder／decoyを検査し、暗号・binding不良での誤PASSを排除。前提に該当しない「未解決残余ゼロ」fixtureは **INVALID FIXTURE**。
5. **結果保存と独立レビュー:** 後続の別PRに機械可読レポートとコマンド/exit status、ケース別観測を保存。提出前に**公開鍵だけ**を残し秘密鍵はcommitしない。報告とCodex/人手レビューを経るまでIssue #47を完了にしない。

**ケース別記録必須項目（例、定義のみ）:** `case_id` / `pinned_ap2_sha` / `ruby_head_sha` / `fixture_origin` / `presentation_sha256` / `root_signed_wire_commitments`（場所・個数・未解決数、機密の生disclosureは必要時のみ管理） / `issuer_signature` / `agent_pop` / `sd_hash` / `merchant_signature` / `official_schema` / `local_profile` / `completeness_oracle` / `ruby_observed_reason` / `outcome`（`PASS | FAIL | BLOCKED | NOT_RUN`） / `runner` / `command` / `timestamp`。**期待と実測を別フィールド**にする。CI successは負例安全PASSと同義ではない。

**運用制約:** 一時ディレクトリで完全合成Issuer/Agent/Merchant鍵を生成し公開鍵のみ記録。秘密鍵・証明書私有部分・本物のCheckout情報・認証トークンをgit/CI artifact/ログに置かない。ネットワーク実サービス、GCP、有料リソース、非公開Host、実支払いは用いない。サイズ・JSON深さ・Disclosure個数・時間を厳格制限、例外はFail Closed。新しいgem公開・production API変更は禁止。

## 6. 判定の境界と残作業

| 種類 | この計画での扱い |
| --- | --- |
| **SUPPORTED候補** | DC01で真正発行できる固定Issuer 2hop・完全開示、署名wire上の権限制約commitment残余ゼロ・Host固定profile適合。**現時点は候補であって実証済みではない**。 |
| **UNSUPPORTEDとしてREJECT予定** | 未開示constraint/配列要素、権限関係のdecoy・未知path・余剰Disclosure・別Issuer/layout、汎用多hop、決済判断。 |
| **UNPROVEN/HOLD** | DC01–DC05全件の署名実測、公式SDKでのconstraint全体SD発行可能性、独立O3の実装整合、Agent/CheckoutのHost現行性、nonce CAS、失効・Receipt・HC06、Phase 2-B/商用化。 |

**Issue #47を閉じる/Phase 2-Bを検討する最低条件:** 別承認でDC01–DC05を本当に実行し、全負例でO1/O2の真正署名を確認しつつ、O3の残余commitmentを原因としたFail ClosedがO5で観測されたことを、再現可能な公開鍵ベースの結果と独立レビューで示す。**どれか1つでもBLOCKED/NOT RUNまたは不一致ならHOLD。** これを満たしてもHost強失効・再生対策・Gem/実決済のGOには直結しない。

**本PRの実測:** `DC01 NOT RUN / DC02 NOT RUN / DC03 NOT RUN / DC04 NOT RUN / DC05 NOT RUN`。テスト、CI、署名fixture生成、Ruby修正は実施していない。
