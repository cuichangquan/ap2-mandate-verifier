# frozen_string_literal: true
# Trusted GitHub/MRI harness, not runtime attestation or a new product runtime.
gem "json", "= 2.19.9"
gem "digest", "= 3.2.1"
gem "openssl", "= 4.0.0"
require "json"
require "digest"
require "openssl"
require "open3"
require "timeout"
require "tmpdir"
require "fileutils"
require "rbconfig"
ROOT = File.expand_path("../..", __dir__)
def need(ok, why) = (raise why unless ok)
# Same bounded regular-file capture as the reviewed Stage15 harness.
def capture(path, cap)
  before = File.lstat(path)
  need(before.file? && before.size.between?(1, cap), "capture type/size")
  metadata = ->(s) { [s.dev,s.ino,s.mode,s.nlink,s.uid,s.gid,s.size,s.mtime,s.ctime] }
  File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |f|
    need(metadata.call(before) == metadata.call(f.stat), "capture changed at open")
    raw = f.read(cap + 1)
    need(raw.bytesize == before.size && metadata.call(before) == metadata.call(f.stat) &&
      metadata.call(before) == metadata.call(File.lstat(path)), "capture changed during read")
    raw
  end
end
def child(command, cwd, env, seconds, cap = 131_072)
  output = error = nil
  Open3.popen3(env, *command, chdir: cwd, pgroup: true) do |stdin, stdout, stderr, waiter|
    stdin.close
    reader = Thread.new { stdout.read(cap + 1).to_s }
    errors = Thread.new { stderr.read(16_385).to_s }
    begin
      Timeout.timeout(seconds) { output = reader.value; error = errors.value; waiter.value }
      need(waiter.value.success? && output.bytesize <= cap && error.bytesize <= 16_384,
        "subprocess failed/output limit")
      # Build/install warnings remain private to this ephemeral runner, not trusted results.
    ensure
      if waiter.alive?
        Process.kill("KILL", -waiter.pid)
        waiter.value
      end
      [reader,errors].each { |t| t.kill if t.alive? }
    end
  end
  output
end
need(RUBY_ENGINE == "ruby" && RUBY_VERSION == "4.0.1" && RUBY_PLATFORM.match?(/x86_64-linux/), "MRI/Linux x64")
need(File.read("/etc/os-release").lines.any? { |l| l.strip == 'VERSION_ID="24.04"' }, "Ubuntu24.04")
need(ENV.fetch("GITHUB_SHA") == ENV.fetch("EXPECTED_SHA") &&
  ENV.fetch("GITHUB_REF") == "refs/heads/main" && ENV.fetch("GITHUB_RUN_ATTEMPT") == "1", "dispatch identity")
manifest_raw = capture(File.join(__dir__, "CURRENT_MANIFEST.json"), 32_768)
need(Digest::SHA256.hexdigest(manifest_raw) == ARGV.fetch(0), "reviewed manifest identity")
manifest = JSON.parse(manifest_raw)
need(manifest.fetch("candidate_version") == "0.1.0.pre.2", "candidate version")
versions = manifest.fetch("dependencies")
versions.each { |name, version| need(Gem::Specification.find_by_name(name, "= #{version}"), "missing fixed provider") }
need(Gem::Specification.find_by_name("openssl", "= 4.0.0").default_gem? &&
  Gem::Specification.find_by_name("digest", "= 3.2.1").default_gem?, "default providers")
captured = manifest.fetch("files_sha256").to_h do |name, sha|
  need(!name.start_with?("/") && !name.split("/").include?(".."), "capture path")
  cap = manifest.fetch("data_files").include?(name) ? 1_048_576 : 131_072
  raw = capture(File.join(ROOT, name), cap)
  need(Digest::SHA256.hexdigest(raw) == sha, "source/input identity")
  [name, raw]
end
ENV.delete("RUBYOPT"); ENV.delete("RUBYLIB"); ENV.delete("AP2_STAGE7_EXPORT")
ENV.keys.grep(/\ABUNDLE_/).each { |k| ENV.delete(k) }
report = {scope: "STAGE18_LINUX_ACTUAL_PACKAGE_NOT_HOST_ALLOW", github_sha: ENV.fetch("GITHUB_SHA"),
  manifest_sha256: Digest::SHA256.hexdigest(manifest_raw), harness_sha256: Digest::SHA256.file(__FILE__).hexdigest,
  independent_expectations: "existing MBA Oracle facts; no Linux Python/Schema Oracle re-execution"}
