# Phase 2-A / E06 — 最小固定Issuer Ruby Verifierの統合検証順序（設計契約）

**2026-10-13 JST / 親[Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) / `DESIGN_ONLY` / `E06_NOT_INTEGRATED` / `PHASE2B_HOLD`**

> **設計判断:** 候補A（Hostが事前に固定した単一Issuer、閉じた署名済みRoot文法、2hop、Open Root 1件、許可SD array slot 3箇所）に限定し、**Pre-auth厳格処理 → Host trust → Issuer Root署名 → 原署名Rootの全域Disclosure完全性 → Agent Terminal/Merchant真正性・結合 → Open/Closed公式Schema → 固定制約・Checkout/Host照合 → Evidenceのみ**を成功経路の依存関係とする。
>
> これは[最小Verifier設計§4](PHASE2A_MINIMAL_VERIFIER_DESIGN.md)と[固定Issuer受理契約§4](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md)の**設計上の順序差を解決する提案**であり、実行済み統合Rubyコード・テスト・安全性PASSではない。署名前・completeness前の**構文/Schema早期REJECT**は許すが、後段の検証を実行した証明として繰り上げない。

## 1. 適用範囲と正本の出所

- **公式固定基準:** [AP2 v0.2.0 pinned commit `b4587ac1d055888a73b4b21750973cffba961793`](https://github.com/google-agentic-commerce/AP2/tree/b4587ac1d055888a73b4b21750973cffba961793)。最低限 [Open Checkout Schema](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json)、[Closed Checkout Schema](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/checkout_mandate.json)、[Merchant type Schema](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/types/merchant.json)を区別する。固定した原本・`$id`/`$ref`の登録・検証器の版が未確認なら成功不能。実行時の任意URL参照・最新AP2への自動切替は禁止。
- **検証主体を分離:** ① Host正本のIssuer/Merchant許可鍵・Agent/challenge/Checkout・用途・policy snapshot、② Root JWSに署名したIssuerの元byte、③ Root Disclosure、④ Agent署名済みTerminal/Closed、⑤ Merchant署名済みCheckout JWT、⑥独立オラクルとRubyの到達ゲート。Untrusted `kid`/`iss`/自己申告JWKから新しいHost鍵を登録しない。Host `policy_version`を実際にはないIssuer署名claimと呼ばない。
- **対象プロフィール:** Candidate Aの固定3 path（`$/delegate_payload/0`、`$/delegate_payload/0/disclosed/constraints/1/allowed/0`、`$/delegate_payload/0/disclosed/constraints/0/items/0/acceptable_items/0`）のみ。全array/object `_sd`/unknown slot/decoy、余剰Disclosure、複数Open、別hopは拒否。公式AP2の一般形状を狭める**研究Hostのローカル方針**であり、規格自体が全Issuerに3 pathを要求するわけではない。
- **現状の実測と違い:** [E01-S修正後の実測 #38328627077](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38328627077) / [PR #68](https://github.com/cuichangquan/ap2-mandate-verifier/pull/68) はRubyの `S0→S1→S2→S3→既存DC04 S4` とIP01–03を観測した。**公式Open Schema VALIDは独立したPython O4**であり、Ruby成功経路自身が**OpenとClosedの公式Schemaを通過する実装は未証明**。別の新しい統合コードやCIはこの文書で作成/許可しない。

## 2. 単一成功経路に要求する順序（論理ステージ。実装済みRuby APIではない）

**原則:** すべての入力は上限と厳格parseに従い、元のJWS署名対象byteを一切再直列化しない。前段で拒否できることと、後段の検証が証明できることを混同しない。Stage名 `G0–G7` は**この文書の設計ラベル**であり、既存のE01-S `S0–S4`コードが全部実装済みとの主張ではない。

| Stage | 入力・依存 | 成功するための確定条件と生成物 | 拒否 / 証拠境界 |
| --- | --- | --- | --- |
| **G0 PREAUTH_BOUNDS** | raw 2hop wire、Host原本context、取得済みの固定Schema | bytes/parts/hops/深度/項目数に明示上限、Base64URL canonical、UTF-8、署名対象JOSE header/payload・全Disclosure・Merchant JWT内JSONの重複key厳格parse（escape後重複含む）。非対応 `alg/typ/crit/b64=false/jwk/jku/x5u` 等を拒否。parsed値は**未認証**として保持 | `ambiguous_signed_json/unsupported_jose_header/resource_limit/unsupported_profile`。**署名を証明したとは記録しない** |
| **G1 HOST_TRUST_SNAPSHOT** | presentationから独立したHost鍵/Issuer profile/challenge/Checkout/trust snapshot | 単一のactive Issuer鍵・固定発行文法/用途/期限/不変Host policy versionを選択、Merchant trust・Host承認Agent鍵・challenge発行時固定Agent thumbprint・Checkout正本をロックした同一検証contextとして取得。曖昧/失効不明/正本不達はSTOP | `untrusted_issuer/ambiguous_policy/incomplete_context`。**合成policy hashのみでは実Issuerの登録・出所証明にならない** |
| **G2 ISSUER_ROOT_AUTHENTICITY** | G1 Host許可Issuer JWK、G0の**元compact Root JWS** | Host許可ES256鍵でRoot original JWS署名・保護header・元payload検証、root `typ`と署名対象byte同一性を確認。Root claimsはこの時点で**署名済みだがDisclosureは未確定** | `invalid_issuer_signature/unsupported_signed_header`。署名VALIDだけで可視制約を承認しない |
| **G3 ROOT_ORIGINAL_SD_CLOSURE** | G2で署名確認した**元Root payload全文**＋元Disclosure bytes、G1固定文法 | **署名対象原文のRoot全域**を深さ制限付き走査し、object `_sd`、array `...`、未知slot、未知sibling/claim、重複/未解決digest・decoy・余剰Disclosureを検出。3つの固定slotのdigest一対一・全消費・残余0と、Disclosure再帰展開後の固定Open claims/権限container存在を検証。認証済みの**完全に解決されたOpen**とcommitment監査結果を出力 | `incomplete_disclosure/unsupported_signed_profile/duplicate_commitment/unused_disclosure`。**可視Open Schema VALIDやSDK resolved payloadのみで代用しない** |
| **G4 AGENT_AND_MERCHANT_CRYPTO_BINDING** | G3のIssuer認証済み`cnf.jwk`とRoot original wire、G1 Host Agent/Checkout/Merchant原本、G0 Terminal/Checkout JWT原文 | Root Agent鍵＝Host承認Agent鍵＝Host challenge発行時固定thumbprint。Terminal original JWSをこのAgent鍵で検証、`kb+sd-jwt`/Agent PoP/`sd_hash=SHA256(exact Root SD-JWT wire)`、aud/nonce、exactly one Closed、Terminal自身/Closed内の時刻・Issuer Open→Closed保持を検証。Merchant Checkout JWT原文を**Host許可Merchant鍵**で署名検証、Closed `checkout_jwt`とHost JWT原文一致、Closed `checkout_hash`を**JWT文字列原文**から再計算（Hashだけで署名確認したことにはならない） | `expected_agent_mismatch/invalid_chain_binding/invalid_terminal_signature/invalid_checkout_signature/checkout_jwt_mismatch/checkout_hash_mismatch`。必要なTerminal Disclosure・署名済みClaimの厳格な閉包性も検査。不正時は未認証Checkout semanticsを評価しない |
| **G5 OFFICIAL_SCHEMA_AND_LOCAL_SHAPE** | G3完全展開・G4真正性確定済みのOpen/Closed、署名済みMerchant情報、**固定公式Schema原本** | 固定Draft-2020-12 `Open Checkout` と `Closed Checkout` 各全文に公式Schemaを**同じRuby検証経路の成功条件として**適用。Merchant nested objectには固定`types/merchant.json`を適切なref経由で適用。署名済みCheckout JWT payloadの**本OSS限定**厳格1行profile型/必須/未知keyも別判定（公式Checkout Mandate SchemaをMerchantのCheckout JWT schemaと誤同一視しない）。公式Schema不正ならローカルshapeやRuby受理より優先して**不受理** | `invalid_open_schema/invalid_closed_schema/invalid_merchant_type/unsupported_profile`。SDK `verify_chain`、Python O4、Ruby独自の一部型チェックは**Ruby統合Schema実施の代用ではない**。Schemaが参照解決不能なら `verification_unavailable` |
| **G6 FULL_CONSTRAINT_CHECKOUT_HOST_BINDING** | G5完了済みOpen/ClosedとMerchant署名JWT、G1 Host正本/challenge、期限policy | 残る**全権限制約**と固定候補のMerchant/SKU/quantity/通貨/金額/subtotal/total/statusをHost期待値と比較。署名検証済Checkout JWT payloadの`id`＝Host checkout ID、Host JWT recordのtenant/id/version＝challenge recordのtenant/id/version、Buyer/Account ref三者結合、Open→Closed制約非緩和。Host aud/nonce/有効期限・trust policy/challenge最短deadlineを合成した**有限**`valid_until`を計算。ずれ/現在性不明はSTOP | `constraint_violation/checkout_context_mismatch/buyer_context_mismatch/invalid_checkout_claim/invalid_time/incomplete_context`。VerifierがHostの現在の在庫/注文・外部失効・nonce CASを保証したとしない |
| **G7 EVIDENCE_ONLY** | G0–G6**全成功**の監査済みsnapshot | `VerifiedEvidence`候補は`profile_ref`、Host正本の`trust_snapshot`、`verified_challenge`、`checkout_binding`（JWT raw digest + id/version/Host challenge ref）、`valid_until`等必須。同じsnapshot/実検証鍵/shaと到達stageを紐付ける | どれか欠落なら成功値を返さず`Rejection`/HOLD。`allow/approved/payment_succeeded/nonce_consumed/not_revoked`を出力しない。Host側のnonce CAS・現在注文・強失効・最終ALLOWは独立の将来Gate |

### 順序の正規化と早期拒否の区別

- [旧最小Verifier§4](PHASE2A_MINIMAL_VERIFIER_DESIGN.md)の **「Claims + Schema（3）→ Completeness（4）」**を成功ルートでは採用しない。Schemaが可視部分にVALIDを返しても、原Rootの未知commitmentを否定できないため。**G2 Root真正性 → G3 root completeness → G5 Open/Closed公式Schema**を設計上の優先関係とする。
- [固定Issuer契約§4](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md)はCrypto全体→completenessを列挙していたが、Terminal署名に使う`cnf.jwk`は**G3で開示完全化したIssuer署名済みOpen**から得る。そこで**Root真正性（G2）→ Root completeness（G3）→ Agent Terminal真正性/Host三者鍵bindingとMerchant署名（G4）**へ具体化する。G0でRoot型/件数を早期rejectする例は**Root署名検証成功・G3到達とは記録しない**。
- **早期`invalid_schema`拒否は許す**。ただし後段に依存する認証済みSchema判定や完全開示の主張をする場合はG2/G3/G4の前提が必要。署名前に型を見て拒否しただけなら`preauth_shape_reject`としてログ化し、`invalid_signed_schema`や`incomplete_disclosure`検証成功へ昇格させない。
- G4でCheckout JWT原文の署名を独立に検証した事実と、G5で公式AP2 Closed Schemaに適合した事実と、G6で**Host正本のCheckout id/tenant/version・制約を満たした事実**は全て別条件。どれかの代用禁止。
- **時刻・TOCTOU:** 既存DC04とP1-2は別々の`Time.now`を読む。合成E01-SのHost`freeze_epoch`は時計同一性を保証しない。G1/G6は検証timestamp interval・許容skew・最短期限・期限境界上の不確実性とHost側再評価の契約を要求し、未決ならHOLD。ここでグローバルTimeをmonkey-patchしない。具体数値と実際の限界実測は**E07未完了**。

## 3. 因果的Rejectを区別する最小テスト・オラクル行列（今回すべて**新規NOT RUN**）

| ID | 条件（将来の合成署名は本物を独立検証） | 期待first rejecting stage | 必須の独立証拠 / 誤認禁止 |
| --- | --- | --- | --- |
| **E06-P** | 固定A FULL + 権限3 slot完全開示、Root/Terminal/Merchant署名・Open/Closed公式Schema・Host Checkout全一致 | **G7 `Evidence-only` 候補** | G0–G6の**同じRuby実行**到達、公式Open/Closed双方のvalidator明示結果、O1–O5; 本番ALLOWでない |
| **E06-N1** | 本物の署名＋対応するagent/merchant/checkout成立、SD slot内の有効digest非開示。可視OpenがSchema VALIDでも可 | **G3 `incomplete_disclosure`** | original Root全文の未解決commitment/path。先行Schema/Root配列rejectはG3証明にならない |
| **E06-N2** | 本物のA署名 + 完全開示、Issuerが違うsigned SD slot/未知`_sd`/decoy（独立graph証明） | **G3 `unsupported_signed_profile`** | 公式Schema VALIDな解決Openと署名済み未知graphの差。IP03既存観測は合成S3**のみ** |
| **E06-N3** | Issuer署名と完全性はVALID、公式OpenまたはClosedの必要型/必須が不正 | **G5 `invalid_open_schema/invalid_closed_schema`** | pinned正本Schema/独立validator/同じRuby経路の拒否。Root cardinality早期rejectを型検証成功と呼ばない |
| **E06-N4** | Open/Closed公式Schema VALID、Merchant署名VALIDだがHost id/versionやConstraint/金額が異なる | **G6 `checkout_context_mismatch/constraint_violation`** | 各原署名とHost正本比較値を保全。Schema VALIDをCheckout認可と呼ばない |
| **E06-N5** | Agent Terminal署名・`sd_hash`不一致、Host三者Agent鍵相違、またはMerchant署名不正 | **G4 `invalid_chain_binding/expected_agent_mismatch/invalid_checkout_signature`** | Root署名/完全性が成功した条件を固定。署名を検証前の構造拒否と混同しない |
| **E06-N6** | Unknown/disabled Issuer、Host trust policy失効/曖昧、key fallback要求 | **G1 `untrusted_issuer/incomplete_context`** | B署名独立VALIDが必要なら**別オラクルO1**で確認。G1拒否時にG2署名検証済みとしない |
| **E06-N7** | JWS/disclosure JSONキー重複、JOSE非対応、入力cap超過、Schema読み込み不能 | **G0 `ambiguous_signed_json/resource_limit`** または **G5 `verification_unavailable`** | 実際に到達したstageを記録。bounded fail closedをfull security proofへ転用しない |

**すでにあるが別経路の証拠:** E01-S IP01/02/03は合成S4/S1/S3までの限定実測、DC03は部分Open Schema INVALID、DC06の重複digestや第2 OpenはRoot件数に先行拒否。**本表のE06-P/N1–N7をRuby統合経路で実行済みと誤記禁止**。

将来の統合検証では、独立O1**元JWS署名**／O2**Agent・Merchant・Host binding**／O3**元Root全域commitment→Disclosure一対一**／O4**pinned公式Open/Closed Schema＋Host固定policy**／O5**同一Ruby候補のfirst reject stageと肯定前提**を保存する。**真正署名のない偽装負例・早期拒否だけ・CI SUCCESSだけ**を安全PASSと記さない。

## 4. 設計出口と、今は進めてはいけない範囲

- **今回のE06結果：`DESIGN_ORDER_PROPOSED / INTEGRATED_RUBY_UNPROVEN / PHASE2B_HOLD`。** この文書のCodexレビュー/PRマージだけでE06 technical gateをPASSにしない。最新の親[Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47)も**OPEN**。
- **次に別途審査すべき実装前の1件:** 既存DC04/P1-2/P1-3と合成E01-Sの境界を変更せずにG0–G7を同一Ruby経路で実現するための**小さな候補設計・差分一覧**、公式SchemaをRubyでどの形で固定ロードするか、入力/CPU/time/clock等の有限E07値、`VerifiedEvidence`のHost正本境界、E06-P/N1–N7のO1–O5オラクルと1回のCI上限/STOP条件を**別Issueで提案するだけ**。その実装・fixture・CIは独立したオーナー承認まで禁止。
- **本番と別:** 実Issuer identity/key/profileのR01–R06正本と鍵rotation/revocation **E01/E05未証明**、Host nonce消費CAS・Buyer本人性/Account認可・注文現在性・外部Authority HC06・決済・Receipt **E08/他GateでHOLD**、Artifact失効後の永続公開証拠 **E09未解決**。Rubyが署名を検証しても**お金を払ってよいという権限は出ない**。
- 対象・許可slot・Schemaを不明なまま広げたり、旧CI結果で新しい順序を証明したことにしたり、未知`_sd`を無視する変更を伴うなら**STOP/HOLD**。

## 5. 根拠

- [E00–E10 Exit Gate](PHASE2A_EXIT_GATE_DECISION_CHECKLIST.md)、[E01-S後の時点別スコアカード](PHASE2A_POST_E01S_EXIT_GATE_STATUS_2026_10_13.md)、[最小Verifier§4](PHASE2A_MINIMAL_VERIFIER_DESIGN.md)、[固定Issuer受理契約§4](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md)
- [DC01–DC06監査](PHASE2A_DC01_DC06_PROOF_GAP_AUDIT.md)、[E01-S設計](PHASE2A_E01S_MINIMAL_HOST_TRUST_ADAPTER_CONTRACT.md)、[PR #68](https://github.com/cuichangquan/ap2-mandate-verifier/pull/68)、[修正後E01-S CI](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38328627077)
- **現行Rubyの実装上限:** [合成E01-S `trust_probe.rb`](../research/phase2a_e01s/trust_probe.rb) → [隔離DC04 `fixed_issuer_verifier.rb`](../research/phase2a_dc04/fixed_issuer_verifier.rb) → [P1-2 two-hop](../research/p1_2/two_hop_research.rb) / [P1-3 Checkout binding](../research/p1_3/checkout_binding_research.rb)。Ruby側の公式Open/Closed Schema一体検証を実装済みとは主張しない。
- [公式AP2 v0.2.0 pinned schemas](https://github.com/google-agentic-commerce/AP2/tree/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2)。**過去の証拠を時点外へ昇格しない。**
