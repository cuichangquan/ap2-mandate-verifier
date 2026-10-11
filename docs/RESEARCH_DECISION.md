# Research Decision — Phase 0 / P0-5 (GO / HOLD / NO-GO)

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
