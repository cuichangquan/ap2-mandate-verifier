# Payment constraint audit — AP2 Issue #395

Scope: published Ruby SDK **1.6.0**, source baseline
`339add6564b2b41f6acc7ae539d42a3b60b3378f`. Synthetic offline inputs only.
This audit concerns malformed Payment constraints; it is not a general AP2
conformance, real-Issuer, production-authorization or settlement certification.

## Upstream evidence and the distinct contracts

[AP2 #395](https://github.com/google-agentic-commerce/AP2/issues/395)
reports a Python model conversion problem at
`e1ea56db72a6385bce3e5c1112b3a56ce60acb43` (Pydantic 2.12.5).
An object lacking `type`, such as `{"foo":"bar"}`, is tried against union
members, accepted as `ExecutionDate` using its default discriminator, and loses
its unknown fields. The resulting constraint has no date bounds. A later
unknown-type evaluator guard cannot recover the original object.
An explicitly unknown discriminator is a separate case; the report does not
establish that every explicitly unknown type is accepted.

The [normative verification rules](https://github.com/google-agentic-commerce/AP2/blob/e1ea56db72a6385bce3e5c1112b3a56ce60acb43/docs/ap2/agent_authorization.md#verification-and-processing-rules)
require unknown constraints to fail evaluation. The
[official Schema](https://github.com/google-agentic-commerce/AP2/blob/e1ea56db72a6385bce3e5c1112b3a56ce60acb43/code/sdk/schemas/ap2/open_payment_mandate.json)
requires `type` on every constraint variant and a `payment.reference` in the
array. A Schema `default` does not remove a `required` requirement.
By contrast the [generated Python model](https://github.com/google-agentic-commerce/AP2/blob/e1ea56db72a6385bce3e5c1112b3a56ce60acb43/code/sdk/python/ap2/sdk/generated/open_payment_mandate.py#L105-L118)
defaults `ExecutionDate.type`; its optional bounds and ordinary BaseModel
handling permit the reported coercion. The
[evaluation helper](https://github.com/google-agentic-commerce/AP2/blob/e1ea56db72a6385bce3e5c1112b3a56ce60acb43/code/sdk/python/ap2/sdk/constraints.py)
returns a list of violations; an empty list is not full signature/chain/consent
verification or payment success. This audit inspected these fixed Python
sources; it does **not** claim a fresh execution of that Python reproduction.

Important distinctions:

- `{"type":"payment.execution_date"}` is valid under the official Schema's
  constraint definition, whose bounds are optional. Ruby's explicit PISP/date
  profiles require at least one bound; refusal here is a **Ruby profile rule**.
- The official Schema does not uniformly forbid extra properties. Ruby's
  exact-field grammar deliberately rejects extras; this is stricter supported
  behavior, not a claim that the Schema forbids every extra field.
- The Issue's minimal reproduction also omits `payment.reference`. Ruby tests
  add malformed constraints to otherwise valid, reference-bearing mandates,
  and separately replace required constraints, avoiding that confounder.
- [#339](https://github.com/google-agentic-commerce/AP2/issues/339) concerns
  presence-driven evaluation/withheld constraints and budget units.
  [#356](https://github.com/google-agentic-commerce/AP2/issues/356) concerns
  code generation dropping Schema `contains`. These are related but distinct
  mechanisms. All three Issues were open on 2026-11-06; a search for PRs
  referencing #395 found none. Required discriminators/discriminated unions
  are suggested fixes, not an adopted new normative specification.
- Ruby retains its adopted AP2 source pin
  `b4587ac1d055888a73b4b21750973cffba961793`. The incident commit above is
  comparison evidence, not a source-pin update. JPY ON_DEMAND and UTC monthly
  long-Open semantics remain explicit Ruby profiles; UTC monthly is not full
  generic AP2 MONTHLY compliance.

The Open Payment Schema blob is identical at both pins:
`22c9dcaa145f692ba53a0d83fce428ba7976c282` (Git blob SHA).

## Ruby validation and normalization audit

| Public route | Validation before a useful result |
| --- | --- |
| `Payment.issue_open`, `issue_closed`, `present`, `verify` | `Payment.open!` checks the complete type multiset and exact field grammar; `verify` authenticates the original root and binds Checkout, Agent, audience, nonce and expected Payment |
| `SelectivePayment.issue_open`, `select`, `issue_closed`, `present`, `verify` | `parse!` resolves only approved candidate slots, rejects unused/duplicate/unresolved disclosures, then validates the entire reconstructed Open using `Payment.open!` |
| `PaymentPolicy` complete/selective profiles | Known PISP/date conditions are validated **before** projection into the base grammar; remaining conditions still pass the exact base type set |
| `RecurringPayment` complete/selective profiles, `approved_open!` | Count, budget, frequency, currency and exact extension fields are checked before removing those known extensions; the remaining base constraints are mandatory |
| `LongPayment` lifecycle, `approved_open!`, `approved_pair!` | Validated monthly/budget extensions feed the base validator; pair approval also checks current trusted Checkout authority and the exact reference |
| Direct Closed Payment (base and PISP/date) | No Open constraint grammar exists here; injected `constraints` fields fail exact Closed/details validation |
| `PaymentAcceptance::Service.accept` / `start` | Re-run the corresponding public verifier from raw inputs before calling protected reservation/start operations |

There is no generated union or default discriminator in these Ruby paths.
Extension filtering is restricted to known, already-validated types; unknown
constraints remain for base rejection. Candidate reduction affects only
allowlist leaves, not the constraint array or condition types. PISP timestamps
are explicitly parsed to exact instants; no malformed condition becomes absent.
`details` prepares Closed data and does not authorize it. `reference` and
Receipt APIs identify/authenticate final Closed bytes and do not validate an
Open or grant execution; receipt lookup/finish does not create a new reservation.

## Reproducible evidence

Run using the repository's pinned dependencies (MRI 3.4.12 or 4.0.9):

```sh
ruby test/payment_constraint_regression_test.rb
sh scripts/check_ruby_compatibility.sh /tmp/ap2-regression
```

The new suite is also included in installed-candidate checks. It covers all
seven profile constants: base complete, selective candidates, PISP/date complete
and selective, JPY ON_DEMAND complete and selective, and long-Open UTC monthly
complete. Existing suites separately cover SQLite atomicity, durable enrollment,
quotas, replay, Receipt outcomes and process races.

Attack cases include the five requested objects, secret-bearing unknown values,
null/array discriminators, missing amount fields, per-type missing/extra fields,
duplicate constraints, missing/empty/non-array constraints and hidden-condition
markers. Every conditional attack carries a genuinely signed Issuer root with
updated disclosure commitment and a genuinely re-signed Agent binding. Test
construction uses direct JSON/Base64/Digest/JWT operations, not SDK issuance to
create malformed claims. JWT signature/hash oracles and accepted no-op
re-signing controls ensure failures are not merely stale signatures or bindings.
Valid Checkout inputs and Payment expectations stay unchanged.

Positive controls cover every profile and the same public paths; selective
controls actually withhold two alternative candidate disclosures. Rejection
checks require empty Payment projections and redacted exceptions, no Ticket or
wire returned by failed acceptance, and no reservation/start callback. The
acceptance callback probe demonstrates verifier ordering, not database durability
or actual external execution. Direct tests inject conditions into signed Closed
mandates and require rejection before an issuance signer is called.

## Decision and limits

Observed on 2026-11-06 in existing Debian Bookworm `aarch64-linux` Docker images,
network disabled, read-only source, temporary test storage, 2 CPUs / 768 MiB:

| Target | Result |
| --- | --- |
| Source, MRI 3.4.12 and 4.0.9 | Entire `check_ruby_compatibility.sh` PASS on both, including all three process oracles |
| Normally built/installed candidate, both MRI versions | Entire `check_candidate_package.sh` PASS on both, including installed regression and process oracles |
| Already installed published Gem 1.6.0, MRI 4.0.9 | New constraint suite PASS, `AP2_INSTALLED=1` (no source-library load path) |
| New constraint suite in each target above | 275 conditional signed attacks across seven profiles, 12 Direct signed injections, 3,273 assertions PASS |

The unchanged runtime/gemspec matches tag `v1.6.0`. Fixed dependencies were
json 2.19.9, jwt 3.3.0, base64 0.3.0, openssl 4.0.2, digest 3.2.1; existing
durable tests use optional sqlite3 2.10.2. The new suite's identical summary log
SHA256 in all five targets is
`976dd733bf28a2d358088ea4dc339750af4f4a47b399b16fa8f9c28670d79f22`.
This hash identifies the summary, not retained signed-wire artifacts; attack
wires/keys are generated in memory and their original signatures/commitments
are checked during each run. The construction oracle shares the JWT dependency
with the SDK and is not an independent cryptographic implementation. x86_64
coverage belongs to CI; no fresh Python SDK execution or live-processor test
was performed. Review/CI links and exact reviewed commit are recorded in the
linked [audit Issue #252](https://github.com/cuichangquan/ap2-mandate-verifier/issues/252).

No production-code change is proposed: source inspection and the regression
matrix found no #395-style silent constraint conversion in supported Ruby
profiles. This finding is bounded to the tested grammars and inputs; it does not
assert that every possible hostile input or third-party adapter is safe.
The demo pins Gem 1.6.0 and delegates Payment verification to the SDK; no demo
change is necessary for this constraint-parser issue. Its synthetic data cannot
establish real consent, fresh external trust or production payment safety.

Verification success is separate from payment success. Applications own user
authentication/consent, current trust, protected approval/order state and actual
payment execution. No release/version bump is required for this test/document
change; publication and production decisions remain with the Owner.
