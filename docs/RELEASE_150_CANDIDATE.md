# 1.5.0 release candidate preparation

Historical preparation snapshot: Owner subsequently approved publication; [actual distribution and release verification](POST_RELEASE_150.md). Production connections and real payments remain outside scope.

Release candidate preparation; final exact-source/artifact/review/CI evidence is recorded in the PR and external manifest. RubyGems/public tag/GitHub Release/production connection/real payment remain HOLD pending Owner decision.

## Proposed notes and main use

1.5 adds opt-in transactional Payment acceptance: enroll a protected business occurrence, verify raw Mandates, reserve atomically, reverify before one fenced start and reconcile the original Receipt after uncertain outcomes. Re-signing does not create a new operation. Separately authorized new occurrences are supported without globally consuming every Open Mandate. Existing1.x verifier APIs/results and base runtime dependencies remain unchanged; SQLite reference persistence uses an optional pinned driver.

```ruby
accepted = service.accept(**trusted_scope, mode: :conditional, verification_inputs: raw_inputs)
dispatch = service.start(ticket: accepted.ticket, verification_inputs: fresh_inputs) if accepted.ticket
# Application-owned processor call reuses dispatch.processor_key; no SDK payment call.
```

State reservation, verification and settlement are distinct. No automatic release/takeover after timeout, Error Receipt, worker crash or response loss. Stable Host identity, protected enrollment, one authoritative durable store and processor lookup/idempotency remain application requirements. Receipt authenticity is not proof of settlement. Custom adapters need their own atomicity/durability tests.

## Final gates and publication procedure

Full supported MRI3.4.12/4.0.9 regressions; optional-driver absence isolation; source/installed acceptance tests; independent multi-process barrier/external counter/SIGKILL/restart and re-sign/new-occurrence controls; schema/commit/Receipt/expiry/privacy negatives; exact-HEAD independent review with zero unresolved P1/P2; Draft-first PRs, successful CI and verified merged-tree equality; candidate package metadata and every source/archive/installed file identical. Fixed builder/source-date epoch must reproduce the same archive; both MRIs install that one archive. Evidence/checksum remain outside their own package.

Only after Owner approves an exact candidate may publication begin. Recheck registry absence/source/bytes/review/CI; no blind retry of uncertain writes. Verify downloaded published bytes before formal tag/Release. No publication or deployment CI trigger may be added.
