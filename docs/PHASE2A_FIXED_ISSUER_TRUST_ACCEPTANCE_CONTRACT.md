# Phase 2-A — 固定IssuerのTrust / 発行Profile受理契約（設計案）

**2026-10-13 JST / Parent [Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) / DESIGN ONLY / NOT IMPLEMENTED / NO NEW TESTS / Phase 2-B HOLD**

> **決定候補:** Candidate A（Hostが事前固定したIssuerと閉じたsigned-wire文法、すべてのcommitmentが解決されたときだけ限定的Evidence）。Issuerの署名だけで「隠れた権限はない」と断定しない。**この資料はTrust onboardingが完了したことも、実Issuerがこの契約を受諾したことも、Phase 2-A gate PASSも意味しない。**
>
> **変更範囲:** 文章のみ。Ruby実装/公開API/Gem、実署名fixture、CI実測、GCP、実Issuer、Authority/Host実装、Payment/Receiptの承認を含まない。親#47は**OPEN/HOLD**、Phase 2-Bとproductionは**NO-GO**。

## 1. 前提・暗号で証明できる上限

Pinned公式AP2 v0.2.0: `b4587ac1d055888a73b4b21750973cffba961793`。[開示完全性Gate](PHASE2A_DISCLOSURE_COMPLETENESS_GATE.md)、[最小Verifier契約](PHASE2A_MINIMAL_VERIFIER_DESIGN.md)、[DC01–DC06監査](PHASE2A_DC01_DC06_PROOF_GAP_AUDIT.md)、[Fail Closed Profile](FAIL_CLOSED_PROFILE.md)の**補完**であり、既存条件を緩めない。

区別する命題は次の3つ。

| 証明/信頼の層 | 誰の正本か | 得られる保証（条件付き） | **証明できないこと** |
| --- | --- | --- | --- |
| **T1 Issuer真正性** | Hostが事前登録したIssuer公開鍵・許可用途・alg、署名済みRoot原文 | その鍵に対応する秘密鍵で、**そのRootの署名対象バイト列**が署名された | 署名者の実世界の正当性、Root外の隠れた契約、全Disclosure提示、発行profileの自動認証 |
| **T2 signed-wire開示完全性** | T1で真正と認定したRootの**原文**、Disclosure原文とSHA-256 digest、固定の許可path文法 | Root全域の`_sd` / `{"...":digest}`を列挙し、各slotとDisclosureを1対1対応・完全消費、残余0／未知位置0／重複0を確認できる | SDKが返した解決済みOpenだけからの完全性、Rootに存在しない外部権限情報の不存在 |
| **T3 発行Profileの信頼** | Hostが**presentationとは独立に**審査・登録したIssuer identity / scope / 公開鍵 / immutable policy version / 閉じた文法 | **Hostが受理対象と定めた有限文法に対する**全権限フィールドの確認を求められる | Issuerがその文法以外の権限情報を現実に保持しないこと、発行元とHostの契約・鍵ライフサイクルが現に履行されたこと |

**受理の必要条件:** `T1 ∧ T2 ∧ T3 ∧ Schema ∧ constraints ∧ Host binding`。いずれか不明なら `Rejection` / `HOLD`、部分的な成功によるEvidenceは禁止。T3の独立の信頼根拠が欠けるとき、T1+T2だけでT3を「証明済み」に格上げしない。

**Profile versionに関する重要な線引き:** `issuer_policy_version` は**Host正本のバージョン**であり、pinned AP2 v0.2.0のRootが自動的に署名するprofile-id claimだとは仮定しない。異なるHost policyが同じIssuer鍵を受理するなら、`kid`や文字列versionの自己申告だけでは区別できない。Hostの**選択可能なpolicy集合を絞り、署名済み構造を選択済みの不変文法へ完全照合**しなければならない。選択が曖昧、降格可能、旧versionへfallbackするなら拒否する。

## 2. Host管理の固定Issuer Profile（構造候補、実データではない）

これはHost側の**不変・審査済みpolicy record**の論理フィールド。JSON形式やRubyのpublic APIを規定しない。値をユーザーが送ったMandateから信用・上書き・補完しない。

