"""Fixed one-shot static inventory. Target files are DATA, never executed.

HTTP transport is preserved from reviewed P1R; new archive scanner never
extracts a target rootfs. GitHub control/signature tools are runner tools.
"""
from contextlib import contextmanager
import datetime as dt
import gzip
import hashlib
import io
import json
import lzma
import os
from pathlib import Path
import re
import resource
import runpy
import shutil
import signal
import socket
import ssl
import stat
import struct
import subprocess
import sys
import tempfile
import time
import urllib.parse
import zipfile

BASE=Path(__file__).resolve().parent
REPO=BASE.parents[1]
USED=0
CONTRACT=None
SPEC=None
REPORT={"scope":"STATIC_IMAGE_AND_PIP_CONTENTS_ONLY_RUNTIME_UNPROVEN",
        "status":"STOP_HOLD","target_executions":0,"installs_builds_docker":0,
        "runtime":"UNPROVEN","phase2_gate":"UNPROVEN","phase2b":"HOLD"}

def need(ok, reason):
    if not ok: raise ValueError(reason)

def encoded(obj):
    return json.dumps(obj,sort_keys=True,ensure_ascii=True,allow_nan=False,separators=(",",":")).encode()

def sha(raw): return hashlib.sha256(raw).hexdigest()

def document(raw):
    def pairs(items):
        out={}
        for k,v in items:
            need(k not in out,"DUPLICATE_JSON")
            out[k]=v
        return out
    def bad(_): raise ValueError("NONFINITE_JSON")
    out=json.loads(raw.decode("utf8"),object_pairs_hook=pairs,parse_constant=bad)
    need(type(out) is dict,"JSON_OBJECT")
    encoded(out)
    return out

def url_parts(url):
    need(len(url) <= 8192 and all(32 < ord(c) < 127 for c in url), "URL")
    u = urllib.parse.urlsplit(url)
    need(u.scheme == "https" and u.username is None and u.password is None and
         u.port is None and not u.fragment and u.hostname, "URL")
    return u


def config_redirect_url(url):
    u = url_parts(url)
    rule = CONTRACT["oci"]["config_redirect"]
    need(u.netloc == rule["host"] and u.path == rule["path"] and u.query,
         "CONFIG_REDIRECT_TARGET")
    return url


def request(url, cap, *, token=None, method="GET", data=b"", redirect=False,
            config_redirect=False):
    """Direct TLS HTTP/1.1, no proxy/retry/redirect. Bound header before parsing."""
    global USED
    u = url_parts(url)
    head_urls = set(CONTRACT["gem_head_urls"].values())
    need(method in ("GET", "HEAD", "POST"), "METHOD")
    need((method == "HEAD") == (url in head_urls), "GEM_HEAD_ONLY")
    need(method != "POST" or url == CONTRACT["refs_url"], "POST_TARGET")
    need(url in CONTRACT["metadata_urls"] or redirect or config_redirect, "UNAPPROVED_URL")
    need(not (redirect and config_redirect), "REDIRECT_ROLE")
    if config_redirect:
        config_redirect_url(url)
        need(token is None and not data and method == "GET", "CONFIG_CREDENTIAL_STRIPPING")
    if redirect:
        need(re.fullmatch(CONTRACT["artifact_redirect_host_regex"], u.hostname) is not None,
             "ARTIFACT_REDIRECT_HOST")
        need(token is None and method == "GET", "CREDENTIAL_REDIRECT")
    need(0 <= cap <= CONTRACT["body_limit"] - USED and
         (method == "HEAD" or cap > 0), "BODY_BUDGET")
    deadline = time.monotonic() + 45
    context = ssl.create_default_context()
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    with socket.create_connection((u.hostname, 443), timeout=5) as plain:
        with context.wrap_socket(plain, server_hostname=u.hostname) as conn:
            def receive(n):
                remaining = deadline - time.monotonic()
                need(remaining > 0, "RESPONSE_TIMEOUT")
                conn.settimeout(min(5, remaining))
                return conn.recv(n)

            path = u.path + ("?" + u.query if u.query else "")
            headers = {"Host": u.hostname, "User-Agent": "issue73-p1s-static-inventory",
                       "Connection": "close", "Accept-Encoding": "identity",
                       "Accept": "application/json, application/vnd.oci.image.index.v1+json, "
                                 "application/vnd.oci.image.manifest.v1+json, "
                                 "application/vnd.docker.distribution.manifest.list.v2+json, "
                                 "application/vnd.docker.distribution.manifest.v2+json"}
            if token is not None:
                need(u.hostname in ("api.github.com", "registry-1.docker.io"), "AUTH_HOST")
                need(re.fullmatch(r"[A-Za-z0-9_.~+/=-]{1,16384}", token) is not None, "TOKEN")
                headers["Authorization"] = "Bearer " + token
            if data:
                headers.update({"Content-Type": "application/json", "Content-Length": str(len(data))})
            conn.sendall((method + " " + path + " HTTP/1.1\r\n" +
                          "".join(k + ": " + v + "\r\n" for k, v in headers.items()) +
                          "\r\n").encode("ascii") + data)
            head = bytearray()
            while not head.endswith(b"\r\n\r\n"):
                need(len(head) < 8192, "HEADER_LIMIT")
                part = receive(1)
                need(part, "HEADER_EOF")
                head.extend(part)
            lines = bytes(head).decode("iso-8859-1").split("\r\n")
            match = re.fullmatch(r"HTTP/1\.[01] ([0-9]{3}) [^\r\n]*", lines[0])
            need(match is not None, "HTTP_STATUS")
            status = int(match[1])
            parsed = {}
            for line in lines[1:-2]:
                key, colon, value = line.partition(":")
                need(colon and re.fullmatch(r"[A-Za-z0-9-]+", key), "HEADER_SYNTAX")
                key = key.lower()
                need(not any(ord(c) < 32 for c in value.strip()), "HEADER_SYNTAX")
                need(key not in parsed or key not in ("location", "content-length",
                     "transfer-encoding", "content-encoding"), "HEADER_DUPLICATE")
                parsed.setdefault(key, value.strip())
            need(parsed.get("content-encoding", "identity") == "identity", "ENCODING")
            need(not ("content-length" in parsed and "transfer-encoding" in parsed), "FRAMING")
            if "content-length" in parsed:
                need(re.fullmatch(r"[0-9]{1,16}", parsed["content-length"]), "CONTENT_LENGTH")
            if method == "HEAD":
                # A HEAD Content-Length describes a prospective representation.
                # Never read it as a response body or fetch a .gem with GET.
                return status, parsed, b""
            body = bytearray()

            def take(n):
                global USED
                need(n <= cap - len(body) and USED + n <= CONTRACT["body_limit"], "BODY_LIMIT")
                result = bytearray()
                while len(result) < n:
                    piece = receive(min(n - len(result), 65536))
                    need(piece, "BODY_EOF")
                    USED += len(piece)
                    result.extend(piece)
                return bytes(result)

            def line():
                result = bytearray()
                while not result.endswith(b"\r\n"):
                    need(len(head) + len(result) < 8192, "TRAILER_LIMIT")
                    piece = receive(1)
                    need(piece, "CHUNK_EOF")
                    result.extend(piece)
                head.extend(result)
                return bytes(result)

            if "transfer-encoding" in parsed:
                need(parsed["transfer-encoding"] == "chunked", "TRANSFER_ENCODING")
                for _ in range(20000):
                    chunk = line()
                    need(re.fullmatch(rb"[0-9a-fA-F]{1,8}\r\n", chunk) is not None, "CHUNK")
                    size = int(chunk, 16)
                    if size == 0:
                        need(line() == b"\r\n", "TRAILERS")
                        break
                    body.extend(take(size))
                    need(receive(1) == b"\r" and receive(1) == b"\n", "CHUNK_CRLF")
                else:
                    raise ValueError("CHUNK_COUNT")
            elif "content-length" in parsed:
                need(re.fullmatch(r"[0-9]{1,16}", parsed["content-length"]), "CONTENT_LENGTH")
                body.extend(take(int(parsed["content-length"])))
            else:
                raise ValueError("UNKNOWN_BODY_LENGTH")
            need(USED <= CONTRACT["body_limit"], "BODY_BUDGET")
            return status, parsed, bytes(body)


