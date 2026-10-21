"""Independent synthetic binding/subset predicates, not official O4 Schema."""
import argparse
import hashlib
import json
import os
from pathlib import Path
from jwcrypto import jws
from jwcrypto.jwk import JWK

ORACLE_SHA = '884900e2c3420ebfc2393413ae0e6010db71b28f8a6ef02eec997defa57b8caf'
G = ['root_signature', 'root_graph', 'agent_key_confirmation',
     'agent_signature', 'merchant_signature', 'scoped_schema']
EXPECTED = {
    'FULL': ('scoped_constraints_verified_only', 6),
    'NORMAL': ('scoped_constraints_verified_only', 6),
    'HIDDEN': ('missing_disclosure', 2),
    'UNKNOWN': ('unsupported_disclosure_profile', 2),
    'DUPLICATE': ('duplicate_commitment', 2),
    'EXTRA': ('extra_disclosure', 2),
    'DECOY': ('missing_disclosure', 2),
    'WRONG_AGENT_KEY': ('agent_key_mismatch', 3),
    'WRONG_AGENT_SIGNATURE': ('invalid_root_signature', 4),
    'TAMPERED_AGENT_SIGNATURE': ('invalid_root_signature', 4),
    'ROOT_BINDING': ('root_binding_mismatch', 4),
    'AUDIENCE': ('audience_mismatch', 4), 'NONCE': ('nonce_mismatch', 4),
    'EXPIRED': ('invalid_purchase_time', 2),
    'FUTURE_AGENT': ('invalid_purchase_time', 4),
    'CLOSED_TIME': ('delegation_claim_mismatch', 4),
    'CHECKOUT_ORIGINAL': ('checkout_binding_mismatch', 4),
    'CHECKOUT_HASH': ('checkout_binding_mismatch', 4),
    'WRONG_MERCHANT_KEY': ('invalid_root_signature', 5),
    'CHECKOUT_ID': ('checkout_identity_mismatch', 5),
    'MERCHANT_ID': ('checkout_identity_mismatch', 5),
    'S01': ('invalid_scoped_schema', 6),
    # Unknown type fails before the exact-field helper used as trace marker.
    'UNKNOWN_CONSTRAINT': ('unsupported_constraint', 5),
    'QUANTITY_TYPE': ('invalid_scoped_schema', 6),
    'QUANTITY_MISMATCH': ('constraint_mismatch', 6),
    'AMOUNT': ('amount_mismatch', 6), 'CURRENCY': ('currency_mismatch', 6),
    'TOTALS': ('amount_mismatch', 6),
    'AGENT_BEFORE_S01': ('invalid_root_signature', 4),
    'NONCE_BEFORE_MERCHANT': ('nonce_mismatch', 4),
    'MERCHANT_BEFORE_QUANTITY': ('invalid_root_signature', 5),
    'HIDDEN_BEFORE_AMOUNT': ('missing_disclosure', 2),
}


class Reject(Exception):
    pass


def need(ok, reason):
    if not ok:
        raise Reject(reason)


def public(pem):
    key = JWK.from_pem(pem.encode('ascii'))
    return {k: json.loads(key.export_public())[k] for k in ('kty', 'crv', 'x', 'y')}


def signed(wire, pem, typ, oracle, events, phase):
    events.append(phase)
    parts = wire.split('.')
    need(len(parts) == 3, 'invalid_root_signature')
    header = oracle.strict_json(oracle.decode64(parts[0]))
    need(set(header) <= {'alg', 'typ', 'kid'} and header['alg'] == 'ES256'
         and header['typ'] == typ, 'invalid_root_signature')
    try:
        token = jws.JWS()
        token.deserialize(wire)
        token.verify(JWK.from_pem(pem.encode('ascii')), alg='ES256')
    except Exception as exc:
        raise Reject('invalid_root_signature') from exc
    return oracle.strict_json(oracle.decode64(parts[1]))


def lifetime(claims, now):
    a, b = claims['iat'], claims['exp']
    need(type(a) is int and type(b) is int and 0 <= a < b <= 4102444800
         and a <= now < b and b-a <= 7200, 'invalid_purchase_time')


