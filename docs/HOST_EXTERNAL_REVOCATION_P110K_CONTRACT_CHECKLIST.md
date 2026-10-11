# P1-10k — 独立Authority / Merchant Host間の安全契約チェックリスト

**2026-10-11 JST / DESIGN + CONTRACT DISCOVERY ONLY / NOT RUN。**

目的：独立運営のAuthorityがHost DBを直接読めない状況で、[P1-10jの条件付き研究判断](HOST_EXTERNAL_REVOCATION_P110J_DECISION.md)を**相手方に質問できる契約・責務・要求証拠・未達時のSTOP条件**に落とす。APIや実装仕様を確定するものではない。公式AP2 v0.2.0固定基準は commit `b4587ac1d055888a73b4b21750973cffba961793`（変更しない）。ここでいう`P / R_request / R_effective / finalize / Host decision`は**本OSSの研究用Host協調モデル**であり、AP2公式に存在する標準API・署名Receiptと主張しない。

**スコープ：文書のみ。** 実Authority/Host/Issuerへの照会・接続、署名鍵の作成、Rubyコード、DB、テスト、CI、GCP、決済、Gem公開、他リポジトリの操作なし。**以下のすべての外部相手の回答・運用証拠は未取得（UNCONFIRMED）。** 紙のチェックリスト完成と安全性検証完了は違う。

## 1. 一枚で使う判定ルール

- **CHECKED**：要求が実環境の設計・障害復旧・試験証拠で確認済み。契約文書に書くだけでは足りない。
- **OPEN**：必要条件の実現方法・責任者・証拠が未確定。今回の**全項目はOPEN**。
- **BLOCKED**：不成立、証拠拒否、検証不能、または責任者が不明。**R_effectiveを進めない**、本番適用はHOLD。
- **N/A**：責任者と理由を記録したうえで、安全条件に影響しないと検証できた場合のみ。基幹安全項目を都合よくN/Aにしない。

**最終GOゲート（未達・NOT EVALUATED）：** すべてのブロッキング項目C01〜C12をCHECKEDとし、横断的な権威の順序付け・故障復旧・偽造/再送/遅延Cの独立実測を完了し、使用者に`R_request accepted`と`R_effective confirmed`の違いを明示する。**CHECKEDになったとしても自動的にGem/APIの実装・本番・決済へのGOとはならない**。現時点の判断は**HOLD**。

## 2. 担当者別契約チェック表（全項目OPEN / 実装・実測なし）

| ID | 契約上の保証・相手への確認事項 | 主責任者（候補） | 必要な確認証拠（未取得） | 未達時の動作 |
| --- | --- | --- | --- | --- |
| **C01** | **権威の所有者**：Issuer/Agent/Buyerなど、どの失効源がどのtenant・subject・scopeを決め、誰が`R_effective`を確定するか。複数Authorityの横断整合性の責任者は誰か | Authority提供者 + 委任元 | trust/権限範囲・全失効源・競合順位の契約図 | **NO-GO**：単一Authorityだけを勝手に権威と扱わない |
| **C02** | **予約Pの実在**：予約の耐久原子性、同一operationの一意性、権限撤回とP/Cの直列化関係、失効要求`R_request`をPENDINGにできるか | Authority提供者 | 実APIの公開仕様、線形化点・不変条件、競合試験証拠 | **HOLD**：単なるALLOW/TTL/照会をPと偽称しない |
| **C03** | **Hostの決定強制**：すべてのHost C経路（別worker、直接DB書込、再試行、旧epoch、管理・outbox）にterminal checkout gateを強制できるか | Merchant Host運用者 | 変更経路の全数一覧、DB constraint/権限/トランザクション境界、負例結果 | **STOP**：`ABORTED`を将来C不能と扱わない |
| **C04** | **排他的なdurable決定**：Host`C_DURABLE`時にnonce CAS・Checkout・operation/outboxが一体確定し、`ABORT_DURABLE`時は同一gateで以降のCを不可能にするか | Merchant Host運用者 | durable schema/唯一の書込経路、C-vs-abort実レース、ACK喪失の復元ログ | **UNKNOWN / PENDING**：イベント行・メッセージのみ受理不可 |
| **C05** | **Host proofの出所**：Host証拠発行者のidentity、権限、信頼根・署名鍵の事前登録/rotation/revocation、audienceをAuthorityがどう検証するか | Host証拠発行責任者 + Authority | credential/trust-store仕様、鍵管理・失効運用、未知鍵/誤aud試験 | **REJECT**：自己申告JWK・kid・URLでtrust確立しない |
| **C06** | **文脈の完全束縛**：tenant・Authority/Host ID・subject/scope・reservation/operation・Checkout ID/version/fingerprint・nonce digest・epoch/fence・decision ID・idempotency keyがAuthority保存済みPと一致するか | Host proof発行者 + Authority | field schemaと照合規則、署名対象のcanonicalization、別scope/旧Pの流用拒否 | **REJECT / PENDING**：誤文脈・欠落を受理しない |
| **C07** | **耐久性と発行の接続**：Host決定とproof用outboxが同一Hostトランザクションで記録され、crash/ACK欠落後も同じ決定を再取得できるか | Merchant Host運用者 | write ordering、outboxとDB transaction証拠、crash/recovery注入結果 | **UNKNOWN / PENDING**：送信成功や署名成功をDB commitと同一視しない |
| **C08** | **rollback/failover禁止**：backup復元、リージョンfailover、旧worker復帰で`ABORTED`/epochがOPENへ戻り、Cが再許可されないか | Merchant Host運用者 + インフラ管理者 | anti-rollback/monotonic fencing・復旧手順、failover/復元実測、監視責任 | **STOP / RECOVERY_REQUIRED**：古いデータを`fresh`と判定しない |
| **C09** | **Authorityの確定規則**：P、R_request、決定証拠、R_effectiveの遷移をAuthorityが耐久記録し、保留中・不確実なin-flight Cがあれば有効化しないか | Authority提供者 | durable transitionとlinearization仕様、concurrency/partitionケース証拠 | **R_pending**：ACK/署名/TTLのみで取消完了にしない |
| **C10** | **再送・矛盾**：同じdecision ID/digest再送は冪等、違うdecision/epoch/operationの競合は拒否、監査イベント重複なし | Authority提供者 + Host proof発行者 | 保存期間・unique constraints・replay/ABA/decision conflict負例 | **CONFLICT / STOP**：最後に届いた証拠で上書きしない |
| **C11** | **障害時の責務・利用者表示**：Host/Authority不達、UNKNOWN COMMIT、鍵切れ、長期partition時の責任者、保留期間、停止/照合手順、「失効要求受付」と「失効確定」の文言を区別できるか | Authority提供者 + Merchant Host + 業務責任者 | 運用Runbook、手動照合/復旧SLA、顧客説明、通知やエスカレーション規則 | **PENDING + STOP**：即時取消の約束をしない |
| **C12** | **既存Cと外部Dの境界**：Cが既に確定なら失効で自動的に注文・Provider送出・返金まで取消されると誤解させないか | Merchant Host + 決済業務責任者 | C/D分離、idempotency責任表、撤回/返金/補償の契約範囲 | **HOLD**：C/D/Receipt成功を同一結果として表示しない |

