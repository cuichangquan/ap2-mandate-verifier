# frozen_string_literal: true
require_relative "runtime_dependencies"
require "ap2_mandate_verifier"
data = JSON.parse(File.read(ARGV.fetch(0)))
%w[direct conditional].each do |mode|
  args = data.fetch(mode).transform_keys(&:to_sym)
  args[:checkout_mode] = args.fetch(:checkout_mode).to_sym
  args[:checkout_inputs] = args.fetch(:checkout_inputs).transform_keys(&:to_sym)
  raise "Python Payment rejected: #{mode}" unless AP2MandateVerifier::Payment.verify(**args).verified?
end
data.fetch("receipts").each do |raw|
  args = raw.transform_keys(&:to_sym)
  result = AP2MandateVerifier::PaymentReceipt.verify(**args)
  raise "Python Receipt rejected" unless result.verified?
end
puts "PASS official Python SDK->Ruby: Direct, conditional with full existing Checkout verification, Success/Error Receipt for both"
