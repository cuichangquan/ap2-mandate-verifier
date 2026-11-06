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

| Target | Method and scope | Status before PR CI |
| --- | --- | --- |
| Linux ARM64, both MRI versions | Native `ubuntu-24.04-arm`; Debian bookworm containers; SDK source/candidate and published Gem | CI pending |
| Linux AMD64, both MRI versions | Native `ubuntu-24.04`; same checks; x86_64 SQLite native Gem | CI pending |
| macOS / Windows | Gem-only; would require their own pinned native runtime/dependency evidence | NOT_RUN |

Local native Linux ARM64 checks passed both MRI versions: full existing source and
candidate suites, published guides, all 68 published payload hashes and 28 loaded
SDK files. Five causal identity-negative probes passed. See the
[validation record](evidence/platform160_validation.json). Native hosted CI is still
pending; local source candidates are not the published archive.

両MRIのローカルLinux ARM64検証は合格しました。公開Gemの全68ファイルと読み込んだ
28ファイルを照合し、5種類の改変・source混入も拒否しました。ネイティブCIは実行待ちです。

Do not read a configured matrix as a passing observation. Consult the exact PR
commit and its Actions logs. The runner, Docker server and container architectures
must match; these jobs install no QEMU and explicitly select the matching native image platform.
ARM64 Docker on an ARM64 Mac is Linux ARM64 validation, **not native macOS Ruby**.
Any local AMD64 container on ARM hardware is emulated and must be labelled separately.

設定済みマトリクスは合格証拠ではありません。対象HEADのActions結果を確認します。
runner・Docker server・containerのCPU一致を必須にし、エミュレーションと区別します。
ARM Mac上のLinux containerはmacOS Rubyの検証ではありません。
Official `ruby/setup-ruby` at `b3aaceaef7e0ee231b499e7b5f49c03fc1d32199`
declares Node24; ruby-builder and RubyInstaller publish both exact MRI versions.
However this repository's native-provider audit uses Debian `dpkg` and Linux
`/proc/self/maps`, and Windows native dependency builds may require MSYS2 packages.
No macOS/Windows-specific equivalent provider audit has been run here. Next step:
separate core Gem-only hash/load/example checks from Linux provider and persistence
checks, validate pinned native dependencies, then add scoped standard hosted jobs.

macOS/Windowsは対応外と断定せず、未検証として残します。次は各OSのネイティブMRIと
依存pinを確認したGem単体検証です。この作業のためにMacへソフトを直接導入しません。

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
One matching PR update starts **one workflow run with four matrix jobs**, not four
runs. No push/merge/dispatch trigger is added. Existing historical/research/one-shot
workflows are untouched. Total budget remains at most three workflow runs per PR;
failed or unexpected runs STOP, with no blind rerun. Zero added billing is required:
these are standard Linux runners in this public repository, not larger runners.

現行製品CIのみNode24版へ更新し、履歴workflowは触りません。PRあたり最大3 runは
上限であり再試行許可ではありません。Node警告解消は更新後の実行ログで確認するまで
未証明です。green CIだけで本番安全性・実Issuer・実決済・一般AP2適合を主張しません。
