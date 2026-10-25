# frozen_string_literal: true
# NOT_RUN: explicit future approval required. Controller expectations are fixed.
gem 'json', '= 2.19.9'
require 'json'
require 'digest'
require 'rbconfig'
require 'fileutils'
require 'timeout'
INPUT_SHA = 'cc26cf7115c59c5e44c34a5a051f7dd17577958c32df7113ecbe022bb390a4f5'
BASE = '80ea13149543befe106a258d87d7131cc688a158'
EXPECTED = {
 'NORMAL_REPLAY' => [%w[COMMITTED REJECT_REPLAY], 'CONSUMED', 'RESERVED', 'order-v1', 1],
 'SAME_EVIDENCE_RACE' => [%w[COMMITTED REJECT_REPLAY], 'CONSUMED', 'RESERVED', 'order-v1', 1],
 'EDIT_FIRST' => [%w[EDITED REJECT_ORDER], 'ISSUED', 'OPEN', 'order-v2', 0],
 'CONSUME_FIRST' => [%w[COMMITTED TOO_LATE], 'CONSUMED', 'RESERVED', 'order-v1', 1],
 'CAS_ZERO_ROLLBACK' => [%w[REJECT_CAS], 'ISSUED', 'OPEN', 'order-v1', 0]
}.freeze
ACTIVE = []
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
  socket = ENV.fetch('HDB_SOCKET')
  need(socket == 'hdb-db', 'dedicated internal DB service')
  port=ENV.fetch('HDB_PORT')
  need(/\A[0-9]{4,5}\z/.match?(port) && Integer(port).between?(1024,65535),'dedicated port')
  db = PG.connect(host:socket,port:port, dbname:'ap2_handoff_research', user:'ap2_handoff_lab', password:ENV.fetch('HDB_PASSWORD'), connect_timeout:2)
  row = db.exec("SELECT current_database() AS db,current_user AS role,session_user AS session,usesuper FROM pg_user WHERE usename=current_user").first
  need(row == {'db'=>'ap2_handoff_research','role'=>'ap2_handoff_lab','session'=>'ap2_handoff_lab','usesuper'=>'f'}, 'dedicated non-superuser identity')
  need(db.exec('SHOW server_version').first.values.first == ENV.fetch('HDB_SERVER_VERSION') &&
    ENV.fetch('HDB_SERVER_VERSION').start_with?('16.') && PG.library_version.to_s == ENV.fetch('HDB_LIBPQ_VERSION'), 'exact provider identity')
  need(db.exec("SELECT pg_get_userbyid(datdba) AS owner FROM pg_database WHERE datname=current_database()").first['owner']=='ap2_handoff_lab', 'dedicated database owner')
  need(db.host=='hdb-db' && db.port==5432,'dedicated internal endpoint')
  db.exec("SET statement_timeout='2s'; SET lock_timeout='2s'")
  db
end
def start_worker(out, root, args, id, action, hold)
  started=clock
  input_r, input_w = IO.pipe
  output_r, output_w = IO.pipe
  error_path=File.join(out,"#{id}-#{action}-#{hold}.stderr")
  errors = File.open(error_path, File::WRONLY | File::CREAT | File::EXCL, 0o600)
  pid = Timeout.timeout(remaining) do
    Process.spawn({'HDB_COORDINATOR_PID'=>Process.pid.to_s}, RbConfig.ruby, File.join(out,'worker.rb'), '--owned-worker',
      in:input_r,out:output_w,err:errors,close_others:true)
  end
  w={pid:pid,input:input_w,output:output_r,deadline:started+10,events:[],reaped:false,case_id:id,stderr:error_path}
  ACTIVE << w
  input_r.close; output_w.close; errors.close
  request = {case_id:id,action:action,hold:hold,source_root:root,args:args}
  raw = JSON.generate(request) + "\n"
  need(raw.bytesize <= 262144, 'request cap')
  Timeout.timeout(remaining) { input_w.write(raw); input_w.flush }
  w
end
def event(w)
  need(IO.select([w[:output]],nil,nil,remaining), 'worker deadline')
  line = Timeout.timeout(remaining) { w[:output].gets(65537) }
  need(line && line.bytesize<=65536 && line.end_with?("\n"), 'event cap/EOF')
  row = JSON.parse(line,allow_duplicate_key:false)
  w[:events] << row
  need(w[:events].size<=16, 'event count')
  row
end
def until_event(w, name)
  loop do
    row = event(w)
    return row if row['event']==name
    need(%w[READY TRY NONCE_TENTATIVE ORDER_CAS].include?(row['event']), 'unexpected event')
  end
