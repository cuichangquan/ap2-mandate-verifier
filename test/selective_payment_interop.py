"""Offline pinned AP2 primitive interoperability + independent narrow-profile oracle.

The extra signed profile marker and candidate selection use an explicit adapter;
this is not a claim that the upstream facade enforces this Ruby profile.
"""
import base64
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
from unittest.mock import patch

from ap2.sdk.disclosure_metadata import DisclosureMetadata as DM
from ap2.sdk.generated.open_payment_mandate import OpenPaymentMandate
from ap2.sdk.generated.payment_mandate import PaymentMandate
from ap2.sdk.generated.payment_receipt import PaymentReceipt
from ap2.sdk.jwt_helper import create_jwt, verify_jwt
from ap2.sdk.mandate import MandateClient
from ap2.sdk.payment_mandate_chain import PaymentMandateChain
from ap2.sdk.sdjwt import common, kb_sd_jwt, sd_jwt, chain as sdk_chain
from jwcrypto.jwk import JWK
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

NOW = 1_800_000_000
PROFILE = 'ap2.payment.selective_candidates.1'
OFFICIAL = Path(os.environ.get('AP2_OFFICIAL_ROOT', '/official')).resolve()
assert Path(sd_jwt.__file__).resolve().is_relative_to(OFFICIAL), 'unexpected SDK source'
AXES = {'payment.allowed_payees': 'payee', 'payment.allowed_payment_instruments': 'payment_instrument'}
REQUIRED = set(AXES) | {'payment.amount_range', 'payment.reference'}
counts = {'ruby_to_python_cases': 0, 'python_to_ruby_cases': 0, 'negative_cases': 0, 'receipt_cases': 0}

def digest(wire):
    return base64.urlsafe_b64encode(hashlib.sha256(wire.encode('ascii')).digest()).decode().rstrip('=')

def decode(wire):
    return json.loads(base64.urlsafe_b64decode(wire + '=' * (-len(wire) % 4)))

def payload(wire):
    return decode(wire.split('~', 1)[0].split('.')[1])

def exact(value, fields):
    assert isinstance(value, dict) and set(value) == set(fields)

def oracle(wire, fixture):
    """Read only this presentation; no missing disclosure is borrowed from full issuance."""
    assert wire.endswith('~') and len(wire.encode()) <= 65_536
    compact, *encoded = wire.split('~')
    assert encoded.pop() == '' and 2 <= len(encoded) <= 17
    claims = payload(compact)
    exact(claims, ['ap2_profile', '_sd_alg', 'delegate_payload'])
    assert claims['ap2_profile'] == PROFILE and claims['_sd_alg'] == 'sha-256'
    assert len(claims['delegate_payload']) == 1
    exact(claims['delegate_payload'][0], ['...'])
    disclosures = {}
    salts = set()
    for d in encoded:
        a = decode(d)
        assert isinstance(a, list) and len(a) == 2 and isinstance(a[0], str) and 22 <= len(a[0]) <= 128
        assert a[0] not in salts and digest(d) not in disclosures
        salts.add(a[0]); disclosures[digest(d)] = a[1]
    root_digest = claims['delegate_payload'][0]['...']
    opening = copy.deepcopy(disclosures[root_digest])
    exact(opening, ['vct', 'constraints', 'cnf', 'iat', 'exp'])
    assert opening['vct'] == 'mandate.payment.open.1' and opening['iat'] == NOW and opening['exp'] == NOW+60
    assert len(opening['constraints']) == 4 and {c.get('type') for c in opening['constraints']} == REQUIRED
    used = {root_digest}
    seen_commitments = {root_digest}
    for c in opening['constraints']:
        kind = c['type']
        if kind in AXES:
            exact(c, ['type', 'allowed'])
            assert isinstance(c['allowed'], list) and 1 <= len(c['allowed']) <= 8
            marker_flags = [isinstance(v, dict) and set(v) == {'...'} for v in c['allowed']]
            assert all(marker_flags) or not any(marker_flags)
            if all(marker_flags):
                revealed = []
                for marker in c['allowed']:
                    h = marker['...']
                    assert isinstance(h, str) and len(h) == 43 and h not in seen_commitments
                    seen_commitments.add(h)
                    if h in disclosures:
                        revealed.append(disclosures[h]); used.add(h)
                assert len(revealed) == 1
                c['allowed'] = revealed
            field = AXES[kind]
            assert fixture['details'][field] in c['allowed']
            for candidate in c['allowed']:
                mandatory = {'id', 'name'} if field == 'payee' else {'id', 'type'}
                optional = {'website'} if field == 'payee' else {'description'}
                assert isinstance(candidate, dict) and mandatory <= set(candidate) <= mandatory | optional
                assert all(isinstance(v, str) and 1 <= len(v.encode()) <= 512 for v in candidate.values())
        elif kind == 'payment.amount_range':
            exact(c, ['type', 'currency', 'min', 'max'])
            assert c['currency'] == 'USD' and type(c['min']) is int and type(c['max']) is int
            assert c['min'] == 100 and c['max'] == 300
        elif kind == 'payment.reference':
            exact(c, ['type', 'conditional_transaction_id'])
            assert c['conditional_transaction_id'] == digest(fixture['open_checkout'])
    assert used == set(disclosures), 'unused/duplicate/noncandidate disclosure'
    return opening

