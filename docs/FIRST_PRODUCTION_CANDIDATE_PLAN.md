# 初回本番候補：残タスク・証拠・完了条件

状態：**計画文書／本番GO・次版公開はHOLD**。
読解基準main：`305d0a5ee913bf8122d6ea808d4b8aeed11f8256`（PR #193後）。

## 決定済みの範囲と判断の分離

Ownerは初回本番候補を、既存固定profileの**検証専用Gem**とする範囲を承認した。
AP2固定参照 `b4587ac1d055888a73b4b21750973cffba961793`、
`ap2.checkout.single_merchant_sku` v1・7支持形状が出発点。
Host運用、実決済、発行・提示生成は候補Gemの対象外。利用サービス・用途・実Issuerは未定。
範囲承認は本番安全性、元E06/Phase2-A全面PASS、Phase2-B/E10 GO、Gem公開の承認ではない。
検証専用Gemの公開判定、特定Hostの運用GO、将来フルSDKの完成は別判断である。

本書は[PRODUCT_VISION](PRODUCT_VISION.md)の初回候補について、既存資料を参照して残作業を整理する。
[原Gate](PHASE2A_EXIT_GATE_DECISION_CHECKLIST.md)の過去判定を上書きせず、
[完成条件](VERIFIER_CORE_COMPLETION_CRITERIA.md)・[E06証拠表](E06_SCOPED_EVIDENCE_MAP.md)の採用済み根拠を再利用する。
ここで新しい実装欠落や追加必須ケースを確認したことにはしない。

## 既存証拠をそのまま利用する項目

