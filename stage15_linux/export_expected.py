"""MBA independent expected facts only: never runs/reads Gem observations."""
import sys
if sys.flags.optimize:
    raise SystemExit('STOP optimized exporter')
import hashlib
import json
from pathlib import Path
import runpy
import types
ROOT=Path(__file__).resolve().parent.parent
API=runpy.run_path(str(ROOT/'security_json/compare.py'))
READ=API['READ']; SHA=API['SHA']

def main():
    identity=API['I']['current_identity']()
    raw=READ(ROOT/'stage15/compare.py',65536)
    if SHA(raw)!=API['OLD_ADAPTER_SHA']:raise ValueError('independent adapter identity')
    old=types.ModuleType('independent');old.__file__=str(ROOT/'stage15/compare.py')
    exec(compile(raw,old.__file__,'exec'),old.__dict__)
    oracle=old.load(ROOT/'research/phase2a_e06i/e03_e04_signed_oracle.py','884900e2c3420ebfc2393413ae0e6010db71b28f8a6ef02eec997defa57b8caf','oracle')
    binding=old.load(ROOT/'test/o2o5_compare.py',old.BINDING_SHA,'binding')
    bundle=json.loads(API['I']['pinned_bytes'](ROOT/'O2O5_PUBLIC_CASES.json','O2O5_PUBLIC_CASES.json',1048576))['cases']
    input_raw=READ(ROOT/'stage15/results/R3/INPUTS.json',1048576)
    if SHA(input_raw)!=API['INPUT_SHA']:raise ValueError('input identity')
    saved=json.loads(input_raw);rows={}
    for name,m,authored in old.cases(bundle):
        code,events,facts=old.evaluate(m,oracle,binding)
        expected=authored or ('scoped_research_verified' if name=='FULL' else binding.EXPECTED[name][0])
        if code!=expected or old.args(m)!=saved[name]:raise ValueError('independent expectation/input')
        entered=['trust'] if 'trust' in events else []
        if 'root_signature' in events:
            entered+=['constraints','purchase','root_graph']+['signature']*sum(x in events for x in ['root_signature','agent_signature','merchant_signature'])
        rows[name]=dict(code=code,evidence=facts,entries=entered,python_events=events)
    for name,code in API['PROBES'].items():rows[name]=dict(code=code,evidence=None,entries=[],python_events=[])
    if len(rows)!=42 or set(rows)!=set(saved):raise ValueError('complete42')
    report=dict(scope='INDEPENDENT_MBA_EXPECTATIONS_FOR_LINUX_REPLAY_NOT_LINUX_ORACLE',
      inputs_sha256=SHA(input_raw),oracle_identity=identity,
      sources={n:SHA(READ(ROOT/n,65536)) for n in ['stage15/compare.py','test/o2o5_compare.py','research/phase2a_e06i/e03_e04_signed_oracle.py','security_json/compare.py','stage15_linux/export_expected.py']},cases=rows)
    dest=Path(sys.argv[1])
    with dest.open('x') as f:f.write(json.dumps(report,indent=2)+'\n')
    print('PASS exported30 independent+12 authored boundaries; no Gem invocation')
if __name__=='__main__':main()
