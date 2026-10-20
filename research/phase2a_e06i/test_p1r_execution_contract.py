"""Offline profile tests: no runtime materialization or target imports."""
import hashlib
import unittest
from dataclasses import replace
import p1r_execution_contract as c


def profile(files=None):
    data = dict(files or {})
    for kind in ('infrastructure','runtime','source','upstream'):
        data.setdefault('/'+kind+'/sentinel', kind.encode())
    entries = tuple(c.Entry(p,len(raw),hashlib.sha256(raw).hexdigest(),
                     next((k for k in ('infrastructure','runtime','upstream') if p.startswith('/'+k+'/')), 'source'))
                    for p,raw in data.items() if not p.startswith(('/run/ap2-supervisor/input/','/run/ap2-supervisor/output/')))
    return c.Profile('offline-fixture',entries,65534,65534,('/opt/ap2-runtime/stdlib','/opt/ap2-runtime/packages'),('/opt/ap2-runtime/gems',)),data


class Tests(unittest.TestCase):
    def test_registry_has_no_native_authority(self):
        self.assertEqual(dict(c.APPROVED_PROFILES),{})
        for value in ('offline-fixture','',True,None,{},[],'linux-approved'):
            with self.subTest(value=value), self.assertRaises(c.Stop):
                c.select_native(value)
        with self.assertRaises(TypeError):
            c.APPROVED_PROFILES['injected'] = profile()[0]

    def test_complete_declared_byte_stream_including_tail(self):
        p,data = profile()
        c.check_bytes(p, lambda path,cap:data[path])
        for path in data:
            for raw in (data[path]+b'changed-tail',data[path][:-1],b''):
                changed = dict(data); changed[path] = raw
                with self.subTest(path=path,raw=raw), self.assertRaises(c.Stop):
                    c.check_bytes(p,lambda path,cap:changed[path])

    def test_profile_bounds_and_metadata(self):
        p,_ = profile()
        changes = ({'uid':0},{'uid':True},{'gid':False},{'purpose':'ready'},
                   {'name':'../x'},{'inventory':list(p.inventory)},
                   {'python_paths':('/runtime/x',)*2},{'gem_paths':('/bad:paths',)})
        for change in changes:
            with self.subTest(change=change), self.assertRaises(c.Stop):
                c.validate(replace(p,**change))
        entry = p.inventory[0]
        for change in ({'path':'/runtime/../x'},{'size':True},{'size':c.MAX_FILE+1},
                       {'sha256':'0'*63},{'mode':0o777},{'uid':1},{'gid':True},{'kind':'unreviewed'},
                       {'directory':True}):
            with self.subTest(change=change), self.assertRaises(c.Stop):
                c.validate(replace(p,inventory=(replace(entry,**change),)+p.inventory[1:]))
        with self.assertRaises(c.Stop):
            c.validate(replace(p,inventory=p.inventory+(entry,)))

    def test_digest_binds_inventory_paths_modes_ids_imports_purpose(self):
        p,_ = profile()
        for other in (replace(p,uid=65533),replace(p,gid=65533),
                      replace(p,python_paths=('/runtime/other',)),
                      replace(p,gem_paths=('/runtime/other',)),replace(p,purpose='LINUX_APPROVED'),
                      replace(p,inventory=(replace(p.inventory[0],mode=0o555),)+p.inventory[1:])):
            self.assertNotEqual(p.digest(),other.digest())

    def test_environment_has_no_ambient_loader_or_interpreter_knobs(self):
        p,_ = profile()
        env = c.environment(p)
        for forbidden in ('PYTHONPATH','PYTHONHOME','RUBYOPT','LD_PRELOAD','LD_LIBRARY_PATH','GIT_CONFIG_COUNT'):
            self.assertNotIn(forbidden,env)
        self.assertEqual(env['GIT_ALLOW_PROTOCOL'],'')
        self.assertEqual(env['PATH'],'/opt/ap2-runtime/bin')

    def test_fixed_argv_and_outputs(self):
        for role in c.ROLES:
            argv = c.payload_argv(role,1700000000)
            self.assertNotIn('-c',argv)
            self.assertNotIn('sh',argv)
            good = {name:b'{}' for name,_ in c.OUTPUTS[role]}
            self.assertEqual(set(c.check_artifacts(role,good)),set(good))
            for name,cap in c.OUTPUTS[role]:
                exact = dict(good); exact[name] = b'x'*cap
                c.check_artifacts(role,exact)
                for raw in (b'',b'x'*(cap+1),'x'):
                    bad = dict(good); bad[name] = raw
                    with self.subTest(role=role,name=name),self.assertRaises(c.Stop):
                        c.check_artifacts(role,bad)
            with self.assertRaises(c.Stop):
                c.check_artifacts(role,dict(good,foreign=b'x'))
        for role in ('sh','python',None):
            with self.assertRaises(c.Stop):
                c.payload_argv(role,1700000000)

    def test_dynamic_inputs_are_data_not_fixed_runtime_authority(self):
        from test_p1r_linux_port import Ops
        import p1r_linux_supervisor as s
        ops=Ops('oracle');before=ops.profile.digest()
        values={'fixture.json':b'{"new":1}','policy.json':b'{}'}
        manifest=c.manifest_for(ops.profile,'oracle',1700000000,values)
        plan=s.plan_for('oracle','123',manifest)
        self.assertEqual(ops.profile.digest(),before)
        self.assertEqual({pin.path.rsplit('/',1)[1] for pin in plan.pins if pin.path.startswith(s.INPUT+'/')},set(values))
        for bad in ({},dict(values,foreign=b'x'),dict(values,**{'fixture.json':b'x'*262145}),[]):
            with self.subTest(bad=type(bad)),self.assertRaises(c.Stop):c.frozen_inputs('oracle',bad)
        for paths in (('/run/ap2-supervisor/output',),('/tmp',),('/opt/ap2-source',)):
            with self.assertRaises(c.Stop):c.validate(replace(ops.profile,python_paths=paths))

    def test_full_worker_result_roundtrip_handoff_and_binding(self):
        from test_p1r_linux_port import Ops,execute
        for role in c.ROLES:
            ops = Ops(role);value,_ = execute(ops)
            value = dict(value,status='SUPERVISOR_LIFECYCLE_COMPLETE',actual_execution=True)
            wire = c.encode_result(value)
            self.assertEqual(c.decode_result(wire,role,'123',ops.manifest),value)
            for other in ('124','0'):
                with self.subTest(role=role,run=other),self.assertRaises(c.Stop):
                    c.decode_result(wire,role,other,ops.manifest)
            value['actual_execution'] = False
            value['status'] = 'MOCK_SUPERVISOR_LIFECYCLE_COMPLETE'
            with self.assertRaises(c.Stop):c.decode_result(c.encode_result(value),role,'123',ops.manifest)

    def test_worker_packet_mutation_limits_and_no_gate_promotion(self):
        import json
        from test_p1r_linux_port import Ops,execute
        ops=Ops();value,_=execute(ops)
        value=dict(value,status='SUPERVISOR_LIFECYCLE_COMPLETE',actual_execution=True)
        wire=c.encode_result(value)
        for field,wrong in (('phase2_gate','PASS'),('cleanup',1),('actual_execution',1),
                            ('seconds',True),('exit',True),('argv',['/bin/sh']),
                            ('stdout','!'),('artifacts',{})):
            packet=json.loads(wire);packet['result'][field]=wrong
            with self.subTest(field=field),self.assertRaises(c.Stop):
                c.decode_result(c.canonical(packet),'builder','123',ops.manifest)
        packet=json.loads(wire);packet['artifact_sha256']['policy.json']='0'*64
        for raw in (c.canonical(packet),wire+b' ',wire[:-1],b'{"x":0,"x":1}',b'x'*(c.MAX_RESULT+1)):
            with self.assertRaises(c.Stop):c.decode_result(raw,'builder','123',ops.manifest)
        for change in ({'stdout':b'x'*65537},{'stderr':b'x'*4097},{'argv':('x'*c.MAX_RESULT,)},
                       {'artifacts':{'policy.json':b'x'*16385,'fixture.json':b'{}'}}):
            with self.assertRaises(c.Stop):c.encode_result(dict(value,**change))

    def test_shared_absolute_timing_no_reset_or_payload_extension(self):
        self.assertEqual(c.time_bounds(10),(13,16,17,19))
        self.assertEqual((c.WORK_SECONDS,c.TOTAL_SECONDS,c.OWNER_SECONDS),(3,6,6))
        self.assertEqual(c.owner_deadlines('13.0','16.0',12.99),(13,16))
        for start in (True,-1,float('inf'),float('nan'),1e30):
            with self.subTest(start=start),self.assertRaises(c.Stop):c.time_bounds(start)
        for work,life,now in (('13','16.0',12),('13.0','16',12),('nan','nan',12),
            ('inf','inf',12),('13.0','17.0',12),('13.0','16.0',13),
            ('13.0','16.0',9),('13.0','16.0',True),('13.00','16.0',12),
            ('13.0','16.0',float('nan'))):
            with self.subTest(work=work,life=life,now=now),self.assertRaises(c.Stop):
                c.owner_deadlines(work,life,now)
