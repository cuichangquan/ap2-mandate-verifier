# P1-10o — A-onlyの合成実署名Checkout Mandate統合負例8件（CI実測）

**2026-10-12 JST / LIMITED SYNTHETIC RESEARCH PASS / NO PUBLIC API / NOT AUTHORIZED FOR PAYMENTS.**

[P1-10nの狭いPoC設計](VERIFIER_P110N_OFFLINE_POC_GATE.md)で提案した**AN-P01＋AN-N01〜N07の8 IDだけ**を、固定公式AP2 v0.2.0 `b4587ac1d055888a73b4b21750973cffba961793` のPython SDK発行合成Open→Closed SD-JWT、Python `jwcrypto` Merchant ES256 Checkout JWT、Ruby `jwt` 3.3.0/既存`research/`研究コードで実測。**テスト数と安全性主張を増幅しない。** Gem/安定Public API/実User/Issuer/Authority/GCP/Provider/決済/Receipt発行なし。

## 1. 一次CI実測、失敗履歴、境界

| 項目 | 一次証拠 |
| --- | --- |
| **初回CI（FAILED）** | [Actions #38153577136](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38153577136)／head `20189df89ad6f9923d975a1b2a1941bf042888bc`。**Ruby 8 runs/42 assertions/0 failures/errors/skips**は成功したが、証拠JSONの**文字列sort**では`AN-P01`が`AN-N07`の後になるにもかかわらず、CIのPythonゲートがP01先頭順と誤想定して`AssertionError: missing/duplicate/unexpected case`。**Workflow結果FAIL**、安全のPASSとは表示しない。 |
| **修正後CI（SUCCESS）** | [Actions #38153636500](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38153636500)／テスト済head `158d999776f20f92591062a920a62844b6568662`。**Ruby Minitest 8 runs/42 assertions/0 failures/0 errors/0 skips**。CIはIDの**厳密集合＋重複なし＋8件**・分類・claim-driftの証拠をチェックしPASS。 |
| **Artifacts（7日間）** | [run artifact ID 11707811563](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38153636500/artifacts/11707811563)：`p110o-results.json`、`p110o-run.log`、`p110o-python-packages.txt`。**合成署名JWT、Issuer/Agent/Merchant秘密鍵、実nonce、実PII、実決済内容はアップロードなし**。 |
| **実行環境と固定度** | GitHub ubuntu-24.04、Python 3.11、Ruby 3.3、`jwt` **3.3.0**、公式AP2 checkoutで**指定commit完全一致をチェック**。上流Pythonの**pyproject直接依存ピン＋公開PyPI**を使用。private Artifact Registry付き`uv.lock`のtransitive lock完全再現ではない。 |
| **件数・実装範囲** | 新Ruby `research/p1_10o/test_strict_a_only_signed.rb` 8 test methods、固定issuer/agent/merchant合成署名fixtureをCI時生成。既存`research/p1_2/two_hop_research.rb`の**Open→Closed固定claim保持**を追加検査、既存`research/p1_5/generate_signed_negatives.py`に**合成用署名負例だけ追加**。`research/p1_1`/`p1_3`は変更しない。 |

**修正内容の意味:** 集計ゲートのID比較だけを「配列順」→「8件の厳密な一意集合」に直した。CI未成功の歴史を消していない。資料書き込み後の最終headでもCI再実行し、これと異なる結果なら本資料を更新すること。

## 2. AN-P01＋AN-N01〜N07の実測

| ID | 実際に確認した条件 | 分類 / 結論 |
| --- | --- | --- |
| **AN-P01** | Hostが事前に設定した合成Issuer公開JWK、2hop Agent `cnf`/PoP/SD-hash、研究固定layoutの完全開示、Merchant署名済元Checkout JWT/sha256/金額 | **LIMITED_POSITIVE** — Ruby限定検証は成功。戻り値はCheckout hash/ID/金額など**証拠のみ**、`ALLOW`/Paymentはない |
| **AN-N01** | Issuer署名は正しいがMerchant制約のDisclosureを欠落、さらに第3の権限制約を隠す/すべて開示して固定profile外へ出る | **REJECTED**（3負例）。**一般的な隠れた権限制約不存在の証明にはならない** |
| **AN-N02** | 別Issuerの公開鍵・Issuer trust欠落・Merchant信頼鍵欠落 | **REJECTED**（3負例）。自称Issuer/任意trust rootの本番扱いなし |
| **AN-N03** | `cnf`で指定されたAgent以外の実署名、未対応の`issuer_jwt_hash` mode、3要素chain | **REJECTED**（3負例）。固定2hop以外は未対応。3hop否定は**長さの検査**であり中間hopの安全性を一般検証したわけではない |
| **AN-N04** | 誤/空nonce、誤audience、期限切れClosed、未来Closed iat、期限切れOpen、**期限内のAgent署名済Closed `exp`変更**、**Issuer署名済Openへ追加した`currency`固定claimをClosedが省略** | **REJECTED**（8負例）。前者は`Closed changed a fixed Open claim`、後者は`unsupported signed Open claim layout`という狙った理由までassert。形式エラーだけの拒否ではない |
| **AN-N05** | Merchant ES256で正当に署名された二重payloadキー、二重JOSE `alg`、未対応`typ`/`jku`、16KiB超Checkout、48層の深いJSON、32KiB超Root | **REJECTED**（7負例）。厳格JSON parse/max nestingとbounded profileの部分的観測。全DoS/Unicode/JOSE変種網羅とは主張しない |
| **AN-N06** | 署名有りCheckout JWTのhash偽、別Merchant鍵、Host元wireの不一致、数量不足、拒否Merchant、SKU不一致、余剰商品、合計不一致 | **REJECTED**（8負例）。公式Python SDKの数量の解釈との差は依然あり、Rubyは固定profileとしてexact quantityを強制 |
| **AN-N07** | **同じ有効なchainを2回独立に検証し両方成功**、証拠が同じで`ALLOW`/Receiptがないことを確認 | **HOST_BOUNDARY** — **replay拒否を実測したのではない**。Hostのatomic nonce consumeなしでは二重許可を防げない |

**8 test methods / 45 assertions**の中には、同じ分類ID内部に複数の署名付き変種がある。**45 assertionsを45独立セキュリティケースとは数えない**。合成fixture generator内部の検証もMinitestケース数に足さない。

## 3. R06 claim-preservation（前回PR #35 Codex P1指摘）

[PR #35のreview](https://github.com/cuichangquan/ap2-mandate-verifier/pull/35)で、`research/p1_2/two_hop_research.rb`はClosed `iat/exp`がRoot期間内に収まるだけを確認し、**Open→Closedの既存固定claimを変更されても受理し得る**と指摘された。[VERIFIER_REQUIREMENTS R06](VERIFIER_REQUIREMENTS.md)と[FAIL_CLOSED_PROFILE G03](FAIL_CLOSED_PROFILE.md)にも**共有固定claimの保存**は既に要求されていた。

- 研究2hop Verifierに`iat`/`exp`の**完全一致**と、`vct`・`iat`・`exp`以外の**共通名claim**がある場合の同値を追加。OpenとClosedの`vct`は用途が異なるため等値とはしない。
- Python固定SDKの`kb_sd_jwt.create`で、同じRoot/Agent/Checkoutから**Closedの`exp`だけを`now+3600`→`now+3000`へ変更**した有効期間内の**実署名**fixtureを発行。Rubyの単なる署名/期限内検査なら通る余地があるが、追加した同値条件で明示的に拒否。
- **この修正は研究用コードのみで正式Verifier修正ではない。** 上流の仕様全体・異なるIssuer layout/Direct/中間hopの全claim保存保証や独立監査は未実施。固定layout外は拒否する。

## 4. 明示した限界・次のGo/HOLD

- 合成Issuer固定layoutのDisclosureを**fixture生成器が知っている**ことを前提にする。Verifierが**一般的なSD-JWTの未開示Constraintが存在しないことを単独で証明**したわけではない。Issuer/Agentの外部登録・鍵rotation、複数Agent、未知constraint、Direct、3hopは未対応。
- 本実験の`VerifiedEvidence`相当は**認可ALLOWではない**。Hostは信頼設定、Checkout正本とビジネス状態、**nonce原子的消費/replay防止/operation/outbox**と最終許可を別途責任として持つ。AN-N07のHOST_BOUNDARYを**安全PASS扱いしない**。
- Host/独立Authority間の強い失効**HC06 HOLD**、C01〜C12全部OPEN/UNCONFIRMED。P1-10i H01では旧Authorityが`R_effective`後もHost COMMITを許す危険反例が実測され、今回修正したわけではない。
- **過去と混算禁止：** 正本Host **9/34件実測、25 NOT RUN（歴史的12 runs/465 assertions）**。P1-10c 8 runs/94 assertions、P1-10g 2 runs/118 assertions、P1-10i 6 runs/178 assertionsは独立合成研究。P1-0 14/17、P1-1 10/22、P1-2 15/32、P1-3 18/40、P1-6 17 GREEN/0 RED/1 HOST_BOUNDARY＋43回帰は**過去別Run**であり、このCIでは再実行していない。公式Python SDKのintermediate hop **186 PASS / 2 FAIL**も未解決。
- **P1-4 G1〜G6／P1-7 T1〜T5は全て完了とは判定しない。** H07〜H12 NOT RUN、N17 replay HOST_BOUNDARY。P1-10oの限定合成結果から汎用Gem/API/本番をGOへ変更しない。

**P1-10o判定：狭い合成2hop A-only研究の予定8 IDについて、署名付き正負入力を限定的に再実測し、P1指摘の固定claim書換えを拒否。** 他のIssuer/レイアウト・Host業務認可・replay・HC06/実決済の安全性は未証明。**汎用Gem/public API・本番Host統合HOLD、RubyGems公開・Production・実決済・署名Receipt NO-GO。** 自己レビューは独立セキュリティ監査ではない。

**次のおすすめ1件（別途明示承認が必要）：P1-10p — 静的Gapレビューだけ。** 固定layoutの前提をHostが自分で確認できるか、Root/Closed間でClaimを余さず確認するにはどんなschema/登録が必要か、P1-10oの既存8ケースで**まだ許容してしまう未対応入力**を、新規コード/CIなしで危険度つきに整理する。新Gem/API・GCP/外部サービス・実決済は別承認。

## 5. PR #36のCodex P1/P2フォローアップ（最終実測）

[P1-10o最終の修正後CI #38154695155](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38154695155)、head `12fe3b6d2cc70a7d9ed448ed99bc8d3cf76fe584`、**8 Minitest runs / 45 assertions / 0 failures / 0 errors / 0 skips**、期待した正例1・拒否6分類・AN-N07 **HOST_BOUNDARY**。証拠：[artifact 11708585368](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38154695155/artifacts/11708585368)。文書更新後の最終PR headについてもPR Checksを別途確認する。過去の8/42は**レビュー修正前の別commit実測**であり最終の42件ではない。

**Codex PR #36 P1：「Issuer署名Openの固定claimをAgentがClosedから省略すれば、共通キー交差で比較するだけでは見逃す」**。研究2hopのRootとClosedに固定Issuerの**厳格な許可キー集合**（Open: `cnf,constraints,exp,iat,vct`／Closed: `checkout_hash,checkout_jwt,exp,iat,vct`）を要求し、追加/未知固定claimを**署名が正しくても拒否**する。追加したAN-N04負例は、Issuer署名RootのOpen **Mandate disclosureそのもの**へ`currency`を加え、**DisclosureのSHA-256 digestの再計算・Root JWS再署名**を行い、公式SDKのRoot署名/開示検証でも受理された後、公式SDKでAgent署名Closedを発行。Rubyでは`unsupported signed Open claim layout`という意図した理由で拒否。**他のIssuer layoutまで互換/安全と主張しない。**

**途中の失敗を保持：** [Actions #38154446241](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38154446241)は追加claimを誤ってSD-JWT placeholderへ挿入したため`unhandled placeholder`でAN-N04失敗（**8 runs / 45 assertions / 1 failure**）。この段階では狙ったP1を未検証だったためDisclosureを修正した。次の[Actions #38154591430](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38154591430)はRuby**8/45のassertion全部成功**でも、JSON evidence noteから`claim drift`語が抜けてCI集計ゲートが失敗し**Workflow FAILURE**。最終#38154695155ではどちらも修正して**Workflow SUCCESS**。初回#38153577136も別の結果順バグによるWorkflow FAILであり経緯は§1のとおり。

**Codex PR #36 P2：** 8ケースに直接依存する`research/p1_1/root_sdjwt_research.rb`、`research/p1_3/checkout_binding_research.rb`、`research/p1_3/generate_merchant_checkout.py`、`research/shared/strict_json_research.rb`の変更にも専用CIが自動起動するよう、`pull_request.paths`に追加（既存のP1-2、P1-5も引き続き対象）。**この8-case CIは依存研究全体の完全回帰検証ではなく、一般プロトコル適合や本番利用GOにはならない。**

**GO/HOLDは不変：** 合成固定Issuer研究に限る。一般的なhidden Constraint不存在、Host final ALLOW/atomic nonce/replay、外部Authority HC06、汎用Gem/本番は**HOLD**。RubyGems公開・実決済・署名Receipt**NO-GO**。
