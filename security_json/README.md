# JSON2.19.9 security dependency update — limited MBA validation

Base main `4748972992c3ae2756cd4c86da2fc286b0c40d1d` fixed JSON2.18.0 and
`allow_duplicate_key: false`, matching the published affected configuration for
[CVE-2026-33210](https://github.com/advisories/GHSA-3m6g-2423-7cp3).
This update pins2.19.9 in the gemspec and parser gate. Duplicate rejection and all
existing limits/options remain enabled. There is no exploit PoC, crash or
information-disclosure experiment; ordinary existing synthetic tests are replayed.
Historical executions are retained, not blanket-invalidated or relabelled as tests
of the new dependency.

2.19.2 repairs that parser defect;2.19.9 additionally repairs the IO generator
[CVE-2026-54696](https://github.com/advisories/GHSA-x2f5-4prf-w687).
It is a minimal fixed2.x candidate, not a claim to be the newest JSON release or
free of unknown defects. The separate ResumableParser advisory affects2.20.0–2.21.1;
that API/version range is not introduced here.

## Acquisition and installation

One official `https://rubygems.org/gems/json-2.19.9.gem` GET, exact107008B and
SHA256 `9b9025b7cdddafa38d316eca0b2358488e42d417045c1b90d216a9fefe46b79a`.
HTTP/1.1 trace records95 request-header bytes and1061 response-header bytes:
total108164B, within262144B budget. `size_request` returned0, so it was not used.
Header trace counts, response-header-file size, body size/writeout and SHA were
cross-checked before install. No redirects, automatic retries or index requests.
These are HTTP-layer observations, not a pre-guaranteed hard cap or DNS/TLS/
interface-wide measurement. Prior two acquisition measurement gaps remain unproved.

The initial CLI launch put `--norc` before `install` and failed option parsing
before any installation/native compilation. The corrected common-option position
was used once after confirming the dedicated GEM_HOME was empty. One actual
offline native build succeeded in5.12s (limit300s). Both logs remain private and
separate. No rebuild, new build tool, extra dependency, network install or global
environment update was performed. Existing Ruby4.0.1, JWT3.3.0, base640.3.0,
Xcode/clang/make/SDK/headers were reused. JSON has no additional runtime gems.

`dependencies.lock.json` fixes the archive, versions and runtime-manifest hash.
`runtime.json` records all seven loaded JSON Ruby/native files by relative path
and SHA256. This is a comparison against the recorded MBA build, not an execution
environment attestation, trusted-source registration or portable binary identity.
The archive, installed gems/native binaries and raw environment/build/network
logs stay in ignored `.local-deps/`; they are not distributed in this change.

## New comparison entry; old evidence remains unchanged

Use `security_json/compare.py` for this dependency. Stage11 and Stage15 adapters,
pins, input originals and R3/R5 results are unchanged. Their historical exact
source/runtime pins intentionally do not describe the updated Gem. The new
adapter captures ten current verifier sources plus the distributable gemspec,
Gemfile and Gemfile.lock (thirteen files)
into a private temporary tree and
uses the ordinary Gem entry; candidate/runtime/lock/observer bytes are fixed by
reviewed SHA pins. The old Stage15 adapter is loaded only as fixed Python oracle
functions; its main, old runtime check and old result reader are never invoked.
Forcing a fixed test GEM_PATH alone does not certify normal Bundler resolution.
The resolver tuple is fixed together: the root lock is regenerated offline with
`bundle lock --local --update json`, retaining all other versions/platforms. The old CHECKSUMS section contained no
actual checksums and prevents frozen setup under Bundler4.0.3; that empty section
is removed. The acquired JSON archive and existing JWT archive hashes remain
fixed in the dedicated dependency ledger; no archive checksum is invented for
the built-in OpenSSL gem.
Each captured-tree Ruby probe runs ordinary frozen Bundler setup against those
captured resolver files, without install/network/build. Observed resolved gems,
Bundler4.0.3 and existing OpenSSL4.0.0 are also compared with the pinned runtime.
Seven candidate controls start from a complete baseline and cover original,
reverted/relaxed/missing gemspec, stale/missing lock and changed Gemfile before
Ruby executes. This resolver-boundary reassessment addresses both review gaps
together. Old R2/R3 results remain historical; the completed resolver run is R4.
The old original signed Oracle and binding adapter are independently pinned
before execution. Expected outcomes are not generated from Gem results.

New comparisons reuse the same42 exact public synthetic inputs from retainedR3:
30 independently expected contract cases,12 ordinary byte/depth/shape probes,
plus8 fixed local Schema judgments. No new attacker payload, external key/data,
Schema, dependency or network-dependent test is introduced. Four optimized Python
invocations must stop before inputs/artifacts; the entry rejects -O/-OO and
PYTHONOPTIMIZE. Evidence v2 and the old non-success API semantics remain unchanged.
The implementation revision is a static API identifier, not a source/dependency
attestation; candidate/runtime hashes identify this dependency-specific run.

With existing task venv Python and schemas, run from the repository, using a new
destination. No acquisition/install occurs in these commands:

```python
import subprocess, sys, time
started = time.monotonic()
subprocess.run([sys.executable, 'security_json/compare.py', '../json2199-new-run'],
               timeout=300, check=True)
subprocess.run([sys.executable, 'security_json/optimization_test.py'],
               timeout=max(1, 300-(time.monotonic()-started)), check=True)
```

The adapter supplies only task-local GEM_HOME plus read-only existing dependency
locations. Every Ruby probe has at most10s; comparison and regression batches each
have300s limits. Existing885 regression cases use the new task-local JSON, with
only three explicit test version expectations updated. JSON version mismatch
still returns non-success before parsing. Unknown result, mismatch or timeout
stops the comparison; no successful report is minted on failure.

Results here are new dependency observations on the MBA. Trusting the harness,
interpreter, temporary tree and installed dependency files remains necessary;
hostile same-user/runtime integrity is not proved. Other environments, hard
CPU/RSS/parallel-load guarantees, real Issuer/Host/clock provenance, atomic latest
state recheck+nonce/order CAS, payments, general Schema/all constraints, Stage7
final acceptance and Stage16 GO remain unproved/HOLD. terminal.iat+301 is included
in the independent minimum but these saved wires do not isolate it as the
limiting expiry. Production, Gem distribution and Phase2B remain HOLD. No Actions.
