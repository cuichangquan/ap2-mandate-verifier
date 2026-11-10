# Rubyアプリ組込みとプロセス終了後の復旧

[English](RUBY_INTEGRATION.md) · [Quick Start](QUICK_START.ja.md) · [受理契約](PAYMENT_ACCEPTANCE.md)

アプリの正本データ、条件付きCheckout、Payment、永続的な受理、元取引に結合したReceiptを
つなぐ入口です。実行ファイルは[`examples/ruby_integration.rb`](../examples/ruby_integration.rb)、
アプリ入力の構築は[`integration/inputs.rb`](../examples/integration/inputs.rb)です。
合成の登場者とSQLiteの模擬processorだけを使い、Rails・A2A・外部アカウント・実決済は不要です。
**組込みを理解するための実装例であり、本番の認証・認可backendではありません。**

## 1. Dockerと公開Gemで動かす

Docker導入済みが前提です。ホストへのRuby・SQLiteインストールは不要です。
新しいcheckoutから実行します：

```sh
git clone https://github.com/cuichangquan/ap2-mandate-verifier.git
cd ap2-mandate-verifier
docker build -f examples/integration/Dockerfile -t ap2-ruby-integration .
docker volume create ap2-ruby-integration-state
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration init /state/happy
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration run /state/happy success
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration inspect /state/happy
```

build時はRuby・依存を取得し、例の実行時はネットワークを無効にします。
imageはRuby 4.0.9、公開`ap2_mandate_verifier = 1.6.0`、任意driverの
`sqlite3 = 2.10.2`を使います。新しい実装例のsourceはこのcheckoutから取得し、
**公開済み1.6.0 Gem archiveには含まれていません**。実際のSDKの版と読込先も確認します：

```sh
docker run --rm --network none --entrypoint ruby ap2-ruby-integration -rap2_mandate_verifier -e 's = Gem.loaded_specs.fetch("ap2_mandate_verifier"); puts "gem=#{s.version}; path=#{s.full_gem_path}"'
```

SDKはインストール先のGemディレクトリを指す必要があり、リポジトリの`lib`ではありません。
公開Gemでの実行を確認する際は`-Ilib`や`RUBYLIB`を追加しないでください。
既存の`conditional_checkout.rb`、`payment.rb`、`payment_acceptance.rb`はGemだけで
取得できる例です。[Quick Start](QUICK_START.ja.md)に同梱場所の確認手順があります。
新CLIと補助ファイルは次版向けsource-built Gem候補に同梱します。
リリース判断前の候補が`1.6.0`と表示されても、公開archiveとは別のartifactです。
公開1.6.0のインストールだけで新CLIを取得できるとは扱わないでください。

候補Gemと任意のSQLite driverを分離したRuby環境へ導入した後は、同梱CLIの実行に
リポジトリは不要です：

```sh
AP2_GEM_DIR="$(ruby -e 'puts Gem::Specification.find_by_name("ap2_mandate_verifier").full_gem_path')"
test -f "$AP2_GEM_DIR/examples/ruby_integration.rb"
ruby "$AP2_GEM_DIR/examples/ruby_integration.rb" init /tmp/ap2-integration-new
ruby "$AP2_GEM_DIR/examples/ruby_integration.rb" run /tmp/ap2-integration-new success
```

`test`は同梱確認であり、別sourceへfallbackするものではありません。新しい保存先を使い、
`init`を通すために既存状態を削除しないでください。次版公開までは、上記Docker／リポジトリ
経路が公開Gemを使う再現手順です。公開と次の版番号は別途判断します。

時計はすべて仮想です。初期epochは**1,800,000,000**で、実時計を使いません。
Mandate／challengeの期限は+60秒、遅延Receiptは独立した検証窓内の+120秒を使います。
翌年に実行しても通常例が突然期限切れになりません。本番では独立した現在の信頼時計へ差し替えます。

正常系では、最初の受理だけがTicketを返し、freshな`start`が模擬実行を1回許可します。
真正なSuccess Receiptを照合すると`receipt_success`になり、永続化した模擬実行数は**1**です。
これは実際の精算の証明ではありません。`inspect`は署名素材ではなく安全な要約を表示します。

## 2. 実際に終了し、別プロセスから復旧する

独立した合成シナリオごとに別ディレクトリを使います。`init`は既存ディレクトリを拒否します。
通常コマンドは既存の`app.json`、`acceptance.sqlite3`、`processor.sqlite3`が必要です。
ファイル消失を初期化で補いません。

