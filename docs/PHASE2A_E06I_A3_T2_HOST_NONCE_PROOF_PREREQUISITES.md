# Phase 2-A E06-I — A3-T2前提条件：Host真正性・永続nonce発行証拠

**2026-10-13 JST · [Issue #89](https://github.com/cuichangquan/ap2-mandate-verifier/issues/89) · DESIGN ONLY · NOT RUN · A3-T2 NOT APPROVED · Approval B NOT APPROVED · G1/G7 HOLD · Phase 2-B HOLD**

- 対象：公式AP2 v0.2.0 [`b4587ac1d055888a73b4b21750973cffba961793`](https://github.com/google-agentic-commerce/AP2/tree/b4587ac1d055888a73b4b21750973cffba961793)、固定Issuer A、2hop、signed Open Root 1件、許可SD array slot 3箇所、Checkout 1件・Merchant 1件・SKU 1件の**限定研究**。
- 状態の正本：親[#47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47)、承認Bゲート[#73](https://github.com/cuichangquan/ap2-mandate-verifier/issues/73)、A3-H1[#83](https://github.com/cuichangquan/ap2-mandate-verifier/issues/83)、A3-T1[#87](https://github.com/cuichangquan/ap2-mandate-verifier/issues/87)とマージ済み[PR #88](https://github.com/cuichangquan/ap2-mandate-verifier/pull/88)。作成時のmain：`1048f31695ec238417e0c8037f940e026e7265d3`。
- 本書は**「後に何を独立して確認すべきか」だけ**を記録する。独立Host registry・DB台帳・nonce消費・実行証拠を新規作成したわけではない。Ruby実装、テスト、fixture、CI、実決済は行わない。

## 1. 一枚でわかる未証明部分

```text
               検証フロー：入力に対するステージ順序
                      G0 元wireの厳格・上限検査
                                |
                                v
                      G1 Host信頼確認
                                ^
                                |
                  HOST正本の世界（未実証）
       登録・承認履歴 / 鍵・policyの失効 / 信頼済み時刻
       発行nonceのHost全域・原子的・永続一意性（未実証）
       ※ G0を通過した入力に対してのみG1へ進む
                                |
              （G1の成功には独立出所の証明が必要）
                                v
                 G2 Issuerの元Root署名確認
                                |
                 G3 元Root全域の完全開示
                                |
                 G4 Agent/Merchant署名と結合
                                |
                 G5 公式Open/Closed/Merchant Schema
                                |
                 G6 全制約とHost Checkoutの照合
                                |
                 G7 有限期限のEvidence「のみ」
                                |
          Hostによる現在状態の再照合と一回限りのnonce消費
                                |
                       Hostだけが最終判断
```

**現実：** A3-H1はユーザーが渡した「Hostらしい登録簿／nonce台帳JSON」の整合を見るだけ。A3-T1は同じ`verified_at`と元のRoot/Terminal/Checkoutワイヤのダイジェストを結びつけるHOLD専用候補。いずれも**本物のHostを証明する出所がない**ためG1・G7はHOLD。歴史的`observe`も真正なG0→G7統合実装ではない。

## 2. Host真正性：必要な証拠（HT）

| ID | Host正本から証明する事項 | 独立した証拠の作成者／確認手段（将来） | 満たさない場合 |
| --- | --- | --- | --- |
| HT01 | Issuer Aの実体、許可用途・tenant、固定`profile_ref`/version、ES256公開鍵のRFC 7638 thumbprint | JWT/Presentationと**別の承認経路**でHost管理者が固定し、登録・変更・承認者・対象キーと用途の監査履歴を保存する。読み取り側は登録正本と照合 | 未登録/不一致：REJECT。不明/経路不明：HOLD |
| HT02 | Issuer・Agent・Merchantの**それぞれの鍵とポリシー**が`verified_at`でactive、明示的にnon-revoked、有限の`not_before/not_after`を持つ | Host管理下の版固定されたkey/policyレコードと署名またはアクセス制御された監査ログ、失効観測時刻・取得元・期限。鍵rotate/撤回の旧版履歴 | 既知revoked/disabled/期限外：REJECT。状態不明・古い正本：HOLD |
| HT03 | 独立Hostの信頼ルート、書込権限と検証器の信頼済み読出し境界 | 事前登録されたHostスコープ/権限・正本配布経路と変更管理。tokenの`iss/kid/jwk/jku/x5u`、caller JSON、申告した`source_ref`や一致SHAを**選択権限にしない** | 独立の出所未証明：HOLD |
| HT04 | 同一版・同一時点のIssuer/Agent/Merchant/Challenge/Checkoutスナップショット | 信頼できるスナップショットrevision/トランザクション境界、整合したrecord-id/version、監査可能な単一`verified_at`と有限skew/鮮度policy | 読み分け・後から一部差替え・clock由来不明：HOLD。既知改変：REJECT |
| HT05 | Challenge発行時のAgent thumbprint・Buyer/Account・aud・nonceと、`checkout_ref=(tenant_id,checkout_id,checkout_version)`および**元のMerchant署名JWTバイト列**のHost側結合 | Hostの永続Checkoutレコードとimmutable JWT digest / issuance reference / 同一revisionのトランザクション証跡。Checkout versionはtokenの`id`だけから**推定しない** | 明確な不一致：REJECT。記録不在/出所不明：HOLD |
| HT06 | policy・鍵・revocation変更後に旧Evidenceを安全に扱えること | revision増分、失効/rotationの反映ポリシー、Host最終判断直前の**現在の正本の再照合**と監査結果 | 矛盾/既知失効：REJECT。不確実/取得不能：HOLD |

**重要：** ラボ内で固定した`Issuer A`という**架空の識別子**と鍵fingerprintの整合は、実社会でそのIssuerが登録・承認された証拠ではない。動的JWKS取得、署名済みRootからのHost登録、自己署名されたclaims、あるいはRuby内の`SourceClaim`をHost信頼ルートに昇格させない。外部Authorityの強失効HC06は**別境界**として未証明のまま。

## 3. Host-wide nonce：発行の証拠と消費の証拠を分ける（NI/NC）

**署名上の落とし穴：** 現行の固定Terminalは`aud`と`nonce`に署名するが、`tenant_id`、session、`challenge_ref`を署名で束縛しない。そのためセッション別・tenant別だけの`UNIQUE`を信頼してはならない。最小の保守的設計は**Host-verifier全体**で同じnonceを永久に再発行しないこと（同じ署名検証領域内の全tenant/session、発行済み・消費済み・期限切れ・再発行を含む）。

| ID | 必須不変条件 | 将来必要な独立証拠 | 不備時の判断 |
| --- | --- | --- | --- |
| NI01 生成 | CSPRNG由来の推測困難性が**最低128 bit**。nonce長が16 bytesあることや`entropy_bits=128`文字列は証明でない | レビュー済みCSPRNG API/設定、発行側実装経路、OS乱数失敗時のSTOP、発行監査・独立なテスト観測。サンプルの統計値だけで128bit保証と呼ばない | 出所不明：HOLD。既知非CSPRNG：REJECT |
| NI02 全域一意 | issuanceの**DB原子的UNIQUE**をtenant/session/期間で分断しない。例：単一Host-verifier domainの`nonce_sha256`一意制約（または同等に厳密な全域制約） | DB schemaの実制約・migration SHA、全worker/書込経路で同じ共有正本を使用する設計、2 worker競合時の一方のみcommitの観測 | scope不足・既知重複：REJECT。耐久性/共有域不明：HOLD |
| NI03 永続履歴 | 発行→消費→失効→再発行後も**元のnonce使用履歴は忘れない**。TTL deleteで一意性をリセットしない | append-only発行イベントまたは削除されないunique/tombstone等の保持契約、バックアップ/復元・復旧時のmonotonic履歴、reissue時の旧nonce参照 | 既知再利用：REJECT。履歴欠落/rollback疑い：HOLD |
| NI04 紐付け | `issuance_ref`、`challenge_ref`、`aud`、`nonce_sha256`、発行時Agent thumbprint、Buyer/Account、Checkoutのtenant/id/version・**元のCheckout JWT digest**、`issued_at/expires_at`が同じHost発行コミットに固定 | 独立Host書込レコード、commit/row-versionと原記録の照合、Terminalの署名済みaud/nonceと別途G4で突合 | 既知別Challengeへの貼替：REJECT。独立レコードなし：HOLD |
| NI05 可用性 | durable registry不可・読み取りが遅延/古い・二重primary・commit ACK不明などで安全な新発行/検証成功を主張しない | authoritative primary / consistency契約、失敗・障害時の停止、各リクエストの読み取りrevisionと確定commitの監査 | 判定不能：HOLD（推測で「未発行」扱いしない） |
| NC01 一回消費 | **Host最終認可時**に`state=ISSUED`→`CONSUMED`の条件付きatomic update/CASで更新成功1件だけ | DB row-count=1とcheckout-current-state・operation一意性を1トランザクションに含む監査可能なcommit証拠（将来別承認） | 二度目の既知消費：REJECT。DB競合・結果不明：STOP/HOLD |
| NC02 業務上の副作用 | 異なるnonceでも同一の一回限りCheckoutに新operationを発生させない。決済Providerの冪等性は別の責任 | checkout/operation一意制約、同一transaction outbox、Provider側idempotency key処理の別契約 | Verifier EvidenceだけでHost ALLOWにしない |

**NI02とNC01は別物。** 発行時の一意制約は「異なるChallengeに同じnonceを配らない」保証であり、消費のCASは「同じChallengeを二度使えない」保証。A3-T2のRubyが`nonce_consumed=true`、支払許可、配送成功を返す設計は不可。P1-8以降のHost replay検証資料はHost-side CAS/Checkout/Providerを扱う**別の証拠系列**であり、このE06-I A3-H1の実登録正本やHost全体のnonce発行履歴に証明を自動移植しない。

## 4. 依存する同一スナップショットと時計の制約（G1→G7）

- **G0**：元JWS/Disclosure/Checkout JWT全バイト列をbounded・strict JSON/JOSEとして検査。ここでは署名やHost登録は未証明。
- **G1**：HT01–HT05・NI01–NI05の**独立Host正本**を照合して初めて、登録Issuerとnonce発行の信頼を条件付きで検討できる。現行の`isolated_host_snapshot.rb`、`isolated_host_source.rb`、`isolated_nonce_issuance_source.rb`はcallerの主張同士の照合で、すべてHOLD専用。
- **G2/G3**：G1でHostが選択した公開鍵で**元Root署名対象byte**を検証し、Issuerの固定3箇所の完全開示と署名済み`iat/exp`を同じ`verified_at`で判定する。A3-T1`verify_full_root_at!`は時計一元化の**診断候補**であり、caller時刻や自称Host鍵を採用しても真正なG2/G3にならない。
- **G4**：G3の認証済みAgent公開鍵・G1の発行時Agent thumbprintの三者一致、Agent署名Terminalの`aud/nonce`と`sd_hash`、Merchant署名・元Checkout JWTバイト同一性を照合する。別物を暗号通過扱いしない。
- **G5→G6**：同じ呼出しで固定公式Open/Closed/深いMerchant JSON Schemaの後に、完全に開示済み制約とHost Checkout現在状態を比較する。旧monolithic検証をG4へ流用してG6がG5より先に動くことは禁止。
- **G7**：G0–G6の各実到達・出所・元バイトSHAが一つの改変不能な結果チェーンに結びついた後に、**Evidence-only**を検討。`valid_until`は次の**独立して確認した有限期限の最小値以下**：Issuer署名Open exp、Agent署名Terminal exp（欠ける場合、別途審査済の有限Host代替期限）、**Agent署名Closed exp（Terminal代替では免除不可）**、Host Challenge expiry、Issuer/Agent/Merchantの各鍵・各policy not_after、Host policy/TTL cutoff、その他適用される署名済み/信頼済み期限。欠ける期限や未決skewではHOLD。
- **Host final decision（Verifierの外）**：現在のtrust/失効/Buyer/Checkoutを**再照合**し、原子的なnonce消費・Checkout一度限りのoperation更新を完了したHostだけが認可を判断する。Evidenceの作成時点はHostの最終認可時点ではない。

## 5. 将来の反証可能なケース（**すべて未実行・新たな実行許可ではない**）

| ケース | 変更点（独立オラクルが対象を確認） | 期待・制約 |
| --- | --- | --- |
| TP01 | Host登録済Issuer A、key/policy/checkout/challenge/nonceが**正本に**一致 | 完全な独立Host source／issuance証拠が得られる**まではHOLD**。fixture自己申告だけではGREENにしない |
| TP02 | 未登録Issuer Bの署名はB鍵でVALID、HostにBの登録がない | 真正の署名とHost拒否を区別。Host信頼段階でREJECT（G2/G3を実行した証拠にしない） |
| TP03 | Issuer/Agent/Merchantの鍵またはpolicyが撤回済み、またはpolicy version rollback | 既知撤回・旧版fallback：REJECT。観測遅延/unknown：HOLD |
| TP04 | 自称Host JSONとdigestは一致しているが、Host正本の出所・ACL・監査証跡がない | HOLD。`source_ref`文字列とsha256一致を認証と呼ばない |
| TP05 | 別tenant/sessionで同一nonceを同時発行する2worker | 一方だけ発行commit、他方は失敗。**未来の別承認されたDB実験**で独立に観測 |
| TP06 | 期限切れ/消費済みnonceを別Challengeに再割当、または台帳一部を削除/復元 | 既知nonce再利用はREJECT。履歴が欠損ならHOLD |
| TP07 | nonceは同一だが`challenge_ref`、Buyer、Checkout version、発行時Agentを変更 | 発行元の凍結された関連レコードと不一致：REJECT。Terminalはchallenge_ref等を署名していない |
| TP08 | registry timeout、未知commit、stale replica、DB復旧後の不整合 | HOLD/STOP。Host台帳の失敗を「存在しない」と見做さない |
| TP09 | clockの起源不明、Host SnapshotとG3のverified_at違い、期限の境界 | HOLD（時刻不明）、または有効期間外でREJECT。再サンプル`Time.now`へのfallbackなし |
| TP10 | 一つのCheckoutに別nonceで2回、同じnonceで2workerが認可競合 | Host CAS+Checkout/operationで一つのみcommit。Verifierの成功をHost CASの成功と呼ばない |
| TP11 | 最短期限のうちClosed expやMerchant key/policy期限が欠損・先に満了 | G7 evidenceなし。勝手な延長や欠損期限の代用なし |
| TP12 | Issuer/nonce正本は自称一致、しかしG0元wire/署名/Root closureに失敗 | 前段の実到達REJECTとして記録。後段到達の偽装・根拠なきHOLD→SUCCESS禁止 |

**注意：** これらは**証明責務の例示**であり、承認Bの既存「13ケース以内・手動1回」の実行計画へ自動追加しない。DB競合・障害注入を伴う実験は、既存のRuby統合検証Bとは**別スコープの明示承認**が必要。合成ラボでの成功も本番Host/Issuerの運用保証にならない。

## 6. 証拠パッケージに最低限必要なもの（提案・未収集）

| 区分 | 後続の独立レビューが照合する記録（公開可能な合成・秘密なしの形） | 出所がない時 |
| --- | --- | --- |
| E-Host | Host登録承認者と独立正本の所在/権限、Issuer/Agent/Merchant key thumbprint・policy version、active/revocationの根拠と観測時点、版更新履歴 | HT01–HT04 HOLD |
| E-Clock | 単一`verified_at`の取得元、snapshot revision、UTC epoch単位、許容skew/鮮度/タイムアウトを**事前承認**したpolicy | G1/G3/G7 HOLD |
| E-Checkout | ChallengeとCheckout tenant/id/version、Buyer/Agent/nonce/aud、元Checkout JWT SHA、同じrevisionでの読出し・発行commit参照 | G1/G4/G6 HOLD |
| E-Issuance | 採用したCSPRNG実装の根拠、実DB uniqueスキーマと全worker共有域、発行commit/不再利用履歴、atomic race/rollback/restoreの独立観測 | NI01–NI05 HOLD |
| E-HostFinal | 消費CASの更新件数、Checkout/operation/outboxの同一transaction、衝突/障害後の結果とProvider冪等性の別境界 | Host final ALLOW未証明 |
| E-Crypto | 公式固定AP2原文SHA、独立Issuer/Agent/Merchant署名・original SD全域開示・Open/Closed/Merchant Schema oracle、ステージの実到達と停止原因 | Verifier統合正例未証明 |

機密・実データ/秘密鍵、raw nonce、Buyer識別情報、実JWTを証拠artifactに含めない。digestを記録するなら**その元データの真の信頼源**も記載する。PR/Issueコメント、静的Codexレビュー、`freeze`、`unique=true`、成功した別研究のCI Run、自己整合JSONは独立Host正本や原子的DB commitの証拠ではない。

## 7. 最終判定表とSTOP条件

| 判定対象 | 現在（PR #88マージ後） | 前進の必要条件 |
| --- | --- | --- |
| A3-H1 Host source / nonce inspectors | 研究ソース静的レビュー済・**未実行**・入力自己申告につきHOLD | HT01–HT06、NI01–NI05の出所と監査可能な真のHost台帳を別途設計・レビュー・必要なら承認済み実測で確認 |
| A3-T1 clock / stage candidate | マージ済み・**未実行**・verified_atは未認証、deep freezeは構造のみ | trusted clockと正本の同一revision、一つの原ワイヤidentityを認証済みresultに安全に接続できる契約 |
| A3-T2 authenticated G1→G7 handoff | **未承認 / 未実装** | 本書の未証明点の審査後、**新たなOwner明示承認**で対象パス・Host責務・結果型・STOPを先に固定 |
| 承認B（Ruby/Python/fixture/test/CI） | **未承認 / NOT RUN** | [#73](https://github.com/cuichangquan/ap2-mandate-verifier/issues/73)で別途明示許可。承認外のlocal Ruby/CI/DBは不可 |
| Phase 2-A exit / Phase 2-B | **HOLD** | 独立証拠・段階別実測・安全性・未実装境界の審査と別のGO判断。docsのマージだけでは移行しない |
| Real Host/Gem/payment/Receipt | **対象外 / NO-GO** | 生産環境の独立Host信頼、失効/Buyer/Checkout/二重決済・障害時保証は別の設計/運用証明が必要 |

**Fail-closed優先順位：** 既知の偽造・不一致・revoked・nonce再利用 ⇒ **REJECT**。Host出所・nonce履歴・clock・stateが未取得/unknown/stale ⇒ **HOLD**。一方のsourceがHOLDでも、独立して確認できた他方の**既知不正をHOLDで覆わない**。ただし検証実行以前のHOLD/REJECTから未到達段階のPASSや`first_reject_stage`を作らない。

### 必ず停止する条件
1. 発行者提示の鍵、`kid`、`iss`、`jwk`や自己申告digestでHostの登録を済ませようとした場合。
2. `unique=true`・nonce長・局所`UNIQUE(tenant_id,nonce_sha256)`・in-memory HashでHost-wide一意性を証明済みと扱った場合。
3. 期限切れ履歴を削除してnonce再利用を許す場合、失効状態unknownをnon_revokedに置換する場合。
4. Challenge/Checkout/Buyer/Agent/元JWTを一つの確定したHost発行revisionで照合できない場合。
5. `Time.now`やtoken `iat`をHost監査時刻として昇格した場合。
6. G0–G6未実行のままG7 Evidenceを構築、EvidenceをHost ALLOW/CAS/paymentと取り違えた場合。
7. 本Issueやdocs PRを根拠にA3-T2コード・CI・署名fixture・DB作成を始めようとした場合。

## 8. 参照した研究境界（実装・実測の権限は継承しない）

- [A2終了時のHost/G1/G7不備の監査](PHASE2A_E06I_A2_EXIT_A3_TRUST_BOUNDARY_DECISION.md)
- [B1 Hostスナップショット・Evidence期限契約](PHASE2A_E06I_B1_IMMUTABLE_HOST_SNAPSHOT_CONTRACT.md)
- [E06 G0→G7検証順序](PHASE2A_E06_INTEGRATED_VERIFICATION_ORDER_CONTRACT.md)
- [固定Issuerの登録・発行Profile境界](PHASE2A_FIXED_ISSUER_TRUST_ACCEPTANCE_CONTRACT.md)
- [E01-S 独立Host trust adapterの検証契約](PHASE2A_E01S_MINIMAL_HOST_TRUST_ADAPTER_CONTRACT.md)
- [P1-8 Host replay / atomic nonceの**別の実験設計**](HOST_REPLAY_LAB_DESIGN.md)
- [Host security test plan（本書のTP01–12とは別）](HOST_SECURITY_TEST_PLAN.md)
- [A3-H1の未実行研究コード](../research/phase2a_e06i/isolated_host_source.rb) / [nonce発行記録の主張照合](../research/phase2a_e06i/isolated_nonce_issuance_source.rb) / [Host snapshot](../research/phase2a_e06i/isolated_host_snapshot.rb)
- [A3-T1の未実行clock path](../research/phase2a_e06i/isolated_root_closure.rb) / [HOLD-only context](../research/phase2a_e06i/isolated_stage_context.rb)

**この設計の完成＝証明責務を明確にしただけ。** 実Hostの真正性、全域nonce非再利用、G1/G7成功、承認B・Phase 2-B移行を意味しない。
