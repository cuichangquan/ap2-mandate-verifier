"""Offline scoped recurring wire comparison; aggregate quota is NOT SDK proof."""
import base64
import copy
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
from ap2.sdk.disclosure_metadata import DisclosureMetadata as DM
from ap2.sdk.generated.open_payment_mandate import OpenPaymentMandate
from ap2.sdk.generated.payment_mandate import PaymentMandate
from ap2.sdk.mandate import MandateClient
from ap2.sdk.payment_mandate_chain import PaymentMandateChain
from ap2.sdk.constraints import MandateContext
from ap2.sdk.sdjwt import common, sd_jwt, chain
from ap2.sdk.jwt_helper import create_jwt, verify_jwt
from jwcrypto.jwk import JWK
from jsonschema import Draft202012Validator
from referencing import Registry, Resource
NOW=1800000000
OFFICIAL=Path(os.environ.get('AP2_OFFICIAL_ROOT','/official')).resolve()
assert Path(sd_jwt.__file__).resolve().is_relative_to(OFFICIAL)
counts=dict(ruby_to_python=0,python_to_ruby=0,receipts=0,negatives=0)
evidence=[]
REQUIRED={'payment.amount_range','payment.allowed_payees','payment.allowed_payment_instruments','payment.reference','payment.agent_recurrence','payment.budget'}
AXES={'payment.allowed_payees','payment.allowed_payment_instruments'}
def decode(w):return json.loads(base64.urlsafe_b64decode(w+'='*(-len(w)%4)))
def digest(w):return base64.urlsafe_b64encode(hashlib.sha256(w.encode('ascii')).digest()).decode().rstrip('=')
def sha(w):return hashlib.sha256(w.encode('ascii')).hexdigest()
def payload(w):return decode(w.split('~')[0].split('.')[1])
def exact(v,keys):assert isinstance(v,dict) and set(v)==set(keys)
def oracle(wire,f):
    """Original supplied graph only; mandatory condition omissions never repaired."""
    assert wire.endswith('~'); parts=wire.split('~');assert parts.pop()==''
    outer=payload(parts.pop(0));exact(outer,['ap2_profile','_sd_alg','delegate_payload'])
    assert outer['ap2_profile']==f['profile'] and outer['_sd_alg']=='sha-256' and len(outer['delegate_payload'])==1
    exact(outer['delegate_payload'][0],['...'])
    ds={};salts=set()
    for p in parts:
        d=decode(p);assert len(d)==2 and isinstance(d[0],str) and 22<=len(d[0])<=128
        assert d[0] not in salts and digest(p) not in ds
        salts.add(d[0]);ds[digest(p)]=d[1]
    h=outer['delegate_payload'][0]['...'];used={h};seen={h}
    opening=copy.deepcopy(ds[h]);exact(opening,['vct','iat','exp','cnf','constraints'])
    assert opening['vct']=='mandate.payment.open.1' and opening['iat']==NOW and opening['exp']==NOW+60
    cs=opening['constraints'];assert len(cs)==6 and {c.get('type') for c in cs}==REQUIRED
    for c in cs:
        kind=c['type']
        if kind in AXES:
            exact(c,['type','allowed']);resolved=[]
            for candidate in c['allowed']:
                if isinstance(candidate,dict) and set(candidate)=={'...'}:
                    d=candidate['...'];assert d not in seen;seen.add(d)
                    if d in ds:resolved.append(ds[d]);used.add(d)
                else:resolved.append(candidate)
            assert len(resolved)==1
            expected=f['details']['payee' if kind=='payment.allowed_payees' else 'payment_instrument']
            assert resolved==[expected];c['allowed']=resolved
        elif kind=='payment.agent_recurrence':
            exact(c,['type','frequency','max_occurrences'])
            assert c['frequency']=='ON_DEMAND' and type(c['max_occurrences']) is int and c['max_occurrences']==2
        elif kind=='payment.budget':
            exact(c,['type','currency','max'])
            assert c['currency']=='JPY' and type(c['max']) is int and c['max']==600
        elif kind=='payment.amount_range':
            exact(c,['type','currency','min','max']);assert c['currency']=='JPY' and c['min']==1 and c['max']==300
        else:
            exact(c,['type','conditional_transaction_id']);assert c['conditional_transaction_id']==digest(f['open_checkout'])
    assert used==set(ds)
    return opening

