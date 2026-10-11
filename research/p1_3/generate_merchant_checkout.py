"""P1-3: official AP2 v0.2 Python signed 2-hop chain with merchant-signed checkout.

Synthetic research vectors only: generates ephemeral issuer/Agent/Merchant keys
in memory, exports PUBLIC JWKs and signed JWTs only. No payments or replay state.
"""
import base64
import hashlib
import json
import sys
import time
from pathlib import Path

from jwcrypto import jws
from jwcrypto.jwk import JWK

from ap2.sdk.disclosure_metadata import DisclosureMetadata
from ap2.sdk.generated.checkout_mandate import CheckoutMandate
from ap2.sdk.generated.open_checkout_mandate import (
    AllowedMerchants, Item as RequiredItem, LineItems,
    LineItemRequirements, OpenCheckoutMandate,
)
from ap2.sdk.generated.types.checkout import Checkout
from ap2.sdk.generated.types.merchant import Merchant
from ap2.sdk.mandate import MandateClient
from ap2.sdk.constraints import check_checkout_constraints
from ap2.sdk.sdjwt import common, kb_sd_jwt
from ap2.sdk.sdjwt.chain import verify_chain


AUD = "checkout-merchant.example"
NONCE = "host-issued-test-challenge-001"


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def checkout_json(*, merchant_id="merchant-allowed", sku="SKU-1", quantity=2,
                  extra_item=False, totals_delta=0, status="ready_for_complete"):
    def make_line(item_id, item_sku, item_qty):
        price = 1200
        amount = price * item_qty
        return {
            "id": item_id,
            "item": {"id": item_sku, "title": "Research Widget", "price": price},
            "quantity": item_qty,
            "totals": [{"type": "subtotal", "amount": amount},
                       {"type": "total", "amount": amount}],
        }

    lines = [make_line("li-1", sku, quantity)]
    if extra_item:
        lines.append(make_line("li-extra", "SKU-EXTRA", 1))
    total = sum(x["item"]["price"] * x["quantity"] for x in lines)
    data = {
        "id": "checkout-001",
        "merchant": {"id": merchant_id, "name": "Research Merchant"},
        "line_items": lines,
        "status": status,
        "currency": "USD",
        "totals": [{"type": "subtotal", "amount": total},
                   {"type": "total", "amount": total + totals_delta}],
        "links": [],
    }
    # Ensure every research variant remains valid as an upstream Checkout data
    # shape (business invalidity != malformed JSON/Pydantic).
    Checkout.model_validate(data)
    return data


