"""Closed profile contract: no installed runtime or execution approval ships here.

Production registry is empty. Inventory matching is not authority/completeness;
those require external review before insertion. Fake profiles never arm Linux.
"""
from dataclasses import dataclass
import hashlib
import base64
import math
import json
import re
from types import MappingProxyType
APPROVED_PROFILES = MappingProxyType({})
ROLES = ('builder', 'oracle', 'ruby')
ROOT = '/opt/ap2-bundle'
OUTPUTS = {'builder': (('policy.json', 16384), ('fixture.json', 262144)),
           'oracle': (('oracle.json', 65536),), 'ruby': (('ruby.json', 65536),)}
MAX_RESULT = 1048576
MAX_INVENTORY = 512
MAX_BYTES = 33554432
MAX_FILE = 16777216
class Stop(RuntimeError):
    pass

def need(ok, why):
    if not ok:
        raise Stop(why)

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'),
                      ensure_ascii=True, allow_nan=False).encode('ascii')

@dataclass(frozen=True)
class Entry:
    path: str
    size: int
    sha256: str
    kind: str
    mode: int = 0o444
    uid: int = 0
    gid: int = 0
    directory: bool = False

@dataclass(frozen=True)
class Profile:
    """Both infrastructure TCB and whole immutable target root are inventoried.

    Interpreters, loaders/libs, stdlib, Python packages/Ruby gems, git, AP2 Git
    objects and relative source loads must be reviewed for completeness BEFORE
    registry insertion. Hashing a caller's list does not establish that closure.
    Pseudo-files and sole writable tmpfs are admitted separately.
    """
    name: str
    inventory: tuple[Entry, ...]
    uid: int
    gid: int
    python_paths: tuple[str, ...]
    gem_paths: tuple[str, ...]
    purpose: str = 'OFFLINE_FAKE'
    def digest(self):
        return hashlib.sha256(canonical({'name': self.name, 'uid': self.uid,
            'gid': self.gid, 'python_paths': self.python_paths,
            'gem_paths': self.gem_paths, 'purpose': self.purpose,
            'inventory': [(x.path, x.size, x.sha256, x.kind, x.mode, x.uid, x.gid, x.directory) for x in self.inventory]})).hexdigest()

def path_ok(path):
    return (type(path) is str and len(path) <= 1024 and path.isascii() and
            re.fullmatch(r'/(?:[A-Za-z0-9_-][A-Za-z0-9_.-]*/)*[A-Za-z0-9_-][A-Za-z0-9_.-]*', path))

def validate(profile):
    need(type(profile) is Profile and type(profile.name) is str and
         re.fullmatch(r'[a-z0-9-]{1,64}', profile.name), 'PROFILE')
    need(type(profile.uid) is int and 0 < profile.uid < 2147483648 and type(profile.gid) is int and 0 < profile.gid < 2147483648, 'PROFILE_IDS')
    need(profile.purpose in ('OFFLINE_FAKE', 'LINUX_APPROVED'), 'PROFILE_PURPOSE')
    need(type(profile.inventory) is tuple and 0 < len(profile.inventory) <= MAX_INVENTORY, 'INVENTORY')
    seen, kinds, total = set(), set(), 0
    for item in profile.inventory:
        need(type(item) is Entry and path_ok(item.path) and item.path not in seen, 'INVENTORY_PATH')
        need(type(item.size) is int and (item.size == 0 if item.directory else 0 < item.size <= MAX_FILE) and type(item.sha256) is str and
             re.fullmatch(r'[0-9a-f]{64}', item.sha256), 'INVENTORY_PIN')
        need(item.kind in ('infrastructure', 'runtime', 'source', 'upstream'), 'INVENTORY_KIND')
        need(type(item.directory) is bool and type(item.mode) is int and 0 <= item.mode <= 0o777 and
             item.mode & 0o022 == 0 and type(item.uid) is int and item.uid == 0 and
             type(item.gid) is int and item.gid == 0, 'INVENTORY_METADATA')
        need(item.directory or not any(item.path.startswith(root+'/') for root in ('/run/ap2-supervisor/input','/run/ap2-supervisor/output')), 'DYNAMIC_DATA_IN_RUNTIME')
        seen.add(item.path); kinds.add(item.kind); total += item.size
    need(total <= MAX_BYTES and kinds == {'infrastructure', 'runtime', 'source', 'upstream'}, 'INVENTORY_CLOSURE')
    for values in (profile.python_paths, profile.gem_paths):
        need(type(values) is tuple and 0 < len(values) <= 32 and len(set(values)) == len(values) and
             all(path_ok(p) and p.startswith('/opt/ap2-runtime/') for p in values), 'IMPORT_PATHS')
    return profile

