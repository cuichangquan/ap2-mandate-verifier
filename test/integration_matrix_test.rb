# frozen_string_literal: true
require "json"
require "base64"
require "openssl"
require "digest"
require_relative "../lib/ap2_mandate_verifier"

module IntegrationMatrixTest
  @cases = 0
  @public_cases = {}
  @observations = {}
  @issuer, @agent, @merchant, @other = Array.new(4) { OpenSSL::PKey::EC.generate("prime256v1") }
  def self.assert(ok) = (raise "integration assertion failed" unless ok)
  def self.copy(value) = Marshal.load(Marshal.dump(value))
  def self.b64(bytes) = Base64.urlsafe_encode64(bytes, padding: false)
  def self.hash(bytes) = b64(Digest::SHA256.digest(bytes))
  def self.jwk(key)
    point = key.public_key.to_octet_string(:uncompressed)
    {"kty" => "EC", "crv" => "P-256", "x" => b64(point.byteslice(1, 32)), "y" => b64(point.byteslice(33, 32))}
  end
  def self.sign(key, claims, typ)
    input = b64(JSON.generate("alg" => "ES256", "typ" => typ)) + "." + b64(JSON.generate(claims))
    values = OpenSSL::ASN1.decode(key.sign("SHA256", input)).value
    input + "." + b64(values.map { |n| n.value.to_s(2).rjust(32, "\x00") }.join)
  end
  def self.signature_oracle(wire, key)
    a, b, c = wire.split(".")
    raw = Base64.urlsafe_decode64(c)
    der = OpenSSL::ASN1::Sequence.new([0, 32].map do |i|
      OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(raw.byteslice(i, 32), 2))
    end).to_der
    OpenSSL::PKey.read(key.public_to_pem).verify("SHA256", der, a + "." + b)
  end
  def self.disclosure(value) = b64(JSON.generate(["integration-salt", value]))
  def self.marker(segment) = {"..." => hash(segment)}
  def self.totals(n) = [{"type" => "subtotal", "amount" => n}, {"type" => "total", "amount" => n}]
  def self.root_variant(kind)
    sku = disclosure({"id" => "sku", "title" => "item"})
    merchant = disclosure({"id" => "shop", "name" => "store"})
    open = {"vct" => "mandate.checkout.open.1", "iat" => 1_799_999_900, "exp" => 1_800_000_100,
      "cnf" => {"jwk" => jwk(@agent)}, "constraints" => [
        {"type" => "checkout.line_items", "items" => [{"id" => kind == :s01 ? 123 : "req", "quantity" => 2,
          "acceptable_items" => [marker(sku)]}]},
        {"type" => "checkout.allowed_merchants", "allowed" => [marker(merchant)]}]}
    extra = nil
    if kind == :unknown
      extra = disclosure({"future" => true})
      open["future_authority"] = [marker(extra)]
    elsif kind == :duplicate
      open["constraints"][1]["allowed"][0] = marker(sku)
    elsif kind == :decoy
      open["constraints"][1]["allowed"][0] = marker("deliberate-unresolved-decoy")
    end
    opening = disclosure(open)
    jws = sign(@issuer, {"delegate_payload" => [marker(opening)], "_sd_alg" => "sha-256"}, "example+sd-jwt")
    segments = [opening, sku, merchant]
    segments.pop if %i[hidden duplicate decoy].include?(kind)
    segments << extra if extra
    segments << disclosure({"unused" => true}) if kind == :extra
    [jws, segments]
  end
  def self.presentation(jws, segments) = ([jws] + segments + [""]).join("~")
  def self.checkout(quantity = 2)
    {"id" => "order", "merchant" => {"id" => "shop", "name" => "store"}, "status" => "ready_for_complete",
     "currency" => "USD", "links" => [], "totals" => totals(200), "line_items" => [
       {"id" => "line", "item" => {"id" => "sku", "title" => "item", "price" => 100},
        "quantity" => quantity, "totals" => totals(200)}]}
  end
  def self.inputs(root_wire, cart = checkout, agent: @agent, nonce: "n", sd_hash: hash(root_wire))
    checkout_wire = sign(@merchant, cart, "JWT")
    closed = {"vct" => "mandate.checkout.1", "iat" => 1_799_999_900, "exp" => 1_800_000_100,
      "checkout_jwt" => checkout_wire, "checkout_hash" => hash(checkout_wire)}
    terminal = sign(agent, {"iat" => 1_800_000_000, "aud" => "host", "nonce" => nonce,
      "sd_hash" => sd_hash, "delegate_payload" => [closed]}, "kb+sd-jwt")
    {root_presentation: root_wire, terminal_jws: terminal, host_checkout_jws: checkout_wire,
      trusted_issuer_public_key_pem: @issuer.public_to_pem, expected_agent_public_key_pem: @agent.public_to_pem,
      trusted_merchant_public_key_pem: @merchant.public_to_pem, expected_aud: "host", expected_nonce: "n",
      verified_at: 1_800_000_000, expected_checkout_id: "order", expected_merchant_id: "shop",
      expected_currency: "USD", expected_total_minor: 200}
  end

  # Observe real method entries in the same invocation; no stubbed verifier or
  # caller-supplied stage callbacks. Entries are reachability, not individual
  # PASS events. Result+causal controls establish the limited attribution.
  def self.observe(input)
    reached = []
    trace = TracePoint.new(:call) do |event|
      owner = event.defined_class
      name = event.method_id
      stage = if owner == AP2MandateVerifier::RootSignature.singleton_class && name == :verified_payload!
                {"example+sd-jwt" => :root_signature, "kb+sd-jwt" => :agent_signature, "JWT" => :merchant_signature}[event.binding.local_variable_get(:expected_typ)]
              elsif owner == AP2MandateVerifier::RootDisclosures.singleton_class && name == :walk!
                :root_graph
              elsif owner == AP2MandateVerifier::RootSignature.singleton_class && name == :public_jwk!
                :agent_key_confirmation
              elsif owner == AP2MandateVerifier::ScopedConstraints.singleton_class && name == :exact!
                :scoped_schema
              end
      reached << stage if stage && !reached.include?(stage)
    end
    result = trace.enable { AP2MandateVerifier.verify_scoped_constraints(**input) }
    [result, reached]
  ensure
    trace&.disable
  end
  def self.expect(name, input, code, expected_reached, status = :rejected, signatures: true)
    if signatures
      assert(signature_oracle(input[:root_presentation].split("~")[0], @issuer))
      assert(signature_oracle(input[:terminal_jws], @agent))
      assert(signature_oracle(input[:host_checkout_jws], @merchant))
    end
    result, reached = observe(input)
    raise "#{name}: expected #{status}/#{code}, got #{result.status}/#{result.code}" unless result.status == status && result.code == code
    raise "#{name}: incorrect reached stage order" unless reached == expected_reached
    assert(!result.success? && result.evidence.nil? && result.frozen?)
    @cases += 1
    @observations[name] = {"status" => result.status, "code" => result.code, "entered_stages" => reached,
      "root_sha256" => Digest::SHA256.hexdigest(input[:root_presentation]),
      "terminal_sha256" => Digest::SHA256.hexdigest(input[:terminal_jws]),
      "checkout_sha256" => Digest::SHA256.hexdigest(input[:host_checkout_jws])}
    puts "#{name} #{result.status}/#{result.code} reached=#{reached.join('>')}"
  end

  full_stages = %i[root_signature root_graph agent_key_confirmation agent_signature merchant_signature scoped_schema]
  closure_stages = %i[root_signature root_graph]
  normal_jws, normal_segments = root_variant(:full)
  normal_root = presentation(normal_jws, normal_segments)
  normal = inputs(normal_root)
  expect("NORMAL", normal, :scoped_constraints_verified_only, full_stages, :unverified)
  {"FULL" => [:full, :scoped_constraints_verified_only], "HIDDEN" => [:hidden, :missing_disclosure],
   "UNKNOWN" => [:unknown, :unsupported_disclosure_profile], "DUPLICATE" => [:duplicate, :duplicate_commitment],
   "EXTRA" => [:extra, :extra_disclosure], "DECOY" => [:decoy, :missing_disclosure]}.each do |name, (kind, code)|
    jws, segments = kind == :full ? [normal_jws, normal_segments] : root_variant(kind)
    # HIDDEN/EXTRA reuse exactly the FULL signed JWS; only presentation differs.
    jws = normal_jws if %i[hidden extra].include?(kind)
    input = inputs(presentation(jws, segments))
    expect(name, input, code, kind == :full ? full_stages : closure_stages, kind == :full ? :unverified : :rejected)
    @public_cases[name] = input
  end
  assert(@public_cases["HIDDEN"][:root_presentation].split("~")[0] == normal_jws)
  assert(@public_cases["EXTRA"][:root_presentation].split("~")[0] == normal_jws)
  reordered = presentation(normal_jws, normal_segments.reverse)
  expect("REORDER_REBOUND", inputs(reordered), :scoped_constraints_verified_only, full_stages, :unverified)
  expect("REORDER_OLD_TERMINAL", normal.merge(root_presentation: reordered), :root_binding_mismatch,
    %i[root_signature root_graph agent_key_confirmation agent_signature])
  s01_jws, s01_segments = root_variant(:s01)
  s01_root = presentation(s01_jws, s01_segments)
  expect("S01", inputs(s01_root), :invalid_scoped_schema, full_stages)
  expect("BAD_AGENT_BEFORE_S01", inputs(s01_root, agent: @other), :invalid_root_signature,
    %i[root_signature root_graph agent_key_confirmation agent_signature], signatures: false)
  bad_merchant = inputs(normal_root, checkout(0)).merge(trusted_merchant_public_key_pem: @other.public_to_pem)
  expect("BAD_MERCHANT_BEFORE_SCHEMA", bad_merchant, :invalid_root_signature,
    %i[root_signature root_graph agent_key_confirmation agent_signature merchant_signature])
  expect("NONCE_BEFORE_MERCHANT", bad_merchant.merge(expected_nonce: "other"), :nonce_mismatch,
    %i[root_signature root_graph agent_key_confirmation agent_signature])
  expect("HIDDEN_BEFORE_AMOUNT", @public_cases["HIDDEN"].merge(expected_total_minor: 201), :missing_disclosure, closure_stages)
  bad_root = copy(@public_cases["HIDDEN"])
  a, b, c = bad_root[:root_presentation].split("~")[0].split(".")
  signature = Base64.urlsafe_decode64(c); signature.setbyte(0, signature.getbyte(0) ^ 1)
  bad_root[:root_presentation] = presentation(a + "." + b + "." + b64(signature), normal_segments[0, 2])
  expect("BAD_ROOT_BEFORE_DISCLOSURE", bad_root, :invalid_root_signature, [:root_signature], signatures: false)
  expect("AMOUNT_AFTER_ALL_CRYPTO", normal.merge(expected_total_minor: 201), :amount_mismatch, full_stages)

  if ENV["AP2_STAGE7_EXPORT"] == "1"
    exported = {"scope" => "LOCAL_SYNTHETIC_ONLY_NOT_INDEPENDENT_ORACLE_OR_EVIDENCE", "main" => "027ed4734af47c8289dbcb837373bb6086463ec4",
      "ap2_commit" => "b4587ac1d055888a73b4b21750973cffba961793", "observations" => @observations,
      "public_keys" => {"issuer" => jwk(@issuer), "agent" => jwk(@agent), "merchant" => jwk(@merchant)},
      "gem_inputs" => @public_cases,
      "oracle_fixture" => {"ap2_commit" => "b4587ac1d055888a73b4b21750973cffba961793",
        "cases" => @public_cases.to_h { |name, input| [name, {"root" => input[:root_presentation], "terminal" => input[:terminal_jws]}] }}}
    bytes = JSON.pretty_generate(exported) + "\n"
    assert(bytes.bytesize < 1_048_576 && !bytes.include?("PRIVATE KEY"))
    File.open(File.expand_path("../research/stage11/inputs/STAGE7_PUBLIC_CASES.json", __dir__), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(bytes) }
  end
  puts "PASS #{@cases} same-candidate integration cases; entered stages only; no full AP2/independent Oracle PASS"
end
