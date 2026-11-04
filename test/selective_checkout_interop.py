"""Pinned official SD primitives plus independent closed Checkout profile oracle.

Offline synthetic keys. This is not generic AP2 or facade conformance.
"""
import base64
import copy
import hashlib
import itertools
import json
import os
import platform
from pathlib import Path
import subprocess
from ap2.sdk.disclosure_metadata import DisclosureMetadata as DM
from ap2.sdk.generated.checkout_mandate import CheckoutMandate
from ap2.sdk.generated.open_checkout_mandate import LineItemRequirements
from ap2.sdk.generated.types.line_item import LineItem
from ap2.sdk.max_flow_helper import evaluate_line_items_max_flow
from ap2.sdk.checkout_mandate_chain import CheckoutMandateChain
from ap2.sdk.jwt_helper import create_jwt, verify_jwt
from ap2.sdk.mandate import MandateClient
from ap2.sdk.sdjwt import common, sd_jwt, chain
from jwcrypto.jwk import JWK
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

NOW = 1800000000
PROFILE = 'ap2.checkout.selective_candidates.1'
OFFICIAL = Path(os.environ.get('AP2_OFFICIAL_ROOT', '/official')).resolve()
assert Path(sd_jwt.__file__).resolve().is_relative_to(OFFICIAL)
counts = dict(ruby_to_python_cases=0, python_to_ruby_cases=0, receipt_cases=0, negative_cases=0)
wire_evidence = []

def decode(w):
    return json.loads(base64.urlsafe_b64decode(w + '=' * (-len(w) % 4)))
def digest(w):
    return base64.urlsafe_b64encode(hashlib.sha256(w.encode('ascii')).digest()).decode().rstrip('=')
def payload(w):
    return decode(w.split('~')[0].split('.')[1])
def exact(v, keys):
    assert isinstance(v, dict) and set(v) == set(keys)

def assignment(reqs, rows):
    """Bounded exhaustive unit ownership, independent of either maxflow implementation."""
    assert len(reqs) <= 4 and sum(r['quantity'] for r in rows) <= 8
    units = [r['item']['id'] for r in rows for _ in range(r['quantity'])]
    if not reqs or any(type(r['quantity']) is not int or r['quantity'] <= 0 or not r['acceptable_items'] for r in reqs):
        return False
    if len(units) != sum(r['quantity'] for r in reqs):
        return False
    for owners in itertools.product(range(len(reqs)), repeat=len(units)):
        if all(owners.count(i) == r['quantity'] for i, r in enumerate(reqs)) and all(
                sku in {v['id'] for v in reqs[i]['acceptable_items']} for sku, i in zip(units, owners)):
            return True
    return False

