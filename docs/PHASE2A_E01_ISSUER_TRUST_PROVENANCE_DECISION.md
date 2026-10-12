# Phase 2-A / E01 — Issuer信頼根拠の出所と研究スコープの分離

**決定記録: 2026-10-13 JST / [親Issue #47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) / DESIGN ONLY / 実Issuerの契約・登録 NOT VERIFIED / Phase 2-B HOLD**

> **判断:** 今ある証拠を基に `E01_REAL_ISSUER = UNPROVEN` と明記する。一方、`E01_SYNTHETIC_TRUST_INPUT = RESEARCH-DESIGN-ONLY` は**構成を定義できる**という意味に限る。合成Issuerの署名やHost役fixtureを実Issuerの本人確認・発行方針保証に昇格させない。どちらも `E01 = PASS` ではない。
>
> **本PRの作用範囲:** E01の根拠、未取得証拠、将来の承認分岐を文書化するのみ。実Issuerへの問い合わせ・Hostへの鍵登録・Ruby実装・fixture生成・CIテスト・GCP/本番決済は行わない。親#47 OPEN/HOLDとPhase 2-B NO-GOは維持する。

## 1. この判断が必要な理由

AP2 Open Checkoutの**Issuer JWS署名が有効**であっても、Veriferがその鍵を「Merchant Hostが承認するIssuerの鍵」と独立に結び付けていなければ、誰の権限を検証したのか決まらない。署名済Root全域のcommitmentを解析できても、**どの発行文法・どの権限範囲を受け入れるか**は署名単独から導出できない。

ここでは[固定Issuer受理契約](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md)の **T1（Root署名真正性）・T2（原signed-wire完全性）・T3（Hostの帯域外Issuer trust）**を別の証拠源として維持する。

- **T1**: 事前に選ばれた公開鍵で署名対象Root bytesが検証できる、という条件付き事実。自己申告`iss`/`kid`や署名それ自体は、その鍵の実世界の帰属先を示さない。
- **T2**: T1が成立したsigned Rootの内部に存在する許可commitment位置とDisclosureが一対一で尽きるかという検査。Rootに現れないIssuerの外部業務契約まで証明しない。
- **T3**: Merchant Hostが**提示Mandateの外から**Issuer identity・鍵・用途・不変profile version/文法・有効期間/失効を登録したという信頼設定。レコードの審査・真正性・現在性が独立に検証可能でなければ`UNPROVEN`。

**AP2 v0.2.0に標準Issuer registry、Issuerが署名する本OSS専用policy-version claim、信頼できるmanifest発行を仮定しない。** この設計はpinned公式commit `b4587ac1d055888a73b4b21750973cffba961793` に対象を固定する。Issuer鍵のTrustはネットワーク越しのJWT header URL/JWKSからその場で新規承認しない。

## 2. 現在の証拠台帳 — 提示済み事実と欠落

| 根拠ID | 原本・所在 | 実際に言えること | E01の位置付け |
| --- | --- | --- | --- |
| **P01 / pinned SDK** | 公式AP2 v0.2.0固定SHA、[DC01–DC06監査](PHASE2A_DC01_DC06_PROOF_GAP_AUDIT.md) | 合成Issuer/Agent/Merchantが実際の暗号署名を発行し、独立Pythonが公開鍵で検証した限定研究の証拠 | **T1限定OBSERVED**。実Issuer本人確認ではない |
| **P02 / Ruby候補** | [DC04隔離Ruby研究](PHASE2A_DC04_BOUNDED_RUBY_FOLLOWUP.md)、[DC05](PHASE2A_DC05_OBSERVATION.md)、[DC06](PHASE2A_DC06_FOLLOWUP_OBSERVATION.md) | Host役に相当する別与えの公開鍵を使用したstrict profileの限定受理と負例REJECT | **Hostの実運用Trust登録・T3ではない**。さらに統合完全性は未証明 |
| **P03 / 設計文書** | [固定Issuer受理契約](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md)、[Phase 2-A終了Gate](PHASE2A_EXIT_GATE_DECISION_CHECKLIST.md) | 必要なIssuer ID/key、immutable profile/鍵rotation、fail-closedと判定基準を文書化 | **DESIGN ONLY**。審査実施・Issuer同意・鍵登録の証拠ではない |
| **P04 / 実IssuerとHostの帯域外証拠** | **この研究リポジトリ・対象Issueに確認可能な審査済み証跡を記録していない** | 特定の実Issuerと、その本人性/公開鍵/発行用途/issuer-layout versionを結び付けた認証・承認を検証したとは言えない | **REAL_ISSUER_UNPROVEN**。外部世界にIssuerや契約が存在しないと断定するものではない |
| **P05 / 現在の登録・失効正本** | 本研究には本番Host trust registry、activation/revocation/rotation正本を構築・検証した証拠がない | 現在もそのIssuer鍵が当該Merchantで承認済み・有効だと確証できない | **OPERATIONAL_TRUST_NOT_RUN / HOLD** |

**証拠不足の正確な意味:** 「公開済みのSDKがある」「発行者を名乗る署名がある」「GitHub CIが緑」「論理的にHostが固定鍵を渡せる」は**本人・鍵所有・Issuer権限発行profileの同一性の根拠ではない**。実Issuerとの契約取得可否そのものはここでは評価・交渉していない。根拠未提示・未確認として扱う。

## 3. 実Issuerモードへ進むなら必要な独立のTrust package（本Issueでは取得しない）

特定のMerchant / tenant / use caseに対して、少なくとも次を**Hostの信頼正本**に結び付けた証拠IDと審査記録を持つ。

| 必須証拠 | 独立の出所・確認方法（案） | 欠落した場合 |
| --- | --- | --- |
| **R01 Issuerのidentityと発行権限** | Merchantが信用する帯域外の登録・契約・認証済み相手先記録で、そのIssuerが**どの用途のMandateを発行可能か**を特定する。署名claim内の表示名を根拠にしない | `untrusted_issuer` |
| **R02 identity→鍵の結合** | 上記の審査済みIssuerからの認証済み鍵受渡し・署名付きkey assertion等を、Host承認記録に参照して鍵thumbprint/JWKパラメータ・alg・purposeを固定。自己申告JWKS URLだけを信頼起点にしない | `untrusted_issuer` / `invalid_signature` |
| **R03 issuer→発行profileの結合** | IssuerとHostがレビュー可能な固定の発行文法・version/適用条件・disclosure位置・decoy方針を明示し、その相互対応を**独立した認証済み合意または信頼できる発行証跡**で拘束する。pinned AP2がsigned `profile_version` claimを自動提供すると仮定しない | `unsupported_profile` / `incomplete_context` |
| **R04 Host immutable policy** | Merchant/tenant scope、`profile_ref`、`policy_version`、`policy_digest`、承認者/時刻、鍵not_before/not_after、policy active statusを追跡可能に保全。**鍵とprofileの組合せを一意に絞り、downgrade候補は除外** | `incomplete_context` / `unsupported_profile` |
| **R05 lifecycle** | Issuer/鍵/profile変更・rotation・撤回の情報源と判定時のfreshness、Host検証時と後段CAS時の再照合、未知ならSTOP。外部Authority HC06の失効保証は別系統 | `verification_unavailable` / HOLD |
| **R06 独立のacceptance evidence** | Pinned公式SDKで発行されたFULL positiveと署名付きprofile/鍵ミスマッチを、Issuer T1、signed-wire T2、Host T3に分けたオラクルで確認 | **NOT RUN**（IP02/IP03/IP07は未実施） |

**本人確認の難度と範囲:** 公開鍵を手渡された証拠とIssuerが特定merchantの権限を発行してよいという**業務信頼**は別。Host審査の根拠を物理的に公開する必要はないが、**審査の実施・承認者・検証方法・immutabilityを後から監査可能**にする。機密の契約書や秘密鍵を公開リポジトリへcommitしない。必要に応じて機密Host recordへの非秘密な証拠参照のみ残す。

## 4. 合成Issuer研究モードの意味（別承認が必要）

**候補研究目的:** 実Issuerの本人/運用保証とは切り離し、同一固定形状の合成Issuerで「Hostが鍵・version・閉じた文法を独立に固定したと仮定すると、署名VALIDでも異なる鍵・profile・非開示の権限をどこでREJECTできるか」を確かめること。

研究用Host trust fixtureの**概念上の前提**（本資料では未作成）:

1. 研究者が**合成**Issuer identityと公開鍵thumbprint/用途/alg/有効期間/不変`policy_version`を**入力Mandateと独立**に決め、研究profileの根拠として固定する。合成鍵のprivate部分はCI等の隔離実行で一時利用し、永続化・commitしない。
2. `signed_wire_grammar`は[Candidate A固定文法](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md#3-候補aのclosed-world受理文法)と一致させ、3つの許可slot・Root Open 1・Constraint 2の厳密shapeを宣言。全unknown/decoy/remaining commitment/余剰DisclosureはREJECTする。
3. Synthetic issuance と Host fixture生成を**別の経路/原本**として扱い、Verifierにpresentation由来の鍵・profile版を自動承認させない。本人確認・本物の契約履行・商用Issuer registryが存在したように見せない。
4. `T1`（誰かが署名した）と`T3_SYNTHETIC`（Hostが事前に試験用のその鍵/profileを選んだ）と`T2`（Root全commitmentが許可文法に一致し開示済み）を**別欄**にする。成功でも`REAL_ISSUER_TRUST`、`AUTHORIZED_PAYMENT`に変換しない。
5. 秘密鍵/実JWT・商用ユーザー情報を保管しない。表示する証拠はpublic-key-only、原文SHA256/byte size、upstream SHA、Ruby HEAD、依存freeze、署名原本に対する独立検証結果。Actions artifactの7日期限を超える長期再現性は別設計が必要。

| 将来の負例（**ALL NOT RUN in this decision**） | 独立の真偽 | 期待する限定的なRuby判定と境界 |
| --- | --- | --- |
| **IP01** 固定鍵/profileのFULL | T1 VALID + synthetic Host T3 match + original Root T2 complete +公式Schema VALID | 限定的positive prerequisite。Host ALLOWではない |
| **IP02** 未登録署名鍵 | 攻撃者自身の鍵では署名VALID、**Host trust不一致**を独立確認 | `untrusted_issuer`。署名自体がINVALIDだったから拒否では足りない |
| **IP03** 同一鍵別version/layout/曖昧profile | T1 VALID、**Host選択の不変文法と不一致**を独立確認 | `unsupported_profile`。Root cardinality等の先行REJECTは正確に表示 |
| **IP05** Merchant/SKU/constraintのDisclosure省略 | Issuer署名/Agent binding VALID、signed Rootに未解決digestがある | Rubyが`incomplete_disclosure`を実際に判定した到達stageを記録。可視Schema INVALIDによる先行REJECTと区別 |
| **IP07** 廃止/撤回/有効期限外の鍵・policy | T1暗号署名VALID、**Hostの現在trust正本は非承認** | `untrusted_issuer`/`verification_unavailable`等、policy未確定はSTOP。実運用revocationには一般化不可 |

**次回の合成実験実行はこの文書で許可しない。** 別Issue/PRで、前提・オラクル・有限の資源上限/時間上限・実装改変の有無・署名鍵の扱い・CI scope・停止条件を承認してから着手する。E07の具体的な数字は**未決**なので、無制限入力を成功させる前提は承認しない。

## 5. E01判断の分岐と停止規則

| 分岐 | 判定できる条件 | その場合の行動・許可境界 |
| --- | --- | --- |
| **A: REAL_ISSUER_EVIDENCE_READY** | 特定のIssuer/Hostが選定され、R01–R05の審査証拠が原本に遡れ、後続R06の実測計画が別承認可能 | E01を**再評価する資格がある**だけ。現時点では**該当事実なし**。R06/E03–E09未達ならPhase 2-B HOLD |
| **B: SYNTHETIC_ONLY_RESEARCH_CANDIDATE** | 実Issuer出所を証明する証跡が未取得でも、Host役trust fixtureと限定評価目的を区別できる | E01_REALを**UNPROVENに固定**。別承認されたPhase 2-A合成の範囲内でIP02/03等の技術検証を提案可能。**本決定ではまだ着手しない** |
| **C: NO_INDEPENDENT_TRUST_OR_ORACLE** | 合成でもHostから独立のkey/profile定義が作れない、signed-wire原本が監査不可能、または未解決が容認される | **研究自体HOLD**。見えるConstraintだけで成功させず、追加negative量産で代替しない |

**今回の実際の選択: B（研究候補としての計画のみ）+ `E01_REAL_ISSUER=UNPROVEN`。** 実Issuerを選定・認証したという記録はこのリポジトリで確認していないため、Aを選ばない。Bも**Phase 2-A安全GateをPASSしたわけではなく、合成実験の許可でもない**。追加の別承認がなければ現状維持/HOLD。

**Phase 2-A E01終了条件:** R01–R05の正本参照と適用範囲・限界、または合成に限定した明示的な研究スコープ・trust fixtureの確立が別途独立に審査され、R06の署名付き負例とE03–E09の残課題が証拠付で評価されて初めて**対象を限定した再判断**が可能。synthetic-onlyの成功は`E01_REAL`をPASSさせない。

## 6. ここで引き継ぐ次の**一件**

**別Issueで提案するだけ:** `Phase 2-A / E01-S — synthetic Host-fixed Issuer trust provenance probe (IP01–IP03)`。範囲は**signed FULL positive+有効署名だが未登録鍵/異なる発行profile**の最小ケースにし、Issuer署名とHost鍵受理の因果の分離に専念する。IP05/IP07、統合Schema、リソース上限値、Host CASは必要性を別判断する。実行/CI/fixture変更は**別承認後のみ**。

- **合格に必要:** 有効Issuer署名であることをHost trust判定から独立に示し、同じRuby候補で正例と負例を確認できる設計。失敗コードと実到達stageを残し、事前構造拒否をIssuer trust拒否の成功へすり替えない。
- **未決/ストッパー:** 誰がHost trust fixtureを正本として凍結するか、`policy_version`の取り扱い、署名primitiveとの整合、有限のinput/TTL上限、実行environment/cost、7日artifact後の再現性。
- **判定:** 今回は**PROPOSED ONLY**。Phase 2-B/Gem/public API/Host本番・外部HC06・payment・Receiptについて新たなGOは一つもない。

## 7. 出典（研究scopeでの根拠）

- [E00–E10終了チェックリスト](PHASE2A_EXIT_GATE_DECISION_CHECKLIST.md) / [PR #63](https://github.com/cuichangquan/ap2-mandate-verifier/pull/63)
- [固定Issuer acceptance contract](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md) / [PR #62](https://github.com/cuichangquan/ap2-mandate-verifier/pull/62)
- [DC01–DC06監査](PHASE2A_DC01_DC06_PROOF_GAP_AUDIT.md) / [PR #61](https://github.com/cuichangquan/ap2-mandate-verifier/pull/61)
- [最小Verifier・Host責務](PHASE2A_MINIMAL_VERIFIER_DESIGN.md) / [開示完全性候補A/B](PHASE2A_DISCLOSURE_COMPLETENESS_GATE.md)
- [固定Ruby候補の実到達拒否](PHASE2A_DC04_BOUNDED_RUBY_FOLLOWUP.md) / [二個Open/重複digest追試](PHASE2A_DC06_FOLLOWUP_OBSERVATION.md)
- [公式pinned AP2 v0.2.0](https://github.com/google-agentic-commerce/AP2/tree/b4587ac1d055888a73b4b21750973cffba961793)

**この記録は研究上のGate判断であり、公式AP2の全Issuerに適用される安全性認定ではない。**
