# 失敗時の診断（未公開 0.4.0候補）

Gem内部を追わず、失敗した検査と次の確認候補を取得できます。診断は補助情報です。
既存呼び出し、status/code、固定profile、Fail Closed、非成功時のEvidenceなし契約は不変です。
成功時のdiagnosticはnilです。診断処理が失敗してもnilとなり、検証結果は変わりません。
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

## ローカルで試す

公開済み0.3.0は変更しません。対応MRI 3.4.12または4.0.9と固定依存を備えた隔離環境で、
チェックアウトから候補を通常インストールしてください。

```sh
gem build ap2_mandate_verifier.gemspec
gem install --local --no-document ./ap2_mandate_verifier-0.4.0.gem
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
公開、実Issuer接続、本番購入許可、Phase 2-B移行を意味しません。