def privacy(full, selected, closed, fixture, mode):
    decoded = json.dumps([payload(selected), *[decode(d) for d in selected.split('~')[1:-1]],
        payload(closed), *[decode(d) for d in closed.split('~')[1:-1]]])
    hidden = []
    if mode in ['payees', 'both']:
        hidden.extend(v for v in fixture['constraints'][1]['allowed'] if v != fixture['details']['payee'])
    if mode in ['instruments', 'both']:
        hidden.extend(v for v in fixture['constraints'][2]['allowed'] if v != fixture['details']['payment_instrument'])
    selected_parts = set(selected.split('~')[1:-1])
    for candidate in hidden:
        assert all(value not in decoded for value in candidate.values())
        leaf = [d for d in full.split('~')[1:-1] if decode(d)[1] == candidate]
        assert len(leaf) == 1 and leaf[0] not in selected_parts
        assert all(value not in fixture['result_inspection'] for value in candidate.values())
    assert payload(full) == payload(selected) and full.split('~')[0] == selected.split('~')[0]
    assert digest(full) != digest(selected)

registry = Registry(retrieve=lambda uri: (_ for _ in ()).throw(ValueError('unregistered Schema ' + uri)))
schemas = OFFICIAL/'code/sdk/schemas'
for path in schemas.rglob('*.json'):
    data = json.loads(path.read_text())
    registry = registry.with_resource(data['$id'], Resource.from_contents(data))
registry = registry.with_resource('https://ap2-protocol.org/schemas/types/receipt_status.json',
    Resource.from_contents(json.loads((schemas/'ap2/types/receipt_status.json').read_text())))
def schema(name, value):
    Draft202012Validator(json.loads((schemas/'ap2'/name).read_text()), registry=registry).validate(value)

