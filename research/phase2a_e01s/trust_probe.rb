# frozen_string_literal: true
# Isolated E01-S synthetic Host trust stages, NOT a Gem/API or business ALLOW.
require "json"
require "set"
require "digest"
require "base64"
require "jwt"
require_relative "synthetic_host_policy"

module AP2E01STrustProbe
  Rejected = AP2E01SHostPolicy::Rejected
  HOST = AP2E01SHostPolicy

  class << self
    def verify!(policy:, case_data:, policy_digest:)
      stage = "S0_PREAUTH_BOUNDS"
      root = case_data.fetch("root")
      terminal = case_data.fetch("terminal")
      candidate = case_data.fetch("candidate")
      reject!(stage, "INVALID_WIRE") unless root.is_a?(String) &&
        root.bytesize.between?(1, 32_768) && root.ascii_only? &&
        terminal.is_a?(String) && terminal.bytesize.between?(1, 32_768) &&
        terminal.ascii_only?
      reject!(stage, "INPUT_TOO_LARGE") if HOST.canonical({
        "Host" => policy, "root" => root, "terminal" => terminal,
        "candidate" => candidate
      }).bytesize > 131_072
      parts = root.split("~", -1)
      reject!(stage, "BAD_ROOT_SEGMENTS") unless parts.size.between?(3, 18) &&
        parts.last == "" && parts[1...-1].length.between?(1, 16)
      original_jws = parts.first
      header, signed = AP2StrictJSONResearch.validate_signed_jws_json!(original_jws)
      reject!(stage, "UNSUPPORTED_JOSE") unless header.is_a?(Hash) &&
        (header.keys - %w[alg typ kid]).empty? &&
        header["alg"] == "ES256" && header["typ"] == "example+sd-jwt" &&
        (header["kid"].nil? || header["kid"].is_a?(String))
      reject!(stage, "BAD_SIGNED_ROOT") unless signed.is_a?(Hash)

      # S1: untrusted case public key cannot replace the frozen Host A key.
      trusted = HOST.verify_candidate!(
        policy, candidate, case_policy_digest: policy_digest
      )
      stage = "S2_ISSUER_JWS"
      actual, = JWT.decode(
        original_jws, JWT::JWK.import(trusted).public_key, true,
        { algorithms: ["ES256"] }
      )
      reject!(stage, "SIGNATURE_PAYLOAD_MISMATCH") unless actual == signed

      # S3: independent Host grammar check on ORIGINAL signed Root, not on
      # a resolved Open returned by DC04 or the general Python SD helper.
      stage = "S3_HOST_SIGNED_GRAMMAR"
      enforce_original_graph!(signed, parts[1...-1], policy)

      # S4: reuse the existing, explicitly named DC04 resolver unchanged.
      stage = "S4_DC04_CHAIN_CHECKOUT"
      result = AP2DC04FixedIssuerResearch.verify!(
        **HOST.checkout_context(policy), chain: [root, terminal]
      )
      reject!(stage, "UNEXPECTED_AUTHORIZATION") unless
        result.is_a?(Hash) &&
        (result.keys & %i[allow approved authorized payment nonce_consumed]).empty? &&
        result[:checkout_id] == policy["expected_checkout_id"]
      {
        "status" => "LIMITED_POSITIVE", "last_stage" => stage,
        "reason" => nil, "host_trust_gate" => "OBSERVED",
        "checkout_id" => result.fetch(:checkout_id)
      }
    rescue Rejected => error
      { "status" => "REJECT", "first_reject_stage" => error.stage,
        "reason" => error.code, "host_trust_gate" => "OBSERVED" }
    rescue AP2RootSDJWTResearch::Rejected => error
      { "status" => "REJECT", "first_reject_stage" => "S4_DC04_CHAIN_CHECKOUT",
        "reason" => error.message, "host_trust_gate" => "NOT_TARGET_GUARD" }
    rescue JWT::DecodeError, JWT::JWKError => error
      { "status" => "REJECT", "first_reject_stage" => "S2_ISSUER_JWS",
        "reason" => "INVALID_SIGNATURE_#{error.class.name.split('::').last}",
        "host_trust_gate" => "NOT_TARGET_GUARD" }
    rescue JSON::ParserError, KeyError, TypeError, ArgumentError => error
      { "status" => "REJECT", "first_reject_stage" => "S0_PREAUTH_BOUNDS",
        "reason" => "INVALID_INPUT_#{error.class.name.split('::').last}",
        "host_trust_gate" => "NOT_TARGET_GUARD" }
    end

    private

    def reject!(stage, code)
      HOST.reject!(stage, code)
    end

    def decode_disclosure!(part)
      stage = "S3_HOST_SIGNED_GRAMMAR"
      reject!(stage, "INVALID_DISCLOSURE_BASE64URL") unless
        part.is_a?(String) && part.match?(/\A[A-Za-z0-9_-]+\z/)
      raw = Base64.urlsafe_decode64(part + ("=" * (-part.size % 4)))
      reject!(stage, "NONCANONICAL_DISCLOSURE") unless
        Base64.urlsafe_encode64(raw, padding: false) == part
      value = AP2StrictJSONResearch.parse!(raw)
      reject!(stage, "UNSUPPORTED_DISCLOSURE") unless value.is_a?(Array) &&
        value.length == 2 && value[0].is_a?(String) &&
        value[0].bytesize.between?(8, 128) && value[1].is_a?(Hash)
      value[1]
    rescue JSON::ParserError, ArgumentError => error
      reject!(stage, "INVALID_DISCLOSURE_#{error.class.name.split('::').last}")
    end

    def enforce_original_graph!(signed, disclosures, policy)
      stage = "S3_HOST_SIGNED_GRAMMAR"
      reject!(stage, "UNSUPPORTED_SIGNED_PROFILE") unless
        (signed.keys - %w[delegate_payload _sd_alg]).empty? &&
        [nil, "sha-256"].include?(signed["_sd_alg"]) &&
        signed["delegate_payload"].is_a?(Array) &&
        signed["delegate_payload"].size == 1
      mapping = {}
      disclosures.each do |disc|
        decoded = decode_disclosure!(disc)
        digest = Base64.urlsafe_encode64(
          Digest::SHA256.digest(disc.b), padding: false
        )
        reject!(stage, "DUPLICATE_DISCLOSURE") if mapping.key?(digest)
        mapping[digest] = decoded
      end
      consumed = Set.new
      observed = []
      walker = lambda do |value, path|
        reject!(stage, "DEPTH_EXCEEDED") if path.size > 24
        case value
        when Hash
          reject!(stage, "UNSUPPORTED_SIGNED_PROFILE") if
            value.key?("_sd") || value.key?("...")
          reject!(stage, "OBJECT_SIZE_EXCEEDED") if value.size > 32
          value.each { |key, child| walker.call(child, path + [key]) }
        when Array
          reject!(stage, "ARRAY_SIZE_EXCEEDED") if value.size > 16
          value.each_with_index do |child, i|
            here = path + [i]
            if child.is_a?(Hash) && child.key?("...")
              reject!(stage, "UNSUPPORTED_SIGNED_PROFILE") unless
                child.keys == ["..."] &&
                policy.fetch("allowed_sd_paths").include?("$/#{here.join('/')}")
              d = child["..."]
              reject!(stage, "INVALID_COMMITMENT_DIGEST") unless
                d.is_a?(String) && d.match?(/\A[A-Za-z0-9_-]{43}\z/)
              reject!(stage, "INCOMPLETE_DISCLOSURE") unless mapping.key?(d)
              reject!(stage, "REPEATED_COMMITMENT") if consumed.include?(d)
              consumed.add(d)
              observed << "$/#{here.join('/')}"
              walker.call(mapping.fetch(d), here + ["disclosed"])
            else
              walker.call(child, here)
            end
          end
        end
      end
      walker.call(signed, [])
      reject!(stage, "UNSUPPORTED_SIGNED_PROFILE") unless
        observed.sort == HOST::PINNED_PATHS
      reject!(stage, "UNUSED_DISCLOSURE") unless consumed.size == mapping.size
      true
    end
  end
end
