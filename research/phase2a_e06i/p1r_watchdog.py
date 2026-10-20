"""Outside-unit allocation/cleanup watchdog. Native entry has no approved profile.

A missing owner reap receipt is permanently uncertain, even if fallback kills
all processes. Submitter barrier ALWAYS precedes final unit stop (late register).
FD ownership is disarmed before close: never retry a reused descriptor number.
"""
import math
import re
import os
import signal
import time
import select
from dataclasses import dataclass, field
import p1r_execution_contract as c

@dataclass
class Allocation:
    unit: str
    submitter: object = None
    fds: list = field(default_factory=list)
    owner_reaped: bool = False
    retired: bool = False
    submitter_reaped: bool = False
    stopped: bool = False
    closed: bool = False

class Watchdog:
    def __init__(self, ops, clock=time.monotonic):
        self.ops, self.clock, self.allocations = ops, clock, {}
        self.last = None

    def before(self, deadline):
        now = self.clock()
        c.need(type(now) in (int,float) and math.isfinite(now) and now >= 0 and
               (self.last is None or now >= self.last) and now < deadline, 'WATCHDOG_DEADLINE')
        self.last = now

    def own(self, unit):
        c.need(type(unit) is str and re.fullmatch(r'ap2-sup-[0-9]{1,20}-(builder|oracle|ruby)\.service', unit) and unit not in self.allocations, 'UNIT_REUSE')
        self.before(float('inf'))
        row = self.allocations[unit] = Allocation(unit)
        return row

    def cleanup(self, unit, deadline, *, owner_receipt):
        row = self.allocations[unit]
        failures = []
        # This sequence runs on ordinary completion AND outer controller death.
        # Receipt verification must precede retirement; fallback never invents it.
        row.owner_reaped = owner_receipt is True
        for name in ('retire', 'submitter', 'stop', 'close', 'empty'):
            try:
                self.before(deadline)
                if name == 'retire':
                    self.ops.retire_owner(row, deadline)
                    row.retired = True
                elif name == 'submitter':
                    row.submitter_reaped = self.ops.reap_submitter(row, deadline) is True
                    c.need(row.submitter_reaped, 'SUBMITTER_UNREAPED')
                elif name == 'stop':
                    self.ops.stop_unit(row, deadline)
                    row.stopped = True
                elif name == 'close':
                    bad = False
                    while row.fds:
                        handle = row.fds.pop()  # ownership disarmed before close
                        try:
                            handle.close()
                        except BaseException:
                            bad = True
                    c.need(not bad, 'FD_CLOSE_UNCERTAIN')
                    row.closed = True
                else:
                    c.need(self.ops.empty(row, deadline) is True, 'GROUP_NOT_EMPTY')
            except BaseException:
                failures.append(name)
        c.need(row.owner_reaped and row.retired and row.submitter_reaped and
               row.stopped and row.closed and not failures, 'CLEANUP_UNCERTAIN')
        return True

    def controller_lost(self, unit, deadline):
        # No clean completion can be emitted by this fallback path.
        try:
            self.cleanup(unit, deadline, owner_receipt=False)
        finally:
            raise c.Stop('CONTROLLER_LOST_CLEANUP_UNCERTAIN')


def _write_result(fd, raw, deadline):
    c.need(type(raw) is bytes and 0 < len(raw) <= c.MAX_RESULT, 'WATCHDOG_RESULT')
    os.set_blocking(fd,False)
    view = memoryview(raw)
    while view:
        c.need(time.monotonic() < deadline, 'WATCHDOG_RESULT_DEADLINE')
        if select.select([], [fd], [], 0.01)[1]:
            try:
                count = os.write(fd,view[:16384])
            except BlockingIOError:
                continue
            c.need(0 < count <= len(view), 'WATCHDOG_RESULT_WRITE')
            view = view[count:]


