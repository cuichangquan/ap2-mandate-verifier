"""Pinned official SDK cross-language checks. Keys remain in process memory."""
import base64
import hashlib
import json
import subprocess
from pathlib import Path
from jsonschema import Draft202012Validator
from referencing import Registry, Resource
from ap2.sdk.receipt_wrapper import ReceiptClient
from ap2.sdk.sdjwt.common import parse_token, compute_sd_hash
from ap2.sdk.mandate import MandateClient
from jwcrypto.jwk import JWK
from ap2.sdk.jwt_helper import create_jwt, verify_jwt


def digest(wire):
    return base64.urlsafe_b64encode(hashlib.sha256(wire.encode('ascii')).digest()).decode().rstrip('=')


totals = [{'type': 'subtotal', 'amount': 200}, {'type': 'total', 'amount': 200}]
checkout = {'id': 'order', 'merchant': {'id': 'shop', 'name': 'store'}, 'currency': 'USD',
            'status': 'ready_for_complete', 'links': [], 'totals': totals,
            'line_items': [{'id': 'line', 'item': {'id': 'sku', 'title': 'item', 'price': 100},
                            'quantity': 2, 'totals': totals}]}
process = subprocess.Popen(['ruby', '-Ilib', 'test/merchant_interop_driver.rb'],
                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)


def rpc(**request):
    process.stdin.write(json.dumps(request) + '\n')
    process.stdin.flush()
    return json.loads(process.stdout.readline())


