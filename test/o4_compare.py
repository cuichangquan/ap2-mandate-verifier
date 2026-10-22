"""Pinned official Schema observations, distinct from strict local profile."""
import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import types

import runpy
IDENTITY = runpy.run_path(str(Path(__file__).with_name('stage11_identity.py')))
PYTHON_IDENTITY = IDENTITY['current_identity']()
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

AP2 = 'b4587ac1d055888a73b4b21750973cffba961793'
ORACLE_SHA = '884900e2c3420ebfc2393413ae0e6010db71b28f8a6ef02eec997defa57b8caf'
CASES = ['NORMAL','FULL','HIDDEN','UNKNOWN','DUPLICATE','EXTRA','DECOY',
         'S01','QUANTITY_TYPE','AMOUNT','CURRENCY','TOTALS','UNKNOWN_CONSTRAINT']
EXPECTED_OPEN = {'NORMAL':True,'FULL':True,'HIDDEN':False,'UNKNOWN':True,
                 'DUPLICATE':False,'EXTRA':True,'DECOY':False,'S01':False,
                 'QUANTITY_TYPE':True,'AMOUNT':True,'CURRENCY':True,
                 'TOTALS':True,'UNKNOWN_CONSTRAINT':False}
FILES = ['ap2/open_checkout_mandate.json','ap2/checkout_mandate.json',
         'ap2/types/item.json','ap2/types/merchant.json'] + [
             'ucp/types/'+s+'.json' for s in ('checkout','line_item','total',
             'link','buyer','message','message_error','message_warning','message_info')]


def need(value, why):
    if not value:
        raise ValueError(why)


def load_source(path, digest, name, cap=16384):
    raw=IDENTITY['bounded_regular'](Path(path), cap)
    need(hashlib.sha256(raw).hexdigest()==digest, name+' source identity')
    module=types.ModuleType(name)
    module.__file__=str(Path(path).resolve())
    exec(compile(raw,str(path),'exec'),module.__dict__)
    return module


