# frozen_string_literal: true

module AP2MandateVerifier
  # Checks authenticated Host assertions; never issues/consumes a challenge.
  module HostBinding
    B_IDS = %w[tenant_id buyer_account_id order_id merchant_id audience profile_ref order_version profile_version].freeze
    B_HASHES = %w[approved_agent_key_fingerprint root_presentation_digest checkout_jwt_digest].freeze
    B_FIELDS = (B_IDS + B_HASHES + %w[currency expected_total]).freeze
    REFERENCES = %w[trust_snapshot_id policy_version trust_content_hash profile_definition_hash].freeze
    CHALLENGE_FIELDS = (%w[challenge_id nonce issuer_id B not_before not_after state] + REFERENCES).freeze

    def self.reject!(code = :invalid_host_context) = raise(RootSignature::Rejected, code)
    def self.shape!(value, fields)
      reject! unless value.instance_of?(Hash) && value.keys.sort == fields.sort
    end
    def self.id!(value)
      reject! unless value.instance_of?(String) && value.bytesize.between?(1, 256)
    end
    def self.hash!(value)
      reject! unless value.instance_of?(String) && /\A[0-9a-f]{64}\z/.match?(value)
    end
    def self.time!(value)
      reject! unless value.instance_of?(Integer) && value.between?(0, PurchaseBinding::MAX_EPOCH)
    end
    def self.binding!(value)
      shape!(value, B_FIELDS)
      B_IDS.each { |field| id!(value[field]) }
      B_HASHES.each { |field| hash!(value[field]) }
      reject! unless ScopedConstraints::CURRENCIES.include?(value["currency"]) &&
        value["expected_total"].instance_of?(Integer) && value["expected_total"].between?(0, ScopedConstraints::MAX_AMOUNT)
    end
    def self.check!(trust_json:, selection_json:, host_json:, root_presentation:, terminal_jws:,
                   host_checkout_jws:, verified_at:)
      # Capture every caller-owned original before key processing. JSON parse
      # yields detached values; neither the Host nor signed bytes are rewritten.
      root = InputValidator.snapshot!(root_presentation)
      terminal = InputValidator.snapshot!(terminal_jws, max_bytes: 32_768)
      checkout = InputValidator.snapshot!(host_checkout_jws, max_bytes: 16_384)
      trust = InputValidator.snapshot!(trust_json)
      selection = InputValidator.snapshot!(selection_json, max_bytes: 16_384)
      host = InputValidator.parse!(InputValidator.snapshot!(host_json, max_bytes: 32_768))
      time!(verified_at)
      shape!(host, %w[binding challenge expected_challenge_issuer_id clock_source_id])
      id!(host["expected_challenge_issuer_id"])
      id!(host["clock_source_id"])
      binding = host["binding"]
      challenge = host["challenge"]
      binding!(binding)
      shape!(challenge, CHALLENGE_FIELDS)
      binding!(challenge["B"])
      %w[challenge_id nonce issuer_id trust_snapshot_id policy_version].each { |f| id!(challenge[f]) }
      %w[trust_content_hash profile_definition_hash].each { |f| hash!(challenge[f]) }
      time!(challenge["not_before"])
      time!(challenge["not_after"])
      reject! unless challenge["not_before"] < challenge["not_after"]
      reject!(:challenge_state_mismatch) unless challenge["state"] == "issued"
      reject!(:host_binding_mismatch) unless challenge["B"] == binding &&
        challenge["issuer_id"] == host["expected_challenge_issuer_id"]
      reject!(:challenge_time_mismatch) unless challenge["not_before"] <= verified_at && verified_at < challenge["not_after"]
      context = TrustContext.verified_context!(trust_json: trust, selection_json: selection,
        verified_at: verified_at, expected_merchant_id: binding["merchant_id"])
      references = context.fetch(:references)
      reject!(:challenge_reference_mismatch) unless REFERENCES.all? { |f| challenge[f] == references[f] }
      reject!(:host_binding_mismatch) unless %w[tenant_id profile_ref profile_version].all? { |f| binding[f] == references[f] } &&
        binding["approved_agent_key_fingerprint"] == context.fetch(:agent_fingerprint) &&
        binding["root_presentation_digest"] == Digest::SHA256.hexdigest(root) &&
        binding["checkout_jwt_digest"] == Digest::SHA256.hexdigest(checkout)
      # This is B_verified, not just a copy of authenticated Host context:
      # external key -> Root cnf; signed terminal nonce/aud/sd_hash; Closed
      # original Checkout hash/bytes; Merchant signature/IDs; signed constraints.
      details = ScopedConstraints.verified_constraints!(root_presentation: root, terminal_jws: terminal,
        host_checkout_jws: checkout, **context.fetch(:keys), expected_aud: binding["audience"],
        expected_nonce: challenge["nonce"], verified_at: verified_at,
        expected_checkout_id: binding["order_id"], expected_merchant_id: binding["merchant_id"],
        expected_currency: binding["currency"], expected_total_minor: binding["expected_total"])
      open, closed, proof = details.values_at(:open, :closed, :terminal)
      starts = [context.fetch(:valid_from), challenge["not_before"], open["iat"], closed["iat"], proof["iat"]]
      ends = [context.fetch(:valid_until), challenge["not_after"], open["exp"], closed["exp"], proof["iat"] + 301]
      # The sole registered profile has no separate validity interval. Merchant
      # JWT has no iat/exp/nbf: inventing one would change the pinned profile.
      reject!(:invalid_host_validity) unless starts.max <= verified_at && verified_at < ends.min
      nil # No Evidence, ALLOW, nonce consumption, database or clock access.
    end
    private_class_method :reject!, :shape!, :id!, :hash!, :time!, :binding!
  end
end
