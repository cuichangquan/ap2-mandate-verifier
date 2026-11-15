# AP2 #398: defensive audit of Payment verification and acceptance

**Scope:** RubyGems `ap2_mandate_verifier` 1.6.1 and source main at
[`aeae0bc`](https://github.com/cuichangquan/ap2-mandate-verifier/tree/aeae0bc7de043dec225399c1c5d9c4ba868d7040),
reviewed on 2026-11-15 JST. This is a source review of supported Ruby profiles
and their integration contracts, not certification of AP2 generally or a
production authorization or settlement result.

[AP2 Issue #398](https://github.com/google-agentic-commerce/AP2/issues/398) was
open at review time. The SDK retains its adopted source pin
[`b4587ac`](https://github.com/google-agentic-commerce/AP2/tree/b4587ac1d055888a73b4b21750973cffba961793).
The pinned [verification rules](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#verification-and-processing-rules)
require failure for unknown conditions and define `unresolved_constraint` for
constraints the verifier cannot evaluate. The report's proposed changes to
cross-role disclosure, mandate linkage and usage accounting are not adopted
requirements here. [The #395 audit](PAYMENT_CONSTRAINT_AUDIT.md) and
[its SDK tracking issue](https://github.com/cuichangquan/ap2-mandate-verifier/issues/252)
cover malformed or unknown constraint objects, a separate problem; those results are
historical evidence, not fresh #398 validation.

| Question | Source assessment | Boundary |
| --- | --- | --- |
| A. Are required conditions always evaluated? | Controls present in the supported Open Payment profiles. Direct Closed profiles have no Open conditions to disclose. | Selective Payment permits hiding unselected candidate values, not condition objects. No general split-role Payment disclosure support. |
| B. Does the verifier match the authorized Checkout, Payment and Receipt? | Conditional and Selective verification bind signed originals, the verified Checkout and independent expected terms. Direct verifies the two final objects against trusted Checkout/payment inputs. | The caller supplies authoritative inputs. A valid result does not establish the authenticity of a caller's approval records, nor constrain a verifier who skips checks. |
| C. Is usage enforced independently of the Agent? | Supported recurring/long profiles verify signed terms; the protected acceptance ledger enforces aggregate use. | Stateless verification alone has no cumulative usage guarantee. Single-host SQLite is not a shared multi-host ledger or an external processor guarantee. |

## A. Understand the supported disclosure scope

[Payment](../lib/ap2_mandate_verifier/payment.rb) requires an exact base
condition set covering the payment reference, amount range, payees and
instruments. Explicit [PISP/date](PAYMENT_POLICY.md), [recurring](RECURRING_PAYMENT.md)
and [long-Open](LONG_PAYMENT.md) profiles validate their additional conditions
before applying the base contract. [Selective Payment](SELECTIVE_PAYMENT.md)
requires the committed payload and condition structure. Only supported candidate
list positions may retain unopened alternatives; each selected axis requires a
disclosed choice. The reconstructed conditions still pass the base and profile
validators. Unknown layouts or an unavailable required condition must not
produce a useful verified Payment. Do not treat the absence of a verified
projection as an empty set of restrictions, or retry by downgrading profiles.

## B. Keep trust and transaction provenance outside the request

For Conditional/Selective flows, the SDK re-verifies Checkout, checks signed
Open/Closed bindings and compares the Checkout reference and transaction digest
with verified originals. The Host binds customer, order, approved agent and
challenge to the current authenticated records. In the Direct flow use the
expected, trusted merchant Checkout JWT and model the application approval
explicitly; there is no conditional Open pair or Agent challenge in that route.
Verify Payment and Checkout against expected facts, not only against other
values carried by the same request.

Keep the approved Open Checkout/Payment pair and permitted role identities
with the same protected approval record. Check the approved pair and trusted
authority for that operation, not a pair selected through Agent-supplied
references. Standard Conditional and Selective verification verify the
expected role keys independently; they do not impose a universal same-Issuer
rule across roles. The Long profile additionally reconciles its Payment
Provider and Agent with the Host-selected Checkout trust context.

| Information | Authoritative source |
| --- | --- |
| Tenant, customer, approval, occurrence, allowed Agent, active policy | Host's authenticated approval and authorization records; an Agent identifier is only a lookup hint. |
| Checkout bytes, merchant identity, order/items/quantity, currency and total; expected Payee, payment instrument and profile context | Current canonical order and protected payment instruction. Do not synthesize the expected side from the received Mandates. |
| Trusted Issuer, merchant, Agent and processor keys; audience, nonce and verification time | Role- and tenant-scoped registries and Host policy; a server-controlled challenge record and clock. Do not bootstrap trust from the Mandate. |
| Receipt reference and expected issuer/key, payment ID and window | Original reserved Closed bytes and protected processing context. A verified Receipt authenticates a report, not settlement; an Error report is not success. |

A malicious merchant or credential provider can disregard a verifier it
controls. Independent enforcement belongs to the party with the ability to
authorize, block or settle the payment. That party must enforce its own
authoritative approval, trust, transaction and replay requirements; a
merchant-supplied success flag, a signed Receipt alone or a local ledger is not
a substitute. The existing Receipt does not attest to which independent roles
evaluated the Checkout or Payment, or which approval each used. This SDK is
not a credential-provider, payment-network or settlement control.

## C. Keep one authoritative history and fail closed on uncertainty

- Use stable business IDs from protected enrollment and route all relevant
  workers through one authoritative ledger. Re-signing and retrying must not
  allocate a new occurrence or refresh the allowance. The first signed wires,
  Receipt reference and processor idempotency key remain associated with the
  original reservation.
- `PaymentAcceptance::Service` revalidates raw inputs before reservation and
  again before start. The protected store owns the authoritative reservation
  and atomically decides whether it may be started. Ordinary `SQLiteStore`
  uses protected, explicitly enrolled occurrences/grants. For cumulative
  checks, use the matching adapter: `RecurringSQLiteStore` for the JPY
  ON_DEMAND profiles or `LongSQLiteStore` for the long-Open UTC monthly profile.
  Both check durable occurrence and cumulative amount limits in the reservation
  transaction. Agent-provided usage counters are not part of the verifier or
  acceptance contract.
- Do not treat a new root as new consent. Use the supported enroll/rotation/
  revocation contract in [Long Payment](LONG_PAYMENT.md), preserving the
  history of the existing approval. For other flows establish renewal and
  revocation against Host policy and persist lineage; do not silently replace
  a grant or discard already-reserved usage when an approval changes.
- Never reopen execution on timeout, failed lookup, lost state or a genuine
  Error Receipt. Query and reconcile the original processor key. Keep SQLite
  on a protected local filesystem with one database and separate connections
  across worker processes. Do not accept a rolled-back, partitioned or newly
  initialized copy as authority. A multi-host deployment needs atomic budget
  and count reservation, durable unique business IDs, current-authorization
  checks and monotonic fencing in its shared store, plus a processor-side
  idempotency and lookup/reconciliation contract. See
  [Payment Acceptance](PAYMENT_ACCEPTANCE.md).

For application wiring, see [Ruby integration and restart recovery](RUBY_INTEGRATION.md).
The [purchase demo](https://github.com/cuichangquan/ap2-mandate-verifier-demo/blob/e3de0047419eb14a44b1fa2735d0f0f7b23ca49d/docs/PURCHASE_DEMO.md)
is a synthetic example at a separately pinned Gem version (1.6.0). The
Seller compares original mandates and Checkout against its protected records
before verification and owns the mock processor. There is no independent
credential-provider or network verification in that deployment.

## Evidence and limits

- PASS: downloaded the public 1.6.1 archive; SHA-256
  `97958467a326d5ab6dd4ca2ad45e22799a96d7e4fe181fa660795928a086edeb`
  matches the [publication record](POST_RELEASE_161.md). All packaged
  `lib/` paths and contents match the reviewed main. The released source
  `53a19787734a426c03221d3de7891d1e648751df` differs from that main only in
  documentation and publication records.
- Existing evidence includes all seven conditional Payment profiles in
  [#395](PAYMENT_CONSTRAINT_AUDIT.md); release-time native Linux Docker
  integration tests include restart/recovery across separate Ruby processes
  [for the public 1.6.1 archive](POST_RELEASE_161.md#tests-and-review).
  Neither is presented as a new run or a full independent #398 oracle.
- Fresh focused regression: installed public **1.6.1**, native Debian 13
  Linux x86_64, MRI 3.4.12, sqlite3 2.10.2 (SQLite 3.54.1), with no SDK
  source load-path overlay. Synthetic fixtures and the packaged examples
  use their fixed demonstration clocks.

| Fresh smoke check | Result |
| --- | --- |
| Packaged `selective_checkout_payment.rb` | PASS: one candidate per selected axis disclosed, original Issuer JWT retained, Payment verified, Success/Error reports distinguished. |
| Packaged `long_payment_acceptance.rb` | PASS: 12 approved UTC-month occurrences, 12 mock starts, JPY 96,000 reserved under JPY 100,000, original Receipts reconciled. |
| Packaged `ruby_integration.rb`: 4 concurrent Ruby processes running the same approved purchase against one SQLite ledger | PASS: one completion, three no-new-Ticket responses, one durable mock dispatch; re-signed retry retained original identity and remained at one dispatch. |
| Same CLI, exit after durable mock result and recover in a new process | PASS: exit 75 / pending, then original Receipt reconciled with dispatch count still one. |
| Same CLI, no processor result and authenticated Error report | PASS: unknown remained unknown; authentic Error remained Error on retry, with no new Ticket or dispatch. |

- NOT_RUN: #398 attack reproduction and new bypass fixtures; real Issuer,
  merchant/credential-provider or processor/network checks, and distributed
  fault or ledger-rollback testing. Aggregate-limit contention across distinct
  occurrences, root replacement/revocation and the full product/demo suites
  were not rerun for this documentation change. No live service or keys
  were used.

No Ruby API, profile, storage format, workflow or demo runtime is changed by
this audit note. A new Gem release is not needed for the documentation.