def merchant_signed_jwt(key, payload):
    token = jws.JWS(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    token.add_signature(key, protected=json.dumps({"alg": "ES256", "typ": "JWT"}))
    return token.serialize(compact=True)


def generate():
    issuer = JWK.generate(kty="EC", crv="P-256")
    agent = JWK.generate(kty="EC", crv="P-256")
    merchant_key = JWK.generate(kty="EC", crv="P-256")
    wrong_merchant_key = JWK.generate(kty="EC", crv="P-256")
    now = int(time.time())

    root_model = OpenCheckoutMandate(
        constraints=[
            LineItems(items=[LineItemRequirements(
                id="req-1",
                acceptable_items=[RequiredItem(id="SKU-1", title="Research Widget")],
                quantity=2,
            )]),
            AllowedMerchants(allowed=[Merchant(id="merchant-allowed", name="Research Merchant")]),
        ],
        cnf={"jwk": json.loads(agent.export_public())},
        iat=now,
        exp=now + 3600,
    )
    root = MandateClient().create(
        payloads=[root_model], issuer_key=issuer,
        sd=DisclosureMetadata(children={
            "constraints": DisclosureMetadata(sd_array_indices=[1])
        }),
    )

    versions = {
        "valid": checkout_json(),
        "disallowed_merchant": checkout_json(merchant_id="merchant-denied"),
        "wrong_sku": checkout_json(sku="SKU-OTHER"),
        "wrong_quantity": checkout_json(quantity=1),
        "extra_item": checkout_json(extra_item=True),
        "wrong_total": checkout_json(totals_delta=100),
        "wrong_status": checkout_json(status="completed"),
    }
    valid_jwt = merchant_signed_jwt(merchant_key, versions["valid"])
    signed_jwts = {name: merchant_signed_jwt(merchant_key, data)
                   for name, data in versions.items() if name != "valid"}
    # Reuse the EXACT signed JWT bytes saved by Host. ES256 signing twice can
    # generate distinct signatures for the same JSON; comparing payloads alone
    # is explicitly insufficient for P1-3 Checkout binding.
    signed_jwts["valid"] = valid_jwt
    wrong_signer_jwt = merchant_signed_jwt(wrong_merchant_key, versions["valid"])

    # Validating against the official Python constraint evaluator is useful for
    # distinguishing AP2-like rules from stricter Host-only checks.
    assert check_checkout_constraints(root_model, Checkout.model_validate(versions["valid"])) == []
    for name in ("disallowed_merchant", "wrong_sku"):
        assert check_checkout_constraints(root_model, Checkout.model_validate(versions[name])), name
    # Observed in official AP2 v0.2 SDK: quantity=1 against requirement=2
    # produces no violations. Ruby research profile therefore REQUIRES exact
    # quantity, rather than claiming upstream enforces it.
    assert check_checkout_constraints(
        root_model, Checkout.model_validate(versions["wrong_quantity"])
    ) == []

    def terminal(checkout_jwt, checkout_hash=None):
        if checkout_hash is None:
            checkout_hash = b64(hashlib.sha256(checkout_jwt.encode("ascii")).digest())
        closed = CheckoutMandate(
            checkout_jwt=checkout_jwt, checkout_hash=checkout_hash, iat=now, exp=now + 3600
        )
        wire = kb_sd_jwt.create(
            prev_token=common.parse_token(root), holder_key=agent,
            payload=closed, aud=AUD, nonce=NONCE,
            sd=DisclosureMetadata(), hash_mode="sd_hash"
        ).sd_jwt_issuance
        checked = verify_chain(
            [common.parse_token(root), common.parse_token(wire)],
            public_key_provider=lambda _t: JWK.from_json(issuer.export_public()),
            expected_aud=AUD, expected_nonce=NONCE,
        )
        assert len(checked) == 2
        return wire

    variants = {name: terminal(jwt) for name, jwt in signed_jwts.items()}
    variants["wrong_merchant_signer"] = terminal(wrong_signer_jwt)
    variants["incorrect_checkout_hash"] = terminal(valid_jwt, checkout_hash="invalid-checkout-hash")
    variants["missing_checkout_hash"] = terminal(valid_jwt, checkout_hash="")

    return {
        "source": "AP2 v0.2 official Python SDK signed Open/Closed plus jwcrypto ES256 merchant JWS",
        "ap2_commit": "b4587ac1d055888a73b4b21750973cffba961793",
        "root_open_sdjwt": root,
        "valid_terminal": variants.pop("valid"),
        "bad_terminals": variants,
        "trusted_issuer_public_jwk": json.loads(issuer.export_public()),
        "expected_agent_public_jwk": json.loads(agent.export_public()),
        "trusted_merchant_public_jwk": json.loads(merchant_key.export_public()),
        "untrusted_merchant_public_jwk": json.loads(wrong_merchant_key.export_public()),
        "host_checkout_jwt": valid_jwt,
        "other_signed_checkout_jwt": signed_jwts["wrong_sku"],
        "expected_aud": AUD,
        "expected_nonce": NONCE,
        "expected_checkout_id": "checkout-001",
        "expected_merchant_id": "merchant-allowed",
        "expected_currency": "USD",
        "expected_total_minor": 2400,
    }


if __name__ == "__main__":
    out = Path(sys.argv[1])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(generate(), sort_keys=True, indent=2) + "\n")
    print("PASS: generated Python AP2 Open/Closed with merchant-signed Checkout JWT")