def oracle(wire, checkout):
    """Resolve only supplied bytes; missing mandatory conditions cannot be repaired."""
    assert wire.endswith('~')
    compact, *parts = wire.split('~'); assert parts.pop() == ''
    outer = payload(compact)
    exact(outer, ['ap2_profile', '_sd_alg', 'delegate_payload'])
    assert outer['ap2_profile'] == PROFILE and outer['_sd_alg'] == 'sha-256'
    assert len(outer['delegate_payload']) == 1
    exact(outer['delegate_payload'][0], ['...'])
    disclosures, salts = {}, set()
    for p in parts:
        d = decode(p)
        assert len(d) == 2 and isinstance(d[0], str) and 22 <= len(d[0]) <= 128
        assert d[0] not in salts and digest(p) not in disclosures
        salts.add(d[0]); disclosures[digest(p)] = d[1]
    root = outer['delegate_payload'][0]['...']; used = {root}; seen = {root}
    opened = copy.deepcopy(disclosures[root])
    exact(opened, ['vct', 'cnf', 'iat', 'exp', 'constraints'])
    assert opened['vct'] == 'mandate.checkout.open.1' and opened['iat'] == NOW-100 and opened['exp'] == NOW+600
    constraints = opened['constraints']
    assert len(constraints) == 2 and {c.get('type') for c in constraints} == {'checkout.allowed_merchants', 'checkout.line_items'}
    def candidates(markers, singleton=False):
        assert isinstance(markers, list) and 1 <= len(markers) <= 8
        result = []
        for m in markers:
            exact(m, ['...']); h = m['...']
            assert isinstance(h, str) and len(h) == 43 and h not in seen
            seen.add(h)
            if h in disclosures:
                v = disclosures[h]; exact(v, ['id', 'name'] if singleton else ['id', 'title'])
                assert all(isinstance(x, str) and x for x in v.values())
                used.add(h); result.append(v)
        assert len(result) == 1 if singleton else len(result) >= 1
        return result
    for c in constraints:
        if c['type'] == 'checkout.allowed_merchants':
            exact(c, ['type', 'allowed']); c['allowed'] = candidates(c['allowed'], True)
            assert c['allowed'][0] == checkout['merchant']
        else:
            exact(c, ['type', 'items']); assert c['items']
            ids = set()
            for req in c['items']:
                exact(req, ['id', 'quantity', 'acceptable_items'])
                assert req['id'] not in ids; ids.add(req['id'])
                assert type(req['quantity']) is int and req['quantity'] > 0
                req['acceptable_items'] = candidates(req['acceptable_items'])
            assert assignment(c['items'], checkout['line_items'])
    assert used == set(disclosures)
    return opened

schemas = OFFICIAL/'code/sdk/schemas'
registry = Registry(retrieve=lambda uri: (_ for _ in ()).throw(ValueError('unknown Schema')))
for path in schemas.rglob('*.json'):
    obj = json.loads(path.read_text()); registry = registry.with_resource(obj['$id'], Resource.from_contents(obj))
registry = registry.with_resource('https://ap2-protocol.org/schemas/types/receipt_status.json',
    Resource.from_contents(json.loads((schemas/'ap2/types/receipt_status.json').read_text())))
def schema(name, value):
    Draft202012Validator(json.loads((schemas/'ap2'/name).read_text()), registry=registry).validate(value)

