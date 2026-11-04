# 1.3.0 publication and verification

Owner registered1.3.0 at **2026-11-04T00:29:50.504Z**. Independent registry metadata and downloaded distribution bytes confirm publication. [Machine-readable record](evidence/1.3.0_publication.json).

| Identity | Verified value |
| --- | --- |
| Gem/version/platform | ap2_mandate_verifier/1.3.0/ruby |
| Bytes | 137,728 |
| SHA256 | `fb95cf669bc4cba1cc1360653bfd7ae8aec58404f13810f6d5a8fb205bc8841d` |
| Approved source | `36c87026007e2aa221139c54c0ca0055485cb296` |
| Reviewed source | `fd9e7a3f0a2319089be7197a4d585083861884f1` |
| Identical reviewed/merged tree | `91c67d8f88afae58f7fea143b55f0b700da885e9` |
| Payload | All49 source/archive/installed files identical on both MRI endpoints |

The retained approved candidate, actual RubyGems download and downloaded GitHub Release asset are byte-identical. Registry metadata SHA agrees. This associates source through the retained candidate and complete payload comparison; it is not a RubyGems source attestation. No additional Gem push, archive substitution or version overwrite occurred.

## Formal tag and Release

[Release v1.3.0](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v1.3.0) is public, non-draft and non-prerelease, ID433372757, published2026-11-04T00:33:38Z. Annotated tag object `da356b56e39e429d4b83157d5627420ac7957adf` peels to the approved source. Release target_commitish is the same SHA. Asset `ap2_mandate_verifier-1.3.0.gem` was independently downloaded and matched the approved bytes; renaming its initial download-prefixed filename changed only metadata, not the asset content.

## Verification

[Issue#241](https://github.com/cuichangquan/ap2-mandate-verifier/issues/241#issuecomment-6618882572) records prerelease regressions,95 new selective Checkout assertions plus119 Payment and120 selective Payment assertions per supported MRI3.4.12/4.0.9, independent latest-HEAD reviews and [successful exact-HEAD CI](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/41744899452). Repeated transitive suites are not summed into a total.

After publication, isolated containers installed the ACTUAL downloaded Gem on both MRI endpoints, repeated the package/source/installed49-file comparison and passed installed tests and standalone examples. The combined example retains6 Checkout disclosures and sends4, then retains5 Payment disclosures and sends3; issuer JWTs stay unchanged, exact presentation references change and both Success/Error Receipt alternatives authenticate. Unselected values/salts/full issuance are not printed.

The published installed Gem also passed pinned official AP2 `b4587ac1d055888a73b4b21750973cffba961793` low-level SDK/profile-adapter comparison under Ruby3.4.12/Python3.11.2:2 scenarios each direction,8 Receipt checks and28 negatives. Independent exhaustive quantity expectations reject upstream wildcard/underfill behavior. High-level candidate selection and inline terminal issuance require explicit adapters. This is scoped synthetic interoperability, not complete facade support or generic AP2 conformance.

## Compatibility and limits

Existing1.x defaults/APIs/saved formats remain unchanged. The new Host-registered profile and Payment Checkout-profile opt-in remain explicit. Merchant/product sets are independent; correlated approval requires separate Opens. Hidden candidate preimages/schema/uniqueness and consent provenance cannot be certified. Counts/order/issuer linkage remain visible. See [the profile contract](SELECTIVE_CHECKOUT.md).

Verifier evidence and Receipt authenticity do not grant final purchase/payment permission. Trust enrollment/consent/revocation/current order/atomic nonce consumption/replay prevention/payment and uncertain-outcome handling remain application responsibilities. No production deployment or real payment occurred. Normal demo now uses the public Gem; postpublication guide/demo PRs record their own validation and independent reviews.
