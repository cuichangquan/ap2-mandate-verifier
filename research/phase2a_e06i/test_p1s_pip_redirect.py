"""Offline synthetic transport replies only; never connects or downloads."""
import hashlib
import json
from pathlib import Path
import runpy
import unittest
from unittest.mock import patch

BASE=Path(__file__).resolve().parent
M=runpy.run_path(str(BASE/'p1s_static_inventory.py'))
G=M['pip_deb_get'].__globals__
SPEC=json.loads((BASE/'p1s_input_contract.json').read_text())
LOCATION=SPEC['pip_deb']['redirect_location']
BODY=b'synthetic package bytes'


class Redirect(unittest.TestCase):
    def test_actual_header_parser_keeps_exact_location(self):
        class Wire:
            def __init__(self,data):self.data=data
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def settimeout(self,*args):pass
            def sendall(self,*args):pass
            def recv(self,n):
                out,self.data=self.data[:n],self.data[n:]
                return out
        class Context:
            def __init__(self,wire):self.wire=wire
            def wrap_socket(self,*args,**kwargs):return self.wire
        def parse(value):
            M['configure'](SPEC,1)
            url=M['allow'](SPEC['pip_deb']['url'])
            wire=Wire(b'HTTP/1.1 302 Found\r\nLocation:'+value+b'\r\nContent-Length: 0\r\n\r\n')
            with patch('socket.create_connection',return_value=wire),patch('ssl.create_default_context',return_value=Context(wire)):
                return M['request'](url,4096)[1]['location']
        raw=LOCATION.encode('ascii')
        for good in (raw,b' '+raw):self.assertEqual(parse(good),LOCATION)
        for bad in (b'  '+raw,b'\t'+raw,b' '+raw+b' ',raw+b'\t',b' \t'+raw):
            with self.assertRaisesRegex(ValueError,'LOCATION_WIRE'):parse(bad)

    def attempt(self,replies):
        spec=dict(SPEC['pip_deb'],size=len(BODY),sha256=hashlib.sha256(BODY).hexdigest())
        M['configure'](SPEC,1)
        calls=[]
        def request(url,cap,**kwargs):
            calls.append((url,cap,kwargs))
            if not replies:raise AssertionError('unexpected additional request')
            return replies.pop(0)
        with patch.dict(G,request=request):
            return M['pip_deb_get'](spec),calls

    def test_exact_single_hop(self):
        raw,calls=self.attempt([(302,{'location':LOCATION},b'redirect body'),(200,{},BODY)])
        self.assertEqual(raw,BODY)
        self.assertEqual([c[0] for c in calls],[SPEC['pip_deb']['url'],'https://snapshot.debian.org'+LOCATION])
        self.assertTrue(all(c[1]==len(BODY) and c[2]=={} for c in calls))
        self.assertTrue(G['REPORT']['pip_transport']['size_sha256_verified'])

    def test_direct_200(self):
        self.assertEqual(len(self.attempt([(200,{},BODY)])[1]),1)

    def test_reject_locations(self):
        for location in [None,'','https://evil.example'+LOCATION,'https://snapshot.debian.org'+LOCATION,
                         '//snapshot.debian.org'+LOCATION,LOCATION+'?x=1',LOCATION+'#x',
                         LOCATION.replace('%2B','+'),LOCATION.replace('%2B','%2b'),
                         '/other',LOCATION+'/..',LOCATION+'\r\nX: value']:
            with self.subTest(location=location):
                with self.assertRaisesRegex(ValueError,'PIP_REDIRECT_TARGET'):
                    self.attempt([(302,{} if location is None else {'location':location},b'')])

    def test_reject_status_and_multihop(self):
        for status in (301,303,307,308,404,429,500):
            with self.assertRaisesRegex(ValueError,'PIP_HTTP'):
                self.attempt([(status,{'location':LOCATION},b'')])
        with self.assertRaisesRegex(ValueError,'PIP_HTTP'):
            self.attempt([(302,{'location':LOCATION},b''),(302,{'location':LOCATION},b'')])

    def test_reject_payload(self):
        for raw in (BODY[:-1],BODY+b'x',b'x'*len(BODY)):
            with self.assertRaisesRegex(ValueError,'PIP_DEB_HASH'):
                self.attempt([(302,{'location':LOCATION},b''),(200,{},raw)])


if __name__=='__main__':unittest.main()