process = subprocess.Popen(['ruby', str(Path(__file__).with_name('selective_payment_interop_driver.rb'))],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
def rpc(operation, **args):
    process.stdin.write(json.dumps({'operation': operation, 'arguments': args})+'\n'); process.stdin.flush()
    line = process.stdout.readline()
    assert line, 'Ruby driver exited'
    return json.loads(line)
def rejected(call):
    result = call()
    assert result.get('rejected') or result.get('verified') is False
    counts['negative_cases'] += 1

def official_chain(open_wire, closed_wire, provider, fixture):
    tokens = [common.parse_token(open_wire), common.parse_token(closed_wire)]
    values = sdk_chain.verify_chain(tokens, lambda _: provider, expected_aud=fixture['audience'],
        expected_nonce=fixture['nonce'], current_time=NOW, clock_skew_seconds=0)
    joined = open_wire.removesuffix('~')+'~~'+closed_wire
    assert MandateClient().verify(joined, lambda _: provider, expected_aud=fixture['audience'],
        expected_nonce=fixture['nonce'], current_time=NOW, clock_skew_seconds=0) == values
    return values

def metadata(mode, hide_constraint=None):
    indexes = {}
    for kind, index in [('payees', 1), ('instruments', 2)]:
        if mode in [kind, 'both']:
            indexes[index] = DM(children={'allowed': DM(sd_array_indices=[0, 1])})
    return DM(children={'constraints': DM(array_children=indexes,
        sd_array_indices=[] if hide_constraint is None else [hide_constraint])})

def python_issuance(opening, provider, mode, hide_constraint=None):
    model = OpenPaymentMandate.model_validate(opening)
    # Explicit new-profile adapter around official AP2 primitives; facade create
    # has no argument for this signed outer profile marker.
    claims = common.selectively_disclosable_claims(common.delegate_claims_from_model(model),
        metadata(mode, hide_constraint), {'ap2_profile': PROFILE})
    return common.issue_sd_jwt(claims=claims, issuer_key=provider,
        header_params=common.header_parameters(provider, 'example+sd-jwt'),
        add_decoy_claims=False, serialization_format='compact').sd_jwt_issuance

def select_python(full, fixture):
    # Preserve original candidate Disclosure bytes; never reconstruct them.
    leaves = []
    for d in full.split('~')[1:-1]:
        value = decode(d)[1]
        if isinstance(value, dict) and (value.get('vct') == 'mandate.payment.open.1' or
                value == fixture['details']['payee'] or value == fixture['details']['payment_instrument']):
            leaves.append(d)
    return '~'.join([full.split('~')[0], *leaves, ''])

def terminal_python(open_wire, fixture, agent, overrides=None):
    closed = dict(fixture['details'], vct='mandate.payment.1', iat=NOW, exp=NOW+60)
    if overrides: closed.update(overrides)
    with patch('ap2.sdk.sdjwt.kb_sd_jwt.time.time', return_value=NOW):
        return kb_sd_jwt.create(common.parse_token(open_wire), agent, PaymentMandate.model_validate(closed),
            aud=fixture['audience'], nonce=fixture['nonce'], sd=DM()).sd_jwt_issuance

try:
    for mode, selected_index in [('payees', 0), ('instruments', 0), ('both', 0), ('both', 1)]:
        f = rpc('fixture', mode=mode, selected_index=selected_index)
        assert not f.get('rejected'), 'Ruby fixture rejected'
        provider = JWK.from_pem(f['provider'].encode())
        opened = oracle(f['selected'], f)
        privacy(f['full'], f['selected'], f['closed'], f, mode)
        values = official_chain(f['selected'], f['closed'], provider, f)
        assert values[0] == opened
        assert values[1] == dict(f['details'], vct='mandate.payment.1', iat=NOW, exp=NOW+60)
        schema('open_payment_mandate.json', values[0]); schema('payment_mandate.json', values[1])
        assert PaymentMandateChain.parse(values).verify(expected_transaction_id=digest(f['checkout_jwt']),
            expected_open_checkout_hash=digest(f['open_checkout'])) == []
        assert payload(f['closed'])['sd_hash'] == digest(f['selected'])
        assert common.compute_sd_hash(common.parse_token(f['selected'])) == digest(f['selected'])
        assert common.compute_sd_hash(common.parse_token(f['closed'])) == digest(f['closed'])
        counts['ruby_to_python_cases'] += 1
        for receipt in f['receipts']:
            claims = verify_jwt(receipt['jwt'], JWK.from_pem(receipt['key'].encode()))
            PaymentReceipt.model_validate(claims); schema('payment_receipt.json', claims)
            assert claims['reference'] == digest(f['closed']) and claims['status'] == receipt['outcome']
            counts['receipt_cases'] += 1

        # A reordered disclosure list preserves issuer JWT but changes sd_hash.
        reverse = '~'.join([f['selected'].split('~')[0], *reversed(f['selected'].split('~')[1:-1]), ''])
        rejected(lambda: rpc('verify_external', open=reverse, closed=f['closed'], provider=f['provider'], agent=f['agent']))
        rebound = rpc('reclose', open=reverse)
        assert 'closed' in rebound and official_chain(reverse, rebound['closed'], provider, f)[0] == opened
        assert payload(rebound['closed'])['sd_hash'] == digest(reverse) != digest(f['selected'])

        # Python keys are independent of Ruby signing and remain process-local.
        py_provider = JWK.generate(kty='EC', crv='P-256'); py_agent = JWK.generate(kty='EC', crv='P-256')
        jwk = {k:v for k,v in py_agent.export_public(as_dict=True).items() if k in ['kty', 'crv', 'x', 'y']}
        whole = dict(vct='mandate.payment.open.1', constraints=copy.deepcopy(f['constraints']) +
            [{'type':'payment.reference', 'conditional_transaction_id':digest(f['open_checkout'])}],
            cnf={'jwk':jwk}, iat=NOW, exp=NOW+60)
        full = python_issuance(whole, py_provider, mode)
        selected = select_python(full, f)
        closed = terminal_python(selected, f, py_agent)
        oracle(selected, f); privacy(full, selected, closed, f, mode)
        actual = rpc('verify_external', open=selected, closed=closed,
            provider=py_provider.export_to_pem().decode(), agent=py_agent.export_to_pem().decode())
        assert actual.get('verified') and actual['payment'] == dict(f['details'], vct='mandate.payment.1', iat=NOW, exp=NOW+60)
        assert official_chain(selected, closed, py_provider, f)[0] == oracle(selected, f)
        for constraint in f['constraints'][1:]:
            field = AXES[constraint['type']]
            selective_axis = (field == 'payee' and mode in ['payees', 'both']) or (field == 'payment_instrument' and mode in ['instruments', 'both'])
            if selective_axis:
                for candidate in constraint['allowed']:
                    if candidate != f['details'][field]:
                        assert all(value not in actual['inspection'] for value in candidate.values())
        # A complete confidential issuance is not a reduced presentation, even
        # when the Agent signs the exact full bytes and selected Closed values.
        full_terminal = terminal_python(full, f, py_agent)
        rejected(lambda: rpc('verify_external', open=full, closed=full_terminal,
            provider=py_provider.export_to_pem().decode(), agent=py_agent.export_to_pem().decode()))
        counts['python_to_ruby_cases'] += 1
        for outcome in ['Success', 'Error']:
            claims = dict(iss='processor', payment_id='payment-1', status=outcome, iat=NOW, reference=digest(closed))
            claims.update(dict(psp_confirmation_id='python-psp', network_confirmation_id='python-network') if outcome == 'Success' else
                dict(error='declined', error_description='Python synthetic rejection'))
            receipt = create_jwt({'alg':'ES256','typ':'JWT'}, claims, py_provider)
            result = rpc('verify_receipt', jwt=receipt, closed=closed, key=py_provider.export_to_pem().decode())
            assert result['verified'] and result['outcome'] == outcome and result['succeeded'] == (outcome=='Success')
            counts['receipt_cases'] += 1
            rejected(lambda: rpc('verify_receipt', jwt=receipt, closed=f['closed'], key=py_provider.export_to_pem().decode()))

        # Authentic but semantically wrong Closed values are rejected by Ruby
        # and independently by the official typed conditions (not syntax alone).
        bad_closed = terminal_python(selected, f, py_agent, {'payment_amount':{'amount':301, 'currency':'USD'}})
        bad_values = official_chain(selected, bad_closed, py_provider, f)
        assert PaymentMandateChain.parse(bad_values).verify(expected_open_checkout_hash=digest(f['open_checkout']))
        rejected(lambda: rpc('verify_external', open=selected, closed=bad_closed,
            provider=py_provider.export_to_pem().decode(), agent=py_agent.export_to_pem().decode()))

        # Show the exact upstream safety boundary: generic AP2 SD/Schema/typed
        # checking can accept a hidden amount constraint. New profile rejects it.
        hidden_full = python_issuance(whole, py_provider, mode, hide_constraint=0)
        hidden_open = select_python(hidden_full, f)
        hidden_closed = terminal_python(hidden_open, f, py_agent)
        hidden_values = official_chain(hidden_open, hidden_closed, py_provider, f)
        schema('open_payment_mandate.json', hidden_values[0])
        assert len(hidden_values[0]['constraints']) == 3
        assert PaymentMandateChain.parse(hidden_values).verify(expected_open_checkout_hash=digest(f['open_checkout'])) == []
        try:
            oracle(hidden_open, f)
        except (AssertionError, KeyError):
            pass
        else:
            raise AssertionError('independent oracle accepted hidden mandatory amount')
        rejected(lambda: rpc('verify_external', open=hidden_open, closed=hidden_closed,
            provider=py_provider.export_to_pem().decode(), agent=py_agent.export_to_pem().decode()))

    print(json.dumps(dict(status='PASS', counts=counts,
        candidate_axis_modes=3, selected_original_slots=[0, 1],
        source='official AP2 b4587ac1d055888a73b4b21750973cffba961793',
        scope='three candidate-axis modes; official SD/chain/typed constraints/Schema + independent profile/privacy oracle; separate Python-key issuance adapter to Ruby; Success/Error Receipts',
        limitations=['MandateClient.create/present does not expose this signed outer profile marker or candidate-array selection; explicit lowlevel profile adapter is used',
            'upstream generic SDK/Schema/typed constraints do not enforce mandatory four-constraint closure; signed hidden-amount control is accepted upstream and rejected by Ruby/independent oracle',
            'no full facade support, generic AP2 conformance, actual payments or production trust claim']), sort_keys=True))
finally:
    process.stdin.close()
    process.wait(timeout=10)
    assert process.returncode == 0
