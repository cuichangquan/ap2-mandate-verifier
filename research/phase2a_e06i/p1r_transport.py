"""U3 public GET receiver. No CLI, import-time I/O or execution authority.

Explicit connector/clock injection is mandatory in acquire(). tls_connect is
an optional stdlib adapter, NOT invoked by the offline tests. Pins supplied by
the caller are not authenticated here. Counts cover returned HTTP plaintext,
not TLS/TCP/DNS/kernel buffering. Blocking DNS/connect/handshake/sink/close
need a future external watchdog; local deadlines do not attest OS isolation.

The caller quarantines sink content and transfers handle-close ownership to
acquire, including on failure. No file staging, fsync, commit, installer or
legacy preparation adapter ships. A partial sink must NEVER be consumed.
"""
from dataclasses import dataclass, field
import hashlib
import math
import re
import socket
import ssl
from urllib.parse import unquote, urlsplit


class Stop(ValueError):
    pass


ERROR_CODES = frozenset('URL LIMITS SPEC SPEC_ID HOP_POLICY CLOCK DUPLICATE_INPUT '
                       'DEADLINE REQUEST_LIMIT READ_SIZE RECV_TYPE RECV_CONTRACT '
                       'HEADER_EOF BODY_EOF HEADER_LIMIT LINE_LIMIT HEADERS '
                       'DUPLICATE_HEADER LOCATION ENCODING FRAMING BODY_SIZE '
                       'CONTENT_LENGTH FRAMING_POLICY CHUNK CHUNK_COUNT CHUNK_CRLF '
                       'TRAILER SINK_WRITE STATUS UNEXPECTED_LOCATION HASH '
                       'CLOSE_UNCERTAIN CONNECT_TIMEOUT TLS_PROTOCOL '
                       'EXPIRED_OR_UNKNOWN_CLOCK TLS_ENV_OVERRIDE EXPLICIT_APPROVAL_FLAG '
                       'DIAGNOSTIC_LIMIT DIAGNOSTIC_PHASE RUNTIME_IDENTITY_UNAVAILABLE'.split()) | frozenset(
    prefix + key for prefix in ('BUDGET_', 'LIMIT_')
    for key in ('HEADER', 'CONTENT', 'WIRE', 'FRAMING'))

PHASES = frozenset('UNKNOWN SPEC_CHECK OPERATION_CLOCK CONNECTOR TLS_VALIDATE TLS_CONTEXT '
                   'DNS_OR_TCP_CONNECT TLS_WRAP TLS_TIMEOUT_SETUP TLS_HANDSHAKE TLS_ALPN '
                   'HTTP_TIMEOUT_SETUP HTTP_SEND HTTP_HEADERS HTTP_BODY CONTENT_HASH '
                   'CONNECTION_CLOSE SINK_CLOSE TIME_FINALIZATION PROBE_PRECONDITION'.split())


def annotate(error, note):
    """Fixed notes only; diagnostic failure must never replace a primary."""
    try:
        BaseException.add_note(error, note)
    except BaseException:
        pass


def in_phase(phase, function, *args, **kwargs):
    """One boundary for failures from finalization primitives and callbacks.

    Inner, more-specific annotations take precedence. Unlike mutable caller
    state, this boundary also covers exceptions raised after a try's body.
    """
    need(phase in PHASES, 'DIAGNOSTIC_PHASE')
    try:
        return function(*args, **kwargs)
    except BaseException as error:
        annotate(error, 'U3_PHASE:' + phase)
        raise


def safe_reason(error):
    if type(error) is Stop and type(error.args) is tuple and len(error.args) == 1:
        value = error.args[0]
        if type(value) is str and value in ERROR_CODES:
            return value
    return 'IO_OR_CALLBACK_FAILURE'


