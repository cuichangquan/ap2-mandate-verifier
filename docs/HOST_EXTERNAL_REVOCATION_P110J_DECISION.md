# P1-10j — Host DB直接参照なしの独立Authority: 耐久決定証拠の成立条件と採否

**2026-10-11 JST / ARCHITECTURE DECISION REVIEW ONLY / NOT RUN。** 対象は[P1-10hのAuthority信頼境界レビュー](HOST_EXTERNAL_REVOCATION_P110H_PROOF_BOUNDARY_REVIEW.md)と[P1-10iの独立PG負例実測](HOST_EXTERNAL_REVOCATION_P110I_EVIDENCE.md)を踏まえ、**AuthorityがHost PostgreSQLを直接照会できない場合**に、どの契約・正本・失敗処理が必要かを判定することだけ。コード、Ruby Gem/API、署名・秘密鍵、DB、テスト、CI、外部Authority/Host接続、GCP、決済、Receipt等は一切追加・実行しない。

固定一次基準：公式AP2 v0.2.0 commit `b4587ac1d055888a73b4b21750973cffba961793`。本書の`Authority reserve/finalize`、`Host durable decision proof`、`R_effective`協調は**本OSSの研究用Host設計**であり、公式AP2プロトコルに存在すると仮定しない。

## 1. 問題と明確な判断

[P1-10i](HOST_EXTERNAL_REVOCATION_P110I_EVIDENCE.md)は、別PG16.9インスタンス2つを実際に用いて**6 runs/178 assertions PASS**だった。だが`research/p1_10i/authority_guard.rb`が別Host DBを**直接、信頼できる管理者として読み取る**ことが安全判定の要。現実の他社Authorityにはこのアクセス権限がない場合が普通で、その保証も確認していない。

さらにH01で既存`research/p1_10g/worker.rb`の**危険な反例**（Authority `R_effective`成立後にHost `C`が成功）を実測している。H01の旧経路は安全性PASSではない。**「HostがABORTした」とする署名済みJSONを信用するだけでは同じ穴が残る。**

**決定: CONDITIONAL FEASIBILITY / DESIGN RESEARCH ONLY — 具体的な実サービスでの採用・実装はHOLD。** 以下の**信頼済みHost、Host全C経路の強制gate、独立Authorityとの失効保留契約**がすべて確認できれば研究対象にはなり得るが、実現できることは未確認。どれか満たせない・不明なら`R_effective`や「取消完了」を確定してはいけない。

## 2. 「証拠」が証明するもの／しないもの

| 層 | 研究候補の必要契約 | この層**だけ**では保証できないこと |
| --- | --- | --- |
| 発行者認証 | Authority事前設定のHost trust anchor（許可Host ID、鍵・更新/廃止権限、purpose、audience）。mTLSや署名を**既知の鍵**で検証。メッセージ中のJWK/`kid`/URL自己申告から信頼根を作らない | Hostが正直か、Host DBに本当にABORTがcommitしたか |
| 文脈束縛 | reservation/operation/Authority/Host/tenant/subject/scope/checkout ID＋version＋fingerprint/nonce digest/epoch・fence/decision IDを、Authorityが保存した予約`P`と完全照合。署名付き正規化envelopeに含める候補 | HostとAuthorityの原子的順序、未知の別Authority失効 |
| 耐久的な結果 | Hostが`COMMITTED`と`ABORTED`を同じCheckout gateで**排他的に**決定。abortなら`ABORTED`に固定し、**すべてのC経路**で将来COMMIT禁止。決定レコードと証拠送出用outboxは同一Host transactionで耐久記録、ACK後に再読可能 | 自己申告だけで耐久状態を外部から独立立証できること、将来の悪意あるHostによるgate迂回 |
| 継続的強制と復旧 | 再起動・別worker・failover・バックアップ復旧後も同一reservation/epochに対する`ABORTED`を巻き戻せず、未発見の古いworker/未確定Cがgateを通れない。ログ保持/復元手順/運用責任が契約で明確 | Hostが障害時に過去データを任意に巻き戻す、悪意あるHostが嘘の証拠を発行するケース |
| Authorityの確定 | 正本`P/R_request/R_effective`を条件付き・単調にcommitし、decision ID/digest/epochを一意に記録。重複は冪等、矛盾はCONFLICT。受信順ではなく証拠の継続的正本性に依存 | 別DB間の原子性や全順序を「署名+2回HTTP」で自動獲得すること |

