# frozen_string_literal: true
# Run in the task's Linux container after dependency installation, with network disabled.
require_relative "../test/runtime_dependencies"
require "rbconfig"
require "open3"
gem "bundler", "= 4.0.20"
require "bundler/version"
raise "Bundler baseline" unless Bundler::VERSION == "4.0.20"
raise "Linux only" unless RUBY_PLATFORM.include?("linux")
native = $LOADED_FEATURES.select { |f| File.basename(f) == "openssl.so" }
raise "OpenSSL extension identity" unless native.size == 1
maps = File.read("/proc/self/maps").lines.map { |l| l.split(" ", 6).last&.strip }.compact
crypto = maps.select { |p| p.match?(%r{/lib(?:ssl|crypto)\.so\.3\z}) }.uniq.sort
raise "mapped OpenSSL libraries" unless crypto.size == 2 &&
  crypto.map { |p| File.basename(p) }.sort == %w[libcrypto.so.3 libssl.so.3]
paths = [*native, *crypto]
packages, errors, status = Open3.capture3("dpkg-query", "-W", "-f=${Package}|${Version}|${Architecture}|${Status}\n", "libssl3*")
raise "native package identity" unless status.success? && errors.empty?
providers = packages.lines.map(&:strip).select do |record|
  fields = record.split("|", -1)
  fields.size == 4 && %w[libssl3 libssl3t64].include?(fields[0]) &&
    !fields[1].empty? && !fields[2].empty? && fields[3] == "install ok installed"
end
raise "native package selection" unless providers.size == 1
package = providers.first
fields = package.split("|", -1)
provider = "#{fields[0]}:#{fields[2]}"
files, errors, status = Open3.capture3("dpkg-query", "-L", provider)
raise "native package file list" unless status.success? && errors.empty?
owned_paths = files.lines.map(&:strip).filter_map { |p| File.realpath(p) if File.file?(p) }
raise "mapped OpenSSL package ownership" unless crypto.all? { |p| owned_paths.include?(File.realpath(p)) }
integrity, errors, status = Open3.capture3("dpkg", "--verify", provider)
raise "native package verification" unless status.success? && errors.empty? && integrity.empty?
puts JSON.pretty_generate(ruby: RUBY_DESCRIPTION, engine: RUBY_ENGINE, executable: RbConfig.ruby,
  platform: RUBY_PLATFORM, os: File.read("/etc/os-release"), bundler: Bundler::VERSION,
  dependencies: %w[json jwt base64 openssl digest].to_h { |n|
    s = Gem.loaded_specs.fetch(n)
    [n, {version: s.version.to_s, default_gem: s.default_gem?, path: s.full_gem_path}]
  }, compiled_openssl: OpenSSL::OPENSSL_VERSION, loaded_openssl: OpenSSL::OPENSSL_LIBRARY_VERSION,
  native_package: package.strip, native_package_verify: "PASS",
  native_files_sha256: paths.to_h { |p| [File.realpath(p), Digest::SHA256.file(p).hexdigest] })
