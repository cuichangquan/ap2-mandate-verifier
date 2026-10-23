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
