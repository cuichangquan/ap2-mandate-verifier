"""Trusted owner state machine and closed Linux syscall implementation.

The owner is MainPID/subreaper, not the payload. Its control pipe is never
inherited by payloads. Owner frames attest its own waits/FDs, NOT isolation.
Native construction requires an approved registry profile (none ships).
"""
import base64
import ctypes
import json
import os
import platform
import stat
import selectors
import signal
import struct
import sys
import time
sys.path.insert(0, os.path.dirname(__file__))
import p1r_execution_contract as c

RAW_CAP = 98304
CONTROL_CAP = 8192
FRAME_CAP = 8192
EVENT_CAP = 256
CAPS = {'stdout': 65536, 'stderr': 4096}
SOURCE = '/opt/ap2-source/research/phase2a_e06i'
OUTPUT = '/run/ap2-supervisor/output'


def unique(pairs):
    value = {}
    for key, item in pairs:
        c.need(key not in value, 'FRAME_DUPLICATE')
        value[key] = item
    return value


class Codec:
    def __init__(self, run, role):
        c.need(type(run) is str and run.isascii() and run.isdigit() and 1 <= len(run) <= 20 and role in c.ROLES, 'IDENTITY')
        self.run, self.role, self.sequence = run, role, 0
        self.raw = self.control = 0
        self.buffer = bytearray()

    def encode(self, kind, body):
        raw = c.canonical({'run': self.run, 'role': self.role, 'seq': self.sequence,
                           'kind': kind, 'body': body})
        c.need(len(raw) <= FRAME_CAP, 'FRAME_LIMIT')
        self.sequence += 1
        c.need(self.sequence <= EVENT_CAP, 'FRAME_EVENTS')
        return struct.pack('!I', len(raw)) + raw

    def feed(self, raw):
        c.need(type(raw) is bytes and 0 < len(raw) <= RAW_CAP, 'FRAME_INPUT')
        self.raw += len(raw)
        c.need(self.raw <= RAW_CAP, 'FRAME_RAW_LIMIT')
        self.buffer.extend(raw)
        out = []
        while len(self.buffer) >= 4:
            size, = struct.unpack('!I', self.buffer[:4])
            c.need(0 < size <= FRAME_CAP, 'FRAME_SIZE')
            if len(self.buffer) < size + 4:
                break
            packet = bytes(self.buffer[4:size+4]); del self.buffer[:size+4]
            try:
                row = json.loads(packet, object_pairs_hook=unique)
            except (ValueError, UnicodeError) as exc:
                raise c.Stop('FRAME_JSON') from exc
            c.need(type(row) is dict and set(row) == {'run','role','seq','kind','body'} and
                   row['run'] == self.run and row['role'] == self.role and
                   type(row['seq']) is int and row['seq'] == self.sequence, 'FRAME_BINDING')
            self.sequence += 1
            c.need(self.sequence <= EVENT_CAP, 'FRAME_EVENTS')
            if row['kind'] != 'data':
                self.control += size
                c.need(self.control <= CONTROL_CAP, 'FRAME_CONTROL_LIMIT')
            out.append((row['kind'], row['body']))
        return out

    def eof(self):
        c.need(not self.buffer, 'FRAME_TRUNCATED')


