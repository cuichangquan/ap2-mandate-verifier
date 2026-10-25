from pathlib import Path
import subprocess, json, time, hashlib, os, resource
from stream_results import transfer
ROOT=Path(__file__).parent
DOCKER='/usr/local/bin/docker'
IMAGE='ruby@sha256:42c18f0c9807ba1349c0253617d7f08ef98b815463b2f7785d97c4efdfd80f4d'
NAME='ap2-hcr-stream-d2-20261025'
CONTENT=b'AP2_STREAM_TRANSFER_V1\n'
START=json.loads((ROOT/'AUTHORIZATION.json').read_text())['start_epoch']
DEADLINE=START+1200
def save(name,value):
    with (ROOT/name).open('x') as f: json.dump(value,f,indent=2)
def command(name,args,seconds=15):
    save(name+'.start.json',{'args':args,'epoch':time.time()})
    if time.time()>=DEADLINE-60: raise RuntimeError('deadline reserve')
    def limits(): resource.setrlimit(resource.RLIMIT_FSIZE,(262144,262144))
    with (ROOT/(name+'.stdout')).open('xb') as out,(ROOT/(name+'.stderr')).open('xb') as err:
        q=subprocess.run(args,stdout=out,stderr=err,timeout=min(seconds,DEADLINE-time.time()-60),preexec_fn=limits)
    save(name+'.end.json',{'exit':q.returncode,'epoch':time.time()})
    if q.returncode: raise RuntimeError(name+' exit '+str(q.returncode))
    return (ROOT/(name+'.stdout')).read_bytes()
failure=None;created=False;cleanup=[];files=None
try:
    save('RUN_ONCE.json',{'epoch':time.time(),'transfer_calls_max':1,'rerun':False})
    image=json.loads(command('image-inspect',[DOCKER,'image','inspect',IMAGE]))[0]
    if IMAGE not in image['RepoDigests'] or image['Architecture']!='arm64': raise RuntimeError('image identity')
    # Name is exclusive to this diagnostic. No unrelated objects are enumerated.
    created=True
    command('container-start',[DOCKER,'run','-d','--pull=never','--name',NAME,'--label','ap2.stream.owner='+NAME,
        '--platform','linux/arm64','--network','none','--cpus','1','--memory','256m','--memory-swap','256m',
        '--pids-limit','32','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges:true',
        '--log-driver','json-file','--log-opt','max-size=64k','--log-opt','max-file=1',
        '--tmpfs','/results:size=1048576,uid=1000,gid=1000,mode=0700',
        '--mount','type=bind,src='+str(ROOT)+',dst=/supervision,readonly',
        '--user','1000:1000','--entrypoint','sh',IMAGE,'-c','trap "exit 0" TERM INT; while :; do sleep 1; done'])
    state=json.loads(command('container-inspect',[DOCKER,'inspect',NAME]))[0]
    h=state['HostConfig']
    if state['Config']['Labels'].get('ap2.stream.owner')!=NAME or not h['ReadonlyRootfs'] or h['Memory']!=268435456 or h['MemorySwap']!=268435456 or h['NanoCpus']!=1000000000 or h['NetworkMode']!='none' or h['PortBindings']:
        raise RuntimeError('isolation/resource mismatch')
    observed=command('actual-cgroup',[DOCKER,'exec',NAME,'sh','-c','cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory.swap.max; df -B1 -P / /results'])
    if not observed.startswith(b'100000 100000\n268435456\n0\n'): raise RuntimeError('actual cgroup mismatch')
    rows=observed.decode().splitlines()[4:]
    if len(rows)!=2: raise RuntimeError('capacity observation shape')
    baseline=int(rows[0].split()[2])
    command('dummy-create',[DOCKER,'exec',NAME,'ruby','-rdigest','-e',
        'Dir.mkdir("/results/DUMMY",0700); data="AP2_STREAM_TRANSFER_V1\\n"; File.open("/results/DUMMY/known.txt",File::CREAT|File::EXCL|File::WRONLY,0600){|f|f.write(data)}; puts data.bytesize; puts Digest::SHA256.hexdigest(data)'])
    save('TRANSFER_ONCE.json',{'epoch':time.time(),'calls':1,'rerun':False})
    files=transfer(DOCKER,NAME,'dummy',ROOT/'received',ROOT,min(time.time()+30,DEADLINE-60))
    end=json.loads((ROOT/'received/TRANSFER_END.json').read_text())
    if set(files)!={'DUMMY/known.txt'} or end['missing']!=['DUMMY/not-created.txt'] or not end['complete']:
        raise RuntimeError('independent present/missing inventory mismatch')
    item=files['DUMMY/known.txt']
    if item['bytes']!=len(CONTENT) or item['sha256']!=hashlib.sha256(CONTENT).hexdigest() or (ROOT/'received/files/DUMMY/known.txt').read_bytes()!=CONTENT:
        raise RuntimeError('independent known-content mismatch')
    capacity=command('capacity-after',[DOCKER,'exec',NAME,'df','-B1','-P','/','/results'])
    rows=capacity.decode().splitlines()[1:]
    if len(rows)!=2: raise RuntimeError('capacity observation shape')
    host=sum(p.stat().st_size for p in ROOT.rglob('*') if p.is_file())
    proxy=max(0,int(rows[0].split()[2])-baseline)+int(rows[1].split()[2])+host
    save('CAPACITY.json',{'host_output_bytes':host,'observed_increment_proxy':proxy,
        'scope':'start/end logical filesystem samples plus tmpfs and task outputs; not physical VM peak or hard quota'})
    if host>64*1024**2 or proxy>8*1024**3: raise RuntimeError('capacity observation budget')
