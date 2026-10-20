"""U6: synthetic Linux mechanisms only; never AP2/runtime/Gate evidence.

Nine fixed cases. Only transient systemd units and their private tmpfs are used.
No installation, host policy edits, network payloads, or retry. Missing support
is STOP. This module is importable on Mac; main refuses all non-Linux hosts.
"""
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import selectors
import shutil
import signal
import subprocess
import sys
import stat
import tempfile
import time

CASES = ("network", "readonly_permissions", "descendants", "timeout", "pids",
         "memory", "disk", "inode", "output")
OUTPUT_CAP = 65536
RESULT_CAP = 1048576
BATCH_SECONDS = 120
ENV = {"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C", "SYSTEMD_COLORS": "0"}
_spec = importlib.util.spec_from_file_location('u6_capture', Path(__file__).with_name('u6_systemd_diagnostic.py'))
_capture = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_capture)
PROPERTIES = {
    "Type": "exec", "User": "nobody", "Group": "nogroup",
    "PrivateNetwork": "yes", "PrivateTmp": "yes", "PrivateDevices": "yes",
    "ProtectSystem": "strict", "ProtectHome": "yes", "NoNewPrivileges": "yes",
    "CapabilityBoundingSet": "", "AmbientCapabilities": "",
    "RestrictSUIDSGID": "yes", "RestrictNamespaces": "yes",
    "ProtectControlGroups": "yes", "ProtectKernelTunables": "yes",
    "ProtectKernelModules": "yes", "KillMode": "control-group",
    "SendSIGKILL": "yes", "TimeoutStopSec": "1s", "RuntimeMaxSec": "3s",
    "MemoryMax": "67108864", "MemorySwapMax": "0", "TasksMax": "16",
    "OOMPolicy": "continue", "LimitCORE": "0", "UMask": "0077",
    "RemainAfterExit": "no", "Restart": "no", "Delegate": "no",
    "TimeoutStartSec": "2s", "InaccessiblePaths": "/tmp /var/tmp /dev/shm",
    "RestrictAddressFamilies": "AF_INET AF_INET6", "SystemCallArchitectures": "native",
    "Slice": "system.slice",
}
COMMON = '''import os, sys, time, errno, socket, json, stat
def text(path):
 with open(path) as f: value=f.read(65537)
 assert len(value)<=65536
 return value
work=sys.argv[1]
os.chdir(work)
assert os.getuid() != 0
s = text('/proc/self/status')
assert 'NoNewPrivs:\\t1' in s
assert int(next(x.split()[1] for x in s.splitlines() if x.startswith('CapEff:')),16)==0
v = os.statvfs(work)
assert v.f_blocks*v.f_frsize == 33554432 and v.f_files == 256
mounts=[line.split(' - ') for line in text('/proc/self/mountinfo').splitlines() if line.split()[4]==work]
assert len(mounts)==1 and mounts[0][1].split()[0]=='tmpfs'
assert {'rw','nosuid','nodev'} <= set(mounts[0][0].split()[5].split(','))
net=os.readlink('/proc/self/ns/net'); mnt=os.readlink('/proc/self/ns/mnt')
assert net!=sys.argv[3] and mnt!=sys.argv[4]
for fd in (0,1,2): assert stat.S_ISFIFO(os.fstat(fd).st_mode)
for fd in os.listdir('/proc/self/fd'):
 try: assert not stat.S_ISSOCK(os.fstat(int(fd)).st_mode)
 except OSError as e: assert e.errno==errno.EBADF
for path in ('/tmp','/var/tmp','/dev/shm'):
 try:
  fd=os.open(path,os.O_RDONLY|os.O_DIRECTORY); os.close(fd); raise AssertionError('extra writable path accessible')
 except OSError as e: assert e.errno==errno.EACCES
try:
 sock=socket.socket(socket.AF_UNIX); sock.close(); raise AssertionError('AF_UNIX allowed')
except OSError as e: assert e.errno in (errno.EAFNOSUPPORT,errno.EPERM)
cgroup=text('/proc/self/cgroup').strip().split('::')[1]
cg='/sys/fs/cgroup'+cgroup
assert text(cg+'/memory.max').strip()=='67108864'
assert text(cg+'/memory.swap.max').strip()=='0'
assert text(cg+'/pids.max').strip()=='16'
def events(name):
 return dict((k,int(v)) for k,v in (line.split() for line in open(cg+'/'+name)))
print('U6_READY '+json.dumps({'pid':os.getpid(),'uid':os.getuid(),'net':net,'mnt':mnt,'cgroup':cgroup,'fs_bytes':v.f_blocks*v.f_frsize,'inodes':v.f_files}),flush=True)
assert sys.stdin.readline(4)=='GO\\n'
open('control','w').close()
'''
WORK = {
    "network": '''assert len(text('/proc/net/route').splitlines()) == 1
assert all(int(line.split()[4],16)==0 for line in text('/proc/net/ipv6_route').splitlines())
for family,address in ((socket.AF_INET,('192.0.2.1',9)),(socket.AF_INET6,('2001:db8::1',9))):
 sock=socket.socket(family); sock.settimeout(0.2)
 try:
  sock.connect(address); raise AssertionError('network allowed')
 except OSError as e: assert e.errno==errno.ENETUNREACH
 finally: sock.close()
print('NETWORK_BLOCKED',flush=True)
''',
    "readonly_permissions": '''try:
 open(sys.argv[2]+'/forbidden','w'); raise AssertionError('write allowed')
except OSError as e: assert e.errno == errno.EROFS
try:
 os.setuid(0); raise AssertionError('privilege allowed')
except OSError as e: assert e.errno == errno.EPERM
print('READONLY_UNPRIVILEGED',flush=True)
''',
    "descendants": '''p=os.fork()
if p==0:
 os.setsid()
 p=os.fork()
 if p==0: time.sleep(30); os._exit(0)
 os._exit(0)
os.waitpid(p,0)
print('DESCENDANT_READY',flush=True)
time.sleep(30)
''',
    "timeout": "print('TIMEOUT_READY',flush=True); time.sleep(30)\n",
    "pids": '''children=[]
before=events('pids.events')['max']
try:
 for i in range(32):
  p=os.fork()
  if p==0: time.sleep(30); os._exit(0)
  children.append(p)
 raise AssertionError('pids unbounded')
except OSError as e: assert e.errno==errno.EAGAIN
after=events('pids.events')['max']
assert after>before
print('PIDS_MAX_DELTA='+str(after-before),flush=True)
print('PIDS_BLOCKED',flush=True)
time.sleep(30)
''',
    "memory": '''before=events('memory.events')
p=os.fork()
if p==0:
 open('/proc/self/oom_score_adj','w').write('1000')
 a=[]
 for i in range(128): a.append(bytearray(1048576)); time.sleep(0.005)
 os._exit(1)
_,status=os.waitpid(p,0)
after=events('memory.events')
assert os.WIFSIGNALED(status) and os.WTERMSIG(status)==9
assert after['max']>before['max'] and after['oom']>before['oom'] and after['oom_kill']>before['oom_kill']
print('MEMORY_EVENTS_DELTA='+json.dumps({k:after[k]-before[k] for k in ('max','oom','oom_kill')}),flush=True)
print('MEMORY_BLOCKED',flush=True)
''',
    "disk": '''try:
 with open('large','wb',buffering=0) as f:
  for i in range(40): f.write(b'x'*1048576)
 raise AssertionError('disk unbounded')
except OSError as e:
 assert e.errno==errno.ENOSPC and os.statvfs(work).f_bavail==0
print('DISK_BLOCKED',flush=True)
''',
    "inode": '''try:
 for i in range(300): open('f'+str(i),'w').close()
 raise AssertionError('inodes unbounded')
except OSError as e:
 assert e.errno==errno.ENOSPC and os.statvfs(work).f_favail==0
print('INODE_BLOCKED',flush=True)
''',
    "output": "sys.stdout.buffer.write(b'x'*131072); sys.stdout.flush(); time.sleep(30)\n",
}
TOKENS = dict(zip(CASES, ("NETWORK_BLOCKED", "READONLY_UNPRIVILEGED",
                         "DESCENDANT_READY", "TIMEOUT_READY", "PIDS_BLOCKED",
                         "MEMORY_BLOCKED", "DISK_BLOCKED", "INODE_BLOCKED", "")))