def binding(i, opening, oracle, events):
    now = i['verified_at']
    events.append('open_time'); lifetime(opening, now)
    events.append('external_agent_match')
    need(opening['cnf']['jwk'] == public(i['expected_agent_public_key_pem']),
         'agent_key_mismatch')
    t = signed(i['terminal_jws'], i['expected_agent_public_key_pem'],
               'kb+sd-jwt', oracle, events, 'agent_signature')
    events.append('root_hash')
    need(t['sd_hash'] == oracle.b64url(hashlib.sha256(i['root_presentation'].encode('ascii')).digest()), 'root_binding_mismatch')
    events.append('aud_nonce')
    need(t['aud'] == i['expected_aud'], 'audience_mismatch')
    need(t['nonce'] == i['expected_nonce'], 'nonce_mismatch')
    events.append('terminal_time')
    need(type(t['iat']) is int and max(now-300, opening['iat']) <= t['iat'] <= now
         and t['iat'] < opening['exp'], 'invalid_purchase_time')
    need(type(t['delegate_payload']) is list and len(t['delegate_payload']) == 1,
         'unsupported_purchase_profile')
    c = t['delegate_payload'][0]
    events.append('closed_time'); lifetime(c, now)
    need((c['iat'], c['exp']) == (opening['iat'], opening['exp']), 'delegation_claim_mismatch')
    events.append('checkout_original_hash')
    wire = i['host_checkout_jws']
    need(c['checkout_jwt'] == wire and c['checkout_hash'] ==
         oracle.b64url(hashlib.sha256(wire.encode('ascii')).digest()), 'checkout_binding_mismatch')
    cart = signed(wire, i['trusted_merchant_public_key_pem'], 'JWT', oracle,
                  events, 'merchant_signature')
    events.append('checkout_identity')
    need(cart['id'] == i['expected_checkout_id'] and
         cart['merchant']['id'] == i['expected_merchant_id'], 'checkout_identity_mismatch')
    need(cart['status'] == 'ready_for_complete', 'unsupported_purchase_profile')
    return cart


def resolve(value, disclosures, oracle):
    mapping = {oracle.b64url(hashlib.sha256(p.encode('ascii')).digest()):
               oracle.strict_json(oracle.decode64(p))[1] for p in disclosures}
    def visit(v):
        if type(v) is dict:
            if set(v) == {'...'}:
                return visit(mapping[v['...']])
            return {k: visit(x) for k, x in v.items()}
        if type(v) is list:
            return [visit(x) for x in v]
        return v
    return visit(value)


