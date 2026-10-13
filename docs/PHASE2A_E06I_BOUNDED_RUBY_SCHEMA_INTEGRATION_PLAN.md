# Phase 2-A / E06-I — Ruby公式Open/Closed Schema統合の限定実装・実測計画（未承認）

**2026-10-13 JST / [計画Issue #71](https://github.com/cuichangquan/ap2-mandate-verifier/issues/71) / 親[Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) / `PLAN_ONLY` / `NOT_RUN` / `NO_EXECUTION_APPROVAL` / `PHASE2B_HOLD`**

> **今回の成果物は計画文書のみ。** Ruby/Python/fixture/workflowの変更、Schema検証の新規実行、CI/GCP、実Issuer登録、Gem/public API、Checkout決済、Receiptは一切実施・承認しない。レビュー/mergeは実装・実行・Phase 2-B移行の許可ではない。最初の将来候補は**既存の合成Issuer A、固定2hop・3 SD array slot**に対するオフライン研究に限定する。

## 1. 目的・今わかっている技術的な障害

[E06 G0–G7統合順序契約](PHASE2A_E06_INTEGRATED_VERIFICATION_ORDER_CONTRACT.md)の最重要命題は、**元署名Root真正性(G2) → 元Root全域の開示完全性(G3) → Agent/Merchant真正性と結合(G4) → Ruby同一経路の公式Open/Closed Schema(G5) → Host正本との金額・制約照合(G6) → 全成功時だけEvidence(G7)** である。前段での不正構文/形状の早期REJECTは許すが、後段まで検査した証拠にはならない。

現行の実装境界は次の通り。**既存コードにSchema検証1行を追加するだけではG5→G6の実行順序を証明できない。**

| 既存研究コード（今回変更禁止） | 実装済みの局所責務 | E06-Iで混同してはいけないこと |
| --- | --- | --- |
| [E01-S Host trust adapter](../research/phase2a_e01s/trust_probe.rb) / [policy](../research/phase2a_e01s/synthetic_host_policy.rb) | 合成Host S0–S3、既存DC04/P1-3 S4への接続 | S1の合成Issuer trustは実Issuer登録ではない。S4はG4–G6に分割されたAPIではない |
| [DC04固定Root候補](../research/phase2a_dc04/fixed_issuer_verifier.rb) | Root署名、3 pathの原Root commitment / Disclosure完全性、厳格な固定Open shape | `verify_full_root!` は署名/closureに加えshape・時刻を先に評価する。G5到達の代用品にしない |
| [P1-2 two-hop](../research/p1_2/two_hop_research.rb) | Agent鍵/Terminal署名/`sd_hash`、Closedの限定形状・時刻 | G4暗号確認と一部G5/G6関連ローカル判定が混在 |
| [P1-3 Checkout](../research/p1_3/checkout_binding_research.rb) | Merchant JWT署名、原JWT/hash、固定merchant/SKU/total/Host照合 | G4とG6を一度に処理する。P1-3終了後にG5を呼ぶのは**E06順序違反** |
| [P1-0 Ruby Schema spike](../research/p1_0/test_ruby_feasibility.rb) | `json_schemer 2.5.0`で**公式Openのみ**検証する既存局所例 | Closed/merchant `$ref`と同一署名付き統合経路は未証明 |

**採用する設計:** まず `G4` と `G6` を観測・実行順序上分離できる研究限定の**明示的なstage orchestration**を検討する。既存P1-2/P1-3を丸ごと先に呼んだ後でSchemaを確認する案は不採用。安全な最小抽出に必要な旧コード変更範囲を別途レビューし、差分が広がる場合・既存受理を緩める必要がある場合は**実装前STOP / 再設計**とする。既存コードの挙動は維持し、将来の新入口は隔離する。

## 2. 固定する正本とSchemaのオフライン導入

**公式AP2 v0.2.0 pinned commit: `b4587ac1d055888a73b4b21750973cffba961793`**。将来のCI/研究ランナーは**実行前に**このcommitを検証専用worktreeへcheckoutし、Rubyはそこから固定原本を読む。実行中の外部URLへの参照解決、main/latestへの自動追随、schemaの不明な代替、オンザフライの自動ダウンロードを認めない。

| 用途 | pinned `code/sdk/schemas/ap2/` 相対path | 重要な挙動 |
| --- | --- | --- |
| **G5 Open** | `open_checkout_mandate.json` | `$id=https://ap2-protocol.org/schemas/open_checkout_mandate`、Merchantの相対参照 `types/merchant.json`、`contains` と quantity型 |
| **G5 Closed** | `checkout_mandate.json` | `$id=https://ap2-protocol.org/schemas/checkout_mandate.json`、`vct/checkout_jwt/checkout_hash`必須 |
| **Open内 Merchant** | `types/merchant.json` | `$id=https://ap2-protocol.org/schemas/types/merchant.json`、`id/name`必須。**Merchant Checkout JWTのJSON Schemaではない** |

- Ruby 3.3、`json_schemer 2.5.0`、`jwt 3.3.0`の互換性を**将来テスト**する。Draft 2020-12を保持し、`$id`を削除・書換えせずに、**唯一許可したMerchant canonical URI** を事前ロード済みスキーマに解決する、fail-closedなallowlist resolverを設計する。未登録 `$ref`、複数解決、schema loaderの例外・ファイル欠落は `verification_unavailable` として停止し、network fallbackしない。
- 3つのSchema raw bytes、SHA256、Git blob SHA、`$id`と `$schema` を記録してpinned commitと照合する。既存P1-0のOpen blob SHA `e3d9cafa7311d90612c7f908ae9b8821ddc8735a` は参考値であり、**Closed/Merchantについては未確認のdigestを捏造しない**。
- 検証対象はG3で完全展開した**認証済みOpen**とG4で真正性・bindingが確定した**Closed**。署名前に分解したJSON、部分開示visible claim、Agent/Issuerが自己申告したキー、外部Python O4の結果をRubyのG5成功として使わない。
- `Open/Closed schema VALID`、`固定Host shape VALID`、`署名VALID`、`checkout authorization`は別命題。公式Schemaには任意に追加プロパティを禁止する規則がない箇所もあるため、**固定Issuerの未知signed authority field拒否**は独立して維持する。
- 通信できない環境でもschema validationを**失敗または同一結果**に固定できることを将来負例で検証する。外部HTTPを呼ばないという事実をテスト/ログで確認する。

## 3. 将来の限定差分案（現時点で作成しない）

| 変更候補 | 新規/既存 | 目的・ガード |
| --- | --- | --- |
| `research/phase2a_e06i/schema_gate.rb` | **新規予定** | pinned 3原本のoffline loader、限定 `$ref` resolver、Open/Closedを別々に判定、ref欠落時STOP |
| `research/phase2a_e06i/integrated_probe.rb` | **新規予定** | G0–G7 stage ledger、G1のHost政策固定、認証済みOpen/Closedを一度だけG5へ渡し、G6後だけEvidence-only |
| `research/phase2a_e06i/test_schema_gate.rb` | **新規予定** | RubyのOpen/Closed正負・nested Merchant参照・無ネットワーク・未解決ref・pinned digestの独立単体検査 |
| `research/phase2a_e06i/observe_integrated.rb` | **新規予定** | 実際のfirst reject stage、G5個別到達結果、原wire SHA256/Host policy digest等を公開情報のみで記録 |
| `research/phase2a_e06i/generate_and_oracle.py` | **新規予定** | 合成鍵を一時生成しO1–O4真正性・Root graph・公式Schema・Host bindingをRuby O5から独立監査 |
| `research/p1_2/two_hop_research.rb` / `research/p1_3/checkout_binding_research.rb` 等 | **必要なら別途審査** | G4暗号とG6意味評価を、安全に別入口へ抽出する最小差分。既存entrypointの結果/例外/受理範囲は変えない。単なる呼出し順変更で安全性が失われるならSTOP |
| `.github/workflows/phase2a-e06i-bounded.yml` | **別の実行承認後だけ** | 当該研究のみの手動・有界runner。今回のdocs-only PRに追加しない |

**実装可能性の出口:** 新入口から**同一Ruby invocationがG0–G6を実行した到達証拠**を出せなければ `E06_INTEGRATED_UNPROVEN`。まずオフラインSchema loaderの単体試験だけ成功した場合は `SCHEMA_FEASIBILITY_ONLY` と記録し、**E06-P統合PASSに昇格しない**。stage分割が想定以上の変更・仕様拡大を要する場合は、コードを増やす前にIssue #71でHOLDを宣言する。

## 4. 将来の最大6ケースと因果オラクル（全部 NOT RUN）

合成Issuer A・固定3 path・同一Host正本、original JWS/SD-JWT wire、Agent/Merchantの一時鍵を使う。O1 = 元署名独立検証、O2 = Agent/Merchant/Host binding、O3 = original Root全域commitment graph、O4 = pinned Python独立Schema+policy、O5 = **同一Ruby候補**の到達stage・理由。

| ID | 未来の対象 | 期待・証明の条件 |
| --- | --- | --- |
| **E06-I-P** | 本物の合成署名付き完全FULL・全3 disclosure・Host Checkout一致 | **G0–G6全到達・Open/Closed/Merchant refのRuby G5各VALID**、G7 `VerifiedEvidence`**候補のみ**。最初に成功しなければ全負例を安全性証明として採点しない |
| **E06-I-N1** | Issuer署名原本に残る有効なMerchant/SKU権限slotの非開示、Terminalは提示wireに対応する真正署名 | G3 `incomplete_disclosure`。完全FULLが成功していること、original Root commitment/digestのO3を要する。早期件数拒否では代用不能 |
| **E06-I-N3O** | Open schema-invalid候補（先行G0–G4を満たすか検証） | Ruby G5 `invalid_open_schema`に到達**できた場合だけ**統合負例。先に固定shapeが拒否する場合はそのstageをそのまま記録し、別の**単体Open Schema INVALID**の証拠と区別 |
| **E06-I-N3C** | Closed schema-invalid候補（先行G0–G4を満たすか検証） | Ruby G5 `invalid_closed_schema`に到達**できた場合だけ**統合負例。署名/bindingやローカルshapeで先行拒否ならG5到達証明に数えない |
| **E06-I-N4** | Open/Closed schema-valid・署名VALID、Host checkout id/total/merchant policyと不一致 | G6 `checkout_context_mismatch/constraint_violation`。署名やSchema VALIDがHost認可ではないことをO2/O4/O5で区別 |
| **E06-I-N5** | issuer root署名・開示完全性はVALID、Agent Terminal `sd_hash`あるいはMerchant JWT署名不正 | G4 `invalid_chain_binding/invalid_checkout_signature`。G5/G6へ未到達と記録 |

**Schema gate単体の必須追加アサーション（6件の「署名付きシナリオ」を増やさない）:** 正常Open/Closed、必要型と必須欠落、Merchant `id/name`欠落、相対refを読めない状態、未知ref、未承認のネットワークref、固定原本blob/hash違い。これらは**G5機構テスト**であり、原署名真正性やG0–G7通しの実証ではない。

**難しい負例の扱い:** 現行の固定DC04/P1-2/P1-3は公式Schemaより狭いshapeを先行検査するため、signed-invalid Open/Closed がG5の「first reject」に届かない可能性がある。**本来rejectすべき不正入力を通すようにローカルshapeを緩めるのは禁止**。G5自身の検査実行をstage ledgerで検証し、負例が構造的に先行拒否された場合は `G5_CAUSAL_NEGATIVE_NOT_PROVEN` とHOLDし、次の改訂計画を審査する。

## 5. 上限・実行権限（将来の別承認に必要な提案値）

| 境界 | 提案する研究限定cap / 違反時 |
| --- | --- |
| profile / samples | synthetic A・2hop・Root Open 1・3 SD array slot、**署名付き最大6ケース**、追加variantを無断生成しない |
| 元wire/Host材料 | Root SD-JWT ≤32,768B、Terminal ≤32,768B、Merchant Checkout JWT ≤16,384B、1 case総入力 ≤128KiB。超過・型不明 `resource_limit` |
| 解析木 | Disclosure 1–16、深度 ≤24、各object ≤32 fields、各array ≤16 elements。重複key/不正base64url・未知JOSE・未知 `$ref` はFail Closed |
| Ruby/Python実行 | Ruby 3.3、`jwt=3.3.0`、`json_schemer=2.5.0`、依存版ログ固定。**外部独立プロセス単位10秒のOSレベルhard timeout**、timeout/例外時STOP。Ruby `Timeout.timeout`単体をOS hard killと誤記しない |
| GitHub Actions | **実行承認後に手動起動する1 run / 1 job、`ubuntu-24.04`、`timeout-minutes:10`、限定workflowのみに閉じる。無承認のrerun・PR自動runは禁止**。想定外の自動トリガーが発生する変更は承認前STOP |
| 証跡 | public-only ≤1MiB、retention 7 days、検証対象HEAD SHA・公式AP2 SHA・3 Schema digest・O1–O5結果・到達stage・依存版・UTC実行時刻を記録。秘密鍵、nonce等の秘密、live checkout情報を含めない |
| Clock/E07 | Open/Closed最長7,200秒等の旧限定値は継承。**同一時計・skew・CPU・schema複雑度/全資源制約の十分性はまだ未証明**。新値はレビューし、E07 PASSに繰り上げない |

このcapは**計画上の暫定提案値**であり、現在E07を満たした根拠ではない。**1 runの実際の実行も未許可**。失敗からの無制限re-runは認めず、再実行は理由・新しい上限・オーナーの別途了承を要する。

## 6. 実施前Gate・停止・Exit

1. **Before code:** Issue #71に、stage責務の差分・今あるG4/G6混在コードの安全な切り出し方法・正確な参照URI/digest・暫定cap・独立O1–O5と署名付きpositiveの生成方法を追記する。古いRubyの検証経路を緩める必要があれば **STOP**。
2. **Before run:** 研究用コードPRの**最新HEADに対するCodexレビュー**と指摘解決、workflowのtrigger/path scopeと手動実行権限の検証、合成鍵・公開証拠の扱い、1run/1job/10分/10秒上限を確認する。その後、**別途明示的なオーナーの実装・実行承認が存在するときだけ**fixture生成・CIを行う。計画PR mergeとIssue closeを承認に代用しない。
3. **During/after run:** 本物の合成署名・独立O1–O4が欠けた入力、official Open/Closed loaderがfallbackする状態、Ruby FULLがG5を通過しない状態、G5より先にG6意味検証する経路、Host原本・Issuer profile未確定の状態は **RED/HOLD**。実到達stageと失敗理由を報告し、`REJECT`やCI greenだけを合格としない。
4. **Scope-only Exit:** `E06I_SCHEMA_FEASIBILITY_OBSERVED`はRuby Schema単体の有限な観測、`E06I_INTEGRATED_LIMITED_OBSERVED`は本物の署名付きFULLがG0–G7（Evidence-only）を一貫して通った**研究限定実測**のみを示す。N3O/N3Cなどが先行拒否なら該当因果は `UNPROVEN` と併記。どちらも**E01実Issuer provenance、E03/E05/E07/E08/E09全域、親#47、Phase 2-BへのGOではない**。
5. **事業責務は不変:** Ruby Verifierは支払許可、Host nonce CAS、リアルタイム失効/Issuer rotation、Buyer認可、Host注文現在性、実決済、Receipt、External Authority HC06を保証しない。

**現時点の最終判断：`E06I_PLAN_PROPOSED / CODE_NOT_CHANGED / NO_NEW_CI / PHASE2A_GATE_HOLD / PHASE2B_HOLD`。**

## 7. 証拠への参照

- [E06統合順序G0–G7](PHASE2A_E06_INTEGRATED_VERIFICATION_ORDER_CONTRACT.md)、[Exit Gate E00–E10](PHASE2A_EXIT_GATE_DECISION_CHECKLIST.md)、[E01-S実測後スコア](PHASE2A_POST_E01S_EXIT_GATE_STATUS_2026_10_13.md)
- [E01-S限定Host adapter](PHASE2A_E01S_MINIMAL_HOST_TRUST_ADAPTER_CONTRACT.md)、[DC04実測](PHASE2A_DC04_BOUNDED_RUBY_FOLLOWUP.md)、[P1-0のOpen Schema Ruby研究](../research/p1_0/test_ruby_feasibility.rb)
- [公式 pinned Open](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json)、[公式 pinned Closed](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/checkout_mandate.json)、[公式 pinned Merchant](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/types/merchant.json)
- [E01-S修正後の限定CI（**過去の実測であり新E06-Iではない**）](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38328627077)、[親Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47)、[本計画Issue #71](https://github.com/cuichangquan/ap2-mandate-verifier/issues/71)
