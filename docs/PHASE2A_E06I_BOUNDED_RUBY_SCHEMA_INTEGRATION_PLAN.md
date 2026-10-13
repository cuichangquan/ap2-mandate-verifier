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

**Evidence有効期限の契約:** G7の `valid_until` は、署名済みRoot Open・Agent Terminal・Closedの全ての有効期限、challenge期限、Issuer/Agent/Merchant trustの有効期限、Host policy TTL等、**適用される有限の期限の最小値**以下に固定する。G4で一時的に有効だった署名を、後から期限切れでも再利用可能な証拠にしてはならない。どれかの期限が不明・矛盾・到達不能ならEvidenceを発行せずSTOP。最終時刻判定とnonce消費はHost側の別責務とし、署名済み期限の見落としをHostに丸投げしない。

**実装可能性の出口:** 新入口から**同一Ruby invocationがG0–G6を実行した到達証拠**を出せなければ `E06_INTEGRATED_UNPROVEN`。まずオフラインSchema loaderの単体試験だけ成功した場合は `SCHEMA_FEASIBILITY_ONLY` と記録し、**E06-P統合PASSに昇格しない**。stage分割が想定以上の変更・仕様拡大を要する場合は、コードを増やす前にIssue #71でHOLDを宣言する。

## 4. 将来の最大13シナリオと因果オラクル（全件 NOT RUN）

[E06順序契約§3](PHASE2A_E06_INTEGRATED_VERIFICATION_ORDER_CONTRACT.md)の**E06-PおよびN1–N7をすべて対応表に含める**。最大13回のシナリオ判定であり、**13件の新規署名を意味しない**（FULL原署名wireの安全な再利用、Host policy切替、上限超過・Schema読み込み不能の環境負例を含む）。合成Issuer Aの固定2hop・固定3 pathを肯定基準とし、N6だけ未登録Issuer Bを用いる。対象の増加は再承認が必要。

**共通オラクル:** O1 = 元JWSの独立署名検証（G0不正入力に署名VALIDを要請しない）、O2 = Agent/Merchant/Host binding、O3 = **Issuer署名済みoriginal Root全域**のSD commitment graph、O4 = pinned独立Open/Closed Schema＋Host固定policy、O5 = **同一Ruby invocation**のstage ledgerとfirst reject code。E06-I-Pの同一実行でG0–G6が通りG7 Evidence-onlyを返すことが、後続負例を安全性証拠として評価する前提。各負例は**先行条件の到達・独立証明があって初めて**そのstageの因果証明となる。

