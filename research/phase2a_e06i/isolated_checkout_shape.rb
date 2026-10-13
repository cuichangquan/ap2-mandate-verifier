# frozen_string_literal: true
#
# E06-I A2-2: local Checkout JWT payload SHAPE ONLY, not official AP2 Schema.
# RESEARCH-ONLY / NOT RUN / NO CI APPROVAL / NO AUTHENTICATION / NO EVIDENCE.
#
# This must receive a G4-authenticated and immutable Checkout payload in a
# later, separately reviewed integration. Passing an arbitrary Hash here
# cannot prove a Merchant signature, G5 official Open/Closed Schema validity,
# Issuer authorization, Host business semantics or payment authorization.
# Never pass this ShapeOnly result directly to G6/G7 as a "G5 success".
require "json"

module AP2E06ILocalCheckoutShape
  ROOT_KEYS = %w[currency id line_items links merchant status totals].freeze
  MERCHANT_KEYS = %w[id name].freeze
  LINE_KEYS = %w[id item quantity totals].freeze
  ITEM_KEYS = %w[id price title].freeze
  TOTAL_KEYS = %w[amount type].freeze
  TOTAL_TYPES = %w[subtotal total].freeze
  MAX_CHECKOUT_BYTES = 16_384

  class Rejected < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  # Internal, shape-only observation. Not a G5 or G7 authorization artifact.
  class ShapeOnly
    def local_checkout_shape
      "VALID"
    end

    def authority
      "NONE_SHAPE_ONLY"
    end

    def authenticated?
      false
    end

    def evidence
      nil
    end
  end

  class Gate
    # Contractual name matches B2's proposed internal G5 checker entrypoint.
    # The orchestrator (not this standalone Gate) must enforce that the
    # incoming payload came from a successfully authenticated G4 result and
    # that the official pinned Open+Closed+nested Merchant schemas passed.
    def check!(verified_checkout_payload:)
      payload = verified_checkout_payload
      exact_keys!(payload, ROOT_KEYS)
      # String/number shape checks are conservative lab-only restrictions;
      # comparing IDs, status, amount or inventory to Host belongs to G6.
      present_string!(payload["id"])
      present_string!(payload["status"])
      present_string!(payload["currency"])

      merchant = payload.fetch("merchant")
      exact_keys!(merchant, MERCHANT_KEYS)
      present_string!(merchant["id"])
      present_string!(merchant["name"])

      lines = payload.fetch("line_items")
      reject!("unsupported_checkout_line_count") unless
        lines.is_a?(Array) && lines.length == 1
      line = lines.fetch(0)
      exact_keys!(line, LINE_KEYS)
      present_string!(line["id"])
      reject!("invalid_checkout_quantity_type") unless
        line["quantity"].is_a?(Integer)

      item = line.fetch("item")
      exact_keys!(item, ITEM_KEYS)
      present_string!(item["id"])
      present_string!(item["title"])
      reject!("invalid_checkout_price_type") unless
        item["price"].is_a?(Integer)

      totals_shape!(line.fetch("totals"), "line")
      totals_shape!(payload.fetch("totals"), "checkout")

      # Existing P1-3 checked presence of links but did not evaluate link
      # semantics. This narrower, fixed lab profile accepts NO linked
      # follow-up actions so unreviewed URL/payment authority is not ignored.
      # The historical P1-3 normal fixture contains links=[].
      reject!("unsupported_checkout_links") unless payload["links"] == []

      # Cap the complete payload as well; G0 also enforces independent wire
      # and nested resource limits before any authenticity claims.
      reject!("checkout_shape_resource_limit") unless
        JSON.generate(payload).bytesize.between?(1, MAX_CHECKOUT_BYTES)

      ShapeOnly.new.freeze
    rescue Rejected
      raise
    rescue KeyError, TypeError, ArgumentError, JSON::GeneratorError
      reject!("invalid_checkout_shape")
    end

    private

    def reject!(code)
      raise Rejected.new(code)
    end

    def exact_keys!(obj, keys)
      reject!("unsupported_checkout_fields") unless
        obj.is_a?(Hash) && obj.keys.sort == keys
    end

    def present_string!(value)
      reject!("invalid_checkout_string") unless
        value.is_a?(String) && !value.empty? && value.bytesize <= 256
    end

    def totals_shape!(totals, level)
      reject!("invalid_#{level}_totals_shape") unless
        totals.is_a?(Array) && totals.length == 2
      labels = []
      totals.each do |item|
        exact_keys!(item, TOTAL_KEYS)
        reject!("invalid_#{level}_total_type") unless
          item["type"].is_a?(String) && TOTAL_TYPES.include?(item["type"])
        reject!("invalid_#{level}_total_amount_type") unless
          item["amount"].is_a?(Integer)
        labels << item["type"]
      end
      reject!("invalid_#{level}_total_labels") unless
        labels.sort == TOTAL_TYPES
      # The mathematical amount == positive(price*quantity), equality of
      # line/checkout subtotal/total and Host expected total are G6 ONLY.
    end
  end
end