def select_native(name):
    need(type(name) is str and name in APPROVED_PROFILES, 'PROFILE_NOT_APPROVED')
    profile, expected_digest = APPROVED_PROFILES[name]
    validate(profile)
    need(profile.purpose == 'LINUX_APPROVED' and profile.digest() == expected_digest, 'PROFILE_AUTHORITY')
    return profile

def check_bytes(profile, read):
    validate(profile)
    for entry in profile.inventory:
        if entry.directory:
            continue
        data = read(entry.path, entry.size + 1)
        need(type(data) is bytes and len(data) == entry.size and
             hashlib.sha256(data).hexdigest() == entry.sha256, 'INVENTORY_BYTES')

def environment(profile):
    validate(profile)
    return {'PATH': '/opt/ap2-runtime/bin', 'LANG': 'C', 'LC_ALL': 'C',
            'HOME': '/nonexistent', 'PYTHONDONTWRITEBYTECODE': '1',
            'GEM_HOME': profile.gem_paths[0], 'GEM_PATH': ':'.join(profile.gem_paths),
            'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null',
            'GIT_NO_LAZY_FETCH': '1', 'GIT_ALLOW_PROTOCOL': '',
            'GIT_TERMINAL_PROMPT': '0', 'GIT_OPTIONAL_LOCKS': '0'}

def check_artifacts(role, artifacts):
    need(role in ROLES and type(artifacts) is dict and
         set(artifacts) == {name for name, _ in OUTPUTS[role]}, 'ARTIFACT_NAMES')
    need(all(type(artifacts[name]) is bytes and 0 < len(artifacts[name]) <= cap
             for name, cap in OUTPUTS[role]), 'ARTIFACT_LIMIT')
    need(sum(map(len, artifacts.values())) <= MAX_RESULT, 'RESULT_LIMIT')
    return {name: hashlib.sha256(raw).hexdigest() for name, raw in artifacts.items()}


def payload_argv(role, epoch):
    need(role in ROLES and type(epoch) is int and 61 <= epoch <= 4102441200, 'PAYLOAD_ROLE')
    source = '/opt/ap2-source/research/phase2a_e06i'
    output = '/run/ap2-supervisor/output'
    inputs = '/run/ap2-supervisor/input'
    script = source+'/e03_e04_'+{'builder':'fixture_builder.py', 'oracle':'signed_oracle.py',
                                'ruby':'stage_observer.rb'}[role]
    if role == 'ruby':
        argv = ('/opt/ap2-runtime/bin/ruby', script)
    else:
        argv = ('/opt/ap2-runtime/bin/python3', '-I', '-S', '-B',
                source+'/p1r_exec_owner.py', '--python-target='+role, script)
    if role == 'builder':
        return argv+('--epoch', str(epoch), '--upstream-root', '/opt/ap2-upstream',
                     '--policy', output+'/policy.json', '--fixture', output+'/fixture.json')
    argv += ('--fixture', inputs+'/fixture.json', '--policy', inputs+'/policy.json')
    if role == 'ruby':
        argv += ('--oracle', inputs+'/oracle.json', '--upstream-root', '/opt/ap2-upstream')
    return argv+('--report', output+'/'+role+'.json')

INPUTS = {'builder': (), 'oracle': (('fixture.json',262144),('policy.json',16384)),
          'ruby': (('fixture.json',262144),('policy.json',16384),('oracle.json',65536))}

def frozen_inputs(role, inputs):
    need(role in ROLES and type(inputs) is dict and set(inputs) == {n for n,_ in INPUTS[role]}, 'INPUT_NAMES')
    need(all(type(inputs[n]) is bytes and 0 < len(inputs[n]) <= cap for n,cap in INPUTS[role]), 'INPUT_LIMIT')
    return tuple((name,inputs[name]) for name,_ in INPUTS[role])


def manifest_for(profile, role, epoch, inputs):
    """Runtime authority and changing data are separate; data never adds code."""
    import p1r_linux_supervisor as s
    frozen = frozen_inputs(role,inputs)
    pins = [s.Pin(e.path,e.size,e.sha256) for e in profile.inventory
            if not e.directory and any(e.path.startswith(root+'/') for root in s.READONLY)
            and not e.path.startswith(s.INPUT+'/')]
    pins += [s.Pin(s.INPUT+'/'+name,len(raw),hashlib.sha256(raw).hexdigest()) for name,raw in frozen]
    return s.Manifest(tuple(pins),epoch)


