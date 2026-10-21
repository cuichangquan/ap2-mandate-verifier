"""Offline synthetic tests: actual process/socket/fork/signal actions forbidden."""
import contextlib
import io
import os
import subprocess
import datetime as dt
import hashlib
import importlib.util
import json
import lzma
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).parent
spec = importlib.util.spec_from_file_location('metadata_under_test',HERE/'p1r_runtime_prepare.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
IO_EVENTS = []
def audit(event,args):
    if event in ('subprocess.Popen','socket.__new__','socket.getaddrinfo','os.fork','os.kill','os.killpg','os.system'):
        IO_EVENTS.append(event)
        raise AssertionError('FORBIDDEN_REAL_IO')
sys.addaudithook(audit)
NOW = dt.datetime(2026,10,20,8,tzinfo=dt.timezone.utc)

# Literal field projections from the retained run39394877547 originals, not
# signature evidence or a new signed-metadata replay. Historical NOW is used
# only for fixture parsing; production UTC/expiry/signature checks are unchanged.
# ZIP SHA256: 1e5c4b3ea8008b883cd4798cb545de515d41c51010c0da632c4884690fd49048
# main InRelease SHA256: 77737fa4b34f2693e982cc9ee35736816c35a7778fc2d326cc1bbf5b301fe1aa
# security InRelease SHA256: 1fdef039b234961ba7a4a4fb0977a2a2d2a76a42fc746a3c243c451ee51bdb7c
SAVED_RELEASE_FIELDS = {
    'main': b'''Origin: Debian
Label: Debian
Suite: oldstable
Codename: bookworm
Date: Sat, 11 Jul 2026 10:16:37 UTC
Architectures: all amd64 arm64 armel armhf i386 mips64el mipsel ppc64el s390x
Components: main contrib non-free-firmware non-free
SHA256:
 9e0b5aabb2465b3d2e7a7fe27f9913846277833f7a2826e7767acccff5b588c5  8790396 main/binary-amd64/Packages.xz
''',
    'security': b'''Origin: Debian
Label: Debian-Security
Suite: oldstable-security
Codename: bookworm-security
Date: Tue, 20 Oct 2026 02:02:23 UTC
Valid-Until: Tue, 27 Oct 2026 02:02:23 UTC
Architectures: amd64 arm64 armhf i386 ppc64el
Components: updates/main updates/contrib updates/non-free-firmware updates/non-free
SHA256:
 91b95fb63d502d38db76ec77806f614d6ee8731912c1301cd4fa13e53059437b   354040 main/binary-amd64/Packages.xz
'''}

def sig(origin):
    data = []
    for role in p.ROLES[origin]:
        primary, signer = p.KEYS[role]
        data += ['[GNUPG:] NEWSIG','[GNUPG:] KEY_CONSIDERED '+primary+' 0',
                 '[GNUPG:] GOODSIG '+signer[-16:]+' untrusted user words',
                 '[GNUPG:] VALIDSIG '+signer+' 2026-10-20 1792480000 0 4 0 1 8 01 '+primary]
    return ('\n'.join(data)+'\n').encode()

def key(role):
    primary, signer = p.KEYS[role]
    data = 'pub:::::::::\nfpr:::::::::'+primary+':\nuid:::::::::UNTRUSTED:\n'
    if signer != primary:
        data += 'sub:::::::::\nfpr:::::::::'+signer+':\n'
    return data.encode()

def release(origin,index,expiry='Tue, 27 Oct 2026 08:00:00 +0000'):
    identity = ('Origin:','Codename:','Architectures:','Components:')
    text = '\n'.join(line for line in SAVED_RELEASE_FIELDS[origin].decode('ascii').splitlines()
                     if line.startswith(identity))+'\n'
    text += 'Date: Tue, 20 Oct 2026 07:00:00 +0000\n'
    if expiry is not None:
        text += 'Valid-Until: '+expiry+'\n'
    text += 'SHA256:\n '+p.digest(index)+' '+str(len(index))+' main/binary-amd64/Packages.xz\n'
    return text.encode()

class Integration:
    def __init__(self,recipe,output,scratch,budget):
        self.recipe,self.output,self.scratch,self.budget = recipe,output,scratch,budget
        self.events,self.fail,self.bad = [],None,None
        self.indexes = {}
        for origin in p.ROLES:
            stanzas = []
            for r in recipe['candidates']:
                if r['origin'] == origin:
                    stanzas.append('\n'.join(k+': '+str(r[v]) for k,v in
                                  [('Package','package'),('Version','version'),('Architecture','architecture'),
                                   ('Filename','filename'),('Size','size'),('SHA256','sha256')]))
            self.indexes[origin] = lzma.compress(('\n\n'.join(stanzas)+'\n\n').encode())
    def get(self,label,destination):
        self.budget.reserve(label)
        self.events.append(label)
        if label == self.fail:
            raise p.Stop('FETCH_FAILURE')
        data = b'synthetic public key' if label in p.KEYS else b'signed release'
        if label.endswith('_index'):
            data = self.indexes[label[:-6]]
        self.budget.body(len(data))
        destination.write_bytes(data)
        return destination
    def run(self,argv):
        if argv[0].endswith('gpgv'):
            source = Path(argv[-1])
            origin = source.name.split('_')[0]
            self.events.append('verify_'+origin)
            data = release(origin,self.indexes[origin],None if self.bad == 'expiry' and origin == 'security' else 'Tue, 27 Oct 2026 08:00:00 +0000')
            Path(argv[argv.index('--output')+1]).write_bytes(data)
            return (1 if self.bad == 'signature' else 0),sig(origin)
        role = Path(argv[-1]).stem
        if '--show-keys' in argv:
            return 0,key(role)
        Path(argv[argv.index('--output')+1]).write_bytes(b'keyring')
        return 0,b''

class Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.recipe = json.loads((HERE/'p1r_runtime_recipe.json').read_text())
        self.budget = p.Budget(lambda:1.0)
    def stop(self,fn,*args):
        with self.assertRaises(p.Stop):
            fn(*args)
    def index(self,data,rows,descriptor=None):
        path = self.root/'index'
        path.write_bytes(data)
        return p.index_check(path,descriptor or {'size':len(data),'sha256':p.digest(data)},rows,self.budget)
    def test_approved_scope_and_closed_urls(self):
        self.assertEqual(len(p.ENDPOINTS),9)
        self.assertEqual(len({(x[1],x[2]) for x in p.ENDPOINTS}),9)
        self.assertEqual({x[1] for x in p.ENDPOINTS},{'ftp-master.debian.org','deb.debian.org','security.debian.org'})
        self.assertEqual(sum(x[3] for x in p.ENDPOINTS),5*131072+2*524288+2*16*p.MIB)
        self.assertEqual(len(p.recipe_check(self.recipe)),35)
        self.assertFalse(self.recipe['executable'])
        self.assertFalse(self.recipe['runtime_authority'])
    def test_recipe_rejects_scope_and_descriptor_changes(self):
        for k,v in [('schema',2),('executable',True),('runtime_authority',True),('ap2_six_cases','PASS'),('candidates',[])]:
            with self.subTest(k=k):
                self.stop(p.recipe_check,dict(self.recipe,**{k:v}))
        for k,v in [('origin','unknown'),('sha256','0'*63),('size',True),('architecture','arm64'),('filename','pool/main/../bad')]:
            with self.subTest(k=k):
                r=json.loads(json.dumps(self.recipe));r['candidates'][0][k]=v
                self.stop(p.recipe_check,r)
        self.stop(p.unique,[('x',1),('x',2)])
    def test_header_direct200_exact_limits(self):
        header = b'HTTP/1.1 200 OK\r\nContent-Length: 131072\r\n\r\n'
        self.assertEqual(p.parse_header(header,131072),131072)
        for raw in [header.replace(b'200',b'302'),header.replace(b'131072',b'131073'),
                    header.replace(b'131072',b'0'),header.replace(b'131072',b'-1'),
                    header.replace(b'\r\n\r\n',b'\r\nLocation: https://evil/\r\n\r\n'),
                    header.replace(b'\r\n\r\n',b'\r\nTransfer-Encoding: chunked\r\n\r\n'),
                    header.replace(b'\r\n\r\n',b'\r\nContent-Length: 1\r\n\r\n'),
                    header.replace(b'\r\n\r\n',b'\r\nContent-Encoding: gzip\r\n\r\n'),
                    header.replace(b'Content-Length',b' Content-Length'),b'x'*8193]:
            with self.subTest(raw=raw[:60]):
                self.stop(p.parse_header,raw,131072)
    def test_budget_before_network_no_retry_and_total(self):
        self.budget.reserve('main_key')
        self.stop(self.budget.reserve,'main_key')
        self.stop(self.budget.reserve,'unknown')
        self.budget.body(p.BODY_CAP)
        self.stop(self.budget.body,1)
        clock=[0.0];b=p.Budget(lambda:clock[0]);clock[0]=110
        self.stop(b.reserve,'main_key')
        self.assertFalse(b.requests)
    def test_fetch_exact_request_close_and_bounds(self):
        class Wire:
            def __init__(self,data): self.data,self.sent,self.closed=data,b'',False
            def settimeout(self,x): pass
            def sendall(self,x): self.sent=x
            def recv(self,n): value,self.data=self.data[:n],self.data[n:];return value
            def close(self): self.closed=True
        wire=Wire(b'HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nabc')
        class Context:
            def set_alpn_protocols(self,x): pass
            def wrap_socket(self,x,server_hostname): return wire
        with patch.object(p.socket,'create_connection',return_value=wire),patch.object(p.ssl,'create_default_context',return_value=Context()):
            p.Fetch(self.budget).get('main_key',self.root/'key')
        self.assertEqual((self.root/'key').read_bytes(),b'abc')
        self.assertTrue(wire.closed)
        self.assertIn(b'GET /keys/archive-key-12.asc HTTP/1.1',wire.sent)
        self.assertNotIn(b'Authorization',wire.sent)
        self.assertEqual(self.budget.used,3)
        self.assertEqual(self.budget.receipts[0]['sha256'],p.digest(b'abc'))
    def test_fetch_rejects_redirect_and_header_before_body(self):
        for data in (b'HTTP/1.1 302 Found\r\nContent-Length: 1\r\n\r\nx',b'A'*8193):
            class Wire:
                closed=False
                def settimeout(self,x): pass
                def sendall(self,x): pass
                def recv(self,n): nonlocal data;v,data=data[:n],data[n:];return v
                def close(self): self.closed=True
            wire=Wire()
            class Context:
                def set_alpn_protocols(self,x): pass
                def wrap_socket(self,x,server_hostname): return wire
            budget=p.Budget(lambda:1)
            with patch.object(p.socket,'create_connection',return_value=wire),patch.object(p.ssl,'create_default_context',return_value=Context()):
                self.stop(p.Fetch(budget).get,'main_key',self.root/'unused')
            self.assertTrue(wire.closed)
            self.assertEqual(budget.used,0)
            self.assertLessEqual(budget.headers,8192)
    def test_exact_primary_subkey_set(self):
        for role in p.KEYS:
            with self.subTest(role=role):
                p.key_check(key(role),role)
                self.stop(p.key_check,key(role).replace(p.KEYS[role][0].encode(),b'F'*40),role)
                self.stop(p.key_check,key(role)+key(role),role)
                self.stop(p.key_check,key(role)+b'unknown::\n',role)
        self.stop(p.key_check,key('main_key').replace(b'sub:',b'pub:'),'main_key')
        self.stop(p.key_check,key('stable_key')+b'sub:::::::::\nfpr:::::::::'+b'F'*40+b':\n','stable_key')
    def test_signature_exact_roles_and_error_return(self):
        for origin in p.ROLES:
            p.signature_check(sig(origin),origin)
            for bad in [sig(origin)+b'[GNUPG:] ERROR untrusted\n',sig(origin).replace(b'VALIDSIG',b'BADSIG',1),
                        sig(origin).replace(b'NEWSIG',b'UNEXPECTED',1),sig(origin).replace(b'GOODSIG',b'ERRSIG',1),
                        sig(origin).replace(p.KEYS[p.ROLES[origin][0]][1].encode(),b'F'*40)]:
                self.stop(p.signature_check,bad,origin)
            self.stop(p.signature_check,sig(origin),origin,1)
            self.stop(p.signature_check,sig(origin)+sig(origin),origin)
    def test_signature_pair_missing_duplicate_and_bounds(self):
        source=sig('main')
        for source in [b'',source.replace(b'GOODSIG',b'NO_PUBKEY',1),
                       b'[GNUPG:] NEWSIG\n'+source,source.replace(b'[GNUPG:] ',b'',1),
                       source+b'x'*65537]:
            self.stop(p.signature_check,source,'main')
        self.stop(p.signature_check,sig('security'),'main')
    def test_saved_release_fields_keep_origin_and_signed_index_distinct(self):
        expected = {
            'main': (8790396,'9e0b5aabb2465b3d2e7a7fe27f9913846277833f7a2826e7767acccff5b588c5','ABSENT'),
            'security': (354040,'91b95fb63d502d38db76ec77806f614d6ee8731912c1301cd4fa13e53059437b','2026-10-27T02:02:23+00:00')}
        self.assertEqual(p.INDEX_PATH,'main/binary-amd64/Packages.xz')
        for origin, raw in SAVED_RELEASE_FIELDS.items():
            with self.subTest(origin=origin):
                result = p.release_check(raw,origin,NOW)
                self.assertEqual((result['size'],result['sha256'],result['valid_until']),expected[origin])
                # Components must not rewrite the signed index path or GET URL.
                rewritten = raw.replace(b' main/binary-amd64/Packages.xz',
                                        b' updates/main/binary-amd64/Packages.xz')
                with self.assertRaises(p.Stop) as rejected:
                    p.release_check(rewritten,origin,NOW)
                self.assertEqual(str(rejected.exception),'INDEX_DESCRIPTOR')
        for origin in ('unknown','bookworm-security',None):
            self.stop(p.release_check,SAVED_RELEASE_FIELDS['security'],origin,NOW)

    def test_saved_components_reject_swapped_missing_and_partial_tokens(self):
        for origin, raw in SAVED_RELEASE_FIELDS.items():
            line = next(line for line in raw.splitlines() if line.startswith(b'Components:'))
            swapped = b'updates/main' if origin == 'main' else b'main'
            partial = b'main-extra' if origin == 'main' else b'updates/main-extra'
            for replacement in (b'Components: '+swapped,b'Components: '+partial,
                                b'Components: contrib',b'Components:',b''):
                with self.subTest(origin=origin,replacement=replacement):
                    changed = raw.replace(line+b'\n',replacement+b'\n' if replacement else b'')
                    with self.assertRaises(p.Stop) as rejected:
                        p.release_check(changed,origin,NOW)
                    self.assertEqual(str(rejected.exception),'RELEASE_IDENTITY')

    def test_saved_security_component_fix_preserves_expiry_rejection(self):
        raw = SAVED_RELEASE_FIELDS['security']
        missing = raw.replace(b'Valid-Until: Tue, 27 Oct 2026 02:02:23 UTC\n',b'')
        deadline = dt.datetime(2026,10,27,2,2,23,tzinfo=dt.timezone.utc)
        for candidate, now in ((missing,NOW),(raw,deadline),
                               (raw,deadline+dt.timedelta(seconds=1))):
            with self.subTest(missing=candidate == missing,now=now):
                with self.assertRaises(p.Stop) as rejected:
                    p.release_check(candidate,'security',now)
                self.assertEqual(str(rejected.exception),'RELEASE_EXPIRED')

    def test_release_date_expiry_identity_and_unique_hash(self):
        raw=release('main',b'abc',None)
        self.assertEqual(p.release_check(raw,'main',NOW)['valid_until'],'ABSENT')
        p.release_check(release('security',b'abc'),'security',NOW)
        for raw in [release('security',b'abc',None),release('security',b'abc','Tue, 20 Oct 2026 08:00:00 +0000'),
                    release('security',b'abc').replace(b'07:00:00',b'09:00:00'),
                    release('security',b'abc').replace(b'bookworm-security',b'trixie-security'),
                    release('security',b'abc').replace(b'SHA256:',b'Date: duplicated\nSHA256:'),
                    release('security',b'abc').replace(p.INDEX_PATH.encode(),b'otherpath'),
                    release('security',b'abc')+(' '+p.digest(b'abc')+' 3 '+p.INDEX_PATH+'\n').encode()]:
            self.stop(p.release_check,raw,'security',NOW)
    def test_index_exact_membership_and_xz_integrity(self):
        r=self.recipe['candidates'][0]
        text='\n'.join(k+': '+str(r[v]) for k,v in [('Package','package'),('Version','version'),('Architecture','architecture'),('Filename','filename'),('Size','size'),('SHA256','sha256')])+'\n\n'
        data=lzma.compress(text.encode())
        self.assertEqual(self.index(data,[r]),1)
        for text2 in [text.replace(r['version'],'0.0'),text.replace(r['sha256'],'f'*64),text+text,text.replace('Size:','Size: 1\nSize:')]:
            with self.subTest(text=text2[:40]): self.stop(self.index,lzma.compress(text2.encode()),[r])
        for data2 in [data+b'extra',data+data,data[:-4]]:
            with self.subTest(length=len(data2)):
                try:self.index(data2,[r])
                except (p.Stop,lzma.LZMAError):pass
                else:self.fail('accepted corrupt/trailing xz')
        self.stop(self.index,data,[r],{'size':len(data),'sha256':'f'*64})
    def test_full_mock_nine_fetches_order_and35_members(self):
        output=self.root/'out';output.mkdir();scratch=self.root/'private';scratch.mkdir()
        fake=Integration(self.recipe,output,scratch,self.budget)
        with patch.object(p,'TRIXIE_SHA',p.digest(b'synthetic public key')):
            result=p.verify(self.recipe,fake,fake,output,scratch,self.budget,lambda:NOW)
        self.assertEqual(sum(result['matched'].values()),35)
        self.assertEqual(len(self.budget.requests),9)
        self.assertLess(fake.events.index('verify_security'),fake.events.index('main_index'))
    def test_no_index_after_bad_signature_expiry_or_key(self):
        for failure in ('signature','expiry','key'):
            with tempfile.TemporaryDirectory(dir=self.root) as tmp:
                root=Path(tmp);out=root/'out';out.mkdir();private=root/'private';private.mkdir()
                fake=Integration(self.recipe,out,private,p.Budget(lambda:1));fake.bad=failure
                with patch.object(p,'TRIXIE_SHA',p.digest(b'WRONG' if failure=='key' else b'synthetic public key')):
                    self.stop(p.verify,self.recipe,fake,fake,out,private,fake.budget,lambda:NOW)
                self.assertFalse(any(x.endswith('_index') for x in fake.events))
    def test_first_failure_no_second_fetch(self):
        out=self.root/'out';out.mkdir();private=self.root/'private';private.mkdir()
        fake=Integration(self.recipe,out,private,self.budget);fake.fail='main_key'
        self.stop(p.verify,self.recipe,fake,fake,out,private,self.budget,lambda:NOW)
        self.assertEqual(fake.events,['main_key'])
    def test_workflow_guards_and_no_automatic_trigger(self):
        text=(HERE.parent.parent/'.github/workflows/phase2a-runtime-preflight-v2-once.yml').read_text()
        for token in ['workflow_dispatch:','github.run_attempt == 1','runs-on: ubuntu-24.04','timeout-minutes: 5',
                      'runtime-preflight-v2-once-consumed-20261021','persist-credentials: false','--kill-after=5s 115s',
                      'retention-days: 7','ARTIFACT_CAP','zero_cost_confirmed','RECIPE_SHA','SOURCE_SHA']:
            self.assertIn(token,text)
        self.assertEqual(text.split('SOURCE_SHA: ',1)[1].split()[0],
                         p.digest((HERE/'p1r_runtime_prepare.py').read_bytes()))
        self.assertEqual(text.split('RECIPE_SHA: ',1)[1].split()[0],
                         p.digest((HERE/'p1r_runtime_recipe.json').read_bytes()))
        previous=HERE.parent.parent/'.github/workflows/phase2a-runtime-preflight-once.yml'
        self.assertEqual(p.digest(previous.read_bytes()),
                         'dd47fbdfc7868726bb4b696e8fb85c47a6317d1792361712c8c10965c3ef0262')
        self.assertNotIn('pull_request:',text)
        self.assertNotIn('push:',text)
        self.assertNotIn('sudo ',text)
        self.assertIn('env -i PATH=/usr/bin:/bin',text)
        self.assertIn("report['sha'] == os.environ['GITHUB_SHA']",text)
        self.assertIn("report['run'] == os.environ['GITHUB_RUN_ID']",text)
        self.assertIn("report['attempt'] == os.environ['GITHUB_RUN_ATTEMPT'] == '1'",text)
    def test_commands_owned_child_deadline_cleanup_and_output(self):
        for mode in ('ok','timeout','kill_error','reap_error','poll_error','overflow','spawn_error'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(dir=self.root) as folder:
                calls=[]
                class Child:
                    waits=0
                    done=False
                    def wait(self,timeout):
                        calls.append('wait');self.waits+=1
                        if mode in ('timeout','kill_error','reap_error','poll_error') and self.waits==1:
                            raise subprocess.TimeoutExpired('closed-verifier',timeout)
                        if mode=='reap_error': raise OSError('synthetic')
                        self.done=True;return 0
                    def poll(self):
                        calls.append('poll')
                        if mode=='poll_error':raise OSError('synthetic')
                        return 0 if self.done else None
                    def kill(self):
                        calls.append('kill')
                        if mode=='kill_error':raise OSError('synthetic')
                child=Child()
                def spawn(argv,**kw):
                    self.assertFalse(kw['start_new_session'])
                    self.assertTrue(kw['close_fds'])
                    self.assertNotIn('GH_TOKEN',kw['env'])
                    if mode=='spawn_error':raise OSError('synthetic')
                    kw['stdout'].write(b'x'*(65537 if mode=='overflow' else 2))
                    return child
                with patch.object(p.subprocess,'Popen',side_effect=spawn):
                    if mode=='ok':self.assertEqual(p.Commands(self.budget,Path(folder)).run(['/usr/bin/gpg']), (0,b'xx'))
                    elif mode=='spawn_error':
                        with self.assertRaises(OSError):p.Commands(self.budget,Path(folder)).run(['/usr/bin/gpg'])
                    else:self.stop(p.Commands(self.budget,Path(folder)).run,['/usr/bin/gpg'])
                if mode in ('timeout','kill_error','reap_error','poll_error'):
                    self.assertIn('kill',calls)
                    self.assertEqual(calls.count('wait'),2)
    def test_main_success_deadline_cleanup_and_artifact_bound(self):
        original_text,original_bytes=Path.read_text,Path.read_bytes
        for mode in ('ok','deadline','cleanup','expired','oversize','foreign'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(dir=self.root) as folder:
                old=os.getcwd();os.chdir(folder)
                try:
                    if mode=='foreign':
                        Path('runtime-metadata-evidence').mkdir()
                        Path('runtime-metadata-evidence/result.json').write_text('{"foreign":true}')
                    budget=p.Budget(lambda:1)
                    if mode=='deadline':budget.left=lambda: p.need(False,'DEADLINE')
                    def read_text(path,*a,**kw):
                        if str(path)=='/etc/os-release':return 'VERSION_ID="24.04"'
                        return original_text(path,*a,**kw)
                    def read_bytes(path):
                        if str(path) in ('/usr/bin/gpg','/usr/bin/gpgv'):return b'trusted-host-tool'
                        return original_bytes(path)
                    def fake_verify(recipe,fetch,commands,output,scratch,budget,utc):
                        if mode=='oversize':(output/'main_key.asc').write_bytes(b'x'*200000)
                        return {'releases':{'main':{'valid_until':'ABSENT'},'security':{'valid_until':
                                    '2000-01-01T00:00:00+00:00' if mode=='expired' else '2099-01-01T00:00:00+00:00'}},'matched':{'main':21,'security':14}}
                    real_temp=p.tempfile.TemporaryDirectory
                    class Private:
                        def __init__(self,**kw):self.inner=real_temp(**kw)
                        def __enter__(self):return self.inner.__enter__()
                        def __exit__(self,*args):
                            self.inner.__exit__(*args)
                            if mode=='cleanup':raise p.Stop('SCRATCH_CLEANUP')
                    with contextlib.ExitStack() as stack:
                        for patcher in (patch.object(p.platform,'system',return_value='Linux'),
                                        patch.object(p.platform,'machine',return_value='x86_64'),
                                        patch.object(p.os,'access',return_value=True),patch.object(p.signal,'signal'),
                                        patch.object(p,'Budget',return_value=budget),patch.object(p,'verify',side_effect=fake_verify),
                                        patch.object(p.tempfile,'TemporaryDirectory',Private),patch.object(Path,'read_text',read_text),
                                        patch.object(Path,'read_bytes',read_bytes),patch.object(p,'ARTIFACT_CAP',200000),
                                        patch.dict(os.environ,{'GITHUB_SHA':'a'*40,'GITHUB_RUN_ID':'123','GITHUB_RUN_ATTEMPT':'1'}),
                                        contextlib.redirect_stdout(io.StringIO())):
                            stack.enter_context(patcher)
                        code=p.main()
                    report=json.loads(Path('runtime-metadata-evidence/result.json').read_text())
                    if mode=='foreign':
                        self.assertEqual(code,78)
                        self.assertEqual(report,{'foreign':True})
                        continue
                    self.assertEqual(code,0 if mode=='ok' else 78)
                    self.assertEqual(report['status'].startswith('FIXED_METADATA'),mode=='ok')
                    self.assertLessEqual(sum(x.stat().st_size for x in Path('runtime-metadata-evidence').iterdir()),200000-p.ZIP_RESERVE)
                    if mode=='oversize':self.assertEqual(report['reason'],'ARTIFACT_LIMIT')
                finally:os.chdir(old)
    def test_no_real_io(self):
        self.assertEqual(IO_EVENTS,[])

if __name__ == '__main__':
    result=unittest.main(exit=False,verbosity=2).result
    summary={'methods':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),
             'skips':len(result.skipped),'forbidden_real_io':IO_EVENTS,'scope':'OFFLINE_SYNTHETIC_ONLY'}
    print(json.dumps(summary,sort_keys=True))
    raise SystemExit(0 if result.wasSuccessful() and not IO_EVENTS else 1)
