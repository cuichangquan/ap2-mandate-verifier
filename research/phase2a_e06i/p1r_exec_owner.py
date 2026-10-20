"""Trusted owner state machine and closed Linux syscall implementation.

The owner is MainPID/subreaper, not the payload. Its control pipe is never
inherited by payloads. Owner frames attest its own waits/FDs, NOT isolation.
Native construction requires an approved registry profile (none ships).
"""
import base64
import ctypes
import json
import os
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
