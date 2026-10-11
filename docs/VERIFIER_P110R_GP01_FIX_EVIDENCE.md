# P1-10r — GP01未知ネストConstraintの限定Fail Closed修正・正署名回帰

**2026-10-12 JST / FIXED ISSUER SYNTHETIC RESEARCH ONLY / GP01 LIMITED REJECT CONFIRMED / NOT A PUBLIC GEM**

[P1-10qの修正前RED反例](VERIFIER_P110Q_GP01_EVIDENCE.md)では、既知`checkout.allowed_merchants`の署名済みConstraint内部に架空の未知`policy_override`属性を追加しても、RubyのA-only研究Verifierが**ACCEPT**した。Issuer・Agent・Merchantの署名とSD-JWT Disclosure digestは真正であり、以前の**SECURITY RED/HOLD**という歴史的な観測は変更しない。

P1-10rでは、**合成固定Issuerの既知Constraint構造に限って**全階層の既知フィールド集合をチェックする、**研究用の局所Fail Closed**を追加した。同じGP01 generatorを使って予期しない署名済みフィールドを**意図した理由でREJECT**し、別の正常な署名付きCheckoutが引き続き検証できることを観測。**一般的AP2適合/Issuer多様性、本番決済、外部Authority HC06、Gem/APIにGOは出さない。**

## 1. 結果（別のCI実行を混算しない）

| 時点・対象 | 署名とCheckoutの条件 | 実測および意味 |
| --- | --- | --- |
| **修正前P1-10q** | 合成Rootの署名＋2層Disclosure digest＋Agent/Checkout署名が有効 | [最終観測CI #38184315222](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38184315222)：**1 run/8 assertions**、Rubyが`policy_override`を**ACCEPT = SECURITY RED/HOLD**。この履歴を消さない |
| **P1-10r初回CI：FAILED** | GP01の意味的REJECT自体は確認したが、**正常系Minitestに余分な`checkout_wire` keyword引数**が残って例外となった | [CI #38185616542](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38185616542)：**2 runs / 5 assertions / 1 error**。Workflow FAILを安全性PASSと誤記しない。テスト呼び出しだけ修正 |
| **P1-10r修正後CI** | **同じ正署名GP01**を使って拒否理由を明示、さらに別の合成正常署名Checkoutを検証 | [CI #38185735639](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38185735639)：**2 runs / 10 assertions / 0 failures/errors/skips**。GP01は`unsupported or missing signed Constraint profile fields`で**REJECT**、既知正常形は`VerifiedEvidence`相当の事実Hashを返す（Host ALLOWではない） |
| **旧P1-10oの8ケース回帰** | 固定Issuer/2hop/Merchant署名の先行8ケース全部 | [CI #38185735652](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38185735652)：**8 runs / 45 assertions / 0 failures/errors/skips**。AN-N07は2度verifyできる**HOST_BOUNDARY**でありreplay防御PASSでない |
| **P1-10q観測スクリプト再実行** | 修正後の研究Verifierを**同じ署名済みGP01 probe**で観測（P1-10qコードは観測専用） | [CI #38185735644](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38185735644)：Workflow SUCCESS・**REJECT**（限定拒否を観測しただけ）。**過去のP1-10q REDをなかったことにしない** |

上記はソース変更後・文書作成前の実測。最終PR headのCI成功も別途確認する。**P1-10rは新規2 Minitest test methods（2/10）**、過去のP1-10o 8/45・P1-10q 1件・Host正本測定とは**独立**。

## 2. 実装した最小のローカル制約

変更範囲は既存`research/p1_3/checkout_binding_research.rb`の**研究用 Checkout 最終照合**のみ。署名の検証／SD-JWT digestの演算／公開APIは変更しない。

| Issuer署名済みの固定オブジェクト | 許容するキー（完全一致） |
| --- | --- |
| `checkout.allowed_merchants` | `type, allowed` |
| `allowed[0]` Merchant | `id, name` |
| `checkout.line_items` | `type, items` |
| `items[0]` requirement | `id, acceptable_items, quantity` |
| `acceptable_items[0]` Item | `id, title` |

固定レイアウトと異なるキー集合（未知・欠落）は`AP2RootSDJWTResearch::Rejected`で**`unsupported or missing signed Constraint profile fields`**とする。**トップレベルOpen/Closedの許可キー検査は既存P1-10oと同じ**。新しいConstraint type/複数Merchant/複数商品/他Issuer profileを「サポート」と解釈しない。

**重要な規格上の区別：** [公式AP2 v0.2.0固定Open Checkout Schema](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json)は当該Constraintに`additionalProperties: false`を宣言していない。**このOSSの限定プロフィールによる未知キー拒否 ≠ AP2公式Schemaがすべての追加キーを禁止**。合法なIssuer独自の拡張も意図的に拒否し得るが、**将来の汎用化は別設計・別承認**。

## 3. 追加の報告精度修正

P1-10qの旧`observe_gp01.rb`は、Verifier自身を修正したPRで再利用しても、Artifactに`no_fix_applied_to_existing_verifier: true`と**誤った主張**を残した。P1-10rでは観測結果の`ACCEPT/REJECT`ロジックを変更せず、この報告フラグのみ`observation_script_does_not_modify_verifier: true`へ変更。対応するP1-10q CIの意味検査も同様に更新し、「この観測スクリプトはVerifierを変更しない」と正確に記載する。**元のP1-10q RED証拠は独立した実行・artifactとしてそのまま残す。**

## 4. セキュリティの判断・今後の1件

- **今回のGP01固定研究レイアウト：限定REJECTを実測。** 「署名が正しければ意味を見ずに受理する」局所的な失敗を、この固定入出力に限って塞ぐ。**他の未知field/SD-JWT構造への一般的保証、AP2プロトコル全体の適合性、第三者セキュリティ監査を意味しない**。
- GP02未開示Constraintの一般的完全性、GP03外部Issuer正本/trust、Host業務最終ALLOW・nonce原子消費/replay、外部Authorityの強い失効**HC06 HOLD**は未解決。P1-10i H01旧Authorityの危険反例、外部契約C01〜C12 OPEN/UNCONFIRMED、H07〜H12 NOT RUN。
- Host正本**9/34件実測・25 NOT RUN（従来12 runs/465 assertions）**、P1-10c 8/94、P1-10g 2/118、P1-10i 6/178とは分ける。公式Python intermediate-hop **186 PASS / 2 FAIL**未解決、N17はHost replay境界。
- **汎用Gem/public API、本番Host統合・HC06はHOLD、RubyGems公開/Production/実決済/署名Receipt NO-GO。** GP01が固定合成ケースでREJECTへ変わってもこれらの判断を変更しない。

**次のおすすめ（別途明示承認後のみ）：P1-10s — 固定Constraintプロファイルの残りの未知・欠落・型の意味を設計/負例のどちらかに限定して整理する。** 一般的な外部Issuer互換・Gem/API化/決済などへの拡大は別途判断する。本資料だけでは次の実装/CIを許可しない。
