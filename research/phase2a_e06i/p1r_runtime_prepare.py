"""One-shot public metadata verifier. No installer, runtime or native authority.

Only the main-only guarded workflow is an execution entry point. Trust pins are
copied from reviewed phase2a-p1-h4-metadata.yml; TLS does not confer signing trust.
No package/OCI/wheel/Gem bodies, redirects, retries, key discovery or auto-repin.
"""
import datetime as dt
import email.utils
import hashlib
import json
import lzma
import os
from pathlib import Path
import platform
import re
import resource
import signal
import socket
import ssl
import subprocess
import tempfile
import time

MIB = 1048576
BODY_CAP, HEADER_CAP, ARTIFACT_CAP = 32*MIB, 8192, 32*MIB
ZIP_RESERVE = 65536  # <=10 fixed short filenames, ZIP framing/metadata reserve
INDEX_PATH = 'main/binary-amd64/Packages.xz'
# label, host, path, maximum body. This closed table is the entire network scope.
ENDPOINTS = (
 ('main_key','ftp-master.debian.org','/keys/archive-key-12.asc',131072),
 ('security_key','ftp-master.debian.org','/keys/archive-key-12-security.asc',131072),
 ('stable_key','ftp-master.debian.org','/keys/release-12.asc',131072),
 ('trixie_key','ftp-master.debian.org','/keys/archive-key-13.asc',131072),
 ('bullseye_key','ftp-master.debian.org','/keys/archive-key-11-security.asc',131072),
 ('main_release','deb.debian.org','/debian/dists/bookworm/InRelease',524288),
 ('security_release','security.debian.org','/debian-security/dists/bookworm-security/InRelease',524288),
 ('main_index','deb.debian.org','/debian/dists/bookworm/'+INDEX_PATH,16*MIB),
 ('security_index','security.debian.org','/debian-security/dists/bookworm-security/'+INDEX_PATH,16*MIB))
# Exact primary/signing pairs, no newly discovered roles or subkeys.
KEYS = {
 'main_key':('B8B80B5B623EAB6AD8775C45B7C5D7D6350947F8','4CB50190207B4758A3F73A796ED0E7B82643E131'),
 'security_key':('05AB90340C0C5E797F44A8C8254CF3B5AEC0A8F0','B0CAB9266E8C3929798B3EEEBDE6D2B9216EC7A8'),
 'stable_key':('4D64FEC119C2029067D6E791F8D2585B8783D481','4D64FEC119C2029067D6E791F8D2585B8783D481'),
 'trixie_key':('04B54C3CDCA79751B16BC6B5225629DF75B188BD','B8E5F13176D2A7A75220028078DBA3BC47EF2265'),
 'bullseye_key':('AC530D520F2F3269F5E98313A48449044AAD5C5D','ED541312A33F1128F10B1C6C54404762BBB6E853')}
ROLES = {'main':('main_key','stable_key','trixie_key'),
         'security':('security_key','bullseye_key')}
TRIXIE_SHA = '6f1d277429dd7ffedcc6f8688a7ad9a458859b1139ffa026d1eeaadcbffb0da7'
HEX = r'[0-9a-f]{64}'

class Stop(Exception):
    pass

def need(ok, code):
    if not ok:
        raise Stop(code)

def unique(pairs):
    out = {}
    for key, value in pairs:
        need(key not in out, 'DUPLICATE_FIELD')
        out[key] = value
    return out

def digest(data):
    return hashlib.sha256(data).hexdigest()

class Budget:
    def __init__(self, clock=time.monotonic):
        self.clock, self.end = clock, clock()+110
        self.used, self.headers, self.requests = 0, 0, set()
        self.receipts = []
    def left(self):
        left = self.end-self.clock()
        need(left > 0, 'DEADLINE')
        return min(10, left)
    def reserve(self, label):
        self.left()
        need(label in {x[0] for x in ENDPOINTS} and label not in self.requests, 'REQUEST_SCOPE')
        self.requests.add(label)  # before DNS/connect, failed attempts consumed
    def body(self, size):
        self.used += size
        need(self.used <= BODY_CAP, 'BODY_TOTAL')
        self.left()

