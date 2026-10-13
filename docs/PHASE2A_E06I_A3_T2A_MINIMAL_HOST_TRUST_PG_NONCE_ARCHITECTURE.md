# Phase 2-A / E06-I — A3-T2a 最小Host信頼正本とPostgreSQL nonce発行台帳（設計のみ）

**2026-10-13 JST · Issue [#91](https://github.com/cuichangquan/ap2-mandate-verifier/issues/91) · DESIGN ONLY / NOT RUN / NO IMPLEMENTATION OR EXECUTION APPROVAL / G1-G7 HOLD / PHASE 2-B HOLD**

## 0. 目的・固定境界・承認

本書は [PR #90の証明条件](PHASE2A_E06I_A3_T2_HOST_NONCE_PROOF_PREREQUISITES.md) のうち、独立したHost登録正本（HT01–HT06）とHost全域の永続nonce発行台帳（NI01–NI05）を、**後で独立に反証できる最小研究アーキテクチャ**として設計する。**正本・DB・スキーマ・API・署名・検証実装・テストを作成したものではない。**

対象は公式AP2 v0.2.0 pinned commit [b4587ac1d055888a73b4b21750973cffba961793](https://github.com/google-agentic-commerce/AP2/tree/b4587ac1d055888a73b4b21750973cffba961793)、合成Issuer A、固定profile 1種、2hop、signed Open Root 1件、既存の許可済みSD array slot 3箇所、Checkout / Merchant / SKU 各1件に限る。一般的なAP2適合、本番Host、実Issuer登録、外部Authorityの失効を保証しない。

- 親 [#47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47)、実行承認 [#73](https://github.com/cuichangquan/ap2-mandate-verifier/issues/73)、A3-H1 [#83](https://github.com/cuichangquan/ap2-mandate-verifier/issues/83)、A3-T1 [#87](https://github.com/cuichangquan/ap2-mandate-verifier/issues/87) / [PR #88](https://github.com/cuichangquan/ap2-mandate-verifier/pull/88) と [#89 / PR #90](https://github.com/cuichangquan/ap2-mandate-verifier/pull/90) の未証明境界を継承する。
- 今回の許可は**本設計文書1ファイルと静的レビューまで**。A3-T2b実装、A3-T2c実測、承認B、DBの実作成、Ruby/Python/fixture/CI/GCP/ネットワーク/実決済/Receipt/Gemは**未承認**。
- これまでの A3-H1 の独立っぽく見える source JSON / SHA 照合や A3-T1 の caller 時刻を **Host真正性・nonce履歴・G1/G7 PASS とみなさない**。

## 1. 誰が何を信頼するか

**Host** はCheckoutとChallengeの正本を保有し、検証に用いるIssuer・Agent・Merchantの鍵とポリシーを独立に登録・管理し、購入の最終認可を判断する主体。Buyer本人でも、Issuerでも、必ずMerchantでもない。Merchant運営者がHost責務を持つ構成はあり得るが、**責務が同一組織かどうかは実運用では別途確定**する。

| 主体 | 役割 | 信頼してはいけない入力 |
| --- | --- | --- |
| Host管理者（承認権限者） | Mandate/tokenとは**別経路**で登録・変更・失効・監査の管理を行う | Issuerが提示した公開鍵だけを根拠に自動登録 |
| Host信頼正本（提案） | 管理者が承認したIssuer/Agent/Merchantの鍵、policy、版・監査履歴を保持する | JSON内の source_ref / SHA / active 自称を認証と扱う |
| Host Challenge発行主体（提案） | 発行するaud/nonceとBuyer/Agent/Checkoutを確定し永続記録する | Agentの「既発行・一意」自己申告 |
| Ruby Verifier（将来候補） | 信頼済み読出し境界から検証時スナップショットを受け、G0→G7の証拠のみを評価する | JWTのkid/iss/jwk/jku/x5uを信頼ルートにする |
| Host最終認可（別責務） | 現在状態再照合、nonce消費CAS、Checkout/operationを一括更新 | Verifier Evidenceだけで購入・支払をALLOW |

### 最小の信頼ブートストラップ案（認証済みではない）

1. 合成ラボのHost管理者とその**別経路の承認手順**を事前に固定。管理者がIssuer Aの実体・固定profile/version・ES256公開鍵thumbprint、Agent/Merchantの各鍵・policy・scopeを独立に確認した根拠を承認台帳に残す。単に任意の固定キーをプログラムに書いたことは、実社会のIssuer真正性を証明しない。
2. Host管理権限とVerifierの**読取専用資格**を分離。Host正本への書込み、承認、失効観測と監査ログは別権限。caller、Issuer、Agent、提示JWT、自由なローカルファイルパスに正本の選択・上書き権限を与えない。
3. Verifierに渡すのはHost側が認証済み接続で取得したrevision固定スナップショットであり、攻撃者が渡したsnapshot JSONではない。Hostの接続・ACL・承認経路・監査ログの独立した証拠がない限り**HOLD**。
4. 将来の合成ラボでは管理主体を人工的に固定することは可能だが、それは**ラボ内の仮定を検証**するだけ。実際のHostの鍵配布経路、operator権限、管理者本人性、監査改ざん耐性、外部Authority失効の証明にはならない。

## 2. 最小データモデル（概念図・DDL/マイグレーションではない）

研究候補は**単一の隔離されたHost管理PostgreSQL 16 primary**。Host trust registryとnonce issuance historyを**同じ保護された正本境界内**で扱うと、同一checkout/challenge/issuanceの読出し整合性を追跡しやすい。ただし**同じDBであること自体は独立Host出所の証拠ではない**。権限分離・承認経路・監査根拠が必要。

| 論理レコード | 必須の概念フィールド / 不変条件 | 独立証拠の責任 |
| --- | --- | --- |
| Host trust revisions | host_verifier_domain、revision、承認者・承認時刻、承認経路、監査event ID、参照policy version | Host管理者、ACL/監査（HT03–HT04） |
| Signer enrollment versions | Issuer/Agent/Merchantを**個別**識別するsubject、tenant/use scope、profile_ref/version、key thumbprint/公開鍵参照/alg、key・policyの別々のactive、revocation、not_before/not_after、revision履歴 | 独立登録・失効/rotationの証拠（HT01–HT02、HT06） |
| Checkout versions | (tenant_id, checkout_id, checkout_version)、buyer_account_ref、merchant、現在status、元Merchant署名Checkout JWTの**元バイトSHA256と取得元**、金額/通貨/商品・constraint照合元 | Host正本・Checkout発行過程（HT05） |
| Challenge versions | challenge_ref、checkout三つ組、buyer_account_ref、aud、発行時Agent thumbprint、issuance_ref、issued_at/expires_at、状態・revision | Host発行経路・後からの差替え防止（HT05 / NI04） |
| Nonce issuance history | issuance_ref、**nonce_sha256 の単独・Host-verifier全域UNIQUE**、challenge_ref、aud、Agent thumbprint、Buyer/Checkout三つ組、**元Checkout JWT digest**、issued_at/expires_at、commit ID、元発行eventの削除禁止 | Host発行commit・DB実制約（NI01–NI05） |
| Host final operation（**別ゲート**） | checkout一回性のoperation ID/一意制約、challengeのISSUED→CONSUMED CAS、durable outbox、Provider用安定idempotency key | Host final認可・Provider（NC01–NC02） |

**重要な設計優先関係:**

- 現行固定TerminalのAgent署名は **aud と nonce を保護**するが、tenant/session/challenge_ref自体は署名で結合しない。そのため **UNIQUE(tenant_id, nonce_sha256)** や **UNIQUE(challenge_ref, nonce_sha256)** だけでは、同じ署名付きTerminalの別tenant/sessionへの再ラベルを防げない。
- 最小案では、**同じHost-verifierの署名検証領域で一度でも発行した全nonceに対して、テーブル全体で UNIQUE(nonce_sha256)** を強制する。tenant、session、発行日、失効、消費、期限、Checkout versionでは分割しない。複数worker/全tenantが**同じ権威あるprimaryと同じ一意制約**を共有する。別primary・複数DB・シャード間の全域性はこの単一DB案では**未証明/HOLD**。
- 一意性と予測困難性は別。nonceは**信頼済みHost発行経路のCSPRNGから最低128 bitの推測困難性**を得る必要がある。16-byte、entropy_bits=128の欄、nonce_sha256、サンプル分布だけではその証明にならない。
- SHA256 digestはraw nonceの記録・公開を避けるための**研究候補**であり、nonce原文の認証・CSPRNGの品質やDB履歴の真正性は証明しない。digest衝突等で一意性を安全に確定できない場合は再発行せずSTOP/HOLD。raw nonce、PII、JWT原文・秘密鍵は公開証拠に出さない。
- 発行済み・消費済み・期限切れ・再発行前の履歴を**削除して再利用可能にしない**。履歴のappend-only監査とUNIQUE保持の両方が必要。TTL清掃、バックアップ復元、巻戻り、クラッシュ復旧でこの性質が失われる場合はHOLD。無期限保持コスト/バックアップ方針は**未解決の運用判断**。
- [P1-8 DB設計](HOST_REPLAY_LAB_DESIGN.md)にあるtenant付きnonce一意制約は、当時の**Host replay/CAS研究用の別のモデル**であり、今回のA3固定Terminal受入れ領域のHost-wide issuance証明に十分ではない。既存文書や実験を修正・成功扱いせず、本設計では**より広いスコープ**を必須とする。

## 3. 将来の発行・読出し・検証の境界（すべて未実装）

**Verifierにwireが届いた後の実行順序は必ず G0 → G1 → G2 → G3 → G4 → G5 → G6 → G7。** G0で元wireのサイズ・strict JSON/JOSE・上限を検査してPASSした後にのみ、G1のHost trust/nonce正本参照へ進む。G0失敗時に正本照会やG1の到達成功を記録しない。以下の登録・Checkout確定・Challenge発行は**検証前のHost内部準備**であり、G0より先にVerifierがG1を実行する意味ではない。

1. **管理者による登録（別経路）:** 鍵thumbprint、署名アルゴリズム、使用tenantと用途、profile、別々のkey/policy失効状態、有限な期限を承認・版管理する。古いrevoked版へrollbackして受理しない。独立根拠がなければHOLD。
2. **Checkout確定:** Hostが元のMerchant署名JWT**全バイト列**とCheckout三つ組、Buyer/Agent、revisionの結合を記録。JWT内部idからversionを推定しない。元バイトdigestの一致は**Hostが記録した元データの由来が認証されて初めて有用**。
3. **Challenge発行:** Host管理のCSPRNGで生成→全域UNIQUE制約付き発行event/Challenge/Checkout関連を**同一原子的commit**として固定→commit確定後にChallengeを配布する、を候補とする。UNIQUE衝突時はその候補を発行せず新規乱数を検討。commit ACK不明では**未発行と推定せず**、回復確定まで停止する。発行済みnonceを後から別Checkoutへ再紐付けしない。
4. **G1読出し:** Hostが認証済み読取接続を使い、Issuer/Agent/Merchantのkey+policy、revocation、Challenge、issuance、Checkout、元JWT digestを**単一の整合したsnapshot revision**で解決する。単一DBのsnapshot read/適切なisolation方式は実装前に審査。古いreplicaや別時刻の個別読出しの寄せ集めは不可。
5. **時刻:** Hostが事前に承認したclockの取得元、UTC epoch、skew/鮮度/timeout上限を証明し、1つの **verified_at** を全検証段階に渡す。tokenのiat、callerが選んだ時刻、各段階のTime.nowへのfallbackを信頼時刻にしない。
6. **G2→G6:** G1のHost承認済みIssuer鍵で元Root署名、原Rootの全開示、Root Agent key/Challenge発行時thumbprint/Terminal署名aud+nonce+sd_hash、元Merchant Checkout署名、固定公式Schema→全制約とHost Checkout比較の順を守る。既存A3-H1/T1の未実行research observerはこの真正な統合パスではない。
7. **G7:** 各ステージの実到達、正本出所、元wireのidentity、revision、有限の全期限を一つのEvidence-only結果に束縛する。Closed expやMerchant key/policy期限の欠落を他の期限で補わない。**Host認可・nonce消費・Payment成功は返さない**。
8. **Host final（Verifier外）:** 最新のtrust/失効、Buyer/Checkout現在状態を再照合し、同一transactionで**Challenge未消費→CONSUMEDの条件付きCAS / Checkout更新 / operation一意登録 / outbox予約**を確定させる別Gateとする。発行時UNIQUEが満たされても再利用防止のCASの実証にはならない。Providerのidempotencyも別証拠。

**同一snapshotと現在性は別:** G1が得た整合した過去スナップショットをG7 Evidenceに束縛できても、その後のrevocationやCheckout変更を凍結するものではない。Host最終認可時に**最新状態をもう一度確認**する。外部revocationの現在性を同じDB transactionだけで保証できない場合はHost final HOLD/STOP。

### 将来の候補読出し契約（APIではない）

| 入力元 | 最小識別子 / 出所 | 出力・失敗 |
| --- | --- | --- |
| Host内部の認証済みCheckout/challenge context | 認証されたHost領域、checkout三つ組、challenge_ref（token由来の推定不可） | 対応するtrusted revisionを一意に解決。不明/複数候補HOLD |
| Host独立read-only trust source | revision、事前許可key/policy、失効観測時刻・取得元 | active/non-revokedと期限を**別々に**照合。既知revoked REJECT、unknown/stale HOLD |
| Host独立nonce issuance source | 唯一のHost-wide nonce history、commit確定済みissuance_ref、凍結した発行イベント | challenge/Buyer/Agent/aud/Checkout/JWT digestの一致確認。既知不一致REJECT、commit/履歴不明HOLD |
| Host trusted clock | clock policy、verified_at、skew/TTLの境界証拠 | 各stageで同じ時刻。時計出所不明HOLD |

返却型・Rubyコード・DBドライバ・接続情報・実スキーマ・隔離権限の詳細は**A3-T2bの別審査まで未決定**。将来これらのテーブルをユーザー提示JSONで代用してG1成功を返す実装は許さない。

## 4. 独立の証拠と判定

| Gate | 独立に確認すべき証拠 | 失敗と現在地 |
| --- | --- | --- |
| HT01–HT03 / E-Host | Mandateと別経路の登録承認者・Host trust root、登録・ACL・書込/読取権限、Issuer/Agent/Merchant鍵とprofile、key/policy別の失効履歴 | known未登録・revoked・不一致=REJECT、出所不明=HOLD。**現在HOLD** |
| HT04–HT06 / E-Checkout + E-Clock | 同一revisionのTrust/Checkout/Challenge、元Merchant JWT SHAの**由来**、単一verified_at、有限鮮度、rotation後の再照合 | known改変・期限外=REJECT、snapshot/clock出所不明=HOLD。**現在HOLD** |
| NI01 / E-Issuance | review可能なHost CSPRNGコードパス・OS乱数失敗時のSTOP・発行監査 | known非CSPRNG=REJECT、出所/品質不明=HOLD。**現在HOLD** |
| NI02 / E-Issuance | 現実の全域UNIQUE制約・migration digest・全worker共有正本、同nonce同時発行のcommitが最大1という独立観測 | knownscope不足/重複=REJECT、DB未実装/障害=HOLD。**現在HOLD** |
| NI03–NI05 / E-Issuance | 全発行履歴/tombstone、restore/rollbackの検知・耐久性、Checkout/Buyer/Agentと同一commitの結合 | known再利用/紐付け違反=REJECT、履歴やcommit不明=HOLD。**現在HOLD** |
| NC01–NC02 / E-HostFinal | CAS rowcount、Checkout/operation/outbox同一transaction、Provider独自idempotencyの証拠 | これはVerifier/G1-G7ではなく**別のHost final Gate**。**現在未実証** |
| G0→G7 / E-Crypto | 公式原文pin、元ワイヤ・署名・完全開示・Schema・制約・全stageと短いvalid_untilの別オラクル | 独立Host証拠なしならG1/G7成功不可。**現在HOLD/NOT RUN** |

**判定の優先順位:** 独立に確定した偽造/失効/不一致/nonce再利用は **REJECT**。正本なし/権限不明/古いrevocation/時計不明/DBタイムアウト/未知commit/復旧による巻戻り疑いは **HOLD/STOP**。一方の未知が他方の既知不正を覆わない。ただし未到達stageのPASS・first_reject_stageを生成しない。

## 5. 後日、別承認で反証する最小シナリオ（すべて NOT RUN）

| 観測候補 | 独立オラクル | 期待する否定能力 |
| --- | --- | --- |
| Trust root偽装 | Host管理者側の独立登録正本とcallerの自己申告を突合 | 同じSHA/鍵文字列であっても独立出所なし→HOLD |
| 未登録Issuer・既知revoked key/policy | Host承認履歴・revocation正本 | 暗号署名VALIDでもG1 REJECT |
| 2workerが別tenant/sessionで同一nonce発行 | 2独立DB接続と**実**unique constraint/確定commit、発行履歴 | 1 commit以下、衝突側の配布0 |
| 期限切れ/消費済みnonceを別Challengeで再発行 | 全履歴とdigest global unique index | known再利用REJECT。TTL purgeでは一意性リセットしない |
| DB停止/commit ACK不明/復旧で履歴欠落 | primaryのcommit状態と外部監査、復元された全履歴 | unknownを未発行扱いしない。HOLD/STOP |
| Challenge/Buyer/Checkout version/Agent thumbprint/元JWT bytes貼替 | Host発行commitの各結合情報と元wire | known不一致REJECT、元レコード出所不明HOLD |
| VerifiedEvidence後の失効/Checkout変更 | 現在のHost正本と最終CASの別証拠 | G7 Evidenceを最終ALLOWにしない |
| 同nonce・別nonceで同Checkout finalが競合 | Host最終transactionとProviderの別記録 | NC01/NC02として独立扱い。発行一意性試験だけで証明しない |

これらは既存 [PR #90のTP01–TP12](PHASE2A_E06I_A3_T2_HOST_NONCE_PROOF_PREREQUISITES.md) の**具体化案**であり、追加テスト実行を許可しない。[Issue #73](https://github.com/cuichangquan/ap2-mandate-verifier/issues/73) の13ケース/手動CI1回枠に自動追加しない。DB競合・障害注入・バックアップ復元は別の明示承認と安全・費用・cleanup計画が必要。

## 6. 未決のOwner判断と次の承認ゲート

1. Host trust rootの独立承認者・登録/rotation/revocation経路、認証済みread-only読出し主体を何に固定するか。合成ラボの固定operatorは本番登録証明ではない。
2. 同一Host-verifier domainと全worker/全tenantの正本共有範囲、複数primary/shard/復元時に全発行履歴をどう防衛するか。**単一PG16の設計は分散全域保証ではない**。
3. 永続nonce発行eventとChallenge/Checkout書込みをどのtransaction boundaryで整合させるか。障害時のcommit確定確認と、無期限保持による容量/個人情報・運用要件。
4. Trusted clock・revocation鮮度・外部Authority失効と最終Checkout current stateの契約。有限でないdeadline、未知clock、古い失効記録はHOLD。
5. A3-T2bでどの**新しい**限定ファイルのみを実装するか、静的レビュー後のA3-T2c PostgreSQL/競合試験の権限・件数/予算/停止条件。許可のないコードやテストは始めない。

| 次の段階 | 状態 | 前進条件 |
| --- | --- | --- |
| **A3-T2a — 本文書** | DESIGN PROPOSAL / NOT RUN | docs-only PR、最新HEAD静的レビュー、P1/P2全解決・未解決thread 0を確認後に文書のみマージ可能 |
| A3-T2b — 限定研究コード | **NOT APPROVED / HOLD** | 別Issue・Ownerの明示的な対象ファイル別承認。独立Host正本の作成を自動許可しない |
| A3-T2c — DBの実作成/競合実測 | **NOT APPROVED / NOT RUN** | 別Issue・別Owner実行承認、独立オラクル/隔離DB/rollback/費用/cleanupを固定 |
| E06-I承認B / G1→G7統合 | **HOLD** | [#73](https://github.com/cuichangquan/ap2-mandate-verifier/issues/73) の明示承認と全stage実到達・独立証拠 |
| Phase 2-A Exit / Phase 2-B / Gem / 本番決済 | **HOLD / NO-GO** | 正本真正性・Host final・未知境界の別審査とOwnerのGO判断 |

### STOP

- Self-consistentなHost JSON、source_refやdigest、JWTから選んだJWKをHost trust rootに昇格する。
- CSPRNG・唯一性をnonce長、uniqueフラグ、tenant別indexやin-memory Hashで代用する。
- PG primaryの共通性が未証明なのにhost-wide一意発行済みと表現する。古い履歴を削除・restoreで忘却する。
- Clock/Checkout/Challengeの同一revisionと元Merchant JWTの由来を証明できないのにG1/G7成功を生成する。
- 発行のunique成功を、消費CAS・Checkout一度限り・Provider副作用最大1の成功へ読み替える。
- 本書/PR/Issueや一般的な「OK」をコード・SQL適用・DB起動・テスト/CI実行承認と解釈する。

**結論:** A3-T2aは独立出所・Host-wide nonce発行の**研究用設計責務**を整理するだけ。真正なHostの登録、永続nonce台帳、一意性/耐久性実測、Host最終認可、G1/G7 PASSは今も**未実証**である。