def get(url, cap, token=None):
    status, headers, raw = request(url, cap, token=token)
    need(status == 200, "METADATA_HTTP")
    return raw


class Budget:
    def __init__(self, spec, spool_dir=None):
        self.spec=spec; self.spool_dir=spool_dir; self.expanded=0; self.entries=0; self.written=0
        self.record()
    def record(self):
        REPORT["resource_counters"]={"expanded_bytes":self.expanded,"entries":self.entries,
                                     "managed_write_reservations":self.written}
    def expand(self,n):
        need(type(n) is int and n>=0 and self.expanded+n<=self.spec['expanded_limit'],'EXPANSION_LIMIT')
        self.expanded+=n; self.record()
    def entry(self):
        self.entries+=1; self.record(); need(self.entries<=self.spec['entry_count'],'ENTRY_COUNT')
    def reserve(self,n):
        need(n>=0 and self.written+n<=self.spec['managed_write_limit'],'MANAGED_WRITE_BUDGET')
        self.written+=n; self.record()
    def write(self,path,raw):
        self.reserve(len(raw))
        path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
        with path.open('xb') as out: out.write(raw)

class ExpandedReader:
    def __init__(self,stream,budget):
        self.stream=stream; self.budget=budget; self.digest=hashlib.sha256();self.count=0
    def read(self,n):
        need(0<=n<=65536,'READ_SIZE')
        raw=self.stream.read(min(n,self.budget.spec['expanded_limit']-self.budget.expanded+1))
        self.budget.expand(len(raw)); self.digest.update(raw);self.count+=len(raw)
        return raw
    def exact(self,n):
        out=bytearray()
        while len(out)<n:
            part=self.read(min(65536,n-len(out))); need(part,'ARCHIVE_EOF'); out.extend(part)
        return bytes(out)

def path_name(raw, allow_root=False):
    need(type(raw) is str and len(raw.encode('utf8'))<=SPEC['path_limit'] and '\x00' not in raw and
         all(ord(c)>=32 and ord(c)!=127 for c in raw),'ARCHIVE_PATH')
    while raw.startswith('./'): raw=raw[2:]
    raw=raw.rstrip('/')
    if raw in ('','.'):
        need(allow_root,'EMPTY_PATH'); return ''
    need(not raw.startswith('/') and all(x not in ('','..','.') for x in raw.split('/')),'ARCHIVE_PATH')
    return raw

def octal(raw):
    text=raw.rstrip(b'\0 ').lstrip(b' ')
    need(not text or re.fullmatch(rb'[0-7]+',text),'TAR_NUMBER')
    return int(text or b'0',8)

def pax_fields(raw):
    out={};offset=0
    while offset<len(raw):
        sep=raw.find(b' ',offset); need(sep>offset,'PAX_LENGTH')
        digits=raw[offset:sep]; need(re.fullmatch(rb'[0-9]{1,6}',digits),'PAX_LENGTH')
        n=int(digits); need(n>sep-offset+2 and offset+n<=len(raw),'PAX_LENGTH')
        record=raw[sep+1:offset+n]; need(record.endswith(b'\n'),'PAX_RECORD')
        k,eq,v=record[:-1].partition(b'='); need(eq and k not in out,'PAX_DUPLICATE')
        key=k.decode('ascii'); need(key in ('path','linkpath','mtime','atime','ctime','uid','gid','uname','gname'),'UNSUPPORTED_PAX')
        out[k]=v;offset+=n
    return out

