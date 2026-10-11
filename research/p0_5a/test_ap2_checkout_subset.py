"""P0-5a isolated subset checks; NOT the official AP2 pytest suite.

Requires: pytest, pydantic, jsonschema (no network, issuer SDK, or real payments).
Set AP2_SOURCE_ROOT to AP2 v0.2.0 root checkout, or a tree with ap2/sdk
and open_checkout_mandate.json copied byte-for-byte from that revision.
Stubbed dependencies limit the checked surface to exact CheckoutChain methods.
"""
import base64
import hashlib
import importlib
import json
import os
import sys
import types
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator
from pydantic import BaseModel, ValidationError

BASE = Path(os.environ["AP2_SOURCE_ROOT"]).resolve()
SDK = BASE / "code/sdk/python" if (BASE / "code/sdk/python").exists() else BASE
SCHEMA_FILE = (BASE / "code/sdk/schemas/ap2/open_checkout_mandate.json"
               if (BASE / "code/sdk/schemas/ap2/open_checkout_mandate.json").exists()
               else BASE / "open_checkout_mandate.json")
sys.path.insert(0, str(SDK))

FROZEN_BLOBS = {
    "ap2/sdk/generated/types/merchant.py": "0275ea9469d83f1ad658ce080465676fa1775043",
    "ap2/sdk/generated/open_checkout_mandate.py": "0d85f1b79f6334a5db68b188f50ed2226fb94286",
    "ap2/sdk/generated/checkout_mandate.py": "f78fa665dea404373ae693cc7851d16d42996c8d",
    "ap2/sdk/checkout_mandate_chain.py": "2fb4b0e0dcdca6e05f4f1c980a4778c2bfc9f091",
}
SCHEMA_SHA = "e3d9cafa7311d90612c7f908ae9b8821ddc8735a"


def blob_sha(path):
    data = path.read_bytes()
    return hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()


from ap2.sdk.generated.open_checkout_mandate import LineItems, OpenCheckoutMandate  # noqa: E402
from ap2.sdk.generated.checkout_mandate import CheckoutMandate  # noqa: E402

SCHEMA = json.loads(SCHEMA_FILE.read_text())

class CheckoutStub(BaseModel):
    id: str


def constraints_stub(open_mandate, checkout):
    assert open_mandate.constraints == []
    return []


# Replace ONLY unrelated integrations that would require extra Python dependencies.
# DO NOT interpret these checks as cryptographic or full merchant verification.
for name in ("ap2.sdk.constraints", "ap2.sdk.generated.types.checkout", "ap2.sdk.mandate", "ap2.sdk.utils"):
    sys.modules[name] = types.ModuleType(name)
sys.modules["ap2.sdk.constraints"].check_checkout_constraints = constraints_stub
sys.modules["ap2.sdk.generated.types.checkout"].Checkout = CheckoutStub
sys.modules["ap2.sdk.mandate"]._log_event = lambda *args, **kwargs: None
sys.modules["ap2.sdk.utils"].b64url_decode = lambda s: base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))
CheckoutChain = importlib.import_module("ap2.sdk.checkout_mandate_chain").CheckoutMandateChain


def unsigned_jwt(session="checkout-A"):
    enc = lambda b: base64.urlsafe_b64encode(b).decode().rstrip("=")
    return ".".join([enc(b'{"alg":"ES256"}'), enc(json.dumps({"id": session}).encode()), "FAKE_SIGNATURE"])


def chain(closed_jwt=None, closed_hash="obviously_invalid_hash"):
    return CheckoutChain.parse([
        OpenCheckoutMandate(constraints=[], cnf={"jwk": {}}).model_dump(),
        CheckoutMandate(checkout_jwt=closed_jwt or unsigned_jwt(), checkout_hash=closed_hash).model_dump(),
    ])


def test_00_official_source_blob_hashes_match():
    assert {p: blob_sha(SDK / p) for p in FROZEN_BLOBS} == FROZEN_BLOBS
    assert blob_sha(SCHEMA_FILE) == SCHEMA_SHA


def test_01_model_accepts_empty_constraints():
    assert OpenCheckoutMandate.model_validate({"constraints": [], "cnf": {}}).constraints == []


def test_02_schema_rejects_empty_constraints():
    obj = {"vct": "mandate.checkout.open.1", "constraints": [], "cnf": {}}
    assert any(e.validator == "contains" for e in Draft202012Validator(SCHEMA).iter_errors(obj))


def test_03_both_accept_line_items():
    obj = {"vct": "mandate.checkout.open.1", "cnf": {}, "constraints": [{
        "type": "checkout.line_items", "items": [{"id": "r1", "acceptable_items": [{"id": "sku", "title": "Widget"}], "quantity": 1}]}]}
    assert not list(Draft202012Validator(SCHEMA).iter_errors(obj))
    assert isinstance(OpenCheckoutMandate.model_validate(obj).constraints[0], LineItems)


def test_04_invalid_vct_is_rejected():
    with pytest.raises(ValidationError):
        OpenCheckoutMandate.model_validate({"vct": "mandate.checkout.open", "constraints": [], "cnf": {}})


def test_05_unsigned_jwt_payload_passes_helper():
    assert chain().verify(checkout_jwt=unsigned_jwt()) == []


def test_06_invalid_hash_passes_without_expected_hash():
    assert chain(closed_hash="not_a_real_digest").verify(checkout_jwt=unsigned_jwt()) == []


def test_07_explicit_expected_hash_mismatch_is_rejected():
    errors = chain(closed_hash="actual").verify(checkout_jwt=unsigned_jwt(), expected_checkout_hash="different")
    assert len(errors) == 1 and "checkout_hash mismatch" in errors[0]


def test_08_different_closed_and_presented_checkout_passes_helper():
    assert chain(closed_jwt=unsigned_jwt("checkout-A")).verify(checkout_jwt=unsigned_jwt("checkout-B")) == []


def test_09_malformed_jwt_rejected():
    assert "Malformed checkout_jwt" in chain().verify(checkout_jwt="header.payload")[0]


def test_10_missing_jwt_rejected():
    assert "required" in chain().verify()[0]
