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
source regressions. **pre3 Linux subsequently passed [run40038620413 attempt1](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/40038620413).** The earlier NOT_RUN status was historical and is superseded by that pre3 observation. The successful pre2 Linux
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


## 未公開0.1.0候補の現在地と採用済み保守条件（2026-10-26 UTC）

公開物の表はpre3/pre2のままです。**0.1.0は未公開候補**であり、[候補source・Mac/Ubuntu結果](../research/stable010_candidate/README.md)を別記録に保存します。候補43,008B / SHA256 `0553645fa6c067dd8d7a7a1a7cdf13799370393e76dc3bc4ba161ab2ca5981b0`、両環境13 payload/10 loaded/52 installedが確認済み。候補内の未実施記述は包装時点snapshotで、後続Ubuntu成功は外部追補を参照してください。再包装や公開済みGem/tag/Releaseの上書きはしません。

前節の月次/勧告時/次版前の手動見直しをOwnerが具体条件として採用しました。担当はOwner/保守者、通常不具合はIssues、脆弱性はSECURITYの非公開窓口です。初回安定系列の最新修正版のみを対象とし、pre/旧系列backport・一定年数・受付/修正期限・24時間対応は約束しません。更新/廃止/保守終了は対象版・理由・移行先と状態を告知し、固定猶予期間は設けません。自動監視は稼働中と扱わず、担当不在/保守不能/重大未対処問題はHOLDです。

上記の一般的な回帰計画は全件再実行の義務ではありません。今回の版/文書/包装期待値の差分では、製品10件・固定依存と既存証拠を照合して885を再利用し、新候補の包装/導入を両環境各1回確認しました。147は885の内数、旧runtime独立比較や保存期待値再生は新独立Oracleではありません。追加検証は具体的不足に応じ別承認とし、今回追加試験/取得/build/Actions/公開はなしです。

Provider/component確認と全面安全性は別です。D1/D2停止とD3限定成功、JSON公式修正ソース根拠とGHSA metadata不整合、OS dyld/全binding・通信全量・物理容量peak等の未証明を保持します。最後にexact archive・配布先・保証範囲・残余を示すS7公開GOが必要で、特定Host本番GOは別/HOLDです。

The public-artifact table still lists pre3/pre2 only. Candidate0.1.0 has separate Mac/Ubuntu evidence; its packaging snapshots are supplemented externally without rebuilding. Adopted maintenance covers the latest patch in the initial stable series, with manual monthly/advisory/pre-release review, existing reporting routes and explicit update/deprecation notices; no backport/fixed-term/SLA/24-hour promises or automatic monitoring. Diff-based historical evidence reuse is not a fresh885 run. Publication and specific Host production GO remain separate and unapproved.



## 0.1.0 release-facing documentation / 公開向け文書のR2

The0.1.0 consumer documentation now describes the fixed verification contract and installation only after official listing, without declaring publication. Earlier candidate/R1/pre3 descriptions above are historical. A newly built R2 archive has separate [source and validation evidence](../research/stable010_release_linux_package/README.md); R1's43,008B archive and observations are not reused as new-byte validation. Existing maintenance scope/reporting routes/exclusions remain unchanged. RubyGems publication and specific Host production GO still require separate authorization.

0.1.0の公開向け文書を整理しましたが、公開済みとは表示しません。旧candidate/R1/pre3は履歴として保持し、新R2は別archive・別証拠です。採用済み保守条件・窓口・保証除外は不変で、Gem公開GO・特定Host本番GOは別途必要です。


## R2 validation supplement / R2検証追補

The new34,304B R2 archive (SHA256 `37b2a235b6fab2d9d9765ae985dd9db27afd3b2c5407fe263a6b65314550db32`) passed Mac and [Ubuntu run40288305150 attempt1](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/40288305150) payload13/loaded10/installed52 checks with matching payload/dependency identities. See [exact results and limitations](../research/stable010_release_linux_package/README.md). This is distinct from R1/pre3, not a new885 or independent Oracle run. Source/packaged bytes remain frozen. No Gem, tag or Release publication occurred; S7 and specific Host production GO remain HOLD. Existing maintenance policy and reporting routes are unchanged.

新R2はMac/Ubuntuで限定包装検証済みですが未公開です。provider確認を全面安全性へ昇格せず、JSON勧告metadata不整合、OS dyld/全binding、総通信/physical peak等の未証明を保持します。原結果のhash/読戻し後に今回分だけを清掃し、旧停止履歴・証拠・archiveは保持。追加build/試験/Actions/取得はこの追補作業では行いません。
