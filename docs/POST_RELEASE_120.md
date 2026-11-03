# 1.2.0 publication and verification

Owner registered1.2.0 at **2026-11-03T12:30:27.200Z**. Independent official metadata and distribution retrieval confirms publication. [Machine-readable receipt](evidence/1.2.0_publication.json).

| Identity | Verified value |
| --- | --- |
| Gem / version / platform | ap2_mandate_verifier /1.2.0/ruby |
| Prerelease / yanked at comparison | false / false |
| Bytes | 129,536 |
| SHA256 | `327ddb9f19e2b6348631ccb38838abd8247b4b7c2dfeb3ce2cf53bc2b0961443` |
| Approved release source | `52ebc7cb37f20967d4a53d88c57e347b0bc4b769` |
| Reviewed/tested source | `fd79d2c230eaa2cd2d65f4bb7394351b5a60c1ea` |
| Identical source tree | `8e823b7dc9a97322d0a8bf1e6f59b080f3461cbc` |
| Payload comparison | All44source/archive/installed files identical on both MRI endpoints |

Candidate, downloaded RubyGems archive and downloaded GitHub Release asset are byte-identical. Registry metadata SHA agrees. Every archive payload agrees with the approved release source and ordinary installed files. This associates source through the retained approved candidate and payload comparison, not a RubyGems source attestation. No archive rebuild/version overwrite/additional push after successful registration was performed.

## Formal tag and Release

[Release v1.2.0](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v1.2.0) is public, non-draft and non-prerelease, ID432672816, published2026-11-03T12:33:58Z. Annotated tag object `7463195d07faaa333cd0480b120100077889b632` peels to the approved source above. Release target_commitish is that exact SHA. Attached `ap2_mandate_verifier-1.2.0.gem` was independently downloaded and matches the same size/SHA256.

## Verification and supported boundary

Pre-release evidence is in [Issue#238](https://github.com/cuichangquan/ap2-mandate-verifier/issues/238): existing Checkout/Payment/Receipt regression,119legacyPayment and120selective assertions each on MRI3.4.12/4.0.9, ordinary same-candidate install/all44payload identity, independent final-HEAD Codex reviews and [source/package CI](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/41633156201). Repeated transitive suites are not summed into a total.

After publication, fresh isolated containers install the ACTUAL downloaded public archive and again compare all44files against approved-source snapshot and installed payload. Both MRI endpoints pass installed119Payment/120selective assertions and packaged examples. Updated English/Japanese README and retained Checkout/Payment guides plus the physically installed selective example pass both endpoints. The comparison demonstrates retained5→sent3disclosures, unchanged issuerJWT and changed presentationbytes, selected Payment/fullCheckout and both Receipt outcomes; no unselected values/salts/fullwire are printed. Subsequent published-guide CI belongs to its own documentation PR and does not replace original exact-artifact observations.

The public installed Gem also passes the pinned officialAP2 `b4587ac1d055888a73b4b21750973cffba961793` low-level SDK/profile-adapter suite on Ruby3.4.12/Python3.11.2:4cases eachdirection TOTAL spanning3axis modes and originalslot1,16Receipt checks and24negative controls. Official crypto/Schema/typedconstraints are paired with an independent strictprofile/privacy/original-wire oracle. Python highlevelcreate/present cannot directly express this profile marker/candidate-array selection. A signed hidden-amount control accepted by generic upstream checks is rejected by the new Ruby/independentprofile checks. This is scoped adapter interoperability, not full-facade support or genericAP2 conformance.

[SelectivePayment](SELECTIVE_PAYMENT.md) is explicit; the existing1.1.0 complete-content `Payment` profile/defaults/formats/Receipt references are preserved. Snapshot consistency is tightened. Correlated subsets reject before signing and require separate singleton/approved-rectangle Opens. Candidatecount/order and sameissuerJWT/digest linkage remain visible. No genericSD, Checkoutselective extension, recurrence/budget/PISP/execution_date/risk_data or live-payment integration is claimed.

Runtimepins remain json2.19.9,jwt3.3.0,base640.3.0,openssl4.0.2,digest3.2.1. Tested MRI endpoints are3.4.12/4.0.9; installationrange>=3.4.12,<4.1 is not formal support for every intermediate release. Immutable packaged/tagged documents retain preparation status wording; current repository records update publication status without replacing released bytes.

## Usage

```sh
gem install ap2_mandate_verifier --version 1.2.0
ruby "$(ruby -e 'puts Gem::Specification.find_by_name("ap2_mandate_verifier", "1.2.0").full_gem_path')/examples/selective_payment.rb"
```

The SDK works without Rails. The separately reviewed demo upgrade installs this exact public artifact with a frozen lock and checks every payload; its tests use synthetic data/keys and reported outcomes only. Applications retain user authentication/consent, keytrust/custody/revocation, current-order checks, final authorization, durable atomic one-use state, actual payment and uncertain Receipt reconciliation. Verification is not execution permission; Receipt authenticity and reported outcome are distinct. No production deployment, real payment, customer data or security-setting change was performed.
