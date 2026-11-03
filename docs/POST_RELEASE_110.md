# 1.1.0 publication and verification

Owner registered 1.1.0 on RubyGems at **2026-11-03 09:20:11.580 UTC**. Independent official metadata and distribution retrieval confirms publication. [Machine-readable receipt](evidence/1.1.0_publication.json).

| Identity | Verified value |
| --- | --- |
| Gem / version / platform | ap2_mandate_verifier / 1.1.0 / ruby |
| Prerelease / yanked at comparison | false / false |
| Bytes | 115,200 |
| SHA256 | `4c64cf5b6c61ae4395577828093a6f4022c35cf18b6ad1bcfcb9f95fbb4f43c9` |
| Release source | `89e779cadeac0ea7941e68f12951eed13f1b8081` |
| Reviewed/tested source | `631537ec52c33c3472fd856da55faeff3fb62203` |
| Same source tree | `4282e3349d2a2851940d3f153460a013f0ea6ceb` |
| Payload comparison | All 38 archive/source/installed files identical on both MRI endpoints |

The downloaded public archive is byte-for-byte identical to the Owner-approved candidate. The registry metadata SHA and GitHub Release asset also agree. Association with source follows the retained reviewed candidate and every payload comparison, not a RubyGems source attestation. No Gem rebuild or version overwrite was performed. After successful registration, no additional push was attempted.

The Owner's terminal reported successful registration while the browser showed a WebAuthn verification/callback error. These are distinct observations: registry metadata and actual distributed bytes establish successful publication. A cached metadata URL initially retained its earlier HTTP 404; a fresh read returned the published version and matching SHA. The browser error's precise cause is not established. It does not justify another push or credential/security-setting changes.

## Tag and Release

[Formal v1.1.0 Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v1.1.0), ID 432487583, is public, non-draft and non-prerelease, published 2026-11-03T09:23:10Z. Annotated tag object `dff5006234c35c24de416786fa7d088953f86105` peels to the release-source commit above. The attached `ap2_mandate_verifier-1.1.0.gem` was downloaded independently and matches the same SHA256 and byte count.

## Verification and compatibility

The approved candidate's existing Checkout regression and 113 Payment assertions per source/installed runtime, strict latest-HEAD independent reviews and [CI](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/41605001799) are recorded in [Issue #235](https://github.com/cuichangquan/ap2-mandate-verifier/issues/235). Official AP2 SHA `b4587ac1d055888a73b4b21750973cffba961793` SDK/Schema comparisons cover Ruby→Python and Python→Ruby Direct/conditional Payment and both Receipt outcomes, plus independent original-wire hashes. Tests are synthetic and scoped; they do not establish general AP2 conformance or real Issuer trust.

After publication, fresh containers separately install the **downloaded public archive**, compare all 38 files against the formal tag source and installed payload, and pass the existing installed package checks, 113 Payment assertions and Direct/conditional/Success/Error packaged examples on MRI **3.4.12 and 4.0.9**. Updated published-guide checks also pass both English/Japanese README Quick Starts and retained Checkout walkthroughs plus the installed Payment sample. Repeated transitive suites are not summed into a total. Subsequent documentation CI is separate from the pre-release source/package CI above.

Dependencies remain json=2.19.9, jwt=3.3.0, base64=0.3.0, openssl=4.0.2 and digest=3.2.1. Existing 1.0.0 Checkout arguments/defaults/profiles/results/storage and Receipt references are preserved. [Payment API and bounds](PAYMENT.md) are additive. The Gem's immutable packaged README/API documents retain their preparation snapshot; current repository publication records supersede status wording without changing published bytes.

## Usage and application duties

```sh
gem install ap2_mandate_verifier --version 1.1.0
ruby "$(ruby -e 'puts Gem::Specification.find_by_name("ap2_mandate_verifier", "1.1.0").full_gem_path')/examples/payment.rb"
```

Framework-independent SDK use needs no Rails. The separate Rails demo upgrade uses the same public artifact and verifies it independently; it performs no deployment. SDK verification is not final execution permission. Receipt authentication and reported outcome are separate. Applications retain consent/trust/key lifecycle, current-order checks, durable atomic one-use state, actual payment and reconciliation of missing/invalid Receipts or uncertain processing. Unsupported recurrence/budget, PISP/execution_date/risk_data and arbitrary disclosure/delegation forms reject under the documented profile. No real payment or production deployment was performed.
