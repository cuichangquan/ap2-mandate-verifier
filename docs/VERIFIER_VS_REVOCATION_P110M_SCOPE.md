# P1-10m — VerifierとHost/Authority強失効を分離するスコープ・GO/HOLD表

**2026-10-12 JST / DESIGN DECISION ONLY / NOT RUN / NO PUBLIC API.** [P1-10l公式AP2 v0.2.0照合](HOST_EXTERNAL_REVOCATION_P110L_AP2_SPEC_MAPPING.md)、[P1-10k C01〜C12契約表](HOST_EXTERNAL_REVOCATION_P110K_CONTRACT_CHECKLIST.md)、[P0-4 API案](API_PROPOSAL.md)、[Host契約](HOST_SECURITY_CONTRACT.md)を前提に、**A. Merchant側Checkout Mandate暗号Verifier** と **B. Host/Authority間の強い分散失効・注文確定制御** を**別責務**にする。決定は**分離方針への設計合意だけ**で、Gem・public API・最小Ruby PoC実装の開始承認ではない。

公式固定基準：AP2 v0.2.0 commit `b4587ac1d055888a73b4b21750973cffba961793`。AP2のMerchant側Mandate verification/Checkout JWT hash/constraints/Receipt義務は規定される。一方、研究用`P / R_request / R_effective / finalize_abort / C_DURABLE`は**AP2公式Authority APIではない**。実Authority提供能力はUNKNOWN。

## 1. 一枚のスコープ表（設計候補：まだ実装しない）

| 境界と所有者 | **対象** / Verifierが返せるもの | **Verifierが行わない**こと | 次段階に進めるために必要な証拠 / 現在判定 |
| --- | --- | --- | --- |
| **A. Ruby Checkout Mandate Verifier（候補）** | Merchantが渡す**既知の信頼Issuer/鍵/期待audience・nonce/時刻・原文Checkout JWT/鍵・制約評価policy**に対し、固定v0.2の`vct`、SD-JWT署名/chain、`cnf`とPoP、hash・disclosure・open→closed constraints、merchant-signed Checkout JWTと最新正本hashを検証。出力は**VerifiedEvidence / Rejection（設計名、未確定）** | **ALLOW、支払い、Receipt発行、失効確定、nonce消費、stateful budget、ネットワーク照会、公開Trust anchorの自動登録は行わない**。「Verified」は現在の購入を許可した意味ではない | **狭い隔離非本番PoCなら条件付き検討可能**。P0-5bの過去の`CONDITIONAL GO`は**範囲限定の研究判断**であり、今回改めて実装GOを出さない。Python↔Rubyの正負互換、必要開示の完全性、key binding、Fail Closedの証拠を先にレビュー |
| **Aを呼ぶMerchant Host（必須の別層）** | どのIssuer/merchant/Agentを信用し、Checkoutの最新状態・価格・在庫・金額/通貨・業務ID・ユーザー関係を判定するかを所有。`VerifiedEvidence`受領後も**host-side policy、atomic replay nonce、durable operation/outbox、注文最終ALLOW/STOP**を管理 | Verifierへ**商取引の最終判断**やnonceの原子的更新を丸投げしない。署名PASSで自動決済しない | Host正本テスト**9/34件実測、25 NOT RUN**。N17 replayのHost境界ほか未完了。Host管理責務を将来PoCの仕様上の**明示的な外部前提**とする |
| **B. Host↔独立Authority強い失効／HC06（別研究トラック）** | Host terminal COMMIT/ABORTとAuthorityの`P/R_request/R_effective`を整合させ、全C経路の排他的durable gate、真正なHost durable proof、ロールバック防止、unknown/partition時のPENDING/STOPを実現できるかを研究 | **Aの暗号Verifierに内包しない**。形式上の署名済`ABORTED`、Coordinatorの`finalize_abort`、AP2 Checkout Receiptで安全確定したと主張しない | **HOLD**。C01〜C12全件**OPEN/UNCONFIRMED**。AP2固定版にはこの**完全な外部失効協調契約はNOT SPECIFIED（照合範囲）**。H01で旧Authorityの`R_effective`後Host C成功という**危険反例** |
| **決済・Checkout Receipt・外部Provider（Gem外）** | Merchant/MPP/CP/Providerの責務としてCheckout実行・Payment Mandate/トークン・実支払、Receipt署名発行・返金/取消、監査を管理 | Ruby Verifierを**決済実行者、Wallet、Issuer、Trusted Surface、MCP/A2A transport**として扱わない | **Production / payment / Receipt発行 NO-GO**。AP2のReceipt構造はHostのdurable ABORT証明ではない |
| **汎用Gem・安定Public API／リリース（現時点で存在しない）** | **将来の採否対象**。最小PoCとセキュリティ・相互運用が成立してから公開範囲/依存関係/サポートmatrixを判断 | この表をもって`AP2 compliant`・`production ready`・公開API確定・RubyGems配布を主張しない | **HOLD**。Gem/API/本番統合を許可しない。先に非本番研究成果と負例・独立レビュー/残課題の明示が必要 |

