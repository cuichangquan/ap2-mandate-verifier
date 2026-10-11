"""P0-5a full-dependency regression probes for the pinned upstream AP2 SDK.

Research-only, no external payment calls. These check behavior *of individual
upstream helpers* and MUST NOT be interpreted as whole-protocol exploits or as
a merchant Host authorization decision. Run against official AP2 v0.2.0
commit b4587ac1d055888a73b4b21750973cffba961793.
"""
from __future__ import annotations

import base64
import json
import time

import pytest
from cryptography.hazmat.primitives import serialization
from jwcrypto.jwk import JWK
from sd_jwt.issuer import SDJWTIssuer

from ap2.sdk.checkout_mandate_chain import CheckoutMandateChain
from ap2.sdk.constraints import check_checkout_constraints
from ap2.sdk.generated.checkout_mandate import CheckoutMandate
from ap2.sdk.generated.open_checkout_mandate import (
    AllowedMerchants,
    LineItemRequirements,
    LineItems,
    Item as MandateItem,
)
from ap2.sdk.generated.types.merchant import Merchant
from ap2.sdk.disclosure_metadata import DisclosureMetadata
from ap2.sdk.mandate import MandateClient
from ap2.tests.conftest import make_line_item
from ap2.sdk.generated.open_checkout_mandate import OpenCheckoutMandate
from ap2.sdk.generated.open_payment_mandate import OpenPaymentMandate
from ap2.sdk.sdjwt import common, kb_sd_jwt, parse_token, sd_jwt
from ap2.sdk.sdjwt import chain as chain_mod
from ap2.sdk.sdjwt.chain import verify_chain
from ap2.tests.conftest import make_checkout_jwt, make_cnf, sample_payment_mandate
from ap2.tests.chain_tests import _generate_test_cert


def _root(issuer_key: JWK, holder_key: JWK) -> str:
    return sd_jwt.create(
        payload=OpenPaymentMandate(
            constraints=[], cnf=make_cnf(holder_key)
        ),
        issuer_key=issuer_key,
    ).sd_jwt_issuance


def _verified_root(root: str, issuer_key: JWK):
    parsed = parse_token(root)
    issuer_pub = JWK.from_json(issuer_key.export_public())
    verified_payload = sd_jwt.verify(parsed.canonical, issuer_pub)
    return parsed.with_verified_payload(verified_payload, [])


def _resigned_terminal_with_missing_claims(
    root: str, holder_key: JWK, *, missing: frozenset[str]
) -> str:
    """Sign a *genuine* terminal KB-SD-JWT lacking selected challenge claims."""
    extra = {
        "iat": int(time.time()),
        "aud": "merchant.example",
        "nonce": "challenge-example",
        "sd_hash": common.compute_sd_hash(parse_token(root)),
    }
    for claim in missing:
        del extra[claim]
    claims = common.selectively_disclosable_claims(
        common.delegate_claims_from_model(sample_payment_mandate()),
        None,
        extra,
    )
    issued = common.issue_sd_jwt(
        claims=claims,
        issuer_key=holder_key,
        header_params={"typ": kb_sd_jwt.TYP_TERMINAL[0]},
        add_decoy_claims=False,
        serialization_format="compact",
    )
    return issued.sd_jwt_issuance


@pytest.mark.parametrize("missing", [
    frozenset({"aud"}),
    frozenset({"nonce"}),
    frozenset({"aud", "nonce"}),
])
def test_terminal_missing_challenge_is_accepted_when_expected_values_absent(missing):
    issuer, holder = JWK.generate(kty="EC", crv="P-256"), JWK.generate(kty="EC", crv="P-256")
    root = _root(issuer, holder)
    terminal = _resigned_terminal_with_missing_claims(root, holder, missing=missing)
    verified = kb_sd_jwt.verify(parse_token(terminal), _verified_root(root, issuer))
    assert "iat" in verified
    for claim in missing:
        assert claim not in verified


@pytest.mark.parametrize("missing", ["aud", "nonce"])
def test_explicit_challenge_rejects_absent_claim(missing):
    issuer, holder = JWK.generate(kty="EC", crv="P-256"), JWK.generate(kty="EC", crv="P-256")
    root = _root(issuer, holder)
    terminal = _resigned_terminal_with_missing_claims(root, holder, missing=frozenset({missing}))
    kwargs = {f"expected_{missing}": "merchant.example" if missing == "aud" else "challenge-example"}
    with pytest.raises(ValueError, match=f"{missing} mismatch"):
        kb_sd_jwt.verify(parse_token(terminal), _verified_root(root, issuer), **kwargs)


def _root_with_x5c():
    key, _, cert = _generate_test_cert("Ephemeral Untrusted Root")
    leaf_jwk = JWK.from_pyca(key)
    encoded = base64.b64encode(cert.public_bytes(serialization.Encoding.DER)).decode()
    issued = SDJWTIssuer(
        user_claims={"vct": "mandate.payment.open.1", "iat": int(time.time())},
        issuer_key=leaf_jwk,
        extra_header_parameters={"x5c": [encoded]},
    )
    return parse_token(issued.sd_jwt_issuance)


