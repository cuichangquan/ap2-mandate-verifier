# frozen_string_literal: true

require "json"
require "base64"
require "openssl"
require "digest"
require_relative "../lib/ap2_mandate_verifier"

raise "unexpected runtime" unless %w[3.4.12 4.0.9].include?(RUBY_VERSION) && JSON::VERSION == "2.19.9"

module DisclosureTest
  @cases = 0
  def self.assert(ok) = (raise "disclosure assertion failed" unless ok)
  def self.b64(s) = Base64.urlsafe_encode64(s, padding: false)
  def self.disclose(value, salt = "synthetic-salt") = b64(JSON.generate([salt, value]))
  def self.digest(s) = b64(Digest::SHA256.digest(s))
  def self.marker(s) = {"..." => digest(s)}
  def self.sign(key, payload)
    input = b64('{"alg":"ES256","typ":"example+sd-jwt"}') + "." + b64(JSON.generate(payload))
    integers = OpenSSL::ASN1.decode(key.sign("SHA256", input)).value
    input + "." + b64(integers.map { |n| n.value.to_s(2).rjust(32, "\x00") }.join)
  end
  def self.present(jws, disclosures) = ([jws] + disclosures + [""]).join("~")
  def self.expect(wire, pem, code, status = :rejected)
    result = AP2MandateVerifier.verify_root_disclosures(presentation: wire, trusted_issuer_public_key_pem: pem)
    raise "case #{@cases + 1}: expected #{status}/#{code}, got #{result.status}/#{result.code}" unless
      result.status == status && result.code == code
    assert(!result.success? && result.evidence.nil? && result.frozen?)
    @cases += 1
  end

  # Independent iterative original-wire oracle, not candidate walk/constants.
  # Native OpenSSL verifies every six-class signature before graph observation.
  # This shares Ruby/JSON/OpenSSL, and is NOT full independent O1–O5/SDK proof.
  def self.oracle(wire, pem)
    jws, *segments = wire.split("~")
    a, b, c = jws.split(".")
    signature = Base64.urlsafe_decode64(c)
    asn = OpenSSL::ASN1::Sequence.new([0, 32].map do |offset|
      OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(signature.byteslice(offset, 32), 2))
    end).to_der
    assert(OpenSSL::PKey.read(pem).verify("SHA256", asn, a + "." + b))
    pairs = segments.map { |s| [b64(Digest::SHA256.digest(s)), JSON.parse(Base64.urlsafe_decode64(s))[1]] }
    queue = [JSON.parse(Base64.urlsafe_decode64(b))]
    encountered = []
    missing = []
    until queue.empty?
      value = queue.shift
      if value.is_a?(Hash) && value.keys == ["..."]
        hash = value["..."]
        return :duplicate if encountered.include?(hash)
        encountered << hash
        match = pairs.find { |pair| pair[0] == hash }
        match ? queue << match[1] : missing << hash
      elsif value.is_a?(Hash)
        queue.concat(value.values)
      elsif value.is_a?(Array)
        queue.concat(value)
      end
    end
    return :missing unless missing.empty?
    return :extra if pairs.any? { |pair| !encountered.include?(pair[0]) }
    :complete
  end

  issuer = OpenSSL::PKey::EC.generate("prime256v1")
  pem = issuer.public_to_pem
  sku = disclose({"id" => "sku"})
  merchant = disclose({"id" => "merchant"})
  open_value = {"constraints" => [
    {"items" => [{"acceptable_items" => [marker(sku)]}]},
    {"allowed" => [marker(merchant)]}
  ]}
  opening = disclose(open_value)
  payload = {"delegate_payload" => [marker(opening)], "_sd_alg" => "sha-256"}
  jws = sign(issuer, payload)
  full = present(jws, [opening, sku, merchant])
  hidden = present(jws, [opening, sku])
  future = disclose({"future" => true})
  unknown_payload = payload.merge("future_authority" => [marker(future)])
  unknown = present(sign(issuer, unknown_payload), [opening, sku, merchant, future])
  repeated_open = Marshal.load(Marshal.dump(open_value))
  repeated_open["constraints"][1]["allowed"][0] = marker(sku)
  repeated = disclose(repeated_open)
  duplicate = present(sign(issuer, {"delegate_payload" => [marker(repeated)]}), [repeated, sku])
  extra = present(jws, [opening, sku, merchant, disclose({"extra" => true})])
  decoy_value = Marshal.load(Marshal.dump(open_value))
  decoy_value["constraints"][1]["allowed"][0] = marker("unpresented-decoy")
  decoy_open = disclose(decoy_value)
  decoy = present(sign(issuer, {"delegate_payload" => [marker(decoy_open)]}), [decoy_open, sku])

  six = {
    "FULL" => [full, :complete, :root_disclosures_verified_only, :unverified],
    "HIDDEN" => [hidden, :missing, :missing_disclosure, :rejected],
    "UNKNOWN" => [unknown, :complete, :unsupported_disclosure_profile, :rejected],
    "DUPLICATE" => [duplicate, :duplicate, :duplicate_commitment, :rejected],
    "EXTRA" => [extra, :extra, :extra_disclosure, :rejected],
    "DECOY" => [decoy, :missing, :missing_disclosure, :rejected]
  }
  six.each do |name, (wire, observation, code, status)|
    assert(oracle(wire, pem) == observation)
    expect(wire, pem, code, status)
    puts "#{name} original_wire_sha256=#{Digest::SHA256.hexdigest(wire)} oracle=#{observation} result=#{code}"
  end
  assert(hidden.split("~").first == jws && extra.split("~").first == jws)
  expect(present(jws, [merchant, opening, sku]), pem, :root_disclosures_verified_only, :unverified)
  expect(present(jws, [opening, merchant]), pem, :missing_disclosure)
  expect(present(jws, [opening, sku, merchant, sku]), pem, :duplicate_disclosure)
  expect(full, OpenSSL::PKey::EC.generate("prime256v1").public_to_pem, :invalid_root_signature)
  expect(full, nil, :issuer_key_unavailable, :unavailable)

  # Valid signature checked before parsing unsupported/invalid disclosures.
  damaged = jws.split(".")
  raw = Base64.urlsafe_decode64(damaged[2]); raw.setbyte(0, raw.getbyte(0) ^ 1)
  damaged[2] = b64(raw)
  expect(present(damaged.join("."), ["!invalid"]), pem, :invalid_root_signature)
  ["", jws, jws + "~", full + "~", full + "terminal", "~a~", "\xFF".b].each do |wire|
    expected = wire == "\xFF".b ? :invalid_encoding : :invalid_root_presentation
    expect(wire, pem, expected)
  end
  [nil, {}, Class.new(String).new(full)].each { |wire| expect(wire, pem, :invalid_input_type) }
  expect("x" * 131_073, pem, :input_too_large)
  expect(present(jws, ["a"] * 17), pem, :invalid_root_presentation)
  expect(present(jws, ["a" * 8193]), pem, :disclosure_limit_exceeded)
  ["!", opening + "=", "e31"].each { |s| expect(present(jws, [s]), pem, :invalid_disclosure) }
  ['["salt-salt",{"x":1,"x":2}]', '["salt-salt",{"x":1,"\\u0078":2}]'].each do |s|
    expect(present(jws, [b64(s)]), pem, :duplicate_key)
  end
  ["/*x*/[]", "\xEF\xBB\xBF[]".b, '["salt-salt",{"x":1e999}]'].each do |s|
    expect(present(jws, [b64(s)]), pem, :invalid_json)
  end
  expect(present(jws, [b64("\xFF".b)]), pem, :invalid_encoding)
  expect(present(jws, [b64("[" * 25 + "0" + "]" * 25)]), pem, :input_too_deep)
  [[], ["short", {}], ["salt-salt", []], ["salt-salt", "field", {}]].each do |s|
    expect(present(jws, [b64(JSON.generate(s))]), pem, :unsupported_disclosure_profile)
  end
  [{"delegate_payload" => [marker(opening)], "_sd_alg" => "sha-512"},
   payload.merge("_sd_alg" => nil),
   {"delegate_payload" => [marker(opening), marker(opening)]},
   {"delegate_payload" => []}, {"delegate_payload" => {}},
   payload.merge("_sd" => [])].each do |p|
    expect(present(sign(issuer, p), [opening, sku, merchant]), pem, :unsupported_disclosure_profile)
  end

  # Root-wide traversal catches unsupported markers even outside known claims.
  [{"_sd" => [digest(sku)]}, {"..." => digest(sku)},
   {"nested" => [{"..." => digest(sku)}]}, {"_sd_alg" => "sha-256"}].each do |extension|
    value = open_value.merge("future" => extension)
    segment = disclose(value)
    expect(present(sign(issuer, {"delegate_payload" => [marker(segment)]}), [segment, sku, merchant]),
      pem, :unsupported_disclosure_profile)
  end
  [nil, "a" * 43, "A" * 42 + "B"].each do |hash|
    expect(present(sign(issuer, {"delegate_payload" => [{"..." => hash}]}), [opening]), pem, :invalid_disclosure)
  end
  expect(present(sign(issuer, {"delegate_payload" => [{"..." => digest(opening), "extra" => 1}]}), [opening]),
    pem, :unsupported_disclosure_profile)
  visible = disclose({"constraints" => []})
  expect(present(sign(issuer, {"delegate_payload" => [marker(visible)]}), [visible]), pem, :unsupported_disclosure_profile)

  # Expanded-depth and container bounds apply after authenticating the Root.
  [{"padding" => [0] * 17}, (1..33).to_h { |i| ["k#{i}", 0] },
   {"padding" => 24.times.reduce(0) { |child, _| [child] }}].each do |extension|
    value = open_value.merge(extension)
    segment = disclose(value)
    expected = extension.key?("padding") && extension["padding"].is_a?(Array) && extension["padding"].size == 1 ?
      :input_too_deep : :disclosure_limit_exceeded
    expect(present(sign(issuer, {"delegate_payload" => [marker(segment)]}), [segment, sku, merchant]), pem, expected)
  end
  [21, 22].each do |levels|
    segment = disclose(open_value.merge("padding" => levels.times.reduce(0) { |child, _| [child] }))
    expect(present(sign(issuer, {"delegate_payload" => [marker(segment)]}), [segment, sku, merchant]), pem,
      levels == 21 ? :root_disclosures_verified_only : :disclosure_limit_exceeded,
      levels == 21 ? :unverified : :rejected)
  end
  [6, 8].each do |width|
    grid = Array.new(16) { Array.new(16) { Array.new(width, 0) } }
    segment = disclose(open_value.merge("padding" => grid))
    assert(segment.bytesize <= 8192)
    expect(present(sign(issuer, {"delegate_payload" => [marker(segment)]}), [segment, sku, merchant]), pem,
      width == 6 ? :root_disclosures_verified_only : :disclosure_limit_exceeded,
      width == 6 ? :unverified : :rejected)
  end
  padded = open_value.merge("padding" => "")
  padded["padding"] = "x" * (6144 - JSON.generate(["synthetic-salt", padded]).bytesize)
  segment = disclose(padded)
  assert(segment.bytesize == 8192)
  expect(present(sign(issuer, {"delegate_payload" => [marker(segment)]}), [segment, sku, merchant]),
    pem, :root_disclosures_verified_only, :unverified)
  callbacks = 0
  spoof = +"bad"
  spoof.define_singleton_method(:bytesize) { callbacks += 1; full.bytesize }
  spoof.define_singleton_method(:byteslice) { |*_args| callbacks += 1; full }
  expect(spoof, pem, :invalid_root_presentation)
  assert(callbacks.zero?)
  original = AP2MandateVerifier::RootDisclosures.singleton_class.instance_method(:check!)
  begin
    AP2MandateVerifier::RootDisclosures.define_singleton_method(:check!) { |*_args| raise "internal detail" }
    expect(full, pem, :root_disclosure_check_unavailable, :unavailable)
  ensure
    AP2MandateVerifier::RootDisclosures.singleton_class.define_method(:check!, original)
  end
  puts "PASS #{@cases} disclosure cases; six synthetic signed classes; no full AP2/O1-O5 claim"
end