class Fetch:
    """HTTP/1.1 Content-Length only; unsupported framing stops, never falls back.

    Header bytes bounded before retention. Read no more than declared/capped body.
    DNS/connect/TLS can be interrupted by workflow's independent 115+5s deadline.
    No proxy/redirect/auth/cookie subsystem; verification uses system CA roots.
    """
    def __init__(self, budget):
        self.budget = budget
    def get(self, label, destination):
        row = next((x for x in ENDPOINTS if x[0] == label), None)
        need(row is not None, 'URL_SCOPE')
        self.budget.reserve(label)
        _, host, path, cap = row
        raw = tls = None
        try:
            raw = socket.create_connection((host,443),timeout=self.budget.left())
            ctx = ssl.create_default_context()
            ctx.set_alpn_protocols(['http/1.1'])
            tls = ctx.wrap_socket(raw,server_hostname=host)
            tls.settimeout(self.budget.left())
            tls.sendall(('GET '+path+' HTTP/1.1\r\nHost: '+host+
                         '\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n').encode('ascii'))
            header = bytearray()
            while not header.endswith(b'\r\n\r\n'):
                need(len(header) < HEADER_CAP and self.budget.headers < 9*HEADER_CAP, 'HEADER_LIMIT')
                tls.settimeout(self.budget.left())
                byte = tls.recv(1)
                need(len(byte) == 1, 'HEADER_EOF')
                header.extend(byte)
                self.budget.headers += 1
            size = parse_header(bytes(header), cap)
            need(self.budget.used+size <= BODY_CAP, 'BODY_TOTAL')
            sha = hashlib.sha256()
            with destination.open('xb') as stream:
                left = size
                while left:
                    tls.settimeout(self.budget.left())
                    data = tls.recv(min(left,65536))
                    need(bool(data), 'BODY_EOF')
                    self.budget.body(len(data))
                    stream.write(data)
                    sha.update(data)
                    left -= len(data)
                stream.flush()
            self.budget.receipts.append({'label':label,'size':size,'sha256':sha.hexdigest()})
            return destination
        finally:
            # A close failure remains a failure, never an authenticated receipt.
            try:
                if tls is not None:
                    tls.close()
            finally:
                if raw is not None:
                    raw.close()

def parse_header(raw, cap):
    need(len(raw) <= HEADER_CAP and raw.endswith(b'\r\n\r\n'), 'HEADER_LIMIT')
    lines = raw[:-4].split(b'\r\n')
    need(re.fullmatch(rb'HTTP/1\.[01] 200 [\x20-\x7e]*',lines[0]) is not None, 'HTTP_NOT_DIRECT_200')
    fields = {}
    for line in lines[1:]:
        name, sep, value = line.partition(b':')
        name = name.lower()
        need(sep and re.fullmatch(rb'[a-z0-9-]+',name) is not None and name not in fields and
             all(32 <= x <= 126 or x == 9 for x in value), 'HEADER_FORMAT')
        fields[name] = value.strip()
    need(b'location' not in fields and b'transfer-encoding' not in fields and
         fields.get(b'content-encoding',b'identity') == b'identity', 'HTTP_UNSUPPORTED')
    length = fields.get(b'content-length',b'')
    need(re.fullmatch(rb'[0-9]{1,10}',length) is not None, 'HTTP_LENGTH')
    size = int(length)
    need(0 < size <= cap, 'BODY_LIMIT')
    return size

def key_check(raw, role):
    need(len(raw) <= 65536, 'KEY_STATUS_LIMIT')
    expected, signer = KEYS[role]
    pending, primary, subs, seen = None, [], [], set()
    for line in raw.decode('ascii').splitlines():
        cols = line.split(':')
        kind = cols[0]
        if kind in ('pub','sub'):
            need(pending is None, 'KEY_FORMAT')
            pending = kind
        elif kind == 'fpr':
            need(pending is not None and len(cols) > 9 and re.fullmatch(r'[0-9A-F]{40}',cols[9]) and cols[9] not in seen, 'KEY_FORMAT')
            seen.add(cols[9])
            (primary if pending == 'pub' else subs).append(cols[9])
            pending = None
        else:
            need(kind in ('uid','uat','rvk'), 'KEY_FORMAT')
    need(pending is None and primary == [expected] and len(subs) <= 16 and
         subs == ([] if signer == expected else [signer]), 'KEY_PIN')

