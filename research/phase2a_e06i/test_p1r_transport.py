"""Fake HTTP plaintext only. No DNS/TLS/network, SDK or installation proof."""
from dataclasses import replace
import datetime as dt
import hashlib
import io
import math
import socket
import ssl
import sys
import unittest
from unittest.mock import Mock, patch

import p1r_transport as m
import p1r_transport_probe as probe


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
                         connect=connect or fake, clock=self.clock)

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
        self.assertEqual(cm.exception.__notes__,['CLOSE_UNCERTAIN','CLOSE_UNCERTAIN'])
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
        with patch.object(socket,'create_connection',return_value=plain) as create, patch.object(ssl,'SSLContext',return_value=context), patch.object(ssl,'create_default_context',side_effect=AssertionError('ENV_KEYLOG_CONTEXT_FORBIDDEN')):
            self.assertIs(m.tls_connect(ORIGIN,2),wrapped)
            create.assert_called_once_with(('snapshot.example.invalid',443),timeout=2)
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
                with patch.object(socket,'create_connection',return_value=plain),patch.object(ssl,'SSLContext',return_value=context):
                    with self.assertRaises((OSError,m.Stop)) as cm:m.tls_connect(ORIGIN,1)
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
        self.assertEqual(error.__notes__,['CLOSE_UNCERTAIN','CLOSE_UNCERTAIN'])
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
        def connect(url,seconds):return connections.pop(0)
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
                with self.assertRaisesRegex(m.Stop,'EXPIRED_OR_UNKNOWN_CLOCK'):
                    probe.run_once(connect=connect,clock=self.clock,utc_now=lambda:now)
        for name in ('SSL_CERT_FILE','SSL_CERT_DIR','SSLKEYLOGFILE'):
            with self.subTest(name=name),patch.dict('os.environ',{name:'synthetic'},clear=True):
                with self.assertRaisesRegex(m.Stop,'TLS_ENV_OVERRIDE'):
                    probe.run_once(connect=connect,clock=self.clock,utc_now=lambda:dt.datetime(2026,10,17,tzinfo=dt.timezone.utc))
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
            self.assertEqual(cm.exception.__notes__,['CLOSE_UNCERTAIN','CLOSE_UNCERTAIN'])
            self.assertFalse(hasattr(ambient,'__notes__'))

    def test_tls_local_primary_is_explicit_inside_caller_except(self):
        plain,wrapped=Mock(),Mock();context=Mock();context.wrap_socket.return_value=wrapped
        wrapped.do_handshake.side_effect=OSError('local handshake')
        wrapped.close.side_effect=OSError('local close')
        try:
            raise RuntimeError('unrelated caller exception')
        except RuntimeError as ambient:
            with patch.object(socket,'create_connection',return_value=plain),patch.object(ssl,'SSLContext',return_value=context):
                with self.assertRaisesRegex(OSError,'local handshake') as cm:m.tls_connect(ORIGIN,1)
            self.assertEqual(cm.exception.__notes__,['CLOSE_UNCERTAIN'])
            self.assertFalse(hasattr(ambient,'__notes__'))

    def test_no_actual_network_events(self):
        self.assertEqual(self.network_events,[])


if __name__ == '__main__':
    unittest.main(verbosity=2)
