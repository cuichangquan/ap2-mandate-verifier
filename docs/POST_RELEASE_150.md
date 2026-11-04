# 1.5.0 publication and verification

Owner registered1.5.0 at **2026-11-04T13:05:50.125Z**. Fresh official metadata and the actual public distribution confirm publication. [Machine-readable record](evidence/1.5.0_publication.json).

| Identity | Verified value |
| --- | --- |
| Gem/platform | ap2_mandate_verifier1.5.0/ruby |
| Bytes | 160,256 |
| SHA256 | `9fdd419d031ff10b17c5a9bf31afc74a5f03a70cdcb442d7b4c561f6f90f1802` |
| Released source | `29db1b269f08b59dd4da210c1fa374d14d9df48d` |
| Reviewed source | `456ecd634b76fb05cabd37da9c05c1662b462f07` |
| Identical reviewed/merged tree | `d5cae07d62c51a02dbdf8bd459d175b74a9d4de3` |
| Payload | All58 source/archive/installed files match on both MRI endpoints |

Approved candidate, actual RubyGems download and independently downloaded GitHub Release asset are byte-identical. Registry metadata and Release asset digest agree. This associates source through full payload comparison, not a registry source attestation. No agent Gem push, rebuild, version overwrite or duplicate push occurred. Repository documentation updates do not change the released archive's historical preparation snapshot.

## Formal tag and Release

[Release v1.5.0](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v1.5.0) is public, non-draft/non-prerelease, published2026-11-04T13:15:57Z. Annotated tag object `2c1bea827efac8af59f4a1dd0ada9359d12c2fe9` peels to the released source; Release target_commitish matches. Attached `ap2_mandate_verifier-1.5.0.gem` matches the approved/registry bytes.

## Tests and interoperability

[Implementation PR246](https://github.com/cuichangquan/ap2-mandate-verifier/pull/246#issuecomment-6630710969) records independent exact-HEAD review with no unresolved substantiveP1/P2, [successful CI](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/41828953439), full source/installed regressions,84acceptance assertions and95independent process/crash checks per supportedMRI3.4.12/4.0.9. A schema-validationP2 was fixed before final review. Repeated transitive suites are not summed.

After publication, isolated containers installed the ACTUAL public archive on both supported MRIs and passed all installed tests/examples with all58payload files equal to released source. Eight fresh processes race for one Ticket/one durable mock effect; realSIGKILL before acceptance permits one later start, whereas crashes after reservation/start/effect never produce a second start. Re-signing, changed terms, authorized new occurrences, original-wire Receipt recovery and post-expiry reconciliation are exercised. These are synthetic single-host checks, not real payment or a distributed exactly-once proof.

Actual installed publicGem wire interoperability uses official pinnedAP2 `b4587ac1d055888a73b4b21750973cffba961793`: three lifecycles each direction,12Receipts,62negative checks. Six weaker upstream date outcomes remain documented. This is scoped low-level signed-profile adapter interoperability; the official SDK does not validate this application-side acceptance protocol or provide generic profile conformance.

## Integration and boundaries

[Payment acceptance contract](PAYMENT_ACCEPTANCE.md) and the [plain Ruby recovery example](../examples/payment_acceptance.rb) explain protected enrollment, stable authenticated tenant/merchant/operation/approval/occurrence identities, atomic reservation, fresh fenced start, original Receipt reconciliation and optionalSQLite2.10.2. Existing1.x verifier APIs/defaults/stored formats and five base dependencies remain unchanged.

One authoritative durable ledger and correct current authority/order/nonce CAS are application requirements. Unknown outcomes, Error Receipts, timeouts or crashes never automatically release a reservation. Processor query/idempotency, database rollback/loss recovery and actual settlement remain application responsibilities. Recurrence/budget evaluation is unsupported; standing supported Opens may serve separately authorized fresh occurrences. No production deployment, real payment, credential/security/protection changes or public announcement occurred.
