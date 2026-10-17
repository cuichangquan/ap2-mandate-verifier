"""Explicitly invoked, fixed two-payload U3 check. No workflow or installer.

No import-time I/O. CLI requires the exact approval flag below. No payload,
raw header or diagnostic artifact is saved; only a bounded summary is printed.
Platform TLS/clock trust and OS isolation remain unproven. Stop on first error;
never repeat this command after an uncertain/failed attempt without reporting.
"""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import signal
import sys
import time

# -I omits the script directory: use the explicitly verified sibling source,
# not cwd/PYTHONPATH/user site. The caller must hash-bind these files first.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p1r_transport as transport


def plans():
    ap2 = transport.TransferSpec(
        'fixed-ap2', 'ap2', 'source_archive', 1776074,
        '526288baea429019db3f4a7ccb8aad15d629b8c760db3f30ec511d32a53b0d47',
        'https://codeload.github.com/google-agentic-commerce/AP2/tar.gz/b4587ac1d055888a73b4b21750973cffba961793',
        transport.Limits(8192, 1776074, 2000000, 32768, 1, 60, 45, 4096))
    deb = transport.TransferSpec(
        'fixed-libkeyutils1', 'libkeyutils1', 'debian_package', 8808,
        'cfac89e6a7a54ff3c6a4f843310e25efeddaa771baeae470bd98bd588c373563',
        'https://snapshot.debian.org/archive/debian/20261014T000000Z/pool/main/k/keyutils/libkeyutils1_1.6.3-2_amd64.deb',
        transport.Limits(8192, 12904, 65536, 16384, 2, 45, 20, 4096),
        location='/file/5d49f8def7847ffc2f78fa1430a385e1a40fd188/libkeyutils1_1.6.3-2_amd64.deb',
        final='https://snapshot.debian.org/file/5d49f8def7847ffc2f78fa1430a385e1a40fd188/libkeyutils1_1.6.3-2_amd64.deb')
    return (ap2, deb)


class Discard:
    """No file/memory payload retention beyond the incoming bounded block."""
    def write(self, block):
        return len(block)
    def close(self):
        pass


def runtime_identity():
    """This process's bounded numeric/digest identity, no raw filesystem paths."""
    identity = dict(python_version=list(sys.version_info[:3]),
                    implementation='CPYTHON' if sys.implementation.name == 'cpython' else 'OTHER',
                    openssl_version=list(transport.ssl.OPENSSL_VERSION_INFO),
                    platform=sys.platform if sys.platform in ('darwin', 'linux') else 'OTHER',
                    isolated=bool(sys.flags.isolated), no_site=bool(sys.flags.no_site),
                    dont_write_bytecode=bool(sys.flags.dont_write_bytecode),
                    source_sha256={}, status='COMPLETE')
    try:
        for key, path in (('executable', sys.executable), ('socket_module', transport.socket.__file__),
                          ('ssl_module', transport.ssl.__file__)):
            transport.need(type(path) is str and 0 < len(path) <= 8192, 'RUNTIME_IDENTITY_UNAVAILABLE')
            identity[key + '_path_sha256'] = hashlib.sha256(os.fsencode(path)).hexdigest()
        for key, path in (('transport', transport.__file__), ('probe', __file__)):
            with open(path, 'rb') as stream:
                raw = stream.read(131073)
            transport.need(0 < len(raw) <= 131072, 'RUNTIME_IDENTITY_UNAVAILABLE')
            identity['source_sha256'][key] = hashlib.sha256(raw).hexdigest()
    except BaseException:
        identity['status'] = 'INCOMPLETE'
    return identity


def run_once(*, connect, clock, utc_now):
    budget = None
    result = dict(status='STOP', started_at=None, completed_at=None, receipts=[], records=[],
                  runtime=runtime_identity(),
                  raw_payload_saved=False, raw_headers_saved=False, diagnostic_artifact_saved=False,
                  installed_or_executed_payload=False, retry=0,
                  physical_tls_tcp_dns_wire_bytes='UNMEASURED',
                  dns_and_tcp_attempts='UNKNOWN_MULTIPLE_RESOLVED_ADDRESSES_POSSIBLE',
                  independent_signature_key_clock_and_isolation='UNPROVEN')
    try:
        transport.need(result['runtime']['status'] == 'COMPLETE', 'RUNTIME_IDENTITY_UNAVAILABLE')
        now = utc_now()
        transport.need(type(now) is dt.datetime and now.tzinfo is not None and
                       now < dt.datetime(2026, 10, 20, 7, 32, 55, tzinfo=dt.timezone.utc),
                       'EXPIRED_OR_UNKNOWN_CLOCK')
        result['started_at'] = now.isoformat()
        transport.need(not any(k in os.environ for k in ('SSL_CERT_FILE', 'SSL_CERT_DIR', 'SSLKEYLOGFILE')),
                       'TLS_ENV_OVERRIDE')
        specs = plans()
        for spec in specs:
            spec.checked()
        budget = transport.Budget(transport.Limits(24576, 1800000, 2097152, 65536,
                                                  3, 120, 45, 4096), clock())
        result['records'] = budget.records
        for spec in specs:
            # Recheck actual UTC at each payload; never extend the frozen deadline.
            transport.need(utc_now() < dt.datetime(2026, 10, 20, 7, 32, 55,
                                                  tzinfo=dt.timezone.utc), 'EXPIRED_OR_UNKNOWN_CLOCK')
            result['receipts'].append(transport.acquire(spec, budget, Discard(),
                                                       connect=connect, clock=clock))
        result['status'] = 'PINNED_TRANSPORT_PROBE_CONTENT_MATCH_RUNTIME_UNPROVEN'
    except BaseException as error:
        result['reason'] = transport.safe_reason(error)
        result['failure'] = transport.diagnostic(error, 'PROBE_PRECONDITION')
        result['status'] = 'STOP_NO_RETRY'
    result['used'] = dict(budget.used) if budget is not None else {}
    try:
        finished = utc_now()
        transport.need(type(finished) is dt.datetime and finished.tzinfo is not None, 'CLOCK')
        result['completed_at'] = finished.isoformat()
    except BaseException as error:
        result['clock_finalization'] = 'UNAVAILABLE'
        if 'failure' not in result:
            result.update(status='STOP_NO_RETRY', reason=transport.safe_reason(error),
                          failure=transport.diagnostic(error, 'TIME_FINALIZATION'))
    return result


