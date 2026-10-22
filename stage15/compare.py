"""Stage15 local-only independent contract comparison; never a Host ALLOW."""
import copy
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import time
import types

ROOT = Path(__file__).resolve().parent.parent
I = runpy.run_path(str(ROOT / 'test/stage11_identity.py'))
READ = I['bounded_regular']
SHA = lambda b: hashlib.sha256(b).hexdigest()
J = lambda v: json.dumps(v, ensure_ascii=False, separators=(',', ':'))
PROFILE = '{"profile_ref":"ap2.checkout.single_merchant_sku","version":"1","ap2_source":"b4587ac1d055888a73b4b21750973cffba961793","subset_source":"027ed4734af47c8289dbcb837373bb6086463ec4","algorithm":"ES256","key_format":"canonical-public-SPKI-P256-SHA256","root_type":"example+sd-jwt","terminal_type":"kb+sd-jwt","checkout_type":"JWT","disclosure_path_semantics":"root-walker-with-synthetic-disclosed-edges","disclosure_positions":["delegate_payload[0]","delegate_payload[0].disclosed.constraints[0].items[0].acceptable_items[0]","delegate_payload[0].disclosed.constraints[1].allowed[0]"],"constraints":["checkout.line_items","checkout.allowed_merchants"]}'
P = json.loads(PROFILE)
PH = SHA(PROFILE.encode())
ROLES = {'Issuer':'trusted_issuer_public_key_pem', 'Agent':'expected_agent_public_key_pem',
         'Merchant':'trusted_merchant_public_key_pem'}
SCOPE = ['strict_inputs','host_trust_profile_input_checks','issuer_root_signature',
         'original_root_graph_closure','agent_key_confirmation','agent_terminal_signature',
         'closed_original_checkout_binding','merchant_checkout_signature',
         'fixed_subset_schema_constraints','host_challenge_order_binding','validity_intersection']
CANDIDATE_MANIFEST_SHA = '93ca43dd65a6f7bdbc0bbed30004517e059043308cd1e2688e4eaa975675a5e9'
BINDING_SHA = '97faec0c3a36bcf60b6c7a340a38ab9e0512ab3bc04716af04ce7c8f47bc4ba4'


def load(path, digest, name):
    raw = READ(path, 65536)
    assert SHA(raw) == digest, name + ' source identity'
    m = types.ModuleType(name); m.__file__ = str(path)
    exec(compile(raw, str(path), 'exec'), m.__dict__)
    return m


def model(i):
    now = i['verified_at']
    records = []
    for role, field in ROLES.items():
        pem = i[field]
        records.append(dict(role=role, identity=i['expected_merchant_id'] if role=='Merchant' else role.lower(),
          tenant_id='synthetic-tenant', purpose='checkout', key_ref=role.lower()+'-1',
          profile_ref=P['profile_ref'], profile_version='1', public_key_pem=pem,
          key_fingerprint=SHA(pem.encode()), algorithm='ES256', active=True,
          not_before=now-2000, not_after=now+2000))
    snapshot = dict(id='synthetic-snapshot', policy_version='policy-1', active=True,
                    not_before=now-2000, not_after=now+2000, records=records)
    body = J(snapshot); h = SHA(body.encode())
    selection = dict(trust_snapshot_id=snapshot['id'], policy_version='policy-1',trust_content_hash=h,
      profile_ref=P['profile_ref'],profile_version='1',profile_definition_hash=PH,tenant_id='synthetic-tenant')
    for r in records: selection[r['role']] = {k:r[k] for k in ['identity','purpose','key_ref']}
    trust = dict(snapshot=dict(id=snapshot['id'],policy_version='policy-1',content_hash=h,body=body),
                 profile=dict(profile_ref=P['profile_ref'],version='1',definition_hash=PH,body=PROFILE))
    b = dict(tenant_id='synthetic-tenant',buyer_account_id='synthetic-buyer',order_id=i['expected_checkout_id'],
      merchant_id=i['expected_merchant_id'],audience=i['expected_aud'],profile_ref=P['profile_ref'],
      order_version='order-v1',profile_version='1',approved_agent_key_fingerprint=records[1]['key_fingerprint'],
      root_presentation_digest=SHA(i['root_presentation'].encode()),checkout_jwt_digest=SHA(i['host_checkout_jws'].encode()),
      currency=i['expected_currency'],expected_total=i['expected_total_minor'])
    c = dict(challenge_id='synthetic-challenge',nonce=i['expected_nonce'],issuer_id='synthetic-host',B=copy.deepcopy(b),
      trust_snapshot_id=snapshot['id'],policy_version='policy-1',trust_content_hash=h,profile_definition_hash=PH,
      not_before=now-2000,not_after=now+2000,state='issued')
    return dict(i=copy.deepcopy(i),trust=trust,selection=selection,
                host=dict(binding=b,challenge=c,expected_challenge_issuer_id='synthetic-host',clock_source_id='fixed-synthetic-clock'))


