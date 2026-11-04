# 1.3.0 release candidate preparation

Status: implementation and verification in progress. **HOLD: no release recommendation yet.** RubyGems publication, formal v1.3.0 tag, GitHub Release and announcements require the Owner’s final approval. No production deployment or real payment is included.

## Proposed release notes

Ruby applications can retain the approved full Checkout Mandate while disclosing only the merchant and products needed for the purchase. Every required line group and quantity remains enforced, including overlapping product choices and multiple purchased lines. The same Ruby lifecycle can combine selective Checkout with selective Payment and authenticate their respective Receipts.

Existing complete Checkout and Payment profiles retain their APIs and defaults. The new Checkout profile requires explicit Host trust registration and explicit Payment issuance profile selection. It describes independent merchant/product candidate sets; correlated policies need separate Opens. Counts, ordering and issuer-JWT linkage remain visible. No general AP2 or official high-level Python facade conformance is claimed.

## Completion gates

- Exact source SHA and independent latest-HEAD review, with no unresolved substantive findings.
- Signed positive/negative/privacy/quantity coverage and all prior regressions on supported MRI versions.
- Official pinned Python low-level interoperability with independently checked expectations and explicit high-level limitations.
- CI on the reviewed HEAD; merged source tree equals reviewed tree.
- Build one candidate, inspect metadata/allowlist, install the same bytes offline under both supported MRI versions and compare every packaged file with source.
- Run standalone installed Checkout and combined Payment samples and optional demo.
- Record exact artifact size, SHA256, source and evidence before Owner GO/HOLD judgment.

## Publication procedure (not authorized yet)

After explicit approval of an exact candidate, recheck registry version absence and the approved artifact bytes/source/reviews/CI. The Owner can perform the single interactive RubyGems push using existing credentials and Docker. Never print credentials or retry an ambiguous push. Read registry metadata and download the published Gem, compare its complete bytes and payload to the approved candidate, then create the matching formal tag and GitHub Release only under the approved publication scope. Update published-state documentation after verification. Stop on any mismatch or uncertain mutation.
