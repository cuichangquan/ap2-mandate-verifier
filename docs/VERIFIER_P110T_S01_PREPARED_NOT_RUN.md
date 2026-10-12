# P1-10t — S01 正署名・公式Schema型不一致のDockerローカル実測：ACCEPT / RED-HOLD

**2026-10-12 JST / FIXED SYNTHETIC ISSUER / LOCAL DOCKER OBSERVED / SECURITY RED-HOLD / CI NOT RUN**

**対象：** [P1-10sで見つけたS01](VERIFIER_P110S_CONSTRAINT_SHAPE_TYPE_GAPS.md)。固定AP2 v0.2.0公式SHA `b4587ac1d055888a73b4b21750973cffba961793`、[公式Open Schema](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_checkout_mandate.json)。Open Checkoutの`checkout.line_items.items[0].id`（Constraint requirement `id`）を**文字列`"req-1"`から数値`123`**にした**合成Issuer署名済みMandate 1件**。公式JSON Schemaでは文字列型必須。この型の未検査は[既存Ruby研究Verifier](../research/p1_3/checkout_binding_research.rb)に限定される。

## 1. ユーザー提供Docker実測（GitHub Actionsではない）

ユーザーがMac（Apple Silicon）から実行したDocker `ruby:3.4-bookworm` コンテナの**実際のターミナルログを受領**した。ChatGPT自身がDocker内部を操作・再実行したログではない。PR #41ブランチ `82e278815537d41252a4e8ac25ee1cb50d0f3ba2` の検証プログラム、公式AP2 `b4587ac1d055888a73b4b21750973cffba961793` に固定して実行した。環境：Ruby **3.4.11**（aarch64-linux）、jwt **3.3.0**、Python **3.11.2**、jsonschema **4.25.1**、jwcrypto **1.5.6**。コードは研究用であり、Gem/API・本番システムではない。

| 判定レイヤー | ローカル実測 | 証拠の意味 |
| --- | --- | --- |
| Issuer署名・SD-JWT Disclosure digest・Agent PoP/チェーン・Merchant Checkout JWS | **VALID** | Python検証生成器が`S01 SIGNATURE VALID: issuer disclosure/commitment, agent PoP and merchant JWS`と出力 |
| 固定公式AP2 Open Checkout JSON Schema Draft 2020-12 | **INVALID** | `S01 SCHEMA INVALID: pinned anyOf/contains errors; nested id type:string violation (integer 123)`と出力。トップレベル`anyOf`/`contains`内のネストした`type:string`違反を検出 |
| Ruby側Issuer Root検証 | **true** | Rubyレポートの`ruby_signed_root_verified: true` |
| 既存の未修正`AP2CheckoutBindingResearch.verify!` | **ACCEPT** | `S01 OBSERVED: ACCEPT — RED/HOLD (signed input, official JSON Schema INVALID)` |
| 専用Ruby Minitest 1件 | **1 run / 7 assertions / failures 0 / errors 0 / skips 0** | **危険なACCEPTの観測に成功**という意味。セキュリティPASSではない |
| Ruby `observed.security` | **RED_HOLD** | ローカル研究コードは型違反の署名済みConstraintを受理 |
| GitHub Actions | **新規0件 / NOT RUN** | CI未実施。ローカル観測と混同しない |

**検証結論：この限定研究用Verifierに対し、正しく署名・開示されたものの公式Schemaに違反する`Requirement.id: 123`を受理する具体的な再現例が成立。P1-10t SECURITY RED/HOLD。** 有効署名はSchema適合を保証しない。合成入力の実測であって、実際の決済悪用・一般的AP2プロファイル・外部Issuerが同じ条件で受理されるとの実証ではない。

## 2. 実行ログの必要部分（秘密鍵・JWT・fixtureは転載しない）

公式コードの取得は次を`git rev-parse HEAD`で確認：
- PR #41 head（ローカル実行時点）：`82e278815537d41252a4e8ac25ee1cb50d0f3ba2`
- 公式 AP2：`b4587ac1d055888a73b4b21750973cffba961793`

ユーザー実行コマンド：

```bash
export AP2_P110T_UPSTREAM_ROOT=/work/AP2
python /work/verifier/research/p1_10t/generate_s01.py /work/s01.json

export AP2_P110T_FIXTURE=/work/s01.json
export AP2_P110T_REPORT=/work/s01-report.json
ruby /work/verifier/research/p1_10t/observe_s01.rb --verbose
```

