# Multi-item candidate validation — 2026-10-31

**Subsequent publication:** Owner published the exact verified candidate as
0.6.0 at 11:50:18.664 UTC. Official download comparison completed at 11:51:54 UTC,
matching all 22 payloads and the approved source. See the
[publication record](PROJECT_STATUS.md#060-publication) and
[new post-publication measurements](POST_RELEASE_060.md).
The original scope, table and pending statements below describe the
pre-publication task; they are retained without turning those earlier NOT_RUN
entries into measurements from a later task.

Owner's 178-line formal request delegates this compatible feature, isolated
Docker preparation/tests/retries, synthetic fixtures, independent Codex review,
Draft PRs and conditional Squash Merge. It replaces earlier task-specific
single-file/single-run/multiple-item exclusions. Publication, real Issuer keys,
payments, production GO, costs and Mac installation remain outside this task.

Start: verifier main `6ea21489c445dd6442be772b7e711f06fabcd8e8`, demo main
`1e3d5232e4b4c339df134db8e930126c1a0facb0`. AGENTS and Issue #101 body/current
comments were read. No open PRs were present. Library formal input was read in
full and materialized through its supported identity-preserving flow.

## Code and results

Product code commit: `a1e8188ccbd889650a521446f218353f76c5a3c5`.
[Verifier PR #227](https://github.com/cuichangquan/ap2-mandate-verifier/pull/227).
Demo code: `5512ab69e2d6626da7f1e5b9833dfebdf20ce347`,
[demo PR #14](https://github.com/cuichangquan/ap2-mandate-verifier-demo/pull/14).
Later documentation/evidence commits retain the same product implementation.

| Check | Result |
| --- | --- |
| Full source regression, MRI 3.4.12 and 4.0.9 | PASS, offline bounded Docker |
| New allocation/amount/signing suite | PASS, 431 assertions per MRI; 405 allocation cases use a separate exhaustive oracle |
| New profile/trust/persistence suite | PASS, 21 cases per MRI |
| New signed integration suite | PASS, 35 cases per MRI |
| 8 requirements × 8 candidates, 8 lines, 66 disclosures | PASS, root 11,670 bytes; single build+verify observation 0.0374/0.0343 seconds |
| Independent Python/official fixed SDK comparison | PASS, 288 allocation cases; six full signed pipeline cases and bidirectional signature/Receipt paths |
| Initial candidate ordinary install and payload equality, both MRI | PASS, same 56,832-byte artifact |
| Local Rails candidate fresh build and ordinary frozen Bundler install | PASS, 11 tests / 217 assertions |
| Stable 0.5.0 Rails regression | PASS, 8 tests / 186 assertions |
| Browser at local `/multi-item` | PASS, Coffee×2/Tea×3, later-line shortage rejection, authentic Success/Error displayed |
| Independent Codex source review | PASS, no P1/P2 at both code commits above |
| GitHub source/package CI | PASS, both MRI at a1e8188, [run 41196270172](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/41196270172) |
| Publication / production / real payment | NOT_RUN, outside authorization |

Logs and runtime identity are retained in
[`research/multi_item_checkout`](../research/multi_item_checkout/).
Repeated suites that require Host/InputBuilder suites report those reused counts;
they are not summed into a misleading unique test count. Boundary timing is one
synthetic observation, not a worst-case or production performance guarantee.

Source command for each existing image `ap2-diagnostics-test:3.4.12` / `:4.0.9`:

```sh
docker run --rm --network=none --cpus=2 --memory=768m --pids-limit=128 \
  -v "$PWD:/src:ro" -v "$OUT:/out" -w /src IMAGE \
  timeout 300 sh scripts/check_ruby_compatibility.sh /out/source
```

Packaging: `gem build ap2_mandate_verifier.gemspec --output /out/candidate.gem`,
then in each same bounded offline runtime
`timeout 300 sh scripts/check_candidate_package.sh /out/package /out/candidate.gem`.
This installs normally with local dependency resolution, compares every source,
archive and installed payload, and runs detached legacy/new public API examples.
The source checkout is supplied only for synthetic fixture data.

One initial full regression failed because an existing snapshot-mutation control
forwards positional Root arguments and the new implementation always added a
keyword. The old-profile call shape was restored; both full regressions passed
after the causal fix. No signature/trust checks were disabled. Demo's initial
local-only install failed for missing dependencies; ordinary fixed-lock Bundler
installation corrected its preparation order. Failed attempts are not PASS.

## Specification boundaries

See [the independent comparison](MULTI_ITEM_INTEROP.md). The fixed SDK permits
some underfilled requirements and treats empty candidate lists as wildcard.
This profile follows the normative both-side max-flow fulfillment rule and
rejects empty candidates. Checkout Receipt uses `status: Success/Error` and
original terminal JWS plus trailing `~`; compact-only alternate hashing and
generic authorization `result` are not silently accepted.

The active GitHub rulesets require PR-based squash integration and prohibit
deletion/non-fast-forward. No required approving review count or required status
check is configured; this task nevertheless requires clean independent review
and successful applicable CI. No rule or protection setting was changed.

Public Issue creation was rejected by automatic approval review with reason
"Creating a public GitHub Issue is an external commitment not explicitly
authorized by the task". No Issue was created or retried. Authorized local
development and separate PR/review operations continued. Final external review,
integration and exact-main candidate identity are recorded in the final report;
this document does not predeclare those pending steps complete.
