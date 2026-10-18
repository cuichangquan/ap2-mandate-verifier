"""Offline fake tests: no Linux mechanism, target child, socket or service runs."""
import importlib.util
from pathlib import Path
import sys
import json
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('u6', Path(__file__).with_name('u6_linux_probe.py'))
u6 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u6)


class FakeTests(unittest.TestCase):
    def test_exact_nine_and_payload_syntax(self):
        self.assertEqual(len(u6.CASES), 9)
        self.assertEqual(set(u6.CASES), set(u6.WORK))
        for case in u6.CASES:
            with self.subTest(case=case):
                compile(u6.COMMON+u6.WORK[case], '<synthetic>', 'exec')

    def test_all_oracles_fail_closed(self):
        for case in u6.CASES:
            data = u6.TOKENS[case].encode()
            result = {'timeout':'timeout', 'memory':'oom-kill'}.get(case, 'success')
            overflow = case == 'output'
            with self.subTest(case=case):
                self.assertTrue(u6.verdict(case, data, result, '0', overflow, True))
                self.assertFalse(u6.verdict(case, data, result, '0', overflow, False))
                if case != 'output':
                    self.assertFalse(u6.verdict(case, b'', result, '0', overflow, True))
                    self.assertFalse(u6.verdict(case, data, result, '0', True, True))
                else:
                    self.assertFalse(u6.verdict(case, data, result, '0', False, True))

    def test_wrong_exit_and_attribution(self):
        for case in ('network', 'readonly_permissions', 'disk', 'inode', 'memory', 'timeout'):
            self.assertFalse(u6.verdict(case, u6.TOKENS[case].encode(), 'exit-code', '1', False, True))

    def test_command_has_every_bound_and_no_shell(self):
        args = u6.unit_command('u6-fake.service', Path('/var/tmp/u6-fake/ro'), 'net:[1]', 'network')
        self.assertIn('--property=MemoryMax=67108864', args)
        self.assertIn('--property=MemorySwapMax=0', args)
        self.assertIn('--property=TasksMax=16', args)
        self.assertIn('--property=KillMode=control-group', args)
        self.assertIn('--property=PrivateNetwork=yes', args)
        self.assertIn('--property=CapabilityBoundingSet=', args)
        self.assertIn('--property=ProtectSystem=strict', args)
        self.assertIn('--property=ReadOnlyPaths=/var/tmp/u6-fake/ro', args)
        self.assertIn('--property=RuntimeMaxSec=3s', args)
        self.assertIn('--property=TemporaryFileSystem=/work:rw,size=32M,nr_inodes=256,mode=1777,nosuid,nodev', args)
        self.assertNotIn('shell', args)

    def test_nonlinux_rejected_before_command(self):
        with patch.object(u6.platform, 'system', return_value='Darwin'), patch.object(u6, 'command') as call:
            with self.assertRaisesRegex(u6.Stop, 'LINUX_ROOT_REQUIRED'):
                u6.preflight()
            call.assert_not_called()

    def test_cleanup_removes_only_owned_unit(self):
        lab = u6.Lab(Path('/fake'), 0)
        with patch.object(u6, 'command', return_value='') as call, patch.object(lab, 'show', return_value={'LoadState':'not-found'}), patch.object(Path, 'exists', return_value=False):
            self.assertTrue(lab.cleanup('u6-fake.service', '/system.slice/u6-fake.service'))
            self.assertTrue(lab.cleanup('u6-fake.service', '/system.slice/u6-fake.service'))
            self.assertEqual(call.call_count, 2)

    def test_cleanup_rejects_populated_and_foreign(self):
        for cg, text in (('/system.slice/u6-fake.service', 'populated 1\n'), ('/system.slice/other.service', 'populated 0\n')):
            with self.subTest(cg=cg), patch.object(u6, 'command', return_value=''), patch.object(Path, 'exists', return_value=True), patch.object(Path, 'read_text', return_value=text):
                with self.assertRaises(u6.Stop):
                    u6.Lab(Path('/fake'), 0).cleanup('u6-fake.service', cg)

    def test_stop_failure_and_live_cgroup_never_mark_clean(self):
        for state, populated in (({'ActiveState':'active'}, 'populated 0\n'),
                                 ({'ActiveState':'inactive'}, 'populated 1\n')):
            lab = u6.Lab(Path('/fake'), 0)
            with patch.object(u6, 'command', return_value=''), patch.object(lab, 'show', return_value=state), patch.object(Path, 'exists', return_value=True), patch.object(Path, 'read_text', return_value=populated):
                with self.assertRaises(u6.Stop):
                    lab.cleanup('u6-fake.service', '/system.slice/u6-fake.service')
                self.assertFalse(lab.cleaned)

    def test_fake_batch_success_and_first_failure_stop(self):
        for failed in (None, 'memory'):
            with self.subTest(failed=failed), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)/'lab'
                root.mkdir()
                calls=[]
                def run(case, index):
                    calls.append(case)
                    return {'case':case, 'pass':case != failed, 'cleanup_empty':True}
                lab = type('FakeLab', (), {'units':[], 'run':staticmethod(run)})()
                payloads=[]
                with patch.object(u6, 'preflight'), patch.object(u6.tempfile, 'mkdtemp', return_value=str(root)), patch.object(u6, 'Lab', return_value=lab), patch.object(u6.signal, 'signal'), patch.object(u6.signal, 'alarm'), patch.object(Path, 'write_bytes', side_effect=lambda b:payloads.append(b)):
                    status = u6.main()
                result=json.loads(payloads[0])
                self.assertEqual(status, 0 if failed is None else 78)
                self.assertEqual(len(result['cases']), 9)
                self.assertEqual(len(calls), 9 if failed is None else 6)
                self.assertTrue(result['cleanup'])
                self.assertLess(len(payloads[0]), 1048576)
                if failed:
                    self.assertEqual(result['cases'][-1]['status'], 'NOT_RUN')

    def test_resource_attribution_is_not_only_errno(self):
        self.assertIn("assert after>before", u6.WORK['pids'])
        for event in ('max', 'oom', 'oom_kill'):
            self.assertIn("after['"+event+"']>before['"+event+"']", u6.WORK['memory'])

    def test_command_failure_and_output_limit(self):
        for rc, output in ((1, b''), (0, b'x'*(u6.OUTPUT_CAP+1))):
            p = type('P', (), {'returncode': rc, 'stdout': output})()
            with patch.object(u6.subprocess, 'run', return_value=p):
                with self.assertRaises(u6.Stop):
                    u6.command(['/fake'])


if __name__ == '__main__':
    # Audit the fake suite itself: any subprocess/socket event is a test failure.
    def audit(event, args):
        if event.startswith('socket.') or event == 'subprocess.Popen':
            raise AssertionError('fake test attempted real IO: '+event)
    sys.addaudithook(audit)
    unittest.main(verbosity=2)
