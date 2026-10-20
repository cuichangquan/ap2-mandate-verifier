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

    def test_seccomp_default_deny_arch_x32_and_indirect_signal_routes(self):
        # Pure classic-BPF interpreter, no kernel operation. Tests the exact
        # emitted instructions rather than a separate syscall membership model.
        def evaluate(nr,arch=0xc000003e,args=()):
            data={0:nr,4:arch}
            for i,v in enumerate(args):
                data[16+8*i]=v & 0xffffffff
                data[20+8*i]=(v >> 32) & 0xffffffff
            code=e.payload_filter();pc=0;acc=0
            while pc<len(code):
                op,jt,jf,k=code[pc]
                if op==0x20:acc=data.get(k,0)
                elif op==0x15:pc+=jt if acc==k else jf
                elif op==0x45:pc+=jt if acc&k else jf
                elif op==0x54:acc &= k
                elif op==0x06:return k
                else:self.fail('unknown BPF instruction')
                pc+=1
            self.fail('no terminal verdict')
        for nr in e.ALLOW_SYSCALLS:
            self.assertEqual(evaluate(nr),e.ALLOW)
            self.assertEqual(evaluate(nr|0x40000000),e.KILL)
            self.assertEqual(evaluate(nr,arch=0x40000003),e.KILL)
        # Direct/queued signals, ptrace/memory/pidfd, foreign resource controls,
        # networking/IPC/keyring/uring/perf and future unknown calls are denied.
        blocked=(29,30,31,41,53,62,64,65,66,67,68,69,70,71,101,129,141,
                 142,144,157,200,203,220,234,240,241,242,243,244,245,
                 248,249,250,251,297,298,310,311,314,317,321,424,425,
                 426,427,434,435,438,440,448,999)
        for nr in blocked:
            with self.subTest(nr=nr):self.assertEqual(evaluate(nr),e.DENY)
        for cmd in (8,9,10,15,16):self.assertEqual(evaluate(72,args=(1,cmd,0)),e.DENY)
        self.assertEqual(evaluate(72,args=(1,4,0x2000)),e.DENY)
        self.assertEqual(evaluate(72,args=(1,4,0x800)),e.ALLOW)
        for cmd in (0,1,2,3,5,6,7,1030):self.assertEqual(evaluate(72,args=(1,cmd,0)),e.ALLOW)
        self.assertEqual(evaluate(16,args=(1,0x5412,0)),e.DENY) # TIOCSTI
        for req in (0x5401,0x5413,0x541b):self.assertEqual(evaluate(16,args=(1,req)),e.ALLOW)
        self.assertEqual(evaluate(302,args=(42,0)),e.DENY)
        self.assertEqual(evaluate(302,args=(0,0)),e.ALLOW)
        for flags in (0x8000|17,0x2000|17,0x20000|17,0x10000000|17,0x100000000|17,10):
            self.assertEqual(evaluate(56,args=(flags,)),e.DENY)
        for flags in (17,0x10f00):self.assertEqual(evaluate(56,args=(flags,)),e.ALLOW)

    def test_landlock_file_leaves_and_output_only_writes(self):
        from test_p1r_execution_contract import profile
        from dataclasses import replace
        p,_=profile()
        for role in c.ROLES:
            rules=dict(e.payload_paths(p,role))
            self.assertEqual(rules['/'],e.LL_DIR)
            self.assertFalse(rules['/'] & (e.LL_READ|e.LL_EXEC|e.LL_WRITE))
            self.assertEqual(rules[e.OUTPUT],e.LL_OUTPUT)
            self.assertFalse(rules[e.OUTPUT]&e.LL_EXEC)
            for item in p.inventory:self.assertEqual(rules[item.path],e.LL_READ)
            for name,_ in c.INPUTS[role]:self.assertEqual(rules['/run/ap2-supervisor/input/'+name],e.LL_READ)
            self.assertFalse(any(path.startswith(('/proc/','/sys/')) for path in rules))
        for pseudo in ('/proc/owner/fd','/sys/file','/dev/other','/run/ambient'):
            entry=replace(p.inventory[0],path=pseudo)
            with self.assertRaises(c.Stop):e.payload_paths(replace(p,inventory=(entry,)+p.inventory[1:]),'builder')

    def test_landlock_and_seccomp_each_failure_stop_and_close_all_rule_fds(self):
        from unittest.mock import Mock
        from types import SimpleNamespace
        from test_p1r_execution_contract import profile
        p,_=profile()
        for failure in ('arch','abi','create','open','add','nnp','restrict','seccomp','device','none'):
            libc=Mock();opened=[];closed=[];sequence=[]
            def syscall(nr,*args):
                sequence.append(nr)
                if nr==444 and args[0]==0:return 2 if failure=='abi' else 3
                if nr==444:return -1 if failure=='create' else 10
                if nr==445:return -1 if failure=='add' else 0
                if nr==446:return -1 if failure=='restrict' else 0
                self.fail('unexpected syscall')
            def prctl(cmd,*args):
                sequence.append(cmd)
                return -1 if (cmd==38 and failure=='nnp') or (cmd==22 and failure=='seccomp') else 0
            libc.syscall.side_effect=syscall;libc.prctl.side_effect=prctl
            def opened_fd(path,*args):
                if failure=='open':raise OSError('open')
                opened.append(path);return 11
            def info(fd):
                path=opened[-1]
                mode=0o20666 if path.startswith('/dev/') else 0o40700 if path in ('/',e.OUTPUT) else 0o100444
                return SimpleNamespace(st_mode=mode,st_nlink=1,st_rdev=e.os.makedev(1,
                    99 if failure=='device' else {'/dev/null':3,'/dev/random':8,'/dev/urandom':9}.get(path,0)))
            with patch.object(e.platform,'system',return_value='Darwin' if failure=='arch' else 'Linux'),\
                 patch.object(e.platform,'machine',return_value='x86_64'),patch.object(e.ctypes,'CDLL',return_value=libc),\
                 patch.object(e.os,'open',side_effect=opened_fd),patch.object(e.os,'fstat',side_effect=info),\
                 patch.object(e.os,'close',side_effect=closed.append):
                if failure=='none':e.restrict_payload(p,'builder');self.assertEqual(sequence[-1],22)
                else:
                    with self.assertRaises((c.Stop,OSError)):e.restrict_payload(p,'builder')
                self.assertEqual(closed.count(11),len(opened))
                self.assertEqual(closed.count(10),0 if failure in ('arch','abi','create') else 1)

    def test_child_sandbox_after_FD_close_before_exec_and_failure_blocks_exec(self):
        from unittest.mock import Mock
        from test_p1r_execution_contract import profile
        class Exit(BaseException):pass
        for fail in (False,True):
            native=e.NativeKernel.__new__(e.NativeKernel)
            native.fds={};native.profile=profile()[0];native.role='builder'
            native.argv=c.payload_argv('builder',1700000000);native.env={};native._before=lambda _:None
            calls=[]
            def sandbox(*args):
                calls.append('sandbox')
                if fail:raise c.Stop('sandbox')
            with patch.object(e.os,'pipe',side_effect=[(10,11),(12,13)]),patch.object(e.os,'open',return_value=14),\
                 patch.object(e.os,'fork',return_value=0),patch.object(e.os,'dup2'),\
                 patch.object(e.os,'closerange',side_effect=lambda *a:calls.append('close')),\
                 patch.object(e,'restrict_payload',side_effect=sandbox),\
                 patch.object(e.os,'execve',side_effect=lambda *a:calls.append('exec')) as execute,\
                 patch.object(e.os,'_exit',side_effect=Exit):
                # exec mock returns, so force a fake exit before parent branch.
                if not fail:execute.side_effect=Exit
                with self.assertRaises(Exit):native.spawn(3)
                self.assertEqual(calls[:2],['close','sandbox'])
                if fail:execute.assert_not_called()
                else:execute.assert_called_once()

    def test_owner_absolute_work_and_lifecycle_FINISH_after_work(self):
        from test_p1r_execution_contract import profile
        from unittest.mock import Mock
        kernel=Kernel();deadlines=[];now=[12.5]
        original_prepare=kernel.prepare;original_spawn=kernel.spawn;original_reap=kernel.terminate_reap
        def prepare(deadline):deadlines.append(('prepare',deadline));original_prepare(deadline)
        def spawn(deadline):deadlines.append(('GO',deadline));original_spawn(deadline)
        def reap(deadline):deadlines.append(('reap',deadline));return original_reap(deadline)
        kernel.prepare=prepare;kernel.spawn=spawn;kernel.terminate_reap=reap
        controls=iter((b'GO\n',b'FINISH\n',b'RETIRE\n'));control_deadlines=[]
        def control(deadline):
            value=next(controls);control_deadlines.append(deadline)
            if value==b'FINISH\n':now[0]=13.001
            if value==b'RETIRE\n':now[0]=15.999
            self.assertLess(now[0],deadline)
            return value
        with patch.object(c,'select_native',return_value=profile()[0]),\
             patch.object(e,'NativeKernel',return_value=kernel),patch.object(e,'_write'),\
             patch.object(e,'_control',side_effect=control),patch.object(e.time,'monotonic',side_effect=lambda:now[0]):
            e._entry(['--owner','offline-fixture','builder','123','1700000000','13.0','16.0'])
        self.assertEqual(control_deadlines,[13,16,16])
        self.assertEqual(deadlines,[('prepare',13),('GO',13),('reap',16)])

    def test_owner_expired_startup_or_extended_pair_never_READY_or_exec(self):
        from test_p1r_execution_contract import profile
        for now,work,life in ((13,'13.0','16.0'),(12,'13.0','17.0'),(12,'nan','nan'),(9,'13.0','16.0')):
            with patch.object(c,'select_native',return_value=profile()[0]),\
                 patch.object(e,'NativeKernel') as kernel,patch.object(e,'_write') as write,\
                 patch.object(e.time,'monotonic',return_value=now):
                with self.subTest(now=now,work=work,life=life),self.assertRaises(c.Stop):
                    e._entry(['--owner','offline-fixture','builder','123','1700000000',work,life])
                kernel.assert_not_called();write.assert_not_called()
