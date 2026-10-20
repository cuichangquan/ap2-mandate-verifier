"""Fixed-operation supervisor controller; OFFLINE_FAKE port only in this stage.

Supported: fixed argv, pinned byte checks, pre-GO admission, bounded event
capture, one-shot lifecycle, and submitter-reap -> group-stop -> owned child/IO
finalization -> empty readback.
A port is trusted parent-side infrastructure, NEVER a target-supplied receipt.
Mocks test ordering/validation, not kernel enforcement or source authority.

NOT IMPLEMENTED: Linux/systemd port, gated-exec launcher, authenticated complete
runtime/import manifests, installer, file staging/output collection, report
comparison and AP2 integration. No subprocess/socket or import-time I/O exists.
Missing port/pins or any live-mode request fails closed. CLI always exits HOLD.
The U6 64MiB/32MiB ceilings below are conservative MODEL bounds, not evidence
that AP2 workloads fit; PR136's 2GiB/8GiB design ceilings are not adopted.
"""
from dataclasses import dataclass
import hashlib
import math
import re
import time
from typing import Protocol

RUNTIME = '/opt/ap2-runtime'
SOURCE = '/opt/ap2-source/research/phase2a_e06i'
UPSTREAM = '/opt/ap2-upstream'
INPUT = '/run/ap2-supervisor/input'
OUTPUT = '/run/ap2-supervisor/output'
PYTHON = RUNTIME + '/bin/python3'
RUBY = RUNTIME + '/bin/ruby'
LAUNCHER = RUNTIME + '/trusted_site_launcher.py'
READONLY = (RUNTIME, '/opt/ap2-source', UPSTREAM, INPUT)
MEMORY = 67108864
SCRATCH = 33554432
INODES = 256
TASKS = 16
STDOUT = 65536
STDERR = 4096
WORK_SECONDS = 3
TOTAL_SECONDS = 6
CLEANUP_RESERVE = 2
MAX_EVENTS = 256
MAX_FILES = 512
MAX_FILE_BYTES = 16777216
MAX_PINNED_BYTES = 33554432


class Stop(RuntimeError):
    """Fixed, non-sensitive reason; no raw backend diagnostics in reports."""


def need(condition, code):
    if not condition:
        raise Stop(code)


@dataclass(frozen=True)
class Pin:
    path: str
    size: int
    sha256: str


@dataclass(frozen=True)
class Manifest:
    """Caller expectations only; complete closure/authenticity is not attested."""
    files: tuple[Pin, ...]
    epoch: int


@dataclass(frozen=True)
class Plan:
    unit: str
    operation: str
    argv: tuple[str, ...]
    pins: tuple[Pin, ...]
    expected_exit: int
    readonly: tuple[str, ...] = READONLY
    output_dir: str = OUTPUT
    memory_bytes: int = MEMORY
    swap_bytes: int = 0
    tasks: int = TASKS
    scratch_bytes: int = SCRATCH
    inodes: int = INODES
    stdout_cap: int = STDOUT
    stderr_cap: int = STDERR
    runtime_seconds: int = WORK_SECONDS


class Port(Protocol):
    """Trusted infrastructure seam. ONLY OFFLINE_FAKE is supported here.

    A future separately reviewed Linux port must own/track the submitter BEFORE
    submission can partially succeed, reject pre-existing unit identities,
    freeze checked bytes/paths until cleanup,
    gate target exec on GO, and independently read /proc/cgroup/mount state.
    Its bounded calls need an external watchdog: this controller cannot preempt
    an arbitrary blocking Python callback. next_event must honor each stream in read_limits,
    and read_pinned must close owned handles even when its read fails.
    stop_group must stop the entire exact owned cgroup (including setsid forks),
    with bounded TERM/KILL; a process group alone is insufficient. Reap/stop
    must remain callable after partial submit and during every exception path.
    finalize_owned must use a parent-owned descendant/descriptor ledger and a
    suitable OS reaping owner (not merely infer reaping from an empty cgroup).
    It must attempt all waits/closes, including after partial submission, and
    must never close a reused/foreign descriptor. No such OS boundary ships.
    """
    mode: str
    def read_pinned(self, path: str, read_limit: int, deadline: float) -> bytes: ...
    def submit_gated(self, plan: Plan, deadline: float) -> None: ...
    def observe_parent(self, unit: str, deadline: float) -> dict: ...
    def go(self, unit: str, deadline: float) -> None: ...
    def next_event(self, unit: str, read_limits: dict, deadline: float) -> tuple: ...
    def cancel_reap_submitter(self, unit: str, deadline: float) -> bool: ...
    def stop_group(self, unit: str, deadline: float) -> None: ...
    def finalize_owned(self, unit: str, deadline: float) -> dict: ...
    def observe_stopped(self, unit: str, deadline: float) -> dict: ...