```sh
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration init /state/crash
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration run /state/crash crash-after-charge
# 終了コード75が期待値。元のRubyプロセスはここで終了する。
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration recover /state/crash
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration inspect /state/crash
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration retry /state/crash
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration retry /state/crash resigned
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration inspect /state/crash
```

意図的な非zero終了の後にも復旧コマンドを実行します。`&&`で連結しないでください。
`docker run`ごとに別のRubyプロセスが起動し、named volumeは`--rm`でも残ります。
復旧前はSDKが`pending`で、模擬processorに実行1件と署名済み結果が残っています。
復旧は元のprocessor keyで照会し、元取引に結合したReceiptを検証して
`receipt_success`へ進みます。追加実行はありません。通常再送・再署名とも元のレコードを返し、
**新しいTicketは出ず**、模擬実行数は**1**のままです。
再署名は新しい業務occurrenceではなく、最初の署名原文を置き換えません。

既存の[`payment_acceptance.rb`](../examples/payment_acceptance.rb)は、
**同じRubyプロセス内**でStoreを開き直し、模擬結果をメモリに保持します。
小さなAPI例として有用ですが、プロセス終了・processor結果の永続化を示すものではありません。
復旧を組み込む際はこのCLIを先に読み、その後に既存例でAPIを比較してください。

## 3. アプリから渡す入力と保存対象

受信Mandateの自己申告から承認条件・正規注文・信頼鍵を作らないでください。
合成bootstrapが両者を用意するのは、例を単独実行可能にするためです。

| 入力 | 保持する主体／独立した取得元 | 保存・再確認するもの |
| --- | --- | --- |
| 承認・購入条件 | 認証済み購入者の同意／保護された承認backend | 候補、数量、金額、通貨、支払手段、正確なgrant。現在のactive／失効状態 |
| 正規注文 | 販売者の注文DB | tenant、buyer/account、注文ID・版、merchant、audience、正確なCheckout・期待総額。開始前の現在注文 |
| 現在の信頼鍵 | 保護されたissuer／Agent／merchant registry | identity、用途、鍵selector、公開鍵、active、期限、policy版。JWT headerから信頼を作らず現在registryを取得 |
| challenge | Hostのchallenge／nonceサービス | `InputBuilder.prepare`の保存記録、binding、nonce、audience、期限。fresh入力で`restore`し、本番では現在状態の原子的消費 |
| 期待するPayment | 承認済み注文と支払選択 | 金額、通貨、payee、instrument、Checkoutとの結合。受信Paymentとは独立して構築 |
| 安定した業務scope | 認証済みアプリworkflow | tenant・merchant・operation・approval・occurrence・orderの各ID。再送・再起動でも維持 |
| 最初の署名原文 | 最初に予約された試行 | 正確なCheckout／Open／Closed bytesとReceipt参照。復旧用に再生成しない |
| processorの識別・結果 | 受理レコードとprocessor | 最初のprocessor key、永続化した照会・結果。timeoutで別keyにしない |
| Receipt照合条件 | 保護された登録処理／processorとの契約 | 固定したissuer・公開鍵・payment ID、元Closed参照、独立した検証時間窓 |

`InputBuilder.prepare`でchallengeを保存します。検証・開始時には保護されたfixtureの正本を
読み直し、trustを選び、`restore`と`inputs`を呼び、完全なraw検証入力をSDKに渡します。
記録の復元や保存済みResult／Evidenceの読戻しは**現在の検証ではありません**。
coordinatorは再検証し、実アプリは現在の権限を正本で再確認し、nonce・注文状態を原子的に消費します。

専用ディレクトリ（0700）と`app.json`（0600）には合成秘密鍵、信頼入力、保存challenge、
最初の署名原文を保持します。2つのSQLiteファイルは受理台帳と模擬processor結果です。
一式を保護・保持し、commit・表示・ログ共有しないでください。
例は秘密鍵、再利用可能な署名原文、nonce、Ticketの値を表示しません。
本番ではsecret保管、アクセス制御、保持期限、暗号化、backup方針が別途必要です。

CLIは完了したコマンドごとにJSON要約を出力します。正常系の例（runtime情報は省略）：

```json
{"event":"finished","sdk_state":"receipt_success","ticket":false,"mock_dispatches":1,"receipt_authentic":true,"reported_outcome":"Success"}
```

`ticket`は有無のbooleanだけで、実行能力の値ではありません。
`sdk_version`、`sdk_load`、`ruby`、`fixture_clock`は実行環境を示し、上記経路では
`1.6.0`、`installed_gem`、`4.0.9`、`1800000000`が期待値です。
クラッシュ出力には`simulated_process_exit: 75`が付きます。照会結果がなければ
`event: operator_reconciliation_required`、`result: unknown`となり、SDK状態は
`pending`のままの場合があります。この区別を再実行の許可にしないでください。

