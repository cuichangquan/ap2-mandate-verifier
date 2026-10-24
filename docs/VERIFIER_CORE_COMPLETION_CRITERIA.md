# 固定profile研究用検証コア第一段階の完成判断と条件

更新：2026-10-24 10:51 JST。読解基準：
`64b67ac5541f01489f946b1ed1b334acafbfe967`。
Ownerは当面の完成対象を限定コアとする方針を承認済み。
完成条件の初期読解基準は上記の履歴。2026-10-24 UTCのOwner判断により、下記に限定した研究用検証コア第一段階は完成判断済み。
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
| Schema/制約と統合順序 E06 | [ScopedConstraints](https://github.com/cuichangquan/ap2-mandate-verifier/blob/64b67ac5541f01489f946b1ed1b334acafbfe967/lib/ap2_mandate_verifier/scoped_constraints.rb)、HostBinding | PARTIAL/OPEN：7形状の手書きsubset、証拠対応表を追補 | [E06証拠対応表](E06_SCOPED_EVIDENCE_MAP.md)で条件・実装・既存試験・独立期待値・実因果観測/限界を整理。具体的な追加必須試験は今回未特定。限定profileの判断根拠としてOwner採用済み。E06全体PASSは未承認 |
| 成功Evidence/失敗契約 E08 | [ResearchResult](https://github.com/cuichangquan/ap2-mandate-verifier/blob/64b67ac5541f01489f946b1ed1b334acafbfe967/lib/ap2_mandate_verifier/research_result.rb) | 部分確認：全検査後の不変Evidence、旧API非成功。Host ALLOWは未証明 | 必須fact/最短期限/nonce hash、非成功・結果なしで権限なし、constructor/外部再構成の境界を既存証拠へ対応付ける。不足のみ候補 |
| 資源と環境 E07/E09 | InputValidator、SUPPORT_CONTRACT、Stage21追補 | 部分確認：有限入力とMBA直列観測。CPU/RSS/並列保証は未証明 | 初回対応環境・保証除外は下記追補の範囲をOwner採用済み。利用側が実行時間/メモリ/同時実行制限を設定する。最悪CPU/RSS・並行性能の保証なし。追加測定は行わず、ハーネス期限を製品quotaと呼ばない |
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
初回の対応環境は下記の観測記録に限定してOwner採用済み。その他の版/環境への拡張は未決定。全通信128MiB遵守も未証明のまま。

## 判定を分ける

| 判断 | 状態・必要条件 |
| --- | --- |
| 研究用検証コア第一段階 | Owner完成判断済み。信頼する独立Host入力/Ruby環境、固定profile・7支持形状・採用済み環境に限定。既存証拠と保証除外を採用した判断で、元Gateの全面PASSではない |
| Phase2-A全体 E00–E09 | 全面PASS未成立。元チェックリストの原条件は緩和せず、限定コアの境界変更で埋めない |
| E10/Phase2-B・本番GO・安定版公開 | 本書では承認しない。各対象・未証明・費用・実行を具体化した別判断が必要 |

実Issuerサービス/契約/登録根拠は未確認。実Issuer保証を要求する場合は相手方と発行profile・
鍵登録根拠が前提で、合成データでは代替できない。限定コアではその保証を主張しない。
最悪CPU/RSS・並行性能は初回保証対象外で、利用側が実行時間/メモリ/同時実行制限を設定する。その他のOS/providerや将来版への拡張、安定版の利用主張は未承認。
完全な独立runtime attestationを、合意のない新しい完成要件として追加しない。

## E06証拠対応の追補（2026-10-24 UTC）

上表と冒頭の64b67ac基準は完成条件を整理した時点の記録です。
PR182/183統合後の `0b25529ea97967dbaf657bd8adb4eb26e98898a7` に対する
[証拠対応表](E06_SCOPED_EVIDENCE_MAP.md)で、7支持形状の必須条件・実装・既存回帰・独立期待値・実因果観測と限界を整理しました。
今回の読解では具体的な追加必須試験は未特定です。全fieldの新規独立因果traceや一般Schema適合を主張せず、
この証拠水準は7支持形状・固定profileのE06判断根拠としてOwner採用済み。元E06全体はPARTIAL/OPEN・本番GO未承認。後続の第一段階完成判断は末尾に記録します。
文書化のための追加試験・再包装・CIは行っていません。

## 不足調査の方法（既存の手順記録、追加実行の指示ではない）

1. 既存7形状の各field/constraintを固定公式Schemaとコードへ対応付け、仕様差と未対応を区別する。
2. 既存独立30契約+12境界比較、8 Schema判断、既存source試験から、同じ候補・元wire/hash・独立期待値・実到達stageの対応表を作る。885/52を加算せず、古い13ケース64判断も別証拠として保つ。
3. 早期拒否で目的stageへ到達しない負例、期待値がRuby自身に依存する部分、未対応の必須条件だけを不足として列挙する。既存証拠で満たす命題は再試験から外す。
4. 不足ごとに最小ケース案・独立oracle・固定環境/依存・上限・STOP条件を提示する。この段階ではfixture/試験コード作成、試験、外部archive取得、CIを開始しない。

矛盾、根拠欠落、未知依存/費用、権限拒否は該当部分をHOLDとして報告する。
本書は承認範囲の記録であり、新たな実行権限を付与しない。

## 初回の対応環境・保証範囲（Owner採用済み）

2026-10-24 UTC、OwnerはMRI4.0.9＋下記固定依存と、観測済みMBA/macOS arm64・
Ubuntu24.04/x86_64を初回の限定対象として採用した。これはOS全版、同じGem版の全native build、
providerの将来更新、他Ruby/engine/architectureの動作・安全性保証ではない。
RubyGemsのRuby版要件だけではMRI/OS/native identityを強制しない。

固定Gem依存：JSON2.19.9（Ruby同梱JSON2.18.0の代わりに使用）、
JWT3.3.0、base640.3.0、OpenSSL gem4.0.2、Digest3.2.1。
OpenSSL gem版とロードされるlibssl/libcrypto版は別に確認する。
包装版/実行時点の原記録と出所は保持し、この文書更新を新しい観測と呼ばない。

| 対象 | 採用範囲を支える既存の正確な観測・参照 | 保証しないこと |
| --- | --- | --- |
| MBA/macOS arm64 | MRI4.0.9 `arm64-darwin25`、MBA409-20261023-BUILD02/VALIDATION01の専用runtime、OpenSSL gem4.0.2/libcrypto3.5.9、Digest3.2.1/resolv0.7.2/zlib3.2.3。[PR174](https://github.com/cuichangquan/ap2-mandate-verifier/pull/174)のreport/source identityと[SUPPORT_CONTRACTの履歴](SUPPORT_CONTRACT.md#evidence-identifiers-for-this-runtime-update)、公開pre3のMBA409-PRE3PACKAGE02-20261023は[PR177](https://github.com/cuichangquan/ap2-mandate-verifier/pull/177)。885 source回帰とpre3 installed52は異なる記録 | Darwin25というplatform識別だけから全macOS版の対応を推定しない。追加のCPU/RSS/並列試験はない |
| Ubuntu24.04/x86_64 | 公開pre3の[run40038620413 attempt1](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/40038620413)、実行SHA `d34dbfa3a87a75360fb4bb14d535da8bc5e8cdc4`、[固定manifest](../research/pre3_linux_published/CURRENT_MANIFEST.json)。MRI4.0.9公式builder archive 49100121B SHA256 `046d1422e1be5575eadd55323c85c3efbeaee8c8e1c1bfccee343e28619cb3b3`、上記固定Gem、実ロードlibssl/libcryptoはUbuntu `libssl3t64:amd64 3.0.13-0ubuntu3.16`の所有権/整合性とnative hashを同runで照合。13 payload/10 loaded/52 installed | upstream文字列3.0.13だけの許可ではない。任意のUbuntu provider更新/runner imageを一括保証しない。885 source回帰・独立Linux Oracleの再実行ではない |

[公開GemのSUPPORT_CONTRACT](SUPPORT_CONTRACT.md)は包装時点のスナップショット。
その「pre3 Linux未観測」は当時の記録で、後続の上記成功は本追補/現状メモが補足する。
本PRでは包装13件、gemspec、原実測、公開Gemを変更しない。

最悪CPU/RSS・並行性能は保証対象外。利用側がプロセスの実行時間・メモリ・同時実行制限を設定する。
比較の子10秒/全体300秒、CI job15分等はハーネス制限であり、Gemが強制する期限/メモリquotaではない。
Stage19の7入力×3直列観測は残すが、製品最悪値や並行安全性の証明へ昇格させない。
将来数値保証が必要なら利用条件/測定入力/予算/合格値を別途決める。今は追加測定しない。

Gemの既存有限入力上限、署名前の厳格parse/重複拒否、署名・原wire/閉包、
7形状の型/制約、trust選択、Host binding、期限交差、Evidence/失敗閉鎖は引き続きGemが検査する。
これらを利用側へ移管したり省略したりしない。利用側の制限はその外側の保護である。
Hostは真正/最新の登録・注文/challenge・信頼時計・失効を提供し、利用直前の再照合、
nonce原子消費/注文CAS・未知結果の照合・最終ALLOWを担う。実Host運用は未実証、Evidence≠ALLOW。

採用済みなのは限定E06判断根拠と初回の対応環境・保証範囲のみ。
上記採用時点では完成判断前。その後の研究用コア第一段階完成判断は下記。元E06全体PASS、一般AP2対応、Phase2-A全面PASS/E10/本番GO、追加公開は未承認のまま。

## 研究用検証コア第一段階の完成判断（2026-10-24 UTC）

2026-10-24 UTC、Ownerは、信頼できる独立Host入力と信頼するRuby実行環境を前提に、
固定AP2 commit `b4587ac1d055888a73b4b21750973cffba961793`、
`ap2.checkout.single_merchant_sku` v1・7支持形状・採用済み環境を対象とする
**研究用検証コアの第一段階を完成と判断**した。
対象sourceの読解・同一性確認基準は `26cc5ce1c9bfc93be32dbba6e637b106d60cc68f`。
これは既存証拠・残余条件を採用した限定判断で、新しい試験結果や全パスの安全性証明ではない。
一般AP2、発行・提示生成、実Host運用、最悪CPU/RSS・並行性能保証、
元E06全体PASS、Phase2-A全面PASS、E10/本番GOは対象外。
歴史的通信会計2件と後続送信header/全通信128MiB遵守の未証明も保持する。
利用側の時間・メモリ・同時実行制限とGem自身の既存境界検査の責任分担は変わらない。
公開Gem・実装・原証拠の変更、追加公開や次段階の実行を承認するものではない。

判断根拠は[採用済み証拠対応表](E06_SCOPED_EVIDENCE_MAP.md)と本書の環境・責任境界です。
既存実装/試験と原記録を読み取りで照合した範囲で、採用範囲内の追加実装・必須試験を要する具体的未達条件は特定しませんでした。
この結論は未証明事項の解消や無欠陥保証ではなく、追加試験を行ったという意味でもありません。
既存の実装検査・旧API非成功・研究Evidence≠Host ALLOW・入力制限を保持します。
