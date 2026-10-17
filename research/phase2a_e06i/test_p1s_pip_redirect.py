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