def signature_check(raw, origin, returncode=0):
    need(returncode == 0 and len(raw) <= 65536 and origin in ROLES, 'SIGNATURE_FAILED')
    allowed = {KEYS[r][0]:KEYS[r][1] for r in ROLES[origin]}
    groups, current, plaintext = [], None, False
    for line in raw.decode('ascii').splitlines():
        need(len(line) <= 2048, 'STATUS_FORMAT')
        f = line.split()
        need(len(f) >= 2 and f[0] == '[GNUPG:]', 'STATUS_FORMAT')
        kind = f[1]
        if kind == 'PLAINTEXT':
            need(not plaintext and current is None and not groups and len(f) in (4,5) and f[2] == '74' and f[3].isdigit(), 'STATUS_FORMAT')
            plaintext = True
        elif kind == 'NEWSIG':
            need(len(f) in (2,3) and (len(f) == 2 or len(f[2]) <= 1024), 'STATUS_FORMAT')
            if current is not None:
                groups.append(current)
            current = {}
            need(len(groups) < 8, 'SIGNATURE_COUNT')
        elif kind in ('KEY_CONSIDERED','SIG_ID'):
            need(3 <= len(f) <= 6, 'STATUS_FORMAT')
        else:
            need(current is not None, 'SIGNATURE_PAIR')
            if kind == 'GOODSIG':
                need('good' not in current and len(f) >= 3 and re.fullmatch(r'(?:[0-9A-F]{16}|[0-9A-F]{40})',f[2]), 'SIGNATURE_PAIR')
                current['good'] = f[2]
            elif kind == 'VALIDSIG':
                need('valid' not in current and len(f) in (11,12) and re.fullmatch(r'[0-9A-F]{40}',f[2]) and
                     re.fullmatch(r'[0-9:-]{1,40}',f[3]) and
                     all(re.fullmatch(r'(?:[0-9]{1,40}|[0-9T:+-]{1,40})',v) and (v.isdigit() or 'T' in v) for v in f[4:6]) and
                     all(v.isdigit() for v in f[6:10]) and re.fullmatch(r'[0-9A-F]{2}',f[10]), 'STATUS_FORMAT')
                primary = f[11] if len(f) == 12 else f[2]
                need(primary in allowed and f[2] == allowed[primary], 'SIGNER_PIN')
                current['valid'] = (primary,f[2])
            else:
                raise Stop('UNEXPECTED_SIGNATURE_STATUS')
    if current is not None:
        groups.append(current)
    need(len(groups) == len(allowed), 'SIGNATURE_COUNT')
    seen = set()
    for group in groups:
        need(set(group) == {'good','valid'}, 'SIGNATURE_PAIR')
        primary, signer = group['valid']
        need(group['good'] in (signer,signer[-16:]) and primary not in seen, 'SIGNATURE_PAIR')
        seen.add(primary)
    need(seen == set(allowed), 'SIGNER_PIN')

class Commands:
    """Only verification tools; child outputs are kernel-file-limited, never logged."""
    def __init__(self, budget, scratch):
        self.budget, self.scratch, self.number = budget, scratch, 0
    def run(self, argv):
        need(argv[0] in ('/usr/bin/gpg','/usr/bin/gpgv'), 'TOOL_SCOPE')
        self.number += 1
        need(self.number <= 12, 'COMMAND_COUNT')
        def limits():
            resource.setrlimit(resource.RLIMIT_FSIZE,(MIB,MIB))
            resource.setrlimit(resource.RLIMIT_AS,(512*MIB,512*MIB))
        out, err = self.scratch/('out'+str(self.number)), self.scratch/('err'+str(self.number))
        child = None
        with out.open('xb') as stdout, err.open('xb') as stderr:
            try:
                oldmask = signal.pthread_sigmask(signal.SIG_BLOCK,{signal.SIGTERM})
                try:
                    child = subprocess.Popen(argv,stdin=subprocess.DEVNULL,stdout=stdout,stderr=stderr,
                                             env={'PATH':'/usr/bin:/bin','LC_ALL':'C','GNUPGHOME':str(self.scratch)},
                                             close_fds=True,start_new_session=False,preexec_fn=limits)
                finally:
                    signal.pthread_sigmask(signal.SIG_SETMASK,oldmask)
                try:
                    code = child.wait(timeout=self.budget.left())
                except subprocess.TimeoutExpired as exc:
                    raise Stop('TOOL_DEADLINE') from exc
            finally:
                if child is not None:
                    uncertain = False
                    try:
                        alive = child.poll() is None
                    except BaseException:
                        alive, uncertain = True, True
                    if alive:
                        try:
                            child.kill()
                        except BaseException:
                            uncertain = True
                        try:
                            child.wait(timeout=2)
                        except BaseException:
                            uncertain = True
                    need(not uncertain, 'TOOL_CLEANUP')
        self.budget.left()
        need(out.stat().st_size <= 65536 and err.stat().st_size <= 65536, 'TOOL_OUTPUT_LIMIT')
        return code,out.read_bytes()