生成スクリプト実際の出力（抜粋）：

```text
S01 SIGNATURE VALID: issuer disclosure/commitment, agent PoP and merchant JWS
S01 SCHEMA INVALID: pinned anyOf/contains errors; nested id type:string violation (integer 123)
S01: synthetic ephemeral signing keys never written/uploaded
```

Ruby実際の出力（抜粋）：

```text
S01 OBSERVED: ACCEPT — RED/HOLD (signed input, official JSON Schema INVALID)
Finished in 0.006583s, 151.9045 runs/s, 1063.3316 assertions/s.
1 runs, 7 assertions, 0 failures, 0 errors, 0 skips
Ruby署名検証: True
Ruby判定: ACCEPT
Security: RED_HOLD
```

この`1 runs ... 0 failures`は意図した**観測テストの成功**であって**拒否テスト合格ではない**。ユーザーが実行した生のログに対する記録であり、署名済みfixture JSONや秘密鍵はPRに含めていない。生成器はRAMで一時署名鍵を生成し、JSONには合成署名済みトークンと公開JWKのみを出力する。

## 3. 観測前の1件の検証器スクリプト不具合と修正

ローカル初回の`generate_s01.py`は**`jwcrypto.JWK.from_json(public_jwk)`にPython dictを渡し、`InvalidJWKValue`で停止**。Issuerの改変RootおよびSchema検証は通過していたが、その時点ではMerchant署名・2hopチェーンの完成を主張できなかった。

P1-10t観測**生成器だけ**を次のように1行修正して再実行：
`JWK.from_json(json.dumps(public_jwk))`（PR head `82e2788`）。再実行後に上記の**署名VALID＋Schema INVALID＋Ruby ACCEPT**まで確認。**既存Ruby Verifier実装への修正は0件**。また`anyOf`/`contains`の合成Schemaエラーを1件と取り違えないための観測生成器修正も含む。

### 3a. 最新ヘッドのDocker再実測とCodexのpre-import境界（2026-10-12 JST）

CodexレビューP2に対応した`5aea5c203151b2fdc5f7ee23dd093e180b181017`では、生成器の`ap2.*` import **より前**に次を検証するよう修正した：`python -O`禁止、公式AP2 Checkout HEAD `b4587ac1d055888a73b4b21750973cffba961793`、Open/Merchant Schemaの実Git blob、SDK tracked差分、untracked `.py` の有無。検証済みSDKツリーを`sys.path`に優先追加し、import済`ap2`の先行混入は拒否、import後に`mandate.py`実パスも検証する。**これらのpre-import guardの個別異常系を全件実行したとの主張ではない。**

**更新版もDockerで正常に動作した。** ユーザーがMac上の既存Dockerコンテナ`/work/verifier`内で、PR #41ブランチを`git fetch`/`switch`/`pull --ff-only`し、`git rev-parse HEAD`で正確に **`eb83e26cb569e5717205e5314f532ce655d43b06`** を確認した（後続ドキュメントコミットより前）。同じ`AP2_P110T_UPSTREAM_ROOT=/work/AP2`で下記を実行した：

```bash
python research/p1_10t/generate_s01.py /work/s01.json
export AP2_P110T_FIXTURE=/work/s01.json
export AP2_P110T_REPORT=/work/s01-report.json
ruby research/p1_10t/observe_s01.rb --verbose
```

確認できた出力（抜粋、実行者提供・秘密鍵/JWT/fixtureは非転載）：

```text
S01 SIGNATURE VALID: issuer disclosure/commitment, agent PoP and merchant JWS
S01 SCHEMA INVALID: pinned anyOf/contains errors; nested id type:string violation (integer 123)
S01: synthetic ephemeral signing keys never written/uploaded
S01 OBSERVED: ACCEPT — RED/HOLD (signed input, official JSON Schema INVALID)
1 runs, 7 assertions, 0 failures, 0 errors, 0 skips
```

**結論：** `eb83e26`でpre-import修正後の正規条件の合成S01生成・Ruby観測を再現（Schema INVALID、Ruby ACCEPT / **SECURITY RED-HOLD**）。旧`82e2788`での危険受理と整合し、**Ruby Verifier側の型検証欠落はまだ解消していない**。この結果は**ユーザー実行のDockerローカル証拠**であり、ChatGPT自身の実行やGitHub Actions CIの成功ではない。GitHub Actionsは **0件 / NOT RUN**。Codex再レビュー結果・未解決スレッドを別途検査し、実装対策は次のP1-10uに限定する。外部Issuer/Host/本番Gemは依然HOLD。

