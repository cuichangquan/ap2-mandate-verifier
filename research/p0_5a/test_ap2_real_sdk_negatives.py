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
