# frozen_string_literal: true
require "digest"

module AP2MandateVerifier
  # Authenticated Host assertions, never token-selected registration. No I/O.
  module TrustContext
    PROFILE_BODY = '{"profile_ref":"ap2.checkout.single_merchant_sku","version":"1","ap2_source":"b4587ac1d055888a73b4b21750973cffba961793","subset_source":"027ed4734af47c8289dbcb837373bb6086463ec4","algorithm":"ES256","key_format":"canonical-public-SPKI-P256-SHA256","root_type":"example+sd-jwt","terminal_type":"kb+sd-jwt","checkout_type":"JWT","disclosure_positions":["delegate_payload[0]","delegate_payload[0].constraints[0].items[0].acceptable_items[0]","delegate_payload[0].constraints[1].allowed[0]"],"constraints":["checkout.line_items","checkout.allowed_merchants"]}'.freeze
    PROFILE_REF = "ap2.checkout.single_merchant_sku"
    PROFILE_VERSION = "1"
    PROFILE_HASH = Digest::SHA256.hexdigest(PROFILE_BODY).freeze
    ROLES = {"Issuer" => :trusted_issuer_public_key_pem,
             "Agent" => :expected_agent_public_key_pem,
             "Merchant" => :trusted_merchant_public_key_pem}.freeze
    RECORD_FIELDS = %w[role identity tenant_id purpose key_ref profile_ref profile_version public_key_pem key_fingerprint algorithm active not_before not_after].freeze
    SELECTION_FIELDS = %w[trust_snapshot_id policy_version trust_content_hash profile_ref profile_version profile_definition_hash tenant_id Issuer Agent Merchant].freeze
    INPUTS = %i[root_presentation terminal_jws host_checkout_jws expected_aud expected_nonce verified_at expected_checkout_id expected_merchant_id expected_currency expected_total_minor].freeze

    def self.reject!(code = :invalid_trust_context) = raise(RootSignature::Rejected, code)
    def self.shape!(value, fields)
      reject! unless value.instance_of?(Hash) && value.keys.sort == fields.sort
    end
    def self.id!(value)
      reject! unless value.instance_of?(String) && value.bytesize.between?(1, 256)
    end
    def self.digest!(value)
      reject! unless value.instance_of?(String) && /\A[0-9a-f]{64}\z/.match?(value)
    end
    def self.time!(value)
      reject! unless value.instance_of?(Integer) && value.between?(0, 4_102_444_800)
    end
    def self.window!(value)
      reject! unless value["active"] == true || value["active"] == false
      time!(value["not_before"])
      time!(value["not_after"])
      reject! unless value["not_before"] < value["not_after"]
    end
    def self.live!(value, now, inactive, expired)
      reject!(inactive) unless value["active"]
      reject!(expired) unless value["not_before"] <= now && now < value["not_after"]
    end
    def self.body!(envelope, fields, hash_name, limit)
      shape!(envelope, fields + [hash_name, "body"])
      digest!(envelope[hash_name])
      wire = InputValidator.snapshot!(envelope["body"], max_bytes: limit)
      reject!(:trust_context_mismatch) unless Digest::SHA256.hexdigest(wire) == envelope[hash_name]
      body = InputValidator.parse!(wire)
      fields.each do |field|
        id!(envelope[field])
        reject!(:trust_context_mismatch) unless body.instance_of?(Hash) && body[field] == envelope[field]
      end
      [body, wire]
    end
    def self.keys!(trust_json:, selection_json:, verified_at:, expected_merchant_id:)
      time!(verified_at)
      trust = InputValidator.parse!(trust_json)
      selection = InputValidator.parse!(InputValidator.snapshot!(selection_json, max_bytes: 16_384))
      shape!(trust, %w[snapshot profile])
      shape!(selection, SELECTION_FIELDS)
      %w[trust_snapshot_id policy_version profile_ref profile_version tenant_id].each { |f| id!(selection[f]) }
      %w[trust_content_hash profile_definition_hash].each { |f| digest!(selection[f]) }
      ROLES.each_key do |role|
        shape!(selection[role], %w[identity purpose key_ref])
        selection[role].each_value { |value| id!(value) }
      end
      reject!(:trust_context_mismatch) unless selection["Merchant"]["identity"] == expected_merchant_id
      snapshot, = body!(trust["snapshot"], %w[id policy_version], "content_hash", 65_536)
      shape!(snapshot, %w[id policy_version active not_before not_after records])
      window!(snapshot)
      reject!(:trust_context_mismatch) unless trust["snapshot"].values_at("id", "policy_version", "content_hash") ==
        selection.values_at("trust_snapshot_id", "policy_version", "trust_content_hash")
      live!(snapshot, verified_at, :inactive_trust_snapshot, :trust_snapshot_time_mismatch)
      _profile, wire = body!(trust["profile"], %w[profile_ref version], "definition_hash", 8_192)
      reject!(:unsupported_trust_profile) unless wire == PROFILE_BODY &&
        trust["profile"].values_at("profile_ref", "version", "definition_hash") == [PROFILE_REF, PROFILE_VERSION, PROFILE_HASH] &&
        selection.values_at("profile_ref", "profile_version", "profile_definition_hash") == [PROFILE_REF, PROFILE_VERSION, PROFILE_HASH]
      records = snapshot["records"]
      reject! unless records.instance_of?(Array) && records.length.between?(1, 16)
      records.each do |record|
        shape!(record, RECORD_FIELDS)
        %w[identity tenant_id purpose key_ref profile_ref profile_version].each { |f| id!(record[f]) }
        reject! unless ROLES.key?(record["role"])
        window!(record)
        reject!(:unsupported_trust_profile) unless record.values_at("profile_ref", "profile_version", "algorithm") == [PROFILE_REF, PROFILE_VERSION, "ES256"]
        digest!(record["key_fingerprint"])
        begin
          RootSignature.public_jwk!(record["public_key_pem"])
        rescue RootSignature::Unavailable => error
          raise if error.code == :signature_dependency_unavailable
          reject!(:invalid_trust_key)
        end
        reject!(:invalid_trust_key) unless Digest::SHA256.hexdigest(record["public_key_pem"]) == record["key_fingerprint"]
      end
      ROLES.to_h do |role, keyword|
        wanted = selection[role]
        matches = records.select do |record|
          record["role"] == role && record["tenant_id"] == selection["tenant_id"] &&
            wanted.all? { |field, value| record[field] == value }
        end
        reject!(:trust_key_not_found) if matches.empty?
        reject!(:ambiguous_trust_key) unless matches.length == 1
        record = matches.first
        live!(record, verified_at, :inactive_trust_key, :trust_key_time_mismatch)
        [keyword, record["public_key_pem"].freeze]
      end.freeze
    end
    private_class_method :reject!, :shape!, :id!, :digest!, :time!, :window!, :live!, :body!
  end
end
