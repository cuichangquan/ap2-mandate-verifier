"""P1-10t: ONE cryptographically valid but official-schema INVALID S01.

Synthetic fixed-Issuer research only. Sign with ephemeral Issuer/Agent/Merchant
keys in RAM. Mutate one line_item_requirements.id from "req-1" to INTEGER 123
within the genuinely Issuer-signed Open disclosure, re-commit digest and
re-sign Root. Do not write/upload private keys or real Checkout data.
"""
import json
import sys
import time
from pathlib import Path

from jwcrypto import jws
from jwcrypto.jwk import JWK
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

from ap2.sdk.disclosure_metadata import DisclosureMetadata
from ap2.sdk.generated.checkout_mandate import CheckoutMandate
from ap2.sdk.generated.open_checkout_mandate import (
    AllowedMerchants, Item, LineItems, LineItemRequirements, OpenCheckoutMandate,
)
from ap2.sdk.generated.types.merchant import Merchant
from ap2.sdk.mandate import MandateClient
from ap2.sdk.sdjwt import common, kb_sd_jwt
from ap2.sdk.sdjwt.chain import verify_chain
from ap2.sdk.sdjwt.sd_jwt import verify as verify_root

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "p1_10q"))
from generate_gp01 import decode, compact, sign_compact, digest, rewrite_unique_placeholder  # noqa: E402
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "p1_3"))
from generate_merchant_checkout import AUD, NONCE, b64, checkout_json  # noqa: E402

SHA = "b4587ac1d055888a73b4b21750973cffba961793"
S01_BAD_ID = 123
S01_SCOPE = "checkout.line_items.items[0].id"


def schema_validator():
    """Load pinned official AP2 v0.2 files, no online $ref fetch allowed."""
    upstream = Path(__import__("os").environ["AP2_P110T_UPSTREAM_ROOT"])
    open_schema_path = upstream / "code/sdk/schemas/ap2/open_checkout_mandate.json"
    merchant_schema_path = upstream / "code/sdk/schemas/ap2/types/merchant.json"
    open_schema = json.loads(open_schema_path.read_text())
    merchant_schema = json.loads(merchant_schema_path.read_text())
    Draft202012Validator.check_schema(open_schema)
    Draft202012Validator.check_schema(merchant_schema)
    merchant_resource = Resource.from_contents(merchant_schema)
    registry = Registry().with_resource(merchant_schema["$id"], merchant_resource)
    return Draft202012Validator(open_schema, registry=registry), open_schema


def verify_merchant_signed_jwt(wire, public_jwk, expected_checkout):
    signer = jws.JWS()
    signer.deserialize(wire)
    signer.verify(JWK.from_json(public_jwk))
    assert signer.jose_header["alg"] == "ES256"
    assert signer.payload.decode("utf-8") == compact(expected_checkout)


