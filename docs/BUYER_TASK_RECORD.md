# Buyer task execution record — 2026-11-01

Owner request: https://chatgpt.com/space/page_7b2af449e6e881919e7fbc0af874b863
New independent R2 task, not continuation of the completed 0.6.0 release or a
resumption of legacy Issue #73/#97 research. Owner additionally required ③'s
single-merchant multi-product/multi-line coverage end to end.

Start read: actual main `9078f262a5dc6cd54afee0e1f87875d8336d4471`, published
v0.6.0 source `baee59a603d08123adc0af50e57c8710ea62f4f9`, no open main-repository
PRs at initial REST query. Read root AGENTS.md, canonical Issue #101 body and
11 comments, existing multi-item/signing/Receipt contracts and pinned SDK/spec.
No repository `.agents/skills` directory exists. Historical session directories
were not inspected. Existing Docker images are reused; no host installation.

Safety proposition: only a trusted Provider signature over an exact Closed
Checkout and full required disclosure graph, an independent merchant signature,
exact current merchant order bytes and explicit time window can produce Direct
verification. Human identity/authority, persistent replay prevention, current
order policy and final outcomes remain application responsibilities.

Scope: additive library buyer/Checkout verification and Direct Receipt syntax,
existing ES256 primitive reuse, product tests/interop, runnable example, package
and docs. Preserve existing 2profile contracts and old Result/Evidence/saved data.
Proof: independently verified SD commitments and hashes, official Python root
SD-JWT both directions, original Schema, causal negatives, 3/8-line end-to-end
and both Receipt outcomes, existing full regression and installed candidate on
both supported MRI versions, source audit and latest-HEAD independent Codex review.

Plan: document Direct contract → implement issue/present/receive/Receipt →
negative/compatibility/interop acceptance → self-audit → draft PR → independent
latest-HEAD review/fixes → protected conditional squash merge → exact unpublished
candidate build/install/hash evidence. This task's explicit Owner scope authorizes
Docker/development dependencies, tests, existing CI, draft PR/review and conditional
squash merge; it does not authorize submitting an approval review as Owner.

Execution: offline containers `--network=none --cpus=2 --memory=768m
--pids-limit=128`, individual checks bounded by timeout 120/300 seconds. Existing
CI `merchant-source-package.yml` has two MRI jobs in one workflow run; inspect
all path triggers before PR. Maximum 3 workflow runs per PR, no unconditional
failed-run reruns or changed triggers. No costs, new credentials or security
settings. Retain pinned official AP2 source. No publications/tags/releases,
deployments, real Issuers/wallets/payments or unrelated legacy HOLD resumption.
STOP on permission denial, unknown side effects/cost, exposed secrets, unresolved
substantive P1/P2, incompatible API/source upgrade, unfulfilled protection or
review/CI budget. Never bypass protections or claim review as safety proof.

Initial checks: Direct basic Ruby tests and Python interoperability PASS. Multi
acceptance and complete regression/candidate validation are recorded separately
once final candidate identity is fixed; working-tree results are not final-HEAD
certification.

Self-audit: bounded original strings and strict JSON/base64url, no token-selected
trust or network, full disclosure commitment consumption, no auth boolean,
independent expected Checkout, every line arithmetic, explicit time/expiry,
unchanged legacy profile code, fixed error messages/no causes and no secret logs.
Whole-wire Receipt hash includes original disclosures and trailing separator.
Example now returns the same issuance for duplicate approval and the saved
Receipt for duplicate order; uncertain outcomes remain held. Persistence remains
explicitly app-owned. No workflow changes. Static trigger inspection matches
only Merchant source and package for these product paths, two jobs/one run.

Independent Codex static review of `d6691ba6dc14be599034ce338674ac781a6f96d7`
found one P2: mixed String/Symbol keyword sorting escaped the public failure
contract. Replaced it with key-set checks and added all-three-entry negatives.
No other substantive findings. Latest-HEAD re-review is required after these
changes. No Owner approval review has been submitted.

First PR CI: [41266393844](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/41266393844),
HEAD `d6691ba6dc14be599034ce338674ac781a6f96d7`, attempt 1, success on both MRI
jobs; 1/3 workflow-run budget consumed. Existing branch ruleset 25055863 requires
PR and squash, forbids deletion/non-fast-forward; no Owner approval review count
is required. Protections are not changed. One cohesive PR keeps the authoring,
receiving and Receipt grammar reviewable together instead of exposing an issuer
that the receiver cannot verify.
