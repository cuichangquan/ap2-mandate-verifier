"""Independent LONG profile interoperability. No generic AP2/settlement claim.

Official pinned SDK is mounted read-only. Keys and public signed wires stay in
process memory; output contains hashes, counters and result classifications.
"""
import base64
import copy
import datetime as dt
import hashlib
import json
from pathlib import Path
import platform
import subprocess
from unittest.mock import patch
from ap2.sdk.disclosure_metadata import DisclosureMetadata as DM
from ap2.sdk.generated.open_checkout_mandate import OpenCheckoutMandate
from ap2.sdk.generated.open_payment_mandate import OpenPaymentMandate
from ap2.sdk.generated.checkout_mandate import CheckoutMandate
from ap2.sdk.generated.payment_mandate import PaymentMandate
from ap2.sdk.checkout_mandate_chain import CheckoutMandateChain
from ap2.sdk.payment_mandate_chain import PaymentMandateChain
from ap2.sdk.constraints import MandateContext
from ap2.sdk.jwt_helper import create_jwt, verify_jwt
from ap2.sdk.mandate import MandateClient
from ap2.sdk.sdjwt import common, kb_sd_jwt, sd_jwt, chain
from jwcrypto.jwk import JWK
from jsonschema import Draft202012Validator
from referencing import Registry,Resource

OFFICIAL=Path('/official').resolve()
assert Path(sd_jwt.__file__).resolve().is_relative_to(OFFICIAL)
counts=dict(ruby_to_python=0,python_to_ruby=0,receipts=0,negative_checks=0,sdk_kb_constructor=0,sdk_facade_present=0)
evidence=[]
differences=[]
schemas=OFFICIAL/'code/sdk/schemas'
registry=Registry(retrieve=lambda _:(_ for _ in ()).throw(ValueError('unregistered schema')))
for path in schemas.rglob('*.json'):
    obj=json.loads(path.read_text());registry=registry.with_resource(obj['$id'],Resource.from_contents(obj))
registry=registry.with_resource('https://ap2-protocol.org/schemas/types/receipt_status.json',Resource.from_contents(json.loads((schemas/'ap2/types/receipt_status.json').read_text())))
def schema(name,value):
    Draft202012Validator(json.loads((schemas/'ap2'/name).read_text()),registry=registry).validate(value)

def decode(text):return json.loads(base64.urlsafe_b64decode(text+'='*(-len(text)%4)))
def payload(wire):return decode(wire.split('~')[0].split('.')[1])
def sha(wire):return hashlib.sha256(wire.encode('ascii')).hexdigest()
def digest(wire):return base64.urlsafe_b64encode(hashlib.sha256(wire.encode('ascii')).digest()).decode().rstrip('=')
def canonical(wire):return wire if wire.endswith('~') else wire+'~'
def direct_content(wire):
    outer=payload(wire)
    leaves={digest(d):decode(d) for d in wire.split('~')[1:-1]}
    item=outer['delegate_payload'][0]
    if set(item)=={'...'}:
        d=leaves[item['...']];assert len(d)==2
        return d[1]
    return item

PERIODS=[f'2028-{month:02d}' for month in range(1,13)]
def fixed_context(kind,period,amount=40000):
    assert kind in ['checkout','payment'] and period in PERIODS
    return dict(expected_aud='merchant-host' if kind=='checkout' else 'payment-host',
        expected_nonce=('checkout-nonce-' if kind=='checkout' else 'payment-nonce-')+period+'-'+str(amount))
def official(root,closed,key,at,kind,period,amount=40000):
    outer=payload(closed)
    options=dict(**fixed_context(kind,period,amount),current_time=at,clock_skew_seconds=0)
    values=chain.verify_chain([common.parse_token(root),common.parse_token(canonical(closed))],lambda _:key,**options)
    assert MandateClient().verify(root.removesuffix('~')+'~~'+canonical(closed),lambda _:key,**options)==values
    assert common.compute_sd_hash(common.parse_token(root))==digest(root)==outer['sd_hash']
    return values