def diagnostic(error, phase='UNKNOWN'):
    """Closed enum/numeric metadata; no exception text, URL, IP or traceback.

    DNS_OR_TCP_CONNECT is deliberately combined: create_connection may try
    several resolved addresses and retain only the last error. No DNS/TCP
    packet counts or one-TCP-attempt guarantee are inferred from this label.
    """
    result = dict(phase=phase if phase in PHASES else 'UNKNOWN', category='OTHER',
                  errno=None, errno_domain='NONE', verify_code=None,
                  cleanup_uncertain=None, metadata_uncertain=False)
    try:
        kind = type(error)
        if kind is socket.gaierror:
            result.update(category='DNS_LOOKUP_ERROR', errno_domain='EAI')
        elif kind is ssl.SSLCertVerificationError:
            result['category'] = 'TLS_CERT_VERIFY_ERROR'
            value = getattr(error, 'verify_code', None)
            if type(value) is int and -65535 <= value <= 65535:
                result['verify_code'] = value
        elif kind in (ssl.SSLError, ssl.SSLZeroReturnError, ssl.SSLWantReadError,
                      ssl.SSLWantWriteError, ssl.SSLSyscallError, ssl.SSLEOFError):
            result['category'] = 'TLS_ERROR'
        elif kind is PermissionError:
            result.update(category='OS_PERMISSION_ERROR', errno_domain='OS')
        elif kind is TimeoutError:
            result.update(category='TIMEOUT', errno_domain='OS')
        elif kind in (ConnectionError, ConnectionRefusedError, ConnectionResetError,
                      ConnectionAbortedError, BrokenPipeError, BlockingIOError,
                      InterruptedError, FileNotFoundError, FileExistsError,
                      IsADirectoryError, NotADirectoryError, ProcessLookupError,
                      ChildProcessError, OSError):
            result.update(category='OS_CONNECTION_OR_IO_ERROR', errno_domain='OS')
        elif kind is Stop:
            result['category'] = 'INTERNAL_POLICY_STOP'
        elif kind in (KeyboardInterrupt, SystemExit):
            result['category'] = 'CANCELLED'
        if result['errno_domain'] != 'NONE':
            value = error.errno
            if type(value) is int and -65535 <= value <= 65535:
                result['errno'] = value
        notes = getattr(error, '__notes__', [])
        if type(notes) is not list or len(notes) > 16:
            result['metadata_uncertain'] = True
            return result
        result['cleanup_uncertain'] = any(type(n) is str and n == 'CLOSE_UNCERTAIN' for n in notes)
        for note in notes:
            if type(note) is str and len(note) <= 64 and note.startswith('U3_PHASE:') and note[9:] in PHASES:
                result['phase'] = note[9:]
                break
    except BaseException:
        result['metadata_uncertain'] = True
    return result


def need(ok, reason):
    if not ok:
        raise Stop(reason)


def integer(n, minimum=0, maximum=2**53):
    return type(n) is int and minimum <= n <= maximum


def positive(n):
    return type(n) in (int, float) and 0 < n <= 86400 and math.isfinite(n)


def endpoint(value):
    """Exact canonical public URL syntax; DNS/egress policy is external."""
    need(type(value) is str and 0 < len(value) <= 4096 and
         all(32 < ord(c) < 127 for c in value) and
         not any(c in value for c in ('?', '#', '\\')), 'URL')
    try:
        u = urlsplit(value)
    except ValueError:
        raise Stop('URL') from None
    need(u.scheme == 'https' and u.netloc == u.hostname and u.hostname and
         re.fullmatch(r'[a-z0-9]+(?:[.-][a-z0-9]+)*\.[a-z]{2,63}', u.hostname) and
         u.path.startswith('/') and not u.path.startswith('//') and
         value == 'https://' + u.hostname + u.path, 'URL')
    need(not re.search(r'%(?![0-9A-F]{2})', u.path), 'URL')
    try:
        decoded = unquote(u.path, errors='strict')
    except UnicodeError:
        raise Stop('URL') from None
    need(all(32 < ord(c) < 127 for c in decoded) and '\\' not in decoded and
         decoded.count('/') == u.path.count('/') and
         all(p not in ('.', '..', '') for p in decoded[1:].split('/')), 'URL')
    for match in re.finditer(r'%([0-9A-F]{2})', u.path):
        need(chr(int(match[1], 16)) not in
             'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~', 'URL')
    return u


