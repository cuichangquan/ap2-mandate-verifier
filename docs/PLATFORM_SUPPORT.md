# SDK platform validation / SDK環境別検証

## Contract / 契約

MRI **3.4.12 and 4.0.9**, the five pinned runtime dependencies, and all existing
security/Host responsibility boundaries remain unchanged. The framework-independent
Gem does not depend on Rails. The Rails demo has its own image, lockfile and checks;
a successful demo test is not a substitute for standalone Gem validation.
The optional reference SQLite stores are not a runtime dependency of the core SDK.
SQLite 2.10.2 native binaries must match the actual Ruby/OS/CPU combination.

MRI・依存pin・API・バージョン・Host責任境界は変更しません。SDK単体とRailsデモは
別の検証対象です。core SDKの読み込みにRails・SQLite driverは不要です。
SQLite永続化例は、実際のOS/CPUに合った任意driverを別途使います。

## Matrix and evidence / マトリクスと証拠

| Target | Method and scope | Observed status |
| --- | --- | --- |
| Linux ARM64, both MRI versions | Native `ubuntu-24.04-arm`; Debian bookworm containers; SDK source/candidate and published Gem | PASS: [native run](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/42314708194) |
| Linux AMD64, both MRI versions | Native `ubuntu-24.04`; same checks; x86_64 SQLite native Gem | PASS: [native run](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/42314708194) |
| macOS 15 Intel / Apple Silicon, both MRI versions | Native standard `macos-15-intel` / `macos-15`; published core first, optional SQLite separately | NOT_RUN: workflow prepared, no passing observation yet |
| Windows Server 2022 X64, both MRI versions | Native standard `windows-2022`; published core first, optional SQLite separately | NOT_RUN: workflow prepared, no passing observation yet |

Local native Linux ARM64 checks passed both MRI versions: full existing source and
candidate suites, published guides, all 68 published payload hashes and 28 loaded
SDK files. Five causal identity-negative probes passed. See the
[validation record](evidence/platform160_validation.json). Native hosted CI also passed all four combinations at
`dd04c8ae748e981b5bc504393bd27c981c5d9c6e` in the linked run. Local source
candidates are not the published archive. Final HEAD review and CI remain merge gates.

両MRIのローカルLinux ARM64検証は合格しました。公開Gemの全68ファイルと読み込んだ
28ファイルを照合し、5種類の改変・source混入も拒否しました。リンク先のネイティブCIも
4組すべて合格です。統合には最終HEADの独立レビューとCI成功を別途確認します。

Do not read a configured matrix as a passing observation. Consult the exact PR
commit and its Actions logs. The runner, Docker server and container architectures
must match; these jobs install no QEMU and explicitly select the matching native image platform.
ARM64 Docker on an ARM64 Mac is Linux ARM64 validation, **not native macOS Ruby**.
Any local AMD64 container on ARM hardware is emulated and must be labelled separately.

設定済みマトリクスは合格証拠ではありません。対象HEADのActions結果を確認します。
runner・Docker server・containerのCPU一致を必須にし、エミュレーションと区別します。
ARM Mac上のLinux containerはmacOS Rubyの検証ではありません。
## Native macOS / Windows checks / ネイティブ検証

The native job uses official `ruby/setup-ruby` pinned to
`b3aaceaef7e0ee231b499e7b5f49c03fc1d32199` (Node24), exact MRI 3.4.12 / 4.0.9,
and standard hosted `macos-15-intel`, `macos-15` (Apple Silicon), `windows-2022`
runners. Host architecture, Ruby OS/CPU and runner architecture must agree;
Rosetta is rejected. No containers, QEMU, user-Mac installation or larger runners
are involved. A configured job is not a PASS.

`native-gems.sha256` pins the five existing dependency archives, published SDK and
three optional SQLite binaries to RubyGems API SHA256 observations on 2026-11-07.
Dependencies are installed in the disposable runner's temporary directory, outside
the checkout, without dependency resolution. The published archive is not rebuilt.
Core loading is checked **before SQLite is installed**, followed by seven installed
examples and six existing installed-mode regression suites (Payment, selective
Payment/Checkout, PISP/date policy, long Open, causal constraint negatives).
All 68 archive/installed payloads and every loaded SDK file are compared with the
publication record; subprocesses repeat loaded-file checks after execution.
Reused source example fixtures must also match the published payload hashes.

The optional SQLite stage uses 2.10.2 for the actual OS/CPU, runs both README
Quick Starts and all existing published guide scenarios, then the long acceptance
regression (including budget-only rejection and unchanged reservation state).
Its twelve-month example checks 12 mock starts and 96,000 JPY reserved within
100,000 JPY. Core and optional persistence outcomes must be reported separately.
No Rails demo, native process/crash oracle or real payment is covered by these jobs.
The original full Linux source/candidate/process-oracle coverage remains unchanged.

