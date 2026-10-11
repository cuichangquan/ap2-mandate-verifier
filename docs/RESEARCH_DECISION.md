# Research Decision — Phase 0 / P0-5 (GO / HOLD / NO-GO)

> **最新判定は§27（P1-10f）：E-R01/R02の独立ハーネス構築は条件付き推奨だが、実装未承認・NOT RUN。既存Host正本9/34件実測・25件NOT RUN、HC06分散安全性HOLD。汎用Gem/API実装HOLD、公開/本番/実決済NO-GO。**

**判断日:** 2026-10-11 JST  
**決定:** **HOLD — Ruby Gem / 最小Ruby Checkout Mandate PoCの実装開始をいったん保留**。  
**推奨する次の研究:** AP2公式Python SDK `v0.2.0` 固定ソースを**隔離・オフライン中心**に実行し、公式テストと優先負例を検証して再判定する。**この文書のマージは実装承認や次タスクの自動実行ではない。**

## 1. 判断の対象と限界

本プロジェクトは、AP2 v0.2のMerchant側 **Checkout Mandate Verifier** を、小さなRubyライブラリとして提供すべきか検討する。ここでの **GO = 非本番・最小Ruby PoC実装へ進んでよい**、**HOLD = 証拠不足の間はRubyコード実装しない**、**NO-GO = この企画の開発投資を止め既存技術利用等へ切り替える**、と定義する。

- **今回の選択はHOLD。** Ruby Gemの雛形、公開API確定、依存Gem追加、サンプルアプリ、Rubyでの検証実装、公開は**認めない**。ここまでP0-1〜P0-4は調査・設計文書のみ。
- **HOLD ≠ 中止 / NO-GOではない。** 根拠ある需要・独自価値と低コストの検証余地があるが、セキュリティ境界に実証不足が残る。
- AP2の規範は固定tag `v0.2.0` / commit `b4587ac1d055888a73b4b21750973cffba961793`（[SPEC_BASELINE](SPEC_BASELINE.md)）。Python package metadata `version="0.1"`、Checkout `vct`末尾 `.1`とは別。
- 判断の入力： [VERIFIER_REQUIREMENTS](VERIFIER_REQUIREMENTS.md)（MUST / SHOULD / Host境界）、[ECOSYSTEM_RESEARCH](ECOSYSTEM_RESEARCH.md)（公式SDKの**静的**検討とRuby候補）、[API_PROPOSAL](API_PROPOSAL.md)（**未実装**API草案）、[PROJECT](PROJECT.md)（D001–D006）、[SECURITY_BOUNDARY](SECURITY_BOUNDARY.md)。
- AP2 MerchantがCheckout Mandateの検証を必要とすることは仕様上の事実。しかし**そのためのRuby新規Gemに実際の市場需要があるか、独自プロダクトが支持されるかは未検証**。[docs/ap2/specification.md L292–317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L292-L317)。

## 2. 判断マトリクス（主観評価、計測結果ではない）

| 観点 | 現状の根拠 | 判断への影響 |
| --- | --- | --- |
| 規格の参照安定性 | AP2 v0.2.0の固定commit、Checkout/Agent Authorization/Schemaの一次資料が揃う。[SPEC_BASELINE](SPEC_BASELINE.md)。一方、Delegate SD-JWTは個人draftも参照。 | **前向きだが条件付き**：スコープ限定の研究は可能、仕様が完全に成熟したとは評価しない。 |
| Verifierの差別化余地 | JWT/JWS、JWK、Schemaは再利用の余地。**AP2固有の信頼・dSD-JWT chain・Constraints・Checkout binding**はRubyで明示的に設計する可能性。[ECOSYSTEM_RESEARCH](ECOSYSTEM_RESEARCH.md)。 | **前向き**：価値仮説はあるが競合の不存在は示されていない。 |
| 最小APIの明瞭さ | Hostが信頼Issuer/鍵・merchant-signed Checkout JWT・期待aud/nonce等を提供し、Verifierは`VerifiedEvidence`/拒否のみ返す、という境界が文書化された。[API_PROPOSAL](API_PROPOSAL.md)。 | **前向き**：範囲膨張を抑える設計候補。ただしメソッド名や契約は確定していない。 |
| セキュリティ不確実性 | Checkout hash、信頼する`x5c`のroot、非開示Constraint、terminal aud/nonce、Open JSON Schema `contains` に**ソース上の差分・未解決論点**がある。 | **重大なHOLD理由**：fail closedを実行で保証できていない。 |
| 検証実績 | Pythonのインストール、pytest、正負テスト、Ruby Gem install、Ruby相互運用は**未実施**。 | **重大なHOLD理由**：SDKテストの存在とテストPASSは異なる。 |
| 保守・供給側リスク | 仕様/個人draftへの追従、暗号/依存ライブラリ更新、セキュリティ報告受付、Issuer trustの使い方を誤る利用者のリスクを要考慮。Ruby matrix未決。 | **注意**：汎用Verifierを早期に`production ready`と宣言すべきでない。 |
| 市場・学習価値 | 手元で理解を深め、A2A/ActingForと**独立**して外部委任を評価できる題材。ただし外部ユーザーの利用要望・導入事例は未確認。 | **小規模調査を続ける合理性**はあるが、公開Gemのビジネス性はまだ証明できない。 |
| コスト | ローカル隔離環境の公式Python試験ならGCPネットワーク/VMを新設せずに進められる。具体的所要時間・金額は測定していない。 | **低コストの次ゲートを先に設ける**。クラウド実通信は今不要。 |

評価は形容詞・定性的判断であり、実測のテスト件数・収益・工数予測ではない。

## 3. HOLDの根拠（優先順位順）

