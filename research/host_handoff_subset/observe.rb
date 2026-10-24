# frozen_string_literal: true
# SOURCE_ONLY / NOT_RUN. Sequential synthetic Host model, never payment ALLOW.
gem 'json', '= 2.19.9'
gem 'jwt', '= 3.3.0'
gem 'base64', '= 0.3.0'
gem 'openssl', '= 4.0.2'
gem 'digest', '= 3.2.1'
require 'json'
require 'jwt'
require 'openssl'
require 'base64'
require 'digest'
def need(ok, reason)
  raise reason unless ok
end
need(ARGV.size == 1, 'source root required')
root = File.realpath(ARGV.fetch(0))
require File.join(root, 'lib/ap2_mandate_verifier')
need(RUBY_ENGINE == 'ruby' && RUBY_VERSION == '4.0.9' && RUBY_PLATFORM.start_with?('arm64-darwin'), 'Ruby identity')
need(OpenSSL::OPENSSL_LIBRARY_VERSION.start_with?('OpenSSL 3.5.9 '), 'provider identity')
loaded = $LOADED_FEATURES.select { |f| f.include?('/ap2_mandate_verifier') && f.end_with?('.rb') }
need(loaded.size == 10 && loaded.all? { |f| File.realpath(f).start_with?(root + '/lib/') }, 'loaded identity')
raw = STDIN.read(262_145)
need(raw.bytesize <= 262_144, 'request cap')
request = JSON.parse(raw, allow_duplicate_key: false, max_nesting: 32)
need(request.keys.sort == %w[args scenario], 'request shape')
args = request.fetch('args').transform_keys(&:to_sym)
result = AP2MandateVerifier.verify_research(**args)
need(result.success? && result.code == :scoped_research_verified, 'Gem prerequisite')
evidence = result.evidence
need(evidence.instance_of?(AP2MandateVerifier::ResearchEvidence) && evidence.frozen?, 'real Evidence')
# Initial authoritative model facts come from independent Host input, never Evidence.
host = JSON.parse(args.fetch(:host_json), allow_duplicate_key: false)
trust = JSON.parse(args.fetch(:trust_json), allow_duplicate_key: false)
snapshot = JSON.parse(trust.fetch('snapshot').fetch('body'), allow_duplicate_key: false)
selection = JSON.parse(args.fetch(:selection_json), allow_duplicate_key: false)
state = { available: true, generation: 1, high_water: 1, profile: trust.fetch('profile'),
  snapshot: trust.fetch('snapshot').slice('id', 'policy_version', 'content_hash'),
  trust_active: snapshot.fetch('active'), fresh_from: snapshot.fetch('not_before'),
  fresh_until: snapshot.fetch('not_after'), now: args.fetch(:verified_at),
  keys: snapshot.fetch('records'), binding: host.fetch('binding'), challenge: host.fetch('challenge'),
  nonce: 'issued', order: 'open', attempts: 0, unknown_reply: false }

consume = lambda do |ev|
  need(ev.equal?(evidence) && ev.instance_of?(AP2MandateVerifier::ResearchEvidence), 'same-process Evidence')
  next 'PENDING' if state[:nonce] == 'pending'
  next 'REPLAY_REJECT' unless state[:nonce] == 'issued' && state[:order] == 'open'
  next 'HOLD' unless state[:available] && state[:trust_active] &&
    state[:fresh_from] <= state[:now] && state[:now] < state[:fresh_until]
  next 'ROLLBACK_REJECT' unless state[:generation] == state[:high_water] &&
    state[:profile].fetch('profile_ref') == ev['profile_ref'] &&
    state[:profile].fetch('version') == ev['profile_version'] &&
    state[:profile].fetch('definition_hash') == ev['profile_definition_hash'] && state[:snapshot] == ev['trust_snapshot']
  next 'TIME_REJECT' unless ev['valid_from'] <= state[:now] && state[:now] < ev['valid_until']
  keys_ok = %w[Issuer Agent Merchant].all? do |role|
    selected = selection.fetch(role)
    matches = state[:keys].select { |key| key['role'] == role && key['identity'] == selected['identity'] &&
      key['purpose'] == selected['purpose'] && key['key_ref'] == selected['key_ref'] &&
      key['tenant_id'] == selection['tenant_id'] && key['profile_ref'] == ev['profile_ref'] &&
      key['profile_version'] == ev['profile_version'] }
    original = ev['selected_keys'].find { |key| key['role'] == role && key['key_ref'] == selected['key_ref'] }
    matches.size == 1 && original && matches.first.reject { |key, _| key == 'public_key_pem' } == original && matches.first['active'] &&
      matches.first['not_before'] <= state[:now] && state[:now] < matches.first['not_after']
  end
  next 'KEY_REJECT' unless keys_ok
  next 'ORDER_REJECT' unless state[:binding] == ev['checkout_binding']
  challenge = state[:challenge]
  projected = challenge.reject { |key, _| key == 'nonce' }.merge('verified_nonce_sha256' => Digest::SHA256.hexdigest(challenge.fetch('nonce')))
  next 'CHALLENGE_REJECT' unless projected == ev['verified_challenge'] && challenge['state'] == 'issued'
  # One abstract state replacement after all checks. No DB / no external side effect.
  state = state.merge(attempts: state[:attempts] + 1,
    nonce: state[:unknown_reply] ? 'pending' : 'consumed', order: state[:unknown_reply] ? 'unknown' : 'accepted')
  state[:unknown_reply] ? 'PENDING' : 'MODEL_COMMIT'
end

scenario = request.fetch('scenario')
case scenario
when 'NORMAL', 'REPLAY'
when 'KEY_REVOKED_AFTER_EVIDENCE'
  state[:keys] = state[:keys].map { |key| key['role'] == 'Issuer' ? key.merge('active' => false) : key }
when 'ORDER_CHANGED_AFTER_EVIDENCE'
  state[:binding] = state[:binding].merge('order_version' => 'order-v2')
when 'ROTATED_OLD_KEY'
  state[:keys] = state[:keys].map { |key| key['role'] == 'Issuer' ? key.merge('key_ref' => 'issuer-2') : key }
when 'PROFILE_SNAPSHOT_ROLLBACK'
  state[:generation] = 0
when 'TRUST_UNAVAILABLE'
  state[:available] = false
when 'CONSUMPTION_UNKNOWN'
  state[:unknown_reply] = true
else
  raise 'unknown scenario'
end
verdicts = [consume.call(evidence)]
verdicts << consume.call(evidence) if %w[REPLAY CONSUMPTION_UNKNOWN].include?(scenario)
puts JSON.generate(scenario: scenario, evidence_created: true, gem_code: result.code,
  verdicts: verdicts, nonce_state: state[:nonce], order_state: state[:order], attempts: state[:attempts],
  runtime: {ruby: RUBY_VERSION, platform: RUBY_PLATFORM, libcrypto: OpenSSL::OPENSSL_LIBRARY_VERSION},
  boundary: 'synthetic sequential state model; no DB atomicity or payment authorization')
