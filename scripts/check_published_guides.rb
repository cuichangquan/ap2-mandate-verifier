# frozen_string_literal: true
require "ap2_mandate_verifier"
require "json"
require "open3"
abort "published 0.6.0 not installed" unless Gem.loaded_specs.fetch("ap2_mandate_verifier").version.to_s == "0.6.0"
root = File.expand_path("..", __dir__)
%w[README.md README.ja.md].each do |name|
  blocks = File.read(File.join(root, name)).scan(/```ruby\n(.*?)```/m).flatten
  quickstart = blocks.find { |b| b.include?('require "tmpdir"') }
  abort "missing quick start" unless quickstart
  output, error, status = Open3.capture3(Gem.ruby, "-e", "eval(ARGV[0], TOPLEVEL_BINDING, ARGV[1])", quickstart, File.join(root, "quick_start.rb"))
  abort "guide failed" unless status.success? && output.include?("verified_research/scoped_research_verified; evidence=true")
  puts "PASS installed published Gem #{name} quick start"
end
output, error, status = Open3.capture3(Gem.ruby, File.join(root, "examples/merchant_signing.rb"))
expected = ["checkout_segments=3 checkout_hash_length=43",
  "Success: verified=true purchase_succeeded=true purchase_rejected=false",
  "Error: verified=true purchase_succeeded=false purchase_rejected=true"]
abort "merchant example failed" unless status.success? && output.lines.map(&:strip) == expected
puts output
output, error, status = Open3.capture3(Gem.ruby, File.join(root, "examples/multi_item_checkout.rb"))
expected = ["checkout verified=true profile=ap2.checkout.single_merchant_multi_item",
  "receipt Success: verified=true purchase_succeeded=true", "receipt Error: verified=true purchase_succeeded=false"]
abort "multi-item example failed" unless status.success? && output.lines.first(3).map(&:strip) == expected
puts output
release = File.read(File.join(root, "docs/RELEASE_060.md")).scan(/```ruby\n(.*?)```/m).flatten.fetch(0)
prelude = <<~RUBY
  require "ap2_mandate_verifier"
  require #{File.join(root, "test/support/multi_item_fixture.rb").inspect}
  checkout = MultiItemFixture.checkout
  key = OpenSSL::PKey::EC.generate("prime256v1")
  signer = AP2MandateVerifier::CheckoutJWT.es256_signer(private_key: key)
  public_key_pem = key.public_to_pem
RUBY
output, error, status = Open3.capture3(Gem.ruby, "-e", prelude + release)
abort "Release snippet failed" unless status.success? && output.strip == "checkout_segments=3"
puts output
puts "PASS installed published 0.6.0 guides and Release snippet; no Gem build"
