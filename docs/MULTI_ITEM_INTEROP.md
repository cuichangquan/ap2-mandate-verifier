# Multi-item independent comparison

## Scope and adopted sources

The additive `ap2.checkout.single_merchant_multi_item` v1 profile keeps the
official AP2 source fixed at
[`b4587ac1d055888a73b4b21750973cffba961793`](https://github.com/google-agentic-commerce/AP2/tree/b4587ac1d055888a73b4b21750973cffba961793).
On 2026-10-31, upstream main was
`e1ea56db72a6385bce3e5c1112b3a56ce60acb43`. Comparing those commits found no
changes in `docs/ap2/checkout_mandate.md`, the Open Checkout Schema, or
`sdk/max_flow_helper.py`. The current published
[Line Items normative text](https://ap2-protocol.org/ap2/checkout_mandate/#line-items)
also specifies exact fulfillment of both requirement and Checkout quantities.
This comparison does not upgrade the adopted source or claim general AP2
conformance.

The normative algorithm constructs capacity edges between requirements and
product IDs, and accepts only when flow equals **both** quantity totals. Product
ID determines eligibility; requirement IDs and Checkout line IDs identify
different objects. Product titles do not determine the matching edge. The Gem
preserves its older profile's title comparison while the new profile follows
the ID-based rule. Same-product rows are aggregated only for quantity matching;
the signed Checkout bytes and each row remain intact.

## Recorded differences

| Source | Behavior | Adopted new-profile behavior |
| --- | --- | --- |
| Normative Line Items | Full requirement and Checkout quantity must be assigned | Follow this rule |
| Fixed Python `evaluate_line_items_max_flow` | Checks unassigned Checkout quantity but does not reject remaining unused requirement capacity | Reject shortages; report this SDK disagreement explicitly |
| Fixed Python helper | Empty `acceptable_items` acts as a wildcard | Reject empty candidates; undisclosed IDs cannot authorize a product |
| Open Schema candidate description | Says “One and only one” acceptable item | Follow normative quantity-flow definition, allowing a requirement quantity to be supplied by multiple eligible product IDs |
| Base Schema | Does not enforce this Gem's finite sizes, unique IDs, all monetary arithmetic, or complete signed-wire binding | Apply the documented stricter local profile after signature/disclosure checks |
| Checkout Receipt Schema | `status: Success/Error` | Preserve the Checkout-specific 0.5 contract |
| Generic authorization prose | Uses `result: success/error` | Do not silently accept this alternative spelling |
| SDK `MandateClient.get_closed_mandate_jwt` | Extracts compact terminal JWT | Preserve original final closed SD-JWT including trailing `~`; use `common.parse_token` and `common.compute_sd_hash` |

The SDK's shortage behavior is demonstrated by requirement A×2 and Checkout
A×1: the SDK returns no violations, but the independent exact-assignment oracle
and Ruby reject it. SDK agreement alone is therefore insufficient evidence.

Receipt Schema's relative `types/receipt_status.json` reference differs from
the referenced resource's declared `$id`. As in the existing merchant test, the
comparison registers that URI as an explicit alias for the unmodified resource.
All resources are local and unknown references fail; no network fallback exists.

## Executable checks

[`test/multi_item_interop.py`](../test/multi_item_interop.py) reuses the existing
merchant interoperability approach with a test-only Ruby JSON-lines driver.
Synthetic keys are generated only in process memory; no private PEM is written.

- A separate exhaustive unit-assignment oracle labels 288 bounded allocations.
  Ruby must match every expected result. The official max-flow implementation
  is also executed, with its 139 underfilled-requirement disagreements required
  to be successes only on the SDK side and shortages only on the exact oracle
  side. Empty-candidate wildcard behavior is separately demonstrated.
- Independently Python-signed Root, Merchant Checkout and Agent terminal tokens
  pass through Ruby's public InputBuilder trust/prepare/restore/verify flow.
  Six full-verifier cases include candidate overlap, different quantities,
  same-product multiple rows, impossible allocation, shortage, and reordered
  correctly signed requirements/rows. Success must produce Evidence; negatives
  must not. Wrong Issuer keys and modified signed Checkout bytes reject.
- Ruby-signed multi-item Checkout is verified by the official Python JWT helper,
  with decoded claims and an independently computed original-byte hash checked.
- Ruby and Python signed Success/Error Receipts are checked in both directions,
  including original JSON Schemas, exact expected reference, and outcome
  predicates. The official SDK reference callback compares its actual argument
  with the independently computed expected value; a compact-only hash fails.
  There is no unconditional-success callback or skipped signature verification.

The full-Mandate path is Python signing to Ruby verification, not a claim that
the official SDK enforces every local profile rule. The official independent
paths exercised are JWT signature/claims, constraint evaluator, original
Schema validation, Receipt verification, and normative SD hash calculation.
Host order/nonce provenance and real Issuer enrollment remain application
responsibilities; all test Host state is synthetic.

## Environment, command and initial observation

Initial measurement: 2026-10-31, working tree based on main
`6ea21489c445dd6442be772b7e711f06fabcd8e8` plus the task's multi-item changes.
The final task verification record identifies the committed candidate SHA;
this initial working-tree observation is not a final-commit certification.

Existing isolated image `ap2-merchant-interop:task3` (`343795b18b60`) was reused.
No Mac installation or dependency change was required. Image runtime:
MRI 3.4.12 aarch64-linux, Python 3.11.2; Ruby json 2.19.9/jwt 3.3.0/
openssl 4.0.2/digest 3.2.1/base64 0.3.0. Python comparison dependencies:
jwcrypto 1.5.6, cryptography 46.0.5, pydantic 2.12.5, jsonschema 4.26.0,
referencing 0.37.0, sd-jwt 0.10.4. Other installed Python packages:
annotated-types 0.8.0, attrs 26.1.0, cffi 2.1.1,
jsonschema-specifications 2025.9.1, pycparser 3.12, pydantic_core 2.41.5,
PyYAML 6.0.3, rpds-py 2026.9.1, typing-inspection 0.4.4,
typing_extensions 4.16.0.

With `$PWD` at this repository and the pinned official checkout adjacent at
`../official-ap2`, the complete offline check is:

```sh
docker run --rm --network=none --cpus=2 --memory=768m --pids-limit=128 \
  -v "$PWD:/src:ro" -v "$PWD/../official-ap2:/official:ro" -w /src \
  -e PYTHONPATH=/official/code/sdk/python ap2-merchant-interop:task3 \
  timeout 120 python test/multi_item_interop.py
```

Initial result: **PASS**, process exit 0, 288 allocation comparisons and six
full InputBuilder/Verifier cases. Two expected SDK reference-not-found log lines
come from the required wrong-reference controls. No runtime network was enabled.
This measures these bounded inputs only; it provides no general worst-case
latency, memory, concurrency or production performance guarantee. Ruby 4.0.9
full-source regression is recorded in the main task evidence, separately from
this Python interoperability runtime.

Pinned source file SHA256:

| File | SHA256 |
| --- | --- |
| `sdk/max_flow_helper.py` | `92a6dba9f5b2c2a887ea8ec77dd166cbcd54dd7192a9118939ee51c3eb1a8251` |
| `sdk/sdjwt/common.py` | `6b33fe08b17cca52c5818ee9063903de2febea215b21a3a1384254e9b5a549b1` |
| `schemas/ap2/open_checkout_mandate.json` | `bd6eb1c95a5ccb967259fae49100287755251c9d1bdb48342d96dd99fcb30b41` |
| `docs/ap2/checkout_mandate.md` | `df7ab0ff9e21e518d645b76f430ba1adbba3e3e7cf10e87709db0fb68036cd19` |