class Owner:
    """Single-use owner; kernel seam is infrastructure, never target callbacks."""
    def __init__(self, kernel, run, role):
        self.kernel, self.codec = kernel, Codec(run, role)
        self.state, self.count = 'NEW', 0
        self.bytes = dict.fromkeys(CAPS, 0)
        self.ended, self.exit = set(), None

    def prepare(self, deadline):
        c.need(self.state == 'NEW', 'OWNER_STATE')
        self.state = 'PREPARING'
        self.kernel.prepare(deadline)  # subreaper + non-dumpable, no child yet
        c.need(self.kernel.children() == (), 'PRE_GO_CHILD')
        self.state = 'WAITING'
        return self.codec.encode('ready', {'waiting': True})

    def go(self, deadline):
        c.need(self.state == 'WAITING' and self.kernel.children() == (), 'GO_STATE')
        self.state = 'STARTING'  # ownership precedes possibly-partial spawn
        self.kernel.spawn(deadline)
        self.state = 'RUNNING'

    def step(self, deadline):
        c.need(self.state == 'RUNNING', 'OWNER_STATE')
        self.count += 1
        c.need(self.count <= EVENT_CAP, 'OWNER_EVENTS')
        event = self.kernel.event({k: CAPS[k]-self.bytes[k]+1 for k in CAPS}, deadline)
        c.need(type(event) is tuple and event, 'OWNER_EVENT')
        kind = event[0]
        if kind == 'data':
            c.need(len(event) == 3 and event[1] in CAPS and event[1] not in self.ended and
                   type(event[2]) is bytes and 0 < len(event[2]) <= 4096, 'OWNER_DATA')
            self.bytes[event[1]] += len(event[2])
            c.need(self.bytes[event[1]] <= CAPS[event[1]], 'OWNER_OUTPUT_LIMIT')
            body = {'stream': event[1], 'bytes': base64.b64encode(event[2]).decode('ascii')}
        elif kind == 'eof':
            c.need(len(event) == 2 and event[1] in CAPS and event[1] not in self.ended, 'OWNER_EOF')
            self.ended.add(event[1]); body = {'stream': event[1]}
        elif kind == 'exit':
            c.need(len(event) == 2 and type(event[1]) is int and self.exit is None, 'OWNER_EXIT')
            self.exit = event[1]; body = {'code': event[1]}
        else:
            c.need(event == ('idle',), 'OWNER_EVENT')
            return b''
        return self.codec.encode(kind, body)

    def finish(self, deadline):
        c.need(self.state in ('PREPARING','WAITING','STARTING','RUNNING'), 'OWNER_STATE')
        self.state = 'FINALIZING'
        # Keep owner alive until payload descendants are reaped and outputs
        # collected. Killing whole unit first would destroy the reaping owner.
        result = self.kernel.terminate_reap(deadline)
        c.need(type(result) is dict and set(result) == {'children_reaped','payload_io_closed'} and all(result[k] is True for k in result), 'OWNER_REAP_UNCERTAIN')
        self.state = 'RETAINING'
        return self.codec.encode('reaped', result)

    def retire(self):
        c.need(self.state == 'RETAINING', 'OWNER_STATE')
        self.state = 'RETIRED'


# Linux v6.8 x86 syscall_64.tbl and include/uapi/linux/landlock.h.
# Payload-only restrictions: owner stays outside the Landlock domain and keeps
# its reaping syscalls. New/unsupported calls fail closed, never auto-expanded.
# Actual kernel/runtime compatibility remains UNPROVEN until separate approval.
ALLOW_SYSCALLS = frozenset((
    0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,17,18,19,20,21,22,23,24,
    25,26,27,28,32,33,34,35,36,37,38,39,40,57,58,59,60,61,63,
    73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,
    95,96,97,98,99,100,102,104,107,108,109,110,111,112,115,118,120,
    121,124,125,127,128,130,131,132,137,138,140,143,145,146,147,148,
    158,186,187,191,192,193,194,195,196,201,202,204,213,217,218,219,
    221,228,229,230,231,232,233,235,247,257,258,261,262,263,264,265,
    266,267,268,269,270,271,273,275,276,277,278,280,281,283,284,285,
    286,287,290,291,292,293,295,296,309,316,318,324,326,327,328,332,
    334,436,437,439,441,449))
ALLOW = 0x7fff0000
DENY = 0x00050001  # SECCOMP_RET_ERRNO|EPERM
KILL = 0x80000000  # SECCOMP_RET_KILL_PROCESS


