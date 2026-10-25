# frozen_string_literal: true
# NOT_RUN / research only. No payment, provider fetch, or Evidence reconstruction.
gem 'json', '= 2.19.9'
gem 'pg', "= #{ENV.fetch('HCR_PG_VERSION')}"
gem 'jwt', '= 3.3.0'
gem 'base64', '= 0.3.0'
gem 'openssl', '= 4.0.2'
gem 'digest', '= 3.2.1'
require 'pg'
require 'json'
require 'openssl'
require 'digest'
STDOUT.sync = true
class Refusal < StandardError; end
def need(ok, why)
  raise why unless ok
end
def emit(value)
  puts JSON.generate(value)
end
need(ARGV == ['--owned-worker'] && ENV['HCR_COORDINATOR_PID'] == Process.ppid.to_s, 'owned worker only')
raw = STDIN.gets(262_146)
need(raw && raw.bytesize <= 262_144 && raw.end_with?("\n"), 'request cap')
request = JSON.parse(raw, allow_duplicate_key: false, max_nesting: 32)
need(request.keys.sort == %w[action args case_id hold source_root], 'request shape')
action = request.fetch('action')
need(%w[commit_hide abort_before_commit hold_abort retry].include?(action), 'action')
need(%w[COMMIT_NOTICE_LOST ABORT_THEN_RETRY INFLIGHT_EMPTY BINDING_CONFLICT].include?(request['case_id']), 'case')
root = File.realpath(request.fetch('source_root'))
require File.join(root, 'lib/ap2_mandate_verifier')
need(RUBY_VERSION == '4.0.9' && RUBY_ENGINE == 'ruby' && RUBY_PLATFORM.start_with?('aarch64-linux'), 'Ruby identity')
need(OpenSSL::OPENSSL_LIBRARY_VERSION == ENV.fetch('HCR_OPENSSL_LIBRARY'), 'admitted Linux libcrypto identity')
loaded = $LOADED_FEATURES.select { |f| f.include?('/ap2_mandate_verifier') && f.end_with?('.rb') }
need(loaded.size == 10 && loaded.all? { |f| File.realpath(f).start_with?(root + '/lib/') }, 'product load paths')
result = AP2MandateVerifier.verify_research(**request.fetch('args').transform_keys(&:to_sym))
need(result.success? && result.code == :scoped_research_verified, 'Gem prerequisite')
evidence = result.evidence
need(evidence.instance_of?(AP2MandateVerifier::ResearchEvidence) && evidence.frozen?, 'actual Evidence')
socket = ENV.fetch('HCR_SOCKET')
need(socket == 'hcr-db', 'dedicated internal DB service')
db = PG.connect(host: socket, port: ENV.fetch('HCR_PORT'), dbname: 'ap2_reconcile_research', user: 'ap2_reconcile_lab', password: ENV.fetch('HCR_PASSWORD'), connect_timeout: 2)
need(db.exec("SELECT current_database(),current_user,session_user").first.values ==
  %w[ap2_reconcile_research ap2_reconcile_lab ap2_reconcile_lab], 'DB identity')
need(db.exec('SHOW server_version').first.values.first == ENV.fetch('HCR_SERVER_VERSION'), 'server identity')
need(PG.library_version.to_s == ENV.fetch('HCR_LIBPQ_VERSION'), 'libpq identity')

