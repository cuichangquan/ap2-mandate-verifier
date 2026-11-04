"""Offline pinned AP2 primitives plus independent PISP/time policy oracle.

Fresh Python keys stay in memory. New signed-profile adapters are explicit;
upstream permissive date behavior is measured rather than declared conformant.
"""
import base64
import copy
import datetime as dt
from decimal import Decimal
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
from ap2.sdk.disclosure_metadata import DisclosureMetadata as DM
from ap2.sdk.generated.payment_mandate import PaymentMandate
from ap2.sdk.mandate import MandateClient
from ap2.sdk.payment_mandate_chain import PaymentMandateChain
from ap2.sdk.sdjwt import common, sd_jwt, chain
from ap2.sdk.jwt_helper import create_jwt, verify_jwt
from jwcrypto.jwk import JWK
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

NOW = 1800000000
OFFICIAL = Path(os.environ.get('AP2_OFFICIAL_ROOT','/official')).resolve()
assert Path(sd_jwt.__file__).resolve().is_relative_to(OFFICIAL)
counts = dict(ruby_to_python=0, python_to_ruby=0, receipts=0, negatives=0, upstream_disagreements=0)
wire_evidence = []
disagreements = []

def digest(w):
    return base64.urlsafe_b64encode(hashlib.sha256(w.encode('ascii')).digest()).decode().rstrip('=')
def decode(w):
    return json.loads(base64.urlsafe_b64decode(w+'='*(-len(w)%4)))
def payload(w): return decode(w.split('~')[0].split('.')[1])
def sha(w): return hashlib.sha256(w.encode('ascii')).hexdigest()

def instant(text):
    """Independent calendar library + exact Decimal instant, never lexical/float."""
    assert isinstance(text,str) and len(text) <= 40
    m = re.fullmatch(r'([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,9}))?(Z|[+-][0-9]{2}:[0-9]{2})',text)
    assert m and m[6] != '-00:00'
    calendar = dt.date.fromisoformat(m[1])
    h,minute,second = map(int,m.group(2,3,4))
    assert 0 <= h <= 23 and 0 <= minute <= 59 and 0 <= second <= 59
    offset = 0
    if m[6] != 'Z':
        oh,om = map(int,m[6][1:].split(':')); assert oh <= 23 and om <= 59
        offset = (oh*3600+om*60)*(1 if m[6][0]=='+' else -1)
    return Decimal(calendar.toordinal()*86400+h*3600+minute*60+second-offset)+Decimal('0.'+(m[5] or '0'))

