# P1-10s — 固定Issuer Constraint内部の未知・欠落・型の残余Gap（静的レビュー）

**2026-10-12 JST / DESIGN ONLY / 新規Ruby・Pythonコード0、新規テスト0、CI実行0 / NOT AN AUDIT**

**基準：**公式AP2 v0.2.0 pinned commit `b4587ac1d055888a73b4b21750973cffba961793`、[Open Checkout JSON Schema](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json)、[Merchant Schema](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/types/merchant.json)、[Ruby研究用Checkout Verifier](../research/p1_3/checkout_binding_research.rb)、[Root](../research/p1_1/root_sdjwt_research.rb)、[P1-10r回帰テスト](../research/p1_10r/test_gp01_fix.rb)を**静的に照合**した。外部Issuer・Host・実決済は使っていない。

**直近の実測（本Stepで再実行していない）：** [P1-10r final head CI #38185897025](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38185897025)は**2 runs / 10 assertions / 0 failures/errors**、**正しい合成署名の未知フィールドGP01を意図した理由でREJECT**し、既知正常Checkoutは**検証証拠のみACCEPT**。[P1-10o回帰 #38185897050](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38185897050)は**8 runs / 45 assertions / 0 failures/errors**（AN-N07 replayは**HOST_BOUNDARY**）。[歴史的P1-10q](VERIFIER_P110Q_GP01_EVIDENCE.md)の**修正前GP01 ACCEPT / SECURITY RED-HOLD**は削除せず、修正後の限定REJECTと両方維持する。

## 1. 結論：キー集合の厳格化と型・値の検査は別

P1-10rの`require_exact_constraint_keys!`は署名済みConstraintオブジェクトの**キー集合が固定の5つの構造と一致すること**を強制する。しかし**そのキーに対応する値の型・必須の非空条件・相互関係のすべてを検査する処理ではない**。

- `allowed_merchants` : `type, allowed`
- `allowed[0]` のMerchant : `id, name`
- `line_items` : `type, items`
- `items[0]` のRequirement : `id, acceptable_items, quantity`
- `acceptable_items[0]` のItem : `id, title`

既知のフィールド名でも値が`null`、数値、配列などであれば、**単なるキー集合比較は通過できる**。以下の発見は**コード上の具体的な潜在的受理経路**であり、今回署名付きfixtureを生成して受理成功を再現したという意味ではない。

## 2. リスク・検証ギャップ（P1-10s専用ID、すべて新規NOT RUN）

| ID / 優先度 | 対象 / Rubyの現在の条件 | 公式Schemaとの差・起こり得る影響 | 次に必要な証拠 / 状態 |
| --- | --- | --- | --- |
| **S01 / 高（最優先）** | **`items[0].id`**：`acceptable_items,id,quantity`のキー集合は必須。しかし、Requirement自体の`id`の**String型や内容をRubyでチェックしていない**。 | 公式`$defs.line_item_requirements.properties.id.type = string`。正しく署名されても`id: 123`や`id: null`のような**Schema-invalid値の見落とし疑義**。Checkout IDとの結合要件は仕様・実装別途精査が必要で、今回推測しない。 | **新規NOT RUN**。合成Issuer/Agent再署名・Disclosure digest整合を独立確認し、**Ruby ACCEPT/REJECTを1件観測**。公式Schema上のINVALIDと暗号のVALIDを区別。 |
| **S02 / 高（型検証）** | **`allowed[0].name`**：Merchant子辞書の`id,name`キー集合は厳格だが、**`name`のString型検査がない**。`allowed[0].id`はHost期待Merchant IDに一致する必要あり。 | 固定Merchant Schemaは`name.type = string`、ただし非空`minLength`の制約なし。`name: 123`や`name: null`のような型逸脱があり得る。**Merchant表示名であり、直接の権限昇格は未証明。** | **新規NOT RUN**。数値/NULLをIssuer署名済みDisclosureで観測し、Verifierの型拒否有無を評価。 |
| **S03 / 中（未確認の負例）** | **未知ネストキー・既知必須キー欠落**：5構造のいずれも`object.keys.sort == expected_keys.sort`を強制するため、原理上は未知・欠落キーを拒否する設計。 | P1-10rで実際に確認したのは`checkout.allowed_merchants.policy_override`の**未知キー1件だけ**。残り4階層の未知キーと、5階層のキー欠落を網羅していない。 | **新規NOT RUN**。5階層それぞれの署名済み正規Disclosureで拒否を個別に確認（件数計画は別承認）。 |
| **S04 / 中（型・境界）** | **`allowed`, `items`, `acceptable_items`配列**：Rubyは1件・Hashという形を確認する。**`items[0].quantity`は正のInteger**、`acceptable_items[0].id/title`は非空String。 | 公式Schemaは`quantity`正の整数だが、`Item.id/title`はStringであり非空は明示していない。Rubyの**非空**要件は追加のローカル制約。空配列、2件、非Hash、数値境界などの**新規組合せ**は今回未試験。 | **新規NOT RUN**。Schema MUSTとローカル厳格化を別カラムにして、代表的な境界値を検証。 |
| **S05 / 中（相互関係）** | **Requirementの`id`とCheckoutの`line_items[].id`**：現在、前者は型未確認で、後者とのID同値チェックも要求していない。 | 公式SchemaではRequirement`id`は識別子だが**Checkout lineとの同値が必須だと本資料からは断定できない**。許可すべき意味・対応規則は別仕様レビューが必要。 | **新規NOT RUN / 意味契約UNKNOWN**。推測で厳格一致を足さず、公式文書との対応・想定Host事業者ルールを先に確認。 |
| **S06 / 中（互換性）** | **Merchantの`website`**：公式Merchant Schemaでは**任意String属性**だが、固定研究プロファイルの`allowed[0]`は`id,name`だけで完全一致。 | 正当な公式Schema表現でも`website`があれば研究コードは**意図的に拒否する可能性**。これはローカルプロフィールの**非対応**であり公式Schema違反・攻撃とは違う。 | **新規NOT RUN**。将来Issuer profiles導入時はoptional属性と未知権限属性を分離して定義。 |
| **S07 / 高（スコープ境界）** | **選択的開示の全量性・Issuer trust正本・任意レイアウト**は署名済みConstraintのキー集合チェックだけで完結しない。 | 本研究fixtureのIssuerレイアウトを生成側が知る前提。他Issuer / hidden権限 / 中間hopを、キー照合成功から一般化してはならない。 | **NOT RUN（汎用）/ HOLD**。Host独立のIssuer profile正本・全量開示契約を定義するまで拡張なし。 |
| **S08 / 高（責務境界）** | **Host nonce原子的消費・business ALLOWと外部Authority HC06**：A-only暗号研究とは別。 | P1-10o AN-N07は同じchainが2回verifyできる**HOST_BOUNDARY**。P1-10i H01は旧Authority失効後もHost COMMITした危険反例。 | **本Step NOT RUN / HOLD**。外部C01〜C12 OPEN/UNCONFIRMED、H07〜H12 NOT RUN、Host正本9/34実測・25 NOT RUN。 |

**「新規NOT RUN」はS01〜S08の追加仮説・負例を今回実行していないという意味。** P1-10rでGP01の未知フィールドREJECTを1件観測済みである事実は変えない。8つのGapを「8件の新テスト」と数えない。

## 3. 型・キー・意味・署名の4つのゲートを混同しない

| 層 | 何を証明するか | P1-10r後の状態 |
| --- | --- | --- |
| **署名・Disclosure** | Issuer/Agent JWS、digest chain、Checkout JWT原文が改変されていない | 既知合成2hopで限定実測。**署名が有効でもSchema適合は別** |
| **キー集合** | 認めたオブジェクトに想定外/欠落のフィールド名がない | 固定5オブジェクトで研究コードが完全一致を要求し、GP01の未知キーREJECTを実測 |
| **値の型・範囲** | `id/name`がString、`quantity`が正整数など | **一部実装済み、一部未検査**。S01/S02は静的欠落。正署名Schema-invalid負例は新規NOT RUN |
| **権限・業務の意味** | SKU/数量/Merchant、最新Checkout、Host最終決定、nonceの一回限り | 固定A-onlyの一部照合のみ。**Host ALLOW/replay、HC06はHOLD** |

**公式SchemaとローカルFail Closedを分離：** v0.2 Open Checkout JSON Schemaには`allowed_merchants`等で`additionalProperties: false`がなく、Merchantには任意`website`がある。一方、`id/name`等の`type: string`は公式Schemaに明記されている。**未知フィールドの一律REJECTはローカル研究制約、既知フィールドの型検査不足は公式Schema型との具体的なギャップ**。正式なSchema適合性、Issuer互換性や商用利用まで検証済みとは主張しない。

## 4. 判断と、次のおすすめ1件（別途承認）

**P1-10s結果：DESIGN-ONLY GAP REVIEW完了。新Ruby/Pythonコード0、テスト0、CI実行0。** S01/S02の型検証不足が最も具体的な次の調査候補。**汎用Gem/API・本番Host統合HOLD、外部HC06強失効HOLD、RubyGems公開/実決済/署名Receipt NO-GO**。P1-10r修正の限定REJECT成果を取り消すものではない。

**次の1件 P1-10t（別途ユーザー明示承認後のみ）：S01に限定した合成正署名・Schema-invalid型の観測。** `checkout.line_items.items[0].id` を合成`123`の数値へ変更し、**Disclosure digest・Issuer/Agent JWSは有効であることを独立に確認**した上で、**公式JSON SchemaではINVALID**であることを別途検証し、**既存Ruby研究VerifierのACCEPT/REJECTをそのまま観測**する。**もしACCEPTならRED/HOLDと記録、コード修正はさらに別承認。** 署名の有効性と公式Schema適合を混同しない。新規テスト/CI/研究コードをこのP1-10s PRでは作成・実行しない。

**維持する既存数値：** Host正本 **9/34実測・25 NOT RUN（過去12 runs/465 assertions）**、P1-10r **2/10**、P1-10o **8/45**、P1-10q修正前 **ACCEPT/RED-HOLD**、公式Python intermediate hop **186 PASS / 2 FAIL**未解決。各実行は独立、合算して安全性を主張しない。

## 5. 現在の引き継ぎ先（旧HANDOFFからの移行に注意）

**新しいチャットでは、このP1-10s資料と[更新済みRESEARCH_PLAN](RESEARCH_PLAN.md)を最新の作業指示とする。** [旧HANDOFF](HANDOFF.md)はプロジェクト全体の過去経緯の参照用であり、同書の「次はP1-10s」は**更新未了の古い指示**なので再実行しない。編集の安全性チェックにより同ファイルは今回変更できておらず、変更済みとは主張しない。正式[RESEARCH_DECISION §36](RESEARCH_DECISION.md)のGem/API/本番HOLDは不変。

### 次のチャットで渡す指示文

```text
ap2-mandate-verifierのP1-10tを検討したい。
https://github.com/cuichangquan/ap2-mandate-verifier

最初にGitHub最新main/Open PR/IssueとCodexレビュー状態を確認。
docs/VERIFIER_P110S_CONSTRAINT_SHAPE_TYPE_GAPS.md と
docs/RESEARCH_PLAN.md を現行の引き継ぎ資料として読む。
docs/HANDOFF.mdの次はP1-10sという記述は古く、再実行しない。

P1-10sは静的設計レビューだけ完了。S01は公式Open Checkout
JSON SchemaでString必須のitems[0].idがRubyでは型未検査、
S02はMerchant nameのString型未検査。両方とも新署名負例NOT RUN。

P1-10tは別途明示承認後のみ、S01数値idの合成署名・Disclosure
真正性VALIDと公式Schema INVALIDを独立に確認し、現行Rubyの
ACCEPT/REJECTを1件だけ観測。不適切なACCEPTならRED/HOLDを記録。
修正コードはさらに別承認。
P1-10r GP01限定修正2/10、P1-10o 8/45（N07 HOST_BOUNDARY）、
Host正本9/34・25 NOT RUN、HC06/一般Gem/本番HOLDを維持。
新しいGem/API、GCP、実Issuer/Authority/Host、決済、Receiptは禁止。
```
