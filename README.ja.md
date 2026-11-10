# AP2 Mandate Verifier — Checkout・PaymentのRuby SDK

[English](README.md) · **公開済み安定版：1.6.0** · [Quick Start](docs/QUICK_START.ja.md)

対応するAP2 Checkout・Payment MandateをRubyだけで発行・提示・検証できます。
購入者が何を承認し、Agentが何を選べるか、署名済みの注文・支払いが条件を満たすかを
アプリで確認したいときに使います。Rails依存はありません。
**検証成功は購入・決済成功ではなく、SDKは決済を実行しません。**


**対応環境：** MRI 3.4.12 / 4.0.9。公開GemはLinux ARM64・AMD64、macOS Intel・Apple Silicon、Windows Server 2022 X64でネイティブ検証に合格しました。記録したOSイメージでの実測であり、Railsデモの対応範囲とは別です。[検証範囲と再現方法](docs/PLATFORM_SUPPORT.md)を参照してください。

## まず動かす

```sh
gem install ap2_mandate_verifier --version 1.6.0
AP2_GEM_DIR="$(ruby -e 'puts Gem::Specification.find_by_name("ap2_mandate_verifier", "1.6.0").full_gem_path')"
ruby "$AP2_GEM_DIR/examples/conditional_checkout.rb"
ruby "$AP2_GEM_DIR/examples/payment.rb"
```

Gem同梱例で合成鍵・承認を作り、Mandateの発行・提示・検証から、代替の成功／拒否Receiptの
真正性確認まで試せます。真正なError Receiptは失敗を通知します。
アカウント・認証情報・DB・Railsは不要です。対応Ruby導入済みなら約10分が目安です。
依存buildやDockerの初回取得には追加時間がかかる場合があります。

