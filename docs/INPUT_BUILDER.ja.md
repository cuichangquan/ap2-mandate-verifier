# 入力組み立て支援

## 0.6.0準備中の複数明細profile

公開安定版は0.5.0です。このcheckoutでは
`InputBuilder.trust(..., profile_ref: "ap2.checkout.single_merchant_multi_item")`
を明示指定できます。省略時は旧単一SKU profile v1のままです。選択は認証済みHost方針であり、
受信Mandateから推測しません。`prepare`、`restore`、`restore_trust`、`inputs`、`verify` は
既存引数のまま検証済みprofileに従います。保存済み識別子・定義hash・bindingと現在trustが
異なる場合に、再生成して修復しません。旧保存形式は旧profileのまま維持し、移行は提示前に
新selectionと新challengeを作る手順です。

`CheckoutJWT.sign` と `CheckoutReceipt.reference/sign/verify` にも同じ `profile_ref:` を
明示します。[複数明細の契約](MULTI_ITEM_CHECKOUT.md)に識別子・数量・開示・上限、
[一連の合成動作例](../examples/multi_item_checkout.rb)に署名・準備・保存・復元・現在状態の
検証と真正なSuccess/Error Receiptを示します。以下の業務注文は引き続き独立したHost値です。
受信claimの合計や鍵を、そのまま期待注文・信頼登録へ昇格させないでください。

公開済み0.4.0では安全な診断を利用できます。[診断APIと確認方法](DIAGNOSTICS.ja.md)。既存の判定・Evidence契約は維持します。

`AP2MandateVerifier::InputBuilder` は、Hostが信頼する業務情報から既存の7入力を作ります。
Rails、DB、通信、nonceの発行・消費、決済は行いません。入力の作成だけではEvidenceを返さず、
`verify` は必ず既存の `verify_checkout` 完全検証を呼びます。新旧APIを併用できます。

## 動く最小例

公開済み0.4.0を通常導入（`gem install ap2_mandate_verifier --version 0.4.0`）した後、リポジトリの例を実行します。

```sh
ruby examples/input_builder.rb valid
ruby examples/input_builder.rb tampered
ruby examples/input_builder.rb expired
ruby examples/input_builder_before.rb
```

例には独立した合成注文・公開鍵登録情報、署名原文、発行前準備、一時ファイルへの保存、復元、
現在状態の再取得、完全検証、結果の扱いが含まれます。完成済み `full.json` の読込や、
署名claimから期待金額・鍵・宛先・nonceを自己承認する処理はありません。
署名は既存の合成fixtureの原文を維持し、末尾の `~` や開示順を変更しません。
有効期限のある履歴署名なので時計も合成の固定時刻です。秘密鍵・実データは含みません。

## アプリから渡す情報

| 時点 | 渡す情報 | Gemが担当する処理 |
| --- | --- | --- |
| 初期設定／信頼情報更新 | 認証済みsnapshot、全公開鍵記録、tenant、用途・identity・key_refによる明示選択 | fingerprint、固定profile、snapshot envelope、selection JSON |
| Challenge発行前 | 注文、Root／Checkout原文、Hostが決めたID・nonce・issuer・期限 | 発行時B、原文digest、信頼参照、版付き保存String |
| 保存／復元 | Hostが保護して保存したString | 版・形状の検査。既存hashや参照を再生成しない |
| 検証 | 独立して取得した現在の注文・信頼情報、保存String、署名原文、信頼時計 | 現在B、host JSON、既存7入力、完全検証 |
| 結果の利用 | ResultとEvidence | 検証事実のみ。購入許可・決済・nonce消費はHost |

構造化入力はStringキーの通常のHash／Array／String／Integer／booleanを使います。
モデルそのもの、Symbolキー、サブクラス、暗黙変換、循環・過大な構造、未知項目は拒否します。
純粋な組み立てメソッドの不正入力は `InputBuilder::Invalid` です。
例外、結果なし、拒否・検証不能を許可として扱わないでください。

`verify` は組み立て引数の不正を既存Resultの `rejected / invalid_host_context`、
依存の不足や予期しない組み立て失敗を `unavailable / research_verification_unavailable` にします。
どちらも非成功・Evidenceなしです。完全検証に入った後の判定codeは維持します。

