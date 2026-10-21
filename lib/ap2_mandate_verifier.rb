# frozen_string_literal: true

require_relative "ap2_mandate_verifier/result"
require_relative "ap2_mandate_verifier/input_validator"

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
end