def progress(stage, **fields):
    """Controlled parser labels plus bounded public archive identity, never URLs."""
    current=REPORT.setdefault('progress',{})
    current['stage']=stage
    for key,value in fields.items():
        need(key in ('entry_path','entry_path_sha256','entry_size','entry_bytes_read',
                     'compressed_digest_verified','requested_spool_bytes'),'DIAGNOSTIC_FIELD')
        current[key]=value


def entry_identity(name,size):
    # Canonical tar path only. Do not expose URL-like/query-bearing names.
    portable=bool(re.fullmatch(r'[A-Za-z0-9_./+@=-]{1,4096}',name))
    progress('TAR_ENTRY',entry_path=name if portable else '[REDACTED_NONPORTABLE_PATH]',
             entry_path_sha256=sha(name.encode('utf8')),entry_size=size,entry_bytes_read=0)


@contextmanager
def elf_spool(budget,size,enabled):
    """One private opaque file, reserved before creation; no rootfs extraction."""
    if not enabled:
        yield None
        return
    progress('ELF_SPOOL_RESERVE',requested_spool_bytes=size)
    need(type(size) is int and 64<=size<=budget.spec['entry_limit'],'ELF_FILE_BOUND')
    soft,_=resource.getrlimit(resource.RLIMIT_FSIZE)
    need(soft==resource.RLIM_INFINITY or size<=soft,'ELF_SPOOL_OS_LIMIT')
    budget.reserve(size)
    stream=None
    try:
        stream=tempfile.TemporaryFile(mode='w+b',prefix='p1s-elf-',dir=budget.spool_dir)
        info=os.fstat(stream.fileno())
        need(stat.S_ISREG(info.st_mode) and info.st_uid==os.geteuid() and
             info.st_mode&0o077==0,'ELF_SPOOL_PRIVATE')
        yield stream
    except BaseException as primary:
        if stream is not None:
            try:stream.close()
            except BaseException:
                REPORT.setdefault('progress',{})['cleanup_uncertain']=True
                primary.add_note('ELF_SPOOL_CLOSE_UNCERTAIN')
        raise
    else:
        progress('ELF_SPOOL_CLOSE')
        # A close error is STOP, never retry a potentially reused descriptor.
        try:stream.close()
        except BaseException:
            REPORT.setdefault('progress',{})['cleanup_uncertain']=True
            raise


def elf_metadata(source,size=None):
    """Selective bounded reads from seekable DATA, never load/execute the ELF.

    Input can be a bytes fixture or a private spool. Each read is <=1MiB;
    PHDR/dynamic/string bounds remain unchanged. Whole-file size <=128MiB.
    """
    if type(source) in (bytes,bytearray):
        need(size is None or size==len(source),'ELF_INPUT_SIZE')
        size=len(source);source=io.BytesIO(source)
    need(type(size) is int and 64<=size<=SPEC['entry_limit'],'ELF_FILE_BOUND')
    def read_at(offset,length):
        need(type(offset) is int and type(length) is int and 0<=offset<=size and
             0<=length<=1048576 and length<=size-offset,'ELF_READ_RANGE')
        source.seek(offset);raw=source.read(length)
        need(type(raw) is bytes and len(raw)==length,'ELF_TRUNCATED')
        return raw
    header=read_at(0,64)
    need(header[:7]==b"\x7fELF\x02\x01\x01" and struct.unpack_from('<I',header,20)[0]==1 and
         struct.unpack_from('<H',header,52)[0]==64,'ELF_FORMAT')
    need(struct.unpack_from('<H',header,18)[0]==62,'ELF_MACHINE')
    off=struct.unpack_from('<Q',header,32)[0];width,count=struct.unpack_from('<HH',header,54)
    need(width==56 and count<=1024 and off<=size and width*count<=size-off,'ELF_PHDR')
    table=read_at(off,width*count);loads=[];dynamic=None;interp=None
    for i in range(count):
        kind,flags,start,va,pa,length,mem,align=struct.unpack_from('<IIQQQQQQ',table,i*width)
        need(start<=size and length<=size-start and va+mem<=2**64-1,'ELF_SEGMENT')
        if kind==1:
            need(mem>=length,'ELF_LOAD_SIZE');loads.append((va,start,length))
        if kind==2:
            need(dynamic is None and length<=1048576,'ELF_DYNAMIC');dynamic=(start,length)
        if kind==3:
            need(interp is None and 1<length<=4096,'ELF_INTERP')
            text=read_at(start,length)
            need(text[-1:]==b'\0' and b'\0' not in text[:-1],'ELF_INTERP')
            interp=text[:-1].decode('ascii')
            need(all(32<=ord(c)<127 for c in interp),'ELF_INTERP')
    needed=[];strings=None;labels={};ended=dynamic is None
    if dynamic:
        start,length=dynamic;need(length%16==0,'ELF_DYNAMIC_SIZE')
        data=read_at(start,length)
        for i in range(0,length,16):
            tag,val=struct.unpack_from('<qQ',data,i)
            if tag==0:ended=True;break
            if tag==1:needed.append(val)
            if tag in (5,10,14,15,29):
                need(tag not in labels,'ELF_DYNAMIC_DUPLICATE');labels[tag]=val
        need(ended and len(needed)<=256,'ELF_DYNAMIC_TERMINATOR')
        if needed or any(t in labels for t in (5,10,14,15,29)):
            need(5 in labels and 10 in labels and 0<labels[10]<=1048576 and
                 labels[5]+labels[10]<=2**64-1,'ELF_STRTAB')
            matches=[start+labels[5]-va for va,start,length in loads
                     if va<=labels[5] and labels[5]+labels[10]<=va+length]
            need(len(matches)==1,'ELF_STRTAB_MAPPING')
            strings=read_at(matches[0],labels[10])
    def text(index):
        need(strings is not None and index<len(strings),'ELF_STRING_INDEX')
        end=strings.find(b'\0',index);need(end>=0 and end-index<=4096,'ELF_STRING')
        value=strings[index:end].decode('ascii');need(all(32<=ord(c)<127 for c in value),'ELF_STRING')
        return value
    out={'class':'ELF64_LE_AMD64','needed':[text(x) for x in needed], 'interpreter':interp}
    for tag,key in ((14,'soname'),(15,'rpath'),(29,'runpath')):
        if tag in labels:out[key]=text(labels[tag])
    return out


