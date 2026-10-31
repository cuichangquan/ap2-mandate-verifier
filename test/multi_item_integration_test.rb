# frozen_string_literal: true
require_relative "support/multi_item_fixture"

module MultiItemIntegrationTest
  F = MultiItemFixture
  B = AP2MandateVerifier::InputBuilder
  R = AP2MandateVerifier::CheckoutReceipt
  @cases = 0
  def self.assert(value, label)
    raise "multi-item integration: #{label}" unless value
  end
  def self.verdict(model, success, label, code = nil)
    result = B.verify(**model.fetch(:args))
    assert(result.success? == success, "#{label}: #{result.status}/#{result.code}")
    assert(result.code == code, "#{label}: expected #{code}, got #{result.code}") if code
    assert(result.evidence.nil?, "#{label}: no Evidence on failure") unless success
    @cases += 1
    result
  end
  normal = F.build
  evidence = verdict(normal, true, "multiple products and unequal quantities").evidence
  assert(evidence["profile_ref"] == F::PROFILE, "explicit profile in Evidence")
  assert(evidence["checkout_jwt_digest"] == Digest::SHA256.hexdigest(normal[:args][:host_checkout_jws]), "original checkout digest")
  assert(evidence["root_presentation_digest"] == Digest::SHA256.hexdigest(normal[:args][:root_presentation]), "original root digest")
  saved = normal[:args][:saved_challenge]
  assert(B.restore(saved_challenge: " \n" + saved) == " \n" + saved, "saved bytes preserved")
  restored = B.restore_trust(trust_json: normal[:args][:trust].trust_json, selection_json: normal[:args][:trust].selection_json, verified_at: F::NOW)
  verdict(normal.merge(args: normal[:args].merge(trust: restored)), true, "restored trust and challenge")

  split = F.checkout([F.line("A-1", "A", 1), F.line("B-1", "B", 1, 250), F.line("A-2", "A", 1)])
  verdict(F.build(checkout: split), true, "same product on distinct lines")
  reversed = F.checkout(F.checkout["line_items"].reverse)
  verdict(F.build(checkout: reversed), true, "separately signed reverse order")
  greedy = [F.requirement("either", 1, %w[A B]), F.requirement("only-A", 1, %w[A])]
  verdict(F.build(requirements: greedy, checkout: F.checkout([F.line("A", "A", 1), F.line("B", "B", 1)])), true, "non-greedy overlap")

  [0, 1, 3].each do |qty|
    req = F.copy(F.requirements); req[1]["quantity"] = qty
    verdict(F.build(requirements: req), false, "second requirement quantity #{qty}")
  end
  [1, 3].each do |qty|
    changed = F.checkout([F.line("A", "A", qty), F.line("B", "B", 1, 250)])
    verdict(F.build(checkout: changed), false, "under/over checkout quantity #{qty}")
  end
  verdict(F.build(checkout: F.checkout([F.line("A", "A", 2)])), false, "missing second product")
  verdict(F.build(checkout: F.checkout([F.line("A", "A", 2), F.line("B", "B", 1), F.line("C", "C", 1)])), false, "extra product")
  req = F.copy(F.requirements); req[1]["id"] = req[0]["id"]
  verdict(F.build(requirements: req), false, "duplicate requirement id")
  req = F.copy(F.requirements); req[1]["acceptable_items"] << F.item("A")
  verdict(F.build(requirements: req), false, "duplicate candidate id")
  duplicate = F.checkout([F.line("same", "A", 2), F.line("same", "B", 1)])
  verdict(F.build(checkout: duplicate, raw_checkout: true), false, "duplicate line id")
  unknown = F.build(open_transform: ->(open) { open["constraints"][1]["future"] = true })
  verdict(unknown, false, "unknown second constraint field")
  verdict(F.build(open_transform: ->(open) { open["constraints"][1]["type"] = "checkout.future" }), false, "unknown second constraint type")
  ["price", "quantity", "totals"].each do |field|
    changed = F.copy(F.checkout)
    case field
    when "price" then changed["line_items"][1]["item"]["price"] = 250.0
    when "quantity" then changed["line_items"][1]["quantity"] = "1"
    when "totals" then changed["line_items"][1]["totals"] = F.totals(249)
    end
    verdict(F.build(checkout: changed, raw_checkout: true), false, "second line invalid #{field}")
  end
  changed = F.copy(F.checkout); changed["currency"] = "EUR"
  verdict(F.build(checkout: changed), false, "signed currency versus independent Host", :currency_mismatch)
  changed = F.copy(F.checkout); changed["line_items"][1]["tax"] = 1
  verdict(F.build(checkout: changed, raw_checkout: true), false, "unsupported monetary item not ignored")

  missing = F.build(root_transform: ->(wire) { parts = wire.split("~", -1); parts.delete_at(4); parts.join("~") })
  verdict(missing, false, "missing second requirement disclosure", :missing_disclosure)
  extra = F.build(root_transform: ->(wire) { parts = wire.split("~", -1); parts.insert(-2, F.disclose(F.item("C"), "unused")); parts.join("~") })
  verdict(extra, false, "unused disclosure", :extra_disclosure)
  reused = F.build(open_transform: ->(open) { open["constraints"][0]["items"][1]["acceptable_items"][0] = F.copy(open["constraints"][0]["items"][0]["acceptable_items"][0]) })
  verdict(reused, false, "another requirement's disclosure reused", :duplicate_commitment)
  inline = F.build(open_transform: ->(open) { open["constraints"][0]["items"][1]["acceptable_items"][0] = F.item("A") })
  verdict(inline, false, "required candidate commitment replaced with inline claim")

  tampered = F.build(checkout_wire_transform: lambda do |wire|
    parts = wire.split("."); claims = JSON.parse(Base64.urlsafe_decode64(parts[1])); claims["line_items"].reverse!
    parts[1] = F.b64(JSON.generate(claims)); parts.join(".")
  end)
  verdict(tampered, false, "post-signature line reordering")
  changed = F.copy(normal[:args][:order]); changed["expected_total"] += 1
  verdict(normal.merge(args: normal[:args].merge(order: changed)), false, "independent Host total drift", :host_binding_mismatch)
  bad = JSON.parse(saved); bad["challenge"]["profile_definition_hash"] = "0" * 64
  bad_wire = JSON.generate(bad)
  assert(B.restore(saved_challenge: bad_wire) == bad_wire, "restore never repairs saved digest")
  verdict(normal.merge(args: normal[:args].merge(saved_challenge: bad_wire)), false, "saved digest mismatch", :challenge_reference_mismatch)
  old_trust = B.trust(**normal[:trust_args].reject { |field, _| field == :profile_ref })
  verdict(normal.merge(args: normal[:args].merge(trust: old_trust)), false, "old trust with new saved challenge")

  boundary_req = 8.times.map { |i| F.requirement("r#{i}", 1, (0...8).map { |j| "p#{j}" }) }
  boundary_checkout = F.checkout(8.times.map { |i| F.line("l#{i}", "p#{i}", 1) })
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  boundary = F.build(requirements: boundary_req, checkout: boundary_checkout)
  verdict(boundary, true, "66 disclosures/8 requirements/8 lines/64 candidate edges")
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  assert(boundary[:args][:root_presentation].split("~", -1).length - 2 == 66, "boundary disclosure count")
  oversized = F.build(requirements: boundary_req + [F.requirement("r8", 1, ["p0"])], checkout: boundary_checkout)
  verdict(oversized, false, "ninth requirement rejected")
  too_many_disclosures = F.build(requirements: boundary_req, checkout: boundary_checkout,
    root_transform: ->(wire) { parts = wire.split("~", -1); parts.insert(-2, F.disclose(F.item("extra"), "67th")); parts.join("~") })
  verdict(too_many_disclosures, false, "67th disclosure rejected", :invalid_root_presentation)

  %w[Success Error].each do |outcome|
    args = {closed_sd_jwt: normal[:args][:terminal_jws] + "~", profile_ref: F::PROFILE, issuer: "shop", outcome: outcome,
      issued_at: F::NOW, signer: AP2MandateVerifier::CheckoutJWT.es256_signer(private_key: normal[:keys][2]), public_key_pem: normal[:keys][2].public_to_pem}
    outcome == "Success" ? args[:order_id] = "order" : args.merge!(error: "host_rejected", error_description: "Independent Host policy rejected this order")
    signed = R.sign(**args)
    result = R.verify(jwt: signed.jwt, closed_sd_jwt: args[:closed_sd_jwt], profile_ref: F::PROFILE,
      trusted_public_key_pem: args[:public_key_pem], expected_issuer: "shop", not_before: F::NOW - 1, not_after: F::NOW + 1, verified_at: F::NOW)
    assert(result.verified? && result.purchase_succeeded? == (outcome == "Success") && result.purchase_rejected? == (outcome == "Error"), "genuine #{outcome} Receipt")
    assert(signed.reference == F.hash(args[:closed_sd_jwt]), "Receipt original terminal plus trailing separator")
    old = R.verify(jwt: signed.jwt, closed_sd_jwt: args[:closed_sd_jwt], trusted_public_key_pem: args[:public_key_pem],
      expected_issuer: "shop", not_before: F::NOW - 1, not_after: F::NOW + 1, verified_at: F::NOW)
    assert(!old.verified?, "old Receipt default rejects multi-line Checkout")
    @cases += 1
  end
  puts "PASS #{@cases} multi-item integration cases; boundary root_bytes=#{boundary[:args][:root_presentation].bytesize} build_and_verify_seconds=#{elapsed.round(4)}; synthetic only, not Host ALLOW"
end
