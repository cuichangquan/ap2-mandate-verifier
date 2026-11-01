"""Offline independent pinned official AP2 SDK, Schema and original-wire oracle."""
import base64
import hashlib
import json
import os
import subprocess
from pathlib import Path
from unittest.mock import patch
from ap2.sdk.sdjwt import sd_jwt, kb_sd_jwt
from ap2.sdk.sdjwt.common import parse_token, compute_sd_hash
from ap2.sdk.generated.open_checkout_mandate import OpenCheckoutMandate
from ap2.sdk.generated.checkout_mandate import CheckoutMandate
from ap2.sdk.disclosure_metadata import DisclosureMetadata
from ap2.sdk.jwt_helper import create_jwt, verify_jwt
from jwcrypto.jwk import JWK
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

NOW = 1800000000
def digest(wire):
    return base64.urlsafe_b64encode(hashlib.sha256(wire.encode('ascii')).digest()).decode().rstrip('=')

def decode(part):
    return json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))

def rpc(operation, **arguments):
    process.stdin.write(json.dumps(dict(operation=operation, arguments=arguments)) + '\n')
    process.stdin.flush()
    return json.loads(process.stdout.readline())

def no_remote(uri):
    raise ValueError('unregistered Schema: ' + uri)
registry = Registry(retrieve=no_remote)
official_root = Path(os.environ.get('AP2_OFFICIAL_ROOT', '/official')).resolve()
assert Path(sd_jwt.__file__).resolve().is_relative_to(official_root), 'SDK and Schema roots differ'
root = official_root / 'code/sdk/schemas'
for path in root.rglob('*.json'):
    body = json.loads(path.read_text())
    registry = registry.with_resource(body['$id'], Resource.from_contents(body))
status = json.loads((root/'ap2/types/receipt_status.json').read_text())
registry = registry.with_resource('https://ap2-protocol.org/schemas/types/receipt_status.json', Resource.from_contents(status))
def schema(name, value):
    Draft202012Validator(json.loads((root/name).read_text()), registry=registry).validate(value)

