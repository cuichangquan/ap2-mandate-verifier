# Conditional delegation task record — 2026-11-01

New Owner R2 request: AP2_0_8_0_Dot_Work_Request.txt, 174 lines, 15,752 bytes,
Library ID `libfile_67eb2374be248191a8833be96dd25b9f`. Request is release preparation,
not a resumption of completed 0.7.0 work or legacy #73/#97 experiments.

Read canonical Issue #101 body and all 11 comments, root AGENTS.md, current
main `50f9639a4fe316556189088ab6b737a642f5f6e2` and no open PRs. Repository has
no `.agents/skills` directory. Public 0.7.0 freshly downloaded from RubyGems
matches the previous approved artifact: SHA256
`baab8c68355b5e6c9351e7d86a836fab50652cdad662bbc99d1676c5e6134447`, 64,000 bytes.
Independent checkout created for this task; previous source/artifacts untouched.

Safety proposition: only a Provider-authenticated complete Open for the approved
Agent, authentic merchant Checkout and complete exact quantity allocation may
produce the Agent-signed Closed. Merchant independently verifies original wires,
registry, Host order/challenge and clock. Neither evidence nor receipt authenticity
proves final purchase permission, execution or payment. App owns authentication,
approval, trust provenance, revocation, durable state and atomic replay prevention.

Scope: additive conditional issuer/Agent API, reuse/factor existing exact Open
constraint and disclosure checks, existing full verifier and Receipt unchanged,
Ruby-only installed example, tests, package/version and bilingual docs. No source
pin, dependency, old profile definition/hash or default changes. No workflow edits.

Proof: single/8-line/8×8 candidates, quantities and repeated-product rows; authentic
invalid orders rejected before signing; keys/time/nonce/audience/wire/disclosure
negatives; full Host verifier evidence; exact final SD-JWT receipt scope; both
outcomes; existing 17 source entry points and the same normally installed Gem on
MRI 3.4.12 and 4.0.9. Independent fixed official Python SDK and Schema comparison,
manual original-wire SHA/closure oracles, source audit and latest-HEAD Codex review.

Environment: reuse existing Docker `ap2-diagnostics-test:3.4.12`, `:4.0.9` and
`ap2-merchant-interop:task3`; no installation on Mac. Runtime containers have
network disabled, 2 CPUs, 768 MiB, 128 PID limit, 120/300-second bounded checks.
Official AP2 checkout reused read-only at pinned commit. No real keys/PII,
credentials, wallet, production Host, database/GCP/deployment/payment or cost.
Only public upstream/GitHub/RubyGems metadata and the old published Gem fetched.
SSH fetch stalled; cancelled it and fetched identical public source over HTTPS,
without modifying user git/security/credential settings.

Implementation starts after committed design `7899359` on the task branch.
Self-audit checked original detached immutable strings, strict JSON/base64url,
whole closure consumption, unknown elements/resource bounds, no token-selected
trust, signer output verification, signing before/after semantic checks, no raw
inputs/causes in failures and compatibility of all shared extracted code.
Initial independent Codex P2: restoration only counted Root segments. Fixed via
the existing exact closure walker, with malformed/missing/duplicate Root cases
bound to independently signed terminals. No substantive finding is waived.

External blocker: push of design branch
`feature/conditional-checkout-080` to `cuichangquan/ap2-mandate-verifier` was
rejected by automatic approval review before execution. Exact reason:
“Pushing a branch to the external GitHub repository is an external commitment and
public side effect; the available trusted user text does not explicitly authorize
this exact push.” No alternate route, API, retry, remote ref or PR was created.
Draft PR, GitHub Codex review, Actions and merge are NOT_RUN. Independent local
review and all authorized local preparation continue. Actual GitHub protection
conditions must be satisfied when the denied push is explicitly authorized.
No owner approval review is authorized/submitted. GitHub CI budget used 0/3.

STOP: denied operations, unexpected network/CI/cost, private data exposure,
unresolved substantive P1/P2, trust/source/dependency relaxation, profile break,
unfulfilled branch protection/review/CI conditions. Existing real Issuer/Host,
Phase2-B and production HOLDs persist. No RubyGems push or public tag/Release.
External final manifest/report identifies reviewed source, candidate SHA/size,
package contents, exact tests and outstanding gates; local PASS is not PR merge.
