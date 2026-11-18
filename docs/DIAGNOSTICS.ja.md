# 診断

Checkout・InputBuilderは0.4.0で導入。Payment以降は公開済み1.7.0で追加。

Gem内部を追わず、失敗した検査と次の確認候補を取得できます。診断は補助情報です。
既存呼び出し、status/code、固定profile、Fail Closed、非成功時のEvidenceなし契約は不変です。
Checkout・InputBuilderの成功時のdiagnosticはnilです。診断処理が失敗してもnilとなり、検証結果は変わりません。
ヒントから購入・決済の許可を判断しないでください。

## Before / After

```ruby
result = AP2MandateVerifier::InputBuilder.verify(**host_arguments)
# 従来の利用方法も引き続き有効
puts "#{result.status}/#{result.code}"
# 追加の診断
if (diagnostic = result.diagnostic)
  puts diagnostic.to_h(locale: :ja) # 英語は :en（既定）
  # stage: :input_assembly, field: "order.currency",
  # reason: :missing_required_field, hint: "文書記載の必須項目を…"
end
```

診断は変更不能なDiagnosticオブジェクトです。stage、field、reason、hint(locale:)と
変更不能なHashを返すto_h(locale:)を利用できます。diagnostic[:stage]等も利用可能です
（hintは英語）。未対応localeは英語になります。機械判読識別子は翻訳せず、アプリ独自の
翻訳も可能です。ヒントの文面は固定契約ではないので文字列一致で判定しないでください。
今後、診断の詳細が追加される場合があります。検証結果には従来のstatus/codeを使います。

純粋なBuilder補助メソッドtrust・restore_trust・prepare・restore・inputsは、従来どおり
不備時にInputBuilder::Invalid（ArgumentErrorの子クラス）を送出します。
rescueしてerror.diagnosticを確認できます。依存障害の例外型は維持します。
例外を成功扱いせず、入力原文・任意の依存例外メッセージ・例外チェーンをログに出さないでください。

| stage / field / reason | 意味と次の確認 |
| --- | --- |
| input_assembly / order.currency / missing_required_field | 独立した現在の注文情報から通貨を取得してください。 |
| input_assembly / order.expected_total / invalid_type | 価格の表示文字列ではなく最小単位のIntegerを渡してください。 |
| input_assembly / order / unknown_field | 文書の注文項目一覧と照合してください。未知項目名は表示しません。 |
| input_assembly / saved_challenge / unsupported_saved_format | 保存形式とprofileの版の対応を確認してください。受理させるために保存済みの版を書き換えないでください。 |
| host_binding / nil / host_binding_mismatch | 保存記録と独立した現在の注文・trust・期待issuer・原文digestを比較してください。具体的な不一致項目は特定していません。 |
| purchase_binding / nil / invalid_purchase_time | 独立した時計、署名済みOpen・Closedの有効期間、terminal proofの時刻窓を確認してください。どの時刻が誤りかは断定しません。 |
| verification_unavailable / nil / 既存code | 検証を完了できません。対応依存・実行環境を確認し、業務データ不正と決めつけないでください。 |
| verification / nil / undetermined | 安全に詳しく診断できません。API契約とstatus/codeを確認してください。 |

stageは失敗検査の分類であり、実行経路の証明ではありません。既存invalid_root_signatureは
Root以外にAgent・Merchant署名でも使われるため、signature_verificationと表示します。
犯人や根本原因を断定しません。必須不足を未知項目より先に表示します。グラフ上限、parse、
下位検査等ではfieldがnil・理由が汎用になる場合があります。診断は一件だけで、後続検査は
未実行の場合があります。

既存Resultの全コードに対し、JSON・バイト、署名、Root開示、購入・委任、制約・schema、
trust選択、Host・challengeの確認候補を提供します。旧unverifiedには保証範囲の案内を返し、
完全検証成功にはしません。工程・項目・理由・ヒントは既知候補のみです。値、未知の項目名、
署名原文、鍵、nonce、個人情報、stack traceは保持・表示しません。診断はEvidenceではなく、
元入力の再構築もできません。

## 公開版をローカルで試す

対応MRI 3.4.12または4.0.9と固定依存を備えた環境で、公開済み0.4.0を通常導入し、
リポジトリのチェックアウトから例を実行してください。

```sh
gem install ap2_mandate_verifier --version 0.4.0
ruby examples/input_builder.rb valid
ruby examples/input_builder.rb tampered
ruby examples/input_builder.rb expired
ruby examples/input_builder.rb missing_currency
ruby examples/input_builder.rb wrong_total_type
ruby examples/input_builder.rb unknown_order_field
ruby examples/input_builder.rb unsupported_saved_format
```

正常はEvidenceあり、改ざんはhost_binding_mismatch、期限切れはinvalid_purchase_timeです。
後半4例はrejected / invalid_host_contextのまま、理由が順にmissing_required_field、invalid_type、
unknown_field、unsupported_saved_formatになります。合成fixtureの固定時刻を使います。
業務データの対応・保存責務は[InputBuilderガイド](INPUT_BUILDER.ja.md)を参照してください。
Gemの公開は、実Issuer接続、本番購入許可、Phase 2-B移行を意味しません。

## Payment以降の診断（公開済み1.7.0）