def selected(path):
    return (path=='var/lib/dpkg/status' or
            (path.endswith('.gemspec') and ('/specifications/' in path)) or
            path.endswith('/pip-23.0.1-py3-none-any.whl') or
            path.endswith('/pip-23.0.1+dfsg-py3-none-any.whl') or
            path in ('usr/local/lib/ruby/3.3.0/rbconfig.rb','etc/ld.so.conf') or
            path.startswith('etc/ld.so.conf.d/'))

def scan_tar(stream,budget,vfs,contents):
    """Parse canonical USTAR/GNU/PAX data; apply whiteouts before layer entries.

    No filesystem extraction, device creation, chmod, eval or target execution.
    Symlinks are opaque metadata; traversal through a symlink is rejected.
    """
    reader=ExpandedReader(stream,budget); layer={};data={};white=[];opaque=[];pending={}
    while True:
        progress('TAR_HEADER',entry_path=None,entry_path_sha256=None,entry_size=None,entry_bytes_read=0)
        header=reader.exact(512)
        if header==bytes(512):
            need(reader.exact(512)==bytes(512),'TAR_END')
            while True:
                tail=reader.read(65536)
                if not tail:break
                need(not any(tail),'TAR_TRAILING_DATA')
            need(not pending and reader.count%512==0,'TAR_END_ALIGNMENT');break
        budget.entry()
        need(octal(header[148:156])==sum(header[:148])+8*32+sum(header[156:]),'TAR_CHECKSUM')
        need(header[257:263] in (b'ustar\0',b'ustar '),'TAR_MAGIC')
        size=octal(header[124:136])
        progress('TAR_HEADER_SIZE',entry_size=size)
        kind=header[156:157];name=header[:100].split(b'\0',1)[0]
        if header[257:263]==b'ustar\0':
            prefix=header[345:500].split(b'\0',1)[0]
            if prefix:name=prefix+b'/'+name
        link=header[157:257].split(b'\0',1)[0]
        if kind in (b'x',b'L',b'K'):
            entry_identity(path_name(name.decode('utf8')),size)
            progress('TAR_EXTENSION')
            need(size<=min(65536,SPEC['entry_limit']),'TAR_EXTENSION_LIMIT')
            raw=reader.exact(size);reader.exact((-size)%512)
            if kind==b'x':
                need(not pending,'TAR_EXTENSION_CHAIN');pending=pax_fields(raw)
            else:
                key=b'path' if kind==b'L' else b'linkpath'
                need(key not in pending and raw.endswith(b'\0'),'GNU_EXTENSION')
                pending[key]=raw[:-1]
            continue
        name=pending.get(b'path',name);link=pending.get(b'linkpath',link);pending={}
        name=path_name(name.decode('utf8'),allow_root=kind==b'5')
        entry_identity(name,size)
        need(size<=SPEC['entry_limit'],'TAR_ENTRY_LIMIT')
        need(kind in (b'0',b'\0',b'5',b'1',b'2'),'UNSUPPORTED_TAR_TYPE')
        need(kind in (b'0',b'\0') or size==0,'NONFILE_BODY')
        mode=octal(header[100:108]);need(mode<=0o7777,'TAR_MODE')
        h=hashlib.sha256();kept=bytearray();want=selected(name)
        need(not want or size<=4*1024**2,'SELECTED_DATA_LIMIT')
        first=reader.exact(min(size,65536)) if size else b''
        is_elf=first.startswith(b"\x7fELF")
        elf=None
        with elf_spool(budget,size,is_elf) as spool:
            left=size;raw=first
            while left:
                progress('ELF_SPOOL_WRITE' if is_elf else 'TAR_ENTRY_READ')
                h.update(raw)
                if want:kept.extend(raw)
                if spool is not None:need(spool.write(raw)==len(raw),'ELF_SPOOL_WRITE')
                left-=len(raw)
                progress('TAR_ENTRY_BODY',entry_bytes_read=size-left)
                if left:raw=reader.exact(min(left,65536))
            if spool is not None:
                progress('ELF_PARSE')
                spool.flush()
                need(spool.tell()==size,'ELF_SPOOL_SIZE')
                elf=elf_metadata(spool,size)
        progress('TAR_ENTRY_PADDING')
        pad=reader.exact((-size)%512);need(not any(pad),'TAR_PADDING')
        basename=name.rsplit('/',1)[-1];parent=name.rpartition('/')[0]
        if basename.startswith('.wh.'):
            need(kind in (b'0',b'\0') and size==0,'WHITEOUT_SHAPE')
            if basename=='.wh..wh..opq':opaque.append(parent)
            else:
                victim=basename[4:];need(victim and victim not in ('.','..'),'WHITEOUT_PATH')
                white.append((parent+'/' if parent else '')+victim)
            continue
        need(name not in layer or (kind==b'5' and layer[name]['type']=='dir'),'DUPLICATE_TAR_PATH')
        record={'type':{b'0':'file',b'\0':'file',b'5':'dir',b'1':'hardlink',b'2':'symlink'}[kind],
                'size':size,'mode':mode}
        if record['type']=='file':
            record['sha256']=h.hexdigest()
            if is_elf:record['elf']=elf
        if kind in (b'1',b'2'):
            target=link.decode('utf8');need(len(link)<=SPEC['path_limit'] and '\x00' not in target,'LINK_LIMIT')
            if kind==b'1':target=path_name(target)
            record['link']=target
        layer[name]=record
        if want:data[name]=bytes(kept)
    for victim in white:
        for k in list(vfs):
            if k==victim or k.startswith(victim+'/'):vfs.pop(k);contents.pop(k,None)
    for parent in opaque:
        for k in list(vfs):
            if not parent or k.startswith(parent+'/'):vfs.pop(k);contents.pop(k,None)
    for name,record in layer.items():
        for i in range(1,len(name.split('/'))):
            ancestor='/'.join(name.split('/')[:i]);existing=layer.get(ancestor,vfs.get(ancestor))
            need(existing is None or existing['type']=='dir','LINK_OR_FILE_TRAVERSAL')
        old=vfs.get(name)
        if old and old['type']=='dir' and record['type']!='dir':
            for k in list(vfs):
                if k.startswith(name+'/'):vfs.pop(k);contents.pop(k,None)
        vfs[name]=record;contents.pop(name,None)
        if name in data:contents[name]=data[name]
    for name,record in list(vfs.items()):
        if record['type']=='hardlink':
            target=record['link'];seen={name}
            while vfs.get(target,{}).get('type')=='hardlink':
                need(target not in seen,'HARDLINK_CYCLE');seen.add(target);target=vfs[target]['link']
            need(vfs.get(target,{}).get('type')=='file','HARDLINK_TARGET')
            vfs[name]=dict(vfs[target],hardlink=record['link'])
            if name in data or selected(name):
                need(target in contents,'HARDLINK_SELECTED_UNAVAILABLE');contents[name]=contents[target]
    return reader.digest.hexdigest()