registry=Registry(retrieve=lambda _:(_ for _ in ()).throw(ValueError('unknown Schema')))
schemas=OFFICIAL/'code/sdk/schemas'
for path in schemas.rglob('*.json'):
    obj=json.loads(path.read_text());registry=registry.with_resource(obj['$id'],Resource.from_contents(obj))
registry=registry.with_resource('https://ap2-protocol.org/schemas/types/receipt_status.json',Resource.from_contents(json.loads((schemas/'ap2/types/receipt_status.json').read_text())))
def schema(name,value):Draft202012Validator(json.loads((schemas/'ap2'/name).read_text()),registry=registry).validate(value)
process=subprocess.Popen(['ruby',str(Path(__file__).with_name('recurring_interop_driver.rb'))],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
def rpc(operation,**arguments):
    process.stdin.write(json.dumps(dict(operation=operation,arguments=arguments))+'\n');process.stdin.flush()
    wire=process.stdout.readline();assert wire,'Ruby RPC exited';return json.loads(wire)
def issue(opening,provider,profile,selective,hide=None):
    child={i:DM(children={'allowed':DM(sd_array_indices=list(range(len(c['allowed']))))}) for i,c in enumerate(opening['constraints']) if selective and c['type'] in AXES}
    dm=DM(children={'constraints':DM(array_children=child,sd_array_indices=[] if hide is None else hide)})
    # Explicit JSON-mode adapter for upstream issue354, not a patched SDK/facade.
    # Negative values still pass generated schema validation; the explicit
    # narrow profile must reject their unsupported semantics independently.
    value=OpenPaymentMandate.model_validate(opening).model_dump(mode='json',by_alias=True,exclude_none=True)
    # The upstream generated Budget model coerces numbers to float. Preserve
    # the explicitly narrower profile's original integer JPY cap on the wire.
    for before,after in zip(opening['constraints'],value['constraints']):
        if before['type']=='payment.budget':after['max']=before['max']
    claims=common.selectively_disclosable_claims(value,dm,{'ap2_profile':profile})
    return common.issue_sd_jwt(claims=claims,issuer_key=provider,header_params=common.header_parameters(provider,'example+sd-jwt'),add_decoy_claims=False,serialization_format='compact').sd_jwt_issuance

def select(full,f):
    return '~'.join([full.split('~')[0],*[p for p in full.split('~')[1:-1] if isinstance(decode(p)[1],dict) and
        (decode(p)[1].get('vct')=='mandate.payment.open.1' or decode(p)[1] in [f['details']['payee'],f['details']['payment_instrument']])],''])
def close(root,f,agent):
    value=dict(f['details'],vct='mandate.payment.1',iat=NOW,exp=NOW+60)
    PaymentMandate.model_validate(value)
    return create_jwt({'alg':'ES256','typ':'kb+sd-jwt'},dict(ap2_profile=f['profile'],delegate_payload=[value],iat=NOW,aud='processor',nonce='payment-interop',sd_hash=digest(root)),agent)+'~'
def official(root,closed,provider,f):
    values=chain.verify_chain([common.parse_token(root),common.parse_token(closed)],lambda _:provider,expected_aud='processor',expected_nonce='payment-interop',current_time=NOW,clock_skew_seconds=0)
    assert MandateClient().verify(root.removesuffix('~')+'~~'+closed,lambda _:provider,expected_aud='processor',expected_nonce='payment-interop',current_time=NOW,clock_skew_seconds=0)==values
    assert values[0]==oracle(root,f)
    assert values[1]==dict(f['details'],vct='mandate.payment.1',iat=NOW,exp=NOW+60)
    assert PaymentMandateChain.parse(values).verify(expected_open_checkout_hash=digest(f['open_checkout']),expected_transaction_id=digest(f['checkout_jwt']),mandate_context=MandateContext(total_amount=0,total_uses=0))==[]
    schema('open_payment_mandate.json',values[0]);schema('payment_mandate.json',values[1])
    assert payload(closed)['sd_hash']==digest(root) and common.compute_sd_hash(common.parse_token(closed))==digest(closed)
    return values
try:
    for mode in ['complete','selective']:
        f=rpc('fixture',mode=mode);assert not f.get('rejected'),('fixture',mode)
        official(f['root'],f['closed'],JWK.from_pem(f['provider'].encode()),f);counts['ruby_to_python']+=1
        for r in f['receipts']:
            value=verify_jwt(r['jwt'],JWK.from_pem(r['key'].encode()));schema('payment_receipt.json',value)
            assert value['reference']==digest(f['closed']) and value['status']==r['outcome'];counts['receipts']+=1
        provider,agent=[JWK.generate(kty='EC',crv='P-256') for _ in range(2)]
        whole=dict(vct='mandate.payment.open.1',iat=NOW,exp=NOW+60,
            cnf={'jwk':{k:v for k,v in agent.export_public(as_dict=True).items() if k in ['kty','crv','x','y']}},
            constraints=copy.deepcopy(f['constraints'])+[dict(type='payment.reference',conditional_transaction_id=digest(f['open_checkout']))])
        full=issue(whole,provider,f['profile'],mode=='selective');root=select(full,f) if mode=='selective' else full
        closed=close(root,f,agent)
        def verify(opened=root,terminal=closed):
            return rpc('verify',root=opened,closed=terminal,provider=provider.export_to_pem().decode(),agent=agent.export_to_pem().decode())
        result=verify();assert result.get('verified'),result
        official(root,closed,provider,f);counts['python_to_ruby']+=1
        if mode=='selective':
            for presentation in [f['root'],root]:
                visible=json.dumps([payload(presentation),*[decode(p) for p in presentation.split('~')[1:-1]]])
                assert 'private-payee-B' not in visible and 'private-card-B' not in visible
            assert 'private-payee-B' not in result['inspection'] and 'private-card-B' not in result['inspection']
        evidence.append(dict(mode=mode,ruby=dict(root=sha(f['root']),closed=sha(f['closed'])),python=dict(root=sha(root),closed=sha(closed))))
        for outcome in ['Success','Error']:
            value=dict(iss='processor',payment_id='payment',status=outcome,iat=NOW,reference=digest(closed))
            value.update(dict(psp_confirmation_id='python-psp',network_confirmation_id='python-net') if outcome=='Success' else dict(error='declined',error_description='Synthetic'))
            receipt=create_jwt({'alg':'ES256','typ':'JWT'},value,provider)
            got=rpc('receipt',jwt=receipt,closed=closed,key=provider.export_to_pem().decode());assert got.get('verified') and got['outcome']==outcome
            counts['receipts']+=1
            assert not rpc('receipt',jwt=receipt,closed=f['closed'],key=provider.export_to_pem().decode()).get('verified');counts['negatives']+=1
        # Reordering preserves the root signature but changes exact presentation.
        reverse='~'.join([root.split('~')[0],*reversed(root.split('~')[1:-1]),''])
        if reverse!=root:
            assert not verify(reverse,closed).get('verified');counts['negatives']+=1
            rebound=close(reverse,f,agent);assert verify(reverse,rebound).get('verified')
        for indexes in [[3],[4],[3,4]]:
            hidden_full=issue(whole,provider,f['profile'],mode=='selective',indexes)
            hidden=select(hidden_full,f)
            try:oracle(hidden,f)
            except (AssertionError,KeyError):pass
            else:raise AssertionError('oracle accepted hidden recurrence/budget')
            assert not verify(hidden,close(hidden,f,agent)).get('verified');counts['negatives']+=1
        for field,changed_value in [('frequency','MONTHLY'),('max_occurrences',0)]:
            bad=copy.deepcopy(whole);bad['constraints'][3][field]=changed_value
            badfull=issue(bad,provider,f['profile'],mode=='selective');badroot=select(badfull,f) if mode=='selective' else badfull
            assert not verify(badroot,close(badroot,f,agent)).get('verified');counts['negatives']+=1
    print(json.dumps(dict(status='PASS',counts=counts,wire_sha256=evidence,runtime=dict(python=platform.python_version(),ruby=f['runtime']),
        source='official AP2 b4587ac1d055888a73b4b21750973cffba961793',
        scope='complete and selective recurring Open/Closed/Receipt original-wire cryptography, typed constraints at zero usage and independent mandatory-profile/privacy oracle; separate fresh Python issuer/Agent keys',
        limitations=['explicit JSON-mode Enum/profile-marker/integer-JPY adapter; generated Budget model coerces cap to float; no generic facade compatibility claim','Python SDK does not supply atomic aggregate quota or enforce frequency; its JPY budget arithmetic disagrees beyond narrow zero-usage positives','durable aggregate safety is separately tested by recurring_process_oracle.rb; no settlement/calendar recurrence claim']),sort_keys=True))
finally:
    process.stdin.close();process.wait(timeout=10)
