"""U6: synthetic Linux mechanisms only; never AP2/runtime/Gate evidence.

Nine fixed cases. Only transient systemd units and their private tmpfs are used.
No installation, host policy edits, network payloads, or retry. Missing support
is STOP. This module is importable on Mac; main refuses all non-Linux hosts.
"""
import datetime
import json
import os
from pathlib import Path
import platform
import selectors
import shutil
import signal
import subprocess
import sys
import tempfile
import time

CASES = ("network", "readonly_permissions", "descendants", "timeout", "pids",
         "memory", "disk", "inode", "output")
OUTPUT_CAP = 65536
RESULT_CAP = 1048576
BATCH_SECONDS = 120
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
    "TemporaryFileSystem": "/work:rw,size=32M,nr_inodes=256,mode=1777,nosuid,nodev",
    "WorkingDirectory": "/work", "RemainAfterExit": "yes",
    "Slice": "system.slice",
}
COMMON = '''import os, sys, time, errno, socket, json
assert os.getuid() != 0
s = open('/proc/self/status').read()
assert 'NoNewPrivs:\\t1' in s
assert int(next(x.split()[1] for x in s.splitlines() if x.startswith('CapEff:')),16)==0
v = os.statvfs('/work')
assert v.f_blocks*v.f_frsize == 33554432 and v.f_files == 256
open('/work/control','w').close()
cg='/sys/fs/cgroup'+open('/proc/self/cgroup').read().strip().split('::')[1]
assert open(cg+'/memory.max').read().strip()=='67108864'
assert open(cg+'/memory.swap.max').read().strip()=='0'
assert open(cg+'/pids.max').read().strip()=='16'
def events(name):
 return dict((k,int(v)) for k,v in (line.split() for line in open(cg+'/'+name)))
'''
WORK = {
    "network": '''assert os.readlink('/proc/self/ns/net') != sys.argv[2]
assert len(open('/proc/net/route').read().splitlines()) == 1
sock=socket.socket(); sock.settimeout(0.2)
try:
 sock.connect(('192.0.2.1',9)); raise AssertionError('network allowed')
except OSError as e:
 assert e.errno == errno.ENETUNREACH
finally: sock.close()
print('NETWORK_BLOCKED',flush=True)
''',
    "readonly_permissions": '''try:
 open(sys.argv[1]+'/forbidden','w'); raise AssertionError('write allowed')
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
 with open('/work/large','wb',buffering=0) as f:
  for i in range(40): f.write(b'x'*1048576)
 raise AssertionError('disk unbounded')
except OSError as e:
 assert e.errno==errno.ENOSPC and os.statvfs('/work').f_bavail==0
print('DISK_BLOCKED',flush=True)
''',
    "inode": '''try:
 for i in range(300): open('/work/f'+str(i),'w').close()
 raise AssertionError('inodes unbounded')
except OSError as e:
 assert e.errno==errno.ENOSPC and os.statvfs('/work').f_favail==0
print('INODE_BLOCKED',flush=True)
''',
    "output": "sys.stdout.buffer.write(b'x'*131072); sys.stdout.flush(); time.sleep(30)\n",
}
TOKENS = dict(zip(CASES, ("NETWORK_BLOCKED", "READONLY_UNPRIVILEGED",
                         "DESCENDANT_READY", "TIMEOUT_READY", "PIDS_BLOCKED",
                         "MEMORY_BLOCKED", "DISK_BLOCKED", "INODE_BLOCKED", "")))


class Stop(RuntimeError):
    pass


def command(args, *, check=True):
    # All management calls have fixed small output and a hard per-call deadline.
    p = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL, timeout=4, env={"PATH": "/usr/bin:/bin"})
    if len(p.stdout) > OUTPUT_CAP or (check and p.returncode):
        raise Stop("MANAGEMENT_COMMAND")
    return p.stdout.decode("utf-8", "strict")


def unit_command(unit, ro, netns, case):
    props = dict(PROPERTIES, ReadOnlyPaths=str(ro))
    return ["/usr/bin/systemd-run", "--quiet", "--pipe", "--unit="+unit] + [
        "--property="+k+"="+v for k, v in props.items()] + [
        "/usr/bin/python3", "-I", "-S", "-B", "-c", COMMON+WORK[case], str(ro), netns]


