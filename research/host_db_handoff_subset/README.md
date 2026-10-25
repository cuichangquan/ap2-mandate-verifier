# Actual Evidence → isolated PostgreSQL transaction (limited research)

Observed ID **HOST-DB-DOCKER-20261025-R3**, baseline main `80ea13149543befe106a258d87d7131cc688a158`. Five cases, one batch, eight workers, exit0,0.8206269589999238 seconds; owned process group recovered. [Original REPORT](results/R3/REPORT.json) SHA256 `7464ec9e4bf0fda1773bf8f9838f3b4150a0dee0d9d1e49b06985e174b25f939` is byte-preserved. [Provenance](results/R3/PROVENANCE.json), [summary](results/R3/SUMMARY.json), [provider](results/R3/PROVIDER.json), [cleanup](results/R3/CLEANUP.json).

This is security-evidence research (Issue101 R1 classification), not product integration or production ALLOW. The execution-attempt R1/R2 names below are separate from that process classification.

## Proposition and independent expectations

A real frozen ResearchEvidence is created by the public API and kept in the same trusted Ruby process through each transaction. Host facts come from the independently saved synthetic input, not returned Evidence. Under locks policy→order→challenge, nonce UPDATE, guarded order CAS and unique operation insert commit together or roll back together. The fixed expectation table was authored before execution. The third connection checks every column of all four tables against independently seeded values; only row hashes/sanitized facts are retained. DB sessions must disappear.

| Case | Expected = observed | Final nonce/order/operation count |
|---|---|---|
| NORMAL_REPLAY | COMMITTED then REJECT_REPLAY on same object | CONSUMED / RESERVED v1 /1 |
| SAME_EVIDENCE_RACE | A COMMITTED, B REJECT_REPLAY | CONSUMED / RESERVED v1 /1 |
| EDIT_FIRST | EDITED then REJECT_ORDER | ISSUED / OPEN v2 /0 |
| CONSUME_FIRST | COMMITTED then TOO_LATE | CONSUMED / RESERVED v1 /1 |
| CAS_ZERO_ROLLBACK | tentative nonce UPDATE1 then forced order CAS0; REJECT_CAS | ISSUED / OPEN v1 /0 |

All three two-session schedules observed actual `pg_blocking_pids` and `wait_event_type=Lock`; sleeps alone were not counted. All five full-row checks and worker-session closure checks matched. Each process receives actual Evidence independently for identical saved wire; Evidence is never reconstructed from JSON. COMMITTED means a local synthetic operation row, not payment or Host production ALLOW. CONSUME_FIRST observes the model refusing its later edit, not a guarantee that arbitrary outside writers are blocked. CAS-zero is a research-only injection, not a product option.

## Tested source and environment

The five executable/configuration sources in this directory are byte-identical to R3. They have not been rerun for publication. Product10 hashes remain in compare.rb and REPORT; no lib/gemspec/public Gem changed. Saved FULL input is referenced by the pinned baseline path/hash in PROVENANCE, not regenerated or resigned. Clock is fixed synthetic `verified_at`, not today's wall clock or operational revocation proof.