def ar_data(raw):
    need(raw.startswith(b'!<arch>\n'),'AR_MAGIC');pos=8;members={}
    while pos<len(raw):
        need(pos+60<=len(raw),'AR_HEADER');head=raw[pos:pos+60];pos+=60
        need(head[58:]==b'`\n','AR_HEADER')
        name=head[:16].decode('ascii').strip().rstrip('/')
        need(name in ('debian-binary','control.tar.xz','control.tar.gz','data.tar.xz','data.tar.gz') and name not in members,'AR_MEMBER')
        digits=head[48:58].strip();need(re.fullmatch(rb'[0-9]{1,10}',digits),'AR_SIZE');size=int(digits)
        need(size<=SPEC['entry_limit'] and pos+size<=len(raw),'AR_BODY')
        members[name]=raw[pos:pos+size];pos+=size
        if size%2:need(raw[pos:pos+1]==b'\n','AR_PADDING');pos+=1
    need(pos==len(raw) and members.get('debian-binary')==b'2.0\n' and len(members)==3,'DEB_MEMBERS')
    paths=[k for k in members if k.startswith('data.tar.')];need(len(paths)==1,'DEB_DATA')
    key=paths[0];return key,members[key]

def pip_metadata(raw,budget):
    REPORT['progress']={'archive':'PIP_DEB_DATA','stage':'AR_PARSE'}
    key,data=ar_data(raw);vfs={};contents={}
    stream=lzma.LZMAFile(io.BytesIO(data)) if key.endswith('xz') else gzip.GzipFile(fileobj=io.BytesIO(data))
    with stream:scan_tar(stream,budget,vfs,contents)
    wheels=[(k,v) for k,v in contents.items() if k.endswith('.whl')];need(len(wheels)==1,'PIP_WHEEL_SET')
    name,wheel=wheels[0];total=0;metas=[]
    with zipfile.ZipFile(io.BytesIO(wheel)) as archive:
        entries=archive.infolist();need(len(entries)<=10000 and len({e.filename for e in entries})==len(entries),'WHEEL_ENTRIES')
        for entry in entries:
            path_name(entry.filename.rstrip('/'));need(not entry.flag_bits&1 and entry.compress_type in (0,8),'WHEEL_FORMAT')
            need(not stat.S_ISLNK(entry.external_attr>>16) and entry.file_size<=8*1024**2,'WHEEL_ENTRY')
            with archive.open(entry) as source:
                captured=bytearray();actual=0
                while True:
                    piece=source.read(65536)
                    if not piece:break
                    budget.expand(len(piece));actual+=len(piece);total+=len(piece)
                    need(total<=16*1024**2 and actual<=entry.file_size,'WHEEL_EXPANSION')
                    if entry.filename.endswith('.dist-info/METADATA'):
                        need(len(captured)+len(piece)<=262144,'PIP_METADATA_LIMIT');captured.extend(piece)
                need(actual==entry.file_size,'WHEEL_LENGTH')
                if captured:metas.append(bytes(captured))
    need(len(metas)==1,'PIP_METADATA_SET');text=metas[0].decode('utf8')
    need(re.findall(r'^Name: (.+)$',text,re.M)==['pip'] and re.findall(r'^Version: (.+)$',text,re.M)==['23.0.1'],'PIP_IDENTITY')
    return {'path':name,'size':len(wheel),'sha256':sha(wheel),'entry_count':len(entries),
            'expanded_bytes':total,'name':'pip','version':'23.0.1','executed':False}

