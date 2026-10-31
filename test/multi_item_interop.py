"""Offline fixed-AP2 comparison; all private keys stay in process memory.

Mount fixed b4587ac1 AP2 at /official and set PYTHONPATH=/official/code/sdk/python.
Uses the existing merchant-interop dependency image; never fetches at test time.
"""
import base64
import copy
import hashlib
import itertools
import json
import subprocess
from pathlib import Path

from ap2.sdk.generated.open_checkout_mandate import LineItemRequirements
from ap2.sdk.generated.types.line_item import LineItem
from ap2.sdk.jwt_helper import create_jwt, verify_jwt
from ap2.sdk.mandate import MandateClient
from ap2.sdk.max_flow_helper import evaluate_line_items_max_flow
from ap2.sdk.receipt_wrapper import ReceiptClient
from ap2.sdk.sdjwt.common import compute_sd_hash, parse_token
from jsonschema import Draft202012Validator
from jwcrypto.jwk import JWK
from referencing import Registry, Resource

PIN = 'b4587ac1d055888a73b4b21750973cffba961793'
NOW = 1800000000
PROFILE = 'ap2.checkout.single_merchant_multi_item'


def b64(value):
    return base64.urlsafe_b64encode(value).decode().rstrip('=')


def digest(wire):
    return b64(hashlib.sha256(wire.encode('ascii')).digest())


def totals(amount):
    return [{'type': kind, 'amount': amount} for kind in ['subtotal', 'total']]


def line(identity, sku, quantity, price=100):
    return {'id': identity, 'item': {'id': sku, 'title': 'Merchant ' + sku, 'price': price},
            'quantity': quantity, 'totals': totals(price * quantity)}


def checkout(lines):
    return {'id': 'order', 'merchant': {'id': 'shop', 'name': 'store'}, 'currency': 'USD',
            'status': 'ready_for_complete', 'links': [], 'line_items': lines,
            'totals': totals(sum(row['quantity'] * row['item']['price'] for row in lines))}


def requirement(identity, quantity, candidates):
    return {'id': identity, 'quantity': quantity,
            'acceptable_items': [{'id': sku, 'title': 'Allowed ' + sku} for sku in candidates]}


def constraints(requirements):
    return [{'type': 'checkout.line_items', 'items': requirements},
            {'type': 'checkout.allowed_merchants', 'allowed': [{'id': 'shop', 'name': 'store'}]}]


def independent_assignment(requirements, lines):
    """Small independent exhaustive unit assignment, not max-flow reuse."""
    units = [row['item']['id'] for row in lines for _ in range(row['quantity'])]
    if len(units) != sum(req['quantity'] for req in requirements):
        return False
    for assignment in itertools.product(range(len(requirements)), repeat=len(units)):
        if all(sum(owner == i for owner in assignment) == req['quantity']
               for i, req in enumerate(requirements)) and all(
                   sku in {item['id'] for item in requirements[owner]['acceptable_items']}
                   for sku, owner in zip(units, assignment)):
            return True
    return False


process = subprocess.Popen(['ruby', '-Ilib', 'test/multi_item_interop_driver.rb'],
                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)


def rpc(**request):
    process.stdin.write(json.dumps(request) + '\n')
    process.stdin.flush()
    response = process.stdout.readline()
    assert response, 'Ruby interop driver ended before replying'
    return json.loads(response)


def sdk_accepts(requirements, lines):
    return not evaluate_line_items_max_flow([LineItem.model_validate(row) for row in lines],
        [LineItemRequirements.model_validate(req) for req in requirements])


def no_remote(uri):
    raise ValueError('unregistered schema reference: ' + uri)