| Scenario / 元E06 | 将来の合成条件 | 期待するfirst reject / 誤認禁止 |
| --- | --- | --- |
| **E06-I-P / E06-P** | 正しい合成A FULL、固定3 Disclosure・Root/Agent/Merchant真正署名・Host正本一致 | G0–G6全到達（Ruby G5でOpen/Closed/ネストMerchantの固定Schema判定）→G7 `VerifiedEvidence`候補のみ。本番ALLOWではない |
| **E06-I-N1 / N1** | A真正署名Rootの許可Merchant/SKU権限slotを未開示にし、元提示wireに対応するAgent Terminalは真正に再署名 | **G3 `incomplete_disclosure`**。O1/O3原signed graphの有効digest未解決が必要。配列件数・Schemaでの先行拒否をG3証拠としない |
| **E06-I-N2 / N2** | A本人の真正Issuer署名と対応する本物のTerminal/Merchant署名で、**original signed Rootだけに未承認SD commitment pathを1箇所追加**。許可済みDisclosureをすべて解決後の**Openは独立O4でpinned公式Open Schema VALID**、Merchant nested refもVALID、Closedもpinned公式Schema VALID。Openの権限・制約値は正常Pと同一であることを独立比較する | **G3 `unsupported_signed_profile`**。O1署名VALID＋O3原Root graphに未知commitment存在＋**O4 resolved Open Schema VALIDが必須**（schema-invalidならN2不成立・`N2_ORACLE_INVALID`/HOLD）。**「可視OpenはSchema-validだがoriginal signed graphは未承認」**という差を証明し、同一Ruby経路のG3到達とfirst rejectを記録。既存E01-S S3だけの拒否は代用不可。decoy/unknown object `_sd`全網羅は別Gate |
| **E06-I-N3O / N3 Open** | G0–G4の肯定前提を満たすよう発行した署名済み公式Open Schema-invalid型/必須 | **G5 `invalid_open_schema`に実到達した場合のみ**原因を記録。早期固定shape拒否なら`G5_CAUSAL_NEGATIVE_NOT_PROVEN` |
| **E06-I-N3C / N3 Closed** | G0–G4を通過可能な署名済み公式Closed Schema-invalid型/必須 | **G5 `invalid_closed_schema`に実到達した場合のみ**。G4が先にClosed型/時刻/hashを消費する場合はその事実を記録し、G5の負例PASSと誤称しない |
| **E06-I-N4 / N4** | SchemaとRoot/Terminal/Merchant署名はVALID、Host期待Checkout id/total/merchantが不一致 | **G6 `checkout_context_mismatch`または`constraint_violation`**。G5 VALIDはHost認可の代用不可 |
| **E06-I-N5A / N5 Agent** | A Root署名・G3完全性VALID、Agent Terminal `sd_hash`不一致（Terminal自体の署名は有効） | **G4 `invalid_chain_binding`**。G5/G6未到達を証明 |
| **E06-I-N5M / N5 Merchant** | A Root/Agent真正・G3完全性VALID、Merchant Checkout JWT署名を破壊（正しいHost公開鍵に対しINVALID） | **G4 `invalid_checkout_signature`**。原JWT一致/hashとの因果差もO2で記録 |
| **E06-I-N6B / N6 未登録Issuer** | 未登録Bによる**B公開鍵でVALIDな独立署名**、Host事前固定Aのみ | **G1 `untrusted_issuer`**。G1拒否時にG2成功を主張しない。E01-S IP02の過去結果で新候補の到達を代用しない |
| **E06-I-N6T / N6 信頼期限** | A自身の署名は独立VALIDだがHost固定Issuer policyが期限切れ/disabled（発行物に選択権なし） | **G1 `incomplete_context/untrusted_issuer`**。Host policy失効をIssuer署名無効と誤称しない |
| **E06-I-N7J / N7 G0構文** | **必須の統合シナリオは、Root compact JWSの署名対象payloadにescape復元後同一になるJSON key重複を含む未認証wire**。具体例は元raw JSON中の `"delegate_payload"` と `"\u0064elegate_payload"`（JSON escapeを解釈すると両方 `delegate_payload`）で、署名済みpayloadの重複をG0の厳格parserが最初に検出することを確認する。非対応JOSE headerは別の**単体アサーションのみ**で、このケースの代用不可 | **G0 `ambiguous_signed_json`がfirst rejectで必須**。G2署名が無効でもよいが、G0の前に署名検証/緩いparseへ進んだ結果のrejectは不合格。original raw JSONでescape後の同名衝突を独立オラクルで示す。1代表例だけで全parser攻撃面は証明しない |
| **E06-I-N7R / N7 G0資源** | 事前に固定したraw wire / case総byte cap超過（失敗自体に真正署名は不要） | **G0 `resource_limit`**。メモリ確保後・署名処理後の拒否はG0限界実証としない |
| **E06-I-N7S / N7 G5 Schema unavailable** | 正しいA FULL提示を使い回し、固定Closed/Merchant Schema原本またはallowlist `$ref`の読み込みを意図的に不可にする | **G5 `verification_unavailable`**。Network fallback禁止。原本loadがG0で失敗する実装なら到達stageをその通り記し、G5因果はHOLD |

