# 1.6.0 onboarding validation — 2026-11-05 UTC

Scope: README/Quick Start navigation, existing published examples, and a source-only
long-budget comparison. No public API, runtime library, Gem payload list, version,
release, production deployment or payment changes. Existing research and production
HOLDs remain separate. User authorized implementation, tests, independent review
and conditional main integration for both repositories.

Baseline SDK main: `7fae869ecfd58eab749eb788293a9f11246d61e1`.
Baseline demo main: `d2b1804d317928d8eafd953f7e766862c8f6f901`.

## Observed locally

Docker Desktop, Linux ARM64, MRI 4.0.9, pinned demo dependencies. Network disabled
for execution; CPU 1, memory 512 MiB, pids 128, individual timeouts 60–120 seconds.
Normal image build reused its existing pinned dependency layer; the optional
acceptance layer fetched and verified pinned sqlite3 2.10.2. This is not a fresh
no-cache dependency reproduction. No software was installed directly on macOS.

Published Gem: 186,368 bytes, SHA256
`62de85123e1379c538c9c4302b71a9c55c590162591169a4e335aaa03a8991f8`.
`installed_gem_check.rb` confirmed all 68 installed/archive payloads match and
loading occurs outside the demo source. No Gem rebuild/source-library overlay.

| Check | Observed result |
| --- | --- |
| `scripts/check_published_guides.rb` in SQLite-equipped image | Exit 0; both README code blocks, Direct/conditional Checkout, merchant/multi-item, Payment, selective, PISP/date, acceptance recovery and twelve-month examples passed |
| `examples/long_payment_limits.rb` | Exit 0; twelve mock starts / 96,000 JPY; separate 40,000 + 40,000 reservations followed by budget-only rejection; stateless wire control valid, no Ticket, amount/count remain 80,000 / 2 |
| `AP2_INSTALLED=1 ruby test/long_payment_test.rb` | 162 assertions passed |
| `AP2_INSTALLED=1 ruby test/long_payment_acceptance_test.rb` | 75 assertions passed |
| Demo regression | 11 runs, 221 assertions, no failures/errors/skips |
| Demo Checkout/Payment/selective wrappers | Exit 0; authentic Success and Error outcomes distinguished |
| Local relative README/Quick Start links; `git diff --check` | Passed |

An initial whole-guide run in the normal demo image stopped at the optional
acceptance example because SQLite is deliberately absent there. Repeating with
the documented acceptance image passed; no dependency pin/fallback was changed.

The SDK/demo limits supplements are byte-identical and use the published Gem's
existing fixture helper. Fixed explicit expected amounts/counts form the comparison
oracle; the stateless verifier is a separate control showing that history is what
causes rejection. This is a teaching example, not new independent cryptographic or
processor exactly-once evidence. No raw keys/wires/nonces are logged.

## Review and limits

Independent Codex static review of the implementation found no substantive P1/P2.
Final commit review and CI results are recorded on the associated PRs so their
reviewed SHA is not confused with this baseline or an earlier draft.

Local MRI 3.4.12, x86_64, other OSes, a no-cache build, real Issuer trust, production
storage/processors, elapsed-year scheduling and settlement were not tested here.
CI's existing published-guides matrix covers MRI 3.4.12/4.0.9 separately; its actual
result must be read from the PR. No numerical performance or generic AP2 MONTHLY
conformance claim follows from these observations.
