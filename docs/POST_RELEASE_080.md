# 0.8.0 publication and post-release verification

Owner published from their Terminal at **2026-11-01 06:01:31.103 UTC**.
Official metadata/download comparison at **06:03:20 UTC** found exactly
79,872 bytes, SHA256
`6c07664e4291aa8bc025b152075869322411a0d99861e1267959f1794e99acec`,
identical to the approved retained final Gem and all29 payloads from source
`5a7394c1b98f000b321423e2c2f80d50b5157808`. Runtime dependencies and MRI
requirements match. [Publication receipt](evidence/0.8.0_publication.json).
The initial cached version inventory lag resolved on a read-only recheck.
No re-push or attempt-record edit was made. The receipt's NOT_RUN list describes
that verification checkpoint, before separate postpublication authorization.

The published source and reviewed HEAD `35749455db7330c0dc9c1497d78e991319cc09bc`
share the complete tree `726fe5439a1bea41245dee731b75b006e5d3cbff`.
[Implementation PR231](https://github.com/cuichangquan/ap2-mandate-verifier/pull/231)
has latest-HEAD Codex no-findings, resolved threads and both MRI CI success.
Superseded79,360-byte candidates are not published artifacts.

Owner separately approved exact-source v0.8.0 tag/Release, English/Japanese
current guides and default demo alignment, with Draft PR/latest-HEAD independent
reviews and conditional Squash Merge after gates. This task changes no lib,
gemspec, dependency pins or profile contract. Packaged preparation documents stay
unchanged; repository-only updates do not rebuild or replace official Gem bytes.

## Fresh official-Gem measurements

The published-guides Dockerfile freshly downloads official0.8.0, checks size/hash
and normally installs it with unchanged pinned dependencies. There is no source
library overlay or Gem build. On Linux arm64 both formal MRI versions pass:

| MRI | Image SHA256 | Result |
| --- | --- | --- |
| 3.4.12 | `6db7bdb0a07108f9f35011aae9b5cd0b3c98c4d3cd2e3c05a18041626214a8ea` | PASS |
| 4.0.9 | `e385e678185be2eefbf18a48a4aca248cdc66238b265ff533cb4a64c5613262c` | PASS |

Fresh runs execute both README InputBuilder Quick Starts, merchant/Success/Error,
old multi-item and Direct examples, the example physically inside the installed
Gem, and the exact [Release snippet](RELEASE_080.md). Conditional output is:

```text
Conditional verified=true
Receipt verified=true purchase_succeeded=false
```

The installed complete example covers A/B×1 and C×2 across three rows, both
Receipt outcomes and application consumption/retry/pending-state responsibilities.
Release setup also uses only the installed example/public APIs, with independently
prepared Host trust/current-order records and fresh synthetic challenge values.
No test-only issuance helper or internal API is required.
[New logs](evidence/published080-guides/) retain outputs, not previous candidate PASS.

```sh
docker build --build-arg RUBY_VERSION=3.4.12 -t ap2-published080-guides:3.4.12 \
  -f .github/published-guides.Dockerfile .github
docker run --rm --network=none --cpus=2 --memory=768m --pids-limit=128 \
  -v "$PWD:/src:ro" -w /src ap2-published080-guides:3.4.12 \
  timeout 120 ruby scripts/check_published_guides.rb
```

Repeat with4.0.9. Existing docs CI uses the same two-job/one-workflow path.
No workflow edits or extra triggers; max3runs/PR remains a ceiling with no blind
reruns. Exact follow-up PR/review/CI identities are recorded in PR comments;
latest-HEAD clean review, unresolved0, current protection and all test gates apply.
No owner approval review is submitted.

## Local demo scope

Default demo installs the checksum-pinned official0.8.0 with frozen lock and
unchanged remaining dependencies. Its existing Open→Agent Closed verification,
merchant signing and multi-item/Receipt UI are retained. There is no conditional
approval/Open-issuance UI or Provider-key-management backend; the standalone
Ruby example is the main conditional-delegation entry. Fresh demo test/browser
measurements are recorded in the demo's `docs/PUBLISHED_080.md` and follow-up PR.

No host installation, extra costs, security settings, credentials, real Issuer,
wallet/payment, production deployment or public Web. Dedicated preview tab and
container are cleaned after inspection; shared images/cache/services are retained.
