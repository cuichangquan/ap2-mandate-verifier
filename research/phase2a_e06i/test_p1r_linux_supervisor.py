"""Offline controller regressions; no target child, shell, socket or Linux unit."""
import hashlib
import importlib.util
from pathlib import Path
import sys
import unittest
from dataclasses import replace

spec = importlib.util.spec_from_file_location('fixed_supervisor', Path(__file__).with_name('p1r_linux_supervisor.py'))
s = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = s
spec.loader.exec_module(s)


def fixture(operation='builder'):
    executable = s.RUBY if operation == 'ruby' else s.PYTHON
    script = s.SOURCE + '/e03_e04_' + {'builder': 'fixture_builder.py', 'oracle': 'signed_oracle.py', 'ruby': 'stage_observer.rb'}[operation]
    paths = [executable, script, s.SOURCE + '/closure_dependency.py']
    if operation != 'ruby':
        paths.append(s.LAUNCHER)
    paths += [s.INPUT + '/' + n + '.json' for n in {'builder': (), 'oracle': ('fixture', 'policy'), 'ruby': ('fixture', 'policy', 'oracle')}[operation]]
    files = {p: ('FAKE BYTES FOR ' + p).encode() for p in paths}
    manifest = s.Manifest(tuple(s.Pin(p, len(b), hashlib.sha256(b).hexdigest()) for p, b in files.items()), 1700000000)
    return manifest, files


def observation(plan):
    return {'unit': plan.unit, 'cgroup': '/system.slice/' + plan.unit, 'pid': 42, 'uid': 65534,
            'netns': 'net:[2]', 'parent_netns': 'net:[1]', 'mntns': 'mnt:[2]', 'parent_mntns': 'mnt:[1]',
            'no_new_privileges': True, 'effective_caps': 0, 'readonly': plan.readonly,
            'writable': (plan.output_dir,), 'memory_max': s.MEMORY, 'swap_max': 0,
            'pids_max': s.TASKS, 'scratch_bytes': s.SCRATCH, 'inodes': s.INODES,
            'sealed_files': plan.pins, 'network_routes': 0, 'inherited_sockets': 0,
            'gate_waiting': True, 'restart': False, 'delegate': False, 'kill_mode': 'control-group',
            'gid': 65534, 'cgroup_pids': (42,), 'socket_families': (),
            'inaccessible': ('/tmp', '/var/tmp', '/dev/shm'), 'private_devices': True,
            'protected_cgroup': True, 'suid_sgid': False, 'new_namespaces': False,
            'rootfs_readonly': True, 'fd_streams': ('pipe', 'pipe', 'pipe'),
            'scratch_fs': 'tmpfs', 'mount_flags': ('rw', 'nosuid', 'nodev')}


class FakePort:
    mode = 'OFFLINE_FAKE'

    def __init__(self, operation='builder'):
        self.manifest, self.files = fixture(operation)
        self.time = 0.0
        self.calls = []
        self.plan = None
        self.change = None
        self.events = [('data', 'stdout', b'bounded log'), ('eof', 'stdout'), ('eof', 'stderr'), ('exit', 0 if operation == 'builder' else 1)]
        self.reaped = False
        self.registered = False
        self.stop_failure = False
        self.reap_failure = False
        self.readback = None
        self.error_at = None
        self.late_registration = False
        self.advance_at = None
        self.finalization = None

    def tick(self, stage):
        self.calls.append(stage)
        if self.advance_at == stage:
            self.time = 7
        if self.error_at == stage:
            raise OSError('fake backend failure')

    def read_pinned(self, path, read_limit, deadline):
        self.tick('read')
        return self.files[path]

    def submit_gated(self, plan, deadline):
        self.plan = plan
        self.tick('submit')
        self.registered = True

    def observe_parent(self, unit, deadline):
        self.tick('observe')
        data = observation(self.plan)
        if self.change:
            self.change(data)
        return data

    def go(self, unit, deadline):
        self.tick('GO')

    def next_event(self, unit, read_limits, deadline):
        self.tick('event')
        return self.events.pop(0) if self.events else ('idle',)

    def cancel_reap_submitter(self, unit, deadline):
        self.tick('reap')
        if self.late_registration:
            self.registered = True
        self.reaped = not self.reap_failure
        return self.reaped

    def stop_group(self, unit, deadline):
        self.tick('stop')
        if not self.reaped:
            # Stop is still attempted on reap failure, never cached as clean.
            pass
        if self.stop_failure:
            raise OSError('stop failed')
        self.registered = False

    def finalize_owned(self, unit, deadline):
        self.tick('finalize')
        return self.finalization if self.finalization is not None else {'unit': unit, 'children_reaped': True, 'owned_io_closed': True, 'open_owned_fds': 0}

    def observe_stopped(self, unit, deadline):
        self.tick('stopped')
        return self.readback if self.readback is not None else {'unit': unit, 'cgroup': '/system.slice/' + unit, 'active': 'inactive', 'populated': int(self.registered)}


