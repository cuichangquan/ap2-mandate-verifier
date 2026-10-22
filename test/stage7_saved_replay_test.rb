# frozen_string_literal: true
# Replays retained public signed bytes. No signing, key generation or export.
require "json"
require "digest"
require_relative "../lib/ap2_mandate_verifier"

module Stage7SavedReplayTest
  ROOT = File.expand_path("..", __dir__)
  FIXTURES = {
    "STAGE7_PUBLIC_CASES.json" => "ba8bfe3cea97b2230084a5ab5ef97d99701e3974160abbad06a346f8115c85b0",
    "O2O5_PUBLIC_CASES.json" => "be17fc33612ec561147100fbb901f5c2ef288d4535ed1aa69b56a61447fc8942"
  }.freeze
  def self.same_stat?(a, b)
    a.file? && b.file? && %i[dev ino mode nlink uid gid size mtime ctime].all? { |key| a.public_send(key) == b.public_send(key) }
  end
  def self.bounded_regular(path, cap)
    before = File.lstat(path)
    raise "fixture type/size" unless before.file? && before.size.positive? && before.size <= cap
    File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
      file.binmode
      opened = file.stat
      raise "fixture changed at open" unless same_stat?(before, opened)
      raw = file.read(cap + 1)
      after = file.stat
      raise "fixture changed during read" unless raw && raw.bytesize == opened.size &&
        same_stat?(opened, after) && same_stat?(after, File.lstat(path))
      raw
    end
  end
  def self.source_hashes
    Dir[File.join(ROOT, "lib/**/*.rb")].sort.to_h do |path|
      [path.delete_prefix(ROOT + "/"), Digest::SHA256.hexdigest(bounded_regular(path, 65_536))]
    end
  end
  def self.observe(input)
    entries = []
    trace = TracePoint.new(:call) do |event|
      owner, method = event.defined_class, event.method_id
      stage = if owner == AP2MandateVerifier::RootSignature.singleton_class && method == :verified_payload!
                {"example+sd-jwt" => "root_signature", "kb+sd-jwt" => "agent_signature", "JWT" => "merchant_signature"}[event.binding.local_variable_get(:expected_typ)]
              elsif owner == AP2MandateVerifier::RootDisclosures.singleton_class && method == :walk!
                "root_graph"
              elsif owner == AP2MandateVerifier::RootSignature.singleton_class && method == :public_jwk!
                "agent_key_confirmation"
              elsif owner == AP2MandateVerifier::ScopedConstraints.singleton_class && method == :exact!
                "scoped_schema"
              end
      entries << stage if stage && !entries.include?(stage)
    end
    result = trace.enable { AP2MandateVerifier.verify_scoped_constraints(**input.transform_keys(&:to_sym)) }
    raise "non-success boundary changed" unless !result.success? && result.evidence.nil? && result.frozen?
    {"status" => result.status.to_s, "code" => result.code.to_s,
     "entries" => entries, "success" => result.success?, "evidence" => result.evidence,
     "root_sha256" => Digest::SHA256.hexdigest(input.fetch("root_presentation")),
     "terminal_sha256" => Digest::SHA256.hexdigest(input.fetch("terminal_jws")),
     "checkout_sha256" => Digest::SHA256.hexdigest(input.fetch("host_checkout_jws"))}
  ensure
    trace&.disable
  end

  if $PROGRAM_NAME == __FILE__
    fixture_path, report_path = ARGV
    raise "fixture and NEW report paths required" unless fixture_path && report_path && ARGV.size == 2
    expected_sha = FIXTURES.fetch(File.basename(fixture_path))
    raw = bounded_regular(fixture_path, 1_048_576)
    raise "original fixture changed" unless Digest::SHA256.hexdigest(raw) == expected_sha
    fixture = JSON.parse(raw)
    inputs = fixture.fetch("cases", fixture["gem_inputs"])
    historical = fixture.fetch("gem_observations", fixture["observations"])
    before = source_hashes
    cases = inputs.to_h do |name, input|
      measured = observe(input)
      expected = historical.fetch(name)
      entries = expected.fetch("entries", expected["entered_stages"])
      raise "#{name}: result/order mismatch" unless measured["status"] == expected.fetch("status") &&
        measured["code"] == expected.fetch("code") && measured["entries"] == entries
      %w[root_sha256 terminal_sha256 checkout_sha256].each do |key|
        raise "#{name}: original wire hash mismatch" unless measured[key] == expected.fetch(key)
      end
      [name, measured]
    end
    raise "source changed during replay" unless before == source_hashes
    report = {"scope" => "STAGE11_SAVED_WIRE_REPLAY_NOT_NEW_FIXTURES", "fixture_sha256" => expected_sha,
      "observer_sha256" => Digest::SHA256.hexdigest(bounded_regular(__FILE__, 65_536)),
      "verifier_source_sha256" => before, "case_count" => cases.size, "cases" => cases,
      "runtime" => {"ruby" => RUBY_VERSION, "json" => JSON::VERSION, "jwt" => Gem.loaded_specs.fetch("jwt").version.to_s},
      "success" => false, "evidence" => nil, "conclusion" => "HOLD"}
    encoded = JSON.pretty_generate(report) + "\n"
    raise "report cap" unless encoded.bytesize < 65_536
    File.open(report_path, File::WRONLY|File::CREAT|File::EXCL, 0o600) { |file| file.write(encoded) }
    puts "PASS #{cases.size} retained-wire Gem replays; no fixture generation; HOLD"
  end
end