def fields(text):
    """Strict Debian control stanza; signed metadata is still bounded input."""
    result, last = {}, None
    for line in text.splitlines():
        need(len(line) <= 65536 and '\x00' not in line, 'CONTROL_LINE')
        if line.startswith((' ','\t')):
            need(last is not None, 'CONTROL_FORMAT')
            result[last] += '\n'+line
        else:
            key, sep, value = line.partition(':')
            need(sep and re.fullmatch(r'[A-Za-z0-9-]+',key) and key not in result, 'CONTROL_FORMAT')
            result[key], last = value.strip(), key
    return result

def release_check(raw, origin, now):
    need(0 < len(raw) <= 524288, 'RELEASE_LIMIT')
    f = fields(raw.decode('utf-8'))
    need(origin in ROLES, 'RELEASE_IDENTITY')
    # Security's Components token is updates/main, but its signed SHA256 index
    # path is still main/binary-amd64/Packages.xz. Never derive a URL from it.
    component = 'main' if origin == 'main' else 'updates/main'
    need(f.get('Origin') == 'Debian' and f.get('Codename') == ('bookworm' if origin == 'main' else 'bookworm-security') and
         'amd64' in f.get('Architectures','').split() and component in f.get('Components','').split(), 'RELEASE_IDENTITY')
    def parsed(name):
        try:
            value = email.utils.parsedate_to_datetime(f[name])
            need(value.tzinfo is not None, 'RELEASE_DATE')
            return value.astimezone(dt.timezone.utc)
        except (KeyError,ValueError,TypeError,OverflowError) as exc:
            raise Stop('RELEASE_DATE') from exc
    date = parsed('Date')
    need(date <= now, 'RELEASE_FUTURE')
    expiry = parsed('Valid-Until') if 'Valid-Until' in f else None
    need((expiry is not None or origin == 'main') and (expiry is None or expiry > now), 'RELEASE_EXPIRED')
    candidates = []
    for line in f.get('SHA256','').splitlines():
        parts = line.split()
        if not parts:
            continue
        need(len(parts) == 3 and re.fullmatch(HEX,parts[0]) and re.fullmatch(r'[0-9]{1,12}',parts[1]), 'RELEASE_HASH_FORMAT')
        if parts[2] == INDEX_PATH:
            candidates.append((int(parts[1]),parts[0]))
    need(len(candidates) == 1 and 0 < candidates[0][0] <= 16*MIB, 'INDEX_DESCRIPTOR')
    return {'size':candidates[0][0],'sha256':candidates[0][1],
            'date':date.isoformat(),'valid_until':expiry.isoformat() if expiry else 'ABSENT'}

def recipe_check(recipe):
    need(recipe.get('schema') == 1 and recipe.get('executable') is False and
         recipe.get('runtime_authority') is False and recipe.get('ap2_six_cases') == 'NOT_RUN', 'RECIPE_SCOPE')
    rows = recipe.get('candidates')
    need(type(rows) is list and len(rows) == 35, 'RECIPE_COUNT')
    seen = set()
    for r in rows:
        need(set(r) == {'package','version','architecture','filename','size','sha256','origin','historical_index_sha256'} and
             r['origin'] in ROLES and r['architecture'] in ('all','amd64') and
             re.fullmatch(r'[a-z0-9][a-z0-9+.-]{0,127}',r['package']) and
             type(r['version']) is str and 0 < len(r['version']) <= 128 and
             type(r['filename']) is str and r['filename'].startswith('pool/main/' if r['origin'] == 'main' else 'pool/updates/main/') and
             '..' not in r['filename'].split('/') and
             type(r['size']) is int and 0 < r['size'] <= 32*MIB and
             re.fullmatch(HEX,r['sha256']) and re.fullmatch(HEX,r['historical_index_sha256']), 'RECIPE_DESCRIPTOR')
        identity = (r['origin'],r['package'],r['version'],r['architecture'])
        need(identity not in seen, 'RECIPE_DUPLICATE')
        seen.add(identity)
    return rows

