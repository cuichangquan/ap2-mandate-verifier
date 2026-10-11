# Research Plan — 小さく始める

更新日：2026-10-11。**研究・小さなオフライン技術検証を実施。Ruby Gem/API実装・公開は未実施。**

## Phase 0 — 仕様と競合調査

- [x] AP2 v0.2の公式Commit SHAを固定してCheckout Mandate検証のMUSTを一覧化（[SPEC_BASELINE](SPEC_BASELINE.md) / [VERIFIER_REQUIREMENTS](VERIFIER_REQUIREMENTS.md)）。
- [x] 公式Python SDKの対応範囲、署名・開示・チェーン検証を**ソースとテストで静的照合**（[ECOSYSTEM_RESEARCH](ECOSYSTEM_RESEARCH.md)、実行検証は未実施）。
- [x] RubyGems/GitHubでAP2専用Gem、SD-JWT VC、JWT等を限定調査（[ECOSYSTEM_RESEARCH](ECOSYSTEM_RESEARCH.md)）。競合不存在は断定しない。
- [x] 最小のVerifier API案・スコープ・未保証項目を**設計としてのみ整理**（[API_PROPOSAL](API_PROPOSAL.md)）。公開API未確定、未実装。
- [x] P0-5でGO/HOLD/NO-GOを評価し、**HOLD**を記録（[RESEARCH_DECISION](RESEARCH_DECISION.md)）。Ruby実装は未承認。
- [x] **P0-5a完了（公式pytest 186 PASS / 2 FAIL、実署名負例12 PASS、先行限定11 PASS）**。[実測記録](PYTHON_BASELINE_VERIFICATION.md)。公式uv.lockはprivate registry 401のためpyproject直接依存を公開PyPIから取得。**Gem実装HOLD継続**。
- [x] **P0-5b完了**：[Fail Closed Profile](FAIL_CLOSED_PROFILE.md)でIssuer trust、terminal aud/nonce、required disclosure、Checkout原文・hash、Host認可を限定し、[RESEARCH_DECISION](RESEARCH_DECISION.md) §9で**非本番Ruby PoCだけCONDITIONAL GO**（汎用Gem・本番利用はHOLD/NO-GO）。
- [x] **P1-0完了**：合成Python ES256 JWS fixtureと固定AP2公式Open Checkout Schemaに対するRuby `jwt`・`json_schemer`互換性試験 **14 runs/17 assertions, 0 failures**。([RUBY_FEASIBILITY_SPIKE](RUBY_FEASIBILITY_SPIKE.md)、[CI実測](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38123249933))。Gem実装ではない。
- [x] **P1-1完了**：[RUBY_SDJWT_RESEARCH](RUBY_SDJWT_RESEARCH.md) — 固定AP2 v0.2 Python SDKで実署名Root SD-JWTを生成し、RubyでES256 Root署名＋array disclosure digestの完全開示を検証。Merchant制約の非開示／署名・開示改ざんは拒否。**10 runs/22 assertions、0 failures**（[CI実測](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38123828122)）。研究用Strict Profileのみ、Gem実装ではない。
- [x] **P1-2完了**：[RUBY_DELEGATION_SPIKE](RUBY_DELEGATION_SPIKE.md) — 固定AP2 v0.2公式Python SDK発行・Python検証済みOpen→ClosedをRubyで検証。Root `cnf`、Terminal ES256署名、`sd_hash`、Host `aud`/`nonce`の正負を確認 **15 runs/32 assertions、失敗0**。P1-1回帰 **10 runs/22 assertions、失敗0**（[CI](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38124823804)）。実Checkout JWTはダミー。
- [x] **P1-3完了**：[RUBY_CHECKOUT_BINDING_SPIKE](RUBY_CHECKOUT_BINDING_SPIKE.md) — 公式AP2 v0.2 Open→Closed＋**Merchant ES256署名済Checkout JWT**を生成し、Host JWT正本のバイト一致、SHA-256 hash、店舗/商品/数量/単純合計の厳格評価をRubyで確認。**18 runs/40 assertions、0 failures**、P1-2回帰15 PASS、P1-1回帰10 PASS（[GitHub Actions](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38126247946)）。SDK数量評価との差異を記録。
- [x] **P1-4完了（静的レビューのみ）**：[SECURITY_GAP_REVIEW](SECURITY_GAP_REVIEW.md) — P1-1〜P1-3コードに基づく**12項目のリスク登録＋6つのGem受入れゲート**。公開/汎用Gemの実装は**HOLD**、Production/実決済は**NO-GO**。研究テスト追加に限定したP1-5はGO候補（別途承認）。新CI・新攻撃実証はなし。
- [x] **P1-5完了（テストのみ）**：[SECURITY_NEGATIVE_TESTS](SECURITY_NEGATIVE_TESTS.md)、[Actions #38127279271](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38127279271)。固定AP2 SDK＋Ruby研究コードの署名済負例**18件：GREEN 11（正例1/拒否10）、RED 6（想定外受理）、HOST_BOUNDARY 1、ERROR 0**。既存P1-1/2/3回帰43件はPASS。**汎用Gem/API実装HOLD、公開/本番NO-GO**。既存検証器は変更しない。
- [x] **P1-6完了（研究コード修正のみ）**：[SECURITY_HARDENING_RESEARCH](SECURITY_HARDENING_RESEARCH.md)、[CI #38128152237](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38128152237)。以前の**6 REDをすべてGREEN化**。署名付き観測18件=**17 GREEN / 0 RED / 0 ERROR / 1 Host Boundary**。P1-1〜3回帰**10+15+18=43件成功**。重複JSON/JOSE・Closed内時刻・Merchant JWT typ・未知Checkout fieldを厳格化。**Gem実装/公開・実決済はHOLD/NO-GO**。
- [x] **P1-7完了（設計資料のみ）**：[HOST_SECURITY_CONTRACT](HOST_SECURITY_CONTRACT.md) / [HOST_SECURITY_TEST_PLAN](HOST_SECURITY_TEST_PLAN.md)。Issuer/Buyer/Agent/MerchantのHost鍵信頼登録、Host current Checkout、`VerifiedEvidence ≠ ALLOW`、nonceと注文の**原子的な一度限り遷移**、失効・Clock・外部処理Idempotency/Receiptの責務を分け、**34件の将来テストID**を設計。**新テスト/CI、Host DB/実決済、Gem/API実装なし**。汎用Gem実装HOLD・Production NO-GO。
- [x] **P1-8完了（設計のみ）**：[HOST_REPLAY_LAB_DESIGN](HOST_REPLAY_LAB_DESIGN.md) — SQLiteとPostgreSQLを比較して**一時PG16**を採用候補に選定。2 worker、nonce CAS＋Checkout unique、commit前後crash/Retry、Fake Provider idempotency、費用/cleanup、HR01〜HR10試験順序とGO/HOLDを設計。**Host DB・新CI・新テストなし、34件すべてNOT RUN。**
- [x] **P1-9a完了（隔離Host DB研究のみ）**：[HOST_REPLAY_P19A_EVIDENCE](HOST_REPLAY_P19A_EVIDENCE.md) — PostgreSQL 16.9とRuby 2独立worker、実DBロック競合測定、nonce CAS/Checkout unique/Outbox。**HR01/02/03/08の4ケース：CI 4 runs・108 assertions・0 failures/0 errors**（[Actions #38133951057](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38133951057)、[digest-pinned再検証 #38134040469](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38134040469)）。初回構文エラーのCI失敗も記録。**残り30 HostケースはNOT RUN、Gem/API/実決済は未実装**。
- [x] **P1-9b完了（隔離Host PG16クラッシュ研究のみ）**：[HOST_REPLAY_P19B_EVIDENCE](HOST_REPLAY_P19B_EVIDENCE.md) — HR04（COMMIT前SIGKILL/全Rollback）・HR05（COMMIT ACK後SIGKILL/PENDING復元・再送STOP）**2 runs / 84 assertions成功**、P1-9a回帰4/108成功、計**6/34実測・残り28件未実行**（[CI #38134591784](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38134591784)）。
- [x] **P1-9c完了（オフラインUnknown COMMIT/Mock Provider研究のみ）**：[HOST_REPLAY_P19C_EVIDENCE](HOST_REPLAY_P19C_EVIDENCE.md) — HR06（COMMIT非同期送信・ACK未受信で別DB回復／実lock_timeout `55P03`）、HR07（Mock Provider応答喪失＋同一key 2回試行／論理効果1件＋別key STOP）。**新2 runs /149 assertions、旧6 runs/192 assertionsの計8/34件PASS・341 assertions成功**（[CI #38135302918](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38135302918)）。**残る26件未実行**。
- [x] **P1-10a完了（HR10・同一DBのCheckout変更/失効競合のみ）**：[HOST_REPLAY_P110A_EVIDENCE](HOST_REPLAY_P110A_EVIDENCE.md) — PostgreSQL 16.9独立2workerのDBロック競合を実測。cancel先/Buyer block先/Checkout version更新先→STOP・nonce未使用・operation/outbox0、注文先→遅い取消はtoo_late。**HR10の4 subcases：4 runs/124 assertions PASS**、既存8 runs/341 assertions回帰PASS。**正本Host34件中9件実測・25件未実行**（[CI #38136341199](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38136341199)）。外部失効源は保証対象外。
- [x] **P1-10b完了（HC06は設計・テスト戦略のみ、NOT RUN）**：[HOST_EXTERNAL_REVOCATION_HC06_DESIGN](HOST_EXTERNAL_REVOCATION_HC06_DESIGN.md) — 外部Issuer/Agent/Buyer失効の有効時点RとHost確定Cの整合性、単純な照会方式のTOCTOU、fencing/leaseの条件、UNKNOWN時Fail Closed、HC06-A〜Hの負例を設計。新実装・CI実行・Host ID実測の増加なし。**既存9/34件のみ実測、25件未実行**。
- [x] **P1-10c完了（HC06の架空Authority/Host状態モデルのみ）**：[HOST_EXTERNAL_REVOCATION_P110C_EVIDENCE](HOST_EXTERNAL_REVOCATION_P110C_EVIDENCE.md) — 再照会成功後の失効Q→R→C、fence発行のみで最終検査を省いたF→R→Cの**危険な負例2件**を再現。**共有Mutexによる人工的な最終認可境界**ならR<CでSTOP、C<Rで既存operationを偽取消しないなど、合計**8 Minitest runs/94 assertions/失敗0**（[CI #38137575582](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38137575582)）。実Authority/DB間の原子性は証明せず、**HC06完全PASSには数えない**。実DB Host正本9/34件、残り25件未実行を維持。
- [x] **P1-10d完了（HC06の外部Authority/Host協調プロトコル設計のみ）**：[HOST_EXTERNAL_REVOCATION_P110D_PROTOCOL](HOST_EXTERNAL_REVOCATION_P110D_PROTOCOL.md) — 外部の失効有効化RとHost耐久COMMIT Cの順序、予約P/失効要求の保留、fence強制境界、障害/不明COMMIT/遅延COMMIT/二重送出の判断表、候補方式A〜Fを整理。**実装・新テスト・CIなし**。実DBでの正本Host9/34件・25件NOT RUN、HC06フルHOLDのまま。
- [x] **P1-10e完了（設計のみ／NOT RUN）**：[HOST_EXTERNAL_REVOCATION_P110E_TEST_PLAN](HOST_EXTERNAL_REVOCATION_P110E_TEST_PLAN.md) — 独立した架空Authority/Hostによる予約後失効要求、COMMIT応答不明、予約timeoutと遅延COMMITの3系統12将来計画ID、fault barrier、耐久証拠、不変条件I1〜I6を設計。**実装・新テスト/CI・新DB検証なし**。正本Host 9/34件・25件NOT RUN、HC06 FULL HOLDは不変。
- [x] **P1-10f完了（採否判断資料のみ・NOT RUN）**：[HOST_EXTERNAL_REVOCATION_P110F_HARNESS_DECISION](HOST_EXTERNAL_REVOCATION_P110F_HARNESS_DECISION.md) — E-R01/E-R02に限り、2独立Ruby worker＋別PG16インスタンス×2のローカル検証を**条件付き推奨**。abort gateの耐久・全C経路強制、barrier/障害注入・cleanup・費用/ローカル制約の着手ゲートを文書化。**実装/CI/新実測0**、HC06分散HOLD・Host正本9/34のまま。
- [x] **P1-10g完了（2限定合成ケースの実PG16実測のみ）**：[HOST_EXTERNAL_REVOCATION_P110G_EVIDENCE](HOST_EXTERNAL_REVOCATION_P110G_EVIDENCE.md) — Ruby別プロセス＋**別PG16.9インスタンス×2**でE-R01/R02の隔離合成研究、[専用CI #38143039035](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38143039035) **2 runs/118 assertions/0 failures**。Host abort COMMIT後のSIGKILL、別接続復旧、遅延worker STOPを観測。Authorityの本当の線形化保証は**未実証**でHC06 HOLD。正本Host9/34・25 NOT RUNを維持。
- [x] **P1-10h完了（信頼境界の設計レビューのみ・H01〜H12 NOT RUN）**：[HOST_EXTERNAL_REVOCATION_P110H_PROOF_BOUNDARY_REVIEW](HOST_EXTERNAL_REVOCATION_P110H_PROOF_BOUNDARY_REVIEW.md) — Coordinatorの偽`finalize_abort`を無条件に信じる現行合成Authorityの穴、Hostのdurable C/abort真正性・全C経路STOP・証拠束縛、再送/矛盾/partition/rollbackのFail Closedを整理。**実装・CI・テスト・DB新実測なし**、正本Host9/34・25 NOT RUN、HC06 FULL HOLD。
- [x] **P1-10i完了（合成負例H01〜H06だけの実測）**：[HOST_EXTERNAL_REVOCATION_P110I_EVIDENCE](HOST_EXTERNAL_REVOCATION_P110I_EVIDENCE.md) — [CI #38145972566](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38145972566) **6 runs / 178 assertions / 0失敗・0エラー**。H01は旧Authorityが誤って失効有効化後もHost COMMIT可能だった**危険な反例**を観測（安全PASSに数えない）。研究用guardではUNPROVEN。H02〜H06は限定REJECT/IDEMPOTENT/CONFLICT/UNPROVENを確認。初回CI #38145867563はテスト解析エラーで失敗、修正後PASS。**Hostへの直接PG接続は研究用信頼前提**、本物のHost署名・遠隔認証・分散原子性ではない。正本Host9/34・25 NOT RUN、HC06 HOLDは不変。
- [ ] **P1-10j（次のおすすめ1件・別途明示承認後のみ）**：直接Host DB参照のない独立Authorityが実際に安全なHost durable decisionを確認できるか、真正性・anti-rollback・全C経路強制/STOP条件を**採否設計レビューだけ**で判断。外部API/実装/GCP/決済は別承認。

## Phase 1 — Checkout Mandate PoC（GO後）

- [ ] 正しいMandate形式・バージョン（vct）・Open/Closedの扱い。
- [ ] SD-JWT署名、開示、Agent鍵・Proof-of-Possession、aud/nonce/期限など仕様が要求する確認。
- [ ] Hostが指定するIssuer信頼ポリシー。Mandate内のJWK/issを無条件に信頼しない。
- [ ] 委任チェーン、Mandate制約、merchant-signed checkoutとhashの照合。
- [ ] Verifier結果は「Verified Evidence」であって最終ALLOWではない。

## Phase 2 — セキュリティ負例（GO後）

- [ ] 改ざん、誤った鍵・Issuer、不正アルゴリズム、期限外、別Agentへの転用。
- [ ] Audience/Nonce不一致、key binding欠落、未開示/未知の必須Constraint。
- [ ] Checkout/金額/通貨/取引先不一致、委任範囲の拡大、replay対策の責務。
- [ ] 巨大Payload/長いチェーンのリソース制限と、情報漏えい防止。

## Phase 3 — 相互運用と公開判断（GO後）

- [ ] 公式Python実装と同じ正例・負例をRubyでも検証。
- [ ] 仕様との差分があればテスト証拠を残し、必要に応じupstreamへ報告。
- [ ] Ruby/Railsサポートmatrix、依存関係、ライセンス、セキュリティ窓口を確定。
- [ ] 監査とCIが整うまでは**production ready**や**AP2 compliant**を主張しない。

## 研究の成功条件

単にMandateのJSONを解析できることではない。発行元・Agent・委任範囲・提示先・Checkoutの結び付きを正しく検証し、**不正な証明を拒否できること**が必要。
