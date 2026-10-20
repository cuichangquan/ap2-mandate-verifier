"""Owner/framing regressions using fake kernel events only."""
import json
import struct
import unittest
from unittest.mock import patch
import p1r_execution_contract as c
import p1r_exec_owner as e

class Kernel:
    def __init__(self):
        self.calls=[]; self.members=(); self.failure=None
        self.events=[('data','stdout',b'log'),('eof','stdout'),('eof','stderr'),('exit',0)]
    def prepare(self,deadline):
        self.calls.append('prepare')
        if self.failure=='prepare': raise OSError('prctl')
    def children(self): return self.members
    def spawn(self,deadline):
        self.calls.append('spawn'); self.members=(42,)
        if self.failure=='spawn': raise OSError('partial spawn')
    def event(self,limits,deadline):
        self.calls.append('event')
        return self.events.pop(0) if self.events else ('idle',)
    def terminate_reap(self,deadline):
        self.calls.append('reap')
        if self.failure=='reap': raise OSError('wait/close')
        self.members=()
        return {'children_reaped':True,'payload_io_closed':True}

class Tests(unittest.TestCase):
    def test_singleton_gate_and_reap_before_retirement(self):
        k=Kernel(); owner=e.Owner(k,'123','builder'); decoder=e.Codec('123','builder')
        self.assertEqual(decoder.feed(owner.prepare(3)),[('ready',{'waiting':True})])
        self.assertNotIn('spawn',k.calls)
        owner.go(3)
        for _ in range(4): decoder.feed(owner.step(3))
        self.assertEqual(owner.exit,0);self.assertEqual(len(owner.ended),2)
        decoder.feed(owner.finish(5));self.assertEqual(owner.state,'RETAINING')
        owner.retire();self.assertEqual(owner.state,'RETIRED')
        with self.assertRaises(c.Stop):owner.go(3)

    def test_pre_GO_children_and_duplicate_GO_block_spawn(self):
        for members in ((42,),(42,43)):
            k=Kernel(); k.members=members
            with self.subTest(members=members),self.assertRaises(c.Stop):e.Owner(k,'123','builder').prepare(3)
            self.assertNotIn('spawn',k.calls)
        k=Kernel();owner=e.Owner(k,'123','builder');owner.prepare(3);owner.go(3)
        with self.assertRaises(c.Stop):owner.go(3)
        self.assertEqual(k.calls.count('spawn'),1)

    def test_partial_spawn_failure_remains_owned_for_reap(self):
        k=Kernel(); k.failure='spawn';o=e.Owner(k,'123','builder');o.prepare(3)
        with self.assertRaises(OSError):o.go(3)
        self.assertEqual(o.state,'STARTING');o.finish(5);self.assertIn('reap',k.calls)

    def test_both_decoded_stream_exact_limits_and_overflow(self):
        for stream,cap in e.CAPS.items():
            for extra in (0,1):
                k=Kernel();o=e.Owner(k,'123','builder');o.prepare(3);o.go(3)
                k.events=[('data',stream,b'x'*min(4096,cap+extra-i)) for i in range(0,cap+extra,4096)]
                if extra:
                    with self.assertRaises(c.Stop):
                        for _ in range(len(k.events)):o.step(3)
                else:
                    decoder=e.Codec('123','builder');decoder.sequence=1
                    for _ in range(len(k.events)):decoder.feed(o.step(3))
                    self.assertEqual(o.bytes[stream],cap)

    def test_invalid_payload_events_never_become_owner_control(self):
        for event in (('ready',{}),('data','control',b'x'),('data','stdout','x'),
                      ('exit',True),('eof','foreign'),('exit',0,1),('data','stdout',b'x'*4097)):
            k=Kernel();o=e.Owner(k,'123','builder');o.prepare(3);o.go(3);k.events=[event]
            with self.subTest(event=event),self.assertRaises(c.Stop):o.step(3)

    def test_wait_or_close_failure_is_never_reaped_receipt(self):
        k=Kernel();o=e.Owner(k,'123','builder');o.prepare(3);k.failure='reap'
        with self.assertRaises(OSError):o.finish(5)
        self.assertEqual(o.state,'FINALIZING')
        with self.assertRaises(c.Stop):o.retire()

    def test_frame_binding_sequence_duplicates_fragmentation_and_truncation(self):
        enc=e.Codec('123','builder');packet=enc.encode('ready',{'waiting':True})
        dec=e.Codec('123','builder');out=[]
        for byte in packet:out+=dec.feed(bytes([byte]))
        self.assertEqual(out,[('ready',{'waiting':True})]);dec.eof()
        for other in (e.Codec('124','builder'),e.Codec('123','ruby')):
            with self.assertRaises(c.Stop):other.feed(packet)
        with self.assertRaises(c.Stop):dec.feed(packet)
        dec=e.Codec('123','builder');dec.feed(packet[:-1])
        with self.assertRaises(c.Stop):dec.eof()
        raw=b'{"run":"123","run":"123"}'
        with self.assertRaises(c.Stop):e.Codec('123','builder').feed(struct.pack('!I',len(raw))+raw)
        with self.assertRaises(c.Stop):e.Codec('123','builder').feed(struct.pack('!I',e.FRAME_CAP+1))

    def test_raw_control_and_event_caps_are_independent(self):
        with self.assertRaises(c.Stop):e.Codec('123','builder').feed(b'x'*(e.RAW_CAP+1))
        enc=e.Codec('123','builder');dec=e.Codec('123','builder')
        with self.assertRaises(c.Stop):
            for _ in range(20):dec.feed(enc.encode('ready',{'value':'x'*1024}))
        enc=e.Codec('123','builder')
        with self.assertRaises(c.Stop):
            for _ in range(e.EVENT_CAP+1):enc.encode('eof',{'stream':'stdout'})

    def test_native_and_bootstrap_reject_before_any_effect(self):
        for role in c.ROLES:
            with self.assertRaises(c.Stop):e.NativeKernel('offline-fixture',role,'123',1700000000)
            with self.assertRaises(c.Stop):e._entry(['--python-target='+role,'/arbitrary.py'])
        with self.assertRaises(c.Stop):e._entry(['--owner','offline-fixture','builder','123','1700000000'])

    def test_native_partial_fork_or_selector_failure_reaps_and_closes_ledger(self):
        from unittest.mock import Mock
        for failure in ('fork','selector'):
            native=e.NativeKernel.__new__(e.NativeKernel)
            native.fds={};native.selector=None;native.payload_pid=None
            native.argv=c.payload_argv('builder',1700000000);native.env={}
            native._before=lambda deadline:None;native._members=lambda:(e.os.getpid(),)
            selector=Mock()
            if failure=='selector':selector.register.side_effect=OSError('selector')
            with patch.object(e.os,'pipe',side_effect=[(10,11),(12,13)]),patch.object(e.os,'open',return_value=14),\
                 patch.object(e.os,'fork',side_effect=OSError('fork') if failure=='fork' else None,return_value=42),\
                 patch.object(e.os,'set_blocking'),patch.object(e.os,'close') as close,\
                 patch.object(e.selectors,'DefaultSelector',return_value=selector),\
                 patch.object(e.os,'waitpid',side_effect=ChildProcessError),patch.object(e.os,'listdir',return_value=[]):
                with self.assertRaises(OSError):native.spawn(3)
                self.assertEqual(native.terminate_reap(5),{'children_reaped':True,'payload_io_closed':True})
                self.assertEqual(sorted(x.args[0] for x in close.call_args_list),[10,11,12,13,14])
                self.assertTrue(all(fd is None for fd in native.fds.values()))

    def test_native_close_failure_or_unknown_FD_never_claims_IO_closed(self):
        from unittest.mock import Mock
        for failure in ('close','foreign'):
            native=e.NativeKernel.__new__(e.NativeKernel)
            native.fds={'stdout-read':10};native.selector=None
            native._before=lambda deadline:None;native._members=lambda:(e.os.getpid(),)
            with patch.object(e.os,'waitpid',side_effect=ChildProcessError),\
                 patch.object(e.os,'close',side_effect=OSError('close') if failure=='close' else None) as close,\
                 patch.object(e.os,'listdir',return_value=['99'] if failure=='foreign' else []),\
                 patch.object(e.os,'readlink',return_value='pipe:[1]'):
                with self.assertRaises(c.Stop):native.terminate_reap(5)
                self.assertEqual(native.fds['stdout-read'],None)
                close.assert_called_once_with(10)