- New Linux arm64 Docker environment on MBA, distinct from previous Darwin Host-model8 and Ubuntu x86_64 package52 evidence.
- Ruby4.0.9, JSON2.19.9, JWT3.3.0, base640.3.0, OpenSSL gem4.0.2, Digest3.2.1, pg1.7.0 aarch64-linux binary; libpq180006. Native paths/hashes were observed. Ruby uses system OpenSSL3.5.7 with Debian `libssl3t64/openssl 3.5.7-1~deb13u3` security backports. pg's dedicated libpq binary hash matches its archive; upstream1.7.0 identifies bundled OpenSSL3.6.5/krb51.22.2, but this embedded OpenSSL was not separately queried through Ruby OpenSSL.
- Ruby image `ruby@sha256:42c18f0c9807ba1349c0253617d7f08ef98b815463b2f7785d97c4efdfd80f4d`; PostgreSQL image `postgres@sha256:d735d89e0f050dd5efa611ad633e44e06b526da77b04a7501cece311cd032375`, server `16.15 (Debian 16.15-1.pgdg13+2)`.
- Official metadata/references: [Ruby](https://hub.docker.com/v2/repositories/library/ruby/tags/4.0.9-trixie), [PostgreSQL](https://hub.docker.com/v2/repositories/library/postgres/tags/16.15-trixie), [pg1.7.0](https://github.com/ged/ruby-pg/releases/tag/v1.7.0), [Debian OpenSSL security](https://security-tracker.debian.org/tracker/source-package/openssl). Security assessment was scoped to the reviewed provider conditions, not a complete vulnerability-free certification.

## Admission, execution and cleanup boundary

These files are a preserved experiment snapshot, not a one-command turnkey deployment. The separately supervised approved execution performed: local image/archive hash admission → exact provider admission → network-disabled Docker build with per-step CPU2/RAM2GiB/swap0 and explicit cgroup checks → JSON native build once/180s and offline fixed Gem installs → no-network actual pg/Ruby load/hash check and UID1000 result-write check → dedicated internal network/tmpfs DB → dedicated non-superuser owner/database bootstrap → one batch → logs/state preservation → owned-object cleanup. Dockerfile and compose.yaml alone do not implement that entire admission/bootstrap/supervisor sequence; new execution needs a fresh scoped plan/approval, not blind `compose up`.

The PostgreSQL `dpkg -V libssl3t64 openssl` output had to be exit0 and **byte-for-byte equal** to [DIAG01's373 missing-document records](history/DIAG01/EXPECTED_POSTGRES_DPKG_VERIFY.txt); Ruby output had to be empty. No broad path-prefix exemption. Any other missing/hash difference or failure is STOP. R3 admission succeeded. Do not interpret package version environment variables as authorization or proof.

Runtime used CPU1/RAM512MiB for DB and CPU1/RAM1536MiB for worker, swap disabled, no published port, dedicated internal network, no host root/Docker socket mount, DB PGDATA tmpfs256MiB, worker readonly root/cap-drop/no-new-privileges and limited mounts. Same trusted Docker/Ruby/controller and local evidence storage remain harness assumptions. Lab-only ephemeral SCRAM credentials were not published. No real Issuer/payment/production data or new signing keys.

Five cases once, eight workers each≤10s, controller≤300s, whole execution through image cleanup233.916s within20min. Worker stderr empty, third-connection final DB-session count0. JSON build once, no pg source build, no new archive/image downloads in R3, no CI. CPU/RAM configurations were checked; these are harness limits, not product performance guarantees. Exact shared build-cache attribution and a continuous hard8GiB quota were not proved: the work proceeded without that proof, and the5/5 result must not be represented as full resource-condition compliance. Observed derived image1154126474B; local source/results about5MB; aggregate shared cache3.313GB after cleanup is not an R3-only measurement. Total setup/registry/DNS/TLS communication is unmeasured; no128MiB or total-network compliance claim.

Logs/results and object IDs were preserved before deleting the owned DB/worker/admission containers, dedicated network/tmpfs and derived tag. Owned containers/network remaining0. Shared fixed base images and unidentifiable shared BuildKit cache remain; no generic prune or unrelated object deletion. See CLEANUP. Mac received no direct dependency installation. Original R1/R2/DIAG01 were retained locally.

## Historical stops are not overwritten

- [R1 STOP](history/R1/STOP.json): bookworm Ruby OpenSSL3.0.22 / Debian3.0.22-1~deb12u1 had unresolved provider advisories. No Gem install/DB/batch. Later reachability review distinguished verification-only P-256 from signing/DTLS/CMP paths; no blanket unsafe/safe conclusion.
- [R2 STOP](history/R2/STOP.json): trixie packages matched fixed version, Ruby admission passed, PostgreSQL nonempty dpkg output stopped before Gem install/DB/batch. The original shell test failed to retain individual difference lines; exact reason was then unresolved.
- [DIAG01](history/DIAG01/SUMMARY.json): one diagnostic,373 missing files only (356man/15doc/2lintian), dpkg exit0, no executable/library/config difference reported; libcrypto/libssl hashes matched Ruby's verified files. Missing paths agree with official Debian slim exclusions. Not a general safety proof.

## Remaining HOLDs

No general concurrency/throughput or arbitrary schedule proof; no crash durability (tmpfs), network-partition/unknown-COMMIT recovery, real Issuer provenance, real trust/clock/revocation, production ALLOW/payments, Phase2-A full PASS or production GO. No new E06/Gem release claim. Historical communication gaps, full-duration disk enforcement and shared-cache accounting limitations remain. This publication work is static-only: no syntax check/test/build/Docker rerun/dependency acquisition/CI/Gem republication.
