# frozen_string_literal: true
# Trusted GitHub/MRI harness, not runtime attestation or a new product runtime.
gem "digest", "= 3.2.1"
gem "openssl", "= 4.0.2"
require "digest"
require "openssl"
require "open3"
require "timeout"
require "tmpdir"
require "fileutils"
require "rbconfig"
require "resolv"
require "zlib"
require "bundler"
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
def child(command, cwd, env, seconds, cap = 131_072, strict_stderr: false)
  output = error = nil
  Open3.popen3(env, *command, chdir: cwd, pgroup: true) do |stdin, stdout, stderr, waiter|
    stdin.close
    reader = Thread.new { stdout.read(cap + 1).to_s }
    errors = Thread.new { stderr.read(16_385).to_s }
    begin
      Timeout.timeout(seconds) { output = reader.value; error = errors.value; waiter.value }
      need(waiter.value.success? && output.bytesize <= cap && error.bytesize <= 16_384,
        "subprocess failed/output limit")
      need(!strict_stderr || error.empty?, "provider command stderr")
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
UBUNTU_OPENSSL_POLICY = {
  "os_id"=>"ubuntu", "os_version"=>"24.04", "codename"=>"noble",
  "package"=>"libssl3t64:amd64", "source"=>"openssl", "architecture"=>"amd64",
  "package_version"=>"3.0.13-0ubuntu3.16", "upstream_version"=>"3.0.13",
  "security_notice"=>"https://ubuntu.com/security/notices/USN-8847-1"
}.freeze

def provider_identity!
  policy = UBUNTU_OPENSSL_POLICY
  os = File.read("/etc/os-release", 16_385).lines.to_h do |line|
    k,v = line.strip.split("=",2)
    [k,v&.delete_prefix('"')&.delete_suffix('"')]
  end
  need(os["ID"]==policy["os_id"] && os["VERSION_ID"]==policy["os_version"] &&
    os["UBUNTU_CODENAME"]==policy["codename"], "unknown distro")
  need(Gem.loaded_specs.fetch("openssl").version.to_s=="4.0.2" &&
    Gem.loaded_specs.fetch("openssl").default_gem? &&
    Gem.loaded_specs.fetch("digest").version.to_s=="3.2.1" &&
    Gem.loaded_specs.fetch("digest").default_gem?, "loaded default providers")
  need(Bundler::VERSION=="4.0.20" && Resolv::VERSION=="0.7.2" && Zlib::VERSION=="3.2.3", "auxiliary providers")
  need(OpenSSL::OPENSSL_LIBRARY_VERSION.split.fetch(1)==policy["upstream_version"] &&
    OpenSSL::OPENSSL_VERSION.split.fetch(1)==policy["upstream_version"], "unknown compile/runtime OpenSSL")
  prefix = "/opt/hostedtoolcache/Ruby/4.0.9/x64/"
  need(File.realpath(RbConfig.ruby).start_with?(prefix+"bin/"), "unknown Ruby provider")
  extensions = $LOADED_FEATURES.select { |f| File.basename(f)=="openssl.so" }
  need(extensions.size==1, "ambiguous OpenSSL extension")
  extension = File.realpath(extensions.first)
  need(extension.start_with?(prefix), "extension outside verified Ruby archive")
  extension_sha = Digest::SHA256.hexdigest(capture(extension,16_777_216))
  maps = File.read("/proc/self/maps",1_048_577)
  need(maps.bytesize<=1_048_576, "process map limit")
  paths = maps.lines.map { |l| l.split(" ",6).last&.strip }.compact
  need(!paths.any? { |v| v.match?(/lib(?:ssl|crypto)\.so.* \(deleted\)\z/) }, "deleted crypto mapping")
  need(paths.include?(extension), "extension absent from process maps")
  libraries = %w[libssl.so.3 libcrypto.so.3].map do |name|
    found = paths.select { |v| File.basename(v)==name }.uniq
    need(found.size==1, "missing/ambiguous actual library mapping")
    File.realpath(found.first)
  end
  query = ->(*args) { child(["/usr/bin/dpkg-query",*args],ROOT,{},10,strict_stderr:true) }
  package = policy.fetch("package")
  format = '${binary:Package}|${Version}|${Architecture}|${db:Status-Status}|${source:Package}|${source:Version}'
  fields = query.call("-W","-f="+format,package).strip.split("|",-1)
  need(fields == [package,policy["package_version"],"amd64","installed","openssl",policy["package_version"]],
    "unknown/incomplete Ubuntu package identity")
  sum_pairs = query.call("--control-show",package,"md5sums").lines.map do |line|
    parts=line.strip.split(/\s+/,2)
    need(parts.size==2 && parts.first.match?(/\A[0-9a-f]{32}\z/), "package integrity metadata")
    [parts.last,parts.first]
  end
  need(sum_pairs.map(&:first).uniq.size==sum_pairs.size, "duplicate package checksum metadata")
  sums = sum_pairs.to_h
  integrity = child(["/usr/bin/dpkg","--verify",package],ROOT,{},10,strict_stderr:true)
  need(integrity.empty?, "Ubuntu package verification failed")
  identities = libraries.to_h do |path|
    need(query.call("-S",path).strip==package+": "+path, "library outside approved package")
    raw = capture(path,16_777_216)
    need(sums.fetch(path.delete_prefix("/"),nil)==Digest::MD5.hexdigest(raw), "library/package checksum mismatch")
    [path,{"sha256"=>Digest::SHA256.hexdigest(raw),"package"=>package,"package_version"=>fields[1],
      "architecture"=>fields[2],"package_md5_match"=>true}]
  end
  {"policy"=>policy,"package_fields"=>fields,"dpkg_verify"=>"PASS",
    "libcrypto"=>OpenSSL::OPENSSL_LIBRARY_VERSION,"compiled_openssl"=>OpenSSL::OPENSSL_VERSION,
    "extension"=>{"path"=>extension,"sha256"=>extension_sha,"origin"=>"verified official Ruby archive, not dpkg"},
    "actual_mapped_libraries"=>identities,"trust_boundary"=>"trusted runner and dpkg database, not runtime attestation"}
