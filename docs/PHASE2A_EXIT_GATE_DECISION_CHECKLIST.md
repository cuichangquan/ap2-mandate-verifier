# Phase 2-A — 終了条件・Phase 2-B判断の証拠チェックリスト

**2026-10-13 JST / 親[Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) / DESIGN ONLY / PROPOSED CHECKLIST / Phase 2-B HOLD**

> **現在の結論: `DESIGN_RECORDED / SECURITY_GATE_UNPROVEN / PHASE2B_HOLD`。** DC01–DC06の限定実測、監査総括、固定Issuer信頼契約の文書化は済んだ。しかしIssuer権限開示完全性の独立した信頼根拠と統合時の検査順序を証明したわけではない。チェックリストの作成・Codexの文書レビュー・PRマージは、以下の未達GateをPASSさせない。
>
> **範囲:** この資料の追加自体に実装・fixture生成・CIの新規実行はない。親#47は**OPEN/HOLD**。Gem/public API、本番Host/Checkout・nonce-CAS、HC06、決済・Receipt、GCP・他リポジトリは対象外。

## 1. 「完了」の意味を3段階に分ける

| 段階 | 何を承認するか | 今回の状態 |
| --- | --- | --- |
| **D — 設計資料として整理済み** | 必要な信頼根拠、受入・拒否ルール、独立オラクル、未決事項、判断方法がレビュー可能な形になった | **文書として候補を提示。** Dは研究完了・安全PASSではない |
| **A — Phase 2-A技術Gate** | 固定Issuerの限定プロファイルに対する**真正性・signed-wire完全性・Issuer trustを混同しない独立証拠**と具体的なFail Closed境界が揃う | **HOLD / UNPROVEN** |
| **B — 別途Phase 2-B scoped offline PoC GO判断** | Aの評価を基に、対象Issuer・形式・実装上限・テスト計画・停止条件を明記した**新しい承認記録**がある | **HOLD / NO AUTOMATIC GO** |

**重要:** Phase 2-Bは本番対応や公開Gemではなく、仮に後でGOが出ても**隔離されたオフライン研究PoCに限る**。実Issuerの本人確認・運用上の発行契約が得られない状況では、合成Issuerによる暗号・構造の技術証明と**実Isssuer利用の保証を区別**しなければならない。実Issuer保証を捏造して前進するより、Phase 2-Aで個別の合成実験を**別スコープ・別承認**する選択を残す。

## 2. Exit Gate — 全項目が証拠リンク付きで埋まるまでAはHOLD

各項目の証跡には **(a) tested source SHA + pinned upstream SHA、(b) 条件付き主張の範囲、(c) 独立の証拠ファイル/CI runと期待結果、(d) Verifier/Hostの担当、(e) 実測と設計の区別** を明記する。単純な`REJECT`・緑のCI・Codex指摘ゼロだけでは暗号・完全性の証明と認めない。

