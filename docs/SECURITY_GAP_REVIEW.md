# Security Gap Review & Gem GO/HOLD Gates — Phase 1 / P1-4

**審査日:** 2026-10-11 JST  
**判断:** **汎用・公開Ruby Gemの実装開始はHOLD、公開・本番・決済利用はNO-GO。既存研究コードのオフライン負例テスト強化（次のP1-5）のみGO候補**（P1-5実行には別途承認が必要）。  
**性質:** 既存のRuby研究コード・検証資料・固定AP2仕様に基づく**静的セキュリティギャップレビュー**。**P1-4で新たな攻撃実験、CI、独立監査は行っていない**。表中のHigh/Criticalは*公開時の影響と改善の優先度*の評価で、実利用環境の脆弱性を再現した「確定CVE」ではない。

## 1. 実績と境界（どこまでは確認したか）

対象リポジトリのmain固定Commit：[`fd3cc5ea5373b025ae6fe992a88e407308a5d3ca`](https://github.com/cuichangquan/ap2-mandate-verifier/commit/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca)。公式AP2は `v0.2.0` 固定Commit [`b4587ac1d055888a73b4b21750973cffba961793`](https://github.com/google-agentic-commerce/AP2/tree/b4587ac1d055888a73b4b21750973cffba961793)。

| 証拠 | 実測 | 正確に意味すること |
| --- | --- | --- |
| [P1-0](RUBY_FEASIBILITY_SPIKE.md) | Ruby 14 tests PASS | 合成Python ES256 JWT、checkout hash、公式Open Schemaの最低限の互換性 |
| [P1-1](RUBY_SDJWT_RESEARCH.md) | Ruby 10 tests PASS | **特定Issuerレイアウト**のRoot SD-JWT署名、array disclosure digest、必須Merchant開示欠落の拒否 |
| [P1-2](RUBY_DELEGATION_SPIKE.md) | Ruby 15 tests PASS、P1-1回帰10 PASS | **2hopだけ**のAgent署名、root `cnf.jwk`、`sd_hash`、Host期待 `aud`/`nonce` |
| [P1-3](RUBY_CHECKOUT_BINDING_SPIKE.md) | Ruby 18 tests PASS、P1-2回帰15/P1-1回帰10 PASS | 署名済み**架空**Merchant Checkout JWT原文・hash・店舗/SKU/数量/単純合計の狭い統合 |
| [P0-5a](PYTHON_BASELINE_VERIFICATION.md) | 公式Python pytest **186 PASS / 2 FAIL**、別途実署名負例12 PASS | 中間hop aud/nonceの上流テスト2件失敗は未解決。Rubyがその全条件に適合したという意味ではない |

**テスト件数は各テストスイートの証拠であり、全AP2適合テストの合計ではない。** P1-3の43件成功（18+15+10）は**同一Runの研究コード内**であり、実決済や本番運用を保証しない。P1-4は新テストを追加せず、既存コードをレビューしただけ。

### 最新スコープ

「Issuer署名済Open Checkout Root → 同一Agent署名済Closed Terminal」の**ちょうど2段**、Issuer/Merchant/Agent公開鍵はHostから渡される、ES256とSHA-256、開示制約が事前許可のレイアウトに適合、単一Merchant/SKU/数量完全一致/単純合計のオフライン研究のみ。他Agent転委任、複数段、Direct/Human Present、一般SD-JWT、Payment Mandate、実決済は対象外。[FAIL_CLOSED_PROFILE](FAIL_CLOSED_PROFILE.md)を維持する。

## 2. 優先順位付きセキュリティギャップ

**評価の意味:** **B0**=汎用Gemの受入れ範囲/APIを決める前に必ず解消・仕様で拒否、**B1**=限定非本番Gemの最初の実装/テストへ進む前に証拠が必要、**B2**=公開/Productionを検討する前に解消。B0/B1の未達があるため現時点では**Gem実装HOLD**。B2は重要でないという意味ではない。

| ID / 優先度 | 静的コード証拠・既知実測 | Risk / 必要な判断と負例（まだ未実行） |
| --- | --- | --- |
| **S01 / B0** JSON重複キー・解釈差 | [`research/p1_1/root_sdjwt_research.rb:60-64`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_1/root_sdjwt_research.rb#L60-L64)、[`research/p1_3/checkout_binding_research.rb:37-46`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_3/checkout_binding_research.rb#L37-L46)はJSON.parse + JWT.decodeでJOSE header/payloadを複数回パース。 | 同じJSON objectの`alg`/`iss`/`merchant.id`/`totals`等の重複キーを**必ず拒否**。parser間・後段との意味の不一致を許さない。署名済みの重複キーfixtureでテストする。**攻撃成功は未実証**。 |
| **S02 / B0** JOSE鍵/アルゴリズムの境界 | [`research/p1_1/root_sdjwt_research.rb:59-64`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_1/root_sdjwt_research.rb#L59-L64) / [`research/p1_3/checkout_binding_research.rb:37-44`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_3/checkout_binding_research.rb#L37-L44)はES256 allowlistと一部headerの拒否あり。Terminal `typ`は[`research/p1_2/two_hop_research.rb:27-30`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_2/two_hop_research.rb#L27-L30)が検査。 | `alg=none`/HS混同、未知`crit`、`jwk`/`jku`/`x5c`/`x5u`、`kid`による不意の鍵選択、typ/encoding差、JWK private `d`や無効曲線を**入口で一貫拒否**。現状の個別検査を汎用安全性とはしない。 |
| **S03 / B0** Selective Disclosure完全性 | [`research/p1_1/root_sdjwt_research.rb:88-112`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_1/root_sdjwt_research.rb#L88-L112)はarray `...` digestを追跡し、`_sd` object disclosureは拒否。2種類のConstraintを[`research/p1_1/root_sdjwt_research.rb:29-36`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_1/root_sdjwt_research.rb#L29-L36)で要求。P0-5aでは**署名が有効な非開示Merchant制約**を観測。 | 必要Constraintがhidden/decoy/unknown layout/unknown type/部分開示だったとき**一般化せずunsupportedまたはincomplete_disclosure**。デコイと正当な非開示を判別できないIssuerには対応宣言しない。Nested array/object変形の正負fixture必須。 |
| **S04 / B0** Host trustの実体 | [`research/p1_2/two_hop_research.rb:12-25`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_2/two_hop_research.rb#L12-L25)と[`research/p1_3/checkout_binding_research.rb:11-27`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_3/checkout_binding_research.rb#L11-L27)はIssuer・Agent・Merchantの**受け取った公開JWK**に依存。 | `iss`↔Issuer鍵・Merchant ID↔Merchant鍵・Account/Buyer↔委任主体、鍵ローテーション/失効の**信頼済みHost設定契約**は未設計。トークン内自称`iss`/`kid`をtrust anchorとしない。Untrusted key・鍵ID矛盾・issuer-switchの拒否fixtureが必要。 |
| **S05 / B1** Terminal Closed expiry・時刻 | [`research/p1_1/root_sdjwt_research.rb:37-39`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_1/root_sdjwt_research.rb#L37-L39)はRootの期限と`iat`、[`research/p1_2/two_hop_research.rb:34-48`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_2/two_hop_research.rb#L34-L48)はTerminal`iat`（固定300秒）を確認するが、**Closed Mandate内の`exp`を独立にチェックしていない**。 | Signed Closedの期限切れ、未来`iat`、Root/Closed順序、clock-skew境界・Host時計注入、`exp`欠落の拒否方針を決定。**署名が正しいExpired Closed**の負例が未実行。 |
| **S06 / B1** Replay/nonce一度限り | [`research/p1_2/two_hop_research.rb:12-38`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_2/two_hop_research.rb#L12-L38)はaud/nonce**値の照合だけ**、Host DBの消費履歴なし。 | 同じ有効チェーンを同時に2回使う場合の**原子的な1回消費**、Checkout sessionとnonceの紐付け、idempotency・失効のHost責務/API分割が必要。**stateless Gemだけでreplay防止達成と主張しない**。 |
| **S07 / B1** 複雑なJSON/リソース境界 | [`research/p1_1/root_sdjwt_research.rb:45-56`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_1/root_sdjwt_research.rb#L45-L56)はSD-JWT 32KiB/開示16個、[`research/p1_1/root_sdjwt_research.rb:88-112`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_1/root_sdjwt_research.rb#L88-L112)は再帰的resolve、Merchant JWTは[`research/p1_3/checkout_binding_research.rb:14-16`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_3/checkout_binding_research.rb#L14-L16)で16KiB。 | サイズ制限は一部存在するが入れ子深さ/JSON文字数/デコード後配列要素・例外時fail-closedは包括的に検証されていない。Deep nesting、巨大Disclosure、圧縮/非canonical Base64url、未知Encodingとパーサ例外を試す。 |
| **S08 / B1** Failure APIと責務分離 | [`research/p1_2/two_hop_research.rb:50-56`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_2/two_hop_research.rb#L50-L56)と[`research/p1_3/checkout_binding_research.rb:94-99`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_3/checkout_binding_research.rb#L94-L99)は検証事実をHashで返し、例外を限定rescue。 | `VerifiedEvidence`をHostの最終**ALLOW**と誤用しない型/API、unsupported/invalid/untrusted/incompleteの区別、予期しないExceptionでも**購入STOP**とする契約が必要。説明不能な成功を認めない。 |
| **S09 / B1** 取引意味論/Schema | [`research/p1_3/checkout_binding_research.rb:54-93`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_3/checkout_binding_research.rb#L54-L93)は1商品・税/割引なし、価格×数量を比較。Checkoutの全UCP Schema検証や複数商品matchingはなし。 | 余分な未知Checkout claim、正規商品IDとTitleの意味、複数SKU、Total/tax/送料・discount、不正文字列・通貨・Overflow等を「unsupported」として明示的拒否する。**厳格PoC subsetと全AP2適合の混同禁止**。 |
| **S10 / B2** 上流/仕様差分 | [AP2 `code/sdk/python/ap2/sdk/constraints.py` L407-419](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/constraints.py#L407-L419)。P1-3実行で、必要数量2/Checkout数量1は**公式Python evaluatorから違反0件**、Ruby Strict Profileでは拒否。中間hop aud/nonce pytestも2件失敗。 | 差異をOpen issue／公式要件と分けて継続追跡。仕様違反・CVEと断定せず、数量解釈の相互運用テストを追加。対応外なら明記する。 |
| **S11 / B2** Audit/Privacy/運用 | 研究コードは[`research/p1_1/root_sdjwt_research.rb:14-17`](https://github.com/cuichangquan/ap2-mandate-verifier/blob/fd3cc5ea5373b025ae6fe992a88e407308a5d3ca/research/p1_1/root_sdjwt_research.rb#L14-L17)で`minitest/autorun`をrequireし、実行時とライブラリの境界が分離されていない。 | Gem化でresearch test autorunを読み込ませない。Mandate/Buyer/Checkoutの機微データをログへ出さず、最小監査イベント・秘密鍵ゼロ保存・Ruby/Rails version matrix・依存Gem固定/脆弱性対応・Security policyを設計。 |
| **S12 / B2** 本番Merchant責務 | 現研究は署名Receipt、失効・価格/在庫正本、Buyer/Accountの最終業務認可、注文状態遷移・決済を行わない。[VERIFIER_REQUIREMENTS](VERIFIER_REQUIREMENTS.md) R10–R14。 | Hostとライブラリで**誰が拒否後のReceiptを署名するか、nonce消費するか、決済を止めるか**をAPI契約で明確化。統合試験（競合、再送、失効、返却）が完了するまでProduction NO-GO。 |

**注意:** B0/B1は現段階では**レビュー上のリスク仮説/未検証ギャップ**。P1-4では悪用可能なexploitを再現していない。「このGemにCritical脆弱性がある」と公表する根拠ではなく、そもそも**Gem製品は存在していない**。また研究用の狭いProfileで未対応入力を拒否していても、一般のSD-JWT受理が安全になったとは言えない。

## 3. 初期Gemの最小契約を成立させるための受入れゲート

| Gate | 優先 | 具体的な合格条件（将来の負例と成果物） | 現在 |
| --- | --- | --- | --- |
| **G1 Parsing/JOSE** | **Gem実装前** | 厳格に唯一の意味へパース（重複JSONキー不受理）、untrusted header/unknown alg/key・malformed SD-JWTをreject。検証済みの実署名ベクトルを改変し、false acceptanceを0件にする。 | **未実測** |
| **G2 Disclosure / Authority** | **Gem実装前** | 2-hop/Issuer指定profile/required disclosure一覧を固定。hidden/unknown/decoy/追加Constraintをrejectまたは非対応扱いにできる実証を残す。完全性が証明不能なIssuer layoutを受け付けない。 | **部分実測（P1-1/2）、汎用化未達** |
| **G3 Time / Context** | **Gem実装前** | Host提供の時計・max TTLでRoot/Closed/terminalの時刻境界を負例検証。Merchant IDと信頼鍵/Issuer IDをHost設定に束縛する契約を固定。 | **部分実測、Closed expは未検証** |
| **G4 Resource/Failure** | **Gem実装前** | 制限付き入力で巨大/深い/破損データでも**外向きの認可失敗が明確**、未知の例外をHostが成功扱いしない。 | **未実測** |
| **G5 Evidence/Host API** | **Gem実装前** | `VerifiedEvidence`と`Rejection`の意味、Issuer/Holder/Checkout Hash/Constraint実証のレベル、Host final ALLOWとの非同一性とReplay担当を文書＋テストで固定。 | **文書のみ、API未実装** |
| **G6 Public/beta/production** | **将来の別審査** | 完全なAP2対応範囲、相互運用・Ruby/Rails CI matrix、脅威モデル、依存/窓口、hostでのatomic replay/Receipt/失効/業務認可、レビュー/監査と実取引前の安全検証。 | **未達** |

G1〜G5のゲートがクリアされるまで、**汎用または外部利用を想定したGem実装はHOLD**。研究PoCの適用外の機能を「動くので対応」と拡大しない。G6は本番評価の別基準であり、G1〜G5達成だけでProduction GOとはしない。

## 4. GO / HOLD / NO-GO の再判定

| 対象 | P1-4判定 | 理由 |
| --- | --- | --- |
| **P1-5：研究コードのセキュリティ負例テスト** | **GO候補（ユーザーの別承認が必要）** | G1〜G4をオフラインで検査し、Ruby/公式Python fixtureの差を保存する。Gem雛形は不要 |
| P1-1〜P1-3研究PoCの限定利用 | **CONDITIONAL GO（研究だけ）** | 既存の厳格profileは43件の回帰検証に成功。依然として未完成 |
| **汎用AP2 Ruby Gem実装・公開API** | **HOLD** | JSON/JOSE、Time、Disclosure、Host trust契約と不明なエラー面の**未実測ゲート**が残る |
| 公開RubyGems・本番利用・実決済 | **NO-GO** | 署名Receipt、Replay/失効、Buyer/Checkout業務正本、監査/相互運用が未完成 |

**最も費用対効果が高い順序:** **P1-5（テストのみ）→ G1〜G5再点検 → 初期Gem設計GO/HOLDを改めて判断**。既存の固定Ruby/Python fixtureとGitHub Actions手動起動を再利用する。高額なGCPや実サービス検証はこの段階で不要。

## 5. P1-5として次に着手する1件（本書は実装しない）

**目的:** `research/p1_1`〜`research/p1_3`の検証器を変更せず、既存fixtureを用いて **セキュリティ負例テストを先に追加**し、現在の不足・曖昧さを**failとして実測**すること。修正は別タスクで承認を取り、失敗テストの事実を隠さずレポートする。

**最優先の6群:**

1. **Duplicate JSON keys / JOSE:** `alg`/`iss`/`merchant.id`、`crit`/`jku`/`jwk`/`x5c`、unknown `typ`、`alg=none`、不正JWK。
2. **Terminal expires:** 正規Agent署名のClosed `exp`過去、未来`iat`、Rootとの時刻ずれ、Host時計の境界。
3. **Hidden authority:** Merchant制約/追加未知制約/digest/decoy/開示不足/partial `_sd`を分類したfail-closed判定。
4. **Trust:** Merchant公開鍵入替/Host期待Issuer ID/Agent identity、Checkout ID↔nonceの関連。
5. **DoS/Fault:** JWT長/SD-JWT segment数、深いネスト、破損JSON、失敗時例外の扱い。
6. **Host contract tests:** 同一nonceの重複提示が**stateless verifier成功しても、それを業務許可とみなさない**こと。Hostのatomic consumeが別責務である限界を明示し、stateful実装まではしない。

**実行条件:** 固定AP2 v0.2 source、現在のRuby `jwt 3.3.0`に対する正負fixture。まずコードを実験用ブランチで追加し、**既存の成功に見せかけず、期待した拒否に反する例をREDとして明示**。CIは手動起動にし、必要最小の1回だけ依存を取得する。**Gem作成・GCP・実決済・公開API・他OSS変更は禁止**。

## 6. 本レビューの限界

- **P1-4は静的レビュー**。B0/B1を新しいテストで再現済みとは記載しない。既存の実測結果は各レポートとCIを参照。
- 今後のGem化で行うべきセキュリティ試験を網羅した最終脅威モデルではない。AP2 v0.2以外や外部Issuer、実プロトコル相互運用は検証していない。
- 「Hostの責務を明示すること」は「Gemが本番で安全である」と同義ではない。HostがCheckout/Agent/Issuerの正本とatomic replay制御を担い、署名Checkout Receiptを返す設計が必要。