class Stop(RuntimeError):
    pass


def need(ok, reason):
    if not ok:
        raise Stop(reason)


def read_file(path, cap=65536):
    with open(path, 'rb') as f:
        value = f.read(cap+1)
    need(len(value) <= cap, 'CAPTURE_LIMIT_FILE')
    return value.decode('utf-8', 'strict')


def pairs(text):
    out = {}
    for line in text.splitlines():
        need('=' in line, 'PROPERTY_FORMAT')
        key, value = line.split('=', 1)
        need(key not in out, 'PROPERTY_DUPLICATE')
        out[key] = value
    return out


class Management:
    def __init__(self, report, deadline):
        self.report, self.deadline = report, deadline
        self.calls = 0
        self.bytes = 2  # JSON array brackets; each entry reserves its separator too.
        self.case_deadline = None

    def record(self, entry, cleanup):
        size = len(json.dumps(entry).encode())+2
        if self.bytes+size > 65536:
            self.report['management_truncated'] = True
            need(cleanup, 'CAPTURE_LIMIT_MANAGEMENT_LEDGER')
            return
        self.report['management'].append(entry)
        self.bytes += size

    def run(self, args, *, stage, seconds=1, cleanup=False, check=True, allow_stderr=False):
        self.calls += 1
        need(self.calls <= (160 if cleanup else 140), 'COMMAND_COUNT_LIMIT')
        remaining = min(self.deadline,self.case_deadline or self.deadline)-time.monotonic()
        need(remaining > 0, 'DEADLINE_MANAGEMENT')
        entry = {'stage': stage, 'argv': args, 'started_utc': utc()}
        try:
            proc = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, start_new_session=True, env=ENV)
        except OSError as exc:
            entry.update(failure='COMMAND_SPAWN_ERROR', errno=exc.errno)
            self.record(entry,cleanup)
            raise Stop('COMMAND_SPAWN_ERROR')
        row = _capture.capture(proc, deadline_seconds=min(seconds, remaining))
        entry.update(row, ended_utc=utc())
        self.record(entry,cleanup)
        need(row['query_reaped'] and not row['failure'], row['failure'] or 'MANAGEMENT_CLEANUP_UNKNOWN')
        need(allow_stderr or not row['stderr'], 'MANAGEMENT_STDERR')
        need(not check or row['returncode'] == 0, 'COMMAND_NONZERO_'+stage)
        return row