def verdict(case, data, result, status, exceeded, clean):
    if not clean or (exceeded and case != "output"):
        return False
    if case == "output":
        return exceeded
    if TOKENS[case].encode() not in data:
        return False
    if case == "memory":
        return result in ("success", "oom-kill") and status == "0"
    if case == "timeout":
        return result == "timeout"
    if case in ("descendants", "pids"):
        return True
    return result == "success" and status == "0"


class Lab:
    def __init__(self, root, deadline):
        self.root, self.deadline = root, deadline
        self.units = []
        self.cleaned = set()

    def show(self, unit):
        text = command(["/usr/bin/systemctl", "show", unit,
                        "-p", "Result", "-p", "ExecMainStatus", "-p", "ControlGroup",
                        "-p", "MemoryMax", "-p", "MemorySwapMax", "-p", "TasksMax",
                        "-p", "SubState", "-p", "ActiveState", "-p", "LoadState"], check=False)
        return dict(line.split("=", 1) for line in text.splitlines() if "=" in line)

    def cleanup(self, unit, cg):
        if unit in self.cleaned:
            return True
        if cg != '/system.slice/'+unit or not unit.startswith('u6-'):
            raise Stop("CGROUP_PATH")
        command(["/usr/bin/systemctl", "stop", unit], check=False)
        state = self.show(unit)
        if state.get('ActiveState') not in ('inactive', 'failed') and state.get('LoadState') != 'not-found':
            raise Stop("UNIT_NOT_STOPPED")
        # Only inspect the owned, exact cgroup. No host-wide kill or scan.
        path = Path("/sys/fs/cgroup") / cg.lstrip("/")
        if path.exists():
            events = (path / "cgroup.events").read_text()
            if "populated 0" not in events:
                raise Stop("DESCENDANTS_REMAIN")
        command(["/usr/bin/systemctl", "reset-failed", unit], check=False)
        self.cleaned.add(unit)
        return True

    def run(self, case, index):
        unit = "u6-"+str(os.getpid())+"-"+str(index)+".service"
        expected_cg = '/system.slice/'+unit
        self.units.append((unit, expected_cg))  # Track before service creation.
        ro = self.root / "ro"
        proc = subprocess.Popen(unit_command(unit, ro, os.readlink('/proc/self/ns/net'), case),
                                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, env={"PATH": "/usr/bin:/bin"})
        data, exceeded, cg, observed = bytearray(), False, expected_cg, {}
        started = time.monotonic()
        try:
            with selectors.DefaultSelector() as sel:
                sel.register(proc.stdout, selectors.EVENT_READ)
                while True:
                    if time.monotonic() >= min(self.deadline, started+9):
                        raise Stop("CONTROLLER_DEADLINE")
                    observed = self.show(unit)
                    actual_cg = observed.get("ControlGroup", "")
                    if actual_cg:
                        if actual_cg != expected_cg:
                            raise Stop("CGROUP_PATH")
                        if any(observed.get(k) != v for k, v in (
                            ("MemoryMax", "67108864"), ("MemorySwapMax", "0"), ("TasksMax", "16"))):
                            raise Stop("LIMIT_READBACK")
                    for key, _ in sel.select(0.05):
                        chunk = os.read(key.fd, min(4096, OUTPUT_CAP+1-len(data)))
                        if not chunk:
                            sel.unregister(key.fileobj)
                        data.extend(chunk)
                    exceeded = len(data) > OUTPUT_CAP
                    ready = TOKENS[case].encode() in data
                    if exceeded or (ready and case in ("descendants", "pids")):
                        if case == "descendants":
                            members = Path('/sys/fs/cgroup'+cg+'/cgroup.procs').read_text().split()
                            if len(members) < 2:
                                raise Stop("DESCENDANT_NOT_OBSERVED")
                        break
                    if ((ready and observed.get("SubState") == "exited") or
                            observed.get("ActiveState") == "failed"):
                        break
                    if proc.poll() is not None and not sel.get_map():
                        break
            observed = self.show(unit)
            clean = self.cleanup(unit, cg)
            proc.wait(timeout=4)
            ok = verdict(case, data, observed.get("Result"),
                         observed.get("ExecMainStatus"), exceeded, clean)
            return {"case": case, "pass": ok, "seconds": round(time.monotonic()-started, 3),
                    "observed": observed, "bytes_read": len(data), "output_exceeded": exceeded,
                    "synthetic_evidence": data.decode('utf-8', 'replace')[:4096] if case != 'output' else 'OUTPUT_CAP_REACHED',
                    "cleanup_empty": clean}
        finally:
            # Any exceptional path still stops the entire owned cgroup.
            try:
                self.cleanup(unit, cg)
            finally:
                if proc.poll() is None:
                    proc.kill()
                proc.wait(timeout=4)
                proc.stdout.close()


