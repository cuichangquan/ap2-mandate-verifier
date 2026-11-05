# frozen_string_literal: true

module AP2MandateVerifier
  # Narrow signed wire profile only. Aggregate occurrence/budget reservation
  # belongs to the protected durable acceptance store, never to this verifier.
  module RecurringPayment
    PROFILE_REF = "ap2.payment.recurring.jpy_on_demand.complete.1".freeze
    SELECTIVE_PROFILE_REF = "ap2.payment.recurring.jpy_on_demand.selective.1".freeze
    TYPES = %w[payment.agent_recurrence payment.budget].freeze
    MAX_OCCURRENCES = 1_000_000
    class Invalid < ArgumentError
      def initialize = super("invalid recurring payment information")
    end

    def self.profile?(profile) = [PROFILE_REF, SELECTIVE_PROFILE_REF].include?(profile)
    def self.profile!(value)
      profile = InputValidator.snapshot!(value, max_bytes: 256)
      raise Invalid unless profile?(profile)
      profile
    end
    def self.selective?(profile) = profile == SELECTIVE_PROFILE_REF

    # Internal structural handoff only; it does not authenticate a signature.
    def self.validated_open!(source, profile_ref:, complete:)
      profile = profile!(profile_ref)
      raise Invalid unless complete == true || complete == false
      if selective?(profile)
        parsed = SelectivePayment.send(:parse!, source, complete: complete, profile_ref: profile)
        opening, wire, compact = parsed.values_at(:opening, :wire, :compact)
      else
        opening, wire = Payment.send(:root!, source, profile_ref: profile)
        Payment.send(:open!, opening, profile_ref: profile)
        compact = wire.split("~", -1).first
      end
      recurrence = opening.fetch("constraints").find { |c| c["type"] == TYPES[0] }
      budget = opening.fetch("constraints").find { |c| c["type"] == TYPES[1] }
      {opening: ResearchEvidence.send(:copy_frozen, opening), root_wire: compact.freeze,
        presentation_wire: wire.freeze, reference: Payment.send(:digest, compact).freeze,
        currency: "JPY".freeze, max_occurrences: recurrence.fetch("max_occurrences"), budget_max: budget.fetch("max"),
        profile_ref: profile}.freeze
    end

    # Protected Host enrollment uses confidential complete issuance. The root
    # reference covers the original JWS alone so leaf selection cannot reset it.
    def self.approved_open!(open_sd_jwt:, profile_ref:, trusted_provider_public_key_pem:, expected_agent_public_key_pem:, verified_at:)
      profile = profile!(profile_ref)
      wire = InputValidator.snapshot!(open_sd_jwt, max_bytes: selective?(profile) ? SelectivePayment::MAX_WIRE : 32_769)
      provider = InputValidator.snapshot!(trusted_provider_public_key_pem, max_bytes: 1024)
      agent = InputValidator.snapshot!(expected_agent_public_key_pem, max_bytes: 1024)
      CheckoutReceipt.send(:epoch!, verified_at)
      # Authenticate the exact original compact JWS before parsing its graph.
      RootSignature.verified_payload!(wire.split("~", -1).first, provider, max_bytes: 32_768)
      parsed = validated_open!(wire, profile_ref: profile, complete: true)
      opening = parsed.fetch(:opening)
      Payment.send(:valid_now!, opening, verified_at)
      raise Invalid unless opening.fetch("cnf") == {"jwk" => RootSignature.public_jwk!(agent)}
      parsed
    rescue StandardError, LoadError
      raise Invalid.new, cause: nil
    end

    def self.constraints!(opening)
      raise Invalid unless opening.instance_of?(Hash)
      cs = opening.fetch("constraints")
      raise Invalid unless cs.instance_of?(Array) && cs.size == 6 && cs.all? { |c| c.instance_of?(Hash) }
      recurrence = cs.select { |c| c["type"] == TYPES[0] }
      budget = cs.select { |c| c["type"] == TYPES[1] }
      raise Invalid unless recurrence.size == 1 && budget.size == 1
      recurrence, budget = recurrence.first, budget.first
      Payment.send(:exact!, recurrence, %w[type frequency max_occurrences])
      Payment.send(:exact!, budget, %w[type max currency])
      raise Invalid unless recurrence["frequency"] == "ON_DEMAND" && integer?(recurrence["max_occurrences"]) &&
        recurrence["max_occurrences"].between?(1, MAX_OCCURRENCES) && budget["currency"] == "JPY" &&
        integer?(budget["max"]) && budget["max"].between?(1, ScopedConstraints::MAX_AMOUNT)
      amount = cs.select { |c| c["type"] == "payment.amount_range" }
      raise Invalid unless amount.size == 1 && amount.first["currency"] == "JPY"
      # This only detects an impossible individual payment, not aggregate use.
      raise Invalid if integer?(amount.first.fetch("min", 0)) && amount.first.fetch("min", 0) > budget["max"]
      if opening.key?("payment_amount")
        Payment.send(:amount!, opening["payment_amount"])
        raise Invalid unless opening["payment_amount"]["currency"] == "JPY" && opening["payment_amount"]["amount"] <= budget["max"]
      end
      opening.merge("constraints" => cs.reject { |c| TYPES.include?(c["type"]) })
    end
    def self.conditions!(opening, closed)
      base = constraints!(opening)
      budget = opening.fetch("constraints").find { |c| c["type"] == TYPES[1] }
      raise Invalid unless closed.fetch("payment_amount").fetch("currency") == "JPY" && closed["payment_amount"]["amount"] <= budget.fetch("max")
      Payment.send(:conditions!, base, closed)
    end
    def self.integer?(value) = Object.instance_method(:instance_of?).bind_call(value, Integer)

    # Same raw public lifecycle as Payment/SelectivePayment. No direct Closed
    # issuance is exposed because the mandatory limits belong to signed Open.
    %i[details issue_open issue_closed present verify select].each do |name|
      define_singleton_method(name) do |profile_ref: PROFILE_REF, **arguments|
        profile = profile!(profile_ref)
        if name == :details
          next Payment.details(**arguments, profile_ref: PROFILE_REF)
        end
        raise Invalid if name == :select && !selective?(profile)
        api = selective?(profile) ? SelectivePayment : Payment
        api.public_send(name, **arguments, profile_ref: profile)
      rescue StandardError, LoadError
        next Payment::Verification.send(:new) if name == :verify
        raise Invalid.new, cause: nil
      end
    end
    private_class_method :profile!, :validated_open!, :constraints!, :conditions!, :integer?
  end
end
