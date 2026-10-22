"""Limited synthetic O1/O3 comparison; never AP2 acceptance or Evidence."""
import argparse
import hashlib
import importlib.util
import importlib.metadata
import json
import os
from pathlib import Path

import runpy
IDENTITY = runpy.run_path(str(Path(__file__).with_name('stage11_identity.py')))
PYTHON_IDENTITY = IDENTITY['current_identity']()

ORACLE_SHA = '884900e2c3420ebfc2393413ae0e6010db71b28f8a6ef02eec997defa57b8caf'
BUNDLE_SHA = 'ba8bfe3cea97b2230084a5ab5ef97d99701e3974160abbad06a346f8115c85b0'
EXPECTED = {
    'FULL': ('FULL', 'unverified', 'scoped_constraints_verified_only'),
    'HIDDEN': ('MISSING', 'rejected', 'missing_disclosure'),
    'UNKNOWN': ('UNKNOWN_SLOT', 'rejected', 'unsupported_disclosure_profile'),
    'DUPLICATE': ('DUPLICATE', 'rejected', 'duplicate_commitment'),
    'EXTRA': ('UNUSED', 'rejected', 'extra_disclosure'),
    'DECOY': ('MISSING', 'rejected', 'missing_disclosure'),
}


def demand(value, message):
    if not value:
        raise ValueError(message)


