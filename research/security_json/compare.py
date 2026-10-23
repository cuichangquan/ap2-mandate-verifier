"""Fixed JSON security-update replay. Old Stage11/15 evidence is immutable."""
import sys
if sys.flags.optimize != 0:
    raise SystemExit('STOP: optimized Python execution is not supported')
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import time
import types

ROOT = Path(__file__).resolve().parent.parent.parent
HERE = Path(__file__).resolve().parent
SHA = lambda b: hashlib.sha256(b).hexdigest()
I = runpy.run_path(str(ROOT/'test/stage11_identity.py'))
READ = I['bounded_regular']
PINS = {'candidate.json':'4c1eede6944da3704b3136bb22a94de6262d10ffc73db4fb01aea9663274f0f5',
        'runtime.json':'f52e9fc94334d31ec057ba82e1473b8be865a4efa75937737a10f8436fe9d636',
        'dependencies.lock.json':'a01b7cf96091dd8046868e6ec343a4abbd1ad87546864f573c7801eeea57d9f8',
        'observe.rb':'7d643f55918bb7b7d62783f946ec957d8c768d840fc50a2c468e96a9ba313d3e'}
CURRENT_ADAPTER_SHA='b4d83be75dd9083fcfee7733e160b37e47cf4eb28b72497b51f45e1c9e2fbc8e' # relocated revision; historical pin retained in original commit
INPUT_SHA='41ad845a7ea82a9c7316c9ef11fb8ee5281453afafe2b4932c7217c1936562c1'
PROBES={**{k+'_over':'input_too_large' for k in ['root_presentation','terminal_jws','host_checkout_jws','trust_json','selection_json','host_json']},
        'HOST_DEPTH24':'invalid_host_context','HOST_DEPTH25':'input_too_deep','HOST_DUPLICATE':'duplicate_key',
        'HOST_AT_CAP':'invalid_host_context','HOST_INVALID_TYPE':'invalid_input_type','HOST_BOM':'invalid_json'}


def need(ok, why):
    if not ok: raise ValueError(why)


def pinned(name):
    raw=READ(HERE/name,16384)
    need(SHA(raw)==PINS[name],name+' identity')
    return raw


def capture_candidate(root, candidate):
    sources={str(p.relative_to(root)):READ(p,65536) for p in sorted((root/'lib').rglob('*.rb'))}
    # All normal Bundler resolver inputs belong to the security proposition.
    for name in ['ap2_mandate_verifier.gemspec','Gemfile','Gemfile.lock']:
        sources[name]=READ(root/name,16384)
    need({k:SHA(v) for k,v in sources.items()}==candidate['sources'],'captured verifier/package identity')
    return sources


