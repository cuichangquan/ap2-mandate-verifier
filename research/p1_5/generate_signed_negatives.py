"""P1-5 signed security-negative vectors; never export ephemeral private JWKs.

Generated with official AP2 v0.2 SDK pinned at b4587ac1... and jwcrypto.
Research-only; intentionally creates invalid/ambiguous *yet signed* inputs.
No live payment, Host storage, production tokens, or off-box calls.
"""
import base64
import hashlib
import json
import sys
import time
from pathlib import Path

from jwcrypto.jwk import JWK
from jwcrypto import jws
from ap2.sdk.disclosure_metadata import DisclosureMetadata
from ap2.sdk.generated.checkout_mandate import CheckoutMandate
from ap2.sdk.generated.open_checkout_mandate import (
    AllowedMerchants, Item, LineItems, LineItemRequirements, OpenCheckoutMandate,
)
from ap2.sdk.generated.types.merchant import Merchant
from ap2.sdk.mandate import MandateClient
from ap2.sdk.sdjwt import common, kb_sd_jwt

# Reuse exact simple Checkout fixture shape from P1-3, without editing it.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "p1_3"))
from generate_merchant_checkout import checkout_json, b64, AUD, NONCE  # noqa: E402


def sign_merchant_raw(key, payload_str, header_raw='{"alg":"ES256","typ":"JWT"}'):
    j = jws.JWS(payload_str.encode("utf-8"))
    j.add_signature(key, protected=header_raw)
    return j.serialize(compact=True)


def json_compact(data):
    return json.dumps(data, separators=(",", ":"), ensure_ascii=True)