def payload_filter():
    # sock_filter tuples (code,jt,jf,k), seccomp_data arch4/nr0/args16.
    code = [(0x20,0,0,4),(0x15,1,0,0xc000003e),(0x06,0,0,KILL),
            (0x20,0,0,0),(0x45,0,1,0x40000000),(0x06,0,0,KILL)]
    for nr in sorted(ALLOW_SYSCALLS):
        code += [(0x15,0,1,nr),(0x06,0,0,ALLOW)]
    def restricted(nr, body):
        code.append((0x15,0,len(body),nr))
        code.extend(body)
    # No F_SETOWN/F_SETSIG/O_ASYNC -> cannot signal host through async pipe IO.
    fcntl = [(0x20,0,0,24)]
    for cmd in (0,1,2,3,5,6,7,1030):
        fcntl += [(0x15,0,1,cmd),(0x06,0,0,ALLOW)]
    fcntl += [(0x15,1,0,4),(0x06,0,0,DENY),(0x20,0,0,32),
              (0x45,0,1,0x2000),(0x06,0,0,DENY),(0x06,0,0,ALLOW)]
    restricted(72,fcntl)
    ioctl = [(0x20,0,0,24)]
    for request in (0x5401,0x5413,0x541b):  # TCGETS,TIOCGWINSZ,FIONREAD only
        ioctl += [(0x15,0,1,request),(0x06,0,0,ALLOW)]
    restricted(16,ioctl+[(0x06,0,0,DENY)])
    # pid==0 means own task; no foreign-process resource limit manipulation.
    restricted(302,[(0x20,0,0,16),(0x15,0,1,0),(0x06,0,0,ALLOW),(0x06,0,0,DENY)])
    # No alternate parent/tracer/namespaces or non-SIGCHLD exit notification.
    restricted(56,[(0x20,0,0,20),(0x15,1,0,0),(0x06,0,0,DENY),(0x20,0,0,16),(0x45,0,1,0x7e82a000),(0x06,0,0,DENY),
                   (0x54,0,0,0xff),(0x15,0,1,0),(0x06,0,0,ALLOW),
                   (0x15,0,1,17),(0x06,0,0,ALLOW),(0x06,0,0,DENY)])
    code.append((0x06,0,0,DENY))
    return tuple(code)


class _Filter(ctypes.Structure):
    _fields_ = [('code',ctypes.c_ushort),('jt',ctypes.c_ubyte),
                ('jf',ctypes.c_ubyte),('k',ctypes.c_uint)]
class _Program(ctypes.Structure):
    _fields_ = [('length',ctypes.c_ushort),('filter',ctypes.POINTER(_Filter))]
class _LandlockRule(ctypes.Structure):
    _pack_ = 1
    _fields_ = [('access',ctypes.c_uint64),('parent_fd',ctypes.c_int32)]

LL_EXEC,LL_WRITE,LL_READ,LL_DIR = 1,2,4,8
LL_ALL = (1 << 15)-1  # ABI3: includes REFER and TRUNCATE, no silent downgrade
LL_OUTPUT = sum(1 << n for n in (1,2,3,4,5,7,8,13,14))


def payload_paths(profile,role):
    c.validate(profile)
    c.need(role in c.ROLES, 'SANDBOX_ROLE')
    # Directory enumeration/traversal (builder opens '/' and each ancestor)
    # grants NO file read/execute. Landlock rights form an allow-union.
    rules = {'/':LL_DIR}
    for item in profile.inventory:
        if not item.directory:
            c.need(not any(item.path == x or item.path.startswith(x+'/')
                   for x in ('/proc','/sys','/dev')), 'SANDBOX_PSEUDO_INVENTORY')
            c.need(not item.path.startswith('/run/'), 'SANDBOX_AMBIENT_INPUT')
            rules[item.path] = LL_READ | (LL_EXEC if item.mode & 0o111 else 0)
    for name,_ in c.INPUTS[role]:
        rules['/run/ap2-supervisor/input/'+name] = LL_READ
    rules[OUTPUT] = LL_OUTPUT
    rules.update({'/dev/null':LL_READ|LL_WRITE,'/dev/random':LL_READ,'/dev/urandom':LL_READ})
    return tuple(sorted(rules.items()))


