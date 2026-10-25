# frozen_string_literal: true
# NOT_RUN / research only. No payment, provider fetch, or Evidence reconstruction.
gem 'json', '= 2.19.9'
gem 'pg', "= #{ENV.fetch('HDB_PG_VERSION')}"
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
need(ARGV == ['--owned-worker'] && ENV['HDB_COORDINATOR_PID'] == Process.ppid.to_s, 'owned worker only')
raw = STDIN.gets(262_146)
need(raw && raw.bytesize <= 262_144 && raw.end_with?("\n"), 'request cap')
request = JSON.parse(raw, allow_duplicate_key: false, max_nesting: 32)
need(request.keys.sort == %w[action args case_id hold source_root], 'request shape')
action = request.fetch('action')
need(%w[consume replay edit cas_zero].include?(action), 'action')
need(%w[NORMAL_REPLAY SAME_EVIDENCE_RACE EDIT_FIRST CONSUME_FIRST CAS_ZERO_ROLLBACK].include?(request['case_id']), 'case')
root = File.realpath(request.fetch('source_root'))
require File.join(root, 'lib/ap2_mandate_verifier')
need(RUBY_VERSION == '4.0.9' && RUBY_ENGINE == 'ruby' && RUBY_PLATFORM.start_with?('aarch64-linux'), 'Ruby identity')
need(OpenSSL::OPENSSL_LIBRARY_VERSION == ENV.fetch('HDB_OPENSSL_LIBRARY'), 'admitted Linux libcrypto identity')
loaded = $LOADED_FEATURES.select { |f| f.include?('/ap2_mandate_verifier') && f.end_with?('.rb') }
need(loaded.size == 10 && loaded.all? { |f| File.realpath(f).start_with?(root + '/lib/') }, 'product load paths')
result = AP2MandateVerifier.verify_research(**request.fetch('args').transform_keys(&:to_sym))
need(result.success? && result.code == :scoped_research_verified, 'Gem prerequisite')
evidence = result.evidence
need(evidence.instance_of?(AP2MandateVerifier::ResearchEvidence) && evidence.frozen?, 'actual Evidence')
socket = ENV.fetch('HDB_SOCKET')
need(socket == 'hdb-db', 'dedicated internal DB service')
db = PG.connect(host: socket, port: ENV.fetch('HDB_PORT'), dbname: 'ap2_handoff_research', user: 'ap2_handoff_lab', password: ENV.fetch('HDB_PASSWORD'), connect_timeout: 2)
need(db.exec("SELECT current_database(),current_user,session_user").first.values ==
  %w[ap2_handoff_research ap2_handoff_lab ap2_handoff_lab], 'DB identity')
need(db.exec('SHOW server_version').first.values.first == ENV.fetch('HDB_SERVER_VERSION'), 'server identity')
need(PG.library_version.to_s == ENV.fetch('HDB_LIBPQ_VERSION'), 'libpq identity')
emit(event: 'READY', backend: db.backend_pid, evidence: true)
case_id = request.fetch('case_id')
consume = lambda do |ev, hold, force_zero|
  need(ev.equal?(evidence), 'same-process Evidence')
  committed = false
  begin
    db.exec("BEGIN; SET LOCAL statement_timeout='2s'; SET LOCAL lock_timeout='2s'")
    emit(event: 'TRY', backend: db.backend_pid)
    policy = db.exec_params('SELECT * FROM hdb.policy WHERE case_id=$1 FOR UPDATE', [case_id]).first
    order = db.exec_params('SELECT * FROM hdb.orders WHERE case_id=$1 FOR UPDATE', [case_id]).first
    challenge = db.exec_params('SELECT * FROM hdb.challenges WHERE case_id=$1 FOR UPDATE', [case_id]).first
    need(policy && order && challenge, 'missing seeded state')
    if hold
      emit(event: 'LOCKED', backend: db.backend_pid)
      need(STDIN.gets(4) == "GO\n", 'barrier release')
    end
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
    nonce = db.exec_params("UPDATE hdb.challenges SET state='CONSUMED' WHERE case_id=$1 AND state='ISSUED' RETURNING case_id", [case_id])
    raise Refusal, 'REJECT_NONCE_CAS' unless nonce.ntuples == 1
    emit(event: 'NONCE_TENTATIVE', rows: nonce.ntuples) if force_zero
    expected_version = force_zero ? 'forced-impossible-version' : ev['checkout_binding'].fetch('order_version')
    changed = db.exec_params("UPDATE hdb.orders SET state='RESERVED' WHERE case_id=$1 AND version=$2 AND state='OPEN' RETURNING case_id", [case_id, expected_version])
    emit(event: 'ORDER_CAS', rows: changed.ntuples) if force_zero
    raise Refusal, 'REJECT_CAS' unless changed.ntuples == 1
    db.exec_params('INSERT INTO hdb.operations(case_id,operation_id) VALUES($1,$2)', [case_id, 'synthetic-' + case_id])
    db.exec('COMMIT')
    committed = true
    'COMMITTED'
  rescue Refusal => error
    db.exec('ROLLBACK')
    error.message
  rescue StandardError
    # A rollback attempt does not disambiguate a submitted COMMIT.
    db.exec('ROLLBACK') rescue nil
    raise 'UNKNOWN_PENDING'
  ensure
    need(db.transaction_status == PG::PQTRANS_IDLE, 'transaction recovery unknown') unless committed
  end
end
if action == 'edit'
  begin
    db.exec("BEGIN; SET LOCAL statement_timeout='2s'; SET LOCAL lock_timeout='2s'")
    emit(event: 'TRY', backend: db.backend_pid)
    db.exec_params('SELECT case_id FROM hdb.policy WHERE case_id=$1 FOR UPDATE', [case_id])
    row = db.exec_params('SELECT * FROM hdb.orders WHERE case_id=$1 FOR UPDATE', [case_id]).first
    db.exec_params('SELECT case_id FROM hdb.challenges WHERE case_id=$1 FOR UPDATE', [case_id])
    if request.fetch('hold')
      emit(event: 'LOCKED', backend: db.backend_pid)
      need(STDIN.gets(4) == "GO\n", 'barrier release')
    end
    if row.fetch('state') != 'OPEN'
      db.exec('ROLLBACK')
      verdicts = ['TOO_LATE']
    else
      binding = JSON.parse(row.fetch('binding')).merge('order_version' => 'order-v2')
      changed = db.exec_params("UPDATE hdb.orders SET binding=$2::jsonb,version='order-v2' WHERE case_id=$1 AND state='OPEN' AND version='order-v1' RETURNING case_id", [case_id, JSON.generate(binding)])
      need(changed.ntuples == 1, 'mutation CAS')
      db.exec('COMMIT')
      verdicts = ['EDITED']
    end
  rescue StandardError
    db.exec('ROLLBACK') rescue nil
    raise 'UNKNOWN_PENDING'
  end
else
  verdicts = [consume.call(evidence, request.fetch('hold'), action == 'cas_zero')]
  verdicts << consume.call(evidence, false, false) if action == 'replay'
end
emit(event: 'RESULT', verdicts: verdicts, evidence: true, gem_code: result.code,
  runtime: {ruby: RUBY_VERSION, pg: Gem.loaded_specs.fetch('pg').version.to_s,
    libpq: PG.library_version, libcrypto: OpenSSL::OPENSSL_LIBRARY_VERSION})
db.close
