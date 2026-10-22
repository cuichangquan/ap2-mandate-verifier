"""Gemspec security-pin controls; no install/build or candidate code execution."""
import json
from pathlib import Path
import runpy
import sys
import tempfile

if sys.flags.optimize:
    raise SystemExit('run controls without optimization')
HERE=Path(__file__).resolve().parent
API=runpy.run_path(str(HERE/'compare.py'))


def main():
    candidate=json.loads(API['pinned']('candidate.json'))
    original=API['capture_candidate'](HERE.parent,candidate)
    rows=[]
    with tempfile.TemporaryDirectory(prefix='ap2-json2199-pin-') as tmp:
        root=Path(tmp)
        for name,raw in original.items():
            p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(raw)
        if API['capture_candidate'](root,candidate)!=original:
            raise RuntimeError('unchanged captured package')
        rows.append({'case':'original','result':'CAPTURED13_FILES'})
        spec='ap2_mandate_verifier.gemspec'
        controls=[('reverted',spec,original[spec].replace(b'2.19.9',b'2.18.0')),
                  ('relaxed',spec,original[spec].replace(b'"= 2.19.9"',b'">= 2.18.0"')),
                  ('missing',spec,None),
                  ('stale_lock','Gemfile.lock',original['Gemfile.lock'].replace(b'2.19.9',b'2.18.0')),
                  ('missing_lock','Gemfile.lock',None),
                  ('changed_gemfile','Gemfile',original['Gemfile']+b'\ngem "json", "= 2.18.0"\n')]
        for name,target,raw in controls:
            # Every control starts from the complete original resolver tuple.
            for f in [spec,'Gemfile','Gemfile.lock']:(root/f).write_bytes(original[f])
            if raw is None:(root/target).unlink()
            else:(root/target).write_bytes(raw)
            try:API['capture_candidate'](root,candidate)
            except (OSError,ValueError):rows.append({'case':name,'result':'REJECT_BEFORE_RUBY'})
            else:raise RuntimeError(name+': dependency declaration bypass')
    print(json.dumps({'scope':'JSON2199_GEMSPEC_IDENTITY','cases':rows},indent=2))


if __name__=='__main__':main()