def pisp(value):
    assert isinstance(value,dict) and set(value)=={'legal_name','brand_name','domain_name'}
    assert all(isinstance(v,str) and 0<len(v.encode())<=512 for v in value.values())
    domain=value['domain_name']; assert len(domain)<=253 and domain.isascii()
    assert all(re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?',label) for label in domain.split('.'))

def policy(opening, closed, trusted, execution_at):
    pisp(closed['pisp']); pisp(trusted)
    assert closed['pisp']==trusted and instant(closed['execution_date'])==instant(execution_at)
    if opening is None: return
    extras=[c for c in opening['constraints'] if c['type'] in ['payment.allowed_pisps','payment.execution_date']]
    assert 1<=len(extras)<=2 and len({c['type'] for c in extras})==len(extras)
    for field in ['pisp','execution_date']:
        if field in opening: assert opening[field]==closed[field]
    for c in extras:
        if c['type']=='payment.allowed_pisps':
            assert set(c)=={'type','allowed'} and 1<=len(c['allowed'])<=8
            assert len({json.dumps(v,sort_keys=True) for v in c['allowed']})==len(c['allowed'])
            for v in c['allowed']: pisp(v)
            assert closed['pisp'] in c['allowed']
        else:
            assert set(c)<={'type','not_before','not_after'} and ('not_before' in c or 'not_after' in c)
            low=instant(c['not_before']) if 'not_before' in c else None
            high=instant(c['not_after']) if 'not_after' in c else None
            assert low is None or high is None or low<=high
            at=instant(closed['execution_date'])
            assert (low is None or low<=at) and (high is None or at<=high)

def resolve(wire):
    """Resolve current presentation only; opaque payee/card commitments remain allowed."""
    claims=payload(wire); disclosures={digest(p):decode(p) for p in wire.split('~')[1:-1]}
    used=set()
    def walk(v,path=()):
        if isinstance(v,dict):
            assert '_sd' not in v, 'hidden property outside narrow grammar'
            if v.get('type')=='payment.allowed_pisps':
                assert all(isinstance(p,dict) and set(p)=={'legal_name','brand_name','domain_name'} for p in v['allowed'])
            if set(v)=={'...'}:
                h=v['...']
                if h not in disclosures:
                    assert len(path)>=2 and path[-2]=='allowed' and path[0]=='candidate'
                    return None
                assert h not in used; used.add(h); d=disclosures[h]
                assert len(d)==2
                return walk(d[1],path)
            return {k:walk(x,path+(k,)) for k,x in v.items()}
        if isinstance(v,list):
            # Only candidate arrays belonging to payee/instrument constraints can
            # contain unresolved elements. Mandatory PISP/date stay fully inline.
            result=[]
            for i,x in enumerate(v):
                childpath=path+(i,)
                if path and path[-1]=='allowed': childpath=('candidate','allowed',i)
                decoded=walk(x,childpath)
                if decoded is not None: result.append(decoded)
            return result
        return v
    resolved=walk(claims)['delegate_payload'][0]
    assert used==set(disclosures)
    return resolved

schemas=OFFICIAL/'code/sdk/schemas'; registry=Registry(retrieve=lambda _: (_ for _ in ()).throw(ValueError('unknown Schema')))
for path in schemas.rglob('*.json'):
    obj=json.loads(path.read_text()); registry=registry.with_resource(obj['$id'],Resource.from_contents(obj))
registry=registry.with_resource('https://ap2-protocol.org/schemas/types/receipt_status.json',Resource.from_contents(json.loads((schemas/'ap2/types/receipt_status.json').read_text())))
def schema(name,v): Draft202012Validator(json.loads((schemas/'ap2'/name).read_text()),registry=registry).validate(v)

process=subprocess.Popen(['ruby',str(Path(__file__).with_name('payment_policy_interop_driver.rb'))],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
def rpc(operation,**arguments):
    process.stdin.write(json.dumps(dict(operation=operation,arguments=arguments))+'\n');process.stdin.flush()
    line=process.stdout.readline();assert line,'Ruby RPC exited';return json.loads(line)

def issuance(value,key,profile,selective=False,hide=None):
    children={}
    if selective:
        children={'constraints':DM(array_children={i:DM(children={'allowed':DM(sd_array_indices=list(range(len(c['allowed']))))})
            for i,c in enumerate(value['constraints']) if c['type'] in ['payment.allowed_payees','payment.allowed_payment_instruments']})}
    if hide:
        constraint_meta=children.setdefault('constraints',DM())
        if hide=='pisp_constraint': constraint_meta.sd_array_indices=[3]
        elif hide=='date_constraint': constraint_meta.sd_array_indices=[4]
        elif hide=='pisp_identity': constraint_meta.array_children[3]=DM(children={'allowed':DM(all_array_children=DM(sd_keys=['legal_name']))})
        elif hide=='date_bounds': constraint_meta.array_children[4]=DM(sd_keys=['not_before','not_after'])
    claims=common.selectively_disclosable_claims(copy.deepcopy(value),DM(children=children),{'ap2_profile':profile})
    return common.issue_sd_jwt(claims=claims,issuer_key=key,header_params=common.header_parameters(key,'example+sd-jwt'),add_decoy_claims=False,serialization_format='compact').sd_jwt_issuance

def selected(full,details):
    return '~'.join([full.split('~')[0],*[p for p in full.split('~')[1:-1] if
        isinstance(decode(p)[1],dict) and (decode(p)[1].get('vct')=='mandate.payment.open.1' or decode(p)[1] in [details['payee'],details['payment_instrument']])],''])

def terminal(opening,value,key,profile):
    return create_jwt({'alg':'ES256','typ':'kb+sd-jwt'},dict(delegate_payload=[value],iat=NOW,aud='provider',nonce='policy-nonce',sd_hash=digest(opening),ap2_profile=profile),key)+'~'

def official(f,root,closed,key):
    if f['mode']=='direct':
        value=resolve(closed)
        verified=MandateClient().verify(closed,key,payload_type=PaymentMandate,current_time=NOW,clock_skew_seconds=0)
        assert verified.mandate_payload.model_dump(exclude_none=True)==value
        return None,value
    values=chain.verify_chain([common.parse_token(root),common.parse_token(closed)],lambda _:key,expected_aud='provider',expected_nonce='policy-nonce',current_time=NOW,clock_skew_seconds=0)
    assert MandateClient().verify(root.removesuffix('~')+'~~'+closed,lambda _:key,expected_aud='provider',expected_nonce='policy-nonce',current_time=NOW,clock_skew_seconds=0)==values
    return values

try:
    # Lexical order is not instant order. Oracle sanity checks at both boundaries.
    assert instant('2027-01-15T13:00:00.125+01:00')==instant('2027-01-15T12:00:00.125Z')
    assert instant('2027-01-15T12:00:00.1Z')<instant('2027-01-15T12:00:00.125Z')
    for mode in ['direct','conditional','selective']:
        f=rpc('fixture',mode=mode);assert not f.get('rejected'),('fixture',mode)
        rubykey=JWK.from_pem(f['provider'].encode())
        opening,closed=official(f,f['root'],f['closed'],rubykey)
        assert closed==dict(f['details'],vct='mandate.payment.1',iat=NOW,exp=NOW+60)
        schema('payment_mandate.json',closed)
        if opening:
            schema('open_payment_mandate.json',opening)
            assert resolve(f['root'])==opening and payload(f['closed'])['sd_hash']==digest(f['root'])
            assert PaymentMandateChain.parse([opening,closed]).verify(expected_open_checkout_hash=digest(f['open_checkout']),expected_transaction_id=digest(f['checkout_jwt']))==[]
        policy(opening,closed,f['details']['pisp'],f['details']['execution_date']);counts['ruby_to_python']+=1
        for receipt in f['receipts']:
            value=verify_jwt(receipt['jwt'],JWK.from_pem(receipt['key'].encode()));schema('payment_receipt.json',value)
            assert value['reference']==digest(f['closed']) and value['status']==receipt['outcome'];counts['receipts']+=1
        provider,agent=[JWK.generate(kty='EC',crv='P-256') for _ in range(2)]
        details=copy.deepcopy(f['details']);content=dict(details,vct='mandate.payment.1',iat=NOW,exp=NOW+60)
        root=None
        if mode!='direct':
            whole=dict(vct='mandate.payment.open.1',iat=NOW,exp=NOW+60,
                cnf={'jwk':{k:v for k,v in agent.export_public(as_dict=True).items() if k in ['kty','crv','x','y']}},
                constraints=copy.deepcopy(f['constraints'])+[dict(type='payment.reference',conditional_transaction_id=digest(f['open_checkout']))])
            full=issuance(whole,provider,f['profile'],mode=='selective');root=selected(full,details) if mode=='selective' else full
        def signed(value=content,open_wire=root):
            return issuance(value,provider,f['profile']) if mode=='direct' else terminal(open_wire,value,agent,f['profile'])
        def verify(wire,open_wire=root,**extra):
            return rpc('verify',closed=wire,root=open_wire,provider=provider.export_to_pem().decode(),agent=agent.export_to_pem().decode(),**extra)
        wire=signed();result=verify(wire);assert result.get('verified'),result
        pyopen,pyclosed=official(f,root,wire,provider);policy(pyopen,pyclosed,details['pisp'],details['execution_date'])
        assert common.compute_sd_hash(common.parse_token(wire))==digest(wire)
        if mode=='selective':
            for presented in [f['root'],root]:
                visible=json.dumps([payload(presented),*[decode(p) for p in presented.split('~')[1:-1]]])
                assert 'private-payee-B' not in visible and 'private-instrument-B' not in visible
            assert 'private-payee-B' not in result['inspection'] and 'private-instrument-B' not in result['inspection']
        counts['python_to_ruby']+=1
        wire_evidence.append(dict(mode=mode,ruby={k:sha(f[k]) for k in ['closed','checkout_jwt']},python=dict(closed=sha(wire)),
            ruby_root=sha(f['root']) if f['root'] else None,python_root=sha(root) if root else None))
        for outcome in ['Success','Error']:
            claims=dict(iss='processor',payment_id='payment',status=outcome,iat=NOW,reference=digest(wire))
            claims.update(dict(psp_confirmation_id='python-psp',network_confirmation_id='python-net') if outcome=='Success' else dict(error='declined',error_description='Synthetic'))
            receipt=create_jwt({'alg':'ES256','typ':'JWT'},claims,provider)
            got=rpc('receipt',jwt=receipt,closed=wire,key=provider.export_to_pem().decode());assert got.get('verified') and got['outcome']==outcome
            counts['receipts']+=1
            assert not rpc('receipt',jwt=receipt,closed=f['closed'],key=provider.export_to_pem().decode()).get('verified');counts['negatives']+=1
        # Context is independent from the received signed object and expectation.
        for extra in [dict(trusted_pisp=None),dict(execution_at=None),dict(trusted_pisp=dict(details['pisp'],legal_name='Other legal entity')),
                      dict(trusted_pisp=dict(details['pisp'],brand_name='Other brand')),dict(execution_at='2027-01-15T12:00:00.126Z')]:
            assert not verify(wire,**extra).get('verified');counts['negatives']+=1
        equivalent='2027-01-15T13:00:00.125+01:00'
        assert verify(wire,execution_at=equivalent).get('verified')
        if mode!='direct':
            # Exact closed expectations and independent execution context follow
            # the mutation, isolating actual constraint checks from equality.
            for date,expected in [('2027-01-15T12:00:01.125Z',True),('2027-01-15T13:00:00.125+01:00',True),
                                  ('2027-01-15T12:00:00.124999999Z',False),('2027-01-15T12:00:01.125000001Z',False)]:
                changed=dict(content,execution_date=date);expected_details=dict(details,execution_date=date)
                try: policy(pyopen,changed,details['pisp'],date);oracle=True
                except (AssertionError,ValueError):oracle=False
                assert oracle==expected
                got=verify(signed(changed),expected=expected_details,execution_at=date)
                assert bool(got.get('verified'))==expected,(date,got)
                if not expected:counts['negatives']+=1
                upstream=not PaymentMandateChain.parse([pyopen,changed]).verify(expected_open_checkout_hash=digest(f['open_checkout']))
                if upstream!=expected:
                    counts['upstream_disagreements']+=1
                    disagreements.append(dict(mode=mode,date=date,independent_expected=expected,upstream_accepted=upstream))
            # Each new constraint is supported alone; date windows may be
            # one-sided, and boundary comparison still uses an exact instant.
            for extra in [[whole['constraints'][3]],[dict(type='payment.execution_date',not_before=details['execution_date'])],
                          [dict(type='payment.execution_date',not_after=details['execution_date'])]]:
                variant=copy.deepcopy(whole)
                variant['constraints']=variant['constraints'][:3]+copy.deepcopy(extra)+[variant['constraints'][-1]]
                variant_full=issuance(variant,provider,f['profile'],mode=='selective')
                variant_root=selected(variant_full,details) if mode=='selective' else variant_full
                policy(resolve(variant_root),content,details['pisp'],details['execution_date'])
                assert verify(terminal(variant_root,content,agent,f['profile']),open_wire=variant_root).get('verified')
            # Signed Open changes isolate PISP matching from independent context.
            for field in ['legal_name','brand_name','domain_name']:
                changed=dict(content,pisp=dict(details['pisp'],**{field:'other.example' if field=='domain_name' else 'Other entity'}))
                assert not verify(signed(changed),expected=dict(details,pisp=changed['pisp']),trusted_pisp=changed['pisp']).get('verified')
                counts['negatives']+=1
            for hide in ['pisp_constraint','date_constraint','pisp_identity','date_bounds']:
                hidden_full=issuance(whole,provider,f['profile'],mode=='selective',hide)
                hidden=selected(hidden_full,details)
                try: policy(resolve(hidden),content,details['pisp'],details['execution_date'])
                except (AssertionError,ValueError,KeyError):pass
                else:raise AssertionError('oracle accepted hidden '+hide)
                assert not verify(terminal(hidden,content,agent,f['profile']),open_wire=hidden).get('verified')
                counts['negatives']+=1
            reversed_open=copy.deepcopy(whole)
            reversed_open['constraints'][4].update(not_before='2027-01-16T00:00:00Z',not_after='2027-01-15T00:00:00Z')
            reversed_full=issuance(reversed_open,provider,f['profile'],mode=='selective')
            reversed_root=selected(reversed_full,details) if mode=='selective' else reversed_full
            assert not verify(terminal(reversed_root,content,agent,f['profile']),open_wire=reversed_root).get('verified');counts['negatives']+=1
        for date in ['2027-02-29T12:00:00Z','2027-01-15T12:00:60Z','2027-01-15t12:00:00z','2027-01-15T12:00:00-00:00','2027-01-15T12:00:00.1234567890Z','2027-01-15T24:00:00Z']:
            try:instant(date)
            except (AssertionError,ValueError):pass
            else:raise AssertionError('oracle accepted unsupported date')
            changed=dict(content,execution_date=date)
            assert not verify(signed(changed),expected=dict(details,execution_date=date),execution_at=date).get('verified');counts['negatives']+=1
        missing=dict(content);missing.pop('execution_date')
        assert not verify(signed(missing)).get('verified');counts['negatives']+=1
        if mode!='direct':
            upstream=PaymentMandateChain.parse([pyopen,missing]).verify(expected_open_checkout_hash=digest(f['open_checkout']))
            assert upstream==[];counts['upstream_disagreements']+=1
            disagreements.append(dict(mode=mode,date=None,independent_expected=False,upstream_accepted=True))
    print(json.dumps(dict(status='PASS',counts=counts,upstream_disagreements=disagreements,wire_sha256=wire_evidence,runtime=dict(python=platform.python_version(),platform=platform.platform(),ruby=f['runtime']),
        source='official AP2 b4587ac1d055888a73b4b21750973cffba961793',
        limitations=['explicit signed-profile adapter; no generic facade profile enforcement','official execution-date evaluator is lexical and accepts missing dates; independent Decimal/calendar oracle used',
                    'synthetic PISP identity matching does not establish QWAC/provider provenance or execute/schedule payments']),sort_keys=True))
finally:
    process.stdin.close();process.wait(timeout=10)
