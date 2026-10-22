# Stage15 local MBA comparison — LIMITED_OBSERVED

This directory is a new local candidate, not a rewrite of Stage11 originals,
source pins, reports or acquisition history. The Owner approved publication of
this bounded comparison and its results; production/distribution remain HOLD.
Candidate main: `7635ea59ddd7027fa929e164d68f796a56fbca66`; source tree
`2fb95e9c8eb32e47dfffafe759ddf19bda9006e0`. `candidate.json` fixes all 10 Ruby
source files. Its digest is pinned in compare.py, as is the reused Python binding
adapter. Existing original signed Oracle, public fixture, dependency locks,
runtime identity and 13 Schema identities retain their reviewed pins.
The integration review found that Python optimization could remove assertion
gates. The current adapter rejects -O/-OO/PYTHONOPTIMIZE before loading inputs or
creating artifacts. R3 records the historical adapter; the corrected run is R5.

## Proposition and observation

For the 30 explicitly constructed public synthetic contract cases, independently
computed Python rejection reasons and normal Evidence facts match the same Ruby
candidate. Python jwcrypto verifies the original signatures; the independent
original graph walker and binding/subset predicates are reused without invoking
Ruby to determine expected values. Host trust/selection/challenge predicates and
the max-start/min-exclusive-end interval are independently authored in Python.
The observer only supplies actual Ruby outcomes and entered method sequences.
Entered wrapper methods are reachability, not proof of each stage passing.

The six Root classifications FULL/HIDDEN/UNKNOWN/DUPLICATE/EXTRA/DECOY are included.
Other signed controls cover Agent key/signature, Root binding, nonce, Merchant
signature, signature-valid S01 and amount/totals. Host controls cover consumed and
expired challenge, inclusive start, shortened challenge/key lifetime, split Buyer
and order version, rebound tenant/Root/Agent, revoked/expired/ambiguous/unknown key,
revoked snapshot and unknown profile version. Four normal cases produce exact
immutable Evidence v2; the other 26 produce no Evidence.

Twelve logical probes cover over-limit Root/trust (131072 B), terminal/Host
(32768 B), Checkout/selection (16384 B), Host depth24/25, duplicate keys, BOM,
wrong input type and a Host input exactly at its byte cap. At-cap/depth24 values
are still rejected by subsequent shape checks; they are not valid transactions.
The remaining disclosure/node/key/body/quantity limits retain existing regression
coverage and are not all independently re-probed here.

Eight additional official Schema judgments authenticate FULL and S01 first, then
validate disclosed Open, Closed, Merchant and Checkout against the existing
13-file local Registry. FULL is valid in all four; S01 Open is invalid, the other
three valid. No format dependency or remote ref retrieval is permitted. This does
not turn the Gem's narrow profile into a general official Schema validator.

## Execution and evidence

Use the existing task Python venv (CPython3.11.15/Darwin arm64, ten fixed deps),
Ruby4.0.1/JSON2.18.0/jwt3.3.0 and already acquired Schema directory. No install,
network, custom runtime or OS isolation is involved. Run from this repository:

```python
# Run with the existing task venv Python. Destination must be new.
import subprocess, sys
subprocess.run([sys.executable, 'stage15/compare.py', '../ap2-stage15-results-R3'],
               timeout=300, check=True)
```

Each Ruby child has a 10-second subprocess timeout and the enclosing command has
a 300-second timeout. The script also tracks the remaining whole-run budget.
Run optimization_test.py without optimization to check four optimized invocation
rejections. Optimized execution is unsupported, never a successful comparison.
`INPUTS.json` preserves each exact Gem input; REPORT.json binds its hash, source
manifest, observer, Python adapter, original fixture, Oracle, dependencies and
Schema identities to expectations and observations. New results use separate
R1/R2/R3 directories; older results are not overwritten. Existing885 regressions
and syntax checks are separate from these 30+12+8 observations.

The trusted harness captures bounded source bytes matching the reviewed manifest,
writes a private temporary tree, and loads its normal Gem entry. The harness,
manifest pin, interpreter, dependencies, OS and temp directory remain trusted.
This is not hostile same-user/process attestation or signed remote Evidence.

## Limits and HOLDs

The public signed fixture's Open expires before terminal.iat+301; the latter is
included in the independently computed minimum, but is not independently isolated
as the limiting expiry here. Existing Ruby regression checks cover 300/301.
Only these constructed Host shapes/fields are independently compared; unknown
algorithm/PEM/record-shape variants retain prior regression coverage rather than a
new complete Python implementation. Fixtures, profile definitions and cryptographic
design/providers are shared assumptions despite separate Ruby/Python code paths.

Elapsed times and logical bounds are local observations, not hard CPU/RSS,
parallel-load or product denial-of-service guarantees. Other-environment replay
is NOT_RUN. Real Issuer/Host authority and clock provenance, latest trust/order/
challenge atomic recheck, nonce consumption/order CAS, payments, general Schema/
all constraints, Stage7 final acceptance and Stage16 GO remain unproved/HOLD.
Historical acquisition measurement defects (O1/O3 metadata-inclusive total10MB;
O4 sent-header-inclusive1MiB) remain unproved; no acquisition was repeated.
Evidence v2 is research output, not Host ALLOW. Production, Gem distribution and
Phase2B remain HOLD. No Actions or other host runs were performed. See
PUBLICATION.md for the unchanged R3 artifacts and the integration audit.