@dataclass(frozen=True)
class Limits:
    header: int
    content: int
    wire: int
    framing: int
    requests: int
    total_seconds: float
    hop_seconds: float
    error_body: int
    chunk_line: int = 32
    chunks: int = 4096
    fields: int = 128

    def checked(self, *, aggregate_header=False):
        # Spec.header is per response; Budget.header is the explicit sum cap.
        need(integer(self.header, 4, 2**53 if aggregate_header else 8192) and integer(self.content) and
             integer(self.wire) and integer(self.framing) and
             integer(self.requests, 1, 512) and integer(self.error_body) and
             integer(self.chunk_line, 3, 128) and integer(self.chunks, 1, 65536) and
             integer(self.fields, 1, 128) and positive(self.total_seconds) and
             positive(self.hop_seconds), 'LIMITS')


@dataclass(frozen=True)
class TransferSpec:
    identity: str
    name: str
    kind: str
    size: int
    sha256: str
    origin: str
    limits: Limits
    location: str | None = None
    final: str | None = None
    framings: tuple = ('length', 'chunked')

    def checked(self):
        need(type(self.limits) is Limits, 'SPEC')
        self.limits.checked()
        for value in (self.identity, self.name):
            need(type(value) is str and
                 re.fullmatch(r'[A-Za-z0-9_-][A-Za-z0-9_.-]{0,127}', value), 'SPEC_ID')
        need(type(self.kind) is str and self.kind in
             ('source_archive', 'debian_package', 'pip_bootstrap', 'python_wheel', 'ruby_gem') and
             integer(self.size, 1) and self.size <= self.limits.content and
             self.size <= self.limits.wire and type(self.sha256) is str and
             re.fullmatch(r'[a-f0-9]{64}', self.sha256) and
             type(self.framings) is tuple and 1 <= len(self.framings) <= 2 and
             all(type(x) is str for x in self.framings) and
             len(set(self.framings)) == len(self.framings) and
             all(x in ('length', 'chunked') for x in self.framings), 'SPEC')
        origin = endpoint(self.origin)
        if self.location is None and self.final is None:
            need(self.limits.requests == 1, 'HOP_POLICY')
        else:
            need(type(self.location) is str and type(self.final) is str and
                 self.limits.requests == 2 and self.final != self.origin, 'HOP_POLICY')
            final = endpoint(self.final)
            need(origin.hostname == final.hostname and
                 self.location in (self.final, final.path), 'HOP_POLICY')


@dataclass
class Budget:
    """Shared counters are monotonic, including failed operations. Not thread-safe."""
    limits: Limits
    started: float
    used: dict = field(init=False)
    records: list = field(default_factory=list, init=False)
    identities: set = field(default_factory=set, init=False)
    names: set = field(default_factory=set, init=False)
    busy: bool = field(default=False, init=False)
    last: float = field(init=False)

    def __post_init__(self):
        need(type(self.limits) is Limits, 'BUDGET')
        self.limits.checked(aggregate_header=True)
        need(type(self.started) in (int, float) and abs(self.started) <= 2**53 and
             math.isfinite(self.started), 'CLOCK')
        self.last = self.started
        self.used = dict(header=0, content=0, wire=0, framing=0, requests=0)

    def now(self, clock):
        now = clock()
        need(type(now) in (int, float) and abs(now) <= 2**53 and
             math.isfinite(now) and now >= self.last, 'CLOCK')
        self.last = now
        return now


def close_once(resource, primary=None):
    """One attempt; never mask a primary exception or retry an uncertain FD."""
    try:
        resource.close()
    except BaseException as error:
        if primary is not None:
            annotate(primary, 'CLOSE_UNCERTAIN')
            return False
        else:
            raise Stop('CLOSE_UNCERTAIN') from error
    return True


def tls_connect(url, seconds):
    """Optional connector, deliberately not a default argument to acquire().

    No proxy/netrc/auth. OS resolver may outlive socket timeout: caller MUST
    arrange an external worker watchdog before any separately approved use.
    """
    phase, owned = 'TLS_VALIDATE', None
    try:
        u = endpoint(url)
        need(positive(seconds), 'CONNECT_TIMEOUT')
        phase = 'TLS_CONTEXT'
        # Avoid SSLKEYLOGFILE side effects; platform CA trust is still external.
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname = True
        context.verify_mode = ssl.CERT_REQUIRED
        context.load_default_certs()
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.set_alpn_protocols(['http/1.1'])
        phase = 'DNS_OR_TCP_CONNECT'
        owned = socket.create_connection((u.hostname, 443), timeout=min(seconds, 5))
        phase = 'TLS_WRAP'
        wrapped = context.wrap_socket(owned, server_hostname=u.hostname,
                                      do_handshake_on_connect=False)
        owned = wrapped  # wrap_socket takes ownership; never close the old handle too.
        phase = 'TLS_TIMEOUT_SETUP'
        wrapped.settimeout(min(seconds, 5))
        phase = 'TLS_HANDSHAKE'
        wrapped.do_handshake()
        phase = 'TLS_ALPN'
        need(wrapped.selected_alpn_protocol() in (None, 'http/1.1'), 'TLS_PROTOCOL')
        return wrapped
    except BaseException as error:
        annotate(error, 'U3_PHASE:' + phase)
        if owned is not None:
            close_once(owned, error)
        raise