RESULT_KEYS = {'status','operation','unit','argv','files','stdout','stderr','exit',
    'seconds','cleanup','artifacts','actual_execution','runtime_attestation',
    'source_closure_authority','report_comparison','ap2_six_cases','phase2_gate'}

def encode_result(result):
    """Bounded lossless worker transport; no evidence field is dropped."""
    import p1r_linux_supervisor as s
    need(type(result) is dict and set(result) == RESULT_KEYS, 'RESULT_SCHEMA')
    role = result['operation']
    need(role in ROLES and type(result['actual_execution']) is bool, 'RESULT_ROLE')
    native = result['actual_execution']
    need(result['status'] == ('SUPERVISOR_LIFECYCLE_COMPLETE' if native else
         'MOCK_SUPERVISOR_LIFECYCLE_COMPLETE') and result['cleanup'] is True and
         result['runtime_attestation'] == result['source_closure_authority'] == 'UNPROVEN' and
         result['report_comparison'] == 'NOT_IMPLEMENTED' and
         result['ap2_six_cases'] == 'NOT_RUN' and result['phase2_gate'] == 'HOLD', 'RESULT_CLAIMS')
    need(type(result['unit']) is str and re.fullmatch(r'ap2-sup-[0-9]{1,20}-'+role+r'\.service',result['unit']), 'RESULT_IDENTITY')
    need(type(result['argv']) is tuple and all(type(x) is str for x in result['argv']) and
         type(result['files']) is tuple and 0 < len(result['files']) <= MAX_INVENTORY and
         all(type(x) is s.Pin for x in result['files']), 'RESULT_EVIDENCE')
    need(type(result['exit']) is int and result['exit'] == (0 if role == 'builder' else 1) and
         type(result['seconds']) in (int,float) and math.isfinite(result['seconds']) and
         0 <= result['seconds'] < s.TOTAL_SECONDS, 'RESULT_COMPLETION')
    for name,cap in (('stdout',s.STDOUT),('stderr',s.STDERR)):
        need(type(result[name]) is bytes and len(result[name]) <= cap, 'RESULT_STREAM')
    hashes = check_artifacts(role,result['artifacts'])
    wire = dict(result,files=[(x.path,x.size,x.sha256) for x in result['files']],
        argv=list(result['argv']),stdout=base64.b64encode(result['stdout']).decode('ascii'),
        stderr=base64.b64encode(result['stderr']).decode('ascii'),
        artifacts={k:base64.b64encode(v).decode('ascii') for k,v in result['artifacts'].items()})
    raw = canonical({'version':1,'result':wire,'artifact_sha256':hashes})
    need(len(raw) <= MAX_RESULT, 'RESULT_LIMIT')
    return raw

def decode_result(raw, role, run, manifest):
    import p1r_linux_supervisor as s
    def unique(pairs):
        out = {}
        for k,v in pairs:
            need(k not in out, 'RESULT_DUPLICATE')
            out[k] = v
        return out
    need(type(raw) is bytes and 0 < len(raw) <= MAX_RESULT, 'RESULT_LIMIT')
    try:
        packet = json.loads(raw,object_pairs_hook=unique)
        need(type(packet) is dict and set(packet) == {'version','result','artifact_sha256'} and
             type(packet['version']) is int and packet['version'] == 1, 'RESULT_PACKET')
        row = packet['result']
        need(type(row) is dict and set(row) == RESULT_KEYS and type(row['artifacts']) is dict and
             type(row['argv']) is list and type(row['files']) is list, 'RESULT_SCHEMA')
        def binary(value):
            need(type(value) is str, 'RESULT_ENCODING')
            data = base64.b64decode(value,validate=True)
            need(base64.b64encode(data).decode('ascii') == value, 'RESULT_ENCODING')
            return data
        pins = []
        for item in row['files']:
            need(type(item) is list and len(item) == 3, 'RESULT_PIN')
            pins.append(s.Pin(*item))
        result = dict(row,files=tuple(pins),argv=tuple(row['argv']),
            stdout=binary(row['stdout']),stderr=binary(row['stderr']),
            artifacts={k:binary(v) for k,v in row['artifacts'].items()})
        plan = s.plan_for(role,run,manifest)
        need(result['operation'] == role and result['unit'] == plan.unit and
             result['argv'] == plan.argv and result['files'] == plan.pins and
             result['actual_execution'] is True, 'RESULT_BINDING')
        need(encode_result(result) == raw, 'RESULT_CANONICAL_OR_HASH')
        return result
    except (ValueError,TypeError,KeyError,UnicodeError) as exc:
        raise Stop('RESULT_DECODE') from exc