def subset(o, cart, i):
    # Explicit narrow policy, separate from all official JSON Schema claims.
    need(type(o['constraints']) is list and len(o['constraints']) == 2,
         'unsupported_constraint')
    reqs, merchants = o['constraints']
    need(reqs['type'] == 'checkout.line_items' and
         merchants['type'] == 'checkout.allowed_merchants', 'unsupported_constraint')
    def exact(v, keys):
        need(type(v) is dict and set(keys) <= set(v), 'invalid_scoped_schema')
        need(set(v) == set(keys), 'unsupported_scoped_profile')
    def single(v):
        need(type(v) is list, 'invalid_scoped_schema')
        need(len(v) == 1, 'unsupported_scoped_profile')
        return v[0]
    def text(v, cap=256):
        need(type(v) is str and len(v)>0, 'invalid_scoped_schema')
        need(len(v.encode()) <= cap, 'constraint_limit_exceeded')
    def integer(v, positive=False):
        need(type(v) is int and v >= (1 if positive else 0), 'invalid_scoped_schema')
        need(v <= (1000000 if positive else 9007199254740991), 'constraint_limit_exceeded')
    exact(reqs, ['type','items']); exact(merchants, ['type','allowed'])
    r = single(reqs['items']); exact(r, ['id','quantity','acceptable_items'])
    text(r['id']); integer(r['quantity'], True)
    sku = single(r['acceptable_items']); exact(sku, ['id','title'])
    text(sku['id']); text(sku['title'],512)
    m = single(merchants['allowed']); exact(m, ['id','name'])
    text(m['id']); text(m['name'],512)
    text(cart['id']); text(cart['merchant']['id']); text(cart['merchant']['name'],512)
    need(cart['merchant'] == m, 'constraint_mismatch')
    text(cart['currency'],3)
    need(cart['currency'] in ['USD','EUR','JPY'], 'unsupported_scoped_profile')
    need(cart['currency'] == i['expected_currency'], 'currency_mismatch')
    need(type(cart['links']) is list, 'invalid_scoped_schema')
    need(not cart['links'], 'unsupported_scoped_profile')
    line = single(cart['line_items']); exact(line, ['id','item','quantity','totals'])
    text(line['id']); integer(line['quantity'],True)
    p = line['item']; exact(p, ['id','title','price'])
    text(p['id']); text(p['title'],512); integer(p['price'])
    need(p['id'] == sku['id'] and p['title'] == sku['title'] and
         line['quantity'] == r['quantity'], 'constraint_mismatch')
    amount = p['price']*line['quantity']
    need(amount <= 9007199254740991, 'constraint_limit_exceeded')
    need(amount == i['expected_total_minor'], 'amount_mismatch')
    for totals in (line['totals'],cart['totals']):
        need(type(totals) is list, 'invalid_scoped_schema')
        need(len(totals) == 2, 'unsupported_scoped_profile')
        for total in totals:
            exact(total,['type','amount']); text(total['type']); integer(total['amount'])
        need(sorted(t['type'] for t in totals) == ['subtotal','total'], 'unsupported_scoped_profile')
        need(all(t['amount'] == amount for t in totals), 'amount_mismatch')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--oracle', required=True)
    parser.add_argument('--fixture', required=True)
    parser.add_argument('--report', required=True)
    parser.add_argument('--gem-replay', required=True)
    args = parser.parse_args()
    source = Path(args.oracle).read_bytes()
    need(hashlib.sha256(source).hexdigest() == ORACLE_SHA, 'oracle identity')
    import types
    oracle = types.ModuleType('o1o3')
    exec(compile(source,args.oracle,'exec'),oracle.__dict__)
    raw = oracle.read_regular(args.fixture, 1048576)
    bundle = oracle.strict_json(raw)
    replay_raw = oracle.read_regular(args.gem_replay, 65536)
    replay = oracle.strict_json(replay_raw)
    need(replay['fixture_sha256'] == hashlib.sha256(raw).hexdigest()
         and replay['case_count'] == 32 and replay['success'] is False
         and replay['evidence'] is None, 'fresh Gem replay identity')
    need(set(bundle['cases']) == set(EXPECTED), 'case set mismatch')
    rows = {}
    for name, i in bundle['cases'].items():
        events = ['root_signature']
        _, payload, disclosures = oracle.original_signature(i['root_presentation'], public(i['trusted_issuer_public_key_pem']))
        # Authenticate the Open independently even for incomplete descendant graph.
        digest = payload['delegate_payload'][0]['...']
        matching = [p for p in disclosures if oracle.b64url(hashlib.sha256(p.encode('ascii')).digest()) == digest]
        need(len(matching) == 1, 'authenticated Open unavailable')
        opening = oracle.strict_json(oracle.decode64(matching[0]))[1]
        events.append('root_graph')
        graph = oracle.inspect_graph(payload,disclosures)
        o2_events = []
        try:
            binding(i, opening, oracle, o2_events)
            o2 = 'VALID_LIMITED_BINDING'
        except Reject as exc:
            o2 = str(exc)
        try:
            need(graph == 'FULL', {'MISSING':'missing_disclosure','UNKNOWN_SLOT':'unsupported_disclosure_profile',
                 'DUPLICATE':'duplicate_commitment','UNUSED':'extra_disclosure'}.get(graph,'unsupported_disclosure_profile'))
            cart = binding(i, opening, oracle, events)
            events.append('local_profile')
            subset(resolve(payload,disclosures,oracle)['delegate_payload'][0],cart,i)
            code = 'scoped_constraints_verified_only'
        except Reject as exc:
            code = str(exc)
        expected_code, entry_count = EXPECTED[name]
        graph_negatives = {'HIDDEN','UNKNOWN','DUPLICATE','EXTRA','DECOY','HIDDEN_BEFORE_AMOUNT'}
        profile_cases = {'FULL','NORMAL','S01','UNKNOWN_CONSTRAINT','QUANTITY_TYPE',
                         'QUANTITY_MISMATCH','AMOUNT','CURRENCY','TOTALS'}
        expected_o2 = 'VALID_LIMITED_BINDING' if name in graph_negatives | profile_cases else expected_code
        need(o2 == expected_o2, name+': isolated O2 mismatch')
        expected_last = ('root_graph' if name in graph_negatives else
                         'local_profile' if name in profile_cases else {
            'WRONG_AGENT_KEY':'external_agent_match',
            'WRONG_AGENT_SIGNATURE':'agent_signature',
            'TAMPERED_AGENT_SIGNATURE':'agent_signature',
            'ROOT_BINDING':'root_hash','AUDIENCE':'aud_nonce','NONCE':'aud_nonce',
            'EXPIRED':'open_time','FUTURE_AGENT':'terminal_time',
            'CLOSED_TIME':'closed_time','CHECKOUT_ORIGINAL':'checkout_original_hash',
            'CHECKOUT_HASH':'checkout_original_hash','WRONG_MERCHANT_KEY':'merchant_signature',
            'CHECKOUT_ID':'checkout_identity','MERCHANT_ID':'checkout_identity',
            'AGENT_BEFORE_S01':'agent_signature','NONCE_BEFORE_MERCHANT':'aud_nonce',
            'MERCHANT_BEFORE_QUANTITY':'merchant_signature'}[name])
        need(events[-1] == expected_last, name+': independent rejection order')
        observed = replay['cases'][name]
        status = 'unverified' if code == 'scoped_constraints_verified_only' else 'rejected'
        need(code == expected_code == observed['code'] and observed['status'] == status,
             name+': result mismatch')
        need(observed['entries'] == G[:entry_count] and observed['success'] is False
             and observed['evidence'] is None, name+': stage/Evidence mismatch')
        for field, wirefield in [('root','root_presentation'),('terminal','terminal_jws'),('checkout','host_checkout_jws')]:
            need(hashlib.sha256(i[wirefield].encode('ascii')).hexdigest() == observed[field+'_sha256'], 'wire mismatch')
        rows[name] = {'expected_code':expected_code,'python_code':code,'gem_code':observed['code'],
          'o2_isolated':o2,'o2_events':o2_events,'python_pipeline_events':events,
          'gem_entries':observed['entries'],'comparison':'MATCH','original_wire_hashes':
          {k:observed[k] for k in ('root_sha256','terminal_sha256','checkout_sha256')}}
    report = {'scope':'LOCAL_SYNTHETIC_O2_O5_AND_MANUAL_SUBSET_COMPARISON',
      'fixture_sha256':hashlib.sha256(raw).hexdigest(),'oracle_sha256':ORACLE_SHA,
      'adapter_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
      'fresh_gem_replay_sha256':hashlib.sha256(replay_raw).hexdigest(),
      'case_count':len(rows),'cases':rows,'official_O4':'NOT_RUN',
      'success':False,'evidence':None,'conclusion':'HOLD',
      'limits':['Shared fixture/profile/cryptographic design; separate implementations',
        'Gem TracePoint entries are reachability, not per-stage PASS',
        'Synthetic external context does not establish Host authority',
        'Official Schema/general constraints/stages8-9 remain unproven',
        'Prior metadata-inclusive 10MB acquisition total remains unmeasured']}
    data = (json.dumps(report,indent=2,sort_keys=True)+'\n').encode()
    need(len(data)<131072,'report cap')
    fd=os.open(args.report,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,'wb') as stream:
        stream.write(data)
    print(f'PASS {len(rows)} independent binding/profile/Gem comparisons; official O4 NOT RUN; HOLD')


if __name__ == '__main__':
    main()
