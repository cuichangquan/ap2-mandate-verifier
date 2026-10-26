# frozen_string_literal: true
# Preparation only. Running any mode needs separate Owner approval B.
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

module Stable010
  extend self
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
  work=ENV.fetch("STABLE010_WORK")
  @child_index=(@child_index||0)+1
  tag=File.join(work,"child-#{Process.pid}-%03d" % @child_index)
  stdout=tag+".stdout";stderr=tag+".stderr";pid=nil;status=nil;failure=nil;clear=false
  seconds=[seconds,ENV.fetch("STABLE010_DEADLINE").to_i-Time.now.to_i].min
  need(seconds>0,"work deadline; reserve cleanup")
  began=Process.clock_gettime(Process::CLOCK_MONOTONIC)
  begin
    pid=Process.spawn(env,*command,chdir:cwd,pgroup:true,in:File::NULL,out:stdout,err:stderr)
    loop do
      waited=Process.waitpid2(pid,Process::WNOHANG)
      if waited;status=waited[1];break;end
      need(Process.clock_gettime(Process::CLOCK_MONOTONIC)-began<seconds,"child timeout")
      need(File.size(stdout)<=cap && File.size(stderr)<=16_384,"child output cap")
      sleep 0.05
    end
  rescue Exception=>e
    failure=e
  ensure
    if pid
      begin
        begin;Process.kill("KILL",-pid);rescue Errno::ESRCH;end
        until_time=Process.clock_gettime(Process::CLOCK_MONOTONIC)+3
        loop do
          begin
            waited=Process.waitpid2(pid,Process::WNOHANG)
            if waited;status||=waited[1];break;end
          rescue Errno::ECHILD;break;end
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC)>=until_time
          sleep 0.05
        end
        until_time=Process.clock_gettime(Process::CLOCK_MONOTONIC)+3
        loop do
          begin;Process.kill(0,-pid);rescue Errno::ESRCH;clear=true;break;end
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC)>=until_time
          sleep 0.05
        end
      rescue Exception=>e
        failure||=e
      end
    end
    File.write(tag+".receipt", {exit:status&.exitstatus,group_clear:clear,error:failure&.message}.inspect+"\n")
  end
  need(failure.nil? && status&.success? && clear,"child failed; bounded logs preserved")
  need(File.size(stdout)<=cap && File.size(stderr)<=16_384,"child output cap")
  output=File.binread(stdout);error=File.binread(stderr)
  need(!strict_stderr || error.empty?,"provider stderr; logs preserved")
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
  need(!paths.any? { |v| v.match?(/(?:openssl\.so|lib(?:ssl|crypto)\.so.*) \(deleted\)\z/) }, "deleted crypto mapping")
  mapped_extensions = paths.select { |v| File.basename(v)=="openssl.so" }.uniq
  need(mapped_extensions.size==1 && File.realpath(mapped_extensions.first)==extension,
    "missing/ambiguous actual OpenSSL extension mapping")
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

def runtime!
  need(RUBY_ENGINE == "ruby" && RUBY_VERSION == "4.0.9" &&
    RUBY_PLATFORM.match?(/x86_64-linux/), "MRI4.0.9/Linux x64")
  identity = provider_identity!
  executable = File.realpath(RbConfig.ruby)
  identity.merge("ruby_executable"=>{"path"=>executable,
    "sha256"=>Digest::SHA256.hexdigest(capture(executable,16_777_216))})
end

def json_identity!
  need(Gem.loaded_specs.fetch("json").version.to_s == "2.19.9" &&
    JSON.parser.name == "JSON::Ext::Parser" && JSON.generator.name == "JSON::Ext::Generator", "actual JSON provider")
  spec = Gem.loaded_specs.fetch("json")
  roots = [spec.full_gem_path,spec.extension_dir].map { |p| File.realpath(p)+"/" }
  features = $LOADED_FEATURES.select { |p| p.match?(/\/json\/ext\/(?:parser|generator)\.so\z/) }
  need(features.map { |p| File.basename(p) }.sort == %w[generator.so parser.so], "JSON native features")
  features.to_h do |p|
    actual = File.realpath(p)
    need(roots.any? { |root| actual.start_with?(root) }, "JSON extension outside fixed Gem")
    [actual,Digest::SHA256.hexdigest(capture(actual,16_777_216))]
  end
end

