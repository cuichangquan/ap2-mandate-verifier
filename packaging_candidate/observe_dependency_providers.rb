require "ap2_mandate_verifier"
require "json"
require "digest"
require "openssl"
require "rbconfig"
Digest::SHA256.hexdigest("provider check")
roots={"ruby_stdlib"=>File.realpath(RbConfig::CONFIG.fetch("rubylibdir")),"ruby_archlib"=>File.realpath(RbConfig::CONFIG.fetch("archdir"))}
identities={}
$LOADED_FEATURES.each do |f|
  next unless f.start_with?("/") # built-in Ruby features have no on-disk provider
  absolute=File.realpath(f)
  roots.each do |label,root|
    next unless absolute.start_with?(root+"/")
    relative=absolute.delete_prefix(root+"/")
    supported=label=="ruby_stdlib" ? (relative=="digest.rb" || relative.start_with?("digest/")) : %w[digest.bundle digest/sha2.bundle].include?(relative)
    next unless supported
    key=label+"/"+relative
    raise "duplicate provider identity" if identities.key?(key)
    identities[key]=Digest::SHA256.file(absolute).hexdigest
  end
end
expected=%w[ruby_stdlib/digest.rb ruby_stdlib/digest/version.rb ruby_stdlib/digest/loader.rb ruby_stdlib/digest/sha2.rb ruby_stdlib/digest/sha2/loader.rb ruby_archlib/digest.bundle ruby_archlib/digest/sha2.bundle]
raise "missing/extra Digest provider" unless identities.keys.sort==expected.sort
raise "Digest provider version" unless Digest::VERSION==Gem.loaded_specs.fetch("digest").version.to_s
puts JSON.pretty_generate(ruby:RUBY_VERSION,engine:RUBY_ENGINE,dependencies:%w[json jwt base64 openssl digest].to_h{|n|s=Gem.loaded_specs.fetch(n);[n,{version:s.version.to_s,default:s.default_gem?,runtime_dependencies:s.runtime_dependencies.map{|d|[d.name,d.requirement.to_s]}}]},openssl_library:OpenSSL::OPENSSL_LIBRARY_VERSION,digest_loaded_files_sha256:identities,native_rebuild:false,new_dependency_installs:0,supersedes:"DEPENDENCY_PROVIDERS.json basename collision; historical incorrect digest.rb identity is not relied on")