end
def finish(w)
  row = until_event(w,'RESULT')
  status = Timeout.timeout(remaining) { Process.waitpid2(w[:pid]).last }
  w[:reaped]=true
  need(status.success? && File.size(w[:stderr]).zero? && row['evidence']==true && row['gem_code']=='scoped_research_verified', 'worker failed/Evidence missing/stderr')
  row
end
def race(db, workers, out, root, args, id, first, second)
  a = start_worker(out,root,args,id,first,true)
  a_pid = until_event(a,'LOCKED').fetch('backend')
  b = start_worker(out,root,args,id,second,false)
  b_pid = until_event(b,'TRY').fetch('backend')
  need(a_pid!=b_pid && a_pid!=db.backend_pid && b_pid!=db.backend_pid, 'three independent sessions')
  deadline=[clock+2,a[:deadline]-1,b[:deadline]-1].min
  observed=false
  while clock<deadline
    row=Timeout.timeout(remaining) do
      db.exec_params("SELECT wait_event_type, ($2::int=ANY(pg_blocking_pids(pid))) AS blocked FROM pg_stat_activity WHERE pid=$1::int",[b_pid,a_pid]).first
    end
    if row && row['wait_event_type']=='Lock' && row['blocked']=='t'
      observed=true; break
    end
    sleep 0.01
  end
  need(observed, 'actual lock wait unobserved')
  Timeout.timeout(remaining) { a[:input].write("GO\n"); a[:input].flush }
  [finish(a),finish(b)]
end
def batch(out)
  gem 'pg', "= #{ENV.fetch('HDB_PG_VERSION')}"
  require 'pg'
  need(RUBY_VERSION=='4.0.9' && RUBY_PLATFORM.start_with?('aarch64-linux'), 'Linux arm64 runtime')
  root=File.join(out,'source')
  FileUtils.mkdir_p(File.join(root,'lib/ap2_mandate_verifier'),mode:0o700)
  PINS.each do |key,pin|
    name=key.end_with?('.rb') ? key : "lib/ap2_mandate_verifier/#{key}.rb"
    raw=read_regular(File.join(ENV.fetch('HDB_SOURCE_ROOT'),name),65536)
    need(Digest::SHA256.hexdigest(raw)==pin,'product pin')
    File.write(File.join(root,name),raw,mode:'wx',perm:0o400)
  end
  worker=read_regular(File.join(__dir__,'worker.rb'),65536)
  File.write(File.join(out,'worker.rb'),worker,mode:'wx',perm:0o400)
  input=read_regular(ENV.fetch('HDB_INPUTS'),262144)
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
  db=database
  need(db.exec("SELECT to_regnamespace('hdb') AS existing").first['existing'].nil?,'schema exists STOP')
  sql=read_regular(File.join(__dir__,'schema.sql'),65536)
  db.exec(sql)
  workers=ACTIVE; rows=[]
  begin
    EXPECTED.each do |id,expected|
      db.exec('BEGIN')
      db.exec_params('INSERT INTO hdb.policy VALUES($1,1,1,true,$2,$3::jsonb)',[id,args.fetch('verified_at'),JSON.generate(facts)])
      db.exec_params("INSERT INTO hdb.orders VALUES($1,$2::jsonb,'order-v1','OPEN')",[id,JSON.generate(host.fetch('binding'))])
      db.exec_params("INSERT INTO hdb.challenges VALUES($1,$2::jsonb,'ISSUED')",[id,JSON.generate(challenge)])
      db.exec('COMMIT')
      outputs=case id
      when 'SAME_EVIDENCE_RACE' then race(db,workers,out,root,args,id,'consume','consume')
      when 'EDIT_FIRST' then race(db,workers,out,root,args,id,'edit','consume')
      when 'CONSUME_FIRST' then race(db,workers,out,root,args,id,'consume','edit')
      else
        w=start_worker(out,root,args,id,id=='NORMAL_REPLAY' ? 'replay' : 'cas_zero',false)
        [finish(w)]
      end
      actual=db.exec_params("SELECT c.state AS nonce,o.state AS order_state,o.version,(SELECT count(*) FROM hdb.operations p WHERE p.case_id=o.case_id) AS operations FROM hdb.orders o JOIN hdb.challenges c USING(case_id) WHERE o.case_id=$1",[id]).first
      observed=[outputs.flat_map { |r| r.fetch('verdicts') },actual.fetch('nonce'),actual.fetch('order_state'),actual.fetch('version'),Integer(actual.fetch('operations'))]
      need(observed==expected,'fixed expectation mismatch')
      expected_binding=host.fetch('binding').merge('order_version'=>expected[3])
      expected_rows={
        'policy'=>[{'case_id'=>id,'generation'=>'1','high_water'=>'1','available'=>'t','test_now'=>args.fetch('verified_at').to_s,'facts'=>facts}],
        'orders'=>[{'case_id'=>id,'binding'=>expected_binding,'version'=>expected[3],'state'=>expected[2]}],
        'challenges'=>[{'case_id'=>id,'facts'=>challenge,'state'=>expected[1]}],
        'operations'=>expected[4]==1 ? [{'case_id'=>id,'operation_id'=>'synthetic-'+id}] : []}
      full_rows={}
      %w[policy orders challenges operations].each do |table|
        values=db.exec_params("SELECT * FROM hdb.#{table} WHERE case_id=$1",[id]).to_a
        values.each do |row|
          %w[facts binding].each { |key| row[key]=JSON.parse(row[key]) if row.key?(key) }
        end
        need(values==expected_rows.fetch(table),'third-session full row mismatch')
        full_rows[table]=values
      end
      backends=workers.select { |w| w[:case_id]==id }.flat_map { |w| w[:events].filter_map { |e| e['backend'] } }.uniq
      session_deadline=clock+2
      loop do
        sessions=db.exec_params('SELECT count(*) AS n FROM pg_stat_activity WHERE pid=ANY($1::int[])',['{'+backends.join(',')+'}']).first
        break if sessions.fetch('n')=='0'
        need(clock<session_deadline,'worker DB session recovery unknown')
        sleep 0.01
      end
      if id=='CAS_ZERO_ROLLBACK'
        need(w[:events].any? { |e| e=={'event'=>'NONCE_TENTATIVE','rows'=>1} } &&
          w[:events].any? { |e| e=={'event'=>'ORDER_CAS','rows'=>0} },'partial update/zero CAS not observed')
      end
      # Store full row hashes, not raw nonce-bearing data; exact fields checked above.
      row_hashes=full_rows.transform_values { |values| Digest::SHA256.hexdigest(JSON.generate(values)) }
      case_events=workers.select { |w| w[:case_id]==id }.map { |w| w[:events].map { |e| e.reject { |k,_| k=='backend' } } }
      rows << {case_id:id,observed:observed,workers:outputs,events:case_events,full_row_sha256:row_hashes,
        full_rows_matched:true,worker_sessions_closed:true,lock_wait_observed:outputs.size==2}
    end
    save(File.join(out,'WORKER_REPORT.json'),{state:'COMPLETE_NOT_FINAL',baseline:BASE,completed:5,results:rows,
      worker_sha256:Digest::SHA256.hexdigest(worker),schema_sha256:Digest::SHA256.hexdigest(sql),input_sha256:INPUT_SHA,
      compare_sha256:Digest::SHA256.hexdigest(read_regular(__FILE__,65536)),
      product_sha256:PINS,server:ENV.fetch('HDB_SERVER_VERSION'),pg:ENV.fetch('HDB_PG_VERSION'),libpq:PG.library_version,
      clock:'fixed synthetic input time; not real clock attestation',production_go:false})
  ensure
    workers.each do |w|
      w[:input].close rescue nil
      w[:output].close rescue nil
      next if w[:reaped]
      begin; Process.kill('KILL',w[:pid]); rescue Errno::ESRCH; end
      begin; Timeout.timeout(1) { Process.waitpid(w[:pid]) }; rescue Errno::ECHILD; end
    end
    db.close unless db.finished?
  end
