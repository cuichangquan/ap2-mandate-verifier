# Phase 1 研究成果の総括と Phase 2 入口判断

**判定日：2026-10-12 JST / Issue [#43](https://github.com/cuichangquan/ap2-mandate-verifier/issues/43) / DESIGN & EVIDENCE INVENTORY ONLY / 新規セキュリティテストなし**

## 結論を先に

**Phase 1の限定的な研究成果は「次の最小仕様を設計するための材料」として十分。Phase 2の`設計のみ`はCONDITIONAL GO、Ruby Gem/API実装・公開・本番Merchant導入はHOLD、実決済・Receipt・外部Authority連携はNO-GO。**

`P1-10a`〜`P1-10u` は機能完成率ではなく、暗号Verifier、Merchant Host、外部Authorityの**異なる信頼境界**に関する調査の枝番号。**新しい`P1-10v`を追加することは、研究を終わらせる条件ではない。** 何かがテストでGREENでも、他の境界やAP2の一般適合性までGREENにしてはならない。

### 公式基準と対象

- 公式AP2：**v0.2.0 pinned commit `b4587ac1d055888a73b4b21750973cffba961793`**（[基準点](SPEC_BASELINE.md)）。将来の公式SDK変更を自動で包含しない。
- 現在のRubyコード：**固定Issuer・完全開示・厳格2hop・一行Checkoutの合成研究用プロファイル**。製品Gem/APIではない。
- 参照する現行研究結果：P1-10t [PR #41](https://github.com/cuichangquan/ap2-mandate-verifier/pull/41) は修正前の危険ACCEPT、P1-10u [PR #42](https://github.com/cuichangquan/ap2-mandate-verifier/pull/42) はS01限定の修正・回帰実測。過去の結果を事後的に書き換えない。

## 1. 研究エビデンス一覧 — 成果の種類を混同しない

`VERIFIED_CI`=参照したGitHub Actionsで実測、`VERIFIED_LOCAL`=ユーザーがMac Dockerで実測、`OBSERVED_UNSAFE`=危険なACCEPT等が**事実として再現**、`DESIGN_ONLY`=調査・仕様案のみ、`NOT_RUN`=予定ケース未実行、`OUT_OF_SCOPE`=今回のVerifier研究が保証しない領域。結果は**同じコードSHA・fixture・境界でのみ解釈**し、独立したテスト数を加算して適合率にはしない。

| 対象 | 確認した限定事実 | 証拠区分・参照 | 現在の境界 |
| --- | --- | --- | --- |
| P1-0〜3 Ruby↔公式Python | ES256/Schema spike **14/17**、SD-JWT Root完全開示 **10/22**、Agent委任 **15/32**、Merchant署名Checkout結合 **18/40**（順にrun/assertion、各0 failures） | **VERIFIED_CI**：[研究計画](RESEARCH_PLAN.md)と各CIリンク | 合成・固定AP2での限定相互運用。任意Issuerや非開示に一般化不可 |
| P1-5→P1-6 防御負例 | 初期署名付き負例18件で**6 RED/11 GREEN/1 HOST_BOUNDARY**、限定修正後 **17 GREEN/0 RED/1 HOST_BOUNDARY** | **VERIFIED_CI + OBSERVED_UNSAFE（当時）**：[負例](SECURITY_NEGATIVE_TESTS.md)、[修正](SECURITY_HARDENING_RESEARCH.md) | 修正した負例だけ。HOST_BOUNDARYは安全PASSではない |
| P1-10o 固定Issuer A-only | 正例1・拒否カテゴリ6・Host replay境界1、**8 runs / 45 assertions** | **VERIFIED_CI**：[結果](VERIFIER_P110O_EVIDENCE.md)、[Actions](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38154695155) | Replay/Host ALLOW未保証 |
| P1-10q→r GP01 | 旧VerifierはIssuer署名済み未知ネスト`policy_override`を**ACCEPT**。型・key allowlistの限定修正後は同じGP01をREJECT、別署名正常例ACCEPT：**2 runs / 10 assertions** | **OBSERVED_UNSAFE（旧）→ VERIFIED_CI（限定修正）**：[旧証拠](VERIFIER_P110Q_GP01_EVIDENCE.md)、[修正後](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38185735639) | 公式Schemaの全属性を網羅したわけではない。未知キーを全て許さないのはローカル研究policy |
| P1-10s 制約型・構造 | S01〜S08の残余リスクを静的に列挙 | **DESIGN_ONLY**：[一覧](VERIFIER_P110S_CONSTRAINT_SHAPE_TYPE_GAPS.md) | 現行のS01のみ後続で動的検証済み。他は一律GREENではない |
| P1-10t S01修正前 | Issuer/Agent/Merchant署名VALID、公式Schema INVALID（`Requirement.id=123`）、研究Verifier **ACCEPT / SECURITY RED-HOLD**。修正後observerによる観測は**1 run / 6 assertions** | **OBSERVED_UNSAFE + VERIFIED_LOCAL**：[PR #41](https://github.com/cuichangquan/ap2-mandate-verifier/pull/41)、[詳細](VERIFIER_P110T_S01_PREPARED_NOT_RUN.md) | **歴史的な危険受理の再現**。テスト緑は安全PASSでない。専用CI未実行 |
| P1-10u S01修正後 | 署名VALIDな同じ型不整合を、`invalid signed requirement id type`の**正確な理由でREJECT**。別の正署名正常例はevidence-only ACCEPT。**2 runs / 12 assertions / 失敗0** | **VERIFIED_LOCAL**：[PR #42](https://github.com/cuichangquan/ap2-mandate-verifier/pull/42)、[詳細](VERIFIER_P110U_S01_TYPE_FIX_PREPARED_NOT_RUN.md) | **固定IssuerのS01 String型だけLIMITED GREEN**。専用P1-10u GitHub Actions **NOT_RUN**、既存P1-10o/q/rのCI 3件は別範囲 |
| Host実DB競合・replay研究 | PostgreSQL 16で正本34ケース中**9件実測・25件NOT RUN**。nonce CAS、checkout version等の隔離した一部動作 | **VERIFIED_CI + NOT_RUN**：[Host計画](HOST_SECURITY_TEST_PLAN.md)、[P1-10a](HOST_REPLAY_P110A_EVIDENCE.md) | VerifierがHostリプレイ防止を保証することはない |
| 外部Authority・HC06 | 疑似Authorityの旧挙動に危険な失効/COMMIT競合、改良モデルの限定STOP。C01〜C12外部契約は未確認 | **OBSERVED_UNSAFE（合成旧方式） + DESIGN_ONLY/NOT_RUN（本物）**：[分離設計](VERIFIER_VS_REVOCATION_P110M_SCOPE.md)、[契約](HOST_EXTERNAL_REVOCATION_P110K_CONTRACT_CHECKLIST.md) | **HC06 FULL HOLD**。合成Mutex/2-DB試験を本番分散保証に加算しない |
| 実Issuer・非開示/任意hop・商用Trust管理、Gem、実決済 | 一般適合性・外部Issuer・Host最終ALLOW・Receipt、公開配布は検証していない | **NOT_RUN / OUT_OF_SCOPE**：[要件](VERIFIER_REQUIREMENTS.md)、[設計候補](API_PROPOSAL.md) | **Gem/API/本番統合HOLD、公開・実決済NO-GO** |

**脚注：** P1-10t旧observerの`1 run / 7 assertions`は変更前の**歴史的値**であり、現在の観測器の再実測`1/6`と混ぜない。P1-10u `2/12`はユーザー提供のMac Dockerログを保存したもので、CI実行を意味しない。CIで過去の「危険ACCEPT観測」が成功しても防御成功とは解釈しない。

## 2. MerchantのVerifierとHost/Authorityの信頼境界

```text
Issuer署名 + SD-JWT開示  ─────┐
Agent委任・PoP・aud/nonce ────┤
Merchant署名Checkout JWT ────┼──> [Ruby Mandate Verifier (候補)]
Hostから提供したCheckout正本 ─┘       │
              trusted keys/expected context   ├─ VERIFIED EVIDENCE (暗号・限定制約の証拠)
                                            └─ REJECTION（明確な理由でSTOP）
                                                │
                                                ▼
                                   [Merchant Host: 別の責任者]
                                    最新注文・ポリシー・在庫/金額
                                    nonce原子的消費・replay対策
                                    durable operation / outbox
                                    独立失効状態の確認 / STOP
                                                │
                                        最終ALLOWを判断
                                                │
                                  [決済Provider / Receipt: 別責務]
```

| 検証項目 | Ruby研究で確認できたこと | Ruby研究だけでは未証明なこと |
| --- | --- | --- |
| Issuer JWS・SD-JWT Disclosure | 固定IssuerのIssuer署名・Digest一致・必要Disclosureを合成正負で確認 | 未知Issuer、Issuer鍵更新/失効・hidden権限・任意レイアウト/全Schema |
| Root→Agent Closed、PoP | 固定2hopで`cnf`、Agent署名、`sd_hash`、`aud`/`nonce`、期限等の限定負例 | 多hop・第三者Issuer・異なる公式SDK/バージョン・全プロファイル |
| Merchant Checkout JWT・binding | Merchant署名とHostから受け取る原文JWT、hash、固定商品/店舗/金額の一部照合 | Hostの本当の「現在の注文」、認可、価格・在庫、決済可否 |
| Constraint/S01 | GP01の未知署名キーとS01の既知String型欠落を発見し、限定REJECTを観測 | S02〜S08、完全なSchema/意味評価、全ての開示・未知Constraint |
| Replay / revocation / 決済 | 限定DB/Authority合成研究で一部失敗モードを測定 | Host正本25件とHC06全体、リアルな外部AuthorityとProvider、Receipt |

**強制する原則：** Verifierが返す検証済み値は**「正当に署名されたデータから導ける証拠」**であって、**「この注文を実行してよい」ではない**。Issuer trustやMerchant鍵をVerifierが勝手に発見/承認しない。Hostは検証成功後も注文とnonceを自分の耐久トランザクション上で確認し、失効等の証拠が不明ならSTOPする。HC06の分散強失効をこのRuby Gemで解決済みと主張しない。

## 3. 残課題を3つの箱に分ける

| 優先分類 | 課題 | Phase 2での扱い |
| --- | --- | --- |
| **A：次の設計に必須** | 固定Issuerの明示的なTrust入力、何を完全開示とみなすか、`VerifiedEvidence`/`Rejection` の最低限の構造、署名とSchema検証の順番、未知/型不一致時Fail Closed、Hostから提供する期待context、テストオラクル | **設計のみ着手可**。まず受理可能なプロファイルと拒否規則を明文化。実装/配布は別決定 |
| **B：将来の拡張・互換性の条件** | S02〜S07の型/shape、optional`website`の扱い、その他全Schema項目、未知Issuer・hidden constraint・任意hop・SDK変更、複数Checkout | **Gap registerとして保持**。設計の互換性前提が必要な場合は調査するが、`P1-10v`等を自動開始しない |
| **C：別サービスの安全性責務** | Host replay正本残25件、operation/nonce一回限り、強い外部Authority失効HC06、C01〜C12、実Provider/Receipt、GCP/運用 | **Ruby暗号Verifierと分離**。本番利用可否のブロッカーを明示。別系統の実装/検証がない限り本番NO-GO |

**注意：** Bを後回しにするのは「安全だと判明したから」ではない。Aの設計自体が実装可能になるためにBの前提を必要とする場合、その箇所は**HOLDで停止**する。CをGemの外へ出しても、Hostが保証しない購入処理が安全になるわけではない。

## 4. Phase 2へのGO/HOLDゲート

| 進める対象 | 今回の判断 | Exit criteria |
| --- | --- | --- |
| **Phase 1の研究結果の棚卸し** | **COMPLETE FOR DECISION DOCUMENT**（全テスト完了ではない） | この一覧から各実測・危険観測・未確認・境界が辿れる |
| **Phase 2-A：最小Verifierの非本番仕様設計** | **CONDITIONAL GO — DESIGN ONLY** | ① 固定Issuer/完全開示/2hopのプロファイルを明示、②信頼鍵と期待値入力を定義、③検証と拒否の不変条件を定義、④Host責務を別表に記載、⑤S02等の未対応入力はSTOPと明記、⑥署名付き負例・正常例の必要最小テスト計画を定義、⑦実装着手前に残余リスクを再判定 |
| **Phase 2-B：Rubyライブラリ/APIのPoC実装** | **HOLD（自動的にGOではない）** | Phase 2-Aレビューと明示的なスコープ/実装判断。一般AP2準拠は引き続き主張しない |
| **Phase 2-C：汎用Gem、公開配布、商用Merchant/Host統合** | **HOLD/NO-GO** | サポート対象profile、完全Schema/失敗時安全性、独立した相互運用/CI、Host側security contract、運用責務の検証 |
| **外部HC06強失効・実決済/Receipt** | **HOLD/NO-GO** | 実Authority契約、Host排他的durable gate/耐障害証拠、Provider/監査/規格要件。独立した別プロジェクト判断が必要 |

### 次にやる「一件」だけ

**Phase 2-A の設計パッケージを一つ作る。** 内容は (1) `TrustedInputs` の候補、(2) `VerifiedEvidence / Rejection` の候補、(3) fail-closed decision table、(4) S02等の未対応ケースの明示、(5) Host integration contract、(6) 合成署名付き最小受入れ試験計画。**この資料はpublic Ruby APIを確定するものではない**。設計レビュー後にのみ次の実装/追加検証を選ぶ。

Phase 1の成果は「Rubyでできるか」という**限定技術成立性**と「署名が正しくても受け入れてはいけないデータがある」という**具体的な危険認識**。現実のMerchant導入準備が終わったことではない。

## 5. 引き継ぎの正本・更新ルール

- **現在の入口はこの資料と[RESEARCH_PLAN](RESEARCH_PLAN.md)、[Issue #43](https://github.com/cuichangquan/ap2-mandate-verifier/issues/43)**。旧`HANDOFF.md`やP1-10s/tの「次にP1-10t/uをやる」はその時点の**歴史的手順**で再実行しない。
- 最新GitHub main SHA / Open PR / Issue / Actions / Codex review は**次の作業時に再確認**する。この資料の数値は記載日の実測証拠であり、将来の最新版・汎用安全保証ではない。
- Phase 2-Aが動き出しても**Gem/API公開、本番決済、外部Authority/GCPサービス起動、他プロジェクト変更を自動承認しない**。
