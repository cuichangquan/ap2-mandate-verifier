"""Independent official SD-JWT/Schema and original-wire checks, offline."""
import base64
import hashlib
import json
import subprocess
from pathlib import Path
from ap2.sdk.sdjwt import sd_jwt
from ap2.sdk.sdjwt.common import parse_token, compute_sd_hash
from ap2.sdk.generated.checkout_mandate import CheckoutMandate
from ap2.sdk.jwt_helper import create_jwt, verify_jwt
from jwcrypto.jwk import JWK
from jsonschema import Draft202012Validator


def digest(value):
    return base64.urlsafe_b64encode(hashlib.sha256(value.encode('ascii')).digest()).decode().rstrip('=')


def decode(value):
    return json.loads(base64.urlsafe_b64decode(value + '=' * (-len(value) % 4)))


process = subprocess.Popen(['ruby', '-Ilib', 'test/buyer_interop_driver.rb'], stdin=subprocess.PIPE,
                           stdout=subprocess.PIPE, text=True)


def rpc(operation, **arguments):
    process.stdin.write(json.dumps(dict(operation=operation, arguments=arguments)) + '\n')
    process.stdin.flush()
    response = json.loads(process.stdout.readline())
    assert 'rejected' not in response, operation
    return response


try:
    key = JWK.generate(kty='EC', crv='P-256')
    pem = key.export_to_pem().decode()
    totals = [{'type': 'subtotal', 'amount': 100}, {'type': 'total', 'amount': 100}]
    checkout = {'id': 'office-1', 'merchant': {'id': 'shop', 'name': 'Supplies'},
                'status': 'ready_for_complete', 'currency': 'USD', 'links': [], 'totals': totals,
                'line_items': [{'id': 'line-1', 'item': {'id': 'pen', 'title': 'Office pen', 'price': 100},
                                'quantity': 1, 'totals': totals}]}
    token = create_jwt({'alg': 'ES256', 'typ': 'JWT'}, checkout, key)
    checkout['line_items'] = [dict(id=f'row{i}', item=dict(id=f'product{i % 3}', title='Office supplies', price=100),
                                   quantity=i+1, totals=[dict(type=t, amount=100*(i+1)) for t in ['subtotal', 'total']])
                              for i in range(8)]
    checkout['totals'] = [dict(type=t, amount=3600) for t in ['subtotal', 'total']]
    token = create_jwt({'alg': 'ES256', 'typ': 'JWT'}, checkout, key)
    closed = dict(vct='mandate.checkout.1', checkout_jwt=token, checkout_hash=digest(token),
                  iat=1800000000, exp=1800000060)
    validator = Draft202012Validator(json.loads(Path('/official/code/sdk/schemas/ap2/checkout_mandate.json').read_text()))
    ruby = rpc('issue', checkout_jwt=token, approved_checkout_jwt=token,
               trusted_merchant_public_key_pem=pem, expected_merchant_id='shop',
               issued_at=closed['iat'], expires_at=closed['exp'])
    ruby_key = JWK.from_pem(ruby['public_key_pem'].encode())
    resolved = sd_jwt.verify(ruby['wire'], ruby_key)['delegate_payload']
    assert resolved == [closed]
    validator.validate(resolved[0])
    assert verify_jwt(resolved[0]['checkout_jwt'], key) == checkout
    parsed = parse_token(ruby['wire'])
    assert compute_sd_hash(parsed) == digest(ruby['wire'])
    # Compute both SD commitment edges independently of Ruby and SDK resolver.
    body = decode(parsed.disclosures[0])
    leaf = decode(parsed.disclosures[1])
    assert parsed.payload['delegate_payload'] == [{'...': digest(parsed.disclosures[0])}]
    assert body[1]['_sd'] == [digest(parsed.disclosures[1])]
    assert leaf[1:] == ['checkout_jwt', token] and body[1]['checkout_hash'] == digest(token)
    # Fixed SDK issuance emits the same supported graph. Disclosure order is
    # irrelevant to SD resolution; preserve each generated disclosure verbatim.
    python = sd_jwt.create(CheckoutMandate(**closed), key).sd_jwt_issuance
    parts = python.split('~')
    disclosures = parts[1:-1]
    # Product profile chooses parent-before-leaf order for presentation and
    # receipts. No claim reserialization or re-signing of SDK output occurs.
    disclosures.sort(key=lambda d: len(decode(d)))
    python = '~'.join([parts[0], *disclosures, ''])
    assert sd_jwt.verify(python, key)['delegate_payload'] == [closed]
    args = dict(closed_sd_jwt=python, trusted_provider_public_key_pem=pem,
                trusted_merchant_public_key_pem=pem, expected_checkout_jwt=token,
                expected_merchant_id='shop', verified_at=1800000000)
    result = rpc('verify', **args)
    assert result == dict(verified=True, reference=digest(python))
    for changes in [dict(trusted_provider_public_key_pem=ruby['public_key_pem']),
                    dict(expected_checkout_jwt=token+'x'), dict(verified_at=1800000060),
                    dict(closed_sd_jwt=python.replace('~', '~~', 1))]:
        assert rpc('verify', **(args | changes))['verified'] is False
    # Signed Receipt in both directions and exact complete-wire reference.
    for wire in [ruby['wire'], python]:
        receipt = rpc('receipt', closed_sd_jwt=wire, profile_ref='ap2.checkout.direct.single_merchant',
                      issuer='shop', outcome='Success', issued_at=1800000001, order_id='office-1')
        claims = verify_jwt(receipt['jwt'], JWK.from_pem(receipt['public_key_pem'].encode()))
        assert claims == dict(iss='shop', status='Success', iat=1800000001, order_id='office-1', reference=digest(wire))
        python_receipt = create_jwt({'alg': 'ES256', 'typ': 'JWT'}, claims, key)
        receipt_args = dict(jwt=python_receipt, closed_sd_jwt=wire,
                            profile_ref='ap2.checkout.direct.single_merchant', trusted_public_key_pem=pem,
                            expected_issuer='shop', not_before=1800000000, not_after=1800000060, verified_at=1800000002)
        assert rpc('verify_receipt', **receipt_args)['verified']
        claims['reference'] = digest(parse_token(wire).issuer_jwt)
        compact_only = create_jwt({'alg': 'ES256', 'typ': 'JWT'}, claims, key)
        assert not rpc('verify_receipt', **(receipt_args | dict(jwt=compact_only)))['verified']
    print('PASS Ruby issuance -> official SD-JWT verification; official issuance -> Ruby verification; Schema, disclosure graph, original hashes and bidirectional receipts')
finally:
    process.stdin.close()
    process.wait(timeout=10)
    assert process.returncode == 0
