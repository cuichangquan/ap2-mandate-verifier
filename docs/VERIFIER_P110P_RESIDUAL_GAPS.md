# P1-10p — A-only Verifier 残余リスク・Issuer Layout / Constraint Gapレビュー

**2026-10-12 JST / STATIC DESIGN REVIEW ONLY / 新規テスト・CI・実装 0件 / NOT A SECURITY AUDIT**

基準：公式AP2 v0.2.0 commit `b4587ac1d055888a73b4b21750973cffba961793`。研究用Ruby正本：[P1-1 Root](../research/p1_1/root_sdjwt_research.rb)、[P1-2 2hop](../research/p1_2/two_hop_research.rb)、[P1-3 Checkout](../research/p1_3/checkout_binding_research.rb)、[厳格JSON](../research/shared/strict_json_research.rb)、[P1-10o 8ケース](../research/p1_10o/test_strict_a_only_signed.rb)。先行[設計ゲート](VERIFIER_P110N_OFFLINE_POC_GATE.md)と[最終CI実測](VERIFIER_P110O_EVIDENCE.md)を対照した。**今回行ったのはコード・資料の静的照合のみ。Ruby/Pythonプログラムを実行せず、CIも変更/起動していない。**

**P1-10o実測は固定合成Issuer、Open→Closedの2hop、1商品/1Merchantの範囲で [Actions #38155050010](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38155050010) が 8 runs / 45 assertions / 0 failures/errors。** AN-P01は限定正例、AN-N01〜N06は拒否分類、AN-N07は**2度verify可能というHOST_BOUNDARY**。過去の8/45を本レビューの新規検証結果に加算しない。トップレベルOpen/Closedに許可キーの**完全一致**を導入したことは確かだが、それだけでネストしたConstraintやSD-JWTの汎用意味解析まで証明できない。

## 1. 重要な判断

> **最優先の次の検証対象は「Issuer署名自体は有効だが、既知のConstraintオブジェクトの内部に未知の権限関連フィールドがある」ケース。** 現状は**静的な受理可能性の疑い**であり、実署名負例による攻撃成功の実測ではない。**未知フィールドを既存のMerchant/SKU/数量チェックが解釈せずに通過させるおそれ**があるため、汎用Verifier拡大より先に隔離テストが必要。

**残余リスクの重大度は、将来の汎用Gem・Merchant本番運用に誤って転用した場合の影響を評価するレビュー上の相対順位であり、実被害・確定脆弱性・CVE判定ではない。** 各GP項目は今回新規の**テスト未実施（NOT RUN）**。既にP1-10oでカバーした一部負例を新規成功として数えない。

## 2. ギャップ一覧（技術的根拠と次の判定ゲート）

| ID / 優先順位 | 静的に分かること・未検証のリスク | 実証状況と必要な証拠 | 現時点の扱い |
| --- | --- | --- | --- |
| **GP01 / 高・次の1件** | `root_sdjwt_research.rb` は`constraints`の**タイプ集合が2種**か確認し、`checkout_binding_research.rb`は`allowed[0].id`、SKU、数量等を読む。しかし**署名済みConstraintオブジェクトやその内部辞書のキー集合は完全一致で検査しない**。未知属性が追加された場合の無視・権限意味逸脱の可能性。 | **今回NOT RUN**。同一Issuer/Agentの正署名Root/Terminalで、例えば`checkout.allowed_merchants`へ架空の追加`policy_override`属性を入れる一つの合成ケースを構築し、**暗号・開示が正しいことを独立検証したうえでRubyの結果を観測**。想定外受理なら**RED/HOLD**、拒否ならどの段で拒否したかを明示。 | **一般化HOLD／最優先で隔離負例を提案** |
| **GP02 / 高** | `verify_signed_payload!`は開示プレースホルダーの欠落/余剰に限定的にFail Closedするが、**一般のIssuerレイアウトで権限Constraintの「全量」を外部から証明できるわけではない**。デコイ・未知の開示構造・同じtypeの意味差は未解決。 | **NOT RUN（汎用完全性）**。既知fixtureでのAN-N01受理拒否を、未知Issuerの全Constraint完全性の保証に昇格させない。Issuer発行layout、開示数/構造、未知policyを扱う正本契約が必要。 | **汎用HOLD** |
| **GP03 / 高** | 2hop研究コードは**Openキー集合`cnf,constraints,exp,iat,vct`／Closedキー集合`checkout_hash,checkout_jwt,exp,iat,vct`**を固定し、Issuer追加`currency`やClosed`exp`改変の拒否は実測した。ただし**Issuerが合法に持つ別layout/他の共有固定claim・Direct/中間hopには拡張できない**。固定layoutをHostが独立に認証・版管理できるかは未設計。 | **拡張NOT RUN**。Hostに事前登録されたIssuer ID、profile/schemaバージョン、許可フィールド・型・必須/optionalと比較し、**Open側の全固定claimの引継ぎ義務**を仕様と対応させる。現在の`other_shared`は固定キー交差で空集合となりやすく、汎用保存検証の証拠ではない。 | **他layout HOLD** |
| **GP04 / 高・Host境界** | Hostから渡された`trusted_issuer_public_jwk`等を使用するが、外部署名者のIssuer ID/tenant/purpose/audience/鍵ローテーション・剥奪が本当に正本に結び付くかは**Host trust model次第**。ヘッダー`kid/x5c`の自己申告は信頼しない方針。 | **外部運用NOT RUN**。Host正本による信頼Issuer/鍵/用途/merchant/tenant/profile/versionの登録・変更/失効、対象Checkoutとの結合、および不明時STOPの契約証明が必要。実Issuer照合はしていない。 | **実Issuer/HOST統合HOLD** |
| **GP05 / 高** | `checkout_binding_research.rb` はCheckout**トップレベル、merchant、cart line、product、totals**の固定キーを確認するが、`links`や**Issuer署名側のConstraint内部**の全意味を一般的に検査しない。SKU/quantityは研究用に**exact match**、1商品・税なし・手数料なし・合計固定で、公式SDKの一般的な数量解釈とも異なる。 | **汎用Checkout NOT RUN**。公式Checkout Schemaとの対応表・認可に影響するネスト項目すべての意味と未知値のREJECTを設計。割引/送料/税/複数明細/権限拡大をサポート済みと主張しない。 | **汎用Checkout HOLD** |
| **GP06 / 高・Host境界** | `expected_nonce/aud`と期限は検証するが、`Time.now`直接利用でHostから時刻/許容skewを注入する最終契約はない。AN-N07では**同じ有効chainを2回検証できた**。Hostによる一度限りのnonce消費・Checkout確定レース防御・撤回をAの成功は証明しない。 | **AN-N07 HOST_BOUNDARYは実測済み／Host強安全性は未検証**。Hostが同一operation/nonce/Checkout正本で原子的に1回しかALLOWしない契約と負例が必要。 | **Host final ALLOW/本番HOLD** |
| **GP07 / 中** | `strict_json_research.rb`は二重JSONキー、最大nesting40などを厳格化。Root/Terminal JWS最大32KiB、Checkout最大16KiB等の局所上限はある。しかし**全Unicode/数値変種、SD-JWT disclosure計数/エラー、JOSE拡張・特殊header、全負荷/リソースDoS**を網羅していない。 | **追加変種 NOT RUN**。固定protocolの入力容量・深さ・処理時間・error分類・異常復旧を境界値で検証。P1-10o AN-N05は7負例の限定観測のみ。 | **一般公開HOLD** |
| **GP08 / 中** | CIは公式AP2 source SHAをピンするが、Pythonは公開PyPIから上流直接依存を入れ、**private registry付きupstream `uv.lock`のtransitive版までは再現しない**。P1-10oは8test/45assertionのみで、Ruby旧研究43件回帰や公式Python全suiteを再実行していない。 | **互換性/網羅NOT RUN**。Pin/lockの保証範囲、Ruby/Pythonケース対応、完全回帰の別実行計画を設計する。公式Python中間hopは過去**186 PASS/2 FAIL**のままで、上流欠陥と断定しない。 | **汎用互換HOLD** |
| **GP09 / 高・別トラック** | 独立Host↔AuthorityのHC06、durable terminal gate・真正Host proof・anti-rollbackはAの暗号成功と**別責務**。P1-10i H01は旧Authorityの`R_effective`後にHost Cが成功する**危険な反例**だった。 | **GP09で新実験NOT RUN**。外部C01〜C12 **OPEN/UNCONFIRMED**、H07〜H12 NOT RUN、Host正本9/34・25 NOT RUN。 | **B/HC06 HOLD** |

### GP01の優先順位に関する注意

- **トップレベルが厳格であることと、ネストした権限制約が厳格であることは別。** 公式Open JSON Schemaが存在することは、現在のRuby研究コードがそのスキーマを全階層で検証していることを意味しない。
- **未知の追加フィールドがすべてAP2で意味を持つと断定しない。** 未認識属性が権限に関係するか判断できなければ、固定研究profileではREJECTする設計が安全側の候補。**不適切なACCEPTを実測するまでは「確定した攻撃」と書かない。**
- Issuer/Agent署名を持つ反例生成では**OpenのDisclosure digest再計算と署名原文整合性を独立検査**し、壊れたtokenが単にパース段階で拒否される結果を、GP01の安全性PASSとして扱わない（[P1-10oでの失敗履歴](VERIFIER_P110O_EVIDENCE.md#5-pr-36のcodex-p1p2フォローアップ最終実測)）。
- **GP01だけを修正/拒否できても** GP02 hidden disclosure一般完全性、GP03外部Issuer profile正本、GP06 replay、GP09分散失効は解決しない。

## 3. 必要なIssuer Profile正本（将来の契約案・NOT IMPLEMENTED）

固定合成fixtureの外へ進むための研究上の必要条件を整理する。**ここで公開APIや設定ファイル形式を決定しない。**

| Hostが独立に決める情報 | 今の研究での位置付け | 「不明」時の期待判断 |
| --- | --- | --- |
| 許可Issuer identity / 署名アルゴリズム / 公開鍵 / 有効期・ローテーション・tenant・用途 | 今は研究fixture由来の公開JWK等をHost相当の呼び出し元が渡す。実登録簿の信頼性は未検証 | **STOP / Rejection** |
| 標準AP2版＋Issuer profile版、許可するOpen/Closed claim完全集合と型、必須/optional | トップレベルは現在の合成layoutにハードコード。別合法layoutはHOLD | **HOLD / REJECT** |
| 必須Constraintの種類・件数・**各Constraint内部のキー集合とネスト形状**、unknown field policy | 現在の研究コードは種類と主要値中心。署名された追加権限フィールドの一般的意味は未確定 | **REJECT / HOLD** |
| Full Disclosureの信頼できる成立条件、未開示権限/デコイの扱い | テスト作成側がレイアウト既知であることを前提。一般的完全開示を証明しない | **REJECT / HOLD** |
| Checkout JWT原文の正本、Merchant署名鍵/Checkout ID/期待aud/nonce/最新業務状態 | 署名/hashと固定merchant/SKU/数量は一部実測。nonceの消費/注文確定はHostが担う | **Host STOP** |
| 受入後の結果の意味：VerifiedEvidence/Rejection≠Business ALLOW | P1-10oは購入もReceiptも生成しない | **ALLOWへ変換しない** |

## 4. 次の単一提案とGO/HOLD

**P1-10p判断：静的Gapレビューのみ完了。** GP01〜GP09は**今回実行した試験IDではない**。P1-10oの**8 runs/45 assertions**を超える検証成功を主張しない。固定Issuer layoutは研究上の有効な境界だが、**未知のネストした権限関連fieldを拒否する検証が十分であるとの実測はまだない**。よってA-onlyの汎用対応・Public API・Gem公開・本番Host統合のGOへ進めない。

**次のおすすめ1件（別途ユーザー明示承認後のみ）：P1-10q — GP01限定の1つの合成実署名負例検証。** 正規Disclosure・Issuer署名/Agent署名・merchant Checkoutを保ちながら、既知`checkout.allowed_merchants`のネストに**研究用の未知`policy_override`フィールドを追加**し、既存Rubyがそれを**ACCEPT/REJECT**するかを**隔離オフライン専用CI**で正直に観測する。**不適切にACCEPTされた場合はRED/HOLDを記録し、別承認なしに修正コード追加・既存安全性主張を変更しない。** 正例/負例を水増ししない。CI・コード変更自体はP1-10qの別承認事項であり、このPRでは実行しない。

**継続HOLD：** 一般的Issuer trust・SD-JWT hidden Constraint完全性・任意layout/multihop、Host replay/atomically-consumed nonce、外部HC06、公開Gem/API、本番Host。**RubyGems公開・Production・実Checkout/決済・署名Receipt NO-GO。** Host正本**9/34測定・25 NOT RUN（過去12 runs/465 assertions）**、P1-10c **8/94**、P1-10g **2/118**、P1-10i **6/178** は混算しない。N17 Host replay境界、H07〜H12 NOT RUN、Python intermediate hop**186 PASS/2 FAIL**は未解決。**P1-10p新規テスト/CI実行0件**。