def restrict_payload(profile,role):
    """Called only in forked payload after all nonstdio inherited FDs close.

    No proc regular-file allow. Proc special-FD access is also constrained by
    Landlock's ptrace-domain hierarchy (owner outside), owner nondumpable, no
    inherited owner FDs, and no ptrace/process_vm/pidfd_getfd syscalls.
    Filesystem policy alone is not claimed to mediate proc pipe/socket objects.
    """
    c.need(platform.system() == 'Linux' and platform.machine() == 'x86_64', 'SANDBOX_ARCH')
    paths = payload_paths(profile,role)
    libc = ctypes.CDLL(None,use_errno=True)
    libc.syscall.restype = ctypes.c_long
    c.need(libc.syscall(444,0,0,1) >= 3, 'LANDLOCK_ABI')
    access = ctypes.c_uint64(LL_ALL)
    ruleset = libc.syscall(444,ctypes.byref(access),ctypes.sizeof(access),0)
    c.need(ruleset >= 0, 'LANDLOCK_CREATE')
    try:
        for path,rights in paths:
            fd = os.open(path,0x200000|os.O_NOFOLLOW|os.O_CLOEXEC)  # Linux O_PATH
            try:
                info = os.fstat(fd)
                kind = stat.S_IFMT(info.st_mode)
                c.need(not stat.S_ISLNK(info.st_mode), 'LANDLOCK_PATH')
                if path.startswith('/dev/'):
                    expected = {'/dev/null':(1,3),'/dev/random':(1,8),'/dev/urandom':(1,9)}[path]
                    c.need(kind == stat.S_IFCHR and (os.major(info.st_rdev),os.minor(info.st_rdev)) == expected, 'LANDLOCK_DEVICE')
                elif path in ('/',OUTPUT):
                    c.need(kind == stat.S_IFDIR, 'LANDLOCK_DIRECTORY')
                else:
                    c.need(kind == stat.S_IFREG and info.st_nlink == 1, 'LANDLOCK_FILE')
                rule = _LandlockRule(rights,fd)
                c.need(libc.syscall(445,ruleset,1,ctypes.byref(rule),0) == 0, 'LANDLOCK_ADD')
            finally:
                os.close(fd)
        c.need(libc.prctl(38,1,0,0,0) == 0, 'PAYLOAD_NNP')
        c.need(libc.syscall(446,ruleset,0) == 0, 'LANDLOCK_RESTRICT')
    finally:
        os.close(ruleset)
    instructions = payload_filter()
    array = (_Filter*len(instructions))(*(_Filter(*row) for row in instructions))
    program = _Program(len(instructions),array)
    c.need(libc.prctl(22,2,ctypes.byref(program),0,0) == 0, 'PAYLOAD_SECCOMP')


