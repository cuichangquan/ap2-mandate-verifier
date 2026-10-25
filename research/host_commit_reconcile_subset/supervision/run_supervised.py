from pathlib import Path
import subprocess, os, time, json, hashlib, signal, secrets, resource, base64
from stream_results import transfer

ROOT = Path(__file__).parent
DOCKER = '/usr/local/bin/docker'
OWNER = 'ap2-hcr-20261025-r5'
WORKER = OWNER + '-worker'
DB = OWNER + '-db'
NETWORK = OWNER + '-internal'
RUBY = 'ruby@sha256:42c18f0c9807ba1349c0253617d7f08ef98b815463b2f7785d97c4efdfd80f4d'
POSTGRES = 'postgres@sha256:d735d89e0f050dd5efa611ad633e44e06b526da77b04a7501cece311cd032375'
AUTH = json.loads((ROOT/'AUTHORIZATION.json').read_text())
# New R3 approval includes bounded emergency stop/remove with recorded evidence loss.
if AUTH.get('preservation_failure_policy') != 'owner_approved_stop_remove_record_loss':
    raise RuntimeError('NOT_RUN: bounded evidence-loss contingency needs explicit Owner approval')
DEADLINE = AUTH['start_epoch'] + 1200
CAP = 64*1024*1024
OWNED = []
NETWORK_ID = None
EXPORT_OK = False
DIAGNOSTICS_OK = False
INSTALL_STARTED = False
INSTALL_OUTCOME = 'NOT_STARTED'
BATCH_STARTED = False
ENVIRONMENT_OK = False
DB_STARTED = False
VM_BASE = None
OBSERVATIONS = []
ENV = os.environ.copy()
PASSWORD = secrets.token_hex(24)
ENV.update(POSTGRES_PASSWORD=PASSWORD, HCR_PASSWORD=PASSWORD)

def total_bytes():
    return sum(p.stat().st_size for p in ROOT.rglob('*') if p.is_file())

def save(name, value):
    data = json.dumps(value, indent=2).encode()
    if total_bytes()+len(data) > CAP:
        raise RuntimeError('host output64MiB cap')
    with (ROOT/name).open('xb') as f:
        os.chmod(ROOT/name, 0o600)
        f.write(data)

def info(cmd, seconds=10):
    seconds=cleanup_timeout(seconds)
    q = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       timeout=seconds, env=ENV)
    if q.returncode or len(q.stdout)+len(q.stderr)>65536:
        raise RuntimeError('metadata failure: '+q.stderr.decode(errors='replace')[:4096])
    return q.stdout

def cleanup_timeout(maximum):
    left=DEADLINE-time.time()
    if left<=1: raise RuntimeError('cleanup deadline; retained')
    return min(maximum,left-0.5)

def limited_files():
    resource.setrlimit(resource.RLIMIT_FSIZE,(524288,524288))

def observe():
    global VM_BASE
    now=time.time()
    raw=info([DOCKER,'exec',WORKER,'df','-B1','-P','/','/opt/hcr-gems','/tmp','/results'])
    rows=raw.decode().splitlines()[1:]
    if len(rows)!=4:
        raise RuntimeError('capacity observation shape')
    used=[int(line.split()[2]) for line in rows]
    if VM_BASE is None:
        VM_BASE=used[0]
    host=total_bytes()
    db_used=[]
    if DB_STARTED:
        db_raw=info([DOCKER,'exec',DB,'df','-B1','-P','/var/lib/postgresql/data','/var/run/postgresql','/tmp','/dev/shm'])
        db_rows=db_raw.decode().splitlines()[1:]
        if len(db_rows)!=4: raise RuntimeError('DB capacity observation shape')
        db_used=[int(line.split()[2]) for line in db_rows]
    conservative=max(0,used[0]-VM_BASE)+sum(used[1:])+sum(db_used)+host
    OBSERVATIONS.append({'epoch':now,'vm_filesystem_used':used[0],
                         'db_tmpfs_used':db_used,'worker_tmpfs_used':used[1:],'host_output_bytes':host,
                         'observed_increment_upper_proxy':conservative})
    if host>CAP or conservative>8*1024**3:
        raise RuntimeError('capacity observation budget exceeded')
    if now>=DEADLINE:
        raise RuntimeError('whole20min deadline')