### 3b. Codex追加P2：ignored SDK Pythonソースの検証漏れと最新版Docker再実測（2026-10-12 JST）

`eb83e26`へのCodex再レビューで、`git ls-files --others --exclude-standard` が`.gitignore`・`.git/info/exclude`・global excludesの対象を列挙せず、ignored SDK Pythonソースがpre-import検証を通過し得ることが指摘された。コミット`6bca6a43ecc2336ff5ecf06a98158b1e1ef35a93`は`--exclude-standard`を削除し、ignoredを含むSDKツリーの無追跡`.py`をSDK import前に拒否するよう修正した。隔離した一時Gitリポジトリでも、無視対象`code/sdk/python/hidden.py`が`git ls-files --others -- code/sdk/python`に列挙され、`--exclude-standard`指定時には列挙されないことを実測確認した（Git列挙挙動の確認であり、異常なAP2 SDKの実行ではない）。

**最新Docker実測：** ユーザーが`/work/verifier`で`git pull --ff-only`し、実際のHEADを **`db732295a26fbf213f65af74d385715fb6abb698`** と確認。すなわち、Codex P2のpre-importおよびignoredソース列挙対策を含むコミットである。続けて前節と同じ`AP2_P110T_UPSTREAM_ROOT=/work/AP2`、`generate_s01.py`、`observe_s01.rb --verbose`を実行し、次の結果を提供した：

```text
S01 SIGNATURE VALID: issuer disclosure/commitment, agent PoP and merchant JWS
S01 SCHEMA INVALID: pinned anyOf/contains errors; nested id type:string violation (integer 123)
S01: synthetic ephemeral signing keys never written/uploaded
S01 OBSERVED: ACCEPT — RED/HOLD (signed input, official JSON Schema INVALID)
1 runs, 7 assertions, 0 failures, 0 errors, 0 skips
```

**判定：`db732295`最新版の合成・正常なSDK環境でも署名VALID / 公式Schema INVALID / Ruby研究Verifier ACCEPT、よって依然 SECURITY RED/HOLD。** これはローカル実測された危険受理の再現であり、修正された型検査の成功ではない。異常なignored SDKを配置したnegative実行テストや総合的ソース完全性、GitHub Actions CIの成功は主張しない。**GitHub Actionsは本PRで0件 / NOT RUN**。Gem/API/本番/HC06は引き続きHOLD、決済・公開はNO-GO。

### 3c. Codex 追加P2：Git fsmonitor実行とuntracked import artifacts（最新版未実行）

PR #41の`db732295`に対するCodex再レビューで**さらに2件のP2**が追加された。

1. `git ls-files`等は、checkoutの`.git/config`に設定された`core.fsmonitor`外部フックを起動する可能性がある。検証前のGit呼び出しを `-c core.fsmonitor=false -c core.hooksPath=/dev/null -c diff.external=` に固定し、`git diff --no-ext-diff --no-textconv` とした。
2. すべてのuntracked`.py`を拒否するだけでは`.pyc`・拡張module・未追跡のディレクトリSymlink等が残る。SDKツリー内の**あらゆるuntracked/ignored成果物を拒否**し、通常の編集可能インストール由来のroot-level `*.egg-info` にある限定した非実行メタデータファイルのみ許容する。

修正コードのcommit：**`f65ad6d40ce8a381daa35064e32ecac1473b6dd4`**。隔離した一時Gitリポジトリで`git ls-files --others -- code/sdk/python`がignored`.py`、ignored`.pyc`、未追跡Symlink、`*.egg-info/PKG-INFO`をいずれも列挙することを確認した。ただしこれは**Git列挙動作のみ**であり、AP2 SDKおよびDocker本試験の更新版PASSではない。

**この追加修正についてDocker実行はNOT RUN。** 直近のユーザー提供Docker実測は前節の`db732295`：署名VALID / 公式Schema INVALID / Ruby研究Verifier **ACCEPT / SECURITY RED-HOLD**。CI 0件、外部Issuer/HC06/一般Gem/本番HOLD、公開/決済NO-GOは変わらない。最新コードで再実行してレビューを確認するまでPRマージ保留。

### 3d. 最新Dockerブロック：SDK未追跡ファイルとstale fixtureの疑い（2026-10-12 JST）

