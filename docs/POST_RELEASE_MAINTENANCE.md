# 公開後の整備 / Post-release maintenance

研究用途限定・本番利用不可 / RESEARCH ONLY — NOT FOR PRODUCTION.
固定profile `ap2.checkout.single_merchant_sku` version1のみを対象とします。
一般AP2互換性・Phase2-A全面PASS・E10全面GOは未成立、発行・提示生成・Rails SDKは未完成です。
EvidenceはHost ALLOW・nonce消費・決済許可ではありません。
Only the fixed profile above is supported. General AP2 compatibility, full
Phase2-A PASS and full E10 GO are not established. Issuance, presentation
generation and a Rails SDK remain incomplete. Evidence is not Host ALLOW,
nonce consumption or payment permission.

## 公開物と証拠 / Artifacts and evidence

| 配布先 / Distribution | 版 / Version | bytes | SHA256 |
| --- | --- | ---: | --- |
| [RubyGems](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.1.0.pre.3) | 0.1.0.pre.3 | 37,888 | `8ad627818dc69b450d0fba970dafaf368ec42dd64fb51eec631731027de3882c` |
| [GitHub Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v0.1.0.pre.2) | 0.1.0.pre.2 | 33,280 | `e910659bbebda7aa5f00d63fb579f3b56819d59b5ee7d8b1734a6331f01d8de4` |

pre3は2026-10-23に所有者 `cuichangquan` が公開し、Ownerが公式API・実配布物・MBA原本の一致を確認しました。
今回のMac mini監査ではRubyGems閲覧取得不能／APIへのDNS解決失敗のため独立再確認できていません。
これは昨日の公開検証記録を否定するものでも、今回の再検証成功を示すものでもありません。
The Owner's 2026-10-23 publication check matched the official API, distributed
pre3 archive and MBA original under owner `cuichangquan`. The subsequent Mac mini
audit could not independently refetch RubyGems (page/API retrieval unavailable,
local API DNS resolution failed); it does not constitute another successful
publication validation.

[PR177](https://github.com/cuichangquan/ap2-mandate-verifier/pull/177) records
`MBA409-PRE3PACKAGE02-20261023`: MBA Darwin arm64, MRI4.0.9,13 payload identities,
10 loaded libraries and52 installed checks (42 saved independent expectations,
7 legacy APIs,2 input rejections,1 constructor rejection). It did not rerun885
source regressions. **pre3 Linux: NOT_RUN.** The successful pre2 Linux
[run39939021098 attempt1](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/39939021098)
is historical pre2 evidence, not a pre3 package or independent Linux Oracle run.
Unknown safety, runtime/native attestation and worst-case CPU/RSS/concurrency
remain unproved; historical communication-accounting gaps remain unresolved.

## 文書と再公開の境界 / Documentation and publication

READMEとSUPPORT_CONTRACTはGem同梱対象です。公開Gem内の文書は包装時点のスナップショットとして保持し、
「RubyGems未公開」等の古い記載はmainの文書で追補します。現在のmainは同梱文書と異なります。
同じ版を再ビルドしても公開Gemと同一ではなく、公開SHA・包装検証を引き継ぎません。
公開Gem・タグ・Releaseは上書きせず、文書訂正だけの再リリースは行いません。
Gemの次版が必要になったときに、同梱文書・候補metadataを別途見直します。
README and SUPPORT_CONTRACT are packaged files. Published copies remain immutable
packaging snapshots; main supplements their stale unpublished wording. Current
main differs from packaged documentation. A same-version rebuild is not the
published artifact and inherits neither its SHA nor package-validation evidence.
Do not overwrite published Gems, tags or Releases. Documentation corrections alone
do not require a new Gem release. Review packaged documents and candidate metadata
when a separately approved next version is needed.

## 受付 / Reporting

- 通常の不具合・導入問題 / Ordinary bugs and installation issues:
  [GitHub Issues](https://github.com/cuichangquan/ap2-mandate-verifier/issues).
  Include Gem version, artifact SHA if known, Ruby/OS/dependency versions,
  sanitized minimal synthetic reproduction, expected/actual behavior and scope.
- 脆弱性 / Suspected vulnerabilities: follow [SECURITY.md](../SECURITY.md).
  Do not publish exploit details in Issues or PRs. Never include credentials,
  private keys, real Mandates/nonces or personal data in either reporting route.
- Owner `cuichangquan` is the initial maintainer contact through these GitHub
  routes. Triage distinguishes reproducible defects, unsupported profiles,
  environment failures and security concerns. No response/fix deadline or
  production support commitment is promised.

## 依存と回帰 / Dependencies and regression

担当はOwner／保守者です。推奨する見直し頻度は月1回、および関連advisory判明時・次版判断前です。
これは運用案であり、定期監視・自動実行・対応期限が稼働中だという宣言ではありません。
2026-10-24 JSTの設定確認ではPrivate vulnerability reportingを有効化しました。
Dependabot alerts／security updatesは無効、version更新用設定ファイルもありません。
今回、Dependabot・CI・認証の設定は変更していません。
The Owner/maintainers should review dependencies monthly, on relevant advisory
discovery and before considering a next release. This is a recommended manual
cadence, not an active scheduled monitor or SLA. Private vulnerability reporting
was enabled on2026-10-24 JST. Dependabot alerts/security updates remain disabled;
no version-update configuration is present. No Dependabot, CI or authentication
setting was changed by this maintenance.

Before proposing an update, assess official Ruby/JSON/JWT/base64/OpenSSL/Digest
advisories and the actual native providers, affected scope and reproducibility.
Keep exact dependency pins until a scoped change is approved; do not silently
accept a later provider or relabel historical manifests/results.

文書のみの変更はリンク・日英整合・版／SHA・証拠範囲・CI triggerを静的確認します。
依存／コード／包装を変更する場合は、承認された環境で既存885回帰、
13 payload／10 loaded／52 installedと必要な独立正常・因果負例／Schema比較を計画します。
新しい結果は版・source SHA・runtime/provider・入力／期待値・環境・runを区別して保存します。
Linuxの保存期待値再生を独立Oracle再実行とは呼びません。失敗・未知・不一致はSTOP/HOLDです。
For documentation-only changes, statically check links, bilingual consistency,
version/SHA identities, evidence scope and CI triggers. Dependency/code/package
changes need an approved validation plan for885 existing regressions,13 payload/
10 loaded/52 installed checks and relevant independent positive/causal-negative
or Schema comparisons. Preserve new evidence separately by version, source SHA,
runtime/provider, inputs/expectations, environment and run. Saved-expectation
replays are not independent Oracle reruns. Failure, uncertainty or mismatch means
STOP/HOLD. Builds, installs, dynamic tests, Actions, dependency changes and releases
need their own explicit scope/approval; this document grants none.