| Profileレコードの必須概念 | 保持/照合すべき情報 | 未設定・不一致の場合 |
| --- | --- | --- |
| `profile_ref`, `policy_version`, `policy_digest` | 一意ID、不変version、canonical policy内容のdigest。Tenant/使用目的にscopeし、監査可能な改訂履歴と承認者/承認時点を保存 | `unsupported_profile` / `incomplete_context` |
| `issuer_identity`, `trust_provenance` | Hostが**帯域外の審査**で確認したIssuerと根拠/出所（審査・承認記録）。JWT内`iss`だけを根拠にしない | `untrusted_issuer` |
| `issuer_keys` | 許可済み公開鍵の厳密なthumbprint/使用用途/ES256 P-256、固定key reference、not_before/not_after、active/失効判定の正本。提示`kid`は既登録鍵の候補検索のみ | `untrusted_issuer` / `invalid_signature` / `incomplete_context` |
| `allowed_spec_and_flow` | pinned AP2 commit、Autonomous/Human Not Present、Root `mandate.checkout.open.1` → Closed `mandate.checkout.1` **2hopだけ**、許可`typ`・`alg`・`_sd_alg`・SD hashモード | `unsupported_profile` |
| `signed_wire_grammar` | Root/Closed/JWS header・claimsの許可キー、型・個数・順序（意味があるとき）、Root階層と許可SD slotの**明示的closed allowlist**、重複/未知の拒否 | `unsupported_profile` / `incomplete_disclosure` |
| `authority_schema` | 制約は`checkout.line_items`と`checkout.allowed_merchants`各1、Merchant 1、Requirement 1、SKU 1、Checkout 1。未知権限フィールドとConstraint typeは拒否。公式Schemaとは別の**本OSS限定形状** | `unsupported_profile` / `unknown_constraint` |
| `disclosure_policy` | すべての権限関連signed commitmentの完全開示を要求。未知`_sd`・`...`・余剰Disclosure・decoy残余は受理しない。**decoy無効とのIssuer自己申告だけではなく、原wire残余を実査** | `incomplete_disclosure` / `unsupported_profile` |
| `bounded_limits` / `ttl_policy` | wire/JWT/Disclosure合計bytes、JWS個数、委任hop、ネスト深度、commitment/Disclosure数、JSON要素、処理時間、時刻skew、有限TTLの**審査済み具体的上限** | `incomplete_context` / `resource_limit_exceeded`。デフォルト無制限は禁止 |
| `trust_lifecycle` | activation/expiry/revocation、key rotation、issuer/profile再承認、policy撤回時の旧Evidence失効、Host trust snapshot再照合方式 | `untrusted_issuer` / `verification_unavailable` |

`policy_digest`は**Hostレコードの改ざん・改訂検出用**であり、Issuerの署名として扱わない。Hostの管理者権限・永続record改変・審査証拠の真正性は**Host運用の前提**で、この資料では実装・監査していない。

**Issuerが署名するprofile結合の選択肢（まだ採用しない）:** (A1) Host側で特定Issuer鍵／用途を1つの不変profileにだけ割当て、Rootの**元署名済み構造全体**が完全一致するときだけ認定する。(A2) Issuer自身が認証可能な署名済みprofile識別子/manifestを明示して固定profileへ結合する。**A2がpinned AP2で発行・検証できるかは未証明**で、独自拡張を標準AP2の必須機能と表現しない。初期候補AはA1の厳密なHost allowlistを先に評価するが、**実Issuerが発行profileに従う独立の約束/証拠の取得は未実施**。

## 3. 候補Aのclosed-world受理文法

[DC04の隔離Ruby研究候補](PHASE2A_DC04_BOUNDED_RUBY_FOLLOWUP.md)と一致させるため、**実験で受理した元署名Root array placeholder**の許可pathは次の3つだけ。下記pathは署名元wireを起点とした監査位置であり、発行者によって動的に増やしてはならない。

1. `$/delegate_payload/0` — 単一のRoot Open。
2. `$/delegate_payload/0/disclosed/constraints/1/allowed/0` — Merchantの選択配列要素1件。
3. `$/delegate_payload/0/disclosed/constraints/0/items/0/acceptable_items/0` — SKUの選択配列要素1件。