class NativeWatchdog:
    """Dedicated OS parent of the fixed controller; not a PID/callback API.

    Registry admission precedes ALL Linux effects. The fixed worker inherits
    the allocation identity; outside parent adopts late submitters after worker
    death, reaps them, then performs final owned-unit stop. Fallback is HOLD.
    """
    def __init__(self, profile_name):
        self.profile = c.select_native(profile_name)
        self.profile_name = profile_name

    def run(self, role, run, manifest, inputs=None):
        import ctypes
        import json
        import p1r_linux_port as lp
        import p1r_linux_supervisor as supervisor
        c.need(role in c.ROLES and type(run) is str and run.isascii() and run.isdigit() and len(run) <= 20, 'IDENTITY')
        c.need(__name__ == '__main__', 'WATCHDOG_DEDICATED_ENTRY_REQUIRED')
        c.frozen_inputs(role,{} if inputs is None else inputs)
        port = lp.LinuxPort.native(self.profile_name,role,run,inputs)
        plan = supervisor.plan_for(role,run,manifest)
        # Reservation query cannot submit a target. All subsequent allocation,
        # including pipe/fork SETUP, is under one ownership/failure guard.
        port.reserve(plan)
        handles = {'read':None,'write':None,'pid':None}
        child = None
        status = None
        success = False
        result = None
        primary = None
        errors = []
        deadline = time.monotonic()+6
        def close_owned(name):
            handle,handles[name] = handles[name],None
            if handle is not None:
                os.close(handle)
        try:
            libc = ctypes.CDLL(None,use_errno=True)
            c.need(libc.prctl(36,1,0,0,0) == 0, 'WATCHDOG_SUBREAPER')
            signal.signal(signal.SIGCHLD,signal.SIG_DFL)
            handles['read'],handles['write'] = os.pipe()
            child = os.fork()  # PID recorded before close/pidfd/nonblocking calls
            if child == 0:
                try:
                    close_owned('read')
                    result = supervisor.Supervisor(port).run_native(role,run,manifest)
                    raw = c.encode_result(result)
                    _write_result(handles['write'],raw,deadline-2)
                    os._exit(0)
                except BaseException:
                    os._exit(78)
            close_owned('write')
            handles['pid'] = os.pidfd_open(child,0)
            os.set_blocking(handles['read'],False)
            data = bytearray()
            eof = False
            while time.monotonic() < deadline-2:
                if not eof:
                    try:
                        chunk = os.read(handles['read'],min(65536,c.MAX_RESULT+1-len(data)))
                    except BlockingIOError:
                        chunk = None
                    if chunk == b'':
                        eof = True
                    elif chunk is not None:
                        data.extend(chunk)
                        c.need(len(data) <= c.MAX_RESULT, 'WATCHDOG_RESULT')
                if status is None:
                    pid,value = os.waitpid(child,os.WNOHANG)
                    if pid:
                        status = value
                if status is not None and eof:
                    break
                select.select(([handles['pid']] if status is None else [])+
                              ([handles['read']] if not eof else []),[],[],0.01)
            if status is not None and os.waitstatus_to_exitcode(status) == 0 and eof:
                result = c.decode_result(bytes(data),role,run,manifest)
                success = True
            c.need(success, 'WATCHDOG_WORKER_OR_RESULT')
        except BaseException as error:
            primary = error
        finally:
            if not success:
                # Each action is independent. An allocation/signal failure must
                # NEVER bypass adopted-child barrier, final stop or FD close.
                if child is not None and child > 0 and status is None:
                    try:
                        if handles['pid'] is not None:
                            signal.pidfd_send_signal(handles['pid'],signal.SIGKILL)
                        else:
                            # Dedicated single-threaded parent still owns this
                            # unreaped child PID, so the kernel cannot reuse it.
                            os.kill(child,signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    except BaseException:
                        errors.append('worker-kill')
                try:
                    self._fallback(port,deadline)
                except BaseException:
                    errors.append('fallback')
            for name in ('pid','read','write'):
                try:
                    close_owned(name)
                except BaseException:
                    errors.append('fd-close')
        c.need(success and not errors and primary is None, 'CONTROLLER_LOST_CLEANUP_UNCERTAIN')
        return result

    def _fallback(self, port, deadline):
        errors = []
        try:
            self._reap_adopted(min(time.monotonic()+0.75,deadline-0.75))
        except BaseException:
            errors.append('reap')
        try:
            port.fallback_stop(deadline)
        except BaseException:
            errors.append('stop/readback')
        c.need(not errors, 'CLEANUP_UNCERTAIN')

    def _reap_adopted(self, deadline):
        while time.monotonic() < deadline:
            try:
                while os.waitpid(-1, os.WNOHANG)[0]:
                    pass
            except ChildProcessError:
                return
            with open('/proc/self/task/'+str(os.getpid())+'/children', encoding='ascii') as handle:
                raw = handle.read(4097)
            c.need(len(raw) <= 4096 and all(p.isdigit() for p in raw.split()), 'WATCHDOG_CHILDREN')
            for text in raw.split():
                pid = int(text)
                try:
                    handle = os.pidfd_open(pid, 0)
                    try:
                        # After pidfd_open confirm this still denotes our child,
                        # not a recycled numeric PID belonging to someone else.
                        with open('/proc/self/fdinfo/'+str(handle), encoding='ascii') as info:
                            pinned = info.read(4096)
                        with open('/proc/'+text+'/status', encoding='ascii') as info:
                            fields = dict(line.split(':',1) for line in info.read(8192).splitlines() if ':' in line)
                        c.need('Pid:\t'+text+'\n' in pinned and int(fields['PPid']) == os.getpid(), 'WATCHDOG_PID_IDENTITY')
                        signal.pidfd_send_signal(handle, signal.SIGKILL)
                    finally:
                        os.close(handle)
                except (ProcessLookupError, FileNotFoundError):
                    pass
        raise c.Stop('WATCHDOG_REAP_DEADLINE')

if __name__ == '__main__':
    import base64,json,sys
    import p1r_exec_owner as owner
    try:
        c.need(len(sys.argv) == 5, 'WATCHDOG_ENTRY')
        _,name,role,run,epoch = sys.argv
        profile = c.select_native(name)  # empty: refuse BEFORE reading input
        c.need(epoch.isascii() and epoch.isdigit(), 'EPOCH')
        raw = sys.stdin.buffer.read(c.MAX_RESULT+1)
        c.need(len(raw) <= c.MAX_RESULT, 'INPUT_LIMIT')
        packet = json.loads(raw,object_pairs_hook=owner.unique)
        c.need(type(packet) is dict, 'INPUT_NAMES')
        inputs = {}
        for key,value in packet.items():
            c.need(type(value) is str, 'INPUT_ENCODING')
            data = base64.b64decode(value,validate=True)
            c.need(base64.b64encode(data).decode('ascii') == value, 'INPUT_ENCODING')
            inputs[key] = data
        c.frozen_inputs(role,inputs)
        manifest = c.manifest_for(profile,role,int(epoch),inputs)
        result = NativeWatchdog(name).run(role,run,manifest,inputs)
        print(c.encode_result(result).decode('ascii'))
    except (c.Stop,ValueError,OSError):
        print('{"status":"HOLD","reason":"NATIVE_PROFILE_OR_INPUT_REJECTED"}')
        raise SystemExit(78)