READBACK = {
    key: value for key, value in PROPERTIES.items()
    if key not in ('TimeoutStartSec', 'TimeoutStopSec', 'RuntimeMaxSec', 'Slice')}
READBACK.update(Transient='yes', RuntimeMaxUSec='3s', TimeoutStartUSec='2s', TimeoutStopUSec='1s')
STATE_KEYS = ('LoadState', 'ActiveState', 'SubState', 'Result', 'ExecMainStatus')


def unit_command(unit, root, netns, mntns, case):
    work = str(root/'work')
    props = dict(PROPERTIES, ReadOnlyPaths=str(root/'ro'), WorkingDirectory=work,
                 TemporaryFileSystem=work+':rw,size=32M,nr_inodes=256,mode=1777,nosuid,nodev')
    tail = '' if case in ('timeout', 'output', 'pids', 'descendants') else '\ntime.sleep(30)\n'
    code = COMMON+WORK[case]+tail
    args = ['/usr/bin/systemd-run', '--system', '--quiet', '--pipe', '--no-ask-password',
            '--expand-environment=no', '--unit='+unit]
    args += ['--property='+k+'='+v for k, v in props.items()]
    return args+['/usr/bin/python3', '-I', '-S', '-B', '-c', code,
                 work, str(root/'ro'), netns, mntns], props, code


