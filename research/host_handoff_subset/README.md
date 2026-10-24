# Synthetic Host handoff subset

SOURCE_ONLY / NOT_RUN. Exactly four preparation files, no product edits or result claim.
The preparation text below is historical. The subsequent approved **HOST-HANDOFF-MBA-20261024-R1** execution observed all eight fixed expectations in one batch, 0.843462 seconds, exit0, owned group recovered. [REPORT](results/R1/REPORT.json), [SUPERVISION](results/R1/SUPERVISION.json), [provenance](results/R1/PROVENANCE.json). Execution allowance is consumed; no further run is authorized by this document. Executable sources are byte-identical to that run. Documentation-only follow-up did not rerun anything. Real DB atomicity, concurrency, Issuer trust and production GO remain unproved.
Baseline main: `feb3c426365b5bb9d2fe2752a30f0e08f7eee48c`.

The observer calls the existing public Gem entry point once in each child and keeps its real Evidence in that child. The controller compares only sanitized observations against this pre-authored Host transition table; Gem output never generates the expected verdicts.

| Scenario | Post-Evidence change / operation | Expected observations | Model ledger |
|---|---|---|---|
| NORMAL | current authoritative state unchanged | MODEL_COMMIT | consumed, order accepted, 1 transition |
| REPLAY | use identical Evidence a second time | MODEL_COMMIT then REPLAY_REJECT | consumed, 1 transition |
| KEY_REVOKED_AFTER_EVIDENCE | current Issuer key becomes revoked | KEY_REJECT | issued, 0 |
| ORDER_CHANGED_AFTER_EVIDENCE | current order version changes | ORDER_REJECT | issued, 0 |
| ROTATED_OLD_KEY | current enrolled Issuer reference rotates | KEY_REJECT | issued, 0 |
| PROFILE_SNAPSHOT_ROLLBACK | current generation below durable high-water | ROLLBACK_REJECT | issued, 0 |
| TRUST_UNAVAILABLE | current trust refresh cannot be established | HOLD | issued, 0 |
| CONSUMPTION_UNKNOWN | synthetic store reply is indeterminate | PENDING, subsequent use remains PENDING | pending, order unknown, 1 attempt |

All eight require `scoped_research_verified` and an actual frozen ResearchEvidence before the Host transition. No negative is credited merely because Gem verification failed. Freshness, time, full binding, snapshot and selected keys are rechecked by the common model operation; no scenario name directly selects its verdict. The unknown scenario models uncertainty, not a second commit attempt. Single-process state replacement is only an abstract atomic transition, not a real database transaction.

## Future execution candidate — approval still required

One batch / eight children once each, each at most 10 seconds, total 300 seconds including cleanup. Network 0, acquisition 0, cost 0; existing MBA MRI 4.0.9 / JSON 2.19.9 / JWT 3.3.0 / base64 0.3.0 / OpenSSL gem 4.0.2 / Digest 3.2.1 / libcrypto 3.5.9 only. No Ruby native build or package installation. No Python third-party package is needed by this controller.

Planned arguments: `compare.py --execute-approved --source-root <existing fixed source checkout> --inputs <saved PUBLIC_INPUTS.json> --ruby <existing dedicated Ruby> --gem-home <existing dedicated GEM_HOME> --gem-path <existing dedicated GEM_PATH> --out <new exclusive result directory>`.

Saved input is the prior semantic R1 PUBLIC_INPUTS.json, SHA256 `cc26cf7115c59c5e44c34a5a051f7dd17577958c32df7113ecbe022bb390a4f5`; only its FULL arguments are replayed. Historical semantic results establish the wire's prior normal behavior, not this new Host model's outcome. The controller pins ten product source files; it uses no generator imports or signing helper and never reads a private key. Future source reads and Ruby environment validation occur inside the same 300-second budget. Existence alone has not established that dependencies are currently usable.
The saved input is already published at [`research/e06_semantic_subset/results/R1/PUBLIC_INPUTS.json`](../e06_semantic_subset/results/R1/PUBLIC_INPUTS.json) in the baseline commit. No duplicate wire or key material is added here. R1 used the existing MRI4.0.9 MBA environment and checked dependency activation / libcrypto identity inside each child; its runtime observations are in REPORT, not a promise that any later environment will match.

Future execution copies the hash-checked product bytes and observer into a new private result tree and requires that exact product tree. The outer controller supervises the worker's complete process group, including preflight, for 296 seconds with cleanup reserved inside 300 seconds. Local regular-file operations and a trusted, unmodified controller/runtime remain harness assumptions, not an OS hard real-time guarantee.

Run output is a new local REPORT.json or STOP.json / CONTROLLER_STOP.json with SUPERVISION.json; never overwrite old evidence. Reports contain case/verdict/ledger/runtime and source/input hashes, not raw wire, nonce or keys. The source copy contains existing public product source only. Any failure, timeout, identity mismatch or uncertain child recovery stops the batch with no rerun. No syntax checks, imports, tests or comparisons have been run in this preparation. Before execution approve the exact paths and verify this prepared source's hashes, existing runtime/dependencies, fixed input and source identity. Real trust, DB concurrency and worst-resource guarantees remain unproved.
