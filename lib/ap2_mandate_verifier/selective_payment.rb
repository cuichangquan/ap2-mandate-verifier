# frozen_string_literal: true

module AP2MandateVerifier
  # Explicit conditional-Payment profile. Unknown hidden conditions are never
  # inferred to be absent; unresolved commitments exist only at candidate slots.
  module SelectivePayment
    PROFILE_REF = "ap2.payment.selective_candidates.1".freeze
    MAX_WIRE = 65_536
    MAX_DISCLOSURES = 17
    AXES = {"payment.allowed_payees" => "payee", "payment.allowed_payment_instruments" => "payment_instrument"}.freeze
    class Invalid < ArgumentError
      def initialize = super("invalid selective payment information")
    end

    # All candidates and their exact Cartesian authorization come from a
    # protected approval record. This confidential issuance MUST NOT be sent.
    def self.issue_open(open_checkout_sd_jwt:, constraints:, fixed:, approved_combinations:, selective:,
                        agent_public_key_pem:, issued_at:, expires_at:, signer:, public_key_pem:,
                        checkout_profile_ref: ScopedConstraints::MULTI_PROFILE_REF)
      RootSignature.send(:dependencies!)
      raise Invalid unless %i[payees instruments both].include?(selective)
      checkout = Payment.send(:checkout_open!, open_checkout_sd_jwt, profile_ref: checkout_profile_ref)
      cs = InputBuilder.send(:copy!, constraints)
      raise Invalid unless cs.instance_of?(Array)
      cs << {"type" => "payment.reference", "conditional_transaction_id" => digest(checkout)}
      value = InputBuilder.send(:copy!, fixed)
      raise Invalid unless value.instance_of?(Hash) && (value.keys - Payment::FIELDS.drop(1)).empty?
      opening = value.merge("vct" => "mandate.payment.open.1", "iat" => issued_at, "exp" => expires_at,
        "cnf" => {"jwk" => RootSignature.public_jwk!(agent_public_key_pem)}, "constraints" => cs)
      Payment.send(:open!, opening)
      payees = constraint!(opening, "payment.allowed_payees").fetch("allowed")
      instruments = constraint!(opening, "payment.allowed_payment_instruments").fetch("allowed")
      pairs = InputBuilder.send(:copy!, approved_combinations)
      expected = payees.each_index.flat_map { |p| instruments.each_index.map { |i| [p, i] } }
      raise Invalid unless pairs.instance_of?(Array) && pairs.size == expected.size && pairs.all? do |pair|
        pair.instance_of?(Array) && pair.size == 2 && pair.all? { |n| Object.instance_method(:instance_of?).bind_call(n, Integer) }
      end
      raise Invalid unless pairs.sort == expected.sort
      AXES.each do |type, field|
        raise Invalid if opening.key?(field) && !constraint!(opening, type).fetch("allowed").include?(opening[field])
      end
      disclosures = []
      modes = selective == :both ? AXES.keys : [selective == :payees ? AXES.keys[0] : AXES.keys[1]]
      modes.each do |type|
        c = constraint!(opening, type)
        c["allowed"] = c["allowed"].map { |candidate| disclose!(candidate, disclosures) }
      end
      content = []
      pointer = disclose!(opening, content)
      payload = {"ap2_profile" => PROFILE_REF, "_sd_alg" => "sha-256", "delegate_payload" => [pointer]}
      preview = [encode({"alg" => "ES256", "typ" => "example+sd-jwt"}), encode(payload), encode("\0" * 64)].join(".")
      wire = ([preview] + content + disclosures + [""]).join("~")
      parse!(wire, complete: true) # Full wire/disclosure bounds BEFORE signer effects.
      jwt = MerchantSignature.sign!(payload, signer, public_key_pem, typ: "example+sd-jwt")
      ([jwt] + content + disclosures + [""]).join("~").freeze
    end

    # Each selective index selects one original signed candidate slot. For an
    # inline/nonselective axis, pass nil: every approved inline value is visible.
    def self.select(open_sd_jwt:, payee_index:, instrument_index:)
      parsed = parse!(open_sd_jwt, complete: true)
      keep = [parsed.fetch(:content_digest)]
      {"payment.allowed_payees" => payee_index, "payment.allowed_payment_instruments" => instrument_index}.each do |type, index|
        c = constraint!(parsed.fetch(:original), type)
        slots = parsed.fetch(:slots).fetch(type)
        if slots.empty?
          raise Invalid unless index.nil?
        else
          raise Invalid unless Object.instance_method(:instance_of?).bind_call(index, Integer) && index.between?(0, slots.size - 1)
          keep << slots.fetch(index)
          field = AXES.fetch(type)
          selected = parsed.fetch(:values).fetch(slots.fetch(index))
          raise Invalid if parsed.fetch(:original).key?(field) && parsed.fetch(:original)[field] != selected
        end
      end
      wire = ([parsed.fetch(:compact)] + parsed.fetch(:disclosures).select { |d| keep.include?(digest(d)) } + [""]).join("~")
      parse!(wire, complete: false)
      wire.freeze
    end

    def self.issue_closed(open_presentation:, payment:, trusted_provider_public_key_pem:, agent_public_key_pem:,
                          audience:, nonce:, verified_at:, signer:)
      agent = InputValidator.snapshot!(agent_public_key_pem, max_bytes: 1_024)
      provider = InputValidator.snapshot!(trusted_provider_public_key_pem, max_bytes: 1_024)
      aud = InputValidator.snapshot!(audience, max_bytes: 512)
      challenge = InputValidator.snapshot!(nonce, max_bytes: 512)
      parsed = authenticated!(open_presentation, provider)
      opening = parsed.fetch(:opening)
      Payment.send(:valid_now!, opening, verified_at)
      raise Invalid unless opening.fetch("cnf") == {"jwk" => RootSignature.public_jwk!(agent)}
      closed = Payment.send(:copy_details!, payment).merge("vct" => "mandate.payment.1", "iat" => verified_at, "exp" => opening.fetch("exp"))
      Payment.send(:closed!, closed); Payment.send(:conditions!, opening, closed)
      Payment.send(:text!, aud, 512); Payment.send(:text!, challenge, 512)
      claims = {"delegate_payload" => [closed], "iat" => verified_at, "aud" => aud, "nonce" => challenge,
        "sd_hash" => digest(parsed.fetch(:wire))}
      Payment.send(:preflight!, claims, "kb+sd-jwt")
      terminal = MerchantSignature.sign!(claims, signer, agent, typ: "kb+sd-jwt")
      Payment::Presentation.send(:new, parsed.fetch(:wire), terminal + "~")
    end

    # Structural restoration only. It never authenticates a stored presentation.
    def self.present(open_presentation:, closed_sd_jwt:)
      root = parse!(open_presentation, complete: false)
      terminal, wire = Payment.send(:final!, closed_sd_jwt, conditional: true)
      closed = terminal.fetch("delegate_payload").first
      bind_terminal!(root, terminal, closed)
      Payment::Presentation.send(:new, root.fetch(:wire), wire)
    end

    def self.verify(open_presentation:, closed_sd_jwt:, checkout_inputs:, expected_payment:,
                    trusted_provider_public_key_pem:, expected_agent_public_key_pem:,
                    expected_audience:, expected_nonce:, verified_at:)
      CheckoutReceipt.send(:epoch!, verified_at)
      agent = InputValidator.snapshot!(expected_agent_public_key_pem, max_bytes: 1_024)
      provider = InputValidator.snapshot!(trusted_provider_public_key_pem, max_bytes: 1_024)
      aud = InputValidator.snapshot!(expected_audience, max_bytes: 512)
      nonce = InputValidator.snapshot!(expected_nonce, max_bytes: 512)
      fields = %i[trust_json selection_json host_json root_presentation terminal_jws host_checkout_jws verified_at]
      raise Invalid unless checkout_inputs.instance_of?(Hash) && checkout_inputs.size == fields.size &&
        fields.all? { |f| checkout_inputs.key?(f) } && checkout_inputs[:verified_at] == verified_at
      limits = {host_json: 32_768, terminal_jws: 32_768, host_checkout_jws: 16_384}
      inputs = checkout_inputs.to_h do |key, value|
        [key, key == :verified_at ? value : InputValidator.snapshot!(value, max_bytes: limits.fetch(key, 131_072))]
      end.freeze
      raise Invalid unless inputs.size == fields.size && fields.all? { |f| inputs.key?(f) } && inputs[:verified_at] == verified_at
      expected = Payment.send(:copy_details!, expected_payment)
      checkout = AP2MandateVerifier.verify_checkout(**inputs)
      raise Invalid unless checkout.success?
      raise Invalid unless expected.fetch("transaction_id") == digest(inputs.fetch(:host_checkout_jws))
      binding = checkout.evidence["checkout_binding"]
      amount = expected.fetch("payment_amount")
      raise Invalid unless expected.fetch("payee").fetch("id") == binding.fetch("merchant_id") &&
        amount.fetch("currency") == binding.fetch("currency") && amount.fetch("amount") == binding.fetch("expected_total")
      Payment.send(:bind_checkout!, expected, Payment.send(:jwt_payload!, inputs.fetch(:host_checkout_jws), "JWT"))
      parsed = authenticated!(open_presentation, provider)
      opening = parsed.fetch(:opening)
      Payment.send(:valid_now!, opening, verified_at)
      raise Invalid unless opening.fetch("cnf") == {"jwk" => RootSignature.public_jwk!(agent)}
      terminal, wire = Payment.send(:final!, closed_sd_jwt, conditional: true)
      RootSignature.verified_payload!(wire.split("~", -1).first, agent,
        expected_typ: "kb+sd-jwt", max_bytes: 32_768)
      Payment.send(:text!, aud, 512); Payment.send(:text!, nonce, 512)
      raise Invalid unless terminal.fetch("aud") == aud && terminal.fetch("nonce") == nonce &&
        terminal.fetch("iat") <= verified_at && verified_at - terminal.fetch("iat") <= 300
      closed = terminal.fetch("delegate_payload").first
      bind_terminal!(parsed, terminal, closed)
      Payment.send(:valid_now!, closed, verified_at)
      ref = constraint!(opening, "payment.reference").fetch("conditional_transaction_id")
      raise Invalid unless ref == digest(inputs.fetch(:root_presentation)) && closed.slice(*Payment::FIELDS) == expected
      Payment::Verification.send(:new, closed, wire)
    rescue StandardError, LoadError
      Payment::Verification.send(:new)
    end

    def self.bind_terminal!(root, terminal, closed)
      opening = root.fetch(:opening)
      Payment.send(:closed!, closed)
      raise Invalid unless terminal.fetch("sd_hash") == digest(root.fetch(:wire)) && terminal.fetch("iat") == closed.fetch("iat") &&
        closed.fetch("iat") >= opening.fetch("iat") && closed.fetch("exp") <= opening.fetch("exp")
      Payment.send(:conditions!, opening, closed)
    end
    def self.authenticated!(wire, key)
      parsed = parse!(wire, complete: false)
      RootSignature.verified_payload!(parsed.fetch(:compact), key, max_bytes: 16_384)
      parsed
    end
    def self.parse!(source, complete:)
      RootSignature.send(:dependencies!)
      wire = InputValidator.snapshot!(source, max_bytes: MAX_WIRE)
      raise Invalid unless wire.ascii_only? && wire.end_with?("~")
      compact, *disclosures = wire.split("~", -1)
      disclosures.pop
      raise Invalid unless disclosures.size.between?(2, MAX_DISCLOSURES) && disclosures.none?(&:empty?)
      compact = InputValidator.snapshot!(compact, max_bytes: 16_384)
      claims = Payment.send(:jwt_payload!, compact, "example+sd-jwt")
      Payment.send(:exact!, claims, %w[ap2_profile _sd_alg delegate_payload])
      raise Invalid unless claims["ap2_profile"] == PROFILE_REF && claims["_sd_alg"] == "sha-256" &&
        claims["delegate_payload"].instance_of?(Array) && claims["delegate_payload"].size == 1
      pointer = claims.fetch("delegate_payload").first
      Payment.send(:exact!, pointer, ["..."])
      hash!(pointer["..."])
      values = {}; salts = []
      disclosures.each do |disclosure|
        value = Buyer.send(:decode_disclosure!, disclosure, 2)
        hash = digest(disclosure)
        raise Invalid if values.key?(hash) || salts.include?(value[0])
        salts << value[0]
        values[hash] = value[1]
      end
      content_digest = pointer.fetch("...")
      original = values.fetch(content_digest)
      raise Invalid unless original.instance_of?(Hash) && original["constraints"].instance_of?(Array)
      opening = InputBuilder.send(:copy!, original)
      slots = {}; used = [content_digest]; all_commitments = [content_digest]
      AXES.each do |type, field|
        c = constraint!(opening, type)
        Payment.send(:exact!, c, %w[type allowed])
        list = c.fetch("allowed")
        raise Invalid unless list.instance_of?(Array) && list.size.between?(1, 8)
        markers = list.map { |item| item.instance_of?(Hash) && item.keys == ["..."] }
        raise Invalid unless markers.all? || markers.none?
        slots[type] = []
        if markers.all?
          selected = []
          list.each do |item|
            h = item.fetch("..."); hash!(h)
            raise Invalid if all_commitments.include?(h)
            all_commitments << h; slots[type] << h
            if values.key?(h)
              selected << values.fetch(h); used << h
            elsif complete
              raise Invalid
            end
          end
          raise Invalid unless complete ? selected.size == list.size : selected.size == 1
          c["allowed"] = selected
        end
      end
      raise Invalid if slots.values.all?(&:empty?)
      raise Invalid unless used.sort == values.keys.sort
      Payment.send(:open!, opening) # Only candidate markers were resolved/omitted.
      {wire: wire, compact: compact, disclosures: disclosures, opening: opening,
        original: original, content_digest: content_digest, slots: slots, values: values}
    end
    def self.constraint!(opening, type)
      cs = opening.fetch("constraints")
      raise Invalid unless cs.instance_of?(Array)
      found = cs.select { |c| c.instance_of?(Hash) && c["type"] == type }
      raise Invalid unless found.size == 1
      found.first
    end
    def self.disclose!(value, disclosures)
      require "securerandom"
      wire = encode([encode(SecureRandom.random_bytes(16)), value])
      disclosures << wire
      {"..." => digest(wire)}
    end
    def self.hash!(value)
      raise Invalid unless value.instance_of?(String) && value.match?(/\A[A-Za-z0-9_-]{43}\z/)
    end
    def self.encode(value) = Buyer.send(:encode, value)
    def self.digest(wire) = Payment.send(:digest, wire)

    %i[issue_open select issue_closed present verify].each do |name|
      implementation = method(name)
      required = implementation.parameters.filter_map { |kind, field| field if kind == :keyreq }.freeze
      fields = implementation.parameters.map(&:last).freeze
      define_singleton_method(name) do |**args|
        unless (required - args.keys).empty? && (args.keys - fields).empty?
          next Payment::Verification.send(:new) if name == :verify
          raise Invalid
        end
        implementation.call(**args)
      rescue StandardError, LoadError
        next Payment::Verification.send(:new) if name == :verify
        raise Invalid.new, cause: nil
      end
    end
    singleton_methods(false).reject { |n| %i[issue_open select issue_closed present verify].include?(n) }.each { |n| private_class_method n }
  end
end