except BaseException as e:
    failure={'class':type(e).__name__,'message':str(e)}
finally:
    if created:
        try:
            q=subprocess.run([DOCKER,'inspect',NAME],capture_output=True,timeout=10)
            if q.returncode: raise RuntimeError('container state UNKNOWN or absent; see startup receipt')
            x=json.loads(q.stdout)[0]
            if x['Config']['Labels'].get('ap2.stream.owner')!=NAME: raise RuntimeError('owner mismatch; no cleanup')
            save('CLEANUP_BEFORE.json',{'id':x['Id'],'state':x['State'],'host_config':x['HostConfig'],'evidence_incomplete':failure is not None})
            left=DEADLINE-time.time()
            if left<25: raise RuntimeError('insufficient cleanup deadline; UNKNOWN')
            if x['State']['Running']:
                q=subprocess.run([DOCKER,'stop','--time','5',NAME],capture_output=True,timeout=10)
                save('stop.json',{'exit':q.returncode,'stdout':q.stdout.decode(),'stderr':q.stderr.decode()})
                if q.returncode: raise RuntimeError('stop failed')
            q=subprocess.run([DOCKER,'inspect',NAME],capture_output=True,timeout=5)
            if q.returncode or json.loads(q.stdout)[0]['State']['Running']: raise RuntimeError('termination UNKNOWN')
            q=subprocess.run([DOCKER,'rm',x['Id']],capture_output=True,timeout=10)
            save('remove.json',{'exit':q.returncode,'stdout':q.stdout.decode(),'stderr':q.stderr.decode()})
            if q.returncode: raise RuntimeError('remove failed')
            check=subprocess.run([DOCKER,'ps','-a','--filter','label=ap2.stream.owner='+NAME,'--format','{{.ID}}'],capture_output=True,timeout=5)
            if check.returncode or check.stdout.strip(): raise RuntimeError('cleanup readback failed')
            cleanup.append({'id':x['Id'],'removed':True,'label_readback_empty':True})
        except BaseException as e:
            cleanup.append({'state':'UNKNOWN_OR_RETAINED','reason':str(e)})
            failure=failure or {'class':'CleanupFailure','message':str(e)}
    save('FINAL.json',{'pass':failure is None,'failure':failure,'files':files,'cleanup':cleanup,
        'elapsed_seconds':time.time()-START,'downloads':0,'builds':0,'DB_runs':0,'case_batches':0,
        'transfer_calls':int((ROOT/'TRANSFER_ONCE.json').exists()),'shared_images_cache_retained':True})
    save('SHA256SUMS.json',{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in ROOT.rglob('*') if p.is_file() and p.name!='SHA256SUMS.json'})
print((ROOT/'FINAL.json').read_text())
if failure: raise SystemExit(2)
