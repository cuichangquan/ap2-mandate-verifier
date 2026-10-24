# E06 causal subset — LIMITED_OBSERVED (MBA, one batch)

Result ID: **E06-CAUSAL-MBA-20261024-R1**. Baseline repository commit:
`53370a3c6e85ec7850166550e740f163122afafe` (PR181).
Official AP2 Schema commit: `b4587ac1d055888a73b4b21750973cffba961793`.

Owner-approved B ran once on MBA: four Ruby children, four independent matches,
exit0, total0.796575749758631s (worker comparison0.778269459027797s), owned group
recovered. This is a limited observation of the two propositions below, **not E06
full PASS, verifier-core completion or production GO**. E06 remains PARTIAL/OPEN.
No network, acquisition, installation, build, CI, product change or Gem republish
occurred. The B execution allowance is consumed; no rerun is authorized.

[Results](results/R1/REPORT.json), [completion receipt](results/R1/BATCH.json),
[synthetic public inputs/original wires](results/R1/PUBLIC_INPUTS.json), and
[provenance/original hashes](results/R1/PROVENANCE.json) are saved separately from
historical Stage15 evidence. REPORT removes only the unnecessary worker PID;
the original report remains unmodified locally. BATCH and PUBLIC_INPUTS preserve
original bytes. Executed compare.py and observe.rb preserve exact executed bytes,
including preparation-time SOURCE_ONLY labels; this README records the later run.
Private keys existed only in worker memory; saved inputs contain public keys and
synthetic wires, never real credentials, private keys or personal data.

## Two propositions, four inputs

| New synthetic input | Independently authored expected result | Required Ruby causal evidence |
| --- | --- | --- |
| FULL | All three signatures valid; graph/binding and official Open/Closed/Merchant/Checkout/Item Schema valid; full research Evidence | Issuer/Agent/Merchant calls each return normally; purchase binding returns before the first actual content check; Evidence exactly matches the separate Python contract facts |
| S01 | Open `constraints[0].items[0].id = 123`; all signatures and graph/binding valid; official Open Schema type rejection; `invalid_scoped_schema`, Evidence nil | All three signatures and binding return normally before the first content check; actual content raise is `text!` |
| PRICE_STRING | Checkout `line_items[0].item.price` becomes a String; Merchant signature, Closed hash, Agent signature, Host Checkout digest all rebuilt consistently; Item/Checkout Schema type rejection; `invalid_scoped_schema`, Evidence nil | All three signatures and binding return normally before content; actual content raise is `amount!` |
| S01_BAD_AGENT | Exact S01 public arguments except one flipped bit in the canonical64-byte Agent signature; Issuer/Merchant signatures remain valid; `invalid_root_signature`, Evidence nil | Issuer returns; Agent calls then raises; Merchant signature, binding normal return and content check are not reached |

`S01` is the nested LineItemRequirements id type, not a nonexistent top-level Open
id field. PRICE_STRING changes the required Checkout Item.price field, not an
unsupported extra field on Open's acceptable-item subset. The positive control
and two signed content negatives are new signatures under the same three fresh
synthetic keys. They are **not replay of saved signature bytes**. Distinct synthetic
challenge/nonce bindings are made per independent case; S01_BAD_AGENT retains the
same S01 challenge/wires except its signature. No real challenge is issued/consumed.

The compared facts remain stateless research Evidence, never Host ALLOW. A
rejection before the intended content check does not establish either content
proposition. Missing observations, wrong order, unresolved Schema reference,
unknown source/runtime/dependency or unexpected exception stop as UNPROVEN.
terminal300/301 expiry comparisons are explicitly out of scope.

## Fixed-reference reuse and independence

`compare.py` contains immutable SHA256 pins for all10 product source files,
the existing original signed-Root O1/O3 oracle, `test/o2o5_compare.py`,
`research/p1_10q/generate_gp01.py`, `research/stage15/compare.py`,
`test/stage11_identity.py`, the historical acquisition ledger and both dependency
locks. Current required product files were statically matched by Git blob to
baseline53370a3. These pins do not modify any historical file or old manifest.

During the one approved execution, bounded no-follow/same-descriptor
reads authenticate those exact bytes. AST selection takes only explicitly named
definitions/constants from each pinned Python source:

