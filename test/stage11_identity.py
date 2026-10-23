"""Reviewed local comparison identity contract; no acquisition or installation."""
import hashlib
import importlib.metadata
import json
import os
import stat
import platform
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PYTHON = {'implementation': 'CPython', 'version': '3.11.15',
          'system': 'Darwin', 'machine': 'arm64'}
DEPENDENCIES = {'jwcrypto': '1.6.1', 'cryptography': '50.0.2', 'cffi': '2.0.0',
                'typing-extensions': '4.15.0', 'pycparser': '2.23',
                'jsonschema': '4.26.0', 'jsonschema-specifications': '2025.9.1',
                'referencing': '0.37.0', 'rpds-py': '0.30.0', 'attrs': '26.1.0'}
LOCKS = {'o1o3-requirements.lock': '8e6d9f8898e607fc95b41e3ed8cf24b8cb88afd95aadd86bf9797349341092ba',
         'o4-requirements.lock': '7a468daf8e42b283c0172f3cd6a61f480a04b1f10fa5be1a547e917ff8b96432'}
PINS = {'O4_HTTP_ACQUISITION.json': '06ee7ad9d219af1619c5a5aec59000ff87f6be49cff91e4a60f68968b57b20c3',
        'STAGE7_PUBLIC_CASES.json': 'ba8bfe3cea97b2230084a5ab5ef97d99701e3974160abbad06a346f8115c85b0',
        'O2O5_PUBLIC_CASES.json': 'be17fc33612ec561147100fbb901f5c2ef288d4535ed1aa69b56a61447fc8942',
        'O1O3_POLICY.json': 'e8d7ff92b0340f2415b0ebff629fbed5d631768eb1ed844d1b3733dca7656a88'}


def require_equal(actual, expected, why):
    if actual != expected:
        raise ValueError(why)


def same_stat(a, b):
    return (stat.S_ISREG(a.st_mode) and stat.S_ISREG(b.st_mode) and
            all(getattr(a, key) == getattr(b, key) for key in
                ('st_dev', 'st_ino', 'st_mode', 'st_nlink', 'st_uid', 'st_gid',
                 'st_size', 'st_mtime_ns', 'st_ctime_ns')))


def bounded_regular(path, cap):
    path = os.fspath(path)
    if not hasattr(os, 'O_NOFOLLOW') or not hasattr(os, 'O_NONBLOCK'):
        raise ValueError('safe input open unavailable')
    before = os.lstat(path)
    if not stat.S_ISREG(before.st_mode) or not 1 <= before.st_size <= cap:
        raise ValueError('pinned input type/size')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK |
                 getattr(os, 'O_CLOEXEC', 0))
    try:
        opened = os.fstat(fd)
        if not same_stat(before, opened):
            raise ValueError('pinned input changed at open')
        raw = os.read(fd, cap + 1)
        after = os.fstat(fd)
        if (len(raw) != opened.st_size or not same_stat(opened, after)
                or not same_stat(after, os.lstat(path))):
            raise ValueError('pinned input changed during read')
        return raw
    finally:
        os.close(fd)


def pinned_bytes(path, pin_name, cap):
    raw = bounded_regular(path, cap)
    require_equal(hashlib.sha256(raw).hexdigest(), PINS[pin_name], 'pinned input identity')
    return raw


def observed_environment():
    return {'python': {'implementation': platform.python_implementation(),
                       'version': platform.python_version(), 'system': platform.system(),
                       'machine': platform.machine()},
            'dependencies': {name: importlib.metadata.version(name) for name in DEPENDENCIES}}


def validate_environment(observed):
    require_equal(observed, {'python': PYTHON, 'dependencies': DEPENDENCIES},
                  'unapproved Python/dependency identity')


def current_identity():
    observed = observed_environment()
    validate_environment(observed)
    for name, digest in LOCKS.items():
        require_equal(hashlib.sha256(bounded_regular(ROOT / "research/stage11/dependencies" / name, 16384)).hexdigest(), digest,
                      'dependency lock identity')
    return {**observed, 'locks': LOCKS,
            'identity_source_sha256': hashlib.sha256(bounded_regular(Path(__file__), 16384)).hexdigest()}


def require_identity(identity):
    require_equal(identity, current_identity(), 'report Python/dependency identity')


def validate_schema(raw, expected):
    require_equal(hashlib.sha256(raw).hexdigest(), expected['sha256'], 'Schema bytes changed')
    blob = b'blob ' + str(len(raw)).encode('ascii') + b'\0' + raw
    require_equal(hashlib.sha1(blob).hexdigest(), expected['git_blob'], 'Schema git blob changed')


def schema_ledger(path):
    return json.loads(pinned_bytes(path, 'O4_HTTP_ACQUISITION.json', 65536))
