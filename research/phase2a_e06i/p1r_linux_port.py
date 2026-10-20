"""Closed Linux adapter plus OFFLINE_FAKE integration path.

Native profile lookup precedes filesystem/process effects. No runtime profile is
approved in this stage. Owner receipts are NEVER copied into kernel observations.
No arbitrary command API or caller supplied argv is accepted.
"""
import base64
import hashlib
import re
import os
import secrets
import selectors
import stat
import subprocess
import time
from dataclasses import asdict
import p1r_execution_contract as c
import p1r_exec_owner as eo
import p1r_watchdog as wd

PROPERTIES = {'Type':'exec', 'PrivateNetwork':'yes', 'PrivateDevices':'yes',
    'ProtectSystem':'strict', 'ProtectHome':'yes', 'NoNewPrivileges':'yes',
    'CapabilityBoundingSet':'', 'AmbientCapabilities':'', 'RestrictSUIDSGID':'yes',
    'RestrictNamespaces':'yes', 'ProtectControlGroups':'yes', 'KillMode':'control-group',
    'Restart':'no', 'LimitNOFILE':'1024', 'Delegate':'no', 'SendSIGKILL':'yes', 'TimeoutStopSec':'1s',
    'RuntimeMaxSec':str(c.OWNER_SECONDS)+'s', 'MemoryMax':'67108864', 'MemorySwapMax':'0', 'TasksMax':'16',
    'InaccessiblePaths':'/tmp /var/tmp /dev/shm',
    'SystemCallFilter':'~@network-io', 'SystemCallArchitectures':'native',
    'RootDirectory':c.ROOT, 'MountAPIVFS':'yes'}
ENV = {'PATH':'/usr/bin:/bin', 'LANG':'C', 'LC_ALL':'C', 'SYSTEMD_COLORS':'0'}


def harmless_ipv6(raw):
    # Private netns can retain kernel loopback/unreachable rows. No external
    # interface or nonzero next hop is admissible; malformed rows fail closed.
    for line in raw.splitlines():
        fields = line.split()
        if (len(fields) != 10 or fields[9] != 'lo' or
            not all(re.fullmatch(r'[0-9A-Fa-f]{32}',fields[i]) for i in (0,2,4)) or
            not all(re.fullmatch(r'[0-9A-Fa-f]{2}',fields[i]) for i in (1,3)) or
            not all(re.fullmatch(r'[0-9A-Fa-f]{8}',fields[i]) for i in (5,6,7,8)) or
            fields[4] != '0'*32):
            return False
    return True


def unchanged(before, after):
    keys = ('st_dev','st_ino','st_mode','st_uid','st_gid','st_nlink','st_size','st_mtime_ns','st_ctime_ns')
    return all(getattr(before,k) == getattr(after,k) for k in keys)


class OwnedFD:
    def __init__(self, fd):
        self.fd = fd
    def close(self):
        fd, self.fd = self.fd, None
        if fd is not None:
            os.close(fd)


def mount_topology(raw, readonly, output):
    table = {}
    for line in raw.splitlines():
        pieces = line.split(' - ')
        c.need(len(pieces) == 2 and len(pieces[0].split()) >= 6 and len(pieces[1].split()) >= 3, 'MOUNT_FORMAT')
        fields = pieces[0].split()
        point, flags = fields[4], set(fields[5].split(','))
        c.need('\\' not in point and c.path_ok(point) or point == '/', 'MOUNT_PATH')
        c.need(point not in table, 'MOUNT_DUPLICATE')
        c.need(('rw' in flags) != ('ro' in flags), 'MOUNT_FLAGS')
        table[point] = (flags,pieces[1].split()[0])
        # Every effective mount must be readonly except the one bounded output.
        c.need(('rw' in flags and point == output) or ('ro' in flags and 'rw' not in flags), 'UNEXPECTED_WRITABLE_MOUNT')
    c.need('/' in table and output in table and table[output][1] == 'tmpfs' and
           {'rw','nosuid','nodev'} <= table[output][0], 'OUTPUT_MOUNT')
    for path in readonly:
        covering = [point for point in table if point == '/' or path == point or path.startswith(point+'/')]
        c.need(covering and 'ro' in table[max(covering,key=len)][0], 'READONLY_OVERMOUNT')
    return table