class Reader:
    def __init__(self, conn, spec, budget, operation, hop, clock):
        self.conn, self.spec, self.budget = conn, spec, budget
        self.operation, self.hop, self.clock = operation, hop, clock

    def remaining(self):
        now = self.budget.now(self.clock)
        left = min(self.budget.started + self.budget.limits.total_seconds,
                   self.operation['started'] + self.spec.limits.total_seconds,
                   self.hop['started'] + min(self.spec.limits.hop_seconds,
                                             self.budget.limits.hop_seconds)) - now
        need(left > 0, 'DEADLINE')
        return min(left, 5)

    def reserve(self, n, category):
        keys = ('header',) if category == 'header' else ('wire', category)
        for key in keys:
            cap = getattr(self.budget.limits, key)
            need(self.budget.used[key] + n <= cap, 'BUDGET_' + key.upper())
            if key == 'header':
                need(self.hop[key] + n <= self.spec.limits.header, 'HEADER_LIMIT')
            else:
                need(self.operation[key] + n <= getattr(self.spec.limits, key),
                     'LIMIT_' + key.upper())

    def receive(self, n, category):
        need(integer(n, 1, 65536), 'READ_SIZE')
        self.reserve(n, category)  # Before settimeout/recv, never cap only after reading.
        self.conn.settimeout(self.remaining())
        part = self.conn.recv(n)
        need(type(part) is bytes, 'RECV_TYPE')
        keys = ('header',) if category == 'header' else ('wire', category)
        for key in keys:
            self.budget.used[key] += len(part)
            self.operation[key] += len(part)
            self.hop[key] += len(part)
        # A malicious injected connector may violate recv(n); record all returned
        # bytes but fail closed. A compliant socket never returns more than n.
        need(len(part) <= n, 'RECV_CONTRACT')
        need(part, 'HEADER_EOF' if category == 'header' else 'BODY_EOF')
        self.remaining()
        return part

    def exact(self, n, category):
        result = bytearray()
        while len(result) < n:
            result.extend(self.receive(min(n - len(result), 65536), category))
        return bytes(result)

    def line(self, cap, category):
        raw = bytearray()
        while not raw.endswith(b'\r\n'):
            need(len(raw) < cap, 'LINE_LIMIT')
            raw.extend(self.receive(1, category))
        return bytes(raw)

    def headers(self):
        raw = bytearray()
        while not raw.endswith(b'\r\n\r\n'):
            raw.extend(self.receive(1, 'header'))
        lines = bytes(raw).split(b'\r\n')
        match = re.fullmatch(rb'HTTP/1\.([01]) ([0-9]{3}) [ -~]*', lines[0])
        need(match is not None and len(lines) - 3 <= self.spec.limits.fields, 'HEADERS')
        self.hop['status'] = int(match[2])
        result = {}
        for line in lines[1:-2]:
            name, colon, value = line.partition(b':')
            need(colon and re.fullmatch(rb"[!#$%&'*+.^_`|~0-9A-Za-z-]+", name) and
                 all(32 <= c < 127 for c in value), 'HEADERS')
            key = name.lower()
            need(key not in result, 'DUPLICATE_HEADER')
            if key == b'location':
                value = value[1:] if value.startswith(b' ') else value
                need(value and all(32 < c < 127 for c in value), 'LOCATION')
            else:
                value = value.strip(b' ')
            result[key] = value
        need(result.get(b'content-encoding', b'identity') == b'identity', 'ENCODING')
        need(not (b'content-length' in result and b'transfer-encoding' in result), 'FRAMING')
        need(match[1] == b'1' or b'transfer-encoding' not in result, 'FRAMING')
        return result


