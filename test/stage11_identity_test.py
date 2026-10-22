"""Offline identity rejection controls. Retained inputs are read only."""
import copy
import hashlib
import json
from pathlib import Path
import runpy
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    identity = runpy.run_path(str(ROOT / 'test/stage11_identity.py'))
    count = 0
    def rejects(action):
        nonlocal count
        try:
            action()
        except ValueError:
            count += 1
        else:
            raise AssertionError('untrusted identity accepted')
    observed = identity['observed_environment']()
    identity['validate_environment'](observed); count += 1
    measured = identity['current_identity']()
    identity['require_identity'](measured); count += 1
    for section in ('python', 'dependencies'):
        for key in observed[section]:
            for kind in ('wrong', 'missing'):
                bad = copy.deepcopy(observed)
                if kind == 'wrong': bad[section][key] = 'unapproved'
                else: bad[section].pop(key)
                rejects(lambda: identity['validate_environment'](bad))
        bad = copy.deepcopy(observed); bad[section]['extra'] = 'unapproved'
        rejects(lambda: identity['validate_environment'](bad))
    for section in ('python', 'dependencies'):
        bad = copy.deepcopy(observed); bad.pop(section)
        rejects(lambda: identity['validate_environment'](bad))
    bad = copy.deepcopy(observed); bad['extra'] = {}
    rejects(lambda: identity['validate_environment'](bad))
    for key in measured:
        bad = copy.deepcopy(measured); bad.pop(key)
        rejects(lambda: identity['require_identity'](bad))
    bad = copy.deepcopy(measured); bad['dependencies']['jwcrypto'] = '0'
    rejects(lambda: identity['require_identity'](bad))
    bad = copy.deepcopy(measured); bad['extra'] = True
    rejects(lambda: identity['require_identity'](bad))
    with tempfile.TemporaryDirectory(prefix='stage11-identity-') as directory:
        work = Path(directory)
        for name in identity['PINS']:
            original = (ROOT / name).read_bytes()
            identity['pinned_bytes'](ROOT / name, name, 1048576); count += 1
            altered = work / name; altered.write_bytes(original + b' ')
            rejects(lambda: identity['pinned_bytes'](altered, name, 1048576))
        ledger = identity['schema_ledger'](ROOT / 'O4_HTTP_ACQUISITION.json')
        row = next(r for r in ledger['requests'] if r['name'] == 'ap2/open_checkout_mandate.json')
        altered_schema = b'{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object"}\n'
        altered_blob = b'blob ' + str(len(altered_schema)).encode() + b'\0' + altered_schema
        forged = copy.deepcopy(row)
        forged['sha256'] = hashlib.sha256(altered_schema).hexdigest()
        forged['git_blob'] = hashlib.sha1(altered_blob).hexdigest()
        identity['validate_schema'](altered_schema, forged); count += 1
        rejects(lambda: identity['validate_schema'](altered_schema, row))
        wrong_blob = copy.deepcopy(forged); wrong_blob['git_blob'] = '0' * 40
        rejects(lambda: identity['validate_schema'](altered_schema, wrong_blob))
        row.update(forged)
        fake_ledger = work / 'forged-ledger.json'; fake_ledger.write_text(json.dumps(ledger))
        # Even mutually consistent forged ledger+Schema cannot cross the pinned ledger gate.
        rejects(lambda: identity['schema_ledger'](fake_ledger))
    for adapter in ('o1o3', 'o2o5', 'o4'):
        module = runpy.run_path(str(ROOT / 'test' / (adapter + '_compare.py')))
        assert module['PYTHON_IDENTITY'] == measured
        count += 1
    o4 = runpy.run_path(str(ROOT / 'test/o4_compare.py'))
    binding_path = ROOT / 'test/o2o5_compare.py'
    binding = o4['load_source'](binding_path, hashlib.sha256(binding_path.read_bytes()).hexdigest(), 'identity_binding_control')
    assert binding.PYTHON_IDENTITY == measured
    count += 1
    print(f'PASS {count} identity controls; fixed Python/dependencies and pinned ledger/inputs; no acquisition')


if __name__ == '__main__':
    main()