try:
    ruby = rpc(operation='sign_checkout', checkout=checkout)
    ruby_key = JWK.from_pem(ruby['public_key_pem'].encode())
    assert verify_jwt(ruby['jwt'], ruby_key) == checkout
    assert ruby['checkout_hash'] == digest(ruby['jwt'])
    python_key = JWK.generate(kty='EC', crv='P-256')
    python_public = python_key.export_to_pem().decode()
    token = create_jwt({'alg': 'ES256', 'typ': 'JWT'}, checkout, python_key)
    assert rpc(operation='verify_checkout_signature', jwt=token, public_key_pem=python_public) == {'claims': checkout}
    assert rpc(operation='verify_checkout_signature', jwt=token, public_key_pem=ruby['public_key_pem']) == {'rejected': True}
    closed = {'vct': 'mandate.checkout.1', 'iat': 1800000000, 'exp': 1800000600,
              'checkout_jwt': token, 'checkout_hash': digest(token)}
    terminal = create_jwt({'alg': 'ES256', 'typ': 'kb+sd-jwt'},
                          {'aud': 'host', 'nonce': 'synthetic-nonce', 'iat': 1800000000,
                           'sd_hash': digest('synthetic-root~'), 'delegate_payload': [closed]}, python_key)
    wire = terminal + '~'
    expected_reference = digest(wire)
    assert compute_sd_hash(parse_token(wire)) == expected_reference
    assert rpc(operation='receipt_reference', wire=wire) == {'reference': expected_reference}
    assert rpc(operation='receipt_reference', wire=terminal) == {'rejected': True}
    # Do not use the SDK's leaf helper as the normative hash oracle.
    helper_leaf = MandateClient.get_closed_mandate_jwt(None, 'synthetic-root~~' + wire)
    assert helper_leaf == terminal and digest(helper_leaf) != expected_reference
    schema_root = Path('/official/code/sdk/schemas/ap2')
    schema = json.loads((schema_root / 'checkout_receipt.json').read_text())
    receipt_status = json.loads((schema_root / 'types/receipt_status.json').read_text())
    def no_remote(uri):
        raise ValueError('unregistered schema reference: ' + uri)
    registry = Registry(retrieve=no_remote).with_resources([
        ('https://ap2-protocol.org/schemas/types/receipt_status.json', Resource.from_contents(receipt_status))])
    for schema_path in Path('/official/code/sdk/schemas').rglob('*.json'):
        resource = json.loads(schema_path.read_text())
        registry = registry.with_resource(resource['$id'], Resource.from_contents(resource))
    checkout_schema = json.loads(Path('/official/code/sdk/schemas/ucp/types/checkout.json').read_text())
    closed_schema = json.loads((schema_root / 'checkout_mandate.json').read_text())
    Draft202012Validator(checkout_schema, registry=registry).validate(checkout)
    Draft202012Validator(closed_schema, registry=registry).validate(closed)
    validator = Draft202012Validator(schema, registry=registry)
    client = ReceiptClient()
    verification = {'closed_sd_jwt': wire, 'trusted_public_key_pem': python_public,
                    'expected_issuer': 'shop', 'not_before': 1799999940,
                    'not_after': 1800000060, 'verified_at': 1800000000}
    for outcome, fields in [('Success', {'order_id': 'order'}),
                            ('Error', {'error': 'declined', 'error_description': 'Application declined'})]:
        signed = rpc(operation='sign_receipt', arguments={'closed_sd_jwt': wire, 'issuer': 'shop',
                     'outcome': outcome, 'issued_at': 1800000000, **fields})
        pub = JWK.from_pem(signed['public_key_pem'].encode())
        payload = verify_jwt(signed['jwt'], pub)
        assert payload == {'status': outcome, 'iss': 'shop', 'iat': 1800000000,
                           'reference': expected_reference, **fields}
        validator.validate(payload)
        seen = []
        def reference_in_store(actual):
            seen.append(actual)
            return actual == expected_reference
        # Explicit JWK adapter: the SDK annotation says cryptography key but its
        # verify_jwt implementation calls jwcrypto. No signature check skipped.
        assert client.verify_receipt(signed['jwt'], pub, reference_in_store,
                                     is_payment_receipt=False) == {'verified': True}
        assert seen == [expected_reference]
        assert client.verify_receipt(signed['jwt'], pub, lambda actual: actual == digest(terminal),
                                     is_payment_receipt=False).get('error') == 'receipt_reference_not_found_in_store'
        # Python official SDK helper produces Success; Error uses the official model
        # through the same verification path, not a product Mandate issuer.
        if outcome == 'Success':
            from unittest.mock import patch
            import datetime
            class FixedDateTime(datetime.datetime):
                @classmethod
                def now(cls, tz=None):
                    return cls.fromtimestamp(1800000000, tz)
            with patch('ap2.sdk.receipt_wrapper.datetime.datetime', FixedDateTime):
                model = client.create_checkout_receipt('shop', expected_reference, 'order')
            python_payload = model.model_dump(exclude_none=True)
        else:
            from ap2.sdk.generated.checkout_receipt import CheckoutReceipt
            python_payload = CheckoutReceipt.model_validate(payload).model_dump(exclude_none=True)
        validator.validate(python_payload)
        python_jwt = create_jwt({'alg': 'ES256', 'typ': 'JWT'}, python_payload, python_key)
        result = rpc(operation='verify_receipt', arguments={**verification, 'jwt': python_jwt})
        assert result == {'verified': True, 'outcome': outcome,
                          'purchase_succeeded': outcome == 'Success', 'purchase_rejected': outcome == 'Error'}
        for changed in [dict(python_payload, iss='other'),
                        dict(python_payload, reference=digest(terminal)),
                        dict(python_payload, reference=digest('synthetic-root~~' + wire)),
                        dict(python_payload, iat=1800000001),
                        dict(python_payload, status=outcome.lower())]:
            bad = create_jwt({'alg': 'ES256', 'typ': 'JWT'}, changed, python_key)
            assert not rpc(operation='verify_receipt', arguments={**verification, 'jwt': bad})['verified']
        assert not rpc(operation='verify_receipt', arguments={**verification, 'jwt': python_jwt,
                       'trusted_public_key_pem': signed['public_key_pem']})['verified']
    print(json.dumps({'receipt_both_outcomes_bidirectional_signature_schema_claims': True,
                      'sdk_callback_compared_exact_expected_reference': True,
                      'sd_hash_oracle_original_final_sd_jwt_includes_tilde': True,
                      'sdk_leaf_helper_differs': True,
                      'original_checkout_and_closed_mandate_schema_valid': True,
                      'receipt_status_local_ref_alias_explicit': True,
                      'wrong_issuer_reference_time_case_key_rejected': True}))
    print(json.dumps({'checkout_ruby_to_official_python_signature_claims_hash': True,
                      'checkout_official_python_to_ruby_signature_claims': True,
                      'wrong_key_rejected': True}))
finally:
    process.stdin.close()
    assert process.wait(timeout=10) == 0