def fixed_plan(plan):
    import p1r_linux_supervisor as s
    c.need(type(plan.unit) is str and plan.unit == 'ap2-sup-'+plan.unit.split('-')[2]+'-'+plan.operation+'.service', 'PLAN_UNIT')
    run = plan.unit.split('-')[2]
    manifest = s.Manifest(tuple(s.Pin(p.path,p.size,p.sha256) for p in plan.pins),
                          int(plan.argv[plan.argv.index('--epoch')+1]) if plan.operation == 'builder' else 1700000000)
    expected = s.plan_for(plan.operation, run, manifest)
    c.need(asdict(plan) == asdict(expected), 'PLAN_OVERRIDE')
    return run


class LinuxPort:
    def __init__(self, profile, ops):
        c.need(getattr(ops, 'mode', None) == 'OFFLINE_FAKE' and
               profile.purpose == 'OFFLINE_FAKE', 'FAKE_ONLY')
        self._init(c.validate(profile), ops, 'OFFLINE_FAKE')

    @classmethod
    def native(cls, profile_name, role, run, inputs=None):
        profile = c.select_native(profile_name)  # empty registry: zero IO
        obj = cls.__new__(cls)
        obj._init(profile, NativeOps(profile, role, run, inputs), 'LINUX')
        return obj

    def _init(self, profile, ops, mode):
        self.profile, self.ops, self.mode = profile, ops, mode
        self.clock = ops.clock
        self.watchdog = wd.Watchdog(ops, self.clock)
        self.row = self.plan = self.decoder = None
        self.events = []
        self.phase, self.receipt = 'NEW', False
        self.artifacts = {}
        self.ended, self.payload_exit = set(), None
        self.counts = dict.fromkeys(eo.CAPS, 0)

    def reserve(self, plan):
        c.need(self.phase == 'NEW', 'PORT_CONSUMED')
        run = fixed_plan(plan)
        self.phase = 'RESERVING'
        self.row = self.watchdog.own(plan.unit)  # before any partial submit
        self.plan = plan
        self.decoder = eo.Codec(run, plan.operation)
        c.need(self.ops.absent(self.row) is True, 'UNIT_EXISTS')
        self.phase = 'RESERVED'

    def read_pinned(self, path, read_limit, deadline):
        self.watchdog.before(deadline)
        return self.ops.read_pinned(path, read_limit)

    def submit_gated(self, plan, deadline):
        c.need(self.phase in ('NEW', 'RESERVED'), 'PORT_CONSUMED')
        if self.phase == 'NEW':
            self.reserve(plan)
        c.need(asdict(self.plan) == asdict(plan), 'PLAN_OVERRIDE')
        self.watchdog.before(deadline)
        c.check_bytes(self.profile, self.ops.read_pinned)
        self.ops.verify_tree(self.profile)
        self.phase = 'SUBMITTING'
        self.ops.submit(self.row, plan, self.profile, deadline)
        self.phase = 'WAITING'
        kind, body = self._frame(deadline)
        c.need(kind == 'ready' and type(body) is dict and set(body) == {'waiting'} and body['waiting'] is True, 'OWNER_READY')

    def _frame(self, deadline):
        while not self.events:
            self.watchdog.before(deadline)
            raw = self.ops.receive(self.row, deadline)
            c.need(raw, 'OWNER_CHANNEL_CLOSED')
            self.events.extend(self.decoder.feed(raw))
        return self.events.pop(0)

    def observe_parent(self, unit, deadline):
        c.need(self.phase == 'WAITING' and unit == self.plan.unit, 'PORT_STATE')
        self.watchdog.before(deadline)
        observed = self.ops.readback(self.row, self.plan, self.profile, deadline)
        # Trusted owner binding is checked separately from parent kernel facts.
        c.need(observed.get('gate_waiting') is True, 'OWNER_GATE')
        return observed

    def go(self, unit, deadline):
        c.need(self.phase == 'WAITING' and unit == self.plan.unit, 'GO_STATE')
        self.phase = 'GO_SENT'
        self.ops.control(self.row, b'GO\n', deadline)
        self.phase = 'RUNNING'

    def next_event(self, unit, read_limits, deadline):
        c.need(self.phase == 'RUNNING' and unit == self.plan.unit and
               read_limits == {k:eo.CAPS[k]-self.counts[k]+1 for k in eo.CAPS}, 'PORT_EVENT_STATE')
        kind, body = self._frame(deadline)
        c.need(type(body) is dict, 'OWNER_BODY')
        if kind == 'data':
            c.need(set(body) == {'stream','bytes'} and body['stream'] in eo.CAPS and
                   body['stream'] not in self.ended and type(body['bytes']) is str, 'OWNER_DATA')
            try:
                data = base64.b64decode(body['bytes'], validate=True)
            except (ValueError, base64.binascii.Error) as exc:
                raise c.Stop('OWNER_BASE64') from exc
            stream = body['stream']
            c.need(base64.b64encode(data).decode('ascii') == body['bytes'] and
                   0 < len(data) <= min(4096,read_limits[stream]), 'OWNER_DATA')
            self.counts[stream] += len(data)
            c.need(self.counts[stream] <= eo.CAPS[stream], 'OWNER_OUTPUT_LIMIT')
            return ('data',stream,data)
        if kind == 'eof':
            c.need(set(body) == {'stream'} and body['stream'] in eo.CAPS and body['stream'] not in self.ended, 'OWNER_EOF')
            self.ended.add(body['stream'])
            return ('eof',body['stream'])
        c.need(kind == 'exit' and set(body) == {'code'} and type(body['code']) is int and self.payload_exit is None, 'OWNER_EXIT')
        self.payload_exit = body['code']
        return ('exit',body['code'])

    def finish_children(self, unit, deadline):
        c.need(self.row is not None and unit == self.plan.unit, 'PORT_IDENTITY')
        self.ops.control(self.row, b'FINISH\n', deadline)
        kind, body = self._frame(deadline)
        c.need(kind == 'reaped' and type(body) is dict and set(body) == {'children_reaped','payload_io_closed'} and all(body[k] is True for k in body), 'OWNER_REAP_UNCERTAIN')
        self.receipt = True
        return body

    def collect_outputs(self, unit, deadline):
        c.need(self.receipt and unit == self.plan.unit, 'COLLECT_BEFORE_REAP')
        self.watchdog.before(deadline)
        artifacts = self.ops.collect(self.row, self.plan.operation, deadline)
        c.check_artifacts(self.plan.operation, artifacts)
        self.artifacts = dict(artifacts)
        return dict(artifacts)

    def cancel_reap_submitter(self, unit, deadline):
        c.need(unit == self.plan.unit, 'PORT_IDENTITY')
        error = None
        try:
            self.ops.retire_owner(self.row, deadline)
            self.row.retired = True
        except BaseException as exc:
            error = exc
        self.row.submitter_reaped = self.ops.reap_submitter(self.row, deadline) is True
        if error is not None:
            raise error
        return self.row.submitter_reaped

    def stop_group(self, unit, deadline):
        c.need(unit == self.plan.unit, 'PORT_IDENTITY')
        self.ops.stop_unit(self.row, deadline)

    def finalize_owned(self, unit, deadline):
        c.need(unit == self.plan.unit, 'PORT_IDENTITY')
        failures = []
        while self.row.fds:
            handle = self.row.fds.pop()
            try:
                handle.close()
            except BaseException:
                failures.append(True)
        c.need(not failures, 'FD_CLOSE_UNCERTAIN')
        return {'unit':unit, 'children_reaped':self.receipt,
                'owned_io_closed':True, 'open_owned_fds':0}

    def observe_stopped(self, unit, deadline):
        c.need(unit == self.plan.unit, 'PORT_IDENTITY')
        c.need(self.ops.empty(self.row,deadline) is True and self.row.submitter_reaped, 'CLEANUP_UNCERTAIN')
        self.phase = 'CLOSED'
        return {'unit':unit, 'cgroup':'/system.slice/'+unit, 'active':'inactive', 'populated':0}

    def fallback_stop(self, deadline):
        # Called by the outer reaping parent only AFTER submitter barrier.
        failed = False
        try:
            self.ops.stop_unit(self.row, deadline)
        except BaseException:
            failed = True
        empty = self.ops.empty(self.row,deadline) is True
        c.need(not failed and empty, 'CLEANUP_UNCERTAIN')