def generate():
    issuer = JWK.generate(kty="EC", crv="P-256")
    agent = JWK.generate(kty="EC", crv="P-256")
    merchant = JWK.generate(kty="EC", crv="P-256")
    other_issuer = JWK.generate(kty="EC", crv="P-256")
    wrong_agent = JWK.generate(kty="EC", crv="P-256")
    now = int(time.time())
    items = LineItems(items=[
        LineItemRequirements(
            id="req-1", acceptable_items=[Item(id="SKU-1", title="Research Widget")],
            quantity=2,
        )
    ])
    allowed = AllowedMerchants(allowed=[Merchant(id="merchant-allowed", name="Research Merchant")])
    open_mandate = OpenCheckoutMandate(
        constraints=[items, allowed], cnf={"jwk": json.loads(agent.export_public())},
        iat=now, exp=now + 3600,
    )
    root = MandateClient().create(
        payloads=[open_mandate], issuer_key=issuer,
        sd=DisclosureMetadata(children={"constraints": DisclosureMetadata(sd_array_indices=[1])}),
    )
    base_checkout = checkout_json()
    base_checkout_json = json_compact(base_checkout)
    # A semantically ambiguous, *authentically ES256-signed* JSON payload:
    # first denied merchant ID, then approved ID in one object.
    duplicated_merchant_json = base_checkout_json.replace(
        '"merchant":{"id":"merchant-allowed",',
        '"merchant":{"id":"merchant-denied","id":"merchant-allowed",',
        1,
    )
    assert duplicated_merchant_json != base_checkout_json
    assert duplicated_merchant_json.count('"merchant-denied","id":"merchant-allowed"') == 1

    checkout_with_extra = dict(base_checkout)
    checkout_with_extra["opaque_unverified_authorization"] = {"role": "override"}
    deep_nested = "leaf"
    for _ in range(48):
        deep_nested = {"nested": deep_nested}
    checkout_jwts = {
        "valid": sign_merchant_raw(merchant, base_checkout_json),
        "duplicate_merchant_id": sign_merchant_raw(merchant, duplicated_merchant_json),
        "duplicate_header_alg": sign_merchant_raw(
            merchant, base_checkout_json,
            '{"alg":"none","alg":"ES256","typ":"JWT"}',
        ),
        "merchant_header_wrong_typ": sign_merchant_raw(
            merchant, base_checkout_json,
            '{"alg":"ES256","typ":"unexpected+jwt"}',
        ),
        "merchant_header_jku": sign_merchant_raw(
            merchant, base_checkout_json,
            '{"alg":"ES256","typ":"JWT","jku":"https://evil.invalid/jwk.json"}',
        ),
        "unknown_checkout_field": sign_merchant_raw(merchant, json_compact(checkout_with_extra)),
        "large_checkout": sign_merchant_raw(
            merchant, json_compact({**base_checkout, "padding": "A" * 19500})
        ),
        # P1-10o: authentic ES256 JWT whose extra nested data exceeds the
        # strict research JSON max nesting (distinct from an over-size token).
        "deep_checkout": sign_merchant_raw(
            merchant, json_compact({**base_checkout, "unexpected": deep_nested})
        ),
    }

    def terminal(jwt, exp=now + 3600, timestamp=now, signer=agent,
                 hash_mode="sd_hash", prior_root=None):
        closed = CheckoutMandate(
            checkout_jwt=jwt, checkout_hash=b64(hashlib.sha256(jwt.encode()).digest()),
            iat=timestamp, exp=exp,
        )
        return kb_sd_jwt.create(
            prev_token=common.parse_token(prior_root or root), holder_key=signer, payload=closed,
            aud=AUD, nonce=NONCE, sd=DisclosureMetadata(), hash_mode=hash_mode,
        ).sd_jwt_issuance

    terminal_variants = {k: terminal(jwt) for k, jwt in checkout_jwts.items()}
    terminal_variants["expired_closed"] = terminal(checkout_jwts["valid"], exp=now - 120)
    terminal_variants["future_closed_iat"] = terminal(checkout_jwts["valid"], timestamp=now + 1800)
    # P1-10o / Codex P1 claim-preservation review: valid signed Closed
    # still inside Root time window, but an Issuer fixed claim was changed.
    terminal_variants["changed_closed_exp_in_window"] = terminal(
        checkout_jwts["valid"], exp=now + 3000
    )
    # P1-10o Codex follow-up: a correctly Issuer-signed Open can carry an
    # EXTRA fixed claim. A naive intersection-only comparison misses that
    # the Agent has omitted it in Closed. The strict fixed-layout verifier
    # must reject the root itself rather than infer unchanged authority.
    root_parts = root.split("~")
    root_header, root_payload, _ = root_parts[0].split(".")
    extra_open_payload = json.loads(base64.urlsafe_b64decode(
        root_payload + "=" * (-len(root_payload) % 4)
    ))
    assert isinstance(extra_open_payload["delegate_payload"][0], dict)
    extra_open_payload["delegate_payload"][0]["currency"] = "USD"
    original_header_json = base64.urlsafe_b64decode(
        root_header + "=" * (-len(root_header) % 4)
    ).decode("utf-8")
    signed_extra_root = sign_merchant_raw(
        issuer, json_compact(extra_open_payload), original_header_json
    ) + "~" + "~".join(root_parts[1:])
    # Independently check valid Issuer signature before testing rejection.
    from ap2.sdk.sdjwt.sd_jwt import verify as verify_root
    assert verify_root(signed_extra_root, JWK.from_json(issuer.export_public()))[
        "delegate_payload"
    ][0]["currency"] == "USD"
    signed_extra_terminal = terminal(
        checkout_jwts["valid"], prior_root=signed_extra_root
    )
    terminal_variants["wrong_agent_signature"] = terminal(
        checkout_jwts["valid"], signer=wrong_agent
    )
    terminal_variants["unsupported_hash_mode"] = terminal(
        checkout_jwts["valid"], hash_mode="issuer_jwt_hash"
    )
    # An already-expired-but-signed Root is tested separately: root signature
    # valid; Root clock should reject. Use an independent issuance.
    expired_root = MandateClient().create(
        payloads=[OpenCheckoutMandate(
            constraints=[items, allowed], cnf={"jwk": json.loads(agent.export_public())},
            iat=now - 1800, exp=now - 30,
        )], issuer_key=issuer,
        sd=DisclosureMetadata(children={"constraints": DisclosureMetadata(sd_array_indices=[1])}),
    )
    # Root with explicitly signed THIRD authority rule (fully disclosed).
    extra_authority = OpenCheckoutMandate(
        constraints=[items, allowed, AllowedMerchants(allowed=[
            Merchant(id="merchant-different", name="Research Merchant 2")
        ])], cnf={"jwk": json.loads(agent.export_public())}, iat=now, exp=now + 3600,
    )
    extra_authority_root = MandateClient().create(
        payloads=[extra_authority], issuer_key=issuer,
        sd=DisclosureMetadata(children={"constraints": DisclosureMetadata(sd_array_indices=[1, 2])}),
    )
    # Remove only the third signed authority disclosure from the wire.
    parts = extra_authority_root.split("~")
    third_disclosure = None
    for part in parts[1:]:
        if not part:
            continue
        val = json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))
        if isinstance(val, list) and len(val) == 2 and isinstance(val[1], dict):
            if val[1].get("type") == "checkout.allowed_merchants":
                allowed_ids = [m["id"] for m in val[1].get("allowed", [])]
                if "merchant-different" in allowed_ids:
                    third_disclosure = part
    assert third_disclosure
    hidden_extra_root = "~".join(
        [parts[0], *[p for p in parts[1:] if p and p != third_disclosure], ""]
    )
    root_wire_parts = root.split("~")
    merchant_disclosure = None
    for p in root_wire_parts[1:]:
        if p and '"checkout.allowed_merchants"' in base64.urlsafe_b64decode(
            p + "=" * (-len(p) % 4)
        ).decode():
            merchant_disclosure = p
    assert merchant_disclosure
    root_hidden_merchant = "~".join(
        [root_wire_parts[0], *[p for p in root_wire_parts[1:] if p and p != merchant_disclosure], ""]
    )
    # A large root string and extra disclosure are cheaply testable without
    # creating real signatures (these should be rejected at parse/binding).
    oversized_root = root + "A" * 34000
    return {
        "ap2_commit": "b4587ac1d055888a73b4b21750973cffba961793",
        "trusted_issuer_public_jwk": json.loads(issuer.export_public()),
        "wrong_issuer_public_jwk": json.loads(other_issuer.export_public()),
        "expected_agent_public_jwk": json.loads(agent.export_public()),
        "trusted_merchant_public_jwk": json.loads(merchant.export_public()),
        "root_open_sdjwt": root,
        "valid_terminal": terminal_variants.pop("valid"),
        "signed_extra_fixed_open_root": signed_extra_root,
        "signed_extra_fixed_open_terminal": signed_extra_terminal,
        "terminal_variants": terminal_variants,
        "checkout_jwts": checkout_jwts,
        "expired_root": expired_root,
        "extra_authority_root": extra_authority_root,
        "hidden_extra_authority_root": hidden_extra_root,
        "root_hidden_merchant": root_hidden_merchant,
        "oversized_root": oversized_root,
        "expected_aud": AUD, "expected_nonce": NONCE,
        "expected_checkout_id": "checkout-001",
        "expected_merchant_id": "merchant-allowed",
        "expected_currency": "USD",
        "expected_total_minor": 2400,
    }


if __name__ == "__main__":
    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(generate(), indent=2, sort_keys=True) + "\n")
    print("PASS: generated synthetic signed JOSE/SD-JWT ambiguity and expiry fixtures (public-only)")