def dispatch!
  need(Time.now.to_i < ENV.fetch("STABLE010_DEADLINE").to_i,"work deadline")
  need(ENV.fetch("GITHUB_REPOSITORY") == "cuichangquan/ap2-mandate-verifier" &&
    ENV.fetch("GITHUB_EVENT_NAME") == "workflow_dispatch" &&
    ENV.fetch("GITHUB_SHA") == ENV.fetch("EXPECTED_SHA") &&
    ENV.fetch("EXPECTED_SHA").match?(/\A[0-9a-f]{40}\z/) &&
    ENV.fetch("GITHUB_REF") == "refs/heads/main" &&
    ENV.fetch("GITHUB_RUN_ATTEMPT") == "1" &&
    ENV.fetch("APPROVAL_B_CONFIRMED") == "true" &&
    ENV.fetch("ZERO_COST_CONFIRMED") == "true", "execution identity/approval/cost")
end

def main(args)
  dispatch!
  ENV.delete("RUBYOPT"); ENV.delete("RUBYLIB"); ENV.delete("AP2_STAGE7_EXPORT")
  ENV.keys.grep(/\ABUNDLE_/).each { |k| ENV.delete(k) }
  provider = runtime!
  if args == ["--provider-preflight"]
    puts "STABLE010_CANDIDATE_PROVIDER_PREFLIGHT "+provider.inspect
    return
  end
  if args == ["--install-dependencies"]
    gem_cli=File.join(RbConfig::CONFIG.fetch("bindir"),"gem")
    archive_root=File.join(ENV.fetch("RUNNER_TEMP"),"ap2-stable010-archives")
    [["json",180],["jwt",30],["base64",30]].each do |name,seconds|
      file=Dir[File.join(archive_root,name+"-*.gem")]
      need(file.size==1,"fixed dependency archive")
      File.write(File.join(ENV.fetch("STABLE010_WORK"),name+"-install-started"),"started\n")
      child([RbConfig.ruby,gem_cli,"install","--norc","--local",file.first,"--ignore-dependencies","--no-document"],ROOT,{},seconds)
      File.write(File.join(ENV.fetch("STABLE010_WORK"),name+"-install-completed"),"completed\n")
    end
    puts "OFFLINE_DEPENDENCIES_INSTALLED"
    return
  end
  need(args.size == 2 && args[0].match?(/\A[0-9a-f]{64}\z/), "manifest/artifact arguments")
  gem "json", "= 2.19.9"
  require "json"
  require "rubygems/package"
  json_provider = json_identity!
  raw = capture(File.join(__dir__,"CURRENT_MANIFEST.json"),32_768)
  need(Digest::SHA256.hexdigest(raw) == args[0], "reviewed manifest")
  manifest = JSON.parse(raw)
  need(manifest.fetch("scope") == "STABLE010_CANDIDATE_LINUX_NOT_HOST_ALLOW" &&
    manifest.fetch("ubuntu_openssl_policy") == UBUNTU_OPENSSL_POLICY, "manifest scope/provider policy")
  manifest.fetch("harness_files_sha256").each do |name,sha|
    need(%w[verify_package.rb installed_test.rb].include?(name), "harness path")
    need(Digest::SHA256.hexdigest(capture(File.join(__dir__,name),131_072)) == sha, "harness identity")
  end
  data = manifest.fetch("data_files_sha256").to_h do |name,sha|
    need(["research/stage15/results/R3/INPUTS.json","research/stage15_linux/EXPECTED.json"].include?(name), "data path")
    body = capture(File.join(ROOT,name),1_048_576)
    need(Digest::SHA256.hexdigest(body) == sha, "saved data identity")
    [name,body]
  end
  artifact = File.realpath(args[1])
  archive = capture(artifact,43_008)
  ref = manifest.fetch("candidate_artifact")
  need(ref.fetch("bytes") == 43_008 && ref.fetch("version") == "0.1.0" &&
    ref.fetch("sha256") == "0553645fa6c067dd8d7a7a1a7cdf13799370393e76dc3bc4ba161ab2ca5981b0" &&
    archive.bytesize == ref.fetch("bytes") &&
    Digest::SHA256.hexdigest(archive) == ref.fetch("sha256"), "published archive identity")
  package = Gem::Package.new(artifact)
  package.verify
  spec = package.spec
  expected = manifest.fetch("payload_sha256")
  names = expected.keys.sort
  libraries = names.grep(/\Alib\/.*\.rb\z/)
  need(names.size == 13 && libraries.size == 10 &&
    (names-libraries).sort == %w[LICENSE README.md docs/SUPPORT_CONTRACT.md], "exact13 reference")
  need(package.contents.sort == names && spec.files.sort == names &&
    spec.name == "ap2_mandate_verifier" && spec.version.to_s == "0.1.0" &&
    spec.platform == Gem::Platform::RUBY && spec.required_ruby_version.to_s == "= 4.0.9" &&
    spec.license == "MIT" && spec.extensions.empty? && spec.executables.empty? &&
    spec.require_paths == ["lib"] &&
    spec.runtime_dependencies.to_h { |d| [d.name,d.requirement.to_s] } == manifest.fetch("dependencies"),
    "archive whitelist/metadata")
  report = {scope:manifest.fetch("scope"),github_sha:ENV.fetch("GITHUB_SHA"),
    run_url:"https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/#{ENV.fetch("GITHUB_RUN_ID")}",
    run_attempt:ENV.fetch("GITHUB_RUN_ATTEMPT"),manifest_sha256:Digest::SHA256.hexdigest(raw),
    candidate_artifact:ref,product_reference_commit:manifest.fetch("product_reference_commit"),
    provider:provider,json_provider:json_provider,ruby_provider_archive:manifest.fetch("ruby_provider"),
    source_regressions:"NOT_RUN (885 omitted)",independent_oracle:"NOT_RERUN; saved MBA expectations"}
  work=File.join(ENV.fetch("STABLE010_WORK"),"package")
  Dir.mkdir(work)
  begin # Retain install/extraction until evidence is emitted/read back by the always step.
    extracted = File.join(work,"extracted"); installed = File.join(work,"installed")
    detached = File.join(work,"detached")
    FileUtils.mkdir_p([extracted,installed,detached])
    package.extract_files(extracted)
    hashes = names.to_h do |name|
      body = capture(File.join(extracted,name),131_072)
      need(Digest::SHA256.hexdigest(body) == expected.fetch(name), "pinned packaging payload mismatch")
      need(!body.match?(/-----BEGIN (?:EC |RSA |ENCRYPTED )?PRIVATE KEY-----/) &&
        !body.include?("/Users/"), "private content")
      [name,Digest::SHA256.hexdigest(body)]
    end
    # No Gem build. Install only the exact downloaded archive; dependencies already provisioned.
    ordinary = {"GEM_HOME"=>installed,"GEM_PATH"=>installed+File::PATH_SEPARATOR+ENV.fetch("GEM_PATH"),
      "RUBYOPT"=>nil,"RUBYLIB"=>nil}
    gem_cli = File.join(RbConfig::CONFIG.fetch("bindir"),"gem")
    child([RbConfig.ruby,gem_cli,"install","--norc","--local",artifact,"--install-dir",installed,
      "--ignore-dependencies","--no-document"],detached,ordinary,60)
    installed_root = File.join(installed,"gems","ap2_mandate_verifier-0.1.0")
    need(File.realpath(installed_root).start_with?(File.realpath(installed)+"/"), "installed path")
    names.each do |name|
      need(Digest::SHA256.hexdigest(capture(File.join(installed_root,name),131_072)) == expected.fetch(name),
        "installed payload mismatch")
    end
    audit_path = File.join(work,"package.json")
    File.binwrite(audit_path,JSON.generate(files_sha256:hashes))
    data_paths = data.to_h do |name,body|
      path = File.join(work,File.basename(name)); File.binwrite(path,body); [name,path]
    end
    observed = JSON.parse(child([RbConfig.ruby,File.join(__dir__,"installed_test.rb"),
      data_paths.fetch("research/stage15/results/R3/INPUTS.json"),
      data_paths.fetch("research/stage15_linux/EXPECTED.json"),audit_path,ROOT],detached,ordinary,300))
    need(observed.fetch("total_cases") == 52 && observed.fetch("installed_lib_files") == 10 &&
      observed.fetch("ordinary_entry") && observed.fetch("candidate_version") == "0.1.0" &&
      observed.fetch("dependencies").transform_values { |v| "= "+v } == manifest.fetch("dependencies") &&
      observed.fetch("provider_identity") == provider &&
      observed.fetch("json_provider_identity") == json_provider, "installed52/provider result")
    report.merge!(payload_files:13,payload_sha256:hashes,archive_installed_reference_match:true,installed:observed)
  end
  report[:holds] = "unpublished stable candidate only; E06 PARTIAL/OPEN; general AP2/production/Phase2B/Host atomic processing/resources unproved; prior acquisition and all-network128MiB gaps retained"
  text = JSON.pretty_generate(report)
  need(text.bytesize <= 131_072, "summary size")
  File.write(File.join(ENV.fetch("STABLE010_WORK"),"REPORT.json"),text+"\n")
  puts "STABLE010_REPORT_BEGIN"
  puts text
  puts "STABLE010_REPORT_END"
  File.open(ENV.fetch("GITHUB_STEP_SUMMARY"),"a") { |f| f.puts("https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/#{ENV.fetch("GITHUB_RUN_ID")}\n\n```json\n#{text}\n```") }
end
end

Stable010.main(ARGV) if $PROGRAM_NAME == __FILE__