def pinned(raw,blob):
    need(hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()==blob,'FIXED_SOURCE_BLOB')
    return raw

def configure(spec,bootstrap):
    global SPEC,CONTRACT,USED
    SPEC=spec;USED=bootstrap
    need(type(bootstrap) is int and 0<bootstrap<=262144,'BOOTSTRAP_LEDGER')
    o=spec['oci'];repo='https://api.github.com/repos/cuichangquan/ap2-mandate-verifier'
    CONTRACT={'body_limit':spec['body_limit'],'gem_head_urls':{},'metadata_urls':[],
              'refs_url':repo+'/git/refs','artifact_redirect_host_regex':spec['artifact_redirect_host_regex'],
              'oci':o}
    return repo

def allow(url):
    CONTRACT['metadata_urls'].append(url);return url

def fixed_get(url,cap,token=None):
    return get(allow(url),cap,token)

def blob_get(digest,size,token):
    url=SPEC['oci']['config_url_prefix']+digest
    status,headers,raw=request(allow(url),max(size,4096),token=token)
    if status==307:
        h=digest.removeprefix('sha256:')
        CONTRACT['oci']['config_redirect']={'host':'production.cloudfront.docker.com',
            'path':'/registry-v2/docker/registry/v2/blobs/sha256/'+h[:2]+'/'+h+'/data'}
        location=config_redirect_url(headers.get('location',''))
        status,headers,raw=request(location,size,config_redirect=True)
    need(status==200 and len(raw)==size and 'sha256:'+sha(raw)==digest,'FIXED_BLOB')
    return raw

def readiness(spec):
    need(sys.platform.startswith('linux') and spec['body_limit']==100663296 and
         spec['expanded_limit']==1073741824 and spec['entry_limit']==134217728 and spec['memory_limit']==536870912 and
         spec['managed_write_limit']==2147483648,'LIMIT_CONTRACT')
    for tool in ('bash','curl','timeout','gpg','gpgv','sha256sum','awk','xz','date','stat','head','mkfifo','jq','grep','cp','cat','mktemp','rm'):
        need(shutil.which(tool),'REQUIRED_TOOL')
    resource.setrlimit(resource.RLIMIT_AS,(spec['memory_limit'],spec['memory_limit']))
    need(resource.getrlimit(resource.RLIMIT_AS)==(spec['memory_limit'],)*2,'MEMORY_CONTROL')
    resource.setrlimit(resource.RLIMIT_FSIZE,(spec['entry_limit'],spec['entry_limit']))
    need(resource.getrlimit(resource.RLIMIT_FSIZE)==(spec['entry_limit'],)*2,'FILE_SIZE_CONTROL')
    resource.setrlimit(resource.RLIMIT_CPU,(380,380))
    signal.signal(signal.SIGALRM,lambda *_:(_ for _ in ()).throw(ValueError('DEADLINE')))
    signal.alarm(390)
    need(dt.datetime.now(dt.timezone.utc)<dt.datetime.fromisoformat(spec['security_valid_until'].replace('Z','+00:00')),'EXPIRED')

def signature_child_limits():
    # Preserve the original verifier's narrower per-file bound in its child.
    resource.setrlimit(resource.RLIMIT_FSIZE,(16*1024**2,16*1024**2))


def verify_saved(repo,token,work,budget):
    spec=SPEC['saved_artifact'];meta=document(fixed_get(spec['url'],16384,token))
    need(meta['id']==spec['id'] and meta['size_in_bytes']==spec['size_in_bytes'] and
         meta['digest']==spec['digest'] and meta['expires_at']==spec['expires_at'] and
         meta['expired'] is False and meta['workflow_run']['id']==38851173209 and
         meta['workflow_run']['head_sha']=='55dccb98507316044187e48843aef754cd0b5c57','SAVED_PROVENANCE')
    need(dt.datetime.now(dt.timezone.utc)<dt.datetime.fromisoformat(spec['expires_at'].replace('Z','+00:00')),'ARTIFACT_EXPIRED')
    status,headers,_=request(allow(spec['url']+'/zip'),4096,token=token)
    need(status==302,'SAVED_REDIRECT')
    status,_,raw=request(headers.get('location',''),spec['size_in_bytes'],redirect=True)
    need(status==200 and len(raw)==spec['size_in_bytes'] and 'sha256:'+sha(raw)==spec['digest'],'SAVED_HASH')
    archive=work/'saved.zip';budget.write(archive,raw)
    helper=runpy.run_path(str(REPO/'research/phase2a_e06i/p1m_saved_artifact_replay.py'))
    # Reserve the reviewed fixed ZIP extraction and fixed signature subprocess
    # write set before allowing it. No target archive is extracted here.
    budget.reserve(16*1024**2);saved=work/'originals';helper['extract_saved'](archive,saved)
    script=helper['signature_script'](REPO/'.github/workflows/phase2a-p1-h4-metadata.yml',
        (REPO/'research/phase2a_e06i/p1m_debian_dependency_closure.py').read_bytes())
    scriptpath=work/'verify.sh';budget.write(scriptpath,script)
    budget.reserve(512*1024**2)
    env={k:v for k,v in os.environ.items() if 'TOKEN' not in k and not k.startswith('ACTIONS_')}
    env.update(P1M_SAVED=str(saved),TMPDIR=str(work),GNUPGHOME=str(work/'gnupg'))
    (work/'gnupg').mkdir(mode=0o700)
    with tempfile.TemporaryFile(dir=work) as out:
        proc=subprocess.run(['bash',str(scriptpath)],stdin=subprocess.DEVNULL,stdout=out,stderr=out,
                            env=env,timeout=90,check=False,preexec_fn=signature_child_limits)
        out.seek(0);log=out.read(262145)
    need(proc.returncode==0 and len(log)<=262144,'SAVED_SIGNATURE_OR_EXPIRY')
    # The unchanged script checks both signatures, exact keys, signed index
    # hashes/sizes and run-time Valid-Until before any new package request.
    REPORT['saved_originals']='SIGNATURE_HASH_AND_CURRENT_EXPIRY_VERIFIED'
    index=saved/'main.Packages.xz';found=[]
    with lzma.open(index,'rt',encoding='utf8') as stream:
        fields={};used=0
        for line in stream:
            used+=len(line.encode());need(used<=60000000,'INDEX_READ_LIMIT')
            if line=='\n':
                if fields.get('Package')=='python3-pip-whl':found.append(fields)
                fields={}
            elif not line[0].isspace():
                k,sep,v=line.partition(':');need(sep,'INDEX_FIELD');fields[k]=v.strip()
    p=SPEC['pip_deb'];need(len(found)==1 and found[0]['Version']==p['version'] and
        int(found[0]['Size'])==p['size'] and found[0]['SHA256']==p['sha256'] and
        p['url'].endswith('/'+found[0]['Filename']),'SIGNED_PIP_DESCRIPTOR')

