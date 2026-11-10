# frozen_string_literal: true
require_relative "runtime_dependencies"
require "tmpdir"
require "open3"
require "rbconfig"
require "timeout"
require "fileutils"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__)) unless ENV["AP2_INSTALLED"] == "1"
require "ap2_mandate_verifier"
# In package testing, use the actual INSTALLED examples, not the checkout copy.
ROOT = ENV["AP2_EXAMPLES_ROOT"] || File.expand_path("../examples", __dir__)
require File.join(ROOT, "ruby_integration")
module RubyIntegrationTest
  M = AP2MandateVerifier
  A = M::PaymentAcceptance
  I = RubyIntegration::Inputs
  NOW = RubyIntegration::NOW
  @checks = 0
  @pids = []
  def self.check(value, label)
    @checks += 1
    raise "integration: #{label}" unless value
  end
  def self.command(*args, exit_code: 0)
    load_path = ENV["AP2_INSTALLED"] == "1" ? [] : ["-I", File.expand_path("../lib", __dir__)]
    output = error = status = nil
    Open3.popen3(RbConfig.ruby, *load_path, File.join(ROOT, "ruby_integration.rb"), *args) do |stdin, stdout, stderr, wait|
      stdin.close
      @pids << wait.pid
      begin
        Timeout.timeout(20) { output = stdout.read; error = stderr.read; status = wait.value }
      rescue Timeout::Error
        Process.kill("KILL", wait.pid); wait.value
        raise "subprocess timeout"
      end
    end
    check(status.exitstatus == exit_code, "child status #{args.first}")
    check(!output.include?("PRIVATE KEY") && !output.include?("synthetic-one-use-nonce") &&
      !output.match?(/eyJ[A-Za-z0-9_-]+\./), "safe output")
    if exit_code == 1
      check(error.start_with?("STOP:") && output.empty?, "redacted error")
      return
    end
    check(error.empty?, "quiet stderr")
    result = JSON.parse(output)
    unless exit_code == 75
      check(result.fetch("sdk_load") == (ENV["AP2_INSTALLED"] == "1" ? "installed_gem" : "repository_lib"), "actual load route")
      check(result.fetch("sdk_version") == "1.6.0", "actual version") if ENV["AP2_INSTALLED"] == "1"
    end
    result
  end
  def self.record(directory)
    store = A::SQLiteStore.new(path: File.join(directory, "acceptance.sqlite3"))
    data = JSON.parse(File.read(File.join(directory, "app.json")))
    result = A::Service.new(store: store).lookup(**data.fetch("scope").transform_keys(&:to_sym))
    [result.processor_key, result.closed_sd_jwt, result.reference, result.signed_wires]
  ensure
    store&.close
  end
  Dir.mktmpdir("ap2-integration-") do |root|
    scenarios = {"success" => ["receipt_success", 1], "error" => ["receipt_error", 1],
      "pause-before-start" => ["receipt_success", 1], "expired-before-start" => ["pending", 0],
      "crash-before-start" => ["pending", 0], "crash-after-start" => ["pending", 0],
      "crash-after-charge" => ["receipt_success", 1], "unknown" => ["unknown", 1], "delayed" => ["receipt_success", 1]}
    scenarios.each do |scenario, (expected, count)|
      dir = File.join(root, scenario)
      command("init", dir)
      before = File.binread(File.join(dir, "app.json"))
      run = command("run", dir, scenario, exit_code: scenario.start_with?("crash-") ? 75 : 0)
      check(run.fetch("mock_dispatches") == count, "durable run count")
      identity = record(dir)
      %w[retry recover].each do |action|
        result = command(action, dir)
        check(result.fetch("mock_dispatches") == count && result.fetch("ticket") == false, "no redispatch #{scenario}")
      end
      result = command("recover", dir)
      check(result.fetch("sdk_state") == expected, "recovery outcome #{scenario}")
      result = command("retry", dir, "resigned")
      check(result.fetch("mock_dispatches") == count && result.fetch("ticket") == false, "resign no dispatch")
      check(record(dir) == identity && File.binread(File.join(dir, "app.json")) == before, "first wires IDs and processor key unchanged")
      command("run", dir, "success")
      check(command("inspect", dir).fetch("mock_dispatches") == count, "repeat run no execution")
      processor = RubyIntegration::Processor.new(File.join(dir, "processor.sqlite3"))
      check(processor.count == count, "independent persistent mock record count")
      processor.close
    end
    check(@pids.uniq.length == @pids.length, "distinct Ruby OS processes")
    # Fresh verification must reject changed current authenticated Host data.
    %w[order trust expiry].each do |change|
      dir = File.join(root, "fresh-#{change}"); command("init", dir)
      data = JSON.parse(File.read(File.join(dir, "app.json")))
      store = A::SQLiteStore.new(path: File.join(dir, "acceptance.sqlite3")); service = A::Service.new(store: store)
      first = service.accept(**data.fetch("scope").transform_keys(&:to_sym), mode: :conditional, verification_inputs: I.verification(data, now: NOW))
      check(first.ticket, "first reservation")
      case change
      when "order" then data.fetch("order")["order_version"] = "2"
      when "trust" then data.fetch("trust_snapshot").fetch("records").last["active"] = false
      end
      begin
        inputs = I.verification(data, now: change == "expiry" ? NOW + 61 : NOW)
        check(service.start(ticket: first.ticket, verification_inputs: inputs).nil?, "fresh #{change} blocks")
      rescue M::InputBuilder::Invalid
        check(change == "trust", "invalid current trust blocks")
      end
      check(service.lookup(**data.fetch("scope").transform_keys(&:to_sym)).status == :pending, "no start rights issued")
      store.close
    end
    # Authentic but differently referenced Receipt cannot finalize original attempt.
    dir = File.join(root, "mismatch"); command("init", dir); command("run", dir, "unknown")
    data = JSON.parse(File.read(File.join(dir, "app.json")))
    store = A::SQLiteStore.new(path: File.join(dir, "acceptance.sqlite3")); service = A::Service.new(store: store)
    scope = data.fetch("scope").transform_keys(&:to_sym)
    original = service.lookup(**scope)
    other_wire = I.resign(data, now: NOW)
    bad = I.receipt(data, wire: other_wire, outcome: "Success", now: NOW + 120)
    check(M::PaymentReceipt.verify(jwt: bad, closed_sd_jwt: other_wire, verified_at: NOW + 120,
      **data.fetch("receipt_context").transform_keys(&:to_sym)).verified?, "wrong-reference Receipt genuinely signed")
    check(service.reconcile(**scope, receipt_jwt: bad, verified_at: NOW + 120).status == :rejected, "original reference mismatch rejected")
    check(service.lookup(**scope).status == :unknown, "mismatch preserves unknown")
    store.close
    db = SQLite3::Database.new(File.join(dir, "processor.sqlite3"))
    db.execute("UPDATE results SET receipt=?", [bad]); db.close
    command("recover", dir, exit_code: 1)
    check(command("inspect", dir).fetch("sdk_state") == "unknown", "CLI mismatched Receipt leaves unknown")
    check(record(dir).first == original.processor_key, "mismatch keeps processor key")
    corrupt = File.join(root, "corrupt-record"); command("init", corrupt); command("run", corrupt, "unknown")
    db = SQLite3::Database.new(File.join(corrupt, "acceptance.sqlite3"))
    db.execute("UPDATE ap2_attempts SET record='{}'"); db.close
    %w[recover inspect run].each { |action| command(action, corrupt, exit_code: 1) }
    processor = RubyIntegration::Processor.new(File.join(corrupt, "processor.sqlite3"))
    check(processor.count == 1, "corruption never dispatches again"); processor.close
    # Lost acceptance or processor DB is never recreated by normal commands/init.
    %w[acceptance.sqlite3 processor.sqlite3 app.json].each do |name|
      dir = File.join(root, "lost-#{name}"); command("init", dir)
      File.unlink(File.join(dir, name))
      command("recover", dir, exit_code: 1); command("init", dir, exit_code: 1)
      check(!File.exist?(File.join(dir, name)), "lost storage not recreated")
    end
  end
  puts JSON.generate(suite: "ruby_integration", checks: @checks, separate_ruby_processes: @pids.size,
    scenarios: 9, result: "PASS", sdk_load: ENV["AP2_INSTALLED"] == "1" ? "installed_gem" : "repository_lib")
end
