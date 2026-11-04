# PISP and execution-date Payment constraints (published1.4.0)

New explicit complete/selective Payment profiles add `payment.allowed_pisps` and `payment.execution_date` without changing the existing1.x defaults. Direct and conditional issuance, presentation, strict verification, selective Checkout/Payment and Payment Receipt references share the existing cryptographic and Host verification paths. This SDK remains framework independent and performs no payment scheduling or execution.

## Ruby API

```ruby
m = AP2MandateVerifier
profile = m::PaymentPolicy::PROFILE_REF
payment = m::Payment.details(**existing_checkout_details,
  pisp: approved_pisp, execution_date: "2026-11-10T00:00:00Z",
  profile_ref: profile)
constraints = existing_payment_constraints + [
  {"type" => "payment.allowed_pisps", "allowed" => [approved_pisp]},
  {"type" => "payment.execution_date",
   "not_before" => "2026-11-10T00:00:00Z", "not_after" => "2026-11-30T23:59:59Z"}
]
open = m::Payment.issue_open(**existing_open_inputs,
  constraints: constraints, candidate_policy: :independent, profile_ref: profile)
# Existing issue_closed/present flow, with profile_ref: profile on each call.
checked = m::Payment.verify(**existing_verification_inputs,
  profile_ref: profile,
  trusted_pisp: authenticated_registry.fetch("processor-A"),
  execution_at: independent_application_execution_at)
```

Keep the application’s protected approval, authenticated registry and execution context distinct from received claims. Do not build the last two inputs by copying a received Payment. All existing parameters remain required; the snippets show only additions. The [complete installed Ruby example](../examples/payment_policy.rb) runs Direct, complete conditional and selective conditional Payment, rejects mismatched provider/time and an out-of-window date, then verifies both Receipt alternatives.

For `SelectivePayment`, use `PaymentPolicy::SELECTIVE_PROFILE_REF` on every lifecycle call (including `select`), retain its existing protected payee/instrument `approved_combinations` and `selective:` inputs, and add `candidate_policy: :independent` on issuance. `Payment.details` prepares the shared details using the new complete profile. Receipt `reference`, `sign` and `verify` take the corresponding explicit profile; final Closed bytes remain the reference source.

## Which conditions are checked, and when?

| Condition | Issuance/Agent preparation | Verification |
| --- | --- | --- |
| PISP identity | Validate exact legal/brand/domain fields and approved allowlist membership | Authenticate signed chain; compare Closed PISP to independent trusted application PISP and any allowed set |
| Execution instant | Parse explicit Closed/fixed date and every supplied bound; enforce inclusive window | Compare signed instant with independent application `execution_at`, then all window/fixed conditions |
| Existing amount/payee/instrument | Retain existing complete or selective constraints | Retain complete Checkout/Host/order/challenge/reference verification |
| Receipt | Sign a reference to exact final Closed bytes | Authenticate issuer, outcome/time and exact reference; no settlement inference |

The new profiles require both explicit `pisp` and `execution_date` in Closed and both `trusted_pisp` and `execution_at` during verification. New Open constraints can contain either new type or both, with at least one. This is a deliberately strict subset: it does not silently interpret an omitted date as immediate execution. The old profiles retain their existing contract.

## Independent trusted execution context

`trusted_pisp` must come from the application’s independently authenticated provider selection/registry/channel, not from a received token. Matching `expected_payment` alone is insufficient. Each PISP has exactly `legal_name`, `brand_name` and `domain_name`; all three compare exactly. Domain is canonical lowercase ASCII DNS in this supported profile (bounded valid labels; no URL, port, path, wildcard, trailing dot or unknown field). Names are bounded descriptive strings with no implicit Unicode or case normalization.

The official PISP Schema describes the domain as secured by an eIDAS QWAC certificate. This library does not fetch/validate QWACs, establish legal authorization or authenticate a network endpoint from text. Applications own certificate/channel validation, enrollment, revocation and the provenance/freshness of their trusted PISP input. A syntactically valid domain or valid Mandate signature does not establish those facts.