try:
    # Register unchanged pinned resources; explicit receipt-status URI alias.
    schema_dir = Path('/official/code/sdk/schemas')
    registry = Registry(retrieve=no_remote)
    for path in schema_dir.rglob('*.json'):
        schema = json.loads(path.read_text())
        registry = registry.with_resource(schema['$id'], Resource.from_contents(schema))
    receipt_schema = json.loads((schema_dir / 'ap2/checkout_receipt.json').read_text())
    status_schema = json.loads((schema_dir / 'ap2/types/receipt_status.json').read_text())
    registry = registry.with_resource('https://ap2-protocol.org/schemas/types/receipt_status.json',
                                     Resource.from_contents(status_schema))

    def validate(relative, value):
        schema = json.loads((schema_dir / relative).read_text())
        Draft202012Validator(schema, registry=registry).validate(value)

    compared = disagreements = 0
    for first, second, q1, q2, a, b in itertools.product(
            [('A',), ('B',), ('A', 'B')], [('A',), ('B',), ('A', 'B')],
            [1, 2], [1, 2], [0, 1, 2], [0, 1, 2]):
        if a + b == 0:
            continue
        reqs = [requirement('r1', q1, first), requirement('r2', q2, second)]
        rows = ([line('a', 'A', a)] if a else []) + ([line('b', 'B', b)] if b else [])
        expected = independent_assignment(reqs, rows)
        actual = rpc(operation='constraints', constraints=constraints(reqs), checkout=checkout(rows))
        assert actual.get('accepted') == expected, (reqs, rows, expected, actual)
        official = sdk_accepts(reqs, rows)
        if official != expected:
            # Fixed SDK permits underfilled requirements, never a Ruby success.
            assert official and not expected and a + b < q1 + q2
            disagreements += 1
        compared += 1
    assert disagreements > 0
    empty = [requirement('wildcard', 1, [])]
    assert sdk_accepts(empty, [line('a', 'A', 1)])
    assert rpc(operation='constraints', constraints=constraints(empty),
               checkout=checkout([line('a', 'A', 1)])).get('accepted') is False

    issuer, agent, merchant = [JWK.generate(kty='EC', crv='P-256') for _ in range(3)]
    public_keys = dict(zip(['Issuer', 'Agent', 'Merchant'],
                          [key.export_to_pem().decode() for key in [issuer, agent, merchant]]))

    def fixture(reqs, rows):
        original = checkout(rows)
        jwt = create_jwt({'alg': 'ES256', 'typ': 'JWT'}, original, merchant)
        disclosures = []

        def commitment(value):
            part = b64(json.dumps(['independent-salt-' + str(len(disclosures)), value],
                                  separators=(',', ':')).encode())
            disclosures.append(part)
            return {'...': digest(part)}

        hidden = copy.deepcopy(reqs)
        for req in hidden:
            req['acceptable_items'] = [commitment(item) for item in req['acceptable_items']]
        root_constraints = [{'type': 'checkout.line_items', 'items': hidden},
            {'type': 'checkout.allowed_merchants', 'allowed': [commitment(original['merchant'])]}]
        opening = {'vct': 'mandate.checkout.open.1', 'iat': NOW - 100, 'exp': NOW + 600,
            'cnf': {'jwk': {key: value for key, value in json.loads(agent.export_public()).items()
                            if key in ['kty', 'crv', 'x', 'y']}}, 'constraints': root_constraints}
        root_payload = {'delegate_payload': [commitment(opening)], '_sd_alg': 'sha-256'}
        root = create_jwt({'alg': 'ES256', 'typ': 'example+sd-jwt'}, root_payload, issuer) + '~' + '~'.join(disclosures) + '~'
        closed = {'vct': 'mandate.checkout.1', 'iat': NOW - 100, 'exp': NOW + 600,
                  'checkout_jwt': jwt, 'checkout_hash': digest(jwt)}
        terminal_payload = {'aud': 'host', 'nonce': 'synthetic-nonce', 'iat': NOW,
            'sd_hash': compute_sd_hash(parse_token(root)), 'delegate_payload': [closed]}
        terminal = create_jwt({'alg': 'ES256', 'typ': 'kb+sd-jwt'}, terminal_payload, agent)
        validate('ap2/open_checkout_mandate.json', dict(opening, constraints=constraints(reqs)))
        validate('ucp/types/checkout.json', original)
        validate('ap2/checkout_mandate.json', closed)
        assert verify_jwt(jwt, merchant) == original
        return {'root': root, 'terminal': terminal, 'checkout_jwt': jwt,
                'expected_total': original['totals'][0]['amount'], 'public_keys': public_keys, 'now': NOW}

    flexible = requirement('flexible', 1, ['A', 'B'])
    fixed = requirement('fixed', 1, ['A'])
    cases = [([flexible, fixed], [line('a', 'A', 1), line('b', 'B', 1)], True),
             ([requirement('a', 2, ['A']), requirement('b', 3, ['B'])],
              [line('a', 'A', 2), line('b', 'B', 3, 125)], True),
             ([requirement('same', 3, ['A'])], [line('a1', 'A', 1), line('a2', 'A', 2)], True),
             ([flexible, fixed], [line('b1', 'B', 1), line('b2', 'B', 1)], False),
             ([requirement('a', 2, ['A'])], [line('a', 'A', 1)], False)]
    wires = []
    for reqs, rows, expected in cases:
        signed = fixture(reqs, rows)
        result = rpc(operation='verify_mandate', **signed)
        assert result.get('success') == expected and result.get('evidence') == expected, result
        wires.append(signed)
    original = wires[0]
    reordered = fixture([fixed, flexible], [line('b', 'B', 1), line('a', 'A', 1)])
    assert rpc(operation='verify_mandate', **reordered)['success']
    assert reordered['checkout_jwt'] != original['checkout_jwt']
    damaged = dict(original, checkout_jwt=original['checkout_jwt'][:-1] +
                   ('A' if original['checkout_jwt'][-1] != 'A' else 'B'))
    assert not rpc(operation='verify_mandate', **damaged)['success']
    wrong_keys = dict(public_keys, Issuer=merchant.export_to_pem().decode())
    assert not rpc(operation='verify_mandate', **dict(original, public_keys=wrong_keys))['success']

    ruby = rpc(operation='sign_checkout', checkout=checkout([line('a', 'A', 2), line('b', 'B', 3, 125)]))
    assert verify_jwt(ruby['jwt'], JWK.from_pem(ruby['public_key_pem'].encode())) == checkout(
        [line('a', 'A', 2), line('b', 'B', 3, 125)])
    assert ruby['checkout_hash'] == digest(ruby['jwt'])

    wire = original['terminal'] + '~'
    reference = compute_sd_hash(parse_token(wire))
    assert reference == digest(wire)
    assert rpc(operation='receipt_reference', wire=wire) == {'reference': reference}
    assert rpc(operation='receipt_reference', wire=original['terminal']) == {'rejected': True}
    helper = MandateClient.get_closed_mandate_jwt(None, original['root'] + '~' + wire)
    assert helper == original['terminal'] and digest(helper) != reference
    client = ReceiptClient()
    for outcome, fields in [('Success', {'order_id': 'order'}),
                            ('Error', {'error': 'declined', 'error_description': 'Application declined'})]:
        receipt = rpc(operation='sign_receipt', arguments={'closed_sd_jwt': wire, 'issuer': 'shop',
                      'outcome': outcome, 'issued_at': NOW, **fields})
        pub = JWK.from_pem(receipt['public_key_pem'].encode())
        claims = verify_jwt(receipt['jwt'], pub)
        assert claims == {'status': outcome, 'iss': 'shop', 'iat': NOW, 'reference': reference, **fields}
        validate('ap2/checkout_receipt.json', claims)
        seen = []

        def exact_reference(actual):
            seen.append(actual)
            return actual == reference

        assert client.verify_receipt(receipt['jwt'], pub, exact_reference,
                                     is_payment_receipt=False) == {'verified': True}
        assert seen == [reference]
        assert client.verify_receipt(receipt['jwt'], pub, lambda actual: actual == digest(helper),
            is_payment_receipt=False).get('error') == 'receipt_reference_not_found_in_store'
        python_jwt = create_jwt({'alg': 'ES256', 'typ': 'JWT'}, claims, merchant)
        verification = {'jwt': python_jwt, 'closed_sd_jwt': wire, 'trusted_public_key_pem': public_keys['Merchant'],
            'expected_issuer': 'shop', 'not_before': NOW - 60, 'not_after': NOW + 60, 'verified_at': NOW}
        assert rpc(operation='verify_receipt', arguments=verification) == {
            'verified': True, 'outcome': outcome, 'purchase_succeeded': outcome == 'Success',
            'purchase_rejected': outcome == 'Error'}
        wrong = create_jwt({'alg': 'ES256', 'typ': 'JWT'}, dict(claims, reference=digest(helper)), merchant)
        assert not rpc(operation='verify_receipt', arguments=dict(verification, jwt=wrong))['verified']
    print(json.dumps({'ap2_source': PIN, 'profile': PROFILE, 'allocation_cases': compared,
        'ruby_matches_independent_exhaustive_oracle': True,
        'sdk_underfilled_requirement_disagreements': disagreements,
        'sdk_empty_candidates_wildcard_differs': True,
        'python_signed_full_builder_verifier_evidence_cases': len(cases) + 1,
        'reordered_resigned_passes_post_signature_mutation_rejects': True,
        'ruby_checkout_to_python_signature_claims_hash': True,
        'bidirectional_success_error_receipts_signature_schema_reference': True,
        'common_parse_token_compute_sd_hash_original_terminal_tilde': True,
        'sdk_compact_leaf_helper_differs': True,
        'unconditional_reference_callbacks': False}, sort_keys=True))
finally:
    process.stdin.close()
    assert process.wait(timeout=10) == 0