process = subprocess.Popen(['ruby', str(Path(__file__).with_name('selective_checkout_interop_driver.rb'))],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
def rpc(operation, **arguments):
    process.stdin.write(json.dumps(dict(operation=operation, arguments=arguments))+'\n'); process.stdin.flush()
    line = process.stdout.readline(); assert line, 'Ruby RPC exited'
    return json.loads(line)
def official(root, closed, key):
    tokens = [common.parse_token(root), common.parse_token(closed)]
    values = chain.verify_chain(tokens, lambda _: key, expected_aud='host', expected_nonce='test-nonce', current_time=NOW, clock_skew_seconds=0)
    assert MandateClient().verify(root.removesuffix('~')+'~~'+closed, lambda _: key,
        expected_aud='host', expected_nonce='test-nonce', current_time=NOW, clock_skew_seconds=0) == values
    return values

def issue(opened, provider, hide=None):
    groupmeta = {}
    for i, c in enumerate(opened['constraints']):
        if c.get('type') == 'checkout.allowed_merchants':
            groupmeta[i] = DM(children={'allowed': DM(sd_array_indices=list(range(len(c['allowed']))))})
        elif c.get('type') == 'checkout.line_items':
            reqmeta = {j: DM(sd_keys=['quantity'] if hide == 'quantity' and j == 0 else [], children={'acceptable_items': DM(sd_array_indices=list(range(len(r['acceptable_items']))))}) for j, r in enumerate(c['items'])}
            groupmeta[i] = DM(children={'items': DM(array_children=reqmeta, sd_array_indices=[0] if hide == 'group' else [])})
    metadata = DM(children={'constraints': DM(array_children=groupmeta, sd_array_indices=[1] if hide == 'merchant' else [])})
    claims = common.selectively_disclosable_claims(copy.deepcopy(opened), metadata, {'ap2_profile':PROFILE})
    return common.issue_sd_jwt(claims=claims, issuer_key=provider, header_params=common.header_parameters(provider, 'example+sd-jwt'), add_decoy_claims=False, serialization_format='compact').sd_jwt_issuance

def select(full, selected_values):
    kept = []
    for p in full.split('~')[1:-1]:
        d = decode(p)
        if len(d) == 2 and (isinstance(d[1], dict) and d[1].get('vct') == 'mandate.checkout.open.1' or d[1] in selected_values):
            kept.append(p)
    return '~'.join([full.split('~')[0], *kept, ''])
def close(root, f, agent, checkout_jwt=None):
    jwt = checkout_jwt or f['checkout_jwt']
    obj = dict(vct='mandate.checkout.1', iat=NOW-100, exp=NOW+600, checkout_jwt=jwt, checkout_hash=digest(jwt))
    # Existing Checkout finalClosed grammar is inline, while the facade's KB
    # creator makes its delegate payload disclosable. Use official JWT primitive
    # with explicit exact-byte binding adapter, not a false facade PASS.
    CheckoutMandate.model_validate(obj)
    return create_jwt({'alg':'ES256','typ':'kb+sd-jwt'},
        dict(aud='host', nonce='test-nonce', iat=NOW, sd_hash=digest(root), delegate_payload=[obj]), agent)+'~'

def raw_mutation(full, provider, transform):
    """Authentic issuer signature over an intentionally invalid commitment graph."""
    original = payload(full)
    old_hash = original['delegate_payload'][0]['...']
    leaves = full.split('~')[1:-1]
    root_part = next(p for p in leaves if digest(p) == old_hash)
    disclosed = decode(root_part)
    transform(disclosed[1])
    new_part = base64.urlsafe_b64encode(json.dumps(disclosed, separators=(',', ':')).encode()).decode().rstrip('=')
    original['delegate_payload'][0]['...'] = digest(new_part)
    jwt = create_jwt({'alg':'ES256','typ':'example+sd-jwt'}, original, provider)
    assert verify_jwt(jwt, provider) == original
    return '~'.join([jwt, *[new_part if p == root_part else p for p in leaves], ''])

def privacy(full, reduced, closed, selected_values, inspection):
    visible = [decode(p) for p in reduced.split('~')[1:-1]] + [payload(closed)]
    for p in full.split('~')[1:-1]:
        d = decode(p)
        if len(d) == 2 and isinstance(d[1], dict) and 'vct' not in d[1] and d[1] not in selected_values:
            assert p not in reduced and d[1] not in visible
            for value in d[1].values():
                assert value not in json.dumps(visible) and value not in inspection
    assert full.split('~')[0] == reduced.split('~')[0] and digest(full) != digest(reduced)

def item(sku): return dict(id=sku, title='Product '+sku)
def req(identity, qty, skus): return dict(id=identity, quantity=qty, acceptable_items=[item(s) for s in skus])
def checkout(skus):
    totals = lambda amount: [dict(type=t, amount=amount) for t in ['subtotal','total']]
    rows = [dict(id='line-'+str(i), item=dict(item(s), price=100), quantity=q, totals=totals(100*q)) for i,(s,q) in enumerate(skus)]
    return dict(id='order', merchant=dict(id='shop', name='Store'), currency='USD', status='ready_for_complete', links=[], line_items=rows, totals=totals(sum(q for _,q in skus)*100))

try:
    # Actual upstream boundary controls: SDK acceptance is never promoted to
    # narrow-profile permission when mandatory demand/candidates are absent.
    for requirements in [[req('underfilled', 2, ['A'])], [req('empty-wildcard', 1, [])]]:
        rows = checkout([('A',1)])['line_items']
        assert not assignment(requirements, rows)
        assert evaluate_line_items_max_flow([LineItem.model_validate(r) for r in rows],
            [LineItemRequirements.model_validate(r) for r in requirements]) == []
    # Multiple retained candidates, overlapping groups and original nonzero slots.
    cases = [([req('ab',1,['A','B','private-item-X']), req('a',2,['A','private-item-Y'])], [('A',2),('B',1)], [[0,1],[0]]),
             ([req('a',2,['private-item-Z','A']), req('b',1,['private-item-Q','B'])], [('A',2),('B',1)], [[1],[1]])]
    for requirements, cart, selection in cases:
        f = rpc('fixture', requirements=requirements, checkout=checkout(cart), selection=selection)
        assert not f.get('rejected'), 'Ruby fixture rejected'
        values = official(f['selected'], f['closed'], JWK.from_pem(f['provider'].encode()))
        assert values[0] == oracle(f['selected'], f['checkout'])
        schema('open_checkout_mandate.json', values[0]); schema('checkout_mandate.json', values[1])
        assert CheckoutMandateChain.parse(values).verify(expected_checkout_hash=digest(f['checkout_jwt']), checkout_jwt=f['checkout_jwt']) == []
        assert payload(f['closed'])['sd_hash'] == digest(f['selected']) == common.compute_sd_hash(common.parse_token(f['selected']))
        chosen = [f['checkout']['merchant']] + [r['acceptable_items'][j] for r, indexes in zip(requirements, selection) for j in indexes]
        privacy(f['full'], f['selected'], f['closed'], chosen, f['inspection']); counts['ruby_to_python_cases'] += 1
        for receipt in f['receipts']:
            claims = verify_jwt(receipt['jwt'], JWK.from_pem(receipt['key'].encode()))
            schema('checkout_receipt.json', claims)
            assert claims['reference'] == digest(f['closed']) and claims['status'] == receipt['outcome']
            counts['receipt_cases'] += 1
        reverse = '~'.join([f['selected'].split('~')[0], *reversed(f['selected'].split('~')[1:-1]), ''])
        stale = rpc('verify_external', open=reverse, closed=f['closed'], provider=f['provider'], agent=f['agent'])
        assert not stale.get('verified'); counts['negative_cases'] += 1
        rebound = rpc('reclose', open=reverse); assert 'closed' in rebound
        assert payload(rebound['closed'])['sd_hash'] == digest(reverse) != digest(f['selected'])
        official(reverse, rebound['closed'], JWK.from_pem(f['provider'].encode()))
        provider, agent = [JWK.generate(kty='EC', crv='P-256') for _ in range(2)]
        whole = dict(vct='mandate.checkout.open.1', iat=NOW-100, exp=NOW+600,
            cnf={'jwk':{k:v for k,v in agent.export_public(as_dict=True).items() if k in ['kty','crv','x','y']}},
            constraints=[dict(type='checkout.line_items', items=copy.deepcopy(requirements)), dict(type='checkout.allowed_merchants', allowed=f['merchants'])])
        def verify(root, terminal):
            return rpc('verify_external', open=root, closed=terminal, provider=provider.export_to_pem().decode(), agent=agent.export_to_pem().decode())
        full = issue(whole, provider); reduced = select(full, chosen); terminal = close(reduced, f, agent)
        got = verify(reduced, terminal); assert got.get('verified'), got
        assert official(reduced, terminal, provider)[0] == oracle(reduced, f['checkout'])
        privacy(full, reduced, terminal, chosen, got['inspection']); counts['python_to_ruby_cases'] += 1
        wire_evidence.append(dict(case=len(wire_evidence)+1,
            ruby={name:hashlib.sha256(f[name].encode('ascii')).hexdigest() for name in ['full','selected','closed','checkout_jwt']},
            python=dict(full=hashlib.sha256(full.encode('ascii')).hexdigest(), selected=hashlib.sha256(reduced.encode('ascii')).hexdigest(), closed=hashlib.sha256(terminal.encode('ascii')).hexdigest())))
        for outcome in ['Success','Error']:
            claims = dict(iss='shop', status=outcome, iat=NOW, reference=digest(terminal))
            claims.update(dict(order_id='order') if outcome == 'Success' else dict(error='declined', error_description='Synthetic decline'))
            receipt = create_jwt({'alg':'ES256','typ':'JWT'}, claims, provider)
            checked = rpc('verify_receipt', jwt=receipt, closed=terminal, key=provider.export_to_pem().decode())
            assert checked.get('verified') and checked['outcome'] == outcome
            counts['receipt_cases'] += 1
            assert not rpc('verify_receipt', jwt=receipt, closed=f['closed'], key=provider.export_to_pem().decode()).get('verified')
            counts['negative_cases'] += 1
        # Causal, authentically signed semantic and original-graph negatives.
        bads = []
        empty = copy.deepcopy(whole); empty['constraints'][0]['items'][0]['acceptable_items'] = []
        bads.append(('empty_candidates', empty, None))
        under = copy.deepcopy(whole); under['constraints'][0]['items'][0]['quantity'] += 1
        bads.append(('demand_underfill', under, None))
        wrong = copy.deepcopy(whole); wrong['constraints'][1]['allowed'] = [dict(id='private-wrong-shop',name='Wrong merchant')]
        bads.append(('unauthorized_merchant', wrong, None))
        unknown = copy.deepcopy(whole); unknown['constraints'].append(dict(type='checkout.unknown', value=True))
        bads.append(('unknown_constraint', unknown, None))
        hall = copy.deepcopy(whole)
        # Equal total supply/demand but the A-only requirement cannot receive B.
        hall['constraints'][0]['items'] = [req('a-only', 1, ['A']), req('b-only', 2, ['B'])]
        bads.append(('equal_total_hall_deficit', hall, None))
        for name, bad, hide in bads + [('hidden_group',whole,'group'), ('hidden_quantity',whole,'quantity'), ('hidden_merchant_constraint',whole,'merchant')]:
            badfull = issue(bad, provider, hide); badroot = select(badfull, chosen); badterminal = close(badroot, f, agent)
            try: oracle(badroot, f['checkout'])
            except (AssertionError,KeyError,TypeError): pass
            else: raise AssertionError('independent oracle accepted '+name)
            assert not verify(badroot, badterminal).get('verified'), name
            counts['negative_cases'] += 1
        duplicate = reduced.removesuffix('~')+'~'+reduced.split('~')[1]+'~'
        assert not verify(duplicate, close(duplicate, f, agent)).get('verified'); counts['negative_cases'] += 1
        # Nested/duplicate commitments are signed by the trusted synthetic issuer.
        def nested(opened):
            opened['constraints'][0]['items'][0]['quantity'] = {'...': digest('hidden-quantity')}
        def duplicate_marker(opened):
            slots = opened['constraints'][0]['items'][0]['acceptable_items']
            slots.append(copy.deepcopy(slots[0]))
        for transform in [nested, duplicate_marker]:
            malformed = select(raw_mutation(full, provider, transform), chosen)
            assert not verify(malformed, close(malformed, f, agent)).get('verified')
            counts['negative_cases'] += 1
    print(json.dumps(dict(status='PASS', counts=counts, source='official AP2 b4587ac1d055888a73b4b21750973cffba961793',
        runtime=dict(python=platform.python_version(), platform=platform.platform(), ruby=f['runtime']), wire_sha256=wire_evidence,
        scope='two overlapping/nonzero-slot Checkout cases each direction; exact reduced bytes; independent exhaustive quantity allocation; candidate privacy; Success/Error Receipt',
        limitations=['explicit lowlevel adapter required for profile marker/candidate filtering; facade selection drops array leaf disclosures',
          'Python inline Checkout terminal uses official create_jwt plus explicit exact-byte binding adapter; facade KB creation makes delegate payload disclosable',
          'official maxflow helper permits empty-candidate wildcard and demand underfill; independent oracle requires full demand and supply closure',
          'synthetic offline scoped comparison, not generic AP2 conformance or payment execution']), sort_keys=True))
finally:
    process.stdin.close(); process.wait(timeout=10)
