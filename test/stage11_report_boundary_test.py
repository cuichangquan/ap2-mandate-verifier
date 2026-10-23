"""Offline stale/incomplete evidence controls; no network or fixture generation."""
import copy
import hashlib
import json
from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parent.parent

def main():
    modules = {name: runpy.run_path(str(ROOT / 'test' / (name + '_compare.py')))
               for name in ('o1o3', 'o2o5', 'o4')}
    count = 0
    def rejected(action):
        nonlocal count
        try:
            action()
        except (ValueError, modules['o2o5']['Reject']):
            count += 1
        else:
            raise AssertionError('stale/incomplete evidence accepted')
    for name, module in modules.items():
        replay = json.loads((ROOT / ('research/stage11/archive/STAGE11_SNAPSHOT_GEM_REPLAY_6.json' if name == 'o1o3'
                                     else 'research/stage11/archive/STAGE11_SNAPSHOT_GEM_REPLAY_32.json')).read_text())
        validate = module['validate_replay']
        args = (replay['fixture_sha256'], set(replay['cases']))
        validate(replay, *args); count += 1
        for mutation in ('observer', 'stale_source', 'missing_source', 'extra_source',
                         'missing_case', 'success_row', 'evidence_row', 'status_row', 'missing_runtime', 'ruby_runtime',
                         'json_runtime', 'jwt_runtime', 'extra_runtime', 'missing_loading',
                         'wrong_loading_mode', 'wrong_loading_commit', 'wrong_loading_count', 'extra_loading'):
            bad = copy.deepcopy(replay)
            if mutation == 'observer': bad['observer_sha256'] = '0' * 64
            elif mutation == 'stale_source':
                bad['verifier_source_sha256'][next(iter(bad['verifier_source_sha256']))] = '0' * 64
            elif mutation == 'missing_source': bad['verifier_source_sha256'].pop(next(iter(bad['verifier_source_sha256'])))
            elif mutation == 'extra_source': bad['verifier_source_sha256']['lib/stale.rb'] = '0' * 64
            elif mutation == 'missing_case': bad['cases'].pop(next(iter(bad['cases'])))
            elif mutation == 'success_row': bad['cases'][next(iter(bad['cases']))]['success'] = True
            elif mutation == 'evidence_row': bad['cases'][next(iter(bad['cases']))]['evidence'] = {}
            elif mutation == 'status_row': bad['cases'][next(iter(bad['cases']))]['status'] = 'success'
            elif mutation == 'missing_runtime': bad.pop('runtime')
            elif mutation == 'ruby_runtime': bad['runtime']['ruby'] = '3.4.0'
            elif mutation == 'json_runtime': bad['runtime']['json'] = '2.17.0'
            elif mutation == 'jwt_runtime': bad['runtime']['jwt'] = '3.2.0'
            elif mutation == 'extra_runtime': bad['runtime']['unapproved'] = True
            elif mutation == 'missing_loading': bad.pop('source_loading')
            elif mutation == 'wrong_loading_mode': bad['source_loading']['mode'] = 'CHECKOUT_REQUIRE'
            elif mutation == 'wrong_loading_commit': bad['source_loading']['trusted_verifier_commit'] = '0' * 40
            elif mutation == 'wrong_loading_count': bad['source_loading']['captured_file_count'] = 6
            elif mutation == 'extra_loading': bad['source_loading']['extra'] = True
            rejected(lambda: validate(bad, *args))
    binding = modules['o2o5']
    prior = json.loads((ROOT / 'research/stage11/archive/STAGE11_SNAPSHOT_O2O5_REPORT.json').read_text())
    replay_raw = (ROOT / 'research/stage11/archive/STAGE11_SNAPSHOT_GEM_REPLAY_32.json').read_bytes()
    replay = json.loads(replay_raw)
    adapter_sha = hashlib.sha256((ROOT / 'test/o2o5_compare.py').read_bytes()).hexdigest()
    validate = binding['validate_binding_report']
    validate(prior, adapter_sha, replay_raw, replay); count += 1
    for mutation in ('minimal', 'stale_replay', 'missing_case', 'not_match',
                     'wrong_code', 'wrong_wire', 'failed', 'success', 'evidence', 'wrong_o2', 'wrong_o2_order', 'wrong_pipeline_order', 'missing_python_identity',
                     'wrong_python_dependency', 'extra_python_identity'):
        bad = copy.deepcopy(prior)
        if mutation == 'minimal': bad = {k: bad[k] for k in ('fixture_sha256', 'adapter_sha256')}
        elif mutation == 'stale_replay': bad['fresh_gem_replay_sha256'] = '0' * 64
        elif mutation == 'missing_case': bad['cases'].pop('FULL')
        elif mutation == 'not_match': bad['cases']['FULL']['comparison'] = 'MISMATCH'
        elif mutation == 'wrong_code': bad['cases']['FULL']['python_code'] = 'rejected'
        elif mutation == 'wrong_wire': bad['cases']['FULL']['original_wire_hashes']['root_sha256'] = '0' * 64
        elif mutation == 'failed': bad['conclusion'] = 'FAILED'
        elif mutation == 'success': bad['success'] = True
        elif mutation == 'evidence': bad['evidence'] = {}
        elif mutation == 'wrong_o2': bad['cases']['FULL']['o2_isolated'] = 'invalid_signature'
        elif mutation == 'wrong_o2_order': bad['cases']['FULL']['o2_events'] = ['open_time']
        elif mutation == 'wrong_pipeline_order': bad['cases']['FULL']['python_pipeline_events'] = ['root_signature','root_graph']
        elif mutation == 'missing_python_identity': bad.pop('python_identity')
        elif mutation == 'wrong_python_dependency': bad['python_identity']['dependencies']['jwcrypto'] = '0'
        elif mutation == 'extra_python_identity': bad['python_identity']['extra'] = True
        rejected(lambda: validate(bad, adapter_sha, replay_raw, replay))
    print(f'PASS {count} report-boundary controls; stale verifier/observer and incomplete prerequisites rejected')

if __name__ == '__main__':
    main()
