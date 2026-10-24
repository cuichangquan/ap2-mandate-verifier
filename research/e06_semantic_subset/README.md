# E06 semantic subset — LIMITED_OBSERVED (MBA, one batch)

Result ID: **E06-SEMANTIC-MBA-20261024-R1**. Baseline main is
`b858d2b37b529527307957335b722b88481d7fe7` (PR182).
Official AP2 Schema remains `b4587ac1d055888a73b4b21750973cffba961793`.

Separately approved execution B ran exactly once: four Ruby invocations, all four
independent comparisons MATCH, exit0, total0.7031205422244966s (worker comparison
0.6691130003891885s), owned group recovered. The execution allowance is consumed;
no rerun is authorized. Product code, historical inputs/results/pins, prior causal
comparison evidence and the published Gem are unchanged. The comparison used no
network, acquisition, installation, build, new signature or private key.

[Result](results/R1/REPORT.json), [completion receipt](results/R1/BATCH.json),
[public saved-wire inputs](results/R1/PUBLIC_INPUTS.json), and
[provenance/original hashes](results/R1/PROVENANCE.json) preserve the evidence.
Public REPORT removes only worker PID; the complete original is retained locally.
BATCH/PUBLIC_INPUTS and the two executed code files preserve original bytes.
SOURCE_ONLY labels in code describe the preparation snapshot. This README records
the later approved execution, rather than rewriting executed source identity.
The empty original console log is retained locally; causal observer output is
recorded as original event JSON in REPORT, not a separately saved child stream.

Preservation/static review performed **no new comparison, import, syntax check,
test, build or CI**. E06 remains PARTIAL/OPEN; this is not generic AP2 conformance,
core completion, Phase2-A full PASS or production GO. It is separate from the
previous E06-CAUSAL-MBA-20261024-R1 observation of S01/price types and Agent rejection.

## Four inputs and expected causal facts

All original Root presentation, Agent terminal and Merchant Checkout signed wire
Strings are replayed exactly from the pinned saved public fixture. No private
key is read, generated, exported or persisted, and no signing helper is used.
Existing independent Python functions construct synthetic Host trust/selection/
challenge assertions from those public inputs; that model is not real Host
enrollment, nonce issuance/consumption, current order state or clock provenance.
The fixed synthetic evaluation time is retained, not replaced with today's clock.

| Name | Saved source | Independent expected result | Required Ruby observation |
| --- | --- | --- | --- |
| FULL | FULL | Issuer/Agent/Merchant valid; five Schema objects valid; exact research Evidence | Three signature calls return, Root graph and binding return, actual content check reached, constraints return before Evidence |
| QUANTITY_FLOAT | QUANTITY_TYPE | Checkout line quantity has literal2.0; official JSON Schema integer permits this mathematical integer, but strict profile requires a Ruby Integer; invalid_scoped_schema, no Evidence | All three signatures and binding return before content; quantity! raises at pinned source line93 |
| TOTALS_ONLY | TOTALS | Only Checkout total is201; price100 x quantity2, Host expected200 and line totals200 remain consistent; official Schema valid; amount_mismatch, no Evidence | All three signatures and binding return; content reached; totals! raises at pinned equality line109, rather than earlier product/Host amount check |
| BAD_MERCHANT_BEFORE_TOTALS | TOTALS plus saved WRONG_MERCHANT_KEY public PEM | Same exact TOTALS signed wires; Issuer/Agent valid, Merchant invalid against selected negative key; all five Schema objects remain valid; invalid_root_signature, no Evidence | Issuer/Agent return; Merchant raises; binding does not return; actual content check/exception absent |

The fourth case changes the selected external Merchant verification key, not the
Checkout signature bytes or Merchant identity. Its synthetic trust record PEM,
fingerprint, snapshot hash and challenge references are made self-consistent by
the existing independent Host model. This prevents a stale Host hash from
masking the intended Merchant signature rejection. It does not authorize a real
key registration. The model preserves tenant/profile/identity/purpose selection.
The independent verifier explicitly verifies the three saved original signatures
against each selected key. A signature failure is not called content rejection.

## Fixed reuse and independence

- Ten current product-source SHA256 pins are unchanged from PR182. The ordinary
  Ruby entry is loaded from the exact captured private temporary source tree.
- Public fixture: research/stage11/inputs/O2O5_PUBLIC_CASES.json, SHA256
  `be17fc33612ec561147100fbb901f5c2ef288d4535ed1aa69b56a61447fc8942`.