**13ケースを予算内で管理:** 同じ元A FULL wire、同一固定Host snapshotのreadonly再利用が可能なものは使い回す。各caseの入力/fixture数・最大bytes・子プロセスhard timeoutを事前チェックし、**13ケース以内・1 run / 1 job / 10分**で実施できないなら自動増枠せず `STOP/REPLAN`。G0負例は未認証入力であるためO1署名成功を要求しない。N6BのB署名はB公開鍵で独立に検証してよいが、Host trust鍵として昇格しない。

**Schema gateの単体アサーション（上記13ケースと別の単体テスト・統合因果の代用不可）:** Open/Closedの正常と必須/型不正、Merchant `id/name`欠落、相対`$ref`未解決、未知ref、外部HTTP禁止、pinned原本blob/hash相違、strict parserの別JSON階層でのduplicate-key、および非対応JOSE header。単体テストを`E06-P/N1–N7`の証拠に流用しない。**統合N7Jでは厳格な重複key検査が必須で、JOSE拒否のみでは代用不可。**

**検査順序と因果の留保:** 現行DC04/P1-2/P1-3の固定shapeが、公式Schema INVALIDより先に拒否する可能性がある。本来拒否すべき形状を通すよう緩めることは禁止。G4が必要とする暗号・hash・署名入力検査以外のsemantic/schema判定をG5/G6へ安全に分離できない場合、**N3O/N3Cの因果は未証明のままHOLD**。未知pathが合成Host S3で先行拒否されればN2の統合G3とは呼ばない。

**未網羅を明示:** N2のO4による**公式Open Schema VALID**を独立証明できない場合、またはN7Jで**escape後重複JSON keyのG0到達**を観測できない場合は、該当代表シナリオ自体が未達である。13代表シナリオだけではN2の全decoy/unknown object `_sd`/重複digest/余剰Disclosure、N6のpolicy rollback/二重一致/rotation/revocation、N7の全JOSE・複数JSON階層/clock/CPU上限は証明しない。これらは**E03/E05/E07の残余GateとしてOPEN**。将来の `E06I_INTEGRATED_LIMITED_OBSERVED` は**13ケースのstage確認済み範囲のみ**に制限する。どれかの代表ケースがfirst rejecting stageに到達できない場合、未到達のG0/G1/G3/G5/G6に関する統合検査保証は `UNPROVEN` のまま。親E06 technical gate全体・Phase 2-A exit/Phase 2-BをPASSさせない。

## 5. 上限・実行権限（将来の別承認に必要な提案値）

| 境界 | 提案する研究限定cap / 違反時 |
| --- | --- |
| profile / samples | synthetic A・2hop・Root Open 1・3 SD array slot、**最大13シナリオ判定**（原署名の再利用・未認証G0・Schema不可環境を含む）、未承認variantを追加しない |
| 元wire/Host材料 | Root SD-JWT ≤32,768B、Terminal ≤32,768B、Merchant Checkout JWT ≤16,384B、1 case総入力 ≤128KiB。超過・型不明 `resource_limit` |
| 解析木 | Disclosure 1–16、深度 ≤24、各object ≤32 fields、各array ≤16 elements。重複key/不正base64url・未知JOSE・未知 `$ref` はFail Closed |
| Ruby/Python実行 | Ruby 3.3、`jwt=3.3.0`、`json_schemer=2.5.0`、依存版ログ固定。**外部独立プロセス単位10秒のOSレベルhard timeout**、timeout/例外時STOP。Ruby `Timeout.timeout`単体をOS hard killと誤記しない |
| GitHub Actions | **実行承認後に手動起動する1 run / 1 job、`ubuntu-24.04`、`timeout-minutes:10`、限定workflowのみに閉じる。無承認のrerun・PR自動runは禁止**。想定外の自動トリガーが発生する変更は承認前STOP |
| 証跡 | public-only ≤1MiB、retention 7 days、検証対象HEAD SHA・公式AP2 SHA・3 Schema digest・O1–O5結果・到達stage・依存版・UTC実行時刻を記録。秘密鍵、nonce等の秘密、live checkout情報を含めない |
| Clock/E07 | Open/Closed最長7,200秒等の旧限定値は継承。**同一時計・skew・CPU・schema複雑度/全資源制約の十分性はまだ未証明**。新値はレビューし、E07 PASSに繰り上げない |