def plan_for(operation, run_id, manifest):
    """No caller argv, executable override, shell, environment or code string."""
    need(type(operation) is str and operation in ('builder', 'oracle', 'ruby'), 'OPERATION')
    need(type(run_id) is str and re.fullmatch(r'[0-9]{1,20}', run_id), 'RUN_ID')
    need(type(manifest) is Manifest and type(manifest.files) is tuple and
         1 <= len(manifest.files) <= MAX_FILES, 'MANIFEST')
    need(type(manifest.epoch) is int and 61 <= manifest.epoch <= 4102441200, 'EPOCH')
    paths = set()
    total = 0
    for pin in manifest.files:
        need(type(pin) is Pin and type(pin.path) is str and 1 <= len(pin.path) <= 1024 and pin.path.isascii() and
             re.fullmatch(r'/(?:[A-Za-z0-9_-][A-Za-z0-9_.-]*/)*[A-Za-z0-9_-][A-Za-z0-9_.-]*', pin.path), 'PIN_PATH')
        need(any(pin.path.startswith(root + '/') for root in READONLY) and
             pin.path not in paths, 'PIN_SCOPE_OR_DUPLICATE')
        need(type(pin.size) is int and 0 < pin.size <= MAX_FILE_BYTES and
             type(pin.sha256) is str and re.fullmatch(r'[a-f0-9]{64}', pin.sha256), 'PIN')
        paths.add(pin.path)
        total += pin.size
    need(total <= MAX_PINNED_BYTES, 'PINNED_BYTES')
    script = SOURCE + '/e03_e04_' + {'builder': 'fixture_builder.py',
              'oracle': 'signed_oracle.py', 'ruby': 'stage_observer.rb'}[operation]
    executable = RUBY if operation == 'ruby' else PYTHON
    required = {executable, script}
    if operation != 'ruby':
        required.add(LAUNCHER)
    inputs = {'builder': (), 'oracle': ('fixture', 'policy'),
              'ruby': ('fixture', 'policy', 'oracle')}[operation]
    required.update(INPUT + '/' + name + '.json' for name in inputs)
    need(required <= paths, 'REQUIRED_PINS_MISSING')
    # Immutable source/dependency inventory may include additional files, all
    # of which are hashed; this does not establish closure completeness/trust.
    argv = (RUBY, script) if operation == 'ruby' else (PYTHON, '-I', '-S', '-B', LAUNCHER, script)
    if operation == 'builder':
        argv += ('--epoch', str(manifest.epoch), '--upstream-root', UPSTREAM,
                 '--policy', OUTPUT + '/policy.json', '--fixture', OUTPUT + '/fixture.json')
    else:
        argv += ('--fixture', INPUT + '/fixture.json', '--policy', INPUT + '/policy.json')
        if operation == 'ruby':
            argv += ('--oracle', INPUT + '/oracle.json', '--upstream-root', UPSTREAM)
        argv += ('--report', OUTPUT + '/' + operation + '.json')
    return Plan('ap2-sup-' + run_id + '-' + operation + '.service', operation, argv,
                manifest.files, 0 if operation == 'builder' else 1)


