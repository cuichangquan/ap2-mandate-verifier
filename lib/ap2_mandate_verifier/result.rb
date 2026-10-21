# frozen_string_literal: true

module AP2MandateVerifier
  # No success state or evidence constructor exists at this stage.
  class Result
    CODES = {
      rejected: %i[invalid_input_type input_too_large invalid_encoding
                   invalid_json duplicate_key input_too_deep].freeze,
      unverified: %i[verification_not_implemented].freeze,
      unavailable: %i[json_dependency_unavailable input_check_unavailable].freeze
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
