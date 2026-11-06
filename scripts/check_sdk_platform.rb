# frozen_string_literal: true
# Published artifact only: never substitute a current-source candidate or overlay.
raise "Ruby load path injection" unless ENV.fetch("RUBYLIB", "").empty? && ENV.fetch("RUBYOPT", "").empty?
require_relative "../test/runtime_dependencies"
require "rubygems/package"
require "tmpdir"
require "rbconfig"
require "ap2_mandate_verifier"

root = File.expand_path("..", __dir__)
record = JSON.parse(File.read(File.join(root, "docs/evidence/1.6.0_publication.json")))
artifact = ARGV.fetch(0)
raise "published artifact bytes" unless File.size(artifact) == record.fetch("bytes")
raise "published artifact SHA256" unless Digest::SHA256.file(artifact).hexdigest == record.fetch("sha256")
package = Gem::Package.new(artifact)
package.verify
spec = Gem.loaded_specs.fetch("ap2_mandate_verifier")
raise "published version" unless spec.version.to_s == "1.6.0" && package.spec.version == spec.version
raise "source overlay" if File.realpath(spec.full_gem_path).start_with?(root + File::SEPARATOR)
expected = record.fetch("payload_files_sha256")
raise "published payload closure" unless package.contents.sort == expected.keys.sort
Dir.mktmpdir("ap2-published-audit") do |dir|
  package.extract_files(dir)
  expected.each do |name, hash|
    [dir, spec.full_gem_path].each do |base|
      raise "published payload mismatch: #{name}" unless Digest::SHA256.file(File.join(base, name)).hexdigest == hash
    end
  end
end
installed_lib = File.realpath(File.join(spec.full_gem_path, "lib")) + File::SEPARATOR
loaded = $LOADED_FEATURES.select { |path| path.match?(%r{(?:\A|/)ap2_mandate_verifier(?:/|\.rb\z)}) }
raise "SDK entrypoint not loaded" unless loaded.any? { |path| File.basename(path) == "ap2_mandate_verifier.rb" }
loaded.each do |path|
  actual = File.realpath(path)
  raise "loaded source overlay" unless actual.start_with?(installed_lib)
  name = "lib/" + actual.delete_prefix(installed_lib)
  raise "loaded SDK hash" unless Digest::SHA256.file(actual).hexdigest == expected.fetch(name)
end
raise "Rails dependency" if spec.runtime_dependencies.any? { |d| %w[rails railties activerecord sqlite3].include?(d.name) }
raise "Rails loaded" if defined?(Rails) || Gem.loaded_specs.keys.any? { |n| %w[rails railties activerecord].include?(n) }
gem "sqlite3", "= 2.10.2"
require "sqlite3"
raise "SQLite version" unless SQLite3::VERSION == "2.10.2"
sqlite = Gem.loaded_specs.fetch("sqlite3")
expected_cpu = {"aarch64" => "aarch64", "x86_64" => "x86_64"}.fetch(RbConfig::CONFIG.fetch("host_cpu"))
raise "SQLite CPU mismatch" unless sqlite.platform.cpu == expected_cpu && sqlite.platform.os == "linux"
puts JSON.pretty_generate(
  artifact_kind: "published", version: spec.version.to_s, sha256: record.fetch("sha256"),
  payload_files_verified: expected.size, loaded_sdk_files_verified: loaded.size, ruby: RUBY_DESCRIPTION, platform: RUBY_PLATFORM,
  sqlite_version: SQLite3::VERSION, sqlite_platform: sqlite.platform.to_s,
  rails_loaded: false, source_overlay: false,
  scope: "Linux Gem-only; native/emulated classification requires runner/host evidence")