**この表の意図:** 「Aの暗号証拠は妥当」→「Hostは購入してよい」→「外部Authorityの失効も保証済み」→「決済成功」という**誤った昇格を各境界で切断**する。**HC06がHOLDだからAの研究価値がない**とは言わない一方、**BをGemから外せばAが本番安全になる**とも言わない。Hostの失効・replay・支払判断が未保証なら本番の購入許可はSTOPする。

## 2. PoCと公開の採否ゲート（本Stepでは採否変更なし）

| 対象 | 今回の判定 | 次のレビューで提出を要するもの |
| --- | --- | --- |
| **Aの狭い非本番Ruby PoC** | **CONDITIONAL RESEARCH CANDIDATE / IMPLEMENTATION NOT AUTHORIZED** | 公式固定PythonとRubyの限定signed fixture相互運用、Trust root固定・失敗時拒否、`vct`/alg/PoP/`aud`/`nonce`/日時、制約**完全性を観測できる範囲**、Host正本Checkout JWT署名・原文・hash、未知/非開示の安全条件はSTOP。独立したPoC作業の明示承認 |
| **Aの広いGem/API** | **HOLD** | 安定API・許可するDirect/Autonomous/任意hop等の境界、脆弱性負例、依存・Ruby matrix、公開前の相互運用証拠、未解決upstream/SDK差分とHost責務の開示 |
| **Bの厳密な外部失効機構（HC06）** | **HOLD** | C01〜C12契約・実Authority能力、Host全C経路強制・耐久/anti-rollback・署名proofの真正性、別プロセス/別DBレース・partition・ACK喪失・復旧。未知なら`R_effective`保留 |
| **Production/GCP/決済/RubyGems/署名Receipt** | **NO-GO / NOT AUTHORIZED** | 本Step対象外、別途明示承認と個別安全判断を要する |

**非本番限定とは:** 合成・偽データで境界を研究することであり、Merchantの現実の購入を実行することではない。P0-5bの旧`CONDITIONAL GO`はP1-0以降の隔離spikeを許す当時の個別判断（[RESEARCH_DECISION `9](RESEARCH_DECISION.md)）。後続の研究で新たな境界が判明し、**現行のGem/API・本番統合HOLD**を覆さない。現在の新規PoC着手は別途明示承認が必要。

## 3. 残るエビデンスと誤解防止

- Host正本**9/34実測・25 NOT RUN（従来12 runs/465 assertions）**。P1-10c Mutex合成**8 runs/94 assertions**、P1-10g独立PG16合成**2 runs/118 assertions**、P1-10i独立PG16合成**6 runs/178 assertions**は**別枠**で、正本実測件数に加算しない。H01の旧方式で`R_effective`後Host Cが成功したのは**危険反例**、防御済みの本番実装を意味しない。
- **H07〜H12 NOT RUN、N17 stateless replay HOST_BOUNDARY、P1-4 G1〜G6/P1-7 T1〜T5未解決、固定公式Python SDK intermediate hop 186 PASS / 2 FAILも未解決**。署名検証があることと完全な安全検証は別。
- [P1-10l](HOST_EXTERNAL_REVOCATION_P110L_AP2_SPEC_MAPPING.md)の分類は、A向けMandate/Checkout/Receiptの公式義務がSUPPORTED、B向けC01〜C12全体は固定ソース照合範囲でNOT SPECIFIED、商用Authority APIはUNKNOWNという**限定的な静的調査**。
- **本Stepは設計文書のみ**。Ruby/Gem/API・DB・CI/テスト・GCP・外部サービス・決済・署名Receipt・他OSS変更は**0件**。安全性の新実測は**0**。自己レビューは独立した安全監査ではない。

**最終判断:** **AとBの責務分離を設計上採用する**。これはAの実装GOではない。**Aの限定非本番研究は次の明示承認を待つ、B/HC06 HOLD、汎用Gem/public API・本番Host統合HOLD、RubyGems公開/Production/実決済/署名Receipt NO-GO**。

**次のおすすめ1件（別途ユーザーの明示承認後のみ）:** **P1-10n — Aだけの非本番PoC再開可否の採否レビュー（設計のみ）**。固定AP2 v0.2に基づく最小の正負fixture、制約開示完全性、Issuer trust、Agent PoP、Checkout JWT原文・hash、および先行Ruby研究結果を一覧化し、残るブロッカーを**GO/HOLD/NO-GOの判定条件として整理**する。実装・CI・GCP・外部API・決済・Gem配布には進まない。
