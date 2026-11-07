# frozen_string_literal: true
# Published archive and ordinary installed RubyGems paths only; never a source candidate.
raise "Ruby load path injection" unless ENV.fetch("RUBYLIB", "").empty? && ENV.fetch("RUBYOPT", "").empty?
require_relative "../test/runtime_dependencies"
require "rubygems/package"
require "tmpdir"
require "rbconfig"
require "open3"
require "ap2_mandate_verifier"

module NativePublishedAudit
  ROOT = File.realpath(File.expand_path("..", __dir__)).tr("\\", "/")
  RECORD = JSON.parse(File.read(File.join(ROOT, "docs/evidence/1.6.0_publication.json")))
  SPEC = Gem.loaded_specs.fetch("ap2_mandate_verifier")
  INSTALLED = File.realpath(SPEC.full_gem_path).tr("\\", "/")
  EXPECTED = RECORD.fetch("payload_files_sha256")
  def self.loaded!
    paths = $LOADED_FEATURES.select { |p| p.tr("\\", "/").match?(%r{(?:\A|/)ap2_mandate_verifier(?:/|\.rb\z)}) }
    raise "SDK entrypoint absent" unless paths.any? { |p| File.basename(p) == "ap2_mandate_verifier.rb" }
    paths.each do |path|
      actual = File.realpath(path).tr("\\", "/")
      raise "loaded source overlay" unless actual.start_with?(INSTALLED + "/lib/")
      raise "loaded SDK hash" unless Digest::SHA256.file(actual).hexdigest == EXPECTED.fetch(actual.delete_prefix(INSTALLED + "/"))
    end
    raise "Rails loaded" if defined?(Rails) || Gem.loaded_specs.keys.any? { |n| %w[rails railties activerecord].include?(n) }
    paths.size
  end
  def self.run(path, *args)
    output, error, status = Open3.capture3({"AP2_NATIVE_CHILD" => "1", "AP2_INSTALLED" => "1"},
      Gem.ruby, "-r", File.expand_path(__FILE__), path, *args)
    puts output
    warn error unless error.empty?
    raise "native check failed: #{File.basename(path)}" unless status.success?
  end