def test_x5c_with_no_trusted_roots_can_pass_helper():
    token = _root_with_x5c()
    result = verify_chain(
        tokens=[token],
        public_key_provider=chain_mod.X5cOrKidPublicKeyProvider(
            lambda _kid: None, trusted_roots=None
        ),
    )
    assert result[0]["vct"] == "mandate.payment.open.1"


def test_x5c_with_wrong_trusted_root_rejects():
    token = _root_with_x5c()
    _, _, unrelated_root = _generate_test_cert("Different Trusted Root")
    with pytest.raises(ValueError, match="trusted root"):
        verify_chain(
            tokens=[token],
            public_key_provider=chain_mod.X5cOrKidPublicKeyProvider(
                lambda _kid: None, trusted_roots=[unrelated_root]
            ),
        )


def _empty_checkout_chain(first_jwt=None, checkout_hash="obviously-invalid-hash"):
    closed_jwt = first_jwt or make_checkout_jwt(checkout_id="A")
    return CheckoutMandateChain.parse([
        OpenCheckoutMandate(constraints=[], cnf={"jwk": {}}).model_dump(),
        CheckoutMandate(checkout_jwt=closed_jwt, checkout_hash=checkout_hash).model_dump(),
    ])


def test_checkout_hash_not_recomputed_when_expected_omitted():
    checkout = make_checkout_jwt(checkout_id="A")  # upstream creates hdr.payload.sig
    # Note: real constraint evaluation, no stub.
    assert _empty_checkout_chain(checkout).verify(checkout_jwt=checkout) == []


def test_checkout_jwt_from_another_session_not_compared_by_helper():
    a = make_checkout_jwt(checkout_id="A")
    b = make_checkout_jwt(checkout_id="B")
    assert a != b
    assert _empty_checkout_chain(a).verify(checkout_jwt=b) == []


def test_generated_model_accepts_empty_open_checkout_constraints():
    m = OpenCheckoutMandate.model_validate({"constraints": [], "cnf": {}})
    assert m.constraints == []


def test_visible_empty_checkout_constraints_evaluate_to_no_violations():
    jwt = make_checkout_jwt(checkout_id="A")
    chain = _empty_checkout_chain(jwt)
    assert chain.verify(checkout_jwt=jwt) == []


def test_signed_open_checkout_disclosure_can_hide_a_merchant_constraint():
    """If a merchant constraint is withheld, a visible-only evaluator misses it.

    This demonstrates the evidence-completeness question, not a purchase exploit:
    no merchant Host should authorize based on a positive low-level result alone.
    """
    issuer = JWK.generate(kty="EC", crv="P-256")
    holder = JWK.generate(kty="EC", crv="P-256")
    checkout_open = OpenCheckoutMandate(
        constraints=[
            LineItems(items=[LineItemRequirements(
                id="item-required",
                acceptable_items=[MandateItem(id="SKU-1", title="Widget")],
                quantity=1,
            )]),
            AllowedMerchants(allowed=[Merchant(id="shop-approved", name="Approved")]),
        ],
        cnf=make_cnf(holder),
    )
    # Issuer itself marks the second array entry selectively disclosable.
    selective_metadata = DisclosureMetadata(
        children={"constraints": DisclosureMetadata(sd_array_indices=[1])}
    )
    issued = MandateClient().create(
        payloads=[checkout_open],
        issuer_key=issuer,
        sd=selective_metadata,
    )
    original_wire = issued  # MandateClient.create returns a compact token string

    def decoded_disclosure(d):
        if not d:
            return None
        pad = "=" * (-len(d) % 4)
        return json.loads(base64.urlsafe_b64decode(d + pad))

    segments = original_wire.split("~")
    available = []
    hidden_count = 0
    for seg in segments[1:]:
        decoded = decoded_disclosure(seg)
        if (
            isinstance(decoded, list) and len(decoded) == 2
            and isinstance(decoded[1], dict)
            and decoded[1].get("type") == "checkout.allowed_merchants"
        ):
            hidden_count += 1
            continue
        if seg:
            available.append(seg)
    assert hidden_count == 1, "Expected a real SD-JWT array-element disclosure"

    redacted_wire = "~".join([segments[0], *available, ""])
    issuer_pub = JWK.from_json(issuer.export_public())
    verified = MandateClient().verify(
        token=redacted_wire,
        key_or_provider=issuer_pub,  # root-only MandateClient.verify requires JWK
    )
    assert len(verified) == 1
    redacted_open = OpenCheckoutMandate.model_validate(verified[0])
    assert len(redacted_open.constraints) == 1
    assert isinstance(redacted_open.constraints[0], LineItems)

    bad_merchant_checkout = make_checkout_jwt(
        merchant=Merchant(id="shop-other", name="Not Approved"),
        line_items=[make_line_item(
            "SKU-1", "Widget", quantity=1, unit_price=1000
        )],
    )
    checkout = _empty_checkout_chain().extract_parsed_checkout_object(bad_merchant_checkout)
    assert any("not in allowed list" in x for x in check_checkout_constraints(checkout_open, checkout))
    assert check_checkout_constraints(redacted_open, checkout) == []