**信頼モデルを明示：** 実用可能性を検討できるのは**誠実で障害停止型のHost、全Checkout経路が同じdurable gateに従う**という管理・契約上の前提を満たす場合だけ。誤実装やDB rollback防止の技術的・運用的証拠は別途必要。**Host自体が悪意ある/侵害済みなら、Host発の正しい署名は虚偽`ABORTED`を防げない**。この脅威に耐えるにはHost以外が強制できる共有直列化境界・独立参加者の合意/決定等、別アーキテクチャが必要で、現状未設計。

## 3. 直接Host DBなしの協調フロー候補（**未実装**）

1. Authority正本が対象の認可`P`をreservation/operation/epoch/tenant/scopeに束縛し、`R_request`到着後は`ACCEPTED_PENDING`に記録。**即時R_effectiveではない**。対応する全Authority/失効源の範囲が不明ならHOLD。
2. Host側で同一gateを通して`C_DURABLE`（nonce CAS、operation/outbox一意）**または**`ABORT_DURABLE`（terminal STOP、operation/outbox 0）を**排他的に**決定する。先行/未知の`C`が残るならABORT確定を作らない。
3. Hostは**耐久的な決定に紐付いた**記録/outboxから、固定trust anchorで検証可能な証拠を提供する設計候補。`decision_id`、単調epoch、署名/送信者、完全context、terminal gate参照、障害復旧手段が必要。通信切断・ACK欠落は再送/権威的な照会により同一決定へ収束させる。**証拠が有効でもHostの実装品質/rollback耐性は自動的に立証されない。**
4. Authorityは自身の予約と事前の信頼設定で検証し、同一決定を原子的かつ冪等に`R_effective`へ進める。証拠の出所・gateの強制・in-flight結果が不明なら`PENDING / UNKNOWN / RECOVERY_REQUIRED`で止める。
5. `C < R_effective`が証明されたときは**既存COMMITTED操作を取消し済みと表示しない**。外部Provider `D`、返金、署名Receiptの処理は別契約。`R_request`から確定までの遅延が許されない即時取消契約にはこの方式を適用しない。

**注意：** 順序説明は**具体的な合意プロトコルの証明ではない**。実際の外部Authorityに`P`/`R_request`/`R_effective`やこのような証拠受理APIがあることを**確認していない**。ログの時刻・署名・短命TTLは単独で`R_effective < C`を排除しない。上記条件を実装・監査・故障注入で裏付けるまではNO-GO for production。

## 4. 成立性を左右する決定的質問（回答がないならHOLD）

| 質問 | 最小の確認内容 |
| --- | --- |
| Q1. 誰が`R_effective`を決めるか | 本物のAuthorityが予約P、失効要求の保留、Host決定後のR_effectiveの順序保証を提供するか。Issuer/Agent/Buyer別失効源の合成責任者は誰か |
| Q2. Hostの全C経路を止められるか | 直接DB write/別worker/outbox再送/旧epoch/再起動を含む全経路がterminal gateを通ることを強制・検証できるか |
| Q3. Host証拠を誰が真正に発行するか | 事前登録された鍵と発行権限、rotation/revocation、異なるAuthority/tenant/scopeへの流用防止、Host侵害時の対応 |
| Q4. Host crash/failoverの真実を誰が保証するか | 決定/outboxの同一transaction、永続ログ・単調epoch、復元/backup/リージョンfailoverによるrollback検出・隔離 |
| Q5. 相手の状態が`UNKNOWN`ならどうするか | PENDINGの有効期間/可用性/SLA/顧客への説明、強制停止、手動照合責任、`R_request≠R_effective`を守れるか |
| Q6. 決定が矛盾・期限切れ・再送ならどうするか | 同一operation一意性、冪等再照会、異なるdecision ID/epochのCONFLICT扱い、証拠保管期間と破棄制限 |
| Q7. Hostを信頼しない脅威モデルが必要か | 必要ならHost単独署名型は不適切。共有正本/外部強制gate/参加者型protocolのコストと権威の所有者を再設計 |
| Q8. 実業務の失効はどこまでか | 「これからの新規C停止」なのか、既存CやProvider D、返金まで要求するのか。顧客への表示/契約を混同しない |