def index_check(path, descriptor, rows, budget):
    need(path.stat().st_size == descriptor['size'] and digest(path.read_bytes()) == descriptor['sha256'], 'INDEX_HASH')
    wanted = {(r['package'],r['version'],r['architecture']):r for r in rows}
    found, total, buffer = set(), 0, bytearray()
    decoder = lzma.LZMADecompressor(format=lzma.FORMAT_XZ,memlimit=128*MIB)
    def stanza(raw):
        if not raw:
            return
        f = fields(raw.decode('utf-8'))
        identity = (f.get('Package'),f.get('Version'),f.get('Architecture'))
        if identity in wanted:
            r = wanted[identity]
            need(identity not in found and f.get('Filename') == r['filename'] and
                 f.get('Size') == str(r['size']) and f.get('SHA256') == r['sha256'], 'PACKAGE_DESCRIPTOR_MISMATCH')
            found.add(identity)
    with path.open('rb') as stream:
        while True:
            chunk = stream.read(65536) if decoder.needs_input else b''
            if not chunk and decoder.needs_input:
                break
            data = decoder.decompress(chunk,max_length=65536)
            total += len(data)
            need(total <= 512*MIB, 'INDEX_EXPANSION')
            buffer.extend(data)
            while b'\n\n' in buffer:
                raw, _, rest = buffer.partition(b'\n\n')
                stanza(raw)
                buffer = bytearray(rest)
            need(len(buffer) <= MIB, 'STANZA_LIMIT')
            budget.left()
            if decoder.eof:
                need(not decoder.unused_data and not stream.read(1), 'XZ_TRAILING')
                break
    need(decoder.eof, 'XZ_TRUNCATED')
    stanza(bytes(buffer).strip(b'\n'))
    need(found == set(wanted), 'STOP_PIN_SET_CHANGED')
    return len(found)

def verify(recipe, fetch, commands, output, scratch, budget, utc):
    rows = recipe_check(recipe)
    keyrings = {}
    for label in KEYS:
        source = fetch.get(label,output/(label+'.asc'))
        if label == 'trixie_key':
            need(digest(source.read_bytes()) == TRIXIE_SHA, 'TRIXIE_RAW_PIN')
        code, raw = commands.run(['/usr/bin/gpg','--no-options','--batch','--no-autostart','--no-auto-key-retrieve',
                                  '--with-colons','--with-fingerprint','--with-subkey-fingerprint','--show-keys',str(source)])
        need(code == 0, 'KEY_TOOL_FAILED')
        key_check(raw,label)
        target = scratch/(label+'.gpg')
        code, _ = commands.run(['/usr/bin/gpg','--no-options','--batch','--no-autostart','--dearmor','--output',str(target),str(source)])
        need(code == 0 and 0 < target.stat().st_size <= 131072, 'KEY_DEARMOR')
        keyrings[label] = target
    releases = {}
    # Authenticate BOTH Releases (including dates/expiry) before ANY index GET.
    for origin in ROLES:
        source = fetch.get(origin+'_release',output/(origin+'_InRelease'))
        plaintext = scratch/(origin+'_Release')
        argv = ['/usr/bin/gpgv','--homedir',str(scratch),'--status-fd','1','--output',str(plaintext)]
        for role in ROLES[origin]:
            argv += ['--keyring',str(keyrings[role])]
        code, status = commands.run(argv+[str(source)])
        signature_check(status,origin,code)
        releases[origin] = release_check(plaintext.read_bytes(),origin,utc())
    matched = {}
    for origin in ROLES:
        # Expiry can elapse between validation and acquisition; never use stale evidence.
        for value in releases.values():
            need(value['valid_until'] == 'ABSENT' or dt.datetime.fromisoformat(value['valid_until']) > utc(), 'RELEASE_EXPIRED')
        source = fetch.get(origin+'_index',output/(origin+'_Packages.xz'))
        matched[origin] = index_check(source,releases[origin],[r for r in rows if r['origin'] == origin],budget)
    for value in releases.values():
        need(value['valid_until'] == 'ABSENT' or dt.datetime.fromisoformat(value['valid_until']) > utc(), 'RELEASE_EXPIRED')
    return {'releases':releases,'matched':matched}