上記0.4.0の説明はCheckout・InputBuilderの導入時期と過去の検証記録です。
今回の追加は公開済み1.7.0で利用できます。Payment・Receiptのcode、述語、例外契約は維持します。
Direct・条件付き・Selective・Longの結果で`diagnostic`を取得できます。
成功したPaymentはnil。真正で参照が一致するError Receiptは**検証成功**であり、
`payment_rejected? == true`、`payment_succeeded? == false`、診断は`reported_error`です。
再決済や利用枠解放の許可ではありません。

```ruby
payment = AP2MandateVerifier::Payment.verify(**payment_inputs)
puts payment.code # 拒否時は従来どおり :payment_verification_failed
puts payment.diagnostic&.to_h(locale: :ja)
# stage: :payment_verification, field: nil,
# reason: :payment_time_mismatch, hint: "..."

# 1回の試行ではどちらか一方だけ。診断のためにstartを繰り返さない。
observation = service.start_with_diagnostic(ticket: ticket,
  verification_inputs: fresh_inputs)
execution = observation.execution # Executionまたはnil
puts observation.diagnostic&.to_h(locale: :ja)
# 従来のservice.start(...)は今までどおりExecutionまたはnil。
# nilなら決済を開始しない。未実行や安全な再試行を意味しない。

receipt = AP2MandateVerifier::PaymentReceipt.verify(**receipt_inputs)
if receipt.verified?
  puts receipt.payment_rejected? # 真正なErrorならtrue
else
  puts receipt.code # :payment_receipt_verification_failed
end
puts receipt.diagnostic&.to_h(locale: :ja)
```

引数・service・ticketの準備は[組み込み例](RUBY_INTEGRATION.ja.md)を参照してください。
この抜粋では独立した信頼情報、時刻、注文、保護された承認、永続保存先と決済処理を省略しています。
診断の取得で検証・予約・開始・決済・保存先の再読込は行いません。
旧版・成功・診断生成失敗で診断がnilでも、元の判定は変わりません。

### 段階・理由と確認できる事実

| stage | 代表reason | 確認できる事実 |
| --- | --- | --- |
| `payment_verification` | `checkout_not_verified` | 内部Checkout検証が成功していない。原因は断定しない |
| `payment_verification` | `checkout_binding_mismatch` | 既存のCheckoutとPaymentの照合が不一致 |
| `payment_verification` | `payment_time_mismatch` | 既存のPayment内容有効期間検査が不一致 |
| `payment_verification` | `payment_conditions_mismatch` | 完全開示profileの既存支払い条件検査が不一致 |
| `payment_verification` | `payment_binding_mismatch` | 期待Paymentまたは証明の結び付けが不一致 |
| `payment_receipt_verification` | `receipt_reference_mismatch` | 発行者・支払いID・原Payment参照の既存照合が不一致 |
| `payment_receipt_verification` | `receipt_time_mismatch` | Receipt発行時刻または独立した許容期間が不一致 |
| `payment_receipt_verification` | `reported_error` | 真正なError報告。決済成功・再試行許可ではない |
| `payment_acceptance` | `pending`・`unknown`・`receipt_error` | 既存の結果status。追加読込による推測はしない |
| `payment_acceptance` | `conflict`・`unavailable` | 保存先の例外区分のみ。具体的原因・保存確定状態は不明 |
| `payment_execution` | `saved_binding_mismatch` | 最新指示または署名原文が保存済み記録と不一致 |
| `payment_execution` | `undetermined` | 実行ハンドルなし。期限切れ・競合・不確実な保存の識別はできない |

`invalid_arguments`はPayment・Receipt・Selective検証のキーワード形状拒否です。
`signed_input_rejected`は署名入力に関する型付き拒否で、暗号署名の失敗とは限りません。
`verification_unavailable`は依存関係・検証処理の明示的な利用不可です。
それ以外の例外は`undetermined`とし、例外全文やシナリオ名から原因を推測しません。
Mandate・鍵・nonce・非開示候補・支払い情報・外部例外全文は診断へ含めません。

診断範囲は網羅的ではありません。Direct・条件付きからpolicy・継続・Longへ共通検査は届きますが、
不正な構造・Selective開示・詳細なPISPや日付制約・Long権限・期間管理は詳細不明の場合があります。
保存先の予約拒否だけでは、利用枠・回数超過と承認欠落・失効・その他の保護状態不正を区別できません。
保存先ガイドに従って保護された承認、現在の期間・利用枠、保存済み処理を確認し、特定の原因と断定しないでください。
Receipt検証は実決済の完了証明ではありません。不明・タイムアウト・真正なErrorは自動再決済や利用枠解放の根拠になりません。

### 保存と並行性

`StartResult`は呼び出しごとの変更不能オブジェクトです。serviceの`last_diagnostic`や
スレッド・Fiber共有の診断変数はありません。受理Resultの診断はfinish・reconcile・lookup・unknownも対象です。
保存形式とStoreの公開インターフェースは変更しません。独自アダプターの結果に診断がない場合は
`respond_to?(:diagnostic)`とnilで扱ってください。

保存するのはカタログ識別子だけとし、`Diagnostic.payment_flow(stage, reason)`で安全な定義へ戻せます。
未知の組合せはnil、fieldは常にnilです。保存済みstage・field・reasonの一致を検査し、
任意の保存済みhintを表示しないでください。未知値から原因を補完せず、表示時に復旧処理を始めないでください。
将来のminor版で詳細が追加され得るため未知・nilのfallbackを持ち、制御は従来のstatus・codeに従います。
