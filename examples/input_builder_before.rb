# frozen_string_literal: true
# Equivalent seven-input path before InputBuilder; same independent fixture files.
require "ap2_mandate_verifier"
require "json"
require "digest"
require "tmpdir"

module InputBuilderBefore
  DIRECTORY = File.expand_path("input_builder", __dir__)
  def self.read(name) = JSON.parse(File.binread(File.join(DIRECTORY, "#{name}.json")))
  def self.trust
    profile = AP2MandateVerifier::TrustContext
    snapshot = read("trust_snapshot")
    snapshot.fetch("records").each do |record|
      record.merge!("profile_ref" => profile::PROFILE_REF,
        "profile_version" => profile::PROFILE_VERSION, "algorithm" => "ES256",
        "key_fingerprint" => Digest::SHA256.hexdigest(record.fetch("public_key_pem")))
    end
    body = JSON.generate(snapshot)
    content_hash = Digest::SHA256.hexdigest(body)
    trust = {"snapshot" => {"id" => snapshot.fetch("id"),
      "policy_version" => snapshot.fetch("policy_version"), "content_hash" => content_hash, "body" => body},
      "profile" => {"profile_ref" => profile::PROFILE_REF, "version" => profile::PROFILE_VERSION,
        "definition_hash" => profile::PROFILE_HASH, "body" => profile::PROFILE_BODY}}
    selection = {"trust_snapshot_id" => snapshot.fetch("id"),
      "policy_version" => snapshot.fetch("policy_version"), "trust_content_hash" => content_hash,
      "profile_ref" => profile::PROFILE_REF, "profile_version" => profile::PROFILE_VERSION,
      "profile_definition_hash" => profile::PROFILE_HASH, "tenant_id" => "synthetic-tenant",
      "Issuer" => {"identity" => "issuer", "purpose" => "checkout", "key_ref" => "issuer-1"},
      "Agent" => {"identity" => "agent", "purpose" => "checkout", "key_ref" => "agent-1"},
      "Merchant" => {"identity" => "shop", "purpose" => "checkout", "key_ref" => "merchant-1"}}
    [JSON.generate(trust), JSON.generate(selection), snapshot]
  end
  def self.binding(order, wires, snapshot)
    agent = snapshot.fetch("records").find { |record| record.fetch("role") == "Agent" }
    order.merge("profile_ref" => AP2MandateVerifier::TrustContext::PROFILE_REF,
      "profile_version" => AP2MandateVerifier::TrustContext::PROFILE_VERSION,
      "approved_agent_key_fingerprint" => agent.fetch("key_fingerprint"),
      "root_presentation_digest" => Digest::SHA256.hexdigest(wires.fetch("root_presentation")),
      "checkout_jwt_digest" => Digest::SHA256.hexdigest(wires.fetch("host_checkout_jws")))
  end
  def self.run
    wires = read("signed_wires")
    trust_json, selection_json, snapshot_at_issue = trust
    selection = JSON.parse(selection_json)
    issued_binding = binding(read("order"), wires, snapshot_at_issue)
    challenge = {"challenge_id" => "synthetic-challenge", "nonce" => "n", "issuer_id" => "synthetic-host",
      "B" => issued_binding, "not_before" => 1_799_998_000, "not_after" => 1_800_002_000, "state" => "issued"}
    %w[trust_snapshot_id policy_version trust_content_hash profile_definition_hash].each do |field|
      challenge[field] = selection.fetch(field)
    end
    Dir.mktmpdir("ap2-before-example") do |directory|
      path = File.join(directory, "challenge.json")
      File.binwrite(path, JSON.generate(challenge))
      saved_challenge = JSON.parse(File.binread(path))
      trust_json, selection_json, current_snapshot = trust
      current_binding = binding(read("order"), wires, current_snapshot)
      host_json = JSON.generate("binding" => current_binding, "challenge" => saved_challenge,
        "expected_challenge_issuer_id" => "synthetic-host", "clock_source_id" => "fixed-synthetic-clock")
      result = AP2MandateVerifier.verify_checkout(trust_json:, selection_json:, host_json:,
        **wires.transform_keys(&:to_sym), verified_at: 1_800_000_000)
      puts "before: #{result.status}/#{result.code}; evidence=#{!result.evidence.nil?}"
      result
    end
  end
end
InputBuilderBefore.run if $PROGRAM_NAME == __FILE__
