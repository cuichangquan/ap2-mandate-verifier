# P1-10i — HC06 H01〜H06の架空Authority証拠負例・独立PG16実測

**2026-10-11 JST / RESEARCH-ONLY / H01 COUNTEREXAMPLE OBSERVED + GUARDED STOP / H02〜H06 LIMITED PASS / HC06 FULL HOLD。**

根拠：[P1-10h信頼境界設計レビュー](HOST_EXTERNAL_REVOCATION_P110H_PROOF_BOUNDARY_REVIEW.md)、[P1-10g独立PG実測](HOST_EXTERNAL_REVOCATION_P110G_EVIDENCE.md)。**公式AP2 v0.2.0固定SHA `b4587ac1d055888a73b4b21750973cffba961793`は変更なし。** `H01〜H06`はP1-10hの**将来用設計ID**で、既存正本Host34 IDやAP2公式規格のAPI/test vectorではない。Gem/API、外部Authority、GCP、実決済、Provider、署名Receipt、PII/秘密署名鍵は使用していない。

## 1. CI一次証拠と実環境

- **初回失敗も記録：** [Actions #38145867563](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38145867563) は**FAILURE**、6 runs / 161 assertions / 0 failures / **1 error**。原因はH01が呼んだ既存`p1_10g/worker.rb`の出力プレフィックス`RESULT:`を新テスト側がJSONとして直接解釈したための`JSON::ParserError`。Host/Authority安全条件が失敗したと装わず、テストコードの解析ミスとして修正。
- **修正後の証拠：** [Actions #38145972566](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38145972566)、実行head `f45cb2712e32dd756050db4ae7f738373f7c71fb`。**SUCCESS / 6 Minitest runs / 178 assertions / 0 failures / 0 errors / 0 skips**。H01反例が観測されたことと防御ガードのSTOPを両方検査。CIのevidence gateがIDの集合・分類・DB隔離・H02〜H06の主要条件を検査し、不足ならFAIL。
- **PG環境：** ubuntu-24.04、Ruby 3.3 / pg 1.5.9 / PostgreSQL **16.9×2**（既存p1-10gと同じイメージdigest）。Authority `ap2g_authority` port 5432、Host `ap2g_host` port 5433。双方`127.0.0.1`限定、`pg_control_system()`の異なるsystem IDを確認（Authority `7695411953910439974`、Host `7695411956910645286`）。同一Actions runner/ホスト上なので別物理マシンではない。CI終了時に2サービスコンテナ破棄。
- **証拠:** [artifact ID 11704602150](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38145972566/artifacts/11704602150)、`p110i-report.json`/`p110i-run.log`/`p110i-environment.txt`、7日保管。実JWT/生nonce/実決済/個人情報/実署名鍵なし。
- **積み上げPR:** P1-10h [PR #29](https://github.com/cuichangquan/ap2-mandate-verifier/pull/29) **2026-10-11にsquashマージ済み（main `c1df549fa536712e5b56e81c478771f4e93282a0`）**を前提として、P1-10i [PR #30](https://github.com/cuichangquan/ap2-mandate-verifier/pull/30)のbaseは`main`へ変更し、P1-10i単独差分で検証する。**P1-10hのsquash後に重複/競合を生じたため、最新mainからP1-10i単独内容を載せ直してCI再実行する。**

## 2. H01〜H06：実測した範囲

| ID | 実際の操作 | 結果・限定解釈 |
| --- | --- | --- |
| **H01** | 既存P1-10gの`Authority finalize_abort`へHost ABORTなしで命令。Authority `R_effective=true`の後、旧Host`commit`が実際に成功。次に別予約h01でHost OPENのまま防御ガードを呼ぶ | **COUNTEREXAMPLE_OBSERVED（旧経路が危険）**。ガードは**UNPROVEN/失効pending**。反例自体は「安全性PASS」に数えない |
| **H02** | Host durable ABORTがある合成データで、自己申告`host_service_id`または`audience`を改変 | **限定PASS / REJECT**。ただし署名/遠隔Host identityの真正性は検証しておらず、単なるメタデータallowlistだけなら偽造可能 |
| **H03** | tenant / scope / operation ID / reservation IDを別文脈に変更 | **限定PASS / REJECT**、Authority保存済み文脈との一致を要求 |
| **H04** | Host durable ABORT後、同じ`decision_id`・同digestの証拠を2回提出 | **限定PASS / EFFECTIVE→IDEMPOTENT**。`R_EFFECTIVE_ABORT`イベントは1、Authority receiptは1。実ネットワークACK dropは注入しておらず、**重複再送を合成** |
| **H05** | durable ABORTの`EFFECTIVE`を記録後、同じ予約に矛盾する`COMMITTED`を送る | **限定PASS / CONFLICT**。既存ABORT記録は維持、二重R_effectiveなし |
| **H06** | Hostの`host_events`へ`ABORT_DURABLE`というイベント行**だけ**を人工的に挿入。Host terminal gateは`OPEN`・nonceはISSUEDのまま | **限定PASS / UNPROVEN**。見かけのイベントだけで`R_effective`にしない。nonce ISSUED、operation/outbox0 |

**集計の厳密な区別:** Minitest自体は6 runs/178 assertions成功。テスト計画IDでは**H01の旧方式に危険な反例1件（安全性PASSではない）＋H01の防御条件STOP、H02〜H06の限定5件PASS**である。**HC06正本Host IDを1件も追加でPASSにしていない。**

## 3. 防御モデルの実体と採用できない理由

- `research/p1_10i/authority_guard.rb`は**研究専用Authority worker**。Authority PGの予約行を`FOR UPDATE`、`revoke_requested`、保存済みtenant/authority/scope/reservation/operation/Checkout/epoch/nonce_digest、decision_id/重複digestを照合する。**別独立Host PGに直接接続し**、Host terminal row・nonce・operation/outbox・Host eventの一致を照会する。受理時にAuthority自身のローカルPG transactionでreceiptと`R_effective`を記録する。
- **この直接Host DB接続を「信頼できる観測用seam」と仮定することがテストの前提。** 別運営主体の本物のAuthorityがHost DBを直接参照できる保証はなく、サービスidentity / mTLS / 署名済みHost decision envelope、Host署名鍵の信頼設定、署名検証、証拠発行の安全なAPI、anti-rollback、バックアップからの復旧、複数Authority/Host、高度な不正Hostモデル、分散原子性は**一切実装・実証していない**。メッセージに自己申告された`host_service_id`をallowlistで比較しても**暗号的な送信元認証にはならない**。
- H04/H05のHost durable abortは**テストオーケストレータがHost DBの単一transactionと行ロックで作成**した合成制御データ。Host別OS workerによる実中止後SIGKILLを再検証したのではない（過去のP1-10gと区別）。H06の不正Host event挿入も**意図的な人工反例**であり、Host DB侵害一般の試験ではない。
- AuthorityがHostを照会後、Host状態が巻き戻る場合、別経路でCする場合、Host自身が虚偽の耐久証拠を発行する場合など、**R_effective < C禁止の強い証明はない**。本実装は安全な外部Authority連携設計として採用不可。Host照会不能/不明な実行結果の全面的な通信・復旧試験もしていない。
- `H07〜H12`（ACK不明、partition、Host rollback、Host自身の不正、過去CとRの順序、timeout）は[P1-10h資料](HOST_EXTERNAL_REVOCATION_P110H_PROOF_BOUNDARY_REVIEW.md)のまま**NOT RUN**。

## 4. 歴史的実測とGO/HOLD・次の一件

- Host正本**9/34件実測 / 25 NOT RUN**、既存**12 runs/465 assertions**（[P1-10a](HOST_REPLAY_P110A_EVIDENCE.md)）。P1-10c単一process合成**8 runs/94 assertions**、P1-10g 2PG合成**2 runs/118 assertions**、**今回P1-10i合成6 runs/178 assertionsはすべて別枠**。これらを混算してHost正本実測数を増やさない。
- N17 stateless replay HOST_BOUNDARY、P1-4 G1〜G6/P1-7 T1〜T5、公式Python SDK中間hop **186 PASS/2 FAIL**は未解決。
- **判定:** P1-10i限定合成試験PASS（危険旧baseline H01の反例再現を含む）。**HC06外部失効の強い保証・Authority証拠の本番採用・Gem/API/本番Host統合HOLD。RubyGems公開・Production・実決済・署名Receipt NO-GO。** 自己レビューは独立安全監査ではない。

**次のおすすめ1件（別途明示承認後のみ）：P1-10j** — **設計・採否レビューのみ**：直接Host DB読取りという研究上の特権を外し、異なる運営主体のAuthorityにどのような真正なdurable decision証拠/認証/anti-rollback/全C経路保証があれば実際に連携可能か、未確認の公式Authority機能を仮定せず、必要条件とSTOP条件を定める。追加コード/CI/GCP/外部API/決済は別承認。
