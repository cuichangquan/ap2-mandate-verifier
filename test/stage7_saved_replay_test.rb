# frozen_string_literal: true
# Replays retained public signed bytes. No signing, key generation or export.
require "json"
require "digest"
require "tmpdir"
require "fileutils"

module Stage7SavedReplayTest
  ROOT = File.expand_path("..", __dir__)
  FIXTURES = {
    "STAGE7_PUBLIC_CASES.json" => "ba8bfe3cea97b2230084a5ab5ef97d99701e3974160abbad06a346f8115c85b0",
    "O2O5_PUBLIC_CASES.json" => "be17fc33612ec561147100fbb901f5c2ef288d4535ed1aa69b56a61447fc8942"
  }.freeze
  TRUSTED_VERIFIER_COMMIT = "027ed4734af47c8289dbcb837373bb6086463ec4".freeze
  VERIFIER_PINS = {
    "lib/ap2_mandate_verifier.rb" => "ec0ba37c67c37662a26faff933f5689920463ececbec3853061f1a4dce05f0c4",
    "lib/ap2_mandate_verifier/input_validator.rb" => "299bc4a4f8eb353aa3e240a3b4cbd99aacd4eb3123b0b578c5f93f5599baf738",
    "lib/ap2_mandate_verifier/purchase_binding.rb" => "551aecadeac6a52d4c1f3d58d85a470114081f6146b017cd2318c9bd7dbdb60d",
    "lib/ap2_mandate_verifier/result.rb" => "bb377c7564bbda10f6a30bdd228f52c540a9da10875c56f97133178439585fda",
    "lib/ap2_mandate_verifier/root_disclosures.rb" => "55e97aa3b606eee64afbf929941fabb24286755297e1ed5bf48a5066e1352df6",
    "lib/ap2_mandate_verifier/root_signature.rb" => "d9b68d989700a0c103f80004e14fb2d3aa992f823434e07bf2971f63052519dd",
    "lib/ap2_mandate_verifier/scoped_constraints.rb" => "c94d317ffc264f016e5e9063413ff4162ed4e0245802e90a4efb6c6d0c4b4132"
  }.freeze
  SOURCE_LOADING = {"mode" => "PRIVATE_TEMP_TREE_STANDARD_REQUIRE",
    "trusted_verifier_commit" => TRUSTED_VERIFIER_COMMIT, "captured_file_count" => 7}.freeze
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
  def self.source_inventory(root)
    lib = File.join(root, "lib")
    raise "source directory type" unless File.lstat(lib).directory? && !File.symlink?(lib)
    entries = Dir.glob(File.join(lib, "**/*"), File::FNM_DOTMATCH).reject { |path| %w[. ..].include?(File.basename(path)) }
    files, dirs = [], []
    entries.each do |path|
      info = File.lstat(path)
      relative = path.delete_prefix(root + "/")
      raise "source link or type" if info.symlink? || !(info.file? || info.directory?)
      (info.file? ? files : dirs) << relative
    end
    raise "source directory set" unless dirs.sort == ["lib/ap2_mandate_verifier"]
    raise "source file set" unless files.sort == VERIFIER_PINS.keys.sort
    files.sort
  end
  def self.capture_sources(root = ROOT)
    root = File.expand_path(root)
    source_inventory(root)
    captured = VERIFIER_PINS.to_h do |relative, expected|
      bytes = bounded_regular(File.join(root, relative), 65_536)
      raise "source pin mismatch" unless Digest::SHA256.hexdigest(bytes) == expected
      [relative, bytes.freeze]
    end.freeze
    source_inventory(root)
    captured
  end
  def self.snapshot_hashes(tree)
    source_inventory(tree).to_h do |relative|
      [relative, Digest::SHA256.hexdigest(bounded_regular(File.join(tree, relative), 65_536))]
    end
  end
  def self.with_verifier_snapshot(captured)
    raise "verifier already loaded" if Object.const_defined?(:AP2MandateVerifier)
    raise "captured source set" unless captured.keys.sort == VERIFIER_PINS.keys.sort
    captured.each do |relative, bytes|
      raise "captured source mismatch" unless Digest::SHA256.hexdigest(bytes) == VERIFIER_PINS.fetch(relative)
    end
    Dir.mktmpdir("ap2-reviewed-verifier-") do |tree|
      tree = File.realpath(tree)
      captured.each do |relative, bytes|
        path = File.join(tree, relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) { |file| file.binmode; file.write(bytes) }
      end
      raise "snapshot source mismatch" unless snapshot_hashes(tree) == VERIFIER_PINS
      require File.join(tree, "lib/ap2_mandate_verifier")
      loaded = $LOADED_FEATURES.grep(/\A#{Regexp.escape(tree)}\//).sort
      raise "snapshot load set" unless loaded == VERIFIER_PINS.keys.map { |relative| File.join(tree, relative) }.sort
      raise "snapshot changed at load" unless snapshot_hashes(tree) == VERIFIER_PINS
      result = yield VERIFIER_PINS
      raise "snapshot changed during replay" unless snapshot_hashes(tree) == VERIFIER_PINS
      result
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
    captured = capture_sources
    report = with_verifier_snapshot(captured) do |before|
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
      {"scope" => "STAGE11_SAVED_WIRE_REPLAY_NOT_NEW_FIXTURES", "fixture_sha256" => expected_sha,
        "observer_sha256" => Digest::SHA256.hexdigest(bounded_regular(__FILE__, 65_536)),
        "verifier_source_sha256" => before, "source_loading" => SOURCE_LOADING, "case_count" => cases.size, "cases" => cases,
        "runtime" => {"ruby" => RUBY_VERSION, "json" => JSON::VERSION, "jwt" => Gem.loaded_specs.fetch("jwt").version.to_s},
        "success" => false, "evidence" => nil, "conclusion" => "HOLD"}
    end
    encoded = JSON.pretty_generate(report) + "\n"
    raise "report cap" unless encoded.bytesize < 65_536
    File.open(report_path, File::WRONLY|File::CREAT|File::EXCL, 0o600) { |file| file.write(encoded) }
    puts "PASS #{report.fetch("case_count")} retained-wire Gem replays; captured pinned sources via standard temporary-tree require; HOLD"
  end
end