| 根拠 | 候補判断で利用できる範囲 | 再利用の限界 |
| --- | --- | --- |
| [研究用コア第一段階の完成判断](VERIFIER_CORE_COMPLETION_CRITERIA.md#研究用検証コア第一段階の完成判断2026-10-24-utc) | 信頼する独立Host入力/Ruby環境、固定profile・7支持形状・採用済み環境での限定判断 | 本番判断へ自動昇格しない |
| [E06証拠対応表](E06_SCOPED_EVIDENCE_MAP.md)・PR182/183の因果/意味各4入力 | 既存型/制約、統合順序、独立期待値・実拒否段階の対応。閉じた7形状について具体的な追加必須試験は未特定 | 全fieldの個別trace・一般Schema適合・全パス証明ではない |
| 同表のMBA409 VALIDATION01・security JSON R2・Stage11 O4 | 885回帰、30独立契約/12境界/8 Schema判断、旧13ケース64判断を各source/runtime/hashのまま引用 | 旧Ruby4.0.1観測を現runtime再実行としない。件数を合算せず、同表の原本hashと来歴を保持 |
| [公開pre3 Linux run40038620413 attempt1](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/40038620413)・[PR177](https://github.com/cuichangquan/ap2-mandate-verifier/pull/177) | 公開pre3のMBA/Linux 13 payload/10 loaded/52 installed同一性 | 885や独立Linux Oracle再実行ではない。将来候補archiveの証拠ではない |
| [DB handoff R3](../research/host_db_handoff_subset/README.md)・[COMMIT回復R5](../research/host_commit_reconcile_subset/README.md) | Host前提と失敗境界の説明、固定合成入力による5/4制御scheduleの限定観測 | 本番adapter・実認証/時計/失効・実TCP障害・crash耐久性・一般並行性能の証明ではない |

公開pre3は37888B、SHA256 `8ad627818dc69b450d0fba970dafaf368ec42dd64fb51eec631731027de3882c`。
公開bytes/原結果/旧停止履歴を保持する。文書が異なる現在mainの同版再ビルドは公開品と同一とは扱わない。

## 優先順と残タスク

分類：**G＝Gem側で整理可能、D＝Owner決定、H＝用途/Issuer/Hostが必要、R＝候補確定後の公開工程**。
以下は作業計画であり実行承認ではない。未実施の試験回数や完了日を捏造しない。

| 優先・ID / Gate | 担当・現在の不足 | 完了条件と最小の次工程 |
| --- | --- | --- |
| 1 G1 / E00・E02〜E06・E08・E09 | Gem保守者＋独立レビュー。本番候補の各主張に対する既存証拠の採用水準が未決。E06以外も含む候補全体の不足判定は未完了 | 主張→実装→既存試験→独立期待値→実測/拒否stage→source/runtime同一性→残余を既存表への参照で結ぶ。証拠充足、紐付け不足、実装欠落、追加検証必要、Host前提を区別。欠落があれば具体的条件だけ記録。まず読み取り監査で追加必須ケースの有無を確定する |
| 2 G2/D1 / E08・API | Gem保守者＋Owner。現行`verify_research`/研究Evidenceを本番候補でどう契約化するか未決 | 入出力、失敗code、旧API非成功、結果なし時の停止、同一信頼Ruby内Evidence、互換性と変更方針を確定。名前変更・新APIが必要とは既定にしない。必要な差分が確定した場合だけ別実装/検証計画へ |
| 2 G3/D2 / E07 | Gem保守者＋Host利用者＋Owner。有限入力上限は実装/既存境界あり。最悪CPU/RSS・並行性能は未証明 | byte/depth/count等は既存根拠を再利用。数値性能保証の有無、Hostが強制する時間/メモリ/同時実行条件、超過/結果なしの扱いを決める。実効性に証拠不足があれば想定入力・独立判定・上限を限定した測定案だけ作る。全組合せストレス試験やライブラリ内quota追加を既定にしない |
| 2 G4/D3 / E09・環境 | Gem保守者＋Owner。MRI4.0.9/固定依存と観測済み環境は採用済みだが、本番候補時点の環境安全性・保守可能性は未証明 | 対象Ruby/OS/architecture、各Gemと実ロードnative/providerの出所・版・hash・修正状況、将来更新時の検証範囲を確認。過去の安全性観測を現在/全環境へ一般化しない。新しい依存/環境が必要なら別承認 |
| 3 G5/D4 / E09・運用 | Gem保守者＋Owner。報告窓口は既存、依存監視/修正版提供/サポート方針は本番契約として未確定 | [公開後整備](POST_RELEASE_MAINTENANCE.md)とSECURITYを再利用し、保守担当・対応範囲・更新/廃止・脆弱性対応の方針を決める。稼働していない自動監視やSLAを主張しない |
| 3 D5 / 通信・資源会計 | Owner。過去の送信header/総通信128MiB、Docker全期間物理増分等の未証明が残る | 原不足と失敗を保持し、本番候補の主張/供給工程への影響と採用可否を根拠付き判断。Gem本体は通信しないが過去取得を計測済みとしない。将来の必要取得には計測できる範囲・予算・未知を定義。過去実験の全再実行を要求しない |
| 用途決定後 H1 / E01・E05 | Host/Issuer＋Owner。主体・用途・真正な鍵配布元、登録承認、更新/失効正本/鮮度が未定 | [Issuer登録票](ISSUER_ONBOARDING_CHECKLIST.md)を実根拠で埋め、固定発行profileとの適合、rotation/revocation/rollback方針を確認。Gem登録検査と実Issuer信頼成立を区別。特定Issuer互換性は根拠なしに公開主張しない |
| Host決定後 H2 / E08・E07 | Host利用者＋Owner。実運用の最新状態・認証・原子消費・障害回復は未実証 | 下記前提を利用契約へ明記し、特定サービスのGOには当該Hostが実装/検証する。Gem候補の一部としてDBや決済機能を追加しない |
| 最後 R1 / E09・公開判断 | Gem保守者＋独立レビュー＋Owner。新候補版/source/archiveは未確定、本番/公開GOなし | 候補差分に応じた回帰・必要な独立比較・包装/導入/ロード同一性と最新HEADレビューを計画/承認後実施。版、配布先、同梱文書、SHA、鍵/MFA、更新/撤回方針を確認し明示GO。元GateとE10/Phase2-Bの判断は別途記録し、文書統合だけで解除しない |

優先1の監査結果が「既存証拠で十分」なら、試験追加ではなくOwnerの採用判断へ進む。
不足が見つかった場合だけ、目的・正常/因果負例・独立oracle・期待stage・対象版・環境・回数/資源/費用・STOPをまとめて承認対象にする。
候補コード/依存/包装が変わるときの再検証は変更範囲と残る不確実性に対応させ、旧証拠を新結果に改称しない。

## 対象外でも外せないHost前提

- 提示tokenと独立した認証済みtrust/profile選択、主体/用途/鍵の根拠、最新失効・更新/rollback防止、信頼時計、正本注文/challengeをHostが供給。不明ならHOLD。
- Gemは供給された入力の既存検査を維持する。Gemが外部出所や最新性を独立証明したとは言わない。
- EvidenceはALLOWではなく、同じ信頼Rubyプロセス内の検査事実。JSON Hashから真正性を復元しない。使用直前に最新条件を再照合する。
- 最終業務判断、nonce原子消費＋注文CAS、認証/照会権限、PENDINGと安全な回復、決済冪等性はHost/決済サービス。Gemのrejected/unavailableを許可へ読み替えず、例外/プロセス終了で結果なしも許可しない。
- 最悪資源/並行性能の保証は未証明。Hostは合意した実行制限と監視を設ける。実環境の安全性を今回証明したとは扱わない。

## 今回の結論と停止境界

**推奨する最初の一件はG1の本番主張と既存証拠の静的対応監査。** E06を重複作成せず、他Gateの本番候補で使える証拠・不足・Owner判断を絞る。
用途/Issuer未定でもG1とAPI・資源・環境・保守の判断案は整理可能。H1/H2は前提を記述する段階に留める。
これは本番GOに実Issuerが一律不要という結論ではない。条件付きGem配布として何を主張できるかはOwner判断、特定Issuer/Hostへの適用は実証までHOLD。
一般AP2、多profile/多hop、発行/提示/Receipt、Rails連携、別言語coreは今回の追加必須作業ではない。
正確な残数・期間は候補主張と不足確定前には断定しない。

本書の文書整理では追加試験・構文実行・Docker・取得/導入・Gem再作成・Actions・Gem公開を行っていない。
追加実装/動的確認が必要な指摘、根拠欠落、未知の費用/副作用、権限拒否はその対象をHOLDにし、別承認前に進めない。