**証拠欄は要求案であり提出された証拠ではない。** いずれも現状`OPEN / UNCONFIRMED`。承認権限者・日付・採否・証拠の保管場所を将来の個別レビューで記録する。API名を先に固定しない。

## 3. 主体ごとの役割境界（RACI候補・未合意）

| 仕事 | 最終決定の責任者候補 | 協力/照会先 | **やってはいけない代替** |
| --- | --- | --- | --- |
| 発行者の認可と失効時点`P/R_effective` | Authority・元の権限所有者 | Issuer/Agent/Buyerの失効管理者 | Hostの独自cacheをAuthority正本と扱う |
| Hostの`C`・nonce・operation/outbox・terminal abort | Merchant Host | DB/運用/セキュリティ担当 | 最終DB gateを通らないC経路を残す |
| Host durable decisionの証拠発行 | 信頼済Hostの証拠発行権限者 | Host DB、鍵・監査運用 | Coordinatorが自由に`ABORTED`を書ける構成 |
| 証拠受入・`R_effective`確定・冪等性 | Authority | Host proof提供者 | 「署名OK」を「Hostが将来C不能」とみなす |
| 配達/再送/ACK管理 | Coordinator（非権威） | HostとAuthority | Coordinatorの到着時刻をR/C全順序の決定に使う |
| 障害復旧と保留の顧客説明 | Merchant + Authorityの契約上の担当者 | セキュリティ・運用・CS | UNKNOWNを成功、期限切れを取消完了に変換 |
| 外部Provider`D`・返金・Receipt | Merchant/Providerとの別契約 | 決済・監査担当 | Host Cの結果を実支払成功に昇格 |

*RACIは提案であり、実サービス提供者との合意は存在しない。*

## 4. 証拠を受理する前に止めるべき条件

| 判定 | 入力/観測 | `R_effective` / Host Cへの扱い |
| --- | --- | --- |
| **REJECT** | 出所・鍵・audienceが未登録、別tenant/scope・Checkout版・epoch・reservationに流用、自己申告の信頼根 | **失効確定しない**。Host新Cも安全な権威的判断なしで発行しない |
| **CONFLICT** | 同一予約のCOMMIT/ABORT矛盾、重複が非同一digest、旧epochの再提出、ABA | **保留・調査**。既確定状態を勝手に巻き戻さない |
| **UNKNOWN / PENDING** | ACK欠落、Host不達、in-flight COMMIT未解決、DB durableと証拠の因果関係不明 | **`R_request accepted`と分離し、R_effectiveは保留** |
| **STOP / RECOVERY_REQUIRED** | Host terminal gate迂回、backup rollback、古いworker復活、Host侵害 | **新Cを停止**。Host証拠だけで復旧完了と宣言しない |
| **IDEMPOTENT** | 同じ証拠を厳密に同じcontext・digestで再送 | 状態/効果/イベントを増やさない（設計要件。実サービス未実装） |
| **ALREADY_COMMITTED** | `C_DURABLE < R_effective`を十分に立証した場合 | **既存Cを「取消済み」と誤表示しない**。外部D/返金は別手続 |

