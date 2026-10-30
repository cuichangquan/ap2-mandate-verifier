# frozen_string_literal: true
# Test preflight only: use normal RubyGems activation, never source-path substitutes.
abort "unsupported test MRI" unless RUBY_ENGINE == "ruby" && %w[3.4.12 4.0.9].include?(RUBY_VERSION)
{"json"=>"2.19.9", "jwt"=>"3.3.0", "base64"=>"0.3.0",
 "openssl"=>"4.0.2", "digest"=>"3.2.1"}.each do |name, version|
  gem name, "= #{version}"
  require name
  raise "loaded dependency mismatch: #{name}" unless Gem.loaded_specs.fetch(name).version.to_s == version
end