class NativeKernel:
    """Concrete Linux primitives, unreachable with the empty profile registry.

    Runs inside the admitted immutable root as the profiled unprivileged UID.
    External watchdog must preempt stalled callbacks; Python deadlines alone
    are not hard preemption. All target exec is from fixed role argv.
    """
    def __init__(self, profile_name, role, run, epoch):
        self.profile = c.select_native(profile_name)
        c.need(role in c.ROLES and type(run) is str and run.isascii() and run.isdigit(), 'IDENTITY')
        c.need(type(epoch) is int and 61 <= epoch <= 4102441200, 'EPOCH')
        self.role = role
        self.argv = c.payload_argv(role, epoch)
        self.unit = 'ap2-sup-'+run+'-'+role+'.service'
        self.payload_pid, self.selector = None, None
        self.fds = {}
        self.payload_reaped = False

    def prepare(self, deadline):
        self._before(deadline)
        libc = ctypes.CDLL(None, use_errno=True)
        c.need(libc.prctl(36, 1, 0, 0, 0) == 0 and libc.prctl(4, 0, 0, 0, 0) == 0, 'OWNER_PRCTL')
        for name in os.listdir('/proc/self/fd'):
            try:
                os.readlink('/proc/self/fd/'+name)
            except FileNotFoundError:
                continue
            c.need(name in ('0','1','2'), 'INHERITED_OWNER_FD')

    def _before(self, deadline):
        c.need(time.monotonic() < deadline, 'OWNER_DEADLINE')

    def children(self):
        # A concrete reaping owner must also verify cgroup membership, not infer
        # child ownership from a target's status. Task list covers all threads.
        result = set()
        for task in os.listdir('/proc/self/task'):
            with open('/proc/self/task/'+task+'/children', encoding='ascii') as handle:
                raw = handle.read(4097)
            c.need(len(raw) <= 4096 and all(x.isdigit() for x in raw.split()), 'OWNER_CHILDREN')
            result.update(map(int, raw.split()))
        return tuple(sorted(result))

    def spawn(self, deadline):
        self._before(deadline)
        # Allocate/ledger pipe ends BEFORE fork, avoiding a Popen constructor
        # failure which hides a live child or owned pipe object from this owner.
        for name in CAPS:
            read,write = os.pipe()
            self.fds[name+'-read'],self.fds[name+'-write'] = read,write
        self.fds['null'] = os.open('/dev/null',os.O_RDONLY|os.O_NOFOLLOW)
        c.need(all(fd < 1024 for fd in self.fds.values()), 'OWNER_FD_RANGE')
        self.payload_pid = os.fork()
        if self.payload_pid == 0:
            try:
                os.dup2(self.fds['null'],0)
                os.dup2(self.fds['stdout-write'],1)
                os.dup2(self.fds['stderr-write'],2)
                os.closerange(3,1024)  # all control/owner FDs absent in target
                restrict_payload(self.profile,self.role)
                os.execve(self.argv[0],self.argv,self.env)
            except BaseException:
                os._exit(78)
        for name in ('null','stdout-write','stderr-write'):
            fd,self.fds[name] = self.fds[name],None
            os.close(fd)
        self.selector = selectors.DefaultSelector()
        for name in CAPS:
            fd = self.fds[name+'-read']
            os.set_blocking(fd,False)
            self.selector.register(fd,selectors.EVENT_READ,name)
        self.exit_sent = False

    def event(self, limits, deadline):
        self._before(deadline)
        ready = self.selector.select(min(0.01,max(0,deadline-time.monotonic())))
        if ready:
            key = ready[0][0]
            raw = os.read(key.fd,min(4096,limits[key.data]))
            if raw:
                return ('data',key.data,raw)
            self.selector.unregister(key.fd)
            return ('eof',key.data)
        if not self.exit_sent:
            pid,status = os.waitpid(self.payload_pid,os.WNOHANG)
            if pid:
                self.exit_sent = self.payload_reaped = True
                return ('exit',os.waitstatus_to_exitcode(status))
        return ('idle',)

    def terminate_reap(self, deadline):
        # No numeric-PID kill after a race: pidfd pins identity. Whole-unit
        # fallback belongs to the outer watchdog and is never a reap receipt.
        failed = False
        try:
            while True:
                self._before(deadline)
                members = self._members()
                for pid in members:
                    if pid == os.getpid():
                        continue
                    try:
                        fd = os.pidfd_open(pid, 0)
                        try:
                            with open('/proc/self/fdinfo/'+str(fd), encoding='ascii') as info:
                                pinned = info.read(4096)
                            with open('/proc/'+str(pid)+'/cgroup', encoding='ascii') as info:
                                group = info.read(4096).strip()
                            c.need('Pid:\t'+str(pid)+'\n' in pinned and
                                   group == '0::/system.slice/'+self.unit, 'OWNER_PID_IDENTITY')
                            signal.pidfd_send_signal(fd, signal.SIGKILL)
                        finally:
                            os.close(fd)
                    except (ProcessLookupError, FileNotFoundError):
                        pass
                no_children = False
                while True:
                    try:
                        pid, _ = os.waitpid(-1, os.WNOHANG)
                    except ChildProcessError:
                        no_children = True; break
                    if pid == 0:
                        break
                if no_children and self._members() == (os.getpid(),):
                    break
        except BaseException:
            failed = True
        finally:
            if self.selector is not None:
                try:
                    self.selector.close()
                except BaseException:
                    failed = True
            for name in list(self.fds):
                fd,self.fds[name] = self.fds[name],None
                if fd is not None:
                    try:
                        os.close(fd)
                    except BaseException:
                        failed = True
        try:
            for name in os.listdir('/proc/self/fd'):
                try:
                    os.readlink('/proc/self/fd/'+name)
                except FileNotFoundError:
                    continue
                c.need(name in ('0','1','2'), 'OWNER_UNKNOWN_FD')
        except BaseException:
            failed = True
        c.need(not failed, 'OWNER_REAP_UNCERTAIN')
        return {'children_reaped': True, 'payload_io_closed': True}

    def _members(self):
        path = '/sys/fs/cgroup/system.slice/'+self.unit+'/cgroup.procs'
        with open(path, encoding='ascii') as handle:
            raw = handle.read(4097)
        c.need(len(raw) <= 4096 and all(x.isdigit() for x in raw.split()), 'OWNER_MEMBERS')
        return tuple(sorted(map(int, raw.split())))


