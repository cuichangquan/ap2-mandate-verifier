# 初回本番候補：主張と既存証拠の静的監査

監査日：2026-10-26 UTC。基準main：`2dcd8ddb03e8da2aec4568de1d4b549f97f877da`（PR194後）。
状態：**過去の静的監査と採用判断を保持。現在の候補統合・Gate整理は末尾追補を参照／公開・本番HOLD**。用途・実Issuerは未定。
対象は既存固定profileの検証専用Gem。Host運用・決済・発行/提示生成は候補Gem外だが、Host前提は外さない。
Ownerは次のリリースで追加pre版ではなく**安定版を目指す**と明示した。版番号・公開GOは未承認。pre接尾辞を外すだけで十分とはせず、一般AP2対応やHost運用を追加必須対象にもしない。
本書は[計画G1](FIRST_PRODUCTION_CANDIDATE_PLAN.md)の読解結果で、[原Gate](PHASE2A_EXIT_GATE_DECISION_CHECKLIST.md)を上書きせず、新たなPASS/実行/公開を承認しない。
以下のコード行はすべて基準main。既存証拠の原本や公開Gemを変更・再実行していない。

## 重要結論

**pre3の入力・出力・検証範囲は確定済み。API再設計・改名を出発点にしない。**
[`lib/ap2_mandate_verifier.rb` L124–126](../lib/ap2_mandate_verifier.rb#L124)の全検査入口は`verify_research`。
旧`verify`は構文検査後も`unverified/verification_not_implemented`（L16–20）。
[`research_result.rb` L7–12/L70–72](../lib/ap2_mandate_verifier/research_result.rb#L7)は研究契約ID・`verified_research/scoped_research_verified`を返す。
これらは[pre3包装基準のSUPPORT_CONTRACT](https://github.com/cuichangquan/ap2-mandate-verifier/blob/20809b057c75d4145eff13e5c183d616c19ef696/docs/SUPPORT_CONTRACT.md#L51)と実装で一致する。研究用という名前は、それ自体が検査欠落や本番適用不能の証拠ではない。
先の「APIを確定する」という説明は、定義済み契約を未定義と誤解させるため訂正する。本番候補への採用は、**既存契約のままで主張する保証に既存証拠が十分か、保証除外とHost前提を受け入れられるか**の判断であり、新API/改名/別入口を今回提案しない。公開pre3は有効な研究用成果物として保持する。
後続の指定スレッド読解を統合し、E05の既存147回帰と独立比較の具体的対応を末尾に記録した。先の「対応が一つに追えない」は初回監査時点の状態で、今回の統合後は**主要拒否条件の対応整理済み／安定版候補への証拠採用判断待ち**とする。code一致を各段階の因果的な拒否証明へ拡大しない。

## source・package・環境・profileを分けた再利用確認

| 確認対象 | 今回の読み取り照合 | 再利用できない主張 |
| --- | --- | --- |
| 製品source10件 | 基準main、pre3包装基準`20809b057c75d4145eff13e5c183d616c19ef696`、MBA409検証source`7822fc2b11b6cb2df4c5b5495d747c0d730083bc`の全`lib/**/*.rb` Git blobが一致 | 同一sourceだけで別runtime/providerの動作・安全性を保証しない |
| 試験source | 基準mainとpre3包装基準の全test Ruby/Python blob一致。MBA409検証sourceとの差は`package_contents_audit.rb`/`packaged_gem_test.rb`のみ | 包装版期待値の変更を含むため885全件をpre3で再実行したとはしない |
| 因果/意味REPORTの製品SHA256 | [因果R1](../research/e06_causal_subset/results/R1/REPORT.json)と[意味R1](../research/e06_semantic_subset/results/R1/REPORT.json)の10件mapが一致し、[pre3 manifest](../research/pre3_linux_published/CURRENT_MANIFEST.json)のpayload SHA256と一致。manifestの10 product Git blobも基準mainと一致 | SHA256とGit blobを同じ値として比較しない。raw archiveの今回再取得/再検証ではない |
| package | 公開pre3 37888B / SHA256 `8ad627818dc69b450d0fba970dafaf368ec42dd64fb51eec631731027de3882c`。MBA/公開Linuxの13payload/10loaded/52installedは既存記録 | mainのREADME/SUPPORTは公開後追補で包装物と異なる。同版再build、新候補archive、独立Linux Oracleへ証拠を転用しない |
| 環境 | MBA409の885回帰はMRI4.0.9、pre3のMBA/Linux installed52は別記録。[JSON security R2](../research/security_json/results/R2/REPORT.json)はRuby4.0.1/JSON2.19.9の42入力（30独立契約＋12境界）、別途8 Schema判断 | 古いRuby実測を現在4.0.9の独立比較としない。現在の実環境安全性・脆弱性状況を今回再確認したわけではない |
| profile | TrustContext L7–10/75–78の固定body/hash、AP2 pin `b4587ac1d055888a73b4b21750973cffba961793`、7支持形状を継続 | 実Issuerの発行profile適合・一般AP2/全Schema互換性は未証明 |

上記source照合はGitHub固定tree/manifestの読み取りであり、手元runtimeを起動した確認ではない。
ローカルMBA409原ログは今回直接再読せず、[既存識別表](SUPPORT_CONTRACT.md#evidence-identifiers-for-this-runtime-update)のreport/source manifest/hashを利用した。原ログの公開取得可能性や第三者再現まで確認済みとはしない。
885、42、8、各4入力、52は異なる命題/時点で重複対照を含むため合計件数を作らない。

## 主張→実装→既存証拠→不足の判定

**「静的実装あり」「過去に限定観測」「本番保証として未採用」を別判定にする。** 試験sourceの存在だけを実行済みの証拠にしない。

| 主張 / Gate | コード・既存試験の箇所 | 実測として利用する根拠 | 残る不足・今回の判定 |
| --- | --- | --- | --- |
| 厳格入力・有限構文 E00/E07 | InputValidator L37–66：正確String snapshot、131072B、depth24、重複/非有限数拒否。RootSignature L27–43/83–109：JOSE、canonical base64url、公開P256。HostBinding L42–61等の個別上限 | 885の入力/署名境界試験、security R2の12境界。既存SUPPORTの各上限 | 実装/旧観測あり。入力有限≠CPU/RSS上限。全境界を現環境で再実測したとはしない。具体的な検査漏れは今回特定せず |
| 原署名・全域閉包 E02/E03/E04 | RootDisclosures L24–54/57–83：Root署名後に全域walk、3path、重複/未解決/余剰拒否。PurchaseBinding L42/51/70で3署名。`root_disclosures_test.rb`、`integration_matrix_test.rb` L129–162 | security R2のFULL/HIDDEN/UNKNOWN/DUPLICATE/EXTRA/DECOY等、独立署名/graph判断。因果/意味FULLで署名3件・graph正常復帰を保存 | 限定profileの構造/拒否根拠あり。integrationのTracePointはcall観測で正常復帰証明ではない。新しい全組合せ因果trace・全パス形式証明はないが、それを新必須試験としない |
| trust選択と未知/失効/旧profile拒否 E01/E05 | TrustContext L56–119：完全body/hash、role/tenant/purpose/key_ref一意、active/期限。`trust_context_test.rb` L41–96/124–153に未知/曖昧/profile/非active/別鍵等 | MBA409回帰記録と同一製品/該当test bytes。Host合成8件は生成後失効・旧鍵・rollback/更新不能のモデル観測 | Gemの検査とHostの外部信頼を混同しない。全E05異常を同じ独立署名/実stage oracleで結ぶ専用実測表は今回未確認。既存試験を未実装とせず、より強い本番主張ならこの紐付け差を先に評価 |
| 委任・購入原文・Host binding E02/E05/E08 | PurchaseBinding L44–75：cnf/Agent鍵、sd_hash、aud/nonce、Closed原文hash、Merchant署名/ID。HostBinding L62–81：B、参照、digest、鍵一致。`host_binding_test.rb` L94–134/196–200 | 既存独立O2/O5・885と同一source。因果/意味FULLと複合署名負例 | 供給されたHost値との一致は確認できるが、正本の真正性/現在性・実Buyer本人認証は証明しない。対称に改ざんしたHost入力をGem単独で排除する保証ではない |
| Schema/意味と順序 E06 | ScopedConstraints L28–75/88–109、[採用済み7形状表](E06_SCOPED_EVIDENCE_MAP.md)。3署名・bindingの後の実内容check | 因果4/4：S01はtext!89、price文字列はamount!97、署名破損は内容未到達。意味4/4：quantity2.0は公式Schema VALIDだがquantity!93、total201はtotals!109、別Merchant鍵は署名拒否 | 固定7形状の判断根拠はOwner採用済み。追加必須ケースは今回特定せず。公式Schema全対応、全field個別traceへ昇格しない |
| 時間交差と短い期限 E05/E08 | PurchaseBinding L56–66、HostBinding L83–87。`host_binding_test.rb` L94/136–161：terminal300/301、inclusive/exclusive、鍵/snapshot/challengeの最短期間 | 885内の既存境界。research Evidence試験もHost固定ケースを再使用 | 旧security R2でterminal+301単独最短未実測という歴史制限は残すが、既存source試験の300/301/最短試験を無視して新規必須扱いしない。実時計・時刻後退・運用失効はHost前提 |
| Evidenceと失敗閉鎖 E08 | ResearchResult L44–60/70–75、Result L33–49：拒否/不能は非成功nil。ResearchEvidence L14–38：深いfreeze/私有constructor。`research_evidence_test.rb` L55以降 | 既存885/installed52、因果/意味FULLの全Evidence期待値一致と負例nil | 検査事実のみ。private constructorは悪意ある同一Rubyからの防御でなく、Hash再構成・別プロセス真正性・Host ALLOWを保証しない。stable API採用は未決 |
| 配布/再現 E09 | 固定manifestの13payloadと10 product blob、原入力/期待値・pin/hash | [pre3 Linux run40038620413](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/40038620413)は公開archive13/10/52。MRI4.0.9/固定依存、Ubuntu実provider所有/整合性の既存観測 | saved MBA期待値の再生で独立Linux Oracleではない。新しい候補、将来provider/OS、全runtime attestationは対象外。未合意の完全attestationを新完成要件にしない |

## 優先する残作業（実行は未承認）

1. **既存証拠の採用判断・最優先**：下記E05対応とS1〜S4案を、既存API契約を変えずに安定版の条件として採用できるか判断する。主要対応は整理済みだが、全E05の因果段階を独立に実測済みとはしない。不足が確定した個別主張だけを記録し、試験を自動追加しない。
2. **証拠採用の差分**：E02/E03/E04/E05/E08の既存試験/独立比較を、本番で要求する命題に十分か判定。特にE05は回帰と独立期待値/実stageの紐付け水準を明確化。不足が確定した個別命題だけ追加検証候補とし、今回一律rerunを提案しない。コードの具体的欠落・脆弱性はこの読解では確定していない。
3. **資源/環境/保守**：既存byte上限以外の時間・メモリ・同時実行条件をHost前提として定義し、実効保護と想定負荷の必要証拠を決める。最悪CPU/RSS・並行性能、現在のRuby/Gem/native/provider安全性、実環境は未証明。新しい観測/依存更新は別承認。脆弱性受付・更新/廃止・サポート方針は既存資料を基に本番契約として決定する。
4. **用途/Issuer/Host待ち**：主体・用途承認、真正鍵/更新失効正本・鮮度・rollback防止、信頼時計・注文/challenge正本、認証/照会権限、利用直前の再照合・原子消費/注文CAS・PENDING回復を利用条件へ明記。具体環境の成立は未確認。Host実装は候補Gem外であり、本番adapter追加を今回要求しない。特定Issuer/Hostの互換性・運用GOは別判断までHOLD。
5. **公開判断待ち**：候補版/source/環境/差分を確定して必要な包装・導入・回帰/独立比較を別計画にする。新候補に旧archive証拠を流用しない。重大指摘なしレビューだけで本番GOとしない。E10/Phase2-B等は独立判断。

過去の通信header/総128MiB、Docker全期間物理増分の未証明は保持する。Gem自体のネットワークI/Oではないが、供給工程の主張への影響と採用可否をOwnerが判断する。過去値を復元済みとせず、全実験再実行を要求しない。
本番向け条件付きGem配布をどこまで主張できるかと、特定Host運用GOは別。実Issuer未定が解決済みという意味ではない。

## 訂正後の分類と、実際にリリースを阻むか

| 分類 | 項目・現状 | 初回検証専用Gemのリリースとの関係 |
| --- | --- | --- |
| **既に満たす（現行契約内）** | 7入力、ResearchResult/Evidence、rejected/unavailable・旧API非成功、固定profileと有限構文/byte/depth/count制限は実装・SUPPORTに定義済み。source同一性と既存回帰/独立比較/包装観測は上表の範囲で根拠あり | 未定義APIの設計や全件再実行は不要。研究用契約から本番保証への自動昇格はしない |
| **既に満たす（Owner採用した証拠水準）** | E06の固定7形状について既存対応表・代表因果観測を採用済み、具体的な追加必須ケースは未特定 | 一般AP2/全Schemaを求めない初回候補に、全field新規traceや汎用Schema実装を必須化しない |
| **証拠の紐付け・採用水準の残余** | E05主要拒否のT/I対応は下記に整理済み。全条件の独立因果stageは未確認。MBA409原ログは今回直接再読せず識別表を参照 | 採用する命題に対する証拠水準の判断が残る。動的未検証と同義でなく、新規試験必須とはまだ言えない |
| **具体的な未検証** | 最悪CPU/RSS・一般並行性能、実環境での外側制限の実効性、現在/将来の全provider安全性は未証明。過去の固定provider確認は時点付き | 有限入力上限がないという意味ではない。数値性能保証を除外し利用側制限を条件に配布する場合、一律にGem改修/ストレス試験が必須とは断定できない。想定負荷・保証したい値・配布対象環境がないため採用可否は判断材料不足 |
| **用途/Issuer/Host次第** | 実主体/用途許可・真正鍵/失効鮮度・信頼時計・最新注文・原子消費・実障害回復・認証権限は未証明 | 実Issuer/Hostへの適用GOには必要。条件付き検証Gemの配布と分離する場合も利用条件に残し、Gemが代替すると書かない。必要情報は用途、対象Issuer/profile、Hostの正本/時計/失効/消費の責任者と成立根拠 |
| **対象外** | 発行/提示/Payment Mandate生成、Receipt、実決済、Host DB adapter、一般AP2/多profile・他言語core | 初回候補の追加必須実装ではない。将来SDKビジョンと区別 |
| **保証・公開判断の不足** | 初回候補としての証拠採用、本番向けサポート/更新方針、候補版/配布物/対象環境、Owner公開GOがない | 未公開の次版本番候補を公開済みと扱えない。既存API契約を書き直す必要を意味しない。新候補が未確定なので包装/導入の新検証も未実施だが、今すぐ再buildする根拠ではない |
| **歴史的会計未証明** | 過去通信量/送信header、Docker全期間物理増分は未証明 | 現行Gemに通信や容量制御の欠陥がある根拠ではない。過去予算全面遵守を主張しない。これが条件付きGem配布を阻むかは供給工程の採用判断で、再取得/研究再実行を自動要求しない |

この監査で、初回候補範囲に対する**具体的な未実装欠落や、既存証拠では絶対に覆えない追加必須試験は確定していない**。未確認を安全確認済みへ繰り上げることも、未確認だけで無条件に試験を増やすこともしない。
必要な次の情報は、既存保証除外（最悪性能/実環境安全性等）とHost前提を条件とする配布を目指すか、さらにどの保証を要求するか。本番GO・公開承認は引き続き未取得。

## 引き継いだ証拠対応（E05）

出典：指定Codexスレッド「安定版公開Gateを具体化」`01a175af-3639-7da3-a9f2-d29f0b5ae429`の完了回答（正式read_threadで読解）。同スレッドの基準mainも本書と同じ。以下はその提案を既存監査へ統合したもので、追加実測ではない。
T＝[trust_context_test.rb](https://github.com/cuichangquan/ap2-mandate-verifier/blob/2dcd8ddb03e8da2aec4568de1d4b549f97f877da/test/trust_context_test.rb)。**147件は885回帰の内数**。
I＝[security JSON R2 REPORT](https://github.com/cuichangquan/ap2-mandate-verifier/blob/2dcd8ddb03e8da2aec4568de1d4b549f97f877da/research/security_json/results/R2/REPORT.json)。**Ruby4.0.1/JSON2.19.9の独立比較で、4.0.9独立再実行ではない**。

| 拒否条件 | code | T / Iの具体的対応 |
| --- | --- | --- |
| 必須/余剰field・型・records数 | invalid_trust_context | T：role必須field、unknown、0/17、時刻/active型 |
| body/hash・envelope・selection矛盾 | trust_context_mismatch | T：snapshot/profile hash、id、policy、Merchant identity |
| 未知profile/version/algorithm・定義bytes | unsupported_trust_profile | T：別定義、空白差、誤った開示path。I：PROFILE_VERSION |
| 選択鍵なし | trust_key_not_found | T：各role identity/tenant/purpose/key_ref差。I：UNKNOWN_KEY |
| 複数鍵一致 | ambiguous_trust_key | T：重複、一方inactiveでも曖昧拒否。I：AMBIGUOUS_KEY |
| snapshot無効/期間外 | inactive_trust_snapshot / trust_snapshot_time_mismatch | T：失効/未来/終了境界。I：SNAPSHOT_REVOKED |
| 鍵無効/期間外 | inactive_trust_key / trust_key_time_mismatch | T：3roleのactive/期間。I：REVOKED_KEY / KEY_EXPIRED |
| PEM/fingerprint不正 | invalid_trust_key等 | T：URL、不正PEM、余分な改行、fingerprint差。大文字digestは構文拒否 |
| JSON構文/重複/上限 | invalid_json / duplicate_key / input_too_large | T：壊れたJSON、重複body/selection、上限。I：入力境界比較 |
| 登録鍵と実署名鍵が不一致 | agent_key_mismatch / invalid_root_signature | T：3role別鍵。I：WRONG_AGENT_KEY / WRONG_MERCHANT_KEY |
| 登録profileと開示形式が不一致 | unsupported_disclosure_profile / missing_disclosure等 | 独立六分類のUNKNOWN/HIDDEN/DUPLICATE/EXTRA/DECOY。各codeは原REPORTを参照 |

Tのsource存在とIのcode比較を合わせても、全T条件の独立実測とはならない。供給されたtrust検査を実Issuer本人確認・最新失効・運用rotation/rollback防止へ昇格しない。Iの入口/イベント記録は各stage正常復帰の証明ではなく、因果復帰/拒否stageはPR182/183の該当入力の範囲に限定。
この閉じた範囲の**具体的な追加必須ケースは今回特定されていない**。採用する命題とsource/runtimeの対応を判断し、不足が具体化した部分だけ別検証候補とする。

## 安定版公開Gate（S1〜S7、判断基準Owner採用済み）

以下は元スレッドの提案を文書化し、2026-10-26 UTCにOwnerが**安定版公開の判断基準として採用**したもの。採用は各Gateの合格・既存契約の安定版保証への採用完了・Gem公開承認ではない。既存API定義、安定版目標、初回候補範囲の承認とも区別する。元E00〜E10を置換/緩和せず、Gem公開GO・特定Host本番GOとも分離する。

| Gate | 完了条件・既存根拠 | 残る作業/Owner判断 |
| --- | --- | --- |
| S1 公開主張/互換性 | 固定AP2/profile/body/hash・既存入口/引数/status/code/Evidence v2・旧API非成功を維持し、対応環境・非保証を安定版契約として明示。SUPPORT/完成条件を再利用 | 安定版としての採用判断。同じ支持入力/前提で判定意味を維持し、安全性修正で受理範囲を狭める際の理由/影響/移行告知を明文化。新profile/依存更新を黙って互換扱いしない |
| S2 証拠充足 | 主張→実装→試験→独立期待値→観測→source/runtimeを対応。既存E06採用・上記T/I・原結果を再利用し、重大欠落なし | E06以外も含む候補全体の証拠採用水準を判断。具体的欠落が確定した場合だけ追加検証を計画 |
| S3 環境/依存 | MRI4.0.9、JSON2.19.9/JWT3.3.0/base640.3.0/OpenSSL gem4.0.2/Digest3.2.1、採用済みMBA/macOS arm64・Ubuntu24.04 x86_64の正確な観測構成を基礎に、候補時点のnative/provider出所・修正状況を確認。重大未対処問題なし | 安定版候補時点の確認と環境範囲採用。全OS版/他Ruby/Windows/Intel Mac/任意provider更新を自動保証せず、過去観測を現在安全性へ転用しない |
| S4 保守 | 担当・報告窓口・対象版・更新/廃止通知・脆弱性受付と対応方針が明確。SECURITY/POST_RELEASE_MAINTENANCEを再利用 | 安定版保守方針を採用。月次・勧告判明時・次版前の手動確認は案であり、未稼働監視/SLAを宣言しない |
| S5 候補実体 | preでない版・source SHA・同梱文書・archive SHAを固定し、承認後に差分相応の回帰/包装/導入/ロード同一性を確認 | 版/候補archiveは未確定・未検証。新候補を旧pre3の検証済みarchiveと扱わない。必要実行は別承認 |
| S6 レビュー | 候補最新HEADの独立Codex完了、重大P1/Gate重要P2未対処なし、未解決thread0 | 将来候補HEADのレビュー。過去PRや本監査の静的確認では代替しない |
| S7 Owner公開GO | 版・配布先・保証範囲・残余・供給工程不足を指定した明示GO | 未承認/HOLD。文書の採用/統合をGem公開GOに読み替えない。特定Host運用GOはさらに別 |

## 採用後の現状と次の作業（2026-10-26 UTC）

**S1〜S7は判断基準として採用済み、全7項目の合格は未判定。** 以下は作業の現在地であり、新しい実測結果や公開GOではない。

| Gate | 確認済み | 不足・次の作業 |
| --- | --- | --- |
| S1 | 既存API契約、固定profile検証専用・安定版目標、Host境界は定義/範囲決定済み | 既存APIを維持した安定版の保証/非保証・互換性/安全性修正時の告知を契約案に明示し、Ownerが採用判断。再設計/改名を前提にしない |
| S2 | 本書のsource/package/runtime対応、147回帰（885の内数）、旧runtime独立比較、限定E06採用を整理済み | 初回候補の主張に対する証拠水準の採用判断。具体的な追加必須試験は今回未特定。code一致を全拒否段階の因果証明としない |
| S3 | 過去のMRI4.0.9/固定依存・MBA/Ubuntuの正確な観測構成は保存済み | 候補時点の配布環境・依存/native/provider出所と修正状況、更新範囲を確認。過去観測を現在安全性としない。今回は追加調査/実行なし |
| S4 | SECURITY/公開後整備の窓口と既存方針あり | 安定版の担当・対象版・更新/廃止・報告対応条件を具体化し採用判断。未稼働の監視やSLAを宣言しない |
| S5 | 公開pre3のbytes/SHAと包装/導入観測は保存済み | 安定版の版/source/同梱文書/archiveは未確定。候補差分に必要な検証範囲を別計画・承認後に実施。旧archive結果を流用しない |
| S6 | 過去の文書/製品PRのレビューは各HEADの記録として存在 | 安定版候補の最新HEADレビューは未実施。本書のレビュー/統合では代替しない |
| S7 | 判断基準採用と文書保存の承認のみ | 版・配布先・保証範囲・残余/供給工程条件を指定した公開GOは未承認。用途/Issuer未定、特定Host本番GOもHOLD |

まずS1/S2の契約・証拠採用案とS4の既存保守方針との差分を最小限にまとめる。追加試験は具体的不足が確定した場合だけ別承認にする。Host運用・決済・発行/提示は候補Gem外だが、Hostの信頼/最新状態/時計・原子消費・最終ALLOWの前提は残す。

## 非保証・前提として整理できる範囲と公開停止条件

「免責可能」は法的免責の成立ではなく、**保証対象外/利用前提として整理可能**という意味。
実Issuer・実Hostの未実証は特定導入の本番GOを止めるが、限定Verifier配布を常に止めるとは限らない。この非保証/前提の具体的な安定版契約への採用と、各Gateの充足判定は未了であり、公開HOLDを維持する。

| 項目 | 非保証/前提として整理する案 | 公開を止める条件 |
| --- | --- | --- |
| 実Issuer | 特定主体/用途/鍵の真正性・互換性は保証せず、実利用前に登録票とHost根拠を要求 | 合成profileを実Issuer対応済みと表示、未確認をactive=trueで埋める、Gemの登録検査欠落 |
| Host運用 | 認証・時計/失効/最新注文・nonce消費/注文CAS・PENDING回復・決済はHost側 | Gem自身のbinding/期限/失敗閉鎖の欠落、EvidenceをALLOWとする案内 |
| 性能 | 最悪CPU/RSS/並行性能・数値SLAは非保証。Hostの外側実行制限を要求 | 既存有限入力上限が不成立、支持入力の既知重大資源問題、根拠のない性能保証 |
| 非対応環境/一般AP2 | 支持範囲外と明示し非保証、未対応形式は拒否 | 支持環境内の既知重大問題を環境依存として除外 |
| 過去通信/容量会計 | 不足を保持し製品命題/供給工程への影響を個別判断 | 合格への書換え、供給物の出所/完全性に影響する不明点を残した公開 |

Gem自身が約束する検査の欠落/失敗は非保証表示で補えない。安全性修正、原Gate、実Issuer/Host前提、未証明会計を隠してGateを満たしたとはしない。

## 引き継ぎと今回承認の境界

元スレッドのユーザー指示は「読み取り専用の調査と提案だけ」「未承認のコード変更、テスト、CI、DB操作、費用発生、公開・マージは禁止。本番GOはHOLD」。その完了回答内のGateは採用済み決定ではない。
その後の別承認で成果を既存監査案へローカル統合・静的確認した。さらに本文書1件のPR・Codexレビュー・条件付きmain統合が承認された。元スレッドの読み取り指示と、後続の文書統合/リポジトリ保存承認は各時点の範囲として区別する。その時点ではGate採用・Gem公開・本番GO・動的検証は未承認だった。後続の2026-10-26 UTCのOwner判断でS1〜S7を判断基準として採用し、その記録・現状整理の文書PR/レビュー/条件付き統合が承認された。各Gate合格・Gem公開・本番GO・追加実行は承認されていない。
最短の次工程は、S1の既存契約・互換性/保証除外とS2の証拠採用水準を具体的な安定版契約案として照合し、未決事項だけ判断すること。S3候補時点確認、S4保守条件、S5候補実体、S6候補レビュー、S7公開GOも残る。版番号や試験回数は今回決めない。

## 確認できなかった範囲・今回の操作

主張と既存資料/製品/試験source/保存REPORTの静的照合まで。候補runtime起動、旧ローカル原ログの直接再照合、現在の脆弱性調査、性能実測、実Issuer照会/外部連絡は行っていない。
workspaceの`.agents`/`.codex`ディレクトリは不存在。固定remote treeにも追加AGENTSや`.agents/skills`なし、root AGENTSとIssue101を適用した。
監査・文書保存では追加試験・構文実行・Docker・取得/導入・Gem build・製品コード変更・Actions・Gem公開なし。本番HOLDを継続。


## 0.1.0候補検証後の追補（2026-10-26 UTC）

上記の未決/未実施は各監査時点の記録であり、現在地は本節と[候補証拠](../research/stable010_candidate/README.md)を参照する。Ownerは既存APIを維持する固定profile検証専用Gemの具体条件（保証/非保証、Host前提、対応観測環境、互換性、初回安定系列の最新修正版のみ・月次/勧告時/次版前の手動保守、期限SLAなし）と限界付き既存証拠を採用した。0.1.0は候補番号として承認され、公開GOではない。

| Gate | 確認済み・現在の判定材料 | 残余/次工程 |
| --- | --- | --- |
| S1 | 採用済み条件を候補README/SUPPORTへ記載。既存7入力/status/code/Evidence/旧API非成功・製品10件は不変 | 今回のsource統合レビューで記述と実体の一致を確認。新API/改名は不要 |
| S2 | 885（147を含む）、旧Ruby4.0.1独立比較、限定E06因果/意味を限界付き採用。同一製品/固定依存と新候補の13/10/52を対応 | code一致を全拒否stageの因果証明にしない。新たな追加必須試験は今回未特定 |
| S3 | MBA D3の10component identity predicates、Ubuntu実ロード/出所/完全package版/所有/整合性、JSON native identityを保存 | 全runtime安全性PASSではない。OS dyld hash/全binding未証明、JSON勧告metadata不整合を保持。範囲・残余をS7で提示 |
| S4 | 保守担当/窓口、最新patchのみ、手動見直し、更新/廃止告知、期限SLAなしを採用しSECURITY/保守文書へ反映 | 自動監視の稼働や将来の無制限実行承認を意味しない |
| S5 | 0.1.0、43,008B、SHA256 `0553645fa6c067dd8d7a7a1a7cdf13799370393e76dc3bc4ba161ab2ca5981b0`をMBA/Ubuntuで各1回13/10/52確認。source manifestと同梱bytes一致 | 今回source保存で新archiveを作らない。同梱NOT_RUNは包装時点の履歴、後続成功は外部追補 |
| S6 | PR197の検証基盤レビューは完了 | 候補sourceを含む今回の最新HEADレビュー・未解決0が別途必要。過去receiptで代替しない |
| S7 | 未承認/HOLD | exact archive・配布先・主張/残余と供給工程条件を示したOwner最終公開GO。特定Host運用GOはさらに別 |

この追補は旧観測/失敗を成功に書き換えない。D1/D2 STOP、D3 limited identity、Mac/Ubuntu packagingを別ID・原本hashで保持し、個人task pathの公開版置換を明示する。過去通信/容量不足、実Issuer/Host・最悪資源等の未証明も残す。追加試験、Gem再build、Actions再実行、公開は今回行わない。



## 文言整理後の新archive R2（2026-10-26 UTC）

R1統合後、公開向け文書の整理だけを別承認し、新R2を作成しました。README/SUPPORT_CONTRACT/gemspec説明文だけを変更し、API・依存・製品10件は不変です。新SHA `37b2a235b6fab2d9d9765ae985dd9db27afd3b2c5407fe263a6b65314550db32` / 34,304B、[R2 source/原結果/由来](../research/stable010_release_linux_package/README.md)を正本とし、R1結果を新bytesの証拠へ転用しません。MBA13/10/52は1回PASS、R2 Ubuntuは準備時点で未実施。新workflowはmanual-onlyで、当該HEADレビュー/統合後に承認済み1runのみ実行します。

S1は日英の現行導入/利用契約へ整理、S2の限界付き既存証拠採用とS3/S4の範囲は不変。S5は新archiveに対して環境別に判定し、S6は各準備/結果追補の最新HEADレビューが必要、S7は別Owner公開GO待ち。全Phase2A/実Issuer/Host運用/最悪資源保証へ昇格しません。既存885は製品/固定依存同一性により再利用し、今回再実行しません。
