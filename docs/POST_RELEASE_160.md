# 1.6.0 publication and verification

Owner registered1.6.0 on **2026-11-05T10:41:57.496Z**. Fresh registry metadata reports `yanked=false`. The actual public archive, approved long-profile candidate and independently downloaded GitHub Release asset are byte-identical. [Machine-readable record](evidence/1.6.0_publication.json).

| Identity | Verified value |
| --- | --- |
| Gem/platform | ap2_mandate_verifier1.6.0/ruby |
| Bytes | 186,368 |
| SHA256 | `62de85123e1379c538c9c4302b71a9c55c590162591169a4e335aaa03a8991f8` |
| Released source | `964e572dc16d886561293cf90ddb9e2c927346bf` |
| Reviewed source | `98f7325a9dd0ee06739fe95e1306abe9b1c6ee5d` |
| Identical reviewed/merged tree | `c9a9faaec045a9854fded3c1b4db375332a5fa57` |
| Payload | All68 files match released source/archive/installation on both supported MRIs |

[Formal Release v1.6.0](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v1.6.0) is public, non-draft/non-prerelease. Annotated tag object `c79b396c02c6399a416b792351d3c3336ef1d81d` peels to released source; Release target_commitish matches. [RubyGems version](https://rubygems.org/gems/ap2_mandate_verifier/versions/1.6.0) metadata SHA and Release asset digest agree with actual downloaded bytes. Source association comes from full payload comparison, not a registry source attestation.

No agent Gem push, duplicate push, new version or replacement of published bytes occurred. Fixed-builder repeats and merged-source builds matched before publication. The earlier171008-byte bounded candidate (`f431c6584af2fda1cded9012424d8e428664036e2cd994c8e9fdb44de8a83843`) remains separately preserved; it is not this distribution. Packaged preparation text is a historical snapshot; repository follow-up documentation does not rebuild the released Gem.

## Tests and review

[Implementation PR249](https://github.com/cuichangquan/ap2-mandate-verifier/pull/249) passed independent final-HEAD review and [both MRI CI jobs](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/42002133295). One P2 concerning the fresh execution deadline was fixed before final review and causally tested against both returned handle and stored deadline. No substantive P1/P2 remained unresolved.

Both supported MRI3.4.12/4.0.9 ran source and installed candidate regressions. After publication, isolated network-disabled containers installed the ACTUAL downloaded public archive, matched all68 payload files to released source and installation, and passed all installed regressions/examples. Each MRI passed162 long-wire assertions,75 long-acceptance assertions and376 independent process checks, in addition to existing suites. Both README quick starts and the guide suite, including the installed12-month example, also passed against the actual public archive without a product-source overlay. Repeated transitive tests are not summed.

Eight independent processes exercise same-period, count-only and budget-only races. ActualSIGKILL/restart, fsynced mock effects, transaction rollback, wrong-period first attempts, Root/Issuer/Agent rotation, authority invalidation/revocation and original late Receipt reconciliation are covered. Installed examples complete12 mock starts ofJPY8000, totaling96000 within100000. These are synthetic single-host checks, not real payments or a distributed exactly-once proof.

Pinned official Python SDK comparison on the identical candidate/archive used12 months each direction,48Receipts and35 signed negatives, actual SDK KB constructors/facade calls and explicit Enum/profile/integer-JPY/inline adapters. That prepublication interop evidence applies to identical bytes; it was not relabeled as a new postpublication run. Python's fixed100xJPY budget conversion, missing frequency evaluation and weaker proof-age behavior remain documented disagreements, not aggregate-policy parity.

## Public integration and limits

[LongPayment API, schedule, authority and migration contract](LONG_PAYMENT.md), [12-period Ruby example](../examples/long_payment_acceptance.rb) and [bounded ON_DEMAND profile](RECURRING_PAYMENT.md) describe the release. Existing1.x defaults, seven-input contract and old600/7200second profile limits remain unchanged; new optional schema3 is explicitly selected and does not migrate schema1/2 history automatically.

UTC calendar windows and exact integerJPY are explicit Host/profile decisions, not generic AP2 MONTHLY semantics. Complete long profiles do not add selective/PISP/date combinations or other currencies/timezones. The application authenticates consent/current trust and synchronizes it into one protected authoritative ledger, supplies stable occurrences and nonce/order CAS, dispatches promptly within the short execution deadline, and provides processor idempotency/query and settlement. Unknown/Error/crash never automatically refunds allowance or grants retry execution. No external revocation feed or remote exactly-once guarantee is supplied.

No production connection, real payment, host software installation, credential/security/protection change or public announcement was performed.
