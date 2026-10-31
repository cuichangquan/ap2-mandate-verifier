# AP2 Mandate Verifier — 0.4.0

[English](README.md)

Rubyで購入委任データを検証する、AP2の固定profile向けGemです。署名データを、Hostが独立して渡す信頼情報・注文情報と照合し、不変のEvidenceを返します。**検証成功は購入許可・決済許可ではありません。**

`InputBuilder` は業務情報から検証入力を作り、Gem独自のtrust／selection／Host JSON、fingerprint、署名原文のdigest計算を担当します。誰を信頼するかの選択、期待する注文・Challenge状態・時計は利用者が渡します。Rails非依存で、通信・DB・決済処理は行いません。

## ローカルデモを試す

[把握しやすいRailsデモ](https://github.com/cuichangquan/ap2-mandate-verifier-demo#readme)は、公開済み0.4.0とInputBuilderを通常経路で使います。Docker手順ならホストへのRuby導入は不要です。正常・改ざん・期限切れの合成ケースについて、実際のstatus/code・診断・Evidence有無を比較できます。ローカル専用で、実Challenge発行・nonce消費・購入実行は行いません。

## インストール

正式対応は **MRI 3.4.12とMRI 4.0.9** です。利用者が選ぶGem環境で導入します。

```sh
gem install ap2_mandate_verifier --version 0.4.0
```

BundlerのGemfile：

```ruby
gem "ap2_mandate_verifier", "= 0.4.0"
```

runtime依存はJSON 2.19.9、JWT 3.3.0、base64 0.3.0、OpenSSL gem 4.0.2、Digest 3.2.1に固定しています。通常導入には依存の取得・buildが伴い得ます。衝突回避のために固定条件を緩めないでください。Rubyの解決範囲は、その間の全Ruby版・OS・native providerへの対応保証ではありません。[対応契約](docs/SUPPORT_CONTRACT.md)を参照してください。

## InputBuilderの最小例

導入後、このリポジトリをcheckoutし、以下をルートの `quick_start.rb` として保存して `ruby quick_start.rb` を実行します。[`examples/input_builder/`](examples/input_builder/)のJSONファイルは、明示された合成注文・公開鍵登録情報と署名原文Stringです。インストール済みGemには含まれません。保存署名には期限があるため固定の合成時計を使います。実登録や本番の現在情報として再利用しないでください。

```ruby
require "ap2_mandate_verifier"
require "json"
require "tmpdir"

builder = AP2MandateVerifier::InputBuilder
fixtures = File.join(__dir__, "examples/input_builder")
read = ->(name) { JSON.parse(File.binread(File.join(fixtures, "#{name}.json"))) }
trust_at = ->(now) do
  builder.trust(snapshot: read.call("trust_snapshot"), tenant_id: "synthetic-tenant",
    issuer: {"identity" => "issuer", "purpose" => "checkout", "key_ref" => "issuer-1"},
    agent: {"identity" => "agent", "purpose" => "checkout", "key_ref" => "agent-1"},
    merchant: {"identity" => "shop", "purpose" => "checkout", "key_ref" => "merchant-1"},
    verified_at: now)
end
wires = read.call("signed_wires").transform_keys(&:to_sym) # 原文Stringのbytesを保持。

# 発行前：独立した注文・信頼情報と、Hostが選んだChallenge情報。
prepared = builder.prepare(trust: trust_at.call(1_800_000_000),
  order: read.call("order"), root_presentation: wires.fetch(:root_presentation),
  host_checkout_jws: wires.fetch(:host_checkout_jws),
  challenge_id: "synthetic-challenge", nonce: "n", issuer_id: "synthetic-host",
  not_before: 1_799_998_000, not_after: 1_800_002_000)

Dir.mktmpdir do |directory|
  record = File.join(directory, "challenge.json")
  File.binwrite(record, prepared) # デモ用保存。本物の保存処理はHostの責任。

  # 検証時：保存原文を読み戻し、現在の注文・信頼情報を独立して取得。
  now = 1_800_000_000 # 外部から供給する合成時計。本番の時刻取得ではない。
  result = builder.verify(trust: trust_at.call(now),
    saved_challenge: builder.restore(saved_challenge: File.binread(record)),
    order: read.call("order"), **wires,
    expected_challenge_issuer_id: "synthetic-host",
    clock_source_id: "fixed-synthetic-clock", verified_at: now)
  puts "#{result.status}/#{result.code}; evidence=#{!result.evidence.nil?}"
  raise "Verification did not succeed; stop" unless result.success?
end
```

変更していない合成入力の期待値は `verified_research/scoped_research_verified; evidence=true` です。準備・保存・後の検証を1プロセス内で示す例であり、実発行や原子的消費を実装していません。実連携では、認証済みの登録・注文情報を明示的に対応付け、署名原文を保持します。構造化業務入力にはStringキーの通常のRuby値を使い、ActiveRecordオブジェクトそのものは渡しません。

検証時に `prepare` をやり直したり、保存hash／参照を現在値に合わせて更新したりしないでください。注文・信頼情報・署名原文の変化は検出できるままにします。保存済みtrust JSONは `restore_trust` で再シリアライズせず読み戻せます。[完全例](examples/input_builder.rb)には正常・改ざん・期限切れがあり、[利用案内](docs/INPUT_BUILDER.ja.md)に業務field・原文復元・Railsモデル対応付けを示しています。

## 結果と責任境界

| 結果 | 意味と利用者の処理 |
| --- | --- |
| `:verified_research` / `:scoped_research_verified`、`success? == true` | 不変のEvidenceに固定profileの検査事実があります。購入を許可するかは、Hostが別途判断します。 |
| `:rejected`、`rejected? == true` | Evidenceなし。停止して `result.code` を確認します。 |
| `:unavailable`、`unavailable? == true` | Evidenceなし。停止します。依存・処理の失敗だけで業務入力が不正とは断定しません。 |

失敗時は追加の確認ヒントを取得できます。成功時の診断は `nil` です。

```ruby
if (diagnostic = result.diagnostic)
  puts diagnostic.to_h(locale: :ja) # 英語は :en
end
```

`stage / field / reason / hint` は確認候補であり、status/codeや判定を変えません。特定不能な項目・原因は断定しません。[詳しい診断ガイド](docs/DIAGNOSTICS.ja.md)を参照してください。

例外・プロセス終了・結果なしでも、購入を許可しません。raw入力・nonceをログに出したり、シリアライズしたEvidenceを認証済みの資格情報として扱ったりしないでください。

Gemは署名、支持する開示閉包、委任、購入／Host binding、制約・期限を検査します。Hostは認証済み・独立・最新のtrust／鍵／失効、注文・Challenge状態、時計を供給します。実行直前に現在状態と期限を再照合し、nonceの原子消費＋注文CAS、不明結果の回復、最終許可・決済判断を担当します。`prepare`／`restore` は保存元の認証やnonce未使用を証明しません。

対応は固定profile `ap2.checkout.single_merchant_sku` v1です。ES256/P256、単一Merchant／SKU／cart行、USD/EUR/JPYと文書化した開示形状に限定し、未知・非対応形式は拒否します。一般AP2／全Schema、実Issuer互換性、署名／Receipt生成、Rails adapter、DB／決済実行、数値性能保証は対象外です。実Issuer・実Hostの本番GOとPhase 2-Bは引き続き別のHOLDです。

### APIの使い分け

| 入口 | 役割 |
| --- | --- |
| `InputBuilder.verify(**business_information)` | 0.4.0の推奨業務情報経路。入力を組み立て、完全検証します。発行前準備・復元は上の例の別処理です。 |
| `verify_checkout(**inputs)` | 既存の7入力を直接渡す完全検証。trust／selection／Host JSONも呼出側が渡します。 |
| `verify_research(**inputs)` | 同じ7入力検証経路の維持された名称。非推奨警告はありません。 |
| `verify(presentation_json:)` | 旧JSON構文検査のみ。成功Evidenceを返しません。 |

`InputBuilder.verify` の不足keywordを含む組み立て引数不正は `:rejected / :invalid_host_context`、組み立て中の依存・予期しない失敗は `:unavailable / :research_verification_unavailable` です。完全検証に入った後のcodeは維持します。一方、直接の `verify_checkout`／`verify_research` の不足・未知keywordは `:unavailable / :research_verification_unavailable` です。これらの非成功では、すべて `success? == false`、`evidence == nil` になります。形状・上限・Rubyの引数束縛上の注意は[正確な契約](docs/SUPPORT_CONTRACT.md#full-entry-and-required-inputs)を参照してください。

## 詳細リンク

- [業務情報の一連の利用とRails対応付け](docs/INPUT_BUILDER.ja.md)、[完全Ruby例](examples/input_builder.rb)、[変更前の例](examples/input_builder_before.rb)。
- [支持入力・上限・Result／Evidence契約](docs/SUPPORT_CONTRACT.md)、[Issuer／Host責務](docs/ISSUER_HOST_MINIMUM_CONTRACT.md)。
- [公開済み0.4.0 Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.4.0)、[公開・撤回記録](docs/PROJECT_STATUS.md)、[変更履歴](CHANGELOG.md)。リポジトリREADMEの変更で公開Gemを再build・置換しません。
- [固定commitの旧7入力・保存FULL例](https://github.com/cuichangquan/ap2-mandate-verifier/blob/e0ab9fb21045e89fc58fb06145eeda4855b2dc54/README.ja.md#保存済み合成入力で試す)、[過去版の配布物・provider証拠](research/stable010_release_linux_package/README.md)、[過去の概念図](https://github.com/cuichangquan/ap2-mandate-verifier/blob/e0ab9fb21045e89fc58fb06145eeda4855b2dc54/README.ja.md#図で見るap2の概念)。履歴は保存していますが、現在の連携手順や対応範囲を広げる根拠ではありません。
- [脆弱性報告](SECURITY.md)、[保守方針](docs/POST_RELEASE_MAINTENANCE.md)、[製品方針](docs/PRODUCT_VISION.md)。秘密鍵・実Mandate・個人情報を報告に含めないでください。

MIT。[LICENSE](LICENSE)を参照。
