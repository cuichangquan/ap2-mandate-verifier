# 0.7.0 release candidate — NOT PUBLISHED

Compatible feature release for Trusted Agent Provider / Direct Human Present
Checkout. Supports merchant signature verification before approval, backend
issuance, Agent presentation, merchant Direct verification and whole-wire
Success/Error Receipt verification with 1–8 lines and multiple products.

[Contract](BUYER_DIRECT_CHECKOUT.md), [runnable example](../examples/direct_checkout.rb),
[PR #229](https://github.com/cuichangquan/ap2-mandate-verifier/pull/229),
[execution/approval record](BUYER_TASK_RECORD.md).

## Verification and review

Offline Docker source regression and ordinary Gem install/content equality on
MRI 3.4.12 and 4.0.9; approved pinned dependencies unchanged. Single SKU and
multi-item legacy APIs/Result/Evidence/save formats retain their contracts.
Direct positive 3/8-line, repeat product and reordered order cases plus both
Receipt outcomes are checked. Authentic hostile malformed Checkout inputs,
wrong keys, altered signatures, substitution, expiry/future time, missing/extra
SD disclosures, unsupported combinations/profile and input bounds reject.

Fixed AP2 commit `b4587ac1d055888a73b4b21750973cffba961793`: Ruby issuance
verified by official Python SD-JWT implementation; SDK issuance verified by Ruby,
including eight lines. Independent SHA256 and both commitment edges, original
Schema and bidirectional signed Receipts checked. Existing independent allocation
comparison remains 288 cases, including 139 expected SDK shortage disagreements.
Receipt reference includes exact disclosures and terminal `~`; the compact-only
SDK helper differs and its hash is rejected. No verification bypass is used.

Independent latest-HEAD Codex review and unresolved thread 0, actual main scope,
CI and all branch rules are required for conditional squash integration. GitHub
review results/run URLs and exact integrated commit are in PR #229; the final
external candidate manifest identifies the built Gem SHA256/bytes and source
commit, without a self-referential hash in package contents. Do not publish a
rebuilt lookalike; verify exact bytes and ordinary installed payload equality.

## Publication remains an Owner decision

1. Review final source, independent review, run results and candidate manifest.
2. Decide whether to publish that exact verified Gem. This task creates no public
   tag or Release and makes no RubyGems push.
3. Only with separate explicit publication approval, publish and independently
   compare registry bytes/source/tag. Update stable docs/demo after availability.

Authentication/purchasing authority/approval record integrity, independent key
registration and lifecycle, persistent order/approval uniqueness and atomic
transitions, uncertain-outcome reconciliation and payment remain app duties.
The example uses memory/Mutex and synthetic acceptance, not durable production
state or actual payment. Open/Agent Closed issuance remains a later candidate.
No demand proof, general AP2 conformity, real Issuer trust or production safety
claim follows from these synthetic tests. Current published version is 0.6.0.