def admission(plan, observed):
    """Validate parent observations, not target self-reported isolation flags."""
    required = {'unit', 'cgroup', 'pid', 'uid', 'netns', 'parent_netns', 'mntns',
                'parent_mntns', 'no_new_privileges', 'effective_caps', 'readonly',
                'writable', 'memory_max', 'swap_max', 'pids_max', 'scratch_bytes',
                'inodes', 'sealed_files', 'network_routes', 'inherited_sockets',
                'gate_waiting', 'restart', 'delegate', 'kill_mode', 'gid', 'cgroup_pids',
                'socket_families', 'inaccessible', 'private_devices', 'protected_cgroup',
                'suid_sgid', 'new_namespaces', 'rootfs_readonly', 'fd_streams', 'scratch_fs', 'mount_flags'}
    need(type(observed) is dict and set(observed) == required, 'ADMISSION_SCHEMA')
    need(observed['unit'] == plan.unit and observed['cgroup'] == '/system.slice/' + plan.unit,
         'ADMISSION_IDENTITY')
    need(type(observed['pid']) is int and observed['pid'] > 1 and
         type(observed['uid']) is int and observed['uid'] > 0 and
         type(observed['gid']) is int and observed['gid'] > 0, 'ADMISSION_PRIVILEGES')
    for kind, prefix in (('netns', 'net'), ('mntns', 'mnt')):
        current, parent = observed[kind], observed['parent_' + kind]
        need(type(current) is str and type(parent) is str and
             re.fullmatch(prefix + r':\[[0-9]+\]', current) and
             re.fullmatch(prefix + r':\[[0-9]+\]', parent) and current != parent, 'ADMISSION_NAMESPACE')
    need(observed['no_new_privileges'] is True and type(observed['effective_caps']) is int and
         observed['effective_caps'] == 0, 'ADMISSION_PRIVILEGES')
    need(observed['readonly'] == plan.readonly and observed['writable'] == (plan.output_dir,),
         'ADMISSION_MOUNTS')
    for key, value in (('memory_max', MEMORY), ('swap_max', 0), ('pids_max', TASKS),
                       ('scratch_bytes', SCRATCH), ('inodes', INODES),
                       ('network_routes', 0), ('inherited_sockets', 0)):
        need(type(observed[key]) is int and observed[key] == value, 'ADMISSION_LIMIT_OR_CHANNEL')
    members = observed['cgroup_pids']
    # Singular credentials/gate observations attest only this PID. No helper
    # may already be running before GO; descendants are allowed only afterwards.
    need(type(members) is tuple and len(members) == 1 and
         type(members[0]) is int and members[0] == observed['pid'], 'ADMISSION_MEMBERSHIP')
    need(observed['socket_families'] == () and observed['inaccessible'] == ('/tmp', '/var/tmp', '/dev/shm') and
         observed['private_devices'] is True and observed['protected_cgroup'] is True and
         observed['suid_sgid'] is False and observed['new_namespaces'] is False and
         observed['rootfs_readonly'] is True and observed['fd_streams'] == ('pipe', 'pipe', 'pipe') and
         observed['scratch_fs'] == 'tmpfs' and observed['mount_flags'] == ('rw', 'nosuid', 'nodev'),
         'ADMISSION_PROTECTION')
    need(observed['sealed_files'] == plan.pins, 'ADMISSION_SEALED_FILES')
    need(observed['gate_waiting'] is True and observed['restart'] is False and
         observed['delegate'] is False and observed['kill_mode'] == 'control-group', 'ADMISSION_LIFECYCLE')