def image_inventory(token,budget):
    o=SPEC['oci'];raw=fixed_get(o['index_url'],131072,token)
    need('sha256:'+sha(raw)==o['index_digest'],'OCI_INDEX')
    index=document(raw);matches=[x for x in index['manifests'] if x.get('platform',{}).get('os')=='linux' and
        x.get('platform',{}).get('architecture')=='amd64' and not x.get('platform',{}).get('variant')]
    need(len(matches)==1 and matches[0]['digest']==o['manifest_digest'],'OCI_PLATFORM')
    raw=fixed_get(o['manifest_url'],131072,token)
    need(len(raw)==matches[0]['size'] and 'sha256:'+sha(raw)==o['manifest_digest'],'OCI_MANIFEST')
    manifest=document(raw)
    need([{k:x[k] for k in ('digest','size')} for x in manifest['layers']]==SPEC['layers'],'OCI_LAYER_SET')
    need(manifest['config']['digest']==o['config_digest'] and manifest['config']['size']==o['config_size'],'OCI_CONFIG_PIN')
    config=document(blob_get(o['config_digest'],o['config_size'],token))
    need(config.get('os')=='linux' and config.get('architecture')=='amd64' and
         config['rootfs']['type']=='layers' and len(config['rootfs']['diff_ids'])==len(SPEC['layers']),'OCI_CONFIG')
    vfs={};contents={};diffs=[]
    REPORT['verified_layers']=[]
    for index,(item,expected) in enumerate(zip(SPEC['layers'],config['rootfs']['diff_ids']),1):
        REPORT['progress']={'archive':'OCI_LAYER','layer_index':index,'layer_digest':item['digest'],
                            'stage':'LAYER_FETCH','compressed_digest_verified':False}
        need(re.fullmatch(r'sha256:[0-9a-f]{64}',expected),'DIFF_ID')
        raw=blob_get(item['digest'],item['size'],token)
        progress('LAYER_SCAN',compressed_digest_verified=True)
        with gzip.GzipFile(fileobj=io.BytesIO(raw)) as stream:diff=scan_tar(stream,budget,vfs,contents)
        progress('LAYER_DIFF_ID')
        need('sha256:'+diff==expected,'LAYER_DIFF_ID');diffs.append('sha256:'+diff)
        REPORT['verified_layers'].append({'index':index,'digest':item['digest'],
                                         'compressed_size':item['size'],'diff_id':'sha256:'+diff})
    need('var/lib/dpkg/status' in contents,'DPKG_INVENTORY_MISSING')
    packages=[]
    for stanza in contents['var/lib/dpkg/status'].decode('utf8').split('\n\n'):
        fields={}
        for line in stanza.splitlines():
            if line and not line[0].isspace():
                k,sep,val=line.partition(':');need(sep and k not in fields,'DPKG_FIELDS');fields[k]=val.strip()
        if fields:
            need(all(k in fields for k in ('Package','Status','Version','Architecture')),'DPKG_RECORD')
            packages.append({k:fields[k] for k in ('Package','Status','Version','Architecture')})
    gems=[]
    for name,data in contents.items():
        if name.endswith('.gemspec'):
            need(len(data)<=262144,'GEMSPEC_SIZE')
            # Never eval Ruby. Literal fields are observations, not complete dependencies.
            text=data.decode('utf8');versions=re.findall(r'^\s*\w+\.version\s*=\s*["\']([^"\']+)["\']',text,re.M)
            gems.append({'path':name,'sha256':sha(data),'literal_versions':versions,'dependency_semantics':'UNPROVEN_NO_EVAL'})
    relevant={k:v for k,v in vfs.items() if ('elf' in v or v['type']=='symlink' or
        k.endswith(('.so','.so.3','.gemspec')) or k in ('usr/local/bin/ruby','usr/bin/dpkg','usr/bin/git','usr/bin/python3.11'))}
    return {'manifest_digest':o['manifest_digest'],'config_digest':o['config_digest'],'diff_ids':diffs,
            'file_count':len(vfs),'paths':sorted(vfs),'full_record_manifest_sha256':sha(encoded(vfs)),
            'selected_records':relevant,'dpkg_packages':packages,'gemspecs':gems,
            'config_env':config.get('config',{}).get('Env',[]),'installed_runtime':'UNPROVEN'}