# No -Ilib: installed mode must use ordinary RubyGems activation with no source overlay.
process = subprocess.Popen(['ruby', str(Path(__file__).with_name('conditional_interop_driver.rb').resolve())],
                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
try:
    key = JWK.generate(kty='EC', crv='P-256')
    pem = key.export_to_pem().decode()
    seller = dict(id='shop', name='Office supplies')
    requirements = [dict(id='choice', quantity=1, acceptable_items=[dict(id=p, title=p) for p in ['A', 'B']]),
                    dict(id='required', quantity=2, acceptable_items=[dict(id='C', title='C')])]
    totals = lambda n: [dict(type=t, amount=n) for t in ['subtotal', 'total']]
    checkout = dict(id='order', merchant=seller, status='ready_for_complete', currency='USD', links=[], totals=totals(300),
                    line_items=[dict(id=f'row{i}', item=dict(id=p, title=p, price=100), quantity=1, totals=totals(100))
                                for i,p in enumerate(['B', 'C', 'C'])])
    token = create_jwt(dict(alg='ES256', typ='JWT'), checkout, key)
    ruby = rpc('issue_open', merchant=seller, requirements=requirements, issued_at=NOW, expires_at=NOW+600)
    provider = JWK.from_pem(ruby['provider'].encode())
    agent = JWK.from_pem(ruby['agent'].encode())
    root_payload = sd_jwt.verify(ruby['root'], provider)
    opening = root_payload['delegate_payload'][0]
    agent_jwk = {k:v for k,v in agent.export_public(as_dict=True).items() if k in ['kty', 'crv', 'x', 'y']}
    assert opening == dict(vct='mandate.checkout.open.1', iat=NOW, exp=NOW+600, cnf=dict(jwk=agent_jwk),
                           constraints=[dict(type='checkout.line_items', items=requirements), dict(type='checkout.allowed_merchants', allowed=[seller])])
    schema('ap2/open_checkout_mandate.json', opening)
    # Independent commitment traversal must consume every disclosure, not just visible claims.
    parts = ruby['root'].split('~')
    mapping = {digest(d): decode(d)[1] for d in parts[1:-1]}
    seen = set()
    def resolve(value):
        if isinstance(value, dict):
            if set(value) == {'...'}:
                commitment = value['...']
                assert commitment not in seen and commitment in mapping
                seen.add(commitment)
                return resolve(mapping[commitment])
            return {k: resolve(v) for k,v in value.items()}
        if isinstance(value, list):
            return [resolve(v) for v in value]
        return value
    assert resolve(decode(parts[0].split('.')[1]))['delegate_payload'] == [opening]
    assert seen == set(mapping)
    args = dict(root_presentation=ruby['root'], checkout_jwt=token, trusted_issuer_public_key_pem=ruby['provider'],
                trusted_merchant_public_key_pem=pem, expected_merchant_id='shop', audience='host', nonce='nonce', verified_at=NOW)
    closed = rpc('issue_closed', **args)
    previous = parse_token(ruby['root']).with_verified_payload(root_payload, root_payload['delegate_payload'])
    verified = kb_sd_jwt.verify(parse_token(closed['closed']), previous, expected_aud='host', expected_nonce='nonce')
    terminal = verified['delegate_payload'][0]
    schema('ap2/checkout_mandate.json', terminal)
    schema('ucp/types/checkout.json', verify_jwt(terminal['checkout_jwt'], key))
    assert terminal['checkout_jwt'] == token and terminal['checkout_hash'] == digest(token)
    assert compute_sd_hash(parse_token(closed['closed'])) == digest(closed['terminal']+'~')
    assert digest(closed['closed']) != digest(closed['terminal']) != digest(ruby['root']+closed['closed'])
    # Review regression: the embedded Checkout fits its own 16KiB wire bound,
    # while the Agent terminal legitimately needs the existing 32KiB bound.
    product = 'p' * 256
    large_requirements = [dict(id='large', quantity=8, acceptable_items=[dict(id=product, title='Product')])]
    large_root = rpc('issue_open', merchant=seller, requirements=large_requirements, issued_at=NOW, expires_at=NOW+600)
    large_checkout = dict(checkout, totals=totals(800), line_items=[dict(id=str(i)+'r'*255,
        item=dict(id=product, title='t'*512, price=100), quantity=1, totals=totals(100)) for i in range(8)])
    large_jwt = create_jwt(dict(alg='ES256', typ='JWT'), large_checkout, key)
    large = rpc('issue_closed', **(args | dict(root_presentation=large_root['root'], checkout_jwt=large_jwt)))
    assert len(large_jwt) < 16384 < len(large['terminal']) <= 32768
    large_payload = sd_jwt.verify(large_root['root'], provider)
    large_prev = parse_token(large_root['root']).with_verified_payload(large_payload, large_payload['delegate_payload'])
    large_verified = kb_sd_jwt.verify(parse_token(large['closed']), large_prev, expected_aud='host', expected_nonce='nonce')
    schema('ap2/open_checkout_mandate.json', large_payload['delegate_payload'][0])
    schema('ap2/checkout_mandate.json', large_verified['delegate_payload'][0])
    schema('ucp/types/checkout.json', verify_jwt(large_jwt, key))
    assert compute_sd_hash(parse_token(large['closed'])) == digest(large['closed'])
    # Official Python issuance -> Ruby full supported signature/constraint path.
    python_open = dict(opening, cnf=dict(jwk=json.loads(key.export_public())))
    python_root = sd_jwt.create(OpenCheckoutMandate(**python_open), key).sd_jwt_issuance
    assert sd_jwt.verify(python_root, key)['delegate_payload'] == [python_open]
    python_closed = dict(terminal)
    # The SDK high-level helper always hides delegate_payload and emits _sd_alg,
    # even with empty metadata. Preserve and explicitly reject that unsupported
    # form; do not relax the old inline profile to force SDK agreement.
    with patch('ap2.sdk.sdjwt.kb_sd_jwt.time.time', return_value=NOW):
        python_wire = kb_sd_jwt.create(parse_token(python_root), key, CheckoutMandate(**python_closed),
                                      aud='host', nonce='nonce', sd=DisclosureMetadata()).sd_jwt_issuance
    helper_wire = python_wire
    python_terminal = create_jwt(dict(alg='ES256', typ='kb+sd-jwt'),
        dict(delegate_payload=[python_closed], iat=NOW, aud='host', nonce='nonce', sd_hash=digest(python_root)), key)
    python_wire = python_terminal + '~'
    verify_args = dict(root_presentation=python_root, terminal_jws=python_terminal, host_checkout_jws=token,
                       trusted_issuer_public_key_pem=pem, expected_agent_public_key_pem=pem, trusted_merchant_public_key_pem=pem,
                       expected_aud='host', expected_nonce='nonce', verified_at=NOW, expected_checkout_id='order',
                       expected_merchant_id='shop', expected_currency='USD', expected_total_minor=300)
    response = rpc('verify', **verify_args)
    assert response == dict(accepted=True), (response, decode(python_terminal.split('.')[1]))
    assert rpc('verify', **(verify_args | dict(terminal_jws=helper_wire[:-1]))).get('rejected') is True
    for changes in [dict(expected_nonce='other'), dict(expected_aud='other'), dict(verified_at=NOW+600),
                    dict(root_presentation=ruby['root']), dict(host_checkout_jws=token+'x'),
                    dict(expected_agent_public_key_pem=ruby['agent'])]:
        assert rpc('verify', **(verify_args | changes)).get('rejected') is True
    for wire in [closed['closed'], python_wire]:
        for outcome, fields in [('Success', dict(order_id='order')), ('Error', dict(error='declined', error_description='Policy'))]:
            receipt = rpc('receipt', closed_sd_jwt=wire, issuer='shop', outcome=outcome, issued_at=NOW, **fields)
            claims = verify_jwt(receipt['jwt'], JWK.from_pem(receipt['key'].encode()))
            schema('ap2/checkout_receipt.json', claims)
            assert claims == dict(iss='shop', status=outcome, iat=NOW, reference=digest(wire), **fields)
            python_receipt = create_jwt(dict(alg='ES256', typ='JWT'), claims, key)
            receipt_args = dict(jwt=python_receipt, closed_sd_jwt=wire, trusted_public_key_pem=pem, expected_issuer='shop',
                                not_before=NOW, not_after=NOW+600, verified_at=NOW)
            assert rpc('verify_receipt', **receipt_args) == dict(verified=True)
            for change in [dict(expected_issuer='other'), dict(trusted_public_key_pem=ruby['agent']), dict(not_before=NOW+1)]:
                assert rpc('verify_receipt', **(receipt_args | change)) == dict(verified=False)
            claims['reference'] = digest(wire[:-1])
            assert rpc('verify_receipt', **(receipt_args | dict(jwt=create_jwt(dict(alg='ES256', typ='JWT'), claims, key)))) == dict(verified=False)

    # Independent Python issuance -> PUBLIC complete verification with saved Host
    # state. This is additional coverage; the scoped differential checks above stay.
    public_provider, public_agent, public_merchant = [JWK.generate(kty='EC', crv='P-256') for _ in range(3)]
    agent_claim = {k: v for k, v in public_agent.export_public(as_dict=True).items() if k in ['kty', 'crv', 'x', 'y']}
    public_open = dict(vct='mandate.checkout.open.1', iat=NOW-100, exp=NOW+600, cnf=dict(jwk=agent_claim),
        constraints=[dict(type='checkout.line_items', items=requirements), dict(type='checkout.allowed_merchants', allowed=[seller])])
    public_root = sd_jwt.create(OpenCheckoutMandate(**public_open), public_provider).sd_jwt_issuance
    assert sd_jwt.verify(public_root, public_provider)['delegate_payload'] == [public_open]
    schema('ap2/open_checkout_mandate.json', public_open)
    public_checkout = dict(checkout, id='public-order')
    public_checkout_jwt = create_jwt(dict(alg='ES256', typ='JWT'), public_checkout, public_merchant)
    assert verify_jwt(public_checkout_jwt, public_merchant) == public_checkout
    schema('ucp/types/checkout.json', public_checkout)
    public_closed = dict(vct='mandate.checkout.1', iat=NOW-100, exp=NOW+600,
        checkout_jwt=public_checkout_jwt, checkout_hash=digest(public_checkout_jwt))
    schema('ap2/checkout_mandate.json', public_closed)
    host_audience, host_nonce = 'conditional-host', 'conditional-nonce'
    public_claims = dict(delegate_payload=[public_closed], iat=NOW, aud=host_audience, nonce=host_nonce,
                         sd_hash=digest(public_root))
    public_terminal = create_jwt(dict(alg='ES256', typ='kb+sd-jwt'), public_claims, public_agent)
    assert verify_jwt(public_terminal, public_agent) == public_claims
    previous = parse_token(public_root).with_verified_payload(
        sd_jwt.verify(public_root, public_provider), [public_open])
    assert kb_sd_jwt.verify(parse_token(public_terminal+'~'), previous,
        expected_aud=host_audience, expected_nonce=host_nonce)['delegate_payload'] == [public_closed]

    # Host expectations are explicit application data, not values decoded from
    # the candidate JWT. Its registry, order and original saved challenge remain
    # unchanged while only an independently re-signed terminal is varied below.
    records = [dict(role=role, identity=identity, tenant_id='tenant', purpose='checkout', key_ref=role.lower(),
                    public_key_pem=key.export_to_pem().decode(), active=True, not_before=NOW-600, not_after=NOW+1200)
               for role, identity, key in [('Issuer', 'issuer', public_provider),
                                           ('Agent', 'agent', public_agent), ('Merchant', 'shop', public_merchant)]]
    selectors = {record['role'].lower(): {name: record[name] for name in ['identity', 'purpose', 'key_ref']}
                 for record in records}
    profile = 'ap2.checkout.single_merchant_multi_item'
    host_order = dict(tenant_id='tenant', buyer_account_id='buyer', order_id='public-order', merchant_id='shop',
                      audience=host_audience, order_version='1', currency='USD', expected_total=300)
    host_trust = dict(snapshot=dict(id='public-registry', policy_version='1', active=True,
        not_before=NOW-600, not_after=NOW+1200, records=records), tenant_id='tenant', verified_at=NOW,
        profile_ref=profile, **selectors)
    assert rpc('prepare_public_host', trust=host_trust, order=host_order, root_presentation=public_root,
        host_checkout_jws=public_checkout_jwt, challenge=dict(challenge_id='public-challenge', nonce=host_nonce,
        issuer_id='public-host', not_before=NOW-10, not_after=NOW+60)) == dict(prepared=True)
    public_result = rpc('verify_public', terminal_jws=public_terminal)
    assert {name: public_result[name] for name in ['success', 'status', 'code', 'evidence_frozen']} == dict(
        success=True, status='verified_research', code='scoped_research_verified', evidence_frozen=True)
    evidence = public_result['evidence']
    assert evidence['contract_version'] == 'ap2.research-evidence.2'
    assert evidence['profile_ref'] == profile
    assert {name: evidence['checkout_binding'][name] for name in host_order} == host_order
    assert evidence['verified_at'] == evidence['valid_from'] == NOW
    assert evidence['valid_until'] == NOW+60
    for name, wire in [('root_presentation_digest', public_root), ('checkout_jwt_digest', public_checkout_jwt),
                       ('terminal_digest', public_terminal)]:
        assert evidence[name] == hashlib.sha256(wire.encode('ascii')).hexdigest()
    assert evidence['verified_challenge']['challenge_id'] == 'public-challenge'
    assert evidence['verified_challenge']['verified_nonce_sha256'] == hashlib.sha256(host_nonce.encode('ascii')).hexdigest()
    assert 'nonce' not in evidence['verified_challenge']
    assert evidence['trust_snapshot']['id'] == 'public-registry'
    assert 'host_challenge_order_binding' in evidence['verified_scope']

    def reject_public(claims, signer, expected_code):
        # A real valid signature over the intended mutation prevents a corrupted
        # signature from masquerading as an audience/nonce/order rejection.
        candidate = create_jwt(dict(alg='ES256', typ='kb+sd-jwt'), claims, signer)
        assert verify_jwt(candidate, signer) == claims
        assert claims['sd_hash'] == digest(public_root)
        rejected = rpc('verify_public', terminal_jws=candidate)
        assert rejected == dict(success=False, status='rejected', code=expected_code,
                                evidence=None, evidence_frozen=False), rejected

    reject_public(public_claims | dict(aud='other-host'), public_agent, 'audience_mismatch')
    reject_public(public_claims | dict(nonce='other-nonce'), public_agent, 'nonce_mismatch')
    changed_checkout = dict(public_checkout, id='different-order')
    changed_jwt = create_jwt(dict(alg='ES256', typ='JWT'), changed_checkout, public_merchant)
    assert verify_jwt(changed_jwt, public_merchant) == changed_checkout
    schema('ucp/types/checkout.json', changed_checkout)
    changed_closed = public_closed | dict(checkout_jwt=changed_jwt, checkout_hash=digest(changed_jwt))
    schema('ap2/checkout_mandate.json', changed_closed)
    reject_public(public_claims | dict(delegate_payload=[changed_closed]), public_agent, 'checkout_binding_mismatch')
    reject_public(public_claims, JWK.generate(kty='EC', crv='P-256'), 'invalid_root_signature')
    # The original proof still succeeds against the same saved Host state.
    assert rpc('verify_public', terminal_jws=public_terminal) == public_result

    public_wire = public_terminal+'~'
    for outcome, fields in [('Success', dict(order_id='public-order')),
                            ('Error', dict(error='declined', error_description='Application policy'))]:
        receipt_claims = dict(iss='shop', status=outcome, iat=NOW, reference=digest(public_wire), **fields)
        schema('ap2/checkout_receipt.json', receipt_claims)
        receipt_jwt = create_jwt(dict(alg='ES256', typ='JWT'), receipt_claims, public_merchant)
        assert verify_jwt(receipt_jwt, public_merchant) == receipt_claims
        assert rpc('verify_public_receipt', jwt=receipt_jwt) == dict(verified=True, outcome=outcome,
            purchase_succeeded=outcome == 'Success', purchase_rejected=outcome == 'Error')
    mode = 'installed Gem' if os.environ.get('AP2_INSTALLED') == '1' else 'source'
    print(json.dumps(dict(public_flow='PASS', mode=mode,
        wire_sha256={name: hashlib.sha256(wire.encode('ascii')).hexdigest() for name, wire in
            [('root_presentation', public_root), ('terminal_jws', public_terminal),
             ('checkout_jwt', public_checkout_jwt), ('closed_sd_jwt', public_wire)]},
        negative_codes=['audience_mismatch', 'nonce_mismatch', 'checkout_binding_mismatch', 'invalid_root_signature'],
        receipt_outcomes=['Success', 'Error']), sort_keys=True))
    print(f'PASS conditional Python issuance -> public InputBuilder.verify ({mode}): immutable Evidence, '
          'independent saved Host state, causal audience/nonce/order/untrusted-Agent negatives, authentic Success/Error receipts')
    print('PASS conditional bidirectional official SDK issuance/signatures, 3-row candidate/repeated-product and large 8-row terminal flows, pinned Schemas, complete commitments, normative final SD hash, Success/Error receipts and negatives')
finally:
    process.stdin.close()
    process.wait(timeout=10)
    assert process.returncode == 0
