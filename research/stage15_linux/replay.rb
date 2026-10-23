# frozen_string_literal: true
# Trusted harness, ordinary Gem entry. No production authority or runtime attestation.
require 'json'
require 'digest'
require 'open3'
require 'timeout'
require 'tmpdir'
require 'fileutils'
ROOT = File.expand_path('../..', __dir__)
def need(ok, why)
  raise why unless ok
end
def read_regular(path, cap)
  before = File.lstat(path)
  need(before.file? && before.size.between?(1, cap), 'input type/size')
  File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |f|
    metadata = ->(s) { [s.dev, s.ino, s.mode, s.nlink, s.uid, s.gid, s.size, s.mtime, s.ctime] }
    need(metadata.call(before) == metadata.call(f.stat), 'input changed at open')
    raw = f.read(cap + 1)
    need(raw.bytesize == before.size && metadata.call(before) == metadata.call(f.stat) &&
      metadata.call(before) == metadata.call(File.lstat(path)), 'input changed during read')
    raw
  end
end
def run_child(command, seconds, input = '')
  output = error = nil
  Open3.popen3(*command, pgroup: true) do |stdin, stdout, stderr, waiter|
    writer = Thread.new { stdin.write(input); stdin.close }
    reader = Thread.new { stdout.read(131073).to_s }
    errors = Thread.new { stderr.read(16385).to_s }
    begin
      Timeout.timeout(seconds) { writer.value; output = reader.value; error = errors.value; waiter.value }
      need(waiter.value.success? && output.bytesize < 131073 && error.empty?, 'child failed/output boundary')
    ensure
      if waiter.alive?
        Process.kill('KILL', -waiter.pid)
        waiter.value
      end
      [writer, reader, errors].each { |t| t.kill if t.alive? }
    end
  end
  output
end
need(RUBY_VERSION == '4.0.1' && JSON::VERSION == '2.19.9', 'Ruby/JSON identity')
linux = RUBY_PLATFORM.match?(/x86_64-linux/)
need(linux, 'Linux x64 required') if ENV['AP2_LINUX_RUN'] == '1'
if linux
  need(File.read('/etc/os-release').lines.any? { |s| s.strip == 'VERSION_ID="24.04"' }, 'Ubuntu24.04 required')
end
manifest_raw = read_regular(File.join(__dir__, 'CURRENT_MANIFEST.json'), 16384)
need(Digest::SHA256.hexdigest(manifest_raw) == ARGV.fetch(0), 'reviewed manifest identity')
manifest = JSON.parse(manifest_raw)
captured = manifest.fetch('captured_sources').to_h do |name, digest|
  raw = read_regular(File.join(ROOT, name), 65536)
  need(Digest::SHA256.hexdigest(raw) == digest, 'source identity')
  [name, raw]
end
manifest.fetch('captured_inputs').each do |name, digest|
  raw = read_regular(File.join(ROOT, name), 1048576)
  need(Digest::SHA256.hexdigest(raw) == digest, 'regression fixture identity')
  captured[name] = raw
end
inputs_raw = read_regular(File.join(ROOT, 'research/stage15/results/R3/INPUTS.json'), 1048576)
expected_raw = read_regular(File.join(__dir__, 'EXPECTED.json'), 131072)
need(Digest::SHA256.hexdigest(inputs_raw) == manifest.fetch('inputs_sha256'), 'inputs identity')
need(Digest::SHA256.hexdigest(expected_raw) == manifest.fetch('expected_sha256'), 'expectations identity')
inputs = JSON.parse(inputs_raw); expected = JSON.parse(expected_raw)
need(expected.fetch('inputs_sha256') == manifest.fetch('inputs_sha256'), 'oracle/input link')
need(inputs.keys.sort == expected.fetch('cases').keys.sort && inputs.size == 42, 'complete42')
rows = []; runtime = nil; regression = nil
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
Dir.mktmpdir('ap2-linux-candidate-') do |tree|
  captured.each do |name, raw|
    path = File.join(tree, name); FileUtils.mkdir_p(File.dirname(path)); File.binwrite(path, raw)
  end
  ENV['BUNDLE_GEMFILE'] = File.join(tree, 'Gemfile')
  ENV['BUNDLE_FROZEN'] = 'true'
  ENV['BUNDLE_IGNORE_CONFIG'] = 'true'
  ENV['BUNDLE_DISABLE_VERSION_CHECK'] = 'true'
  ENV.delete('RUBYOPT')
  tests = manifest.fetch('tests')
  regression = run_child([RbConfig.ruby, '-rbundler/setup', '-I'+File.join(tree, 'lib'), '-e',
    'ARGV.each { |f| require f }', *tests.map { |name| File.join(tree, name) }], 300)
  counts = regression.scan(/^PASS (\d+)/).flatten.map(&:to_i)
  need(counts == [79,74,64,81,97,16,147,149,178] && counts.sum == 885, 'complete885')
  comparison_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  expected.fetch('cases').each do |name, e|
    remaining = 300 - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - comparison_start)
    need(remaining > 0, 'comparison deadline')
    observed = JSON.parse(run_child([RbConfig.ruby, File.join(tree, 'research/security_json/observe.rb')],
      [10, remaining].min, JSON.generate(args: inputs.fetch(name))))
    success = e.fetch('code') == 'scoped_research_verified'
    need(observed.values_at('code','status','success','evidence','entries') ==
      [e['code'], success ? 'verified_research' : 'rejected', success, e['evidence'], e['entries']], 'case mismatch: '+name)
    need(!success || (observed['deeply_frozen'] && observed['stable_after_input_mutation']), 'Evidence immutability')
    r = observed.fetch('runtime')
    need(r.values_at('ruby','json','json_gem_version','jwt','base64','openssl','bundler') ==
      ['4.0.1','2.19.9','2.19.9','3.3.0','0.3.0','4.0.0','4.0.3'], 'resolved runtime versions')
    need(r.fetch('resolved_gems') == manifest.fetch('resolved_gems'), 'resolved gem set')
    need(runtime.nil? || runtime == r, 'runtime changed across cases'); runtime = r
    rows << {name: name, code: e['code'], result: 'MATCH', input_sha256: Digest::SHA256.hexdigest(JSON.generate(inputs.fetch(name)))}
  end
end
report = {scope: linux ? 'LIMITED_LINUX_REPLAY' : 'MBA_PREFLIGHT_NOT_LINUX',
  manifest_sha256: Digest::SHA256.hexdigest(manifest_raw), replay_sha256: Digest::SHA256.file(__FILE__).hexdigest,
  expected_sha256: manifest['expected_sha256'], inputs_sha256: manifest['inputs_sha256'],
  runtime: runtime, ruby_platform: RUBY_PLATFORM, regressions: 885, comparisons: rows,
  wall_seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC)-started,
  children_cpu: Process.times.to_a.drop(2),
  independent_oracle: 'MBA Python expected values, not Linux Oracle re-execution',
  schema8: 'existing MBA evidence only',
  hold: 'Hostatomic/payment/production/distribution/Phase2B/Stage16; prior2 acquisition gaps unchanged'}
puts JSON.pretty_generate(report)
if ENV['GITHUB_STEP_SUMMARY']
  File.open(ENV.fetch('GITHUB_STEP_SUMMARY'), 'a') { |f| f.puts("```json\n#{JSON.pretty_generate(report)}\n```") }
end
