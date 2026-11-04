# frozen_string_literal: true

module AP2MandateVerifier
  # Explicit bounded leaf-candidate profile, never a generic SD-JWT resolver.
  module SelectiveCheckout
    PROFILE_REF = "ap2.checkout.selective_candidates.1".freeze
    MAX_DISCLOSURES = 73
    MAX_SEGMENT = 8_192
    class Invalid < ArgumentError
      def initialize = super("invalid selective checkout information")
    end
    class Open
      attr_reader :root_presentation
      alias open_sd_jwt root_presentation
      def initialize(wire)
        @root_presentation = wire.freeze
        freeze
      end
      private_class_method :new
    end

    # The protected consent must approve independent merchant/product lists.
    # Relationships between lists require separate Open Mandates.
    def self.issue_open(allowed_merchants:, requirements:, candidate_policy:, agent_public_key_pem:,
                        issued_at:, expires_at:, signer:, public_key_pem:)
      RootSignature.send(:dependencies!)
      raise Invalid unless candidate_policy == :independent
      agent = InputValidator.snapshot!(agent_public_key_pem, max_bytes: 1_024)
      provider = InputValidator.snapshot!(public_key_pem, max_bytes: 1_024)
      opening = {"vct" => "mandate.checkout.open.1", "iat" => issued_at, "exp" => expires_at,
        "cnf" => {"jwk" => RootSignature.public_jwk!(agent)}, "constraints" => [
          {"type" => "checkout.line_items", "items" => InputBuilder.send(:copy!, requirements)},
          {"type" => "checkout.allowed_merchants", "allowed" => InputBuilder.send(:copy!, allowed_merchants)}]}
      validate_open!(opening, complete: true)
      disclosures = []
      opening["constraints"][0]["items"].each do |group|
        group["acceptable_items"] = group["acceptable_items"].map { |item| disclose!(item, disclosures) }
      end
      opening["constraints"][1]["allowed"] = opening["constraints"][1]["allowed"].map { |m| disclose!(m, disclosures) }
      content = []
      marker = disclose!(opening, content)
      payload = {"ap2_profile" => PROFILE_REF, "_sd_alg" => "sha-256", "delegate_payload" => [marker]}
      preview = [encode({"alg" => "ES256", "typ" => "example+sd-jwt"}), encode(payload), encode("\0" * 64)].join(".")
      parse!(([preview] + content + disclosures + [""]).join("~"), complete: true)
      jwt = MerchantSignature.sign!(payload, signer, provider, typ: "example+sd-jwt")
      Open.send(:new, ([jwt] + content + disclosures + [""]).join("~"))
    end

    def self.select(open_sd_jwt:, merchant_index:, item_indices:)
      parsed = parse!(open_sd_jwt, complete: true)
      indices = InputBuilder.send(:copy!, item_indices)
      groups = parsed.fetch(:item_slots)
      raise Invalid unless indices.instance_of?(Array) && indices.size == groups.size
      keep = [parsed.fetch(:content_digest), index!(parsed.fetch(:merchant_slots), merchant_index)]
      groups.each_with_index do |slots, i|
        chosen = indices[i]
        raise Invalid unless chosen.instance_of?(Array) && chosen.size.between?(1, slots.size) && chosen.uniq.size == chosen.size
        chosen.each { |n| keep << index!(slots, n) }
      end
      wire = ([parsed.fetch(:compact)] + parsed.fetch(:disclosures).select { |d| keep.include?(digest(d)) } + [""]).join("~")
      parse!(wire, complete: false)
      Open.send(:new, wire)
    end

    # Preparation from caller-owned checkout data only; not Merchant trust.
    def self.select_for_checkout(open_sd_jwt:, checkout:)
      parsed = parse!(open_sd_jwt, complete: true)
      cart = InputBuilder.send(:copy!, checkout)
      ScopedConstraints.multi_checkout!(cart)
      opening = parsed.fetch(:opening)
      merchants = opening.fetch("constraints")[1].fetch("allowed")
      merchant = merchants.index(cart.fetch("merchant"))
      raise Invalid unless merchant
      ids = cart.fetch("line_items").map { |line| line.fetch("item").fetch("id") }
      indices = opening.fetch("constraints")[0].fetch("items").map do |group|
        group.fetch("acceptable_items").each_index.select { |i| ids.include?(group["acceptable_items"][i]["id"]) }
      end
      selected = select(open_sd_jwt: parsed.fetch(:wire), merchant_index: merchant, item_indices: indices)
      details = {open: parse!(selected.root_presentation, complete: false).fetch(:opening), checkout: cart}
      ScopedConstraints.send(:multi_constraints!, details, cart.fetch("currency"), ScopedConstraints.multi_checkout!(cart))
      selected
    end

    def self.issue_closed(root_presentation:, checkout_jwt:, trusted_issuer_public_key_pem:,
                          agent_public_key_pem:, trusted_merchant_public_key_pem:, expected_merchant_id:,
                          audience:, nonce:, verified_at:, signer:)
      provider = InputValidator.snapshot!(trusted_issuer_public_key_pem, max_bytes: 1_024)
      agent = InputValidator.snapshot!(agent_public_key_pem, max_bytes: 1_024)
      merchant = InputValidator.snapshot!(trusted_merchant_public_key_pem, max_bytes: 1_024)
      identity = InputValidator.snapshot!(expected_merchant_id, max_bytes: 256)
      checkout = InputValidator.snapshot!(checkout_jwt, max_bytes: 16_384)
      aud = InputValidator.snapshot!(audience, max_bytes: 512)
      challenge = InputValidator.snapshot!(nonce, max_bytes: 512)
      raise Invalid if aud.empty? || challenge.empty?
      CheckoutReceipt.send(:epoch!, verified_at)
      parsed = authenticated!(root_presentation, provider)
      opening = parsed.fetch(:opening)
      PurchaseBinding.send(:times!, opening, verified_at)
      raise Invalid unless opening["cnf"]["jwk"] == RootSignature.public_jwk!(agent)
      checked = CheckoutJWT.verify(jwt: checkout, trusted_public_key_pem: merchant,
        expected_merchant_id: identity, profile_ref: PROFILE_REF)
      ScopedConstraints.send(:multi_constraints!, {open: opening, checkout: checked.checkout},
        checked.checkout.fetch("currency"), ScopedConstraints.multi_checkout!(checked.checkout))
      closed = {"vct" => "mandate.checkout.1", "iat" => opening.fetch("iat"), "exp" => opening.fetch("exp"),
        "checkout_jwt" => checkout, "checkout_hash" => checked.checkout_hash}
      claims = {"aud" => aud, "nonce" => challenge, "iat" => verified_at,
        "sd_hash" => digest(parsed.fetch(:wire)), "delegate_payload" => [closed]}
      Payment.send(:preflight!, claims, "kb+sd-jwt")
      terminal = MerchantSignature.sign!(claims, signer, agent, typ: "kb+sd-jwt")
      ScopedConstraints.check!(root_presentation: parsed.fetch(:wire), terminal_jws: terminal, host_checkout_jws: checkout,
        trusted_issuer_public_key_pem: provider, expected_agent_public_key_pem: agent,
        trusted_merchant_public_key_pem: merchant, expected_aud: aud, expected_nonce: challenge,
        verified_at: verified_at, expected_checkout_id: checked.checkout.fetch("id"), expected_merchant_id: identity,
        expected_currency: checked.checkout.fetch("currency"), expected_total_minor: ScopedConstraints.multi_checkout!(checked.checkout),
        profile_ref: PROFILE_REF)
      ConditionalCheckout::Closed.send(:new, parsed.fetch(:wire), terminal, checkout)
    end

    # Transport restoration only; authenticate with the genuine Host inputs.
    def self.present(root_presentation:, terminal_jws:, checkout_jwt:)
      parsed = parse!(root_presentation, complete: false)
      terminal = InputValidator.snapshot!(terminal_jws, max_bytes: 32_768)
      checkout = InputValidator.snapshot!(checkout_jwt, max_bytes: 16_384)
      CheckoutReceipt.reference(closed_sd_jwt: terminal + "~", profile_ref: PROFILE_REF)
      claims = Payment.send(:jwt_payload!, terminal, "kb+sd-jwt")
      closed = claims.fetch("delegate_payload").first
      raise Invalid unless claims["sd_hash"] == digest(parsed.fetch(:wire)) && closed["checkout_jwt"] == checkout &&
        %w[iat exp].all? { |f| closed[f] == parsed.fetch(:opening)[f] }
      ConditionalCheckout::Closed.send(:new, parsed.fetch(:wire), terminal, checkout)
    end

    def self.authenticated!(source, provider)
      wire, parts = split!(source)
      RootSignature.verified_payload!(parts.first, provider)
      parse!(wire, complete: false)
    end

    def self.split!(source)
      wire = InputValidator.snapshot!(source)
      raise Invalid unless wire.ascii_only? && wire.end_with?("~")
      parts = wire.split("~", -1)
      raise Invalid unless parts.size.between?(5, MAX_DISCLOSURES + 2) && parts.last == "" && parts[0...-1].none?(&:empty?)
      InputValidator.snapshot!(parts.first, max_bytes: 16_384)
      [wire, parts]
    end

    def self.parse!(source, complete:)
      RootSignature.send(:dependencies!)
      wire, parts = split!(source)
      claims = Payment.send(:jwt_payload!, parts.first, "example+sd-jwt")
      PurchaseBinding.send(:exact!, claims, %w[ap2_profile _sd_alg delegate_payload])
      raise Invalid unless claims["ap2_profile"] == PROFILE_REF && claims["_sd_alg"] == "sha-256" &&
        claims["delegate_payload"].instance_of?(Array) && claims["delegate_payload"].size == 1
      marker = claims["delegate_payload"].first
      PurchaseBinding.send(:exact!, marker, ["..."])
      hash!(marker["..."])
      values = {}; salts = []
      disclosures = parts[1...-1]
      disclosures.each do |part|
        raise Invalid if part.bytesize > MAX_SEGMENT
        value = Buyer.send(:decode_disclosure!, part, 2)
        hash = digest(part)
        raise Invalid if values.key?(hash) || salts.include?(value[0])
        salts << value[0]; values[hash] = value[1]
      end
      content = marker.fetch("...")
      opening = InputBuilder.send(:copy!, values.fetch(content))
      PurchaseBinding.send(:exact!, opening, %w[cnf constraints exp iat vct])
      cs = opening.fetch("constraints")
      raise Invalid unless cs.instance_of?(Array) && cs.size == 2
      PurchaseBinding.send(:exact!, cs[0], %w[type items])
      PurchaseBinding.send(:exact!, cs[1], %w[type allowed])
      raise Invalid unless cs[0]["type"] == "checkout.line_items" && cs[1]["type"] == "checkout.allowed_merchants"
      groups = cs[0]["items"]
      raise Invalid unless groups.instance_of?(Array) && groups.size.between?(1, 8)
      commitments = [content]; used = [content]
      item_slots = groups.map do |group|
        PurchaseBinding.send(:exact!, group, %w[id quantity acceptable_items])
        resolve_list!(group, "acceptable_items", values, commitments, used, complete, false)
      end
      merchant_slots = resolve_list!(cs[1], "allowed", values, commitments, used, complete, true)
      raise Invalid unless used.sort == values.keys.sort
      validate_open!(opening, complete: complete)
      {wire: wire, compact: parts.first, disclosures: disclosures, content_digest: content,
        opening: opening, item_slots: item_slots, merchant_slots: merchant_slots}
    end

    def self.resolve_list!(owner, field, values, commitments, used, complete, merchant)
      list = owner.fetch(field)
      raise Invalid unless list.instance_of?(Array) && list.size.between?(1, 8)
      selected = []
      slots = list.map do |marker|
        PurchaseBinding.send(:exact!, marker, ["..."])
        h = marker.fetch("..."); hash!(h)
        raise Invalid if commitments.include?(h)
        commitments << h
        if values.key?(h)
          selected << values.fetch(h); used << h
        elsif complete
          raise Invalid
        end
        h
      end
      raise Invalid unless selected.size.between?(1, merchant && !complete ? 1 : 8)
      owner[field] = selected
      slots
    end

    def self.validate_open!(opening, complete:)
      PurchaseBinding.send(:exact!, opening, %w[cnf constraints exp iat vct])
      raise Invalid unless opening["vct"] == "mandate.checkout.open.1"
      PurchaseBinding.send(:times!, opening, opening["iat"])
      PurchaseBinding.send(:exact!, opening["cnf"], ["jwk"])
      jwk = opening["cnf"]["jwk"]
      PurchaseBinding.send(:exact!, jwk, %w[kty crv x y])
      raise Invalid unless jwk["kty"] == "EC" && jwk["crv"] == "P-256" &&
        %w[x y].all? { |f| RootSignature.send(:decode!, jwk[f], 32).bytesize == 32 }
      cs = opening["constraints"]
      raise Invalid unless cs.instance_of?(Array) && cs.size == 2
      PurchaseBinding.send(:exact!, cs[1], %w[type allowed])
      raise Invalid unless cs[1]["type"] == "checkout.allowed_merchants"
      merchants = cs[1]["allowed"]
      raise Invalid unless merchants.instance_of?(Array) && merchants.size.between?(1, complete ? 8 : 1)
      ScopedConstraints.send(:unique_ids!, merchants)
      merchants.each do |m|
        PurchaseBinding.send(:exact!, m, %w[id name]); ScopedConstraints.send(:text!, m["name"], 512)
      end
      # Reuse the reviewed multi-item grammar with each approved merchant.
      merchants.each do |m|
        ScopedConstraints.send(:multi_open!, [cs[0], {"type" => "checkout.allowed_merchants", "allowed" => [m]}])
      end
    end
    def self.index!(slots, n)
      raise Invalid unless Object.instance_method(:instance_of?).bind_call(n, Integer) && n.between?(0, slots.size - 1)
      slots.fetch(n)
    end
    def self.hash!(h)
      raise Invalid unless h.instance_of?(String) && h.match?(/\A[A-Za-z0-9_-]{43}\z/) && RootSignature.send(:decode!, h, 32).bytesize == 32
    end
    def self.disclose!(value, disclosures)
      require "securerandom"
      part = encode([encode(SecureRandom.random_bytes(16)), value])
      disclosures << part
      {"..." => digest(part)}
    end
    def self.encode(value) = Buyer.send(:encode, value)
    def self.digest(value) = Payment.send(:digest, value)

    %i[issue_open select select_for_checkout issue_closed present].each do |name|
      implementation = method(name)
      fields = implementation.parameters.map(&:last).freeze
      define_singleton_method(name) do |**args|
        raise Invalid unless (fields - args.keys).empty? && (args.keys - fields).empty?
        implementation.call(**args)
      rescue StandardError, LoadError
        raise Invalid.new, cause: nil
      end
    end
    singleton_methods(false).reject { |n| %i[issue_open select select_for_checkout issue_closed present].include?(n) }.each { |n| private_class_method n }
  end
end
