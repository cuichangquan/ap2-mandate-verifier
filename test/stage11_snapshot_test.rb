# frozen_string_literal: true
require "tmpdir"
require "fileutils"
require_relative "stage7_saved_replay_test"
module Stage11SnapshotTest
  def self.reject
    yield
    raise "invalid source accepted"
  rescue RuntimeError => error
    raise if error.message == "invalid source accepted"
  end
  def self.run
    count = 0
    harness = Stage7SavedReplayTest
    Dir.mktmpdir("stage11-checkout-copy-") do |copy|
      FileUtils.cp_r(File.join(harness::ROOT, "lib"), copy)
      captured = harness.capture_sources(copy)
      raise unless captured.size == 7 && captured.all? { |path, bytes| Digest::SHA256.hexdigest(bytes) == harness::VERIFIER_PINS.fetch(path) }
      count += 1
      target = File.join(copy, "lib/ap2_mandate_verifier.rb")
      original = File.binread(target)
      File.binwrite(target, "raise 'wrong source must never run'\n")
      reject { harness.capture_sources(copy) }; count += 1
      File.binwrite(target, original)
      File.unlink(target)
      reject { harness.capture_sources(copy) }; count += 1
      File.binwrite(target, original)
      ["lib/extra.rb", "lib/extra.txt"].each do |relative|
        extra = File.join(copy, relative); File.binwrite(extra, "extra")
        reject { harness.capture_sources(copy) }; count += 1
        File.unlink(extra)
      end
      extra_dir = File.join(copy, "lib/extra"); Dir.mkdir(extra_dir)
      reject { harness.capture_sources(copy) }; count += 1
      Dir.rmdir(extra_dir)
      File.unlink(target); File.symlink(File.join(harness::ROOT, "lib/ap2_mandate_verifier.rb"), target)
      reject { harness.capture_sources(copy) }; count += 1
      File.unlink(target); File.binwrite(target, original)
      lib = File.join(copy, "lib"); moved = File.join(copy, "original-lib")
      File.rename(lib, moved); File.symlink(moved, lib)
      reject { harness.capture_sources(copy) }; count += 1
      File.unlink(lib); File.rename(moved, lib)
      missing = captured.dup; missing.delete(missing.keys.first)
      reject { harness.with_verifier_snapshot(missing) { raise "must not load" } }; count += 1
      extra = captured.merge("lib/extra.rb" => "extra")
      reject { harness.with_verifier_snapshot(extra) { raise "must not load" } }; count += 1
      changed = captured.merge(captured.keys.first => "raise 'wrong captured bytes'\n")
      reject { harness.with_verifier_snapshot(changed) { raise "must not load" } }; count += 1
      # Mutate the source checkout copy after capture. Loading must never reread it.
      FileUtils.rm_rf(lib)
      Dir.mkdir(lib); File.binwrite(File.join(lib, "ap2_mandate_verifier.rb"), "raise 'checkout reread'\n")
      paths = []
      returned = harness.with_verifier_snapshot(captured) do |pins|
        raise unless pins == harness::VERIFIER_PINS
        paths = $LOADED_FEATURES.select { |path| path.include?("/ap2-reviewed-verifier-") }
        raise unless paths.size == 7 && paths.none? { |path| path.start_with?(copy + "/") }
        result = AP2MandateVerifier.verify(presentation_json: "{}")
        raise unless result.status == :unverified && !result.success? && result.evidence.nil?
        :captured_sources_used
      end
      raise unless returned == :captured_sources_used; count += 1
      raise unless paths.none? { |path| File.exist?(path) }; count += 1
      reject { harness.with_verifier_snapshot(captured) { raise "already loaded must reject" } }; count += 1
    end
    puts "PASS #{count} captured-source snapshot controls; original checkout untouched; standard Gem require only"
  end
end
Stage11SnapshotTest.run if $PROGRAM_NAME == __FILE__
