# P1-10c — HC06のTOCTOU負例とfencing条件：完全オフライン状態モデル実測

**日付：** 2026-10-11 JST  
**位置づけ：** **架空Authority/Hostモデルの8テスト成功（部分的研究）**。正本HC06は**FULL PASSではない／HOLD**。  
**公式AP2：** v0.2.0 固定commit `b4587ac1d055888a73b4b21750973cffba961793`。ここで扱うHost失効同期・fencing tokenは提案モデルでありAP2が規定する分散プロトコルではない。

## 実測したCI・環境・証拠

- [GitHub Actions #38137575582](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38137575582) **SUCCESS**。Ruby **3.3.12**、ubuntu-24.04、Minitest **8 runs / 94 assertions / 0 failures / 0 errors / 0 skips**。
- JSON構造化検証ゲートが正本ID `HC06`、**2つの意図的なUNSAFE負例**と**6つの安全側モデル挙動**、全8シナリオ、および `canonical_host_ids_newly_proven=0` を確認。ログと`p110c-report.json`は7日保持のartifact `p1-10c-hc06-synthetic-evidence`（ID **11702220863**）。
- 実行は**単一Rubyプロセス、メモリ上の二つの論理コンポーネント**だけ。PostgreSQL、外部HTTP、実Issuer/Agent/Buyer、署名鍵、決済/Receipt、GCP/外部サービス/実時刻同期を使わない。従前のPG16検証はこのCIで再実行していない。

## モデル内で観測した状態遷移

モデルの`Authority`は正本の有効/失効・epoch・発行ticketと追跡イベントを持つ。別の`Host`はCheckout OPEN/RESERVED、nonce ISSUED/CONSUMED、operation/outbox件数を持つ。イベント `Q` は権限照会、`F` はticket発行、`R` は失効effective、`C` は注文operationの確定。順序は同一プロセスの増加シーケンス番号で検証。

| シナリオ | 結果 | 意味 |
| --- | --- | --- |
| `naive_q_r_c` | **意図通り危険性を再現**：`Q → R → C_UNGUARDED`、operation 1 | 再照会の成功後に失効しても、Hostが古いALLOWで確定できてしまう。**HC06を満たさない** |
| `fence_not_enforced` | **意図通り危険性を再現**：`F → R → C_UNGUARDED`、operation 1 | ticketを持つだけでは保護にならない。最終確定と同期した検証が必要 |
| `revoke_before_query` | STOP、operation 0、nonce未消費 | すでに失効した権限を照会した場合 |
| `fence_r_before_c` | `F → R`。final gateでSTOP、operation 0 | **共有された単一排他境界の内側**で最終認可とHost確定を原子的に扱った場合 |
| `fence_c_before_r` | `F → C → R`、operation 1。後からの再利用STOP | 失効が後なら確定済みoperationは自動では取り消されない |
| `scope_tenant_subject_and_forgery` | 他tenant/Buyer/scope、不明tokenを拒否 | 架空ticketの識別・scope照合（暗号的な真正性ではない） |
| `offline_at_final_gate` | Authority unavailableでSTOP、operation 0 | 不明な状態をALLOWにしない |
| `fence_replay` | 同一ticketの二重使用はSTOP、operation/outbox各1 | 模擬的な繰返し抑止（本番Host replay証明ではない） |

## 最大の制限：fencingだけでは分散原子性を保証しない

モデル内の`commit_with_fence`は、**Authorityのtoken確認とHostの`commit_one`が同一Rubyプロセスの`Mutex`で保護される**という人工的な前提を置く。つまり、このモデルは**分散サービス間の原子性を実現していない**。

本物のAuthorityへの`validate_fence()`が返った直後に失効Rが確定し、後でHostのPostgreSQL COMMIT Cが成功するなら、**R<Cの競合が再発**する。外部Authorityのトランザクション／atomic reservation、受理側fence強制、失効effectiveの線形化契約、障害回復の設計が確認できない限り、今回の緑色CIから強いHC06保証へ外挿してはいけない。

`F`と`R`の順序だけでは不十分で、**Rと最終的なCを比較可能な共通の確定境界が必要**。有限leaseでRを延期する方式なら「即時失効」とは異なる業務要件になる。

## GO/HOLD・未実行範囲

- **P1-10c：架空状態モデルの負例・不変条件の限定的実測としてPASS**。危険な操作を意図的に成功させた2ケースは**安全性のPASSではなく反例の再現成功**。
- 正本[HC06](HOST_SECURITY_TEST_PLAN.md)は**部分的なモデル研究のみ／完全な外部失効テストとしてはNOT RUN**。[P1-10b設計](HOST_EXTERNAL_REVOCATION_HC06_DESIGN.md)のHC06-A〜Hは全面実証したわけではない。既存の実DB実測**Host 9/34件、25件未実行、12 runs/465 assertions（P1-10a）**というカウントを維持し、新規正本Host IDの実証数は**0**。
- N17 stateless Verifier HOST_BOUNDARY、HT/HC04/HC07/HR09等の未解決検証、P1-4 G1〜G6とP1-7 T1〜T5未完、公式Python SDK中間hopの**186 PASS/2 FAIL**を解消済み扱いにしない。
- **汎用Gem/API・実Host統合HOLD**、RubyGems公開・Production/実決済/署名Receiptは**NO-GO**。自己レビューであり独立したセキュリティ監査ではない。

**次の1件（新たなユーザー明示承認後のみ）：P1-10d** — 外部Authorityが提供し得る原子的な認可予約／失効effective時点とHostのdurable COMMITをどう整合させられるか、**分散トランザクションを装わない形のプロトコル設計・失敗モード表の作成のみ**。実際の外部API/GCPや本番テストは別承認。