def _write(raw, deadline):
    view = memoryview(raw)
    with selectors.DefaultSelector() as select:
        os.set_blocking(1, False)
        select.register(1, selectors.EVENT_WRITE)
        while view:
            c.need(time.monotonic() < deadline, 'OWNER_TRANSPORT_DEADLINE')
            if select.select(0.01):
                try:
                    count = os.write(1, view)
                except BlockingIOError:
                    continue
                c.need(count > 0, 'OWNER_TRANSPORT_CLOSED')
                view = view[count:]


def _control(deadline):
    data = bytearray()
    with selectors.DefaultSelector() as select:
        os.set_blocking(0, False)
        select.register(0, selectors.EVENT_READ)
        while time.monotonic() < deadline:
            if select.select(0.01):
                try:
                    part = os.read(0, 32-len(data))
                except BlockingIOError:
                    continue
                c.need(part, 'OWNER_CONTROL_CLOSED')
                data.extend(part)
                c.need(len(data) < 32, 'OWNER_CONTROL_LIMIT')
                if b'\n' in data:
                    c.need(bytes(data) in (b'GO\n', b'FINISH\n', b'RETIRE\n'), 'OWNER_CONTROL')
                    return bytes(data)
    raise c.Stop('OWNER_CONTROL_DEADLINE')


def _entry(args):
    # Dispatch and imports are fixed. Fake profiles cannot enter either branch.
    if args and args[0].startswith('--python-target='):
        role = args[0].split('=', 1)[1]
        profile = c.select_native(os.environ.get('AP2_PROFILE'))
        epoch = int(os.environ.get('AP2_EPOCH', '0'))
        c.need(tuple(args) == c.payload_argv(role, epoch)[5:], 'PYTHON_BOOTSTRAP_ARGV')
        sys.path[:] = profile.python_paths
        script = args[1]
        sys.argv[:] = [script, *args[2:]]
        import runpy
        runpy.run_path(script, run_name='__main__')
        return
    c.need(len(args) == 5 and args[0] == '--owner', 'OWNER_ENTRY')
    _, name, role, run, epoch_text = args
    profile = c.select_native(name)
    c.need(epoch_text.isascii() and epoch_text.isdigit(), 'EPOCH')
    kernel = NativeKernel(name, role, run, int(epoch_text))
    kernel.env = dict(c.environment(profile), AP2_PROFILE=name, AP2_EPOCH=epoch_text)
    owner = Owner(kernel, run, role)
    work_end = time.monotonic()+3
    cleanup_end = work_end+2
    _write(owner.prepare(work_end), work_end)
    command = _control(work_end)
    try:
        if command == b'GO\n':
            owner.go(work_end)
            while owner.exit is None or len(owner.ended) < 2:
                packet = owner.step(work_end)
                if packet:
                    _write(packet, work_end)
            c.need(_control(work_end) == b'FINISH\n', 'OWNER_CONTROL')
        else:
            c.need(command == b'FINISH\n', 'OWNER_CONTROL')
        _write(owner.finish(cleanup_end), cleanup_end)
        c.need(_control(cleanup_end) == b'RETIRE\n', 'OWNER_CONTROL')
        owner.retire()
    finally:
        if owner.state not in ('RETAINING', 'RETIRED'):
            kernel.terminate_reap(cleanup_end)


if __name__ == '__main__':
    try:
        _entry(sys.argv[1:])
    except (c.Stop, ValueError, OSError):
        print('{"status":"HOLD","reason":"NATIVE_PROFILE_OR_ENTRY_REJECTED"}', file=sys.stderr)
        raise SystemExit(78)
