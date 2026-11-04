# 1.4.0 publication and verification

Owner registered1.4.0 at **2026-11-04T03:17:55.109Z**. Independent official registry metadata/version-list and downloaded distribution bytes confirm publication. The first metadata request returned404; a fresh read and actual distribution download confirmed the registered version. No push was retried. [Machine-readable record](evidence/1.4.0_publication.json).

| Identity | Verified value |
| --- | --- |
| Gem/version/platform | ap2_mandate_verifier/1.4.0/ruby |
| Bytes | 145,920 |
| SHA256 | `ea82c6468f339ed280005e1a270a511b1a8594452ef3de6fb546de43aa6ba454` |
| Approved source | `b0624799f4d9e7cecc3f5b72b5ed760a81ca456c` |
| Reviewed source | `76239c94d7d6966419ae05871fa58b158074a000` |
| Identical reviewed/merged tree | `5075fe56f89b5f150627d9ad5db1e4a811f9b3e1` |
| Payload | All53 source/archive/installed files identical on both MRI endpoints |

Candidate, actual RubyGems download and independently downloaded GitHub Release asset are byte-identical. Registry metadata SHA agrees. This associates source through the approved candidate and complete payload comparison, not a registry source attestation. No agent Gem push, archive substitution, version overwrite or duplicate push occurred.

## Formal tag and Release

[Release v1.4.0](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v1.4.0) is public, non-draft/non-prerelease, ID433473732, published2026-11-04T03:21:24Z. Annotated tag object `10e4db23c6855d4d8088979b0da298b3b90036de` peels to the approved source; Release target_commitish is the same SHA. Attached `ap2_mandate_verifier-1.4.0.gem` matches approved/registry bytes.

## Verification and interoperability

[Implementation PR244](https://github.com/cuichangquan/ap2-mandate-verifier/pull/244#issuecomment-6621303099) records full regressions and136new PISP/date assertions per supportedMRI3.4.12/4.0.9, legacy119Payment/120SelectivePayment/95SelectiveCheckout assertions, independent exact-HEAD review and [successful CI](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/41763588627). Repeated transitive suites are not summed.

After publication, fresh isolated containers installed the ACTUAL public archive under both supported MRIs, compared all53payload files to released source/installed files and passed installed tests and examples. The new plainRuby example verifies Direct, complete conditional and selective Payment with SelectiveCheckout, rejects independentPISP/time mismatches and out-of-window dates, and authenticates Success/Error Receipt alternatives. No payment is scheduled or executed.

Actual published installed Gem interoperability under Ruby3.4.12/Python3.11.2 passed3lifecycles eachdirection,12Receipts and62negativechecks against pinned officialAP2 `b4587ac1d055888a73b4b21750973cffba961793` plus independent strictDecimal expectations. Six upstream date-check disagreements are explicit: lexical ordering and missing-date acceptance are weaker than this parsed/context-bound profile. PISP-only/date-only/one-sided positive variants are also exercised. This is scoped lowleveladapter interoperability, not genericAP2/highlevel-facade conformance.

## Boundaries and postrelease state

Old1.x defaults, APIs and stored formats remain compatible. PISP/date are fullyvisible even underSelectivePayment; newprofiles require explicitPISP/date and independent trustedcontext. QWAC/channel/provideridentity provenance, consent, currentstate/revocation and one-use execution controls remain application responsibilities. Future plan verification does not establish actual execution/settlement or extend the existing maximum600secondMandate validity. Independentcandidate sets cannot encode correlations; separateOpens are needed. Recurrence/budget unsupported. See [the profile contract](PAYMENT_POLICY.md).

Public guides and normal demo use the verified publicGem after their separately reviewed postrelease PRs. No productiondeployment, realpayment, credential/security/protectionchanges or externalannouncement occurred.