## 4. 状態遷移と復旧判断

```text
保護された承認 + raw入力検証
  -> reserved（最初の呼出元にopaque Ticket）
       -> fresh start + fenced CAS -> processing（lookupはpending）
       |                               -> receipt_success
       |                               -> receipt_error
       |                               -> unknown -> 検証済み照合 -> receipt_success/error
       -> 現在入力が無効: 実行しない

再送・再署名・プロセス再起動 -> 元レコードをlookup。新Ticketなし
保存先の消失・破損 -> 停止。代替台帳を初期化しない
```

`reserved`・`processing`は内部phaseです。未完了レコードの後続lookup／再送は
`pending`を返します。freshな`start`を試せるのは元のopaque Ticketだけです。
クラッシュでその能力を失っても再発行されません。

各行について、上記Dockerコマンドのprefixを使い`init /state/NAME`、
`run /state/NAME SCENARIO`、その後`recover /state/NAME`と`inspect`を実行します。
1ディレクトリは保護された合成occurrenceの1件です。再送のための新しい権限を作る手段ではありません。

| SCENARIO | 期待する永続状態／模擬実行数 | 安全な次の判断 |
| --- | --- | --- |
| `success` | `receipt_success`／1 | 元の確定結果を読み、再送で再実行しない |
| `error` | `receipt_error`／1 | 真正なError通知。未課金の証明ではなく自動再決済しない |
| `pause-before-start` | 同一プロセスのreopenでTicketを保持し完了／1 | freshな現在入力で開始。クラッシュ復旧とは別 |
| `expired-before-start` | 開始なし／0。予約は未完了 | challenge／Mandate期限切れで停止。Ticket再発行・自動解放なし |
| `crash-before-start` | 終了75。`pending`／0 | 別プロセスは照会可能だがTicketを復元できない。運用照合へ |
| `crash-after-start` | 終了75。`pending`／0 | Receiptなし。模擬実行数0でもpendingを維持 |
| `crash-after-charge` | 終了75。`pending`／1、署名済みReceiptあり | `recover`で`receipt_success`／1へ。追加実行なし |
| `unknown` | `unknown`／1、Receiptなし | 復旧後もunknown。元keyで照会し、未解決なら運用判断 |
| `delayed` | `unknown`／1、後刻のReceiptあり | +120で`recover`。元のReceipt窓で検証して`receipt_success`／1へ |

観測した呼出数0、Receipt不在、時間経過、`pending`、`unknown`、真正なError Receiptを、
再決済や予約枠解放の許可にしません。模擬processorは効果と結果を1つのlocal transactionに
記録しますが、**実processorの分散exactly-onceを証明しません**。

## 5. 実アプリへ差し替える責務

1. 合成承認・鍵を、認証済み同意、保護された発行処理、現在のtrust registryに置き換えます。
   JSON注文を正本の注文サービスへ置き換え、受信フラグからgrantを登録しないでください。
2. 現在のgrant・注文・nonce・occurrence確認を、同じ正本transaction内の予約／開始CASへ
   統合します。fixtureのsnapshotや「別DBで確認後にCAS」では本番認可の原子性を証明できません。
3. 模擬processorを、冪等性・照会契約を確認したPSP adapterに置き換えます。
   元key・最初の署名原文を維持し、再利用可能な素材をログに出さず結果を保存します。
   固定時計を本番の信頼できる現在時計へ置き換えます。
4. 自動化するのは結果取得可能な場合の読取・照会と、認証した元取引への照合です。
   Receiptの署名、issuer、payment ID、元参照、検証時間窓を確認します。
   正しい署名でも別参照は拒否し、再署名した別原文へ古いReceiptを付け替えません。
5. Ticket消失、結果未取得、DB消失・破損、rollback、trust rotation、証拠の矛盾は運用担当へ
   引き継ぎます。dispatchを止め、PSPで元取引を照合し、明示的な業務復旧方針に従います。
   台帳削除や新IDの作成で復旧したことにしないでください。

**Mandateの検証成功、アプリの現在の実行許可、processorの実行有無、Receiptの真正性、
Receiptが報告する結果**を分けて判断します。Success通知だけでは精算を証明しません。
API・保存契約と永続化の限界は[Payment受理・復旧仕様](PAYMENT_ACCEPTANCE.md)を参照してください。