def validate_replay(replay, fixture_sha, case_names):
    root = Path(__file__).resolve().parent.parent
    observer = root / 'test/stage7_saved_replay_test.rb'
    sources = {str(p.relative_to(root)): hashlib.sha256(IDENTITY['bounded_regular'](p, 65536)).hexdigest()
               for p in sorted((root / 'lib').rglob('*.rb'))}
    if not (replay.get('observer_sha256') == hashlib.sha256(IDENTITY['bounded_regular'](observer, 65536)).hexdigest()
            and replay.get('verifier_source_sha256') == sources
            and replay.get('fixture_sha256') == fixture_sha
            and replay.get('case_count') == len(case_names)
            and set(replay.get('cases', {})) == set(case_names)
            and replay.get('scope') == 'STAGE11_SAVED_WIRE_REPLAY_NOT_NEW_FIXTURES'
            and replay.get('runtime') == {'ruby': '4.0.1', 'json': '2.18.0', 'jwt': '3.3.0'}
            and replay.get('conclusion') == 'HOLD'
            and replay.get('success') is False and replay.get('evidence', 'missing') is None):
        raise ValueError('fresh Gem replay source/result identity')
    for row in replay['cases'].values():
        expected_status = 'unverified' if row.get('code') == 'scoped_constraints_verified_only' else 'rejected'
        if (row.get('success') is not False or row.get('evidence', 'missing') is not None
                or row.get('status') != expected_status):
            raise ValueError('Gem replay row non-success boundary')


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--oracle',required=True)
    p.add_argument('--fixture',required=True)
    p.add_argument('--schema-dir',required=True)
    p.add_argument('--report',required=True)
    p.add_argument('--gem-replay',required=True)
    p.add_argument('--binding-report',required=True)
    args=p.parse_args()
    oracle=load_source(args.oracle,ORACLE_SHA,'original_signed_oracle')
    # Reuse already independently tested binding predicates, not Gem internals.
    binding_path=Path(__file__).with_name('o2o5_compare.py')
    binding_sha=hashlib.sha256(IDENTITY['bounded_regular'](binding_path, 65536)).hexdigest()
    binding=load_source(binding_path,binding_sha,'limited_binding',65536)
    acquisition=IDENTITY['schema_ledger'](Path('O4_HTTP_ACQUISITION.json'))
    expected={r['name']:r for r in acquisition['requests'] if r['name'] in FILES}
    need(set(expected)==set(FILES),'missing Schema acquisition identity')
    schemas={}
    schema_hashes={}
    for file in FILES:
        raw=oracle.read_regular(str(Path(args.schema_dir)/file),16384)
        IDENTITY['validate_schema'](raw, expected[file])
        need(expected[file]['url']=='https://raw.githubusercontent.com/google-agentic-commerce/AP2/'+AP2+'/code/sdk/schemas/'+file,'unpinned Schema URL')
        schema=oracle.strict_json(raw)
        need(schema['$schema']=='https://json-schema.org/draft/2020-12/schema','unknown dialect')
        need(schema['$id'].startswith('https://ap2-protocol.org/schemas/'),'unknown id')
        need(schema['$id'] not in schemas,'duplicate Schema id')
        schemas[schema['$id']]=schema
        schema_hashes[file]={'id':schema['$id'],'sha256':expected[file]['sha256'],
                             'git_blob':expected[file]['git_blob']}
    def no_remote(uri):
        raise ValueError('unregistered reference; STOP: '+uri)
    registry=Registry(retrieve=no_remote)
    for uri,schema in schemas.items():
        registry=registry.with_resource(uri,Resource.from_contents(schema))
    # Check the entire declared reference closure before any instance verdict.
    import urllib.parse
    ref_count=0
    def refs(v,base):
        nonlocal ref_count
        if isinstance(v,dict):
            base=urllib.parse.urljoin(base,v.get('$id',''))
            if '$ref' in v:
                target=urllib.parse.urljoin(base,v['$ref'])
                registry.resolver(base_uri=base).lookup(v['$ref'])
                need(target.split('#')[0] in schemas,'outside local closure')
                ref_count+=1
            for child in v.values(): refs(child,base)
        elif isinstance(v,list):
            for child in v: refs(child,base)
    for uri,schema in schemas.items():
        Draft202012Validator.check_schema(schema)
        refs(schema,uri)
    ids={'open':'https://ap2-protocol.org/schemas/open_checkout_mandate',
         'closed':'https://ap2-protocol.org/schemas/checkout_mandate.json',
         'merchant':'https://ap2-protocol.org/schemas/types/merchant.json',
         'checkout':'https://ap2-protocol.org/schemas/types/checkout.json'}
    validators={k:Draft202012Validator(schemas[uri],registry=registry) for k,uri in ids.items()}
    raw=IDENTITY['pinned_bytes'](args.fixture,'O2O5_PUBLIC_CASES.json',1048576)
    prior=oracle.strict_json(oracle.read_regular(args.binding_report,131072))
    need(hashlib.sha256(raw).hexdigest()==prior['fixture_sha256'],'fixture identity changed')
    need(prior['adapter_sha256']==binding_sha,'binding source/report mismatch')
    replay_raw=oracle.read_regular(args.gem_replay,65536)
    replay=oracle.strict_json(replay_raw)
    need(replay['fixture_sha256']==prior['fixture_sha256'] and replay['case_count']==32
         and replay['success'] is False and replay['evidence'] is None,'fresh Gem replay identity')
    validate_replay(replay, hashlib.sha256(raw).hexdigest(), binding.EXPECTED)
    binding.validate_binding_report(prior, binding_sha, replay_raw, replay)
    fixture=oracle.strict_json(raw)
    def presented(payload,parts):
        mapping={oracle.b64url(hashlib.sha256(s.encode('ascii')).digest()):
                 oracle.strict_json(oracle.decode64(s))[1] for s in parts}
        missing=[]
        def visit(v,path):
            if isinstance(v,dict):
                if set(v)=={'...'}:
                    digest=v['...']
                    if digest not in mapping:
                        missing.append(path)
                        return dict(v)  # Preserve original unresolved marker.
                    return visit(mapping[digest],path+'/disclosed')
                return {k:visit(x,path+'/'+k) for k,x in v.items()}
            if isinstance(v,list):
                return [visit(x,path+'/'+str(n)) for n,x in enumerate(v)]
            return v
        return visit(payload,'$'),missing
    def verdict(kind,value):
        errors=list(validators[kind].iter_errors(value))
        def detail(e):
            return {'instance_path':list(e.absolute_path),
                    'schema_path':list(e.absolute_schema_path),'keyword':e.validator,
                    'causes':[detail(child) for child in e.context]}
        return {'verdict':'INVALID' if errors else 'VALID',
                'errors':[detail(e) for e in errors]}
    full=fixture['cases']['FULL']
    _,full_payload,full_parts=oracle.original_signature(full['root_presentation'],binding.public(full['trusted_issuer_public_key_pem']))
    full_tree,full_missing=presented(full_payload,full_parts)
    need(not full_missing,'FULL missing control')
    rows={}
    validation_count=0
    for name in CASES:
        i=fixture['cases'][name]
        _,payload,parts=oracle.original_signature(i['root_presentation'],binding.public(i['trusted_issuer_public_key_pem']))
        tree,missing=presented(payload,parts)
        opened=tree['delegate_payload'][0]
        events=[]
        cart=binding.binding(i,opened,oracle,events)
        terminal=oracle.strict_json(oracle.decode64(i['terminal_jws'].split('.')[1]))
        closed=terminal['delegate_payload'][0]
        values={'open':opened,'closed':closed,'merchant':cart['merchant'],'checkout':cart}
        observations={kind:verdict(kind,value) for kind,value in values.items()}
        validation_count+=4
        if name in ('NORMAL','FULL'):
            need(all(r['verdict']=='VALID' for r in observations.values()),
                 'NORMAL INVALID: STOP without changing Gem/fixture/Schema')
        need((observations['open']['verdict']=='VALID')==EXPECTED_OPEN[name],
             name+': unexpected Open Schema verdict; STOP')
        need(all(observations[k]['verdict']=='VALID' for k in ('closed','merchant','checkout')),
             name+': unexpected Closed/Merchant/Checkout verdict; STOP')
        # A control is separate from presented data; never fill missing data in it.
        if not missing:
            control_open=opened
            control_origin='same fully resolved original presentation'
        elif i['root_presentation'].split('~')[0]==full['root_presentation'].split('~')[0]:
            control_open=full_tree['delegate_payload'][0]
            control_origin='separate FULL disclosures; identical original Issuer JWS'
        else:
            control_open=None
            control_origin='UNAVAILABLE; no complete same-Issuer-JWS control'
        control=verdict('open',control_open) if control_open is not None else {'verdict':'NOT_AVAILABLE','errors':[]}
        validation_count+=int(control_open is not None)
        try:
            graph=oracle.inspect_graph(payload,parts)
            if graph!='FULL':
                raise binding.Reject({'MISSING':'missing_disclosure',
                    'UNKNOWN_SLOT':'unsupported_disclosure_profile',
                    'DUPLICATE':'duplicate_commitment','UNUSED':'extra_disclosure'}[graph])
            binding.subset(opened,cart,i)
            profile='scoped_constraints_verified_only'
        except (binding.Reject,ValueError) as exc:
            profile=str(exc)
        need(profile==replay['cases'][name]['code'],
             name+': strict local profile mismatch; STOP')
        rows[name]={'presented':observations,'unresolved_original_paths':missing,
            'control_open':control,'control_origin':control_origin,'manual_profile':profile,
            'gem_observation':replay['cases'][name],
            'root_sha256':hashlib.sha256(i['root_presentation'].encode('ascii')).hexdigest(),
            'binding_events':events}
    report={'python_identity':PYTHON_IDENTITY,'scope':'O4_PINNED_SCHEMAS_ON_SYNTHETIC_PROFILE_ONLY','ap2_commit':AP2,
       'schemas':schema_hashes,'registered_reference_count':ref_count,
       'case_count':len(rows),'schema_validation_count':validation_count,'cases':rows,
       'dependencies':{n:importlib.metadata.version(n) for n in
         ('jsonschema','jsonschema-specifications','referencing','rpds-py','attrs')},
       'fixture_sha256':hashlib.sha256(raw).hexdigest(),'binding_source_sha256':binding_sha,
       'adapter_sha256':hashlib.sha256(IDENTITY['bounded_regular'](Path(__file__), 65536)).hexdigest(),
       'fresh_gem_replay_sha256':hashlib.sha256(replay_raw).hexdigest(),
       'format_assertions':'NOT_ENABLED; format-bearing optional values absent in these fixtures',
       'success':False,'evidence':None,'conclusion':'HOLD',
       'limits':['Not general Schema/all constraints/Host authority/ALLOW',
          'Schema permits integer-valued float2.0; manual Ruby profile rejects',
          'Prior 10MB acquisition UNMEASURED; current sent HTTP headers unmeasured']}
    encoded=(json.dumps(report,indent=2,sort_keys=True)+'\n').encode()
    need(len(encoded)<131072,'report cap')
    fd=os.open(args.report,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,'wb') as stream: stream.write(encoded)
    print('PASS O4',len(rows),'cases;',validation_count,'Schema validations;',ref_count,'local refs; overall HOLD')


if __name__=='__main__':
    main()