def validate_replay(replay, fixture_sha, case_names):
    root = Path(__file__).resolve().parent.parent
    observer = root / 'test/stage7_saved_replay_test.rb'
    sources = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
               for p in sorted((root / 'lib').rglob('*.rb'))}
    if not (replay.get('observer_sha256') == hashlib.sha256(observer.read_bytes()).hexdigest()
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
    parser = argparse.ArgumentParser()
    parser.add_argument('--oracle', required=True)
    parser.add_argument('--bundle', required=True)
    parser.add_argument('--policy', required=True)
    parser.add_argument('--report', required=True)
    parser.add_argument('--gem-replay', required=True)
    args = parser.parse_args()
    source = Path(args.oracle).read_bytes()
    demand(hashlib.sha256(source).hexdigest() == ORACLE_SHA, 'oracle identity')
    # Load exactly the checked source bytes, not a second path read.
    spec = importlib.util.spec_from_loader('independent_o1o3', loader=None)
    oracle = importlib.util.module_from_spec(spec)
    exec(compile(source, args.oracle, 'exec'), oracle.__dict__)
    raw = IDENTITY['pinned_bytes'](args.bundle, 'STAGE7_PUBLIC_CASES.json', 262144)
    demand(hashlib.sha256(raw).hexdigest() == BUNDLE_SHA, 'bundle identity')
    bundle = oracle.strict_json(raw)
    replay_raw = oracle.read_regular(args.gem_replay, 65536)
    replay = oracle.strict_json(replay_raw)
    demand(replay['fixture_sha256'] == BUNDLE_SHA and replay['case_count'] == 6
           and replay['success'] is False and replay['evidence'] is None,
           'fresh Gem replay identity')
    validate_replay(replay, BUNDLE_SHA, EXPECTED)
    policy_raw = IDENTITY['pinned_bytes'](args.policy, 'O1O3_POLICY.json', 16384)
    policy = oracle.strict_json(policy_raw)
    demand(set(policy) == {'scope', 'issuer_public_jwk', 'expected_alg',
                           'expected_typ', 'ap2_commit'}, 'policy fields')
    demand(policy['scope'] == 'LOCAL_SYNTHETIC_O1_O3_NO_HOST_AUTHORITY' and
           policy['expected_alg'] == 'ES256' and
           policy['expected_typ'] == 'example+sd-jwt' and
           policy['ap2_commit'] == oracle.PINNED_AP2, 'policy profile')
    key = policy['issuer_public_jwk']
    demand(set(key) == {'kty', 'crv', 'x', 'y'}, 'public key only')
    fixture = bundle['oracle_fixture']
    demand(set(fixture) == {'ap2_commit', 'cases'} and
           fixture['ap2_commit'] == oracle.PINNED_AP2 and
           set(fixture['cases']) == set(EXPECTED), 'fixture profile')
    result = {}
    for name, (expected_graph, expected_status, expected_code) in EXPECTED.items():
        case = fixture['cases'][name]
        demand(set(case) == {'root', 'terminal'}, 'case fields')
        _, payload, disclosures = oracle.original_signature(case['root'], key)
        graph = oracle.inspect_graph(payload, disclosures)
        observed = replay['cases'][name]
        demand(hashlib.sha256(case['root'].encode('ascii')).hexdigest() ==
               observed['root_sha256'], 'same Root bytes')
        demand(hashlib.sha256(case['terminal'].encode('ascii')).hexdigest() ==
               observed['terminal_sha256'], 'same terminal bytes')
        demand(graph == expected_graph and observed['status'] == expected_status
               and observed['code'] == expected_code, 'comparison mismatch')
        demand(observed['entries'][:2] == ['root_signature', 'root_graph'],
               'recorded Gem order')
        demand(name == 'FULL' or observed['entries'] ==
               ['root_signature', 'root_graph'], 'negative Gem boundary')
        result[name] = {'o1': 'VALID', 'o3_expected': expected_graph,
                        'o3_actual': graph, 'comparison': 'MATCH',
                        'root_sha256': observed['root_sha256'],
                        'gem_status': expected_status, 'gem_code': expected_code,
                        'gem_recorded_entries': observed['entries']}
    normal = bundle['observations']['NORMAL']
    demand(normal['root_sha256'] == bundle['observations']['FULL']['root_sha256']
           and normal['status'] == 'unverified', 'normal Root alias')
    full = fixture['cases']['FULL']['root']
    compact, suffix = full.split('~', 1)
    header, payload, signature = compact.split('.')
    sig = bytearray(oracle.decode64(signature))
    sig[0] ^= 1
    tampered = '.'.join((header, payload, oracle.b64url(bytes(sig)))) + '~' + suffix
    controls = {}
    for name, root, external_key in (
        ('TAMPERED_SIGNATURE', tampered, key),
        ('WRONG_EXTERNAL_KEY', full, bundle['public_keys']['agent']),
    ):
        entered_graph = False
        try:
            _, tree, disclosures = oracle.original_signature(root, external_key)
            entered_graph = True
            oracle.inspect_graph(tree, disclosures)
        except oracle.Stop as exc:
            demand(str(exc) == 'invalid_original_issuer_signature' and
                   not entered_graph, 'signature negative failed')
            controls[name] = {'o1': str(exc), 'o3_entered': False}
        else:
            raise ValueError('signature negative accepted')
    report = {'python_identity': PYTHON_IDENTITY, 'scope': 'LOCAL_SYNTHETIC_O1_O3_ONLY', 'comparison': 'MATCH',
              'oracle_sha256': ORACLE_SHA, 'bundle_sha256': BUNDLE_SHA,
              'policy_sha256': hashlib.sha256(policy_raw).hexdigest(),
              'adapter_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'fresh_gem_replay_sha256': hashlib.sha256(replay_raw).hexdigest(),
              'dependencies': {name: importlib.metadata.version(name) for name in
                               ('jwcrypto', 'cryptography', 'cffi',
                                'typing-extensions', 'pycparser')},
              'cases': result, 'NORMAL': 'same Root as FULL; Gem unverified',
              'signature_controls': controls,
              'not_established': ['O2', 'O4', 'O5 independent comparison',
                                  'Host authority', 'general Schema', 'full AP2'],
              'success': False, 'evidence': None, 'conclusion': 'HOLD'}
    encoded = (json.dumps(report, indent=2, sort_keys=True) + '\n').encode()
    demand(len(encoded) < 65536, 'report size')
    fd = os.open(args.report, os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                 os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(encoded)
    print('PASS O1/O3: 6 classifications + NORMAL Root alias + 2 signature controls; HOLD')


if __name__ == '__main__':
    main()
