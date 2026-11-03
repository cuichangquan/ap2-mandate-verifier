> Historical preparation snapshot. The exact approved candidate is now published; see [publication evidence](POST_RELEASE_120.md). Earlier approval boundaries below describe that checkpoint.

# 1.2.0 candidate — unpublished, Owner decision required

Published1.1.0 remains the released SDK. This is preparation for an additive opt-in Payment candidate-disclosure profile. No RubyGems push/yank, formal tag, GitHub Release, announcement or deployment is authorized by this document. The Owner decides final version and publication after reviewing exact source/artifact/verification identity in Issue#238.

## Proposed Release body

Adds `SelectivePayment` for conditional Payment with individually disclosed payee and payment-instrument candidates. Retain the full issuance confidentially, select candidates, and send only the reduced Open plus Agent Closed. Mandatory amount/currency/time/delegation/fixed fields/Checkout reference remain visible and verified; partial disclosure never makes a required condition optional. Existing1.1.0 Checkout, Payment and Receipt APIs/defaults/formats are unchanged.

```ruby
# Read approved_combinations from the protected consent record; do not derive
# broader consent by expanding a correlated subset into a Cartesian product.
full = AP2MandateVerifier::SelectivePayment.issue_open(
  **approved_open_inputs, approved_combinations: protected_approved_pairs,
  selective: :both)
sent = AP2MandateVerifier::SelectivePayment.select(
  open_sd_jwt: full, payee_index: 0, instrument_index: 0)
# Agent signs the exact reduced `sent` bytes, then receiver uses independently
# trusted Checkout/payment/key/challenge inputs. See examples/selective_payment.rb.
```

Supported: single immediate conditional Payment, one Agent hop, candidate-array elements only, independent Cartesian allowlists with explicit approval guard. Correlated subsets require separate singleton/approved-rectangle Open Mandates; unsupported correlation, mandatory-field hiding, unknown structures and arbitrary SD reject. This does not add a generic selective-disclosure API or change Checkout disclosure support.

[Full profile, reference and Python interoperability contract](SELECTIVE_PAYMENT.md). Receipt authenticity, reported outcome and final execution permission remain separate. Application-owned consent/trust/key lifecycle, durable atomic one-use state and payment execution are required. Unknown/missing Receipt remains pending and never automatic retry permission.

## Exact-artifact publication checklist (not execution authority)

1. Confirm the recorded reviewed and merged source/tree, latest-HEAD independent review with zero substantive unresolved findings, relevant CI, both MRI endpoint regressions, candidate ordinary installation/all-file identity, installed sample/privacy comparison and honest official SDK/profile-adapter interoperability scope. Missing required verification means HOLD.
2. Verify exact candidate filename/bytes/SHA256 and unchanged five runtime dependencies in the final manifest and Issue#238. Earlier development builds are not publication candidates. Owner chooses version and approves that exact artifact plus any formal tag/Release/announcement separately.
3. Only after that separate approval, inspect current registry/version/tag/Release state. Never overwrite a version or rebuild during publication. Publish the approved archive using existing Owner-controlled authentication; stop at any human authentication handoff and never request credentials/OTP in chat. On uncertain outcome inspect registry before retry.
4. Fetch actual public metadata/distribution, compare full bytes/SHA256 and every payload against approved source, install into fresh isolated environments and rerun published lifecycle/privacy/Receipt guides. Only then create the approved tag on the approved source and publish Release. Preserve source vs repository-only postpublication documentation identities.

No new publication/deployment workflow is introduced. Current product CI builds test candidates only. Existing unrelated research/Rust/production HOLDs remain untouched. Tested MRI endpoints remain3.4.12 and4.0.9; runtime dependencies remain json2.19.9,jwt3.3.0,base640.3.0,openssl4.0.2,digest3.2.1. Installation range>=3.4.12,<4.1 is not formal support for every intermediate release.