def failure_result(error):
    result = dict(status='PRECONDITION_OR_TIMEOUT_STOP_NO_RETRY',
                  reason=transport.safe_reason(error),
                  failure=transport.diagnostic(error, 'PROBE_PRECONDITION'))
    try:
        result['runtime'] = runtime_identity()
    except BaseException:
        result['runtime'] = {'status': 'UNAVAILABLE'}
    return result


def main():
    """All controllable CLI rejection paths use one bounded output boundary.

    Interpreter/import bootstrap and an unwritable OS stdout are not claimed
    to produce a complete JSON document. No exception text is printed here.
    """
    alarm_expired = False
    alarm_installed = False
    cancellation = transport.WallCancellation()
    # Available before arming the timer, including if richer diagnostics are
    # interrupted. It carries no untrusted string or claimed causal phase.
    result = dict(status='SAFE_OUTPUT_STOP_NO_RETRY', reason='FALLBACK_UNAVAILABLE',
                  runtime={'status': 'UNAVAILABLE'},
                  failure={'phase': 'UNKNOWN', 'category': 'OTHER', 'metadata_uncertain': True})
    def expired(*_):
        nonlocal alarm_expired
        alarm_expired = True
        cancellation.request()
    try:
        transport.need(sys.argv[1:] == ['--run-approved-public-transport-once'], 'EXPLICIT_APPROVAL_FLAG')
        signal.signal(signal.SIGALRM, expired)
        alarm_installed = True
        signal.alarm(120)  # Attempt clear even if installation raises uncertainly.
        result = run_once(connect=lambda url, seconds, owner: transport.tls_connect(
                              url, seconds, owner, cancellation=cancellation), clock=time.monotonic,
                          utc_now=lambda: dt.datetime.now(dt.timezone.utc))
    except BaseException as error:
        try:
            result = failure_result(error)
        except BaseException:
            pass  # Preserve the initialized bounded fallback, even on SIGALRM.
    finally:
        if alarm_installed:
            try:
                transport.in_phase('TIME_FINALIZATION', signal.alarm, 0)
            except BaseException as error:
                # Preserve any earlier failure, receipts and consumption.
                if 'failure' not in result:
                    result.update(status='STOP_NO_RETRY', reason=transport.safe_reason(error),
                                  failure=transport.diagnostic(error, 'TIME_FINALIZATION'))
                result['alarm_finalization'] = 'UNAVAILABLE'
    result['local_wall_alarm_expired'] = alarm_expired
    if alarm_expired:
        # Even a defensive metadata/cleanup handler that absorbed cancellation
        # cannot turn an expired invocation into a successful probe result.
        result['status'] = 'STOP_NO_RETRY'
        if 'failure' not in result:
            result.update(reason='PROBE_DEADLINE',
                          failure=transport.diagnostic(transport.WallDeadline()))
    try:
        raw = json.dumps(result, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
        transport.need(len(raw) <= 1048576, 'DIAGNOSTIC_LIMIT')
    except BaseException:
        raw = b'{"status":"SAFE_OUTPUT_STOP_NO_RETRY","reason":"DIAGNOSTIC_ENCODING_OR_LIMIT"}'
        result['status'] = 'SAFE_OUTPUT_STOP_NO_RETRY'
    try:
        text = raw.decode() + '\n'
        if sys.stdout.write(text) != len(text):
            return 78
        sys.stdout.flush()
    except BaseException:
        return 78  # Never print a secondary traceback to stderr.
    return 0 if result['status'] == 'PINNED_TRANSPORT_PROBE_CONTENT_MATCH_RUNTIME_UNPROVEN' else 78


if __name__ == '__main__':
    raise SystemExit(main())
