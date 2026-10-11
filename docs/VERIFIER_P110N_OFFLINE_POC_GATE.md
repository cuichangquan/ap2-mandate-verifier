# P1-10n — A（Merchant Checkout Mandate Verifier）限定・非本番PoC再開の採否

**2026-10-12 JST / DESIGN-ONLY GO–HOLD REVIEW / NO TESTS RUN / NOT AN IMPLEMENTATION AUTHORIZATION**

[P1-10m責務分離](VERIFIER_VS_REVOCATION_P110M_SCOPE.md)で切り出した**A：Merchant側の暗号的なCheckout Mandate証拠検証**だけを対象に、[P0-5bのFail Closed Profile](FAIL_CLOSED_PROFILE.md)、[P1-1〜P1-6のRuby実測](RUBY_SDJWT_RESEARCH.md)、[公式Python SDK実測](PYTHON_BASELINE_VERIFICATION.md)を根拠として、「**何を狭く検証する研究なら前進可能か／何が未解決なら停止すべきか**」を再審査した。**このStepでRubyコード・既存研究テスト・CI・DB・外部サービス・GCP・決済・秘密鍵・Gem/API/公開物は新規作成/変更/実行しない。**

公式AP2 v0.2.0固定基準：\`b4587ac1d055888a73b4b21750973cffba961793\`。本OSSは独立した研究であり、公式SDK互換・AP2適合・実運用の安全性を認証するものではない。

## 1. 最新の判定（対象を混同しない）

| 対象 | P1-10n判断 | 意味 |
| --- | --- | --- |
| **A：合成fixtureに限定した非本番Ruby研究PoCの次の小実験** | **CONDITIONAL GO CANDIDATE / 別途明示承認が必要** | 既知Issuer＋既知公開鍵、単一Agentの正確にOpen→Closed **2hop**、Issuer発行レイアウトを**信頼できる研究用fixtureで固定**、必要制約が完全開示されるケースに限定。下のG01〜G08を明示的に検査し、条件に適合しない入力は拒否/STOP。**今回は実装していない** |
| **A：任意Issuer/汎用SD-JWT/Direct/3hop・任意Constraintへの一般化** | **HOLD** | hidden/unknown/decoy制約の一般的な完全性、非固定layoutの主体認定、公式Python中間hop \`aud/nonce\` 差分が未解決。限定研究で安全と示しても一般化しない |
| **A：安定Gem／Public API、RubyGems公開、本番Merchant統合** | **HOLD / 公開NO-GO** | Host最終ALLOW/nonce原子消費、規格・相互運用範囲、公開安全ゲートが未確定。PoC通過だけでは許可しない |
| **B：Host↔独立Authorityの強い失効HC06** | **HOLD** | Aの静的な暗号証拠を検証しても、HostのCOMMIT/ABORT durable gate、外部 \`R_effective\`、anti-rollbackを証明しない |
| **GCP、実Checkout/決済、Provider、署名Receipt** | **NO-GO / 未承認** | 本OSSの隔離研究対象外 |

**P0-5b §9の旧CONDITIONAL GOは小さなオフライン技術Spikeに限った履歴**で、Gem/安定API・ProductionへのGOではなかった。P1-10nは研究を**続ける余地がある**との設計判断のみ。**次の具体的なコード／CI実験は再度ユーザーの明示承認が必要。**

## 2. 一次実測の対応表：成功した部分と未証明部分

| 層／証拠 | 実際の過去の観測（*新規実行ではない*） | P1-10nで許される解釈／限界 |
| --- | --- | --- |
| Ruby JWS/JWK・Hash・Open JSON Schema | [P1-0](RUBY_FEASIBILITY_SPIKE.md)：**14 runs / 17 assertions、失敗0**。ES256とOpen Schema \`contains\` の基礎を検証 | 固定1プロファイルの暗号部品が動く証拠。全Checkout/chainの安全性ではない |
| Ruby Root SD-JWTとDisclosure | [P1-1](RUBY_SDJWT_RESEARCH.md)：**10 runs / 22 assertions、失敗0**。Issuer署名・Root disclosure digest、Merchant制約の非開示拒否 | **限定Issuer layout**の完全開示のみ。一般的な選択的開示の権限完全性は未証明 |
| Ruby Open→Closed（2hop） | [P1-2](RUBY_DELEGATION_SPIKE.md)：**15 runs / 32 assertions、失敗0**。Agent \`cnf\`・Terminal署名・\`sd_hash\`・期待aud/nonce・3hop拒否 | 同じAgentの限定2hopだけ。中間hop/別hash mode/Directは対象外 |
| Ruby Merchant署名Checkout/hash | [P1-3](RUBY_CHECKOUT_BINDING_SPIKE.md)：**18 runs / 40 assertions、失敗0**。原文JWT・Merchant署名、閉じたMandateのhashとHost正本、SKU/数量等の研究用厳格照合 | Checkoutの現実の価格・在庫・最終許可、未知フィールドの規格全互換性は未証明。**数量の意味判定と公式Python evaluatorの差**は記録済み |
| 負例の失敗→限定修正 | [P1-5](SECURITY_NEGATIVE_TESTS.md)：合成signed負例 **6 RED / 11 GREEN / 1 HOST_BOUNDARY**（N17二重stateless verify）。[P1-6](SECURITY_HARDENING_RESEARCH.md)で同じ18例を再実測：**17 GREEN / 0 RED / 0 ERROR / 1 HOST_BOUNDARY**、既存P1-1〜P1-3 **43件回帰成功** | 修正対象は二重JSONキー、JOSE header、Closed内部時刻、\`typ\`、未知Checkoutフィールドの6例。**G1〜G6全達成ではない**。N17はVerifierの責務ではなくHostのatomically-consumed nonce境界 |
| 固定公式Python SDK | [P0-5a](PYTHON_BASELINE_VERIFICATION.md)：公式pytest **186 PASS / 2 FAIL**（intermediate hop \`aud/nonce\` のコードとテストの期待差）；追加signed負例12 PASS | 上流の一般的な欠陥と断定しない。今回は**中間hopをすべて非対応**とすることでのみこの曖昧さを境界外に置く |
| Host側と外部失効 | [Host正本計画/記録](HOST_SECURITY_TEST_PLAN.md)：**9/34件実測・25 NOT RUN、12 runs/465 assertions**。[P1-10i](HOST_EXTERNAL_REVOCATION_P110I_EVIDENCE.md)別PG16合成**6 runs/178 assertions** | どちらもAのVerifier適合性に混ぜず、Host本番許可も証明しない。P1-10i **H01は旧Authorityが\`R_effective\`後もHost COMMITできた危険反例** |

**過去の数値を「全部でX件のVerifier安全PASS」に加算しない。** P1-10c単一process合成8 runs/94 assertions、P1-10g別PG16合成2 runs/118 assertionsもHost/HC06用の別研究。未解決のH07〜H12、N17 HOST_BOUNDARY、P1-4 G1〜G6とP1-7 T1〜T5、Python公式2 FAILを削除しない。

## 3. A限定PoCのゲート／未達時のSTOP（すべて設計上の期待値で新規PASSではない）

| Gate | 限定PoCの必須前提・検証要件 | 既存根拠 | **未達・不明なとき** |
| --- | --- | --- | --- |
| **G01 Issuer trust** | Hostが事前承認した**単一Issuer identity＋公開鍵＋用途＋tenant/profile**だけを使用。\`kid\`/issuer URL/自称\`x5c\`をtrust anchorへ昇格させない | P0-5a自己署名\`x5c\`と異なるtrust rootの負例、P1-0/P1-2 wrong key拒否 | **REJECT / HOLD**。実Issuer認定は対象外 |
| **G02 署名・chain・PoP** | 公式v0.2のstrict Open→Closed **2hopのみ**。署名、前hop \`cnf.jwk\`、Root/Terminal文脈、\`sd_hash\`、披露digestを**元wire**から検証。\`issuer_jwt_hash\` mode/Direct/3hopは非対応 | P1-1/P1-2 signed fixture、P1-6回帰 | **REJECT**。未実装モードを黙認しない |
| **G03 Constraint完全性／最重要BLOCKER** | 研究対象のIssuer発行layoutと**必要な制約の完全開示が信頼できる独立fixture定義から確定**できる場合だけ受理。可視0件を成功とせず、未知・隠れたMerchant/権限制約、デコイと本物の区別が曖昧なlayoutは非対応。**元Issuerが発行した全Constraintが開示されたと一般的に証明する方法は未実証** | P0-5aで署名済Merchant制約の非開示が可視評価で通る例、P1-1/P1-2研究用固定layoutの拒否 | **REJECT / PoC HOLD**。署名PASSや「見えている制約だけOK」を安全PASSとしない |
| **G04 時刻・challenge** | Root/Closed内部/terminalの期限・\`iat\`、時計注入と最大TTL、Host必須の非空\`aud\`/\`nonce\`が一致。単なるtimestampやnonce一致では**一回限りの使用**にならない | P1-2、P1-5のN03/N04 RED→P1-6 GREEN | **REJECT**。nonceの原子的消費はHost側 |
| **G05 JOSE/JSON安全性・DoS** | 安全なES256 alg/typ allowlist、payloadとprotected headerの厳密JSON（重複キー拒否）、最大size/depth/segment/例外の失敗側停止 | P1-6はN01/N02/N05/N07等の**限定6件**の改善、深いJSON・Unicode・その他Headerは未実測 | **REJECT / UNKNOWNならHOLD**。広い入力/General-purpose APIは対象外 |
| **G06 Checkout真正性／hash／意味** | Hostが渡す**最新のMerchant署名Checkout JWT原文**と鍵、Closedから抽出したJWT原文が一致、ES256真正性と独立SHA-256、open constraintsのmerchant/SKU/line item/数量を厳密照合。数量評価の公式SDKとの差を記録し非互換を曖昧にしない | P1-3 signed Checkout 18件。公式SDK evaluatorとの数量差あり | **REJECT / 意味不明ならHOLD**。価格・在庫・税・支払判断はHost |
| **G07 Ruby↔固定Python一致範囲** | **同一の限定signed positive/negative fixture**で、発行・検証と期待Rejectionの段階／理由を並べる。独自Ruby strict policyと公式SDKの「見えるConstraint」挙動差を**期待差分として別記**。公式pytest2 FAILを隠さない | P0-5a、P1-1〜P1-3、P1-6個別CI証拠 | **HOLD** if unexplained false acceptance / unsupported modeを受理 |
| **G08 結果の意味／Host境界** | 出力は研究用の\`VerifiedEvidence\`または\`Rejection\`候補のみ。\`ALLOW\`やPurchase/Receipt/Paymentではない。同じ有効chainの2回verifyはHostの原子的nonce消費なしに購入を許可しない。内部生JWT/秘密鍵/PIIのログ出力禁止 | [API_PROPOSAL](API_PROPOSAL.md)、N17 HOST_BOUNDARY、Host正本9/34 | **NO BUSINESS ALLOW / HOST STOP**。B/HC06や支払成功へ昇格しない |

**重要な区別：** G01〜G08は「次の限定実験でどう受理/拒否を判定するか」の条件表であり、**G01〜G08に新しいPASSを付与したものではない**。先行の[SECURITY_GAP_REVIEW](SECURITY_GAP_REVIEW.md)の**G1〜G6やHost T1〜T5の完了判定を上書きしない**。同名の既存証拠を新たに数えない。

## 4. 次の単一実験が許可された場合の限定受入マトリクス（提案、全件 NOT RUN）

ここでの\`AN-P*\`/\`AN-N*\`は**将来のA-only受入試験案**。**テスト実行IDではなくすべてNOT RUN**。実験に進める場合も対象は**一つのIssuer固定layout、2hop、単一架空Merchant/Checkout、公開鍵のみを記録した合成signed fixtures**。SDK固定commit・Ruby依存バージョンをピンし、\`research/\`内の非本番コードだけを利用。正式API・Gem雛形・DB/GCP・決済なし。

| 提案ID | 合成入力／期待値 | 安全性の境界 |
| --- | --- | --- |
| **AN-P01** | Issuerが事前承認された、**完全開示・正しい2hop・正しいCheckout JWT/hash** → 限定\`VerifiedEvidence\`候補 | **Issuer layout完全性を外部テスト作成過程で知っている**ことを前提にする。一般Issuerでは未証明 |
| **AN-N01** | Issuer署名は正しいがMerchant制約または第3権限制約が非開示 → \`Rejection\` | G03、見えるConstraintだけで成功禁止 |
| **AN-N02** | 正署名だが別Issuerの鍵/identity、自己申告の鍵 → \`Rejection\` | G01 |
| **AN-N03** | 3hop／別Agent／\`issuer_jwt_hash\` → \`Rejection\` | G02、公式Pythonの中間hopの曖昧さを迂回 |
| **AN-N04** | \`aud\`/\`nonce\`違い・Host期待値なし・Root/Closed期限切れ・未来\`iat\` → \`Rejection\` | G04 |
| **AN-N05** | JOSE/payload重複JSONキー、予期しない\`typ\`／alg、巨大/深い入力 → \`Rejection\` | G05 |
| **AN-N06** | 別Checkout JWT、偽Merchant署名、hash不一致、数量不足、未知有効Checkout項目 → \`Rejection\`（固定profileの既知条件） | G06。公式SDKと数量解釈の差を記録 |
| **AN-N07** | 同一valid tokenを2回verifyし、暗号部分は両方validでも**HostのALLOWを一切発行しない** | G08／N17。Host replay耐久性を試験済みと主張しない |

**失敗条件:** 不適切な受理（false acceptance）1件でもあれば実験結果を**RED/HOLD**とし、都合のよいテストだけをPASSと呼ばない。fixtureを失敗に合わせて根拠なく変更しない。署名fixtureの実行時秘密鍵はコミットしない。CI実行を後で承認する場合は**限定workflowのみ・事前依存固定・費用小・証拠保持短期**。

## 5. Go/HOLD判断・残りの未検証・次の一件

**P1-10n判断：Aの限定、合成・非本番・研究用次実験のみCONDITIONAL GO CANDIDATE（別途承認待ち）。** 過去P1-0〜P1-3の実署名基礎、P1-6のRED改善から、狭い固定layoutなら実装実験する研究価値はある。しかしIssuer layout完全性を**固定fixtureの外に一般化した時点でHOLD**。一般的なIssuer trust・別Agent/Direct/多hop、外部失効HC06、Host replay/Receipt/本番支払を「解決」とは扱わない。

**現実の実装／公開許可：** 今回は**新PoCのコード/CI実行はしない**。ユーザーが次実験の対象と禁止事項を個別に明示承認するまでは**実装未承認**。汎用Gem/public API・本番Host統合**HOLD**、RubyGems公開・Production・実決済・署名Receipt**NO-GO**。B/HC06強い外部失効**HOLD**、C01〜C12すべてOPEN/UNCONFIRMED。

**未解決のまま保持：** 正本Host **9/34件・25 NOT RUN、過去12 runs/465 assertions**。P1-10c 8 runs/94 assertions、P1-10g 2 runs/118 assertions、P1-10i 6 runs/178 assertionsは**別証拠**。H01旧Authorityの\`R_effective\`後Host C成功は**危険反例**、H07〜H12 NOT RUN、N17 HOST_BOUNDARY、P1-4 G1〜G6/P1-7 T1〜T5、公式Python **186 PASS / 2 FAIL**が未解決。**本Stepの新コード・テスト・CI・外部通信・GCP・決済は0。**

**次のおすすめ1件（別途明示承認後のみ）：P1-10o — A-onlyの最小合成オフライン受入試験**。上表の**AN-P01＋AN-N01〜N07**だけを対象に、既存\`research/\`のコードを可能な限り再利用して、Issuer/Agent/Merchant実署名fixtureとRuby Fail Closedの**限定的な統合再実測**を行う。公式SDKコミットをピンし、PRと専用CIで実測を記録し、**新しいGem/public API/本番接続・外部Authority/GCP・実決済を行わない**。本Stepでは開始しない。