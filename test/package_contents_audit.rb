# frozen_string_literal: true
require "rubygems/package"
require "fileutils"
gem "json", "= 2.19.9"
require "json"
require "digest"
package = Gem::Package.new(ARGV.fetch(0))
package.verify
spec = package.spec
files = package.contents.sort
expected = (Dir["lib/**/*.rb"] + %w[README.md LICENSE docs/SUPPORT_CONTRACT.md docs/DIAGNOSTICS.md docs/DIAGNOSTICS.ja.md docs/MERCHANT_SIGNING.md docs/MULTI_ITEM_CHECKOUT.md docs/BUYER_DIRECT_CHECKOUT.md]).sort
expected = (expected + %w[README.ja.md SECURITY.md docs/PUBLIC_API.md docs/INPUT_BUILDER.md docs/POST_RELEASE_MAINTENANCE.md docs/CONDITIONAL_CHECKOUT.md docs/RELEASE_100_CANDIDATE.md examples/conditional_checkout.rb]).sort
expected = (expected + %w[docs/PAYMENT.md docs/RELEASE_110_CANDIDATE.md examples/payment.rb]).sort
expected = (expected + %w[docs/SELECTIVE_PAYMENT.md docs/RELEASE_120_CANDIDATE.md examples/selective_payment.rb]).sort
expected = (expected + %w[docs/POST_RELEASE_110.md docs/evidence/1.1.0_publication.json]).sort
expected = (expected + %w[docs/SELECTIVE_CHECKOUT.md docs/RELEASE_130_CANDIDATE.md examples/selective_checkout.rb examples/selective_checkout_payment.rb]).sort
expected = (expected + %w[docs/PAYMENT_POLICY.md docs/RELEASE_140_CANDIDATE.md examples/payment_policy.rb]).sort
expected = (expected + %w[docs/PAYMENT_ACCEPTANCE.md docs/RELEASE_150_CANDIDATE.md examples/payment_acceptance.rb]).sort
expected = (expected + %w[docs/RECURRING_PAYMENT.md docs/RELEASE_160_CANDIDATE.md examples/recurring_payment.rb docs/LONG_PAYMENT.md examples/long_payment.rb examples/long_payment_acceptance.rb]).sort
expected = (expected + %w[examples/ruby_integration.rb examples/integration/inputs.rb examples/integration/processor.rb docs/RUBY_INTEGRATION.md docs/RUBY_INTEGRATION.ja.md]).sort
raise "package whitelist" unless files == expected && spec.extensions.empty?
versions = {"base64"=>"= 0.3.0","json"=>"= 2.19.9","jwt"=>"= 3.3.0","openssl"=>"= 4.0.2","digest"=>"= 3.2.1"}
raise "package metadata" unless spec.name == "ap2_mandate_verifier" && spec.version.to_s == "1.6.0" &&
  spec.required_ruby_version == Gem::Requirement.new(">= 3.4.12", "< 4.1") && spec.license == "MIT" &&
  spec.runtime_dependencies.to_h { |d| [d.name, d.requirement.to_s] } == versions
package.extract_files(ARGV.fetch(1))
hashes = files.to_h { |name| [name, Digest::SHA256.file(File.join(ARGV[1], name)).hexdigest] }
files.each do |name|
  raise "source/archive mismatch" unless hashes[name] == Digest::SHA256.file(name).hexdigest
  raise "installed mismatch" unless hashes[name] == Digest::SHA256.file(File.join(ARGV.fetch(2), name)).hexdigest
  raw = File.binread(File.join(ARGV[1], name))
  raise "private key/path" if raw.match?(/-----BEGIN (?:EC |RSA |ENCRYPTED )?PRIVATE KEY-----/) || raw.include?("/Users/")
end
puts JSON.pretty_generate(version:spec.version.to_s, required_ruby:spec.required_ruby_version.to_s,
  dependencies:versions, files:files, files_sha256:hashes,
  artifact_sha256:Digest::SHA256.file(ARGV[0]).hexdigest, artifact_bytes:File.size(ARGV[0]),
  native_extensions:spec.extensions, source_archive_installed_all_files_match:true)
