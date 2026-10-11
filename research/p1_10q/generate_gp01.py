"""P1-10q: ONE ephemeral, correctly signed unknown nested constraint probe.

AP2 v0.2.0 research ONLY. No real payment, Host, remote issuer, Gem, or
committed private key. Mutates an *already valid* issuer-signed disclosure,
updates both nested SHA-256 commitments, re-signs Root and issues a properly
Agent-signed Closed from that updated Root.
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
    AllowedMerchants, Item, LineItems, LineItemRequirements, OpenCheckoutMandate,
)
from ap2.sdk.generated.types.merchant import Merchant
from ap2.sdk.mandate import MandateClient
from ap2.sdk.sdjwt import common, kb_sd_jwt
from ap2.sdk.sdjwt.chain import verify_chain
from ap2.sdk.sdjwt.sd_jwt import verify as verify_root

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "p1_3"))
from generate_merchant_checkout import AUD, NONCE, b64, checkout_json  # noqa: E402

FIXED_AP2_SHA = "b4587ac1d055888a73b4b21750973cffba961793"
INJECTED_KEY = "policy_override"
INJECTED_VALUE = "synthetic-unrecognized-authorization-constraint"


def decode(segment):
    return json.loads(base64.urlsafe_b64decode(segment + "=" * (-len(segment) % 4)))


def compact(value):
    return json.dumps(value, separators=(",", ":"), ensure_ascii=True)


def sign_compact(key, raw_payload, raw_header='{"alg":"ES256","typ":"JWT"}'):
    j = jws.JWS(raw_payload.encode("utf-8"))
    j.add_signature(key, protected=raw_header)
    return j.serialize(compact=True)


def digest(segment):
    return b64(hashlib.sha256(segment.encode("ascii")).digest())


def rewrite_unique_placeholder(value, old_digest, new_digest):
    """Change exactly one object-commitment, not a token string or a type field."""
    count = 0

    def visit(item):
        nonlocal count
        if isinstance(item, dict):
            if list(item.keys()) == ["..."] and item["..."] == old_digest:
                item["..."] = new_digest
                count += 1
            else:
                for v in item.values():
                    visit(v)
        elif isinstance(item, list):
            for v in item:
                visit(v)

    visit(value)
    assert count == 1, "Expected exactly one child commitment"
    return value


def generate():
    issuer = JWK.generate(kty="EC", crv="P-256")
    agent = JWK.generate(kty="EC", crv="P-256")
    merchant = JWK.generate(kty="EC", crv="P-256")
    now = int(time.time())

    items = LineItems(items=[LineItemRequirements(
        id="req-1", acceptable_items=[Item(id="SKU-1", title="Research Widget")],
        quantity=2,
    )])
    allowed = AllowedMerchants(allowed=[
        Merchant(id="merchant-allowed", name="Research Merchant")
    ])
    root_model = OpenCheckoutMandate(
        constraints=[items, allowed], cnf={"jwk": json.loads(agent.export_public())},
        iat=now, exp=now + 3600,
    )
    root_original = MandateClient().create(
        payloads=[root_model], issuer_key=issuer,
        sd=DisclosureMetadata(children={
            "constraints": DisclosureMetadata(sd_array_indices=[1])
        }),
    )
    parts = root_original.split("~")
    assert parts[-1] == ""
    outer_header_b64, outer_payload_b64, _ = parts[0].split(".")
    outer_header = base64.urlsafe_b64decode(
        outer_header_b64 + "=" * (-len(outer_header_b64) % 4)
    ).decode("utf-8")
    outer_payload = decode(outer_payload_b64)

    # Exactly one allowed_merchants disclosure and one Open Mandate disclosure.
    disclosures = parts[1:-1].copy()
    allowed_idx = [
        i for i, part in enumerate(disclosures)
        if isinstance(decode(part), list)
        and len(decode(part)) == 2
        and isinstance(decode(part)[1], dict)
        and decode(part)[1].get("type") == "checkout.allowed_merchants"
    ]
    open_idx = [
        i for i, part in enumerate(disclosures)
        if isinstance(decode(part), list)
        and len(decode(part)) == 2
        and isinstance(decode(part)[1], dict)
        and decode(part)[1].get("vct") == "mandate.checkout.open.1"
    ]
    assert len(allowed_idx) == len(open_idx) == 1
    ai, oi = allowed_idx[0], open_idx[0]

    # Modify the SIGNED, DISCLOSED allowed_merchants object itself, not
    # malformed placeholder syntax or the unsigned checkout.
    allowed_disclosure = decode(disclosures[ai])
    original_keys = sorted(allowed_disclosure[1])
    assert original_keys == ["allowed", "type"]
    allowed_disclosure[1][INJECTED_KEY] = INJECTED_VALUE
    allowed_new = b64(compact(allowed_disclosure).encode("utf-8"))
    allowed_digest_before = digest(disclosures[ai])
    allowed_digest_after = digest(allowed_new)
    disclosures[ai] = allowed_new

    open_disclosure = decode(disclosures[oi])
    assert open_disclosure[1]["vct"] == "mandate.checkout.open.1"
    rewrite_unique_placeholder(open_disclosure, allowed_digest_before, allowed_digest_after)
    open_new = b64(compact(open_disclosure).encode("utf-8"))
    open_digest_before = digest(disclosures[oi])
    open_digest_after = digest(open_new)
    disclosures[oi] = open_new

    rewrite_unique_placeholder(outer_payload, open_digest_before, open_digest_after)
    # Cryptographically sign the corrected outer commitment with the Issuer.
    root_signed = sign_compact(issuer, compact(outer_payload), outer_header)
    root_signed += "~" + "~".join([*disclosures, ""])

    resolved = verify_root(root_signed, JWK.from_json(issuer.export_public()))
    open_claim = resolved["delegate_payload"][0]
    constraints = open_claim["constraints"]
    affected = [x for x in constraints if x.get("type") == "checkout.allowed_merchants"]
    assert len(affected) == 1
    assert affected[0][INJECTED_KEY] == INJECTED_VALUE
    assert sorted(affected[0]) == ["allowed", "policy_override", "type"]

    checkout = checkout_json()
    host_jwt = sign_compact(merchant, compact(checkout))
    closed = CheckoutMandate(
        checkout_jwt=host_jwt,
        checkout_hash=b64(hashlib.sha256(host_jwt.encode("ascii")).digest()),
        iat=now, exp=now + 3600,
    )
    terminal = kb_sd_jwt.create(
        prev_token=common.parse_token(root_signed), holder_key=agent,
        payload=closed, aud=AUD, nonce=NONCE,
        sd=DisclosureMetadata(), hash_mode="sd_hash",
    ).sd_jwt_issuance
    verified_chain = verify_chain(
        [common.parse_token(root_signed), common.parse_token(terminal)],
        public_key_provider=lambda _t: JWK.from_json(issuer.export_public()),
        expected_aud=AUD, expected_nonce=NONCE,
    )
    assert len(verified_chain) == 2, "Signed official SDK chain must be valid"

    print("GP01 FIXTURE VALID: Issuer JWS, two Disclosure digests, Agent PoP/chain and Merchant JWS")
    print("GP01 CONTEXT: exactly one unknown nested signed policy_override, otherwise identical 2hop fixture")
    return {
        "ap2_commit": FIXED_AP2_SHA,
        "probe_id": "GP01",
        "fixture_signature_verified_by_python": True,
        "root_open_sdjwt": root_signed,
        "valid_terminal": terminal,
        "host_checkout_jwt": host_jwt,
        "trusted_issuer_public_jwk": json.loads(issuer.export_public()),
        "expected_agent_public_jwk": json.loads(agent.export_public()),
        "trusted_merchant_public_jwk": json.loads(merchant.export_public()),
        "expected_aud": AUD,
        "expected_nonce": NONCE,
        "expected_checkout_id": "checkout-001",
        "expected_merchant_id": "merchant-allowed",
        "expected_currency": "USD",
        "expected_total_minor": 2400,
    }


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: generate_gp01.py <temporary-output.json>")
    path = Path(sys.argv[1])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(generate(), sort_keys=True, indent=2) + "\n")
    print("GP01: no private keys written to disk")
