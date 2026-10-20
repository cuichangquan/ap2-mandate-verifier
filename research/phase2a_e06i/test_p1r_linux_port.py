"""Integrated source/mock lifecycle; never a Linux execution or Gate proof."""
from dataclasses import replace
import unittest
from unittest.mock import patch
import p1r_execution_contract as c
import p1r_exec_owner as e
import p1r_linux_port as p
import p1r_linux_supervisor as s
from test_p1r_execution_contract import profile
from test_p1r_exec_owner import Kernel
from test_p1r_linux_supervisor import fixture, observation

class Handle:
    def __init__(self,fail=False):self.calls=0;self.fail=fail
    def close(self):
        self.calls+=1
        if self.fail:raise OSError('close')

class Ops:
    mode='OFFLINE_FAKE'
    def __init__(self,role='builder'):
        self.role=role;self.manifest,files=fixture(role);self.profile,self.files=profile(files)
        self.now=0.;self.calls=[];self.queue=[];self.owner=None;self.kernel=Kernel()
        self.kernel.events[-1]=('exit',0 if role=='builder' else 1)
        self.change=None;self.error=None;self.active=False;self.late=False;self.reaped=False
        self.artifacts={name:b'{}' for name,_ in c.OUTPUTS[role]}
        self.clock=lambda:self.now
    def hit(self,name):
        self.calls.append(name)
        if self.error==name:raise OSError('fake '+name)
    def absent(self,row):self.hit('absent');return True
    def read_pinned(self,path,limit):self.hit('read');return self.files[path]
    def verify_tree(self,profile):self.hit('tree')
    def submit(self,row,plan,profile,deadline):
        self.plan=plan;self.active=True;row.fds.extend((Handle(),Handle(),Handle()))
        self.hit('submit');self.owner=e.Owner(self.kernel,'123',plan.operation)
        self.queue.append(self.owner.prepare(deadline))
    def receive(self,row,deadline):
        self.hit('receive')
        if self.queue:return self.queue.pop(0)
        return self.owner.step(deadline)
    def readback(self,row,plan,profile,deadline):
        self.hit('observe');value=observation(plan)
        if self.change:self.change(value)
        return value
    def control(self,row,raw,deadline):
        self.hit(raw.decode().strip())
        if raw==b'GO\n':self.owner.go(deadline)
        elif raw==b'FINISH\n':self.queue.append(self.owner.finish(deadline))
    def collect(self,row,role,deadline):self.hit('collect');return dict(self.artifacts)
    def retire_owner(self,row,deadline):self.hit('retire');self.owner.retire()
    def reap_submitter(self,row,deadline):
        self.hit('reap')
        self.reaped=True
        if self.late:self.active=True
        return True
    def stop_unit(self,row,deadline):
        self.hit('stop');self.active=False
    def empty(self,row,deadline):self.hit('empty');return not self.active


def execute(ops):
    port=p.LinuxPort(ops.profile,ops)
    return s.Supervisor(port,clock=ops.clock).run_mock(ops.role,'123',ops.manifest),port

