# 固定profile検証コアの完成条件（判断案）

更新：2026-10-24 10:51 JST。読解基準：
`64b67ac5541f01489f946b1ed1b334acafbfe967`。
Ownerは当面の完成対象を限定コアとする方針を承認済み。
本書は完成条件の判断案であり、コアの完成宣言ではない。
文書の反映・レビュー・統合の承認は、安定版公開、コード変更・試験実行・本番GOへ拡張しない。

## 目的と正本の分担

[SUPPORT_CONTRACT](SUPPORT_CONTRACT.md)はAPI・入力・有限上限の仕様、
[Stage21追補](STAGE21_VALIDATION_SUPPLEMENT.md)は限定観測と残余、
[PROJECT_STATUS](PROJECT_STATUS.md)は現在地の入口。
本書はそれらを置き換えず、完成判断に必要な証拠と責任者を対応付ける。
[元E00–E10](PHASE2A_EXIT_GATE_DECISION_CHECKLIST.md)の原条件・過去の判定は変更しない。
古いNOT_RUNは各記録時点の事実であり、現在の公開pre3 Linux結果は現状メモを参照する。

対象は公式AP2 `b4587ac1d055888a73b4b21750973cffba961793`、
`ap2.checkout.single_merchant_sku` v1の厳密なPROFILE_BODY/hash、ES256/P256、
Open1→Closed1、固定3開示位置、単一Merchant/SKU、USD/EUR/JPY、empty links。
認証済みでtokenと独立したHost入力、信頼するRuby実行環境を前提にする。
未知profileや非対応形状は拒否し、一般AP2/Schema fallbackを追加しない。
発行・提示生成・Rails SDK・実Issuer運用は別段階。本番利用不可を維持する。

## GemとHostの責任

Gemは渡されたtrust登録の厳格構文、snapshot/profile hash、登録と選択の参照整合、
role/identity/tenant/purpose/key_refの一意性、P256公開鍵・fingerprint、active状態と期限を検査する。
Root/Agent/Merchant署名・元wire・開示閉包・固定Schema/制約・購入bindingを検査し、
Host challengeのB全体、登録参照、鍵、nonce/aud、注文・原文digest・金額を照合する。
渡されたverified_atでtoken/鍵/snapshot/challengeの期限交差を計算する。
これらをHost責任として省略しない。全必須条件成立前に成功Evidenceを出さない。

Hostは登録の真正性と最新性、承認・更新/rollback防止、信頼時計、最新失効状態を提供する。
利用直前に最新trust/profile/鍵・注文/Buyer/Agent/challenge・時刻を再確認し、
nonce消費と注文CASを原子的に行う。結果不明はPENDING/照合へ送り、認可・決済を独自判断する。
自己整合するhashは出所や最新性の認証ではない。古い入力だけからGemが現在の失効を検出したとは言わない。
Evidence≠Host ALLOW。Evidenceは信頼する同一Rubyプロセス内の不変な検査事実であり、
JSON転送の真正性、悪意ある同一プロセスRuby、nonce消費・決済成功を保証しない。

## 限定コアの完成条件と証拠

「既証明」は下記の固定観測命題だけを指す。部分確認を全面PASSへ繰り上げない。
ソースリンクはすべて上記固定コミット。追加試験の必要性は差分調査後に確定する。