def main():
    spec=document((BASE/'p1s_input_contract.json').read_bytes())
    readiness(spec)
    expected=os.environ.get('EXPECTED_MAIN','');token=os.environ.get('P1S_GITHUB_TOKEN','')
    need(re.fullmatch(r'[0-9a-f]{40}',expected) and os.environ.get('GITHUB_SHA')==expected and
         os.environ.get('GITHUB_REF')=='refs/heads/main' and os.environ.get('GITHUB_RUN_ATTEMPT')=='1','MAIN_MANUAL_ATTEMPT')
    repo=configure(spec,int(os.environ.get('P1S_BOOTSTRAP_BYTES','0')))
    budget=Budget(spec);budget.reserve(USED)
    # All reusable sources remain frozen at the previous audited main.
    for path,blob in spec['fixed_sources'].items():
        url='https://raw.githubusercontent.com/cuichangquan/ap2-mandate-verifier/'+spec['baseline']+'/'+path
        raw=pinned(fixed_get(url,131072),blob);budget.write(REPO/path,raw)
    ref=document(fixed_get(repo+'/git/ref/heads/main',16384,token))
    need(ref['object']['sha']==expected,'MAIN_MOVED')
    runs=document(fixed_get(repo+'/actions/runs?head_sha='+expected+'&per_page=100',131072,token))
    need(runs['total_count']==1 and len(runs['workflow_runs'])==1 and
         runs['workflow_runs'][0]['id']==int(os.environ['GITHUB_RUN_ID']) and
         runs['workflow_runs'][0]['run_attempt']==1,'UNEXPECTED_RUN')
    guard=repo+'/git/ref/'+spec['once_ref'].removeprefix('refs/')
    status,_,_=request(allow(guard),4096,token=token);need(status==404,'GUARD_CONSUMED_OR_UNCERTAIN')
    # Permanent claim before any archive/payload request. No delete/reset/retry.
    data=encoded({'ref':spec['once_ref'],'sha':expected})
    status,_,raw=request(allow(repo+'/git/refs'),16384,token=token,method='POST',data=data)
    need(status==201 and document(raw)['object']['sha']==expected,'CLAIM_UNCERTAIN')
    REPORT.update(guard_consumed=True,once_ref=spec['once_ref'],main_sha=expected,run_id=os.environ['GITHUB_RUN_ID'],attempt=1)
    with tempfile.TemporaryDirectory(prefix='p1s-') as temp:
        work=Path(temp);budget.spool_dir=work;REPORT['stage']='SAVED_SIGNATURES';verify_saved(repo,token,work,budget)
        auth=document(fixed_get(spec['oci']['auth_url'],32768))
        registry_token=auth.get('token');need(type(registry_token) is str and 0<auth.get('expires_in',0)<=3600,'REGISTRY_AUTH')
        REPORT['stage']='IMAGE_STATIC_SCAN';REPORT['image']=image_inventory(registry_token,budget)
        REPORT['stage']='PIP_STATIC_SCAN';p=spec['pip_deb'];raw=fixed_get(p['url'],p['size'])
        need(len(raw)==p['size'] and sha(raw)==p['sha256'],'PIP_DEB_HASH')
        REPORT['pip_wheel']=pip_metadata(raw,budget)
    REPORT.update(status='STATIC_CONTENTS_INVENTORIED_RUNTIME_UNPROVEN',controlled_response_body_bytes=USED,
                  expanded_bytes=budget.expanded,entries=budget.entries,managed_write_reservations=budget.written,
                  missing=['ACTUAL_RUNTIME_IMPORTS_ABI','OFFLINE_INSTALL_RECONCILIATION','GIT_ADDITIONAL_CLOSURE',
                           'AP2_OBJECT_STORE','TRUSTED_SUPERVISOR','E03_E04_E06_GATES'])

def report_bytes(report):
    """Bound the serialized result while producing it, retain small diagnostics."""
    limit=1048576-65536;out=bytearray();failed=False
    encoder=json.JSONEncoder(sort_keys=True,ensure_ascii=True,allow_nan=False,separators=(',',':'))
    try:
        for part in encoder.iterencode(report):
            # ensure_ascii makes character count equal to encoded byte count.
            if len(part)>limit-len(out):
                failed=True;break
            out.extend(part.encode('ascii'))
    except (MemoryError,ValueError,TypeError,OverflowError):
        failed=True
    if not failed:return bytes(out),False
    out.clear()
    fallback={'status':'STOP_HOLD','stop_reason':'METADATA_OUTPUT_LIMIT',
              'controlled_response_body_bytes':report.get('controlled_response_body_bytes',0),
              'guard_consumed':report.get('guard_consumed',False),'runtime':'UNPROVEN',
              'stage':report.get('stage'),'progress':report.get('progress'),
              'verified_layers':report.get('verified_layers',[]),
              'resource_counters':report.get('resource_counters')}
    raw=encoded(fallback)
    need(len(raw)<=32768,'DIAGNOSTIC_OUTPUT_BOUND')
    return raw,True


if __name__=='__main__':
    code=0
    try:main()
    except BaseException as exc:
        # Only controlled uppercase reason labels or exception class, never URLs.
        reason=str(exc)
        REPORT['status']='STOP_HOLD'
        REPORT['stop_reason']=reason if re.fullmatch(r'[A-Z0-9_]{1,80}',reason) else type(exc).__name__
        code=1
    REPORT['controlled_response_body_bytes']=USED
    raw,output_failed=report_bytes(REPORT)
    if output_failed:code=1
    out=REPO/'p1s-result';out.mkdir(mode=0o700,exist_ok=True)
    with (out/'inventory.json').open('xb') as stream:stream.write(raw)
    print('P1S_STATUS='+document(raw)['status'])
    raise SystemExit(code)