**強い安全性の未証明性：** 事前登録された鍵による署名検証、信頼済Hostのdurable gate、Authority側の失効保留の**全条件が揃っても**、実際の独立運営主体間の線形化・ロールバック/フェイルオーバー・未解決in-flight Cの安全保証は試験・レビューなしに確定できない。**悪意あるHostモデルではHost自身の正しい署名は無力**。必要ならHost以外が強制する共通直列化正本/合意された参加者型決定に再設計し、方式自体のGOは未承認。

## 5. 最小の外部相手向け質問票（回答・署名依頼は今回送らない）

質問の相手が決まったときに、次の**4つの塊**をまず聞く（現状すべて**未確認**）。

1. **Authority提供者へ：** `reserve(P)`、失効`R_request`と`R_effective`の区別、失効保留、同一operation/epochの耐久直列化・冪等decision受理と、複数失効源の統合保証を**実際に提供するか**。存在しないなら「AP2標準だから使える」とみなさず**HOLD**。
2. **Merchant Host担当へ：** すべてのC経路を一つのdurable terminal gateに束縛する設計、nonce/operation/outboxの原子性、ABORT後の未来C拒否、crash/failover/backup rollback後の持続強制を**どのログ・負例で実証できるか**。
3. **証拠発行/鍵運用担当へ：** 鍵とHost発行権限の事前登録、rotation/revocation、署名対象field、context束縛、decision/outbox同一transaction、ACK紛失時の再照会と監査を**何を根拠に保証するか**。
4. **運用/業務責任者へ：** 結果UNKNOWNの保留・新C停止と顧客表示、復旧の責任分界・保留SLA、即時失効要件、既存注文/Provider D/返金の範囲に**合意できるか**。

**必要な添付候補（取得なし）：** Auth API/契約仕様、Host DBと全書込経路の境界図、署名信頼ストア設計、鍵ローテーション計画、failure matrix/テストログ、DBバックアップ・復旧runbook、運用責務表、顧客説明文。これらは機微情報になり得るため公開OSSに秘密鍵・実個人情報・生credential等を持ち込まない。

## 6. 根拠の追跡・GO/HOLD・次の一件

| 根拠 | 本Stepが継承すること |
| --- | --- |
| [P1-10d 外部Authority/Host協調設計](HOST_EXTERNAL_REVOCATION_P110D_PROTOCOL.md) | 共有線形化点が無ければ`R_effective < C`が破られる。方式C/D/Fは本番未採用 |
| [P1-10h Authority盲信レビュー](HOST_EXTERNAL_REVOCATION_P110H_PROOF_BOUNDARY_REVIEW.md) | Coordinatorの`finalize_abort`や署名という形式だけではHost durable結果/将来C不能を保証しない |
| [P1-10i 実測](HOST_EXTERNAL_REVOCATION_P110I_EVIDENCE.md) | H01：旧Authorityは`R_effective`後にHost Cを許した**危険な反例**。防御モデルは**信頼できるHost DBの直接読取**前提。H02〜H06は限定合成試験 |
| [P1-10j 採否判断](HOST_EXTERNAL_REVOCATION_P110J_DECISION.md) | 直接Host DBアクセスが無い独立Authorityの真正なdurable decision/anti-rollback/全C経路契約は未確認 |

**検証進捗の再分類禁止：** Host正本 **9/34件実測・25 NOT RUN／過去12 runs/465 assertions**。P1-10c Mutex合成8 runs/94 assertions、P1-10g 2独立PG16 E-R01/R02合成2 runs/118 assertions、P1-10i H01〜H06別PG16合成**6 runs/178 assertions**（[最終P1-10i CI #38148130154](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38148130154)）は**別枠**。H01の旧経路は危険反例であって安全PASSではない。H07〜H12 **NOT RUN**。N17 HOST_BOUNDARY、P1-4 G1〜G6、P1-7 T1〜T5、公式Python SDK中間hop**186 PASS/2 FAIL**未解決。**P1-10k新テスト/CI/実装：0件。**

**判断：チェックリストの設計整理のみ完了。C01〜C12はすべてOPEN/UNCONFIRMED、実相手との契約・認証・分散順序/回復は未確認。HC06外部失効強保証・公開Gem/API・本番Host統合HOLD、RubyGems公開/Production/実決済/署名Receipt NO-GO。** 自己レビューは独立セキュリティ監査ではない。

**次のおすすめ1件（別途明示承認後）：P1-10l — 読み取り専用の仕様照合だけ。** 固定した**公式AP2 v0.2.0仕様/SDK**に、P1-10kのC01〜C12に対応するAuthority予約・失効保留・耐久最終決定証拠の**実際の標準API/契約が存在するのか**を節・ファイル単位で照合し、`SUPPORTED / NOT SPECIFIED / UNKNOWN`の根拠表にする。外部Authority・GCP・新コード/CI・決済・Gem化は別承認。