## 5. 負例・中断の判断表（**設計期待値のみ・NOT RUN**）

| 境界 | 異常入力/障害 | 必須の停止動作 |
| --- | --- | --- |
| Host identity | 自己申告`kid`/JWK、未登録Host、誤audience、期限切れ/廃止鍵 | **REJECT / R_pending**。適切な鍵管理モデルも未実装 |
| 文脈 | 別reservation/tenant/checkout version/epochの正しく署名された旧証拠 | **REJECT / R_pending**。署名の正しさは文脈の正しさでない |
| durable proof | 署名OKだがHostはOPEN、abort eventだけ、別C経路が残る | **UNPROVEN / R_pending**。Hostの自己申告以外の強制前提が必要 |
| conflicting result | 同一予約でCOMMITとABORT、別`decision_id`での再提出 | **CONFLICT / STOP / operator investigation**。勝手に新方を採用しない |
| lost ACK | Host決定確定後、ネットワーク分断/ACK喪失/中間Coordinator故障 | **再照会と冪等復旧、結果不明ならPENDING**。timeoutによるR_effective推定禁止 |
| stale Host | DB backup復元/旧epoch worker/クロスリージョンfailover | **STOP / RECOVERY_REQUIRED**。terminal ABORTの反転を許さない |
| policy | Authorityが即時失効を約束するがHostの中止完了を確認できない | **HOLD/別アーキテクチャ**。`ACCEPTED_PENDING`を「取消完了」と案内しない |
| Byzantine Host | 正当鍵でHostが虚偽中止証拠を発行 | **NO-GO for untrusted Host model**。署名だけで解決できない |

これらは**P1-10jの設計チェック行であり、新規テストID・PASS数ではない**。P1-10h `H07〜H12`もすべてNOT RUN。合成PG16試験で実際に検証したのはP1-10i `H01〜H06`だけ（H01旧経路危険反例を含む）。

## 6. 比較採否・次の研究ゲート

| 候補 | 対象となる信頼モデル | 判定 |
| --- | --- | --- |
| A. Coordinatorの`finalize_abort`/署名済み`ABORTED`文字列だけ | 任意の中継者を信用 | **NO-GO**。H01で旧経路の重大問題実測 |
| B. Host署名済durable terminal decision + transactional outbox + Authority側context/正本照合 + terminal gateの全C経路強制 | **誠実で障害停止型Hostと検証可能な復旧規則が前提** | **CONDITIONAL RESEARCH ONLY**。API/参加意思/ログ復旧/anti-rollback・耐久証拠の検証性が不明。導入GOではない |
| C. Hostとは独立の共有強制直列化点/明示的prepare参加者による共通決定 | Host自身を信用しない/即時取消に近い要求 | **HOLD**。外部Authorityが参加できる保証なし、複雑性/費用/可用性大 |
| D. キャッシュ/短命ALLOW、TTL再照会、署名済fence単独 | eventual consistency | **NO-GO for strict HC06**。R/C間TOCTOUを消せない |

**最終判定：P1-10jの比較レビューだけ完了。** 実Authorityに必要な契約は**未確認**であり、実Host DB連携の保証は未証明。**HC06外部分散安全性HOLD、汎用Gem/API・本番Host統合HOLD、RubyGems/Production/実決済/署名Receipt NO-GO。** P1-10iの研究成功をproduction-readyと主張しない。自己レビューは独立安全監査ではない。

**実測カウント不変：** 正本Host **9/34件PASS/25 NOT RUN**、既存**12 runs/465 assertions**。P1-10c単一process合成8 runs/94 assertions、P1-10g別PG16 E-R01/R02合成2 runs/118 assertions、P1-10i別PG16 **6 runs/178 assertions**（[最新main向け最終CI #38148130154](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38148130154)）は別枠。N17 HOST_BOUNDARY、P1-4 G1〜G6/P1-7 T1〜T5、公式Python SDK中間hop186 PASS/2 FAIL未解決。

**次のおすすめ1件（別途明示承認が必要）：P1-10k — 設計のみ。** 実外部API/署名秘密鍵実装に進む前に、Hostの「信頼できる障害停止・全C経路durable gate」**契約チェックリストと最低限の証拠の出し手/受け手責務**を具体的な契約表としてまとめ、実装可否判定の未回答項目を残す。新規コード・CI・GCP・本番・決済・Gem公開は別途承認。
