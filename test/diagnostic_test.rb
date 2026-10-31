# frozen_string_literal: true
# Also usable against an ordinarily installed gem with AP2_INSTALLED=1.
if ENV["AP2_INSTALLED"]
  require "ap2_mandate_verifier"
  require "json"
else
  require_relative "runtime_dependencies"
  require_relative "../lib/ap2_mandate_verifier"
end

module DiagnosticTest
  B = AP2MandateVerifier::InputBuilder
  D = AP2MandateVerifier::Diagnostic
  @count = 0
  def self.need(ok, message)
    raise "diagnostic: #{message}" unless ok
    @count += 1
  end
  def self.check_failure(args, field, reason)
    result = B.verify(**args)
    need([result.status, result.code, result.success?, result.evidence] == [:rejected, :invalid_host_context, false, nil], "unchanged rejected contract")
    d = result.diagnostic
    need(d && [d.stage, d.field, d.reason] == [:input_assembly, field, reason], "precise builder diagnostic #{field}/#{reason}")
    need(d.frozen? && d.to_h.frozen? && d.hint.frozen? && d.hint(locale: :ja).frozen? && d.dup.equal?(d) && d.clone(freeze: false).equal?(d), "immutable guidance")
    d
  end
  directory = File.expand_path("../examples/input_builder", __dir__)
  read = ->(name) { JSON.parse(File.binread(File.join(directory, "#{name}.json"))) }
  trust_args = {snapshot: read.call("trust_snapshot"), tenant_id: "synthetic-tenant",
    issuer: {"identity" => "issuer", "purpose" => "checkout", "key_ref" => "issuer-1"},
    agent: {"identity" => "agent", "purpose" => "checkout", "key_ref" => "agent-1"},
    merchant: {"identity" => "shop", "purpose" => "checkout", "key_ref" => "merchant-1"}, verified_at: 1_800_000_000}
  trust = B.trust(**trust_args)
  order = read.call("order")
  wires = read.call("signed_wires").transform_keys(&:to_sym)
  saved = B.prepare(trust: trust, order: order, **wires.slice(:root_presentation, :host_checkout_jws),
    challenge_id: "synthetic-challenge", nonce: "n", issuer_id: "synthetic-host",
    not_before: 1_799_998_000, not_after: 1_800_002_000)
  args = {trust: trust, order: order, saved_challenge: saved, **wires,
    expected_challenge_issuer_id: "synthetic-host", clock_source_id: "fixed-synthetic-clock", verified_at: 1_800_000_000}
  need(B.verify(**args).success? && B.verify(**args).diagnostic.nil?, "success unchanged and no failure guidance")
  check_failure(args.merge(order: order.reject { |k,_| k == "currency" }), "order.currency", :missing_required_field)
  check_failure(args.merge(order: order.merge("currency" => nil)), "order.currency", :invalid_type)
  check_failure(args.merge(order: order.merge("expected_total" => "200")), "order.expected_total", :invalid_type)
  check_failure(args.merge(order: nil), "order", :invalid_type)
  check_failure(args.merge(order: order.merge("currency" => "XX")), "order.currency", :invalid_value)
  secret = "SECRET_DIAGNOSTIC_MARKER_4389"
  check_failure(args.merge(order: order.merge(secret => secret)), "order", :unknown_field)
  check_failure(args.merge(order: order.merge("currency" => secret)), "order.currency", :invalid_value)
  check_failure(args.reject { |k,_| k == :terminal_jws }, "arguments", :missing_required_field)
  check_failure(args.merge(secret.to_sym => secret), "arguments", :unknown_field)
  future = JSON.parse(saved).merge("format_version" => secret)
  check_failure(args.merge(saved_challenge: JSON.generate(future)), "saved_challenge", :unsupported_saved_format)
  %w[profile_ref profile_version].each do |field|
    future = JSON.parse(saved).merge(field => secret)
    check_failure(args.merge(saved_challenge: JSON.generate(future)), "saved_challenge", :unsupported_saved_format)
  end
  begin
    B.restore(saved_challenge: JSON.generate(future))
    raise "expected Invalid"
  rescue B::Invalid => error
    need(error.diagnostic.reason == :unsupported_saved_format && error.cause.nil?, "pure helper diagnostic and no parser cause")
    need(!error.full_message.include?(secret), "sanitized exception")
  end
  [[], {}, Object.new, Class.new(String).new("JPY")].each do |bad|
    r = B.verify(**args.merge(order: order.merge("currency" => bad)))
    need(!r.success? && r.evidence.nil? && r.diagnostic, "odd type fail closed")
  end
  %i[trust restore_trust prepare restore inputs].each do |method|
    begin
      B.public_send(method, secret.to_sym => secret)
      raise "expected sanitized keyword failure"
    rescue B::Invalid => error
      need(!error.full_message.include?(secret), "keyword exception redaction #{method}")
      need(error.diagnostic.reason == :missing_required_field, "missing keyword diagnostic #{method}")
    end
  end
  # These controls have independent expected result codes from the existing API.
  drift = B.verify(**args.merge(order: order.merge("expected_total" => 201)))
  need(drift.code == :host_binding_mismatch && drift.diagnostic.stage == :host_binding, "current/saved mismatch")
  expired = B.verify(**args.merge(verified_at: 1_800_000_101))
  need(expired.code == :invalid_purchase_time && expired.diagnostic.hint.include?("independent clock"), "time check not cause assertion")
  AP2MandateVerifier::Result::CODES.each do |status, codes|
    codes.each do |code|
      r = AP2MandateVerifier::Result.new(status: status, code: code)
      d = r.diagnostic
      need(d && d.hint && d.hint(locale: :ja) && !r.success? && r.evidence.nil?, "all registered codes #{code}")
      need(d.field.nil?, "do not invent exact field from code")
      need(d.stage == :verification_unavailable, "unavailable distinct") if status == :unavailable
    end
  end
  unknown = D.for_result(:unavailable, secret)
  need(unknown.reason == :undetermined && !unknown.inspect.include?(secret), "unknown code not echoed")
  need(D.builder(secret, secret).field.nil? && D.builder(secret, secret).reason == :invalid_builder_input, "allowlist fallback")
  # Diagnostics must not retain a raw order, arbitrary field name or values.
  malformed = [args.merge(order: order.merge(secret => secret)), args.merge(order: order.merge("currency" => secret)),
    args.merge(saved_challenge: secret), args.merge(trust: secret)]
  malformed.each do |input|
    result = B.verify(**input)
    need(!result.success? && result.evidence.nil?, "secret malformed fail closed")
    need(![result.inspect, result.diagnostic.inspect, result.diagnostic.to_h.inspect].join.include?(secret), "no diagnostic input echoes")
  end
  # Fault injection occurs after a verdict, not in the verification pipeline.
  original = D.method(:for_result)
  D.define_singleton_method(:for_result) { |*| raise secret }
  begin
    r = AP2MandateVerifier.verify_checkout
    need([r.status, r.code, r.success?, r.evidence, r.diagnostic] == [:unavailable, :research_verification_unavailable, false, nil, nil], "catalog fault cannot change outcome")
  ensure
    D.define_singleton_method(:for_result, original)
  end
  builder_original = D.method(:builder)
  validator = AP2MandateVerifier::InputValidator
  snapshot_original = validator.method(:snapshot!)
  D.define_singleton_method(:builder) { |*| raise secret }
  validator.define_singleton_method(:snapshot!) { |*_, **_| raise ArgumentError, secret }
  begin
    r = B.verify(**args)
    need([r.status, r.code, r.success?, r.evidence] == [:rejected, :invalid_host_context, false, nil], "catalog fault inside ArgumentError rescue cannot leak")
  ensure
    D.define_singleton_method(:builder, builder_original)
    validator.define_singleton_method(:snapshot!, snapshot_original)
  end
  validator = AP2MandateVerifier::InputValidator
  original = validator.method(:snapshot!)
  [AP2MandateVerifier::RootSignature::Unavailable.new(:signature_dependency_unavailable),
   AP2MandateVerifier::InputValidator::Unavailable.new(:json_dependency_unavailable), LoadError.new(secret), RuntimeError.new(secret)].each do |fault|
    validator.define_singleton_method(:snapshot!) { |*_, **_| raise fault }
    begin
      r = B.verify(**args)
      need(r.unavailable? && !r.success? && r.evidence.nil? && r.diagnostic.stage == :verification_unavailable, "dependency failure not rejected")
      need(!r.inspect.include?(secret) && !r.diagnostic.inspect.include?(secret), "fault details withheld")
    ensure
      validator.define_singleton_method(:snapshot!, original)
    end
  end
  puts "PASS #{@count} diagnostic checks; no Host ALLOW claim"
end
