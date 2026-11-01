# 0.8.0 candidate — conditional Checkout delegation, unpublished

Compatible feature release preparation for approved conditional purchasing:
`ConditionalCheckout.issue_open` → Agent `.issue_closed` → `.present` → existing
full `InputBuilder.verify` → `CheckoutReceipt.sign/verify`. The installed
[standalone example](../examples/conditional_checkout.rb) uses A/B×1 and C×2,
three rows and repeated C products. [API/specification](CONDITIONAL_CHECKOUT.md).

Published stable remains 0.7.0, verified from the official RubyGems versions API
on 2026-11-01; 0.8.0 is absent, so no version-plan collision is currently observed.
0.7.0 source/tag is `9b4b78a7ed9aa95e7d35e01a64efc1281ba95be3`; its published
64,000-byte SHA256 is `baab8c68355b5e6c9351e7d86a836fab50652cdad662bbc99d1676c5e6134447`.
Current base main is `50f9639a4fe316556189088ab6b737a642f5f6e2`, initially no open PRs.
No verified prior artifact or previous task checkout was modified.

## Validation and compatibility

All 17 source-suite entry points pass offline on MRI 3.4.12 and 4.0.9. Existing
regression includes Direct, both old profiles, signed missing/unknown/duplicate
disclosures, original-wire binding, InputBuilder save/restore, Result/Evidence,
diagnostics and Receipt outcomes. New tests add 8 cases / 123 assertions for
issuance, sign-before-check prevention, bounds, 8×8 candidate/requirement cases,
same-product separate rows, wrong keys/time/audience/nonce, restoration closure,
and exact final Closed Receipt reference. A long-ID/title eight-row Checkout
also completes through the larger existing Agent-terminal bounds while Merchant
JWT and Direct signing bounds remain unchanged. Suite counts include shared legacy
dependencies; no misleading aggregate of repeated assertion counters is claimed.

Official pinned Python comparison passes for signatures in both directions,
Open/Closed/Checkout/Receipt Schemas, complete Open commitments and normative
sd_hash including final `~`, both receipt outcomes and negative controls. SDK
high-level Closed helper emits an unsupported SD form; it is a rejection control,
not claimed accepted interoperability. Existing max-flow shortage/empty-candidate
differences and compact-only Receipt helper remain documented and fail closed.

Candidate Gem identity, corresponding final source SHA, payload hashes, byte size,
ordinary installation on both Rubies and exact example output are recorded in the
external candidate manifest beside the Gem. The Gem includes both READMEs, this
decision document, the API contract and the standalone example. Dependencies and
supported MRI versions are unchanged; old callers require no migration.

## Review and external-operation status

Initial independent Codex review found one substantive P2 (restoration Root
closure); fixed through shared structural parsing and signed negative regression.
GitHub review additionally found that the Merchant signing helper's 12,000-byte
claims / 16,384-byte JWS limits prevented valid larger Agent terminals. KB terminal
signing now uses its existing verifier's 24,576-byte payload / 32,768-byte wire
bounds only; JWT and Direct retain the old limits. Long-ID/title eight-row Ruby
and official Python signature/Schema/hash regressions exercise this fix.
Latest-HEAD independent review must be completed and identified in the external
verification report. Review no-findings alone is not a security proof.

Initial Draft PR branch push was denied by automatic approval review before
execution. Owner subsequently explicitly authorized the specified commit/branch
push, Draft PR, existing-budget CI, latest-HEAD Codex review/fixes and conditional
Squash Merge at 2026-11-01 14:41 JST. The branch was pushed and
[Draft PR #231](https://github.com/cuichangquan/ap2-mandate-verifier/pull/231)
created. No alternate route bypassed the denial; authorization resolved it first.
No owner approval review is submitted. Current exact-HEAD review, CI and merge
results are recorded in that PR and the external final verification report.
Only existing `merchant-source-package.yml` is expected to trigger for this diff:
two MRI jobs in one workflow run, existing Ubuntu runner/15-minute job timeout,
public dependencies, no secrets, extra cost zero. No workflow edits. Issue #101's
maximum 3 runs/PR is a ceiling, no blind reruns; the PR records every consumed run.

## Build and final candidate evidence

Use the final committed tree, existing pinned Docker images and no network:

```sh
gem build ap2_mandate_verifier.gemspec --output /out/ap2_mandate_verifier-0.8.0.gem
sh scripts/check_candidate_package.sh /out/package /out/ap2_mandate_verifier-0.8.0.gem
```

Run source regression with `sh scripts/check_ruby_compatibility.sh /out/source`.
The packaging script installs the **same** built Gem with normal RubyGems
resolution (`gem install --local`), audits every source/archive/installed payload,
then executes detached old APIs and the example physically inside the installed
Gem. Reuse one artifact across both MRI runtimes. Do not substitute an earlier
working-tree package or rebuild a lookalike after approval. Exact source SHA and
Gem SHA cannot be embedded recursively in their own bytes; use external manifest.

## Publication decision and recovery plan

1. Review final source SHA, strict latest-HEAD review, all tests/independent
   comparison, exact candidate manifest and remaining GitHub PR/CI gates.
2. Obtain separate Owner authorization for that exact Gem publication; **no push,
   public tag or GitHub Release is authorized by this request**.
3. After explicit authorization only, RubyGems push the approved exact artifact,
   fetch the official distribution and compare bytes/SHA/size and every payload.
4. Only under publication/tag/Release authorization, bind `v0.8.0` to its verified
   source, publish release notes and update stable install guides/demo after the
   registry version is actually available. A candidate README is not publication.
5. On mismatch, invalid dependency/content, signature or material regression,
   stop rollout and retain evidence. Do not overwrite a published version; assess
   scoped yank/patch publication with separate Owner decision. Keep 0.7.0 install
   guidance until the successor is independently verified. Preserve original
   saved mandates/challenges; do not reinterpret them under a changed profile.

Limits: one merchant/Checkout, all candidates disclosed, ES256/P-256, exact finite
profile, no real Issuer trust/production Host proof. Authentication/consent,
revocation/key lifecycle, persistence/CAS/nonce consumption, execution and payment
remain app responsibilities. Payment Mandates, budgets, repeating/split orders,
User Credentials and tax/shipping/discount engines remain out of scope.
Production/real wallet/payment/deployment, RubyGems push and public tag/Release
are NOT_RUN. Release readiness requires the final exact-HEAD PR/review/CI and
package gates; the external report records their actual completion state.
