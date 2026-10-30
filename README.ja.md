# AP2 Mandate Verifier — 0.2.0

[English](README.md)

RubyでAP2の固定profileを検証する、Rails非依存のGemです。**署名の正しさだけで購入を許可しません。** 必要な検査が成立した場合に不変のEvidenceを返し、最終業務判断はHostが行います。

購入委任の正常・改ざん・期限切れを試すには、[ローカルRailsデモ](https://github.com/cuichangquan/ap2-mandate-verifier-demo)と[Zennの解説記事](https://zenn.dev/ccq/articles/7f9643f96fe5c7)をご覧ください。

## 導入経路を選ぶ

| 経路 | 最初に見る場所 |
| --- | --- |
| Dockerデモ：3つの合成ケースを比較 | [デモREADME](https://github.com/cuichangquan/ap2-mandate-verifier-demo#readme)のローカル起動手順と正常／改ざん／期限切れの例を参照。Dockerコマンドはデモ側で管理します。 |
| デモを使わないRuby単体：既存のMRI 4.0.9 | 下記の[導入](#配布と導入)から[保存済み合成入力の例](#保存済み合成入力で試す)へ進みます。 |

どちらも固定profileの検証器を使う経路であり、決済実行やHostの業務許可を提供しません。範囲は[対応契約](#対応範囲)を参照してください。5分程度で選択肢を理解できる説明を目指すもので、導入やbuildが5分で完了する保証ではありません。

## 配布と導入

[0.2.0はRubyGemsで公開済み](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.2.0)です。固定profileの検証専用安定版であり、旧研究版pre3は別の成果物です。

既存のMRI 4.0.9環境と利用者が選ぶGem隔離環境で使用します。通常の導入は依存取得・JSON native buildを伴い得ます。依存衝突や未知providerを許容するために固定条件を緩めないでください。

```sh
ruby --version # MRI 4.0.9 required
gem install ap2_mandate_verifier --version 0.2.0
```

BundlerのGemfile：

```ruby
gem "ap2_mandate_verifier", "= 0.2.0"
```

固定runtime依存：JSON 2.19.9、JWT 3.3.0、base64 0.3.0、OpenSSL gem 4.0.2、Digest 3.2.1。
Bundler 4.0.20は既存resolver基準でruntime依存ではありません。Gemの版制約だけではMRI engine、OSや実native/providerの出所を保証しません。

## 検証API：0.2.0と互換性

**下記の導入コマンドと保存済み入力の例は、公開済み0.2.0の推奨入口 `verify_checkout` を使います。** 0.1.0の既存利用者は `verify_research` を継続でき、0.2.0でも非推奨警告なしで維持します。0.1.0には `verify_checkout` はありません。

| 入口 | 利用可能な版と契約 |
| --- | --- |
| `verify_checkout(**inputs)` | 0.2.0の推奨完全検証入口。入力を加工せず `ResearchResult.verify` に直接委譲し、検証経路を変更しません。 |
| `verify_research(**inputs)` | 公開済み0.1.0の完全検証入口。v0.2.0でも変更せず維持し、非推奨警告も追加しません。 |
| `verify(presentation_json:)` | 既存のJSON構文検査のみ。有効なJSONでも `:unverified` / `:verification_not_implemented` を返し、成功Evidenceを返しません。完全検証の代用にはなりません。 |

推奨入口には7入力すべてを渡します。下記の保存済み入力例では `full` から読み、実連携では認証済みHost入力契約に従います。

```ruby
result = AP2MandateVerifier.verify_checkout(
  trust_json: full.fetch("trust_json"),
  selection_json: full.fetch("selection_json"),
  host_json: full.fetch("host_json"),
  root_presentation: full.fetch("root_presentation"),
  terminal_jws: full.fetch("terminal_jws"),
  host_checkout_jws: full.fetch("host_checkout_jws"),
  verified_at: full.fetch("verified_at")
)
```

両完全検証入口とも、[責任境界](#実入力と責任境界)に示す7入力（原文String 6つと外部から供給される整数Unix秒）がすべて必要です。7入力と7支持形状は別の数え方です。下記の固定profileを広げたり、不足したtrust・Host状態・時刻を補完したりしません。不足・未知keywordは `:unavailable` / `:research_verification_unavailable`、`success? == false`、`evidence == nil` になります。位置引数や不正なkeyword展開は検証開始前に例外となり得ます。

[結果の扱い](#結果の読み方)も不変です。成功は `ResearchResult` の `:verified_research` / `:scoped_research_verified` と不変のEvidence v2、拒否・検証不能はEvidenceなしです。Evidenceは検査事実であり、**購入許可ではありません**。例外・無結果でも呼出し側を停止します。設計経緯は[API移行計画](docs/V0_2_0_API_PLAN.md)を参照してください。同書の過去の実装承認待ち記録と、公開済み0.1.0の成果物・本書の利用可能版の区別を混同しないでください。

## 対応範囲

- AP2固定source `b4587ac1d055888a73b4b21750973cffba961793`、登録profile `ap2.checkout.single_merchant_sku` v1の正確なbody/hash・7支持形状

- ES256/P256、Open1→Closed1、固定3開示位置、単一Merchant/SKU/行、USD/EUR/JPY、empty links。未知/非対応形式は拒否

- 厳格入力と有限上限、供給trust選択、Root原文署名と全域閉包、Agent/Merchant署名・委任・購入/Host binding、型/制約/期限をGemが検査

- 上記の両完全検証入口で `verified_research/scoped_research_verified`・Evidence v2契約を維持。安定版番号でも一般AP2対応やHost許可へ昇格しない

正確な必須形状・全上限・失敗codeは[SUPPORT_CONTRACT](docs/SUPPORT_CONTRACT.md)を参照してください。

## 環境・互換性・保守

対象はMRI 4.0.9と固定依存、観測されたMBA/macOS arm64 (`arm64-darwin25`) およびUbuntu 24.04/x86_64の正確な構成です。[現行版の包装・provider証拠](research/stable010_release_linux_package/README.md)と[過去の環境記録](docs/VERIFIER_CORE_COMPLETION_CRITERIA.md#初回の対応環境保証範囲owner採用済み)を区別してください。OS全版・他engine/architecture・任意provider更新は保証しません。

支持入力の判定意味・APIを黙って変更しません。安全性修正で受理を狭める場合は理由・影響・移行を明示し、破壊的なAPI/必須field/profile変更を区別します。依存更新は自動互換ではありません。

初回安定系列の最新修正版のみを保守対象とし、月次・関連勧告判明時・次版前に手動確認します。旧版backport・固定保守年数・受付/修正期限・24時間対応は約束しません。[SECURITY](SECURITY.md)と[保守方針](docs/POST_RELEASE_MAINTENANCE.md)を参照し、秘密鍵・実Mandate・個人情報を報告しないでください。

## ローカルデモ

[AP2 Mandate Verifier Demo](https://github.com/cuichangquan/ap2-mandate-verifier-demo)では、正常・改ざん・期限切れの合成入力を実際の検証器へ渡し、Dockerでローカル起動できます。公開ホスト型のデモサイト・本番決済・Hostの業務許可を提供するものではありません。

## 保存済み合成入力で試す

以下は既存の合格済みinstalled検査と同じ公開 `FULL` 入力を読む例です。入力JSONはGemに含まれません。固定commitから取得し、SHA256を確認してから使います。fixtureに秘密鍵は含まれません。fixtureのtrust／Host入力は**テスト専用の合成値**であり、実Issuer登録・現在の注文・実時刻として再利用してはいけません。`verified_at = 1800000000` は保存シナリオの固定時刻です。

```sh
set -eu
curl --fail --location --proto '=https' --proto-redir '=https' \
  --output AP2_RESEARCH_INPUTS.json \
  https://raw.githubusercontent.com/cuichangquan/ap2-mandate-verifier/f6d4f83d396b75505256dba5769a54a8f065eeea/research/stage15/results/R3/INPUTS.json
printf '%s\n' '41ad845a7ea82a9c7316c9ef11fb8ee5281453afafe2b4932c7217c1936562c1  AP2_RESEARCH_INPUTS.json' | shasum -a 256 -c -
# Save the Ruby example below as research_example.rb, then:
ruby research_example.rb
```

```ruby
require "ap2_mandate_verifier"
require "json"
require "digest"

raw = File.binread("AP2_RESEARCH_INPUTS.json")
expected = "41ad845a7ea82a9c7316c9ef11fb8ee5281453afafe2b4932c7217c1936562c1"
raise "fixture checksum mismatch" unless Digest::SHA256.hexdigest(raw) == expected

full = JSON.parse(raw).fetch("FULL")
inputs = {
  trust_json: full.fetch("trust_json"),
  selection_json: full.fetch("selection_json"),
  host_json: full.fetch("host_json"),
  root_presentation: full.fetch("root_presentation"),
  terminal_jws: full.fetch("terminal_jws"),
  host_checkout_jws: full.fetch("host_checkout_jws"),
  verified_at: full.fetch("verified_at")
}

result = AP2MandateVerifier.verify_checkout(**inputs)
puts "status=#{result.status} code=#{result.code}"
if result.success?
  checked_facts = result.evidence.to_h # Detached, deeply frozen in-process facts.
  puts "Scoped verification succeeded; this is NOT purchase authorization."
  # No payment, order update or nonce consumption is performed here.
else
  raise "Verification did not succeed; stop."
end
```

この保存 `FULL` ケースの期待値は `status=:verified_research`、`code=:scoped_research_verified`、`success?=true` です。実入力・不支持入力・依存障害では同じ結果を期待しません。非成功ならEvidenceはnilです。例外やプロセス終了で結果がない場合も停止してください。Evidence全体やraw入力を安易にログへ出さないでください。

## 結果の読み方

| 分類 | `status`と判定メソッド | Evidenceと扱い |
| --- | --- | --- |
| 固定範囲の検証成功 | `:verified_research`、`success? == true`、`code == :scoped_research_verified` | あり。検査事実であり、**購入許可ではありません**。Host側の責任は残ります。 |
| 拒否 | `:rejected`、`rejected? == true` | なし（`nil`）。停止し、`result.code`で拒否理由を確認します。 |
| 検証不能 | `:unavailable`、`unavailable? == true` | なし（`nil`）。停止します。依存や検証処理の失敗だけで、入力が不正と断定しません。 |

例外・プロセス終了・結果なしの場合も、購入を許可せず停止します。上の例は意図的にすべての非成功で停止します。詳細は[Result and Evidence](docs/SUPPORT_CONTRACT.md#result-and-evidence)を参照してください。

## 実入力と責任境界

| Keyword | 入力契約 |
| --- | --- |
| `trust_json` | 認証済みHostの固定snapshot/profileと公開鍵登録を表すJSON原文String |
| `selection_json` | 独立Hostが選択したtenant・profile版・Issuer/Agent/Merchantの識別／用途／鍵参照 |
| `host_json` | 認証済み現在注文binding、issued challenge、発行元・時計識別 |
| `root_presentation` | disclosure順と末尾`~`を維持した署名付きRoot提示原文String |
| `terminal_jws` | Agent terminal compact JWS原文String |
| `host_checkout_jws` | Hostが固定したMerchant Checkout compact JWT原文String |
| `verified_at` | 外部の信頼時計から供給する整数Unix秒 |

正確な必須形状・型・上限は[SUPPORT_CONTRACT](docs/SUPPORT_CONTRACT.md#full-entry-and-required-inputs)を参照してください。tokenからtrustを自己登録したり、署名原文をparse／再encode／並べ替えして渡したりしません。Host-onlyなBuyer/account等の一致はIssuer署名による本人認証を意味しません。

両完全検証入口の成功は固定profileにおける検証事実です。Hostは最新trust／失効／注文版／challenge／有効期限を再照合し、nonce原子消費＋注文CASを自身で成立させる必要があります。Gemはこれを実行しません。EvidenceをJSON化して再入力し、真正性を回復するAPIもありません。旧 `verify(presentation_json:)` はJSON構文境界だけで、成功Evidenceを返しません。

連携前に[Issuer登録前チェックリスト](docs/ISSUER_ONBOARDING_CHECKLIST.md)と[Issuer/Host最小契約](docs/ISSUER_HOST_MINIMUM_CONTRACT.md)を参照してください。実Issuerの信頼と特定Hostの本番運用GOは、このGemの版番号や検証成功では成立しません。契約と`research/`のHost/DBコードは合成研究の設計・限定観測であり、本番adapterとして提供するものではありません。

`inputs`はtrust_json/selection_json/host_json/root_presentation/terminal_jws/
host_checkout_jws/verified_atです。前3つのJSONは認証済みの独立Host入力として渡し、
提示tokenの自己申告から信頼を追加しません。raw nonceは入力専用、EvidenceにはSHA256だけを
投影します。Hash/JSONへ書き出したものを真正なEvidenceとして再入力するAPIはありません。

旧`verify`はJSON構文境界だけで、その他の低レベルverify入口と共にsuccess?=false/
evidence=nilを維持します。呼出し例のsuccess?を旧APIへ流用してはいけません。

## 非保証と安全な停止

一般AP2/全Schema、任意の実Issuer互換性、発行/提示/Receipt生成、Rails adapter、実決済、実Host/DB/失効運用、最悪CPU/RSS/並行性能・数値SLAは対象外です。無欠陥や全パス安全性を証明したとは主張しません。既知重大問題やGem自身の検査欠落をこの非保証表示で補いません。

Hostはtokenから独立した認証済みtrust/鍵/profile・最新失効/時計/注文/challengeを供給し、Evidence使用直前に再照合し、nonce原子消費＋注文CAS・PENDING回復・最終ALLOWを担当します。Gemの既存検査をHostへ移す意味ではありません。Evidenceは同一の信頼Rubyプロセス内の検査事実で、JSON/Hashから真正性を再構成しません。不明・拒否・不能・例外・結果なしは許可せず、Hostが外側の時間/メモリ/同時実行制限を設けます。

## 証拠と履歴

公開済み0.2.0は**33,280 bytes**、SHA256 `9a52e802de5a0564c34d198f4c4ad2c2b60791a8f1eb6e31db14c49e28e91f16`、公開元commit `9b2e28d91fc4886722de7b9c39a5422e966953a9`です。2026-10-30に公式RubyGems metadata・実配布bytes・保存Gemの一致を確認しました。最終候補のDebian 12/arm64／MRI 4.0.9限定包装観測では、全13 payloadのsource/archive/installed一致・通常requireによる10製品Rubyファイル読込み・保存入力と期待値を使う118ケースが合格しました。対応環境の保証拡張ではなく、包装時にsource190／885は再実行していません。[現在の公開記録](docs/PROJECT_STATUS.md#020公開済み--現在の配布状態)を参照してください。

公開Gem内のREADMEと契約は公開前のsnapshotです。今回のリポジトリ文書更新は公開済みGemを変更せず、再buildは不要です。再buildした別成果物へ検証結果を引き継ぎません。GitHubのsource archiveはリポジトリのソースであり、RubyGemsの配布Gemとは異なります。

公開済み0.1.0のarchiveは**34,304 bytes**、SHA256 `37b2a235b6fab2d9d9765ae985dd9db27afd3b2c5407fe263a6b65314550db32`。2026-10-26に公式metadata・所有者`cuichangquan`・実配布bytes・全13 payloadのhashを照合しました。[公開確認記録](research/stable010_release_linux_package/README.md#rubygems-publication-verified)を参照してください。このリポジトリREADMEは公開後に再整理したもので、公開Gem同梱READMEとは異なります。公開archiveは再作成していません。

公開済み0.1.0のarchiveのSHA・環境別結果・制限は[版別検証記録](research/stable010_release_linux_package/README.md)を参照してください。archiveのSHAを同梱文書へ自己埋込せず、外部manifestで識別します。SHAは配布bytesを識別するもので、Host trustや全面安全性を保証しません。

[旧0.1.0候補R1](research/stable010_candidate/README.md)、[公開pre3](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.1.0.pre.3)、[pre2 Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.1.0.pre.2)は別archiveです。旧NOT_RUN/停止/成功は各時点の記録として保持し、新archiveの実測へ読み替えません。885回帰（147は内数）と旧Ruby4.0.1独立比較の再利用は、新たな885実行やLinux独立Oracleを意味しません。

[過去READMEの研究資料一覧 / Historical research documentation](https://github.com/cuichangquan/ap2-mandate-verifier/blob/2546d112b4bd4eaaf0a55b502f1c40b1fd61be65/README.md#research-documentation)は履歴資料であり、現在の契約・公開状態より優先しません。将来のSDK構想は[PRODUCT_VISION](docs/PRODUCT_VISION.md)を参照してください。

## 図で見るAP2の概念

以下は既存の日本語概念図です。広いAP2の説明を含み、固定profileの正確な対応契約を表すものではありません。上記の固定profile契約を優先してください。発行主体の信頼と最新失効はHostが管理・供給し、Gemが外部の最新状態を独立証明するものではありません。任意の委任チェーン・発行・Payment Mandate・決済実行などの概念は、本版の対応機能ではありません。

### AP2規格の全体像

![AP2規格の全体像](docs/assets/ap2-overview.png)

### 委任とHostの責任境界

![委任とHostの責任境界](docs/assets/ap2-delegation-trust-flow.png)

### Mandateの内部構造

![Mandateの内部構造](docs/assets/mandate-anatomy.png)

### SD-JWTと委任の概念

![SD-JWTと委任の概念](docs/assets/sd-jwt-delegation-chain.png)

### 攻撃パターンとFail Closed・Hostの再利用防止

![攻撃パターンとFail Closed・Hostの再利用防止](docs/assets/attack-patterns-fail-closed.png)

## License

MIT. See [LICENSE](LICENSE).