end

if ARGV==['--coordinator']
  need(ENV.fetch('HDB_CONTROLLER_PID')==Process.ppid.to_s,'owned coordinator only')
  begin
    batch(ENV.fetch('HDB_OUT'))
  rescue StandardError => error
    save(File.join(ENV.fetch('HDB_OUT'),'STOP.json'),{status:'STOP_UNPROVEN',exception_class:error.class.name,rerun:false})
    exit 2
  end
elsif ARGV==['--execute-approved']
  started=clock
  out=ENV.fetch('HDB_OUT')
  Dir.mkdir(out,0o700) # exclusive once guard, never removed automatically
  save(File.join(out,'BATCH.json'),{state:'STARTED',rerun:false})
  child=nil; status=nil; errors=[]; recovered=false
  begin
    child=Process.spawn({'HDB_CONTROLLER_PID'=>Process.pid.to_s},RbConfig.ruby,__FILE__,'--coordinator',
      pgroup:true,out:File::NULL,err:File::NULL,close_others:true)
    status=Timeout.timeout([296-(clock-started),0.1].max) { Process.waitpid2(child).last }
  rescue StandardError => error
    errors << error.class.name
  ensure
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
  need(report['completed']==5,'incomplete batch')
  save(File.join(out,'REPORT.json'),report.merge('state'=>'LIMITED_OBSERVED','seconds'=>clock-started,'group_recovered'=>true))
else
  abort 'Execution HOLD: separate bounded approval and fixed environment required'
end
