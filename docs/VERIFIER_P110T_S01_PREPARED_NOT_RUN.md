# P1-10t — S01 正署名・公式Schema型不一致の観測準備（未実行 / HOLD）

**2026-10-12 JST / PREPARED ONLY / NOT RUN / NO SECURITY RESULT CLAIM**

[P1-10s静的Gapレビュー](VERIFIER_P110S_CONSTRAINT_SHAPE_TYPE_GAPS.md)の最優先 **S01**：公式AP2 v0.2.0 Open Checkout JSON Schemaでは`line_item_requirements.id`は**String**だが、既存Ruby研究Verifier `research/p1_3/checkout_binding_research.rb`はキー集合だけを確認し、Requirement `id`の値のString型を検査しない、という**静的疑義**を対象にする。

## 今回準備できたこと（結果ではない）

- `research/p1_10t/generate_s01.py`：公式固定AP2 v0.2.0 commit `b4587ac1d055888a73b4b21750973cffba961793` のPython SDKを前提として、正常な合成Open→Closed 2hopを作り、**Openのline_items.items[0].idだけを文字列`req-1`から整数`123`へ変更**するよう設計。Open disclosure digestの再計算とIssuer再署名、Agent署名Closed、Merchant署名Checkout JWT、公式Python署名/chain検証、公式JSON Schema Draft 2020-12による**唯一の型エラーの確認**をすべて実行時の前提にする。既知Merchant Schemaの参照も固定ローカルファイルで解決する予定。
- `research/p1_10t/observe_s01.rb`：生成した公開鍵・署名トークンをRubyで独立に検証し、署名済み整数`id`の存在をassertした後、**未修正`AP2CheckoutBindingResearch.verify!`の受理/拒否を1件だけ観測**するよう準備。`ACCEPT`の場合に`RED_HOLD`、`REJECT`の場合に`LIMITED_REJECTION_ONLY`を記録する意図。
- **秘密署名鍵・実Checkout・公開Gem/API・GCP・実Issuer/Authority・実決済は使わない**想定。ただし上記コードは**実行していないため署名検証成功や動作保証はまだない**。

## ブロッカーと判定

**専用`.github/workflows/p1-10t-s01-observation.yml`の作成がプラットフォーム安全性チェックによりブロックされた。** この制限を**迂回していない**。よってCI用workflowを作成・実行できず、Ruby/Pythonテスト実行結果も**0件**。当該S01の公式Schema INVALID（コードで意図した条件）と暗号VALID（コードで意図した条件）を**実測したとは主張しない**。Rubyの`ACCEPT/REJECT`は**UNKNOWN / NOT RUN**。

現時点では**P1-10tを研究PRの草稿（Draft）に留め、CI未検証のままmainへマージしない**。安全性チェックのブロックについて、変更を別ファイル/別手段へ移すなどの回避は行わない。再開するには、許可された検証手段と明示的な実行条件を確認する必要がある。

| 項目 | 現状 |
| --- | --- |
| 正署名の合成S01（数値`id`） | **コードは準備済み、署名・Disclosureの実測NOT RUN** |
| 公式Schema検査 | **予定、NOT RUN**（公式Schema固定SHAは参照済み） |
| Rubyの`ACCEPT / REJECT` | **UNKNOWN / NOT RUN** |
| 新規テスト/CI成功数 | **0** |
| 既存Verifier修正 | **なし** |
| PRの扱い | **Draft / HOLD / main未反映** |

## 既存の実測と継続HOLD

[P1-10q](VERIFIER_P110Q_GP01_EVIDENCE.md)の**修正前GP01 ACCEPT / RED-HOLD**は歴史的に維持し、[P1-10r](VERIFIER_P110R_GP01_FIX_EVIDENCE.md)の固定Issuer GP01 **REJECT＋正常署名**（2 runs/10 assertions）とは別。P1-10o 8 runs/45 assertions（AN-N07 **HOST_BOUNDARY**）、Host正本9/34件・25 NOT RUN、P1-10i H01旧Authorityの危険反例、外部HC06強い失効 **HOLD**。汎用Gem/Public API/本番統合は**HOLD**、RubyGems/実決済/署名Receiptは**NO-GO**。

**次の一件:** 安全性チェックの制限を回避せず、許可された検証ワークフローが明確になるまで本草稿を保留。S01を実測できた段階で初めて`RED/HOLD`または限定REJECTの新判断を記録する。
