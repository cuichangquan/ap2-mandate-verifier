# frozen_string_literal: true
# Run after ordinary installation: ruby examples/input_builder.rb
require "ap2_mandate_verifier"
require "json"
require "tmpdir"

module InputBuilderExample
  DIRECTORY = File.expand_path("input_builder", __dir__)
  def self.read(name) = JSON.parse(File.binread(File.join(DIRECTORY, "#{name}.json")))

  # These public registration records are authenticated Host data in a real app.
  # They are NOT discovered from signed claims or a remote URL.
  def self.current_trust(now)
    AP2MandateVerifier::InputBuilder.trust(
      snapshot: read("trust_snapshot"), tenant_id: "synthetic-tenant",
      issuer: {"identity" => "issuer", "purpose" => "checkout", "key_ref" => "issuer-1"},
      agent: {"identity" => "agent", "purpose" => "checkout", "key_ref" => "agent-1"},
      merchant: {"identity" => "shop", "purpose" => "checkout", "key_ref" => "merchant-1"},
      verified_at: now)
  end

  def self.run(scenario = "valid")
    raise ArgumentError, "unknown scenario" unless %w[valid tampered expired].include?(scenario)
    builder = AP2MandateVerifier::InputBuilder
    wires = read("signed_wires") # Exact original Strings, including Root's final '~'.
    order_at_issue = read("order") # Independent order source, never token-derived.
    trust_at_issue = current_trust(1_800_000_000)
    prepared = builder.prepare(trust: trust_at_issue, order: order_at_issue,
      root_presentation: wires.fetch("root_presentation"),
      host_checkout_jws: wires.fetch("host_checkout_jws"),
      challenge_id: "synthetic-challenge", nonce: "n", issuer_id: "synthetic-host",
      not_before: 1_799_998_000, not_after: 1_800_002_000)

    # Application persistence; this demonstration uses a private temporary file.
    # Production must authenticate storage and issue/consume nonce atomically.
    Dir.mktmpdir("ap2-builder-example") do |directory|
      path = File.join(directory, "challenge.json")
      File.binwrite(path, prepared)
      restored = builder.restore(saved_challenge: File.binread(path))
      now = scenario == "expired" ? 1_800_000_101 : 1_800_000_000
      current_order = read("order") # Retrieve current Host state independently.
      current_order["expected_total"] = 999 if scenario == "tampered"
      result = builder.verify(trust: current_trust(now), saved_challenge: restored,
        order: current_order, **wires.transform_keys(&:to_sym),
        expected_challenge_issuer_id: "synthetic-host",
        clock_source_id: "fixed-synthetic-clock", verified_at: now)
      puts "#{scenario}: #{result.status}/#{result.code}; evidence=#{!result.evidence.nil?}"
      # A success gives checked facts. Host authorization/payment remains separate.
      result
    end
  end
end

InputBuilderExample.run(ARGV.fetch(0, "valid")) if $PROGRAM_NAME == __FILE__
