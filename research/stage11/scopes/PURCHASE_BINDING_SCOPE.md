# Two-hop purchase binding only — stage 5

`AP2MandateVerifier.verify_purchase_binding(**inputs)` accepts these required
keyword inputs: root_presentation, terminal_jws, host_checkout_jws,
trusted_issuer_public_key_pem, expected_agent_public_key_pem,
trusted_merchant_public_key_pem, expected_aud, expected_nonce, verified_at,
expected_checkout_id, expected_merchant_id. Public PEMs and Host context must
come from independent enrollment/current transaction state, never token data.
There is no URL, key discovery, token JWK import or resolver callback.

Limited format: DC04 exact3 Root disclosure profile, one compact inline Closed
terminal with ES256/typ=kb+sd-jwt, one compact ES256/typ=JWT Merchant Checkout.
No chain-string parsing, extra hops, terminal disclosures, issuer_jwt_hash,
object disclosures or unknown top-level Open/Closed/terminal/Checkout fields.
Builds on pinned AP2 b4587ac1 and existing p1_2/p1_3 binding research; imports
none of their autorun, legacy parser, constraint or environment code.

Verification order:

1. Snapshot all original wires and external key/context bytes with core String
   methods. Root131072, terminal32768, HostCheckout16384, keys1024,
   aud/nonce512, checkout/merchant IDs256 bytes; context strings nonempty.
2. Authenticate original Root and its complete bounded disclosure graph.
3. Require Open vct/cnf/constraints/iat/exp layout; validity at Host verified_at.
   Compare Root-endorsed public JWK coordinates with external expected Agent
   PEM-derived coordinates. Reject private/extended JWK; never import its key.
4. Verify original terminal with that external matched key. Require exact Root
   presentation SHA256 (including disclosure order and trailing ~), Host aud
   and nonce. Terminal iat is within [now-300, now], and within Open lifetime.
5. Require one terminal Closed vct/checkout_jwt/checkout_hash/iat/exp; no further
   cnf delegation. Open/Closed iat and exp must match exactly (strict R06).
   Both are integer seconds, 0..4102444800, valid now, duration<=7200.
6. Compare Closed Checkout original compact bytes and SHA256 with the Host
   original; verify that Merchant signature with external trusted PEM.
7. Require Checkout outer/merchant layout, ready_for_complete status and exact
   Host transaction ID and merchant ID. Any failure is rejected/unavailable;
   missing/malformed trusted context is unavailable.

Valid binding returns only `unverified / purchase_binding_verified_only`:
success? false, evidence nil, no claims/keys returned. Shared bounded JWS helper
uses existing invalid_root_* error codes for any segment's crypto failure.
All key/context byte snapshots precede validation to avoid mixed mutable state;
this does not establish atomic Host database state or same-process isolation.

Stage6 remains mandatory: official Schema, type/shape of purchase contents,
currency/prices/totals/items, Root merchant/SKU/quantity/other constraints and
their meaning are NOT evaluated here. Even the binding-positive synthetic
fixture intentionally makes no Schema/monetary-validity claim. Host nonce
issuance/consumption, replay protection, inventory, revocation, payment and
Receipt are also unproved. Signature/time/hash validity never means ALLOW.

Tests use fresh in-memory private keys and independent manual OpenSSL signing
and verification calls, sharing the same provider (no crypto diversity/official
SDK or Python O1–O5 proof). Initial70 binding cases passed. Expanded tests found
a test-only unary+ alias of a mutable Checkout fixture; use .dup to isolate it.
Final input79+signature74+disclosure64+binding81=298 cases pass in one process;
syntax12 files pass. No new dependencies, Actions, OS changes or stages6–9.
Existing task-local Ruby4.0.1/JSON2.18.0/jwt3.3.0 are used in the MBA Codex
sandbox without extra OS isolation. After setting the existing GEM_HOME/PATH:

```sh
ulimit -t 10
bundle exec ruby -e 'ARGV.each { |path| load path }' test/input_boundary_test.rb test/root_signature_test.rb test/root_disclosures_test.rb test/purchase_binding_test.rb
```