def body(reader, fields, *, expected=None, sink=None):
    """Stream or bounded-discard one body; no payload-sized allocation."""
    count, digest = 0, hashlib.sha256()
    cap = reader.spec.limits.error_body if expected is None else expected
    def emit(n):
        nonlocal count
        need(count + n <= cap, 'BODY_SIZE')
        # Reject a declared impossible read before touching the connection.
        reader.reserve(n, 'content')
        while n:
            part = reader.receive(min(n, 65536), 'content')
            count += len(part)
            n -= len(part)
            if sink is not None:
                written = sink.write(part)
                need(type(written) is int and written == len(part), 'SINK_WRITE')
                reader.remaining()
            digest.update(part)
    if b'content-length' in fields:
        value = fields[b'content-length']
        need(re.fullmatch(rb'0|[1-9][0-9]{0,15}', value), 'CONTENT_LENGTH')
        size = int(value)
        need(size <= cap and (expected is None or size == expected), 'BODY_SIZE')
        need(expected is None or 'length' in reader.spec.framings, 'FRAMING_POLICY')
        emit(size)
    else:
        need(fields.get(b'transfer-encoding') == b'chunked', 'FRAMING')
        need(expected is None or 'chunked' in reader.spec.framings, 'FRAMING_POLICY')
        for _ in range(reader.spec.limits.chunks):
            line = reader.line(reader.spec.limits.chunk_line, 'framing')
            need(re.fullmatch(rb'[0-9A-Fa-f]{1,8}\r\n', line), 'CHUNK')
            size = int(line[:-2], 16)
            if not size:
                need(reader.exact(2, 'framing') == b'\r\n', 'TRAILER')
                break
            emit(size)
            need(reader.exact(2, 'framing') == b'\r\n', 'CHUNK_CRLF')
        else:
            raise Stop('CHUNK_COUNT')
    need(expected is None or count == expected, 'BODY_SIZE')
    return digest.hexdigest()


def finish_time(record, budget, clock, primary=None):
    try:
        record['finished'] = budget.now(clock)
        record['seconds'] = record['finished'] - record['started']
    except BaseException as error:
        if primary is not None:
            annotate(primary, 'CLOCK_FINALIZATION_UNCERTAIN')
        else:
            raise


def operation_deadline(budget, operation, spec, clock):
    need(budget.now(clock) < min(budget.started + budget.limits.total_seconds,
                                operation['started'] + spec.limits.total_seconds), 'DEADLINE')


def hop(url, spec, budget, operation, clock, connect, sink, redirect):
    need(budget.used['requests'] < budget.limits.requests and
         operation['requests'] < spec.limits.requests, 'REQUEST_LIMIT')
    now = budget.now(clock)
    record = dict(endpoint='origin' if not operation['hops'] else 'final', started=now,
                  header=0, content=0, wire=0, framing=0, status=None, closed=False,
                  finished=None, seconds=None, observed_sha256=None, hash_match=None,
                  phase='CONNECTOR', connector_returned=False,
                  http_send_started=False, http_send_complete=False)
    operation['hops'].append(record)
    budget.used['requests'] += 1
    operation['requests'] += 1
    # Attempt charged even if connector fails before returning an owned handle.
    left = min(budget.started + budget.limits.total_seconds,
               operation['started'] + spec.limits.total_seconds,
               now + min(spec.limits.hop_seconds, budget.limits.hop_seconds)) - now
    need(left > 0, 'DEADLINE')
    conn, reader, primary = None, None, None
    try:
        conn = connect(url, min(left, 5))
        record['connector_returned'] = True
        reader = Reader(conn, spec, budget, operation, record, clock)
        u = endpoint(url)
        record['phase'] = 'HTTP_TIMEOUT_SETUP'
        conn.settimeout(reader.remaining())
        record.update(phase='HTTP_SEND', http_send_started=True)
        conn.sendall(('GET ' + u.path + ' HTTP/1.1\r\nHost: ' + u.hostname +
                      '\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n').encode('ascii'))
        record.update(phase='HTTP_HEADERS', http_send_complete=True)
        fields = reader.headers()
        record['phase'] = 'HTTP_BODY'
        if record['status'] != 200 or redirect:
            body(reader, fields)  # Include bounded 302/error bytes; never hash them as payload.
            need(redirect and record['status'] == 302, 'STATUS')
            need(fields.get(b'location') == spec.location.encode('ascii'), 'LOCATION')
            return None
        need(b'location' not in fields, 'UNEXPECTED_LOCATION')
        observed = body(reader, fields, expected=spec.size, sink=sink)
        record['phase'] = 'CONTENT_HASH'
        record.update(observed_sha256=observed, hash_match=observed == spec.sha256)
        need(record['hash_match'], 'HASH')
        return observed
    except BaseException as error:
        annotate(error, 'U3_PHASE:' + record['phase'])
        primary = error
        raise
    finally:
        try:
            if conn is not None:
                record['closed'] = in_phase('CONNECTION_CLOSE', close_once, conn, primary)
        except BaseException as error:
            primary = error
            raise
        finally:
            in_phase('TIME_FINALIZATION', finish_time, record, budget, clock, primary)
        if primary is None and reader is not None:
            in_phase('TIME_FINALIZATION', reader.remaining)


