# frozen_string_literal: true

module AP2MandateVerifier
  # Hand-checked closed subset of pinned b4587ac1 AP2/UCP schemas, not a
  # general JSON Schema evaluator. One Merchant/SKU, no tax/discount/links.
  module ScopedConstraints
    MAX_AMOUNT = 9_007_199_254_740_991
    MAX_QUANTITY = 1_000_000
    MULTI_PROFILE_REF = "ap2.checkout.single_merchant_multi_item"
    MAX_LINES = 8
    MAX_REQUIREMENTS = 8
    MAX_CANDIDATES = 8
    CURRENCIES = %w[USD EUR JPY].freeze
    CORE_INSTANCE_OF = Object.instance_method(:instance_of?)
    class Rejected < RootSignature::Rejected; end

    def self.check!(**inputs)
      verified_constraints!(**inputs)
      nil
    end

    # Internal claims handoff after the complete existing limited profile.
    def self.verified_constraints!(expected_currency:, expected_total_minor:, profile_ref: TrustContext::PROFILE_REF, **binding_inputs)
      begin
        currency = InputValidator.snapshot!(expected_currency, max_bytes: 3)
      rescue InputValidator::Invalid
        raise RootSignature::Unavailable, :constraint_context_unavailable
      end
      raise RootSignature::Unavailable, :constraint_context_unavailable unless
        CURRENCIES.include?(currency) && CORE_INSTANCE_OF.bind_call(expected_total_minor, Integer) &&
        expected_total_minor.between?(0, MAX_AMOUNT)
      if profile_ref == MULTI_PROFILE_REF
        details = PurchaseBinding.verified_details!(**binding_inputs, profile_ref: profile_ref)
        multi_constraints!(details, currency, expected_total_minor)
        return details
      end
      raise Rejected, :unsupported_scoped_profile unless profile_ref == TrustContext::PROFILE_REF
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

    # New profile only. IDs identify products; titles are descriptive text.
    # Original arrays remain intact; this graph is solely a quantity proof.
    def self.multi_constraints!(details, currency, expected_total)
      open, checkout = details.values_at(:open, :checkout)
      constraints = open["constraints"]
      raise Rejected, :unsupported_constraint unless constraints.instance_of?(Array) && constraints.size == 2
      required, allowed = constraints
      exact!(required, %w[items type])
      exact!(allowed, %w[allowed type])
      raise Rejected, :unsupported_constraint unless required["type"] == "checkout.line_items" && allowed["type"] == "checkout.allowed_merchants"
      requirements = bounded_array!(required["items"], MAX_REQUIREMENTS)
      unique_ids!(requirements)
      requirements.each do |requirement|
        exact!(requirement, %w[acceptable_items id quantity])
        quantity!(requirement["quantity"])
        candidates = bounded_array!(requirement["acceptable_items"], MAX_CANDIDATES)
        unique_ids!(candidates)
        candidates.each do |candidate|
          exact!(candidate, %w[id title])
          text!(candidate["title"], 512)
        end
      end
      merchant = one!(allowed["allowed"])
      exact!(merchant, %w[id name])
      text!(merchant["id"])
      text!(merchant["name"], 512)
      raise Rejected, :constraint_mismatch unless checkout["merchant"] == merchant
      raise Rejected, :currency_mismatch unless checkout["currency"] == currency
      amount = multi_checkout!(checkout)
      raise Rejected, :amount_mismatch unless amount == expected_total
      quantities_match!(requirements, checkout["line_items"])
    end

    # Also shared with the explicitly selected merchant signing profile.
    def self.multi_checkout!(checkout)
      exact!(checkout, %w[currency id line_items links merchant status totals])
      text!(checkout["id"])
      exact!(checkout["merchant"], %w[id name])
      text!(checkout["merchant"]["id"])
      text!(checkout["merchant"]["name"], 512)
      text!(checkout["currency"], 3)
      raise Rejected, :unsupported_scoped_profile unless CURRENCIES.include?(checkout["currency"]) &&
        checkout["status"] == "ready_for_complete"
      raise Rejected, :invalid_scoped_schema unless checkout["links"].instance_of?(Array)
      raise Rejected, :unsupported_scoped_profile unless checkout["links"].empty?
      lines = bounded_array!(checkout["line_items"], MAX_LINES)
      unique_ids!(lines)
      amount = 0
      lines.each do |line|
        exact!(line, %w[id item quantity totals])
        quantity!(line["quantity"])
        item = line["item"]
        exact!(item, %w[id price title])
        text!(item["id"])
        text!(item["title"], 512)
        amount!(item["price"])
        line_amount = item["price"] * line["quantity"]
        amount!(line_amount)
        totals!(line["totals"], line_amount)
        amount += line_amount
        amount!(amount)
      end
      totals!(checkout["totals"], amount)
      amount
    end

    def self.bounded_array!(value, limit)
      raise Rejected, :invalid_scoped_schema unless value.instance_of?(Array)
      raise Rejected, :constraint_limit_exceeded unless value.length.between?(1, limit)
      value
    end

    def self.unique_ids!(values)
      ids = values.map do |value|
        raise Rejected, :invalid_scoped_schema unless value.instance_of?(Hash)
        text!(value["id"])
        value["id"]
      end
      raise Rejected, :invalid_scoped_schema unless ids.uniq.length == ids.length
    end

    # Integral max flow with reverse residual edges avoids greedy false rejects.
    # At most 18 vertices, 64 candidate edges; capacities never expand per unit.
    def self.quantities_match!(requirements, lines)
      demand = requirements.sum { |requirement| requirement["quantity"] }
      supply = lines.sum { |line| line["quantity"] }
      raise Rejected, :constraint_mismatch unless demand == supply
      sink = 1 + requirements.length + lines.length
      residual = Array.new(sink + 1) { Array.new(sink + 1, 0) }
      requirements.each_with_index do |requirement, i|
        r = i + 1
        residual[0][r] = requirement["quantity"]
        ids = requirement["acceptable_items"].map { |candidate| candidate["id"] }
        lines.each_with_index do |line, j|
          residual[r][requirements.length + j + 1] = demand if ids.include?(line["item"]["id"])
        end
      end
      lines.each_with_index { |line, j| residual[requirements.length + j + 1][sink] = line["quantity"] }
      flow = 0
      loop do
        parents = Array.new(sink + 1)
        parents[0] = 0
        queue = [0]
        until queue.empty? || parents[sink]
          u = queue.shift
          residual[u].each_with_index do |capacity, v|
            next unless capacity > 0 && parents[v].nil?
            parents[v] = u
            queue << v
          end
        end
        break unless parents[sink]
        amount, v = demand, sink
        until v == 0
          u = parents[v]
          amount = [amount, residual[u][v]].min
          v = u
        end
        v = sink
        until v == 0
          u = parents[v]
          residual[u][v] -= amount
          residual[v][u] += amount
          v = u
        end
        flow += amount
      end
      raise Rejected, :constraint_mismatch unless flow == demand
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
    private_class_method :exact!, :one!, :text!, :quantity!, :amount!, :totals!,
      :multi_constraints!, :bounded_array!, :unique_ids!, :quantities_match!
    private_constant :CORE_INSTANCE_OF
  end
end
