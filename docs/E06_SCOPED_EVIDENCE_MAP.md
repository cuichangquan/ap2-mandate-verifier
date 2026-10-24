# E06 固定profileの証拠対応表（限定判断根拠としてOwner採用済み）

整理日：2026-10-24 UTC。読解基準main：
`0b25529ea97967dbaf657bd8adb4eb26e98898a7`（PR #183統合後）。
公式AP2 pin：`b4587ac1d055888a73b4b21750973cffba961793`。
対象は `ap2.checkout.single_merchant_sku` v1、ES256/P256、
Open1→Closed1、固定3開示位置、単一Merchant/SKU、USD/EUR/JPY、empty links。

**2026-10-24 UTC、Ownerは整理済み証拠を7支持形状・固定profileに限定したE06判断根拠として採用した。E06全体合格の承認ではない。**
元E06全体はPARTIAL/OPEN、Phase2-A全面PASS・E10・本番GO未成立を維持する。研究用コア第一段階は、後続のOwner判断により固定profile・7支持形状・採用済み環境に限定して完成判断済み（[完成条件](VERIFIER_CORE_COMPLETION_CRITERIA.md#研究用検証コア第一段階の完成判断2026-10-24-utc)）。
この文書ではコード、公式Schema、原結果、pin、公開Gemを変更せず、追加実行もしない。
[完成条件](VERIFIER_CORE_COMPLETION_CRITERIA.md)と[現状](PROJECT_STATUS.md)を補足し、
[元Gate](PHASE2A_EXIT_GATE_DECISION_CHECKLIST.md)の原条件を置き換えない。

## 根拠の読み方と同一性

以下の実装・試験リンクは読解基準commitに固定する。
P＝[PurchaseBinding](https://github.com/cuichangquan/ap2-mandate-verifier/blob/0b25529ea97967dbaf657bd8adb4eb26e98898a7/lib/ap2_mandate_verifier/purchase_binding.rb)、
C＝[ScopedConstraints](https://github.com/cuichangquan/ap2-mandate-verifier/blob/0b25529ea97967dbaf657bd8adb4eb26e98898a7/lib/ap2_mandate_verifier/scoped_constraints.rb)。
行番号はこのcommitのもの。主な回帰は
[scoped 97件](https://github.com/cuichangquan/ap2-mandate-verifier/blob/0b25529ea97967dbaf657bd8adb4eb26e98898a7/test/scoped_constraints_test.rb)、
[purchase 81件](https://github.com/cuichangquan/ap2-mandate-verifier/blob/0b25529ea97967dbaf657bd8adb4eb26e98898a7/test/purchase_binding_test.rb)。
97/81は既存885件の内数であり、追加件数ではない。

独立期待値は
[Python購入/制約比較](https://github.com/cuichangquan/ap2-mandate-verifier/blob/0b25529ea97967dbaf657bd8adb4eb26e98898a7/test/o2o5_compare.py#L136)、
[固定Schema比較](https://github.com/cuichangquan/ap2-mandate-verifier/blob/0b25529ea97967dbaf657bd8adb4eb26e98898a7/test/o4_compare.py)、
[署名/開示Oracle](https://github.com/cuichangquan/ap2-mandate-verifier/blob/0b25529ea97967dbaf657bd8adb4eb26e98898a7/research/phase2a_e06i/e03_e04_signed_oracle.py)に由来する。
Ruby結果から期待値を作っていないが、合成fixture・profile設計と信頼するハーネスを共有する。
公式13Schema閉包のCheckout検証にはLineItem/Total等への参照が含まれる。
7形状を7個の独立した単体validatorで各々実測したという意味ではない。

| 証拠ID・時点 | 識別と今回への結び付き | 限界 |
| --- | --- | --- |
| MBA409 VALIDATION01（2026-10-23、ローカル保存） | report SHA256 `a329a990fca351380674639181ea487a7f2cc61f52af013f8b474727dd4bf8a4`、source manifest `d5288db5c24827fc9a7b40e3c768f75afd7bda18177a124ef500f69b9037e6e6`、regression stdout `b30c09c029980fa1b8d8539824984f11cd227ed1d5e72e87aa0a95a8818835ce`。MRI4.0.9の885件合格記録。10 product source SHA、および下記scoped/purchase/host/research/integration各試験のbytes一致を読解時照合 | ローカル原本の識別子であり、この表が原ログや第三者再現証明ではない。今回再実行していない。新しい包装の検証ではない |
| [security JSON R2](../research/security_json/results/R2/REPORT.json) | Ruby4.0.1/JSON2.19.9で30独立契約＋12境界＋8 Schema判断、記録内10 product SHAが読解基準と一致 | 旧runtimeの観測。4.0.9での再実行と呼ばない。入口観測だけで各stage正常復帰としない |
| [Stage11 O4](../research/stage11/archive/O4_VERIFIED_REPORT.json) | 13Schema/17ローカル参照、13ケース64判断。原report SHA `f45e3b94c8434ab117acba8b94ca8bfb1e37dae42a2936fb2f5205c103dcdef8` | 当時の実行/source identityを維持。現製品全体の成功Evidence試験ではない |
| [PR182 因果R1](../research/e06_causal_subset/results/R1/PROVENANCE.json) | E06-CAUSAL-MBA-20261024-R1、source `53370a3c6e85ec7850166550e740f163122afafe`。原report `fcd90c74bbfc1494b2055603006a7e67cc5b08351d95ecc52a06ae2e0cfe5069`、公開report `ca6a952ba723f0e63f79d15ad8f05a1a8a35692b20a947c83ee1603c5c590d0c`。MRI4.0.9、4/4、0.797秒 | 新規合成署名。保存wire再生ではない。公開版はworker PIDのみ除去、原本不変 |
| [PR183 意味R1](../research/e06_semantic_subset/results/R1/PROVENANCE.json) | E06-SEMANTIC-MBA-20261024-R1、source `b858d2b37b529527307957335b722b88481d7fe7`。原report `732e4f4e3e7659cb33ac48d1b84a6623df00add3c376e5d1e94fe2112323d064`、公開report `a4cc8dc1684edfc728b1abf6ede790cd4e51467b8dcb1e296d970846ed42cbe1`。MRI4.0.9、4/4、0.703秒 | 保存公開wireのbyte不変再生。新署名/秘密鍵なし。公開版はworker PIDのみ除去 |
| [公開pre3 Linux](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/40038620413) | 13 payload/10 loaded/52 installedの一致。公開archive SHAは現状メモ参照 | 52は保存期待値42＋旧API7＋入力拒否2＋constructor1。885や独立Linux Oracleの再実行ではない |

PR182/183間のproduct bytesも同一。比較器・原入力・原wire hash・観測traceはそれぞれの
[因果report](../research/e06_causal_subset/results/R1/REPORT.json)と
[意味report](../research/e06_semantic_subset/results/R1/REPORT.json)に残す。
885、30/12/8、古い13ケース64判断、各4入力、installed52を合算した「総検証件数」は作らない。
FULL等の重複対照も別命題の対照であり、新しいユニークケースとは数えない。

## 7支持形状：条件から観測への対応

実装欄は必須field/typeと追加profile条件を併記する。
テスト欄の範囲は関連する既存負例群であり、各行すべてに独立した新規実測があるとは主張しない。

| 形状・必須条件／限定条件 | 実装 | 既存テスト | 独立期待値 | 実測・拒否段階 | 証拠の限界／不足区分 |
| --- | --- | --- | --- | --- | --- |
| Open：vct/constraints/cnf、profileでiat/exp必須。2制約を所定順に1つずつ、itemsのid/acceptable_items/quantity、SKU id/title、allowed Merchant id/name。P256公開JWKと外部Agent鍵一致 | P44–49/88–93、C31–49。exact fields、配列個数、非空text・byte上限・正整数数量 | purchase102–130/159–168、scoped78–105/153–174：時刻、型、欠落、余剰/未知/重複、Merchant/SKU制約 | 固定Open Schema、Python subset/外部鍵・時刻照合 | 因果S01はIssuer/Agent/Merchant署名とbinding正常復帰後、C40→text!89でinvalid_scoped_schema。FULL正常 | 公式ではiat/exp任意だがprofileは必須という狭め方。全fieldの組合せに個別因果traceはない |
| Closed：vct/checkout_jwt/checkout_hash、profileでiat/exp必須。単一委任、Openと同じiat/exp、Checkout原文/hash一致 | P59–68/88–93 | purchase102–119/159–179：委任形状、共通claim、原文/hash、期限 | Python signed/binding、固定Closed Schema、独立digest | 各FULLで正常復帰。既存purchase負例と旧比較は各元記録の段階情報に限定 | Closedの全負例を今回再署名/再実行していない。Merchantに存在しないexp/nbfを追加しない |
| Merchant：id/name、Open許可MerchantとCheckout Merchant同一 | P72–74、C46–54 | scoped91–96/158–174、purchase131–145 | 固定Merchant Schema、Python完全値一致と独立Merchant署名 | 意味複合負例はIssuer/Agent正常復帰後、Merchant署名invalid_root_signature。binding復帰・内容検査なし | 署名負例のSchema VALIDは真正性ではない。name不一致等は既存回帰/独立predicateで対応し、新4件での個別traceとはしない |
| Checkout：id/line_items/status/currency/totals/links、profileはmerchantも必須、ready_for_complete、単一行、USD/EUR/JPY、Host値と一致、empty links | P71–75、C51–59/69–75 | purchase131–145、scoped74–76/117–139 | 固定Checkout Schema（参照閉包）、Python currency/identity/math | FULL正常。意味TOTALS_ONLYは3署名/binding復帰後C75→totals!109でamount_mismatch。公式Schema VALID | buyer/messages等任意形状は非対応として拒否。Host出所/最新性は検査済みとしない |
| LineItem：id/item/quantity/totals、profileは単一、数量正整数≤1000000かつMandate数量一致 | C60–63/69–70、83–94 | scoped107–112/135–149/158–174 | Checkout参照Schema＋Python strict quantity/等値 | 意味QUANTITY_FLOATは公式Schema VALIDだが3署名/binding復帰後quantity!93でinvalid_scoped_schema | JSON Schema integerとRuby Integer限定の差は意図的。2.0は一般Schema違反とはしない。parent_idは非対応 |
| Item：id/title/price、profileはSKU id/title一致、price非負Integer≤9007199254740991、積算も同上限 | C64–73/88–98 | scoped97–105/113–115/141–151/171–174 | 固定Item Schema、Python price/積算/Host金額 | 因果PRICE_STRINGは署名/Closed/Host digest整合、3署名/binding復帰後amount!97でinvalid_scoped_schema。FULL正常 | PRICE_STRINGの前段不整合による拒否を合格にしていない。image_url非対応 |
| Total：type/amount、profileはsubtotal/total各1、非負Integer、lineとCheckout双方が積算/Host totalに一致 | C74–75/100–109 | scoped123–134/141–151 | Checkout参照Schema＋Python totals完全照合 | 意味TOTALS_ONLY：積算・Host・line totals200、Checkout totalだけ201、totals!109拒否。複合異常は署名先行で内容未到達 | Schema上のinteger/許容typeより狭い。tax/discount/display_text非対応。全異常組合せの保証ではない |

## 統合順序・失敗閉鎖・周辺境界

| 条件 | 実装／既存試験 | 独立期待値と実際の証拠 | 限界 |
| --- | --- | --- | --- |
| 署名/開示/購入bindingが必要な内容検査に先行 | P42のRoot閉包、P51のAgent署名、P70のMerchant署名、C28のPurchaseBinding呼出し、C31が最初の実内容check。[integration16件](https://github.com/cuichangquan/ap2-mandate-verifier/blob/0b25529ea97967dbaf657bd8adb4eb26e98898a7/test/integration_matrix_test.rb)、purchase/scoped試験 | PR182/183 observerは呼出しだけでなく正常復帰/例外をwire hashと対応。FULLは復帰、S01/price/2.0/totalsは有効署名後の実拒否、Agent/Merchant破損は内容未到達 | 全パスの形式証明ではない。入口wrapperをstage PASSと呼ばない。前段拒否を後段の検証成功に数えない |
| 不正・不明入力でEvidenceなし、全条件後だけ研究Evidence | [研究入口](https://github.com/cuichangquan/ap2-mandate-verifier/blob/0b25529ea97967dbaf657bd8adb4eb26e98898a7/lib/ap2_mandate_verifier.rb)、[ResearchResult](https://github.com/cuichangquan/ap2-mandate-verifier/blob/0b25529ea97967dbaf657bd8adb4eb26e98898a7/lib/ap2_mandate_verifier/research_result.rb)、[research178件](https://github.com/cuichangquan/ap2-mandate-verifier/blob/0b25529ea97967dbaf657bd8adb4eb26e98898a7/test/research_evidence_test.rb#L55) | 両subset FULLのEvidence全字段を独立期待値と照合、全負例nil。既存constructor/例外/旧低レベル非成功試験も885の内数 | Evidence≠ALLOW、同一信頼Ruby内の検査事実。外部再構成真正性/実決済を証明しない |
| 期限交差・terminal age・Host challenge参照 | P56–66/88–93、[host149件](https://github.com/cuichangquan/ap2-mandate-verifier/blob/0b25529ea97967dbaf657bd8adb4eb26e98898a7/test/host_binding_test.rb#L136) | 既存300/301、開始inclusive/終了exclusive、鍵/snapshot/challenge/Open/Closed期間の境界証拠。新4＋4入力の再測定対象外 | 実時計・運用失効・nonce原子消費/注文CASはHost責務。Gem要件へ追加実装しない |

## 不足の分類と次の最小判断

- **未実装扱いにしない**：閉じた7形状の必須field/type/制約に、今回の読解で具体的な実装欠落は特定しなかった。一般Schema engineや任意のAP2形状は対象外だが、必須field欠落を非対応の語で隠した結論ではない。
- **証拠の紐付け**：本表で旧回帰、独立predicate、公式Schema判断、最近の実因果traceを対応付けた。全条件それぞれの新規独立因果traceはない。上記の静的対応＋既存回帰＋代表的独立因果観測は、7支持形状・固定profileに限定したE06判断根拠としてOwner採用済み。全fieldの個別因果traceや一般Schema適合の証明へ拡張しない。
- **追加必須試験**：この閉じた範囲について具体的な追加必須ケースは今回未特定。十分な既存証拠を既定で再実行しない。Ownerがより強い命題を要求する場合のみ、当該差分を限定し、新しい比較の目的・期待拒否段階・承認範囲を定める。
- **未証明**：信頼ハーネス/同一プロセスの完全性、実Issuer/Host信頼入力の真正性・最新性、clock/revocation運用、最悪CPU/RSS/並行保証、歴史的通信会計2件と後続の送信header/全通信128MiB遵守。比較の一致で解消しない。
- **採用済み／残る判断**：限定E06判断根拠と初回の対応環境・保証範囲はOwner採用済み。対応環境の正確な観測・保証除外は[完成条件の追補](VERIFIER_CORE_COMPLETION_CRITERIA.md#初回の対応環境保証範囲owner採用済み)を参照。後続のOwner判断により、信頼するHost入力/Ruby環境を前提とする研究用コア第一段階は採用済み範囲で完成判断済み。E06全体PASS、Phase2-A全面PASS、E10/本番GOはこの文書の統合から導かない。

第一段階の完成判断は既存証拠の限定採用であり、一般AP2・発行/提示・実Host運用・最悪資源/並行性能の保証ではない。通信会計未証明も保持し、追加試験・実装拡大・再包装・追加公開を自動開始しない。