def main():
    report = {'status':'STOP_NO_RETRY','reason':'INCOMPLETE','scope':'METADATA_ONLY_RUNTIME_UNPROVEN',
              'ap2_six_cases':'NOT_RUN','native_authority':False,'cleanup':False,
              'sha':os.environ.get('GITHUB_SHA'),'run':os.environ.get('GITHUB_RUN_ID'),
              'attempt':os.environ.get('GITHUB_RUN_ATTEMPT')}
    output, budget = Path('runtime-metadata-evidence'), Budget()
    def interrupted(*_):
        signal.signal(signal.SIGTERM,signal.SIG_IGN)
        raise Stop('OUTER_DEADLINE')
    signal.signal(signal.SIGTERM,interrupted)
    owned = False
    try:
        need(platform.system() == 'Linux' and platform.machine() == 'x86_64' and
             'VERSION_ID="24.04"' in Path('/etc/os-release').read_text() and
             os.environ.get('GITHUB_RUN_ATTEMPT') == '1' and
             re.fullmatch(r'[0-9a-f]{40}',report['sha'] or '') and
             re.fullmatch(r'[1-9][0-9]{0,19}',report['run'] or ''), 'EXECUTION_CONTEXT')
        tools = {}
        for tool in ('/usr/bin/gpg','/usr/bin/gpgv'):
            need(os.access(tool,os.X_OK), 'MISSING_TOOL')
            tools[tool] = digest(Path(tool).read_bytes())
        recipe = json.loads(Path(__file__).with_name('p1r_runtime_recipe.json').read_text(),object_pairs_hook=unique)
        output.mkdir(mode=0o700)  # existing or foreign output is never reused
        owned = True
        with tempfile.TemporaryDirectory(prefix='p1r-metadata-') as private:
            scratch = Path(private)
            result = verify(recipe,Fetch(budget),Commands(budget,scratch),output,scratch,budget,
                            lambda:dt.datetime.now(dt.timezone.utc))
        accepted = dt.datetime.now(dt.timezone.utc)
        for value in result['releases'].values():
            need(value['valid_until'] == 'ABSENT' or dt.datetime.fromisoformat(value['valid_until']) > accepted, 'RELEASE_EXPIRED')
        budget.left()
        report.update(result,tools=tools,status='FIXED_METADATA_MEMBERSHIP_CONFIRMED_RUNTIME_UNPROVEN',reason='NONE',cleanup=True,accepted_utc=accepted.isoformat())
    except Stop as exc:
        report['status'] = 'STOP_NO_RETRY'
        report['reason'] = str(exc) if re.fullmatch(r'[A-Z0-9_]{1,64}',str(exc)) else 'INTERNAL_STOP'
    except BaseException:
        # No untrusted GPG, HTTP, control text, tokens or exception strings logged.
        report.update(status='STOP_NO_RETRY',reason='VERIFICATION_OR_CLEANUP_FAILED')
    finally:
        if owned:
            report.update(requested=sorted(budget.requests),body_bytes=budget.used,header_bytes=budget.headers,receipts=budget.receipts)
            report['ended_utc'] = dt.datetime.now(dt.timezone.utc).isoformat()
            encoded = (json.dumps(report,sort_keys=True,indent=2)+'\n').encode('ascii')
            need(len(encoded) <= MIB, 'DIAGNOSTIC_LIMIT')
            # Exact closed output namespace, no recursive traversal or foreign cleanup.
            allowed = {r[0]+('.asc' if r[0] in KEYS else '_unused') for r in ENDPOINTS}
            allowed |= {o+'_InRelease' for o in ROLES}|{o+'_Packages.xz' for o in ROLES}
            entries = list(output.iterdir())
            need(all(p.name in allowed and p.is_file() and not p.is_symlink() for p in entries), 'ARTIFACT_SCOPE')
            if sum(p.stat().st_size for p in entries)+len(encoded)+ZIP_RESERVE > ARTIFACT_CAP:
                # Fail and retain only bounded diagnostic; never upload an overbudget set.
                report.update(status='STOP_NO_RETRY',reason='ARTIFACT_LIMIT')
                for p in entries:
                    p.unlink()
                encoded = (json.dumps(report,sort_keys=True,indent=2)+'\n').encode('ascii')
            with (output/'result.json').open('xb') as stream:
                stream.write(encoded)
            print(encoded.decode('ascii'),end='')
    return 0 if report['status'].startswith('FIXED_METADATA') else 78

if __name__ == '__main__':
    raise SystemExit(main())