def baseline(ready, props, unit, root, parent_net, parent_mnt):
    cg = '/system.slice/'+unit
    need(set(ready) == {'pid','uid','net','mnt','cgroup','fs_bytes','inodes'}, 'READY_SCHEMA')
    need(type(ready['pid']) is int and ready['pid'] > 1 and type(ready['uid']) is int and ready['uid'] > 0,
         'BASELINE_IDENTITY')
    need(props.get('ControlGroup') == cg and ready['cgroup'] == cg, 'CGROUP_PATH')
    need(props.get('MainPID') == str(ready['pid']), 'MAIN_PID')
    for key, expected in READBACK.items():
        need(props.get(key) == expected, 'UNIT_PROPERTY_'+key)
    need(props.get('ActiveState') == 'active', 'UNIT_NOT_ACTIVE')
    need(props.get('ReadOnlyPaths') == str(root/'ro') and props.get('WorkingDirectory') == str(root/'work'),
         'UNIT_PATHS')
    need(props.get('TemporaryFileSystem') == str(root/'work')+':rw,size=32M,nr_inodes=256,mode=1777,nosuid,nodev',
         'UNIT_TMPFS')
    proc = '/proc/'+str(ready['pid'])
    for kind, parent in (('net',parent_net), ('mnt',parent_mnt)):
        value = os.readlink(proc+'/ns/'+kind)
        need(value == ready[kind] and value != parent, 'NAMESPACE_'+kind)
    need(read_file(proc+'/cgroup',4096).strip() == '0::'+cg, 'PROC_CGROUP')
    status = read_file(proc+'/status',8192)
    fields = dict(line.split(':',1) for line in status.splitlines() if ':' in line)
    need([int(x) for x in fields['Uid'].split()] == [ready['uid']]*4, 'PROC_UID')
    need(fields['NoNewPrivs'].strip() == '1' and int(fields['CapEff'].strip(),16) == 0, 'PROC_PRIVILEGES')
    path = Path('/sys/fs/cgroup'+cg)
    need(not path.is_symlink() and not path.parent.is_symlink(), 'CGROUP_SYMLINK')
    for name, value in (('memory.max','67108864'),('memory.swap.max','0'),('pids.max','16')):
        need(read_file(path/name,256).strip() == value, 'KERNEL_LIMIT_'+name)
    need(str(ready['pid']) in read_file(path/'cgroup.procs',1024).split(), 'CGROUP_MEMBERSHIP')
    work = proc+'/root'+str(root/'work')
    fs = os.statvfs(work)
    need(fs.f_blocks*fs.f_frsize == ready['fs_bytes'] == 33554432 and fs.f_files == ready['inodes'] == 256,
         'FILESYSTEM_LIMIT')
    mounts = [line.split(' - ') for line in read_file(proc+'/mountinfo').splitlines()
              if line.split()[4] == str(root/'work')]
    need(len(mounts) == 1 and mounts[0][1].split()[0] == 'tmpfs', 'FILESYSTEM_TYPE')
    need({'rw','nosuid','nodev'} <= set(mounts[0][0].split()[5].split(',')), 'FILESYSTEM_FLAGS')
    return cg


def verdict(case, data, props, exceeded, admitted, clean):
    if not admitted or not clean:
        return False
    if case == 'output':
        return exceeded and data.startswith(b'U6_READY ')
    if exceeded or TOKENS[case].encode()+b'\n' not in data:
        return False
    return props.get('Result') == 'timeout' if case == 'timeout' else props.get('ActiveState') == 'active'