1. **取引結合の保証不足。** Merchantは提示Checkout Mandateと対象Checkoutのhashを検証する。ところが公式Python `CheckoutMandateChain.verify`は`expected_checkout_hash`省略時に独立digest計算を行わず、渡したCheckout JWTのpayload parseもMerchant署名の確認とは異なる。[docs/ap2/specification.md L302–317](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L302-L317) / [code/sdk/python/ap2/sdk/checkout_mandate_chain.py L44–137](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/checkout_mandate_chain.py#L44-L137) / [upstream #358](https://github.com/google-agentic-commerce/AP2/issues/358)（2026-10-11確認時Open）。
2. **Issuer trustとHolder確認は別。** 正しい暗号署名だけでTrusted Surfaceの同意・信頼済みIssuer・Agentの業務資格まで証明したことにできない。公式Pythonの`x5c`提供providerは`trusted_roots`が未指定ならアンカー判定をスキップする構造。[docs/ap2/agent_authorization.md L34–79](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#L34-L79) / [code/sdk/python/ap2/sdk/sdjwt/chain.py L35–108](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/chain.py#L35-L108)。
3. **期待aud/nonceと期限が未証明。** Python SDKはKB-SD-JWTを生成するとき`aud`・`nonce`を要求するが、検証時に期待値を指定しない場合の挙動や欠落したclaimがどうなるかは追加の負例確認が必要。`exp`欠落はSDKが一律rejectするわけではない。[code/sdk/python/ap2/sdk/sdjwt/kb_sd_jwt.py L94–140](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/kb_sd_jwt.py#L94-L140) / [code/sdk/python/ap2/sdk/sdjwt/chain.py L272–299](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/sdjwt/chain.py#L272-L299) / [upstream #319](https://github.com/google-agentic-commerce/AP2/issues/319)（Open）。
4. **隠された制約を黙認できない。** 可視`constraints`だけの評価で「違反なし」となっても、必要な制約がSelective Disclosureで落ちている可能性。`OpenCheckoutMandate`公式JSON Schemaには`checkout.line_items`の`contains`がある一方、生成Pydanticモデルの制約は同等とは限らない。[code/sdk/schemas/ap2/open_checkout_mandate.json L1–70](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json#L1-L70) / [code/sdk/python/ap2/sdk/generated/open_checkout_mandate.py L60–91](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/generated/open_checkout_mandate.py#L60-L91) / [upstream #339](https://github.com/google-agentic-commerce/AP2/issues/339)（Open）。
5. **「ソースで見た」は「動く・安全」の証拠ではない。** 公式テストの既存箇所は確認したが、未実行。Ruby依存候補（`jwt`/`json-jwt`、`json_schemer`等）の実際のアルゴリズム制約・JWK/署名・Schema挙動も未テスト。[ECOSYSTEM_RESEARCH](ECOSYSTEM_RESEARCH.md)。

上流Issueは**報告がOpenである事実**であり、このリポジトリで攻撃・脆弱性を再現済み、という主張ではない。**上流IssueがCloseすること自体はGOの必須条件にしない**。必要なのは、自分たちのスコープに対して証拠を揃え、fail closedで扱えること。

## 4. 再判定のための次の1タスク（**まだ実行しない**）

**推奨:** `P0-5a — 公式Python SDKのローカル基準テストと主要負例の確認`（成果物候補：`docs/PYTHON_BASELINE_VERIFICATION.md`）。これは**研究用の独立した隔離テスト**であり、Ruby Gem実装ではない。ユーザーの次の明示承認後にだけ着手。

| 項目 | 実施/証拠として残すもの | 合格基準・判断 |
| --- | --- | --- |
| 固定・隔離 | `b4587ac1d055888a73b4b21750973cffba961793` の公式ソースを取得し、依存バージョン・hash・Pythonバージョンを記録。Git/checkoutとテスト環境は別ディレクトリ。 | 固定tagに対する実行を確認。外部実サービス・課金・GCPリソースを使わない。 |
| 公式テスト | [Python tests README](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/tests/README.md) に基づき隔離環境で`pytest`を実行。 | 実測Pass/Fail/Skip数、エラー、コマンド、実行環境を記録。**PASSを想定して記述しない**。 |
| Checkout | 本来のJWTと改ざんJWT、偽`checkout_hash`、別Checkout JWTの提示を比較。**単独の`CheckoutMandateChain.verify`の安全性と、Host側必須追加検証を区別**。 | 仕様のMUSTを満たすには何を別途検証する必要があるか、fixtureごとに記録。 |
| Binding / issuer | 不正Root鍵・信頼されない`x5c`、異なる`cnf`、chain/disclosure`sd_hash`不一致。 | 検証器が何を拒否し、Host policyが何を補うかの証拠を残す。 |
| aud/nonce・制約 | terminal欠落・不一致、期待値省略、hidden/unknown constraints、Open schema `contains` vs生成モデルを検証。 | **規格MUST / Python挙動 / 本OSS Host policy** を3列で分離。説明できない受理があればRuby PoCのGOは引き続きHOLD。 |
| 取り扱い | 実験用公開可能な疑似鍵・架空Checkoutのみ、データや秘密鍵をログ/PRへ記録しない。 | 認証済み実サービスへの送信禁止。SDKの脆弱性と断言する前に再現条件を確認。 |

**次タスクの完了はGem GOを自動的に意味しない。** 結果をもとにP0-5 decisionを再判定（GitHubで追記）し、その後の明示承認があって初めてPhase 1の最小Ruby PoCに進む。

## 5. 再判定ルール（GO / HOLD / NO-GO）

| 選択 | 実行条件 | その時に許されること |
| --- | --- | --- |
| **GO（最小非本番PoCのみ）** | 対象フローの署名・Root信頼・chain/disclosure・terminal binding・Open/Closed constraints・merchant-signed Checkout JWT/hashを**正負の再現可能なfixture**で評価でき、未規定の部分を**Hostが具体的に拒否/制限**する契約が作れる。Rubyの基本crypto/Schema依存の適合見込みがある。 | **別途ユーザーが承認した場合のみ**、非本番・ローカル・狭いPoCを開始。公開/商用/安全認定は禁止。 |
| **HOLDを継続** | 任意の重要要件が未実証、未開示制約や鍵信頼を安全に扱う方法が不明、互換性が不安定。 | 資料整理・小さなオフライン検証だけ。Ruby Gemは実装しない。 |
| **NO-GO** | スコープを狭めても安全な証拠を返せない、必要な保守コスト/技術的負債が個人OSSに過大、既存Ruby実装と差別化できない、または利用価値の仮説が弱いと判明。 | 新規Gemの計画を停止・研究資料のみ維持。 |

**誤解を避ける注意:** 公式Python SDKが全テストPASSしただけでもGOにはならない。逆に上流バグ報告が残っていても、明示的なHost trustと負例・fail-closed対策により狭いPoCが成立する余地はある。GOしても`AP2 compliant`、`production ready`、`secure for payment`などを証拠なしに名乗らない。

## 6. コストと投資方針

- **短い研究ループを優先:** spec固定→オフラインテスト→観察結果→判断を繰り返す。設計を増やすだけ、またはGem機能を先に増やすことはしない。
- **GCP検証は今不要:** この段階でCloud Run/VM/VPC/Cloud NATや実決済は立ち上げない。実HTTP通信が本当に必要と判明した時だけ別の予算・許可を取る。
- **維持費を軽視しない:** 暗号署名と金銭取引の委任証明は誤った`VerifiedEvidence`のコストが高い。個人OSSとして脆弱性対応・依存追随・API互換・Security Policyの体制が作れない場合は、機能を削る/HOLD/NO-GOを選ぶ。
- **外部需要は未検証:** 学習と検証の成果自体に価値はあるが、他者が導入するGemに成長するかを決定する材料はまだない。

## 7. P0-5の完了条件

- [x] **HOLD**を選択し、GO/NO-GOも含めて理由と再判定条件を記録。
- [x] 規格、現行SDK、Rubyの再利用、セキュリティ境界、OSS価値、保守コスト、最小APIを個別評価。
- [x] **次の調査を1件だけ**に固定し、成果物とpass/fail評価条件を指定。
- [ ] Python SDKテスト・負例・Ruby互換試験：**未実施**。
- [ ] Ruby Gem/PoC実装・CI・公開：**未承認・未実施**。

**現在の最終判断: HOLD。** Agent/Issuerに対する信頼や購入許可を、本OSSが暗号だけで判断できるという主張はしない。


## 8. 2026-10-11 P0-5a実行後の判断更新（追加記録）

**GO/HOLD/NO-GOの再判定: HOLD 継続。** P0-5aは単なる静的調査を越え、固定公式SDK全pytestと、Issuer/terminal aud/nonce/SD-JWT選択的開示・Checkout Hashに関する実署名負例を実行した。実測詳細とログは[PYTHON_BASELINE_VERIFICATION](PYTHON_BASELINE_VERIFICATION.md)。

- **公式Python SDK:** 188件中 **186 PASS / 2 FAIL**。intermediate KB-SD-JWTのaud/nonce mismatchテストでは例外が発生せずテスト失敗。**コードとテストの適用範囲の食い違いであり、仕様違反を独立に断言したものではない**。
- **研究追加負例:** **12 PASS**。期待aud/nonce欠落、信頼されないx5c root、Checkout Hash/JWT別セッション、選択的開示でMerchant制約を秘匿した署名付きOpen SD-JWTを検証。**PASSは不適切受理の観測を含み、全Verifierが安全であるという意味ではない**。
- **再現限界:** upstream公式\`uv.lock\`が認証付き配布先を指して401となったため、公開PyPIからupstream\`pyproject.toml\`の**直接依存ピン**で導入した。**すべての推移的依存の完全lock再現ではない**。GCP・実決済・本番トラフィックなし。
- **HOLDを維持する理由:** 仕様とPython実装間のintermediate aud/nonce境界、Hostが要求する必須disclosureの完全性、trusted rootなしのx5cを受け入れないデフォルト、Merchant署名済Checkout JWT/closed hashの独立照合を、**具体的なHost向け拒否契約**としてまだ固定していない。Ruby互換性の実測も未実施。
- **次の1件（P0-5b）:** 上記に対する最小Fail Closed Profileと適用不能時のHOLD条件を設計し、最小非本番PoCに限定したGO/HOLD判断を更新する。**Gem実装は今なお未承認**。

この追記は以前のP0-5判断時点の「Python tests未実施」の歴史的記述を置き換えるものではなく、**新しい実測を反映した最新判断**。証拠は[PYTHON_BASELINE_VERIFICATION](PYTHON_BASELINE_VERIFICATION.md)を優先。


## 9. P0-5bの最終再判定（2026-10-11）— **CONDITIONAL GO（狭い非本番Ruby PoCのみ）**

**判断:** **CONDITIONAL GO: Phase 1の最小オフラインRuby技術PoC**（別途ユーザーの明示承認が必要）。**HOLD: Gemとしての広範な実装・一般公開・本番決済利用**。

根拠: [FAIL_CLOSED_PROFILE](FAIL_CLOSED_PROFILE.md) に「認める入力」と「必ず拒否する入力」を具体化できた。公式AP2 v0.2 Python SDK全体は **186 PASS / 2 FAIL**（intermediate aud/nonce）だが、最初のRuby PoCは**中間hopを全拒否**し、実験済みの実署名負例12件の重要な境界を**Host必須ポリシーとして明示して埋める設計**とした。ただし**Ruby側でその防御を実装・実証したわけではない**。

### PoC用の条件付き許可（GOの条件）

1. **スコープの固定:** **Autonomous/二段**（issuer-signed Open Checkout → 同じAgentの鍵でsigned Closed Checkout）。Direct、任意3-hop/multi-agent、Payment Mandate、未知type、\`issuer_jwt_hash\` mode、任意\`x5c\`は**受け付けない**。
2. **Hostの信頼境界:** Trusted issuer public key、Agentのendorsement/PoP、merchant signed Checkout JWT、期待aud/nonce、時計/期限、Merchant IDと必要なDisclosureを**必須でHostが供給**。Root内の自己宣言鍵・kid・Issuer URLは信頼根拠にしない。
3. **Fail Closed:** 有効なRoot/Terminal署名、\`sd_hash\`の元tokenとのbinding、all required open constraints completeness、Checkout JWTの署名と原文・independent base64url SHA-256 hash、期限、aud/nonceを検証。未知、曖昧、欠落なら**必ずRejection**。「署名正しい」だけではVerifiedEvidenceを返さない。
4. **制約完全性の最重要Gate:** AP2 SDK上ではIssuerが署名したConstraint自体を非開示にしても可視評価は違反0となることを再現した。**Issuer-approved layout/本物の完全開示状態を検証可能な限定fixture**だけを研究対象にする。発行者が隠したConstraintを区別できない場合は**非対応・REJECT**、安全に判定できない場合は **Ruby PoCをその境界でHOLD**。デコイ・未知のcommitmentを無害扱いしない。プライバシー上の理由で「全AP2は常時全開示必須」とは主張しない。
5. **成功の意味の限定:** 返却は **VerifiedEvidenceかRejectionのみ**。Hostの業務ALLOW、replay/失効の原子管理、Receipt署名・返却、注文と決済は実装しない。失効/Replay等の追加条件を未評価のまま「購入許可」と伝えない。
6. **PoC開始の安全弁:** まずRuby \`jwt\`/JOSE、\`json_schemer\`、OpenSSLの能力・鍵署名・Digestを**公式Pythonの正負fixtureで比較するだけ**。署名未検証のshortcut、未知アルゴリズム許可、手作り暗号実装はしない。Rubyで完全性保証や鍵bindingが成立しない場合は **HOLD/NO-GOへ戻る**。

### 判断表

| 対象 | P0-5b判断 | 含意 |
| --- | --- | --- |
| **ローカル限定Ruby技術PoC** | **CONDITIONAL GO** | **次の明示承認を得た場合に限る**。最初は署名・schema・hashのoffline compatibility spike。脆弱性再現テストを比較して失敗時はSTOP |
| 汎用Ruby Gem/安定Public API | **HOLD** | API固定、依存追加の永続化、サポートmatrix、gem releaseに進まない |
| AP2 v0.2全フローの互換性 | **HOLD** | Direct、Delegation複数Agent、中間hop、Payment等はサポートしない |
| 実決済 / 外部サービス / Production | **NO-GO** | 公開・販売・セキュリティ保証をしない。Hostが最終ALLOWとReceiptを管理する必要あり |

**なぜ全部HOLDではなく限定GOか:** 公式SDKを固定して実行でき、重要な「不適切な受理」を12件の実署名/フルSDKプローブで確認した。この境界を避ける狭いfixtureと、失敗なら必ずREJECTとする仕様上の入口を設計できた。Ruby環境で成立するかを試すのはPoCの目的であり、Pythonの全188件PASSやIssue closeを無期限に待つより安価で検証可能。ただし**POCそのものの技術的成功はまだ証明されていない**。

**次の1件（別途承認後のみ）:** **P1-0 — Ruby暗号・JSON Schemaのオフライン互換性Spike**。Gem/Railsアプリを作らず、隔離したRubyの小さな実験で \`ES256 JWS/JWK\`、\`SHA-256 checkout_hash\`、\`Open Checkout JSON Schema contains\`、invalid/missing-keyケースを固定Python fixtureと照合。**成果物は \`docs/RUBY_FEASIBILITY_SPIKE.md\` と最小研究テスト**。公開API実装、実決済、GCP利用は未承認。


## 10. 2026-10-11 P1-0 実測後の判断（最新）

**限定研究の互換性SpikeはPASS、PoC研究のCONDITIONAL GOを継続。ただし汎用Ruby Gem/API/公開はHOLD、本番・実決済はNO-GO。**

- Ruby 3.3.12 + \`jwt 3.3.0\` + \`json_schemer 2.5.0\`のGitHub Actionsで**14 runs / 17 assertions / 0 failures / 0 errors / 0 skips**。一次証拠は[RUBY_FEASIBILITY_SPIKE](RUBY_FEASIBILITY_SPIKE.md)と[Actions run #38123249933](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38123249933)。
- Python \`cryptography\`生成（**公式AP2テストベクトルではなく合成fixture**）のES256 JWTをRuby JWK検証し、別公開鍵、payload・署名改ざん、\`alg=none\`を拒否。SHA-256 Checkout JWT hashはPythonの値に一致。
- AP2 \`v0.2.0\`固定CommitのOpen Checkout Schema（Git Blob SHA確認）をRuby \`json_schemer\`で検証し、\`contains\`による空constraints拒否、Quantity 0、誤vct、欠けたcnfを拒否した。
- **この結果が示していないもの:** SD-JWTの選択的開示/Proof-of-Possession/issuer-trust、Open→Closed chain、Merchant正本Checkoutの完全な結合、nonce再使用防止、権限制約の完全性、本番安全性。P0-5aで再現したhidden Merchant Constraintの危険を緩和したとは主張しない。
- **次の1件（別の明示依頼後）:** **P1-1：固定AP2 Python由来の署名付きSD-JWT Root・Disclosure digest・権限制約の完全性をRubyで評価する局所Spike**。不明・未開示のauthority constraintは必ずrejectするという方針を守り、Gem/public APIを構築しない。

**P1-0のPASSはPhase 1すべての実装GOではない。** 技術研究用の狭いSpikeに限る。

## 11. 2026-10-11 P1-1 実署名Root SD-JWTのRuby研究結果（最新）

**判定：限定研究PoCのCONDITIONAL GOを継続。汎用Gem/公開API/リリースはHOLD、本番/決済はNO-GO。** 研究結果は[RUBY_SDJWT_RESEARCH](RUBY_SDJWT_RESEARCH.md)、[Actions run #38123828122](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38123828122)に記録。

- 固定AP2 v0.2.0 Python SDKの`MandateClient.create`で架空のIssuer/Agent/Checkout制約を持つOpen Root SD-JWTを**実際に署名・選択的開示**した。
- Ruby 3.3.12 / `jwt 3.3.0` が、Host指定Issuer公開鍵でES256署名を検証し、`delegate_payload`とMerchant制約のarray disclosure SHA-256ダイジェストの整合を確認した。**10 runs、22 assertions、失敗0**。
- 未開示Merchant Constraint、Disclosureのsalt改ざん、Issuer JWT署名改ざん、wrong issuer key、無関係/重複Disclosureはすべて**Fail Closed（拒否）**を実測。
- **未実証:** SD-JWTの任意形式（dictionary disclosure・decoy等）、全権限制約の一般的完全性証明、Terminal agent署名・Rootの`cnf`とのPoP、`sd_hash`、Host期待aud/nonce、merchant-signed Checkout JWT/Hashの統合検証、業務ALLOW、Replay/Receipt。**10 PASSはAP2 Verifierの完成・本番安全性ではない。**

**次の1件（改めて明示承認後のみ）：P1-2 — 固定SDKによるOpen Root → Agent Terminalの厳密2-hop SD-JWTで、RubyのHolder署名、Root `cnf`、`sd_hash`、Host期待aud/nonceを負例込みでオフライン確認。** 3hop以上や他Agent転委任は拒否し、Gem/APIの実装・公開には進まない。

## 12. 2026-10-11 P1-2 2hop署名・Root binding 実測後の判断（最新）

**最新判断：CONDITIONAL GO（限定非本番研究PoCのみ）、汎用Gem/API/公開はHOLD、production/実決済はNO-GO。** 一次証拠は[RUBY_DELEGATION_SPIKE](RUBY_DELEGATION_SPIKE.md)と[Actions run #38124823804](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38124823804)。

- AP2 v0.2固定Python SDKで**Open Root→Agent Terminal Closedを署名し公式Python `verify_chain`で検証**、その真正なwireをRubyで検証。
- Ruby 3.3.12/`jwt 3.3.0`でRootとTerminalの署名、Root `cnf.jwk`に結び付くAgent、`sd_hash`の元wireダイジェスト、Host必須の`aud`/`nonce`に対する正負を評価。**P1-2は15 runs / 32 assertions / 0 failures**、共有Root検証の**P1-1回帰は10 runs / 22 assertions / 0 failures**。
- 署名済みでも別Root hash、違うAgent signer、wrong expected Agent、wrong/missing aud・nonce、intermediate/3hop、非開示Root制約、署名改ざん、未対応`issuer_jwt_hash`は拒否した。
- **特に重要な未完了:** Closed中のCheckout JWTは署名欄`NOT_A_SIGNATURE`の**架空JWT**。Merchant公開鍵による署名検証、Host正本との原文照合、Closed `checkout_hash`の独立再計算、Open制約と実際のMerchant/商品/数量の取引一致は**未実装**。したがって`VerifiedEvidence`や`ALLOW`、購入許可のAPIとしてまだ提供しない。暗号連結だけでは不十分。
- 根拠の範囲はstrict single Issuer layout + exactly two hopsで、任意AP2／SD-JWT、Issuer trust infrastructure、stateful replay/nonce消費、Receipt、本番の安全性には広げない。固定上流公式pytestの失敗2件（intermediate aud/nonce）も解消していない。

**次の1件（新しい明示承認後のみ）：P1-3 — Merchant-signed Checkout JWTのHost正本・原文・SHA-256 checkout_hash、Open `allowed_merchants`/`line_items`をオフラインで統合する小さなRuby Spike。** Gem雛形、安定API、公開、決済実行・GCP・nonce消費・Receiptは未承認。

## 13. 2026-10-11 P1-3 Checkout JWT / Host正本 / Constraint実測後の判断（最新）

**CONDITIONAL GOは非本番研究PoCの範囲のみ継続。汎用Gem/API/リリースはHOLD、実決済・ProductionはNO-GO。** 根拠は[RUBY_CHECKOUT_BINDING_SPIKE](RUBY_CHECKOUT_BINDING_SPIKE.md)と[CI Run #38126247946](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38126247946)。

- 固定AP2 Python SDKによる署名済Open Root→Agent Closed Terminalを使い、さらに**独立Merchant鍵のES256署名付き架空Checkout JWT**を発行。RubyはHostが登録したMerchant公開JWKで検証し、Host正本JWTとClosed `checkout_jwt`の原文一致、Closed `checkout_hash`の独立SHA-256 base64url計算、RootのMerchant/SKU/Quantity、HostのCheckout ID/Currency/Totalを評価した。
- **P1-3：18 runs/40 assertions、失敗0**。Root署名/Disclosure P1-1回帰**10 PASS**、2-hop署名binding P1-2回帰**15 PASS**。**合計43テストが成功**したが、別階層の限定研究結果をAP2標準合格とみなさない。
- **重要な発見:** 上流SDKの`check_checkout_constraints`は、今回の「必要数量2 / 実Checkout数量1」に違反を返さなかった。Ruby研究プロフィールは数量の**完全一致を追加のHost policy**として要求。公式の仕様違反と断定せず、数量一般の解釈を未解決とする。さらに**同じCheckout JSONを再署名するとJWT原文が異なる**ため、Host正本の署名済JWTの**同一バイト列を再利用**するようfixtureを修正した。
- **未実証のまま:** 多店舗/複数SKU、税・割引・送料、任意UCP Schema、署名アルゴリズム/JOSE変種、完全なConstraint/Disclosure一般化、Issuer trust keyの運用、時刻境界とExpired Terminal、**nonce消費/replay、注文・価格・在庫の業務正本、Revocation、署名Receipt、実決済**。これは本番利用を正当化しない。
- **次の1件（別の明示依頼後のみ）：P1-4 — 研究コードP1-1〜P1-3の攻撃面・安全負債レビューと、実際に汎用Gem開発へ進むかのGO/HOLD判断を文書化。** まだGem/API実装しない。

**この文書でP1-3完了を記録することは、Gem実装許可・実決済許可にはならない。**

## 14. 2026-10-11 P1-4 セキュリティ負債レビューによるGO/HOLD再判定（最新）

**結論：汎用・外部利用を想定したRuby Gemの実装開始はHOLD。RubyGems公開、本番/実決済はNO-GO。現行の狭いオフライン研究とセキュリティ負例追加（P1-5）のみGO候補（別のユーザー承認を必要とする）。**

**根拠:** [SECURITY_GAP_REVIEW](SECURITY_GAP_REVIEW.md) — 固定版AP2 v0.2仕様とP1-1〜P1-3のRuby研究コードを静的に確認し、**12項目（S01〜S12）の課題とGem化に先立つ6ゲート（G1〜G6）**を定義。これらは**新しい攻撃/再現実験ではない**。Critical/Highなどの深刻さの断定やCVEを報告するものではない。

**既存成果:** P1-1のRoot署名とdisclosure 10件、P1-2 Agent署名/cnf/sd_hash/aud/nonce 15件、P1-3 Merchant Checkout JWT/Host正本/hash/店舗/数量等18件は、既存の非本番・単一Agent・2hop Strict ProfileのCIでPASS。特にP1-3の最終43件は[Actions #38126247946](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38126247946)。**この成功は不正な追加形式、時間差攻撃、Replayや実決済の安全性を証明しない**。

**Gem実装をHOLDする阻害条件（重要順）:**

1. **厳格なJSON/JWS/JOSEの受入れ（G1）**：重複JSONキー、JOSE鍵選択・署名アルゴリズムを誤解釈せず拒否する負例が不足。
2. **選択的開示・権限制約完全性（G2）**：現行のIssuer Profile外に一般化する証拠がなく、hidden/decoyと未知権限が混在するケースの振舞い未検証。
3. **期限・信頼のHost契約（G3）**：Root TTLとTerminal iatの一部は確認するが、**Closed内expを独立検証していない**。Issuer/merchant identity ↔ trusted JWKの運用契約も不十分。
4. **Resource/Fault（G4）**：深いJSONや過大入力での例外が業務許可に転じない保証がない。
5. **VerifiedEvidenceとHostの最終ALLOWの分離（G5）**：nonce一度限りの原子的消費、失効・取引状態・署名ReceiptはHost側で別途設計/実証しなければならない。

**次の1件（P1-5）：** 上記G1〜G4の優先負例を**研究コードのテストとして先に書き**、RED/GREENと拒否理由を実測・記録する。Ruby verifier本体やGem雛形の実装はその後の**別GO/HOLD判断と明示承認**へ先送りする。P1-4自身は文書変更のみでCI実行・テスト追加・Gem作成なし。

**判断表:** オフライン研究のみCONDITIONAL GO／P1-5はGO候補／汎用Gem実装HOLD／RubyGemsリリース・実決済Production NO-GO。**上流の中間hop aud/nonce公式pytest 2件失敗はまだ未解決**だが、初期研究対象から中間hopを除外しているため、解消済みとは書かない。

## 15. 2026-10-11 P1-5 署名済セキュリティ負例実測後のGO/HOLD（最新）

**P1-5の成果:** 固定AP2 v0.2 Python SDKが生成したOpen→Closedと、実Merchant ES256署名付きの改変Checkoutを使用し、Ruby研究Verifierに**18観測**を実行。[SECURITY_NEGATIVE_TESTS](SECURITY_NEGATIVE_TESTS.md)、[CI Run #38127279271](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38127279271)。

**結果: GREEN 11（正常1＋拒否10）/ RED 6（署名が有効な厳格プロフィール外の入力を想定外受理）/ HOST_BOUNDARY 1（同一tokenを独立2回verifyすれば両方受理。stateless設計上、Hostがreplay消費必要）/ ERROR 0。** 過去P1-1〜P1-3回帰は10+15+18テストすべてPASSしたが、**新しい6 REDの重大性を帳消しにしない**。

**RED内容と優先度:**
1. **B0/G1:** Merchant JWTの同一`merchant.id`重複を許容（N01）、ES256署名済Protected Headerに`alg`重複を許容（N02）。トークン署名の不備が発見されたのではなく、**重複キーがある曖昧な署名済JSONをrejectしていない**ことを実測。
2. **B1/G3:** Root/Terminal outerの時刻チェックがある一方、Closed内部の期限切れ`exp`（N03）と未来`iat`（N04）が受理された。
3. **B0/B1のStrict Profile:** Merchant JWTの想定外`typ`（N05）、Checkout中の未知の権限関連field（N07）が受理された。**全AP2仕様のMUST違反とは主張せず**、初期OSSのfail-closed/supported subsetの未達として扱う。
4. **G2/G4は限定正例あり:** Required Merchant開示欠落・追加Authority、Issuer信頼鍵不一致、JWT過大、Root期限、Host nonce不一致は今回拒否された。しかし深いJSON/Decoy/多Issuerを網羅したわけではない。
5. **G5 Host責務未実装:** 同一nonceの原子的消費/Checkout二重処理防止・失効/Receiptは本研究Gemで証明していない。

**最新判断：P1-5テスト実証は完了、汎用Ruby Gem/API実装はHOLD、RubyGems公開・実決済/ProductionはNO-GO。** 既存研究コードへの限定修正を行う**P1-6のみGO候補（別途ユーザー承認必須）**。先にN01/N02/N03/N04/N05/N07をGREENへ変える。**Gem作成・リリース・Host永続nonce・Receiptの実装は自動承認しない。**

**CIの落とし穴:** 観測stepは6 REDにつきexit 1したが、報告Artifactを残すため`continue-on-error`としたのでworkflow自体は**success**。これは「セキュリティテスト全PASS」ではない。修正前の6 REDは[Security Negative実測レポート](SECURITY_NEGATIVE_TESTS.md)に残す。

## 16. 2026-10-11 P1-6 6 REDの限定研究ハードニング実測（最新）

**成果と一次証拠:** [SECURITY_HARDENING_RESEARCH](SECURITY_HARDENING_RESEARCH.md)、[GitHub Actions #38128152237](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38128152237)。

- P1-5と同じ固定AP2 v0.2公式Python署名fixtureの**18観測**について、以前の6 RED（重複Merchant JSON ID/重複JOSE alg、Closed内部exp/iat、Merchant JWT typ、未知Checkout field）をRuby**研究コードの厳格な受理方針**に合わせて拒否するよう修正。
- **P1-6：GREEN 17（正例1＋拒否16）、RED 0、ERROR 0、HOST_BOUNDARY 1**。P1-1 Root回帰**10/10**、P1-2 Agent binding回帰**15/15**、P1-3 Merchant Checkout回帰**18/18**（計43件、失敗/エラーなし）。
- **正しい鍵の署名・元JWTバイト・checkout_hash・sd_hashを保護するチェックは維持**。曖昧な署名済JSONは原文バイトの厳密Parseで拒否する。Closed内部のiat/expはouter terminalと別に確認。JWT typ/Checkoutのフィールド集合はあくまで**研究用Strict Profile**であり、一般AP2の規範MUSTではない。
- **未達:** HostのIssuer ID/Agent/Buyer/Merchant IDと信頼鍵の登録・失効・正本管理、Atomic nonce replay防止、一般SD-JWT/decoy、深い異常JSON・時間境界とClock注入、最終認可/購入注文・Receipt、実決済。特に**N17の同一トークン2回受理はHost replay境界として残す**。6 REDが0になっても上記の保証は得られない。
- P1-6では**汎用Gem、安定API、RubyGemsリリース、Host DB/state/Receipt、GCP/実決済を作っていない**。

**最新GO/HOLD判断:** 厳格なオフライン研究PoCのみCONDITIONAL GO。**汎用AP2 Ruby Gem/API実装はHOLD、RubyGems公開・本番/実決済はNO-GO。** これを「P1-4ゲートG1〜G6完全クリア」や安全な実取引への許可と解釈しない。

**次の1件（ユーザーが別途明示承認した場合のみ）：P1-7 — Host trust/VerifiedEvidence/Nonce/Clock/失効・Receiptの責務契約と必要な負例の設計資料作成。** 本番コードやGem実装はまだ先に進めない。

## 17. 2026-10-11 P1-7 Host信頼境界・nonce/Receipt責務の設計とGO/HOLD（最新）

**実行内容：文書設計のみ。** [HOST_SECURITY_CONTRACT](HOST_SECURITY_CONTRACT.md)と[HOST_SECURITY_TEST_PLAN](HOST_SECURITY_TEST_PLAN.md)で、AP2 v0.2固定版・単一Agent/2hopの範囲に対し、HostのIssuer/Buyer/Agent/Merchant identity↔信頼鍵、現在Checkout正本、Host期待aud/nonce/Clock、失効、`VerifiedEvidence ≠ ALLOW`、原子的なReplay防止、同一operationによる障害復旧、署名Receiptを責務別に整理した。

**将来テスト計画は34件**：HT01〜HT07（Host鍵/IDとtrust、7）、HC01〜HC07（Context/Clock/TOCTOU、7）、HR01〜HR10（DBによるnonce同時消費・障害・再実行、10）、HE01〜HE10（Evidence/Receipt・Privacy・障害時STOP、10）。**すべて設計のみ・未実装・未実行。** P1-7は新しいCI/Rubyテスト、DBの一意制約、Receipt生成、実決済/GCP実験を行っていない。

**境界の核心:** VerifierはIssuer/Agent/Merchant署名・Checkout制約等の検証**事実**を返し、最終のBuyer資格/失効/注文正本/nonce使用済みを証明しない。Hostがそれらを同一整合性境界で確認し、CASによるnonce消費とCheckout operation作成を**原子的に確定**するという**提案契約**を明示した。複数worker、commit不明時、外部処理timeout/receipt署名失敗で**再実行・二重課金をしない**ことを将来の受入れ基準とする。未達時はSTOP/PENDING、証拠不足で成功へ進めない。

**公式根拠と独自方針の区別:** MerchantによるCheckout Mandate検証・失敗時Receiptは固定[AP2仕様](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#L302-L317)。nonce CAS/Outbox/注文DB/Host IDマッピングは**本OSSのHostセキュリティ設計案**であって規格の必須DB実装ではない。

**GO/HOLD：** 限定研究・設計活動のみCONDITIONAL GO。**汎用AP2 Ruby Gem/public API実装はHOLD、RubyGems公開/本番/実決済はNO-GOを維持。** P1-6の旧RED修正後18ケース（17 GREEN/0 RED/Host責務1）と43回帰は過去CIの証拠であり、**Host Replay/Tenant/Receiptの受入れテスト合格を意味しない**。

**次の1件（別途ユーザー明示承認が必要）：P1-8。** Host nonce/Checkout操作のrace/rollback/retryをオフラインで試すため、**ローカルDB/runner・テスト設計・費用・実装範囲の採用判断を先に行う**。Gem/Host本番コードやDB/決済を自動的に作らない。

## 18. 2026-10-11 P1-8 Host Replay試験環境・DB採用判断（最新）

**成果は設計資料のみ。** [HOST_REPLAY_LAB_DESIGN](HOST_REPLAY_LAB_DESIGN.md)でSQLiteとPostgreSQLを比較し、Host replayの同時性検証には**一時PostgreSQL 16**を第一候補に選定。2 Ruby worker/異なるDB接続、barrierを使うrace、nonce CAS＋Checkout単一操作のunique、単一transaction outbox、commit前後のクラッシュ/unknown commit、Fake Providerの安定idempotency key、runner費用/cleanupと将来テスト順序を設計した。DBモデル/Hostアプリ/CI/Receipt/GCPは**一切新規実装・実行していない**。

**未実証:** P1-7のHT/HC/HR/HE計34ケースは**すべて未実行**。N17 HOST_BOUNDARY継続、nonce一回限りの原子性/注文二重処理抑止はまだ未証明。過去P1-6の17 GREEN / 0 REDと43回帰PASSはVerifier研究の証拠で、Hostテストの成功ではない。**ProviderがidempotencyをサポートしなければDB側だけで外部二重課金防止は断定できない。** AP2の規格MUSTとHost独自DB設計を区別する。

**次の1件（別の明示承認後のみ）:** **P1-9a**、隔離PG16/2 Ruby workerで**HR01/02/03/08**の最小同時性試験を実装・実測。Crash/Retry/Receipt/全34件の実装を一括承認しない。固定AP2 v0.2公式Commit `b4587ac1d055888a73b4b21750973cffba961793`を維持、公式Python SDK 186 PASS / 2 FAIL（中間hop aud/nonce）を解消済みとしない。

**GO/HOLD:** 限定オフライン研究のみCONDITIONAL GO、汎用Gem/public API実装HOLD、RubyGems公開・本番/実決済NO-GO。

## 19. 2026-10-11 P1-9a PostgreSQL Replay最小実測とGO/HOLD（最新）

**限定Host DB研究として4ケースを実測しPASS。** [HOST_REPLAY_P19A_EVIDENCE](HOST_REPLAY_P19A_EVIDENCE.md) と [GitHub Actions #38133951057](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38133951057)、[PGコンテナdigest固定の再検証 #38134040469](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38134040469)に証拠。PostgreSQL 16.9/Ruby 3.3.12/pg 1.5.9、独立OSプロセス2worker/異なるDB接続で実際のロック競合をDBに問い合わせて確認。**HR01同nonce、HR02異nonce同Checkout、HR03 nonce CAS 0行、HR08 Replay**の4つで**4 runs / 108 assertions / 0 failures / 0 errors / 0 skips**。同一Checkout operationとoutboxの一回限り登録、nonce消費、再送STOP、追加のDB UNIQUE違反の観測を確認した。最初のCI [#38133875041](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38133875041)はRubyテスト構文エラーによりFAIL・テスト0件実行であり、隠さず記録。

**未達・正確な範囲:** P1-7 Hostテスト34件中**4実装・30未実装/未実行**。これは**架空のHost session/evidenceに対する限定したDB transaction研究**であり、AP2署名/Buyer認可/ライブ失効・元Checkout/Provider送信・Crashやunknown commit/Receipt/本番安全性を証明しない。N17の**stateless Verifierは同一有効Mandateを2回検証可能**というHOST_BOUNDARY自体は継続。外部Providerの二重課金防止も未実証。上流Python SDKの中間hop aud/nonce 186 PASS/2 FAILは解消済み扱いにしない。

**判断:** 研究用P1-9aはPASS/限定GO（実際のDB競合・失敗分岐を実測した範囲に限る）。Gem/public API実装と全面的Host統合は**HOLD**、RubyGems公開・実決済・本番は**NO-GO**。P1-4のG1〜G6およびP1-7のT1〜T5を完全クリアしたと主張しない。

**次の一件（新しいユーザー明示承認後のみ）：P1-9b。** HR04/HR05の**COMMIT前/後プロセスクラッシュ**と原子Rollback/復元を同じ一時PG16環境で実測。HR06/HR07の不明commit・Provider retry、署名ReceiptやGem化はさらに後の独立タスクとする。

## 20. 2026-10-11 P1-9b COMMIT前後クラッシュ・Host復元の限定実測（最新）

**限定Host DB研究としてHR04/HR05実測成功。** [HOST_REPLAY_P19B_EVIDENCE](HOST_REPLAY_P19B_EVIDENCE.md)、[Actions #38134591784](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38134591784)。実worker SIGKILLで**COMMIT前：nonce/checkout/operation/outboxが全Rollback→別worker新規再評価で正当Commit**、**COMMIT ACK後：operation/idempotency keyが永続化され、別の読み取り専用RecoveryがPENDINGで同じ参照を回収、Replay STOP**を観測。**HR04/05 2 runs /84 assertions/失敗・エラー0**、既存HR01/02/03/08 4 runs/108 assertionsもPASS。**Hostテスト34件中6件実測、残り28件未実行**。

**境界:** ACKが失われCOMMIT結果不明となるHR06やProvider timeout/IdempotencyのHR07は**未試験**。AP2署名/Buyer信頼・失効、Receipt、実決済は対象外。N17 stateless HOST_BOUNDARYは残り、公式Python SDK中間hopの186 PASS / 2 FAILも未解決。G1〜G6/T1〜T5全達成ではない。**狭い研究CONDITIONAL GO、汎用Gem/API・本番統合HOLD、RubyGems公開・Production/実決済NO-GO。** 次の一件（新たな明示承認後のみ）：**P1-9c HR06/HR07のFake環境研究**。

## 21. 2026-10-11 P1-9c Unknown COMMIT / Mock Provider Idempotency研究（最新）

**HR06/HR07の限定オフライン実測PASS。** [HOST_REPLAY_P19C_EVIDENCE](HOST_REPLAY_P19C_EVIDENCE.md)、[GitHub Actions #38135302918](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38135302918)。HR06はlibpq COMMIT非同期送信後のACKを元workerが読まない故障、実SIGKILL、別DB接続でのcommit済operation/key再照会・PENDING復元・再送STOP、さらに実PG lock timeout（SQLSTATE55P03）→新operation作成禁止を測定。HR07は実Providerを使わず**同じ隔離PGの架空台帳**でレスポンス喪失を模擬し、**送信試行2回/架空論理効果1件**、同じoperation/key継続と別key STOPを確認。HR06/07は**2 runs /149 assertions/失敗0**、既存P1-9a/bの6 runs /192 assertionsもPASS。合計Host計34中**8件実測/26件未実行**。

**限界:** HR06のCOMMIT結果不明はACKを**読まないがDB側がcommit成功した経路**に限定。DB rollback/ACK紛失の他形態、実TCP切断、実Providerのidempotency/二重課金保証やReceiptを実証していない。N17 stateless HOST_BOUNDARY継続、P1-4 G1〜G6/P1-7 T1〜T5未完。上流Python SDKの186 PASS/2 FAILも未解決。**限定研究GO、汎用Gem/API・本番Host統合HOLD、RubyGems公開/実決済/Production NO-GO。**

**次の1件（別のユーザー明示承認のみ）：P1-10a** HR10（Checkout更新/失効とnonce消費のrace）を隔離PG16で検討・実測。外部信頼情報更新の一貫性はDB lockだけで保証できない。

## 22. 2026-10-11 P1-10a HR10 Checkout変更/失効とHost認可のDB競合実測（最新）

**限定PG16研究の正本Host ID HR10を実測PASS。** [HOST_REPLAY_P110A_EVIDENCE](HOST_REPLAY_P110A_EVIDENCE.md)、[Actions #38136341199](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38136341199)。実2worker/2接続とPGの実ロック待機を4スケジュールで観測：**cancel先／Buyer block先／Checkout version+fingerprint更新先**なら購入認可STOP、nonce未消費、operation/outbox各0。**購入確定先**なら操作1件で、遅い取消は`too_late_checkout_reserved`として拒否し「防止済み」と誤報告しない。HR10は**4 Minitest runs /124 assertions / 0 failures/errors/skips**。既存8 runs/341 assertionsもPASSで合計**12 runs/465 assertions**。正本34件中**9 ID実測・25件NOT RUN**。

**範囲と限界:** 両側が**同じPostgreSQL checkout→policy行を同一規約でlock**する合成研究。外部Issuer/Buyer/Agentの失効源、別DB、一時的な不整合、真正Checkout JWTの署名・金額/在庫、取消後補償/Refund、正式Receipt、実決済は未検証。HC04/HC06/HC07を自動でPASSにしない。N17 stateless HOST_BOUNDARYも残る。P1-4 G1〜G6、P1-7 T1〜T5の完全達成、公式Python SDK中間hop aud/nonceの186 PASS/2 FAIL解消は主張しない。

**判断:** 狭いHost DB競合研究だけPASS/限定GO。汎用Gem/API、本番Host統合**HOLD**、RubyGems公開・Production/実決済**NO-GO**。**次の一件（別途ユーザー明示承認）：P1-10b HC06の外部失効整合性設計・テスト戦略のみ。** 外部GCP/APIデプロイや実験はその後の独立承認。

## 23. 2026-10-11 P1-10b HC06 外部失効AuthorityとHost COMMIT境界の設計判断（最新）

**今回のP1-10bは設計のみ・HC06 NOT RUN。** [HOST_EXTERNAL_REVOCATION_HC06_DESIGN](HOST_EXTERNAL_REVOCATION_HC06_DESIGN.md)で、外部Issuer/Agent/Buyerの失効がeffectiveになる権威的時点 **R** とHostのnonce/Checkout/operation/outbox確定時点 **C** を分離。理想的な強いポリシーは**R<CならSTOP、nonce未消費、operation/outbox 0**。だがQで外部ALLOWを再照会しても**Q<R<C** のTOCTOUを防げず、Host DBのrow lockも別Authorityを制御しない。

比較：**A）外部再照会+UNKNOWN時STOP**は比較baseline（強い競合保証なし）、**B）失効/Host確定の共有された直列化境界**は強い参照モデル、**C）Authorityの原子的予約とfencing token強制**はAuthorityのAPIと適用側保証が必要な将来候補、**D）lease有効中は失効のeffectiveを遅らせる方式**は即時取消ではない、**E）event/cache同期**は伝播遅延・欠落だけで保証不能。具体的なAuthority契約・実装方式は未決。将来のHC06-A〜H負例/Fail Closedの試験戦略を作成したが、**コード/Actions実行/外部API接続はない**。

**現在の実測は前段P1-10aまでのHost正本9/34 IDs、12 Minitest runs/465 assertions PASSのみ**（[Actions #38136570328](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38136570328)）。**HC06はNOT RUN、残り25件NOT RUN**。N17 stateless HOST_BOUNDARY、HC04/HC07等、P1-4 G1〜G6/P1-7 T1〜T5未達、公式Python SDK 186 PASS/2 FAILを解消したとは主張しない。

**判断：P1-10bの文書設計だけ限定GO。HC06実測とHost本番統合/Gem/APIはHOLD、RubyGems公開・Production・実決済・Receipt NO-GO。** 次の1件（別途ユーザー明示承認後）：**P1-10c**、完全架空のAuthority/Hostオフラインスケジューラで再照会方式のTOCTOUとfencing条件の差を研究する。実Authority/GCP/APIデプロイ等はさらに別承認。

## 24. 2026-10-11 P1-10c HC06 TOCTOU/人工fence境界の合成オフライン実測（最新）

**完全オフラインの合成モデルとして8 runs/94 assertions/0 failures・errors・skipsがPASS。** [HOST_EXTERNAL_REVOCATION_P110C_EVIDENCE](HOST_EXTERNAL_REVOCATION_P110C_EVIDENCE.md)、[Actions #38137575582](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38137575582)。2つは安全性の合格でなく**危険な負例の期待通りの再現**：（1）権限照会QでALLOW→失効Rが有効化→Hostが古いALLOWでoperationを確定C（`Q<R<C`）、（2）fencing ticketを発行しても最終認可を強制しなければ`F<R<C`となり不正確定。Authorityのepoch/token失効後、**最終的な認可とHost確定が同一Mutexで保護された人工モデル**なら、R<CでSTOP・operation 0、C<Rで確定済operationを偽取消しせず、他tenant/subject/scopeや未知ticket、Authority障害、リプレイも停止する挙動を確認した。

**決定的な限界：** Authority/Hostは単一Rubyプロセスの二つの**論理モデル**であり、共有Mutexは本物の別サーバー/別DB間に存在しない。実環境で外部`validate_fence`を受けてからHost DBをCOMMITすると、その隙間で失効が確定するTOCTOUが再発する。今回の成功は**実Authorityの線形化／予約／フェンス強制や分散障害回復を実証せず、正本HC06全体のPASSには数えない**。HC06は**PARTIAL SYNTHETIC ONLY / FULL HOLD**。

既存PostgreSQL16研究の正本Hostテストは**34 ID中9件のみ実測、25件NOT RUN**のまま（[P1-10a最終CI #38136570328](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38136570328)：12 runs/465 assertions PASS）。今回の新8モデルテストを足してHost実DBの17件達成などと数えない。N17 stateless HOST_BOUNDARY、P1-4 G1〜G6、P1-7 T1〜T5未完、公式Python SDK中間hopの186 PASS/2 FAILは残る。

**判断：P1-10c合成研究のみGO、汎用Gem/API・実Host連携HOLD、RubyGems公開・実決済/Production・署名Receipt NO-GO。** 次の1件（新たなユーザー明示承認後のみ）：**P1-10d**。外部Authorityの原子的予約と失効effective時点、Host durable COMMIT間の協調プロトコルを**設計資料と故障モード整理のみ**で検討。外部API/GCP/本番はさらに別承認。

## 25. 2026-10-11 P1-10d HC06 外部AuthorityとHost確定間の失効協調プロトコル（最新・設計のみ）

**設計資料を作成しただけであり、実装・CI・外部Authority検証は行っていない。** [HOST_EXTERNAL_REVOCATION_P110D_PROTOCOL](HOST_EXTERNAL_REVOCATION_P110D_PROTOCOL.md)に、Verifier検証V、Authority照会Q、予約P、失効要求R_request、失効が正本上有効となるR_effective、Hostのdurable COMMIT C、外部Provider送出Dを区別し、**R_effective<Cなら新しいoperation禁止・nonce未消費**という強い契約を定義した。**R_request即時に全操作停止**はさらに強い要件であり、予約中の取引があれば失効有効化を保留する方式とは異なる。二者を混同しない。

単なるQ=ALLOW再照会やfencing token文字列はQとCの間のTOCTOUを解消しない。比較したのは **A: 再照会/TTL（不十分）、B: 共通の線形化境界、C: Authority予約・fence・失効保留（強い前提とブロックの可能性）、D: prepare/coordinator付き分散commit（外部Authority対応未確認）、E: 非同期キャッシュ（不十分）、F: 有効leaseによる失効遅延（即時取消ではない）**。どの方式も実現可能性/運用受容性が未確認なので採用決定していない。**Host COMMIT ACK喪失、予約タイムアウト、Authority障害、期限切れfence、C後D前の取消、回復中の二重送出等**について設計上の安全側応答を定義。Host C未確定なら勝手に予約解放してR_effectiveにせず、再照会しても決着しなければSTOP/PENDING。取消要求受付と失効完了のUIを分離し、長期PENDING/手動復旧の費用を可視化する。

**正本HC06は未実装・NOT FULL PASS / HOLD。** 従来の実PG16 Host研究は34件中9件のみ実測・25件未実行（[P1-10a最終CI #38136570328](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38136570328)：12 runs/465 assertions PASS）。P1-10cの8 runs/94 assertions（危険性を再現する負例2件込み）は**単一Rubyプロセスの合成モデル**であって新しい正本IDとして数えない。今回docs-onlyでActionsを新規実行していない。N17 stateless HOST_BOUNDARYとP1-4 G1〜G6/P1-7 T1〜T5、公式Python SDKの186 PASS/2 FAILは引き続き未解決。

**判断：P1-10d設計文書のみ限定GO。Gem/API、実Host統合HOLD、RubyGems公開・Production・実決済・署名Receipt NO-GO。** 次の1件（別途ユーザー明示承認後）：**P1-10e**、P先行でR_requestが競合／Host COMMIT ACK不明／timeoutによる予約解放という3ケースの**独立した架空Authority/Host検証設計のみ**。外部API/GCP/実実装は別承認。

## 26. 2026-10-11 P1-10e HC06 独立Authority/Host障害注入テスト計画（最新・設計のみ）

**資料のみ作成、新規コード・テスト・CI・PostgreSQL/外部Authority実験なし。** [HOST_EXTERNAL_REVOCATION_P110E_TEST_PLAN](HOST_EXTERNAL_REVOCATION_P110E_TEST_PLAN.md)に3系統：予約P後の失効要求（E-R01〜04）、Host durable COMMIT ACK喪失と不明結果（E-U01〜04）、予約期限切れと遅延COMMIT（E-T01〜04）を整理。**12件はいずれも将来用の計画IDでNOT RUN**。独立OSプロセス/耐久ストア、pause/barrier、ACK drop、partition、SIGKILL/restart、因果ログ・durable証拠・不変条件I1〜I6を定義した。

R_requestの受付とR_effectiveの失効完了を混同しない。COMMIT応答不明、Host row不在、lease期限切れだけで予約を解放しない。Hostの将来C不能を耐久的に強制する境界を**まだ実装しておらず**、共通の権威的順序を証明できないテスト結果はUNPROVEN/HOLD。意図した危険なbaseline再現を安全性PASSと数えない。失効長期保留の可用性リスク、外部Provider D/複数Authorityの未実証も明記。

過去のPG16 Host正本は**9/34件、25件NOT RUN、12 runs/465 assertions PASS**（P1-10a）。P1-10cの単一プロセス合成**8 runs/94 assertions**は分散実験ではない。本Stepでは新規CIを実行していない。N17 HOST_BOUNDARY、G1〜G6/T1〜T5、公式Python SDK中間hop**186 PASS / 2 FAIL**は継続。

**判定：P1-10e計画文書のみCONDITIONAL GO。HC06分散安全性・Gem/API・本番Host連携HOLD、RubyGems公開・Production/実決済/署名Receipt NO-GO。** 自己レビューは独立セキュリティ監査ではない。

**次のおすすめ1件（別途明示承認後）：P1-10f** — E-R01/E-R02に限定し、独立プロセス・独立永続ストアのオフライン実験環境を作るか、barrier/通信障害注入方式と費用・制約を先に採否判断する。自動着手しない。

## 27. 2026-10-11 P1-10f HC06 E-R01/R02の最小独立ハーネス採否判断（最新・設計のみ）

**資料のみ、環境・コード・CI・新規実測なし。** [HOST_EXTERNAL_REVOCATION_P110F_HARNESS_DECISION](HOST_EXTERNAL_REVOCATION_P110F_HARNESS_DECISION.md)に、P1-10eのE-R01（C先行、失効はpending）／E-R02（耐久abortが先、遅延stale C拒否）を独立して観測するため、Ruby worker別OSプロセス＋別PG16インスタンス/耐久領域×2の**ローカル限定研究環境を第一候補**と評価。単一Mutex/共有DBは独立性の証拠にならず、共通ローカル物理ホストの障害ドメインも残る。

**採否：CONDITIONAL GOは将来のハーネス研究案への評価のみ。実装GOではない。** Hostの最終Cを防ぐ全経路共通のdurable abort gateと、Authority側でR_effectiveを確定するための耐久的な因果/通信証拠、隔離PG16×2とfault barrier/cleanupの実現可能性の3ゲートを要求する。未達ならSTOP/再設計。R_request受付≠R_effective完了であり、即時取消を実現したとは言わない。将来の合成テストPASSが本番Authorityの線形化保証を証明することもない。追加GCP費用を発生させない案だが、ローカル計算資源、電力、実装/運用コストは未測定。新CIは未実行で無料枠を断定しない。

**過去証拠は不変：** PostgreSQL16 Host正本**9/34件、25件NOT RUN、12 runs/465 assertions PASS**。P1-10cの8 runs/94 assertionsは単一プロセスの合成研究。今回のE-R01/R02をPASSと数えない。HC06分散安全性、N17 HOST_BOUNDARY、P1-4 G1〜G6/P1-7 T1〜T5、公式Python SDKの**186 PASS/2 FAIL**は継続。**汎用Gem/API・本番Host統合HOLD、RubyGems公開・Production/実決済/署名Receipt NO-GO。** メンテナ自己レビューは独立セキュリティ監査ではない。

**次のおすすめ1件（別途ユーザー明示承認後のみ）：P1-10g** — 上記着手ゲート成立時のみ、E-R01/R02用の独立ローカルPG16/worker障害注入実験を最小実装・実測する。未成立なら設計課題へ戻す。GCP・外部Authority・Gem・本番・決済は別承認。
