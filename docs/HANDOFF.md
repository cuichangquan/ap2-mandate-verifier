# AP2 Mandate Verifier for Ruby — 開発引き継ぎ指示書 / TODO

更新日：2026-10-11
状態：**P0-1〜P0-5b・P1-0〜P1-5完了。P1-5は署名付きセキュリティ負例18ケースでGREEN 11 / RED 6 / Host replay境界1 / ERROR 0、P1-1〜P1-3回帰43件PASS**。次は**P1-6：研究用6 RED対策（別途承認必須）**。現状の研究用Verifierには想定外の受理が残る。**汎用Gem/API実装HOLD、RubyGems公開・Production/実決済NO-GO**。GCP/実決済/Host replay/Receiptは未実施。

## 1. 新しいチャットで最初に読むこと

**正本（GitHub main）：** https://github.com/cuichangquan/ap2-mandate-verifier/tree/main

作業開始時にGitHubの最新 `main`、既存Issue、Open PRを確認すること。過去の会話や、この指示書中のSHAを無条件に最新状態として扱わない。

読む順番：

1. [README](../README.md) — Gemの目的・利用シーン・非スコープ
2. [PROJECT](PROJECT.md) — D001〜D006、責務境界、独立OSS方針
3. [SPEC_BASELINE](SPEC_BASELINE.md) / [VERIFIER_REQUIREMENTS](VERIFIER_REQUIREMENTS.md) / [ECOSYSTEM_RESEARCH](ECOSYSTEM_RESEARCH.md) / [API_PROPOSAL](API_PROPOSAL.md) / [RESEARCH_DECISION](RESEARCH_DECISION.md) / [PYTHON_BASELINE_VERIFICATION](PYTHON_BASELINE_VERIFICATION.md) / [FAIL_CLOSED_PROFILE](FAIL_CLOSED_PROFILE.md) / [RUBY_FEASIBILITY_SPIKE](RUBY_FEASIBILITY_SPIKE.md) / [RUBY_SDJWT_RESEARCH](RUBY_SDJWT_RESEARCH.md) / [RUBY_DELEGATION_SPIKE](RUBY_DELEGATION_SPIKE.md) / [RUBY_CHECKOUT_BINDING_SPIKE](RUBY_CHECKOUT_BINDING_SPIKE.md) / [SECURITY_GAP_REVIEW](SECURITY_GAP_REVIEW.md) / [SECURITY_NEGATIVE_TESTS](SECURITY_NEGATIVE_TESTS.md) — Ruby Root/2hop/Checkout、P1-4静的レビュー、P1-5 RED 6の実測
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

### Phase 0 — 仕様・競合調査【P0-1〜P0-5b完了 / Ruby P1-0〜P1-5完了 / 次はP1-6】

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

- [ ] **P1-6：6 REDに対する狭い研究用対策・再検証（次の1件／別途明示承認）**
  - 署名済JWTの重複JSONキー/JOSE拒否、Closed内部時刻/期限、Merchant `typ`、strict Checkout未知fieldを研究Verifierに限定して対策。18負例＋43回帰の結果を再実行/記録。
  - **成果物案：** `docs/SECURITY_HARDENING_RESEARCH.md` と研究コード/テストのみ。Gem雛形/API/RubyGems、GCP/実決済、Host永続nonce/Receiptは禁止。









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

**P0-1〜P0-5b、P1-0〜P1-5完了。最新はP1-5署名付き負例実測。** [SECURITY_NEGATIVE_TESTS](SECURITY_NEGATIVE_TESTS.md)、[RESEARCH_DECISION](RESEARCH_DECISION.md) §15、[P1-4レビュー](SECURITY_GAP_REVIEW.md)を必ず参照。

**最重要結果:** GitHub Actions [#38127279271](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38127279271)で、固定AP2 v0.2 Python SDK署名済Open/Closed＋Merchant実署名JWTによる**18観測、GREEN 11 / RED 6 / HOST_BOUNDARY 1 / ERROR 0**。既存Ruby回帰43テストはPASS。**6件の想定外受理（RED）は未修正。** REDはduplicate Merchant JSON `id`、JOSE `alg` duplicate、Expired Closed `exp`、未来Closed `iat`、想定外Merchant JWT `typ`、未知Checkoutフィールド。初期Strict Profileのfail-closed policyに対する結果であり、一般AP2仕様違反や実決済攻撃成功とは言わない。

**実行環境:** GitHub Actions GitHub-hosted Ubuntu/Ruby3.3 + `jwt 3.3.0`、Python3.11・固定SDK SHA `b4587ac1d055888a73b4b21750973cffba961793`。P1-5 observerはRED時に**exit 1**、workflowはログ保全のためそのstepだけ`continue-on-error: true`。全体successと安全性PASSを混同しない。研究用CIはマージ時点で**手動起動専用**。

**判断:** 汎用Gem/API実装**HOLD**、公開・Production/実決済**NO-GO**。研究用の最小対策P1-6のみCONDITIONAL GO候補。Issuer trust key-ID管理、unknown SD-JWT layout、atomic nonce/replay、Revocation/Receiptと実Host認可は未実装。

**次の1件（別のユーザー明示承認後のみ）：P1-6。** 既存Ruby研究Verifierを限定して6 REDをGREENにするための最小修正、P1-5 18ケース＋過去43回帰を再実行。結果を`docs/SECURITY_HARDENING_RESEARCH.md`に記録。Gem/公開API/実決済/GCP/Host永続state・他OSS変更は禁止。

### 次チャット用指示文

```text
ap2-mandate-verifier P1-6を開始します。
https://github.com/cuichangquan/ap2-mandate-verifier

最新main/Issue/Open PRを確認し、
docs/SECURITY_NEGATIVE_TESTS.md、docs/SECURITY_GAP_REVIEW.md、
docs/RESEARCH_DECISION.md §15、research/p1_5/observe_security_negatives.rb、
research/p1_5/generate_signed_negatives.py と P1-1〜P1-3の研究コードを読む。

P1-5では署名付き負例18観測中6 RED（予期しないACCEPTED）を実測。
過去43回帰はPASS。CIがsuccessでもP1-5 observer stepはREDでexit 1。
今回は研究コードだけで6 REDをFail Closedへ修正し、
同じ18負例（N00〜N17）と43既存回帰を再実行してください。
Root/Terminal署名・JWT original bytes/Hashの完全性を保ったまま、
JSON重複キー、Closed内部iat/exp、JOSE typ、未知Checkout fieldを対策。
Hostのatomic replay/失効/Receiptは別責務のままにしてください。

docs/SECURITY_HARDENING_RESEARCH.mdにGREEN/RED/ERRORを証拠付きで記録。
Gem/API/公開/Production・実決済・GCP・他OSS変更は禁止。
次段階への自動GO判断をしない。PRレビュー後mainへマージ。
```