Dir.mktmpdir("ap2-package-") do |work|
  source = File.join(work, "source"); installed = File.join(work, "installed")
  detached = File.join(work, "detached"); FileUtils.mkdir_p([source,installed,detached])
  captured.each do |name, raw|
    path = File.join(source, name); FileUtils.mkdir_p(File.dirname(path)); File.binwrite(path, raw)
  end
  dependency_path = ENV.fetch("GEM_PATH")
  ordinary = {"GEM_HOME"=>installed,"GEM_PATH"=>installed+File::PATH_SEPARATOR+dependency_path}
  artifact = File.join(work, "candidate.gem")
  # Invoke MRI's own installed RubyGems CLI; never run dependency resolution or gem update.
  gem_cli = File.join(RbConfig::CONFIG.fetch("bindir"), "gem")
  child([RbConfig.ruby,gem_cli,"build","--norc","ap2_mandate_verifier.gemspec","--output",artifact], source, ordinary, 60)
  child([RbConfig.ruby,gem_cli,"install","--norc","--local",artifact,"--install-dir",installed,
    "--ignore-dependencies","--no-document"], detached, ordinary, 60)
  installed_root = File.join(installed, "gems", "ap2_mandate_verifier-0.1.0.pre.2")
  audit = child([RbConfig.ruby,File.join(source,"test/package_contents_audit.rb"),artifact,
    File.join(work,"extracted"),installed_root], source, ordinary, 30)
  package = JSON.parse(audit)
  need(package.fetch("files").sort == manifest.fetch("package_files").sort, "exact13 package files")
  need(package.fetch("source_archive_installed_all_files_match"), "package identity")
  package.fetch("files_sha256").each { |name, sha| need(sha == manifest.fetch("files_sha256").fetch(name), "package/manifest identity") }
  audit_path = File.join(work,"package.json"); File.binwrite(audit_path,audit)
  regression_env = ordinary.merge("BUNDLE_GEMFILE"=>File.join(source,"Gemfile"),"BUNDLE_FROZEN"=>"true",
    "BUNDLE_IGNORE_CONFIG"=>"true","BUNDLE_DISABLE_VERSION_CHECK"=>"true")
  regression = child([RbConfig.ruby,"-rbundler/setup","-I"+File.join(source,"lib"),"-e",
    "ARGV.each { |f| require f }",*manifest.fetch("tests").map { |f| File.join(source,f) }], source, regression_env, 300)
  need(regression.scan(/^PASS (\d+)/).flatten.map(&:to_i) == [79,74,64,81,97,16,147,149,178], "complete885 source regressions")
  observed = JSON.parse(child([RbConfig.ruby,File.join(source,"research/stage18_linux_package/installed_test.rb"),
    File.join(source,"research/stage15/results/R3/INPUTS.json"),File.join(source,"research/stage15_linux/EXPECTED.json"),
    audit_path,source], detached, ordinary, 300))
  need(observed.fetch("total_cases") == 52 && observed.fetch("ordinary_entry") &&
    observed.fetch("dependencies") == versions, "installed52/runtime")
  report.merge!(package:package,source_regressions:885,source_regression_stdout_sha256:Digest::SHA256.hexdigest(regression),
    installed:observed,expected_sha256:manifest.fetch("files_sha256").fetch("research/stage15_linux/EXPECTED.json"),
    inputs_sha256:manifest.fetch("files_sha256").fetch("research/stage15/results/R3/INPUTS.json"))
end
report[:holds] = "production/distribution/Phase2B/Stage16GO/Hostatomic; productCPU/RSS/concurrency; prior2acquisition gaps and Linux128MiB whole-traffic unproved"
text = JSON.pretty_generate(report)
puts text
File.open(ENV.fetch("GITHUB_STEP_SUMMARY"), "a") { |f| f.puts("```json\n#{text}\n```") }
