"""Fake HTTP plaintext only. No DNS/TLS/network, SDK or installation proof."""
from dataclasses import replace
from contextlib import contextmanager
import datetime as dt
import hashlib
import io
import json
import linecache
import math
import socket
import ssl
import sys
import unittest
from unittest.mock import Mock, patch

import p1r_transport as m
import p1r_transport_probe as probe


STDLIB_CREATE_CONNECTION = socket.create_connection


def tls_for_test(url, seconds, **kwargs):
    owner = m.SocketOwner()
    m.tls_connect(url, seconds, owner, **kwargs)
    return owner.resource


@contextmanager
def fake_tcp(plain=None, constructor=None):
    addresses = [(socket.AF_INET, socket.SOCK_STREAM, 6, '', ('192.0.2.1', 443))]
    constructor = constructor or Mock(return_value=plain or Mock())
    with patch.object(socket, 'getaddrinfo', return_value=addresses), \
         patch.object(socket, 'socket', constructor):
        yield constructor
DATA = b'\x00synthetic\xff content\n'
ORIGIN = 'https://snapshot.example.invalid/archive/fixed/payload.deb'
FINAL = 'https://snapshot.example.invalid/file/abcdef/payload.deb'


def transcript(body=DATA, *, status=200, fields=()):
    return (f'HTTP/1.1 {status} synthetic\r\n'.encode() +
            b''.join(k + b': ' + v + b'\r\n' for k, v in fields) +
            b'\r\n' + body)


def length(body=DATA, **kw):
    return transcript(body, fields=((b'Content-Length', str(len(body)).encode()),), **kw)


def chunked(body=DATA, sizes=(1, 3)):
    chunks, offset = [], 0
    for n in (*sizes, len(body)):
        piece = body[offset:offset + n]
        if piece:
            chunks.append(f'{len(piece):x}\r\n'.encode() + piece + b'\r\n')
            offset += len(piece)
    assert offset == len(body)
    return transcript(b''.join(chunks) + b'0\r\n\r\n', fields=((b'Transfer-Encoding', b'chunked'),))


def limits(**kw):
    return replace(m.Limits(8192, 1048576, 2097152, 65536, 1, 30, 10, 4096), **kw)


def spec(**kw):
    return replace(m.TransferSpec('sample', 'payload', 'debian_package', len(DATA),
                                  hashlib.sha256(DATA).hexdigest(), ORIGIN, limits()), **kw)


class Clock:
    value = 0.0
    def __call__(self):
        return self.value


class Conn:
    def __init__(self, raw, *, split=65536, fail=None, close_error=False, clock=None):
        self.raw, self.offset, self.split = raw, 0, split
        self.fail, self.close_error, self.clock = fail, close_error, clock
        self.reads, self.sent, self.timeouts = [], [], []
        self.closed = 0
    def settimeout(self, value):
        self.timeouts.append(value)
        if self.fail == 'timeout':
            raise OSError('synthetic timeout setup')
    def sendall(self, raw):
        self.sent.append(raw)
        if self.fail == 'send':
            raise OSError('synthetic send')
    def recv(self, n):
        self.reads.append((n, self.offset))
        if self.fail == 'recv':
            raise OSError('synthetic read')
        result = self.raw[self.offset:self.offset + min(n, self.split)]
        self.offset += len(result)
        return result
    def close(self):
        self.closed += 1
        if self.clock is not None:
            self.clock.value += 11
        if self.close_error:
            raise OSError('synthetic connection close')


class Sink:
    def __init__(self, *, short=False, write_error=False, close_error=False, clock=None):
        self.parts, self.closed = [], 0
        self.short, self.write_error, self.close_error, self.clock = short, write_error, close_error, clock
    def write(self, raw):
        if self.write_error:
            raise OSError('synthetic sink write')
        self.parts.append(raw)
        return len(raw) - 1 if self.short else len(raw)
    def close(self):
        self.closed += 1
        if self.clock is not None:
            self.clock.value += 31
        if self.close_error:
            raise OSError('synthetic sink close')


class TransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.network_events = []
        def no_network(event, args):
            if event in ('socket.connect', 'socket.getaddrinfo', 'socket.gethostbyname',
                         'socket.gethostbyaddr', 'socket.sendto'):
                cls.network_events.append(event)
                raise AssertionError('REAL_NETWORK_FORBIDDEN')
        sys.addaudithook(no_network)

    def setUp(self):
        self.clock = Clock()
        self.budget = m.Budget(limits(header=16384, requests=20), 0)
        self.sink = Sink()
        self.connections, self.calls = [], []
        for name in ('create_connection', 'getaddrinfo'):
            p = patch.object(socket, name, side_effect=AssertionError('REAL_NETWORK_FORBIDDEN'))
            p.start(); self.addCleanup(p.stop)

    def run_get(self, raws=None, item=None, sink=None, connections=None, budget=None, connect=None):
        item = item or spec()
        self.connections = connections or [Conn(x) for x in (raws or [length()])]
        def fake(url, seconds):
            self.calls.append((url, seconds))
            self.assertGreater(seconds, 0)
            self.assertLessEqual(seconds, 5)
            self.assertLessEqual(len(self.calls), len(self.connections))
            return self.connections[len(self.calls) - 1]
        return m.acquire(item, budget or self.budget, sink or self.sink,
                         connect=lambda url, seconds, owner: owner.register((connect or fake)(url, seconds)), clock=self.clock)

    def rejects(self, code, **kwargs):
        with self.assertRaisesRegex(m.Stop, '^' + code + '$') as cm:
            self.run_get(**kwargs)
        self.assertEqual(self.budget.records[-1]['state'], 'STOP')
        self.assertFalse(self.budget.busy)
        return cm.exception

    def test_direct_length_and_exact_request(self):
        result = self.run_get()
        self.assertEqual(result['status'], 'CONTENT_HASH_SIZE_MATCH_NOT_NETWORK_ATTESTATION')
        self.assertFalse(result['durable_or_sealed'])
        self.assertFalse(result['execution_authorized'])
        self.assertEqual(b''.join(self.sink.parts), DATA)
        self.assertEqual(self.sink.closed, 1)
        c = self.connections[0]
        self.assertEqual(c.closed, 1)
        self.assertEqual(c.offset, len(length()))
        self.assertEqual(c.sent, [b'GET /archive/fixed/payload.deb HTTP/1.1\r\nHost: snapshot.example.invalid\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n'])
        self.assertEqual(self.budget.used['content'], len(DATA))
        self.assertEqual(self.budget.used['wire'], len(DATA))
        self.assertEqual(self.budget.used['framing'], 0)

    def test_chunked_partial_reads_and_independent_counters(self):
        raw = chunked()
        for split in (1, 2, 7, 65536):
            with self.subTest(split=split):
                self.setUp()
                self.run_get(connections=[Conn(raw, split=split)])
                header, encoded = raw.split(b'\r\n\r\n', 1)
                self.assertEqual(self.budget.used['header'], len(header) + 4)
                self.assertEqual(self.budget.used['content'], len(DATA))
                self.assertEqual(self.budget.used['wire'], len(encoded))
                self.assertEqual(self.budget.used['framing'], len(encoded) - len(DATA))
                self.assertEqual(b''.join(self.sink.parts), DATA)

    def test_large_body_streams_in_bounded_blocks(self):
        data = b'x' * 200003
        self.run_get(raws=[length(data)], item=spec(size=len(data), sha256=hashlib.sha256(data).hexdigest()))
        self.assertEqual(sum(map(len, self.sink.parts)), len(data))
        self.assertLessEqual(max(map(len, self.sink.parts)), 65536)

    def test_fixed_redirect_counts_both_bodies(self):
        first = transcript(b'move', status=302, fields=((b'Location', FINAL.encode()), (b'Content-Length', b'4')))
        item = spec(location=FINAL, final=FINAL, limits=limits(requests=2))
        self.run_get(raws=[first, chunked()], item=item)
        self.assertEqual([x[0] for x in self.calls], [ORIGIN, FINAL])
        self.assertEqual(self.budget.used['content'], len(DATA) + 4)
        self.assertEqual(b''.join(self.sink.parts), DATA)
        self.assertEqual([c.closed for c in self.connections], [1, 1])
        self.assertEqual([h['status'] for h in self.budget.records[0]['hops']], [302, 200])

    def test_fixed_relative_location_uses_frozen_absolute_target(self):
        loc = '/file/abcdef/payload.deb'
        raw = transcript(b'', status=302, fields=((b'Location', loc.encode()), (b'Content-Length', b'0')))
        self.run_get(raws=[raw, length()], item=spec(location=loc, final=FINAL, limits=limits(requests=2)))
        self.assertEqual(self.calls[1][0], FINAL)

    def test_invalid_urls_before_any_connector(self):
        values = ['http://example.invalid/a', 'https://user@example.invalid/a',
                  'https://example.invalid:443/a', 'https://example.invalid/a?',
                  'https://example.invalid/a#', 'https://Example.invalid/a',
                  'https://example.invalid//a', 'https://example.invalid/a/../b',
                  'https://example.invalid/a/%2E/b', 'https://example.invalid/a%2Fb',
                  'https://example.invalid/a%5Cb', 'https://example.invalid/%00',
                  'https://example.invalid/%41', 'https://example.invalid/%ff',
                  'https://example.invalid/%G0', 'https://example.invalid/a\\b',
                  'https://example.invalid/a\r\nx', 'https://[bad/a',
                  'https://127.0.0.1/a', 'https://example.invalid/a/']
        for value in values:
            with self.subTest(url=value):
                self.setUp(); self.rejects('URL', item=spec(origin=value))
                self.assertEqual(self.calls, [])
                self.assertEqual(self.sink.closed, 1)

    def test_invalid_specs_and_limits(self):
        changes = [dict(size=True), dict(size=0), dict(sha256='A' * 64),
                   dict(kind='oci_layer'), dict(identity='../x'), dict(name='a/b'),
                   dict(framings=('length', 'length')), dict(framings=('eof',)),
                   dict(framings=[]), dict(size=2**60), dict(limits=None)]
        for change in changes:
            with self.subTest(change=change):
                self.setUp()
                with self.assertRaises(m.Stop):self.run_get(item=spec(**change))
                self.assertEqual(self.calls, [])
        for change in [dict(header=8193), dict(content=True), dict(wire=-1),
                       dict(framing=None), dict(total_seconds=float('nan')),
                       dict(total_seconds=2**10000), dict(hop_seconds=0), dict(chunks=0),
                       dict(chunk_line=129), dict(fields=129), dict(requests=False)]:
            with self.subTest(limit=list(change)):
                self.setUp(); self.rejects('LIMITS', item=spec(limits=limits(**change)))
        with self.assertRaises(TypeError):m.TransferSpec(**dict(spec().__dict__, unknown=True))

    def test_invalid_redirect_descriptors(self):
        for change in [dict(final=FINAL), dict(location=FINAL),
                       dict(location=FINAL, final=FINAL),
                       dict(location='/wrong', final=FINAL, limits=limits(requests=2)),
                       dict(location='https://evil.invalid/a', final='https://evil.invalid/a', limits=limits(requests=2)),
                       dict(limits=limits(requests=2))]:
            with self.subTest(change=change):
                self.setUp();self.rejects('HOP_POLICY', item=spec(**change));self.assertFalse(self.calls)

    def test_redirect_mismatch_and_no_second_retry(self):
        item = spec(location=FINAL, final=FINAL, limits=limits(requests=2))
        for loc in [b'https://evil.invalid/a', FINAL.encode() + b'?x=1', b' ' + FINAL.encode(), b'/wrong']:
            with self.subTest(loc=loc):
                self.setUp()
                raw = transcript(b'', status=302, fields=((b'Location', loc), (b'Content-Length', b'0')))
                with self.assertRaises(m.Stop):self.run_get(raws=[raw], item=item)
                self.assertEqual(len(self.calls), 1)
        raw = transcript(b'', status=302, fields=((b'Location', FINAL.encode()), (b'Content-Length', b'0')))
        self.setUp();self.rejects('STATUS', raws=[raw, raw], item=item)
        self.assertEqual(len(self.calls), 2)

    def test_unexpected_status_body_is_charged_then_stop(self):
        for status in (301, 302, 307, 401, 404, 500):
            with self.subTest(status=status):
                self.setUp();self.rejects('STATUS', raws=[length(b'error', status=status)])
                self.assertEqual(self.budget.used['content'], 5)
                self.assertEqual(self.sink.parts, [])

    def test_redirect_expected_but_origin_200_is_not_fallback(self):
        self.rejects('STATUS', item=spec(location=FINAL, final=FINAL, limits=limits(requests=2)))
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.sink.parts, [])

    def test_bad_header_syntax_duplicates_and_encoding(self):
        fields = [((b'Content-Length', b'19'), (b'Content-Length', b'19')),
                  ((b'Content-Length', b'19'), (b'Transfer-Encoding', b'chunked')),
                  ((b'X', b'1'), (b'x', b'2')),
                  ((b' Location', FINAL.encode()),), ((b'X', b'a\tb'),),
                  ((b'X', b'a\x7fb'),), ((b'Content-Encoding', b'gzip'),),
                  ((b'Location', FINAL.encode()), (b'Location', FINAL.encode()))]
        for value in fields:
            with self.subTest(fields=value):
                self.setUp()
                with self.assertRaises(m.Stop):self.run_get(raws=[transcript(fields=value)])
                self.assertEqual(self.budget.used['content'], 0)
        self.setUp();self.rejects('HEADERS', raws=[b'HTTP/2 200 ok\r\n\r\n'])

    def test_content_length_shape_wrong_size_and_no_eof_framing(self):
        for value in (b'-1', b'+19', b'019', b'1,1', b'9' * 17, b'0', b'1', b'99999999'):
            with self.subTest(value=value):
                self.setUp()
                with self.assertRaises(m.Stop):self.run_get(raws=[transcript(fields=((b'Content-Length', value),))])
                self.assertEqual(self.budget.used['content'], 0)
        self.setUp();self.rejects('FRAMING', raws=[transcript()])
        self.setUp();self.rejects('FRAMING', raws=[transcript(fields=((b'Transfer-Encoding', b'gzip, chunked'),))])

    def test_partial_header_and_short_bodies_keep_consumed_counts(self):
        raw = length()
        for cut in (5, len(raw) - len(DATA) + 2, len(raw) - 1):
            with self.subTest(cut=cut):
                self.setUp()
                with self.assertRaises(m.Stop):self.run_get(raws=[raw[:cut]])
                self.assertEqual(self.budget.used['header'] + self.budget.used['wire'], cut)
                self.assertEqual(self.connections[0].closed, 1)

    def test_header_cap_before_overread_and_boundary(self):
        base = length()
        pos = base.index(b'\r\n\r\n')
        for n in (8192, 8193):
            with self.subTest(header=n):
                self.setUp()
                raw = base[:pos] + b'\r\nX: ' + b'a' * (n - pos - 9) + base[pos:]
                self.assertEqual(len(raw) - len(DATA), n)
                if n == 8192:self.run_get(raws=[raw])
                else:self.rejects('HEADER_LIMIT', raws=[raw])
                self.assertEqual(self.budget.used['header'], min(n, 8192))
                self.assertLessEqual(self.connections[0].offset, n + len(DATA))
                if n == 8193:self.assertEqual(self.connections[0].offset, 8192)

    def test_global_header_budget_before_read(self):
        self.budget = m.Budget(limits(header=20, requests=20), 0)
        self.rejects('BUDGET_HEADER')
        self.assertEqual(self.connections[0].offset, 20)

    def test_content_wire_and_framing_caps_before_read(self):
        for key, raw in [('content', length()), ('wire', length()), ('framing', chunked())]:
            with self.subTest(key=key):
                self.setUp();self.budget=m.Budget(limits(**{key:0}),0)
                self.rejects('BUDGET_' + key.upper(), raws=[raw])
                self.assertEqual(self.budget.used[key], 0)
                self.assertEqual(self.budget.used['content'], 0)

    def test_exact_body_boundary_and_unread_suffix_not_claimed(self):
        self.run_get(raws=[length() + b'UNREAD'], item=spec(limits=limits(content=len(DATA),wire=len(DATA),framing=0)))
        self.assertEqual(self.connections[0].raw[self.connections[0].offset:], b'UNREAD')
        self.assertEqual(self.budget.used['content'],len(DATA))

    def test_bad_chunks_no_extensions_or_trailers(self):
        for raw in (b'1;x=y\r\nx\r\n0\r\n\r\n', b'Z\r\n', b'123456789\r\n',
                    b'1\r\nxXX', b'0\r\nX: y\r\n', b'1\r\nx\r\n', b'0\r\n\r\n',
                    b'ffffffff\r\n'):
            with self.subTest(raw=raw):
                self.setUp()
                with self.assertRaises(m.Stop):self.run_get(raws=[transcript(raw,fields=((b'Transfer-Encoding',b'chunked'),))])
                self.assertEqual(self.connections[0].closed,1)

    def test_chunk_limits_and_framing_policy(self):
        self.rejects('CHUNK_COUNT',raws=[chunked()],item=spec(limits=limits(chunks=1)))
        self.setUp();self.rejects('LINE_LIMIT',raws=[transcript(b'00000001\r\n',fields=((b'Transfer-Encoding',b'chunked'),))],item=spec(limits=limits(chunk_line=3)))
        self.setUp();self.rejects('FRAMING_POLICY',item=spec(framings=('chunked',)))
        self.setUp();self.rejects('FRAMING_POLICY',raws=[chunked()],item=spec(framings=('length',)))
        self.setUp();self.rejects('FRAMING',raws=[chunked().replace(b'HTTP/1.1',b'HTTP/1.0')])

    def test_hash_failure_and_sink_failures_retain_partial_content(self):
        self.rejects('HASH',item=spec(sha256='0'*64))
        self.assertEqual(b''.join(self.sink.parts),DATA)
        self.assertEqual(self.budget.used['content'],len(DATA))
        self.setUp();self.sink=Sink(short=True);self.rejects('SINK_WRITE')
        self.assertEqual(self.sink.closed,1)
        self.setUp();self.sink=Sink(write_error=True)
        with self.assertRaisesRegex(OSError,'synthetic sink write'):self.run_get()
        self.assertEqual(self.budget.records[-1]['state'],'STOP')
        self.assertEqual(self.sink.closed,1)

    def test_connection_faults_close_once_no_retry(self):
        for failure in ('send','recv','timeout'):
            with self.subTest(failure=failure):
                self.setUp();c=Conn(length(),fail=failure)
                with self.assertRaises(OSError):self.run_get(connections=[c])
                self.assertEqual(c.closed,1);self.assertEqual(self.sink.closed,1)
                self.assertEqual(len(self.calls),1)
        self.setUp()
        with self.assertRaisesRegex(OSError,'connect'):
            self.run_get(connect=Mock(side_effect=OSError('connect')))
        self.assertEqual(self.budget.used['requests'],1)
        self.assertEqual(self.sink.closed,1)

    def test_close_failures_prevent_success_and_preserve_primary(self):
        for which in ('connection','sink','both'):
            with self.subTest(which=which):
                self.setUp();c=Conn(length(),close_error=which!='sink')
                self.sink=Sink(close_error=which!='connection')
                self.rejects('CLOSE_UNCERTAIN',connections=[c])
                self.assertEqual(c.closed,1);self.assertEqual(self.sink.closed,1)
                self.assertTrue(self.budget.records[-1]['close_uncertain'])
        self.setUp();c=Conn(length(),fail='recv',close_error=True);self.sink=Sink(close_error=True)
        with self.assertRaisesRegex(OSError,'synthetic read') as cm:self.run_get(connections=[c])
        self.assertEqual(cm.exception.__notes__.count('CLOSE_UNCERTAIN'),2)
        self.assertFalse(self.budget.records[-1]['hops'][0]['closed'])

    def test_request_caps_duplicates_failed_consumption_and_budget_reuse(self):
        self.rejects('HASH',item=spec(sha256='0'*64))
        used=dict(self.budget.used);self.calls=[];self.sink=Sink()
        self.rejects('DUPLICATE_INPUT')
        self.assertEqual(self.budget.used,used);self.assertEqual(self.calls,[])
        self.calls=[];self.sink=Sink()
        self.run_get(item=spec(identity='other',name='other'))
        self.assertEqual(self.budget.used['content'],len(DATA)*2)
        self.setUp();self.budget=m.Budget(limits(requests=1),0)
        raw=transcript(b'',status=302,fields=((b'Location',FINAL.encode()),(b'Content-Length',b'0')))
        self.rejects('REQUEST_LIMIT',raws=[raw],item=spec(location=FINAL,final=FINAL,limits=limits(requests=2)))
        self.assertEqual(self.budget.used['requests'],1)

    def test_time_and_clock_failures_no_success(self):
        for value in (-1,float('nan'),float('inf'),True):
            with self.subTest(value=value):
                self.setUp();self.clock.value=value;self.rejects('CLOCK');self.assertEqual(self.calls,[])
        self.setUp();self.clock.value=30;self.rejects('DEADLINE');self.assertEqual(self.calls,[])
        self.setUp();c=Conn(length(),clock=self.clock);self.rejects('DEADLINE',connections=[c])
        self.assertEqual(c.closed,1)
        self.setUp();self.sink=Sink(clock=self.clock);self.rejects('DEADLINE')

    def test_read_timeout_after_received_bytes_is_charged(self):
        c=Conn(length())
        recv=c.recv
        def expire(n):
            out=recv(n);self.clock.value=31;return out
        c.recv=expire
        self.rejects('DEADLINE',connections=[c])
        self.assertEqual(self.budget.used['header'],1)

    def test_excess_error_body_is_not_read_and_fake_overread_is_recorded(self):
        self.rejects('BODY_SIZE',raws=[length(b'x'*10,status=404)],item=spec(limits=limits(error_body=9)))
        self.assertEqual(self.budget.used['content'],0)
        self.setUp();c=Conn(b'')
        c.recv=lambda n:b'xx'
        self.rejects('RECV_CONTRACT',connections=[c])
        self.assertEqual(self.budget.used['header'],2)

    def test_header_field_count_and_unexpected_location(self):
        self.rejects('HEADERS',raws=[transcript(fields=((b'X',b'1'),(b'Content-Length',b'19')))],item=spec(limits=limits(fields=1)))
        self.setUp();self.rejects('UNEXPECTED_LOCATION',raws=[transcript(fields=((b'Location',FINAL.encode()),(b'Content-Length',str(len(DATA)).encode())))])

    def test_explicit_connector_and_budget_single_owner(self):
        with self.assertRaises(TypeError):m.acquire(spec(),self.budget,self.sink,clock=self.clock)
        self.assertEqual(self.sink.closed,0)
        self.budget.busy=True
        with self.assertRaisesRegex(m.Stop,'BUDGET_BUSY_OR_TYPE'):self.run_get()

    def test_tls_adapter_with_only_mocked_socket_and_context(self):
        plain,wrapped=Mock(),Mock()
        wrapped.selected_alpn_protocol.return_value='http/1.1'
        context=Mock();context.wrap_socket.return_value=wrapped
        with fake_tcp(plain) as create, patch.object(ssl,'SSLContext',return_value=context), patch.object(ssl,'create_default_context',side_effect=AssertionError('ENV_KEYLOG_CONTEXT_FORBIDDEN')):
            self.assertIs(tls_for_test(ORIGIN,2),wrapped)
            create.assert_called_once_with(socket.AF_INET,socket.SOCK_STREAM,6)
            plain.settimeout.assert_called_once()
            self.assertGreater(plain.settimeout.call_args.args[0],0)
            self.assertLessEqual(plain.settimeout.call_args.args[0],2)
            plain.connect.assert_called_once_with(('192.0.2.1',443))
            context.wrap_socket.assert_called_once_with(plain,server_hostname='snapshot.example.invalid',do_handshake_on_connect=False)
            context.set_alpn_protocols.assert_called_once_with(['http/1.1'])
            self.assertEqual(context.minimum_version,ssl.TLSVersion.TLSv1_2)
            self.assertTrue(context.check_hostname)
            self.assertEqual(context.verify_mode,ssl.CERT_REQUIRED)
            context.load_default_certs.assert_called_once()
            plain.close.assert_not_called();wrapped.close.assert_not_called()
            wrapped.do_handshake.assert_called_once()

    def test_tls_adapter_error_ownership_and_primary(self):
        for phase in ('wrap','handshake','alpn'):
            with self.subTest(phase=phase):
                plain,wrapped=Mock(),Mock();context=Mock();context.wrap_socket.return_value=wrapped
                wrapped.selected_alpn_protocol.return_value='h2' if phase=='alpn' else 'http/1.1'
                if phase=='wrap':context.wrap_socket.side_effect=OSError('wrap failure')
                if phase=='handshake':wrapped.do_handshake.side_effect=OSError('handshake failure')
                owner=plain if phase=='wrap' else wrapped;owner.close.side_effect=OSError('close failure')
                with fake_tcp(plain),patch.object(ssl,'SSLContext',return_value=context):
                    with self.assertRaises((OSError,m.Stop)) as cm:tls_for_test(ORIGIN,1)
                owner.close.assert_called_once();self.assertIn('CLOSE_UNCERTAIN',cm.exception.__notes__)
                (wrapped if phase=='wrap' else plain).close.assert_not_called()

    def test_chunk_framing_exact_boundary(self):
        raw=chunked();encoded=raw.split(b'\r\n\r\n',1)[1]
        frame=len(encoded)-len(DATA)
        self.run_get(raws=[raw],item=spec(limits=limits(content=len(DATA),wire=len(encoded),framing=frame)))
        self.assertEqual(self.budget.used['framing'],frame)
        self.setUp()
        self.rejects('LIMIT_FRAMING',raws=[raw],item=spec(limits=limits(framing=frame-1)))
        self.assertLessEqual(self.budget.used['framing'],frame-1)

    def test_redirect_shared_budget_not_reset_at_second_hop(self):
        first=transcript(b'1234',status=302,fields=((b'Location',FINAL.encode()),(b'Content-Length',b'4')))
        self.budget=m.Budget(limits(content=len(DATA),requests=2),0)
        self.rejects('BUDGET_CONTENT',raws=[first,length()],item=spec(location=FINAL,final=FINAL,limits=limits(requests=2)))
        self.assertEqual(self.budget.used['content'],4)
        self.assertEqual(self.connections[1].offset,len(length())-len(DATA))

    def test_error_chunked_body_charged_without_writing_payload_sink(self):
        raw=chunked(b'err').replace(b'200 synthetic',b'404 synthetic')
        self.rejects('STATUS',raws=[raw])
        self.assertEqual(self.budget.used['content'],3)
        self.assertGreater(self.budget.used['framing'],0)
        self.assertEqual(self.sink.parts,[])

    def test_non_bytes_recv_and_boolean_sink_result_rejected(self):
        c=Conn(b'');c.recv=lambda n:bytearray(b'x')
        self.rejects('RECV_TYPE',connections=[c])
        self.setUp();self.sink.write=lambda raw:True
        self.rejects('SINK_WRITE')

    def test_name_identity_and_future_retry_are_closed(self):
        self.run_get();self.calls=[];self.sink=Sink()
        self.rejects('DUPLICATE_INPUT',item=spec(identity='different'))
        self.assertEqual(self.calls,[])
        self.setUp();self.run_get();self.calls=[];self.sink=Sink()
        self.rejects('DUPLICATE_INPUT',item=spec(name='different'))

    def test_primary_hash_error_survives_all_close_failures(self):
        c=Conn(length(),close_error=True);self.sink=Sink(close_error=True)
        error=self.rejects('HASH',item=spec(sha256='0'*64),connections=[c])
        self.assertEqual(error.__notes__.count('CLOSE_UNCERTAIN'),2)
        self.assertEqual(self.budget.used['content'],len(DATA))

    def test_deadline_while_sending_and_no_extra_read(self):
        c=Conn(length())
        def send(raw):self.clock.value=11
        c.sendall=send
        self.rejects('DEADLINE',connections=[c])
        self.assertEqual(c.reads,[])

    def test_global_hop_timeout_can_be_stricter_than_spec(self):
        self.budget=m.Budget(limits(hop_seconds=1),0);c=Conn(length(),clock=self.clock)
        self.rejects('DEADLINE',connections=[c])
        self.assertLessEqual(self.calls[0][1],1)

    def test_hop_hash_and_timing_records_match_independent_digest(self):
        self.run_get()
        h=self.budget.records[-1]['hops'][0]
        self.assertTrue(h['hash_match'])
        self.assertEqual(h['observed_sha256'],hashlib.sha256(DATA).hexdigest())
        self.assertEqual(h['finished'],0);self.assertEqual(h['seconds'],0)
        self.setUp();self.rejects('HASH',item=spec(sha256='0'*64))
        self.assertFalse(self.budget.records[-1]['hops'][0]['hash_match'])

    def test_failed_connect_and_close_still_have_timing_records(self):
        def connect(url,seconds):self.clock.value=1;raise OSError('connect')
        with self.assertRaises(OSError):self.run_get(connect=connect)
        self.assertEqual(self.budget.records[-1]['hops'][0]['seconds'],1)
        self.setUp();self.rejects('CLOSE_UNCERTAIN',connections=[Conn(length(),close_error=True)])
        self.assertEqual(self.budget.records[-1]['hops'][0]['finished'],0)

    def test_clock_finalization_cannot_mask_primary_failure(self):
        c=Conn(length(),fail='recv')
        def close():c.closed+=1;self.clock.value=float('nan')
        c.close=close
        with self.assertRaisesRegex(OSError,'synthetic read') as cm:self.run_get(connections=[c])
        self.assertIn('CLOCK_FINALIZATION_UNCERTAIN',cm.exception.__notes__)
        self.assertEqual(self.sink.closed,1)

    def test_callback_stop_text_is_not_copied_into_ledger(self):
        with self.assertRaises(m.Stop):
            self.run_get(connect=Mock(side_effect=m.Stop('private callback details')))
        self.assertEqual(self.budget.records[-1]['reason'],'IO_OR_CALLBACK_FAILURE')

    def test_metadata_records_have_a_hard_operation_count_cap(self):
        self.budget=m.Budget(limits(requests=1),0)
        self.rejects('SPEC',item=spec(kind='unsupported'))
        previous=self.sink;self.sink=Sink()
        with self.assertRaisesRegex(m.Stop,'^OPERATION_LIMIT$'):self.run_get()
        self.assertEqual(len(self.budget.records),1)
        self.assertEqual(previous.closed,1);self.assertEqual(self.sink.closed,0)

    def test_probe_frozen_plans_and_global_bounds(self):
        ap2,deb=probe.plans()
        for item in (ap2,deb):item.checked()
        self.assertEqual(ap2.size,1776074)
        self.assertEqual(ap2.sha256,'526288baea429019db3f4a7ccb8aad15d629b8c760db3f30ec511d32a53b0d47')
        self.assertEqual(deb.size,8808)
        self.assertEqual(deb.sha256,'cfac89e6a7a54ff3c6a4f843310e25efeddaa771baeae470bd98bd588c373563')
        self.assertEqual(deb.final,'https://snapshot.debian.org'+deb.location)
        self.assertEqual(sum(x.limits.requests for x in (ap2,deb)),3)
        self.assertLess(sum(x.limits.wire for x in (ap2,deb)),96*1024*1024)

    def test_probe_fake_success_discards_body_and_has_no_durable_claim(self):
        connections=[Conn(length()),Conn(length())]
        def connect(url,seconds,owner):owner.register(connections.pop(0))
        now=lambda:dt.datetime(2026,10,17,tzinfo=dt.timezone.utc)
        with patch.object(probe,'plans',return_value=(spec(),spec(identity='second',name='second'))),patch.dict('os.environ',{},clear=True):
            result=probe.run_once(connect=connect,clock=self.clock,utc_now=now)
        self.assertEqual(result['status'],'PINNED_TRANSPORT_PROBE_CONTENT_MATCH_RUNTIME_UNPROVEN')
        self.assertEqual(result['used']['requests'],2)
        self.assertFalse(result['raw_payload_saved'])
        self.assertFalse(result['diagnostic_artifact_saved'])
        self.assertTrue(all(not x['durable_or_sealed'] for x in result['receipts']))

    def test_probe_first_failure_stops_without_following_target(self):
        connect=Mock(side_effect=OSError('synthetic failed connect'))
        with patch.dict('os.environ',{},clear=True):
            result=probe.run_once(connect=connect,clock=self.clock,utc_now=lambda:dt.datetime(2026,10,17,tzinfo=dt.timezone.utc))
        self.assertEqual(result['status'],'STOP_NO_RETRY')
        self.assertEqual(result['used']['requests'],1)
        connect.assert_called_once()

    def test_probe_expired_or_overridden_tls_stops_before_connector(self):
        connect=Mock(side_effect=AssertionError('must not connect'))
        for now in (dt.datetime(2026,10,20,7,32,55,tzinfo=dt.timezone.utc),dt.datetime(2026,10,17)):
            with self.subTest(now=str(now)),patch.dict('os.environ',{},clear=True):
                result=probe.run_once(connect=connect,clock=self.clock,utc_now=lambda:now)
                self.assertEqual(result['reason'],'EXPIRED_OR_UNKNOWN_CLOCK')
                self.assertEqual(result['status'],'STOP_NO_RETRY')
        for name in ('SSL_CERT_FILE','SSL_CERT_DIR','SSLKEYLOGFILE'):
            with self.subTest(name=name),patch.dict('os.environ',{name:'synthetic'},clear=True):
                result=probe.run_once(connect=connect,clock=self.clock,utc_now=lambda:dt.datetime(2026,10,17,tzinfo=dt.timezone.utc))
                self.assertEqual(result['reason'],'TLS_ENV_OVERRIDE')
        connect.assert_not_called()

    def test_caller_active_except_does_not_suppress_close_failure(self):
        for which in ('connection','sink','both'):
            with self.subTest(which=which):
                self.setUp()
                try:
                    raise RuntimeError('unrelated caller exception')
                except RuntimeError as ambient:
                    c=Conn(length(),close_error=which!='sink')
                    self.sink=Sink(close_error=which!='connection')
                    self.rejects('CLOSE_UNCERTAIN',connections=[c])
                    self.assertFalse(hasattr(ambient,'__notes__'))
                    self.assertEqual(c.closed,1);self.assertEqual(self.sink.closed,1)

    def test_caller_active_except_does_not_skip_hop_deadline(self):
        try:
            raise RuntimeError('unrelated caller exception')
        except RuntimeError as ambient:
            self.rejects('DEADLINE',connections=[Conn(length(),clock=self.clock)])
            self.assertFalse(hasattr(ambient,'__notes__'))

    def test_caller_active_except_clock_failure_is_not_suppressed(self):
        c=Conn(length())
        def close():c.closed+=1;self.clock.value=float('nan')
        c.close=close
        try:
            raise RuntimeError('unrelated caller exception')
        except RuntimeError as ambient:
            self.rejects('CLOCK',connections=[c])
            self.assertFalse(hasattr(ambient,'__notes__'))

    def test_caller_active_except_local_primary_keeps_only_local_notes(self):
        try:
            raise RuntimeError('unrelated caller exception')
        except RuntimeError as ambient:
            self.sink=Sink(close_error=True)
            c=Conn(length(),fail='recv',close_error=True)
            with self.assertRaisesRegex(OSError,'synthetic read') as cm:
                self.run_get(connections=[c])
            self.assertEqual(cm.exception.__notes__.count('CLOSE_UNCERTAIN'),2)
            self.assertFalse(hasattr(ambient,'__notes__'))

    def test_tls_local_primary_is_explicit_inside_caller_except(self):
        plain,wrapped=Mock(),Mock();context=Mock();context.wrap_socket.return_value=wrapped
        wrapped.do_handshake.side_effect=OSError('local handshake')
        wrapped.close.side_effect=OSError('local close')
        try:
            raise RuntimeError('unrelated caller exception')
        except RuntimeError as ambient:
            with fake_tcp(plain),patch.object(ssl,'SSLContext',return_value=context):
                with self.assertRaisesRegex(OSError,'local handshake') as cm:tls_for_test(ORIGIN,1)
            self.assertEqual(cm.exception.__notes__.count('CLOSE_UNCERTAIN'),1)
            self.assertFalse(hasattr(ambient,'__notes__'))

    def test_safe_exception_categories_and_no_secret_text(self):
        secret='secret https://user:password@private.invalid/?token=secret'
        errors=[(socket.gaierror(-2,secret),'DNS_LOOKUP_ERROR','EAI'),
                (PermissionError(1,secret),'OS_PERMISSION_ERROR','OS'),
                (ConnectionRefusedError(61,secret),'OS_CONNECTION_OR_IO_ERROR','OS'),
                (TimeoutError(secret),'TIMEOUT','OS'),
                (ssl.SSLError(1,secret),'TLS_ERROR','NONE'),
                (m.Stop('TLS_PROTOCOL'),'INTERNAL_POLICY_STOP','NONE'),
                (ValueError(secret),'OTHER','NONE')]
        certificate=ssl.SSLCertVerificationError(1,secret);certificate.verify_code=20
        errors.append((certificate,'TLS_CERT_VERIFY_ERROR','NONE'))
        for error,category,domain in errors:
            with self.subTest(category=category):
                d=m.diagnostic(error,'DNS_OR_TCP_CONNECT')
                self.assertEqual(d['category'],category);self.assertEqual(d['errno_domain'],domain)
                self.assertNotIn('secret',json.dumps(d))
        self.assertEqual(m.diagnostic(certificate)['verify_code'],20)
        self.assertEqual(m.safe_reason(m.Stop('TLS_PROTOCOL')),'TLS_PROTOCOL')

    def test_tls_failure_phase_is_recorded_and_original_error_rethrown(self):
        phases=['TLS_CONTEXT','DNS_OR_TCP_CONNECT','TLS_WRAP','TLS_TIMEOUT_SETUP','TLS_HANDSHAKE','TLS_ALPN']
        for phase in phases:
            with self.subTest(phase=phase):
                error=OSError(1,'secret url credentials')
                plain,wrapped,context=Mock(),Mock(),Mock()
                context.wrap_socket.return_value=wrapped
                wrapped.selected_alpn_protocol.return_value='http/1.1'
                create=Mock(return_value=plain);constructor=Mock(return_value=context)
                {'TLS_CONTEXT':context.load_default_certs,
                 'DNS_OR_TCP_CONNECT':create,'TLS_WRAP':context.wrap_socket,
                 'TLS_TIMEOUT_SETUP':wrapped.settimeout,'TLS_HANDSHAKE':wrapped.do_handshake,
                 'TLS_ALPN':wrapped.selected_alpn_protocol}[phase].side_effect=error
                with fake_tcp(constructor=create),patch.object(ssl,'SSLContext',constructor):
                    with self.assertRaises(OSError) as cm:tls_for_test(ORIGIN,1)
                self.assertIs(cm.exception,error)
                self.assertEqual(m.diagnostic(error)['phase'],phase)
                self.assertNotIn('secret',json.dumps(m.diagnostic(error)))
                if phase in ('TLS_CONTEXT','DNS_OR_TCP_CONNECT'):
                    plain.close.assert_not_called();wrapped.close.assert_not_called()
                elif phase=='TLS_WRAP':plain.close.assert_called_once();wrapped.close.assert_not_called()
                else:wrapped.close.assert_called_once();plain.close.assert_not_called()

    def test_tls_alpn_policy_stop_survives_safe_reason_filter(self):
        wrapped=Mock();wrapped.selected_alpn_protocol.return_value='h2'
        context=Mock();context.wrap_socket.return_value=wrapped
        with fake_tcp(),patch.object(ssl,'SSLContext',return_value=context):
            with self.assertRaises(m.Stop) as cm:tls_for_test(ORIGIN,1)
        self.assertEqual(m.safe_reason(cm.exception),'TLS_PROTOCOL')
        self.assertEqual(m.diagnostic(cm.exception)['phase'],'TLS_ALPN')

    def test_connector_and_http_send_are_distinct_diagnostic_facts(self):
        error=socket.gaierror(-2,'secret')
        m.annotate(error,'U3_PHASE:DNS_OR_TCP_CONNECT')
        with self.assertRaises(socket.gaierror):self.run_get(connect=Mock(side_effect=error))
        record=self.budget.records[-1];h=record['hops'][0]
        self.assertFalse(h['connector_returned']);self.assertFalse(h['http_send_started'])
        self.assertFalse(h['http_send_complete']);self.assertEqual(record['failure']['category'],'DNS_LOOKUP_ERROR')
        self.assertEqual(record['failure']['phase'],'DNS_OR_TCP_CONNECT')
        self.setUp()
        with self.assertRaises(OSError):self.run_get(connections=[Conn(length(),fail='send')])
        record=self.budget.records[-1];h=record['hops'][0]
        self.assertTrue(h['connector_returned']);self.assertTrue(h['http_send_started'])
        self.assertFalse(h['http_send_complete']);self.assertEqual(record['failure']['phase'],'HTTP_SEND')

    def test_diagnostic_faults_and_malformed_notes_do_not_mask_primary(self):
        error=OSError('secret')
        error.__notes__='malformed'
        c=Conn(length());c.recv=Mock(side_effect=error);self.sink=Sink(close_error=True)
        with self.assertRaises(OSError) as cm:self.run_get(connections=[c])
        self.assertIs(cm.exception,error)
        self.assertTrue(self.budget.records[-1]['failure']['metadata_uncertain'])
        self.assertTrue(self.budget.records[-1]['close_uncertain'])
        self.assertNotIn('secret',json.dumps(self.budget.records))
        class UnsafeText:
            def __str__(self):raise AssertionError('must not format')
        self.assertEqual(m.safe_reason(m.Stop(UnsafeText())),'IO_OR_CALLBACK_FAILURE')

    def test_probe_records_its_own_runtime_before_connect(self):
        connect=Mock(side_effect=socket.gaierror(-2,'secret credentials URL'))
        with patch.dict('os.environ',{},clear=True):
            result=probe.run_once(connect=connect,clock=self.clock,utc_now=lambda:dt.datetime(2026,10,17,tzinfo=dt.timezone.utc))
        identity=result['runtime']
        self.assertEqual(identity['python_version'],list(sys.version_info[:3]))
        self.assertEqual(identity['openssl_version'],list(ssl.OPENSSL_VERSION_INFO))
        self.assertEqual(set(identity['source_sha256']),{'transport','probe'})
        self.assertTrue(all(len(x)==64 for x in identity['source_sha256'].values()))
        self.assertEqual(result['failure']['category'],'DNS_LOOKUP_ERROR')
        self.assertEqual(result['dns_and_tcp_attempts'],'UNKNOWN_MULTIPLE_RESOLVED_ADDRESSES_POSSIBLE')
        self.assertNotIn('secret',json.dumps(result))
        self.assertNotIn(sys.executable,json.dumps(result))
        self.assertLess(len(json.dumps(result).encode()),1048576)

    def test_probe_incomplete_identity_blocks_before_network(self):
        connect=Mock(side_effect=AssertionError('must not connect'))
        with patch.object(probe,'runtime_identity',return_value={'status':'INCOMPLETE'}):
            result=probe.run_once(connect=connect,clock=self.clock,utc_now=lambda:dt.datetime(2026,10,17,tzinfo=dt.timezone.utc))
        connect.assert_not_called();self.assertEqual(result['reason'],'RUNTIME_IDENTITY_UNAVAILABLE')

    def test_probe_clock_finalization_preserves_original_safe_failure(self):
        times=iter([dt.datetime(2026,10,17,tzinfo=dt.timezone.utc),
                    dt.datetime(2026,10,17,tzinfo=dt.timezone.utc),None])
        with patch.dict('os.environ',{},clear=True):
            result=probe.run_once(connect=Mock(side_effect=PermissionError(1,'secret')),clock=self.clock,utc_now=lambda:next(times))
        self.assertEqual(result['failure']['category'],'OS_PERMISSION_ERROR')
        self.assertEqual(result['clock_finalization'],'UNAVAILABLE')

    def test_post_hop_deadline_has_finalization_phase_after_real_fake_transfer(self):
        original=m.hop
        def completed(*args,**kwargs):
            result=original(*args,**kwargs)
            self.clock.value=31
            return result
        with patch.object(m,'hop',side_effect=completed):self.rejects('DEADLINE')
        record=self.budget.records[-1]
        self.assertEqual(record['failure']['phase'],'TIME_FINALIZATION')
        self.assertEqual(record['content'],len(DATA))
        self.assertTrue(record['hops'][0]['closed']);self.assertTrue(record['sink_closed'])

    def test_post_sink_deadline_and_clock_failures_keep_phase_and_counts(self):
        for kind in ('deadline','invalid_clock'):
            with self.subTest(kind=kind):
                self.setUp()
                def close():
                    self.sink.closed+=1
                    self.clock.value=31 if kind=='deadline' else float('nan')
                self.sink.close=close
                self.rejects('DEADLINE' if kind=='deadline' else 'CLOCK')
                record=self.budget.records[-1]
                self.assertEqual(record['failure']['phase'],'TIME_FINALIZATION')
                self.assertTrue(record['hops'][0]['http_send_complete'])
                self.assertEqual(record['content'],len(DATA))

    def test_post_hop_clock_callback_exception_reaches_probe_with_phase(self):
        class BrokenClock(Clock):
            broken=False
            def __call__(self):
                if self.broken:raise OSError('secret clock failure')
                return self.value
        clock=BrokenClock();original=m.hop
        def completed(*args,**kwargs):
            result=original(*args,**kwargs);clock.broken=True;return result
        with patch.object(m,'hop',side_effect=completed),patch.object(probe,'plans',return_value=(spec(),)),patch.dict('os.environ',{},clear=True):
            result=probe.run_once(connect=lambda url,seconds,owner:owner.register(Conn(length())),clock=clock,utc_now=lambda:dt.datetime(2026,10,17,tzinfo=dt.timezone.utc))
        self.assertEqual(result['failure']['phase'],'TIME_FINALIZATION')
        self.assertEqual(result['records'][0]['failure']['phase'],'TIME_FINALIZATION')
        self.assertEqual(result['used']['content'],len(DATA))
        self.assertNotIn('secret',json.dumps(result))

    def test_standard_ssl_family_is_classified_without_text(self):
        for cls in (ssl.SSLError,ssl.SSLEOFError,ssl.SSLZeroReturnError,
                    ssl.SSLSyscallError,ssl.SSLWantReadError,ssl.SSLWantWriteError):
            with self.subTest(cls=cls.__name__):
                error=cls(1,'secret certificate URL')
                m.annotate(error,'U3_PHASE:TLS_HANDSHAKE')
                result=m.diagnostic(error)
                self.assertEqual(result['category'],'TLS_ERROR')
                self.assertEqual(result['phase'],'TLS_HANDSHAKE')
                self.assertNotIn('secret',json.dumps(result))
        error=ssl.CertificateError(1,'secret')
        m.annotate(error,'U3_PHASE:TLS_HANDSHAKE')
        result=m.diagnostic(error)
        self.assertEqual(result['category'],'TLS_CERT_VERIFY_ERROR')
        self.assertEqual(result['phase'],'TLS_HANDSHAKE')
        self.assertFalse(result['metadata_uncertain'])
        class PrivateSubclass(ssl.SSLError):pass
        self.assertEqual(m.diagnostic(PrivateSubclass('secret'))['category'],'OTHER')

    def test_standard_os_subclasses_use_safe_numeric_domain(self):
        for cls in (BlockingIOError,InterruptedError,FileNotFoundError,FileExistsError,
                    IsADirectoryError,NotADirectoryError,ProcessLookupError,ChildProcessError):
            with self.subTest(cls=cls.__name__):
                d=m.diagnostic(cls(2,'secret filename'))
                self.assertEqual(d['category'],'OS_CONNECTION_OR_IO_ERROR')
                self.assertEqual(d['errno_domain'],'OS');self.assertEqual(d['errno'],2)
                self.assertNotIn('secret',json.dumps(d))

    def test_connection_close_time_and_clock_errors_have_finalization_owner(self):
        for kind in ('deadline','invalid_clock','callback'):
            with self.subTest(kind=kind):
                self.setUp()
                class FinalClock(Clock):
                    broken=False
                    def __call__(self):
                        if self.broken:raise OSError('secret clock error')
                        return self.value
                clock=FinalClock();self.clock=clock;c=Conn(length())
                def close():
                    c.closed+=1
                    if kind=='callback':clock.broken=True
                    else:clock.value=11 if kind=='deadline' else float('nan')
                c.close=close
                with self.assertRaises((m.Stop,OSError)) as cm:self.run_get(connections=[c])
                record=self.budget.records[-1]
                self.assertEqual(record['failure']['phase'],'TIME_FINALIZATION')
                self.assertTrue(record['hops'][0]['closed'])
                self.assertTrue(record['sink_closed']);self.assertEqual(c.closed,1)
                self.assertEqual(record['content'],len(DATA))
                self.assertNotIn('secret',json.dumps(record))

    def test_finalization_boundary_preserves_more_specific_local_primary(self):
        self.sink=Sink(close_error=True)
        c=Conn(length(),fail='recv',close_error=True)
        with self.assertRaises(OSError) as cm:self.run_get(connections=[c])
        self.assertEqual(m.diagnostic(cm.exception)['phase'],'HTTP_HEADERS')
        self.assertEqual(cm.exception.__notes__.count('CLOSE_UNCERTAIN'),2)

    def cli(self,argv,**patches):
        out,err=io.StringIO(),io.StringIO()
        defaults=dict(signal=Mock(),alarm=Mock(return_value=0),
                      run=Mock(return_value={'status':'PINNED_TRANSPORT_PROBE_CONTENT_MATCH_RUNTIME_UNPROVEN',
                                             'used':{'content':17},'receipts':[],'records':[]}))
        defaults.update(patches)
        with patch.object(sys,'argv',['probe']+argv),patch.object(sys,'stdout',out),patch.object(sys,'stderr',err),patch.object(probe.signal,'signal',defaults['signal']),patch.object(probe.signal,'alarm',defaults['alarm']),patch.object(probe,'run_once',defaults['run']):
            code=probe.main()
        self.assertEqual(err.getvalue(),'')
        self.assertLessEqual(len(out.getvalue().encode()),1048576)
        return code,json.loads(out.getvalue()),defaults

    def test_cli_bad_or_missing_flag_is_safe_json_without_network_or_timer(self):
        for argv in ([],['--wrong'],['https://private.invalid/?secret=password'],
                     ['--run-approved-public-transport-once','extra']):
            with self.subTest(argv=argv):
                code,d,p=self.cli(argv)
                self.assertEqual(code,78);self.assertEqual(d['reason'],'EXPLICIT_APPROVAL_FLAG')
                self.assertEqual(d['failure']['phase'],'PROBE_PRECONDITION')
                self.assertNotIn('secret',json.dumps(d));self.assertNotIn(sys.executable,json.dumps(d))
                p['run'].assert_not_called();p['signal'].assert_not_called();p['alarm'].assert_not_called()

    def test_cli_setup_failures_are_redacted_and_clear_uncertain_timer(self):
        for target in ('signal','alarm'):
            with self.subTest(target=target):
                bad=Mock(side_effect=OSError('secret path'))
                if target=='alarm':
                    bad=Mock(side_effect=[OSError('secret path'),0])
                code,d,p=self.cli(['--run-approved-public-transport-once'],**{target:bad})
                self.assertEqual(code,78);self.assertNotIn('secret',json.dumps(d))
                p['run'].assert_not_called()
                if target=='alarm':self.assertEqual(bad.call_args_list[-1].args,(0,))

    def test_cli_alarm_cleanup_keeps_first_failure_or_changes_success_to_stop(self):
        for prior in (False,True):
            with self.subTest(prior=prior):
                data={'status':'PINNED_TRANSPORT_PROBE_CONTENT_MATCH_RUNTIME_UNPROVEN',
                      'used':{'content':17},'receipts':[],'records':[]}
                if prior:data.update(status='STOP_NO_RETRY',reason='HASH',failure={'phase':'CONTENT_HASH'})
                code,d,_=self.cli(['--run-approved-public-transport-once'],run=Mock(return_value=data),alarm=Mock(side_effect=[0,OSError('secret cleanup')]))
                self.assertEqual(code,78);self.assertEqual(d['used'],{'content':17})
                self.assertEqual(d['alarm_finalization'],'UNAVAILABLE')
                self.assertEqual(d['failure']['phase'],'CONTENT_HASH' if prior else 'TIME_FINALIZATION')

    def test_cli_runtime_failure_and_encoding_limits_remain_bounded(self):
        with patch.object(probe,'runtime_identity',side_effect=OSError('secret path')):
            code,d,_=self.cli([])
        self.assertEqual(code,78);self.assertEqual(d['runtime'],{'status':'UNAVAILABLE'})
        for fault in ('encoding','oversize'):
            with self.subTest(fault=fault):
                with patch.object(probe.json,'dumps',side_effect=ValueError('secret') if fault=='encoding' else None,
                                  return_value='x'*1048577):
                    code,d,_=self.cli([])
                self.assertEqual(code,78);self.assertEqual(d['status'],'SAFE_OUTPUT_STOP_NO_RETRY')

    def test_cli_unwritable_stdout_does_not_emit_secondary_traceback(self):
        out,err=Mock(),io.StringIO();out.write.side_effect=OSError('secret stdout path')
        with patch.object(sys,'argv',['probe']),patch.object(sys,'stdout',out),patch.object(sys,'stderr',err):
            self.assertEqual(probe.main(),78)
        self.assertEqual(err.getvalue(),'')

    def test_cli_late_alarm_latches_without_interrupting_fallback_or_traceback(self):
        handlers=[]
        def signal_setup(sig,handler):handlers.append(handler)
        original=probe.failure_result
        def interrupted_fallback(error):
            handlers[0](probe.signal.SIGALRM,None)
            return original(error)
        with patch.object(probe,'failure_result',side_effect=interrupted_fallback):
            code,d,p=self.cli(['--run-approved-public-transport-once'],
                             signal=Mock(side_effect=signal_setup),
                             run=Mock(side_effect=OSError('secret original')))
        self.assertEqual(code,78);self.assertEqual(d['reason'],'IO_OR_CALLBACK_FAILURE')
        self.assertEqual(d['failure']['phase'],'PROBE_PRECONDITION')
        self.assertTrue(d['local_wall_alarm_expired'])
        self.assertNotIn('secret',json.dumps(d))
        self.assertEqual(p['alarm'].call_args_list[-1].args,(0,))

    def test_cli_fallback_failure_and_timer_cleanup_failure_still_emit_safe_result(self):
        with patch.object(probe,'failure_result',side_effect=RuntimeError('secret fallback')):
            code,d,_=self.cli(['--run-approved-public-transport-once'],
                             run=Mock(side_effect=OSError('secret original')),
                             alarm=Mock(side_effect=[0,OSError('secret cleanup')]))
        self.assertEqual(code,78);self.assertEqual(d['reason'],'FALLBACK_UNAVAILABLE')
        self.assertEqual(d['alarm_finalization'],'UNAVAILABLE')
        self.assertNotIn('secret',json.dumps(d))

    def test_stdlib_address_loop_reproduces_old_oserror_alarm_swallow(self):
        # Exercise the installed CPython loop itself, not a copied model.
        first, second = Mock(), Mock()
        first.connect.side_effect = TimeoutError('synthetic old wall alarm')
        addresses = [(socket.AF_INET, socket.SOCK_STREAM, 6, '', ('192.0.2.1', 443)),
                     (socket.AF_INET, socket.SOCK_STREAM, 6, '', ('192.0.2.2', 443))]
        with patch.object(socket, 'getaddrinfo', return_value=addresses), \
             patch.object(socket, 'socket', side_effect=[first, second]) as factory:
            self.assertIs(STDLIB_CREATE_CONNECTION(('fake.invalid', 443), timeout=1), second)
        self.assertEqual(factory.call_count, 2)
        first.close.assert_called_once(); second.connect.assert_called_once()

    def test_wall_cancellation_escapes_stdlib_address_loop_and_stops_probe(self):
        for where in ('resolve', 'connect', 'handshake'):
            with self.subTest(where=where):
                handlers = []
                first, second, wrapped, context = Mock(), Mock(), Mock(), Mock()
                context.wrap_socket.return_value = wrapped
                addresses = [(socket.AF_INET, socket.SOCK_STREAM, 6, '', ('192.0.2.1', 443)),
                             (socket.AF_INET, socket.SOCK_STREAM, 6, '', ('192.0.2.2', 443))]
                def expired(*args, **kwargs): handlers[0](probe.signal.SIGALRM, None)
                def install(sig, handler): handlers.append(handler)
                if where == 'connect': first.connect.side_effect = expired
                if where == 'handshake': wrapped.do_handshake.side_effect = expired
                original = probe.run_once
                with patch.object(socket, 'getaddrinfo', side_effect=expired if where == 'resolve' else None,
                                  return_value=addresses) as resolve, \
                     patch.object(socket, 'socket', side_effect=[first, second]) as factory, \
                     patch.object(ssl, 'SSLContext', return_value=context), \
                     patch.dict('os.environ', {}, clear=True):
                    def run(**kwargs):
                        return original(connect=m.tls_connect, clock=self.clock,
                                        utc_now=lambda:dt.datetime(2026,10,17,tzinfo=dt.timezone.utc))
                    code, d, p = self.cli(['--run-approved-public-transport-once'],
                                         signal=Mock(side_effect=install), run=Mock(side_effect=run))
                self.assertEqual(code, 78); self.assertTrue(d['local_wall_alarm_expired'])
                self.assertEqual(d['reason'], 'PROBE_DEADLINE')
                self.assertEqual(d['failure']['category'], 'TIMEOUT')
                self.assertEqual(d['failure']['phase'], 'TLS_HANDSHAKE' if where == 'handshake' else 'DNS_OR_TCP_CONNECT')
                self.assertEqual(len(d['records']), 1); self.assertEqual(d['receipts'], [])
                self.assertEqual(d['used']['requests'], 1)
                self.assertFalse(d['records'][0]['hops'][0]['connector_returned'])
                self.assertFalse(d['records'][0]['hops'][0]['http_send_started'])
                self.assertEqual(factory.call_count, 0 if where == 'resolve' else 1)
                second.connect.assert_not_called(); resolve.assert_called_once()
                if where == 'handshake': wrapped.close.assert_called_once()
                if where == 'connect': first.close.assert_called_once()
                self.assertEqual(p['alarm'].call_args_list[-1].args, (0,))
                self.assertNotIn('192.0.2', json.dumps(d))

    def test_expired_alarm_cannot_be_reported_as_success_even_if_absorbed(self):
        handlers = []
        def run(**kwargs):
            try: handlers[0](probe.signal.SIGALRM, None)
            except BaseException: pass
            return dict(status='PINNED_TRANSPORT_PROBE_CONTENT_MATCH_RUNTIME_UNPROVEN',
                        used={'content':17}, receipts=[], records=[])
        code, d, _ = self.cli(['--run-approved-public-transport-once'],
                              signal=Mock(side_effect=lambda sig,h:handlers.append(h)),
                              run=Mock(side_effect=run))
        self.assertEqual(code, 78); self.assertEqual(d['status'], 'STOP_NO_RETRY')
        self.assertEqual(d['reason'], 'PROBE_DEADLINE'); self.assertEqual(d['used']['content'],17)
        self.assertFalse(issubclass(m.WallDeadline, (OSError, Exception)))

    def test_wall_cancellation_preempts_cleanup_primary_and_clock_suppression(self):
        for primary in (None, OSError('secret primary'), m.WallDeadline()):
            with self.subTest(primary=type(primary).__name__):
                deadline = m.WallDeadline(); resource = Mock()
                resource.close.side_effect = deadline
                with self.assertRaises(m.WallDeadline) as cm: m.close_once(resource, primary)
                self.assertIs(cm.exception, deadline); resource.close.assert_called_once()
                clock = Mock(side_effect=deadline)
                with self.assertRaises(m.WallDeadline) as cm:
                    m.finish_time({'started':0}, self.budget, clock, primary)
                self.assertIs(cm.exception, deadline)

    def test_wall_cancellation_during_failed_http_cleanup_keeps_stop_and_ledger(self):
        for target in ('connection', 'sink', 'finish_clock'):
            with self.subTest(target=target):
                self.setUp(); deadline = m.WallDeadline(); c = Conn(length(), fail='recv')
                if target == 'connection': c.close = Mock(side_effect=deadline)
                if target == 'sink': self.sink.close = Mock(side_effect=deadline)
                original = m.finish_time
                def finish(*args, **kwargs):
                    if target == 'finish_clock':
                        return original(args[0], args[1], Mock(side_effect=deadline), args[4] if len(args)>4 else None)
                    return original(*args, **kwargs)
                with patch.object(m, 'finish_time', side_effect=finish):
                    with self.assertRaises(m.WallDeadline) as cm:self.run_get(connections=[c])
                self.assertIs(cm.exception, deadline)
                record = self.budget.records[-1]
                self.assertEqual(record['state'], 'STOP')
                self.assertEqual(record['reason'], 'PROBE_DEADLINE')
                self.assertEqual(record['failure']['category'], 'TIMEOUT')
                self.assertEqual(record['requests'], 1); self.assertFalse(self.budget.busy)
                self.assertNotIn('secret', json.dumps(record))

    def test_wall_cancellation_is_not_swallowed_by_diagnostic_metadata_guard(self):
        class InterruptedErrorMetadata(OSError):
            @property
            def __notes__(self): raise m.WallDeadline()
        with self.assertRaises(m.WallDeadline):m.diagnostic(InterruptedErrorMetadata())

    def test_owned_connect_cancellation_closes_before_retained_exception_escapes(self):
        for where in ('timeout_setup', 'connect'):
            for close_fails in (False, True):
                with self.subTest(where=where, close_fails=close_fails):
                    first, second, context = Mock(), Mock(), Mock()
                    cancellation = m.WallDeadline(); held = []
                    getattr(first, 'settimeout' if where == 'timeout_setup' else 'connect').side_effect = cancellation
                    if close_fails:first.close.side_effect=OSError('secret close')
                    addresses=[(socket.AF_INET,socket.SOCK_STREAM,6,'',('192.0.2.1',443)),
                               (socket.AF_INET,socket.SOCK_STREAM,6,'',('192.0.2.2',443))]
                    with patch.object(socket,'getaddrinfo',return_value=addresses), \
                         patch.object(socket,'socket',side_effect=[first,second]) as factory, \
                         patch.object(ssl,'SSLContext',return_value=context):
                        try:tls_for_test(ORIGIN,1)
                        except m.WallDeadline as error:held.append(error)
                    self.assertEqual(held,[cancellation]);self.assertIsNotNone(held[0].__traceback__)
                    first.close.assert_called_once();second.connect.assert_not_called()
                    self.assertEqual(factory.call_count,1);context.wrap_socket.assert_not_called()
                    self.assertEqual(m.diagnostic(held[0])['cleanup_uncertain'],close_fails)

    def test_owned_connect_ordinary_fallback_only_after_known_close(self):
        for close_fails in (False,True):
            with self.subTest(close_fails=close_fails):
                first,second,wrapped,context=Mock(),Mock(),Mock(),Mock()
                events=[];first.connect.side_effect=ConnectionRefusedError(61,'secret')
                def close():
                    events.append('first_closed')
                    if close_fails:raise OSError('secret cleanup')
                first.close.side_effect=close
                second.connect.side_effect=lambda address:events.append('second_connect')
                wrapped.selected_alpn_protocol.return_value='http/1.1';context.wrap_socket.return_value=wrapped
                addresses=[(socket.AF_INET,socket.SOCK_STREAM,6,'',('192.0.2.1',443)),
                           (socket.AF_INET,socket.SOCK_STREAM,6,'',('192.0.2.2',443))]
                with patch.object(socket,'getaddrinfo',return_value=addresses), \
                     patch.object(socket,'socket',side_effect=[first,second]) as factory, \
                     patch.object(ssl,'SSLContext',return_value=context):
                    if close_fails:
                        with self.assertRaises(ConnectionRefusedError) as cm:tls_for_test(ORIGIN,1)
                        self.assertTrue(m.diagnostic(cm.exception)['cleanup_uncertain'])
                    else:self.assertIs(tls_for_test(ORIGIN,1),wrapped)
                self.assertEqual(events,['first_closed'] if close_fails else ['first_closed','second_connect'])
                self.assertEqual(factory.call_count,1 if close_fails else 2)
                first.close.assert_called_once();second.close.assert_not_called()

    def test_owned_connect_empty_or_exhausted_addresses_stop_without_tls(self):
        for count in (0,2):
            with self.subTest(count=count):
                sockets=[Mock(),Mock()];context=Mock()
                for s in sockets:s.connect.side_effect=ConnectionRefusedError(61,'secret')
                addresses=[(socket.AF_INET,socket.SOCK_STREAM,6,'',('192.0.2.1',443))]*count
                with patch.object(socket,'getaddrinfo',return_value=addresses), \
                     patch.object(socket,'socket',side_effect=sockets) as factory, \
                     patch.object(ssl,'SSLContext',return_value=context):
                    with self.assertRaises(OSError):tls_for_test(ORIGIN,1)
                self.assertEqual(factory.call_count,count);context.wrap_socket.assert_not_called()
                for s in sockets[:count]:s.close.assert_called_once()

    def test_cancel_during_socket_creation_or_tls_transfer_closes_new_owner(self):
        for target in ('constructor', 'tls_transfer'):
            with self.subTest(target=target):
                token=m.WallCancellation();plain,wrapped,context=Mock(),Mock(),Mock()
                held=[]
                def create(*args):
                    if target=='constructor':token.request()
                    return plain
                def wrap(*args,**kwargs):
                    self.assertFalse(kwargs['do_handshake_on_connect'])
                    token.request()  # native return-to-owner registration window
                    return wrapped
                context.wrap_socket.side_effect=wrap
                with fake_tcp(constructor=Mock(side_effect=create)),patch.object(ssl,'SSLContext',return_value=context):
                    try:tls_for_test(ORIGIN,1,cancellation=token)
                    except m.WallDeadline as error:held.append(error)
                self.assertEqual(len(held),1);self.assertIsNotNone(held[0].__traceback__)
                (plain if target=='constructor' else wrapped).close.assert_called_once()
                (wrapped if target=='constructor' else plain).close.assert_not_called()
                wrapped.do_handshake.assert_not_called()
                if target=='constructor':plain.connect.assert_not_called()
                self.assertEqual(token.depth,0);self.assertTrue(token.pending)

    def test_pending_cancellation_blocks_reuse_before_any_socket_construction(self):
        token=m.WallCancellation()
        with self.assertRaises(m.WallDeadline):token.request()
        with fake_tcp() as constructor,patch.object(ssl,'SSLContext',return_value=Mock()):
            with self.assertRaises(m.WallDeadline):tls_for_test(ORIGIN,1,cancellation=token)
        constructor.assert_not_called();self.assertEqual(token.depth,0)

    def test_registered_connector_cancel_before_return_closes_from_shared_owner(self):
        for close_fails in (False,True):
            with self.subTest(close_fails=close_fails):
                self.setUp();c=Conn(length(),close_error=close_fails);held=[]
                def connect(url,seconds,owner):
                    owner.register(c)
                    raise m.WallDeadline()  # after registration, before caller resumes
                try:m.acquire(spec(),self.budget,self.sink,connect=connect,clock=self.clock)
                except m.WallDeadline as error:held.append(error)
                self.assertEqual(len(held),1);self.assertIsNotNone(held[0].__traceback__)
                self.assertEqual(c.closed,1);self.assertEqual(c.sent,[])
                record=self.budget.records[-1];h=record['hops'][0]
                self.assertTrue(h['connector_handle_registered'])
                self.assertFalse(h['connector_returned']);self.assertEqual(h['closed'],not close_fails)
                self.assertEqual(record['close_uncertain'],close_fails)
                self.assertEqual(record['failure']['category'],'TIMEOUT')
                self.assertEqual(record['state'],'STOP');self.assertTrue(record['sink_closed'])

    def test_registered_tls_failure_and_hop_share_one_close_attempt(self):
        for close_fails in (False,True):
            with self.subTest(close_fails=close_fails):
                self.setUp();wrapped,context=Mock(),Mock();wrapped.do_handshake.side_effect=OSError('secret handshake')
                if close_fails:wrapped.close.side_effect=OSError('secret cleanup')
                context.wrap_socket.return_value=wrapped
                with fake_tcp(),patch.object(ssl,'SSLContext',return_value=context):
                    with self.assertRaises(OSError):
                        m.acquire(spec(),self.budget,self.sink,connect=m.tls_connect,clock=self.clock)
                wrapped.close.assert_called_once();h=self.budget.records[-1]['hops'][0]
                self.assertTrue(h['connector_handle_registered']);self.assertFalse(h['connector_returned'])
                self.assertEqual(h['closed'],not close_fails)
                self.assertEqual(self.budget.records[-1]['close_uncertain'],close_fails)

    def test_connector_without_registered_handle_is_rejected(self):
        with self.assertRaisesRegex(m.Stop,'^CONNECTOR_OWNERSHIP$'):
            m.acquire(spec(),self.budget,self.sink,connect=Mock(return_value=Conn(length())),clock=self.clock)
        self.assertEqual(self.budget.records[-1]['state'],'STOP')

    def test_owned_address_attempts_recompute_hop_operation_and_global_deadlines(self):
        for bound in ('hop','operation','global'):
            with self.subTest(bound=bound):
                self.setUp();clock=self.clock;context=Mock();sockets=[Mock() for _ in range(8)]
                item=spec(limits=limits(hop_seconds=20,total_seconds=7 if bound=='operation' else 60))
                self.budget=m.Budget(limits(header=16384,requests=20,hop_seconds=20,
                                           total_seconds=7 if bound=='global' else 60),0)
                seen=[]
                for s in sockets:
                    def connect(address,s=s):
                        used=s.settimeout.call_args.args[0];seen.append(used);clock.value+=used
                        raise TimeoutError('synthetic address timeout')
                    s.connect.side_effect=connect
                addresses=[(socket.AF_INET,socket.SOCK_STREAM,6,'',('192.0.2.1',443))]*8
                with patch.object(socket,'getaddrinfo',return_value=addresses), \
                     patch.object(socket,'socket',side_effect=sockets) as factory, \
                     patch.object(ssl,'SSLContext',return_value=context):
                    with self.assertRaisesRegex(m.Stop,'^DEADLINE$'):
                        m.acquire(item,self.budget,self.sink,connect=m.tls_connect,clock=clock)
                self.assertEqual(seen,[5,5,5,5] if bound=='hop' else [5,2])
                self.assertEqual(factory.call_count,len(seen))
                for s in sockets[:len(seen)]:s.close.assert_called_once()
                for s in sockets[len(seen):]:s.connect.assert_not_called()
                context.wrap_socket.assert_not_called();self.assertEqual(self.budget.used['requests'],1)

    def test_dns_or_handshake_time_consumption_blocks_following_network_stage(self):
        for stage in ('dns','handshake'):
            with self.subTest(stage=stage):
                self.setUp();plain,wrapped,context=Mock(),Mock(),Mock();context.wrap_socket.return_value=wrapped
                addresses=[(socket.AF_INET,socket.SOCK_STREAM,6,'',('192.0.2.1',443))]
                def resolve(*args):
                    if stage=='dns':self.clock.value=11
                    return addresses
                def handshake():self.clock.value=11
                wrapped.do_handshake.side_effect=handshake
                with patch.object(socket,'getaddrinfo',side_effect=resolve), \
                     patch.object(socket,'socket',return_value=plain) as factory, \
                     patch.object(ssl,'SSLContext',return_value=context):
                    with self.assertRaisesRegex(m.Stop,'^DEADLINE$'):
                        m.acquire(spec(),self.budget,self.sink,connect=m.tls_connect,clock=self.clock)
                if stage=='dns':factory.assert_not_called();context.wrap_socket.assert_not_called()
                else:wrapped.close.assert_called_once();wrapped.sendall.assert_not_called()

    def test_cancel_preempts_finally_before_close_but_shared_owner_still_closes(self):
        for close_fails in (False,True):
            with self.subTest(close_fails=close_fails):
                self.setUp();c=Conn(length(),close_error=close_fails);token=m.WallCancellation();held=[]
                def connect(url,seconds,owner):owner.cancellation=token;owner.register(c)
                original=m.in_phase;injected=False
                def boundary(phase,function,*args,**kwargs):
                    nonlocal injected
                    if phase=='CONNECTION_CLOSE' and not injected:
                        injected=True;token.request()  # before owner.close starts
                    return original(phase,function,*args,**kwargs)
                with patch.object(m,'in_phase',side_effect=boundary):
                    try:m.acquire(spec(),self.budget,self.sink,connect=connect,clock=self.clock)
                    except m.WallDeadline as error:held.append(error)
                self.assertEqual(len(held),1);self.assertIsNotNone(held[0].__traceback__)
                self.assertEqual(c.closed,1);h=self.budget.records[-1]['hops'][0]
                self.assertTrue(h['connector_handle_registered']);self.assertEqual(h['closed'],not close_fails)
                self.assertEqual(self.budget.records[-1]['close_uncertain'],close_fails)
                self.assertEqual(self.budget.records[-1]['failure']['phase'],'CONNECTION_CLOSE')
                self.assertEqual(self.budget.records[-1]['state'],'STOP')

    def test_alarm_during_local_descriptor_close_delivers_after_completion_record(self):
        for close_fails in (False,True):
            with self.subTest(close_fails=close_fails):
                owner=m.SocketOwner();resource=Mock();owner.register(resource)
                def close():
                    owner.cancellation.request()
                    if close_fails:raise OSError('secret cleanup')
                resource.close.side_effect=close
                with self.assertRaises(m.WallDeadline) as cm:owner.close(OSError('secret primary'))
                self.assertTrue(owner.attempted);self.assertEqual(owner.closed,not close_fails)
                self.assertEqual(m.diagnostic(cm.exception)['cleanup_uncertain'],close_fails)
                owner.close(cm.exception);resource.close.assert_called_once()

    def test_cli_alarm_before_disarm_condition_and_during_disarm_is_safe_stop(self):
        for when in ('condition','disarm'):
            with self.subTest(when=when):
                handlers=[];injected=False
                def install(sig,handler):handlers.append(handler)
                def alarm(seconds):
                    nonlocal injected
                    if seconds==0 and when=='disarm':
                        injected=True;handlers[0](probe.signal.SIGALRM,None)
                    return 0
                def trace(frame,event,arg):
                    nonlocal injected
                    if (when=='condition' and not injected and event=='line' and
                        frame.f_code is probe.main.__code__ and
                        linecache.getline(frame.f_code.co_filename,frame.f_lineno).strip()=='if alarm_installed:'):
                        injected=True
                        handlers[0](probe.signal.SIGALRM,None)
                    return trace
                prior=sys.gettrace()
                try:
                    sys.settrace(trace)
                    code,d,p=self.cli(['--run-approved-public-transport-once'],
                                      signal=Mock(side_effect=install),alarm=Mock(side_effect=alarm))
                finally:sys.settrace(prior)
                self.assertTrue(injected);self.assertEqual(code,78)
                self.assertEqual(d['reason'],'PROBE_DEADLINE');self.assertTrue(d['local_wall_alarm_expired'])
                self.assertEqual(p['alarm'].call_args_list[-1].args,(0,))

    def test_no_actual_network_events(self):
        self.assertEqual(self.network_events,[])


if __name__ == '__main__':
    unittest.main(verbosity=2)