| Gate / 優先 | 合格とできる厳密な条件 | 現在の証拠と不足 | 判定 |
| --- | --- | --- | --- |
| **E00 / 必須: 対象閉包** | pinned AP2 v0.2.0、許可するHost登録Issuer鍵1系統、Open→Closed 2hop、Root Open 1、line_items/allowed_merchants各1、Merchant/SKU/Checkout各1、signed claim/SD slotの**閉じた文法**、公式Schemaとの差分、未知入力の拒否が明記される | [受理契約](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md)設計済み。ただし実装受理保証なし。 | **DESIGN_ONLY** |
| **E01 / BLOCKER: Issuerの信頼根拠** | Hostがpresentationと独立にIssuer identity・用途・公開鍵・`not_before/not_after`・immutable`policy_version`・承認者と根拠を事前固定。**同じ鍵に複数profileが曖昧に該当せず、提示`iss/kid/version`でtrustを昇格・rollbackしない**。実Issuer適用を主張するならissuer onboarding/発行文法への独立の保証が別途必要 | T1/T3契約は文書化済み。[#62](https://github.com/cuichangquan/ap2-mandate-verifier/pull/62)。**Host登録・実Issuerとの契約/証拠はない** | **UNPROVEN** |
| **E02 / BLOCKER: 署名とoriginal signed-wire** | 合成でよいがRoot/Agent Terminal/Merchantの**本物の署名**、公開鍵のみの独立検証、元署名対象byteを保持。Rootの`cnf.jwk`→Agent PoPと`sd_hash`、Host aud/nonceとCheckout JWT/hashを独立照合。事前構造REJECTは署名確認済みと呼ばない | [DC01–DC06監査](PHASE2A_DC01_DC06_PROOF_GAP_AUDIT.md)で各限定ケースを観測。統合Verifierとしての全保証には至っていない | **LIMITED_OBSERVED / OPEN** |
| **E03 / BLOCKER: 全域commitment graph** | **Issuer署名済みRoot全域から**object`_sd`・array `...`を走査し、許可された3つのcommitment位置だけに対してDisclosure元base64url digestを**一対一・全消費**。未知位置/余剰/重複/decoy/未解決のどれかでSTOP。観測したslot自体が増えた場合もSTOP。デコイを勝手に無害化しない | [DC04](PHASE2A_DC04_BOUNDED_RUBY_FOLLOWUP.md)は隔離候補の限定正負。[DC05](PHASE2A_DC05_OBSERVATION.md)はdecoy非対応として拒否。[DC06追試](PHASE2A_DC06_FOLLOWUP_OBSERVATION.md)は重複・追加Openを**配列件数で先行拒否** | **UNPROVEN AS INTEGRATED GATE** |
| **E04 / BLOCKER: 因果を示す負例** | 同じRuby候補で**正しいFULLが限定受理**され、Issuer署名VALID・Agent binding VALIDの負例が**未解決digest/未知signed pathを実際に検査した理由**で拒否される。Schema INVALIDやRoot件数で先行拒否された場合はその事実を別欄に記載、complete guard PASSに繰り上げない | DC02/DC04限定では理由を観測。**DC03は公式Schema INVALID、DC06の追試3件はRoot件数先行**。新しい統合検査は未実測 | **PARTIAL / OPEN** |
| **E05 / BLOCKER: Issuer/profile mismatch** | Host未登録Issuer・署名VALIDな別Issuer鍵・同Issuer別layout・古いversion・複数policy一致・鍵rotation/撤回・policy正本不達を**有効署名とHost trust判定を分離したオラクル**で拒否。未知鍵fallback禁止 | [IP02/IP03/IP07](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md)は**すべてNOT RUN**。旧DC06の未知claim拒否をprofile不一致の証明へ転用しない | **NOT RUN** |
| **E06 / BLOCKER: 検査順序・Schema/制約** | 署名を確定してからRoot全域completenessを評価し、**成功Evidenceの前**に公式pinned Open/ClosedのSchemaとより狭い固定形状・全Constraint意味評価を実施。構造やSchemaの早期REJECTは許すが、completenessを実行していないnegativeをそのPASSと記さない。既存[最小Verifier§4](PHASE2A_MINIMAL_VERIFIER_DESIGN.md)の暫定Schema→completenessと新[Issuer契約§4](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md)の推奨completeness→Schemaについて**単一の統合順序を確定** | **設計間の順序差は文書化済み、統合の同一実装検証なし**。GP01/S01の限定修正が全Schemaを保証しない | **OPEN** |
| **E07 / BLOCKER: 資源上限・厳格構文** | max raw bytes、JWS/hop/Disclosure/commitment数、array/JSON要素、深度、署名検証/実行の期限、clock skewとTTLを**各具体値・単位・根拠・超過時reject code**で凍結。Root/Terminal/Merchant/Disclosure JSONのduplicate key（escape後も）とJOSE`alg/typ/crit`・非canonical base64url・鍵参照禁止を決定 | [Issuer契約§5](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md)の**数値は未決**。N01/N02は過去の限定証拠のみ | **OPEN / NO UNBOUNDED DEFAULTS** |
| **E08 / BLOCKER: Host責務を侵食しないEvidence** | `VerifiedEvidence` は`profile_ref` / `trust_snapshot` / `checkout_binding` / `verified_challenge` / `valid_until`が揃った**検証証拠のみ**。Root鍵＝Host承認Agent鍵＝challenge固定Agent鍵、Buyer/Account/Checkout正本・Merchant JWT payload ID一致。Host側nonce-CAS・失効・現在注文・支払いを「検証済み」にしない | [最小Verifier契約](PHASE2A_MINIMAL_VERIFIER_DESIGN.md)の**設計はあり**。本番Host/実Authorityと一体の証明は別Gate | **DESIGN_ONLY / OPEN FOR IMPLEMENTATION** |
| **E09 / BLOCKER: 独立オラクルと再現性** | O1署名、O2Agent/Merchant/Host binding、O3original Root全域digest graph、O4公式Schema/固定profile、O5 Ruby結果/**実到達stage**を独立に記録。fixture bytes・SHA256・依存lock・upstream SHA・run URL・再生成手順を対応させる。**秘密鍵をcommitせず**、7日後のartifact失効を踏まえ必要なら公開鍵のみの再現手段を用意 | DC01–DC06は限定証拠あり。新しい[IP01–IP09](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md)は**NOT RUN**。過去のCIを新試験に再ラベルしない | **PARTIAL / OPEN** |
| **E10 / 必須: 変更承認と判定記録** | 対象SHA、直前GateのPASS/HOLD、未証明・非対応、テスト実測証拠、残余リスク、責任境界、Codex latest HEADレビュー、CI有無を含めた**独立のPhase 2-B scope/GO-HOLD判断**を記録。設計PRマージやIssue closeにGOを連動させない | **GO判断なし**。親#47 OPEN、Phase 2-B HOLD | **HOLD** |

**判定方法:** 各項目を`PASS (scope-bound)` / `PARTIAL` / `DESIGN_ONLY` / `NOT_RUN` / `UNPROVEN` / `BLOCKED` / `OUT_OF_SCOPE`のどれかにし、証拠URL・SHA・責任者・残余条件を付す。**実測なしのPASSは禁止**。E00の設計整備はE03/E05などを満たさない。AのGO相当の判断は**E01–E09の当該研究scopeでの全BLOCKERが証拠付きに変わるまでしない**。E10の別承認はその後でも必要。

## 3. 次に取り組むべき最小の1件（追加実装ではなく設計判断）

優先度は **E01（Issuer trustの具体的な出所）→ E03/E04/E06（同じ署名付きFULLと同じRuby候補のcompleteness因果・順序）→ E05（issuer/profile不一致）→ E07（実数上限）**。類似したDC0xケースを無期限に増やすより、**既知の未証明命題を一つずつ証拠で潰す**。

1. **まずE01の出所選択:** 実Issuerとの発行プロフィール合意・鍵の登録根拠が取得できるかを判定する。**無い場合は `REAL_ISSUER_UNPROVEN` と固定**し、Hostが管理する**合成Issuer trust fixture**だけで検証可能な命題（署名/closed-world graph）を別欄に絞る。このsynthetic-only契約は**実Issuerのtrust保証ではない**。未入手の契約書や署名済みprofile-idをあるように扱わない。
2. **次の別承認依頼を最小化:** 上の仕様前提に決定的な矛盾がない場合に限り、後続の独立した**Phase 2-A限定実験**（IP02–IP05中心）の計画・オラクル・上限と停止条件を別Issue/PRで提案する。親#47は**DESIGN ONLY**なので、この資料自体でfixture生成や実装、CIを行わない。
3. **無限研究の停止条件:** E01のHost/Issuer信頼根拠が永続的に得られない、またはE03のsigned-wire原本完全性オラクルが実現できない場合は**HOLDを根拠つきで確定**し、汎用Gemを目標に追加negativeだけを延々増やさない。Candidate B（Issuer署名manifest）はpinned AP2互換性未証明のため代替案として黙ってGOしない。

### 将来の別途Phase 2-B判断書テンプレート（**空欄のまま**）

| 項目 | 記載する事実 |
| --- | --- |
| 判断対象 | 特定Issuer/key/policy version・固定仕様・signed paths・合成/実Issuer区分、pinned upstream SHA |
| Evidence | E00–E09表に対応する**独立証拠リンク**、repo HEAD、限定PASSと未証明、fixture/CI evidence |
| 入口条件 | 厳格parseと有限resource/TTL、root/agent/merchant trust・Disclosure・Schema・Checkout bind・Host入力 |
| 排除範囲 | 汎用Issuer・未知SD/path/decoy・非対応形状/多hop・GCP/本番・決済・Receipt |
| 停止・Rollback | 未知鍵/失効・Profile差分・重複/残余commitment・不明Schema・Host失効状態・異常例外 |
| 未完了 / 移行条件 | 確定できないtrust根拠・IP負例・Host責務、必要な別承認/Code review/CI |
| **結論** | **HOLD** または**別途明示された研究限定GO**（この文書では**HOLDのまま**） |

**研究限定GOの意味:** たとえ将来合成Issuer固定のオフラインPoCを「実Issuer信頼根拠なしでも条件付きで行う」と選び直す場合も、それは**従来のE01をPASSにする操作ではない**。別Issueで評価目的と`synthetic-only`残余リスクを明記して例外承認する**新たな判断**であり、商用Issuer受理、Host認可、公開GemへのGOには転用できない。現在その例外承認もない。

## 4. 既存証拠の索引（ここから正確な範囲へ辿る）

- [PR #61](https://github.com/cuichangquan/ap2-mandate-verifier/pull/61) / [DC01–DC06限定実測とProof Gap監査](PHASE2A_DC01_DC06_PROOF_GAP_AUDIT.md)
- [PR #62](https://github.com/cuichangquan/ap2-mandate-verifier/pull/62) / [T1署名・T2完全性・T3 Host trust、固定Issuer受理契約](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md)
- [Disclosure Completeness Gate: 候補A/B](PHASE2A_DISCLOSURE_COMPLETENESS_GATE.md)
- [最小VerifierとHost信頼責務](PHASE2A_MINIMAL_VERIFIER_DESIGN.md)
- [DC04隔離Ruby候補](PHASE2A_DC04_BOUNDED_RUBY_FOLLOWUP.md) / [DC05 decoy](PHASE2A_DC05_OBSERVATION.md) / [DC06追試](PHASE2A_DC06_FOLLOWUP_OBSERVATION.md)
- [Phase 1研究総括とPhase 2移行条件](PHASE1_RESEARCH_CLOSURE_PHASE2_GATE.md)
- [親Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) — 開示完全性デザインGate、OPEN/HOLD

**固定前提:** pinned公式AP2 v0.2.0 `b4587ac1d055888a73b4b21750973cffba961793`。新しいAP2/SDK・署名形式・非標準manifestへの自動拡大なし。既存観測の過去日付/CI成果を事後更新せず、このChecklistの判定を独立の時点として追加する。