def acquire(spec, budget, sink, *, connect, clock):
    """Return a content-only receipt after ALL owned handles close successfully.

    After Budget type/busy/record-cap preconditions, owns sink.close exactly
    once, even for invalid specs. Caller must not use
    partial content on exception. Budget is single-owner, no retry/rollback.
    Explicit connector is a trust boundary; its fake receipts cannot attest
    network/TLS authority. No filesystem sealing or execution follows success.
    """
    need(type(budget) is Budget and not budget.busy, 'BUDGET_BUSY_OR_TYPE')
    need(len(budget.records) < budget.limits.requests, 'OPERATION_LIMIT')
    budget.busy = True
    operation = dict(identity=None, state='SPEC_CHECKING', header=0, content=0,
                     wire=0, framing=0, requests=0, hops=[], sink_closed=False, phase='SPEC_CHECK')
    budget.records.append(operation)
    try:
        primary = None
        try:
            need(type(spec) is TransferSpec, 'SPEC')
            spec.checked()
            need(spec.identity not in budget.identities and spec.name not in budget.names, 'DUPLICATE_INPUT')
            budget.identities.add(spec.identity)
            budget.names.add(spec.name)
            operation['phase'] = 'OPERATION_CLOCK'
            operation.update(identity=spec.identity,
                             started=in_phase('OPERATION_CLOCK', budget.now, clock), state='REQUESTING')
            operation['phase'] = 'CONNECTOR'
            hop(spec.origin, spec, budget, operation, clock, connect, sink, spec.final is not None)
            if spec.final is not None:
                hop(spec.final, spec, budget, operation, clock, connect, sink, False)
            operation['phase'] = 'TIME_FINALIZATION'
            in_phase('TIME_FINALIZATION', operation_deadline, budget, operation, spec, clock)
        except BaseException as error:
            primary = error
            raise
        finally:
            operation['sink_closed'] = in_phase('SINK_CLOSE', close_once, sink, primary)
        # Close time counts too; no successful receipt if close exhausted deadline.
        operation['phase'] = 'TIME_FINALIZATION'
        in_phase('TIME_FINALIZATION', operation_deadline, budget, operation, spec, clock)
    except BaseException as error:
        annotate(error, 'U3_PHASE:' + operation['phase'])
        operation['state'] = 'STOP'
        operation['reason'] = safe_reason(error)
        operation['failure'] = diagnostic(error, operation['phase'])
        operation['close_uncertain'] = (operation['failure']['cleanup_uncertain'] is not False or
            any(h['connector_returned'] and not h['closed'] for h in operation['hops']) or
            operation['reason'] == 'CLOSE_UNCERTAIN' or not operation['sink_closed'])
        raise
    finally:
        budget.busy = False
    operation['state'] = 'CONTENT_VERIFIED'
    return dict(status='CONTENT_HASH_SIZE_MATCH_NOT_NETWORK_ATTESTATION', identity=spec.identity,
                size=spec.size, sha256=spec.sha256, durable_or_sealed=False,
                runtime_validated=False, execution_authorized=False)