このcapは**計画上の暫定提案値**であり、現在E07を満たした根拠ではない。**1 runの実際の実行も未許可**。失敗からの無制限re-runは認めず、再実行は理由・新しい上限・オーナーの別途了承を要する。

## 6. 実施前Gate・停止・Exit

1. **Before code:** Issue #71に、stage責務の差分・今あるG4/G6混在コードの安全な切り出し方法・正確な参照URI/digest・暫定cap・独立O1–O5と署名付きpositiveの生成方法を追記する。古いRubyの検証経路を緩める必要があれば **STOP**。
2. **Before run:** 研究用コードPRの**最新HEADに対するCodexレビュー**と指摘解決、workflowのtrigger/path scopeと手動実行権限の検証、合成鍵・公開証拠の扱い、13シナリオ以内/1run/1job/10分/10秒上限を確認する。その後、**別途明示的なオーナーの実装・実行承認が存在するときだけ**fixture生成・CIを行う。計画PR mergeとIssue closeを承認に代用しない。
3. **During/after run:** 本物の合成署名・独立O1–O4が欠けた入力、official Open/Closed loaderがfallbackする状態、Ruby FULLがG5を通過しない状態、G5より先にG6意味検証する経路、Host原本・Issuer profile未確定の状態は **RED/HOLD**。実到達stageと失敗理由を報告し、`REJECT`やCI greenだけを合格としない。
4. **Scope-only Exit:** `E06I_SCHEMA_FEASIBILITY_OBSERVED`はRuby Schema単体の有限な観測、`E06I_INTEGRATED_LIMITED_OBSERVED`は本物の署名付きFULLがG0–G7（Evidence-only）を通過し、**E06-P/N1–N7の13代表シナリオが同じRuby候補で期待する到達stage・先行条件を満たす**研究限定実測だけに使用する。N2/N6/N7を省略、またはN3O/N3C等が別stageで先行拒否なら統合範囲全体は `E06I_INTEGRATED_PARTIAL / CAUSAL_NEGATIVE_UNPROVEN` と記録し、対象GateをPASSにしない。どちらも**E01実Issuer provenance、E03/E05/E07/E08/E09全域、親#47、Phase 2-BへのGOではない**。
5. **事業責務は不変:** Ruby Verifierは支払許可、Host nonce CAS、リアルタイム失効/Issuer rotation、Buyer認可、Host注文現在性、実決済、Receipt、External Authority HC06を保証しない。

**現時点の最終判断：`E06I_PLAN_PROPOSED / CODE_NOT_CHANGED / NO_NEW_CI / PHASE2A_GATE_HOLD / PHASE2B_HOLD`。**

## 7. 証拠への参照

- [E06統合順序G0–G7](PHASE2A_E06_INTEGRATED_VERIFICATION_ORDER_CONTRACT.md)、[Exit Gate E00–E10](PHASE2A_EXIT_GATE_DECISION_CHECKLIST.md)、[E01-S実測後スコア](PHASE2A_POST_E01S_EXIT_GATE_STATUS_2026_10_13.md)
- [E01-S限定Host adapter](PHASE2A_E01S_MINIMAL_HOST_TRUST_ADAPTER_CONTRACT.md)、[DC04実測](PHASE2A_DC04_BOUNDED_RUBY_FOLLOWUP.md)、[P1-0のOpen Schema Ruby研究](../research/p1_0/test_ruby_feasibility.rb)
- [公式 pinned Open](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json)、[公式 pinned Closed](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/checkout_mandate.json)、[公式 pinned Merchant](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/types/merchant.json)
- [E01-S修正後の限定CI（**過去の実測であり新E06-Iではない**）](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38328627077)、[親Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47)、[本計画Issue #71](https://github.com/cuichangquan/ap2-mandate-verifier/issues/71)
