# frozen_string_literal: true

module AP2MandateVerifier
  # Pure, fixed-profile conversion of authenticated Host business information.
  # Preparation is not issuance, verification, nonce consumption or Host ALLOW.
  module InputBuilder
    FORMAT_VERSION = "1"
    ORDER_FIELDS = %w[tenant_id buyer_account_id order_id merchant_id audience order_version currency expected_total].freeze
    RECORD_FIELDS = (TrustContext::RECORD_FIELDS - %w[profile_ref profile_version algorithm key_fingerprint]).freeze
    class Invalid < ArgumentError; end

    class Trust
      attr_reader :trust_json, :selection_json
      def initialize(trust_json, selection_json, context)
        @trust_json, @selection_json = trust_json.freeze, selection_json.freeze
        @context = context
        freeze
      end
      private_class_method :new
    end

    # All registry entries are preserved, including inactive/nonselected entries.
    # Selection is explicit Host policy, never extracted from signed claims.
    def self.trust(snapshot:, tenant_id:, issuer:, agent:, merchant:, verified_at:)
      verified_at = copy!(verified_at)
      source = copy!(snapshot)
      shape!(source, %w[id policy_version active not_before not_after records])
      invalid! unless source["records"].instance_of?(Array) && source["records"].length.between?(1, 16)
      source["records"].each do |record|
        shape!(record, RECORD_FIELDS)
        record.merge!("profile_ref" => TrustContext::PROFILE_REF, "profile_version" => TrustContext::PROFILE_VERSION,
          "algorithm" => "ES256", "key_fingerprint" => Digest::SHA256.hexdigest(record.fetch("public_key_pem")))
      end
      body = json!(source, 65_536)
      selection = {"trust_snapshot_id" => source["id"], "policy_version" => source["policy_version"],
        "trust_content_hash" => Digest::SHA256.hexdigest(body), "tenant_id" => copy!(tenant_id),
        "profile_ref" => TrustContext::PROFILE_REF, "profile_version" => TrustContext::PROFILE_VERSION,
        "profile_definition_hash" => TrustContext::PROFILE_HASH,
        "Issuer" => copy!(issuer), "Agent" => copy!(agent), "Merchant" => copy!(merchant)}
      wire = json!({"snapshot" => {"id" => source["id"], "policy_version" => source["policy_version"],
        "content_hash" => selection["trust_content_hash"], "body" => body},
        "profile" => {"profile_ref" => TrustContext::PROFILE_REF, "version" => TrustContext::PROFILE_VERSION,
          "definition_hash" => TrustContext::PROFILE_HASH, "body" => TrustContext::PROFILE_BODY}})
      selected = json!(selection, 16_384)
      context = TrustContext.verified_context!(trust_json: wire, selection_json: selected, verified_at: verified_at,
        expected_merchant_id: selection.fetch("Merchant").fetch("identity"))
      Trust.send(:new, wire, selected, context)
    rescue InputValidator::Invalid, RootSignature::Rejected, KeyError, TypeError
      invalid!
    end

    # Restore authenticated registry bytes without reserializing the snapshot
    # or profile body. The Host remains responsible for freshness and provenance.
    def self.restore_trust(trust_json:, selection_json:, verified_at:)
      wire = InputValidator.snapshot!(trust_json)
      selected = InputValidator.snapshot!(selection_json, max_bytes: 16_384)
      selection = InputValidator.parse!(selected)
      context = TrustContext.verified_context!(trust_json: wire, selection_json: selected,
        verified_at: copy!(verified_at), expected_merchant_id: selection.fetch("Merchant").fetch("identity"))
      Trust.send(:new, wire, selected, context)
    rescue InputValidator::Invalid, RootSignature::Rejected, KeyError, TypeError, NoMethodError
      invalid!
    end

    # Persist the returned original String in authenticated Host storage. A nonce
    # and identifier must already have been chosen by the Host, independently.
    def self.prepare(trust:, order:, root_presentation:, host_checkout_jws:, challenge_id:, nonce:, issuer_id:, not_before:, not_after:)
      context = context!(trust, not_before)
      TrustContext.verified_context!(trust_json: trust.trust_json, selection_json: trust.selection_json,
        verified_at: not_before, expected_merchant_id: context.fetch(:selected_keys).find { |r| r["role"] == "Merchant" }.fetch("identity"))
      challenge = {"challenge_id" => copy!(challenge_id), "nonce" => copy!(nonce), "issuer_id" => copy!(issuer_id),
        "B" => binding!(context, order, root_presentation, host_checkout_jws),
        "not_before" => copy!(not_before), "not_after" => copy!(not_after), "state" => "issued"}
      HostBinding::REFERENCES.each { |field| challenge[field] = context.fetch(:references).fetch(field) }
      saved = json!({"format_version" => FORMAT_VERSION, "profile_ref" => TrustContext::PROFILE_REF,
        "profile_version" => TrustContext::PROFILE_VERSION, "challenge" => challenge}, 32_768)
      restore(saved_challenge: saved)
    rescue InputValidator::Invalid, RootSignature::Rejected, KeyError, TypeError
      invalid!
    end

    # Validate, but never regenerate, hash or repair persisted challenge fields.
    # This does not authenticate the storage or attest that its nonce is unused.
    def self.restore(saved_challenge:)
      wire = InputValidator.snapshot!(saved_challenge, max_bytes: 32_768)
      value = InputValidator.parse!(wire)
      shape!(value, %w[format_version profile_ref profile_version challenge])
      invalid! unless value.values_at("format_version", "profile_ref", "profile_version") ==
        [FORMAT_VERSION, TrustContext::PROFILE_REF, TrustContext::PROFILE_VERSION]
      challenge = value["challenge"]
      shape!(challenge, HostBinding::CHALLENGE_FIELDS)
      HostBinding.send(:binding!, challenge["B"])
      invalid! unless challenge["B"].values_at("profile_ref", "profile_version") ==
        [TrustContext::PROFILE_REF, TrustContext::PROFILE_VERSION]
      %w[challenge_id nonce issuer_id trust_snapshot_id policy_version state].each { |field| HostBinding.send(:id!, challenge[field]) }
      %w[trust_content_hash profile_definition_hash].each { |field| HostBinding.send(:hash!, challenge[field]) }
      %w[not_before not_after].each { |field| HostBinding.send(:time!, challenge[field]) }
      invalid! unless challenge["not_before"] < challenge["not_after"]
      wire
    rescue InputValidator::Invalid, RootSignature::Rejected, KeyError, TypeError
      invalid!
    end

    def self.inputs(trust:, saved_challenge:, order:, root_presentation:, terminal_jws:, host_checkout_jws:,
                    expected_challenge_issuer_id:, clock_source_id:, verified_at:)
      context = context!(trust, verified_at)
      saved = InputValidator.parse!(restore(saved_challenge: saved_challenge))
      root = InputValidator.snapshot!(root_presentation)
      checkout = InputValidator.snapshot!(host_checkout_jws, max_bytes: 16_384)
      terminal = InputValidator.snapshot!(terminal_jws, max_bytes: 32_768)
      host = {"binding" => binding!(context, order, root, checkout), "challenge" => saved.fetch("challenge"),
        "expected_challenge_issuer_id" => copy!(expected_challenge_issuer_id), "clock_source_id" => copy!(clock_source_id)}
      {trust_json: trust.trust_json, selection_json: trust.selection_json, host_json: json!(host, 32_768),
       root_presentation: root, terminal_jws: terminal, host_checkout_jws: checkout, verified_at: verified_at}.freeze
    rescue InputValidator::Invalid, RootSignature::Rejected, KeyError, TypeError
      invalid!
    end

    # Building alone never produces Evidence; always enter the full old core.
    def self.verify(**arguments)
      AP2MandateVerifier.verify_checkout(**inputs(**arguments))
    rescue Invalid, ArgumentError
      Result.new(status: :rejected, code: :invalid_input_builder)
    rescue InputValidator::Unavailable, RootSignature::Unavailable, LoadError
      Result.new(status: :unavailable, code: :input_builder_unavailable)
    rescue StandardError
      Result.new(status: :unavailable, code: :input_builder_unavailable)
    end

    def self.context!(trust, now)
      invalid! unless Object.instance_method(:instance_of?).bind_call(trust, Trust)
      HostBinding.send(:time!, copy!(now))
      trust.instance_variable_get(:@context)
    end
    def self.binding!(context, order, root, checkout)
      value = copy!(order)
      shape!(value, ORDER_FIELDS)
      references = context.fetch(:references)
      value.merge!("profile_ref" => references.fetch("profile_ref"), "profile_version" => references.fetch("profile_version"),
        "approved_agent_key_fingerprint" => context.fetch(:agent_fingerprint),
        "root_presentation_digest" => Digest::SHA256.hexdigest(InputValidator.snapshot!(root)),
        "checkout_jwt_digest" => Digest::SHA256.hexdigest(InputValidator.snapshot!(checkout, max_bytes: 16_384)))
      HostBinding.send(:binding!, value)
      value
    end
    def self.shape!(value, fields)
      invalid! unless value.instance_of?(Hash) && value.keys.sort == fields.sort
    end
    def self.invalid! = raise(Invalid, "invalid input-builder information")
    def self.json!(value, limit = InputValidator::MAX_BYTES)
      require "json"
      invalid! unless JSON::VERSION == InputValidator::JSON_VERSION
      InputValidator.snapshot!(JSON.generate(value), max_bytes: limit)
    end

    # Bound and detach before JSON generation, including the pre-serialization
    # graph. No coercion, subclass or singleton callback is invoked by copying.
    def self.copy!(value)
      budget = [0, 0]
      walk!(value, 1, {}, budget)
    end
    def self.walk!(value, depth, ancestors, budget)
      invalid! if depth > 16 || (budget[0] += 1) > 2048
      invalid! unless Object.instance_method(:singleton_methods).bind_call(value, true).empty?
      klass = Object.instance_method(:class).bind_call(value)
      if klass == String
        wire = InputValidator.snapshot!(value, max_bytes: 65_536)
        invalid! if (budget[1] += wire.bytesize) > 131_072
        wire.dup
      elsif klass == Integer
        invalid! unless value.between?(0, ScopedConstraints::MAX_AMOUNT)
        value
      elsif klass == TrueClass || klass == FalseClass || klass == NilClass
        value
      elsif klass == Hash || klass == Array
        id = Object.instance_method(:object_id).bind_call(value)
        invalid! if ancestors[id]
        ancestors[id] = true
        invalid! if value.size > 256
        result = if klass == Array
          value.map { |child| walk!(child, depth + 1, ancestors, budget) }
        else
          result = {}
          value.each do |key, child|
            invalid! unless Object.instance_method(:class).bind_call(key) == String
            copied_key = walk!(key, depth + 1, ancestors, budget)
            invalid! if result.key?(copied_key)
            result[copied_key] = walk!(child, depth + 1, ancestors, budget)
          end
          result
        end
        ancestors.delete(id)
        result
      else
        invalid!
      end
    end
    private_class_method :context!, :binding!, :shape!, :invalid!, :json!, :copy!, :walk!
  end
end
