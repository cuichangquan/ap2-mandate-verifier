# Security policy / 脆弱性の報告

## 対象と限界 / Scope

`ap2_mandate_verifier 0.1.0.pre.3` is a fixed-profile research prerelease,
not a production or stable product. General AP2 compatibility and full Phase2-A
PASS are not established. Issuance, presentation generation and a Rails SDK are
incomplete. Evidence is not Host ALLOW or payment permission. Publication does
not establish a security guarantee or a maintained-version/backport commitment.
固定profileの研究用途限定・本番利用不可です。公開は安全性保証や保守版／バックポートの約束ではありません。

## 非公開報告 / Private reporting

Use [GitHub Security Advisories](https://github.com/cuichangquan/ap2-mandate-verifier/security/advisories)
and choose **Report a vulnerability**. Private vulnerability reporting is enabled
for this repository. GitHub requires sign-in; repository administrators instead
see the draft-advisory workflow. See
[GitHub's reporting instructions](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately).
Do not submit vulnerability details through public Issues or PRs.
[GitHub Security Advisories](https://github.com/cuichangquan/ap2-mandate-verifier/security/advisories)
の **Report a vulnerability** から非公開で報告してください。GitHubへのログインが必要です。
管理権限のある利用者にはdraft advisoryの入口が表示されます。
脆弱性の詳細を公開Issue／PRへ書かないでください。

Include the affected Gem version/source SHA, Ruby/OS/dependency versions,
sanitized synthetic steps to reproduce, expected/actual behavior and impact.
Do not send credentials, private keys, real Mandates/tokens/nonces or personal
data. Describe the issue with minimal synthetic examples instead.
対象版／source SHA、環境、合成値による最小再現、期待／実結果と影響を記載してください。
秘密鍵・認証情報・実Mandate／token／nonce・個人情報は送らないでください。

The initial maintainer contact is Owner `cuichangquan` through the private GitHub
report. No acknowledgement, fix or disclosure deadline is guaranteed. If the
reporting entry is unavailable, a public Issue may ask only for a private contact;
include no vulnerability details or sensitive data. Do not assume that silence
means safety or acceptance.
窓口はGitHub経由のOwner `cuichangquan` です。受付・修正・公開の期限は保証しません。
非公開報告が利用できない場合、公開Issueでは窓口確認だけを行い、詳細や機微情報は掲載しません。
応答がないことを安全性や受理の証拠にしないでください。

Ordinary non-security bugs belong in
[Issues](https://github.com/cuichangquan/ap2-mandate-verifier/issues).
Dependency review and validation boundaries are in
[post-release maintenance](docs/POST_RELEASE_MAINTENANCE.md).
This policy does not authorize tests against real users, payments, external
services or production systems.


## Unpublished 0.1.0 candidate / 未公開候補の採用済み保守条件

The pre3 description above remains its historical scope. Candidate0.1.0 is validated but **not published**, and no specific Host production GO is granted. Its fixed-profile verification contract, exact environment evidence and exclusions are in [candidate evidence](research/stable010_candidate/README.md) and [SUPPORT_CONTRACT](docs/SUPPORT_CONTRACT.md). Publication requires separate S7 approval; no general AP2/real-Issuer/global-runtime safety guarantee follows.

Owner `cuichangquan` remains the initial contact through the routes above. For the initial stable series once separately released, support covers its latest patch only; no prerelease/older-series backport, fixed support term, response/fix/disclosure deadline or 24/7 service is promised. Manual Ruby/Gem/native/provider review is adopted monthly, on relevant advisory discovery and before a release. This is not an active automatic monitor or an unlimited approval to run tools. Security updates, deprecation and end of support identify affected versions, reasons and migration in release documentation; no fixed notice period is promised. Known major unaddressed issues or inability to maintain mean HOLD. New code, execution and publication retain their own approval boundaries.

pre3の歴史的範囲は保持します。0.1.0は限定検証済み・未公開候補です。初回安定系列の最新修正版のみを保守対象とする条件を採用済みですが、公開GOとは別です。担当/窓口は上記、月次・関連勧告判明時・次版前に手動確認し、自動監視/SLA/一定年数/旧版backportを約束しません。重大未対処問題・保守不能はHOLD。更新/廃止は対象版・理由・移行を明示します。

