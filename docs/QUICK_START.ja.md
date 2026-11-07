# Quick Start：Checkout → Payment → Receipt → 月次制限

[English](QUICK_START.md) · [README](../README.ja.md)

MRI 3.4.12または4.0.9のGem環境を用意します。Rails・アカウント・本番認証情報は不要です。
合成鍵と固定時計を使い、processorへ接続しません。約10分はRubyと依存導入後の目安で、
インストール時間の保証ではありません。


SDKはRails非依存です。公開GemはLinux ARM64・AMD64、macOS Intel・Apple Silicon、Windows Server 2022 X64で両対応MRIのネイティブ検証に合格しました。公開済みGemとsource candidateの証拠を分けます。[環境別の範囲](PLATFORM_SUPPORT.md)を確認してください。任意のSQLite例にはRuby・CPU・OSに合ったdriverが必要で、別CPUのnative Gemをコピーしないでください。

## 1. 公開Gemを導入し、同梱例を探す

```sh
gem install ap2_mandate_verifier --version 1.6.0
AP2_GEM_DIR="$(ruby -e 'puts Gem::Specification.find_by_name("ap2_mandate_verifier", "1.6.0").full_gem_path')"
```

導入と実行には同じRubyを使います。既存Bundlerアプリでは
`gem "ap2_mandate_verifier", "= 1.6.0"`を指定して`bundle install`し、
Rubyコマンドに`bundle exec`を付けます。異なる版を要求するGemfileと混ぜないでください。

## 2. Checkoutを発行・提示・検証する（約2分）

```sh
ruby "$AP2_GEM_DIR/examples/conditional_checkout.rb"
```

`ConditionalCheckout.issue_open` → 登録済みAgentの`issue_closed/present`
→ 独立したHost入力の準備 → `InputBuilder.verify` → Checkout Receiptの順に進みます。
合成承認はA／Bから1個＋Cを2個です。期待出力の一部：

```text
Open -> Agent Closed -> merchant evidence: verified=true; rows=3; requirements=2
Receipt Success: authentic=true; purchase_succeeded=true
Receipt Error: authentic=true; purchase_succeeded=false
```

成功と拒否は代替の模擬結果です。真正性と業務上の成功通知は別で、Receipt不在・結果不明は照合待ちです。
確定注文のDirect承認は[source専用例](../examples/direct_checkout.rb)を使います。
このリポジトリをcloneし、Gem導入済みの環境で`ruby examples/direct_checkout.rb`を実行してください。
1.6.0 Gemには同梱されていません。[Direct API](BUYER_DIRECT_CHECKOUT.md)。

## 3. Paymentを追加してReceiptを確認する（約2分）

```sh
ruby "$AP2_GEM_DIR/examples/payment.rb"
```

Checkout例を再利用し、それに結合するDirect／条件付きPaymentを作ります。
`Direct and conditional Payment: verified`、続いて
`Payment Receipt Success: authentic=true; reported_success=true`と
`Payment Receipt Error: authentic=true; reported_success=false`を確認します。
各方式で両方の代替結果を試し、決済は実行しません。
ファイル内の`Payment.details/issue_direct/issue_open/issue_closed/present/verify`と
`PaymentReceipt.sign/verify`が組込みの入口です。[Payment契約](PAYMENT.md)。

## 4. 長期Openを12か月使う（約3分）

署名データだけの例はDB不要です：

```sh
ruby "$AP2_GEM_DIR/examples/long_payment.rb"
```

**永続的な累計制限**には任意のSQLite参照driverが必要です。Gemのcore依存ではありません。
分離したGem環境で`gem install sqlite3 --version 2.10.2`を行い、次を実行します：

```sh
ruby "$AP2_GEM_DIR/examples/long_payment_acceptance.rb"
```

期待出力は`12 explicit leap-year periods, 12 mock starts, reserved96000JPY within100000JPY`。
2028年を合成時計で進めるので1年待つ必要はなく、ジョブも登録しません。
同じOpenペア・12回のfresh proof・保護された権限更新・毎月8,000円・元Receiptの復旧を確認します。
一時DBは終了時に削除します。本番の永続保存として再利用する構成ではありません。

**予算だけによる拒否**の比較には、このリポジトリをcloneして新しい補足例を実行します。
インストール済みGemを使用し、この補足例自体は公開1.6.0 archiveには含まれません：

```sh
git clone https://github.com/cuichangquan/ap2-mandate-verifier.git
cd ap2-mandate-verifier
ruby examples/long_payment_limits.rb
```

12か月の例の後、別の承認で1月・2月に各40,000円を予約します。
3月の署名データは有効で3回目の回数枠も残りますが、累計120,000円は100,000円を超えるため
`acceptance=rejected`、`ticket=false`となり、予約は80,000円／2件のままです。
この比較ではprocessorを開始しません。状態を持たない検証だけでは過去の累計を制限できません。

**ローカルにRuby／SQLiteを導入したくない場合：**
[デモの公開Gem Docker手順](https://github.com/cuichangquan/ap2-mandate-verifier-demo#readme)を使ってください。
記載imageはLinux ARM64向けで、他環境の対応を証明しません。

## 次に試してから組み込む

| 目的 | Gem同梱の実行例 | ガイド |
| --- | --- | --- |
| 候補の送信を減らす | `selective_checkout_payment.rb` | [選択的Checkout](SELECTIVE_CHECKOUT.md) |
| PISP／実行日時を制限 | `payment_policy.rb` | [条件](PAYMENT_POLICY.md) |
| 応答消失から復旧 | `payment_acceptance.rb`（SQLite） | [受理支援](PAYMENT_ACCEPTANCE.md) |
| 短期ON_DEMAND制限 | `recurring_payment.rb` | [回数・予算](RECURRING_PAYMENT.md) |

`ruby "$AP2_GEM_DIR/examples/NAME.rb"`で実行します。archive外のsourceやfixtureを使う
InputBuilder例にはcheckoutが必要です。GitHubの全サンプルがGem内にあるとは限りません。
[対応・依存](SUPPORT_CONTRACT.md)。

組込み時は、合成本人認証・同意・保護された承認・最新trust／注文／Challenge／時計・保存先を
アプリの仕組みに置き換えます。署名原文を保持し、Provider秘密鍵をAgentに渡しません。
共有永続状態・原子的単発消費・processor冪等性・照合復旧を用意してください。
Evidenceや真正なReceiptは精算の証明ではありません。
長期UTC月次JPY profileは汎用AP2 MONTHLY準拠を意味しません。
[正確な範囲と非対応の組合せ](LONG_PAYMENT.md)を確認してください。