# Synthetic authenticated caller context is pinned by the controller, not a real login.
host = JSON.parse(request.fetch('args').fetch('host_json'))
identity = {
  'tenant_id'=>host.fetch('binding').fetch('tenant_id'),
  'principal_id'=>host.fetch('binding').fetch('buyer_account_id'),
  'binding'=>host.fetch('binding'),
  'challenge'=>host.fetch('challenge').reject { |k,_| k=='nonce' },
  'nonce_sha256'=>Digest::SHA256.hexdigest(host.fetch('challenge').fetch('nonce'))
}
descriptor_wire = JSON.generate(identity)
digest = Digest::SHA256.hexdigest(descriptor_wire)
case_id=request.fetch('case_id'); operation_id='synthetic-'+case_id
generation=action=='retry' ? 2 : 1
app='ap2-hcr-'+case_id+'-g'+generation.to_s
db.exec_params("SELECT set_config('application_name',$1,false)",[app])
start=db.exec('SELECT backend_start::text FROM pg_stat_activity WHERE pid=pg_backend_pid()').first.fetch('backend_start')
emit(event:'READY',backend:db.backend_pid,backend_start:start,application_name:app,evidence:true)
begin
  db.exec("BEGIN; SET LOCAL statement_timeout='2s'; SET LOCAL lock_timeout='2s'")
  registry=db.exec_params('SELECT * FROM hcr.requests WHERE operation_id=$1 FOR UPDATE',[operation_id]).first
  need(registry && registry['case_id']==case_id && registry['tenant_id']==identity['tenant_id'] &&
    registry['principal_id']==identity['principal_id'] && registry['request_digest']==digest &&
    JSON.parse(registry['descriptor'])==identity && registry['generation']==generation.to_s &&
    registry['state']=='REGISTERED', 'registry authorization/binding/fence')
  policy=db.exec_params('SELECT * FROM hcr.policy WHERE case_id=$1 FOR UPDATE',[case_id]).first
  order=db.exec_params('SELECT * FROM hcr.orders WHERE case_id=$1 FOR UPDATE',[case_id]).first
  challenge=db.exec_params('SELECT * FROM hcr.challenges WHERE case_id=$1 FOR UPDATE',[case_id]).first
  need(policy && order && challenge,'missing Host state')
  if action=='hold_abort'
    emit(event:'LOCKED')
    need(STDIN.gets(4)=="GO\n",'owned barrier')
    db.close # actual session close with an open transaction: server abort expected
    emit(event:'CHANNEL_CLOSED')
    exit 0
  end
  ev=evidence
    raise Refusal, 'REJECT_REPLAY' unless order['state'] == 'OPEN' && challenge['state'] == 'ISSUED'
    facts = JSON.parse(policy.fetch('facts'))
    now = Integer(policy.fetch('test_now'))
    raise Refusal, 'HOLD' unless policy['available'] == 't' && policy['generation'] == policy['high_water'] &&
      facts.fetch('active') && facts.fetch('not_before') <= now && now < facts.fetch('not_after')
    raise Refusal, 'REJECT_TRUST' unless facts.fetch('profile') ==
      ev.to_h.slice('profile_ref','profile_version','profile_definition_hash') && facts.fetch('snapshot') == ev['trust_snapshot'] &&
      facts.fetch('keys') == ev['selected_keys'] && ev['valid_from'] <= now && now < ev['valid_until']
    raise Refusal, 'REJECT_ORDER' unless JSON.parse(order.fetch('binding')) == ev['checkout_binding'] &&
      order['version'] == ev['checkout_binding'].fetch('order_version')
    raise Refusal, 'REJECT_CHALLENGE' unless JSON.parse(challenge.fetch('facts')) == ev['verified_challenge']
    nonce = db.exec_params("UPDATE hcr.challenges SET state='CONSUMED' WHERE case_id=$1 AND state='ISSUED' RETURNING case_id", [case_id])
    raise Refusal, 'REJECT_NONCE_CAS' unless nonce.ntuples == 1
    expected_version = ev['checkout_binding'].fetch('order_version')
    changed = db.exec_params("UPDATE hcr.orders SET state='RESERVED' WHERE case_id=$1 AND version=$2 AND state='OPEN' RETURNING case_id", [case_id, expected_version])
    raise Refusal, 'REJECT_CAS' unless changed.ntuples == 1

  db.exec_params('INSERT INTO hcr.operations VALUES($1,$2)',[operation_id,digest])
  changed=db.exec_params("UPDATE hcr.requests SET state='DONE' WHERE operation_id=$1 AND generation=$2 AND state='REGISTERED' RETURNING operation_id",[operation_id,generation])
  need(changed.ntuples==1,'registry CAS')
  if action=='abort_before_commit'
    db.close # no COMMIT submitted; close rolls back all tentative writes
  else
    db.exec('COMMIT') # worker receives DB acknowledgment internally
    db.close
  end
  # Deliberately no application success/result is delivered, in either outcome.
  emit(event:'CHANNEL_CLOSED')
rescue StandardError
  db.exec('ROLLBACK') rescue nil
  raise 'UNKNOWN_PENDING: stop; no automatic attempt'
ensure
  db.close unless db.finished?
end