ユーザーがPR #41 head **`806d2517bb3b62c60da4ded887a65cc93d1793a1`**を`git pull --ff-only`でチェックアウトし、`AP2_P110T_UPSTREAM_ROOT=/work/AP2`で`generate_s01.py`を再実行したところ、pre-importで次の**安全側の拒否**が発生した：

```text
RuntimeError: AP2 Python SDK contains untracked or ignored importable/unknown artifacts (including bytecode, extensions or symlinks); use a clean pinned SDK tree
```

この時点で**新しいsigned fixtureは生成されず**、Issuer/Agent/Merchant署名VALIDと公式Schema INVALIDはこのコミット上では観測されていない。原因となった実際のuntrackedファイル名はまだ未調査で、`__pycache__`等と断定しない。

ユーザーは生成器が失敗した後、前回の`AP2_P110T_FIXTURE=/work/s01.json`のままRuby観測を続行した。出力は`S01 OBSERVED: REJECT — limited fixture, not general conformance`、**1 run / 5 assertions / 0 failures, 0 errors, 0 skips**。ただし新たなfixture生成が失敗したため、これは**以前のfixtureを読み込んだ可能性があり、最新版S01の正しい型検査拒否やセキュリティ改善の証拠には使えない**。トークン失効など理由は未確認。Ruby研究Verifier本体に型検査の変更はない。

**判定：新HEAD `806d251`はpre-import制御のため試験未完了 / HOLD。** 最後の一貫した「同じ実行の新規生成＋Ruby観測」は`db732295`での署名VALID、Schema INVALID、Ruby ACCEPT / **RED-HOLD**。GitHub Actions CIは0件/NOT RUN、PRはDraft維持。次のステップは`git ls-files --others -- code/sdk/python`（必要なhook無効化と共に）を**読み取り専用**で実行し、原因ファイル名を確認すること。**やみくもに削除・allowlist緩和・古いfixture再利用・実決済へ移行しない**。

## 4. 次の判断と境界

**P1-10t観測はローカル実測でRED/HOLD。** 原因に対するVerifierの修正・正常署名回帰・別署名負例は**本PRの承認範囲外**。GP01とは別の**S01型検証の反例**として記録し、S02その他の未検証リスクにGOは出さない。

- [P1-10q修正前GP01 RED](VERIFIER_P110Q_GP01_EVIDENCE.md)は歴史的事実として維持。[P1-10rのGP01限定対策と正常signed正例](VERIFIER_P110R_GP01_FIX_EVIDENCE.md)：**2 runs / 10 assertions、0 failures**（別CI）。
- P1-10o：**8 runs / 45 assertions**（別CI、AN-N07は**HOST_BOUNDARY**でありリプレイ防止PASSでない）。
- Host正本 **9/34実測・25 NOT RUN**、外部Authority→Host契約C01〜C12 OPEN/UNCONFIRMED、強い失効HC06 **HOLD**。
- 汎用Gem/Public API/本番利用 **HOLD**、RubyGems公開・実決済・署名Receipt **NO-GO**。
- GitHub Actionsの新規workflow追加は前にプラットフォーム安全性チェックでブロックされており**迂回せず**。**CIは未実行**。PRをどの条件でReady/mergeするかはレビューと証拠の追加判断で決める。
- **次のおすすめ1件（別途ユーザー承認後のみ）：P1-10u**、固定Issuer研究用Verifierで`line_item_requirements.id`の型をFail Closedにする小さな修正を設計し、同じ正署名S01の**REJECT**と別の正署名正常Checkoutの非退行を検証する。S02/汎用Issuer/Gem/本番まで自動拡張しない。

## 5. 新チャット引き継ぎ・次の作業（2026-10-12）

**この文書と[RESEARCH_PLAN](RESEARCH_PLAN.md)を現時点の引き継ぎ正本とする。** 旧[HANDOFF](HANDOFF.md)にはまだ「次はP1-10s」の古い記述が残る（以前、同ファイルの編集が安全性チェックでブロックされたため）。古い指示は再実行しない。PRのマージ後は、**GitHubの最新main / Open PR / Open Issue / 未解決レビュー・CIを最初に実確認**すること。この節の旧SHAを最新と決めつけない。