def update_snapshot(m, change):
    s=json.loads(m['trust']['snapshot']['body']); change(s)
    raw=J(s); h=SHA(raw.encode()); m['trust']['snapshot'].update(body=raw,content_hash=h)
    m['selection']['trust_content_hash']=m['host']['challenge']['trust_content_hash']=h


def args(m):
    return {**{k:m['i'][k] for k in ['root_presentation','terminal_jws','host_checkout_jws','verified_at']},
            'trust_json':J(m['trust']),'selection_json':J(m['selection']),'host_json':J(m['host'])}


def evaluate(m, o, binding):
    """Separate Python crypto/graph/subset plus contract-authored Host predicates.

    Only explicitly constructed shapes in cases below are supported by this
    comparison oracle; this is NOT a second generic parser/profile implementation.
    """
    events=[]
    need=binding.need
    i=m['i']; h=m['host']; c=h['challenge']; b=h['binding']; t=i['verified_at']
    try:
        events.append('host')
        need(c['state']=='issued','challenge_state_mismatch')
        need(c['B']==b and c['issuer_id']==h['expected_challenge_issuer_id'],'host_binding_mismatch')
        need(c['not_before']<=t<c['not_after'],'challenge_time_mismatch')
        events.append('trust')
        trust=m['trust']; s=json.loads(trust['snapshot']['body']); sel=m['selection']
        need(SHA(trust['snapshot']['body'].encode())==trust['snapshot']['content_hash']==sel['trust_content_hash'], 'trust_context_mismatch')
        need(sel['Merchant']['identity']==b['merchant_id'],'trust_context_mismatch')
        need(s['active'],'inactive_trust_snapshot')
        need(s['not_before']<=t<s['not_after'],'trust_snapshot_time_mismatch')
        need(trust['profile']['body']==PROFILE and sel['profile_version']=='1' and sel['profile_ref']==P['profile_ref'] and
             sel['profile_definition_hash']==PH,'unsupported_trust_profile')
        selected=[]
        for role in ROLES:
            rows=[r for r in s['records'] if r['role']==role and r['tenant_id']==sel['tenant_id'] and
                  all(r[k]==v for k,v in sel[role].items())]
            need(bool(rows),'trust_key_not_found'); need(len(rows)==1,'ambiguous_trust_key')
            r=rows[0]
            need(r['key_fingerprint']==SHA(r['public_key_pem'].encode()),'invalid_trust_key')
            need(r['active'],'inactive_trust_key')
            need(r['not_before']<=t<r['not_after'],'trust_key_time_mismatch')
            selected.append(r)
        need(all(c[k]==sel[k] for k in ['trust_snapshot_id','policy_version','trust_content_hash','profile_definition_hash']), 'challenge_reference_mismatch')
        need(all(b[k]==sel[k] for k in ['tenant_id','profile_ref','profile_version']) and
             b['approved_agent_key_fingerprint']==selected[1]['key_fingerprint'] and
             b['root_presentation_digest']==SHA(i['root_presentation'].encode()) and
             b['checkout_jwt_digest']==SHA(i['host_checkout_jws'].encode()),'host_binding_mismatch')
        # Keys and expectations come from independent authenticated Host model.
        inp=copy.deepcopy(i)
        for r,(role,field) in zip(selected,ROLES.items()): inp[field]=r['public_key_pem']
        for field,source in [('expected_aud','audience'),('expected_checkout_id','order_id'),
                             ('expected_merchant_id','merchant_id'),('expected_currency','currency'),
                             ('expected_total_minor','expected_total')]: inp[field]=b[source]
        inp['expected_nonce']=c['nonce']
        events.append('root_signature')
        _,payload,disclosures=o.original_signature(inp['root_presentation'],binding.public(inp['trusted_issuer_public_key_pem']))
        events.append('root_graph'); graph=o.inspect_graph(payload,disclosures)
        need(graph=='FULL',{'MISSING':'missing_disclosure','UNKNOWN_SLOT':'unsupported_disclosure_profile',
             'DUPLICATE':'duplicate_commitment','UNUSED':'extra_disclosure'}.get(graph,'unsupported_disclosure_profile'))
        opening=binding.resolve(payload,disclosures,o)['delegate_payload'][0]
        cart=binding.binding(inp,opening,o,events)
        events.append('local_profile'); binding.subset(opening,cart,inp)
        terminal=o.strict_json(o.decode64(inp['terminal_jws'].split('.')[1])); closed=terminal['delegate_payload'][0]
        start=max([s['not_before'],c['not_before'],opening['iat'],closed['iat'],terminal['iat']]+[r['not_before'] for r in selected])
        end=min([s['not_after'],c['not_after'],opening['exp'],closed['exp'],terminal['iat']+301]+[r['not_after'] for r in selected])
        events.append('interval'); need(start<=t<end,'invalid_host_validity')
        facts=dict(profile_ref=P['profile_ref'],profile_version='1',profile_definition_hash=PH,verified_at=t,
          clock_source_id=h['clock_source_id'],valid_from=start,valid_until=end,
          trust_snapshot={k:trust['snapshot'][k] for k in ['id','policy_version','content_hash']},
          selected_keys=[{k:v for k,v in r.items() if k!='public_key_pem'} for r in selected],checkout_binding=b,
          verified_challenge={**{k:v for k,v in c.items() if k!='nonce'},'verified_nonce_sha256':SHA(terminal['nonce'].encode())},
          root_presentation_digest=SHA(inp['root_presentation'].encode()),checkout_jwt_digest=SHA(inp['host_checkout_jws'].encode()),
          terminal_digest=SHA(inp['terminal_jws'].encode()),contract_version='ap2.research-evidence.2',
          implementation_revision='ap2.research-verifier.2',revision_kind='static_identifier_not_runtime_attestation',verified_scope=SCOPE)
        return 'scoped_research_verified',events,facts
    except binding.Reject as exc:
        return str(exc),events,None


