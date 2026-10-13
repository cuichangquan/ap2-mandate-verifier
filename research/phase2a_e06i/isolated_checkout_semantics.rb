# frozen_string_literal: true
#
# E06-I A2-4 / G6: Host Checkout business-semantics candidate, RESEARCH ONLY.
# CODE WRITTEN / NOT RUN / NO CI APPROVAL / NEVER AUTHORIZES A PURCHASE.
#
# G6 will eventually accept ONLY opaque immutable G5 success + the SAME
# authoritative G1 Host snapshot. These trust-bearing types and their
# provenance are not yet implemented. This isolated inspector deliberately
# accepts untrusted candidate values and ALWAYS returns HOLD. Matching
# issuer/Host IDs, amount or a claimed Checkout status is NOT authorization.
# No p1_1/p1_2/p1_3 imports, no signing keys, no payment, no nonce CAS.

module AP2E06ICheckoutSemantics
  MAX_DEPTH = 24
  MAX_HASH = 32
  MAX_ARRAY = 16
  MAX_STRING = 32_768
  MAX_AMOUNT = 9_007_199_254_740_991

  OPEN_KEYS = %w[cnf constraints exp iat vct].freeze
  CONSTRAINT_KEYS = %w[items type].freeze
  ALLOWED_KEYS = %w[allowed type].freeze
  REQUIREMENT_KEYS = %w[acceptable_items id quantity].freeze
  MERCHANT_KEYS = %w[id name].freeze
  SKU_KEYS = %w[id title].freeze
  CHECKOUT_KEYS = %w[currency id line_items links merchant status totals].freeze
  LINE_KEYS = %w[id item quantity totals].freeze
  ITEM_KEYS = %w[id price title].freeze
  TOTAL_KEYS = %w[amount type].freeze
  TOTAL_TYPES = %w[subtotal total].freeze
  REF_KEYS = %w[checkout_id checkout_version tenant_id].freeze
  HOST_CHECKOUT_KEYS = %w[
    amount_minor buyer_account_ref currency expected_status merchant_id
    original_jwt quantity ref sku_id sku_title
  ].sort.freeze

  class Rejected < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  class SemanticsCandidate
    def status
      "HOLD"
    end

    def reason
      "authenticated_g1_g4_g5_provenance_unavailable"
    end

    def g6_success?
      false
    end

    def evidence
      nil
    end
  end

  class Gate
    # Shape and comparisons are inspected only. NEVER call this with
    # a caller-created "G5_VALID" label as if it were a trusted success.
    # The later orchestrator must verify real G1/G4/G5 stages itself.
    def inspect_candidate!(candidate_open:, candidate_checkout_payload:,
                           candidate_host_snapshot:)
      open = detached!(candidate_open)
      checkout = detached!(candidate_checkout_payload)
      snapshot = detached!(candidate_host_snapshot)

      exact!(snapshot, %w[
        agent_trust challenge checkout issuer_trust merchant_trust
        nonce_issuance profile_ref
      ], "unsupported_host_snapshot")
      reject!("unsupported_host_profile") unless
        snapshot["profile_ref"] == "e06i-fixed-issuer-a-v1"

      host_checkout = snapshot.fetch("checkout")
      host_challenge = snapshot.fetch("challenge")
      host_merchant = snapshot.fetch("merchant_trust")
      exact!(host_checkout, HOST_CHECKOUT_KEYS, "unsupported_host_checkout")
      exact_ref!(host_checkout.fetch("ref"))
      exact_ref!(host_challenge.fetch("checkout_ref"))
      reject!("challenge_checkout_tuple_mismatch") unless
        host_challenge.fetch("checkout_ref") == host_checkout.fetch("ref")
      reject!("challenge_buyer_account_mismatch") unless
        same_present_string?(host_challenge.fetch("buyer_account_ref"),
                             host_checkout.fetch("buyer_account_ref"))
      reject!("host_merchant_tenant_mismatch") unless
        same_present_string?(host_merchant.fetch("tenant_id"),
                             host_checkout.fetch("ref").fetch("tenant_id"))
      reject!("host_merchant_identity_mismatch") unless
        same_present_string?(host_merchant.fetch("subject_ref"),
                             host_checkout.fetch("merchant_id"))

      # Even if those Host claims are self-consistent, they are NOT
      # Host-authenticated; an independent G1 is still mandatory.
      exact!(open, OPEN_KEYS, "unsupported_open_authority")
      reject!("unsupported_open_type") unless
        open["vct"] == "mandate.checkout.open.1"
      allowed_merchant, sku, required_qty = issuer_authority!(open)

      # The G5 local shape-only module already defines this closed-world
      # Checkout layout. Repeat the critical constraints here for safe
      # standalone observation; this does NOT constitute a G5 success.
      exact!(checkout, CHECKOUT_KEYS, "unsupported_checkout_fields")
      reject!("wrong_checkout_id") unless
        same_present_string?(checkout["id"],
                             host_checkout.fetch("ref").fetch("checkout_id"))
      reject!("wrong_checkout_status") unless
        checkout["status"] == "ready_for_complete" &&
        checkout["status"] == host_checkout.fetch("expected_status")
      reject!("wrong_checkout_currency") unless
        same_present_string?(checkout["currency"], host_checkout.fetch("currency"))

      merchant = checkout.fetch("merchant")
      exact!(merchant, MERCHANT_KEYS, "unsupported_checkout_merchant")
      present_string!(merchant["name"])
      reject!("merchant_not_authorized") unless
        same_present_string?(merchant["id"], allowed_merchant.fetch("id")) &&
        same_present_string?(merchant["id"], host_checkout.fetch("merchant_id"))

      lines = checkout.fetch("line_items")
      reject!("unsupported_checkout_line_count") unless
        lines.is_a?(Array) && lines.length == 1
      line = lines.fetch(0)
      exact!(line, LINE_KEYS, "unsupported_checkout_line")
      present_string!(line["id"])
      product = line.fetch("item")
      exact!(product, ITEM_KEYS, "unsupported_checkout_product")
      reject!("sku_not_authorized") unless
        same_present_string?(product["id"], sku.fetch("id")) &&
        same_present_string?(product["id"], host_checkout.fetch("sku_id")) &&
        same_present_string?(product["title"], sku.fetch("title")) &&
        same_present_string?(product["title"], host_checkout.fetch("sku_title"))

      quantity = line.fetch("quantity")
      reject!("invalid_or_unauthorized_quantity") unless
        positive_int?(quantity, 16) && quantity == required_qty &&
        quantity == host_checkout.fetch("quantity")
      unit_price = product.fetch("price")
      reject!("invalid_checkout_unit_price") unless
        positive_int?(unit_price, MAX_AMOUNT)
      expected_total = host_checkout.fetch("amount_minor")
      reject!("invalid_host_expected_amount") unless
        positive_int?(expected_total, MAX_AMOUNT)

      # Ruby Integer is unbounded; enforce the fixed positive money bound
      # BEFORE treating a product as an accepted minor-unit amount.
      amount = unit_price * quantity
      reject!("amount_out_of_bounds") unless positive_int?(amount, MAX_AMOUNT)
      reject!("host_expected_amount_mismatch") unless amount == expected_total
      validate_totals!(line.fetch("totals"), amount, "line")
      validate_totals!(checkout.fetch("totals"), amount, "checkout")
      reject!("unsupported_checkout_links") unless checkout.fetch("links") == []

      # Only a typed, independently verified G5Result and immutable approved
      # G1/G4 result may be connected to a future G6 success. In this PR the
      # matching semantics are an untrusted offline candidate, always HOLD.
      SemanticsCandidate.new.freeze
    rescue Rejected
      raise
    rescue KeyError, ArgumentError, TypeError, RangeError
      raise Rejected, "invalid_checkout_or_host_candidate"
    end

    private

    def reject!(reason)
      raise Rejected, reason
    end

    def exact!(obj, keys, reason)
      reject!(reason) unless
        obj.is_a?(Hash) && obj.keys.sort == keys.sort
    end

    def present_string!(str)
      reject!("invalid_required_string") unless
        str.is_a?(String) && str.bytesize.between?(1, 256)
    end

    def same_present_string?(a, b)
      a.is_a?(String) && b.is_a?(String) &&
        a.bytesize.between?(1, 256) && a == b
    end

    def positive_int?(v, upper)
      v.is_a?(Integer) && v.between?(1, upper)
    end

    def exact_ref!(ref)
      exact!(ref, REF_KEYS, "invalid_host_checkout_tuple")
      reject!("invalid_host_checkout_tuple") unless
        %w[checkout_id tenant_id].all? do |name|
          str = ref[name]
          str.is_a?(String) && str.bytesize.between?(1, 256)
        end &&
        positive_int?(ref["checkout_version"], 1_000_000)
    end

    def issuer_authority!(open)
      constraints = open.fetch("constraints")
      reject!("unsupported_issuer_constraint_count") unless
        constraints.is_a?(Array) && constraints.length == 2
      required, allowed = constraints
      exact!(required, CONSTRAINT_KEYS, "unsupported_line_constraint")
      exact!(allowed, ALLOWED_KEYS, "unsupported_merchant_constraint")
      reject!("wrong_constraint_order") unless
        required["type"] == "checkout.line_items" &&
        allowed["type"] == "checkout.allowed_merchants"

      merchant_options = allowed.fetch("allowed")
      reject!("unsupported_merchant_count") unless
        merchant_options.is_a?(Array) && merchant_options.length == 1
      merchant = merchant_options.fetch(0)
      exact!(merchant, MERCHANT_KEYS, "unsupported_issuer_merchant")
      present_string!(merchant.fetch("id"))
      present_string!(merchant.fetch("name"))

      required_items = required.fetch("items")
      reject!("unsupported_requirement_count") unless
        required_items.is_a?(Array) && required_items.length == 1
      req = required_items.fetch(0)
      exact!(req, REQUIREMENT_KEYS, "unsupported_issuer_requirement")
      present_string!(req.fetch("id"))
      reject!("invalid_issuer_quantity") unless
        positive_int?(req["quantity"], 16)

      alternatives = req.fetch("acceptable_items")
      reject!("unsupported_sku_count") unless
        alternatives.is_a?(Array) && alternatives.length == 1
      sku = alternatives.fetch(0)
      exact!(sku, SKU_KEYS, "unsupported_issuer_sku")
      present_string!(sku.fetch("id"))
      present_string!(sku.fetch("title"))
      [merchant, sku, req.fetch("quantity")]
    end

    def validate_totals!(totals, amount, level)
      reject!("unsupported_#{level}_totals") unless
        totals.is_a?(Array) && totals.length == 2
      names = []
      totals.each do |total|
        exact!(total, TOTAL_KEYS, "unsupported_#{level}_total_keys")
        name = total.fetch("type")
        reject!("unsupported_#{level}_total_label") unless
          TOTAL_TYPES.include?(name)
        reject!("mismatched_#{level}_total_amount") unless
          total.fetch("amount").is_a?(Integer) &&
          total.fetch("amount") == amount
        names << name
      end
      reject!("duplicate_or_missing_#{level}_total") unless
        names.sort == TOTAL_TYPES
    end

    def detached!(value, depth = 0)
      reject!("input_resource_limit") if depth > MAX_DEPTH
      case value
      when Hash
        reject!("input_resource_limit") if value.size > MAX_HASH
        value.each_with_object({}) do |(key, member), result|
          reject!("invalid_candidate_key") unless key.is_a?(String)
          result[key.dup.freeze] = detached!(member, depth + 1)
        end.freeze
      when Array
        reject!("input_resource_limit") if value.length > MAX_ARRAY
        value.map { |member| detached!(member, depth + 1) }.freeze
      when String
        copy = value.dup.freeze
        reject!("input_resource_limit") if copy.bytesize > MAX_STRING
        copy
      when Integer, NilClass, TrueClass, FalseClass
        value
      else
        reject!("unsupported_candidate_type")
      end
    end
  end
end