**現在地：**
- 最終固定AP2公式 v0.2.0 commit `b4587ac1d055888a73b4b21750973cffba961793`。
- P1-10t 1件の正署名S01（Requirement `id: 123`）は公式Schema **INVALID**だが、未修正Ruby研究Verifierで **ACCEPT / SECURITY RED-HOLD**。ユーザーのMac Docker（Ruby 3.4.11/jwt 3.3.0、Python 3.11.2/jsonschema 4.25.1、公式AP2 SDK）は**1 run/7 assertions/0 failures**。テスト緑は「危険なACCEPT観測を正確に記録」、安全性PASSではない。**GitHub Actions CIではない**。
- P1-10q歴史的GP01（未知ネストキーの正署名ACCEPT/RED）、P1-10r修正後GP01限定REJECT＋正常signed 2/10、P1-10o別CI 8/45（AN-N07は**HOST_BOUNDARY**）を別実行として維持。
- Host canonical **9/34測定・25 NOT RUN**。Authority→Host C01–C12 OPEN/UNCONFIRMED、外部HC06、汎用Issuer/SD-JWTの隠れConstraint完全性、Host replay/最終business ALLOW、公開Gem/API、本番統合は**HOLD**。RubyGems/実決済/署名Receiptは**NO-GO**。
- P1-10sのS02（署名済Merchant `allowed[0].name`型）や他のS03–S08は未検証。P1-10uに自動追加しない。
- 秘密鍵や署名済みfixture JSONをコミットしない。GCP、実Issuer/実Host/Authority、production Checkout/receiptには進まない。

**次のおすすめ1件（別途ユーザー承認が必要）：P1-10u** — 固定合成Issuer研究用 `research/p1_3/checkout_binding_research.rb` に限り、`line_item_requirements.id`が**String**であることを確認し、不正な型ならFail Closedで拒否する。**同じ正署名S01を意図した理由でREJECT**し、別の正常な正署名Checkoutが引き続き**証拠のみACCEPT（Host ALLOWではない）**する2系統の回帰を、許可されたDocker/CIで観測する。S02や汎用Schema完全適合への拡張なし。PRは小さく、レビュー指摘とテスト結果を検査してから**マージできるものだけSquashマージ**、Open PR/Issueとmainを再確認。予期しないACCEPTやテスト未実行はそのままRED/HOLDとして報告し、緑と誤認しない。

### 新しいチャットに貼り付ける指示文

```text
ap2-mandate-verifierの開発をP1-10tのDocker実測から引き継いで続けたい。
https://github.com/cuichangquan/ap2-mandate-verifier

まずGitHub最新main、Open PR/Issue、CI、Codex/未解決レビューを確認。
マージ可能なPRは、安全性・実測・レビュー結果を確認後にSquashマージ。
作業単位を小さくし、mainとPR状況を毎回更新して進めてほしい。

最重要資料：
docs/VERIFIER_P110T_S01_PREPARED_NOT_RUN.md
（ファイル名は過去のままだが、中身はP1-10tのDocker実測RED記録）
docs/VERIFIER_P110S_CONSTRAINT_SHAPE_TYPE_GAPS.md
docs/RESEARCH_PLAN.md
docs/VERIFIER_P110R_GP01_FIX_EVIDENCE.md
docs/VERIFIER_P110Q_GP01_EVIDENCE.md
docs/RESEARCH_DECISION.md §36

公式AP2 v0.2.0 SHA：
b4587ac1d055888a73b4b21750973cffba961793

P1-10t：合成Issuer/Agent/Merchant署名・Disclosure VALID、
公式Open Checkout Schema INVALID（line_items.items[0].id=123、
String必須）、未修正Ruby研究VerifierがACCEPT / RED-HOLD。
Mac Dockerで1 run/7 assertions/0 failures＝危険受理の観測成功。
GitHub Actions CIではない。JWK公開鍵dictエラーを生成器のみ修正。
Verifier本体の修正はまだ行っていない。

次の候補はP1-10u：S01 Requirement.idの型だけ固定Issuer研究
VerifierでFail Closedにし、同じ正署名S01 REJECT＋別の正署名
正常Checkout（evidence only）を回帰確認する限定対策。
S02等の他Gapへ勝手に拡張しない。必要な次Step承認を尊重する。

歴史的GP01 pre-fix ACCEPT/REDとP1-10r post-fix GP01 REJECT
（2/10）、P1-10o 8/45（N07 HOST_BOUNDARY）は混同しない。
Host正本9/34測定・25 NOT RUN、HC06/C01–C12と一般Gem/API/
本番統合HOLD。公開Gem/RubyGems/実決済/ReceiptはNO-GO。
新PRでもテストとレビューを確認し、マージ可能なもののみマージ。
旧docs/HANDOFF.mdの次P1-10s記述は古いので従わない。
```