class Supervisor:
    def __init__(self, port=None, *, clock=time.monotonic):
        self.port, self.clock, self.used = port, clock, False
        self.last = None

    def now(self):
        value = self.clock()
        need(type(value) in (float, int) and math.isfinite(value) and value >= 0 and
             (self.last is None or value >= self.last), 'CLOCK')
        self.last = value
        return value

    def before(self, deadline):
        need(self.now() < deadline, 'DEADLINE')

    def cleanup(self, plan, deadline, observed):
        # No clean cache: reaping precedes the FINAL group stop, including a
        # submitter which registers its unit late while being cancelled/reaped.
        failures = []
        reaped = finalized = False
        for step in ('reap', 'stop', 'finalize', 'readback'):
            try:
                if step == 'reap':
                    reaped = self.port.cancel_reap_submitter(plan.unit, deadline) is True
                    need(reaped, 'SUBMITTER_UNREAPED')
                elif step == 'stop':
                    self.port.stop_group(plan.unit, deadline)
                elif step == 'finalize':
                    done = self.port.finalize_owned(plan.unit, deadline)
                    need(type(done) is dict and set(done) == {'unit', 'children_reaped',
                         'owned_io_closed', 'open_owned_fds'} and done['unit'] == plan.unit and
                         done['children_reaped'] is True and done['owned_io_closed'] is True and
                         type(done['open_owned_fds']) is int and done['open_owned_fds'] == 0,
                         'OWNED_FINALIZATION_UNCONFIRMED')
                    finalized = True
                else:
                    state = self.port.observe_stopped(plan.unit, deadline)
                    need(type(state) is dict and set(state) == {'unit', 'cgroup', 'active', 'populated'} and
                         state['unit'] == plan.unit and state['cgroup'] == '/system.slice/' + plan.unit and
                         state['active'] in ('inactive', 'failed') and type(state['populated']) is int and
                         state['populated'] == 0 and observed and reaped and finalized, 'CLEANUP_UNCONFIRMED')
            except BaseException:
                failures.append(step)
        need(not failures, 'CLEANUP_UNCERTAIN')
        self.before(deadline)

    def run_mock(self, operation, run_id, manifest):
        """Exercise controller against trusted fake infrastructure only.

        A matching expected exit (including Oracle/Ruby exit1) is merely a
        lifecycle observation. No report provenance/crypto/semantic PASS follows.
        """
        need(not self.used, 'ALLOCATION_CONSUMED')
        self.used = True
        need(self.port is not None and self.port.mode == 'OFFLINE_FAKE', 'LIVE_BACKEND_UNIMPLEMENTED')
        plan = plan_for(operation, run_id, manifest)
        started = self.now()
        total_end = started + TOTAL_SECONDS
        work_end = min(started + WORK_SECONDS, total_end - CLEANUP_RESERVE)
        # All bytes are verified before a unit can be submitted. A future OS
        # port must keep those same files sealed through exec, not reopen names.
        for pin in plan.pins:
            self.before(work_end)
            raw = self.port.read_pinned(pin.path, pin.size + 1, work_end)
            need(type(raw) is bytes and len(raw) == pin.size and
                 hashlib.sha256(raw).hexdigest() == pin.sha256, 'PIN_MISMATCH')
            self.before(work_end)
        observed = False
        output = {'stdout': bytearray(), 'stderr': bytearray()}
        ended = set()
        code = None
        primary = None
        try:
            # Ownership starts BEFORE this call; even a partial submit must
            # attempt reaping, final group stop and readback. Never retry submit.
            self.port.submit_gated(plan, work_end)
            self.before(work_end)
            admission(plan, self.port.observe_parent(plan.unit, work_end))
            observed = True
            self.before(work_end)
            self.port.go(plan.unit, work_end)
            for _ in range(MAX_EVENTS):
                self.before(work_end)
                if len(ended) == 2 and code is not None:
                    break
                limits = {'stdout': STDOUT - len(output['stdout']) + 1,
                          'stderr': STDERR - len(output['stderr']) + 1}
                event = self.port.next_event(plan.unit, dict(limits), work_end)
                self.before(work_end)
                need(type(event) is tuple and event, 'EVENT')
                if event[0] == 'data':
                    need(len(event) == 3 and event[1] in output and event[1] not in ended and
                         type(event[2]) is bytes and 0 < len(event[2]) <= limits[event[1]], 'EVENT_DATA')
                    cap = STDOUT if event[1] == 'stdout' else STDERR
                    need(len(output[event[1]]) + len(event[2]) <= cap, 'OUTPUT_LIMIT')
                    output[event[1]].extend(event[2])
                elif event[0] == 'eof':
                    need(len(event) == 2 and event[1] in output and event[1] not in ended, 'EVENT_EOF')
                    ended.add(event[1])
                elif event[0] == 'exit':
                    need(len(event) == 2 and type(event[1]) is int and code is None, 'EVENT_EXIT')
                    code = event[1]
                    need(code == plan.expected_exit, 'INCOMPLETE_OR_UNEXPECTED_EXIT')
                else:
                    need(event == ('idle',), 'EVENT_KIND')
            need(len(ended) == 2 and code == plan.expected_exit, 'INCOMPLETE_OR_UNEXPECTED_EXIT')
        except BaseException as error:
            primary = error
            raise
        finally:
            try:
                self.cleanup(plan, total_end, observed)
            except BaseException:
                if primary is not None:
                    primary.add_note('CLEANUP_UNCERTAIN')
                else:
                    raise Stop('CLEANUP_UNCERTAIN') from None
        finished = self.now()
        need(finished < total_end, 'DEADLINE')
        return {'status': 'MOCK_SUPERVISOR_LIFECYCLE_COMPLETE', 'operation': operation,
                'unit': plan.unit, 'argv': plan.argv, 'files': plan.pins,
                'stdout': bytes(output['stdout']), 'stderr': bytes(output['stderr']),
                'exit': code, 'seconds': finished - started, 'cleanup': True,
                'actual_execution': False, 'runtime_attestation': 'UNPROVEN',
                'source_closure_authority': 'UNPROVEN', 'report_comparison': 'NOT_IMPLEMENTED',
                'ap2_six_cases': 'NOT_RUN', 'phase2_gate': 'HOLD'}


if __name__ == '__main__':
    print('{"status":"HOLD","reason":"LIVE_BACKEND_UNIMPLEMENTED"}')
    raise SystemExit(78)
