# Stage15 bounded comparison publication

Status: LIMITED_OBSERVED on one MBA. This records the approved local comparison;
it is not completion of all Stage15 reproducibility requirements or Stage16 GO.
No production Gem code, workflow, previous pin, acquisition record or old result
is changed. The prior Evidence v2 and legacy non-success API contracts remain.

`results/R3/` contains byte-identical copies of the five saved original R3 files.
The historical MANIFEST.json binds the README before this publication note and
all executable files used by R3. Its old README hash is historical, not the hash
of the updated publication README. observe.rb and candidate.json remain identical
to R3; compare.py now adds an early optimization-mode rejection after review.
New integration test output is saved separately in R5;
no R1/R2/R3 evidence is regenerated or replaced to claim previous execution.

PR review found one applicable P1: -O/-OO/PYTHONOPTIMIZE could strip the adapter's
assertions. The corrected adapter stops before loading code/inputs or creating
artifacts whenever sys.flags.optimize is nonzero. Four subprocess controls require
nonzero exit, exact STOP diagnostic, no stdout and no output directory. R5 records
the corrected adapter identity; its deterministic inputs must equal the original
R3 input bytes. R3 success is historical under the recorded unoptimized command,
not evidence that the original adapter safely supported optimized execution.

R3 report SHA256:
`6a691a163cba831fc53c30f7d1dd7991eefef34d7ce0883457424075a9a584dd`.
R3 inputs SHA256:
`41ad845a7ea82a9c7316c9ef11fb8ee5281453afafe2b4932c7217c1936562c1`.
The report identifies the tested main commit/tree, ten captured Ruby source
hashes, observer/adapter/oracle, fixed dependency identity and thirteen Schema
hashes. It records actual expectations/outcomes/entered wrappers, exact input
hashes and normal Evidence contents. Each entered wrapper is only reachability.

Results: 30 independent contract cases (4 verified research outputs,26 rejects),
12 logical boundary probes,8 pinned Schema judgments,885 separate regressions.
R3 elapsed3.565s; longest Ruby probe0.121s rounded up. Limits are per-probe10s
and whole-run300s. These are observed logical bounds/timeouts, not product
CPU/RSS/parallel-load guarantees. No new package, network-dependent test, host,
OS/runtime infrastructure, payment or nonce consumption is involved.

All inputs are deterministically constructed from the repository's existing
public synthetic signed fixtures and literal synthetic Host assertions. Public
fixture nonces/signatures/public PEMs are test vectors, not live credentials or
real issued challenge nonces. Normal public Evidence omits raw nonce; the inputs
necessarily retain the already public synthetic signed nonce. No signing private
key, personal data, private machine path, environment log, venv/vendor/cache is
included. Expanded byte-limit filler is retained to preserve exact original input
hashes instead of silently substituting compact/regenerated evidence.

The six Root classes and signature/binding/profile controls are described in
README.md. Python expectations precede Ruby observations and use independent
signature/graph/contract code; shared fixture/profile/crypto assumptions remain.
The supported Host shape is constructed, not a complete independent JSON/API
implementation. terminal.iat+301 is included in the minimum, but is not isolated
as the limiting expiry by these saved signed wires; Ruby regression covers it.

Other-environment replay remains NOT_RUN. Real trust/clock provenance, Host latest
state atomic recheck plus nonce/order CAS, generic Schema/all constraints,
payments, Stage7 final acceptance, Stage16 GO, production, Gem distribution and
Phase2B remain HOLD. Historical acquisition measurement gaps remain unchanged:
O1/O3 metadata-inclusive10MB and O4 sent-header-inclusive1MiB were not proved.
This publication does not repair or retroactively measure them.