`execution_at` is an independently controlled application execution-plan/operational instant. It must represent the same instant as signed `execution_date`. It is distinct from `verified_at`, which checks signature/Mandate freshness. Future plan verification does not prove that execution occurred or will later occur under that context. The existing maximum600secondMandate lifetime is unchanged; a future execution date does not extend its expiry. At the actual execution gate, the application must recheck the actual provider/time/current approval and a valid Mandate, atomically consume one-use state and reconcile uncertain outcomes. The SDK does not schedule, call a PISP or settle a payment.

## Date semantics

The supported subset is an explicit RFC3339 timestamp: Gregorian year0001..9999, uppercase `T`/`Z`, valid calendar/time, optional1..9 fractional digits and an explicit `Z` or numeric offset. Offsets must be syntactically valid; `-00:00` (unknown offset), date-only/local timestamps, invalid dates, leap seconds and unsupported precision are rejected. Parsing produces an exact rational instant, without floating-point rounding or lexical comparison.

`not_before` and `not_after` are inclusive. At least one bound must be present; if both are present the lower instant cannot exceed the upper. Equivalent offsets denote the same instant for window/context comparisons. A bound ending at `23:59:59Z` denotes that exact instant; later fractions of that second are outside the window. Specify the intended fractional precision or next boundary explicitly. An Open fixed `execution_date` additionally binds its exact string through Agent delegation; a different representation cannot replace that fixed value even if it denotes the same instant.

## Profiles and compatibility

Use `PaymentPolicy::PROFILE_REF` (`ap2.payment.pisp_execution.complete.1`) with `Payment`, or `PaymentPolicy::SELECTIVE_PROFILE_REF` (`ap2.payment.pisp_execution.selective.1`) with `SelectivePayment`. Pass the corresponding explicit `profile_ref:` through issuance, selection/presentation, verification and Receipt APIs. New signed profile markers prevent silent cross-profile interpretation. Omitting the option preserves old defaults; old profiles reject the new fields/conditions/context.

For new Opens, `candidate_policy: :independent` explicitly means the protected consent approved independent PISP/payee/instrument sets. It is not proof of consent. Existing selective payee×instrument `approved_combinations` checks remain required. Correlated PISP/instrument/payee restrictions cannot be flattened into these sets; issue separate Opens for permitted combinations. Recurrence and cumulative budgets remain unsupported and fail closed.

PISP lists and execution conditions are mandatory visible content, including under `SelectivePayment`: the official Schema does not mark the PISP array as selectively disclosable. Only the existing payee/instrument candidate positions may be reduced. Keep complete issuance confidential; counts/order/issuer linkage and intentionally visible PISP conditions remain observable. Errors/diagnostics must not expose hidden candidate values or caller inputs.

Direct Payment uses exact protected `approved_payment`, including PISP and execution instant, rather than an Open constraint window. Conditional Payment adds Open constraints and keeps the exact reduced Checkout Open reference. `checkout_profile_ref:` still explicitly selects selective Checkout when used. Receipt authenticity remains a statement about signed reported outcome, not independent PISP/settlement confirmation.

## Official source and Python boundary

Adopted source remains AP2v0.2.0 `b4587ac1d055888a73b4b21750973cffba961793`: [Payment specification](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/payment_mandate.md), [Open Schema](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/open_payment_mandate.json), [PISP Schema](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/ap2/types/pisp.json).

The normative text requires inclusive execution bounds. Schema permits weakly typed strings; it does not itself enforce this strict timestamp subset. The pinned Python evaluator compares date strings lexically and permits absent dates even with a date constraint. Its PISP evaluator does compare all three identity fields. Ruby’s parsed/context-bound behavior is an explicit safer supported subset, not an unqualified claim that all official high-level helpers behave identically. Source interoperability observed three lifecycle cases in each direction (Direct/complete conditional/selective conditional), twelve Receipt checks and62 negatives, plus six explicitly recorded upstream date-check disagreements. Separate positive variants cover PISP-only/date-only/one-sided constraints. Exact signed-wire hashes and actual runtime provenance are recorded with the candidate; supported claims do not extend to QWAC provenance, execution or generic AP2 conformance.

[Verified public artifact, tag and Release](POST_RELEASE_140.md). The original candidate preparation is retained as [historical evidence](RELEASE_140_CANDIDATE.md).
