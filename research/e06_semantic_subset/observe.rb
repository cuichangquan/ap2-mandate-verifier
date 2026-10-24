# frozen_string_literal: true
# SOURCE_ONLY / NOT_RUN. Trusted observer, not a runtime attestation boundary.
gem "json", "= 2.19.9"
gem "jwt", "= 3.3.0"
gem "base64", "= 0.3.0"
gem "openssl", "= 4.0.2"
gem "digest", "= 3.2.1"
require "json"
require "jwt"
require "openssl"
require "base64"
require "digest"
ROOT = File.expand_path("../..", __dir__)
PINS = {
 "lib/ap2_mandate_verifier.rb" => "4824eeef1ce6c7833bcc24bc0bf9abc265df0b35ba135e54b4341b54c2f65ef2",
 "lib/ap2_mandate_verifier/host_binding.rb" => "917a4c139accd77d5bbe9125c64ea258349b6854ac04e0fefe33536b9b88ec0a",
 "lib/ap2_mandate_verifier/input_validator.rb" => "395f8e6f2012ab400d7b17f1fdcf4ee63a3c1c9622da4f2b32d35b522542bf00",
 "lib/ap2_mandate_verifier/purchase_binding.rb" => "6f2108ac3298e4558fc053139d045d399687ccc3bf39c01945ed52d529dc26df",
 "lib/ap2_mandate_verifier/research_result.rb" => "02159d2f451461ef818d7b6c9d55349cdfb6e23d9ced7d688730d22c8e96827d",
 "lib/ap2_mandate_verifier/result.rb" => "fade8a1e922f7b4cf2439c120580160f85e0f22f6cfac9ff1ab1364d7b34d310",
 "lib/ap2_mandate_verifier/root_disclosures.rb" => "55e97aa3b606eee64afbf929941fabb24286755297e1ed5bf48a5066e1352df6",
 "lib/ap2_mandate_verifier/root_signature.rb" => "d9b68d989700a0c103f80004e14fb2d3aa992f823434e07bf2971f63052519dd",
 "lib/ap2_mandate_verifier/scoped_constraints.rb" => "b2b5fa4cd1b4ce83cfc5ffc1be0a09ce57ad4a1b9be6778e581dd38f5ce5fd84",
 "lib/ap2_mandate_verifier/trust_context.rb" => "430eb9f9f3be4c0d7e799e95b68009c08582b6961aa954cc866ff012a3b2be36"
}.freeze

def need(ok, why)
  raise why unless ok
end

def captured(path, cap)
  before = File.lstat(path)
  need(before.file? && before.size.between?(1, cap), "source type/size")
  fields = ->(s) { [s.dev,s.ino,s.mode,s.nlink,s.uid,s.gid,s.size,s.mtime.to_r,s.ctime.to_r] }
  File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |f|
    opened = f.stat
    raw = f.read(cap + 1)
    need(raw.bytesize == opened.size && fields.call(before) == fields.call(opened) &&
      fields.call(opened) == fields.call(f.stat) && fields.call(f.stat) == fields.call(File.lstat(path)),
      "source changed")
    raw
  end
end

sources = PINS.to_h { |name, pin| [name, captured(File.join(ROOT, name), 65_536)] }
need(sources.transform_values { |bytes| Digest::SHA256.hexdigest(bytes) } == PINS, "source pin")
require_relative "../../lib/ap2_mandate_verifier"
need(RUBY_VERSION == "4.0.9" && RUBY_ENGINE == "ruby" && RUBY_PLATFORM.start_with?("arm64-darwin"),
  "Ruby identity")
versions = {"json"=>"2.19.9","jwt"=>"3.3.0","base64"=>"0.3.0","openssl"=>"4.0.2","digest"=>"3.2.1"}
need(versions.all? { |k,v| Gem.loaded_specs.fetch(k).version.to_s == v } &&
  OpenSSL::OPENSSL_LIBRARY_VERSION.start_with?("OpenSSL 3.5.9 "), "provider identity")
loaded = $LOADED_FEATURES.select { |f| f.include?("/ap2_mandate_verifier") && f.end_with?(".rb") }
need(loaded.size == 10 && loaded.all? { |f| File.realpath(f).start_with?(ROOT + "/lib/") }, "load paths")

raw = STDIN.read(262_145)
need(raw.bytesize <= 262_144, "request cap")
request = JSON.parse(raw, allow_duplicate_key: false, max_nesting: 24)
need(request.keys == ["args"] && request["args"].instance_of?(Hash), "request shape")
args = request["args"].transform_keys(&:to_sym)
need(args.keys.sort == %i[trust_json selection_json host_json root_presentation terminal_jws host_checkout_jws verified_at].sort,
  "public input shape")
events = []
record = ->(value) { need(events.size < 128, "event cap"); events << value }
wrap = lambda do |owner, name, kind|
  mod = Module.new do
    define_method(name) do |*positional, **keywords, &block|
      details = {"kind"=>kind}
      if kind == "signature"
        details["role"] = {"example+sd-jwt"=>"Issuer","kb+sd-jwt"=>"Agent","JWT"=>"Merchant"}.
          fetch(keywords.fetch(:expected_typ, "example+sd-jwt"))
        details["wire_sha256"] = Digest::SHA256.hexdigest(positional.fetch(0))
      end
      record.call(details.merge("state"=>"call"))
      begin
        value = super(*positional, **keywords, &block)
        record.call(details.merge("state"=>"return"))
        value
      rescue StandardError => error
        record.call(details.merge("state"=>"raise", "exception_class"=>error.class.name,
          "code"=>error.respond_to?(:code) ? error.code.to_s : "UNEXPECTED"))
        raise
      end
    end
  end
  owner.singleton_class.prepend(mod)
end
wrap.call(AP2MandateVerifier::RootSignature, :verified_payload!, "signature")
wrap.call(AP2MandateVerifier::RootDisclosures, :verified_root!, "graph")
wrap.call(AP2MandateVerifier::PurchaseBinding, :verified_details!, "binding")
wrap.call(AP2MandateVerifier::ScopedConstraints, :verified_constraints!, "constraints")
scoped_path = File.join(ROOT, "lib/ap2_mandate_verifier/scoped_constraints.rb")
lines = sources.fetch("lib/ap2_mandate_verifier/scoped_constraints.rb").lines
locations = lines.each_index.select do |i|
  lines[i].include?("raise Rejected, :unsupported_constraint unless constraints.instance_of?(Array)")
end
need(locations.size == 1, "content check location unproven")
first_line = locations.first + 1
trace = TracePoint.new(:line, :raise) do |event|
  next unless event.path == scoped_path
  if event.event == :line && event.method_id == :verified_constraints! && event.lineno == first_line
    record.call("kind"=>"content_first_check", "line"=>first_line)
  elsif event.event == :raise
    error = event.raised_exception
    record.call("kind"=>"content_raise", "method"=>event.method_id.to_s, "line"=>event.lineno,
      "code"=>error.respond_to?(:code) ? error.code.to_s : "UNEXPECTED")
  end
end
result = trace.enable { AP2MandateVerifier.verify_research(**args) }
trace.disable
puts JSON.generate(status: result.status, code: result.code, success: result.success?,
  evidence: result.evidence&.to_h, events: events, source_sha256: PINS,
  runtime: {ruby: RUBY_VERSION, platform: RUBY_PLATFORM, dependencies: versions,
    libcrypto: OpenSSL::OPENSSL_LIBRARY_VERSION},
  observation: "call/normal-return/raise; first content source line; not wrapper-entry PASS")