def run(name,cmd,seconds=30,stdin=None,monitor=False):
    if time.time()>=DEADLINE:
        raise RuntimeError('whole20min deadline')
    # Record no credential values; stdin may contain a lab-only password.
    save(name+'.start.json',{'epoch':time.time(),'command':cmd,'stdin_recorded':False})
    with (ROOT/(name+'.stdout')).open('xb') as out, (ROOT/(name+'.stderr')).open('xb') as err:
        os.chmod(out.name,0o600);os.chmod(err.name,0o600)
        p=subprocess.Popen(cmd,stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
                           stdout=out,stderr=err,env=ENV,start_new_session=True,
                           preexec_fn=limited_files)
        try:
            if stdin is not None:
                p.stdin.write(stdin);p.stdin.close()
            limit=min(time.time()+seconds,DEADLINE-180)
            next_observe=0
            while p.poll() is None:
                if time.time()>limit or total_bytes()>CAP-40*1024**2:
                    raise RuntimeError('deadline/output reserve STOP')
                if monitor and time.time()>=next_observe:
                    observe();next_observe=time.time()+2
                time.sleep(0.1)
            rc=p.wait()
        except BaseException as error:
            if p.poll() is None:
                os.killpg(p.pid,signal.SIGKILL);p.wait()
            save(name+'.interrupted.json',{'exit':p.returncode,'reason':str(error),'epoch':time.time()})
            raise
    save(name+'.end.json',{'exit':rc,'epoch':time.time()})
    if rc:
        raise RuntimeError(name+' exit '+str(rc))
    return (ROOT/(name+'.stdout')).read_bytes()

def owned_state(name):
    x=json.loads(info([DOCKER,'inspect',name]))[0]
    if x['Config']['Labels'].get('ap2.hcr.owner')!=OWNER:
        raise RuntimeError('ownership mismatch')
    return x

def export_results():
    global EXPORT_OK
    x=owned_state(WORKER)
    if not x['State']['Running']:
        raise RuntimeError('worker stopped before tmpfs export; evidence incomplete')
    amount=int(info([DOCKER,'exec',WORKER,'du','-sk','/results']).split()[0])*1024
    if total_bytes()+amount+1024**2>CAP:
        raise RuntimeError('cannot preserve all tmpfs output within64MiB')
    # Exactly the function exercised by dummy_once.py; no docker cp or discovery.
    profile='batch' if BATCH_STARTED else 'prebatch'
    files=transfer(DOCKER,WORKER,profile,ROOT/'exported_results',ROOT,
                   min(time.time()+30,DEADLINE-60),cap=CAP)
    save('EXPORTED_HASHES.json',files)
    EXPORT_OK=DIAGNOSTICS_OK and ENVIRONMENT_OK

def collect_diagnostics():
    global DIAGNOSTICS_OK
    # Core Ruby only: no JSON Gem or shell interpolation of discovered paths.
    # Binary payload is bounded, archived, decoded exclusively, then hash-read back.
    target=ROOT/'diagnostics';target.mkdir(mode=0o700)
    raw=ROOT/'diagnostics.protocol'
    with raw.open('xb') as out, (ROOT/'diagnostics.stderr').open('xb') as err:
        def diag_limit(): resource.setrlimit(resource.RLIMIT_FSIZE,(12*1024**2,12*1024**2))
        q=subprocess.run([DOCKER,'exec',WORKER,'ruby','/supervision/collect_diagnostics.rb'],
                         stdout=out,stderr=err,timeout=cleanup_timeout(30),preexec_fn=diag_limit)
    save('diagnostics.end.json',{'exit':q.returncode,'epoch':time.time(),
         'install_started':INSTALL_STARTED,'install_outcome':INSTALL_OUTCOME})
    if raw.stat().st_size>12*1024**2: raise RuntimeError('diagnostic transport cap')
    found={}; terminal=False
    for line in raw.read_bytes().splitlines():
        if line==b'COMPLETE': terminal=True;continue
        kind,h,size,path,payload=line.split(b'\t',4)
        path=path.decode(); rel=Path(path.lstrip('/'))
        if kind!=b'FILE' or '..' in rel.parts or not path.startswith(('/opt/hcr-gems/','/tmp/')):
            raise RuntimeError('diagnostic path/protocol invalid')
        data=base64.b64decode(payload,validate=True)
        if len(data)!=int(size) or hashlib.sha256(data).hexdigest()!=h.decode():
            raise RuntimeError('diagnostic transport mismatch')
        dest=target/rel;dest.parent.mkdir(parents=True,exist_ok=True)
        with dest.open('xb') as f: f.write(data)
        if hashlib.sha256(dest.read_bytes()).hexdigest()!=h.decode():
            raise RuntimeError('diagnostic host readback mismatch')
        found[path]={'bytes':len(data),'sha256':h.decode()}
    must=['/opt/hcr-gems/extensions/aarch64-linux/4.0.0/json-2.19.9/'+n
          for n in ('mkmf.log','gem_make.out')]
    missing=[p for p in must if p not in found]
    # Missing is evidence, never silently accepted as collection completeness.
    reason=('install not started' if not INSTALL_STARTED else
            'UNPROVEN: early failure, timeout, or producer did not create expected file; no cause inferred')
    save('DIAGNOSTIC_MANIFEST.json',{'files':found,'required':must,'missing':missing,
         'absence_reason':reason if missing else None,'producer_outcome':INSTALL_OUTCOME,
         'terminal_record':terminal,'host_readback':True})
    finished=info([DOCKER,'exec',WORKER,'sh','-c',
        'if test -f /results/install.finished; then cat /results/install.finished; else printf UNKNOWN; fi']).decode().strip()
    save('INSTALL_QUIESCENCE.json',{'finished_record':finished,
         'scope':'wrapper records only after bounded install command returns; UNKNOWN forbids normal cleanup'})
    parts=finished.split()
    recovered=len(parts)==2 and parts[0].isdigit() and parts[1]=='recovered'
    DIAGNOSTICS_OK=q.returncode==0 and terminal and (not INSTALL_STARTED or (not missing and recovered))
    if not DIAGNOSTICS_OK: raise RuntimeError('required diagnostic evidence incomplete')

