# frozen_string_literal: true

module AP2MandateVerifier
  # Hand-checked closed subset of pinned b4587ac1 AP2/UCP schemas, not a
  # general JSON Schema evaluator. One Merchant/SKU, no tax/discount/links.
  module ScopedConstraints
    MAX_AMOUNT = 9_007_199_254_740_991
    MAX_QUANTITY = 1_000_000
    CURRENCIES = %w[USD EUR JPY].freeze
    CORE_INSTANCE_OF = Object.instance_method(:instance_of?)
    class Rejected < RootSignature::Rejected; end

    def self.check!(**inputs)
      verified_constraints!(**inputs)
      nil
    end

    # Internal claims handoff after the complete existing limited profile.
    def self.verified_constraints!(expected_currency:, expected_total_minor:, **binding_inputs)
      begin
        currency = InputValidator.snapshot!(expected_currency, max_bytes: 3)
      rescue InputValidator::Invalid
        raise RootSignature::Unavailable, :constraint_context_unavailable
      end
      raise RootSignature::Unavailable, :constraint_context_unavailable unless
        CURRENCIES.include?(currency) && CORE_INSTANCE_OF.bind_call(expected_total_minor, Integer) &&
        expected_total_minor.between?(0, MAX_AMOUNT)
      details = PurchaseBinding.verified_details!(**binding_inputs)
      open, checkout = details.values_at(:open, :checkout)
      constraints = open["constraints"]
      raise Rejected, :unsupported_constraint unless constraints.instance_of?(Array) && constraints.size == 2
      required, allowed = constraints
      raise Rejected, :invalid_scoped_schema unless required.instance_of?(Hash) && allowed.instance_of?(Hash)
      raise Rejected, :unsupported_constraint unless required["type"] == "checkout.line_items" &&
        allowed["type"] == "checkout.allowed_merchants"
      exact!(required, %w[items type])
      exact!(allowed, %w[allowed type])
      requirement = one!(required["items"])
      exact!(requirement, %w[acceptable_items id quantity])
      text!(requirement["id"]) # S01: signature VALID does not make id=123 valid.
      quantity!(requirement["quantity"])
      sku = one!(requirement["acceptable_items"])
      exact!(sku, %w[id title])
      text!(sku["id"])
      text!(sku["title"], 512)
      merchant = one!(allowed["allowed"])
      exact!(merchant, %w[id name])
      text!(merchant["id"])
      text!(merchant["name"], 512)

      text!(checkout["id"])
      text!(checkout["merchant"]["id"])
      text!(checkout["merchant"]["name"], 512)
      raise Rejected, :constraint_mismatch unless checkout["merchant"] == merchant
      text!(checkout["currency"], 3)
      raise Rejected, :unsupported_scoped_profile unless CURRENCIES.include?(checkout["currency"])
      raise Rejected, :currency_mismatch unless checkout["currency"] == currency
      raise Rejected, :invalid_scoped_schema unless checkout["links"].instance_of?(Array)
      raise Rejected, :unsupported_scoped_profile unless checkout["links"].empty?
      line = one!(checkout["line_items"])
      exact!(line, %w[id item quantity totals])
      text!(line["id"])
      quantity!(line["quantity"])
      product = line["item"]
      exact!(product, %w[id price title])
      text!(product["id"])
      text!(product["title"], 512)
      amount!(product["price"])
      raise Rejected, :constraint_mismatch unless product["id"] == sku["id"] &&
        product["title"] == sku["title"] && line["quantity"] == requirement["quantity"]
      amount = product["price"] * line["quantity"]
      raise Rejected, :constraint_limit_exceeded if amount > MAX_AMOUNT
      raise Rejected, :amount_mismatch unless amount == expected_total_minor
      totals!(line["totals"], amount)
      totals!(checkout["totals"], amount)
      details
    end

    def self.exact!(value, fields)
      raise Rejected, :invalid_scoped_schema unless value.instance_of?(Hash) && (fields - value.keys).empty?
      raise Rejected, :unsupported_scoped_profile unless (value.keys - fields).empty?
    end
    def self.one!(value)
      raise Rejected, :invalid_scoped_schema unless value.instance_of?(Array)
      raise Rejected, :unsupported_scoped_profile unless value.size == 1
      value.first
    end
    def self.text!(value, limit = 256)
      raise Rejected, :invalid_scoped_schema unless value.instance_of?(String) && !value.empty?
      raise Rejected, :constraint_limit_exceeded if value.bytesize > limit
    end
    def self.quantity!(value)
      raise Rejected, :invalid_scoped_schema unless value.instance_of?(Integer) && value > 0
      raise Rejected, :constraint_limit_exceeded if value > MAX_QUANTITY
    end
    def self.amount!(value)
      raise Rejected, :invalid_scoped_schema unless value.instance_of?(Integer) && value >= 0
      raise Rejected, :constraint_limit_exceeded if value > MAX_AMOUNT
    end
    def self.totals!(values, expected)
      raise Rejected, :invalid_scoped_schema unless values.instance_of?(Array)
      raise Rejected, :unsupported_scoped_profile unless values.size == 2
      values.each do |entry|
        exact!(entry, %w[amount type])
        text!(entry["type"])
        amount!(entry["amount"])
      end
      raise Rejected, :unsupported_scoped_profile unless values.map { |entry| entry["type"] }.sort == %w[subtotal total]
      raise Rejected, :amount_mismatch unless values.all? { |entry| entry["amount"] == expected }
    end
    private_class_method :exact!, :one!, :text!, :quantity!, :amount!, :totals!
    private_constant :CORE_INSTANCE_OF
  end
end
