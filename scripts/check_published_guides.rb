# frozen_string_literal: true
require "ap2_mandate_verifier"
require "json"
require "open3"
spec = Gem.loaded_specs.fetch("ap2_mandate_verifier")
abort "published 1.6.0 not installed" unless spec.version.to_s == "1.6.0"
root = File.expand_path("..", __dir__)
# The native published harness audits each guide process as well as this parent.
ruby_command = [Gem.ruby]
ruby_command += ["-r", File.join(__dir__, "check_native_published.rb")] if ENV["AP2_NATIVE_CHILD"] == "1"
abort "source library loaded" if File.realpath(spec.full_gem_path).start_with?(root + "/")
%w[README.md README.ja.md].each do |name|
  blocks = File.read(File.join(root, name)).scan(/```ruby\n(.*?)```/m).flatten
  quickstart = blocks.find { |b| b.include?('require "tmpdir"') }
  abort "missing quick start" unless quickstart
  output, error, status = Open3.capture3(*ruby_command, "-e", "eval(ARGV[0], TOPLEVEL_BINDING, ARGV[1])", quickstart, File.join(root, "quick_start.rb"))
  abort "guide failed" unless status.success? && output.include?("verified_research/scoped_research_verified; evidence=true")
  puts "PASS installed published Gem #{name} quick start"
end
output, error, status = Open3.capture3(*ruby_command, File.join(root, "examples/merchant_signing.rb"))
expected = ["checkout_segments=3 checkout_hash_length=43",
  "Success: verified=true purchase_succeeded=true purchase_rejected=false",
  "Error: verified=true purchase_succeeded=false purchase_rejected=true"]
abort "merchant example failed" unless status.success? && output.lines.map(&:strip) == expected
puts output
output, error, status = Open3.capture3(*ruby_command, File.join(root, "examples/multi_item_checkout.rb"))
expected = ["checkout verified=true profile=ap2.checkout.single_merchant_multi_item",
  "receipt Success: verified=true purchase_succeeded=true", "receipt Error: verified=true purchase_succeeded=false"]
abort "multi-item example failed" unless status.success? && output.lines.first(3).map(&:strip) == expected
puts output
output, error, status = Open3.capture3(*ruby_command, File.join(root, "examples/direct_checkout.rb"))
abort "Direct example failed" unless status.success? && output.lines.map(&:strip) == [
  "Direct checkout verified; application acceptance receipt verified; applied once=true",
  "Unknown outcome held for application reconciliation; no payment performed"]
puts output
installed_example = File.join(spec.full_gem_path, "examples/conditional_checkout.rb")
output, error, status = Open3.capture3(*ruby_command, installed_example)
abort "installed conditional example failed" unless status.success? && output.lines.map(&:strip) == [
  "Open -> Agent Closed -> merchant evidence: verified=true; rows=3; requirements=2",
  "Receipt Success: authentic=true; purchase_succeeded=true",
  "Receipt Error: authentic=true; purchase_succeeded=false",
  "Success=consumed; Error=policy decision; missing Receipt/uncertain commit=pending",
  "Synthetic only; evidence and Receipt authenticity are not payment completion."]
puts output
# The 0.8.0 conditional flow remains the canonical sample for the unchanged 1.1.0 API.
release = File.read(File.join(root, "docs/RELEASE_080.md")).scan(/```ruby\n(.*?)```/m).flatten.fetch(0)
prelude = <<~RUBY
  require "ap2_mandate_verifier"
  require "stringio"
  require #{installed_example.inspect}
  original_output = $stdout
  begin
    $stdout = StringIO.new
    model = ConditionalCheckoutExample.run
  ensure
    $stdout = original_output
  end
  provider, agent, merchant = model.fetch(:keys)
  approved_merchant = model.fetch(:checkout).fetch("merchant")
  approved_requirements = model.fetch(:requirements)
  trust = model.fetch(:host_inputs).fetch(:trust)
  host_order = model.fetch(:host_inputs).fetch(:order)
  host_audience = host_order.fetch("audience")
  host_nonce = "synthetic-host-nonce"
  challenge_id = "synthetic-challenge-1"
  checkout_jwt = model.fetch(:closed).checkout_jwt
  provider_public_key = provider.public_to_pem
  provider_signer = AP2MandateVerifier::CheckoutJWT.es256_signer(private_key: provider)
  agent_public_key = agent.public_to_pem
  agent_signer = AP2MandateVerifier::CheckoutJWT.es256_signer(private_key: agent)
  merchant_public_key = merchant.public_to_pem
  merchant_signer = AP2MandateVerifier::CheckoutJWT.es256_signer(private_key: merchant)
  now = 1_800_000_000