OpenSSL compile/load versions and loaded extension SHA256 values are logged.
This is **not** the Linux `dpkg` plus `/proc/self/maps` provider ownership/integrity
audit and is not a security-advisory clearance. Hosted image versions and setup
logs remain part of the evidence. Tests use synthetic inputs and make no service
calls; unlike Linux Docker jobs, native jobs do not enforce network isolation.

Each matching PR update starts one workflow run with four Linux and six native
jobs. The maximum remains three workflow runs per PR; unexpected or failed runs
STOP for diagnosis, with no blind rerun. Read-only contents permissions, no persisted
checkout credentials and the 15-minute job timeout remain. Historical workflows,
public artifact bytes, runtime API, version, release and tags are unchanged.

英日ガイド・署名・選択的開示・長期Openを公開Gemで検証し、coreと任意SQLiteの結果を
分けます。Mac本体への直接導入は行いません。Linuxコンテナの結果をmacOS検証へ
流用せず、設定済み・未実施・失敗を合格扱いしません。OpenSSL情報の記録はLinuxの
provider監査と同等ではなく、本番安全性・実Issuer・実決済の証明でもありません。

## Reproduce / 再現

On a native Linux ARM64 or AMD64 Docker host, from this repository:

```sh
# Repeat sequentially with 4.0.9. No Rails app or real Issuer is used.
RUBY_VERSION=3.4.12
case "$(docker info --format '{{.Architecture}}')" in
  aarch64|arm64) PLATFORM=linux/arm64 ;;
  x86_64|amd64) PLATFORM=linux/amd64 ;;
  *) echo 'Unsupported Docker host CPU'; exit 1 ;;
esac
docker build --platform "$PLATFORM" --build-arg RUBY_VERSION="$RUBY_VERSION" \
  -t ap2-published-guides -f .github/published-guides.Dockerfile .github
docker run --rm --network=none --cpus=2 --memory=768m --pids-limit=128 \
  -v "$PWD:/src:ro" ap2-published-guides sh -c '
    set -eu
    timeout 30 ruby scripts/check_runtime.rb
    timeout 30 ruby scripts/check_sdk_platform.rb /opt/ap2/published.gem
    timeout 120 ruby scripts/check_published_guides.rb
  '
```

The build downloads published **1.6.0**, requiring **186368 bytes** and SHA256
`62de85123e1379c538c9c4302b71a9c55c590162591169a4e335aaa03a8991f8`.
It checks core loading before SQLite installation. Offline execution validates all
published archive/installed payload hashes against `docs/evidence/1.6.0_publication.json`,
the native OpenSSL package identity, SQLite CPU/version, and existing bilingual
README examples and published examples. No source library overlay is permitted.
The existing `check_ruby_compatibility.sh` and `check_candidate_package.sh` remain
separate source/candidate checks in the same workflow. Editing packaged docs makes
a different candidate archive even when the version is unchanged: never publish it
or describe it as the already published artifact.

公開Gemの固定サイズ・SHA・全payload照合と、現sourceから作る候補の検証を分離します。
README等の変更でcandidateのbytesは変わりますが、公開済み1.6.0は変更しません。
既存の署名・因果的負例・独立process oracle・インストール照合は省略しません。

## CI action audit / Actions監査

Only `merchant-source-package.yml`, the current product PR workflow, is changed.
Its previous checkout SHA `11d5960a326750d5838078e36cf38b85af677262` uses Node20.
The replacement is official [checkout v7.0.1](https://github.com/actions/checkout/releases/tag/v7.0.1),
commit `3d3c42e5aac5ba805825da76410c181273ba90b1`; the official action manifest
at that SHA declares `runs.using: node24`. Node24 requires runner >=2.327.1
([upstream migration](https://github.com/actions/checkout/releases/tag/v5.0.0)).
The v7 protection concerns `pull_request_target`/`workflow_run`; this workflow
continues using `pull_request`, read-only contents and no persisted credentials.

The PR event, main branch filter, existing path filters, Ruby versions, timeout,
network-disabled test execution, CPU2/768MiB/128 PID limits and existing test
coverage remain. Added paths cover the new helper/platform and Quick Start docs.
The original Linux validation used one run with four matrix jobs. The native
extension adds six jobs to that same workflow, not six separate workflow runs. No push/merge/dispatch trigger is added. Existing historical/research/one-shot
workflows are untouched. Total budget remains at most three workflow runs per PR;
failed or unexpected runs STOP, with no blind rerun. Zero added billing is required:
these are standard Linux runners in this public repository, not larger runners.

現行製品CIのみNode24版へ更新し、履歴workflowは触りません。PRあたり最大3 runは
上限であり再試行許可ではありません。[更新後の実行ログ](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/42314708194)で、
4 jobすべてのcheckout取得SHAが上記pinと一致し、以前のNode20非推奨警告が0件であることを確認しました。green CIだけで本番安全性・実Issuer・実決済・一般AP2適合を主張しません。