| 条件・関連Gate | 固定ソースの根拠 | 現在の区分 | 合格判定に必要な証拠・追加試験 |
| --- | --- | --- | --- |
| 対象閉包・厳格入力 E00/E07 | [InputValidator](https://github.com/cuichangquan/ap2-mandate-verifier/blob/64b67ac5541f01489f946b1ed1b334acafbfe967/lib/ap2_mandate_verifier/input_validator.rb)、[TrustContext](https://github.com/cuichangquan/ap2-mandate-verifier/blob/64b67ac5541f01489f946b1ed1b334acafbfe967/lib/ap2_mandate_verifier/trust_context.rb) | 部分確認：固定形状・重複拒否・byte/depth/count上限あり | 対応/非対応と各上限の実装・既存境界試験を対応付ける。不足だけ追加候補、全件再実行を既定にしない |
| 署名・元wire・閉包・因果 E02/E03/E04 | [RootDisclosures](https://github.com/cuichangquan/ap2-mandate-verifier/blob/64b67ac5541f01489f946b1ed1b334acafbfe967/lib/ap2_mandate_verifier/root_disclosures.rb)、[PurchaseBinding](https://github.com/cuichangquan/ap2-mandate-verifier/blob/64b67ac5541f01489f946b1ed1b334acafbfe967/lib/ap2_mandate_verifier/purchase_binding.rb) | 部分確認：既存独立比較あり、全パス証明ではない | 同じ候補SHAの正常例と有効署名の因果負例、原wire/hash、独立期待値、実到達stageを対応付ける。早期拒否を未実行stageの合格にしない。不足のみ試験候補 |
| 登録選択・profile/key整合 E01/E05 | TrustContext（上記） | 部分確認：不明/曖昧/非active/期限外拒否。実Issuer出所・運用更新は未証明 | Gem側の参照/一意性/期限負例の既存証拠を照合し、不足だけ候補化。Hostの出所/最新性は前提として明示し、E01/E05原条件をPASSにしない |
| 期限交差・challenge/注文照合 E05/E08 | [HostBinding](https://github.com/cuichangquan/ap2-mandate-verifier/blob/64b67ac5541f01489f946b1ed1b334acafbfe967/lib/ap2_mandate_verifier/host_binding.rb)、PurchaseBinding | 部分確認：渡された時刻で交差を検査。実時計・live失効・CASはHost責務/未証明 | 開始inclusive/終了exclusive、terminal age境界、challenge/B/鍵/nonce参照の既存証拠を照合。Host側実装の完成をGem単体の完成と混同しない。追加は不足確定後 |
| Schema/制約と統合順序 E06 | [ScopedConstraints](https://github.com/cuichangquan/ap2-mandate-verifier/blob/64b67ac5541f01489f946b1ed1b334acafbfe967/lib/ap2_mandate_verifier/scoped_constraints.rb)、HostBinding | PARTIAL/OPEN：7形状の手書きsubset、証拠対応表を追補 | [E06証拠対応表](E06_SCOPED_EVIDENCE_MAP.md)で条件・実装・既存試験・独立期待値・実因果観測/限界を整理。具体的な追加必須試験は今回未特定。証拠水準のOwner採用判断は保留 |
| 成功Evidence/失敗契約 E08 | [ResearchResult](https://github.com/cuichangquan/ap2-mandate-verifier/blob/64b67ac5541f01489f946b1ed1b334acafbfe967/lib/ap2_mandate_verifier/research_result.rb) | 部分確認：全検査後の不変Evidence、旧API非成功。Host ALLOWは未証明 | 必須fact/最短期限/nonce hash、非成功・結果なしで権限なし、constructor/外部再構成の境界を既存証拠へ対応付ける。不足のみ候補 |
| 資源と環境 E07/E09 | InputValidator、SUPPORT_CONTRACT、Stage21追補 | 部分確認：有限入力とMBA直列観測。CPU/RSS/並列保証は未証明 | 将来サポート環境・Host外側制限・測定予算/入力/合格値はOwner未決定。数値決定と別承認前は追加測定しない。ハーネス期限を製品quotaと呼ばない |
| 公開品同一性・限定再現 E09 | [公開品manifest](https://github.com/cuichangquan/ap2-mandate-verifier/blob/64b67ac5541f01489f946b1ed1b334acafbfe967/research/pre3_linux_published/CURRENT_MANIFEST.json)、現状メモ | 既証明（観測限定）：公開pre3のMBA/Linux 13 payload/10 loaded/52 installed一致。完全独立runtime証明は未証明 | 既存archive/source/installed/loadedのhashとrun/providerを保持。52は保存期待値の再生を含み独立Oracle再実行ではない。変更のない公開品を再取得・再ビルドしない |

公開pre3は37888 bytes、SHA256
`8ad627818dc69b450d0fba970dafaf368ec42dd64fb51eec631731027de3882c`。
包装基準は`20809b057c75d4145eff13e5c183d616c19ef696`。
mainの追補文書はGem同梱文書と異なり、同じ版の再ビルドは公開品の証拠を継承しない。
MBAは[PR177](https://github.com/cuichangquan/ap2-mandate-verifier/pull/177)、Linuxは
[run40038620413 attempt1](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/40038620413)
（実行SHA `d34dbfa3a87a75360fb4bb14d535da8bc5e8cdc4`）。1run承認枠は消費済み。
pre3で885 source回帰・独立Linux Oracleを再実行したとは記録しない。
MBA/Darwin arm64とUbuntu24.04 x86_64、MRI4.0.9と固定依存/providerは観測事実であり、
将来のサポート範囲は未決定。全通信128MiB遵守も未証明のまま。

## 判定を分ける

| 判断 | 状態・必要条件 |
| --- | --- |
| 限定検証コアの完成 | 未判定。上表の不足を対応付け、必要な証拠・対応環境・残余条件をOwnerが採用し、対象SHAのレビューと承認された必要検証を踏まえ別途判断 |
| Phase2-A全体 E00–E09 | 全面PASS未成立。元チェックリストの原条件は緩和せず、限定コアの境界変更で埋めない |
| E10/Phase2-B・本番GO・安定版公開 | 本書では承認しない。各対象・未証明・費用・実行を具体化した別判断が必要 |

実Issuerサービス/契約/登録根拠は未確認。実Issuer保証を要求する場合は相手方と発行profile・
鍵登録根拠が前提で、合成データでは代替できない。限定コアではその保証を主張しない。
CPU/RSS・同時実行予算、将来の対応OS/provider、安定版の利用主張はOwner未決定。
完全な独立runtime attestationを、合意のない新しい完成要件として追加しない。

## E06証拠対応の追補（2026-10-24 UTC）

上表と冒頭の64b67ac基準は完成条件を整理した時点の記録です。
PR182/183統合後の `0b25529ea97967dbaf657bd8adb4eb26e98898a7` に対する
[証拠対応表](E06_SCOPED_EVIDENCE_MAP.md)で、7支持形状の必須条件・実装・既存回帰・独立期待値・実因果観測と限界を整理しました。
今回の読解では具体的な追加必須試験は未特定です。全fieldの新規独立因果traceや一般Schema適合を主張せず、
この証拠水準のOwner採用判断は保留。E06 PARTIAL/OPEN・限定コア完成未判定・本番GO未承認は変わりません。
文書化のための追加試験・再包装・CIは行っていません。

## 不足調査の方法（既存の手順記録、追加実行の指示ではない）

1. 既存7形状の各field/constraintを固定公式Schemaとコードへ対応付け、仕様差と未対応を区別する。
2. 既存独立30契約+12境界比較、8 Schema判断、既存source試験から、同じ候補・元wire/hash・独立期待値・実到達stageの対応表を作る。885/52を加算せず、古い13ケース64判断も別証拠として保つ。
3. 早期拒否で目的stageへ到達しない負例、期待値がRuby自身に依存する部分、未対応の必須条件だけを不足として列挙する。既存証拠で満たす命題は再試験から外す。
4. 不足ごとに最小ケース案・独立oracle・固定環境/依存・上限・STOP条件を提示する。この段階ではfixture/試験コード作成、試験、外部archive取得、CIを開始しない。

矛盾、根拠欠落、未知依存/費用、権限拒否は該当部分をHOLDとして報告する。
本書は承認範囲の記録であり、新たな実行権限を付与しない。