def main():
    start=time.monotonic(); out=Path(sys.argv[1]); out.mkdir(exist_ok=False)
    identity=I['current_identity']()
    old_raw=READ(ROOT/'research/stage15/compare.py',65536)
    need(SHA(old_raw)==CURRENT_ADAPTER_SHA,'relocated current adapter source')
    old=types.ModuleType('retained_contract_oracle'); old.__file__=str(ROOT/'research/stage15/compare.py')
    exec(compile(old_raw,old.__file__,'exec'),old.__dict__)
    candidate=json.loads(pinned('candidate.json')); runtime=json.loads(pinned('runtime.json'))
    lock=json.loads(pinned('dependencies.lock.json')); observer=pinned('observe.rb')
    need(lock['runtime_manifest_sha256']==PINS['runtime.json'],'lock/runtime link')
    need({k:runtime[k] for k in ['ruby','json','jwt','base64','openssl','bundler']}==lock['runtime'],'runtime version link')
    need(runtime['resolved_gems']==lock['resolved_gems'],'frozen Bundler resolution link')
    sources=capture_candidate(ROOT,candidate)
    original_inputs=READ(ROOT/'research/stage15/results/R3/INPUTS.json',1048576)
    need(SHA(original_inputs)==INPUT_SHA,'historical public inputs identity')
    saved=json.loads(original_inputs)
    oracle=old.load(ROOT/'research/phase2a_e06i/e03_e04_signed_oracle.py','884900e2c3420ebfc2393413ae0e6010db71b28f8a6ef02eec997defa57b8caf','original_signed')
    binding=old.load(ROOT/'test/o2o5_compare.py',old.BINDING_SHA,'retained_binding')
    fixture=I['pinned_bytes'](ROOT/'research/stage11/inputs/O2O5_PUBLIC_CASES.json','O2O5_PUBLIC_CASES.json',1048576)
    bundle=json.loads(fixture)['cases']; matrix=old.cases(bundle)
    deps=ROOT/'.local-deps/gems'; existing=ROOT.parent/'ap2-gem-input/.local-deps/gems'
    env={**os.environ,'GEM_HOME':str(deps),'GEM_PATH':str(deps)+':'+str(existing)+':/opt/homebrew/Cellar/ruby/4.0.1/lib/ruby/gems/4.0.0'}
    env.pop('RUBYOPT',None)
    rows=[]; inputs={}
    with tempfile.TemporaryDirectory(prefix='ap2-json2199-') as tmp:
        tree=Path(tmp)
        for f,b in {**sources,'research/security_json/observe.rb':observer}.items():
            p=tree/f;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
        def run(name,a,code,events,facts):
            remaining=300-(time.monotonic()-start);need(remaining>0,'whole comparison deadline')
            began=time.monotonic()
            result=subprocess.run(['/opt/homebrew/Cellar/ruby/4.0.1/bin/ruby',str(tree/'research/security_json/observe.rb')],
              input=old.J({'args':a}).encode(),capture_output=True,env=env,timeout=min(10,remaining),check=True)
            need(not result.stderr and len(result.stdout)<131072,'observer output boundary')
            actual=json.loads(result.stdout); ok=code=='scoped_research_verified'
            need(actual['runtime']==runtime,name+': loaded dependency/runtime identity')
            need(actual['code']==code and actual['status']==('verified_research' if ok else 'rejected') and actual['success']==ok,name+': result')
            need(actual['evidence']==facts,name+': exact Evidence/noEvidence')
            if ok:need(actual['deeply_frozen'] and actual['stable_after_input_mutation'],name+': immutability')
            entered=['trust'] if 'trust' in events else []
            if 'root_signature' in events:
                entered+=['constraints','purchase','root_graph']+['signature']*sum(x in events for x in ['root_signature','agent_signature','merchant_signature'])
            need(actual['entries']==entered,name+': entered-wrapper order (not per-stage PASS)')
            inputs[name]=a
            rows.append(dict(name=name,expected_code=code,python_events=events,actual=actual,comparison='MATCH',
                             input_sha256=SHA(old.J(a).encode()),elapsed_seconds=time.monotonic()-began))
        for name,m,expected in matrix:
            code,events,facts=old.evaluate(m,oracle,binding)
            authored=expected or ('scoped_research_verified' if name=='FULL' else binding.EXPECTED[name][0])
            need(code==authored,name+': authored expectation')
            a=old.args(m);need(a==saved[name],name+': retained same original input')
            run(name,a,code,events,facts)
        for name,code in PROBES.items():run(name,saved[name],code,[],None)
    schemas=old.schema_controls(bundle,oracle,binding)
    need(len(rows)==42 and len(schemas['checks'])==8,'complete comparison set')
    # Preserve historical input order and exact bytes as a comparison control.
    need(inputs==saved,'same42 original public inputs')
    need(time.monotonic()-start<300,'whole comparison deadline')
    report=dict(scope='RELOCATED_JSON2199_REPLAY_NOT_HISTORICAL_RUN',candidate=candidate,runtime=runtime,
      dependencies_lock_sha256=PINS['dependencies.lock.json'],candidate_sha256=PINS['candidate.json'],
      adapter_sha256=SHA(READ(Path(__file__),65536)),observer_sha256=PINS['observe.rb'],
      independent_adapter_sha256=CURRENT_ADAPTER_SHA,python_identity=identity,
      original_oracle_sha256='884900e2c3420ebfc2393413ae0e6010db71b28f8a6ef02eec997defa57b8caf',
      binding_adapter_sha256=old.BINDING_SHA,fixture_sha256=SHA(fixture),same_historical_inputs_sha256=INPUT_SHA,
      case_count=42,independent_cases=30,resource_probes=12,cases=rows,schema_controls=schemas,
      total_seconds=time.monotonic()-start,per_probe_timeout_seconds=10,whole_timeout_seconds=300,
      conclusion='LIMITED_MATCH_NOT_HOST_ALLOW',other_environment='NOT_RUN',stage16='HOLD',
      limitations=['Existing safe synthetic cases only; no exploit PoC, crash or disclosure experiment',
       'New dependency observations do not rewrite/validate historical executions',
       'MBA trusted harness/interpreter; shared fixture/profile/crypto assumptions',
       'No real Host trust/clock/atomic consume/payment or product CPU/RSS/parallel guarantee',
       'terminal.iat+301 computed but not isolated as limiting expiry; prior2 acquisition gaps unchanged'])
    (out/'REPORT.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f"PASS JSON2.19.9:30 independent+12bounds+8Schema; {report['total_seconds']:.3f}s")


if __name__=='__main__':main()
