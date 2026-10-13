# Phase 2-A / E06-I — A3-T2c 承認A: PostgreSQL 16実験資材の最小ファイル範囲（設計のみ）

**2026-10-13 JST · [Issue #97](https://github.com/cuichangquan/ap2-mandate-verifier/issues/97) · DESIGN ONLY / NOT APPROVED / NOT RUN / NO SQL, DB, CODE OR CI EXECUTION / G1-G7 HOLD / PHASE 2-B HOLD**

## 1. この設計で決めること

A3-T2cの将来の**承認A（研究資材の新規作成・静的レビューのみ）**に向け、新規ファイル候補、相互の責務、独立オラクル、対象シナリオ、停止・承認Bを先に明文化する。**今回実際に作成するのはこの1 docs ファイルのみ**。下記SQLやRubyは**一切作らない**。Ownerの一般的な「OK」やこのdocs PRのマージは実装・DB・実行の承認ではない。

前提：[A3-T2a設計](PHASE2A_E06I_A3_T2A_MINIMAL_HOST_TRUST_PG_NONCE_ARCHITECTURE.md)、[A3-T2b承認境界](PHASE2A_E06I_A3_T2B_SCOPED_IMPLEMENTATION_APPROVAL_PLAN.md)、[研究Ruby PR #96](https://github.com/cuichangquan/ap2-mandate-verifier/pull/96)、親[#47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47)、統合実行承認[#73](https://github.com/cuichangquan/ap2-mandate-verifier/issues/73)。固定公式AP2 v0.2.0 SHA `b4587ac1d055888a73b4b21750973cffba961793`、合成Issuer A、固定profile。実Host、G1/G7、商用注文・決済・Receipt、公開Gemは対象外。

## 2. 将来の承認Aでのみ作成を検討する新規ファイル（今回作成しない）

**上限は次の4新規ファイルのみ。** いずれも `research/phase2a_e06i/` 配下。既存の統合コード/ワークフロー/READMEは変更しない。

| 提案パス | 最大責務（将来の実装候補） | 禁止・未証明 |
| --- | --- | --- |
| `a3_t2c_nonce_ledger_schema.sql` | PostgreSQL 16**単一primary**の隔離研究スキーマ。Host-verifier domain全員・全tenant/sessionに共通の発行履歴、**全域 `UNIQUE(nonce_sha256)`**、全発行履歴の削除禁止、Challenge/Checkout versionと元Merchant署名JWT**原文バイトdigest**の同一transaction結合、必要な制約・索引/ACLの提案 | `UNIQUE(tenant_id, nonce_sha256)`・部分unique・期限付きpurge・複数primary全域保証・Host本番DB・実適用 |
| `a3_t2c_nonce_issuance_worker.rb` | **将来だけ**Host側のCSPRNG（OS乱数、最低128bitの推測困難性）発行候補→SQL transaction発行記録/Challenge結合→**commit確認後のみ外部配布可**というオフライン研究経路。衝突・unknown ACK・DB断絶時はHOLD/STOP | 固定文字列やSHAからnonce生成、commit前配布、衝突時既発行nonceを返す、G1 PASS、nonce消費CAS、本番配送/ネットワーク |
| `a3_t2c_nonce_ledger_oracle.rb` | workerの自己申告から独立した**別DB接続・読取権限**で、実catalog/indexと非部分 `UNIQUE(nonce_sha256)`、commit後履歴・Challenge紐付け・件数、同じnonceの再発行拒否、未確定結果は未知と判定するオフライン観測 | workerの `unique=true`/stdout/fixture自己報告を唯一の正本とみなす。PG実測なしでPASS |
| `a3_t2c_nonce_scenarios.rb` | **将来の実測Bにのみ**使う合成PG01–PG05ケースの構成・2独立workerの並行開始・最大実行数/timeout/cleanup要求を静的に定義する研究シナリオ。観測結果はoracleと対照 | A段階で実行/DB起動、承認B以前のCI自動起動、任意環境へ接続、PG06 restore/障害注入の自動実行 |

すべて**新規のみ**。対象コード作成時に既存ファイル編集、Dockerfile/Compose、`.github/workflows/**`、Gemfile/依存追加、`research/shared/**`変更などが必要なら**事前STOP・別承認**。既存 `a3_t2b_*_boundary.rb`・`isolated_*`・`integrated_probe.rb` への統合配線はこの段階の対象外。

**境界：** SQLとworkerのコードがレビューを通っても、実DBへの制約適用・CSPRNGやworkerの実動作・過去発行の保持・運用時のHost真正性は証明されない。4ファイル自体を承認Aなしに追加しない。

## 3. 各レコードと誤った「証明」を避ける設計上の条件

- **Nonce issuance history**：`issuance_ref`、`nonce_sha256`（**全域唯一、not null、保持期限で消さない**）、発行元domain、`challenge_ref`、`aud`、発行時Agent公開鍵thumbprint、opaque Buyer/Account、`tenant_id/checkout_id/checkout_version`、元Merchant署名Checkout JWTの**受領時全バイトSHA256と独立した出所ID**、`issued_at/expires_at`、commit同一性を束縛。元nonce/JWT・PIIは証拠へ出さない。
- **DB authority**：2 workerは**同一primary・同一制約・全tenantの共通履歴**を利用することを別証拠で確認。専用ロールの最小権限、書込と監査読取の分離、他テナントが権威正本を自称/書換えできない条件をA静的レビューで審査。DB rootの存在だけでは独立Host登録権限は証明できない。
- **Challengeの配布**：発行eventとChallengeは原子的commitで固定。DB unique衝突側は公開0件。commit outcome不明で「未発行」扱いや同nonce再配布は禁止。後から新Checkoutに付替えない。
- **全域とは**：固定Terminalの署名対象は `aud/nonce`、tenant/session/challengeは含まない。tenant/checkout/時間ごとのpartial uniqueは不可。**単一primary**内の全域に限定し、複数primary/shard、バックアップ巻戻り時のグローバルな保証は別証拠がない限り**HOLD**。
- **独立の実測証拠**：DB catalogでのconstraint/index定義、隔離トランザクションのcommit outcome、別connectionのrowcount、Challenge-issuance一体性、重複時の未配布。worker return codeやログだけで成功としない。
- **NI01 CSPRNG**：少なくとも128-bitの暗号学的予測困難性を満たすOS乱数sourceと停止経路を確認する。統計的「見た目」/nonce長/`entropy_bits`自称で実証済みと書かない。静的レビューはCSPRNGの本番保証ではない。
- **Fail Closed**：独立に確定できる衝突・改変・既知の不正はREJECT。ただし独立の真正なHost trust/clock/issuer rootのないA3-T2cでも、G1/G7成功や`VerifiedEvidence`を返さずHOLDを維持する。

## 4. 独立シナリオと承認Bの範囲（全部 NOT RUN）

| ID | 将来の実験 | 必須の観測/判定 |
| --- | --- | --- |
| PG01 | 1件発行 | commit後だけ発行、Challenge-Checkout-原JWTバイトdigestの同一transaction、正本別接続で1件 |
| PG02 | **同一nonce**を別tenantから2独立DB workerで同時発行 | commit成功最大1、片方のuniqueness衝突。衝突側のChallenge配布なし、DBの実索引を照合 |
| PG03 | 有効期限後・消費相当・別Checkoutで同nonce再発行 | 過去履歴の物理保持と全域constraintによる再発行拒否。purgeや行削除で回避禁止 |
| PG04 | rollback、接続断／commit ACK不明を模した安全な合成ケース | commit確定できない限り**HOLD**。無承認の実DB強制クラッシュ、kill/restore/fault injectionは禁止 |
| PG05 | Challenge、Agent thumbprint、Buyer/Checkout version、原Merchant JWT bytes digest差替え | DB側確定発行eventとの突合で既知不一致のみREJECT、出所不明ならHOLD |
| PG06 | Backup restore/primary切替で履歴巻戻り | **今回の承認A候補とB候補から除外**。別環境・予算・Owner許可が揃うまで NOT RUN/HOLD |

研究環境に実際に発行する合成イベントは**合計100件以下**、**2 worker以内**をB候補にする。Bの選択は1回手動、**1 job 10分以内**、artifact合計**1MiB以下・7日保持**。タイムアウト/上限違反/追加の実行が必要ならSTOPして再承認。**これらは提案であって今回承認された制限値ではない**。実施形式（ローカル隔離環境か承認されたCI）・全timeout・failure cleanup・独立オラクル結果の採否は承認B前に明文化する。

## 5. 環境、費用、後片付け：承認前に決めること

- **第一候補**：私有の隔離された一時PostgreSQL 16単一primary。外部公開しない。実Host/実Buyer/商用決済/認証秘密は一切使用しない。将来の権限Bがなければ**PGを起動せず、DBも作らず、接続もせず、SQLも適用しない**。
- 新規GCP/Cloud SQL/VM/ネットワークの課金リソースは**使わない（追加クラウド費用0円の案）**。GitHub Actions無料とは仮定しない。ランナーの残枠・請求条件・必要な金額上限をOwnerが明示確認するまでCIを実行しない。
- **隔離**：研究用ロールと認証情報を環境外に漏らさず、テストで生成したnonceの原文やJWT、秘密鍵、実PIIをGit commit/CI artifact/ログに含めない。
- **cleanup**：実測承認時にDB・ロール・コンテナ・サービス・networkを誰が消すか、異常終了時も残存をどう検出するか、削除検証と請求検査を事前定義。cleanupが保証できない場合は**実行しない**。
- A3-T2bの既存source-only APIと実PGを今回連結しない。G1 trust bootstrap、root/ACL真正性、Host checkout現在性・verified_at、G7、final CAS/Checkout state・Provider冪等性は**別承認**。

## 6. 承認A/Bの厳格な入口条件

| ゲート | 将来必要な明示承認 | 今回の状態 |
| --- | --- | --- |
| **本設計PR** | **このdocs 1ファイル**＋Codex静的レビュー（P1/P2修正も同文書のみ） | 設計のみ、A/Bを承認しない |
| **[#97] 承認A** | Ownerが**Issue #97と上記新規4パスを明記**して「SQL/Ruby研究資材の作成・静的レビューのみ」を承認。着手前に実際の`.github/workflows/**`のPR/push path filtersと新規パス衝突を点検 | **NOT APPROVED** |
| **[#97] 承認B** | 承認A実装の最新HEAD Codexレビュー合格後、Ownerが**Issue #97 B**、環境/実行方法・課金条件/上限・1 run/10分/100合成件・独立oracle・cleanupを指定して実測を明示承認 | **NOT APPROVED / NOT RUN** |
| **PG06復元実測** | 単独で更に別Owner承認/破壊的試験環境と予算上限 | **HOLD** |
| **統合実測 [#73] B / Phase 2-B** | 別Issueの独立承認と安全証拠/Owner GO | **HOLD** |

将来承認Aを依頼する文面の例：

> **「Issue #97のA3-T2c承認Aとして、上記4つの新規 `research/phase2a_e06i/` 資材ファイルの作成と最新HEADの静的レビューのみを承認します。SQL適用、Ruby/Python実行、テスト/CI、PostgreSQL・コンテナ起動、復旧試験、承認B、G1/G7成功、Phase 2-Bは承認しません。」**

**STOP条件：** 変更対象の拡大／自動CI発火の可能性／path filter未確認／実PGまたは依存導入が必要／commit不明の楽観的再発行／ログへの秘密漏えい／費用またはcleanup未承認。いずれも先にOwnerへ再承認を要求し、暗黙のscope拡大をしない。

## 7. 今回の出口

1. この**1 docs ファイルのみ**を新規PRにし、最新HEAD CodexレビューのP1/P2全解消、未解決thread 0、差分1文書を確認して**docsだけ**マージ可能。
2. この文書の静的レビューやマージはPG一意性・CSPRNG・耐久性・本番Host identityの実証でない。
3. Issue #97は**承認待ちのOPEN/HOLD**として維持。SQL/Ruby worker/oracle/scenarios、DB作成、B実測、[#73] B、G1/G7、Phase 2-Bは全て未承認。