def provider(name,container,expected_missing):
    script='''set -eu
printf 'VERIFY_BEGIN\n'
set +e
dpkg -V libssl3t64 openssl
rc=$?
set -e
printf 'VERIFY_END:%s\n' "$rc"
test "$(dpkg-query -W -f='${Version}' libssl3t64)" = '3.5.7-1~deb13u3'
dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' libssl3t64 openssl
dpkg-query -S /usr/lib/aarch64-linux-gnu/libcrypto.so.3 /usr/lib/aarch64-linux-gnu/libssl.so.3
sha256sum /usr/lib/aarch64-linux-gnu/libcrypto.so.3 /usr/lib/aarch64-linux-gnu/libssl.so.3
'''
    raw=run(name,[DOCKER,'exec',container,'sh','-c',script])
    diff=raw.split(b'VERIFY_BEGIN\n',1)[1].split(b'VERIFY_END:',1)[0]
    rc=raw.split(b'VERIFY_END:',1)[1].splitlines()[0]
    if diff!=expected_missing or rc!=b'0' or b'809909371a1db7d2b9cac4c2fa2eff63eb6169d5979416d94155955a7ad32516' not in raw or b'b3b9a479537bded757b818bb787413d8f8f636135e6546c84e90688eca1dc842' not in raw:
        raise RuntimeError('provider integrity condition failed')