process=subprocess.Popen(['ruby',str(Path(__file__).with_name('long_payment_interop_driver.rb'))],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
def rpc(operation,**arguments):
    process.stdin.write(json.dumps(dict(operation=operation,arguments=arguments))+'\n');process.stdin.flush()
    line=process.stdout.readline();assert line,'LONG Ruby driver exited before response'
    return json.loads(line)
def expect_false(result,label):
    assert not result.get('verified',False),label
    counts['negative_checks']+=1

# Explicit adapter only: JSON-mode Enum conversion and integer JPY preservation.
def issue_root(model_class,value,key,template):
    typed=model_class.model_validate(value)
    obj=typed.model_dump(mode='json',by_alias=True,exclude_none=True)
    for original,converted in zip(value.get('constraints',[]),obj.get('constraints',[])):
        if original.get('type')=='payment.budget':converted['max']=original['max']
    extra={k:v for k,v in payload(template).items() if k not in ['delegate_payload','_sd_alg','_sd']}
    metadata=DM.from_model(typed) if model_class is OpenCheckoutMandate else DM()
    claims=common.selectively_disclosable_claims(obj,metadata,extra)
    return common.issue_sd_jwt(claims=claims,issuer_key=key,header_params=common.header_parameters(key,'example+sd-jwt'),add_decoy_claims=False,serialization_format='compact').sd_jwt_issuance

def issue_closed(model_class,value,key,root,template,at,issuer_key):
    expected=payload(template)
    kind='checkout' if model_class is CheckoutMandate else 'payment'
    period=dt.datetime.fromtimestamp(at,dt.timezone.utc).strftime('%Y-%m')
    context=fixed_context(kind,period)
    # Exercise the unchanged official KB constructor, with a fake external clock.
    with patch('ap2.sdk.sdjwt.kb_sd_jwt.time.time',return_value=at):
        issued=kb_sd_jwt.create(common.parse_token(root),key,model_class.model_validate(value),
            aud=context['expected_aud'],nonce=context['expected_nonce'],sd=DM()).sd_jwt_issuance
        presented=MandateClient().present(holder_key=key,mandate_token=root,payloads=[model_class.model_validate(value)],
            aud=context['expected_aud'],nonce=context['expected_nonce'],sd=DM())
    actual=payload(issued)
    assert actual['iat']==at and direct_content(issued)['iat']==value['iat'] and direct_content(issued)['exp']==value['exp']
    assert official(root,issued,issuer_key,at,kind,period)[1]==value
    facade_terminal=canonical(presented.split('~~')[-1])
    assert official(root,facade_terminal,issuer_key,at,kind,period)[1]==value and payload(facade_terminal)['iat']==at
    counts['sdk_kb_constructor']+=1
    counts['sdk_facade_present']+=1
    # The strict Ruby profile's inline final grammar/profile marker are an
    # explicit adapter, not a claim that the upstream facade emits that grammar.
    claims={k:v for k,v in actual.items() if k!='_sd_alg'}
    claims['delegate_payload']=[copy.deepcopy(value)]
    if 'ap2_profile' in expected:claims['ap2_profile']=expected['ap2_profile']
    if '_sd_alg' in expected:claims['_sd_alg']=expected['_sd_alg']
    return create_jwt({'alg':'ES256','typ':'kb+sd-jwt'},claims,key)+'~'

def oracle(f,month,checkout_values,payment_values):
    at=month['now'];period=month['period'];I=f['t0'];E=f['exp']
    assert dt.datetime.fromtimestamp(at,dt.timezone.utc).strftime('%Y-%m')==period
    assert at==int(dt.datetime(2028,int(period[-2:]),1,1,tzinfo=dt.timezone.utc).timestamp())
    assert I==int(dt.datetime(2028,1,1,tzinfo=dt.timezone.utc).timestamp())
    assert E==int(dt.datetime(2029,1,1,tzinfo=dt.timezone.utc).timestamp()) and E-I==366*86400 and I<=at<E
    for opened,closed in [checkout_values,payment_values]:
        assert opened['iat']==closed['iat']==I and opened['exp']==closed['exp']==E
    for name,value in zip(['open_checkout_mandate','checkout_mandate','open_payment_mandate','payment_mandate'],[*checkout_values,*payment_values]):
        schema(name+'.json',value)
    for wire in [month['checkout_closed'],month['payment_closed']]:
        assert payload(wire)['iat']==at
    assert payment_values[1]['payment_amount']=={'amount':40000,'currency':'JPY'}
    assert payment_values[1]['transaction_id']==digest(month['checkout_jwt'])
    assert payment_values[1]['payment_instrument']=={'id':'synthetic-card','type':'card'}
    assert payment_values[1]['payee']=={'id':'shop','name':'Synthetic Long Shop'}
    assert month['cart']['currency']=='JPY' and month['cart']['status']=='ready_for_complete'
    assert month['cart']['id']=='long-'+period+'-40000'
    assert month['cart']['merchant']=={'id':'shop','name':'Synthetic Long Shop'} and month['cart']['links']==[]
    assert month['cart']['line_items']==[{'id':'row-1','quantity':1,
        'item':{'id':'long-item','title':'Monthly supplies','price':40000},
        'totals':[{'type':'subtotal','amount':40000},{'type':'total','amount':40000}]}]
    assert next(t['amount'] for t in month['cart']['totals'] if t['type']=='total')==40000
    cs=payment_values[0]['constraints']
    recurrence=next(c for c in cs if c['type']=='payment.agent_recurrence')
    budget=next(c for c in cs if c['type']=='payment.budget')
    assert recurrence=={'type':'payment.agent_recurrence','frequency':'MONTHLY','max_occurrences':12}
    assert budget=={'type':'payment.budget','currency':'JPY','max':480000}
    # Explicitly authorized Host windows are separate from the wire evaluator.
    assert period in PERIODS

try:
    f=rpc('fixture');assert 'months' in f, 'fixture unavailable'
    assert f['profiles']=={'checkout':'ap2.checkout.long_open.multi_item.1','payment':'ap2.payment.long_open.jpy_monthly.complete.1'}
    assert payload(f['checkout_open'])['ap2_profile']==f['profiles']['checkout']
    assert payload(f['payment_open'])['ap2_profile']==f['profiles']['payment']
    jan,feb=f['months'][:2]
    assert [m['period'] for m in f['months']]==PERIODS
    old_root_hashes={name:sha(f[name].split('~')[0]) for name in ['checkout_open','payment_open']}
    provider=JWK.from_pem(f['provider'].encode())
    for index,m in enumerate(f['months']):
        cv=official(f['checkout_open'],m['checkout_closed'],provider,m['now'],'checkout',m['period'])
        pv=official(f['payment_open'],m['payment_closed'],provider,m['now'],'payment',m['period'])
        oracle(f,m,cv,pv)
        assert CheckoutMandateChain.parse(cv).verify(expected_checkout_hash=digest(m['checkout_jwt']),checkout_jwt=m['checkout_jwt'])==[]
        assert PaymentMandateChain.parse(pv).verify(expected_open_checkout_hash=digest(f['checkout_open']),
            expected_transaction_id=digest(m['checkout_jwt']),mandate_context=MandateContext(total_uses=index,total_amount=index*40000))==[]
        evidence.append(dict(direction='ruby_to_python',period=m['period'],roots=old_root_hashes,
            checkout_jwt=sha(m['checkout_jwt']),checkout_closed=sha(m['checkout_closed']),payment_closed=sha(m['payment_closed'])))
        counts['ruby_to_python']+=1
        assert len(m.get('receipts',[]))==2, 'Ruby Checkout/Payment receipts required'
        for receipt in m['receipts']:
            value=verify_jwt(receipt['jwt'],JWK.from_pem(receipt['key'].encode()))
            target=m['checkout_closed'] if receipt['kind']=='checkout' else m['payment_closed']
            schema(receipt['kind']+'_receipt.json',value)
            assert value['reference']==digest(canonical(target))
            assert value['iss']=='processor' and value['iat']==m['now'] and value['status']=='Success'
            if receipt['kind']=='payment':assert value['payment_id']=='payment-'+m['period']
            else:assert value['order_id']==m['cart']['id']
            counts['receipts']+=1
    for key in ['checkout_jwt','checkout_closed','payment_closed']:
        assert len({m[key] for m in f['months']})==12, 'all12 occurrence wires must differ: '+key
    assert len({m['cart']['id'] for m in f['months']})==12

    issuer,agent,merchant=[JWK.generate(kty='EC',crv='P-256') for _ in range(3)]
    jwk={k:v for k,v in agent.export_public(as_dict=True).items() if k in ['kty','crv','x','y']}
    co=copy.deepcopy(official(f['checkout_open'],jan['checkout_closed'],provider,jan['now'],'checkout',jan['period'])[0]);co['cnf']={'jwk':jwk}
    checkout_open=issue_root(OpenCheckoutMandate,co,issuer,f['checkout_open'])
    po=copy.deepcopy(official(f['payment_open'],jan['payment_closed'],provider,jan['now'],'payment',jan['period'])[0]);po['cnf']={'jwk':jwk}
    next(c for c in po['constraints'] if c['type']=='payment.reference')['conditional_transaction_id']=digest(checkout_open)
    payment_open=issue_root(OpenPaymentMandate,po,issuer,f['payment_open'])
    new_root_hashes=dict(checkout_open=sha(checkout_open.split('~')[0]),payment_open=sha(payment_open.split('~')[0]))
    python_months=[]
    for m in f['months']:
        cart=copy.deepcopy(m['cart'])
        checkout_jwt=create_jwt({'alg':'ES256','typ':'JWT'},cart,merchant)
        closed_cart=dict(vct='mandate.checkout.1',iat=f['t0'],exp=f['exp'],checkout_jwt=checkout_jwt,checkout_hash=digest(checkout_jwt))
        checkout_closed=issue_closed(CheckoutMandate,closed_cart,agent,checkout_open,m['checkout_closed'],m['now'],issuer)
        payment=copy.deepcopy(direct_content(canonical(m['payment_closed'])));payment.update(transaction_id=digest(checkout_jwt),iat=f['t0'],exp=f['exp'])
        payment_closed=issue_closed(PaymentMandate,payment,agent,payment_open,m['payment_closed'],m['now'],issuer)
        pm=dict(m,checkout_jwt=checkout_jwt,checkout_closed=checkout_closed,payment_closed=payment_closed)
        cv=official(checkout_open,checkout_closed,issuer,m['now'],'checkout',m['period'])
        pv=official(payment_open,payment_closed,issuer,m['now'],'payment',m['period'])
        oracle(f,pm,cv,pv)
        assert CheckoutMandateChain.parse(cv).verify(expected_checkout_hash=digest(checkout_jwt),checkout_jwt=checkout_jwt)==[]
        assert PaymentMandateChain.parse(pv).verify(expected_open_checkout_hash=digest(checkout_open),expected_transaction_id=digest(checkout_jwt),
            mandate_context=MandateContext(total_uses=len(python_months),total_amount=len(python_months)*40000))==[]
        result=rpc('verify_external',checkout_open=checkout_open,payment_open=payment_open,checkout_jwt=checkout_jwt,
            checkout_closed=checkout_closed,payment_closed=payment_closed,provider=issuer.export_to_pem().decode(),
            agent=agent.export_to_pem().decode(),merchant=merchant.export_to_pem().decode(),period=m['period'])
        assert result.get('verified'),result
        counts['python_to_ruby']+=1;python_months.append(pm)
        evidence.append(dict(direction='python_to_ruby',period=m['period'],roots=new_root_hashes,
            checkout_jwt=sha(checkout_jwt),checkout_closed=sha(checkout_closed),payment_closed=sha(payment_closed)))
        for kind,target in [('checkout',checkout_closed),('payment',payment_closed)]:
            value=dict(iss='processor',status='Success',iat=m['now'],reference=digest(target))
            if kind=='checkout':value['order_id']=cart['id']
            else:value.update(payment_id='payment-'+m['period'],psp_confirmation_id='python-psp',network_confirmation_id='python-net')
            jwt=create_jwt({'alg':'ES256','typ':'JWT'},value,merchant)
            receipt=rpc('receipt_verify',jwt=jwt,closed=target,key=merchant.export_to_pem().decode(),period=m['period'],kind=kind)
            assert receipt.get('verified'),receipt
            counts['receipts']+=1
            if m['period']!='2028-01':
                wrong_target=python_months[0]['checkout_closed' if kind=='checkout' else 'payment_closed']
                expect_false(rpc('receipt_verify',jwt=jwt,closed=wrong_target,key=merchant.export_to_pem().decode(),period=m['period'],kind=kind),
                    'authentic receipt must not bind another occurrence wire')
    def external(m,**overrides):
        args=dict(checkout_open=checkout_open,payment_open=payment_open,checkout_jwt=m['checkout_jwt'],
            checkout_closed=m['checkout_closed'],payment_closed=m['payment_closed'],provider=issuer.export_to_pem().decode(),
            agent=agent.export_to_pem().decode(),merchant=merchant.export_to_pem().decode(),period=m['period'])
        args.update(overrides)
        return rpc('verify_external',**args)
    def resign(wire,transform):
        claims=copy.deepcopy(payload(wire));transform(claims)
        return create_jwt({'alg':'ES256','typ':'kb+sd-jwt'},claims,agent)+'~'
    first,second=python_months[:2]
    # All of these are genuinely Agent-signed negatives, not corrupted bytes.
    stale=resign(second['payment_closed'],lambda c:c.update(iat=first['now']))
    assert official(payment_open,stale,issuer,second['now'],'payment',second['period'])
    expect_false(external(second,payment_closed=stale),'stale outer proof must fail independent freshness')
    differences.append(dict(case='stale_outer_iat',official_sdk_crypto_accepted=True,strict_long_expected=False))
    fresh_boundary=resign(second['payment_closed'],lambda c:c.update(iat=second['now']-300))
    assert external(second,payment_closed=fresh_boundary).get('verified'), '300second age boundary must remain usable'
    expired_boundary=resign(second['payment_closed'],lambda c:c.update(iat=second['now']-301))
    expect_false(external(second,payment_closed=expired_boundary),'301second age must reject')
    one_future=resign(second['payment_closed'],lambda c:c.update(iat=second['now']+1))
    expect_false(external(second,payment_closed=one_future),'any future outeriat must reject')
    changed_iat=resign(second['payment_closed'],lambda c:c['delegate_payload'][0].update(iat=second['now']))
    expect_false(external(second,payment_closed=changed_iat),'shared content iat changed')
    changed_exp=resign(second['payment_closed'],lambda c:c['delegate_payload'][0].update(exp=second['now']+300))
    expect_false(external(second,payment_closed=changed_exp),'shared content exp shortened')
    future=resign(second['payment_closed'],lambda c:c.update(iat=second['now']+301))
    expect_false(external(second,payment_closed=future),'future outer proof')
    wrong_transaction=resign(second['payment_closed'],lambda c:c['delegate_payload'][0].update(transaction_id=digest(first['checkout_jwt'])))
    expect_false(external(second,payment_closed=wrong_transaction),'signed Payment bound to another occurrence Checkout')
    expect_false(external(second,period='2027-12'),'period outside independently authorized windows')
    for name in ['aud','nonce']:
        wrong=resign(second['payment_closed'],lambda c:c.update({name:'genuinely-signed-wrong-'+name}))
        try:official(payment_open,wrong,issuer,second['now'],'payment',second['period'])
        except ValueError:pass
        else:raise AssertionError('official SDK accepted wrong independently expected '+name)
        expect_false(external(second,payment_closed=wrong),'Ruby rejects signed wrong '+name)
    # Authenticate each altered Open and its fresh Agent proof. A signature is
    # insufficient when a required constraint is absent; expectations come from
    # this profile's fixed required set, never the received disclosed subset.
    for missing in ['payment.budget','payment.agent_recurrence','payment.amount_range']:
        deficient=copy.deepcopy(po)
        deficient['constraints']=[c for c in deficient['constraints'] if c['type']!=missing]
        deficient_open=issue_root(OpenPaymentMandate,deficient,issuer,payment_open)
        deficient_closed=issue_closed(PaymentMandate,direct_content(second['payment_closed']),agent,
            deficient_open,second['payment_closed'],second['now'],issuer)
        expect_false(external(second,payment_open=deficient_open,payment_closed=deficient_closed),'required signed constraint missing: '+missing)
    # At the last window count11 permits one more use, but a trusted prior spend
    #460001JPY leaves39999JPY. A40000JPY payment must exceed integer480000.
    # The SDK instead multiplies the limit by100: this is a known difference,
    # not a claimed match with the independent durable ledger oracle.
    last=f['months'][-1]
    mc=official(f['checkout_open'],last['checkout_closed'],provider,last['now'],'checkout',last['period'])
    mp=official(f['payment_open'],last['payment_closed'],provider,last['now'],'payment',last['period'])
    oracle(f,last,mc,mp)
    assert PaymentMandateChain.parse(mp).verify(expected_open_checkout_hash=digest(f['checkout_open']),
        expected_transaction_id=digest(last['checkout_jwt']),mandate_context=MandateContext(total_uses=11,total_amount=460001))==[]
    assert 460001+mp[1]['payment_amount']['amount']>480000
    host_budget=rpc('host_budget_control')
    assert host_budget['status']=='rejected' and not host_budget['ticket'],host_budget
    assert (host_budget['count'],host_budget['spent'],host_budget['prior_starts'])==(11,460001,11),host_budget
    assert host_budget['root_sha256']==sha(f['payment_open']) and host_budget['closed_sha256']==sha(last['payment_closed'])
    differences.append(dict(case='december40000_after460001',official_sdk_crypto_and_typed_accepted=True,
        explicit_host_budget_expected=False,host_execution_observation=host_budget))
    # A separately signed second cart in the same January is valid to the SDK
    # under count/budget, because its recurrence evaluator ignores the period.
    # The independently declared Host one-window rule must reject that effect.
    alternate_cart=copy.deepcopy(first['cart']);alternate_cart['id']+='-second-same-period'
    alternate_jwt=create_jwt({'alg':'ES256','typ':'JWT'},alternate_cart,merchant)
    alternate_checkout=dict(vct='mandate.checkout.1',iat=f['t0'],exp=f['exp'],checkout_jwt=alternate_jwt,checkout_hash=digest(alternate_jwt))
    alt_checkout_closed=issue_closed(CheckoutMandate,alternate_checkout,agent,checkout_open,first['checkout_closed'],first['now'],issuer)
    alternate_payment=copy.deepcopy(direct_content(first['payment_closed']));alternate_payment['transaction_id']=digest(alternate_jwt)
    alt_payment_closed=issue_closed(PaymentMandate,alternate_payment,agent,payment_open,first['payment_closed'],first['now'],issuer)
    ac=official(checkout_open,alt_checkout_closed,issuer,first['now'],'checkout',first['period'])
    ap=official(payment_open,alt_payment_closed,issuer,first['now'],'payment',first['period'])
    assert CheckoutMandateChain.parse(ac).verify(expected_checkout_hash=digest(alternate_jwt),checkout_jwt=alternate_jwt)==[]
    assert PaymentMandateChain.parse(ap).verify(expected_open_checkout_hash=digest(checkout_open),expected_transaction_id=digest(alternate_jwt),
        mandate_context=MandateContext(total_uses=1,total_amount=40000))==[]
    differences.append(dict(case='second_distinct_cart_same_january',official_sdk_crypto_and_typed_accepted=True,
        explicit_host_period_expected=False,host_execution_observation='separate Ruby SQLite controls'))
    print(json.dumps(dict(status='PASS',counts=counts,wire_sha256=evidence,runtime=dict(python=platform.python_version(),ruby=f['runtime']),
        sdk_differences=differences,
        scope='same366dayroots, all12monthsfreshclosedproofs, bothdirectionsofficialSDKsource+strictLONGprofile; explicitHostcalendarpolicy',
        limitations=['MONTHLYcalendarandJPYbudgetSDKdifferences require independentHostpolicy, notSDKconformance','explicitJSONEnum/integer/profile/inlinegrammaradapters','controlledclocks, no elapsedyear, productionpayment, renewal orsettlementproof']),sort_keys=True))
finally:
    process.stdin.close();process.wait(timeout=10)
