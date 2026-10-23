# Scoped Schema/constraint check — stage 6

`verify_scoped_constraints(**binding_inputs, expected_currency:, expected_total_minor:)`
checks a closed one-Merchant/one-SKU profile after all stage5 Root/Agent/Merchant
signature, closure, time and Host original-wire binding checks. Host currency
and total must independently come from current transaction state. No network,
key discovery, nonce consumption, general Schema interpreter or new dependency.

Profile rules:

- Exactly two ordered Root constraints: checkout.line_items then
  checkout.allowed_merchants. Unknown/duplicate/extra constraint types rejected.
- Exactly one requirement, one acceptable SKU, one allowed Merchant, one cart
  line. Required and extra fields are checked at every interpreted object.
- Requirement.id and line.id are nonempty strings <=256 bytes. This rejects
  known S01 id=123 after genuinely signed Root/Agent/Merchant binding passes.
- Merchant id/name and SKU id/title are strings, and match Checkout exactly.
  IDs <=256 bytes, names/titles <=512 bytes. Unknown nested fields are rejected.
- Quantity is a Ruby Integer in 1..1000000 and matches the signed requirement.
  Unit price is a Ruby Integer in 0..9007199254740991. Their product and Host
  expected total must be equal and within the same amount bound.
- Currency must be one of USD/EUR/JPY and match independent Host currency.
  Both line and Checkout totals contain exactly one subtotal and one total,
  each nonnegative integer amount equal to price*quantity. Ordering may differ.
- Empty links only. Tax/discount/fees, extra purchase fields, multiple products,
  other currencies, arbitrary constraints and richer UCP objects unsupported.

Valid scoped checks still return only unverified/scoped_constraints_verified_only,
success? false/evidence nil. No general AP2 validity or Host ALLOW is returned.
Unknown forms fail closed; legitimate inputs outside this strict profile may be
rejected. Zero-price purchases are supported; business eligibility is not.

## Pinned Schema correspondence

Read official AP2 commit `b4587ac1d055888a73b4b21750973cffba961793` at
[code/sdk/schemas](https://github.com/google-agentic-commerce/AP2/tree/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas).
These Git blob identities record the files used for correspondence:

| Path under code/sdk/schemas | Git blob SHA |
| --- | --- |
| ap2/open_checkout_mandate.json | `e3d9cafa7311d90612c7f908ae9b8821ddc8735a` |
| ap2/checkout_mandate.json | `8755db60a1c6e15f49cfe6c9a5dee6838d2f379d` |
| ap2/types/item.json | `0b31d4b0a0ee5d96d2d08d0b9d7b6081aaa41c2e` |
| ap2/types/merchant.json | `2e44a4dc943c009af106e7103e9e30f4e556b98c` |
| ucp/types/checkout.json | `bb9697ecea36b81f283165ad85a19753f00cfa59` |
| ucp/types/line_item.json | `a8482fc594d6792c43eb65c3cdeae86a2996cdc4` |
| ucp/types/total.json | `491c47c787a968fb64e72329d97898cfb17353e6` |
| ucp/types/link.json | `e05cc0048c35cd2f89d6b480189739cf3f688da6` |

The Open schema declares Requirement.id as string and positive integer quantity,
SKU id/title and Merchant id/name string; Checkout line/item/total schemas
supply required fields, integer quantity, nonnegative unit price and integer
amounts. Open/Closed vct/cnf/iat/exp/checkout_jwt/checkout_hash already pass the
prior bounded binding stage. Checkout field types are checked here and before
use. UCP references are mapped to the corresponding pinned AP2 item/Merchant
schemas; a general remote-ref resolver is not implemented or exercised.

These are hand-checked **subset rules**, stricter than the general schemas:
exact keys/cardinality, nonempty strings/bounds, Ruby Integer only (including
rejecting 2.0), known currencies, empty links, no fees and arithmetic equality.
Schema descriptions of ISO currency and totals are not treated as complete
machine-enforced constraints. No general draft2020-12 engine, all refs/formats,
all official Schema/constraint coverage or independent Schema oracle is claimed.

## Validation and remaining evidence

Existing MBA Codex sandbox, Ruby4.0.1/JSON2.18.0/jwt3.3.0 task-local deps,
without extra OS isolation. Final input79+signature74+disclosure64+binding81+
scoped97=395 cases PASS in one process; syntax14 PASS. No failed test run in
this stage. Every new fixture has manual native OpenSSL signature verification;
negative tests assert stage5 binding is reached before the scoped rejection.
S01 additionally inspects the authenticated fixture's actual integer123 and
logs original Root presentation SHA256. This is not a fresh general Schema
engine verdict or official-SDK/Python O1–O5 comparison. Same Ruby/crypto provider
is shared. Keys are ephemeral in-memory only; durable signed-wire replay and
real-Issuer provenance remain unproved. Internal static final review: no P1/P2.

With the existing GEM_HOME/PATH, CPU limit10 seconds:

```sh
bundle exec ruby -e 'ARGV.each { |path| load path }' test/input_boundary_test.rb test/root_signature_test.rb test/root_disclosures_test.rb test/purchase_binding_test.rb test/scoped_constraints_test.rb
```

Stages7–9 integrated six-case independent comparison/Gate evaluation/use-scope
judgment remain undone. Host replay/nonce CAS/revocation/payment/Receipt,
production/Phase2B and Gem distribution are outside this stage. No Actions.
