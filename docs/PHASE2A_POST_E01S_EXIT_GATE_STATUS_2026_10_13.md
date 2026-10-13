# Phase 2-A / E01-S実測後のExit Gate再評価 — 2026-10-13 JST

**判定：`E01S_SYNTHETIC_LIMITED_OBSERVED / PHASE2A_SECURITY_GATE_HOLD / PHASE2B_HOLD`**

- 親[Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) **OPEN**。既存[Exit Gate E00–E10](PHASE2A_EXIT_GATE_DECISION_CHECKLIST.md)の**時点別追補**であり、元の設計・実施前 `NOT RUN` 記録を事後に書き換えない。
- 出発点：研究 `main` **`698d1be5515cf92948c76d2c62094f35e8e613cd`**（[E01-S実測PR #68](https://github.com/cuichangquan/ap2-mandate-verifier/pull/68) マージ）。公式AP2 **v0.2.0固定 `b4587ac1d055888a73b4b21750973cffba961793`**。
- **実行・変更の権限：この資料は設計/証拠整理のみ。** 新fixture、鍵、実験、CI、GCP、Gem/API、Host実装、決済、Receipt、他リポジトリの変更を承認しない。
- `PASS` は **その実行時SHA・特定合成Issuer・固定Root文法・対象オラクルだけ**の結果。CIの緑、Codex無指摘、Rubyの単なる `REJECT`、合成Hostポリシーhashだけを商用/汎用安全性PASSに変換しない。

## 1. 実際に前進したこと — E01-Sの限定証拠

[独立スコープIssue #66](https://github.com/cuichangquan/ap2-mandate-verifier/issues/66) は**合成実験としてのみ完了/closed**。[PR #67](https://github.com/cuichangquan/ap2-mandate-verifier/pull/67) は最小Host adapter設計、[PR #68](https://github.com/cuichangquan/ap2-mandate-verifier/pull/68) は隔離した研究コードと実測。Ruby既存 `research/phase2a_dc04/fixed_issuer_verifier.rb`、P1-2/P1-3、およびGemは変更していない。

| 範囲 | 原署名と独立検証O1–O4 | 実際のRuby O5 | 合格として記録可能なこと |
| --- | --- | --- | --- |
| **IP01** A FULL | 合成Issuer Aの本物のES256 JWS、Agent Terminal `sd_hash`/aud/nonce、Merchant署名JWT/hash、固定Openと公式Schema VALID | `S4_DC04_CHAIN_CHECKOUT` まで到達し `LIMITED_POSITIVE` | 同じ合成Host A-only文法内の限定正常例を受理 |
| **IP02** B FULL | **B本人の試験用公開鍵による署名VALID**、Full/binding/公式Schema VALID。Host事前固定はAのみ | `S1_HOST_KEY_POLICY: UNTRUSTED_ISSUER` | **署名自体は正しいB**をHostの未登録Issuerポリシー理由で拒否。A鍵による誤署名拒否とは別 |
| **IP03** A別signed SD slot | **A本人の試験用鍵による署名VALID**、完全開示/binding/公式Schema VALID。Root署名済graphに `$/delegate_payload/0/disclosed/constraints/1` が追加 | `S3_HOST_SIGNED_GRAMMAR: UNSUPPORTED_SIGNED_PROFILE` | Host A-v1固定文法と違う**真の署名済位置**をDC04の早期構造rejectではなく合成Host S3で拒否 |

**結果の出所：** `51c54fd087dc02649907f8e510cba1258047569a` 上の[承認済み修正後CI #38328627077](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38328627077)、一回の `ubuntu-24.04` job、attempt 1、`completed/success`、O1–O5検証ログ・[合成public-only Artifact #11781362263](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38328627077/artifacts/11781362263)（7,230 bytes、保存期限2026-10-20 UTC）。比較元の[初回 #38327291069](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38327291069)も成功したが、外部10秒プロセス上限・再実行防止の欠落が後から判明。修正後CIだけを最新の制限適用実測とする。

**追加の安全措置：** 実験が終了してから、**CIワークフローのみ**を `fdfb1ed78161dcf844674a45e10f56c53f9eeb5a` で実行不能にした（`pull_request` trigger除去、archival `workflow_dispatch` と常に `if: ${{ false }}`）。そのSHAでは**再CIしておらず**、研究Ruby/Pythonのバイト列は修正後CI時点と同一。最終HEAD Codexは重大指摘なし、レビュー指摘4件は解決。[PR #68](https://github.com/cuichangquan/ap2-mandate-verifier/pull/68) は `main=698d1be...` にマージ済み。**過去のGitHub Actions実行は権限者が古い設定で手動再実行し得る**ため、ソース無効化が履歴を遡って完全に禁止するとは主張しない。追加CIは無承認で実行禁止。

## 2. E00–E10 Gateの**今時点**の証拠と残り

| Gate | 2026-10-13 E01-S後の状態 | 主な未達・次の要求 |
| --- | --- | --- |
| **E00 対象閉包** | **DESIGN_RECORDED**：単一Issuer固定、2hop、Root Open 1、許可されたarray SD位置3つの限定候補を定義 | 公式AP2全体の受理プロフィールではない。未知Issuer/多hop/任意制約を受理しない |
| **E01 独立Host/Issuer trust** | **SYNTHETIC_LIMITED_OBSERVED / REAL_ISSUER_UNPROVEN**：事前固定A公開鍵とprofile digest、BのHost S1拒否を実測 | 実Issuer本人/発行文法の独立合意・attestation、鍵の認証済み登録/用途、所有者、activation/retirement/rotation/revocation、長期正本なし。実Issuer用T3はPASSでない |
| **E02 真正署名と結合** | **LIMITED_OBSERVED**：IP01–03の元JWS署名を実際の試験用A/B鍵で独立検証。Agent `sd_hash`、Merchant JWTとHost aud/nonce等はO2で照合 | 新しい統合Ruby public Verifierや一般的な署名/key policyの全形態に拡大しない |
| **E03 元signed-wireの全域commitment** | **LIMITED_FOR_IP01_IP03 / INTEGRATED_GATE_OPEN**：Pythonの元Root graphと合成S3固定3-slot拒否を検証 | **同じ新Ruby adapter**で隠された権限・object `_sd`・decoy・重複digest/余剰Disclosure・deeply nested unknownのすべてに対して、独立署名/全域検査の到達をまだ網羅していない。旧DC06件数先行rejectを重複detector PASSと誤称しない |
| **E04 因果を示す負例** | **PARTIAL**：IP01 FULL受理後、IP02 S1、IP03 S3の実到達段階を証明済み | DC03は部分Schema INVALID、DC06追試はRoot cardinality先行reject。schema-valid隠蔽・未知/重複/decoyを**同一統合経路**で検出する証拠は未取得 |
| **E05 Issuer/profile mismatch** | **IP02/IP03_LIMITED_OBSERVED / LIFECYCLE_UNPROVEN** | Host policy version rollback・二重policy一致・鍵rotation/撤回・失効正本不達・用途違いは未実測。元[固定Issuer契約§6](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md)のIP01–IP09全体を完了と扱わない |
| **E06 統合検査順序・Schema** | **BLOCKER / NOT_INTEGRATED**：IP03の公式Open Schema VALIDは**Python O4の独立検証**。合成Ruby S0→S1→S2→S3→既存DC04 S4を確認 | Ruby側が固定Open/Closed**公式Schemaを成功Evidence前に強制する統合経路**を証明していない。旧最小VerifierとIssuer契約の順序差を決定し、Schema/完全性/意味評価の因果順と正負例を一系統で示す必要 |
| **E07 有限上限と構文** | **SYNTHETIC_CI_BOUNDED / FULL_RUNTIME_UNPROVEN**：3ケース、1job≤10分、外部プロセス10秒、case≤128KiB/Root≤32768B/≤16 Disclosure、7日/≤1MiB公開証拠の設定はある | JWS/Terminal/Checkout/全JSON/元base64url/失効・clock-skewを含む**汎用拒否時の資源上限・超過時code/実測**は未証明。Ruby `Time.now` と合成Host時計が一つの原子的clockだと主張しない |
| **E08 Host責務/Evidence** | **DESIGN_ONLY**：Verifierは技術的証拠、Host最終ALLOW・nonce-CAS・revocation/checkout現在性は別責務 | `VerifiedEvidence`に要求されるchallenge ref/Agent鍵/Buyer・Account参照/Checkout正本/valid_until/Host履歴を統合した本番側保証なし。HC06、外部Authority、Receiptは別ゲート |
| **E09 独立O1–O5/再現性** | **E01S_O1_O5_OBSERVED / DURABILITY_PARTIAL**：実行SHA・公式SHA・ログ・公開鍵のみのArtifactあり | Artifact期限2026-10-20 UTC。再生成は**新しい短期合成署名**で元署名byte-identical再現ではない。7日後も監査可能な長期公開**非秘密**のmanifestとエビデンス正本を別途定義・レビューする必要 |
| **E10 別途Phase 2-B判断** | **HOLD**：親#47 OPEN、限定合成実験Issue #66だけclosed | E01実Issuer・E03/E04/E05/E06/E07/E08/E09の対象別Exitと残余リスク、Phase 2-B研究PoC scopeを別途明示承認。docs merge、Issue close、CI greenはGOにしない |

**分類:** E01-SによってE01の**synthetic**部分、E02、E04のIP02/IP03、E05のIP02/IP03、E09のO1–O5に**限定的な新しい実測証拠**が加わった。未証明ゲート全体がPASSしたのではない。実Issuerの権威を合成鍵で保証したとも言わない。

## 3. 優先すべき次の仕事（追加negativeの量産ではない）

1. **設計だけで着手できる1件：E06の統合順序を一本化する。** 既存[最小Verifier§4](PHASE2A_MINIMAL_VERIFIER_DESIGN.md)と[固定Issuer契約§4](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md)の差を解消し、「どのデータをいつ署名検証するか」「原本Root全域commitment」「公式Open/Closed Schema」「制約とHost Checkout照合」「失敗時の正確な理由」を**同一candidate**で監査可能な決定表にする。統合試験は**別Issueで範囲・code diff・resource/CI上限・承認**が揃うまで実行しない。
2. **並行する非実験の意思決定：実IssuerのR01–R06正本を取得できるか**を評価する。発行者の認証済み鍵・closed signed-wire文法に対する同意/attestation・rotation/失効policyが得られない限り `E01_REAL_ISSUER=UNPROVEN` に固定。偽りの契約や署名済み `policy_version` を捏造しない。
3. **残る実装前の試験設計：** E03/E04/E05/E07の同一Ruby経路での隠蔽/重複/decoy/rollback/期限切れ/資源上限と、E09のArtifact期限後の独立再現性。既存DC0xの緑を別ケースのPASSに再ラベルしない。

**STOP基準:** 実Issuer信頼が得られず実Issuer対応を必須とする場合、Issuerの未知SD commitmentを解析せず受理する必要がある場合、またはHost責務をRubyが代替したことにしなければならない場合、**Phase 2-BはHOLD**。合成限定の追加研究には余地があるが、それ自体がPhase 2-Bへの移行権限ではない。

## 4. 何を承認するか — 3段階の区別

| 水準 | 今の判断 | 将来進める条件 |
| --- | --- | --- |
| **設計・文書更新（Phase 2-A内）** | **GO**（今回のdocs-only整理） | 正本を更新しつつ、未証明と実測を分離。PR最新HEADレビュー |
| **別スコープの合成研究（Phase 2-A内）** | **今回の承認なし** | 1つの未解決命題・O1–O5・厳格な実数cap・鍵取扱い・1回だけのCI・費用・STOP・owner承認を個別Issueに記録 |
| **Phase 2-Bの隔離Ruby PoC実装** | **HOLD** | E00–E09を対象scopeで判定できる証拠、未対応入力の拒否、実Issuer/合成Issuer区分、E10の別途明示GO判断。Phase 2-BもGem公開・実決済を意味しない |

## 5. 根拠・正本

- [E00–E10 Exit Gate](PHASE2A_EXIT_GATE_DECISION_CHECKLIST.md)、[DC01–DC06 proof-gap audit](PHASE2A_DC01_DC06_PROOF_GAP_AUDIT.md)、[固定Issuer T1/T2/T3受理契約](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md)、[E01実Issuer trust出所判断](PHASE2A_E01_ISSUER_TRUST_PROVENANCE_DECISION.md)
- [E01-S3ケース計画](PHASE2A_E01S_SYNTHETIC_ISSUER_TRUST_PROBE_PLAN.md)、[E01-S合成Host adapter設計](PHASE2A_E01S_MINIMAL_HOST_TRUST_ADAPTER_CONTRACT.md)、[実装PR #68](https://github.com/cuichangquan/ap2-mandate-verifier/pull/68)
- [初回CI](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38327291069)、[修正後CI](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38328627077)、[Issue #66の完了記録](https://github.com/cuichangquan/ap2-mandate-verifier/issues/66#issuecomment-6135720077)、[Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47)
- [公式AP2 pinned v0.2.0](https://github.com/google-agentic-commerce/AP2/tree/b4587ac1d055888a73b4b21750973cffba961793)

**この文書は新しい実験ではない。Phase 2-A親Gate・Phase 2-B移行の結論は、証拠が増えても条件の緩和で更新せず、別途明示判断する。**