class Lab:
    def __init__(self, root, management, report):
        self.root, self.management, self.report = root, management, report
        self.units = {}
        self.parent_net = os.readlink('/proc/self/ns/net')
        self.parent_mnt = os.readlink('/proc/self/ns/mnt')

    def show(self, unit, *, full=False, cleanup=False):
        keys = (['LoadState','ActiveState'] if cleanup else list(STATE_KEYS))+(['MainPID','ControlGroup','ReadOnlyPaths','WorkingDirectory','TemporaryFileSystem']+
                               list(READBACK) if full else [])
        row = self.management.run(['/usr/bin/systemctl','--system','show','--all',unit]+['--property='+k for k in keys],
                                  stage='UNIT_SHOW', cleanup=cleanup,check=not cleanup,allow_stderr=cleanup)
        values = pairs(row['stdout'])
        need(set(values) == set(keys), 'UNIT_PROPERTIES_MISSING')
        if cleanup and (row['returncode'] or row['stderr']):
            need(values == {'LoadState':'not-found','ActiveState':'inactive'} and
                 row['returncode'] in (0,1) and row['stderr'] in ('',f'Unit {unit} could not be found.\n'),
                 'CLEANUP_MANAGER_ERROR')
        return values

    def cleanup(self, unit):
        owned = self.units[unit]
        if owned.get('clean'):
            return True
        self.management.run(['/usr/bin/systemctl','--system','stop',unit], stage='UNIT_STOP', cleanup=True,
                            check=False)
        state = self.show(unit, cleanup=True)
        need(state['ActiveState'] in ('inactive','failed'), 'UNIT_NOT_STOPPED')
        path = Path('/sys/fs/cgroup/system.slice')/unit
        if path.exists():
            fields = dict(line.split() for line in read_file(path/'cgroup.events',1024).splitlines())
            need(fields.get('populated') == '0', 'DESCENDANTS_REMAIN')
        need(owned.get('observed_cgroup') and owned.get('submitter_reaped'), 'CLEANUP_UNCONFIRMED_REGISTRATION')
        owned['empty_after_stop'] = True
        if state['ActiveState'] == 'failed':
            self.management.run(['/usr/bin/systemctl','--system','reset-failed',unit],
                                stage='OWNED_RESET_FAILED', cleanup=True)
        owned['clean'] = True
        return True

    def run(self, case, index):
        need(self.management.deadline-time.monotonic() >= 21, 'INSUFFICIENT_CASE_AND_CLEANUP_TIME')
        unit = 'u6-v3-'+self.report['run']+'-'+str(index)+'.service'
        owned = self.units[unit] = {'admitted':False,'clean':False,'empty_after_stop':False,
                                    'observed_cgroup':False,'submitter_reaped':False}
        row = self.report['cases'][index]
        row.update(status='FAIL', unit=unit, started_utc=utc(), admission='NOT_CONFIRMED')
        started = time.monotonic()
        self.management.case_deadline = started+6
        data, errors, admitted, exceeded, proc = bytearray(), bytearray(), False, False, None
        args, config, code = unit_command(unit, self.root, self.parent_net, self.parent_mnt, case)
        row['source_sha256'] = hashlib.sha256(code.encode('utf-8')).hexdigest()
        row['requested_properties'] = config
        try:
            proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    start_new_session=True, env=ENV)
            with selectors.DefaultSelector() as sel:
                sel.register(proc.stdout, selectors.EVENT_READ, 'stdout')
                sel.register(proc.stderr, selectors.EVENT_READ, 'stderr')
                while True:
                    need(time.monotonic() < min(self.management.deadline-15, started+6), 'DEADLINE_CASE')
                    for key, _ in sel.select(0.05):
                        buf, cap = (data,OUTPUT_CAP) if key.data == 'stdout' else (errors,4096)
                        chunk = os.read(key.fd, min(4096, cap+1-len(buf)))
                        if not chunk:
                            sel.unregister(key.fileobj)
                        buf.extend(chunk)
                    need(not errors, 'UNIT_STDERR')
                    exceeded = len(data) > OUTPUT_CAP
                    if not admitted and b'\n' in data:
                        need(data.startswith(b'U6_READY ') and len(data) <= 2048 and
                             data.count(b'\n') == 1 and data.endswith(b'\n'), 'READY_FORMAT')
                        ready = json.loads(bytes(data).split(b'\n',1)[0][9:])
                        props = self.show(unit, full=True)
                        row['admission_properties'] = props
                        cg = baseline(ready, props, unit, self.root, self.parent_net, self.parent_mnt)
                        admitted = owned['admitted'] = owned['observed_cgroup'] = True
                        row.update(admission='PASS', ready=ready, go_utc=utc())
                        proc.stdin.write(b'GO\n')
                        proc.stdin.flush()
                    if admitted and (exceeded or (case != 'output' and TOKENS[case].encode()+b'\n' in data and case != 'timeout')):
                        if case == 'descendants':
                            members = read_file(Path('/sys/fs/cgroup'+cg)/'cgroup.procs',1024).split()
                            need(len(members) >= 2, 'DESCENDANT_NOT_OBSERVED')
                            row['live_cgroup_members'] = members
                        break
                    need(not exceeded, 'OUTPUT_LIMIT_BEFORE_ADMISSION')
                    if proc.poll() is not None and not sel.get_map():
                        break
            props = self.show(unit)
            row['observed'] = props
            need(verdict(case,data,props,exceeded,admitted,True), 'CASE_FAILED_'+case)
            row['status'] = 'PASS'
        except Exception as exc:
            row['reason'] = str(exc) if isinstance(exc,Stop) else type(exc).__name__
            raise
        finally:
            row.update(bytes_read={'stdout':len(data),'stderr':len(errors)}, output_exceeded=exceeded,
                       stdout=bytes(data[:OUTPUT_CAP]).decode('utf-8','backslashreplace') if case != 'output' else 'OUTPUT_CAP_REACHED' if exceeded else bytes(data).decode('utf-8','backslashreplace'),
                       stderr=bytes(errors[:4096]).decode('utf-8','backslashreplace'), ended_utc=utc(),
                       seconds=round(time.monotonic()-started,6))
            try:
                self.finish(unit,proc,row)
            except Exception as exc:
                row['cleanup_error'] = str(exc) if isinstance(exc,Stop) else type(exc).__name__
                row['status'] = 'FAIL'
                raise
            finally:
                row['cleanup'] = dict(owned)
                self.management.case_deadline = None
                row.update(ended_utc=utc(),seconds=round(time.monotonic()-started,6))
                if row['seconds'] > 6:
                    row['status'] = 'FAIL'
                    raise Stop('DEADLINE_CASE_INCLUDING_CLEANUP')

    def finish(self, unit, proc, row):
        # No clean result may be cached while the submitter can still register a unit.
        if proc is not None:
            if proc.poll() is None:
                _capture.kill_query(proc)
            proc.wait(timeout=1)
            self.units[unit]['submitter_reaped'] = True
            row['controller_returncode'] = proc.returncode
            for stream in (proc.stdin,proc.stdout,proc.stderr):
                stream.close()
        self.cleanup(unit)


