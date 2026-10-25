# Issuer登録前チェックリスト兼記入票

状態：**Issuer未定・記入用／実Issuer未証明・本番HOLD**。
基準main：`4eb061ca3edd949b605f66eafe176710ec2533bb`。
これは既存仕様の利用者向け整理であり、新しい登録APIや信頼の自動認定ではありません。
秘密鍵・パスワード・APIキー・認証トークンは記入しないでください。

## Hostが保持する承認・運用記録（Gem JSONの追加項目ではない）

各欄は未決のまま開始します。根拠URL等、実際の確認日、未決理由を対応付け、確認していない日付や主体を埋めないでください。

| 確認項目 | 記入内容・必要な根拠 | 現在の状態 |
| --- | --- | --- |
| 主体・用途 | 発行主体、tenant/利用範囲、許可する用途 | 未決 |
| 承認根拠 | 帯域外で確認した主体と用途の承認根拠、承認者 | 未決 |
| 鍵と主体の紐付け | 真正な公開鍵配布元、主体による鍵所有の根拠、鍵参照・fingerprint | 未決 |
| 有効期間 | 主体・用途・鍵の適用開始/終了、確認期限 | 未決 |
| 更新・失効 | 正本の情報源、確認方法、鮮度上限、次回確認期限、更新不能時の担当 | 未決 |
| 版・rollback防止 | snapshot/profileの正本版・hash、更新履歴、古い状態を拒否するHost側記録 | 未決 |
| 固定profile適合 | 下記固定profileと実際の発行データの差分・適合根拠 | 未決 |
| 根拠の由来 | 上記各項目の根拠URL/文書参照・実確認日・確認者・残る不明点 | 未決 |
| Owner判断 | 採用/保留/拒否、対象範囲、承認者・承認日・再確認条件 | 未判断 |

任意の公開鍵、宣言、取得できた鍵、署名の成功だけでは信頼は成立しません。
Issuerが未定の現在は、用途や担当者の検討を進めても、実Issuerの採用済みとは扱いません。

## 既存Gem入力との対応（新APIを追加しない）

公開入口は `AP2MandateVerifier.verify_research` です。以下は既存入力の要約であり、完全なJSONテンプレートではありません。Host運用記録を厳密なJSON形状へ追加しないでください。

| 既存入力 | 実在する項目・役割 |
| --- | --- |
| `trust_json` のsnapshot内record | `role`、`identity`、`tenant_id`、`purpose`、`key_ref`、`profile_ref`、`profile_version`、`public_key_pem`、`key_fingerprint`、`algorithm`、`active`、`not_before`、`not_after`。fingerprintは受理するPEMの正確なbytesのSHA256 |
| snapshot/profileと`selection_json` | 正確なbody/hashと識別子、固定profile、選択する各roleの`identity`/`purpose`/`key_ref`を整合。任意のprofile定義へ差し替えない |
| `host_json`・`verified_at` | 注文binding、challenge、期待するchallenge issuer、時計sourceと検証時刻。Hostが真正で最新の事実を供給 |
| 署名入力 | `root_presentation`、`terminal_jws`、`host_checkout_jws`。信頼登録用の永続化・外部取得APIではない |

固定profileは `ap2.checkout.single_merchant_sku` / version `1`、7支持形状、ES256/P-256、AP2固定参照 `b4587ac1d055888a73b4b21750973cffba961793` に限定します。一般AP2適合を意味しません。

## 不足時の判断と利用境界

- 外部信頼根拠、失効の最新性、鮮度、用途承認が不明ならHostは**HOLD**。未確認を`active: true`等で埋めて通さない。
- Gemは供給された内容の既存検査を担当し、外部信頼や失効情報の最新性を独立証明しません。入力不正・未知/曖昧な鍵・期限外等は`rejected`、処理系/依存等で判断不能なら`unavailable`。HOLDはHostの判断で、Gemの新しいstatusではありません。
- Evidenceは**ALLOWでも決済許可でもありません**。信頼する同一Rubyプロセス内で扱い、JSONから再構成したHashを真正なEvidenceとしない。使用直前の最新状態再照合、nonce消費と注文CAS、最終ALLOWはHost責任です。
- 記入完了だけでは採用・実Issuer対応・本番GOになりません。Ownerの根拠付き判断を別途記録します。

正本：[最小契約](ISSUER_HOST_MINIMUM_CONTRACT.md)、[TrustContext](../lib/ap2_mandate_verifier/trust_context.rb)、[HostBinding](../lib/ap2_mandate_verifier/host_binding.rb)。既存Gem検査をHostへ移すものではありません。
