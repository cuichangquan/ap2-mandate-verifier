# COMMIT reconciliation subset — LIMITED_OBSERVED

Research only. Baseline product main `27445dafbca5ad9646249b008ce83a99348f9092`.
Attempt **HOST-COMMIT-RECONCILE-DOCKER-20261025-R5** ran one batch/four cases/five
workers. Comparison0.555096s, setup through cleanup67.033s, exit0, owned groups
and worker DB sessions recovered. This publication does not rerun anything.

The worker internally receives PostgreSQL COMMIT ACK and then deliberately
withholds the application result. The same CHANNEL_CLOSED event can follow a
commit or pre-COMMIT abort. This is **controlled application-notification loss**,
not actual PostgreSQL response loss, TCP failure, machine crash or durability.
Fixed synthetic caller identity, clock, saved wire and a trusted controller are
assumptions. Real Issuer trust/authentication/clock/revocation, arbitrary delayed
old-writer schedules, failover and external payment idempotency remain unproved.
Evidence and COMMITTED_EXISTING are not renewed Host ALLOW or payment permission.

## Fixed oracle and measured cases

| Case | Independent expected decision and final state = observation |
| --- | --- |
| COMMIT_NOTICE_LOST | Matching fresh-primary lookup returns COMMITTED_EXISTING; DONE/generation1, CONSUMED/RESERVED, exactly1 operation; no reconsumption |
| ABORT_THEN_RETRY | Original worker/session termination and rollback state established; one generation1→2 retry grant, fresh actual Evidence and consuming rechecks; RETRY_AUTHORIZED_THEN_COMMITTED, exactly1 operation |
| INFLIGHT_EMPTY | Ordinary operation lookup empty while original request lock is held; NOWAIT reconciliation returns PENDING, no grant/retry; controlled abort leaves REGISTERED/generation1, ISSUED/OPEN,0 operations |
| BINDING_CONFLICT | Same operation ID with different order-version binding/digest returns CONFLICT; original DONE/generation1, consumed/reserved,1 operation unchanged |

The table was fixed before execution; it is not generated from Gem results.
A separate third connection checks every column of policy/orders/challenges/
requests/operations against independent values seeded from the saved FULL Host
input. All four full-row checks matched. Each worker creates and uses real
ResearchEvidence in the same trusted Ruby process; no Hash reconstruction is
accepted as Evidence. Saved synthetic wire is replayed byte-identically, with
no private-key generation. The specifically planned retry is one of the five
workers, not a second batch or an unlimited retry policy.

Register stable operation identity before sending the first attempt. Its tenant,
synthetic authenticated principal, full order/version binding, challenge/nonce
hash and fixed-order JSON digest must match before result disclosure. A row's
absence is not nonexecution proof. A fresh authoritative primary lookup locks
the immutable registry with NOWAIT; contention/unknown state keeps PENDING.
One retry requires the original process and DB session to be gone, locked
generation1, no operation, and unchanged issued nonce/open order. Generation2
fences generation1; the retry re-verifies and atomically rechecks current policy,
fixed time/order/challenge before consuming. This is not proof of real caller
authentication, general canonical JSON, multi-tenant global uniqueness or crash
recovery. See [the contract](../../docs/ISSUER_HOST_MINIMUM_CONTRACT.md).

## Original evidence and publication

- [REPORT](results/R5/REPORT.json), SHA256
  `bb05bb10e2c331ec806a46c458c0627cdbc528df0733b1b5cd274d51626eedf9`,
  [BATCH receipt](results/R5/BATCH.json) and [SUPERVISION](results/R5/SUPERVISION.json)
  are published byte-identically to the R5 originals.
- [TRANSFER](results/R5/TRANSFER.json):29 required-present files/72775B,
  exporter exit0, complete inventory, remote SHA and host readback matched.
  Optional STOP files are explicitly MISSING on the successful path.
- [DIAGNOSTICS](results/R5/DIAGNOSTICS.json): mkmf.log/gem_make.out and Makefiles
  copied with size/SHA/host-readback checks. Full native build logs remain local
  and are identified by the manifest rather than unnecessarily republished.
- [PROVIDER](results/R5/PROVIDER.json), [EXECUTION](results/R5/EXECUTION.json),
  [PROVENANCE](results/R5/PROVENANCE.json) distinguish original bytes from public
  projections. Host mountinfo, personal paths, credentials, archives and ephemeral
  container IDs are not published. Full original records remain local.

The three experiment sources are byte-identical to R5. The executed supervision
and D2-tested stream transfer sources are also preserved without semantic edits.
`supervision/dummy_once.py` is the distinct D2 source, not another R5 execution.
NOT_RUN comments in prepared source are historical preparation gates; the files
do not grant future execution. No AUTHORIZATION.json is shipped here.

## Fixed environment and resource boundary

This is a new Docker Linux arm64 research environment on MBA; it does not expand
the previously adopted macOS/Ubuntu product-support guarantee.

- Ruby4.0.9-trixie arm64 digest `42c18f0c9807ba1349c0253617d7f08ef98b815463b2f7785d97c4efdfd80f4d`.
- PostgreSQL16.15-trixie arm64 digest `d735d89e0f050dd5efa611ad633e44e06b526da77b04a7501cece311cd032375`.
- JSON2.19.9/JWT3.3.0/base640.3.0/OpenSSL gem4.0.2/Digest3.2.1;
  pg1.7.0 aarch64-linux binary/libpq18.6. Native load paths and hashes matched;
  no source-build fallback for pg. JSON native build ran once.
- Debian libssl3t64/openssl3.5.7-1~deb13u3. Ruby integrity output empty; PostgreSQL
  matched exactly the previously diagnosed373 missing documentation records.
  This is not a blanket path exclusion or a claim that all future versions are safe.
- Read-only roots, internal network, no published port, dedicated non-superuser
  DB role. Ephemeral lab password remains memory/env only and is not evidence.
- Worker CPU1/RAM1536MiB, DB CPU1/RAM512MiB, memory.swap.max0 confirmed.
  Gem tmpfs384MiB only has approved exec,nosuid,nodev; tmp128MiB/result32MiB,
  PGDATA256MiB plus bounded socket/tmp/shm mounts; logs rotated and host output64MiB.
- One batch, max5 workers/10s each, batch300s, whole20min. New acquisition0,
  image build0, Mac direct install0, incremental monetary cost0.
- Owner approved8GiB as an **observation/STOP budget for task increment**.
  Seven samples, max proxy68935364B; this is not a hard physical VM quota or
  proof of an all-time peak. Shared activity can affect the logical delta.

After verified export, the owned DB/worker/network were removed and label-filtered
lookup found none. Base images and shared cache remain; Docker VM file shrinkage
is not promised. R5 success does not cure earlier evidence/resource gaps.

## History and next use

[ATTEMPTS](history/ATTEMPTS.json) retains R1 unstarted, R2 install failure/log gap,
R3 noexec HOLD, R4 evidence loss, D1 scope bug and D2 small transfer result.
These are COMMIT-reconciliation IDs, not the separate prior
[host DB handoff R3](../host_db_handoff_subset/README.md) five-case experiment.
Do not combine counts or promote R4's exit0 to a preserved4/4 result.

Use the short [REUSE_CHECKLIST](REUSE_CHECKLIST.md) before a separately approved
future operation. No new test, syntax execution, build, Docker run, dependency
fetch, Actions, product change or Gem republication occurs in this save/PR task.
Whole E06/Phase2-A PASS, general AP2, first-stage scope expansion and production
GO remain outside this result.