- 研究候補は**制約の順序も固定**。index `0` をline_items、`1`をallowed_merchantsとしたこの候補の挙動であり、AP2全発行者の標準順序だとは主張しない。
- Root `delegate_payload`は**配列長1**。未知Root同階層claim／余剰Open／同じdigestの2slot・未知object `_sd`は拒否。**先行配列件数拒否で止めた場合、digest走査やIssuer署名がRuby自身で成立した証拠にはならない**（[DC06追試](PHASE2A_DC06_FOLLOWUP_OBSERVATION.md)）。
- Rootの**最上位signed payloadから全子孫**を非破壊走査する。許可3pathの外にある`_sd`、`...`、未解決commitment、未知の署名済み権限候補を**すべて不明/拒否**扱いとする。resolved dictの可視値やOpen Schema VALIDだけで補完しない。
- 対応する各Disclosureは**原文base64urlのdigest**を使い、signed slotとの1対1対応と完全消費を確認。余剰/重複/異なるpathへの再利用/未解決/曖昧decoyはSTOP。Disclosureの型・内容・許可claimは完全解決後に別途制約チェック。
- Signed Rootの未知フィールドに「今後の拡張だから安全」とする例外、未登録のIssuer鍵やprofileへの自動移行、任意Issuer/任意hop/複数商品、privacy目的のauthority部分非開示は**UNSUPPORTED**。合法なAP2の一部を拒否し得る**ローカル制限**である。
- RootとTerminalの署名、Agent PoPと`sd_hash`、Merchant Checkout JWT/hash、Hostの事前固定Agent/Buyer/challenge/Checkout正本照合、時間とnonce CAS等の[別契約](PHASE2A_MINIMAL_VERIFIER_DESIGN.md)は削らない。closed-world文法を通過しても業務ALLOWではない。

## 4. deterministicな検証と証拠の出所

**設計上の順序**（早期拒否は許可、早期成功・権限評価は不可）:

1. **Pre-auth安全な構文判定:** 入力bytes・要素数・深度を固定上限内で扱う。元JWSのheader/payload、Disclosureに対しJSON重複キー（エスケープ後の同名を含む）、不正UTF-8、未知JOSE `alg`/`typ`/`crit`/embedded-key/network-key-lookupを拒否。署名の検証入力バイト列を再serializeしない。**ここでREJECTしても署名真正性を証明したと呼ばない。**
2. **Host trust snapshot:** 発行者候補の非信頼`iss`/`kid`は検索ヒントのみ。Hostが事前承認した単一profile・鍵・用途・有効期間・active/非失効を照合。policy selectionが曖昧、廃止versionへのrollback、正本不達ならSTOP。
3. **Crypto:** 選択済みIssuer鍵によるRoot JWS真正性、Root署名済み`cnf.jwk`とHost `expected_agent_key`・challenge発行時固定鍵の三者一致、Terminal JWS/PoP/`sd_hash`/aud/nonce、Merchant署名JWTとHost正本JWT/hashを各独立に検証する。Crypto検証前に構造上REJECTする実装は可だが、**真正署名付きnegativeとして合格扱いするには独立のO1/O2証明が必須**。
4. **Signed-wire completeness:** 未解決のIssuer Root全域からcommitment graphを収集し、Host固定許可path/slotと完全照合。Disclosure digest一対一、root残余0、未知/重複/decoyなし。拒否の**原因と判定段階**を記録し、cardinalityやSchema rejectと区別する。
5. **型・意味:** 公式pinned Open/Closedと対象Merchantの各Schema検査、Hostのより狭いProfile、全ての権限制約・金額/商品/Checkout・challenge/時刻を評価。**Completenessが成立する前に見えるConstraintだけ評価してEvidenceを生成しない。**
6. **Evidence（候補）:** [最小Verifier契約](PHASE2A_MINIMAL_VERIFIER_DESIGN.md)の必須`profile_ref`、`trust_snapshot`、`verified_challenge`、`checkout_binding`、`valid_until`の意味を保持。policy参照は検証時の**Host原本ID/version**、署名によるIssuer自身のpolicy-id attestではない。nonce-CAS・payment authorization・revocation済みという真偽値を含めない。

