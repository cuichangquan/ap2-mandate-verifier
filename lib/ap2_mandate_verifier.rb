# frozen_string_literal: true

require_relative "ap2_mandate_verifier/result"
require_relative "ap2_mandate_verifier/input_validator"
require_relative "ap2_mandate_verifier/root_signature"
require_relative "ap2_mandate_verifier/root_disclosures"
require_relative "ap2_mandate_verifier/purchase_binding"

module AP2MandateVerifier
  # Accepts original JSON bytes only. Syntax validity is not AP2 validity,
  # authentication, disclosure completeness, or a Host authorization decision.
  def self.verify(presentation_json:)
    unavailable = InputValidator.check!(presentation_json)
    return Result.new(status: :unavailable, code: unavailable) if unavailable

    Result.new(status: :unverified, code: :verification_not_implemented)
  rescue InputValidator::Invalid => error
    Result.new(status: :rejected, code: error.code)
  rescue LoadError
    Result.new(status: :unavailable, code: :json_dependency_unavailable)
  rescue StandardError
    # Unexpected implementation/dependency failure is not proof of bad input.
    # Do not expose parser messages, source text, or claim values.
    Result.new(status: :unavailable, code: :input_check_unavailable)
  end

  # One original compact Root JWS only; no SD disclosure/authority validation.
  # The caller must select this PUBLIC key independently of the token. This
  # API does not establish the caller's key enrollment or Issuer provenance.
  def self.verify_root_signature(root_jws:, trusted_issuer_public_key_pem:)
    RootSignature.check!(root_jws, trusted_issuer_public_key_pem)
    Result.new(status: :unverified, code: :root_signature_verified_only)
  rescue InputValidator::Unavailable, RootSignature::Unavailable => error
    Result.new(status: :unavailable, code: error.code)
  rescue InputValidator::Invalid, RootSignature::Rejected => error
    Result.new(status: :rejected, code: error.code)
  rescue LoadError
    Result.new(status: :unavailable, code: :signature_dependency_unavailable)
  rescue StandardError
    Result.new(status: :unavailable, code: :root_signature_check_unavailable)
  end

  # Exact DC04 disclosure profile only. This grants no AP2/Host authority.
  def self.verify_root_disclosures(presentation:, trusted_issuer_public_key_pem:)
    RootDisclosures.check!(presentation, trusted_issuer_public_key_pem)
    Result.new(status: :unverified, code: :root_disclosures_verified_only)
  rescue InputValidator::Unavailable, RootSignature::Unavailable => error
    Result.new(status: :unavailable, code: error.code)
  rescue InputValidator::Invalid, RootSignature::Rejected => error
    Result.new(status: :rejected, code: error.code)
  rescue LoadError
    Result.new(status: :unavailable, code: :disclosure_dependency_unavailable)
  rescue StandardError
    Result.new(status: :unavailable, code: :root_disclosure_check_unavailable)
  end

  def self.verify_purchase_binding(**inputs)
    PurchaseBinding.check!(**inputs)
    Result.new(status: :unverified, code: :purchase_binding_verified_only)
  rescue InputValidator::Unavailable, RootSignature::Unavailable => error
    Result.new(status: :unavailable, code: error.code)
  rescue InputValidator::Invalid, RootSignature::Rejected => error
    Result.new(status: :rejected, code: error.code)
  rescue LoadError
    Result.new(status: :unavailable, code: :purchase_dependency_unavailable)
  rescue StandardError
    Result.new(status: :unavailable, code: :purchase_check_unavailable)
  end
end