def preflight():
    if platform.system() != "Linux" or os.geteuid() != 0:
        raise Stop("LINUX_ROOT_REQUIRED")
    if Path('/etc/os-release').read_text().find('VERSION_ID="24.04"') < 0:
        raise Stop("UBUNTU_24_04_REQUIRED")
    if not Path('/sys/fs/cgroup/cgroup.controllers').is_file():
        raise Stop("CGROUP_V2_REQUIRED")
    for tool in ("/usr/bin/systemd-run", "/usr/bin/systemctl", "/usr/bin/python3"):
        if not os.access(tool, os.X_OK):
            raise Stop("MISSING_TOOL")
    command(["/usr/bin/systemctl", "is-system-running"])


def main():
    result = {"scope": "SYNTHETIC_LINUX_ONLY_RUNTIME_UNPROVEN",
              "cases": [{"case": c, "status": "NOT_RUN"} for c in CASES],
              "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "sha": os.environ.get("GITHUB_SHA"), "run": os.environ.get("GITHUB_RUN_ID"),
              "attempt": os.environ.get("GITHUB_RUN_ATTEMPT"), "cleanup": False,
              "status": "STOP_NO_RETRY"}
    root = None
    lab = None
    start = time.monotonic()
    def timeout_handler(*_):
        raise Stop("BATCH_DEADLINE")
    try:
        preflight()
        signal.signal(signal.SIGALRM, timeout_handler)
        signal.signal(signal.SIGTERM, timeout_handler)
        signal.alarm(105)  # Reserve 15 seconds of the 120-second batch for cleanup.
        root = Path(tempfile.mkdtemp(prefix="u6-", dir="/run"))
        root.chmod(0o755)
        (root / "ro").mkdir(mode=0o777)
        (root / "ro").chmod(0o777)  # EROFS, rather than DAC, must deny the write.
        lab = Lab(root, start+105)
        for index, case in enumerate(CASES):
            row = lab.run(case, index)
            result["cases"][index] = row
            if not row["pass"]:
                raise Stop("CASE_FAILED_"+case)
        result["status"] = "LIMITED_LINUX_MECHANISMS_OBSERVED"
    except (Exception, KeyboardInterrupt) as exc:
        result["reason"] = str(exc) if isinstance(exc, Stop) else type(exc).__name__
    finally:
        signal.alarm(0)
        try:
            if lab:
                for unit, cg in lab.units:
                    if cg:
                        lab.cleanup(unit, cg)
                    else:
                        command(["/usr/bin/systemctl", "stop", unit], check=False)
            if root:
                shutil.rmtree(root)
            result["cleanup"] = True
        except Exception as exc:
            result["status"] = "STOP_NO_RETRY"
            result["cleanup_error"] = type(exc).__name__
        result["seconds"] = round(time.monotonic()-start, 3)
        result["ended_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        payload = json.dumps(result, sort_keys=True).encode()+b"\n"
        if len(payload) > RESULT_CAP:
            payload = b'{"status":"STOP_RESULT_LIMIT"}\n'
        Path("u6-result.json").write_bytes(payload)
    return 0 if result["status"] == "LIMITED_LINUX_MECHANISMS_OBSERVED" else 78


if __name__ == "__main__":
    sys.exit(main())
