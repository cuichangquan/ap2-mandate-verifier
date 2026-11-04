# 1.4.0 candidate preparation

**Historical prepublication record.1.4.0 is now public; see [verified publication](POST_RELEASE_140.md). Do not repeat its push or substitute a rebuilt artifact.**

Status: release candidate preparation. Final exact-source/package/CI evidence and GO/HOLD recommendation are recorded in the PR and external manifest after verification. RubyGems publication, formalv1.4.0 tag, GitHub Release, announcements, deployment and real payment remain HOLD for Owner decision.

## Proposed notes

Ruby applications can constrain a conditional Payment to approved PISPs and an inclusive execution window, bind its signed plan to independently trusted application provider/time context, and combine it with selective Checkout/Payment and Success/Error Receipts. Direct Payment binds exact approved PISP/date details. Existing1.x defaults remain unchanged.

This explicit profile supports strict parsed RFC3339 instants and exact PISP identity; it does not authenticate QWACs from strings, schedule payments, prove consent provenance or settlement. PISP/date conditions stay visible. Independent allowlists cannot express correlated provider/payment-method policies; separate Opens are required. Recurrence/budget remain unsupported.

## Final gates

Exact-source independent review with no unresolvedP1/P2; signed/context/date/crypto/SD/Receipt/privacy negatives; full regression and installed package verification under supportedMRI3.4.12/4.0.9; independent Python datetime oracle and pinned official SDK/Schema interoperability with discrepancies explicit; exactHEADCI; reproducible one-candidate archive and complete source/archive/installed file equality. Candidate source/size/hash, review/PR/CI links and GO/HOLD recommendation will be recorded externally to avoid self-referential checksums.

The fixed builder is existing MRI3.4.12/RubyGems3.6.9 with `SOURCE_DATE_EPOCH=1793750400`; build twice and compare complete archive bytes. Both supported MRI versions must install the same fixed-builder candidate. A different RubyGems builder may change metadata and must not be silently substituted. No checksum is embedded in its own package.

Only after Owner approves an exact candidate may publication begin. Recheck source/bytes/reviews/CI and registry absence immediately before a single owner-controlled interactive push. Never retry an ambiguous push; verify registry and downloaded bytes first. Formal tag/Release require matching published bytes and separately authorized release scope. No publish/deploy trigger may be introduced into CI.
