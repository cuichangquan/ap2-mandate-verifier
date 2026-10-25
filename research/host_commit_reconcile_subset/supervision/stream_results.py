"""Single bounded receiver shared by the dummy and future real result export."""
from pathlib import Path
import os, subprocess, time, selectors, hashlib, json, signal, resource

COMMON = 'launch.pid install.supervisor install.json.group install.json.exit install.other.group install.other.exit install.finished'.split()
BATCH = ['BATCH01/'+n for n in 'BATCH.json WORKER_REPORT.json SUPERVISION.json REPORT.json controller.stdout controller.stderr worker.rb STOP.json CONTROLLER_STOP.json'.split()]
PRODUCT = ['BATCH01/source/lib/ap2_mandate_verifier/'+n+'.rb' for n in 'host_binding input_validator purchase_binding research_result result root_disclosures root_signature scoped_constraints trust_context'.split()] + ['BATCH01/source/lib/ap2_mandate_verifier.rb']
WORKERS = ['BATCH01/'+n+'.stderr' for n in 'COMMIT_NOTICE_LOST-commit_hide ABORT_THEN_RETRY-abort_before_commit ABORT_THEN_RETRY-retry INFLIGHT_EMPTY-hold_abort BINDING_CONFLICT-commit_hide'.split()]
INVENTORY = {'dummy':['DUMMY/known.txt','DUMMY/not-created.txt'], 'prebatch':COMMON, 'batch':COMMON+BATCH+PRODUCT+WORKERS}
REQUIRED = {'dummy':{'DUMMY/known.txt'}, 'prebatch':set(), 'batch':set(COMMON+BATCH+PRODUCT+WORKERS)-{'BATCH01/STOP.json','BATCH01/CONTROLLER_STOP.json'}}

def transfer(docker, container, profile, destination, budget_root, deadline, cap=64*1024**2):
    """No retry. Persist partial files, remote headers, stderr, exit and hashes."""
    destination=Path(destination); budget_root=Path(budget_root)
    destination.mkdir(mode=0o700)
    allowed=set(INVENTORY[profile]); seen=set(); files={}; missing=[]
    def disk(): return sum(p.stat().st_size for p in budget_root.rglob('*') if p.is_file())
    def note(name,value):
        data=json.dumps(value,indent=2).encode()
        if disk()+len(data)>cap: raise RuntimeError('host evidence budget')
        with (destination/name).open('xb') as f: f.write(data)
    note('TRANSFER_START.json',{'profile':profile,'allowed':sorted(allowed),'required':sorted(REQUIRED[profile]),'deadline':deadline,'rerun':False})
    manifest=(destination/'REMOTE_MANIFEST.jsonl').open('xb')
    err=(destination/'STREAM.stderr').open('xb')
    def limits(): resource.setrlimit(resource.RLIMIT_FSIZE,(256*1024,256*1024))
    p=None; selector=selectors.DefaultSelector(); buffer=bytearray(); active=None
    state='header'; remaining=0; total=0; terminal=False; failure=None; rc=None
    try:
        p=subprocess.Popen([docker,'exec',container,'ruby','/supervision/stream_results.rb',profile],
            stdout=subprocess.PIPE,stderr=err,start_new_session=True,preexec_fn=limits)
        selector.register(p.stdout,selectors.EVENT_READ)
        while True:
            if time.time()>=deadline: raise RuntimeError('stream timeout')
            if disk()>cap-1024**2: raise RuntimeError('host evidence reserve')
            events=selector.select(min(0.25,max(0.001,deadline-time.time())))
            if not events: continue
            chunk=os.read(p.stdout.fileno(),65536)
            if not chunk: break
            if terminal: raise RuntimeError('bytes after terminal record')
            buffer.extend(chunk)
            while True:
                if state=='data':
                    n=min(remaining,len(buffer))
                    if n:
                        part=bytes(buffer[:n]); del buffer[:n]
                        if disk()+n>cap-1024**2: raise RuntimeError('host payload cap')
                        active['file'].write(part); active['hash'].update(part); remaining-=n
                    if remaining: break
                    state='separator'
                if state=='separator':
                    if not buffer: break
                    if buffer.pop(0)!=10: raise RuntimeError('payload framing')
                    active['file'].close()
                    h=active['hash'].hexdigest()
                    readback=hashlib.sha256(active['path'].read_bytes()).hexdigest()
                    if h!=active['expected'] or readback!=h: raise RuntimeError('result SHA/readback mismatch')
                    files[active['name']]={'bytes':active['size'],'sha256':h,'host_readback':True}
                    manifest.write((json.dumps({'host_verified':active['name'],**files[active['name']]})+'\n').encode());manifest.flush()
                    active=None;state='header'
                if b'\n' not in buffer:
                    if len(buffer)>2048: raise RuntimeError('header cap')
                    break
                raw,_,rest=buffer.partition(b'\n');buffer=bytearray(rest)
                fields=raw.decode('ascii').split('\t')
                manifest.write((json.dumps({'remote_header':fields})+'\n').encode());manifest.flush()
                if fields[0]=='COMPLETE':
                    if len(fields)!=4 or [int(v) for v in fields[1:]]!=[len(allowed),len(files),total] or seen!=allowed:
                        raise RuntimeError('terminal inventory/count mismatch')
                    terminal=True
                    if buffer: raise RuntimeError('trailing stream bytes')
                    break
                if len(fields) not in (2,4) or fields[0] not in ('FILE','MISSING'): raise RuntimeError('unknown record')
                name=fields[1]
                if name not in allowed or name in seen: raise RuntimeError('unlisted or duplicate path')
                seen.add(name)
                if fields[0]=='MISSING':
                    if len(fields)!=2: raise RuntimeError('missing shape')
                    missing.append(name);continue
                if len(fields)!=4: raise RuntimeError('file header shape')
                size=int(fields[2]); h=fields[3]
                if size<0 or size>2*1024**2 or total+size>32*1024**2 or len(h)!=64 or any(c not in '0123456789abcdef' for c in h):
                    raise RuntimeError('file bounds/hash header')
                path=destination/'files'/name;path.parent.mkdir(parents=True,exist_ok=True)
                active={'file':path.open('xb'),'path':path,'name':name,'size':size,'expected':h,'hash':hashlib.sha256()}
                total+=size;remaining=size;state='data'
        rc=p.wait(timeout=max(0.1,min(5,deadline-time.time())))
        if rc or not terminal or state!='header' or active: raise RuntimeError('partial stream/nonzero exporter')
        absent=REQUIRED[profile]-set(files)
        if absent: raise RuntimeError('required result files missing: '+','.join(sorted(absent)))
    except BaseException as e:
        failure={'class':type(e).__name__,'message':str(e)}
    finally:
        if active and not active['file'].closed: active['file'].close()
        if p and p.poll() is None:
            try: os.killpg(p.pid,signal.SIGKILL)
            except ProcessLookupError: pass
            try: p.wait(timeout=2)
            except subprocess.TimeoutExpired: failure=failure or {'class':'Unknown','message':'host exporter CLI recovery UNKNOWN'}
        if p: rc=p.returncode
        selector.close();manifest.close();err.close()
        note('TRANSFER_END.json',{'complete':failure is None,'failure':failure,'exit':rc,'terminal':terminal,
            'files':files,'missing':missing,'seen':sorted(seen),'bytes_announced':total,
            'partial_file':active['name'] if active else None,'rerun':False})
    if failure: raise RuntimeError(failure['message'])
    return files