- O1/O3: signature/graph and strict byte-decoding predicates, not its old CLI/policy.
- O2/O5: public-key conversion, signature, binding, resolver and strict-subset predicates.
- `generate_gp01.py`: only `sign_compact`; its imports, SDK models and `generate()`
  are never executed. No AP2 SDK dependency is introduced.
- Stage15: exact PROFILE constants and model/args/evaluate functions, excluding
  top-level runtime checks and old fixtures/execution main.

This limited selection is not a general source loader or AP2 resolver. It reuses
already independent Python JWCrypto verification and original graph traversal;
Ruby output is never used to author expected code, Schema verdict or Evidence.
The separate official Schema registry validates all13 pinned local files and
their full reference closure, with retrieval of unregistered resources forbidden.
Open/Closed/Merchant/Checkout/Item verdicts and type-error paths are recorded
separately from the strict profile's result. Unsupported-format fallback is absent.

Only ephemeral private JWK objects are generated; no private export/PEM is used.
They remain in memory. Saved PUBLIC_INPUTS.json contains signed synthetic wires
and public keys only. The saved Stage15 FULL input is a pinned shape/time template
SHA256 `41ad845a7ea82a9c7316c9ef11fb8ee5281453afafe2b4932c7217c1936562c1`,
not authority, current clock or a preserved signature replay.

`observe.rb` loads the captured10-source private temporary tree through the usual
Ruby entry/require_relative chain and invokes public `verify_research`. Small
forwarding wrappers record call/normal-return/raise and exact wire digest for
Issuer/Agent/Merchant signature routines, graph and purchase binding. Wrapper
entry is never PASS. A TracePoint at the unique pinned first constraint check
records actual content reachability and the content exception method/line/code.
If source lines or trace semantics cannot establish this, comparison must stop.
Trusted harness/interpreter/temp tree and cooperative local filesystem are
preconditions; malicious same-user/runtime attestation is not claimed.

## Observed environment and execution bounds

Preflight and the bounded batch matched the pinned product/reference/fixture/
13Schema bytes and CPython3.11.15 Darwin arm64 plus all ten exact Python
package versions listed in REPORT. Observer processes confirmed MRI4.0.9
arm64-darwin25, JSON2.19.9/JWT3.3.0/base640.3.0/OpenSSL gem4.0.2/Digest3.2.1,
and libcrypto OpenSSL3.5.9. This does not attest the complete runtime or dependency
supply chain. Source snapshot provenance is established by captured hashes,
not by its local directory name or unrecorded mutable checkout reads.

Exactly one batch, four Ruby invocations each capped at10s; total cap300s
including preflight/imports/generation/comparison/cleanup. No child timed out;
the entire observed batch took less than one second. Individual child durations
were not separately recorded, so no per-child timing benchmark is claimed.
No extra test, syntax execution, import probe, generation, dependency installation,
build or CI was performed for repository preservation. Existing output directory
means STOP; failure/unknown means STOP, with no automatic rerun.

A standard subprocess controller in this same comparator gives its one worker
296s, reserving recovery within the300s total. Schema/crypto imports, key
generation and independent evaluation run only in that worker. The four Ruby
children inherit the worker's group; the controller owns only that one group.
Each child is killed/waited in finally if needed. All controller paths check/kill
and wait the owned worker/group; recovery unknown is UNKNOWN with no following
case or final COMPLETE. A worker-complete marker is provisional until the outside
controller verifies cleanup. No new runtime, launcher service or generic monitor
is introduced. The saved completion receipt and report record this one execution and cleanup.

CLI inputs are --source-root, --schema-dir, --ruby, --gem-home,
--gem-path and --out, plus --execute-approved. This flag is only a mechanical
guard and does not grant Owner Approval B. The historical preparation A performed no execution. B is now consumed; do not
run/import/syntax-check/generate again without separate authorization.

This successful batch saved public synthetic inputs, exact wire/input/source/helper/
Schema/dependency hashes, independent signature and Schema decisions, final
result/Evidence and causal traces in a new output. The result
is LIMITED_OBSERVED for these two propositions. It does not close E06, pass all
E00–E09, declare the limited core complete or grant E10/production/Phase2B.
Current published pre3 hash and MBA/Linux observations remain separate immutable
evidence; this preservation does not rebuild/release or alter that Gem.
