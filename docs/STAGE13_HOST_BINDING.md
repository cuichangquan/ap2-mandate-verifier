# Stage13 — authenticated Host challenge/order binding

Limited research only. `verify_host_binding` adds checks for authenticated Host
assertions and their connection to signed original wires. Normal is
`unverified / host_binding_verified_only / success=false / evidence=nil`.
It neither issues nor consumes a nonce, operates a database, authorizes a purchase,
nor produces successful Evidence. Earlier low-level and Stage12 APIs retain their
contracts. Stage11 retained sources, fixtures, pins and reports stay unchanged.

## API and exact inputs

`AP2MandateVerifier.verify_host_binding(trust_json:, selection_json:, host_json:,
root_presentation:, terminal_jws:, host_checkout_jws:, verified_at:)`

The trust/selection strings use the Stage12 contract. `host_json` is a strict
UTF-8 JSON string, at most32768 bytes, with exactly:

- binding: current authenticated Host order binding B.
- challenge: authenticated Host challenge body plus current state, defined below.
- expected_challenge_issuer_id: independent current Host issuer expectation.
- clock_source_id: nonempty Host identity for the externally supplied fixed clock.

B has exactly tenant_id, buyer_account_id, order_id, merchant_id, audience,
profile_ref, order_version, profile_version, approved_agent_key_fingerprint,
root_presentation_digest, checkout_jwt_digest, currency and expected_total.
IDs/versions are nonempty UTF-8 strings <=256 bytes, without normalization.
The three digests are lowercase64-character SHA256 hex. Currency is USD/EUR/JPY;
expected_total is an integer in the existing scoped amount range.

challenge has exactly challenge_id, nonce, issuer_id, B, trust_snapshot_id,
policy_version, trust_content_hash, profile_definition_hash, not_before,
not_after, state. Its B must match current B in every field and type; issuer_id
must equal the independent expected_challenge_issuer_id. Only state=issued is
accepted; consumed, revoked, unknown states, missing/null/extra fields, duplicate
JSON keys and unsupported shapes fail closed. Times are integer Unix seconds
0..4102444800, not_before < not_after and not_before <= verified_at < not_after.

Both Host inputs and trust/selection must come through authenticated Host state;
no signed presentation can establish that provenance. Challenge body immutability
and the separate current consumption/revocation state are Host responsibilities.
This JSON envelope carries those Host assertions together for inspection; the
library does not persist or authenticate their storage/delivery itself.
clock_source_id names a Host assertion, not an attestation of an actual clock.

## Binding is checked against signed content

Before key work, all caller strings are detached. The checked Stage12 context
provides unique keys, active windows and the authenticated current trust/profile
references. Challenge references must match that context. Current B's tenant and
profile/version must match; approved Agent fingerprint must equal the selected
canonical PEM fingerprint. B's Root digest covers the entire exact presentation,
including disclosure order and trailing `~`; Checkout digest covers the exact
compact JWT. Compact Root alone, decode/re-encode or normalization cannot replace
the original byte digests.

The existing full scoped pipeline then verifies Root signature/all disclosures,
Root cnf matching that Agent key, Agent terminal signature plus original Root
sd_hash, challenge nonce and B.audience, Closed exact Checkout bytes/hash and
matching Open/Closed lifetime, Merchant signature and B.order_id/merchant_id,
then signed limited constraints, B.currency and expected_total. Merely making
current B and challenge B equal does not bypass these signed checks. Internal
claims handoffs occur only after their existing checks finish; earlier public
check APIs still return their existing non-success results.

Host-only buyer/account, order_version and tenant are authenticated Host
assertions fixed into B. Their connection uses the signed nonce's one-to-one
association with the immutable challenge. They are not Issuer-signed Buyer
identity claims. The library cannot prove global uniqueness from one input.

## Non-circular issuance and time intersection

Required Host sequence: freeze Root presentation and Merchant Checkout original
bytes; issue immutable challenge with their digests/current B and trust/profile
references; Agent signs terminal with that nonce/audience/Root sd_hash and Closed
Checkout. A terminal digest is deliberately absent from a pre-terminal challenge.
The Host must never rebind or reissue a nonce for a different B during its lifetime.
This sequencing and persistence invariant is not established by a local equality
test or this stateless verifier.

After existing signed time checks, starts are Open.iat, Closed.iat, terminal.iat,
selected-key not_before values, snapshot.not_before and challenge.not_before.
Ends are Open.exp, Closed.exp, terminal.iat+301, selected-key not_after values,
snapshot.not_after and challenge.not_after. max(starts) <= verified_at < min(ends)
is mandatory; no implicit skew. This exactly retains integer terminal age300
acceptance and age301 rejection. The sole registered profile has no separate
period; profile bodies adding one are unsupported, not silently ignored. Merchant
Checkout has no exp/nbf/iat in this subset, and none is fabricated.

## Checks and residual gates

Tests generate only transient in-memory test signing keys and original signed
wires. Provider-level OpenSSL signature controls, contract-derived expected
rejections, symmetric-B changes that still fail signed checks, exact aggregate
interval observations, boundaries, mutation controls and existing regressions
are separate from the historical Stage11 O1–O5 comparisons. No independent
Stage15 Oracle proof or operational identity provenance is claimed here.

Before execution, the Host must recheck latest trust/profile, current order and
Buyer/Agent approval, challenge state and time, then atomically consume nonce
with order CAS. These operations, unknown commit handling, concurrent replay,
real trust/clock provenance and payment authority remain unimplemented. Stage14
Evidence, general Schema/all constraints, Stage7 final acceptance, the two
historical acquisition measurement defects, production/release/Phase2B remain
HOLD. No extra dependency, workflow, runtime or deployment is introduced.
