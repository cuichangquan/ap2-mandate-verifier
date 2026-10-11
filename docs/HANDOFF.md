# AP2 Mandate Verifier for Ruby — 開発引き継ぎ指示書 / TODO

更新日：2026-10-11
状態：**Phase 0 / P0-1〜P0-5a 完了（判断：HOLD）。公式Python SDK 186 PASS / 2 FAIL、追加の実署名負例12 PASS、先行隔離サブセット11 PASS**。Ruby Gem実装・公開・適合性検証・本番安全性検証は未実施。

## 1. 新しいチャットで最初に読むこと

**正本（GitHub main）：** https://github.com/cuichangquan/ap2-mandate-verifier/tree/main

作業開始時にGitHubの最新 `main`、既存Issue、Open PRを確認すること。過去の会話や、この指示書中のSHAを無条件に最新状態として扱わない。

読む順番：

1. [README](../README.md) — Gemの目的・利用シーン・非スコープ
2. [PROJECT](PROJECT.md) — D001〜D006、責務境界、独立OSS方針
3. [SPEC_BASELINE](SPEC_BASELINE.md) / [VERIFIER_REQUIREMENTS](VERIFIER_REQUIREMENTS.md) / [ECOSYSTEM_RESEARCH](ECOSYSTEM_RESEARCH.md) / [API_PROPOSAL](API_PROPOSAL.md) / [RESEARCH_DECISION](RESEARCH_DECISION.md) / [PYTHON_BASELINE_VERIFICATION](PYTHON_BASELINE_VERIFICATION.md) — 仕様・要件・エコシステム・API案・HOLD判断・限定実行結果
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

### Phase 0 — 仕様・競合調査【P0-1〜P0-5a完了（Ruby実装HOLD）/ P0-5bが次】

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

- [ ] **P0-5b：初期Checkout Verifierの最小Fail Closed ProfileとGO/HOLDの再判定（次の1件、設計のみ）**
  - Issuer trust anchors、terminal/intermediateのaud/nonce、Openの必須開示、Checkout JWTのmerchant署名・hash、Host最終業務認可の条件を文書化する。
  - **成果物案：** `docs/FAIL_CLOSED_PROFILE.md` および `docs/RESEARCH_DECISION.md` 更新。Ruby Gem実装・公開なし。ユーザーの明示承認後のみ進める。


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

**P0-1〜P0-5aの研究・実行検証は完了。Ruby PoC判断はHOLDを継続。** [PYTHON_BASELINE_VERIFICATION](PYTHON_BASELINE_VERIFICATION.md)には**公式188件の186 PASS / 2 FAIL**、**フルSDK独立負例12 PASS**、**先行stub化サブセット11 PASS**を別々に記録している。完全成功やAP2適合性の主張は禁止。

公式失敗は `kb_sd_jwt_intermediate_tests.py::test_verify_rejects_aud_mismatch` と `::test_verify_rejects_nonce_mismatch`。中間hopでの期待値検査が省略される実装とテスト期待の差異であり、仕様上の扱いは未決定。実署名Selective DisclosureではMerchant制約を隠して可視LineItemsだけ評価すると違反0件になるケースを確認。Issuerがその項目を選択的開示可能にした状況での結果であり、商用攻撃の成功とは解釈しない。

**次の1件（別の明示依頼後のみ）**：P0-5b — [API_PROPOSAL](API_PROPOSAL.md) と実測結果を使って、初期Host向け最小Fail Closed Profile（trusted issuer、aud/nonce、required disclosure、merchant-signed Checkout JWT/hash、最終業務認可）を**設計文書だけ**で確定候補とし、P0-5 GO/HOLDを再判定する。Ruby Gem/PoC実装・公開、GCP/実決済・ActingFor/a2a-rails変更は禁止。

### 次チャット用指示文

```text
ap2-mandate-verifier P0-5bを進めます。
https://github.com/cuichangquan/ap2-mandate-verifier

最新main・Issue・Open PRを確認し、
docs/PYTHON_BASELINE_VERIFICATION.md、docs/RESEARCH_DECISION.md、
docs/API_PROPOSAL.md、docs/VERIFIER_REQUIREMENTS.mdを読んでください。

AP2 v0.2固定Commit b4587ac1d055888a73b4b21750973cffba961793。
公式Pythonテスト188件中186 PASS / 2 FAIL（intermediate aud/nonce）。
追加フルSDK負例12件PASS（実署名Selective Disclosureの非開示Merchant制約含む）。
これらの実測と仕様のMUST/Host policyを区別してください。

今回は初期Checkout Verifierの最小Fail Closed Profileの設計と
GO/HOLD判断更新のみ。docs/FAIL_CLOSED_PROFILE.mdと
docs/RESEARCH_DECISION.mdへ根拠を記録し、PRでレビュー後mainへ。
Ruby Gem/PoC実装、リリース、GCP利用、他OSS変更は禁止。
```
