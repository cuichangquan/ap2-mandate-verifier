# frozen_string_literal: true
# NOT_RUN: explicit future approval required. Controller expectations are fixed.
gem 'json', '= 2.19.9'
require 'json'
require 'digest'
require 'rbconfig'
require 'fileutils'
require 'timeout'
INPUT_SHA = 'cc26cf7115c59c5e44c34a5a051f7dd17577958c32df7113ecbe022bb390a4f5'
BASE = '27445dafbca5ad9646249b008ce83a99348f9092'
EXPECTED = {
 'COMMIT_NOTICE_LOST'=>['COMMITTED_EXISTING','DONE','CONSUMED','RESERVED',1,1],
 'ABORT_THEN_RETRY'=>['RETRY_AUTHORIZED_THEN_COMMITTED','DONE','CONSUMED','RESERVED',1,2],
 'INFLIGHT_EMPTY'=>['PENDING','REGISTERED','ISSUED','OPEN',0,1],
 'BINDING_CONFLICT'=>['CONFLICT','DONE','CONSUMED','RESERVED',1,1]
}.freeze
ACTIVE = []
LOOKUPS = []
PINS = {
 'lib/ap2_mandate_verifier.rb'=>'4824eeef1ce6c7833bcc24bc0bf9abc265df0b35ba135e54b4341b54c2f65ef2',
 'host_binding'=>'917a4c139accd77d5bbe9125c64ea258349b6854ac04e0fefe33536b9b88ec0a',
 'input_validator'=>'395f8e6f2012ab400d7b17f1fdcf4ee63a3c1c9622da4f2b32d35b522542bf00',
 'purchase_binding'=>'6f2108ac3298e4558fc053139d045d399687ccc3bf39c01945ed52d529dc26df',
 'research_result'=>'02159d2f451461ef818d7b6c9d55349cdfb6e23d9ced7d688730d22c8e96827d',
 'result'=>'fade8a1e922f7b4cf2439c120580160f85e0f22f6cfac9ff1ab1364d7b34d310',
 'root_disclosures'=>'55e97aa3b606eee64afbf929941fabb24286755297e1ed5bf48a5066e1352df6',
 'root_signature'=>'d9b68d989700a0c103f80004e14fb2d3aa992f823434e07bf2971f63052519dd',
 'scoped_constraints'=>'b2b5fa4cd1b4ce83cfc5ffc1be0a09ce57ad4a1b9be6778e581dd38f5ce5fd84',
 'trust_context'=>'430eb9f9f3be4c0d7e799e95b68009c08582b6961aa954cc866ff012a3b2be36'
}.freeze
def need(ok, why)
  raise why unless ok
end
def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
def remaining
  deadlines=ACTIVE.reject { |w| w[:reaped] }.map { |w| w[:deadline] }
  time=deadlines.empty? ? 10 : deadlines.min-clock
  need(time>0,'earliest worker deadline')
  time
end
def read_regular(path, cap)
  before = File.lstat(path)
  need(before.file? && before.size.between?(1,cap), 'regular source size')
  fields = ->(s) { [s.dev,s.ino,s.mode,s.size,s.mtime.to_r,s.ctime.to_r] }
  File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |f|
    need(fields.call(before) == fields.call(f.stat), 'source replaced')
    raw = f.read(cap+1)
    need(raw.bytesize == before.size && fields.call(before) == fields.call(f.stat) &&
      fields.call(before) == fields.call(File.lstat(path)), 'source changed')
    raw
  end
end
def save(path, object)
  File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(JSON.pretty_generate(object)) }