def run(port, operation='builder'):
    return s.Supervisor(port, clock=lambda: port.time).run_mock(operation, '123', port.manifest)


class Tests(unittest.TestCase):
    def test_fixed_operations_and_expected_research_exits(self):
        for operation in ('builder', 'oracle', 'ruby'):
            with self.subTest(operation=operation):
                port = FakePort(operation)
                result = run(port, operation)
                self.assertEqual(result['exit'], 0 if operation == 'builder' else 1)
                self.assertEqual(result['status'], 'MOCK_SUPERVISOR_LIFECYCLE_COMPLETE')
                self.assertFalse(result['actual_execution'])
                self.assertEqual(result['runtime_attestation'], 'UNPROVEN')
                self.assertEqual(result['source_closure_authority'], 'UNPROVEN')
                self.assertEqual(result['ap2_six_cases'], 'NOT_RUN')
                self.assertEqual(result['report_comparison'], 'NOT_IMPLEMENTED')
                self.assertEqual(result['phase2_gate'], 'HOLD')
                self.assertEqual(port.calls[-4:], ['reap', 'stop', 'finalize', 'stopped'])
                self.assertLess(port.calls.index('observe'), port.calls.index('GO'))
                self.assertLess(port.calls.index('GO'), port.calls.index('event'))

    def test_no_generic_command_or_live_backend(self):
        manifest, _ = fixture()
        for operation in ('sh', 'python', 'BUILDER', '', ['builder'], None):
            with self.subTest(operation=operation), self.assertRaises(s.Stop):
                s.plan_for(operation, '123', manifest)
        for port in (None, type('Live', (), {'mode': 'LINUX'})()):
            with self.assertRaisesRegex(s.Stop, 'LIVE_BACKEND_UNIMPLEMENTED'):
                s.Supervisor(port).run_mock('builder', '123', manifest)

    def test_fixed_argv_and_conservative_bounds(self):
        for operation in ('builder', 'oracle', 'ruby'):
            port = FakePort(operation)
            plan = s.plan_for(operation, '123', port.manifest)
            with self.subTest(operation=operation):
                self.assertEqual(plan.argv[0], s.RUBY if operation == 'ruby' else s.PYTHON)
                self.assertNotIn('-c', plan.argv)
                self.assertNotIn('sh', plan.argv)
                if operation != 'ruby':
                    self.assertEqual(plan.argv[1:5], ('-I', '-S', '-B', s.LAUNCHER))
                self.assertEqual(plan.memory_bytes, 67108864)
                self.assertEqual(plan.swap_bytes, 0)
                self.assertEqual(plan.tasks, 16)
                self.assertEqual(plan.scratch_bytes, 33554432)
                self.assertEqual(plan.inodes, 256)
                self.assertEqual(plan.runtime_seconds, 3)
                self.assertEqual(plan.readonly, s.READONLY)
                self.assertEqual(plan.output_dir, s.OUTPUT)

    def test_run_id_and_epoch(self):
        manifest, _ = fixture()
        for value in ('../x', '1.service', '', '1' * 21, 1, None):
            with self.subTest(run_id=value), self.assertRaises(s.Stop):
                s.plan_for('builder', value, manifest)
        for epoch in (True, 60, 4102441201, 1.5, None):
            with self.subTest(epoch=epoch), self.assertRaises(s.Stop):
                s.plan_for('builder', '123', replace(manifest, epoch=epoch))
        for epoch in (61, 4102441200):
            self.assertIn(str(epoch), s.plan_for('builder', '123', replace(manifest, epoch=epoch)).argv)

    def test_manifest_shape_pins_paths_and_aggregate(self):
        manifest, _ = fixture()
        first = manifest.files[0]
        bad = [replace(manifest, files=()), replace(manifest, files=list(manifest.files)),
               replace(manifest, files=manifest.files + (first,)), replace(manifest, files=(first,) * 513)]
        for path in ('/tmp/x', '/opt/ap2-runtime/../x', '/opt/ap2-runtime/a/../../x', '/opt/ap2-runtime/x\n', '/opt/ap2-runtime/é', '/opt/ap2-runtime//x', '/opt/ap2-runtime/' + 'x' * 1024):
            bad.append(replace(manifest, files=(replace(first, path=path),) + manifest.files[1:]))
        for key, value in (('size', True), ('size', 0), ('size', s.MAX_FILE_BYTES + 1), ('sha256', 'A' * 64), ('sha256', '0' * 63)):
            bad.append(replace(manifest, files=(replace(first, **{key: value}),) + manifest.files[1:]))
        bad.append(replace(manifest, files=tuple(replace(p, size=s.MAX_FILE_BYTES) for p in manifest.files)))
        for item in bad:
            with self.subTest(item=item), self.assertRaises(s.Stop):
                s.plan_for('builder', '123', item)

    def test_every_required_pin_is_mandatory(self):
        for operation in ('builder', 'oracle', 'ruby'):
            port = FakePort(operation)
            for pin in port.manifest.files:
                if pin.path.endswith('closure_dependency.py'):
                    continue
                with self.subTest(operation=operation, pin=pin.path), self.assertRaisesRegex(s.Stop, 'REQUIRED_PINS_MISSING'):
                    s.plan_for(operation, '123', replace(port.manifest, files=tuple(p for p in port.manifest.files if p != pin)))

    def test_every_byte_including_dependency_tail_is_hashed_before_submit(self):
        for operation in ('builder', 'oracle', 'ruby'):
            for pin in FakePort(operation).manifest.files:
                for mutation in (lambda b: b[:-1], lambda b: b + b' tail', lambda b: b[:-1] + b'!'):
                    port = FakePort(operation)
                    port.files[pin.path] = mutation(port.files[pin.path])
                    with self.subTest(operation=operation, path=pin.path), self.assertRaisesRegex(s.Stop, 'PIN_MISMATCH'):
                        run(port, operation)
                    self.assertNotIn('submit', port.calls)
                    self.assertNotIn('GO', port.calls)

    def test_read_failure_and_deadline_never_submit(self):
        for change in ('error', 'deadline'):
            port = FakePort()
            if change == 'error':
                port.error_at = 'read'
            else:
                port.advance_at = 'read'
            with self.subTest(change=change), self.assertRaises((s.Stop, OSError)):
                run(port)
            self.assertNotIn('submit', port.calls)

    def test_each_parent_admission_field_missing_or_wrong_blocks_GO(self):
        port = FakePort()
        plan = s.plan_for('builder', '123', port.manifest)
        for key, value in observation(plan).items():
            for missing in (True, False):
                port = FakePort()
                def change(data, key=key, missing=missing):
                    if missing:
                        del data[key]
                    else:
                        data[key] = None
                port.change = change
                with self.subTest(key=key, missing=missing), self.assertRaises(s.Stop):
                    run(port)
                self.assertNotIn('GO', port.calls)
                self.assertEqual(port.calls[-4:], ['reap', 'stop', 'finalize', 'stopped'])

    def test_namespace_privilege_mount_seal_channel_and_bool_confusion(self):
        changes = {'netns': 'net:[1]', 'mntns': 'mnt:[1]', 'uid': 0,
                   'pid': True, 'effective_caps': True, 'no_new_privileges': 1,
                   'readonly': (), 'writable': (s.OUTPUT, '/tmp'), 'sealed_files': (),
                   'memory_max': 2147483648, 'swap_max': 1, 'pids_max': True,
                   'scratch_bytes': 8589934592, 'inodes': True, 'network_routes': True,
                   'inherited_sockets': 1, 'gate_waiting': 1, 'restart': True,
                   'delegate': True, 'kill_mode': 'process'}
        for key, value in changes.items():
            port = FakePort()
            port.change = lambda data, key=key, value=value: data.update({key: value})
            with self.subTest(key=key), self.assertRaises(s.Stop):
                run(port)
            self.assertNotIn('GO', port.calls)

    def test_extra_pre_GO_member_is_not_attested_by_main_PID_credentials(self):
        for members in ((42, 43), (43, 42)):
            port = FakePort()
            port.change = lambda data, members=members: data.update(cgroup_pids=members)
            with self.subTest(members=members), self.assertRaisesRegex(s.Stop, 'ADMISSION_MEMBERSHIP'):
                run(port)
            self.assertNotIn('GO', port.calls)
            self.assertEqual(port.calls[-4:], ['reap', 'stop', 'finalize', 'stopped'])

    def test_output_and_exit_order_requires_both_EOFs(self):
        port = FakePort()
        port.events = [('exit', 0), ('data', 'stderr', b'bounded'), ('eof', 'stderr'), ('data', 'stdout', b'log'), ('eof', 'stdout')]
        result = run(port)
        self.assertEqual(result['stdout'], b'log')
        self.assertEqual(result['stderr'], b'bounded')
        self.assertEqual(port.calls.count('event'), 5)

    def test_exact_capture_caps_and_overflow_each_stream(self):
        for stream, cap in (('stdout', s.STDOUT), ('stderr', s.STDERR)):
            for overflow in (False, True):
                port = FakePort()
                remaining = cap + int(overflow)
                chunks = []
                # Per-stream capture bounds apply even after the other stream is full.
                while remaining:
                    n = min(remaining, 1024)
                    chunks.append(('data', stream, b'x' * n))
                    remaining -= n
                port.events = chunks + [('eof', 'stdout'), ('eof', 'stderr'), ('exit', 0)]
                with self.subTest(stream=stream, overflow=overflow):
                    if overflow:
                        with self.assertRaisesRegex(s.Stop, 'OUTPUT_LIMIT'):
                            run(port)
                    else:
                        self.assertEqual(len(run(port)[stream]), cap)
                self.assertEqual(port.calls[-4:], ['reap', 'stop', 'finalize', 'stopped'])

    def test_full_stderr_does_not_starve_stdout_or_share_its_budget(self):
        port = FakePort()
        port.events = [('data', 'stderr', b'e' * s.STDERR), ('data', 'stdout', b'o' * s.STDOUT),
                       ('eof', 'stdout'), ('eof', 'stderr'), ('exit', 0)]
        result = run(port)
        self.assertEqual(len(result['stdout']), s.STDOUT)
        self.assertEqual(len(result['stderr']), s.STDERR)

    def test_membership_and_remaining_protection_negatives(self):
        for key, value in (('cgroup_pids', (43,)), ('cgroup_pids', (42, 42)), ('cgroup_pids', (True,)),
                           ('socket_families', ('AF_UNIX',)), ('rootfs_readonly', 1), ('private_devices', 1),
                           ('protected_cgroup', 1), ('suid_sgid', True), ('new_namespaces', True),
                           ('gid', 0), ('mount_flags', ('rw',)), ('fd_streams', ('socket', 'pipe', 'pipe')),
                           ('scratch_fs', 'ext4')):
            port = FakePort()
            port.change = lambda data, key=key, value=value: data.update({key: value})
            with self.subTest(key=key, value=value), self.assertRaises(s.Stop):
                run(port)
            self.assertNotIn('GO', port.calls)

    def test_malformed_duplicate_postEOF_and_missing_events(self):
        event_sets = [[], [('eof', 'stdout')], [('exit', True)], [('exit', 0), ('exit', 0)],
                      [('eof', 'stdout'), ('data', 'stdout', b'x')], [('eof', 'stdout'), ('eof', 'stdout')],
                      [('data', 'foreign', b'x')], [('data', 'stdout', '')], [('data', 'stdout', b'')],
                      [('unknown',)], [('idle', 'extra')], ['untyped']]
        for events in event_sets:
            port = FakePort()
            port.events = list(events)
            with self.subTest(events=events), self.assertRaises((s.Stop, TypeError)):
                run(port)
            self.assertEqual(port.calls[-4:], ['reap', 'stop', 'finalize', 'stopped'])

    def test_wrong_exit_never_means_success(self):
        for operation, exit_code in (('builder', 1), ('oracle', 0), ('ruby', 0), ('builder', -9)):
            port = FakePort(operation)
            port.events = [('eof', 'stdout'), ('eof', 'stderr'), ('exit', exit_code)]
            with self.subTest(operation=operation), self.assertRaisesRegex(s.Stop, 'UNEXPECTED_EXIT'):
                run(port, operation)

    def test_failure_and_cancellation_at_each_owned_stage_always_cleanup(self):
        for stage in ('submit', 'observe', 'GO', 'event'):
            port = FakePort()
            port.error_at = stage
            with self.subTest(stage=stage), self.assertRaises(OSError):
                run(port)
            self.assertEqual(port.calls[-4:], ['reap', 'stop', 'finalize', 'stopped'])
        port = FakePort()
        def interrupt(*args):
            raise KeyboardInterrupt()
        port.go = interrupt
        with self.assertRaises(KeyboardInterrupt):
            run(port)
        self.assertEqual(port.calls[-4:], ['reap', 'stop', 'finalize', 'stopped'])

    def test_work_deadlines_and_cleanup_deadline(self):
        for stage in ('submit', 'observe', 'GO', 'event', 'reap', 'stop', 'finalize', 'stopped'):
            port = FakePort()
            port.advance_at = stage
            with self.subTest(stage=stage), self.assertRaises(s.Stop):
                run(port)
            self.assertEqual(port.calls[-4:], ['reap', 'stop', 'finalize', 'stopped'])

    def test_delayed_registration_is_stopped_after_submitter_reap(self):
        port = FakePort()
        port.late_registration = True
        self.assertTrue(run(port)['cleanup'])
        self.assertFalse(port.registered)
        self.assertEqual(port.calls[-4:], ['reap', 'stop', 'finalize', 'stopped'])

    def test_cleanup_faults_never_skip_other_steps_or_claim_success(self):
        for stage in ('reap', 'stop', 'finalize', 'stopped'):
            port = FakePort()
            port.error_at = stage
            with self.subTest(stage=stage), self.assertRaisesRegex(s.Stop, 'CLEANUP_UNCERTAIN'):
                run(port)
            self.assertEqual(port.calls[-4:], ['reap', 'stop', 'finalize', 'stopped'])
        port = FakePort()
        port.reap_failure = True
        with self.assertRaises(s.Stop):
            run(port)
        self.assertEqual(port.calls[-4:], ['reap', 'stop', 'finalize', 'stopped'])

    def test_empty_cgroup_is_not_child_reaping_or_IO_close_evidence(self):
        base = {'unit': 'ap2-sup-123-builder.service', 'children_reaped': True,
                'owned_io_closed': True, 'open_owned_fds': 0}
        for key in base:
            for value in (None, 'foreign', False if key != 'open_owned_fds' else True):
                port = FakePort()
                port.finalization = dict(base, **{key: value})
                with self.subTest(key=key, value=value), self.assertRaisesRegex(s.Stop, 'CLEANUP_UNCERTAIN'):
                    run(port)
                self.assertEqual(port.calls[-4:], ['reap', 'stop', 'finalize', 'stopped'])
                self.assertFalse(port.registered)
        port = FakePort()
        port.finalization = dict(base, open_owned_fds=1)
        with self.assertRaises(s.Stop):
            run(port)
        for key in base:
            port = FakePort()
            port.finalization = {k: v for k, v in base.items() if k != key}
            with self.subTest(missing=key), self.assertRaises(s.Stop):
                run(port)

    def test_child_wait_or_close_failure_preserves_primary_and_attempts_readback(self):
        for label in ('child wait failed', 'pipe close failed'):
            port = FakePort()
            port.error_at = 'GO'
            def fail(unit, deadline, label=label):
                port.tick('finalize')
                raise OSError(label)
            port.finalize_owned = fail
            with self.subTest(label=label), self.assertRaises(OSError) as caught:
                run(port)
            self.assertEqual(str(caught.exception), 'fake backend failure')
            self.assertIn('CLEANUP_UNCERTAIN', caught.exception.__notes__)
            self.assertEqual(port.calls[-4:], ['reap', 'stop', 'finalize', 'stopped'])

    def test_cleanup_identity_active_populated_and_missing_fields(self):
        base = {'unit': 'ap2-sup-123-builder.service', 'cgroup': '/system.slice/ap2-sup-123-builder.service', 'active': 'inactive', 'populated': 0}
        for key in base:
            for value in (None, 'foreign', True):
                port = FakePort()
                port.readback = dict(base, **{key: value})
                with self.subTest(key=key, value=value), self.assertRaises(s.Stop):
                    run(port)
        for active in ('active', 'activating'):
            port = FakePort()
            port.readback = dict(base, active=active)
            with self.assertRaises(s.Stop):
                run(port)
        port = FakePort()
        port.readback = dict(base, populated=1)
        with self.assertRaises(s.Stop):
            run(port)

    def test_cleanup_failure_does_not_mask_primary(self):
        port = FakePort()
        port.error_at = 'GO'
        port.stop_failure = True
        with self.assertRaises(OSError) as caught:
            run(port)
        self.assertIn('CLEANUP_UNCERTAIN', caught.exception.__notes__)
        self.assertEqual(port.calls[-4:], ['reap', 'stop', 'finalize', 'stopped'])

    def test_failed_admission_never_caches_absent_unit_clean(self):
        port = FakePort()
        port.change = lambda data: data.update(gate_waiting=False)
        with self.assertRaises(s.Stop) as caught:
            run(port)
        self.assertIn('CLEANUP_UNCERTAIN', caught.exception.__notes__)
        self.assertNotIn('GO', port.calls)

    def test_single_use_no_retry_even_after_failure(self):
        port = FakePort()
        supervisor = s.Supervisor(port, clock=lambda: port.time)
        supervisor.run_mock('builder', '123', port.manifest)
        count = len(port.calls)
        with self.assertRaisesRegex(s.Stop, 'ALLOCATION_CONSUMED'):
            supervisor.run_mock('builder', '123', port.manifest)
        self.assertEqual(len(port.calls), count)
        port = FakePort()
        supervisor = s.Supervisor(port, clock=lambda: port.time)
        with self.assertRaises(s.Stop):
            supervisor.run_mock('invalid', '123', port.manifest)
        with self.assertRaisesRegex(s.Stop, 'ALLOCATION_CONSUMED'):
            supervisor.run_mock('builder', '123', port.manifest)

    def test_nonfinite_backward_and_bool_clock(self):
        for value in (float('nan'), float('inf'), -1, True, None):
            port = FakePort()
            with self.subTest(value=value), self.assertRaises(s.Stop):
                s.Supervisor(port, clock=lambda: value).run_mock('builder', '123', port.manifest)
            self.assertNotIn('submit', port.calls)
        port = FakePort()
        supervisor = s.Supervisor(port, clock=iter((1, 0)).__next__)
        with self.assertRaisesRegex(s.Stop, 'CLOCK'):
            supervisor.run_mock('builder', '123', port.manifest)
        self.assertNotIn('submit', port.calls)


if __name__ == '__main__':
    def audit(event, args):
        if event == 'subprocess.Popen' or event.startswith('socket.'):
            raise AssertionError('forbidden real IO: ' + event)
    sys.addaudithook(audit)
    unittest.main(verbosity=2)