snapshotは `id, policy_version, active, not_before, not_after, records`、各recordは
`role, identity, tenant_id, purpose, key_ref, public_key_pem, active, not_before, not_after` です。
鍵はcanonical P256 SPKI公開PEMを渡します。非選択・inactiveの記録も暗黙に除外しません。
3役のselectorはそれぞれ `identity, purpose, key_ref` を渡します。
注文は `tenant_id, buyer_account_id, order_id, merchant_id, audience, order_version, currency,
expected_total`（整数の最小通貨単位）です。入れ子の独自JSONとhash計算は不要です。

Railsでは、たとえば `order.external_id → order_id`、`order.lock_version.to_s → order_version`、
`order.total_minor → expected_total` と明示的に対応付けます。任意のActiveRecordモデルを
Gemが自動理解する仕組みはありません。[英語版の実コード](INPUT_BUILDER.md#rails-mapping-example)と
JSONの業務情報例を参照してください。取得元の認証・最新性をアプリ側で保証してください。

## 安全な保存と現在状態

`prepare` は発行前準備であり、実際のnonce発行・永続化ではありません。
戻り値のStringを認証済みHost保存領域に保存し、検証時はそのまま `restore` に渡します。
復元時に `prepare` を再実行したり、保存B・hash・参照を現在値で置き換えたりしないでください。
発行時と現在の注文・鍵・信頼snapshot・署名原文の差異が検査される必要があります。
保存領域の真正性、失効、使用済み状態、時計、注文CASと原子的nonce消費、最終購入判断はHostの責任です。
検証成功・Evidenceは購入許可ではありません。

## Before / Afterの実測

比較対象は実行可能な `examples/input_builder_before.rb` と `examples/input_builder.rb` です。
空行・コメントを除くRuby行数は **変更前64行／変更後42行**。初期設定・対応付け、発行前準備、
保存／読戻し、現在状態、結果処理を含みます。変更後は3シナリオの選択も含みます。
小さな合成例での測定であり、一般的な開発工数の削減率・性能を示すものではありません。

- 初回導入：信頼情報の出所、業務データの対応付け、選択方針、Host保存・原子操作の設計は引き続き必要です。
- 機械的処理：呼出側のSHA256計算は4箇所から0箇所。profile envelope、snapshot body hash、鍵fingerprint、原文digestをGemが担当します。
- 日々の利用：保存Stringを復元し、現在状態を別途取得して渡します。現在B・host JSON・信頼参照の重複転記は不要です。
- 旧7入力API：既存の厳密な入力を用意できる利用者向けに維持します。

再計測コマンドと詳細な比較表は[英語版](INPUT_BUILDER.md#beforeafter-measurement)にあります。

## 版と移行

Gem版（公開0.5.0・次版案0.6.0）、AP2参照SHA `b4587ac1d055888a73b4b21750973cffba961793`、
明示選択するprofile（旧 `ap2.checkout.single_merchant_sku` v1／新 `ap2.checkout.single_merchant_multi_item` v1）、保存format v1を区別します。
未知版は旧版として解釈せずFail Closed。将来の新規業務要件までアプリ変更不要とは約束しません。
既存の7入力連携はそのまま継続でき、新たな準備から補助APIを採用できます。
既存Host JSONを新規発行Challengeへ自動変換せず、非対応保存形式はHostの正式な再承認・再発行で扱います。
[対応契約](SUPPORT_CONTRACT.md)の範囲と実Issuer・実Host・本番GO等のHOLDは変わりません。

### 既存の信頼snapshotの復元

`trust(...)` は業務情報から**新規**snapshotを作ります。既存snapshotを保存するときは
`trust.trust_json` と `trust.selection_json` の原文Stringを保ち、
`restore_trust(trust_json:, selection_json:, verified_at:)` で読み戻してください。
snapshot／profile bodyをparseして再JSON化せず、既存hashと原文を維持します。
保存済みの古いsnapshotを読み込めることは、真正性・最新性・rollback防止の証明ではありません。
