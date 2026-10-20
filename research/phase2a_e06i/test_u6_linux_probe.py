"""Mac-safe fake tests. Never launch services, target payloads or sockets."""
import hashlib
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import sys
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('u6',Path(__file__).with_name('u6_linux_probe.py'))
u6=importlib.util.module_from_spec(spec)
spec.loader.exec_module(u6)


def report():
    return {'management':[], 'run':'123', 'cases':[{'case':c,'status':'NOT_RUN'} for c in u6.CASES]}


def query(out='running\n',code=0,**kw):
    return dict(stdout=out,stderr='',returncode=code,query_reaped=True,failure=None,
                bytes_read={'stdout':len(out),'stderr':0},**kw)


class FakeTests(unittest.TestCase):
    def test_payloads_compile_without_execution(self):
        self.assertEqual(len(u6.CASES),9)
        self.assertEqual(set(u6.CASES),set(u6.WORK))
        for case in u6.CASES:
            args,_,code=u6.unit_command('u6-v3-123-0.service',Path('/run/u6-owned'),'n','m',case)
            self.assertEqual(args[args.index('-c')+1],code)
            compile(code,'<synthetic>','exec')
            tail='' if case in ('timeout','output','pids','descendants') else '\ntime.sleep(30)\n'
            self.assertEqual(code,u6.COMMON+u6.WORK[case]+tail)

    def test_argv_limits_and_lifecycle(self):
        args,props,_=u6.unit_command('u6-v3-123-0.service',Path('/run/u6-owned'),'net:1','mnt:1','network')
        self.assertEqual(props['RemainAfterExit'],'no')
        self.assertEqual(props['Restart'],'no')
        self.assertEqual(props['Delegate'],'no')
        self.assertEqual(props['MemoryMax'],'67108864')
        self.assertEqual(props['TasksMax'],'16')
        self.assertEqual(props['WorkingDirectory'],'/run/u6-owned/work')
        self.assertIn('size=32M,nr_inodes=256',props['TemporaryFileSystem'])
        self.assertIn('--pipe',args)
        self.assertIn('--expand-environment=no',args)
        self.assertNotIn('--collect',args)

    def test_oracles_require_admission_and_cleanup(self):
        for case in u6.CASES:
            data=b'U6_READY {}\n'+u6.TOKENS[case].encode()+b'\n'
            props={'Result':'timeout' if case=='timeout' else 'success','ActiveState':'active'}
            overflow=case=='output'
            self.assertTrue(u6.verdict(case,data,props,overflow,True,True))
            self.assertFalse(u6.verdict(case,data,props,overflow,False,True))
            self.assertFalse(u6.verdict(case,data,props,overflow,True,False))
            self.assertFalse(u6.verdict(case,b'',props,overflow,True,True))
        self.assertFalse(u6.verdict('timeout',b'TIMEOUT_READY\n',{'Result':'success'},False,True,True))
        self.assertFalse(u6.verdict('network',b'NETWORK_BLOCKED\n',{'ActiveState':'failed'},False,True,True))

    def test_property_parse_rejects_duplicates_and_incomplete(self):
        for text in ('Version=255\nVersion=255\n','invalid'):
            with self.assertRaises(u6.Stop): u6.pairs(text)
        self.assertEqual(u6.pairs('A=\nB=0\n'),{'A':'','B':'0'})

    def test_nonlinux_never_calls_management(self):
        with patch.object(u6.platform,'system',return_value='Darwin'):
            with self.assertRaisesRegex(u6.Stop,'LINUX_ROOT_REQUIRED'):
                u6.preflight(None,report())

    def preflight_with(self, manager, rep):
        with patch.object(u6.platform,'system',return_value='Linux'), patch.object(u6.platform,'machine',return_value='x86_64'), patch.object(u6.os,'geteuid',return_value=0), patch.object(u6.os,'access',return_value=True), patch.object(u6,'read_file',side_effect=['VERSION_ID="24.04"','memory pids']):
            u6.preflight(manager,rep)

    def test_manager_state_is_only_permission_to_check_capabilities(self):
        for state in ('running','starting','initializing','degraded','maintenance','stopping','offline','unknown',''):
            with self.subTest(state=state):
                rep=report()
                manager=SimpleNamespace(run=lambda *a,**k:query('Version=255.4-1ubuntu8.12\nSystemState='+state+'\n'))
                if state in ('running','starting'):
                    self.preflight_with(manager,rep)
                    self.assertEqual(rep['capability_admission'],'REQUIRED_BEFORE_EACH_GO')
                else:
                    with self.assertRaisesRegex(u6.Stop,'MANAGER_UNAVAILABLE'):
                        self.preflight_with(manager,rep)
                self.assertTrue(all(c['status']=='NOT_RUN' for c in rep['cases']))

    def test_manager_version_format_and_query_budget(self):
        for body,ok in (('Version=255.4-1ubuntu8.12\nSystemState=starting\n',True),
                        ('Version=256\nSystemState=running\n',False),
                        ('Version=255\nSystemState=running\nVersion=255\n',False),
                        ('Version=255\n',False),('invalid',False)):
            calls=[]
            def run(args,**kw):
                calls.append((args,kw)); return query(body)
            manager=SimpleNamespace(run=run)
            if ok: self.preflight_with(manager,report())
            else:
                with self.assertRaises(u6.Stop): self.preflight_with(manager,report())
            self.assertEqual(len(calls),1)
            self.assertEqual(calls[0][0],['/usr/bin/systemctl','--system','show','--property=Version','--property=SystemState'])
            self.assertEqual(calls[0][1]['seconds'],4)

    def test_manager_failures_stop_before_lab_or_target(self):
        for change in ({'returncode':1},{'stderr':'unexpected'},
                       {'failure':'COMMAND_TIMEOUT'},{'failure':'COMMAND_OUTPUT_LIMIT'},
                       {'query_reaped':False}):
            rep=report(); manager=u6.Management(rep,100)
            row=query('Version=255\nSystemState=starting\n'); row.update(change)
            with self.subTest(change=change), patch.object(u6.time,'monotonic',return_value=0), patch.object(u6.subprocess,'Popen',return_value=object()), patch.object(u6._capture,'capture',return_value=row), patch.object(u6.tempfile,'mkdtemp') as lab:
                with self.assertRaises(u6.Stop): self.preflight_with(manager,rep)
                lab.assert_not_called()
            self.assertTrue(all(c['status']=='NOT_RUN' for c in rep['cases']))

    def test_payload_digest_changes_with_common_body_and_tail(self):
        for case in u6.CASES:
            _,_,original=u6.unit_command('u',Path('/run/u'),'n','m',case)
            for common,work in ((u6.COMMON+'# common changed\n',u6.WORK),
                                (u6.COMMON,dict(u6.WORK,**{case:u6.WORK[case]+'# body changed\n'}))):
                with patch.object(u6,'COMMON',common),patch.object(u6,'WORK',work):
                    _,_,changed=u6.unit_command('u',Path('/run/u'),'n','m',case)
                self.assertNotEqual(hashlib.sha256(original.encode()).hexdigest(),hashlib.sha256(changed.encode()).hexdigest())
            if case in ('network','readonly_permissions','memory','disk','inode'):
                self.assertNotEqual(hashlib.sha256(original.encode()).hexdigest(),hashlib.sha256((u6.COMMON+u6.WORK[case]).encode()).hexdigest())

    def test_management_preserves_nonzero_and_bounded_failures(self):
        for failure in (None,'COMMAND_TIMEOUT','COMMAND_OUTPUT_LIMIT'):
            rep=report(); manager=u6.Management(rep,100)
            row=query('starting\n',1); row['failure']=failure
            with patch.object(u6.time,'monotonic',return_value=0), patch.object(u6.subprocess,'Popen',return_value=object()), patch.object(u6._capture,'capture',return_value=row):
                with self.assertRaises(u6.Stop): manager.run(['/fixed'],stage='TEST')
            self.assertEqual(rep['management'][0]['returncode'],1)
            self.assertEqual(rep['management'][0]['stdout'],'starting\n')

    def test_management_ledger_and_command_caps_leave_cleanup_bounded(self):
        rep=report(); manager=u6.Management(rep,100)
        manager.record({'stdout':'x'*65000},False)
        with self.assertRaisesRegex(u6.Stop,'CAPTURE_LIMIT'):
            manager.record({'stdout':'y'*1000},False)
        manager.record({'stdout':'y'*1000},True)
        self.assertLessEqual(manager.bytes,65536)
        self.assertLessEqual(len(json.dumps(rep['management']).encode()),65536)
        self.assertEqual(len(rep['management']),1)
        self.assertTrue(rep['management_truncated'])
        manager.calls=140
        with self.assertRaisesRegex(u6.Stop,'COMMAND_COUNT_LIMIT'):
            manager.run(['/fixed'],stage='LIMIT')

    def test_main_fake_nine_and_first_failure_stop(self):
        for failed in (None,'memory'):
            rep=[]
            with tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp)/'lab'; root.mkdir()
                class Lab:
                    units={}
                    def __init__(self,root,management,result): self.result=result
                    def run(self,case,index):
                        self.result['cases'][index]['status']='FAIL' if case==failed else 'PASS'
                        if case==failed: raise u6.Stop('CASE_FAILED_memory')
                with patch.dict(u6.os.environ,{'GITHUB_RUN_ID':'123'}), patch.object(u6,'preflight'), patch.object(u6.tempfile,'mkdtemp',return_value=str(root)), patch.object(u6,'Lab',Lab), patch.object(u6.signal,'signal'), patch.object(u6.signal,'alarm'), patch.object(Path,'write_bytes',side_effect=lambda b:rep.append(json.loads(b))):
                    self.assertEqual(u6.main(),0 if failed is None else 78)
            self.assertEqual(len(rep[0]['cases']),9)
            self.assertTrue(rep[0]['cleanup'])
            if failed: self.assertEqual(rep[0]['cases'][-1]['status'],'NOT_RUN')

    def make_lab(self):
        with patch.object(u6.os,'readlink',side_effect=['net:parent','mnt:parent']):
            lab=u6.Lab(Path('/run/u6-owned'),SimpleNamespace(run=lambda *a,**k:query(),case_deadline=None),report())
        unit='u6-v3-123-0.service'
        lab.units[unit]={'observed_cgroup':True,'submitter_reaped':True,'clean':False}
        return lab,unit

    def test_cleanup_requires_stopped_empty_observed_and_reaped(self):
        for state,populated,observed,reaped,ok in (
            ('inactive','0',True,True,True),('active','0',True,True,False),
            ('inactive','1',True,True,False),('inactive','0',False,True,False),
            ('inactive','0',True,False,False)):
            lab,unit=self.make_lab()
            lab.units[unit].update(observed_cgroup=observed,submitter_reaped=reaped)
            with patch.object(lab,'show',return_value={'ActiveState':state}), patch.object(Path,'exists',return_value=True), patch.object(u6,'read_file',return_value='populated '+populated+'\n'):
                if ok: self.assertTrue(lab.cleanup(unit))
                else:
                    with self.assertRaises(u6.Stop): lab.cleanup(unit)
                    self.assertFalse(lab.units[unit]['clean'])

    def test_delayed_registration_is_stopped_after_submitter_reap(self):
        lab,unit=self.make_lab(); lab.units[unit]['submitter_reaped']=False
        events=[]; active=[False]
        class Pipe:
            def close(self): pass
        class Proc:
            pid=12345; returncode=None; stdin=Pipe(); stdout=Pipe(); stderr=Pipe()
            def poll(self): return self.returncode
            def wait(self,timeout):
                events.append('reap_and_late_register'); active[0]=True; self.returncode=-9
        def run(args,**kw):
            events.append('final_stop'); self.assertTrue(active[0]); active[0]=False
            return query()
        lab.management.run=run
        with patch.object(u6._capture,'kill_query',side_effect=lambda p:events.append('kill')), patch.object(lab,'show',side_effect=lambda *a,**k:{'ActiveState':'active' if active[0] else 'inactive'}), patch.object(Path,'exists',return_value=False):
            lab.finish(unit,Proc(),{})
        self.assertEqual(events,['kill','reap_and_late_register','final_stop'])
        self.assertTrue(lab.units[unit]['clean'])
        self.assertFalse(active[0])

    def test_never_registered_absence_cannot_be_cached_clean(self):
        lab,unit=self.make_lab(); lab.units[unit]['observed_cgroup']=False
        with patch.object(lab,'show',return_value={'LoadState':'not-found','ActiveState':'inactive'}), patch.object(Path,'exists',return_value=False):
            with self.assertRaisesRegex(u6.Stop,'CLEANUP_UNCONFIRMED_REGISTRATION'): lab.cleanup(unit)
        self.assertFalse(lab.units[unit]['clean'])

    def test_baseline_rejects_each_property_before_proc_reads(self):
        unit='u6-v3-123-0.service'; root=Path('/run/u6-owned')
        ready={'pid':42,'uid':65534,'net':'n','mnt':'m','cgroup':'/system.slice/'+unit,'fs_bytes':33554432,'inodes':256}
        props=dict(u6.READBACK,ControlGroup=ready['cgroup'],MainPID='42')
        for key in u6.READBACK:
            changed=dict(props); changed[key]='UNTRUSTED'
            with self.subTest(key=key), patch.object(u6,'read_file') as read:
                with self.assertRaises(u6.Stop): u6.baseline(ready,changed,unit,root,'p','q')
                read.assert_not_called()

    def test_full_fake_controller_nine_cases_handshake_and_reap_order(self):
        rejects=[(key,missing) for key in list(u6.READBACK)+['MainPID','ControlGroup','ReadOnlyPaths','WorkingDirectory','TemporaryFileSystem','ActiveState'] for missing in (False,True)]
        for index,case,bad in [(i,c,None) for i,c in enumerate(u6.CASES)]+[(0,'network',None)]+[(0,'network',bad) for bad in rejects]:
            late = bad is None and index==0 and case=='network' and getattr(self,'_network_seen',False)
            if case=='network': self._network_seen=True
            with self.subTest(case=case,late_cleanup=late,bad=bad):
                lab,unit=self.make_lab(); lab.units={}
                lab.management.deadline=100
                events=[]; go=[False]; stopped=[False]
                clock=[0]
                ready={'pid':42,'uid':65534,'net':'n','mnt':'m','cgroup':'/system.slice/'+unit,'fs_bytes':33554432,'inodes':256}
                prefix=('U6_READY '+json.dumps(ready)+'\n').encode()
                body=(b'x'*131072 if case=='output' else u6.TOKENS[case].encode()+b'\n')
                buffers={'stdout':bytearray(prefix),'stderr':bytearray()}
                body_added=[False]; eof=set()
                class Pipe:
                    def __init__(self,name): self.name=name
                    def write(self,value):
                        self_test.assertEqual(value,b'GO\n'); go[0]=True; events.append('GO')
                    def flush(self): pass
                    def close(self): pass
                class Proc:
                    pid=12345; returncode=None
                    stdin=Pipe('stdin'); stdout=Pipe('stdout'); stderr=Pipe('stderr')
                    def poll(self):
                        if len(eof)==2: self.returncode=0
                        return self.returncode
                    def wait(self,timeout):
                        events.append('REAP'); self.returncode=-9
                        if late: clock[0]=6.1
                class Selector:
                    def __init__(self): self.items={}
                    def __enter__(self): return self
                    def __exit__(self,*args): pass
                    def register(self,pipe,mask,name): self.items[pipe]=SimpleNamespace(fd=name,data=name,fileobj=pipe)
                    def unregister(self,pipe): del self.items[pipe]
                    def get_map(self): return self.items
                    def select(self,timeout): return [(key,1) for key in list(self.items.values())]
                def read(name,count):
                    if name=='stdout' and not buffers[name] and go[0] and not body_added[0]:
                        buffers[name].extend(body); body_added[0]=True
                    chunk=bytes(buffers[name][:count]); del buffers[name][:count]
                    if not chunk: eof.add(name)
                    return chunk
                def show(unit,full=False,cleanup=False):
                    events.append('SHOW')
                    if cleanup: return {'LoadState':'not-found','ActiveState':'inactive'}
                    if full and bad:
                        props=dict(u6.READBACK,ControlGroup=ready['cgroup'],MainPID='42',ActiveState='active',ReadOnlyPaths=str(lab.root/'ro'),WorkingDirectory=str(lab.root/'work'),TemporaryFileSystem=str(lab.root/'work')+':rw,size=32M,nr_inodes=256,mode=1777,nosuid,nodev')
                        if bad[1]: props.pop(bad[0],None)
                        else: props[bad[0]]='UNTRUSTED'
                        return props
                    return {'ActiveState':'failed' if case=='timeout' and not full else 'active',
                            'Result':'timeout' if case=='timeout' and not full else 'success'}
                def command(args,**kw):
                    events.append('STOP'); self_test.assertIn('REAP',events); stopped[0]=True
                    return query()
                self_test=self
                lab.show=show; lab.management.run=command
                with patch.object(u6.time,'monotonic',side_effect=lambda:clock[0]), patch.object(u6.subprocess,'Popen',return_value=Proc()), patch.object(u6.selectors,'DefaultSelector',Selector), patch.object(u6.os,'read',side_effect=read), patch.object(u6,'baseline',side_effect=u6.baseline if bad else lambda *a:'/system.slice/'+unit), patch.object(u6,'read_file',return_value='42\n43\n'), patch.object(Path,'exists',return_value=False), patch.object(u6._capture,'kill_query',side_effect=lambda p:events.append('KILL')):
                    if bad:
                        with self.assertRaisesRegex(u6.Stop,'CLEANUP_UNCONFIRMED_REGISTRATION'): lab.run(case,index)
                    elif late:
                        with self.assertRaisesRegex(u6.Stop,'DEADLINE_CASE_INCLUDING_CLEANUP'): lab.run(case,index)
                    else: lab.run(case,index)
                row=lab.report['cases'][index]
                self.assertEqual(row['source_sha256'],hashlib.sha256(u6.unit_command(unit,lab.root,lab.parent_net,lab.parent_mnt,case)[2].encode('utf-8')).hexdigest())
                if bad:
                    self.assertNotIn('GO',events)
                    self.assertFalse(row['cleanup']['clean'])
                    self.assertEqual(row['admission'],'NOT_CONFIRMED')
                    self.assertEqual(row['status'],'FAIL')
                    continue
                self.assertEqual(row['status'],'FAIL' if late else 'PASS')
                self.assertTrue(row['cleanup']['clean'])
                self.assertTrue(stopped[0] and go[0])
                self.assertLess(events.index('REAP'),events.index('STOP'))

    def test_baseline_independent_kernel_and_namespace_positive_and_negative(self):
        unit='u6-v3-123-0.service'; root=Path('/run/u6-owned'); cg='/system.slice/'+unit
        ready={'pid':42,'uid':65534,'net':'n','mnt':'m','cgroup':cg,'fs_bytes':33554432,'inodes':256}
        props=dict(u6.READBACK,ControlGroup=cg,MainPID='42',ActiveState='active',ReadOnlyPaths=str(root/'ro'),WorkingDirectory=str(root/'work'),TemporaryFileSystem=str(root/'work')+':rw,size=32M,nr_inodes=256,mode=1777,nosuid,nodev')
        for bad in (None,'memory.max','memory.swap.max','pids.max','namespace','mount_namespace','uid','nnp','caps','membership','proc_cgroup','fs_bytes','inodes','mount_type','mount_flags','cgroup_symlink'):
            def read(path,cap=65536):
                path=str(path)
                if path.endswith('/cgroup'): return '0::'+('/foreign' if bad=='proc_cgroup' else cg)+'\n'
                if path.endswith('/status'): return 'Uid: '+('0 0 0 0' if bad=='uid' else '65534 65534 65534 65534')+'\nNoNewPrivs: '+('0' if bad=='nnp' else '1')+'\nCapEff: '+('0001' if bad=='caps' else '0000')+'\n'
                if path.endswith('memory.max'): return 'max' if bad=='memory.max' else '67108864'
                if path.endswith('memory.swap.max'): return 'max' if bad=='memory.swap.max' else '0'
                if path.endswith('pids.max'): return 'max' if bad=='pids.max' else '16'
                if path.endswith('cgroup.procs'): return '43\n' if bad=='membership' else '42\n'
                if path.endswith('mountinfo'): return '1 0 0:1 / /run/u6-owned/work '+('rw' if bad=='mount_flags' else 'rw,nosuid,nodev')+' - '+('ext4' if bad=='mount_type' else 'tmpfs')+' tmpfs rw\n'
                raise AssertionError(path)
            with patch.object(u6,'read_file',side_effect=read), patch.object(u6.os,'readlink',side_effect=['parent' if bad=='namespace' else 'n','parent' if bad=='mount_namespace' else 'm']), patch.object(Path,'is_symlink',return_value=bad=='cgroup_symlink'), patch.object(u6.os,'statvfs',return_value=SimpleNamespace(f_blocks=1 if bad=='fs_bytes' else 8192,f_frsize=4096,f_files=1 if bad=='inodes' else 256)):
                if bad is None: self.assertEqual(u6.baseline(ready,props,unit,root,'parent','parent'),cg)
                else:
                    with self.assertRaises(u6.Stop): u6.baseline(ready,props,unit,root,'parent','parent')


if __name__=='__main__':
    def audit(event,args):
        if event=='subprocess.Popen' or event.startswith('socket.'):
            raise AssertionError('forbidden real IO: '+event)
    sys.addaudithook(audit)
    unittest.main(verbosity=2)
