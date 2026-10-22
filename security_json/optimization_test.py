"""Fail-closed invocation controls; no fixture/signature generation or network."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent


def main():
    if sys.flags.optimize:
        raise SystemExit('run controls without optimization')
    rows=[]
    with tempfile.TemporaryDirectory(prefix='ap2-stage15-optimization-') as tmp:
        for name,flags,setting in [('-O',['-O'],None),('-OO',['-OO'],None),
                                   ('PYTHONOPTIMIZE1',[],'1'),('PYTHONOPTIMIZE2',[],'2')]:
            dest=Path(tmp)/name
            env={k:v for k,v in os.environ.items() if k!='PYTHONOPTIMIZE'}
            if setting is not None: env['PYTHONOPTIMIZE']=setting
            p=subprocess.run([sys.executable,*flags,str(ROOT/'compare.py'),str(dest)],
              capture_output=True,text=True,env=env,timeout=10)
            if (p.returncode==0 or dest.exists() or p.stdout or
                p.stderr.strip()!='STOP: optimized Python execution is not supported'):
                raise RuntimeError(name+': optimized run did not stop before artifacts')
            rows.append({'case':name,'exit_code':p.returncode,'destination_created':False,
                         'stdout_empty':True,'result':'STOP_BEFORE_ARTIFACTS'})
    print(json.dumps({'scope':'JSON2199_OPTIMIZATION_REJECTION','cases':rows},indent=2))


if __name__=='__main__': main()
