# frozen_string_literal: true
# Run in the task's Linux container after dependency installation, with network disabled.
require_relative "../test/runtime_dependencies"
require "rbconfig"
require "bundler/version"
raise "Bundler baseline" unless Bundler::VERSION == "4.0.20"
raise "Linux only" unless RUBY_PLATFORM.include?("linux")
native = $LOADED_FEATURES.select { |f| File.basename(f) == "openssl.so" }
raise "OpenSSL extension identity" unless native.size == 1
maps = File.read("/proc/self/maps").lines.map { |l| l.split(" ", 6).last&.strip }.compact
crypto = maps.select { |p| p.match?(%r{/lib(?:ssl|crypto)\.so\.3\z}) }.uniq.sort
raise "mapped OpenSSL libraries" unless crypto.size == 2
paths = [*native, *crypto]
puts JSON.pretty_generate(ruby: RUBY_DESCRIPTION, engine: RUBY_ENGINE, executable: RbConfig.ruby,
  platform: RUBY_PLATFORM, os: File.read("/etc/os-release"), bundler: Bundler::VERSION,
  dependencies: %w[json jwt base64 openssl digest].to_h { |n|
    s = Gem.loaded_specs.fetch(n)
    [n, {version: s.version.to_s, default_gem: s.default_gem?, path: s.full_gem_path}]
  }, compiled_openssl: OpenSSL::OPENSSL_VERSION, loaded_openssl: OpenSSL::OPENSSL_LIBRARY_VERSION,
  native_files_sha256: paths.to_h { |p| [File.realpath(p), Digest::SHA256.file(p).hexdigest] })