**次へ：** [手順と期待出力を示すQuick Start](docs/QUICK_START.ja.md)で、
12のUTC月と累計JPY予算超過の拒否まで試せます。
[Dockerデモ](https://github.com/cuichangquan/ap2-mandate-verifier-demo#readme)も公開済み**1.6.0**を使用し、
ローカルのCheckout画面とRuby単体のPayment例を用意しています。

## 利用方式を選ぶ

**アプリへ組み込む場合：** [Ruby組込み・プロセス終了後の復旧ガイド](docs/RUBY_INTEGRATION.ja.md)で、
保護されたアプリ入力、模擬結果の永続化、別プロセス復旧、安全な再送判断を確認してください。
新しい例はリポジトリ取得＋公開1.6.0で実行し、公開Gem archiveには未同梱です。

Checkoutは注文内容、Checkout Mandateはその承認・委任を表します。
Payment MandateはCheckout承認を参照し、支払い条件を追加します。
Receiptは元の最終Mandateに対するアプリの結果通知を認証するもので、精算を独立に証明しません。

| 方式 | 用途 | API／ガイド |
| --- | --- | --- |
| Direct | 購入者が確定した署名済み注文・支払いを承認する | `Buyer`、`Payment.issue_direct` · [Checkout](docs/BUYER_DIRECT_CHECKOUT.md)／[Payment](docs/PAYMENT.md) |
| 条件付き委任 | 購入者が候補と上限を承認し、登録済みAgentが範囲内で選ぶ | `ConditionalCheckout`、`Payment.issue_open/issue_closed/present` · [Checkout](docs/CONDITIONAL_CHECKOUT.md) |
| 選択的開示 | 完全な承認済みOpenを安全に保持し、販売者・商品または支払先・決済手段の選択候補だけ送る | `SelectiveCheckout`、`SelectivePayment` · [Checkout](docs/SELECTIVE_CHECKOUT.md)／[Payment](docs/SELECTIVE_PAYMENT.md) |
| 長期Open | 同じCheckout／Payment Openを明示UTC月で再利用し、有限回数・累計JPY予算を制限する | `LongPayment`、`PaymentAcceptance::LongSQLiteStore` · [契約](docs/LONG_PAYMENT.md) |

Direct／条件付きCheckoutは明示的な複数明細profileで1販売者・最大8明細と数量に対応します。
既定の単一商品profileは1明細の契約を維持します。選択的profileでも必須条件と数量は残り、
候補数・順序・issuer JWTのリンク可能性は隠しません。
長期Openは独立した完全開示profileです（content最大400日、提示証明は短命）。
選択的開示やPISP／日時profileとの合成は対象外です。
**UTC月次profileはAP2の汎用MONTHLY仕様への完全準拠を意味しません。**

ほかに明示的な[PISP／実行日時条件](docs/PAYMENT_POLICY.md)、
[原子的受理・復旧支援](docs/PAYMENT_ACCEPTANCE.md)、
短期の[ON_DEMAND回数／JPY予算profile](docs/RECURRING_PAYMENT.md)があります。
既存1.x APIの引数・既定値・profile・保存形式は維持します。

## 役割からAPIを選ぶ

| アプリ内の役割 | 入口 |
| --- | --- |
| 販売者バックエンド | `CheckoutJWT.sign`、`CheckoutReceipt.sign/verify` |
| 信頼された承認バックエンド | 同意前に`CheckoutJWT.verify`、`Buyer.issue_closed`または`ConditionalCheckout.issue_open`、対応するPayment発行 |
| 登録済みAgent | `Buyer.present_closed`または条件付きの`issue_closed/present`。対応profileでは選択的API。Provider秘密鍵は承認バックエンド内に保持 |
| 販売者・支払い検証側 | Directは`Buyer.verify`、条件付きCheckoutは`InputBuilder.prepare/restore/verify`、PaymentとCheckout結合は`Payment.verify`、選択的／長期は専用API |
| Receipt受信側 | `CheckoutReceipt.verify`、`PaymentReceipt.verify`。真正性と通知結果を両方確認 |
| 永続的なPayment受理を管理するアプリ | `PaymentAcceptance::Service`と対応する保護store。[組込み契約](docs/PAYMENT_ACCEPTANCE.md) |

`verify_checkout`（別名`verify_research`）は7入力の条件付きCheckout完全検証です。
業務レコードからの入力には`InputBuilder`を推奨します。
旧`verify(presentation_json:)`は構文検査のみで、成功Evidenceを返しません。
[厳密なAPI・結果・例外契約](docs/PUBLIC_API.md)を確認してください。

## 導入と対応環境

正式対応は**MRI 3.4.12と4.0.9**です。今回の手順をGemfileで使う場合は
`gem "ap2_mandate_verifier", "= 1.6.0"`を指定します。
安定1.xを追うアプリでは`"~> 1.0"`を使いlockfile更新を確認できます。
`~> 0.8.0`は1.xを選択しません。[移行案内](docs/RELEASE_100.md)に互換性の詳細を残しています。

runtime依存はJSON 2.19.9、JWT 3.3.0、base64 0.3.0、OpenSSL gem 4.0.2、Digest 3.2.1に固定。
導入時に依存取得・native buildを伴う場合があります。衝突回避のために固定条件を緩めないでください。
解決可能なRuby範囲は全Ruby版・OS・providerの認証ではありません。[対応契約](docs/SUPPORT_CONTRACT.md)。

## アプリに組み込む前の責任境界

core verifierはネットワーク・決済を実行しません。任意のacceptance storeはローカルDBの
トランザクションを実行し、SQLite driverは別途導入が必要です。
**検証・永続予約・アプリの実行許可・精算はそれぞれ別です。**

本人認証・同意・保護された承認記録・独立した最新の信頼鍵／失効／profile policy・注文／Challenge状態・時計は
アプリの責任です。実行前に現在の権限を再照合し、単発利用状態を永続的・原子的に消費し、
不明結果を扱い、processorを呼ぶかを判断します。
SDK受理やReceipt認証は実Issuerの信頼やprocessorのexactly-onceを保証しません。
Receipt不在・不正・結果不明は照合待ちとし、timeout／Errorで自動再実行・枠の返却をしません。

未知・非対応形式は拒否します。例外・unavailable・結果なしは実行許可になりません。
秘密鍵・Mandate／nonce原文をログに出さず、保存したEvidenceを認証済み資格情報として扱わないでください。
一般AP2／全Schema準拠、実Issuer互換性、本番GOは主張しません。
[Issuer／Host責務](docs/ISSUER_HOST_MINIMUM_CONTRACT.md)、[安全性](SECURITY.md)、[受理支援の限界](docs/PAYMENT_ACCEPTANCE.md)。

## 詳細と保持した検証記録

- [公開API](docs/PUBLIC_API.md)、[InputBuilder](docs/INPUT_BUILDER.ja.md)、[診断](docs/DIAGNOSTICS.ja.md)。
- [1.6.0公開照合](docs/POST_RELEASE_160.md)、[変更履歴](CHANGELOG.md)、[公開・撤回履歴](docs/PROJECT_STATUS.md)、[保守方針](docs/POST_RELEASE_MAINTENANCE.md)。
- [販売者署名](docs/MERCHANT_SIGNING.md)、[複数明細](docs/MULTI_ITEM_CHECKOUT.md)、[Python差分](docs/MULTI_ITEM_INTEROP.md)。

過去版・研究文書は当時の証拠として保持し、現在の導入経路とは区別します。
リポジトリの文書更新は公開済み1.6.0 Gemの再build・置換ではありません。

<details>
<summary>source checkoutで試すInputBuilder（発展）</summary>

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


</details>
