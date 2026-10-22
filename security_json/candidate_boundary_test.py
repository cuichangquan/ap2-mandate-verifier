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
        rows.append({'case':'original','result':'CAPTURED11_FILES'})
        gemspec=root/'ap2_mandate_verifier.gemspec'
        for name,raw in [('reverted',original[gemspec.name].replace(b'2.19.9',b'2.18.0')),
                         ('relaxed',original[gemspec.name].replace(b'"= 2.19.9"',b'">= 2.18.0"')),
                         ('missing',None)]:
            if raw is None:gemspec.unlink()
            else:gemspec.write_bytes(raw)
            try:API['capture_candidate'](root,candidate)
            except (OSError,ValueError):rows.append({'case':name,'result':'REJECT_BEFORE_RUBY'})
            else:raise RuntimeError(name+': dependency declaration bypass')
    print(json.dumps({'scope':'JSON2199_GEMSPEC_IDENTITY','cases':rows},indent=2))


if __name__=='__main__':main()