end
def database
  need(ENV.keys.none? { |key| key.start_with?('PG') } &&
    ENV.fetch('RUBYOPT','').empty? && ENV.fetch('RUBYLIB','').empty?, 'ambient DB/Ruby configuration refused')
  socket = ENV.fetch('HCR_SOCKET')
  need(socket == 'hcr-db', 'dedicated internal DB service')
  port=ENV.fetch('HCR_PORT')
  need(/\A[0-9]{4,5}\z/.match?(port) && Integer(port).between?(1024,65535),'dedicated port')
  db = PG.connect(host:socket,port:port, dbname:'ap2_reconcile_research', user:'ap2_reconcile_lab', password:ENV.fetch('HCR_PASSWORD'), connect_timeout:2)
  row = db.exec("SELECT current_database() AS db,current_user AS role,session_user AS session,usesuper FROM pg_user WHERE usename=current_user").first
  need(row == {'db'=>'ap2_reconcile_research','role'=>'ap2_reconcile_lab','session'=>'ap2_reconcile_lab','usesuper'=>'f'}, 'dedicated non-superuser identity')
  need(db.exec('SHOW server_version').first.values.first == ENV.fetch('HCR_SERVER_VERSION') &&
    ENV.fetch('HCR_SERVER_VERSION').start_with?('16.') && PG.library_version.to_s == ENV.fetch('HCR_LIBPQ_VERSION'), 'exact provider identity')
  need(db.exec("SELECT pg_get_userbyid(datdba) AS owner FROM pg_database WHERE datname=current_database()").first['owner']=='ap2_reconcile_lab', 'dedicated database owner')
  need(db.host=='hcr-db' && db.port==5432,'dedicated internal endpoint')
  need(db.exec('SELECT pg_is_in_recovery() AS standby').first['standby']=='f','authoritative primary required')
  db.exec("SET default_transaction_isolation='read committed'")
  db.exec("SET statement_timeout='2s'; SET lock_timeout='2s'")
  db
end

def start_worker(out,root,args,id,action)
  need(ACTIVE.size<5,'five planned workers maximum')
  started=clock
  ir,iw=IO.pipe;orr,ow=IO.pipe
  path=File.join(out,"#{id}-#{action}.stderr")
  err=File.open(path,File::CREAT|File::EXCL|File::WRONLY,0o600)
  pid=Timeout.timeout(remaining) { Process.spawn({'HCR_COORDINATOR_PID'=>Process.pid.to_s},RbConfig.ruby,File.join(out,'worker.rb'),'--owned-worker',in:ir,out:ow,err:err,close_others:true) }
  w={pid:pid,input:iw,output:orr,deadline:started+10,stderr:path,events:[],reaped:false}
  ACTIVE<<w;ir.close;ow.close;err.close
  raw=JSON.generate({case_id:id,action:action,hold:action=='hold_abort',source_root:root,args:args})+"\n"
  need(raw.bytesize<=262144,'request bound')
  Timeout.timeout(remaining) { iw.write(raw);iw.flush }
  w
end
def event(w)
  need(IO.select([w[:output]],nil,nil,remaining),'worker deadline')
  line=Timeout.timeout(remaining) { w[:output].gets(65537) }
  need(line && line.bytesize<=65536 && line.end_with?("\n"),'event frame')
  x=JSON.parse(line,allow_duplicate_key:false)
  need(%w[READY LOCKED CHANNEL_CLOSED].include?(x['event']),'unknown event')
  w[:events]<<x;need(w[:events].size<=8,'event count');x
end
def ready(w)
  x=event(w);need(x['event']=='READY' && x['evidence']==true,'actual Evidence prerequisite');w[:session]=x.slice('backend','backend_start','application_name');x
end
def finish(w)
  need(event(w)['event']=='CHANNEL_CLOSED','unexpected result delivery')
  status=Timeout.timeout(remaining) { Process.waitpid2(w[:pid]).last };w[:reaped]=true
  need(status.success? && File.size(w[:stderr]).zero?,'worker failure/stderr')
  need(IO.select([w[:output]],nil,nil,remaining) && w[:output].read(1).nil?,'unexpected trailing result')
end
def session_absent(db,s)
  row=db.exec_params("SELECT count(*) AS n FROM pg_stat_activity WHERE pid=$1::int AND backend_start=$2::timestamptz AND application_name=$3 AND datname='ap2_reconcile_research' AND usename='ap2_reconcile_lab'",[s.fetch('backend'),s.fetch('backend_start'),s.fetch('application_name')]).first
  row.fetch('n')=='0'
