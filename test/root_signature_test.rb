# frozen_string_literal: true

require "json"
require "base64"
require "openssl"
require "jwt"
require_relative "../lib/ap2_mandate_verifier"

raise "unexpected runtime" unless RUBY_VERSION == "4.0.9" &&
  JSON::VERSION == "2.19.9" && Gem.loaded_specs.fetch("jwt").version.to_s == "3.3.0"

# Keys exist only in this process. No private-key files, output or fixtures.
module RootSignatureTest
  @cases = 0
  def self.assert(ok, message = "root signature assertion failed")
    raise message unless ok
  end
  def self.b64(bytes) = Base64.urlsafe_encode64(bytes, padding: false)

  # Independent original-wire construction: no JWT.encode or candidate helper.
  def self.sign(key, header = '{"alg":"ES256","typ":"example+sd-jwt"}', payload = '{"delegate_payload":[]}')
    input = b64(header) + "." + b64(payload)
    der = key.sign("SHA256", input)
    raw = OpenSSL::ASN1.decode(der).value.map { |n| n.value.to_s(2).rjust(32, "\x00") }.join
    input + "." + b64(raw)
  end

  # Separate OpenSSL verification call is the signature oracle, not JWT.decode.
  # It shares the native provider; cryptographic implementation diversity is
  # not claimed. No stage-4 disclosure or real-Issuer assertion is made.
  def self.oracle(wire, pem)
    a, b, c = wire.split(".")
    raw = Base64.urlsafe_decode64(c)
    der = OpenSSL::ASN1::Sequence.new([
      OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(raw.byteslice(0, 32), 2)),
      OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(raw.byteslice(32, 32), 2))
    ]).to_der
    OpenSSL::PKey.read(pem).verify("SHA256", der, a + "." + b)
  end

  def self.expect(wire, pem, status, code)
    result = AP2MandateVerifier.verify_root_signature(root_jws: wire,
      trusted_issuer_public_key_pem: pem)
    assert(result.status == status && result.code == code,
      "case #{@cases + 1}: expected #{status}/#{code}, got #{result.status}/#{result.code}")
    assert(!result.success? && result.evidence.nil? && result.frozen?)
    assert(result.rejected? == (status == :rejected))
    assert(result.unavailable? == (status == :unavailable))
    assert(result.unverified? == (status == :unverified))
    @cases += 1
  end

  issuer = OpenSSL::PKey::EC.generate("prime256v1")
  other = OpenSSL::PKey::EC.generate("prime256v1")
  public_pem = issuer.public_to_pem
  other_pem = other.public_to_pem
  normal = sign(issuer)
  assert(oracle(normal, public_pem))
  assert(!oracle(normal, other_pem))
  expect(normal, public_pem, :unverified, :root_signature_verified_only)
  expect(normal, other_pem, :rejected, :invalid_root_signature)

  a, b, c = normal.split(".")
  changed = a + "." + b64('{"delegate_payload":["changed"]}') + "." + c
  assert(!oracle(changed, public_pem))
  expect(changed, public_pem, :rejected, :invalid_root_signature)
  sig = Base64.urlsafe_decode64(c)
  sig.setbyte(0, sig.getbyte(0) ^ 1)
  changed_signature = a + "." + b + "." + b64(sig)
  assert(!oracle(changed_signature, public_pem))
  expect(changed_signature, public_pem, :rejected, :invalid_root_signature)

  %w[none HS256 RS256 ES384 ES256K].each do |alg|
    wire = sign(issuer, JSON.generate("alg" => alg, "typ" => "example+sd-jwt"))
    assert(oracle(wire, public_pem)) # causal policy rejection, not bad EC signature
    expect(wire, public_pem, :rejected, :unsupported_root_algorithm)
  end
  %w[JWT kb+sd-jwt unknown].each do |typ|
    expect(sign(issuer, JSON.generate("alg" => "ES256", "typ" => typ)), public_pem,
      :rejected, :unsupported_root_type)
  end

  point = other.public_key.to_octet_string(:uncompressed)
  jwk = {"kty" => "EC", "crv" => "P-256", "x" => b64(point.byteslice(1, 32)), "y" => b64(point.byteslice(33, 32))}
  {"jwk" => jwk, "jku" => "https://example.invalid/jwks", "x5u" => "https://example.invalid/cert",
   "x5c" => [], "crit" => [], "b64" => false}.each do |name, value|
    wire = sign(issuer, JSON.generate("alg" => "ES256", "typ" => "example+sd-jwt", name => value))
    assert(oracle(wire, public_pem))
    expect(wire, public_pem, :rejected, :unsupported_root_header)
  end
  kid = '{"alg":"ES256","typ":"example+sd-jwt","kid":"claimed-issuer"}'
  expect(sign(issuer, kid), public_pem, :unverified, :root_signature_verified_only)
  expect(sign(other, kid), public_pem, :rejected, :invalid_root_signature)
  expect(sign(other, '{"alg":"ES256","typ":"example+sd-jwt"}', JSON.generate("jwk" => jwk)),
    public_pem, :rejected, :invalid_root_signature)
  [nil, 1, "", "k" * 129].each do |value|
    expect(sign(issuer, JSON.generate("alg" => "ES256", "typ" => "example+sd-jwt", "kid" => value)),
      public_pem, :rejected, :unsupported_root_header)
  end

  ['{"alg":"ES256","alg":"ES256","typ":"example+sd-jwt"}',
   '{"alg":"ES256","\\u0061lg":"ES256","typ":"example+sd-jwt"}'].each do |header|
    expect(sign(issuer, header), public_pem, :rejected, :duplicate_key)
  end
  ['{"x":1,"x":2}', '{"nested":{"a":1,"\\u0061":2}}'].each do |payload|
    expect(sign(issuer, '{"alg":"ES256","typ":"example+sd-jwt"}', payload), public_pem, :rejected, :duplicate_key)
  end
  ["/*comment*/{}", "\xEF\xBB\xBF{}".b, '{"x":1e999}'].each do |payload|
    expect(sign(issuer, '{"alg":"ES256","typ":"example+sd-jwt"}', payload), public_pem, :rejected, :invalid_json)
  end
  expect(sign(issuer, '{"alg":"ES256","typ":"example+sd-jwt"}', "\xFF".b), public_pem, :rejected, :invalid_encoding)
  %w[null [] true 0].each do |payload|
    expect(sign(issuer, '{"alg":"ES256","typ":"example+sd-jwt"}', payload), public_pem, :rejected, :invalid_root_payload)
  end
  [nil, 1, {}, Class.new(String).new(normal)].each do |wire|
    expect(wire, public_pem, :rejected, :invalid_input_type)
  end
  ["", "a.b", normal + ".x", normal + "~", a + "=." + b + "." + c,
   a + "." + b + ".", a + "." + b + ".AA", "+." + b + "." + c,
   a + ".e31." + c].each do |wire|
    expect(wire, public_pem, :rejected, :invalid_root_jws)
  end
  expect("x" * 32_769, public_pem, :rejected, :input_too_large)
  # Independently construct an exactly32768-byte, correctly signed wire.
  boundary = nil
  4.times do |spaces|
    header = " " * spaces + '{"alg":"ES256","typ":"example+sd-jwt"}'
    encoded_room = 32_768 - b64(header).bytesize - 2 - 86
    payload_bytes = encoded_room * 3 / 4
    payload = JSON.generate("padding" => "x" * (payload_bytes - 14))
    next unless b64(payload).bytesize == encoded_room
    boundary = sign(issuer, header, payload)
    break
  end
  assert(boundary && boundary.bytesize == 32_768)
  assert(oracle(boundary, public_pem))
  expect(boundary, public_pem, :unverified, :root_signature_verified_only)
  expect(boundary + "x", public_pem, :rejected, :input_too_large)
  expect("\xFF".b, public_pem, :rejected, :invalid_encoding)
  expect(sign(issuer, '{"alg":"ES256","typ":"example+sd-jwt"}', '{"x":' * 25 + "0" + "}" * 25),
    public_pem, :rejected, :input_too_deep)
  expect(sign(issuer, '{"alg":"ES256","typ":"example+sd-jwt"}', '{"x":' * 24 + "0" + "}" * 24),
    public_pem, :unverified, :root_signature_verified_only)
  expect(sign(issuer, JSON.generate("alg" => "ES256", "typ" => "example+sd-jwt", "pad" => "x" * 2100)),
    public_pem, :rejected, :invalid_root_jws)

  [nil, {}, "x" * 1025].each { |pem| expect(normal, pem, :unavailable, :issuer_key_unavailable) }
  [issuer.private_to_pem, "https://example.invalid/key", "-----BEGIN PUBLIC KEY-----\ninvalid\n",
   public_pem + "trailing", other.public_to_pem.sub("PUBLIC", "PRIVATE"),
   OpenSSL::PKey::EC.generate("secp384r1").public_to_pem].each do |pem|
    expect(normal, pem, :unavailable, :issuer_key_unsupported)
  end

  callbacks = 0
  spoof = +"bad"
  spoof.define_singleton_method(:bytesize) { callbacks += 1; normal.bytesize }
  spoof.define_singleton_method(:byteslice) { |*_args| callbacks += 1; normal }
  expect(spoof, public_pem, :rejected, :invalid_root_jws)
  key_copy = +public_pem
  key_copy.define_singleton_method(:bytesize) { callbacks += 1; other_pem.bytesize }
  key_copy.define_singleton_method(:byteslice) { |*_args| callbacks += 1; other_pem }
  expect(normal, key_copy, :unverified, :root_signature_verified_only)
  assert(callbacks.zero?)
  assert(!key_copy.frozen?)

  # A missing/wrong backend and unexpected provider failures are unavailable.
  singleton = AP2MandateVerifier::RootSignature.singleton_class
  original = singleton.instance_method(:dependencies!)
  begin
    singleton.define_method(:dependencies!) { raise AP2MandateVerifier::RootSignature::Unavailable, :signature_dependency_unavailable }
    expect(normal, public_pem, :unavailable, :signature_dependency_unavailable)
  ensure
    singleton.define_method(:dependencies!, original)
    singleton.send(:private, :dependencies!)
  end
  original_decode = JWT.method(:decode)
  begin
    JWT.define_singleton_method(:decode) { |*_args| [{"changed" => true}, {}] }
    expect(normal, public_pem, :unavailable, :root_signature_check_unavailable)
  ensure
    JWT.define_singleton_method(:decode, original_decode)
  end
  begin
    JWT.define_singleton_method(:decode) { |*_args| raise "private provider diagnostic" }
    expect(normal, public_pem, :unavailable, :root_signature_check_unavailable)
  ensure
    JWT.define_singleton_method(:decode, original_decode)
  end

  configuration = JWT.configuration.decode
  original_required = configuration.required_claims
  original_verify_sub = configuration.verify_sub
  begin
    configuration.required_claims = ["exp"]
    configuration.verify_sub = true
    expect(normal, public_pem, :unverified, :root_signature_verified_only)
  ensure
    configuration.required_claims = original_required
    configuration.verify_sub = original_verify_sub
  end

  expect(sign(issuer, "[]"), public_pem, :rejected, :unsupported_root_header)

  # Expiry/authority/disclosure are deliberately NOT certified by signature.
  expect(sign(issuer, '{"alg":"ES256","typ":"example+sd-jwt"}', '{"exp":1,"delegate_payload":[]}'),
    public_pem, :unverified, :root_signature_verified_only)
  puts "PASS #{@cases} root-signature cases; Ruby #{RUBY_VERSION}; JWT #{JWT::VERSION::STRING}; JSON #{JSON::VERSION}"
end
