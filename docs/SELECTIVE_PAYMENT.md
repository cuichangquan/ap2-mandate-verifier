# Payment candidate disclosure — unpublished1.2.0 profile

Published1.1.0 remains available with its unchanged complete-content Payment profile. New `AP2MandateVerifier::SelectivePayment` is an explicit opt-in conditional-only profile: `ap2.payment.selective_candidates.1`. Existing `Payment` remains strict and does not accept this new Open format. Existing Checkout/Payment/Receipt keyword/default/result/storage/reference contracts are unchanged. Payment verification/issuance additionally detaches mutable Agent-key inputs consistently and rechecks copied Checkout time; this tightens snapshot safety without changing supported formats or defaults. This is a framework-independent Ruby API; Rails is optional.

## Normative source and policy boundary

Adopted official AP2 source/SDK/Schema SHA: `b4587ac1d055888a73b4b21750973cffba961793`. Current upstream `e1ea56db72a6385bce3e5c1112b3a56ce60acb43` has identical relevant specification/Schema/SDK. The `open_payment_mandate.json` allowed_payees and allowed_payment_instruments definitions explicitly mark their allowed arrays as selectively disclosable. This profile permits disclosure only at those ARRAY ELEMENT positions; each disclosure is `[salt, complete_candidate_object]` committed through `{"...":digest}` using SHA256/base64url without padding. Salts use16random bytes. Root header remains ES256/example+sd-jwt; Agent terminal is ES256/kb+sd-jwt.

An Open has exactly the existing four constraints: amount_range, allowed_payees, allowed_payment_instruments and payment.reference. The entire Open content and all constraint types/fields are mandatory, as are cnf/iat/exp and any fixed payee/payment_amount/payment_instrument. They cannot be hidden. The new root's signed `ap2_profile` marker and the independently selected API fix this exact grammar. Unresolved commitments are allowed only at known candidate positions; no hidden whole condition, unknown location, nested SD, decoy, duplicate digest/disclosure, extra disclosure or unsupported field is accepted. Strictness is a scoped profile, not proof about arbitrary SD-JWT or a source of trust in the signer.

**Independent allowlists mean Cartesian product.** `[A,B]` and `[X,Y]` authorize all four combinations, not only `(A,X),(B,Y)`. Issuance requires `approved_combinations` from the application's protected approval record: integer index pairs must exactly cover the Cartesian product, with no duplicate/missing/extra pair. Correlated subsets reject BEFORE signer invocation. Do not auto-generate a broader approval matrix from a paired policy. For a correlated policy, issue separate singleton-pair or explicitly approved rectangular-subset Open Mandates, retaining the required amount/reference/time limits in each. This release does not claim general pairing-constraint support. The SDK does not authenticate user consent or the provenance of the supplied approval record.

## Public lifecycle

```ruby
full = AP2MandateVerifier::SelectivePayment.issue_open(
  **independently_approved_open_inputs,
  approved_combinations: protected_approved_pairs, selective: :both)
sent = AP2MandateVerifier::SelectivePayment.select(
  open_sd_jwt: full, payee_index: 0, instrument_index: 0)
```

`full` is confidential issuance material containing all disclosures. Retain it in protected application storage; do not send/log it. `sent` contains only the Open content disclosure plus selected candidate disclosures for selective axes. Nonselective axes are inline and therefore fully visible. `selective: :payees`, `:instruments` and `:both` explicitly determine the privacy boundary at issuance. Pass nil for each nonselective-axis index; providing an index for that axis rejects. Selection indices refer to the ORIGINAL signed candidate positions; reconstruction/removal of hidden array items does not renumber their meaning.

| API | Contract |
| --- | --- |
| `issue_open` | open_checkout_sd_jwt, constraints, fixed, approved_combinations, selective, agent_public_key_pem, issued_at, expires_at, signer, public_key_pem → confidential original issuance String. Constraints supplies exactly the three existing amount/payee/instrument conditions; reference is calculated from exact Open Checkout. |
| `select` | open_sd_jwt, payee_index, instrument_index → detached reduced Open String. Structural selection, not authenticity/consent. Each selective axis reveals exactly one candidate; nonselective axis remains visible. |
| `issue_closed` | open_presentation, payment, trusted_provider_public_key_pem, agent_public_key_pem, audience, nonce, verified_at, signer → Payment::Presentation with reduced Open and final Closed only. No Provider signer is passed to Agent. |
| `present` | open_presentation, closed_sd_jwt → Payment::Presentation preserving exact received reduced Open and final Closed; structural restoration only. |
| `verify` | open_presentation, closed_sd_jwt, checkout_inputs, expected_payment, trusted_provider_public_key_pem, expected_agent_public_key_pem, expected_audience, expected_nonce, verified_at → Payment::Verification. Reruns complete existing conditional Checkout verification, then root/delegation/conditions/reference/expected payment. |

