"""P1-2 pinned upstream AP2 v0.2 Python generator: signed Open -> Closed 2-hop.

Research-only: synthetic issuer, agent, and unsigned dummy Checkout JWT.
Only tests SD-JWT agent signature, cnf, sd_hash and expected aud/nonce.
Checkout Merchant signature/authenticity is NOT tested; never treat as payment.
No signing secrets are serialized to fixtures, logs or the repository.
"""
import base64
import hashlib
import json
import sys
import time
from pathlib import Path

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


EXPECTED_AUD = "research-merchant.example"
EXPECTED_NONCE = "challenge-test-only-no-replay-store"


def b64(data):
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def generate():
    issuer = JWK.generate(kty="EC", crv="P-256")
    holder = JWK.generate(kty="EC", crv="P-256")
    wrong_holder = JWK.generate(kty="EC", crv="P-256")
    now = int(time.time())

    open_mandate = OpenCheckoutMandate(
        constraints=[
            LineItems(items=[LineItemRequirements(
                id="line-1",
                acceptable_items=[Item(id="SKU-1", title="Research Widget")],
                quantity=1,
            )]),
            AllowedMerchants(allowed=[Merchant(id="merchant-allowed", name="Allowed")]),
        ],
        cnf={"jwk": json.loads(holder.export_public())},
        iat=now,
        exp=now + 3600,
    )
    sd_metadata = DisclosureMetadata(children={
        "constraints": DisclosureMetadata(sd_array_indices=[1])
    })
    client = MandateClient()
    root = client.create(payloads=[open_mandate], issuer_key=issuer, sd=sd_metadata)
    alternate_root = client.create(payloads=[open_mandate], issuer_key=issuer, sd=sd_metadata)
    assert root != alternate_root, "Two independent ES256 issuances must differ"

    # Demonstration-only compact value, deliberately NOT merchant-signed.
    checkout_header = b64(json.dumps({"alg": "ES256"}, separators=(",", ":")).encode())
    checkout_payload = b64(json.dumps({"id": "research-only"}, separators=(",", ":")).encode())
    checkout_jwt = f"{checkout_header}.{checkout_payload}.NOT_A_SIGNATURE"
    checkout_hash = b64(hashlib.sha256(checkout_jwt.encode("ascii")).digest())
    closed = CheckoutMandate(
        checkout_jwt=checkout_jwt, checkout_hash=checkout_hash, iat=now, exp=now + 3600
    )

    def issue(prev, signer, aud=EXPECTED_AUD, nonce=EXPECTED_NONCE,
              payload=closed, hash_mode="sd_hash"):
        return kb_sd_jwt.create(
            prev_token=common.parse_token(prev),
            holder_key=signer,
            payload=payload,
            aud=aud,
            nonce=nonce,
            sd=DisclosureMetadata(),  # no nested object field redaction
            hash_mode=hash_mode,
        ).sd_jwt_issuance

    terminal = issue(root, holder)
    issuer_pub = JWK.from_json(issuer.export_public())
    verified = verify_chain(
        [common.parse_token(root), common.parse_token(terminal)],
        public_key_provider=lambda _root: issuer_pub,
        expected_aud=EXPECTED_AUD, expected_nonce=EXPECTED_NONCE,
    )
    assert len(verified) == 2
    assert verified[0]["vct"] == "mandate.checkout.open.1"
    assert verified[1]["vct"] == "mandate.checkout.1"

    mismatched_root_terminal = issue(alternate_root, holder)
    wrong_key_terminal = issue(root, wrong_holder)
    wrong_audience_terminal = issue(root, holder, aud="unexpected-merchant")
    wrong_nonce_terminal = issue(root, holder, nonce="unexpected-nonce")
    other_hash_mode_terminal = issue(root, holder, hash_mode="issuer_jwt_hash")
    intermediate_terminal = issue(root, holder, payload=open_mandate)
    parts = terminal.split("~")
    jwt_parts = parts[0].split(".")
    signature = jwt_parts[-1]
    jwt_parts[-1] = ("A" if signature[0] != "A" else "B") + signature[1:]
    altered_signature_terminal = "~".join([".".join(jwt_parts), *parts[1:]])

    result = {
        "source": "Official AP2 v0.2 Python kb_sd_jwt.create / chain.verify_chain",
        "ap2_commit": "b4587ac1d055888a73b4b21750973cffba961793",
        "trusted_issuer_public_jwk": json.loads(issuer.export_public()),
        "expected_agent_public_jwk": json.loads(holder.export_public()),
        "wrong_agent_public_jwk": json.loads(wrong_holder.export_public()),
        "expected_aud": EXPECTED_AUD,
        "expected_nonce": EXPECTED_NONCE,
        "root_open_sdjwt": root,
        "terminal_closed_sdjwt": terminal,
        "wrong_holder_terminal": wrong_key_terminal,
        "wrong_root_binding_terminal": mismatched_root_terminal,
        "wrong_aud_terminal": wrong_audience_terminal,
        "wrong_nonce_terminal": wrong_nonce_terminal,
        "issuer_jwt_hash_terminal": other_hash_mode_terminal,
        "intermediate_terminal": intermediate_terminal,
        "tampered_terminal_signature": altered_signature_terminal,
    }
    # Nothing with a JWK private 'd' property is returned.
    assert all("PRIVATE KEY" not in str(v) for v in result.values())
    return result


if __name__ == "__main__":
    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(generate(), indent=2, sort_keys=True) + "\n")
    print("PASS: 2-hop official AP2 Python chain verified; public data only")
