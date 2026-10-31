# 0.3.0 candidate — release notes draft

Unpublished. Owner approval is required before RubyGems push, public tag/GitHub Release or Web deployment.

**Previous candidate withdrawn:** the 37,376-byte archive SHA256 `5de6907cfcf0565ddaba1385b1d38ae113cc5e26d52259d769030237378a48a8` must not be published. A GitHub Codex review arrived after PR218 merged and exposed unregistered Result codes in builder error handlers. Those handlers raised ArgumentError instead of returning a failure Result. The replacement reuses existing registered codes and tests the public verify failure paths, including dependency failures, rather than testing assembly exceptions alone. Earlier no-findings reviews and passing124 installed cases did not cover these paths and do not validate the withdrawn archive. Replacement source/artifact identities require fresh validation and review.

Adds InputBuilder: explicit authenticated registry and order information become bounded fixed-profile verification inputs without hand-written internal JSON/hashes. Preparation, exact persistence restoration and current-state assembly are separate; full verification remains mandatory. Existing seven-input APIs, fixed AP2 source/profile, Result/Evidence v2, MRI 3.4.12/4.0.9 and five pinned runtime dependencies are retained.

The runnable comparison includes initialization, persistence and current-state handling: 64 nonblank/noncomment Ruby lines before and42 after; four caller SHA256 calculations before and zero after. These are measurements of the supplied synthetic examples, not generalized productivity percentages. Explicit business mapping and Host freshness/authorization duties remain. See INPUT_BUILDER.md and INPUT_BUILDER.ja.md.

## Task authority and review scope

Owner's 2026-10-31 task-specific written delegation authorizes design/implementation, dedicated Docker preparation, fixed dependencies, tests/retries, Draft PR, independent Codex review and conditional Squash Merge after latest-HEAD checks and zero unresolved substantive findings. It supersedes historical per-file/per-run gates for this release only. Existing research STOP evidence, real Issuer/Host/payment/production/Phase2B HOLDs remain. No Mac installs or shared-cache/container changes. GitHub task Issue creation was blocked by automatic approval review interpreting it as external publication; it was not executed or retried. This local record preserves scope while independent work continues.

Independent Codex review found two P2 graph-boundary defects (identity-Hash duplicate collapse and unbounded Integer conversion); both were fixed at the shared copying boundary and given regressions. Subsequent read-only re-review returned no findings. Exact final review SHA and measured artifact identity are recorded outside the packaged payload after finalization.

## Validation method

Dedicated official bookworm images, Debian12/arm64: MRI3.4.12 and4.0.9, JSON2.19.9/JWT3.3.0/base640.3.0/OpenSSL gem4.0.2/Digest3.2.1, Bundler4.0.20. Source regression runner retains existing independent authored/signed oracles; builder suite adds109 cases without double-counting its reused Host149. Installed-Gem harness ordinarily installs the same archive, compares every payload file, loads11 product Ruby files and checks134 cases (existing118 + builder16), using saved Stage15 input/expected identities and business examples. Tests run network-none with1CPU/512MiB/PIDs128/300s. Setup uses2CPU/2GiB/PIDs256/600s. Actual runtime/provider fingerprints and logs are retained in task evidence; past PASS is not reused.

No real Issuer, revocation source, real Host, payment, performance SLA or production GO was validated. Evidence remains checked facts, never purchase permission. Unknown new storage/profile versions require explicit supported migration or reissuance, not automatic reinterpretation.

The corrective candidate additionally preserves typed crypto-provider unavailability before the broader rejection rescue, treats JSON version mismatch as dependency unavailability, and validates all role-selector shapes before dereferencing them. New tests call verify with malformed inputs and injected dependency failures, exercise trust/restore_trust/prepare provider failures, and mutate caller-owned trust/order/selector/signed/saved inputs after assembly. Existing Result::CODES is unchanged. GitHub PR218 discussion4429729387 records the original finding; closure requires the corrective PR and its latest-HEAD review, including late-arriving GitHub feedback.