end
def wait_closed(db,w)
  limit=clock+1
  until session_absent(db,w.fetch(:session))
    need(clock<limit,'original session termination unknown');sleep 0.01
  end
end
def reconcile(id,identity,digest,session,allow_retry:false)
  db=database # fresh READ COMMITTED primary; never a replica/cache lookup
  begin
    db.exec('BEGIN')
    begin
      row=db.exec_params('SELECT * FROM hcr.requests WHERE operation_id=$1 FOR UPDATE NOWAIT',['synthetic-'+id]).first
    rescue PG::LockNotAvailable
      LOOKUPS << {case_id:id,decision:'PENDING',reason:'registry lock unavailable or retry not authorized'}
      db.exec('ROLLBACK');return 'PENDING'
    end
    need(row,'unregistered operation HOLD')
    # Synthetic caller auth context is supplied by the trusted harness. No ID-only lookup.
    unless row['tenant_id']==identity.fetch('tenant_id') && row['principal_id']==identity.fetch('principal_id') &&
      row['request_digest']==digest && JSON.parse(row['descriptor'])==identity
      LOOKUPS << {case_id:id,decision:'CONFLICT',reason:'tenant/principal/digest/full descriptor mismatch'}
      db.exec('ROLLBACK');return 'CONFLICT'
    end
    op=db.exec_params('SELECT * FROM hcr.operations WHERE operation_id=$1',['synthetic-'+id]).first
    if row['state']=='DONE'
      need(op && op['request_digest']==digest,'inconsistent committed operation HOLD')
      state=db.exec_params('SELECT c.state AS nonce,o.state AS order_state FROM hcr.orders o JOIN hcr.challenges c USING(case_id) WHERE o.case_id=$1',[id]).first
      need(state=={'nonce'=>'CONSUMED','order_state'=>'RESERVED'},'inconsistent final state HOLD')
      LOOKUPS << {case_id:id,decision:'COMMITTED_EXISTING',operation_digest_match:true,nonce:'CONSUMED',order_state:'RESERVED'}
      db.exec('ROLLBACK');return 'COMMITTED_EXISTING'
    end
    need(row['state']=='REGISTERED' && op.nil?,'inconsistent registry HOLD')
    unless allow_retry
      LOOKUPS << {case_id:id,decision:'PENDING',reason:'registry lock unavailable or retry not authorized'}
      db.exec('ROLLBACK');return 'PENDING'
    end
    need(session && session_absent(db,session),'original attempt may still commit')
    need(row['generation']=='1','retry allowance exhausted')
    state=db.exec_params('SELECT c.state AS nonce,o.state AS order_state,o.version,o.binding FROM hcr.orders o JOIN hcr.challenges c USING(case_id) WHERE o.case_id=$1 FOR UPDATE OF o,c',[id]).first
    need(state && state['nonce']=='ISSUED' && state['order_state']=='OPEN' && state['version']==identity.fetch('binding').fetch('order_version') && JSON.parse(state['binding'])==identity['binding'],'retry Host state changed')
    changed=db.exec_params("UPDATE hcr.requests SET generation=2 WHERE operation_id=$1 AND generation=1 AND state='REGISTERED' RETURNING operation_id",['synthetic-'+id])
    need(changed.ntuples==1,'retry grant CAS')
    db.exec('COMMIT') # only a retry grant; no nonce/order consumption
    LOOKUPS << {case_id:id,decision:'RETRY_AUTHORIZED',original_session_absent:true,operation_absent:true,nonce:state['nonce'],order_state:state['order_state'],binding_matched:true,generation_before:1,generation_after:2}
    'RETRY_AUTHORIZED'
  ensure
    db.exec('ROLLBACK') if !db.finished? && db.transaction_status!=PG::PQTRANS_IDLE
    db.close unless db.finished?
  end
