"""Explicitly invoked, fixed two-payload U3 check. No workflow or installer.

No import-time I/O. CLI requires the exact approval flag below. No payload,
raw header or diagnostic artifact is saved; only a bounded summary is printed.
Platform TLS/clock trust and OS isolation remain unproven. Stop on first error;
never repeat this command after an uncertain/failed attempt without reporting.
"""
import datetime as dt
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


def run_once(*, connect, clock, utc_now):
    now = utc_now()
    transport.need(type(now) is dt.datetime and now.tzinfo is not None and
                   now < dt.datetime(2026, 10, 20, 7, 32, 55, tzinfo=dt.timezone.utc),
                   'EXPIRED_OR_UNKNOWN_CLOCK')
    transport.need(not any(k in os.environ for k in ('SSL_CERT_FILE', 'SSL_CERT_DIR', 'SSLKEYLOGFILE')),
                   'TLS_ENV_OVERRIDE')
    specs = plans()
    for spec in specs:
        spec.checked()
    budget = transport.Budget(transport.Limits(24576, 1800000, 2097152, 65536,
                                              3, 120, 45, 4096), clock())
    result = dict(status='STOP', started_at=now.isoformat(), receipts=[], records=budget.records,
                  raw_payload_saved=False, raw_headers_saved=False, diagnostic_artifact_saved=False,
                  installed_or_executed_payload=False, retry=0,
                  physical_tls_tcp_dns_wire_bytes='UNMEASURED',
                  independent_signature_key_clock_and_isolation='UNPROVEN')
    try:
        for spec in specs:
            # Recheck actual UTC at each payload; never extend the frozen deadline.
            transport.need(utc_now() < dt.datetime(2026, 10, 20, 7, 32, 55,
                                                  tzinfo=dt.timezone.utc), 'EXPIRED_OR_UNKNOWN_CLOCK')
            result['receipts'].append(transport.acquire(spec, budget, Discard(),
                                                       connect=connect, clock=clock))
        result['status'] = 'PINNED_TRANSPORT_PROBE_CONTENT_MATCH_RUNTIME_UNPROVEN'
    except BaseException:
        # Ledger contains only fixed reason codes, not raw callback errors/headers.
        result['status'] = 'STOP_NO_RETRY'
    result['used'] = dict(budget.used)
    result['completed_at'] = utc_now().isoformat()
    return result


def main():
    transport.need(sys.argv[1:] == ['--run-approved-public-transport-once'], 'EXPLICIT_APPROVAL_FLAG')
    def expired(*_):
        raise TimeoutError('PROBE_DEADLINE')
    signal.signal(signal.SIGALRM, expired)
    signal.alarm(120)  # Local bounded probe, not external U6 watchdog attestation.
    try:
        result = run_once(connect=transport.tls_connect, clock=time.monotonic,
                          utc_now=lambda: dt.datetime.now(dt.timezone.utc))
    except BaseException:
        result = dict(status='PRECONDITION_OR_TIMEOUT_STOP_NO_RETRY')
    finally:
        signal.alarm(0)
    raw = json.dumps(result, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
    transport.need(len(raw) <= 1048576, 'DIAGNOSTIC_LIMIT')
    print(raw.decode())
    return 0 if result['status'] == 'PINNED_TRANSPORT_PROBE_CONTENT_MATCH_RUNTIME_UNPROVEN' else 78


if __name__ == '__main__':
    raise SystemExit(main())