end
need(RUBY_ENGINE == "ruby" && RUBY_VERSION == "4.0.9" && RUBY_PLATFORM.match?(/x86_64-linux/), "MRI/Linux x64")
need(File.read("/etc/os-release").lines.any? { |l| l.strip == 'VERSION_ID="24.04"' }, "Ubuntu24.04")
need(ENV.fetch("GITHUB_SHA") == ENV.fetch("EXPECTED_SHA") &&
  ENV.fetch("GITHUB_REF") == "refs/heads/main" && ENV.fetch("GITHUB_RUN_ATTEMPT") == "1", "dispatch identity")
provider = provider_identity!
if ARGV == ["--provider-preflight"]
  # No JSON parse/generate or extra Gem is needed before dependency acquisition.
  puts "LINUX409_PROVIDER_PREFLIGHT "+provider.inspect
  exit 0
end
need(ARGV.size==1, "manifest argument")
gem "json", "= 2.19.9"
require "json"
manifest_raw = capture(File.join(__dir__, "CURRENT_MANIFEST.json"), 32_768)
need(Digest::SHA256.hexdigest(manifest_raw) == ARGV.fetch(0), "reviewed manifest identity")
manifest = JSON.parse(manifest_raw)
need(manifest.fetch("candidate_version") == "0.1.0.pre.2", "candidate version")
need(Bundler::VERSION == "4.0.20" && Resolv::VERSION == "0.7.2" && Zlib::VERSION == "3.2.3", "default auxiliary providers")
need(manifest.fetch("ubuntu_openssl_policy")==UBUNTU_OPENSSL_POLICY, "reviewed Ubuntu policy identity")
versions = manifest.fetch("dependencies")
versions.each { |name, version| need(Gem::Specification.find_by_name(name, "= #{version}"), "missing fixed provider") }
need(Gem::Specification.find_by_name("openssl", "= 4.0.2").default_gem? &&
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
report = {scope: "LINUX409_PACKAGE01_NOT_HOST_ALLOW", github_sha: ENV.fetch("GITHUB_SHA"),
  github_run_id:ENV.fetch("GITHUB_RUN_ID"),run_attempt:ENV.fetch("GITHUB_RUN_ATTEMPT"),
  run_url:"https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/#{ENV.fetch("GITHUB_RUN_ID")}",
  manifest_sha256: Digest::SHA256.hexdigest(manifest_raw), harness_sha256: Digest::SHA256.file(__FILE__).hexdigest,
  runtime: {ruby:RUBY_DESCRIPTION,executable:RbConfig.ruby,openssl:OpenSSL::VERSION,
    libcrypto:OpenSSL::OPENSSL_LIBRARY_VERSION,compiled_openssl:OpenSSL::OPENSSL_VERSION,
    digest:Digest::VERSION,resolv:Resolv::VERSION,zlib:Zlib::VERSION,bundler:Bundler::VERSION},
  provider_archive:manifest.fetch("ruby_provider"),provider_identity:provider,
  independent_expectations: "existing MBA Oracle facts; no Linux Python/Schema Oracle re-execution"}
native = $LOADED_FEATURES.select { |f| f.end_with?(".so") && File.file?(f) && f.match?(/openssl|digest|json|zlib/) }
need(native.any? { |f| File.basename(f) == "openssl.so" }, "native OpenSSL identity")
report[:native_extensions] = native.to_h { |f| [File.realpath(f),Digest::SHA256.file(f).hexdigest] }
linked = native.select { |f| File.basename(f) == "openssl.so" }.flat_map do |f|
  output = child(["/usr/bin/ldd",f],ROOT,{},10)
  need(!output.include?("not found"), "unresolved native dependency")
  output.scan(/lib(?:ssl|crypto)\.so\S* => (\/\S+)/).flatten
end.uniq
need(linked.map { |f| File.realpath(f) }.sort == provider.fetch("actual_mapped_libraries").keys.sort,
  "ldd/process-map library mismatch")
report[:linked_crypto_files] = linked.to_h { |f| [File.realpath(f),Digest::SHA256.file(f).hexdigest] }
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
  reference = manifest.fetch("mba_package_reference")
  need(package.fetch("files_sha256") == reference.fetch("files_sha256") &&
    package.fetch("dependencies") == reference.fetch("dependencies") &&
    package.fetch("version") == reference.fetch("version") &&
    package.fetch("required_ruby") == reference.fetch("required_ruby"), "MBA package payload/metadata mismatch")
  report[:mba_package_reference] = reference.reject { |k,_| k == "files_sha256" }
  need(package.fetch("files").sort == manifest.fetch("package_files").sort, "exact13 package files")
  need(package.fetch("source_archive_installed_all_files_match"), "package identity")
  package.fetch("files_sha256").each { |name, sha| need(sha == manifest.fetch("files_sha256").fetch(name), "package/manifest identity") }
  audit_path = File.join(work,"package.json"); File.binwrite(audit_path,audit)
  regression_env = ordinary.merge("BUNDLE_GEMFILE"=>File.join(source,"Gemfile"),"BUNDLE_FROZEN"=>"true",
    "BUNDLE_IGNORE_CONFIG"=>"true","BUNDLE_DISABLE_VERSION_CHECK"=>"true")
  regression = child([RbConfig.ruby,"-rbundler/setup","-I"+File.join(source,"lib"),"-e",
    "ARGV.each { |f| require f }",*manifest.fetch("tests").map { |f| File.join(source,f) }], source, regression_env, 300)
  need(regression.scan(/^PASS (\d+)/).flatten.map(&:to_i) == [79,74,64,81,97,16,147,149,178], "complete885 source regressions")
  observed = JSON.parse(child([RbConfig.ruby,File.join(source,"research/runtime409_linux_package/installed_test.rb"),
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