The seven `checkout_inputs` are the original public `verify_checkout` keywords, prepared if useful with `InputBuilder.inputs`, at the same explicit verified_at. Expected Checkout/payment/keys/audience/challenge/time must come from independently trusted application state, not received unverified Payment. `Payment.details` can assemble expected payment from an independent Merchant JWT/key/current order and selected instrument. Full issuance/selection/restoration does not grant execution permission.

Result is the unchanged immutable `Payment::Verification`: verified?, code, selected payment claims, reference and expiry only; no full issuance/candidate universe. Existing `PaymentReceipt.sign/verify` works on the unchanged final Closed format. Errors use a fixed redacted new-profile Invalid exception without underlying cause; verify fails closed with no selected claims. No raw candidate, wire, parser cause or hidden value belongs in diagnostics/logs. Process/signing failure is not permission and may require reconciliation; preflight bounds run before signing callbacks.

## Original bytes, restoration and privacy

| Value | Exact SHA256 target |
| --- | --- |
| Issuer signature | Original compact root JWT; unchanged when its disclosure subset/order changes |
| Agent sd_hash | ACTUAL reduced Open presentation, all selected disclosure strings in transmitted order, including terminal `~` |
| transaction_id | Original Merchant Checkout JWT, unchanged by Payment disclosure choice |
| payment.reference | Exact Open Checkout presentation from the independently verified Checkout chain |
| Payment Receipt reference | Final Closed Payment SD-JWT alone including its terminal `~`; excludes Open and chain `~~` separator |

Subset/order changes preserve the issuer JWT but change the presented Open hash. Agent must sign the intended exact presentation; later insertion/removal/reordering must fail, never repair the wire from retained issuance. Changing selected candidate usually changes final Closed payment and Receipt reference; with the same Closed claims, a newly signed Agent terminal can still differ and references always follow exact actual bytes. No JSON rebuilding substitutes for original-wire references. Persist exact sent Open and final Closed; `present` restores without reconstructing hidden data, then `verify` must run again with current independent inputs.

The receiver does not receive unselected candidate objects, their random salts or leaf disclosure strings. It DOES see commitment count/order, fixed mandatory fields and selected values. Stable issuer JWT/digests permit linkage between presentations of the same issuance; count hiding, padding/decoys, traffic-analysis resistance, unlinkability and secrecy from the issuer/holder are not promised. Nonselective inline axes are deliberately visible. Issuance and protected approval state necessarily contain candidate values; keep them separate from transmitted data and operational logs.

## SDK differences and honest interoperability scope

Pinned Python `MandateClient.present` selects root2-element vct disclosures and3-element named claims, but drops candidate2-element array leaf disclosures. Its high-level selector cannot directly generate this profile. Use the tested explicit profile adapter and official lower-level issuance/chain primitives, and retain the exact received disclosure strings; do not claim the unsupported selector succeeds.

Official generic crypto verification and Schema validation are not this profile's semantic oracle. For example, the one-time Python payment constraint checker can accept a visible Open missing amount_range, and official Schema does not require all four constraints. This profile explicitly requires them and rejects signed missing/hidden mandatory conditions. Independent profile expectations check this safety boundary alongside official signature/chain/typed condition/Schema validation. Tests must report which layer passed and which stricter profile checks rejected; no signature-only or repaired-input result is called full Payment verification.

## Limits, example and application responsibilities

At most8payees/8instruments, one Agent hop, one immediate payment, supported1.1.0 integer minor units/currencies and600-second lifetime. Only known candidate-array disclosures are supported; no generic arbitrary SD or Checkout selective-disclosure extension. Open wire is limited to65,536bytes, root compactJWT to16,384bytes, each decoded disclosure to24,576bytes, and total disclosures to2–17. Each candidate array has1–8entries; selected presentation requires one revealed candidate per selective axis. Existing JSON depth24, finalClosed32,769-byte wire and per-field bounds are reused. All structural/signing bounds are checked before signer effects. Recurrence/budget/PISP/execution_date/risk_data, arbitrary delegation, unsupported algorithms and unknown constraints reject.

After installing the candidate with its pinned dependencies:

```sh
ruby "$(ruby -e 'puts Gem::Specification.find_by_name("ap2_mandate_verifier", "1.2.0").full_gem_path')/examples/selective_payment.rb"
```

The runnable example prints retained/transmitted disclosure counts and byte counts, confirms unchanged issuer JWT and changed presentation bytes, verifies chosen Payment and both Receipt outcomes without printing unselected values/disclosures. Its approved matrix is explicitly synthetic; real code reads protected consent. The application owns user authentication/consent, key enrollment/custody/revocation, current order/trust, final authorization, payment, durable one-use identity and atomic state transitions. Missing/invalid Receipt or uncertain processing remains pending, never automatic retry permission. Candidate status and exact artifact verification are in [release preparation](RELEASE_120_CANDIDATE.md).
