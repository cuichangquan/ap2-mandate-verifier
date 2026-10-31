# frozen_string_literal: true
require "json"
require "openssl"
require_relative "../lib/ap2_mandate_verifier"

module MultiConstraintsTest
  C = AP2MandateVerifier::ScopedConstraints
  @cases = 0
  def self.assert(value)
    raise "multi constraints assertion" unless value
    @cases += 1
  end
  def self.totals(amount) = %w[subtotal total].map { |type| {"type" => type, "amount" => amount} }
  def self.requirement(id, quantity, candidates)
    {"id" => id, "quantity" => quantity,
      "acceptable_items" => candidates.map { |sku| {"id" => sku, "title" => "Allowed #{sku}"} }}
  end
  def self.line(id, sku, quantity, price = 100)
    {"id" => id, "quantity" => quantity, "item" => {"id" => sku, "title" => "Merchant #{sku}", "price" => price},
      "totals" => totals(quantity * price)}
  end
  def self.checkout(lines)
    {"id" => "order", "merchant" => {"id" => "shop", "name" => "Shop"}, "status" => "ready_for_complete",
      "currency" => "USD", "links" => [], "line_items" => lines,
      "totals" => totals(lines.sum { |row| row["quantity"] * row["item"]["price"] })}
  end
  def self.check(requirements, lines)
    body = checkout(lines)
    C.send(:multi_constraints!, {open: {"constraints" => [
      {"type" => "checkout.line_items", "items" => requirements},
      {"type" => "checkout.allowed_merchants", "allowed" => [body["merchant"]]}]}, checkout: body},
      "USD", body["totals"][0]["amount"])
    assert(true)
  end
  def self.reject(code)
    yield
    raise "multi constraints accepted invalid data"
  rescue C::Rejected => error
    assert(error.code == code)
  end

  # Independent hand-labelled allocation: B fills flexible req, A fills A-only.
  flexible = requirement("flexible", 1, %w[A B])
  fixed = requirement("fixed", 1, %w[A])
  a, b = line("row-A", "A", 1), line("row-B", "B", 1)
  [ [flexible, fixed], [fixed, flexible] ].each do |requirements|
    [ [a, b], [b, a] ].each { |lines| check(requirements, lines) }
  end
  check([requirement("req", 3, %w[A])], [line("one", "A", 1), line("two", "A", 2)])
  check([requirement("one", 2, %w[A B]), requirement("two", 3, %w[B])], [line("a", "A", 2), line("b", "B", 3)])
  reject(:constraint_mismatch) { check([flexible, fixed], [line("b1", "B", 1), line("b2", "B", 1)]) }
  reject(:constraint_mismatch) { check([fixed], [a, b]) }
  reject(:constraint_mismatch) { check([fixed, requirement("r2", 1, %w[A])], [a]) }
  reject(:invalid_scoped_schema) { check([fixed, fixed], [a, b]) }
  reject(:invalid_scoped_schema) { check([flexible, fixed], [a, a]) }
  reject(:invalid_scoped_schema) { check([requirement("r", 1, %w[A A])], [a]) }
  reject(:unsupported_scoped_profile) { check([fixed.merge("future" => true)], [a]) }
  reject(:constraint_limit_exceeded) { check(Array.new(9) { |i| requirement("r#{i}", 1, %w[A]) }, [line("a", "A", 9)]) }
  reject(:constraint_limit_exceeded) { check([requirement("r", 9, %w[A])], Array.new(9) { |i| line("l#{i}", "A", 1) }) }
  reject(:constraint_limit_exceeded) { check([requirement("r", 1, Array.new(9) { |i| "p#{i}" })], [a]) }
  check(Array.new(8) { |i| requirement("r#{i}", 1, Array.new(8) { |j| "p#{j}" }) },
    Array.new(8) { |i| line("l#{i}", "p#{i}", 1) })
  # Separate exhaustive oracle: enumerate each physical unit's product choice,
  # rather than using flow or sharing its capacity construction.
  choices = [%w[A], %w[B], %w[A B]]
  choices.repeated_permutation(2) do |candidates|
    [1, 2, 3].repeated_permutation(2) do |quantities|
      total = quantities.sum
      (0..total).each do |a_count|
        products = quantities.each_with_index.flat_map { |q, i| Array.new(q) { candidates[i] } }
        counts = [0]
        products.each do |options|
          counts = counts.flat_map { |n| options.map { |sku| n + (sku == "A" ? 1 : 0) } }.uniq
        end
        expected = counts.include?(a_count)
        requirements = candidates.each_with_index.map { |ids, i| requirement("r#{i}", quantities[i], ids) }
        lines = []
        lines << line("a", "A", a_count) if a_count > 0
        lines << line("b", "B", total - a_count) if a_count < total
        observed = begin
          C.send(:quantities_match!, requirements, lines)
          true
        rescue C::Rejected => error
          raise unless error.code == :constraint_mismatch
          false
        end
        assert(observed == expected)
      end
    end
  end
  # Explicit-profile signing shares all line and aggregate amount checks.
  key = OpenSSL::PKey::EC.generate("prime256v1")
  api = AP2MandateVerifier::CheckoutJWT
  args = {signer: api.es256_signer(private_key: key), public_key_pem: key.public_to_pem}
  body = checkout([a, b])
  signed = api.sign(checkout: body, profile_ref: C::MULTI_PROFILE_REF, **args)
  assert(JWT.decode(signed.jwt, key, true, algorithms: ["ES256"]).first == body)
  [nil, "unknown", AP2MandateVerifier::TrustContext::PROFILE_REF].each do |profile|
    begin
      api.sign(checkout: body, profile_ref: profile, **args)
      raise "sign accepted wrong profile"
    rescue api::Invalid
      assert(true)
    end
  end
  ["quantity", "price", "total"].each do |field|
    changed = Marshal.load(Marshal.dump(body))
    row = changed["line_items"][1]
    case field
    when "quantity" then row["quantity"] = 1.0
    when "price" then row["item"]["price"] = -1
    when "total" then row["totals"][1]["amount"] = 99
    end
    begin
      api.sign(checkout: changed, profile_ref: C::MULTI_PROFILE_REF, **args)
      raise "sign accepted invalid later line"
    rescue api::Invalid
      assert(true)
    end
  end
  max = C::MAX_AMOUNT
  [checkout([line("max", "A", 2, max)]), checkout([line("max", "A", 1, max), line("plus", "B", 1, 1)])].each do |changed|
    reject(:constraint_limit_exceeded) { C.multi_checkout!(changed) }
  end
  puts "PASS #{@cases} multi quantity allocation, bounds, amount and signing assertions"
end
