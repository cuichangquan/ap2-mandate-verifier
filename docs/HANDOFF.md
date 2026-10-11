# AP2 Mandate Verifier for Ruby — 開発引き継ぎ指示書 / TODO

更新日：2026-10-12
状態：**P0完了、P1-0〜P1-10p研究完了。P1-10pはIssuer/Constraint残余Gapの設計レビューのみ、テスト追加0。** [P1-10p残余リスク表](VERIFIER_P110P_RESIDUAL_GAPS.md)：GP01〜GP09は新試験NOT RUN。最優先GP01はIssuer署名の既知Constraintに未知ネスト属性が追加された場合の**静的な受理可能性の疑い**であり、攻撃の実測ではない。P1-10o最終 [CI #38155050010](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38155050010) **8 runs/45 assertions/失敗0**は以前の独立研究。AN-N07は二度verify成功の**HOST_BOUNDARY**でreplay未防御。Host正本**9/34件・25 NOT RUN（過去12 runs/465 assertions）**、一般SD-JWT/Issuer、本番Gem/API・HC06はHOLD、RubyGems/決済/署名Receipt NO-GO。**次のおすすめはP1-10q：GP01だけの正署名合成負例観測（別承認）**。

## 1. 新しいチャットで最初に読むこと

**正本（GitHub main）：** https://github.com/cuichangquan/ap2-mandate-verifier/tree/main

作業開始時にGitHubの最新 `main`、既存Issue、Open PRを確認すること。過去の会話や、この指示書中のSHAを無条件に最新状態として扱わない。

読む順番：

1. [README](../README.md) — Gemの目的・利用シーン・非スコープ
2. [PROJECT](PROJECT.md) — D001〜D006、責務境界、独立OSS方針
3. [SPEC_BASELINE](SPEC_BASELINE.md) / [VERIFIER_REQUIREMENTS](VERIFIER_REQUIREMENTS.md) / [ECOSYSTEM_RESEARCH](ECOSYSTEM_RESEARCH.md) / [API_PROPOSAL](API_PROPOSAL.md) / [RESEARCH_DECISION](RESEARCH_DECISION.md) / [PYTHON_BASELINE_VERIFICATION](PYTHON_BASELINE_VERIFICATION.md) / [FAIL_CLOSED_PROFILE](FAIL_CLOSED_PROFILE.md) / [RUBY_FEASIBILITY_SPIKE](RUBY_FEASIBILITY_SPIKE.md) / [RUBY_SDJWT_RESEARCH](RUBY_SDJWT_RESEARCH.md) / [RUBY_DELEGATION_SPIKE](RUBY_DELEGATION_SPIKE.md) / [RUBY_CHECKOUT_BINDING_SPIKE](RUBY_CHECKOUT_BINDING_SPIKE.md) / [SECURITY_GAP_REVIEW](SECURITY_GAP_REVIEW.md) / [SECURITY_NEGATIVE_TESTS](SECURITY_NEGATIVE_TESTS.md) / [SECURITY_HARDENING_RESEARCH](SECURITY_HARDENING_RESEARCH.md) / [HOST_SECURITY_CONTRACT](HOST_SECURITY_CONTRACT.md) / [HOST_SECURITY_TEST_PLAN](HOST_SECURITY_TEST_PLAN.md) / [HOST_REPLAY_LAB_DESIGN](HOST_REPLAY_LAB_DESIGN.md) / [HOST_REPLAY_P19A_EVIDENCE](HOST_REPLAY_P19A_EVIDENCE.md) / [HOST_REPLAY_P19B_EVIDENCE](HOST_REPLAY_P19B_EVIDENCE.md) / [HOST_REPLAY_P19C_EVIDENCE](HOST_REPLAY_P19C_EVIDENCE.md) / [HOST_REPLAY_P110A_EVIDENCE](HOST_REPLAY_P110A_EVIDENCE.md) / [HOST_EXTERNAL_REVOCATION_HC06_DESIGN](HOST_EXTERNAL_REVOCATION_HC06_DESIGN.md) / [HOST_EXTERNAL_REVOCATION_P110C_EVIDENCE](HOST_EXTERNAL_REVOCATION_P110C_EVIDENCE.md) / [HOST_EXTERNAL_REVOCATION_P110D_PROTOCOL](HOST_EXTERNAL_REVOCATION_P110D_PROTOCOL.md) — P1-10dは分散Authority協調の設計資料のみ
4. [OFFICIAL_SOURCES](OFFICIAL_SOURCES.md) — AP2/FIDO/IETFの一次資料・ウォッチリスト
5. [RESEARCH_PLAN](RESEARCH_PLAN.md) — Phase 0〜3 の全体工程
6. [SECURITY_BOUNDARY](SECURITY_BOUNDARY.md) — 未信頼Mandateの扱いとFail Closed

本書は**次に何をするかの案内板**であり、仕様の確定根拠は必ずバージョンを固定したAP2一次資料に置く。

## 2. プロジェクトの目的

外部のPersonal AI（分身AI）が持参する**AP2の委任証明（Mandate）**を、Rubyで安全に検証する小さなOSSの実現可能性を研究する。

背景：各ユーザーがすべての外部サービスに事前のAgent Delegationを設定する方式だけでは、分身AIの普及時に負担が大きい可能性がある。**自己宣言をそのまま信じるのではなく、証拠として検証し、各サービスの信頼ポリシーと業務認可を適用する。**

初期ターゲットは **AP2 v0.2 / Checkout Mandate / 受信側Verifier**。API名・Gem名・Namespace・依存Gem・Ruby/Rails対応matrixは**未確定**。

```text
Human -> (trusted authorization) -> Personal AI
  -> (untrusted external Mandate) -> Ruby Host
  -> [AP2 verifier: cryptographic & policy-relevant checks]
  -> Verified Evidence (NOT ALLOW)
  -> Host-side identity, business authorization, replay prevention
  -> Execute or Stop
```

ActingFor（Rails内部のDelegationとAudit）・a2a-rails（A2A通信）とは**独立**。両Gemおよび既存Demoに変更を加えない。

## 3. 全体のTODOと実行順序

### Phase 0 — 仕様・競合調査【P0完了 / Ruby P1-0〜P1-10p静的Gapレビューまで / 次はP1-10q別承認】

- [x] **P0-1：AP2仕様の基準点を固定（完了： [SPEC_BASELINE.md](SPEC_BASELINE.md)）**
  - 公式AP2 v0.2のSpecification / Agent Authorization / Checkout Mandate、および対応する公式Python SDKを確認する。
  - 関連タグ・Commit SHA・参照URL・確認日・仕様の現行状態を記録し、v0.1と混同しない。
  - 上流Issueや仕様の未決定・曖昧な点も明示する。実装やAPI設計はまだ行わない。
  - **成果物案：** `docs/SPEC_BASELINE.md`
  - **完了条件：** 再現可能な参照元が特定され、後続調査が同一基準で進められること。

- [x] **P0-2：Verifier必須要件とTrust Boundaryを整理（完了：[VERIFIER_REQUIREMENTS.md](VERIFIER_REQUIREMENTS.md)）**
  - 署名・SD-JWT/開示・発行者の信頼・Agent/holder鍵との結び付け・aud/nonce/期限・Delegation chain・Open/Closed Checkout・制約・取引内容との一致を、**仕様が要求する範囲を確認して**整理する。
  - `MUST` / `SHOULD` / 仕様で未規定 / Host責務を混同しない。各判断に一次資料の該当節を付ける。
  - 不正・期限切れ・鍵不一致・未知の必須制約等のFail Closed条件をテスト観点として列挙する。
  - **成果物案：** `docs/VERIFIER_REQUIREMENTS.md`
  - **完了条件：** 最小Verifierが保証する範囲と保証しない範囲が説明できること。

- [x] **P0-3：公式Python実装・既存Ruby Gemの競合/再利用調査（完了：[ECOSYSTEM_RESEARCH.md](ECOSYSTEM_RESEARCH.md)）**
  - 公式SDKのどこまでが実装済みかを、ソース・テストで照合する。
  - RubyGems/GitHubでAP2専用実装、SD-JWT/VC、JWT/JWS、暗号・HTTP関連実装を調べる。最新性、ライセンス、保守状況、テストを確認。
  - 「見つからなかった」は「存在しない」の証明にしない。
  - **成果物案：** `docs/ECOSYSTEM_RESEARCH.md`
  - **完了条件：** 再利用可能な部分と、本当にRubyで新規実装が必要な部分が分かること。

- [x] **P0-4：最小Public APIと責務分担の提案（設計のみ・完了：[API_PROPOSAL.md](API_PROPOSAL.md)）**
  - 入力（Mandate、期待するAgent/受取サービス/Checkout、Hostのtrusted issuer policy）と結果（verified evidence / rejection）を整理する。
  - 「署名が正しい」≠「Userが同意した」≠「Hostが業務を実行してよい」を守る。
  - ホストによる失効・Replay防止・ビジネス認可が必要か、VerifierのAPIがどこまで保証できるか明記。
  - **成果物案：** `docs/API_PROPOSAL.md`
  - **完了条件：** API案が小さく、根拠と保留点が明確であること。

- [x] **P0-5：実装GO/HOLD/NO-GOを判断（HOLD、[RESEARCH_DECISION.md](RESEARCH_DECISION.md)）**
  - 仕様の確かさ、SDK相互運用の見込み、OSS需要、Ruby既存実装との差分、セキュリティ・保守コストから判断。
  - **成果物案：** `docs/RESEARCH_DECISION.md`
  - **完了条件：** GO（最小PoC）、HOLD（仕様待ち）、NO-GO（既存活用/価値が小さい）の根拠を記録。**自動的に実装へ進まない。**

- [x] **P0-5a：AP2公式Python SDK基準テスト・Issuer/aud/nonce/Selective Disclosure優先負例（完了：[PYTHON_BASELINE_VERIFICATION.md](PYTHON_BASELINE_VERIFICATION.md)）**
  - **公式pytest実測：188件中186 PASS / 2 FAIL**（中間KB-SD-JWTのaud/nonce mismatchテストが`DID NOT RAISE`）、[GitHub Actions run #38121818162](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38121818162)。
  - **独立フルSDK負例：12 PASS**（署名付きterminal challenge、x5c root、Checkout binding、空Constraint、署名付きOpenのMerchant Constraint非開示）。先行ローカル限定11件も別にPASS。
  - **環境注意：** 公式uv.lockにはprivate registryの401があり、公式pyprojectの直接依存を公開PyPIで取得。推移的依存の完全lock再現ではない。
  - **結論：** 検証実績は得たがSDK全体は2件失敗。**Gem実装HOLDを継続**。このタスク完了はGOを意味しない。

- [x] **P0-5b：初期Fail Closed ProfileとGO/HOLD再判定（完了：[FAIL_CLOSED_PROFILE.md](FAIL_CLOSED_PROFILE.md)、[RESEARCH_DECISION.md](RESEARCH_DECISION.md) §9）**
  - **対象**：Autonomous/単一AgentのOpen→Closed、2hopのみ。HostがIssuer/merchantの信頼鍵、terminal aud/nonce、制約の開示完全性、正本Checkout JWTとhashを供給・検証する。1つでも不明ならRejection。
  - **CONDITIONAL GO**：非本番・オフラインのRuby技術PoCに限る。汎用Gem/公開API/ProductionはHOLD/NO-GO。文書マージで自動的に実装を開始しない。
  - 実署名SD-JWTのMerchant制約非開示、intermediate aud/nonce公式テスト失敗を考慮し、曖昧な入力や中間hopは初期PoCで明示的に拒否。

- [x] **P1-0：Ruby署名・Schema・Hashのオフライン互換性Spike（完了：[RUBY_FEASIBILITY_SPIKE.md](RUBY_FEASIBILITY_SPIKE.md)）**
  - Ruby 3.3.12、`jwt 3.3.0`、`json_schemer 2.5.0` で **14 runs / 17 assertions / 0 failures / 0 errors / 0 skips**。[GitHub Actions実行](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38123249933)。
  - Python cryptographyで署名した**合成**ES256/JWK fixtureをRubyで検証。Checkout SHA-256 hash一致、公式AP2固定Schemaの`contains`や必須項目/型の限定検証を実行。
  - **AP2本物のSD-JWT Delegationは未実装**。今回のCI成功はRuby GemやAP2適合性を意味しない。

- [x] **P1-1：実署名SD-JWT Root / Disclosure digest・厳格Merchant開示プロフィールのRuby研究（完了：[RUBY_SDJWT_RESEARCH.md](RUBY_SDJWT_RESEARCH.md)）**
  - 固定AP2 v0.2 SDKの`MandateClient.create`で実署名Open Rootを生成。RubyのIssuer署名検証と`delegate_payload`/Constraint disclosure digestの整合を確認。
  - **10 tests、22 assertions、0 failures**（[GitHub Actions](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38123828122)）。Merchant制約非開示、署名/Disclosure改ざん、wrong key、重複/無関係Disclosureを拒否。
  - **対象は厳格な合成Issuerレイアウトだけ。** 全SD-JWT規格準拠や隠れた制約全般の不存在を証明しない。

- [x] **P1-2：Ruby Open Root→Terminal Agent 2hop BindingのオフラインSpike（完了：[RUBY_DELEGATION_SPIKE.md](RUBY_DELEGATION_SPIKE.md)）**
  - 公式Python SDK固定v0.2でOpen Root + Agent署名Terminal Closedを生成・Pythonチェーン検証し、RubyでもHostのIssuer/Agent鍵、Terminal署名、`sd_hash`、期待`aud`/`nonce`を検証。
  - **Ruby P1-2：15 runs / 32 assertions、0 failures**、**P1-1 Root回帰：10 runs / 22 assertions、0 failures**。[Actions run #38124823804](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38124823804)。
  - 署名済みのwrong holder/root、チャレンジ不一致/未指定、3hop、intermediate、非開示Merchant、未対応hash mode等を拒否。**Merchant-signed Checkout JWTは未検証（ダミー）**。Gemと一般AP2互換は未達。

- [x] **P1-3：Merchant署名済Checkout JWT・Host正本/HashとOpen制約のオフライン統合Ruby Spike（完了：[RUBY_CHECKOUT_BINDING_SPIKE.md](RUBY_CHECKOUT_BINDING_SPIKE.md)）**
  - 固定AP2 Python SDK生成の署名済Open→Closedと、独立MerchantがES256署名した架空Checkout JWTをRubyで検証。
  - **P1-3：18 runs / 40 assertions、0 failures**、P1-2回帰15/15、P1-1回帰10/10（[GitHub Actions #38126247946](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38126247946)）。
  - Merchant JWT署名、Host原文一致、Closed checkout_hash再計算、Merchant ID/SKU/数量/金額の厳格な1商品プロフィールを検証。**上流Pythonの必要数量2・Checkout数量1は違反0件**を観察したが、仕様違反と断定しない。
  - 取引は架空、最終購入許可/nonce消費/replay/Receipt/Gem/API/Productionは未実施。

- [x] **P1-4：研究コードのセキュリティ負債レビューとGem開発GO/HOLD（完了：[SECURITY_GAP_REVIEW.md](SECURITY_GAP_REVIEW.md)、[RESEARCH_DECISION](RESEARCH_DECISION.md) §14）**
  - 現行P1-1〜P1-3研究コードを静的レビューし、**S01〜S12の12ギャップとG1〜G6の受入れゲート**を優先順位付け。未実行負例と既存実測を区別した。
  - **GO候補：** オフライン負例研究P1-5のみ（別の承認が必要）。**HOLD：** 汎用Gem/API実装。**NO-GO：** RubyGems公開・Production/実決済。
  - P1-4自身では**CI/新しい攻撃実験/Gem実装なし**。前回のRoot/2hop/Checkout既存回帰は10/15/18テストPASSのまま。

- [x] **P1-5：本物の署名付きセキュリティ負例をテスト先行で観測（完了：[SECURITY_NEGATIVE_TESTS.md](SECURITY_NEGATIVE_TESTS.md)）**
  - 固定AP2 v0.2 Python SDKとMerchant実署名JWTを使用。**18ケース：GREEN 11（正例1/拒否10）/ RED 6 / HOST_BOUNDARY 1 / ERROR 0**。[CI #38127279271](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38127279271)。
  - **6 REDは残存:** 重複`merchant.id`、重複`alg`、Closed`exp`期限切れ、Closed内部未来`iat`、JWT想定外`typ`、未知Checkoutフィールドが、署名付き状態で不適切に受理。全AP2規格の脆弱性/実決済攻撃とは断言しない。
  - 既存P1-1回帰10/10、P1-2 15/15、P1-3 18/18成功。**検証器本体変更なし**。CI観測stepはREDで意図的に失敗、Artifact保全のためworkflowはsuccess扱いなので**「セキュリティ全部PASS」としない**。
  - Host原子的nonce/replay、Receipt、Issuer trust運用、一般的Decoy/Deep JSON/SD-JWT完全性は未検証。Gem/API/ProductionはHOLD/NO-GO。

- [x] **P1-6：署名付き6 REDの研究用対策と再検証（完了：[SECURITY_HARDENING_RESEARCH.md](SECURITY_HARDENING_RESEARCH.md)）**
  - 同じP1-5 18観測で**GREEN 17（正例1＋拒否16）/ RED 0 / ERROR 0 / HOST_BOUNDARY 1**、P1-1〜P1-3回帰**43件すべてPASS**。[Actions #38128152237](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38128152237)。
  - 重複JSON/JOSE、Closed内部iat/exp、Merchant JWT `typ`、未知Checkout fieldsを**研究用Strict Profile**に限定して拒否。署名済JWT原文/Hashの照合を維持。
  - **Host replay/nonce原子的消費未実装。** G1〜G6完全達成は主張しない。公開/汎用Gem/APIと本番実決済はHOLD/NO-GO。

- [x] **P1-7：Host Trust/VerifiedEvidence/Nonce契約・Clock/失効/Receipt責務（設計のみ完了）**
  - [HOST_SECURITY_CONTRACT.md](HOST_SECURITY_CONTRACT.md)で、Issuer/Agent/Merchant/BuyerのHost信頼・鍵用途とCheckout正本、Verifierの`VerifiedEvidence ≠ Host ALLOW`、nonce＋order-operationの**一回限りの原子性**、外部実行idempotency、失効・Clock・署名Receiptと障害STOPを文書化。
  - [HOST_SECURITY_TEST_PLAN.md](HOST_SECURITY_TEST_PLAN.md)で、HT01〜07（信頼7）、HC01〜07（文脈7）、HR01〜10（DB Replay/競合10）、HE01〜10（Evidence/Receipt10）の**計34件を将来テストとして設計**。
  - **34件とも実装・実行なし**。Host DB/原子的nonce消費/Receipt/実決済は未実装、Gem/API/ProductionはHOLD/NO-GO。P1-6の歴史的署名CI成功をHost安全性PASSとしない。

- [x] **P1-8：Host Replay/nonce競合の一時DB環境・試験計画（設計のみ完了）**
  - [HOST_REPLAY_LAB_DESIGN.md](HOST_REPLAY_LAB_DESIGN.md)でPG16・2独立worker・nonce CAS/Checkout unique・commit障害・Idempotency・費用/cleanupを選定。**Host新規実装/実行なし、34件NOT RUN**。
- [x] **P1-9a：PostgreSQL 16独立workerのReplay負例4件（限定研究・実測完了）**
  - [HOST_REPLAY_P19A_EVIDENCE.md](HOST_REPLAY_P19A_EVIDENCE.md)：HR01/02/03/08の4件を実PG16.9/Minitestで実行し108 assertions全成功。DB lock競合、CAS0件、Checkout UNIQUEと再送STOPを観測。**他30ケース未実行**。初回失敗も履歴として保存。
- [x] **P1-9b：独立worker SIGKILL（COMMIT前後）とHost復旧（限定研究実測完了）**
  - [HOST_REPLAY_P19B_EVIDENCE.md](HOST_REPLAY_P19B_EVIDENCE.md)でHR04/05の全Rollback/PENDING復元/再送STOP実測。回帰込み6/34件PASS、残り28件未実行。
- [x] **P1-9c：Unknown COMMIT応答/Mock Provider Idempotency（限定オフライン研究完了）**
  - [HOST_REPLAY_P19C_EVIDENCE.md](HOST_REPLAY_P19C_EVIDENCE.md)にHR06/HR07実測（2 runs/149 assertions）＋既存6回帰（192 assertions）を記録。34 Host中8件、残り26件未実行。実決済/実HTTPとの同等性は主張しない。
- [x] **P1-10a：HR10 Checkout失効/Buyer停止・version更新との競合（限定研究実測完了）**
  - [HOST_REPLAY_P110A_EVIDENCE.md](HOST_REPLAY_P110A_EVIDENCE.md)：正本HR10の4サブケースで実際のPGロック待ちを観測、4 runs/124 assertions成功。既存8 runs/341 assertionsもPASS。正本9/34件、残り25件未実行。外部失効源は未保証。
- [x] **P1-10b：HC06外部失効整合性の設計・試験マトリクス（実装/実測なし）**
  - [HOST_EXTERNAL_REVOCATION_HC06_DESIGN.md](HOST_EXTERNAL_REVOCATION_HC06_DESIGN.md)：R/C線形化問題とA〜E案、将来HC06-A〜H負例を整理。**HC06 NOT RUN**。
- [x] **P1-10c：HC06合成モデルでTOCTOUとfencing境界の比較（限定実測完了）**
  - [HOST_EXTERNAL_REVOCATION_P110C_EVIDENCE.md](HOST_EXTERNAL_REVOCATION_P110C_EVIDENCE.md)：8 runs/94 assertions PASS、うち2つは**脆弱な負例の再現成功**。真正な分散Authority/Host保証は**未試験**、正本HC06はFULL PASSではない。
- [x] **P1-10d：HC06外部Authority/Host予約・失効有効化・Host確定境界の設計（資料のみ完了）**
  - [HOST_EXTERNAL_REVOCATION_P110D_PROTOCOL.md](HOST_EXTERNAL_REVOCATION_P110D_PROTOCOL.md)：方式A〜F・障害13種・Authorityへの契約確認項目。実プロトコルも外部Authorityも実装していない。
- [x] **P1-10e（設計のみ完了・NOT RUN）**
  - [HOST_EXTERNAL_REVOCATION_P110E_TEST_PLAN.md](HOST_EXTERNAL_REVOCATION_P110E_TEST_PLAN.md)：P後のR_request、Host COMMIT ACK不明、予約timeout/遅延Cの3系統12ケースを計画。独立永続DB/障害注入/合否証拠・UNPROVENを定義。**実行なし、HC06 HOLD**。
- [x] **P1-10f（採否判断資料のみ完了・NOT RUN）**
  - [HOST_EXTERNAL_REVOCATION_P110F_HARNESS_DECISION.md](HOST_EXTERNAL_REVOCATION_P110F_HARNESS_DECISION.md)：E-R01/R02に絞り、Ruby別プロセス＋PG16別インスタンス×2を条件付き推奨。耐久abort強制・R_effective順序証拠・費用/隔離/cleanupを着手前ゲートとした。**実装/実測/CIなし・HC06 HOLD**。
- [x] **P1-10g（2限定独立合成ケースの実測完了）**
  - [HOST_EXTERNAL_REVOCATION_P110G_EVIDENCE.md](HOST_EXTERNAL_REVOCATION_P110G_EVIDENCE.md)：2 PG16.9インスタンス・別Ruby worker・Host abort後SIGKILL復旧とstale STOP。**2 runs/118 assertions PASS**、外部AuthorityとR/C原子性はHOLD。正本9/34件維持。
- [x] **P1-10h（設計レビューのみ完了・H01〜H12 NOT RUN）**
  - [HOST_EXTERNAL_REVOCATION_P110H_PROOF_BOUNDARY_REVIEW.md](HOST_EXTERNAL_REVOCATION_P110H_PROOF_BOUNDARY_REVIEW.md)：AuthorityがCoordinatorの無証拠finalizeを信じる実装上の穴、Host durable decision/gateのtrustとcontext束縛、偽造/再送/通信断/矛盾の12計画負例を整理。**新CI/コードなし、HC06 HOLD**。
- [x] **P1-10i（隔離合成H01〜H06実測完了／PR #30のmain反映はGitHubで再確認）**
  - [HOST_EXTERNAL_REVOCATION_P110I_EVIDENCE.md](HOST_EXTERNAL_REVOCATION_P110I_EVIDENCE.md)：初回JSON解析CI失敗→修正後**6 runs/178 assertions PASS**。H01は旧Authorityが失効後Host COMMIT可能な**危険反例**とguardのSTOP。H02〜H06限定PASS、Host署名/分散原子性はHOLD。PR #29（`c1df549f`）マージ後のmainにP1-10i変更だけを載せ直すPR #30上。
- [x] **P1-10j（Host DBを直接参照しない独立Authority採否レビュー・設計のみ完了）**
  - [HOST_EXTERNAL_REVOCATION_P110J_DECISION.md](HOST_EXTERNAL_REVOCATION_P110J_DECISION.md)：Hostの事前信頼・証拠認証・durable terminal gate・全C経路STOP/anti-rollback・外部AuthorityのP/R有効化契約の成立条件とFail Closedを比較。**新コード・CI・テストなし、HC06 HOLD。**
- [x] **P1-10k（Host/Authority契約C01〜C12のチェックリスト設計のみ完了）**
  - [HOST_EXTERNAL_REVOCATION_P110K_CONTRACT_CHECKLIST.md](HOST_EXTERNAL_REVOCATION_P110K_CONTRACT_CHECKLIST.md)：必要保証・担当候補・要求証拠・不明時の停止条件・相手先への質問を明記。**全件OPEN/UNCONFIRMED**、実Authority/Host契約の確認なし、CI/実装なし。
- [x] **P1-10l（固定AP2 v0.2.0公式仕様/SDKとの静的照合、実装・CIなし）**
  - [HOST_EXTERNAL_REVOCATION_P110L_AP2_SPEC_MAPPING.md](HOST_EXTERNAL_REVOCATION_P110L_AP2_SPEC_MAPPING.md)：公式Mandate/Checkout/ReceiptのSUPPORTED範囲、C01〜C12完全契約NOT SPECIFIED（照合範囲限定）、外部Authority能力UNKNOWNの根拠表。Host正本9/34・HC06 HOLD維持。
- [x] **P1-10m（責務分離・スコープ/GO-HOLD表の設計完了）**
  - [VERIFIER_VS_REVOCATION_P110M_SCOPE.md](VERIFIER_VS_REVOCATION_P110M_SCOPE.md)：AのVerifiedEvidence/Rejection、Merchant Hostの最終ALLOW/replay、BのHC06強失効、決済/Receiptと公開Gemを別責務に整理。非本番PoCは条件付き候補、**新実装GOなし**。B/HC06・Gem API・本番HOLD。
- [x] **P1-10n（狭いA-only合成PoCの採否・設計だけ完了）**
  - [VERIFIER_P110N_OFFLINE_POC_GATE.md](VERIFIER_P110N_OFFLINE_POC_GATE.md)：G01〜G08・AN-P01/AN-N01〜N07は**将来のテスト案、NOT RUN**。固定Issuer layout・完全開示・2hopだけにCONDITIONAL GO CANDIDATE、一般Issuer/disclosure・Host replay/B/HC06はHOLD。P1-10n新実装・CIゼロ。
- [x] **P1-10o（合成固定Issuer/2hop A-only実署名AN-P01＋AN-N01〜N07実測完了）**
  - [VERIFIER_P110O_EVIDENCE.md](VERIFIER_P110O_EVIDENCE.md)：[修正後CI #38154695155](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38154695155) **8 runs/45 assertions/0 errors/failures**。1限定正例、6拒否カテゴリ、AN-N07は**HOST_BOUNDARY**。前回#35 Codex P1のOpen→Closed共有claim保持漏れ修正を実署名の期限内Closed exp変更で確認。初回CIはPython結果一覧順の誤りでFAILし修正。**汎用Gem/API/本番/HC06はHOLD、決済・公開NO-GO。**
- [x] **P1-10p（残余Issuer/Constraintリスクの静的レビューだけ）**
  - [VERIFIER_P110P_RESIDUAL_GAPS](VERIFIER_P110P_RESIDUAL_GAPS.md)：GP01〜GP09、新実測なし。GP01未知ネストConstraintの潜在的見落としは静的疑義のみ。
- [ ] **P1-10q（次のおすすめ・明示承認後のみ）**
  - GP01の1合成署名負例で既存RubyがACCEPT/REJECTするか隔離観測する研究のみ。予期しない受理はRED/HOLD記録とし、修正実装は別承認。











### Phase 1 — 最小Checkout Mandate PoC【GO承認後のみ】

- [ ] 公式仕様に限定して、検証器の最小Ruby実装とUnitテストを作成。
- [ ] 信頼するIssuerと鍵はHostが指定。Mandate中の自己申告を無条件に信用しない。
- [ ] 検証結果は `Verified Evidence` を返す。最終的な業務操作の `ALLOW` を返すAPIにしない。

### Phase 2 — セキュリティ負例検証【PoC後】

- [ ] 署名改ざん、別Agentへの流用、対象サービス・期限・nonceの不一致、制約未開示/不一致を拒否する。
- [ ] Checkout内容（金額・通貨・Merchant等）と委任条件の照合を検証する。
- [ ] Replay、失効、巨大入力、ログ漏えい、二重決済への責務分担を明確にする。

### Phase 3 — 相互運用・OSS公開判断【検証後】

- [ ] 公式Python SDKとの正例・負例の相互運用テストを実施。
- [ ] 公式との差分を報告・整理し、CI、サポートmatrix、セキュリティポリシー、依存関係、ライセンスを確認。
- [ ] 実施範囲に見合う公開可否を判断。`AP2 compliant`、`production ready` を根拠なしに主張しない。

各Phaseの全体計画は [RESEARCH_PLAN](RESEARCH_PLAN.md)を正本として参照し、本書で設計を二重管理しない。

## 4. 守るべき原則

1. **仕様優先：** AP2 v0.2の一次資料を正本とし、SDKの挙動と仕様が異なる場合は差分を記録する。現行のタグ/Commitを固定する。
2. **小さなOSS：** AP2フルスタック、決済、Wallet、認証サービス、MCP/A2A transportを作らない。
3. **安全性：** 未検証のIssuer・自己申告権限・Mandate内の鍵を信用しない。形式不正や不明な重要制約はFail Closed。
4. **責務分離：** 署名・委任証明検証と、Hostのユーザー権限・商取引・決済・Replay防止を分離する。
5. **現実的な進捗：** ユーザーの「OK」は次の**1タスク**の承認として扱い、未承認の機能実装や公開を先行しない。
6. **出典と記録：** 重要な結論はURL/節/版/Commit SHAを残す。推測・提案・確認済み事実を区別。
7. **検証と報告：** 変更ファイル、Commit SHA、CI/テスト結果、未解決事項、次の1項目を報告する。存在しない検証結果を記載しない。

## 5. 追跡する公式情報

詳細は [OFFICIAL_SOURCES](OFFICIAL_SOURCES.md)。

- AP2 specification: https://ap2-protocol.org/ap2/specification/
- AP2 Agent Authorization: https://ap2-protocol.org/ap2/agent_authorization/
- AP2 Checkout Mandate: https://ap2-protocol.org/ap2/checkout_mandate/
- AP2 official source / Python SDK: https://github.com/google-agentic-commerce/AP2
- FIDO Alliance Agentic AI: https://fidoalliance.org/fido-alliance-agentic-ai/
- IETF SD-JWT RFC 9901: https://www.rfc-editor.org/rfc/rfc9901.html

## 6. 次のチャットで最初に行うこと

**P1-10pの静的Gapレビューまで完了。次はP1-10q（別承認）**。最新のGitHub main/Open PR/Issueとレビュー結果を確認し、[GP01〜GP09残余リスク表](VERIFIER_P110P_RESIDUAL_GAPS.md)→[P1-10o実測](VERIFIER_P110O_EVIDENCE.md)→[P1-10n限定条件](VERIFIER_P110N_OFFLINE_POC_GATE.md)→[正式判断§36](RESEARCH_DECISION.md)を読む。§36は既存HOLD判断の正本で、P1-10p専用Gap表は新たな実装GOではない。

- **今の問題：** RubyはOpen/Closedトップレベルの許可キー集合を厳格チェックするが、既知Constraint内部の追加フィールド集合までは網羅していない可能性がある。GP01は静的疑義で、今回新実験NOT RUN。公式AP2 v0.2.0基準SHA `b4587ac1d055888a73b4b21750973cffba961793`。
- **次の一件 P1-10q（ユーザー明示承認後のみ）：** 既知`checkout.allowed_merchants`に未知`policy_override`を含む架空のIssuer署名Rootを生成し、Disclosure digest/署名とAgent署名Closedを独立確認して、現行Ruby研究Verifierが受理するか拒否するかを**1件だけ専用の隔離CIで観測**。不適切なACCEPTなら**RED/HOLD**、修正・Gem化は別承認。
- **守る証拠境界：** P1-10oのAN-P01＋AN-N01〜N07 **8 runs/45 assertions**（うちN07 HOST_BOUNDARY）。Host正本**9/34・25 NOT RUN**、P1-10iのH01旧Authority危険反例、C01〜C12外部契約OPEN、H07〜H12 NOT RUN、公式Python intermediate hop186 PASS/2 FAIL。Bの強いHC06失効保証HOLD。
- **禁止：** 実Issuer/Authority、GCP、実Checkout/決済/Provider/Receipt、Gem/Public API、RubyGems公開、他OSS変更。P1-10qのテストも明示承認なしに実行しない。

### 次のチャットに渡す指示文

```text
ap2-mandate-verifier P1-10qの限定研究を検討します。
https://github.com/cuichangquan/ap2-mandate-verifier

まずGitHub最新main、Open PR/Issue、Codexレビューを確認。
docs/VERIFIER_P110P_RESIDUAL_GAPS.md
docs/VERIFIER_P110O_EVIDENCE.md
docs/RESEARCH_DECISION.md §36を読む。

P1-10pは新テスト・コード・CIなしの静的Gapレビューを完了。
GP01はIssuer署名された既知Constraint内部の未知fieldを
Rubyが見落とし得る静的リスク仮説であり、攻撃成功未実測。
固定AP2 v0.2.0 commit:
b4587ac1d055888a73b4b21750973cffba961793。

ユーザーが明示承認した場合だけ、GP01一件の合成オフライン
正署名負例を観測。Issuer/Agent署名とDisclosureの整合性を
独立に確かめた上で現行RubyのACCEPT/REJECTを記録し、
不適切なACCEPTはRED/HOLDとする。修正は別承認。

P1-10o過去8 runs/45 assertions、N07 HOST_BOUNDARY、
Host正本9/34・25 NOT RUN、外部HC06 HOLDを維持。
本番/Gem API、GCP、実決済、署名Receipt等は禁止。
```