- Historical Schema judgments: research/stage11/archive/O4_VERIFIED_REPORT.json,
  SHA256 `f45e3b94c8434ab117acba8b94ca8bfb1e37dae42a2936fb2f5205c103dcdef8`.
  FULL, QUANTITY_TYPE and TOTALS were Schema VALID. Those old observations are
  preserved as historical controls, not relabelled as execution of this adapter.
- The selected original signature/graph oracle and test/o2o5_compare.py
  binding/subset predicates are loaded only after fixed hash checks, selecting
  explicitly named definitions. No old CLI/main/runtime pin is run or relaxed.
- research/stage15/compare.py contributes only its pinned profile constants and
  model/args/evaluate functions. Expected status/code/Evidence is authored and
  computed independently of Ruby output. No generator module or SDK is imported.
- All13 existing fixed Schema files and their Git blobs are authenticated;
  registered reference closure is checked with unknown-reference retrieval
  forbidden. Open/Closed/Merchant/Checkout/Item are independently validated.
  Every case must be Schema VALID. Optional format-bearing data is absent;
  this does not add general Schema or format support to the Gem.
- The comparator checks that the quantity is parsed as a float equal to2.0 and
  that other Checkout content equals FULL after replacing only that quantity.
  It separately checks that TOTALS differs only at Checkout total200 ->201,
  and that all four cases retain the same original Issuer Root wire.

observe.rb is the exact PR182 observer (SHA256
`a9c88dba1afedf0d94fc7d5f39704b5c050acff8c4403142aac49ae4b46b785b`).
Its forwarding wrappers record signature role/original-wire hash and
call/normal-return/raise, graph and purchase binding. Its TracePoint records the
unique first actual constraint check and the actual rejecting method/line/code.
Wrapper entry alone is not PASS. Missing/wrong-order/unexpected observations
stop as UNPROVEN. The source pin authenticates the line numbers used above.
Trusted harness/interpreter/temp tree/cooperative filesystem remain assumptions;
this is not malicious same-user or runtime attestation.

## Executed B bounds and remaining limits

The approved cap was one batch, exactly four Ruby children, each at most10seconds;
whole operation
at most300seconds, including environment checks, Schema/crypto imports,
independent evaluation and cleanup. No network, acquisition, install/build,
new Oracle, stress test or Actions. No runtime or dependency repair on mismatch.
Failure, timeout, unknown state, wrong identity or unknown cleanup means STOP;
no rerun, alternate output name or code-fix retry is authorized.

The reviewed PR182 standard subprocess controller is reused: worker allowance
296seconds with recovery reserve within300seconds; Ruby children inherit its
owned process group; each child is waited, and controller cleanup must be
confirmed before final COMPLETE. Existing output directory means STOP. A worker
completion marker is provisional; final output requires controller recovery.
No new monitor/runtime/download service is introduced.

Observed environment after matching preflight source/fixture/Schema pins:
CPython3.11.15 Darwin arm64 and the ten exact pinned Python distributions;
MRI4.0.9 Darwin arm64, JSON2.19.9/JWT3.3.0/base640.3.0/OpenSSL gem4.0.2/
Digest3.2.1/libcrypto3.5.9. Preflight and the successful batch confirmed these versions, without claiming
complete runtime/dependency supply-chain attestation. Individual child durations
were not separately recorded; the whole observed batch was under one second.

CLI inputs remain --source-root, --schema-dir, --ruby, --gem-home, --gem-path,
--out and the mechanical --execute-approved guard. No default discovery or
provisioning occurs. The source root must contain all fixed product, reference,
fixture, historical report and lock bytes; the three-file preparation directory
alone is not that root. Preparation A performed no execution. Do not run/import/--help/syntax-check again
without separate authorization.

The saved results record exact input/wire/helper/product/Schema hashes,
independent signature and Schema verdicts, actual causal events, code/Evidence,
versions, total elapsed time and owned-group recovery. All five Schema object
judgments are VALID for every case, including the signature-negative compound;
structural validity does not authenticate its Merchant signature. FULL produced
exactly expected Evidence; the other three produced none at their intended reject
sites. This remains LIMITED_OBSERVED, not E06 full PASS or core completion.
No CPU/RSS benchmark or performance guarantee is claimed.

Terminal300/301 is excluded because existing regressions cover it; no new
expiry experiment is added. Real Issuer/Host trust/current state/clock/revocation,
nonce/order atomic processing, payment, worst-case resources/concurrency and
historical communication-accounting gaps remain unproved. Public pre3 and
MBA/Linux package observations are separate immutable evidence, not rebuilt here.
