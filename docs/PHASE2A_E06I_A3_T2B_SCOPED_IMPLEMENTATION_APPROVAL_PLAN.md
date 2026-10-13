# Phase 2-A / E06-I — A3-T2b限定研究コード：実装候補・承認境界計画

**2026-10-13 JST · [Issue #93](https://github.com/cuichangquan/ap2-mandate-verifier/issues/93) · DOCS-ONLY PLAN / NOT RUN / A3-T2b NOT APPROVED / APPROVAL B NOT APPROVED / G1/G7 HOLD / PHASE 2-B HOLD**

## 1. 目的と位置づけ

[PR #90：Host/nonce証明条件](PHASE2A_E06I_A3_T2_HOST_NONCE_PROOF_PREREQUISITES.md)、[PR #92：Host正本とPG16 nonce最小構成](PHASE2A_E06I_A3_T2A_MINIMAL_HOST_TRUST_PG_NONCE_ARCHITECTURE.md) の次に、将来のA3-T2b研究コードを**最少の安全な境界**に限定するため、対象ファイル、出入力、fail closed、安全停止・承認分割を先に合意できる形に記す。本書を作っても研究コード/DBは追加しない。

研究対象は公式AP2 v0.2.0固定SHA `b4587ac1d055888a73b4b21750973cffba961793`、合成Issuer A・固定Issuer profile・2hop・signed Open Root 1件・許可された深いSD array slot 3箇所・Checkout/Merchant/SKU各1件に限定。AP2一般適合、実Issuer/Host、実注文・決済、Payment Mandate、Receipt、公開Gemは対象外。

現在の [A3-H1 `isolated_host_source.rb`](../research/phase2a_e06i/isolated_host_source.rb)、[`isolated_nonce_issuance_source.rb`](../research/phase2a_e06i/isolated_nonce_issuance_source.rb) はcallerから渡ったJSONとSHAの**自己整合**のみを検査し、`status=HOLD`・`admissible?=false` を維持する。 [A3-T1 `isolated_stage_context.rb`](../research/phase2a_e06i/isolated_stage_context.rb) はcaller提供`verified_at`と原wireのダイジェストを保持するが、Host時計は認証していない。[`integrated_probe.rb`](../research/phase2a_e06i/integrated_probe.rb) のG0–G3観測経路を、本書だけで真正なG0→G7統合実装に格上げしない。

**重要：今回の「OK」は、この設計文書のみの了承。** A3-T2bのRubyコード作成・実行・DB作成・承認Bは、**別Issueと対象ファイルを指定したOwner明示承認があるまでHOLD**。

## 2. 最小の後続実装候補：新規Ruby 2ファイルのみ（今回作成しない）

| 候補パス（提案） | 責務の最大範囲 | 必ずしないこと |
| --- | --- | --- |
| `research/phase2a_e06i/a3_t2b_host_registry_boundary.rb` | Host管理者が**Mandateと別経路**で承認した鍵・policy・revocation・revision・読取権限の**独立した出所が確定しているか**を検査する、Verifier内部の読取契約。Issuer/Agent/Merchantを別レコードとして扱う | JWT `kid/iss/jwk/jku/x5u`、caller JSON/`source_ref`/自称digestを信頼根として採用、動的JWKS取得、登録/鍵rotate/失効書込、G1 PASS |
| `research/phase2a_e06i/a3_t2b_nonce_issuance_boundary.rb` | 全Host-verifier nonce発行域を網羅する**独立した確定発行イベント**の読取契約：`issuance_ref`、commit根拠、発行時Challenge/Agent/Buyer/Checkout/JWTバイトSHAの結合、全域一意/履歴の根拠を区別する | PostgreSQL接続・schema/DDL・nonce生成/発行/消費・CAS、`unique=true`/`entropy_bits=128`/一致SHAだけで全域履歴やCSPRNGを証明、G7 Evidence作成 |

**なぜ2ファイルでHOLD-onlyなのか：** 真正なHost登録元も永続nonce台帳も現存するとの証明がなく、2ファイルを作るだけで真正なG1成功を返せない。まず**信頼できないデータを信頼へ格上げしない境界**を分離する。単なるクラス名「trusted」、`freeze`、`Digest::SHA256`一致では権威の証明にならない。

- **変更予定のないファイル：** `research/phase2a_e06i/integrated_probe.rb`、`isolated_host_source.rb`、`isolated_nonce_issuance_source.rb`、`isolated_host_snapshot.rb`、`isolated_stage_context.rb`、`isolated_root_closure.rb`、`schema_gate.rb`、`test_schema_gate.rb`、`research/shared/**`、`research/p1_*/**`、`research/phase2a_dc*/**`、`.github/workflows/**`。将来の実装で旧ファイル変更が必要になれば**変更前にSTOPして再承認**。
- この2ファイルで**実際にPGや承認管理システムを接続したり、verified G1Context、G7 Evidenceを出したりしない**。HOLD-onlyのsource/API境界をどう実装・静的レビューするかが次回の承認候補。実装した事実は動作実測を意味しない。
- 新規テスト、fixture、migrations、Ruby実行、ネットワーク/GCPアクセスをこの候補に含めない。現状の`README.md`などの文書更新も、この2ファイル承認に自動追加しない。

## 3. 境界データの契約（Ruby APIではなく将来レビュー用）

| 将来の境界 | 信頼元で固定すべき内容 | 不明・失敗時 |
| --- | --- | --- |
| Host trust selector | Host管理側が固定したroot/承認者/tenant/scope、Issuer Aの`profile_ref/version`・ES256公開鍵thumbprint、Agent/Merchant別鍵とpolicyの承認履歴、書込権限/読取専用資格 | Host root/ACL/署名・監査根拠/主体の確認ができなければ**HOLD**。既知未登録/不一致なら**REJECT** |
| Host trust state | 各key/policy個別`active`かつ`non_revoked`、各`not_before/not_after`、rotation/revocationの観測元と有限鮮度、revision | trusted known revoked/期限外→**REJECT**、unknown/stale/rollback疑い→**HOLD** |
| Challenge and Checkout | Host-issued `challenge_ref`、`aud`、発行時Agent thumbprint、opaque Buyer/Account、`(tenant_id,checkout_id,checkout_version)`、**元Merchant署名Checkout JWTバイトSHAと独立取得元** | known別Checkout等への貼替→**REJECT**、JWT digestの元正本やversion不明→**HOLD** |
| Nonce issuance | CSPRNG≥128-bit**生成経路の根拠**、全Host-verifier domainにわたる`UNIQUE(nonce_sha256)`の**実DB制約・commit**、expiry/consumed/reissueをまたぐ不削除履歴、同一commit紐付け | known重複/危険scope→**REJECT**、自己申告/台帳不在/commit不明→**HOLD** |
| Snapshot/clock | 認証されたHostからの**単一整合revision**・deep detached snapshotと**一つの信頼済み`verified_at`**、有限skew/freshness/TTL、監査時刻起源 | callerが選んだclock、`Time.now`/token `iat`、stale read、混在revision→**HOLD** |

- Readerに入力する`challenge_ref`やcheckout参照は**Host内部の認証済み文脈**から選択し、攻撃者が任意に選んだファイルや任意trust rootへ誘導できないようにする。token由来ID/鍵は**認証済みHost記録との比較対象**であり、正本を選ぶ権限ではない。
- 独立したHost正本（誰が登録し、どんな書込権限を持ち、なぜこの鍵とpolicyを承認したか）を取得・検証できない場合、**正常そうに見える合成fixtureでもHOLD**。PGがまだないため`nonce_issuance_boundary`もnon-authoritative。
- 保存・伝播する`issuer/agent/merchant`、Challenge、Checkout、nonce発行イベントのidentityと`verified_at`は同一revisionの確定したHost記録に結び付ける。raw Checkout JWTを再シリアライズして同一としない。nonce原文やBuyer PIIを証拠artifactへ含めない。
- **全域一意性の範囲**：固定Terminalは署名済み`aud/nonce`であり、tenant/session/challenge_refを署名していない。`UNIQUE(tenant_id,nonce_sha256)`や部分履歴では不足。別primary/shard・restore巻戻りで全域一意性を証明できないならHOLD。
- CSPRNGの品質・原子的一意制約・commit観測は**別々に証明**する。読取APIの値、`durable=true`やSHA、nonce長は実装証拠にならない。

## 4. 将来の戻り値・段階の安全な位置づけ

A3-T2bの後続**source-only**候補の成功形は**意図的にHOLD**。内部診断型を`BoundaryObservation`（仮称）として考えても、`status`は`HOLD`または**明確に確定できる入力不一致の`REJECT`に限る**。`authoritative?=false`、`g1_admissible?=false`、`g3_authenticated?=false`、`evidence=nil`、`valid_until=nil`を常に維持。`SUCCESS`、`PASS`、`ALLOW`、`nonce_consumed=true`、正のstage到達ledgerを返さない。

**検証時の順序は`G0→G1→G2→G3→G4→G5→G6→G7`。** 将来の統合Verifierで、元Root/Terminal/Checkout全wireの**strict/有界G0がPASSした場合にのみ**G1正本へ照会できる。A3-T2b source-only個別診断は**実際の統合G0を実行したことにはならない**。G2署名やG3元Root閉包を局所診断できても、前段信頼がHOLDならG2/G3「認証済み」と記録しない。G4暗号結合・G5固定公式Schema・G6制約/Checkoutの**順序の前後交換は不可**。

REJECTとHOLDは区別する。すでに独立に確認した既知不正（revoked、不一致、既知再利用）はREJECT、正本未取得/失効不明/clock不明/DB不在/通信・commit不明はHOLD/STOP。片方のHOLDが独立の既知不正を覆わないが、未実行stageへの「到達」「first reject stage」を捏造しない。DB未接続のA3-T2b source-only候補に、本番Hostの失効/整合性を証明する能力はない。

### G7とHost最終認可の区別

将来G7で出すとすれば`VerifiedEvidence` **だけ**。必要な全stageの証拠、信頼済みclockと改変不能snapshot、署名済みOpen/Terminal/Closedの期限、Host Challenge期限、Issuer/Agent/Merchantの**鍵/各policy別の`not_after`**、Host TTL/その他適用される有限期限の**最小値以下**を`valid_until`とする。欠損・未証明期限ならHOLD。A3-T2bではG7を作らない。

Nonce**発行**時の全域一意性（NI02）は、Host**最終認可**時の一回消費CAS（NC01）やCheckout operation一意性・Provider側の冪等性（NC02）とは別。Verifierはnonceを消費せず購入認可も支払も行わない。別の[Host replay研究](HOST_REPLAY_LAB_DESIGN.md)の実測成功からA3-T2bの独立Host正本・全域発行台帳への証明移植は禁止。

## 5. 承認A/Bを混同しないための段階表

| 段階 | 将来の最小許可候補 | 現在の判断 |
| --- | --- | --- |
| **本Issue #93** | **この1 docs ファイルと静的Codexレビューのみ** | **設計のみ許可、実装/実行は未承認** |
| **A3-T2b：研究コード作成** | 上記新規`a3_t2b_host_registry_boundary.rb`・`a3_t2b_nonce_issuance_boundary.rb`の**2ファイルのHOLD専用境界定義のみ**。新Issue・Ownerが番号とA3-T2b承認を明示、差分と影響する自動CI triggerを**事前確認** | **NOT APPROVED / NOT RUN** |
| **A3-T2c：独立Host/PG台帳実験** | 別Issueと明示された具体的環境・SQL・migration・CSPRNG・2worker競合/復旧/rollback/障害テスト・正本ACL/監査/cleanup・費用上限 | **NOT APPROVED / NOT RUN** |
| **E06-I承認B [#73](https://github.com/cuichangquan/ap2-mandate-verifier/issues/73)** | 既存の限定統合Ruby/Python/fixture/CI最大13ケース・手動1回を、**別Owner明示承認**・準備完了後に扱う | **HOLD**。A3-T2bコード承認でもBを許可しない |
| **真正なG1→G7/Host final** | 独立Host登録・nonce発行根拠・trusted clock・全stage実到達・Host別CAS/Checkout/Providerのさらに別審査 | **HOLD / 未実装・未実証** |
| **Phase 2-B/Gem/本番** | すべての未証明点について独立審査し別途GO判断 | **NO-GO** |

実装承認を依頼する場合の文面は、たとえば **「新規Issue #（別途作成）のA3-T2b：上記2つのresearch-only Ruby境界ファイルの作成と静的レビューのみを承認。実行、DB、fixture、CI、承認B、G1/G7成功は承認しない」** のように、番号・対象パス・禁止項目を明示する。これを**本Issue #93の作成・docsマージ・単なる『OK』に読み替えない**。

**A3-T2b着手前の必須事前確認:** 現行branchのファイル存在・新規のみの差分、`.github/workflows/**` の全PR/push path filtersが研究用新規パスに反応しないことを**リポジトリの実定義から確認**。意図せず自動CIが走り得る・関連旧コードの編集が必要・安全にHOLD-onlyを保てない時は**コード/PR作成前にSTOPして再承認**。Approval B以前に新workflowを有効化しない。

## 6. 将来の反証計画・証拠はすべてNOT RUN

- tokenの`kid/jwk`で正本を選ばせる、別経路の承認がない一致JSONだけを渡す → Host出所HOLD。
- 登録されていないIssuer B、Hostに既知revokedのkey/policy、別tenant/Checkoutの紐付け → trusted known不一致REJECT。それ以外の単なる偽JSON一致はHOLD。
- 同じnonceを2workerが別tenantで発行、期限切れの再発行、バックアップrollback、不明commit → 将来の**実DB**unique/commit/履歴を独立観測できるまでHOLD。
- `verified_at`がcaller起源/異なるrevision、Checkout JWT原wireに差替え、発行時Agent thumbprint変更 → known不一致REJECTまたは正本欠落HOLD。
- G0異常なのに正本照会へ進む、G0/G1 HOLDなのにG2/G3/G7 PASSにする、Host final CASをVerifierの成果にする → STOP/禁止。

将来のテストケースは[PR #90のTP01–TP12](PHASE2A_E06I_A3_T2_HOST_NONCE_PROOF_PREREQUISITES.md)に対応する**計画候補**であり、今回新たに実行していない。`Ruby -v`やテスト、`ruby -c`、DB接続、実nonce生成、GitHub Actionsを実行しない。独立のE-Host/E-Issuance/E-Clock/E-Checkout/E-Crypto/E-HostFinal証拠は収集していない。

## 7. 文書完了条件

- この**単一docsファイルだけ**をPRで変更。
- latest HEADの**静的Codexレビュー完了**、P1/P2への対応、未解決スレッド0件を確認するまで**マージしない**。
- マージできても**DESIGN COMPLETE / A3-T2b IMPLEMENTATION NOT APPROVED / NOT RUN / G1/G7 HOLD / PHASE 2-B HOLD**。
- 実装を前進させる際は、改めてOwnerが新Issue番号と限定ファイル範囲を**明示承認**する。設計レビュー合格はHostの安全性実証にはならない。