def preflight(management, report):
    if platform.system() != "Linux" or os.geteuid() != 0:
        raise Stop("LINUX_ROOT_REQUIRED")
    if 'VERSION_ID="24.04"' not in read_file('/etc/os-release',4096):
        raise Stop("UBUNTU_24_04_REQUIRED")
    if not {'memory','pids'} <= set(read_file('/sys/fs/cgroup/cgroup.controllers',1024).split()):
        raise Stop("CGROUP_V2_REQUIRED")
    for tool in ("/usr/bin/systemd-run", "/usr/bin/systemctl", "/usr/bin/python3"):
        if not os.access(tool, os.X_OK):
            raise Stop("MISSING_TOOL")
    need(platform.machine() == 'x86_64', 'UNREVIEWED_ARCHITECTURE')
    # Global boot completion is not a sandbox capability. A responsive supported
    # manager may only advance to per-unit READY/readback; no workload before GO.
    row = management.run(['/usr/bin/systemctl','--system','show','--property=Version','--property=SystemState'],
                         stage='MANAGER',seconds=4)
    props = pairs(row['stdout'])
    report['manager'] = props
    need(set(props) == {'Version','SystemState'} and
         props['SystemState'] in ('running','starting'), 'MANAGER_UNAVAILABLE')
    report['global_state'] = props['SystemState']
    report['capability_admission'] = 'REQUIRED_BEFORE_EACH_GO'
    need(re.fullmatch(r'255(?:[. -][0-9A-Za-z.+:~ -]{1,200})?',props['Version']) is not None,
         'UNSUPPORTED_VERSION')


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def main():
    result = {"scope": "SYNTHETIC_LINUX_ONLY_RUNTIME_UNPROVEN",
              "cases": [{"case": c, "status": "NOT_RUN"} for c in CASES],
              "started_utc": utc(), 'management':[],
              "sha": os.environ.get("GITHUB_SHA"), "run": os.environ.get("GITHUB_RUN_ID"),
              "attempt": os.environ.get("GITHUB_RUN_ATTEMPT"), "cleanup": False,
              "status": "STOP_NO_RETRY"}
    root = None
    lab = None
    start = time.monotonic()
    management = Management(result,start+105)
    def timeout_handler(*_):
        raise Stop("BATCH_DEADLINE")
    try:
        signal.signal(signal.SIGALRM, timeout_handler)
        signal.signal(signal.SIGTERM, timeout_handler)
        signal.alarm(90)  # Stop workload admission; reserve bounded cleanup within 105 seconds.
        need(re.fullmatch(r'[0-9]{1,20}',result['run'] or '') is not None, 'RUN_ID')
        result['source_sha256'] = {name:hashlib.sha256(read_file(Path(__file__).with_name(name)).encode()).hexdigest()
                                   for name in ('u6_linux_probe.py','u6_systemd_diagnostic.py')}
        preflight(management,result)
        root = Path(tempfile.mkdtemp(prefix="u6-", dir="/run"))
        root.chmod(0o755)
        (root / "ro").mkdir(mode=0o777)
        (root / "ro").chmod(0o777)  # EROFS, rather than DAC, must deny the write.
        (root / 'work').mkdir()
        lab = Lab(root,management,result)
        for index, case in enumerate(CASES):
            lab.run(case,index)
        result["status"] = "LIMITED_LINUX_MECHANISMS_OBSERVED"
    except (Exception, KeyboardInterrupt) as exc:
        result["reason"] = str(exc) if isinstance(exc, Stop) else type(exc).__name__
    finally:
        signal.alarm(max(1,int(start+105-time.monotonic())))
        try:
            if lab:
                result['units'] = lab.units
                for unit in lab.units:
                    lab.cleanup(unit)
            if root:
                need(not os.path.ismount(root/'work'), 'LAB_STILL_MOUNTED')
                shutil.rmtree(root)
            result["cleanup"] = True
        except Exception as exc:
            result["status"] = "STOP_NO_RETRY"
            result["cleanup_error"] = type(exc).__name__
        result["seconds"] = round(time.monotonic()-start, 3)
        result['management_bytes'] = management.bytes
        result['management_calls'] = management.calls
        result["ended_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        payload = json.dumps(result, sort_keys=True).encode()+b"\n"
        if len(payload) > RESULT_CAP:
            result['status'] = 'STOP_NO_RETRY'
            minimal = {key:result[key] for key in ('status','sha','run','attempt','cleanup','seconds')}
            minimal.update(reason='RESULT_LIMIT', cases=[{'case':c['case'],'status':c['status']} for c in result['cases']])
            payload = json.dumps(minimal,sort_keys=True).encode()+b'\n'
        Path("u6-result.json").write_bytes(payload)
        signal.alarm(0)
    return 0 if result["status"] == "LIMITED_LINUX_MECHANISMS_OBSERVED" else 78


if __name__ == "__main__":
    sys.exit(main())
