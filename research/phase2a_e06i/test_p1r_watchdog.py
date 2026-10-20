"""Fake outside-unit watchdog regression paths; no fork/kill/wait syscalls."""
import unittest
import p1r_execution_contract as c
import p1r_watchdog as w
from test_p1r_linux_port import Handle

class Ops:
    def __init__(self):self.calls=[];self.fail=None;self.active=True;self.late=False
    def hit(self,name):
        self.calls.append(name)
        if self.fail==name:raise OSError(name)
    def retire_owner(self,row,deadline):self.hit('retire')
    def reap_submitter(self,row,deadline):
        self.hit('reap')
        if self.late:self.active=True
        return True
    def stop_unit(self,row,deadline):self.hit('stop');self.active=False
    def empty(self,row,deadline):self.hit('empty');return not self.active

class Tests(unittest.TestCase):
    def test_receipt_and_barrier_required_for_clean_result(self):
        ops=Ops();watch=w.Watchdog(ops,clock=lambda:0);row=watch.own('ap2-sup-123-builder.service')
        row.fds=[Handle(),Handle()];ops.late=True
        self.assertTrue(watch.cleanup(row.unit,2,owner_receipt=True))
        self.assertEqual(ops.calls,['retire','reap','stop','empty'])
        self.assertFalse(ops.active);self.assertEqual(row.fds,[])
        with self.assertRaises(c.Stop):watch.own(row.unit)

    def test_no_receipt_even_empty_group_cannot_be_success(self):
        for receipt in (False,None,1,'true',{}):
            ops=Ops();watch=w.Watchdog(ops,clock=lambda:0);row=watch.own('ap2-sup-123-builder.service')
            with self.subTest(receipt=receipt),self.assertRaises(c.Stop):
                watch.cleanup(row.unit,2,owner_receipt=receipt)
            self.assertIn('stop',ops.calls);self.assertIn('empty',ops.calls)

    def test_each_failure_attempts_remaining_cleanup_and_close_once(self):
        for stage in ('retire','reap','stop','empty','close'):
            ops=Ops();watch=w.Watchdog(ops,clock=lambda:0);row=watch.own('ap2-sup-123-builder.service')
            handle=Handle(stage=='close');row.fds=[handle]
            if stage!='close':ops.fail=stage
            with self.subTest(stage=stage),self.assertRaises(c.Stop):watch.cleanup(row.unit,2,owner_receipt=True)
            self.assertIn('empty',ops.calls);self.assertEqual(handle.calls,1);self.assertEqual(row.fds,[])

    def test_controller_death_always_HOLD_and_stops_late_registration(self):
        ops=Ops();ops.late=True;watch=w.Watchdog(ops,clock=lambda:0);row=watch.own('ap2-sup-123-builder.service')
        with self.assertRaisesRegex(c.Stop,'CONTROLLER_LOST'):watch.controller_lost(row.unit,2)
        self.assertEqual(ops.calls,['retire','reap','stop','empty']);self.assertFalse(ops.active)

    def test_deadline_nonfinite_backward_and_missing_profile_block_native(self):
        for clock in (lambda:float('nan'),lambda:float('inf'),lambda:True,lambda:3):
            watch=w.Watchdog(Ops(),clock=clock)
            with self.assertRaises(c.Stop):watch.before(2)
        values=iter((1.,0.));watch=w.Watchdog(Ops(),clock=lambda:next(values));watch.before(2)
        with self.assertRaises(c.Stop):watch.before(2)
        with self.assertRaises(c.Stop):w.NativeWatchdog('offline-fixture')

    def test_native_fallback_reap_failure_still_attempts_final_stop(self):
        from unittest.mock import Mock,patch
        watch=w.NativeWatchdog.__new__(w.NativeWatchdog)
        watch._reap_adopted=Mock(side_effect=c.Stop('REAP_DEADLINE'))
        port=Mock()
        with patch.object(w.time,'monotonic',return_value=0):
            with self.assertRaises(c.Stop):watch._fallback(port,2)
        port.fallback_stop.assert_called_once_with(2)
        self.assertLess(watch._reap_adopted.call_args.args[0],2)

    def test_native_worker_abnormal_or_forged_success_always_fallback(self):
        from unittest.mock import Mock,patch
        import ctypes,json
        import p1r_linux_port as port_module
        from test_p1r_linux_port import Ops
        for status,raw in ((78<<8,b''),(0,b'{}'),(0,b'not-json')):
            watch=w.NativeWatchdog.__new__(w.NativeWatchdog);watch.profile_name='offline-fixture'
            watch._fallback=Mock();port=Mock();ops=Ops()
            with patch.object(w,'__name__','__main__'),patch.object(ctypes,'CDLL') as libc,\
                 patch.object(port_module.LinuxPort,'native',return_value=port),\
                 patch.object(w.os,'pipe',return_value=(101,102)),patch.object(w.os,'fork',return_value=42),\
                 patch.object(w.os,'pidfd_open',return_value=103,create=True),patch.object(w.os,'set_blocking'),\
                 patch.object(w.signal,'signal'),patch.object(w.os,'close'),patch.object(w.os,'read',side_effect=[raw,b'']),\
                 patch.object(w.select,'select',return_value=([],[],[])),patch.object(w.os,'waitpid',return_value=(42,status)),patch.object(w.time,'monotonic',return_value=0):
                libc.return_value.prctl.return_value=0
                with self.subTest(status=status,raw=raw),self.assertRaises(c.Stop):
                    watch.run('builder','123',ops.manifest)
                watch._fallback.assert_called_once_with(port,6)

    def test_native_worker_success_requires_exact_fixed_result(self):
        from unittest.mock import Mock,patch
        import ctypes,json
        import p1r_linux_port as port_module
        from test_p1r_linux_port import Ops
        watch=w.NativeWatchdog.__new__(w.NativeWatchdog);watch.profile_name='offline-fixture'
        watch._fallback=Mock();port=Mock();ops=Ops()
        from test_p1r_linux_port import execute
        value,_=execute(Ops())
        value=dict(value,status='SUPERVISOR_LIFECYCLE_COMPLETE',actual_execution=True,
                   artifacts={'policy.json':b'p'*16384,'fixture.json':b'f'*262144})
        wire=c.encode_result(value)
        chunks=[wire[i:i+16384] for i in range(0,len(wire),16384)]+[b'']
        with patch.object(w,'__name__','__main__'),patch.object(ctypes,'CDLL') as libc,\
             patch.object(port_module.LinuxPort,'native',return_value=port),\
             patch.object(w.os,'pipe',return_value=(101,102)),patch.object(w.os,'fork',return_value=42),\
             patch.object(w.os,'pidfd_open',return_value=103,create=True),patch.object(w.os,'set_blocking'),\
             patch.object(w.signal,'signal'),patch.object(w.os,'close'),patch.object(w.os,'read',side_effect=chunks),\
             patch.object(w.select,'select',return_value=([],[],[])),patch.object(w.os,'waitpid',return_value=(42,0)),patch.object(w.time,'monotonic',return_value=0):
            libc.return_value.prctl.return_value=0
            self.assertEqual(watch.run('builder','123',ops.manifest),value)
            watch._fallback.assert_not_called()

    def test_every_native_partial_setup_or_signal_failure_keeps_outer_guard(self):
        from unittest.mock import Mock,patch
        import ctypes
        import p1r_linux_port as port_module
        from test_p1r_linux_port import Ops
        for stage in ('pipe','pidfd','nonblock','close-write','signal'):
            watch=w.NativeWatchdog.__new__(w.NativeWatchdog);watch.profile_name='offline-fixture'
            watch._fallback=Mock();port=Mock();ops=Ops()
            closed=[]
            def close(fd):
                closed.append(fd)
                if stage=='close-write' and fd==102:raise OSError('close')
            with patch.object(w,'__name__','__main__'),patch.object(ctypes,'CDLL') as libc,\
                 patch.object(port_module.LinuxPort,'native',return_value=port),\
                 patch.object(w.os,'pipe',side_effect=OSError('pipe') if stage=='pipe' else None,return_value=(101,102)),\
                 patch.object(w.os,'fork',return_value=42),\
                 patch.object(w.os,'pidfd_open',side_effect=OSError('pidfd') if stage=='pidfd' else None,return_value=103,create=True),\
                 patch.object(w.os,'set_blocking',side_effect=OSError('nonblock') if stage=='nonblock' else None),\
                 patch.object(w.os,'close',side_effect=close),patch.object(w.os,'kill') as kill,\
                 patch.object(w.signal,'signal'),patch.object(w.signal,'pidfd_send_signal',side_effect=OSError('signal'),create=True),\
                 patch.object(w.time,'monotonic',side_effect=[0,7]):
                libc.return_value.prctl.return_value=0
                with self.subTest(stage=stage),self.assertRaises(c.Stop):watch.run('builder','123',ops.manifest)
                watch._fallback.assert_called_once_with(port,6)
                self.assertLessEqual(closed.count(102),1)
                if stage!='pipe':self.assertIn(101,closed)
                if stage=='pidfd':kill.assert_called_once_with(42,w.signal.SIGKILL)

    def test_bounded_result_writer_handles_short_writes_and_deadline(self):
        from unittest.mock import patch
        raw = b'x'*20000
        with patch.object(w.os,'set_blocking'),patch.object(w.select,'select',return_value=([],[10],[])),\
             patch.object(w.os,'write',side_effect=[BlockingIOError(),10000,10000]) as write,\
             patch.object(w.time,'monotonic',return_value=0):
            w._write_result(10,raw,4)
            self.assertEqual(write.call_count,3)
        with patch.object(w.os,'set_blocking'),patch.object(w.time,'monotonic',return_value=4),\
             patch.object(w.os,'write') as write:
            with self.assertRaises(c.Stop):w._write_result(10,raw,4)
            write.assert_not_called()
        with self.assertRaises(c.Stop):w._write_result(10,b'x'*(c.MAX_RESULT+1),4)