def generate():
    official_validator, schema = schema_validator()
    assert schema["$defs"]["line_item_requirements"]["properties"]["id"]["type"] == "string"
    issuer = JWK.generate(kty="EC", crv="P-256")
    agent = JWK.generate(kty="EC", crv="P-256")
    merchant = JWK.generate(kty="EC", crv="P-256")
    now = int(time.time())
    root_model = OpenCheckoutMandate(
        constraints=[
            LineItems(items=[LineItemRequirements(
                id="req-1", acceptable_items=[Item(id="SKU-1", title="Research Widget")],
                quantity=2,
            )]),
            AllowedMerchants(allowed=[Merchant(id="merchant-allowed", name="Research Merchant")]),
        ],
        cnf={"jwk": json.loads(agent.export_public())},
        iat=now, exp=now + 3600,
    )
    root_wire = MandateClient().create(
        payloads=[root_model], issuer_key=issuer,
        sd=DisclosureMetadata(children={
            "constraints": DisclosureMetadata(sd_array_indices=[1])
        }),
    )
    issuer_pub = json.loads(issuer.export_public())
    agent_pub = json.loads(agent.export_public())
    merchant_pub = json.loads(merchant.export_public())

    before_claim = verify_root(root_wire, JWK.from_json(issuer.export_public()))["delegate_payload"][0]
    assert not list(official_validator.iter_errors(before_claim)), "valid starting Open must pass pinned schema"

    parts = root_wire.split("~")
    assert parts[-1] == ""
    original_header, original_payload, _ = parts[0].split(".")
    import base64
    header_json = base64.urlsafe_b64decode(
        original_header + "=" * (-len(original_header) % 4)
    ).decode("utf-8")
    outer_payload = decode(original_payload)
    disclosures = parts[1:-1].copy()
    open_idx = [
        i for i, d in enumerate(disclosures)
        if isinstance(decode(d), list) and len(decode(d)) == 2
        and isinstance(decode(d)[1], dict)
        and decode(d)[1].get("vct") == "mandate.checkout.open.1"
    ]
    assert len(open_idx) == 1, "exactly one Open disclosure"
    i = open_idx[0]
    open_disclosure = decode(disclosures[i])
    claim = open_disclosure[1]
    reqs = [
        c for c in claim["constraints"]
        if isinstance(c, dict) and c.get("type") == "checkout.line_items"
    ]
    assert len(reqs) == 1
    assert len(reqs[0]["items"]) == 1
    req = reqs[0]["items"][0]
    assert isinstance(req["id"], str) and req["id"] == "req-1"
    assert set(req.keys()) == {"id", "acceptable_items", "quantity"}
    req["id"] = S01_BAD_ID  # ONE type mutation ONLY, with unchanged keys

    new_open_disclosure = b64(compact(open_disclosure).encode("utf-8"))
    old_digest = digest(disclosures[i])
    new_digest = digest(new_open_disclosure)
    disclosures[i] = new_open_disclosure
    rewrite_unique_placeholder(outer_payload, old_digest, new_digest)
    signed_root = sign_compact(issuer, compact(outer_payload), header_json)
    signed_root += "~" + "~".join([*disclosures, ""])

    verified_root = verify_root(signed_root, JWK.from_json(issuer.export_public()))
    verified_open = verified_root["delegate_payload"][0]
    signed_requirements = [
        c for c in verified_open["constraints"]
        if c.get("type") == "checkout.line_items"
    ][0]["items"]
    assert signed_requirements[0]["id"] == S01_BAD_ID
    assert type(signed_requirements[0]["id"]) is int
    # The pinned schema composes constraints with items.anyOf and contains.
    # One invalid requirement id produces TWO top-level composite failures
    # (anyOf at constraints[0], contains at constraints), while the actual
    # type:string violation is nested in the anyOf error.context.
    # Do not mistake a composite validator error for malformed cryptography
    # or require a nonexistent top-level 'type' error.
    errors = list(official_validator.iter_errors(verified_open))
    error_shapes = {(tuple(e.path), e.validator) for e in errors}
    expected_shapes = {
        (("constraints", 0), "anyOf"),
        (("constraints",), "contains"),
    }
    assert len(errors) == 2 and error_shapes == expected_shapes, [
        (list(e.path), e.validator, e.message) for e in errors
    ]
    compound = next(e for e in errors if e.validator == "anyOf")
    type_errors = [
        child for child in compound.context
        if list(child.path) == ["items", 0, "id"]
        and child.validator == "type"
        and child.validator_value == "string"
    ]
    assert len(type_errors) == 1, [
        (list(child.path), child.validator) for child in compound.context
    ]
    error = type_errors[0]
    full_error_path = [*compound.path, *error.path]
    assert full_error_path == ["constraints", 0, "items", 0, "id"]

    checkout = checkout_json()
    checkout_wire = sign_compact(merchant, compact(checkout))
    verify_merchant_signed_jwt(checkout_wire, merchant_pub, checkout)
    closed = CheckoutMandate(
        checkout_jwt=checkout_wire,
        checkout_hash=b64(__import__("hashlib").sha256(checkout_wire.encode("ascii")).digest()),
        iat=now, exp=now + 3600,
    )
    closed_wire = kb_sd_jwt.create(
        prev_token=common.parse_token(signed_root), holder_key=agent,
        payload=closed, aud=AUD, nonce=NONCE,
        sd=DisclosureMetadata(), hash_mode="sd_hash",
    ).sd_jwt_issuance
    verified_chain = verify_chain(
        [common.parse_token(signed_root), common.parse_token(closed_wire)],
        public_key_provider=lambda _t: JWK.from_json(issuer.export_public()),
        expected_aud=AUD, expected_nonce=NONCE,
    )
    assert len(verified_chain) == 2, "pinned official signed Issuer/Agent chain verification"
    print("S01 SIGNATURE VALID: issuer disclosure/commitment, agent PoP and merchant JWS")
    print("S01 SCHEMA INVALID: pinned anyOf/contains errors; nested id type:string violation (integer 123)")
    return {
        "ap2_commit": SHA,
        "probe_id": "S01",
        "mutation_scope": S01_SCOPE,
        "mutation_value": S01_BAD_ID,
        "upstream_signatures_verified": True,
        "official_schema_invalid": True,
        "schema_error_path": full_error_path,
        "schema_error_keyword": error.validator,
        "root_open_sdjwt": signed_root,
        "valid_terminal": closed_wire,
        "host_checkout_jwt": checkout_wire,
        "trusted_issuer_public_jwk": issuer_pub,
        "expected_agent_public_jwk": agent_pub,
        "trusted_merchant_public_jwk": merchant_pub,
        "expected_aud": AUD,
        "expected_nonce": NONCE,
        "expected_checkout_id": "checkout-001",
        "expected_merchant_id": "merchant-allowed",
        "expected_currency": "USD",
        "expected_total_minor": 2400,
    }


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: generate_s01.py /path/to/temporary-fixture.json")
    out = Path(sys.argv[1])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(generate(), sort_keys=True, indent=2) + "\n")
    print("S01: synthetic ephemeral signing keys never written/uploaded")