def cases(bundle):
    rows=[]
    # Contract/fixture-authored expected rejection codes, never Gem-derived.
    for name in ['FULL','HIDDEN','UNKNOWN','DUPLICATE','EXTRA','DECOY','WRONG_AGENT_KEY',
                 'TAMPERED_AGENT_SIGNATURE','ROOT_BINDING','NONCE','WRONG_MERCHANT_KEY','S01','AMOUNT','TOTALS']:
        rows.append((name,model(bundle[name]),None))
    base=model(bundle['FULL']); n=base['i']['verified_at']
    def add(name, code, change):
        m=copy.deepcopy(base); change(m); rows.append((name,m,code))
    add('CONSUMED','challenge_state_mismatch',lambda m:m['host']['challenge'].update(state='consumed'))
    add('CHALLENGE_EXPIRED','challenge_time_mismatch',lambda m:m['host']['challenge'].update(not_after=n))
    add('CHALLENGE_START','scoped_research_verified',lambda m:m['host']['challenge'].update(not_before=n))
    add('SHORT_CHALLENGE','scoped_research_verified',lambda m:m['host']['challenge'].update(not_after=n+1))
    add('BUYER_SPLIT','host_binding_mismatch',lambda m:m['host']['binding'].update(buyer_account_id='other'))
    add('ORDER_VERSION_SPLIT','host_binding_mismatch',lambda m:m['host']['binding'].update(order_version='other'))
    def both(m,k,v):
        m['host']['binding'][k]=v; m['host']['challenge']['B'][k]=v
    add('TENANT_REBOUND','host_binding_mismatch',lambda m:both(m,'tenant_id','other'))
    add('ROOT_REBOUND','host_binding_mismatch',lambda m:both(m,'root_presentation_digest','0'*64))
    add('AGENT_REBOUND','host_binding_mismatch',lambda m:both(m,'approved_agent_key_fingerprint','0'*64))
    add('REVOKED_KEY','inactive_trust_key',lambda m:update_snapshot(m,lambda s:s['records'][1].update(active=False)))
    add('KEY_EXPIRED','trust_key_time_mismatch',lambda m:update_snapshot(m,lambda s:s['records'][1].update(not_after=n)))
    add('SHORT_KEY','scoped_research_verified',lambda m:update_snapshot(m,lambda s:s['records'][1].update(not_after=n+1)))
    add('SNAPSHOT_REVOKED','inactive_trust_snapshot',lambda m:update_snapshot(m,lambda s:s.update(active=False)))
    add('AMBIGUOUS_KEY','ambiguous_trust_key',lambda m:update_snapshot(m,lambda s:s['records'].append(copy.deepcopy(s['records'][1]))))
    add('UNKNOWN_KEY','trust_key_not_found',lambda m:m['selection']['Agent'].update(key_ref='unknown'))
    add('PROFILE_VERSION','unsupported_trust_profile',lambda m:m['selection'].update(profile_version='2'))
    assert len(rows)==30
    return rows