class NativeOps:
    mode = 'LINUX'
    clock = staticmethod(time.monotonic)
    def __init__(self, profile, role, run, inputs=None):
        c.need(c.select_native(profile.name) == profile, 'PROFILE_AUTHORITY')
        self.profile, self.role, self.run = profile, role, run
        self.inputs = dict(c.frozen_inputs(role,{} if inputs is None else inputs))
        self.token = secrets.token_hex(16)
        self.snapshot = '/run/ap2-controller/ap2-sup-'+run+'-'+role+'-'+self.token
        self.ready_pid = None
        self.management_calls = 0

    def _query(self, row, action, deadline):
        # Fixed management vocabulary; never accepts caller commands/options.
        import re
        c.need(action in ('show','stop') and type(row.unit) is str and
               re.fullmatch(r'ap2-sup-[0-9]{1,20}-(builder|oracle|ruby)\.service',row.unit), 'MANAGER_OPERATION')
        self.management_calls += 1
        c.need(self.management_calls <= 64 and time.monotonic() < deadline, 'MANAGER_LIMIT')
        import u6_systemd_diagnostic as capture
        argv = ['/usr/bin/systemctl','--system','--no-ask-password',action,row.unit]
        if action == 'show':
            argv += ['--all']
        proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, close_fds=True, start_new_session=True, env=ENV)
        result = capture.capture(proc, deadline_seconds=min(1,deadline-time.monotonic()))
        c.need(result['query_reaped'] and not result['failure'], 'MANAGER_CAPTURE')
        if action == 'stop':
            c.need(result['returncode'] == 0 and not result['stderr'], 'MANAGER_STOP')
            return {}
        c.need(result['returncode'] in (0,1) and not result['stderr'], 'MANAGER_SHOW')
        values = {}
        for line in result['stdout'].splitlines():
            c.need('=' in line, 'MANAGER_PROPERTIES')
            key,value = line.split('=',1)
            c.need(key not in values, 'MANAGER_PROPERTIES')
            values[key] = value
        return values

    def absent(self, row):
        values = self._query(row,'show',time.monotonic()+1)
        return values.get('LoadState') == 'not-found' and values.get('ActiveState') == 'inactive'

    def read_pinned(self, path, limit):
        c.need(c.path_ok(path) and type(limit) is int and 1 <= limit <= c.MAX_FILE+1, 'READ_PIN')
        if path.startswith('/run/ap2-supervisor/input/'):
            name = path.rsplit('/',1)[1]
            c.need(name in self.inputs and len(self.inputs[name]) < limit, 'INPUT_PIN')
            return self.inputs[name]
        host = path if path.startswith(c.ROOT+'/') else c.ROOT+path
        fd = os.open(host, os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
        try:
            before = os.fstat(fd)
            c.need(stat.S_ISREG(before.st_mode) and before.st_nlink == 1 and before.st_size < limit, 'READ_PIN_TYPE')
            parts = bytearray()
            while len(parts) < limit:
                raw = os.read(fd,min(65536,limit-len(parts)))
                if not raw:
                    break
                parts.extend(raw)
            after = os.fstat(fd)
            c.need(tuple(getattr(before,k) for k in ('st_dev','st_ino','st_mode','st_uid','st_gid','st_nlink','st_size','st_mtime_ns','st_ctime_ns')) ==
                   tuple(getattr(after,k) for k in ('st_dev','st_ino','st_mode','st_uid','st_gid','st_nlink','st_size','st_mtime_ns','st_ctime_ns')) and len(parts) == before.st_size, 'READ_PIN_CHANGED')
            return bytes(parts)
        finally:
            os.close(fd)

    def verify_tree(self, profile):
        for root in ('/opt',c.ROOT):
            info = os.lstat(root)
            c.need(stat.S_ISDIR(info.st_mode) and not stat.S_ISLNK(info.st_mode) and
                   info.st_uid == 0 and stat.S_IMODE(info.st_mode) & 0o022 == 0, 'ROOT_OWNER')
        entries = {e.path:e for e in profile.inventory}
        seen = set()
        # No links, hardlinks, devices or ambient files in immutable root.
        for directory, dirs, files in os.walk(c.ROOT, followlinks=False):
            for name in dirs+files:
                host = directory+'/'+name
                path = host[len(c.ROOT):]
                c.need(path in entries and path not in seen, 'ROOT_EXTRA_PATH')
                entry = entries[path]; info = os.lstat(host)
                c.need(not stat.S_ISLNK(info.st_mode) and
                       (stat.S_ISDIR(info.st_mode) if entry.directory else stat.S_ISREG(info.st_mode)) and
                       stat.S_IMODE(info.st_mode) == entry.mode and info.st_uid == entry.uid and
                       info.st_gid == entry.gid and (entry.directory or info.st_nlink == 1), 'ROOT_METADATA')
                if not entry.directory:
                    raw = self.read_pinned(host,entry.size+1)
                    c.need(hashlib.sha256(raw).hexdigest() == entry.sha256, 'ROOT_HASH')
                seen.add(path)
        c.need(seen == set(entries), 'ROOT_MISSING_PATH')

    def _stage_inputs(self):
        # Runtime/root stays immutable. Only bounded public input bytes are
        # staged in a distinct root-owned directory, then bound readonly.
        info = os.lstat('/run')
        c.need(stat.S_ISDIR(info.st_mode) and not stat.S_ISLNK(info.st_mode) and info.st_uid == 0 and stat.S_IMODE(info.st_mode)&0o022 == 0, 'INPUT_ANCESTOR')
        try:
            os.mkdir('/run/ap2-controller',0o700)
        except FileExistsError:
            pass
        for path in ('/run','/run/ap2-controller'):
            info = os.lstat(path)
            c.need(stat.S_ISDIR(info.st_mode) and not stat.S_ISLNK(info.st_mode) and
                   info.st_uid == 0 and stat.S_IMODE(info.st_mode)&0o022 == 0, 'INPUT_ANCESTOR')
        os.mkdir(self.snapshot,0o700)  # no reuse/retry of an existing allocation
        parent = os.open(self.snapshot,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
        try:
            stamp = os.open('owner',os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o400,dir_fd=parent)
            try:
                c.need(os.write(stamp,self.token.encode('ascii')) == len(self.token), 'INPUT_STAMP')
            finally:
                os.close(stamp)
            os.mkdir('input',0o700,dir_fd=parent)
            directory = os.open('input',os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=parent)
            try:
                for name,raw in self.inputs.items():
                    fd = os.open(name,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o444,dir_fd=directory)
                    try:
                        os.fchmod(fd,0o444)  # exact readonly mode, independent of umask
                        view = memoryview(raw)
                        while view:
                            size = os.write(fd,view)
                            c.need(size > 0, 'INPUT_WRITE');view = view[size:]
                    finally:
                        os.close(fd)
                os.fchmod(directory,0o555)
            finally:
                os.close(directory)
        finally:
            os.close(parent)

    def _clean_inputs(self):
        # Exact random-token ownership, no recursive deletion/foreign paths.
        try:
            parent = os.open(self.snapshot,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
        except FileNotFoundError:
            return
        try:
            fd = os.open('owner',os.O_RDONLY|os.O_NOFOLLOW,dir_fd=parent)
            try:
                c.need(os.read(fd,65) == self.token.encode('ascii'), 'INPUT_OWNER')
            finally:
                os.close(fd)
            c.need(set(os.listdir(parent)) <= {'owner','input'}, 'INPUT_FOREIGN_PATH')
            try:
                directory = os.open('input',os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=parent)
            except FileNotFoundError:
                directory = None
            if directory is not None:
                try:
                    names = os.listdir(directory)
                    c.need(set(names) <= set(self.inputs), 'INPUT_FOREIGN_PATH')
                    for name in names:
                        info = os.stat(name,dir_fd=directory,follow_symlinks=False)
                        c.need(stat.S_ISREG(info.st_mode) and info.st_uid == 0 and info.st_nlink == 1, 'INPUT_FOREIGN_FILE')
                        os.unlink(name,dir_fd=directory)
                finally:
                    os.close(directory)
                os.rmdir('input',dir_fd=parent)
            os.unlink('owner',dir_fd=parent)
        finally:
            os.close(parent)
        os.rmdir(self.snapshot)

    def submit(self, row, plan, profile, deadline):
        c.need(plan.operation == self.role and fixed_plan(plan) == self.run, 'NATIVE_ROLE')
        self._stage_inputs()
        props = dict(PROPERTIES, BindReadOnlyPaths=self.snapshot+'/input:/run/ap2-supervisor/input', User=str(profile.uid), Group=str(profile.gid),
            Description='ap2-owned-'+self.token,
            ReadOnlyPaths=' '.join(plan.readonly+('/proc','/sys','/dev','/run')),
            ReadWritePaths=plan.output_dir,
            TemporaryFileSystem=plan.output_dir+':rw,size=32M,nr_inodes=256,mode=0700,uid='+str(profile.uid)+',gid='+str(profile.gid)+',nosuid,nodev')
        epoch = plan.argv[plan.argv.index('--epoch')+1] if plan.operation == 'builder' else '1700000000'
        argv = ['/usr/bin/systemd-run','--system','--quiet','--pipe','--no-ask-password',
                '--expand-environment=no','--unit='+row.unit]
        argv += ['--property='+key+'='+value for key,value in props.items()]
        argv += ['/usr/bin/python3','-I','-S','-B',eo.SOURCE+'/p1r_exec_owner.py',
                 '--owner',profile.name,plan.operation,self.run,epoch,
                 repr(float(deadline)),repr(float(deadline+(c.TOTAL_SECONDS-c.WORK_SECONDS)))]
        self.requested = props
        row.submitter = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, close_fds=True, start_new_session=True, env=ENV)
        row.fds.extend((row.submitter.stdin,row.submitter.stdout,row.submitter.stderr))
        for handle in row.fds:
            os.set_blocking(handle.fileno(),False)
        self.selector = selectors.DefaultSelector()
        row.fds.append(self.selector)
        self.selector.register(row.submitter.stdout, selectors.EVENT_READ, 'owner')
        self.selector.register(row.submitter.stderr, selectors.EVENT_READ, 'manager')

    def receive(self,row,deadline):
        while time.monotonic() < deadline:
            for key,_ in self.selector.select(0.01):
                raw = os.read(key.fd,4096)
                if key.data == 'manager':
                    c.need(not raw, 'MANAGER_STDERR')
                    self.selector.unregister(key.fileobj)
                    continue
                return raw
        raise c.Stop('OWNER_TRANSPORT_DEADLINE')

    def control(self,row,raw,deadline):
        c.need(raw in (b'GO\n',b'FINISH\n',b'RETIRE\n'), 'CONTROL')
        view = memoryview(raw)
        while view and time.monotonic() < deadline:
            try:
                n = os.write(row.submitter.stdin.fileno(),view)
                c.need(n > 0, 'CONTROL_CLOSED'); view = view[n:]
            except BlockingIOError:
                import select
                select.select([], [row.submitter.stdin], [], 0.01)
        c.need(not view, 'CONTROL_DEADLINE')

    def readback(self,row,plan,profile,deadline):
        import p1r_linux_supervisor as s
        values = self._query(row,'show',deadline)
        c.need(values.get('Description') == 'ap2-owned-'+self.token and
               values.get('ControlGroup') == '/system.slice/'+row.unit and
               values.get('ActiveState') == 'active', 'UNIT_IDENTITY')
        # Duration properties use manager-normalized names/units.
        normalized = {'RuntimeMaxSec':'RuntimeMaxUSec', 'TimeoutStopSec':'TimeoutStopUSec'}
        for key,value in self.requested.items():
            if key in ('Description','RootDirectory','ReadOnlyPaths','TemporaryFileSystem'):
                c.need(values.get(key) == value, 'UNIT_PROPERTY')
            elif key in normalized:
                c.need(values.get(normalized[key]) == value, 'UNIT_PROPERTY')
            elif key not in ('CapabilityBoundingSet','AmbientCapabilities','SystemCallFilter'):
                c.need(values.get(key) == value, 'UNIT_PROPERTY')
        c.need(values.get('CapabilityBoundingSet') == '' and values.get('AmbientCapabilities') == '' and
               values.get('SystemCallFilter') == '~@network-io', 'UNIT_SANDBOX')
        pid = int(values.get('MainPID','0')); c.need(pid > 1, 'OWNER_PID')
        self.ready_pid = pid
        self.owner_pidfd = OwnedFD(os.pidfd_open(pid,0))
        row.fds.append(self.owner_pidfd)
        self._owner_alive()
        self.owner_root = OwnedFD(os.open('/proc/'+str(pid)+'/root',os.O_RDONLY|os.O_DIRECTORY))
        row.fds.append(self.owner_root)
        self._owner_alive()
        proc = '/proc/'+str(pid)
        fields = dict(line.split(':',1) for line in self._text(proc+'/status',8192).splitlines() if ':' in line)
        c.need([int(x) for x in fields['Uid'].split()] == [profile.uid]*4 and
               [int(x) for x in fields['Gid'].split()] == [profile.gid]*4 and
               fields['NoNewPrivs'].strip() == '1' and int(fields['CapEff'],16) == 0 and
               fields['Seccomp'].strip() == '2', 'KERNEL_PRIVILEGES')
        cg = '/system.slice/'+row.unit
        c.need(self._text(proc+'/cgroup',4096).strip() == '0::'+cg, 'KERNEL_CGROUP')
        members = tuple(sorted(map(int,self._text('/sys/fs/cgroup'+cg+'/cgroup.procs',4096).split())))
        c.need(members == (pid,), 'PRE_GO_MEMBERS')
        for key,value in (('memory.max','67108864'),('memory.swap.max','0'),('pids.max','16')):
            c.need(self._text('/sys/fs/cgroup'+cg+'/'+key,256).strip() == value, 'KERNEL_LIMIT')
        mount_topology(self._text(proc+'/mountinfo',65536),plan.readonly,plan.output_dir)
        directory_fd = self._output_dir()
        try:
            info = os.fstat(directory_fd); fs = os.fstatvfs(directory_fd)
            c.need(stat.S_IMODE(info.st_mode) == 0o700 and info.st_uid == profile.uid and
                   info.st_gid == profile.gid and fs.f_blocks*fs.f_frsize == 33554432 and fs.f_files == 256, 'OUTPUT_OWNER_QUOTA')
        finally:
            os.close(directory_fd)
        fds = [os.readlink(proc+'/fd/'+name) for name in os.listdir(proc+'/fd')]
        c.need(not any(p.startswith('socket:') for p in fds) and
               all(os.readlink(proc+'/fd/'+str(n)).startswith('pipe:') for n in (0,1,2)), 'OWNER_FDS')
        routes = self._text(proc+'/net/route',8192).splitlines()[1:]
        c.need(not routes and harmless_ipv6(self._text(proc+'/net/ipv6_route',8192)), 'OWNER_ROUTES')
        # Recheck exact immutable tree immediately before GO; host root is TCB.
        self.verify_tree(profile)
        self._verify_owner_pins(plan,profile)
        return {'unit':row.unit,'cgroup':cg,'pid':pid,'uid':profile.uid,'gid':profile.gid,
            'netns':os.readlink(proc+'/ns/net'),'parent_netns':os.readlink('/proc/self/ns/net'),
            'mntns':os.readlink(proc+'/ns/mnt'),'parent_mntns':os.readlink('/proc/self/ns/mnt'),
            'no_new_privileges':True,'effective_caps':0,'readonly':plan.readonly,'writable':(plan.output_dir,),
            'memory_max':s.MEMORY,'swap_max':0,'pids_max':s.TASKS,'scratch_bytes':s.SCRATCH,'inodes':s.INODES,
            'sealed_files':plan.pins,'network_routes':0,'inherited_sockets':0,'gate_waiting':True,
            'restart':False,'delegate':False,'kill_mode':'control-group','cgroup_pids':members,
            'socket_families':(),'inaccessible':('/tmp','/var/tmp','/dev/shm'),'private_devices':True,
            'protected_cgroup':True,'suid_sgid':False,'new_namespaces':False,'rootfs_readonly':True,
            'fd_streams':('pipe','pipe','pipe'),'scratch_fs':'tmpfs','mount_flags':('rw','nosuid','nodev')}

    def _text(self,path,cap):
        with open(path,encoding='ascii') as handle:
            raw = handle.read(cap+1)
        c.need(len(raw) <= cap, 'READBACK_LIMIT')
        return raw

    def _verify_owner_pins(self, plan, profile):
        # Hash executable/source/runtime bytes through retained owner root, not
        # merely through the host staging tree (readonly overmount substitution).
        expected = {entry.path:entry for entry in profile.inventory if not entry.directory}
        for pin in plan.pins:
            if pin.path.startswith('/run/ap2-supervisor/input/'):
                continue  # checked below as dynamic, immutable input bytes
            c.need(pin.path in expected and expected[pin.path].size == pin.size and
                   expected[pin.path].sha256 == pin.sha256, 'PIN_PROFILE_MISMATCH')
        items = [(entry.path,entry.size,entry.sha256) for entry in profile.inventory if not entry.directory]
        items += [(pin.path,pin.size,pin.sha256) for pin in plan.pins if pin.path.startswith('/run/ap2-supervisor/input/')]
        for path,size,digest in items:
            self._owner_alive()
            current = os.dup(self.owner_root.fd)
            try:
                pieces = path.split('/')[1:]
                for name in pieces[:-1]:
                    child = os.open(name,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=current)
                    previous,current = current,child
                    os.close(previous)
                child = os.open(pieces[-1],os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK,dir_fd=current)
                try:
                    info = os.fstat(child)
                    c.need(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and info.st_size == size, 'OWNER_PIN_TYPE')
                    if path in expected:
                        entry = expected[path]
                        c.need(stat.S_IMODE(info.st_mode) == entry.mode and info.st_uid == entry.uid and info.st_gid == entry.gid, 'OWNER_PIN_METADATA')
                    hasher = hashlib.sha256();count = 0
                    while count <= size:
                        raw = os.read(child,min(65536,size+1-count))
                        if not raw:
                            break
                        hasher.update(raw);count += len(raw)
                    c.need(count == size and hasher.hexdigest() == digest and unchanged(info,os.fstat(child)), 'OWNER_PIN_HASH')
                finally:
                    os.close(child)
            finally:
                os.close(current)
        self._owner_alive()

    def _owner_alive(self):
        import select
        c.need(self.owner_pidfd.fd is not None and not select.select([self.owner_pidfd.fd],[],[],0)[0], 'OWNER_GONE')
        # pidfd identity survives PID reuse. /proc/fdinfo reports -1 after death.
        pinned = self._text('/proc/self/fdinfo/'+str(self.owner_pidfd.fd),4096)
        c.need('Pid:\t'+str(self.ready_pid)+'\n' in pinned, 'OWNER_PID_IDENTITY')

    def _output_dir(self):
        self._owner_alive()
        current = os.dup(self.owner_root.fd)
        try:
            for name in eo.OUTPUT.split('/')[1:]:
                child = os.open(name,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=current)
                previous, current = current, child
                os.close(previous)
            self._owner_alive()
            result,current = current,None
            return result
        finally:
            if current is not None:
                os.close(current)

    def collect(self,row,role,deadline):
        c.need(self.ready_pid is not None, 'OWNER_UNKNOWN')
        fd = self._output_dir()  # anchored root, never reopen a numeric PID path
        result = {}
        try:
            c.need(set(os.listdir(fd)) == {name for name,_ in c.OUTPUTS[role]}, 'OUTPUT_NAMES')
            for name,cap in c.OUTPUTS[role]:
                c.need(time.monotonic() < deadline, 'COLLECT_DEADLINE')
                child = os.open(name,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK,dir_fd=fd)
                try:
                    info = os.fstat(child)
                    c.need(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and
                           info.st_uid == self.profile.uid and 0 < info.st_size <= cap, 'OUTPUT_FILE')
                    raw = bytearray()
                    while len(raw) <= cap:
                        part = os.read(child,min(65536,cap+1-len(raw)))
                        if not part:
                            break
                        raw.extend(part)
                    c.need(unchanged(info,os.fstat(child)) and len(raw) == info.st_size, 'OUTPUT_CHANGED')
                    result[name] = bytes(raw)
                finally:
                    os.close(child)
        finally:
            os.close(fd)
        self._owner_alive()
        return result

    def retire_owner(self,row,deadline):
        if row.submitter is not None:
            self.control(row,b'RETIRE\n',deadline)

    def reap_submitter(self,row,deadline):
        if row.submitter is None:
            return False  # no handle is not evidence of no partial registration
        proc = row.submitter
        while time.monotonic() < deadline:
            code = proc.poll()
            if code is not None:
                return code == 0
            try:
                proc.wait(timeout=min(0.01,max(0,deadline-time.monotonic())))
            except subprocess.TimeoutExpired:
                pass
        # Exact Popen child identity, not a guessed PID/process group.
        proc.kill()
        try:
            proc.wait(timeout=max(0.001,deadline-time.monotonic()))
        except subprocess.TimeoutExpired:
            return False
        return False

    def stop_unit(self,row,deadline):
        values = self._query(row,'show',deadline)
        if values.get('LoadState') == 'not-found':
            return
        c.need(values.get('Description') == 'ap2-owned-'+self.token, 'FOREIGN_UNIT')
        self._query(row,'stop',deadline)

    def empty(self,row,deadline):
        values = self._query(row,'show',deadline)
        c.need(values.get('LoadState') == 'not-found' or values.get('Description') == 'ap2-owned-'+self.token, 'FOREIGN_UNIT')
        c.need(values.get('ActiveState') in ('inactive','failed'), 'UNIT_ACTIVE')
        path = '/sys/fs/cgroup/system.slice/'+row.unit+'/cgroup.events'
        try:
            fields = dict(line.split() for line in self._text(path,4096).splitlines())
        except FileNotFoundError:
            fields = {'populated':'0'}
        if fields.get('populated') == '0':
            self._clean_inputs()
            return True
        return False