end
def batch(out)
  gem 'pg', "= #{ENV.fetch('HCR_PG_VERSION')}"
  require 'pg'
  need(RUBY_VERSION=='4.0.9' && RUBY_PLATFORM.start_with?('aarch64-linux'), 'Linux arm64 runtime')
  root=File.join(out,'source')
  FileUtils.mkdir_p(File.join(root,'lib/ap2_mandate_verifier'),mode:0o700)
  PINS.each do |key,pin|
    name=key.end_with?('.rb') ? key : "lib/ap2_mandate_verifier/#{key}.rb"
    raw=read_regular(File.join(ENV.fetch('HCR_SOURCE_ROOT'),name),65536)
    need(Digest::SHA256.hexdigest(raw)==pin,'product pin')
    File.write(File.join(root,name),raw,mode:'wx',perm:0o400)
  end
  worker=read_regular(File.join(__dir__,'worker.rb'),65536)
  File.write(File.join(out,'worker.rb'),worker,mode:'wx',perm:0o400)
  input=read_regular(ENV.fetch('HCR_INPUTS'),262144)
  need(Digest::SHA256.hexdigest(input)==INPUT_SHA,'saved input pin')
  args=JSON.parse(input,allow_duplicate_key:false).fetch('FULL')
  host=JSON.parse(args.fetch('host_json'),allow_duplicate_key:false)
  trust=JSON.parse(args.fetch('trust_json'),allow_duplicate_key:false)
  snapshot=JSON.parse(trust.fetch('snapshot').fetch('body'),allow_duplicate_key:false)
  profile=trust.fetch('profile')
  facts={'active'=>snapshot.fetch('active'),'not_before'=>snapshot.fetch('not_before'),'not_after'=>snapshot.fetch('not_after'),
    'profile'=>{'profile_ref'=>profile.fetch('profile_ref'),'profile_version'=>profile.fetch('version'),'profile_definition_hash'=>profile.fetch('definition_hash')},
    'snapshot'=>trust.fetch('snapshot').slice('id','policy_version','content_hash'),
    'keys'=>snapshot.fetch('records').map { |r| r.reject { |k,_| k=='public_key_pem' } }}
  challenge=host.fetch('challenge').reject { |k,_| k=='nonce' }.merge('verified_nonce_sha256'=>Digest::SHA256.hexdigest(host.fetch('challenge').fetch('nonce')))

  identity={'tenant_id'=>host.fetch('binding').fetch('tenant_id'),'principal_id'=>host.fetch('binding').fetch('buyer_account_id'),
    'binding'=>host.fetch('binding'),'challenge'=>host.fetch('challenge').reject { |k,_| k=='nonce' },
    'nonce_sha256'=>Digest::SHA256.hexdigest(host.fetch('challenge').fetch('nonce'))}
  digest=Digest::SHA256.hexdigest(JSON.generate(identity))
  db=database;rows=[]
  begin
    need(db.exec("SELECT to_regnamespace('hcr') AS existing").first['existing'].nil?,'existing schema STOP')
    sql=read_regular(File.join(__dir__,'schema.sql'),65536);db.exec(sql)
    EXPECTED.each do |id,expected|
      db.exec('BEGIN')
      db.exec_params('INSERT INTO hcr.policy VALUES($1,1,1,true,$2,$3::jsonb)',[id,args.fetch('verified_at'),JSON.generate(facts)])
      db.exec_params("INSERT INTO hcr.orders VALUES($1,$2::jsonb,'order-v1','OPEN')",[id,JSON.generate(host.fetch('binding'))])
      db.exec_params("INSERT INTO hcr.challenges VALUES($1,$2::jsonb,'ISSUED')",[id,JSON.generate(challenge)])
      db.exec_params("INSERT INTO hcr.requests VALUES($1,$2,$3,$4,$5::jsonb,$6,1,'REGISTERED')",['synthetic-'+id,id,identity['tenant_id'],identity['principal_id'],JSON.generate(identity),digest])
      db.exec('COMMIT') # stable identity/generation1 exists before the first attempt
      action=id=='ABORT_THEN_RETRY' ? 'abort_before_commit' : id=='INFLIGHT_EMPTY' ? 'hold_abort' : 'commit_hide'
      worker_offset=ACTIVE.size
      w=start_worker(out,root,args,id,action);ready(w)
      if id=='INFLIGHT_EMPTY'
        need(event(w)['event']=='LOCKED','inflight barrier')
        empty=db.exec_params('SELECT count(*) AS n FROM hcr.operations WHERE operation_id=$1',['synthetic-'+id]).first['n']=='0'
        need(empty,'empty-lookup premise')
        decision=reconcile(id,identity,digest,w[:session])
        need(decision=='PENDING','empty does not mean safe retry')
        Timeout.timeout(remaining) { w[:input].write("GO\n");w[:input].flush }
        finish(w);wait_closed(db,w)
      else
        finish(w);wait_closed(db,w)
        if id=='ABORT_THEN_RETRY'
          decision=reconcile(id,identity,digest,w[:session],allow_retry:true)
          need(decision=='RETRY_AUTHORIZED','retry admission')
          retry_worker=start_worker(out,root,args,id,'retry');ready(retry_worker);finish(retry_worker);wait_closed(db,retry_worker)
          need(reconcile(id,identity,digest,retry_worker[:session])=='COMMITTED_EXISTING','retry final lookup')
          decision='RETRY_AUTHORIZED_THEN_COMMITTED'
        elsif id=='BINDING_CONFLICT'
          altered=JSON.parse(JSON.generate(identity));altered['binding']['order_version']='different-version'
          decision=reconcile(id,altered,Digest::SHA256.hexdigest(JSON.generate(altered)),w[:session])
        else
          decision=reconcile(id,identity,digest,w[:session])
        end
      end
      final=db.exec_params("SELECT r.state,r.generation,c.state AS nonce,o.state AS order_state,(SELECT count(*) FROM hcr.operations p WHERE p.operation_id=r.operation_id) AS operations FROM hcr.requests r JOIN hcr.orders o USING(case_id) JOIN hcr.challenges c USING(case_id) WHERE r.case_id=$1",[id]).first
      observed=[decision,final['state'],final['nonce'],final['order_state'],Integer(final['operations']),Integer(final['generation'])]
      need(observed==expected,'fixed expectation mismatch')
      exact={
        'policy'=>[{'case_id'=>id,'generation'=>'1','high_water'=>'1','available'=>'t','test_now'=>args.fetch('verified_at').to_s,'facts'=>facts}],
        'orders'=>[{'case_id'=>id,'binding'=>host['binding'],'version'=>'order-v1','state'=>expected[3]}],
        'challenges'=>[{'case_id'=>id,'facts'=>challenge,'state'=>expected[2]}],
        'requests'=>[{'operation_id'=>'synthetic-'+id,'case_id'=>id,'tenant_id'=>identity['tenant_id'],'principal_id'=>identity['principal_id'],'descriptor'=>identity,'request_digest'=>digest,'generation'=>expected[5].to_s,'state'=>expected[1]}],
        'operations'=>expected[4]==1 ? [{'operation_id'=>'synthetic-'+id,'request_digest'=>digest}] : []}
      hashes={}
      exact.each do |table,wanted|
        query=table=='operations' ? 'operation_id' : 'case_id';key=query=='operation_id' ? 'synthetic-'+id : id
        got=db.exec_params("SELECT * FROM hcr.#{table} WHERE #{query}=$1",[key]).to_a
        got.each { |v| %w[facts binding descriptor].each { |k| v[k]=JSON.parse(v[k]) if v.key?(k) } }
        need(got==wanted,'third-session full row mismatch')
        hashes[table]=Digest::SHA256.hexdigest(JSON.generate(got))
      end
      traces=ACTIVE.drop(worker_offset).map { |v| {events:v[:events].map { |e| e.reject { |k,_| %w[backend backend_start application_name].include?(k) } },reaped:v[:reaped],session_absent:session_absent(db,v.fetch(:session))} }
      rows<<{case_id:id,observed:observed,lookups:LOOKUPS.select { |x| x[:case_id]==id },workers:traces,full_rows_matched:true,full_row_sha256:hashes}
    end
    need(ACTIVE.size==5 && ACTIVE.all? { |w| w[:reaped] && session_absent(db,w.fetch(:session)) },'worker/session recovery')
    save(File.join(out,'WORKER_REPORT.json'),{state:'COMPLETE_NOT_FINAL',completed:4,workers:5,baseline:BASE,input_sha256:INPUT_SHA,results:rows,
      source_sha256:{worker:Digest::SHA256.hexdigest(worker),schema:Digest::SHA256.hexdigest(sql),compare:Digest::SHA256.hexdigest(read_regular(__FILE__,65536))},
      product_sha256:PINS,clock:'fixed synthetic',fault:'application notice suppressed after internal DB ACK; not TCP/DB protocol response fault',production_go:false})
  ensure
    ACTIVE.each do |w|
      w[:input].close rescue nil;w[:output].close rescue nil
      next if w[:reaped]
      begin;Process.kill('KILL',w[:pid]);rescue Errno::ESRCH;end
      begin;Timeout.timeout(1) { Process.waitpid(w[:pid]) };rescue Errno::ECHILD;end
    end
    db.close unless db.finished?
  end