RUBY
output, error, status = Open3.capture3(*ruby_command, "-e", prelude + release)
abort "Release snippet failed" unless status.success? && output.lines.map(&:strip) == ["Conditional verified=true", "Receipt verified=true purchase_succeeded=false"]
puts output
puts "PASS installed published 1.6.0 guides, standalone conditional example and retained 0.8.0 flow; no Gem build"

installed_payment = File.join(spec.full_gem_path, "examples/payment.rb")
output, error, status = Open3.capture3(*ruby_command, installed_payment)
abort "installed Payment example failed" unless status.success? &&
  output.include?("Direct and conditional Payment: verified; no execution permission granted") &&
  output.scan("Payment Receipt Success: authentic=true; reported_success=true").size == 2 &&
  output.scan("Payment Receipt Error: authentic=true; reported_success=false").size == 2 &&
  output.include?("Missing/invalid Receipt = pending; no automatic retry.")
puts output
puts "PASS installed published 1.6.0 Payment Direct/conditional and both Receipt outcomes; no source overlay"

installed_selective = File.join(spec.full_gem_path, "examples/selective_payment.rb")
output, error, status = Open3.capture3(*ruby_command, installed_selective)
retained = output.lines.find { |line| line.start_with?("Retained locally:") }
sent = output.lines.find { |line| line.start_with?("Sent:") }
abort "installed selective Payment example failed" unless status.success? &&
  retained&.include?("disclosures=5;") && sent&.include?("disclosures=3;") &&
  output.include?("Issuer JWT unchanged=true; presentation bytes changed=true") &&
  output.include?("Selected Payment verified=true; unselected candidate values/disclosures were not sent") &&
  output.scan("Payment Receipt Success: authentic=true; reported_success=true").size == 1 &&
  output.scan("Payment Receipt Error: authentic=true; reported_success=false").size == 1
puts output
puts "PASS installed published1.6.0 selective Payment retained/transmitted comparison and Receipts; no source overlay"

%w[selective_checkout selective_checkout_payment].each do |example|
  output, error, status = Open3.capture3(*ruby_command, File.join(spec.full_gem_path, "examples", "#{example}.rb"))
  abort "published selective Checkout example failed" unless status.success? &&
    output.include?("Checkout retained full disclosures=6; sent=4") &&
    output.include?("issuer JWT unchanged=true; unselected candidate values not sent") &&
    output.include?("Receipt Success: authentic=true") && output.include?("Receipt Error: authentic=true")
  abort "combined Payment example failed" if example.end_with?("payment") &&
    !(output.include?("Selected Payment verified=true") && output.include?("Payment Receipt Error: authentic=true"))
  puts "PASS physically installed published1.6.0 #{example}; no source overlay or Gem build"
end

output, error, status = Open3.capture3(*ruby_command, File.join(spec.full_gem_path, "examples/payment_policy.rb"))
abort "published Payment policy example failed" unless status.success? &&
  output.include?("Direct: approved PISP/date verified; wrong independent PISP/time rejected") &&
  output.include?("Conditional: allowed PISP/inclusive window verified; outside window rejected") &&
  output.include?("Selective: Checkout and Payment verified") &&
  output.include?("Success/Error Payment Receipts authenticated for all three modes")
puts "PASS physically installed published1.6.0 PISP/date profiles, three modes, negatives and Receipts; no source overlay or Gem build"

output, error, status = Open3.capture3(*ruby_command, File.join(spec.full_gem_path, "examples/payment_acceptance.rb"))
abort "published acceptance recovery example failed" unless status.success? &&
  output.include?("After reopen=unknown; original processor key available for QUERY; mock dispatches=1") &&
  output.include?("Delayed original-wire Receipt=receipt_success; reconciliation grants no Ticket") &&
  output.include?("no payment performed.")
puts "PASS physically installed published1.6.0 atomic acceptance, unknown recovery and original Receipt; no source overlay"

output, error, status = Open3.capture3(*ruby_command, File.join(spec.full_gem_path, "examples/long_payment_acceptance.rb"))
abort "published long Payment example failed" unless status.success? &&
  output.include?("12 explicit leap-year periods, 12 mock starts, reserved96000JPY within100000JPY") &&
  output.include?("original Receipts reconciled without new Tickets") &&
  output.include?("not generic AP2 MONTHLY semantics.")
puts "PASS physically installed published1.6.0 long Open twelve-month JPY lifecycle; synthetic only"