**旧設計文書との順序:** [最小Verifier契約 §4](PHASE2A_MINIMAL_VERIFIER_DESIGN.md)はSchemaをcompletenessより前に列挙した初期の設計案。本提案は、隠れたConstraintを可視Schema成功で受理したかのように誤認しないよう、**authenticityの成立 → completeness → 可視OpenのSchema／制約意味評価**を安全側の**新しい推奨順序**とする。ただし**Schema INVALIDの早期拒否**そのものは安全上許される。その際completeness検査を実行していないので、completeness拒否を実証したとは**主張禁止**。順序の整合・統合Rubyでの順序証明は未実施で、**将来の別レビューが必要**。

## 5. 登録・rotation・撤回時の扱い（Host責任、未実装）

1. **Enrollment / activation:** Issuer本人/鍵/用途/発行文法を**presentation以外の証跡**からHost管理者が承認し、Issuer鍵と不変`policy_version`とscopeを明示対応付ける。自己申告JWT・動的JWKS取得・SDKデフォルト・合成fixtureをHost trust rootに昇格させない。Issuerが本当に当該レイアウトを発行するという証跡が不足するなら**activation HOLD**。
2. **Immutable revisions:** 発行文法・許可SD slot・decoyポリシー・鍵・用途・時間・constraint型・上限の変更は**新規version**と新たなレビュー/承認が必要。旧versionの上書き、後戻り、互換性fallbackを禁止。発行tokenの`version`文字列だけでpolicyを自動選択しない。
3. **Rotation:** 新鍵は事前審査・有限`not_before/not_after`・鍵用途・profileへ明示対応。旧鍵受理終了時刻と切替ルールを明記。旧tokenの扱いはHostの現在のtrust policyに再照合、activeでなければSTOP。**未知旧keyでの成功fallbackなし**。
4. **Revocation / expiry:** 検証時にpolicy/keyのactive・非失効と現在時刻を照合、不達・不明・撤回でEvidence禁止。後続Host処理時には**trust_snapshotのprofile/key版と`valid_until`を現在のHost正本へ再照合**、変化があればSTOP/再検証。これは外部AuthorityのHC06強失効を証明しない。
5. **Auditability:** policy digest、承認根拠の管理参照、変更/rotation履歴、失敗理由、検証に使った署名原文のdigest（**原文秘密と私鍵は記録しない**）を監査可能にする。ログからraw nonce/JWT/private JWKを漏らさない。

**本資料で未決の設定値:** wire bytes、JWT/Disclosure個数、深度、commitment数、CPU時間、clock skew、TTLとtrust更新頻度の実数値、policy recordの耐久的配布・失効検知方式。**値が未設定のまま実装を始めて無制限に受け入れることは禁止**。この計画では設定値を推測で確定しない。

## 6. 反証可能な独立受入テスト（**設計のみ / ALL NOT RUN**）

将来の**別途承認済み**合成Issuer発行では、毎回**同じRuby候補に正常FULLを受理させた後**でなければnegative rejectionを計上しない。O1 Issuer／O2 Agent・Merchant・Host hash／O3 Root原文graph／O4 公式Schema＋Host profile／O5 Ruby reason+Trace/順序を**独立保存**する。署名無効・Schema INVALID・Root件数異常のみの早期Rejectをcompleteness guard PASSに数えない。