end

if ARGV==['--coordinator']
  need(ENV.fetch('HCR_CONTROLLER_PID')==Process.ppid.to_s,'owned coordinator only')
  begin
    batch(ENV.fetch('HCR_OUT'))
  rescue StandardError => error
    warn error.full_message(highlight:false)
    save(File.join(ENV.fetch('HCR_OUT'),'STOP.json'),{status:'STOP_UNPROVEN',exception_class:error.class.name,reason:error.message.to_s.encode('UTF-8',invalid: :replace,undef: :replace).slice(0,2048),rerun:false})
    exit 2
  end
elsif ARGV==['--execute-approved']
  started=clock
  out=ENV.fetch('HCR_OUT')
  Dir.mkdir(out,0o700) # exclusive once guard, never removed automatically
  save(File.join(out,'BATCH.json'),{state:'STARTED',rerun:false})
  child=nil; status=nil; errors=[]; recovered=false
  controller_out=File.open(File.join(out,'controller.stdout'),File::CREAT|File::EXCL|File::WRONLY,0o600)
  controller_err=File.open(File.join(out,'controller.stderr'),File::CREAT|File::EXCL|File::WRONLY,0o600)
  begin
    child=Process.spawn({'HCR_CONTROLLER_PID'=>Process.pid.to_s},RbConfig.ruby,__FILE__,'--coordinator',
      pgroup:true,out:controller_out,err:controller_err,close_others:true)
    status=Timeout.timeout([296-(clock-started),0.1].max) { Process.waitpid2(child).last }
  rescue StandardError => error
    errors << error.class.name
    controller_err.write(error.full_message(highlight:false));controller_err.flush
  ensure
    controller_out.close;controller_err.close
    if child
      begin; Process.kill('KILL',-child); rescue Errno::ESRCH; rescue StandardError => e; errors << e.class.name; end
      begin; Timeout.timeout(1) { Process.waitpid(child) }; rescue Errno::ECHILD; rescue StandardError => e; errors << e.class.name; end
      until clock-started>=299
        begin; Process.kill(0,-child); rescue Errno::ESRCH; recovered=true; break; rescue StandardError => e; errors << e.class.name; break; end
        sleep 0.01
      end
    end
    save(File.join(out,'SUPERVISION.json'),{exit_code:status&.exitstatus,group_recovered:recovered,errors:errors,seconds:clock-started,rerun:false})
  end
  unless status&.success? && recovered && errors.empty? && clock-started<300
    save(File.join(out,'CONTROLLER_STOP.json'),{status:recovered && errors.empty? ? 'STOP_UNPROVEN' : 'UNKNOWN',rerun:false})
    abort 'STOP: review local supervision record; no retry'
  end
  report=JSON.parse(read_regular(File.join(out,'WORKER_REPORT.json'),65536))
  need(report['completed']==4,'incomplete batch')
  save(File.join(out,'REPORT.json'),report.merge('state'=>'LIMITED_OBSERVED','seconds'=>clock-started,'group_recovered'=>true))
else
  abort 'Execution HOLD: separate bounded approval and fixed environment required'
end