end
A = NativePublishedAudit
raise "unsupported native target" unless %w[macos windows].include?(ENV.fetch("AP2_NATIVE_OS"))
raise "wrong exact MRI" unless RUBY_VERSION == ENV.fetch("AP2_NATIVE_RUBY")
expected_os = ENV.fetch("AP2_NATIVE_OS")
raise "Ruby OS mismatch" unless expected_os == "macos" ? RUBY_PLATFORM.include?("darwin") : RUBY_PLATFORM.include?("mingw-ucrt")
expected_cpu = ENV.fetch("AP2_NATIVE_CPU")
actual_cpu = RbConfig::CONFIG.fetch("host_cpu")
raise "Ruby CPU mismatch" unless {"ARM64" => %w[arm64 aarch64], "X64" => %w[x64 x86_64]}.fetch(expected_cpu).include?(actual_cpu)
raise "runner CPU mismatch" unless ENV.fetch("RUNNER_ARCH") == expected_cpu
raise "published version" unless A::SPEC.version.to_s == "1.6.0"
raise "source installation" if A::INSTALLED.start_with?(A::ROOT + "/")
raise "unexpected installed path" unless A::INSTALLED.start_with?(File.realpath(ENV.fetch("GEM_HOME")).tr("\\", "/") + "/")
raise "Rails/SQLite runtime dependency" if A::SPEC.runtime_dependencies.any? { |d| %w[rails railties activerecord sqlite3].include?(d.name) }
A.loaded!
# Every child audits again after its test/example, including libraries loaded late.
at_exit { A.loaded! }
if ENV["AP2_NATIVE_CHILD"] != "1"
  artifact = ENV.fetch("AP2_PUBLISHED_GEM")
  raise "published bytes" unless File.size(artifact) == A::RECORD.fetch("bytes")
  raise "published SHA256" unless Digest::SHA256.file(artifact).hexdigest == A::RECORD.fetch("sha256")
  package = Gem::Package.new(artifact)
  package.verify
  raise "published package name/version" unless package.spec.name == A::SPEC.name && package.spec.version == A::SPEC.version
  raise "payload closure" unless package.contents.sort == A::EXPECTED.keys.sort
  Dir.mktmpdir("ap2-native-audit") do |dir|
    package.extract_files(dir)
    A::EXPECTED.each do |name, hash|
      [dir, A::INSTALLED].each do |base|
        raise "payload mismatch: #{name}" unless Digest::SHA256.file(File.join(base, name)).hexdigest == hash
      end
      # Reused source test fixtures/examples must be identical to the released ones.
      if name.start_with?("examples/")
        raise "example drift: #{name}" unless Digest::SHA256.file(File.join(A::ROOT, name)).hexdigest == hash
      end
    end
  end
  extensions = $LOADED_FEATURES.select { |p| p.match?(%r{/(?:openssl|digest|sha2|parser)\.(?:so|bundle|dll)\z}) }
  puts JSON.pretty_generate(artifact_kind: "published", version: A::SPEC.version.to_s,
    sha256: A::RECORD.fetch("sha256"), payload_files_verified: A::EXPECTED.size,
    loaded_sdk_files_verified: A.loaded!, ruby: RUBY_DESCRIPTION, platform: RUBY_PLATFORM,
    runner_os: ENV.fetch("RUNNER_OS"), runner_arch: ENV.fetch("RUNNER_ARCH"), host_cpu: actual_cpu,
    image_os: ENV["ImageOS"], image_version: ENV["ImageVersion"],
    dependencies: %w[json jwt base64 openssl digest].to_h { |n| [n, Gem.loaded_specs.fetch(n).version.to_s] },
    compiled_openssl: OpenSSL::OPENSSL_VERSION, loaded_openssl: OpenSSL::OPENSSL_LIBRARY_VERSION,
    native_extensions_sha256: extensions.to_h { |p| [p, Digest::SHA256.file(p).hexdigest] },
    provider_package_audit: "NOT_RUN: not the Linux dpkg/mapped-library audit",
    rails_loaded: false, source_overlay: false)
  case ARGV.fetch(0)
  when "core"
    raise "SQLite unexpectedly installed" unless Gem::Specification.find_all_by_name("sqlite3").empty?
    raise "SQLite loaded" if defined?(SQLite3)
    %w[conditional_checkout payment selective_payment selective_checkout selective_checkout_payment payment_policy long_payment].each do |name|
      A.run(File.join(A::INSTALLED, "examples", "#{name}.rb"))
    end
    %w[payment selective_payment selective_checkout payment_policy long_payment payment_constraint_regression].each do |name|
      A.run(File.join(A::ROOT, "test", "#{name}_test.rb"))
    end
    puts "PASS native published core, seven installed examples and six regression suites; no Rails/SQLite"
  when "persistence"
    gem "sqlite3", "= 2.10.2"
    require "sqlite3"
    sqlite = Gem.loaded_specs.fetch("sqlite3")
    raise "SQLite version/platform" unless SQLite3::VERSION == "2.10.2" && sqlite.platform.to_s == ENV.fetch("AP2_SQLITE_PLATFORM")
    puts JSON.pretty_generate(sqlite_version: SQLite3::VERSION, sqlite_platform: sqlite.platform.to_s,
      sqlite_library_version: SQLite3::SQLITE_VERSION,
      sqlite_extensions_sha256: $LOADED_FEATURES.grep(/sqlite3_native\.(so|bundle|dll)\z/).to_h { |p| [p, Digest::SHA256.file(p).hexdigest] })
    A.run(File.join(A::ROOT, "scripts/check_published_guides.rb"))
    A.run(File.join(A::ROOT, "test/long_payment_acceptance_test.rb"))
    puts "PASS native optional SQLite guides, 12 months/96000JPY and budget rejection/state preservation"
  else
    raise "unknown native check mode"
  end
end