class Tests(unittest.TestCase):
    def test_all_roles_connect_and_artifacts_collected_before_retirement(self):
        for role in c.ROLES:
            with self.subTest(role=role):
                ops=Ops(role);result,port=execute(ops)
                self.assertEqual(result['artifacts'],ops.artifacts)
                self.assertFalse(result['actual_execution'])
                self.assertEqual(result['phase2_gate'],'HOLD')
                self.assertEqual(result['ap2_six_cases'],'NOT_RUN')
                self.assertLess(ops.calls.index('FINISH'),ops.calls.index('collect'))
                self.assertLess(ops.calls.index('collect'),ops.calls.index('retire'))
                self.assertLess(ops.calls.index('reap'),ops.calls.index('stop'))
                self.assertLess(ops.calls.index('stop'),ops.calls.index('empty'))
                self.assertEqual(port.phase,'CLOSED')

    def test_no_fake_profile_native_activation_or_cli_readiness(self):
        ops=Ops()
        with self.assertRaises(c.Stop):p.LinuxPort.native(ops.profile.name,'builder','123')
        with self.assertRaises(c.Stop):p.NativeOps(ops.profile,'builder','123')
        with self.assertRaises(c.Stop):p.LinuxPort(replace(ops.profile,purpose='LINUX_APPROVED'),ops)
        ops.mode='LINUX'
        with self.assertRaises(c.Stop):p.LinuxPort(ops.profile,ops)

    def test_every_parent_observation_missing_or_mismatched_blocks_GO(self):
        for key in observation(s.plan_for('builder','123',Ops().manifest)):
            ops=Ops();ops.change=lambda row,key=key:row.pop(key)
            with self.subTest(key=key),self.assertRaises((s.Stop,c.Stop)):
                execute(ops)
            self.assertNotIn('GO',ops.calls)
            self.assertIn('stop',ops.calls)

    def test_argv_and_resource_override_rejected_before_submission(self):
        ops=Ops();plan=s.plan_for('builder','123',ops.manifest)
        for changes in ({'argv':('/bin/sh',)},{'memory_bytes':2**30},{'output_dir':'/tmp'},
                        {'unit':'ap2-sup-124-builder.service'},{'expected_exit':99}):
            # A different wellformed run ID is allowed by fixed_plan, but not
            # by an already reserved allocation.
            port=p.LinuxPort(ops.profile,ops);port.reserve(plan)
            with self.subTest(changes=changes),self.assertRaises((c.Stop,ValueError)):
                port.submit_gated(replace(plan,**changes),3)
            self.assertNotIn('submit',ops.calls)

    def test_profile_tail_corruption_and_tree_failure_before_submit(self):
        for error in ('hash','tree'):
            ops=Ops()
            if error=='hash':ops.files[ops.profile.inventory[-1].path]+=b'tail'
            else:ops.error='tree'
            with self.subTest(error=error),self.assertRaises((c.Stop,OSError)):
                execute(ops)
            self.assertNotIn('submit',ops.calls)

    def test_partial_submission_owner_death_wait_and_close_uncertainty(self):
        for stage in ('submit','receive','observe','GO','FINISH','collect','retire','reap','stop','empty'):
            ops=Ops();ops.error=stage
            with self.subTest(stage=stage),self.assertRaises((s.Stop,c.Stop,OSError)):
                execute(ops)
            self.assertIn('stop',ops.calls)
            self.assertIn('empty',ops.calls)
        ops=Ops();ops.kernel.failure='reap'
        with self.assertRaises((s.Stop,c.Stop,OSError)):execute(ops)
        self.assertIn('retire',ops.calls);self.assertIn('stop',ops.calls)

    def test_late_registration_stopped_after_submitter_barrier(self):
        ops=Ops();ops.late=True
        result,_=execute(ops)
        self.assertTrue(result['cleanup']);self.assertFalse(ops.active)
        self.assertLess(ops.calls.index('reap'),ops.calls.index('stop'))

    def test_both_output_limits_and_exit_value_not_helper_exit(self):
        for role in c.ROLES:
            ops=Ops(role);ops.kernel.events=[('exit',0),('eof','stdout'),('eof','stderr')]
            if role=='builder':execute(ops)
            else:
                with self.assertRaises(s.Stop):execute(ops)
        for stream,cap in e.CAPS.items():
            for extra in (0,1):
                ops=Ops();ops.kernel.events=[('data',stream,b'x'*min(4096,cap+extra-i)) for i in range(0,cap+extra,4096)]
                ops.kernel.events += [('eof','stdout'),('eof','stderr'),('exit',0)]
                if extra:
                    with self.assertRaises((s.Stop,c.Stop)):execute(ops)
                else:
                    result,_=execute(ops);self.assertEqual(len(result[stream]),cap)

    def test_forged_frame_duplicate_binding_and_control_cannot_be_target_data(self):
        for packet in (e.Codec('124','builder').encode('ready',{'waiting':True}),
                       e.Codec('123','ruby').encode('ready',{'waiting':True}),
                       e.Codec('123','builder').encode('exit',{'code':0})):
            ops=Ops();original=ops.submit
            def submit(*args,packet=packet):
                original(*args);ops.queue[0]=packet
            ops.submit=submit
            with self.subTest(packet=packet),self.assertRaises((s.Stop,c.Stop)):
                execute(ops)
            self.assertNotIn('GO',ops.calls)

    def test_exact_artifact_names_and_sizes_and_collect_before_tmpfs_stop(self):
        for role in c.ROLES:
            for wrong in ({}, {'foreign':b'{}'}, {name:b'x'*(cap+1) for name,cap in c.OUTPUTS[role]}):
                ops=Ops(role);ops.artifacts=wrong
                with self.subTest(role=role),self.assertRaises((s.Stop,c.Stop)):execute(ops)
                self.assertIn('stop',ops.calls)

    def test_close_failure_disarms_owned_handles_and_still_reads_empty(self):
        ops=Ops();original=ops.submit;bad=Handle(True)
        def submit(*args):original(*args);args[0].fds.append(bad)
        ops.submit=submit
        with self.assertRaises(s.Stop):execute(ops)
        self.assertEqual(bad.calls,1);self.assertIn('empty',ops.calls)

    def test_native_tree_rejects_unlisted_links_metadata_and_missing_paths(self):
        ops=Ops();native=p.NativeOps.__new__(p.NativeOps)
        with patch.object(p.os,'lstat',return_value=type('Info',(),{'st_mode':0o40755,'st_uid':0})()), patch.object(p.os,'walk',return_value=[(c.ROOT,[],['foreign'])]):
            with self.assertRaises(c.Stop):native.verify_tree(ops.profile)
        with patch.object(p.os,'lstat',return_value=type('Info',(),{'st_mode':0o40755,'st_uid':0})()), patch.object(p.os,'walk',return_value=[]):
            with self.assertRaises(c.Stop):native.verify_tree(ops.profile)

    def test_native_mount_topology_rejects_other_writes_and_readonly_overmount(self):
        root='1 0 0:1 / / ro - ext4 /dev/root ro\n'
        output='2 1 0:2 / '+s.OUTPUT+' rw,nosuid,nodev - tmpfs tmpfs rw\n'
        p.mount_topology(root+output,s.READONLY,s.OUTPUT)
        for extra in ('3 1 0:3 / /opt/ap2-runtime rw - tmpfs tmpfs rw\n',
                      '3 1 0:3 / /dev/shm rw - tmpfs tmpfs rw\n',
                      '3 1 0:3 / /foreign rw - tmpfs tmpfs rw\n'):
            with self.subTest(extra=extra),self.assertRaises(c.Stop):p.mount_topology(root+output+extra,s.READONLY,s.OUTPUT)

    def test_native_owner_death_or_pid_reuse_blocks_anchored_collection(self):
        import select
        native=p.NativeOps.__new__(p.NativeOps);native.owner_pidfd=p.OwnedFD(10);native.ready_pid=42
        with patch.object(select,'select',return_value=([10],[],[])):
            with self.assertRaises(c.Stop):native._owner_alive()
        for text in ('Pid:\t-1\n','Pid:\t43\n'):
            native._text=lambda path,cap,text=text:text
            with patch.object(select,'select',return_value=([],[],[])):
                with self.subTest(text=text),self.assertRaises(c.Stop):native._owner_alive()
        native._text=lambda path,cap:'Pid:\t42\n'
        with patch.object(select,'select',return_value=([],[],[])):native._owner_alive()

    def test_native_artifact_atime_only_accepted_mtime_inode_changes_rejected(self):
        from types import SimpleNamespace
        native=p.NativeOps.__new__(p.NativeOps);native.ready_pid=42
        native.profile=Ops('oracle').profile;native._owner_alive=lambda:None;native._output_dir=lambda:10
        fields={'st_dev':1,'st_ino':2,'st_mode':0o100600,'st_uid':65534,'st_gid':65534,
                'st_nlink':1,'st_size':2,'st_mtime_ns':3,'st_ctime_ns':4,'st_atime_ns':5}
        before=SimpleNamespace(**fields)
        for change in ({'st_atime_ns':6},{'st_mtime_ns':6},{'st_ino':3}):
            after=SimpleNamespace(**dict(fields,**change))
            with patch.object(p.os,'listdir',return_value=['oracle.json']),patch.object(p.os,'open',return_value=11),\
                 patch.object(p.os,'close'),patch.object(p.os,'fstat',side_effect=[before,after]),\
                 patch.object(p.os,'read',side_effect=[b'{}',b'']),patch.object(p.time,'monotonic',return_value=0):
                if 'st_atime_ns' in change:self.assertEqual(native.collect(None,'oracle',3),{'oracle.json':b'{}'})
                else:
                    with self.assertRaises(c.Stop):native.collect(None,'oracle',3)

    def test_all_native_owner_root_components_are_nofollow_and_anchored(self):
        native=p.NativeOps.__new__(p.NativeOps);native.owner_root=p.OwnedFD(9);native._owner_alive=lambda:None
        with patch.object(p.os,'dup',return_value=10),patch.object(p.os,'open',side_effect=[11,12,13]) as opened,patch.object(p.os,'close') as closed:
            self.assertEqual(native._output_dir(),13)
            self.assertEqual([x.args[0] for x in opened.call_args_list],['run','ap2-supervisor','output'])
            self.assertTrue(all(x.args[1]&p.os.O_NOFOLLOW for x in opened.call_args_list))
            self.assertEqual([x.kwargs['dir_fd'] for x in opened.call_args_list],[10,11,12])

    def test_mock_builder_oracle_ruby_handoff_hashes_changing_inputs(self):
        builder,_=execute(Ops('builder'))
        previous=builder['artifacts']
        for role in ('oracle','ruby'):
            ops=Ops(role)
            values={name:previous[name] for name,_ in c.INPUTS[role]}
            for name,raw in values.items():ops.files[s.INPUT+'/'+name]=raw
            ops.manifest=c.manifest_for(ops.profile,role,1700000000,values)
            result,_=execute(ops)
            previous=dict(previous,**result['artifacts'])
            self.assertEqual(result['phase2_gate'],'HOLD')
            self.assertFalse(result['actual_execution'])

    def test_integer_control_receipts_do_not_pass_as_true(self):
        for packet in (e.Codec('123','builder').encode('ready',{'waiting':1}),):
            ops=Ops();original=ops.submit
            def submit(*args):original(*args);ops.queue[0]=packet
            ops.submit=submit
            with self.assertRaises((c.Stop,s.Stop)):execute(ops)
            self.assertNotIn('GO',ops.calls)

    def test_native_submit_requests_readonly_API_and_separate_sealed_input_bind(self):
        from unittest.mock import MagicMock
        import p1r_watchdog as w
        ops=Ops();native=p.NativeOps.__new__(p.NativeOps)
        native.role='builder';native.run='123';native.token='a'*32;native.snapshot='/run/ap2-controller/fixed'
        native._stage_inputs=MagicMock()
        process=MagicMock();process.stdin.fileno.return_value=10;process.stdout.fileno.return_value=11;process.stderr.fileno.return_value=12
        row=w.Allocation('ap2-sup-123-builder.service');plan=s.plan_for('builder','123',ops.manifest)
        with patch.object(p.subprocess,'Popen',return_value=process) as popen,patch.object(p.os,'set_blocking'),patch.object(p.selectors,'DefaultSelector'):
            native.submit(row,plan,ops.profile,3)
        argv=popen.call_args.args[0]
        props={arg[len('--property='):].split('=',1)[0]:arg.split('=',2)[2] for arg in argv if arg.startswith('--property=')}
        for path in ('/proc','/sys','/dev','/run'):self.assertIn(path,props['ReadOnlyPaths'].split())
        self.assertEqual(props['ReadWritePaths'],s.OUTPUT)
        self.assertEqual(props['BindReadOnlyPaths'],native.snapshot+'/input:'+s.INPUT)
        self.assertEqual(props['RuntimeMaxSec'],'6s')
        self.assertEqual(plan.runtime_seconds,3)
        self.assertEqual(argv[-2:],['3.0','6.0'])
        self.assertIn('mode=0700',props['TemporaryFileSystem'])
        self.assertIn('uid=65534',props['TemporaryFileSystem'])
        self.assertNotIn('-c',argv);self.assertTrue(popen.call_args.kwargs['close_fds'])

    def test_native_staging_foreign_owner_never_unlinks(self):
        native=p.NativeOps.__new__(p.NativeOps);native.snapshot='/run/ap2-controller/fixed';native.token='a'*32;native.inputs={}
        with patch.object(p.os,'open',side_effect=[10,11]),patch.object(p.os,'read',return_value=b'foreign'),patch.object(p.os,'close'),patch.object(p.os,'unlink') as unlink:
            with self.assertRaises(c.Stop):native._clean_inputs()
            unlink.assert_not_called()

    def test_ipv6_kernel_loopback_is_not_external_route(self):
        row = '0'*32+' 00 '+'0'*32+' 00 '+'0'*32+' ffffffff 00000001 00000000 00200200 lo'
        for good in ('',row,row+'\n'+row):
            self.assertTrue(p.harmless_ipv6(good))
        for bad in (row.replace(' lo',' eth0'),row.replace(' lo',' veth0'),
                    row.replace('0'*32+' ffffffff','1'*32+' ffffffff'),
                    row.replace(' 00 ',' zz ',1),row+' extra','malformed'):
            with self.subTest(bad=bad):self.assertFalse(p.harmless_ipv6(bad))

    def test_staged_input_fchmod_ignores_restrictive_umask_and_failure_closes(self):
        from types import SimpleNamespace
        native=p.NativeOps.__new__(p.NativeOps)
        native.snapshot='/run/ap2-controller/fixed';native.token='a'*32
        native.inputs={'fixture.json':b'{}','policy.json':b'{}'}
        for fail in (False,True):
            modes={};written=[]
            def chmod(fd,mode):
                modes[fd]=mode
                if fail and fd==13:raise OSError('chmod')
            def opened(path,flags,mode=0,**kwargs):
                fd={'owner':11,'input':12,'fixture.json':13,'policy.json':14}.get(path,10)
                # Simulated umask077: open0444 becomes0400, then fchmod must fix.
                if path.endswith('.json'):modes[fd]=mode & ~0o077
                return fd
            def write(fd,raw):
                if fd in (13,14):
                    self.assertEqual(modes[fd],0o444);written.append(fd)
                return len(raw)
            with patch.object(p.os,'lstat',return_value=SimpleNamespace(st_mode=0o40755,st_uid=0)),\
                 patch.object(p.os,'mkdir'),patch.object(p.os,'open',side_effect=opened),\
                 patch.object(p.os,'fchmod',side_effect=chmod),patch.object(p.os,'write',side_effect=write),\
                 patch.object(p.os,'close') as close:
                if fail:
                    with self.assertRaises(OSError):native._stage_inputs()
                    self.assertEqual(written,[])
                else:
                    native._stage_inputs();self.assertEqual(written,[13,14]);self.assertEqual(modes[12],0o555)
                self.assertIn(13,[call.args[0] for call in close.call_args_list])
