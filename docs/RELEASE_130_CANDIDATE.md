# 1.3.0 release candidate preparation

Status: release candidate prepared; final evidence and GO/HOLD judgment are tracked in [Issue #241](https://github.com/cuichangquan/ap2-mandate-verifier/issues/241). **Publication remains HOLD pending the Owner’s final decision.** RubyGems publication, formal v1.3.0 tag, GitHub Release and announcements require the Owner’s final approval. No production deployment or real payment is included.

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

## Observed local verification

The implementation has passed the full source regression suite under MRI 3.4.12 and 4.0.9, including 95 new selective Checkout assertions. An initial candidate passed ordinary offline installation on both versions with all 49 files matching source/archive/installed bytes, plus installed standalone and combined examples. Official pinned Python low-level interoperability passed two scenarios in each direction, eight Receipt checks and 28 negative controls, both from source and an ordinary installed Gem under Ruby 3.4.12 / Python 3.11.2.

The fixed candidate builder uses MRI 3.4.12, RubyGems 3.6.9 and `SOURCE_DATE_EPOCH=1793750400`. Two builds under that builder matched byte for byte. MRI 4.0.9’s RubyGems 4.0.20 changes the `rubygems_version` metadata; its payload was identical, but that independently built archive is not the approved candidate. Both supported MRIs must test the same fixed-builder archive. After any packaged source change, rebuild and repeat its package equality checks. Exact final artifact hash, merged source, latest review and CI links belong in the tracking issue/external manifest to avoid a self-referential package checksum.

## Publication procedure (not authorized yet)

After explicit approval of an exact candidate, recheck registry version absence and the approved artifact bytes/source/reviews/CI. The Owner can perform the single interactive RubyGems push using existing credentials and Docker. Never print credentials or retry an ambiguous push. Read registry metadata and download the published Gem, compare its complete bytes and payload to the approved candidate, then create the matching formal tag and GitHub Release only under the approved publication scope. Update published-state documentation after verification. Stop on any mismatch or uncertain mutation.
