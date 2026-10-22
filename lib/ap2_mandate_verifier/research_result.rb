# frozen_string_literal: true

module AP2MandateVerifier
  # In-process immutable checked facts. No JSON/remote reconstruction API.
  # Private constructors are API discipline, not a hostile Ruby-code sandbox.
  class ResearchEvidence
    CONTRACT_VERSION = "ap2.research-evidence.2"
    IMPLEMENTATION_REVISION = "ap2.research-verifier.2"
    SCOPE = %w[strict_inputs host_trust_profile_input_checks issuer_root_signature
      original_root_graph_closure agent_key_confirmation agent_terminal_signature
      closed_original_checkout_binding merchant_checkout_signature
      fixed_subset_schema_constraints host_challenge_order_binding validity_intersection].freeze

    def initialize(facts)
      @data = self.class.__send__(:copy_frozen, facts.merge(
        "contract_version" => CONTRACT_VERSION, "implementation_revision" => IMPLEMENTATION_REVISION,
        "revision_kind" => "static_identifier_not_runtime_attestation", "verified_scope" => SCOPE))
      freeze
    end
    def self.copy_frozen(value)
      case value
      when Hash
        value.to_h { |key, child| [copy_frozen(key), copy_frozen(child)] }.freeze
      when Array
        value.map { |child| copy_frozen(child) }.freeze
      when String
        InputValidator.snapshot!(value)
      when Integer, TrueClass, FalseClass, NilClass
        value
      else
        raise ArgumentError, "unsupported checked fact"
      end
    end
    private_class_method :new, :allocate, :copy_frozen
    def [](field) = @data.fetch(field)
    def to_h = @data
    def dup = self
    def clone(freeze: true) = self
  end

  # Only this factory runs the full supported pipeline and mints research output.
  # Old Result never accepts Evidence, even for a successful research result.
  class ResearchResult
    def self.verify(**inputs)
      facts = HostBinding.verified_binding!(**inputs)
      new(ResearchEvidence.__send__(:new, facts))
    rescue InputValidator::Unavailable, RootSignature::Unavailable => error
      failure(:unavailable, error.code)
    rescue InputValidator::Invalid, RootSignature::Rejected => error
      failure(:rejected, error.code)
    rescue LoadError
      Result.new(status: :unavailable, code: :signature_dependency_unavailable)
    rescue StandardError
      Result.new(status: :unavailable, code: :research_verification_unavailable)
    end
    def self.failure(status, code)
      unless Result::CODES.fetch(status).include?(code)
        status, code = :unavailable, :research_verification_unavailable
      end
      Result.new(status: status, code: code)
    end
    private_class_method :failure
    attr_reader :evidence
    def initialize(evidence)
      raise ArgumentError, "checked research evidence required" unless evidence.instance_of?(ResearchEvidence) && evidence.frozen?
      @evidence = evidence
      freeze
    end
    private_class_method :new, :allocate
    def status = :verified_research
    def code = :scoped_research_verified
    def success? = true
    def rejected? = false
    def unverified? = false
    def unavailable? = false
    def dup = self
    def clone(freeze: true) = self
  end
end
