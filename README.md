# AP2 Mandate Verifier — 0.1.0

RubyでAP2の固定profileを検証する、Rails非依存のGemです。**署名の正しさだけで購入を許可しません。** 必要な検査が成立した場合に不変のEvidenceを返し、最終業務判断はHostが行います。

A Rails-independent Ruby Gem for a deliberately fixed AP2 verification profile. **A valid signature alone never authorizes a purchase.** Successful checks produce immutable Evidence; the Host makes the final business decision.

## 配布と導入 / Distribution and installation

配布状況は[公式RubyGems版一覧](https://rubygems.org/gems/ap2_mandate_verifier/versions)が正本です。この文書や版情報の存在だけでは公開済みを意味しません。次のコマンドは**0.1.0が公式一覧に掲載された後**に使用します。公開前は未登録エラーになり得ます。旧研究版pre3は別の成果物です。

The [official RubyGems version list](https://rubygems.org/gems/ap2_mandate_verifier/versions) is authoritative for availability. This document and version metadata alone do not establish publication. Use these commands **once0.1.0 is listed**; before publication they may fail because the version is absent. Research prerelease pre3 is a separate artifact.

既存のMRI4.0.9環境と利用者が選ぶGem隔離環境で使用します。通常の導入は依存取得・JSON native buildを伴い得ます。依存衝突や未知providerを許容するために固定条件を緩めないでください。

Use an existing MRI4.0.9 environment and your chosen Gem isolation. Normal installation may fetch dependencies and build JSON native extensions. Stop on conflicts or unknown providers rather than relaxing pins.

```sh
ruby --version # MRI 4.0.9 required
gem install ap2_mandate_verifier --version 0.1.0
```

BundlerのGemfile / Bundler Gemfile:

```ruby
gem "ap2_mandate_verifier", "= 0.1.0"
```

固定runtime依存 / Fixed runtime dependencies:
JSON2.19.9, JWT3.3.0, base640.3.0, OpenSSL gem4.0.2, Digest3.2.1.
Bundler4.0.20は既存resolver基準でruntime依存ではありません / Bundler4.0.20 is the observed resolver baseline, not a runtime dependency.
RubyGemsの版制約だけではMRI engine、OSや実native/providerの出所を保証しません / Gem version constraints alone do not enforce the MRI engine, OS or native-provider provenance.

## 対応範囲 / Supported contract

- AP2固定source `b4587ac1d055888a73b4b21750973cffba961793`、登録profile `ap2.checkout.single_merchant_sku` v1の正確なbody/hash・7支持形状 / The exact registered profile v1 body/hash and seven supported shapes at the pinned AP2 source.
- ES256/P256、Open1→Closed1、固定3開示位置、単一Merchant/SKU/行、USD/EUR/JPY、empty links。未知/非対応形式は拒否 / ES256/P256, Open1→Closed1, three fixed disclosure positions, one Merchant/SKU/line, USD/EUR/JPY and empty links; unknown/unsupported forms are rejected.
- 厳格入力と有限上限、供給trust選択、Root原文署名と全域閉包、Agent/Merchant署名・委任・購入/Host binding、型/制約/期限をGemが検査 / The Gem checks strict bounded inputs, supplied trust selection, signed Root wire and full supported closure, Agent/Merchant signatures, delegation, purchase/Host binding, types, constraints and time.
- 入口は既存 `verify_research`。名前と `verified_research/scoped_research_verified`・Evidence v2契約を維持。安定版番号でも一般AP2対応やHost許可へ昇格しない / The existing entry, result names and Evidence v2 contract remain unchanged; a stable version does not imply generic AP2 support or Host authorization.

正確な必須形状・全上限・失敗codeは[SUPPORT_CONTRACT](docs/SUPPORT_CONTRACT.md)を参照してください。 / See [SUPPORT_CONTRACT](docs/SUPPORT_CONTRACT.md) for exact required shapes, bounds and failure codes.

## 環境・互換性・保守 / Environment, compatibility and maintenance

対象はMRI4.0.9と固定依存、観測されたMBA/macOS arm64 (`arm64-darwin25`) およびUbuntu24.04/x86_64の正確な構成です。[現行版の包装・provider証拠](research/stable010_release_linux_package/README.md)と[過去の環境記録](docs/VERIFIER_CORE_COMPLETION_CRITERIA.md#初回の対応環境保証範囲owner採用済み)を区別してください。OS全版・他engine/architecture・任意provider更新は保証しません。

The baseline is MRI4.0.9 with fixed dependencies and the exact observed MBA/macOS arm64 and Ubuntu24.04/x86_64 configurations. Distinguish [release-package/provider evidence](research/stable010_release_linux_package/README.md) from [historical environment records](docs/VERIFIER_CORE_COMPLETION_CRITERIA.md#初回の対応環境保証範囲owner採用済み). Other OS versions, engines, architectures and arbitrary provider updates are not covered.

支持入力の判定意味・APIを黙って変更しません。安全性修正で受理を狭める場合は理由・影響・移行を明示し、破壊的なAPI/必須field/profile変更を区別します。依存更新は自動互換ではありません。

Supported-input semantics and APIs do not change silently. Security-driven narrowing identifies reason, impact and migration; breaking API/required-field/profile changes are explicit. Dependency updates are not automatically compatible.

初回安定系列の最新修正版のみを保守対象とし、月次・関連勧告判明時・次版前に手動確認します。旧版backport・固定保守年数・受付/修正期限・24時間対応は約束しません。[SECURITY](SECURITY.md)と[保守方針](docs/POST_RELEASE_MAINTENANCE.md)を参照し、秘密鍵・実Mandate・個人情報を報告しないでください。

Maintenance covers the latest patch in the initial stable series, with manual monthly/advisory/pre-release review. No old-series backport, fixed support term, response/fix deadline or24/7 promise. See [SECURITY](SECURITY.md) and [maintenance](docs/POST_RELEASE_MAINTENANCE.md); never report private keys, real Mandates or personal data.

## 保存済み合成入力で試す / Try the saved synthetic example

以下は既存の合格済みinstalled検査と同じ公開 `FULL` 入力を読む例です。入力JSONはGemに含まれません。固定commitから取得し、SHA256を確認してから使います。fixtureに秘密鍵は含まれません。fixtureのtrust／Host入力は**テスト専用の合成値**であり、実Issuer登録・現在の注文・実時刻として再利用してはいけません。`verified_at = 1800000000` は保存シナリオの固定時刻です。

This example reads the same public `FULL` input used by the successful installed-Gem checks. The input JSON is not packaged in the Gem. Fetch it from the pinned commit and verify its SHA256 first. It contains no private keys. Its trust/Host assertions are **synthetic test data**, not real Issuer enrollment, a current order or a live clock. `verified_at = 1800000000` is the saved scenario's fixed evaluation time.

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

result = AP2MandateVerifier.verify_research(**inputs)
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

For this saved `FULL` case, the expected result is `status=:verified_research`, `code=:scoped_research_verified`, `success?=true`. This is not the expected outcome for arbitrary real inputs, unsupported forms or dependency failures. Non-success results have nil Evidence. Exceptions or process termination without a result must also stop the caller. Avoid logging complete Evidence or raw inputs.

## 実入力と責任境界 / Real inputs and responsibility boundaries

| Keyword | 入力契約 / Input contract |
| --- | --- |
| `trust_json` | 認証済みHostの固定snapshot/profileと公開鍵登録を表すJSON原文String / Original JSON String for authenticated Host trust snapshot, profile and public-key registration. |
| `selection_json` | 独立Hostが選択したtenant・profile版・Issuer/Agent/Merchantの識別／用途／鍵参照 / Independently selected tenant, profile version and role/identity/purpose/key references. |
| `host_json` | 認証済み現在注文binding、issued challenge、発行元・時計識別 / Authenticated current order binding, issued challenge, expected issuer and clock identity. |
| `root_presentation` | disclosure順と末尾`~`を維持した署名付きRoot提示原文String / Original signed Root presentation String, preserving disclosure order and trailing `~`. |
| `terminal_jws` | Agent terminal compact JWS原文String / Original Agent terminal compact JWS String. |
| `host_checkout_jws` | Hostが固定したMerchant Checkout compact JWT原文String / Original Merchant Checkout compact JWT String frozen by the Host. |
| `verified_at` | 外部の信頼時計から供給する整数Unix秒 / Integer Unix seconds supplied by an external trusted clock. |

正確な必須形状・型・上限は[SUPPORT_CONTRACT](docs/SUPPORT_CONTRACT.md#full-entry-and-required-inputs)を参照してください。tokenからtrustを自己登録したり、署名原文をparse／再encode／並べ替えして渡したりしません。Host-onlyなBuyer/account等の一致はIssuer署名による本人認証を意味しません。

See [SUPPORT_CONTRACT](docs/SUPPORT_CONTRACT.md#full-entry-and-required-inputs) for exact required shapes, types and limits. Do not register trust from the presented token or parse/re-encode/reorder signed wire input. Matching Host-only Buyer/account fields does not establish Issuer-signed identity authentication.

`verify_research`の成功は固定profileにおける検証事実です。Hostは最新trust／失効／注文版／challenge／有効期限を再照合し、nonce原子消費＋注文CASを自身で成立させる必要があります。Gemはこれを実行しません。EvidenceをJSON化して再入力し、真正性を回復するAPIもありません。旧 `verify(presentation_json:)` はJSON構文境界だけで、成功Evidenceを返しません。

A successful `verify_research` result establishes scoped verification facts. The Host still must recheck latest trust/revocation/order version/challenge/time and atomically consume the nonce with order CAS. The Gem does not perform those operations. Serializing Evidence to JSON does not preserve or reconstruct authenticity through this API. Legacy `verify(presentation_json:)` checks only the JSON syntax boundary and never returns successful Evidence.

連携前に[Issuer登録前チェックリスト](docs/ISSUER_ONBOARDING_CHECKLIST.md)と[Issuer/Host最小契約](docs/ISSUER_HOST_MINIMUM_CONTRACT.md)を参照してください。実Issuerの信頼と特定Hostの本番運用GOは、このGemの版番号や検証成功では成立しません。契約と`research/`のHost/DBコードは合成研究の設計・限定観測であり、本番adapterとして提供するものではありません。

Before integration, consult the [Issuer onboarding checklist](docs/ISSUER_ONBOARDING_CHECKLIST.md) and [Issuer/Host minimum contract](docs/ISSUER_HOST_MINIMUM_CONTRACT.md). Real-Issuer trust and a specific Host's production GO are not established by this Gem version or verification success. The contract and Host/DB code under `research/` describe synthetic research designs and limited observations, not a production adapter.

`inputs`はtrust_json/selection_json/host_json/root_presentation/terminal_jws/
host_checkout_jws/verified_atです。前3つのJSONは認証済みの独立Host入力として渡し、
提示tokenの自己申告から信頼を追加しません。raw nonceは入力専用、EvidenceにはSHA256だけを
投影します。Hash/JSONへ書き出したものを真正なEvidenceとして再入力するAPIはありません。

旧`verify`はJSON構文境界だけで、その他の低レベルverify入口と共にsuccess?=false/
evidence=nilを維持します。呼出し例のsuccess?を旧APIへ流用してはいけません。

## 非保証と安全な停止 / Exclusions and safe stopping

一般AP2/全Schema、任意の実Issuer互換性、発行/提示/Receipt生成、Rails adapter、実決済、実Host/DB/失効運用、最悪CPU/RSS/並行性能・数値SLAは対象外です。無欠陥や全パス安全性を証明したとは主張しません。既知重大問題やGem自身の検査欠落をこの非保証表示で補いません。

General AP2/full Schema, arbitrary real-Issuer interoperability, issuance/presentation/Receipt generation, Rails adapters, real payments/Host/DB/revocation operations, worst CPU/RSS/concurrency and numerical SLAs are outside scope. No defect-free/all-path safety proof is claimed; exclusions do not excuse known major defects or missing Gem checks.

Hostはtokenから独立した認証済みtrust/鍵/profile・最新失効/時計/注文/challengeを供給し、Evidence使用直前に再照合し、nonce原子消費＋注文CAS・PENDING回復・最終ALLOWを担当します。Gemの既存検査をHostへ移す意味ではありません。Evidenceは同一の信頼Rubyプロセス内の検査事実で、JSON/Hashから真正性を再構成しません。不明・拒否・不能・例外・結果なしは許可せず、Hostが外側の時間/メモリ/同時実行制限を設けます。

The Host supplies authenticated token-independent trust/keys/profile and current revocation/clock/order/challenge state, rechecks before use, atomically consumes nonce with order CAS, reconciles PENDING and decides ALLOW. Existing Gem checks remain Gem responsibilities. Evidence is in-process checked facts in trusted Ruby, not a transport credential. Unknown/rejected/unavailable/exception/missing results never authorize; the Host provides outer time/memory/concurrency limits.

## 証拠と履歴 / Evidence and history

現在の新archiveのSHA・環境別結果・制限は[版別検証記録](research/stable010_release_linux_package/README.md)を参照してください。archiveのSHAを同梱文書へ自己埋込せず、外部manifestで識別します。SHAは配布bytesを識別するもので、Host trustや全面安全性を保証しません。

See the [versioned validation record](research/stable010_release_linux_package/README.md) for this archive's external SHA, per-environment observations and limits. The archive hash is kept outside its payload to avoid self-reference. A hash identifies bytes, not Host trust or global safety.

[旧0.1.0候補R1](research/stable010_candidate/README.md)、[公開pre3](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.1.0.pre.3)、[pre2 Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.1.0.pre.2)は別archiveです。旧NOT_RUN/停止/成功は各時点の記録として保持し、新archiveの実測へ読み替えません。885回帰（147は内数）と旧Ruby4.0.1独立比較の再利用は、新たな885実行やLinux独立Oracleを意味しません。

[Earlier0.1.0 candidateR1](research/stable010_candidate/README.md), [publishedpre3](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.1.0.pre.3) and [pre2 Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.1.0.pre.2) are different archives. Historical NOT_RUN/stops/passes remain tied to their original bytes and time. Reusing885 regressions (including147) and Ruby4.0.1 independent comparisons is not a fresh885 run or Linux independent Oracle.

[過去READMEの研究資料一覧 / Historical research documentation](https://github.com/cuichangquan/ap2-mandate-verifier/blob/2546d112b4bd4eaaf0a55b502f1c40b1fd61be65/README.md#research-documentation)は履歴資料であり、現在の契約・公開状態より優先しません。将来のSDK構想は[PRODUCT_VISION](docs/PRODUCT_VISION.md)を参照してください。

## License

MIT. See [LICENSE](LICENSE).