failure=None
batch_pass=False
cleanup=[]
try:
    with (ROOT/'RUN_ONCE.json').open('x') as f:
        json.dump({'epoch':time.time(),'rerun':False},f)
    if total_bytes()>CAP-52*1024**2 or time.time()>DEADLINE-600:
        raise RuntimeError('insufficient evidence/time reserve before any Docker creation')
    pins={'json-2.19.9.gem':'9b9025b7cdddafa38d316eca0b2358488e42d417045c1b90d216a9fefe46b79a',
          'jwt-3.3.0.gem':'44cc34fbc341c148233cf66641522b4bce0dfb1ce55e8073f05c56f44f4ee546',
          'base64-0.3.0.gem':'27337aeabad6ffae05c265c450490628ef3ebd4b67be58257393227588f5a97b',
          'pg-1.7.0-aarch64-linux.gem':'101dd3a261000eb64b03ff41a5890674b735b626dbdce88652969b59fb0b1157'}
    for n,h in pins.items():
        if hashlib.sha256((ROOT/'archives'/n).read_bytes()).hexdigest()!=h:
            raise RuntimeError('archive pin mismatch')
    for ref in [RUBY,POSTGRES]:
        x=json.loads(info([DOCKER,'image','inspect',ref]))[0]
        if ref not in x['RepoDigests'] or x['Architecture']!='arm64' or x['Os']!='linux':
            raise RuntimeError('fixed local image identity')
    save('BASE_IMAGE_AGGREGATE.json',{'disk_summary':info([DOCKER,'system','df','--format','{{.Type}} {{.Size}}']).decode()})
    NETWORK_ID=run('network-create',[DOCKER,'network','create','--internal','--label','ap2.hcr.owner='+OWNER,NETWORK]).decode().strip()
    OWNED.append(WORKER)
    cmd=[DOCKER,'run','-d','--pull=never','--name',WORKER,'--label','ap2.hcr.owner='+OWNER,
         '--platform','linux/arm64','--network',NETWORK,'--cpus','1','--memory','1536m','--memory-swap','1536m',
         '--pids-limit','128','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges:true',
         '--log-driver','json-file','--log-opt','max-size=1m','--log-opt','max-file=2',
         '--tmpfs','/opt/hcr-gems:exec,nosuid,nodev,size=402653184,uid=1000,gid=1000,mode=0700',
         '--tmpfs','/tmp:size=134217728,mode=1777','--tmpfs','/results:size=33554432,uid=1000,gid=1000,mode=0700',
         '--mount','type=bind,src='+str(ROOT/'archives')+',dst=/archives,readonly',
         '--mount','type=bind,src='+str(ROOT/'supervision')+',dst=/supervision,readonly',
         '--mount','type=bind,src='+str(ROOT/'source/research/host_commit_reconcile_subset')+',dst=/research,readonly',
         '--mount','type=bind,src='+str(ROOT/'product')+',dst=/product,readonly',
         '--mount','type=bind,src='+str(ROOT/'PUBLIC_INPUTS.json')+',dst=/inputs/PUBLIC_INPUTS.json,readonly',
         '--user','1000:1000','-e','HOME=/tmp/hcr-home','-e','GEM_HOME=/opt/hcr-gems',
         '-e','GEM_PATH=/opt/hcr-gems:/usr/local/lib/ruby/gems/4.0.0','-e','HCR_PASSWORD',
         '-e','HCR_PG_VERSION=1.7.0','-e','HCR_LIBPQ_VERSION=180006',
         '-e','HCR_SERVER_VERSION=16.15 (Debian 16.15-1.pgdg13+2)',
         '-e','HCR_OPENSSL_LIBRARY=OpenSSL 3.5.7 9 Jun 2026','-e','HCR_SOCKET=hcr-db','-e','HCR_PORT=5432',
         '-e','HCR_SOURCE_ROOT=/product','-e','HCR_INPUTS=/inputs/PUBLIC_INPUTS.json','-e','HCR_OUT=/results/BATCH01',
         '--entrypoint','sh',RUBY,'-c','trap "exit 0" TERM INT; while :; do sleep 1; done']
    run('worker-start',cmd)
    observe()
    x=owned_state(WORKER)
    if not (x['HostConfig']['ReadonlyRootfs'] and x['HostConfig']['NanoCpus']==1000000000 and x['HostConfig']['Memory']==1610612736 and x['HostConfig']['MemorySwap']==1610612736):
        raise RuntimeError('worker resource config')
    raw=run('worker-mount-cgroup',[DOCKER,'exec',WORKER,'sh','-c',
        'cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory.swap.max; df -B1 -P /opt/hcr-gems /tmp /results; mkdir -m700 /tmp/hcr-home'])
    if not raw.startswith(b'100000 100000\n1610612736\n0\n'):
        raise RuntimeError('worker actual cgroup')
    environment=run('environment-before-install',[DOCKER,'exec',WORKER,'sh','-c',
        'set -eu; id; pwd; umask; cat /proc/self/mountinfo; '
        'stat -c "%u %g %a %n" / /opt/hcr-gems /tmp /results /tmp/hcr-home; '
        'for c in cc gcc make ruby; do command -v "$c"; done; '
        'cc --version; ruby -rrbconfig -e '\
        "'puts RbConfig::CONFIG.values_at(\"CC\",\"LDSHARED\",\"CFLAGS\",\"tmpdir\").inspect'"])
    # Captured evidence completeness is separate from environment admissibility.
    # A recorded noexec HOLD is not missing evidence.
    ENVIRONMENT_OK=True
    mounts={}
    for line in environment.decode().splitlines():
        fields=line.split()
        if len(fields)>8 and fields[0].isdigit() and '-' in fields:
            split=fields.index('-')
            mounts[fields[4]]={'options':fields[5].split(','),
                'fstype':fields[split+1],'super_options':fields[split+3].split(',')}
    save('EFFECTIVE_MOUNTS.json',mounts)
    for path in ('/opt/hcr-gems','/tmp','/results'):
        entry=mounts.get(path)
        if not entry or entry['fstype']!='tmpfs' or 'rw' not in entry['options']:
            raise RuntimeError('required writable tmpfs not established: '+path)
    if 'noexec' in mounts['/opt/hcr-gems']['options']:
        raise RuntimeError('HOLD before install: Gem tmpfs is noexec; scoped setting change needs approval')
    if not {'nosuid','nodev'}.issubset(mounts['/opt/hcr-gems']['options']):
        raise RuntimeError('Gem tmpfs nosuid/nodev not established')
    provider('ruby-provider',WORKER,b'')
    INSTALL_STARTED=True
    INSTALL_OUTCOME='STARTED_UNKNOWN'
    run('offline-install',[DOCKER,'exec',WORKER,'ruby','/supervision/offline_install.rb'],seconds=225,monitor=True)
    INSTALL_OUTCOME='SUCCESS'
    collect_diagnostics()
    load_code='''gem 'pg','=1.7.0';gem 'json','=2.19.9';gem 'jwt','=3.3.0';gem 'base64','=0.3.0';gem 'openssl','=4.0.2';gem 'digest','=3.2.1'
require 'pg';require 'json';require 'jwt';require 'base64';require 'openssl';require 'digest'
abort 'Ruby/provider' unless RUBY_VERSION=='4.0.9' && RUBY_PLATFORM=='aarch64-linux' && OpenSSL::OPENSSL_LIBRARY_VERSION=='OpenSSL 3.5.7 9 Jun 2026' && PG.library_version==180006
ext=$LOADED_FEATURES.find{|x|x.end_with?('/4.0/pg_ext.so')};pq=File.read('/proc/self/maps').lines.map{|x|x.split.last}.find{|x|x&.end_with?('/libpq-ruby-pg.so.1')}
abort 'pg native hash' unless ext && pq && Digest::SHA256.file(ext).hexdigest=='686aa34dbbd5f4083f92d5c6ed777d95be3966032fa84fd332a1eee2b30f9f5f' && Digest::SHA256.file(pq).hexdigest=='2e1dc792b709ca06df230b50b1f14800b5887b5983ac75a046a0317cf8cc3afd'
puts JSON.generate({ruby:RUBY_VERSION,platform:RUBY_PLATFORM,openssl:OpenSSL::OPENSSL_LIBRARY_VERSION,libpq:PG.library_version,extension:ext,libpq_path:pq,gem_versions:Gem.loaded_specs.transform_values{|s|s.version.to_s}})
'''
    run('actual-load',[DOCKER,'exec',WORKER,'ruby','-e',load_code])
    OWNED.append(DB)
    run('db-start',[DOCKER,'run','-d','--pull=never','--name',DB,'--label','ap2.hcr.owner='+OWNER,
        '--platform','linux/arm64','--network',NETWORK,'--network-alias','hcr-db','--hostname','hcr-db',
        '--cpus','1','--memory','512m','--memory-swap','512m','--pids-limit','128','--read-only','--shm-size','32m',
        '--security-opt','no-new-privileges:true','--log-driver','json-file','--log-opt','max-size=1m','--log-opt','max-file=2',
        '--tmpfs','/var/lib/postgresql/data:size=268435456,uid=999,gid=999,mode=0700',
        '--tmpfs','/var/run/postgresql:size=8388608,uid=999,gid=999,mode=2775','--tmpfs','/tmp:size=33554432,mode=1777',
        '-e','POSTGRES_PASSWORD','-e','POSTGRES_INITDB_ARGS=--auth-host=scram-sha-256',POSTGRES])
    DB_STARTED=True
    provider('postgres-provider',DB,(ROOT/'EXPECTED_POSTGRES_DPKG_VERIFY.txt').read_bytes())
    ready=False;ready_rows=[]
    for i in range(60):
        if time.time()>=DEADLINE-65: raise RuntimeError('readiness deadline reserve')
        q=subprocess.run([DOCKER,'exec',DB,'pg_isready','-U','postgres'],capture_output=True,timeout=5)
        ready_rows.append({'exit':q.returncode,'stdout':q.stdout.decode(),'stderr':q.stderr.decode()})
        if q.returncode==0:
            ready=True;break
        time.sleep(0.5)
    save('DB_READINESS.json',ready_rows)
    if not ready:
        raise RuntimeError('DB readiness timeout')
    script="CREATE ROLE ap2_reconcile_lab LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '"+PASSWORD+"';\nCREATE DATABASE ap2_reconcile_research OWNER ap2_reconcile_lab;\n"
    run('db-bootstrap',[DOCKER,'exec','-i',DB,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],stdin=script.encode())
    x=owned_state(DB)
    if x['HostConfig']['PortBindings'] or x['HostConfig']['Memory']!=536870912 or x['HostConfig']['MemorySwap']!=536870912 or x['HostConfig']['NanoCpus']!=1000000000 or not x['HostConfig']['ReadonlyRootfs']:
        raise RuntimeError('DB resources/isolation')
    run('db-cgroup',[DOCKER,'exec',DB,'sh','-c','cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory.swap.max'])
    if (ROOT/'db-cgroup.stdout').read_bytes()!=b'100000 100000\n536870912\n0\n':
        raise RuntimeError('DB actual cgroup')
    observe()
    save('BATCH_ONCE.json',{'epoch':time.time(),'cases':4,'workers_max':5,'retry_case':'one generation2 attempt is part of the planned case, not a batch rerun'})
    BATCH_STARTED=True
    run('batch',[DOCKER,'exec',WORKER,'sh','-c',
        'echo $$ > /results/launch.pid; exec ruby /research/compare.rb --execute-approved'],seconds=310,monitor=True)
    observe()
    export_results()
    report=json.loads((ROOT/'exported_results/files/BATCH01/REPORT.json').read_text())
    if report['completed']!=4 or report['workers']!=5 or not report['group_recovered']:
        raise RuntimeError('batch report mismatch')
    batch_pass=True