def main():
    import sys
    out=Path(sys.argv[1]); out.mkdir(exist_ok=False)
    start=time.monotonic(); identity=I['current_identity']()
    pinraw=READ(ROOT/'stage15/candidate.json',16384)
    assert SHA(pinraw)==CANDIDATE_MANIFEST_SHA,'reviewed candidate manifest identity'
    pin=json.loads(pinraw)
    sources={str(p.relative_to(ROOT)):READ(p,65536) for p in sorted((ROOT/'lib').rglob('*.rb'))}
    assert {k:SHA(v) for k,v in sources.items()}==pin['sources'],'candidate source mismatch'
    o=load(ROOT/'research/phase2a_e06i/e03_e04_signed_oracle.py','884900e2c3420ebfc2393413ae0e6010db71b28f8a6ef02eec997defa57b8caf','oracle')
    binding_path=ROOT/'test/o2o5_compare.py'
    binding=load(binding_path,BINDING_SHA,'binding')
    fixture=I['pinned_bytes'](ROOT/'O2O5_PUBLIC_CASES.json','O2O5_PUBLIC_CASES.json',1048576)
    bundle=o.strict_json(fixture)['cases']; matrix=cases(bundle)
    observer=READ(ROOT/'stage15/observe.rb',16384)
    ruby='/opt/homebrew/Cellar/ruby/4.0.1/bin/ruby'
    deps=ROOT.parent/'ap2-gem-input/.local-deps/gems'
    env={**os.environ,'GEM_HOME':str(deps),'GEM_PATH':str(deps)+':/opt/homebrew/Cellar/ruby/4.0.1/lib/ruby/gems/4.0.0'}
    observations=[]; saved_inputs={}
    with tempfile.TemporaryDirectory(prefix='ap2-stage15-') as tmp:
        tree=Path(tmp)
        for k,v in {**sources,'stage15/observe.rb':observer}.items():
            target=tree/k; target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(v)
        def run(name,a,expected,events,facts,kind):
            remaining=300-(time.monotonic()-start)
            assert remaining>0,'whole-run deadline'
            before=time.monotonic()
            p=subprocess.run([ruby,str(tree/'stage15/observe.rb')],input=J({'args':a}).encode(),
              stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,timeout=min(10,remaining),check=True)
            elapsed=time.monotonic()-before
            assert len(p.stdout)<131072 and not p.stderr,p.stderr.decode()
            actual=json.loads(p.stdout)
            assert actual['runtime']=={'ruby':'4.0.1','json':'2.18.0','jwt':'3.3.0'}
            assert actual['code']==expected,(name,expected,actual)
            ok=expected=='scoped_research_verified'
            assert actual['status']==('verified_research' if ok else 'rejected') and actual['success']==ok
            assert actual['evidence']==facts,(name,'evidence mismatch')
            if ok: assert actual['deeply_frozen'] and actual['stable_after_input_mutation']
            # Entered wrapper methods are reachability, NOT per-stage PASS.
            if events:
                expected_entries=['trust'] if 'trust' in events else []
                if 'root_signature' in events:
                    expected_entries+=['constraints','purchase','root_graph']
                    expected_entries+=['signature']*sum(x in events for x in ['root_signature','agent_signature','merchant_signature'])
                assert actual['entries']==expected_entries,(name,'entry order',expected_entries,actual['entries'])
            else:
                assert not actual['entries'],'logical input bound should fail before trust/crypto'
            saved_inputs[name]=a
            observations.append(dict(name=name,kind=kind,expected_code=expected,python_events=events,
              actual=actual,elapsed_seconds=elapsed,comparison='MATCH',input_sha256=SHA(J(a).encode())))
        for name,m,expected in matrix:
            code,events,facts=evaluate(m,o,binding)
            authored=expected or ('scoped_research_verified' if name=='FULL' else binding.EXPECTED[name][0])
            assert code==authored,(name,code,authored)
            run(name,args(m),code,events,facts,'independent_contract_comparison')
        # Logical input boundaries; at-limit values can still fail later shape/signature gates.
        base=args(model(bundle['FULL']))
        probes=[]
        def probe(name,field,value,code):
            a=copy.deepcopy(base); a[field]=value; probes.append((name,a,code))
        for field,cap in [('root_presentation',131072),('terminal_jws',32768),('host_checkout_jws',16384),
                          ('trust_json',131072),('selection_json',16384),('host_json',32768)]:
            probe(field+'_over',field,'x'*(cap+1),'input_too_large')
        probe('HOST_DEPTH24','host_json','['*24+'0'+']'*24,'invalid_host_context')
        probe('HOST_DEPTH25','host_json','['*25+'0'+']'*25,'input_too_deep')
        probe('HOST_DUPLICATE','host_json','{"binding":0,"binding":1}','duplicate_key')
        probe('HOST_AT_CAP','host_json','0'+' '*(32768-1),'invalid_host_context')
        probe('HOST_INVALID_TYPE','host_json',None,'invalid_input_type')
        probe('HOST_BOM','host_json','\ufeff{}','invalid_json')
        for name,a,code in probes: run(name,a,code,[],None,'logical_bound_probe')
    schema_checks=schema_controls(bundle,o,binding)
    input_raw=(json.dumps(saved_inputs,indent=2,ensure_ascii=False)+'\n').encode()
    (out/'INPUTS.json').write_bytes(input_raw)
    report=dict(scope='STAGE15_MBA_LOCAL_RESEARCH_ONLY',candidate=pin,python_identity=identity,
      fixture_sha256=SHA(fixture),observer_sha256=SHA(observer),adapter_sha256=SHA(READ(Path(__file__),65536)),
      binding_adapter_sha256=SHA(READ(binding_path,65536)),oracle_sha256=binding.ORACLE_SHA,
      case_count=len(observations),independent_cases=len(matrix),resource_probes=len(probes),cases=observations,
      schema_controls=schema_checks,inputs_sha256=SHA(input_raw),candidate_manifest_sha256=SHA(pinraw),
      total_seconds=time.monotonic()-start,per_probe_timeout_seconds=10,whole_timeout_seconds=300,
      conclusion='LIMITED_MATCH_NOT_HOST_ALLOW',stage16='HOLD',other_environment='NOT_RUN',
      limitations=['Trusted Python/Ruby harness/interpreter and private temporary source tree; not hostile same-user attestation',
       'Independent Python implementation shares public fixtures, fixed profile and ES256 providers/design',
       'Only constructed Host shapes/fields above independently compared; generic parser/profile coverage not claimed',
       'Observed elapsed time/logical bounds are not hard CPU/RSS/parallel load guarantees',
       'No Host authority provenance, latest-state atomic nonce/order CAS, payment or production proof',
       'Historical acquisition measurement defects remain unproven; no new acquisition'])
    assert report['total_seconds']<300
    (out/'REPORT.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
    print(f"PASS {len(matrix)} independent cases + {len(probes)} logical probes + {len(schema_checks['checks'])} Schema controls; {report['total_seconds']:.3f}s; other-environment NOT_RUN")


def schema_controls(bundle,o,binding):
    # No fetch fallback. Fixed saved13 Schema closure is independent of Gem.
    from jsonschema import Draft202012Validator
    from referencing import Registry, Resource
    import urllib.parse
    files=['ap2/open_checkout_mandate.json','ap2/checkout_mandate.json','ap2/types/item.json','ap2/types/merchant.json']+[
      'ucp/types/'+s+'.json' for s in ['checkout','line_item','total','link','buyer','message','message_error','message_warning','message_info']]
    ledger=I['schema_ledger'](ROOT/'O4_HTTP_ACQUISITION.json')
    expected={r['name']:r for r in ledger['requests'] if r['name'] in files}
    assert set(expected)==set(files)
    def no_remote(uri): raise ValueError('unregistered Schema ref: '+uri)
    registry=Registry(retrieve=no_remote); schemas={}; hashes={}
    for f in files:
        raw=READ(ROOT.parent/'ap2-gem-input/.local-deps/o4-schemas'/f,16384)
        I['validate_schema'](raw,expected[f]); s=o.strict_json(raw)
        assert expected[f]['url']=='https://raw.githubusercontent.com/google-agentic-commerce/AP2/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/schemas/'+f
        assert s['$id'] not in schemas
        schemas[s['$id']]=s; hashes[f]=SHA(raw)
        registry=registry.with_resource(s['$id'],Resource.from_contents(s))
    def refs(v,base):
        if type(v) is dict:
            base=urllib.parse.urljoin(base,v.get('$id',''))
            if '$ref' in v:
                assert urllib.parse.urljoin(base,v['$ref']).split('#')[0] in schemas
                registry.resolver(base_uri=base).lookup(v['$ref'])
            for x in v.values(): refs(x,base)
        elif type(v) is list:
            for x in v: refs(x,base)
    for uri,s in schemas.items(): Draft202012Validator.check_schema(s); refs(s,uri)
    ids={'open':'https://ap2-protocol.org/schemas/open_checkout_mandate',
         'closed':'https://ap2-protocol.org/schemas/checkout_mandate.json',
         'merchant':'https://ap2-protocol.org/schemas/types/merchant.json',
         'checkout':'https://ap2-protocol.org/schemas/types/checkout.json'}
    checks=[]
    for name in ['FULL','S01']:
        i=bundle[name]
        _,payload,disclosures=o.original_signature(i['root_presentation'],binding.public(i['trusted_issuer_public_key_pem']))
        assert o.inspect_graph(payload,disclosures)=='FULL'
        opening=binding.resolve(payload,disclosures,o)['delegate_payload'][0]
        cart=binding.binding(i,opening,o,[])
        terminal=o.strict_json(o.decode64(i['terminal_jws'].split('.')[1]))
        instances=dict(open=opening,closed=terminal['delegate_payload'][0],merchant=cart['merchant'],checkout=cart)
        for kind,v in instances.items():
            errors=sorted(Draft202012Validator(schemas[ids[kind]],registry=registry).iter_errors(v),key=lambda e:str(list(e.path)))
            expected_valid=not(name=='S01' and kind=='open')
            assert (not errors)==expected_valid,(name,kind,'Schema mismatch')
            checks.append(dict(case=name,kind=kind,expected='VALID' if expected_valid else 'INVALID',
                               actual='INVALID' if errors else 'VALID',paths=[list(e.path) for e in errors]))
    return dict(schema_sha256=hashes,checks=checks,scope='PINNED13_NORMAL_AND_SIGNATURE_VALID_S01_ONLY')


if __name__=='__main__': main()
