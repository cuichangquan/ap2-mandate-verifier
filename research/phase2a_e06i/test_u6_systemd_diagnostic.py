"""Fake IO only; no subprocess, socket, systemctl or mechanism execution."""
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import sys
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('diag', Path(__file__).with_name('u6_systemd_diagnostic.py'))
diag = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diag)


class Pipe:
    def close(self):
        self.closed = True


class Process:
    pid = 12345
    def __init__(self, code=1):
        self.stdout, self.stderr = Pipe(), Pipe()
        self.returncode = code
    def poll(self):
        return self.returncode
    def wait(self, timeout):
        return self.returncode


class Selector:
    def __init__(self):
        self.items = {}
    def __enter__(self):
        return self
    def __exit__(self, *args):
        pass
    def register(self, file, events, name):
        self.items[file] = SimpleNamespace(data=name, fileobj=file, fd=name)
    def unregister(self, file):
        del self.items[file]
    def get_map(self):
        return self.items
    def select(self, timeout):
        return [(item, 1) for item in list(self.items.values())]


def fake_capture(stdout=b'degraded\n', stderr=b'', code=1, clock=lambda:0):
    streams = {'stdout':bytearray(stdout), 'stderr':bytearray(stderr)}
    proc = Process(code)
    killed=[]
    def read(name, count):
        data=bytes(streams[name][:count])
        del streams[name][:count]
        return data
    row=diag.capture(proc, clock=clock, selector_factory=Selector, read=read,
                     terminate=lambda p:killed.append(p.pid))
    return row, proc, killed


class FakeTests(unittest.TestCase):
    def test_explicit_deadline_and_default_unchanged(self):
        for bound in (1, 20):
            times=iter((0,bound,bound))
            proc=Process()
            killed=[]
            row=diag.capture(proc, clock=lambda:next(times), selector_factory=Selector,
                             read=lambda *args:b'', terminate=lambda p:killed.append(p.pid),
                             deadline_seconds=bound)
            self.assertEqual(row['failure'],'COMMAND_TIMEOUT')
            self.assertEqual(row['seconds'],bound)
            self.assertEqual(killed,[12345])
        self.assertEqual(diag.QUERY_SECONDS,4)

    def test_nonzero_keeps_both_streams_and_actual_code(self):
        row, proc, killed=fake_capture(stderr=b'fixed error\n', code=3)
        self.assertEqual(row['returncode'], 3)
        self.assertEqual(row['stdout'], 'degraded\n')
        self.assertEqual(row['stderr'], 'fixed error\n')
        self.assertEqual(diag.classify(row), 'COMMAND_NONZERO')
        self.assertTrue(proc.stdout.closed and proc.stderr.closed)
        self.assertFalse(killed)

    def test_running_only_is_success(self):
        row, _, _=fake_capture(b'running\n', code=0)
        self.assertEqual(diag.classify(row), 'QUERY_RUNNING_OBSERVED')
        for output, error in ((b'unknown\n', b''), (b'running\n', b'error'), (b' running\n', b'')):
            row, _, _=fake_capture(output, error, 0)
            self.assertEqual(diag.classify(row), 'COMMAND_UNEXPECTED_OUTPUT')

    def test_exact_cap_and_overflow_each_stream(self):
        for name in ('stdout', 'stderr'):
            for size in (diag.STREAM_CAP, diag.STREAM_CAP+1, 1000000):
                with self.subTest(name=name, size=size):
                    row, _, killed=fake_capture(**{name:b'x'*size})
                    self.assertEqual(len(row[name]), min(size, diag.STREAM_CAP))
                    self.assertLessEqual(row['bytes_read'][name], diag.STREAM_CAP+1)
                    self.assertEqual(bool(killed), size>diag.STREAM_CAP)
                    self.assertEqual(row['truncated'][name], size>diag.STREAM_CAP)
                    if size>diag.STREAM_CAP:
                        self.assertEqual(diag.classify(row), 'COMMAND_OUTPUT_LIMIT')

    def test_timeout_and_signal_classification(self):
        times=iter((0,4,4))
        row, _, killed=fake_capture(clock=lambda:next(times))
        self.assertEqual(diag.classify(row), 'COMMAND_TIMEOUT')
        self.assertEqual(killed, [12345])
        row, _, _=fake_capture(code=-9)
        self.assertEqual(diag.classify(row), 'COMMAND_SIGNAL')

    def test_unknown_exit_and_cleanup_are_stop(self):
        row, _, _=fake_capture()
        row['returncode']=None
        self.assertEqual(diag.classify(row), 'COMMAND_EXIT_UNKNOWN')
        row['query_reaped']=False
        self.assertEqual(diag.classify(row), 'COMMAND_CLEANUP_UNCONFIRMED')

    def test_read_error_preserves_partial_and_reaps(self):
        proc=Process()
        with patch.object(diag.os, 'killpg') as kill:
            row=diag.capture(proc, clock=lambda:0, selector_factory=Selector,
                             read=lambda *args: (_ for _ in ()).throw(OSError()))
        self.assertEqual(row['failure'], 'CAPTURE_ERROR_OSError')
        self.assertTrue(row['query_reaped'])
        kill.assert_called_once()

    def test_nonlinux_starts_nothing(self):
        with patch.object(diag.platform, 'system', return_value='Darwin'), patch.object(diag.subprocess, 'Popen') as popen, patch.object(Path, 'write_bytes') as write:
            self.assertEqual(diag.main(), 78)
            popen.assert_not_called()
            self.assertEqual(json.loads(write.call_args.args[0])['queries_attempted'], 0)

    def test_main_uses_only_fixed_query_and_clean_environment(self):
        for code in (0,1):
            row, proc, _=fake_capture(b'running\n' if code==0 else b'degraded\n', code=code)
            with patch.object(diag.platform, 'system', return_value='Linux'), patch.object(diag.os, 'geteuid', return_value=0), patch.object(Path, 'read_text', return_value='VERSION_ID="24.04"'), patch.object(diag.subprocess, 'Popen', return_value=proc) as popen, patch.object(diag, 'capture', return_value=row), patch.object(Path, 'write_bytes') as write:
                self.assertEqual(diag.main(), 0 if code==0 else 78)
                args, kw=popen.call_args
                self.assertEqual(args, (('/usr/bin/systemctl','is-system-running'),))
                self.assertTrue(kw['start_new_session'])
                self.assertEqual(set(kw['env']), {'PATH','LANG','LC_ALL','SYSTEMD_COLORS'})
                result=json.loads(write.call_args.args[0])
                self.assertEqual(result['queries_attempted'],1)
                self.assertEqual(result['experiment_units_created'],0)
                self.assertLess(len(write.call_args.args[0]),diag.RESULT_CAP)

    def test_spawn_failure_is_recorded_without_retry(self):
        with patch.object(diag.platform, 'system', return_value='Linux'), patch.object(diag.os, 'geteuid', return_value=0), patch.object(Path, 'read_text', return_value='VERSION_ID="24.04"'), patch.object(diag.subprocess, 'Popen', side_effect=FileNotFoundError(2,'missing')) as popen, patch.object(Path, 'write_bytes') as write:
            self.assertEqual(diag.main(),78)
            self.assertEqual(popen.call_count,1)
            self.assertEqual(json.loads(write.call_args.args[0])['classification'],'COMMAND_SPAWN_ERROR')


if __name__=='__main__':
    def audit(event, args):
        if event=='subprocess.Popen' or event.startswith('socket.'):
            raise AssertionError('forbidden real IO: '+event)
    sys.addaudithook(audit)
    unittest.main(verbosity=2)
