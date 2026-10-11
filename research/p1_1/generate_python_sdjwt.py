"""Generate genuine AP2 v0.2 root SD-JWT research fixtures, never issuer private keys.

Run in a disposable checkout of the exact pinned official AP2 Python SDK.
Synthetic issuer, agent and merchant names only. No network in generation.
The Ruby verifier must NOT treat this generator as a protocol authority.
"""
import base64
import json
import sys
import time
from pathlib import Path

from jwcrypto.jwk import JWK

from ap2.sdk.disclosure_metadata import DisclosureMetadata
from ap2.sdk.generated.open_checkout_mandate import (
    AllowedMerchants,
    Item,
    LineItemRequirements,
    LineItems,
    OpenCheckoutMandate,
)
from ap2.sdk.generated.types.merchant import Merchant
from ap2.sdk.mandate import MandateClient
from ap2.sdk.sdjwt.sd_jwt import verify as verify_root


def b64url_decode(segment: str):
    return json.loads(base64.urlsafe_b64decode(segment + "=" * (-len(segment) % 4)))


def b64url_encode_json(value):
    return base64.urlsafe_b64encode(
        json.dumps(value, separators=(",", ":")).encode()
    ).decode().rstrip("=")


def generate():
    issuer, wrong_issuer = JWK.generate(kty="EC", crv="P-256"), JWK.generate(kty="EC", crv="P-256")
    holder = JWK.generate(kty="EC", crv="P-256")
    now = int(time.time())
    mandate = OpenCheckoutMandate(
        constraints=[
            LineItems(items=[
                LineItemRequirements(
                    id="item-required",
                    acceptable_items=[Item(id="SKU-1", title="Sample Product")],
                    quantity=1,
                )
            ]),
            AllowedMerchants(allowed=[Merchant(id="shop-approved", name="Sample Merchant")]),
        ],
        cnf={"jwk": json.loads(holder.export_public())},
        iat=now,
        exp=now + 3600,
    )
    metadata = DisclosureMetadata(
        children={"constraints": DisclosureMetadata(sd_array_indices=[1])}
    )
    wire = MandateClient().create(payloads=[mandate], issuer_key=issuer, sd=metadata)
    segments = wire.split("~")
    assert len(segments) >= 4 and segments[-1] == "", "Expected SD-JWT compact disclosure layout"

    merchant_parts = []
    for part in segments[1:-1]:
        decoded = b64url_decode(part)
        if (
            isinstance(decoded, list)
            and len(decoded) == 2
            and isinstance(decoded[1], dict)
            and decoded[1].get("type") == "checkout.allowed_merchants"
        ):
            merchant_parts.append(part)
    assert len(merchant_parts) == 1, "Expected exactly one Merchant array disclosure"

    root_public = json.loads(issuer.export_public())
    wrong_public = json.loads(wrong_issuer.export_public())
    verified = verify_root(wire, JWK.from_json(issuer.export_public()))
    assert len(verified["delegate_payload"][0]["constraints"]) == 2

    hidden = "~".join([segments[0], *[p for p in segments[1:-1] if p != merchant_parts[0]], ""])
    hidden_checked = verify_root(hidden, JWK.from_json(issuer.export_public()))
    assert len(hidden_checked["delegate_payload"][0]["constraints"]) == 1
    # The upstream helper validates the signature and revealed digest, but does
    # not determine whether the removed authority constraint was mandatory.

    decoded = b64url_decode(merchant_parts[0])
    decoded[0] += "-tampered"
    tampered_disclosure = b64url_encode_json(decoded)
    tampered = "~".join([segments[0], *[
        tampered_disclosure if p == merchant_parts[0] else p for p in segments[1:-1]
    ], ""])

    header, payload, signature = segments[0].split(".")
    swapped = ("B" if signature[0] == "A" else "A") + signature[1:]
    bad_signature = "~".join([f"{header}.{payload}.{swapped}", *segments[1:-1], ""])
    duplicate = "~".join([segments[0], *segments[1:-1], merchant_parts[0], ""])
    extra_disclosure = b64url_encode_json(["unexpected", {"type": "checkout.allowed_merchants"}])
    unsolicited = "~".join([segments[0], *segments[1:-1], extra_disclosure, ""])

    return {
        "fixture_origin": "Official AP2 v0.2 Python MandateClient.create; synthetic keys and checkout",
        "ap2_commit": "b4587ac1d055888a73b4b21750973cffba961793",
        "trusted_issuer_public_jwk": root_public,
        "wrong_issuer_public_jwk": wrong_public,
        "full_sd_jwt": wire,
        "hidden_merchant_sd_jwt": hidden,
        "tampered_disclosure_sd_jwt": tampered,
        "tampered_signature_sd_jwt": bad_signature,
        "duplicate_disclosure_sd_jwt": duplicate,
        "unsolicited_disclosure_sd_jwt": unsolicited,
        "expected_constraint_types": ["checkout.line_items", "checkout.allowed_merchants"],
    }


if __name__ == "__main__":
    destination = Path(sys.argv[1])
    destination.parent.mkdir(parents=True, exist_ok=True)
    data = generate()
    destination.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    print("Generated and independently verified Python AP2 root SD-JWT (public keys only).")
