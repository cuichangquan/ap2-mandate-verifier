# frozen_string_literal: true

module AP2MandateVerifier
  # No success state or evidence constructor exists at this stage.
  class Result
    CODES = {
      rejected: %i[invalid_input_type input_too_large invalid_encoding
                   invalid_json duplicate_key input_too_deep invalid_root_jws
                   unsupported_root_header unsupported_root_algorithm
                   unsupported_root_type invalid_root_payload invalid_root_signature
                   invalid_root_presentation unsupported_disclosure_profile invalid_disclosure
                   missing_disclosure duplicate_disclosure duplicate_commitment extra_disclosure
                   disclosure_limit_exceeded unsupported_purchase_profile agent_key_mismatch
                   root_binding_mismatch audience_mismatch nonce_mismatch invalid_purchase_time
                   delegation_claim_mismatch checkout_binding_mismatch checkout_identity_mismatch
                   invalid_scoped_schema unsupported_scoped_profile unsupported_constraint
                   constraint_mismatch amount_mismatch currency_mismatch constraint_limit_exceeded].freeze,
      unverified: %i[verification_not_implemented root_signature_verified_only root_disclosures_verified_only
                     purchase_binding_verified_only scoped_constraints_verified_only].freeze,
      unavailable: %i[json_dependency_unavailable input_check_unavailable
                      signature_dependency_unavailable issuer_key_unavailable
                      issuer_key_unsupported root_signature_check_unavailable
                      disclosure_dependency_unavailable root_disclosure_check_unavailable
                      purchase_context_unavailable purchase_dependency_unavailable purchase_check_unavailable
                      constraint_context_unavailable constraint_dependency_unavailable constraint_check_unavailable].freeze
    }.freeze

    attr_reader :status, :code

    def initialize(status:, code:)
      unless CODES.fetch(status, []).include?(code)
        raise ArgumentError, "unsupported non-success result"
      end
      @status = status
      @code = code
      freeze
    end

    def success? = false
    def evidence = nil
    def rejected? = status == :rejected
    def unverified? = status == :unverified
    def unavailable? = status == :unavailable
  end
end