| ケースID（将来） | 正常FULLとの比較 | 必須オラクルと期待 | 現在 |
| --- | --- | --- | --- |
| **IP01** | Host固定Issuer/鍵・versionと閉じた文法が一致、全Disclosureが一対一・残余0 | O1–O5でcrypto・completeness・Schema PASS、Rubyは**限定Evidence候補**のみ（Host ALLOWなし） | NOT RUN |
| **IP02** | 有効な署名でもHost未登録Issuer/鍵、または提示`kid`で任意鍵差し替え | O1は署名それ自体の正当性とHost trustの**不一致を区別**、Ruby `untrusted_issuer` | NOT RUN |
| **IP03** | 同じIssuer/同じ鍵でもHostのactive profileと異なるlayout/version、旧版へのrollback・曖昧な二つのpolicy | Issuer署名VALIDでもT3不一致、Ruby `unsupported_profile`（古いprofileへfallback禁止） | NOT RUN |
| **IP04** | signed object `_sd`／未知Root兄弟claim／未知Constraint位置、余剰open slot | O3はRoot最上位から未知pathを証明、Rubyは理由を追跡してReject。**先行件数Rejectをcompleteness PASSと誤認しない** | NOT RUN（類似DC06の範囲外追加） |
| **IP05** | 同じIssuer署名RootでMerchant/SKU/line_items Disclosureを隠す | O1/O2はVALID、O3は特定digest未解決、Ruby `incomplete_disclosure`。可視Schema VALID/INVALIDを独立記録 | NOT RUN（類似DC02–DC04は限定実測済み） |
| **IP06** | 署名済み重複digest、余剰Disclosure、正真正銘のdecoy/未知位置 | O3で残余/重複を確認、Rubyが**どのゲートで**Rejectしたか追跡。generic guardは未証明 | NOT RUN（類似DC05–DC06は限定実測済み） |
| **IP07** | 正しい過去tokenだがHost policy/keyの撤回・期限切れ・rotation中、trust正本が不明 | Crypto VALIDと現在Host trust **INVALID/UNKNOWN**を分離し必ずSTOP | NOT RUN |
| **IP08** | Root署名はVALID、別Tenant/Buyer/challenge/Agent鍵/Checkout正本または異なるnonce | Host事前値とcryptographic bindingを照合、Rejection。Hostのnonce-CAS成功は主張しない | NOT RUN |
| **IP09** | signed Root/Disclosure JSONの重複キー・JOSE異常・資源上限逸脱 | crypto/Payload再serializeによる曖昧受理なし。`ambiguous_signed_json`/`resource_limit_exceeded`。境界設定値が確定しない場合BLOCKED | NOT RUN |

**追加設計判断が必要な項目:** 候補Bのmanifest（この文書ではUNSUPPORTED）、Issuer実在の独立確認/契約、実Issuer相互運用、DC07（Issuer/profile mismatch）を上記IP02–03で代用できるか、Schema/完全性の実行順序、長期保存可能な**公開鍵のみ**の再現証拠。過去のDC01–DC06は新IPケースのPASSへ自動繰上げしない。

## 7. Gate判定 — docsの完了とPhase 2-Bを切り離す

| 段階 | 必須事実 | この文書時点 |
| --- | --- | --- |
| **Design record** | Issuer署名・Root原文完全性・Host trust正本の責任境界、固定文法、Fail Closed、未決項目と独立oraclesを明記 | **PROPOSED FOR REVIEW**。docs mergeはこの段階だけ |
| **Phase 2-A completeness gate** | Host trust + Issuer identity/key/layout/versionの独立妥当性をレビューし、文法の閉包性・署名付き未知/非開示・decoy/重複・順序・資源境界を**反証可能な証拠**で確認。未決値を解消 | **HOLD / UNPROVEN** |
| **Phase 2-B scoped offline Ruby PoC** | Phase 2-A gateについて**別の明示的GO判断**、支持範囲を限定した計画・security review | **HOLD**。docsをマージしてもGOにならない |
| **Generic Gem/public API / Host production / payment/Receipt** | 対象Issuer/Schema/Host CAS/失効/耐障害・実業務の別契約と実証 | **NO-GO**。HC06/外部Authorityも別IssueでHOLD |

**最終判断:** Candidate Aは**条件付きの理論的受理方針**として詳細化できたが、Issuerが実際に従う発行契約/Host trust lifecycleが成立した証拠はまだなく、無制限profileの完全性は主張できない。Issuer署名、SDK `verify_chain`成功、Schema VALID、Ruby構造拒否、Codexレビュー/CI greenのいずれも**単独ではPhase 2-B GOではない**。親[Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47)を閉じない。

## 8. Pinned根拠

- [公式 Open Checkout JSON Schema](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json)
- [公式SD-JWT issuance / `add_decoy_claims`](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/sd_jwt.py)
- [公式`selectively_disclosable_claims`とbinding](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/common.py)
- [公式Disclosure metadata](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/disclosure_metadata.py)
- [公式Chain verifier](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/chain.py)
- [隔離Ruby候補と旧研究の境界](PHASE2A_DC04_BOUNDED_RUBY_FOLLOWUP.md) / [DC05独立decoy](PHASE2A_DC05_OBSERVATION.md) / [DC06署名付き未知構造](PHASE2A_DC06_OBSERVATION.md) / [DC06追加](PHASE2A_DC06_FOLLOWUP_OBSERVATION.md)

**資料の範囲は設計のみ。現行実装・実Issuer契約・受入profile認証・新規negative fixtureや実測の存在を主張しない。**