except BaseException as e:
    failure={'class':type(e).__name__,'message':str(e)}
    if INSTALL_STARTED and INSTALL_OUTCOME=='STARTED_UNKNOWN':
        if (ROOT/'offline-install.end.json').exists():
            INSTALL_OUTCOME='FAILURE_EXIT_'+str(json.loads((ROOT/'offline-install.end.json').read_text())['exit'])
        elif (ROOT/'offline-install.interrupted.json').exists():
            INSTALL_OUTCOME='INTERRUPTED_OR_TIMEOUT'
finally:
    # PID1 holds tmpfs alive after exec returns, including Ruby failures.
    if WORKER in OWNED:
        try:
            x=owned_state(WORKER)
            if INSTALL_STARTED and x['State']['Running']:
                try:
                    settled=info([DOCKER,'exec',WORKER,'ruby','/supervision/offline_install.rb','--settle-owned'],seconds=15)
                    save('INSTALL_SETTLED.json',{'output':settled.decode(),'epoch':time.time()})
                except BaseException as e:
                    save('INSTALL_SETTLED_UNKNOWN.json',{'reason':str(e),'epoch':time.time()})
                    # Preserve a bounded partial snapshot as such, never claim quiescence.
            if x['State']['Running'] and not (ROOT/'diagnostics').exists():
                collect_diagnostics()
        except BaseException as e:
            cleanup.append({'diagnostic_preservation':'INCOMPLETE','reason':str(e)})
        try:
            x=owned_state(WORKER)
            if x['State']['Running'] and not (ROOT/'exported_results').exists():
                # Terminate only our recorded launcher, allowing its ensure to reap children.
                subprocess.run([DOCKER,'exec',WORKER,'sh','-c',
                    'if test -f /results/launch.pid; then read p < /results/launch.pid; kill -TERM "$p" 2>/dev/null || :; fi'],capture_output=True,timeout=cleanup_timeout(10))
                time.sleep(1)
                export_results()
        except BaseException as e:
            cleanup.append({'evidence_export':'INCOMPLETE','reason':str(e)})
    for name in reversed(OWNED):
        try:
            x=owned_state(name)
            save(name+'-state.json',{'Id':x['Id'],'State':x['State'],'HostConfig':x['HostConfig']})
            q=subprocess.run([DOCKER,'logs',name],capture_output=True,timeout=cleanup_timeout(15))
            if total_bytes()+len(q.stdout)+len(q.stderr)>CAP:
                raise RuntimeError('log export cap')
            (ROOT/(name+'.stdout.log')).write_bytes(q.stdout)
            (ROOT/(name+'.stderr.log')).write_bytes(q.stderr)
            if not EXPORT_OK:
                # Not normal cleanup. Only the explicit R3 contingency permits
                # this bounded emergency shutdown; it acknowledges tmpfs evidence loss.
                save(name+'-PRESERVATION_FAILURE.json',{'state':'STOP_OWNER_CONSULTATION_REQUIRED',
                    'container':name,'id':x['Id'],'deadline':DEADLINE,
                    'missing_evidence_may_be_lost_on_stop':True,
                    'policy':AUTH['preservation_failure_policy'],
                    'normal_cleanup_forbidden':True,'remove_forbidden':False})
                if x['State']['Running']:
                    q=subprocess.run([DOCKER,'stop','--time','5',name],capture_output=True,
                                     timeout=cleanup_timeout(10))
                    save(name+'-EMERGENCY_STOP.json',{'exit':q.returncode,'stdout':q.stdout.decode(errors='replace'),
                         'stderr':q.stderr.decode(errors='replace'),'epoch':time.time()})
                    if q.returncode: raise RuntimeError('emergency shutdown UNKNOWN')
                x=owned_state(name)
                if x['State']['Running']: raise RuntimeError('emergency shutdown UNKNOWN')
                q=subprocess.run([DOCKER,'rm',x['Id']],capture_output=True,timeout=cleanup_timeout(15))
                if q.returncode: raise RuntimeError('emergency removal failed')
                cleanup.append({'container':name,'state':'REMOVED_EVIDENCE_INCOMPLETE',
                                'id':x['Id'],'tmpfs_loss_recorded':True})
                continue
            if x['State']['Running']:
                q=subprocess.run([DOCKER,'stop','--time','10',name],capture_output=True,timeout=cleanup_timeout(20))
                if q.returncode:raise RuntimeError('owned stop failed')
            x=owned_state(name)
            if x['State']['Running']:raise RuntimeError('termination UNKNOWN')
            q=subprocess.run([DOCKER,'rm',x['Id']],capture_output=True,timeout=cleanup_timeout(15))
            if q.returncode:raise RuntimeError('owned removal failed')
            cleanup.append({'container':name,'id':x['Id'],'removed':True})
        except BaseException as e:
            cleanup.append({'container':name,'state':'UNKNOWN_OR_RETAINED','reason':str(e)})
    if NETWORK_ID:
        try:
            x=json.loads(info([DOCKER,'network','inspect',NETWORK_ID]))[0]
            if x['Labels'].get('ap2.hcr.owner')!=OWNER or x['Containers']:
                raise RuntimeError('network ownership/in-use')
            q=subprocess.run([DOCKER,'network','rm',NETWORK_ID],capture_output=True,timeout=cleanup_timeout(15))
            if q.returncode:raise RuntimeError('network removal')
            cleanup.append({'network':NETWORK_ID,'removed':True})
        except BaseException as e:
            cleanup.append({'network':NETWORK_ID,'state':'RETAINED','reason':str(e)})
    if any(x.get('state') in ('UNKNOWN_OR_RETAINED','RETAINED','REMOVED_EVIDENCE_INCOMPLETE') or x.get('evidence_export')=='INCOMPLETE' or x.get('diagnostic_preservation')=='INCOMPLETE' for x in cleanup):
        failure=failure or {'class':'CleanupIncomplete','message':'STOP: see cleanup evidence'}
    save('CAPACITY_OBSERVATIONS.json',{'baseline_vm_used':VM_BASE,'observations':OBSERVATIONS,
        'scope':'logical VM filesystem delta plus worker and DB tmpfs and host outputs; shared activity can affect it; not physical VM allocation or hard8GiB quota'})
    save('FINAL.json',{'batch_pass':batch_pass,'failure':failure,'cleanup':cleanup,
        'elapsed_seconds':time.time()-AUTH['start_epoch'],'rerun':False,'image_builds':0,'new_download_bytes':0,
        'shared_images_cache_retained':True,'host_output_bytes_before_final':total_bytes()})
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
            for p in ROOT.rglob('*') if p.is_file() and p.name!='SHA256SUMS.json'}
    save('SHA256SUMS.json',hashes)
print((ROOT/'FINAL.json').read_text())
if failure:
    raise SystemExit(2)
