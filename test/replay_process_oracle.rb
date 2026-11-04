# frozen_string_literal: true
# Independent process and external-effect oracle. No real processor is called.
require_relative "runtime_dependencies"
require "json"
require "tmpdir"
require "timeout"
require "rbconfig"
require "stringio"
if ENV["AP2_INSTALLED"] == "1"
  version = ENV.fetch("AP2_GEM_VERSION")
  gem "ap2_mandate_verifier", "= #{version}"
  require "ap2_mandate_verifier"
  root = File.realpath(Gem.loaded_specs.fetch("ap2_mandate_verifier").full_gem_path + "/lib")
  source = File.realpath(File.join(__dir__, "../lib"))
  features = $LOADED_FEATURES.select { |f| f.match?(%r{/ap2_mandate_verifier(?:/|\.rb\z)}) }
  raise "source overlay" unless root != source && !features.empty? && features.all? { |f| File.realpath(f).start_with?(root + "/") }
else
  $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
  require "ap2_mandate_verifier"
end
require "ap2_mandate_verifier/payment_acceptance"
require "ap2_mandate_verifier/payment_acceptance/sqlite_store"
M = AP2MandateVerifier
A = M::PaymentAcceptance
NOW = 1_800_000_000

def symbol_keys(value) = value.to_h { |key, item| [key.to_sym, item] }
def load_public(path)
  value = JSON.parse(File.read(path))
  value["ids"] = symbol_keys(value.fetch("ids"))
  value["verification"] = symbol_keys(value.fetch("verification"))
  value["verification"][:checkout_mode] = value["verification"].fetch(:checkout_mode).to_sym
  value["verification"][:checkout_inputs] = symbol_keys(value["verification"].fetch(:checkout_inputs))
  value
end

def checkpoint(name, requested)
  return unless requested == name
  puts JSON.generate(checkpoint: name)
  STDOUT.flush
  STDIN.read # Parent SIGKILLs this worker; this is not a simulated exception.
end

if ARGV.first == "worker"
  STDOUT.sync = true
  data = load_public(ARGV.fetch(1))
  directory, gate, stage = ARGV.values_at(2, 3, 4)
  service = A::Service.new(store: A::SQLiteStore.new(path: File.join(directory, "ledger.sqlite3")))
  puts JSON.generate(ready: true)
  STDIN.gets # All independent processes reach this barrier before release.
  checkpoint("before_accept", stage)
  result = service.accept(**data.fetch("ids"), mode: :direct, verification_inputs: data.fetch("verification"))
  ticket = result.ticket
  checkpoint("after_reserve", stage)
  execution = ticket && service.start(ticket: ticket, verification_inputs: data.fetch("verification"))
  checkpoint("after_start", stage)
  if execution
    # The external mock owns this durable counter. SDK verification counters and
    # SQLite claim return values cannot manufacture this observation.
    File.open(File.join(directory, "external-effects.jsonl"), File::WRONLY | File::CREAT | File::APPEND, 0o600) do |file|
      file.flock(File::LOCK_EX)
      file.puts(JSON.generate(processor_key: execution.processor_key, reference: execution.reference,
        wire_sha256: Digest::SHA256.hexdigest(execution.closed_sd_jwt)))
      file.flush
      file.fsync
    end
  end
  checkpoint("after_effect", stage)
  service.unknown(ticket: ticket) if stage == "mark_unknown" && execution
  current = service.lookup(**data.fetch("ids"))
  puts JSON.generate(status: current.status, acceptance_status: result.status, acquired: !ticket.nil?, dispatched: !execution.nil?,
    retained_wire_sha256: current.closed_sd_jwt && Digest::SHA256.hexdigest(current.closed_sd_jwt),
    retained_receipt_sha256: current.receipt_jwt && Digest::SHA256.hexdigest(current.receipt_jwt))
  exit 0
end

require_relative "../examples/conditional_checkout"
module ReplayProcessOracle
  @checks = 0
  @cases = []
  @live_workers = []
  def self.assert(value, description)
    @checks += 1
    raise "replay process oracle: #{description}" unless value
  end
  def self.sign(key) = M::CheckoutJWT.es256_signer(private_key: key)
  def self.fixture(context, checkout: nil, merchant: nil)
    provider, _, original_merchant = context.fetch(:keys)
    merchant ||= original_merchant
    checkout ||= context.fetch(:closed).checkout_jwt
    details = M::Payment.details(checkout_jwt: checkout, trusted_merchant_public_key_pem: merchant.public_to_pem,
      expected_merchant_id: "shop", payment_instrument: {"id" => "synthetic-card", "type" => "card"})
    buyer = M::Buyer.issue_closed(checkout_jwt: checkout, approved_checkout_jwt: checkout,
      trusted_merchant_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop", issued_at: NOW,
      expires_at: NOW+60, signer: sign(provider), public_key_pem: provider.public_to_pem)
    payment = M::Payment.issue_direct(payment: details, approved_payment: details, issued_at: NOW,
      expires_at: NOW+60, signer: sign(provider), public_key_pem: provider.public_to_pem)
    verification = {closed_sd_jwt: payment.closed_sd_jwt, checkout_mode: :direct,
      checkout_inputs: {closed_sd_jwt: buyer.closed_sd_jwt, expected_checkout_jwt: checkout,
        trusted_provider_public_key_pem: provider.public_to_pem, trusted_merchant_public_key_pem: merchant.public_to_pem,
        expected_merchant_id: "shop", verified_at: NOW}, expected_payment: details,
      trusted_provider_public_key_pem: provider.public_to_pem, verified_at: NOW}
    assert(M::Payment.verify(**verification).verified?, "every raw candidate independently verifies before occurrence boundary")
    claims = JSON.parse(Base64.urlsafe_decode64(checkout.split(".")[1]))
    {verification: verification, checkout: claims, payment: details, merchant: merchant, provider: provider}
  end
  def self.ids(occurrence = "one")
    {tenant_id: "tenant", merchant_id: "shop", operation_id: "payment-#{occurrence}",
      approval_id: "consent-#{occurrence}", occurrence_id: "installment-#{occurrence}", order_id: "office-1"}
  end
  def self.authorize(store, fixture, ids)
    store.authorize!(**ids, mode: :direct, profile_ref: M::Payment::PROFILE_REF,
      checkout: fixture.fetch(:checkout), payment: fixture.fetch(:payment),
      receipt_context: {trusted_public_key_pem: fixture.fetch(:merchant).public_to_pem,
        expected_issuer: "processor", expected_payment_id: "payment", not_before: NOW, not_after: NOW+60})
  end
  def self.persist(path, fixture, ids)
    # Public wires and Host expectations only: no private keys serialized.
    File.write(path, JSON.generate(ids: ids, verification: fixture.fetch(:verification)), mode: "w", perm: 0o600)
  end
  def self.effects(directory)
    path = File.join(directory, "external-effects.jsonl")
    File.exist?(path) ? File.readlines(path).map { |line| JSON.parse(line) } : []
  end
  def self.spawn_worker(path, directory, phase = "none")
    read_parent, write_child = IO.pipe
    read_child, write_parent = IO.pipe
    pid = Process.spawn(RbConfig.ruby, File.expand_path(__FILE__), "worker", path, directory, "gate", phase,
      in: read_child, out: write_child)
    read_child.close; write_child.close
    worker = [pid, read_parent, write_parent]
    @live_workers << worker
    worker
  end
  def self.line(worker)
    Timeout.timeout(15) do
      wire = worker[1].gets
      raise "worker exited before observation" unless wire
      JSON.parse(wire)
    end
  end
  def self.wait(worker, killed: false)
    _, status = Timeout.timeout(15) { Process.wait2(worker[0]) }
    assert(killed ? status.signaled? && status.termsig == Signal.list.fetch("KILL") : status.success?, "worker termination observed")
    worker[1].close; worker[2].close
    @live_workers.delete(worker)
  end
  def self.single(path, directory, phase = "none")
    worker = spawn_worker(path, directory, phase)
    assert(line(worker)["ready"], "new process ready")
    worker[2].puts("go"); worker[2].flush
    result = line(worker)
    wait(worker)
    result
  end
  def self.run
    old_stdout = $stdout
    begin
      $stdout = StringIO.new
      context = ConditionalCheckoutExample.run
    ensure
      $stdout = old_stdout
    end
    original = fixture(context)
    @wire_sha = Digest::SHA256.hexdigest(original.fetch(:verification).fetch(:closed_sd_jwt))
    Dir.mktmpdir("ap2-process-oracle-") do |workspace|
      # Each case owns a separate DB; all contenders within a case share it.
      race = File.join(workspace, "race"); Dir.mkdir(race)
      store = A::SQLiteStore.create(path: File.join(race, "ledger.sqlite3"))
      authorize(store, original, ids)
      path = File.join(race, "public.json"); persist(path, original, ids)
      workers = Array.new(8) { spawn_worker(path, race) }
      workers.each { |worker| assert(line(worker)["ready"], "all workers blocked at independent process barrier") }
      workers.each { |worker| worker[2].puts("go"); worker[2].flush }
      results = workers.map { |worker| line(worker) }
      workers.each { |worker| wait(worker) }
      assert(results.count { |r| r["acquired"] } == 1, "one acceptance ticket across eight processes")
      assert(results.count { |r| r["dispatched"] } == 1 && effects(race).size == 1,
        "one durable external START across eight processes; observed=#{JSON.generate(results)}")
      assert(effects(race).first.fetch("wire_sha256") == @wire_sha, "dispatched original received wire")
      assert(!single(path, race)["dispatched"] && effects(race).size == 1, "fresh-process restart preserves processing reservation")
      @cases << {case: "eight_process_race", workers: 8, external_starts: effects(race).size}

      %w[before_accept after_reserve after_start after_effect].each do |phase|
        directory = File.join(workspace, phase); Dir.mkdir(directory)
        local = A::SQLiteStore.create(path: File.join(directory, "ledger.sqlite3"))
        authorize(local, original, ids)
        public_path = File.join(directory, "public.json"); persist(public_path, original, ids)
        worker = spawn_worker(public_path, directory, phase)
        assert(line(worker)["ready"], "crash worker ready")
        worker[2].puts("go"); worker[2].flush
        assert(line(worker)["checkpoint"] == phase, "real process reached requested crash boundary")
        Process.kill("KILL", worker[0]); wait(worker, killed: true)
        before = effects(directory).size
        retry_result = single(public_path, directory)
        expected = phase == "before_accept" ? 1 : before
        assert(effects(directory).size == expected, "restart does not repeat an uncertain or started mock effect")
        assert(retry_result["dispatched"] == (phase == "before_accept"), "only never-reserved case may obtain execution")
        @cases << {case: "sigkill_#{phase}", effects_before_restart: before, effects_after_restart: effects(directory).size}
      end
      # A fresh signature/authorization is not a new merchant occurrence.
      rebound = fixture(context)
      resign_path = File.join(race, "resigned.json"); persist(resign_path, rebound, ids)
      assert(rebound[:verification][:closed_sd_jwt] != original[:verification][:closed_sd_jwt], "new signature changes document hash")
      retained = single(resign_path, race)
      assert(!retained["dispatched"] && effects(race).size == 1 && retained["retained_wire_sha256"] == @wire_sha,
        "re-signed mandate preserves original signed wire and prior effect")
      merchant = original.fetch(:merchant)
      resigned_checkout = M::CheckoutJWT.sign(checkout: original.fetch(:checkout), profile_ref: M::ScopedConstraints::MULTI_PROFILE_REF,
        signer: sign(merchant), public_key_pem: merchant.public_to_pem).jwt
      resigned = fixture(context, checkout: resigned_checkout)
      assert(resigned[:payment]["transaction_id"] != original[:payment]["transaction_id"], "re-signed Checkout changes normative transaction_id")
      persist(resign_path, resigned, ids)
      retained = single(resign_path, race)
      assert(!retained["dispatched"] && effects(race).size == 1 && retained["retained_wire_sha256"] == @wire_sha,
        "semantic occurrence preserves first wire across Checkout re-signing")
      rotated_key = OpenSSL::PKey::EC.generate("prime256v1")
      rotated_checkout = M::CheckoutJWT.sign(checkout: original.fetch(:checkout), profile_ref: M::ScopedConstraints::MULTI_PROFILE_REF,
        signer: sign(rotated_key), public_key_pem: rotated_key.public_to_pem).jwt
      rotated = fixture(context, checkout: rotated_checkout, merchant: rotated_key)
      persist(resign_path, rotated, ids)
      assert(!single(resign_path, race)["dispatched"] && effects(race).size == 1, "authenticated stable merchant identity survives key rotation")
      arbitrary = ids.merge(operation_id: "arbitrary-retry-operation")
      persist(resign_path, original, arbitrary)
      assert(!single(resign_path, race)["dispatched"] && effects(race).size == 1, "caller cannot create new operation for consumed approval occurrence")
      begin
        authorize(store, original, arbitrary)
      rescue A::Conflict
        assert(true, "approval occurrence uniqueness also binds protected authorization enrollment")
      else
        assert(false, "same approval occurrence must not enroll another operation")
      end
      changed_checkout = Marshal.load(Marshal.dump(original.fetch(:checkout)))
      row = changed_checkout.fetch("line_items").first
      row.fetch("item")["price"] += 100
      row.fetch("totals").each { |total| total["amount"] += 100 * row.fetch("quantity") }
      changed_checkout.fetch("totals").each { |total| total["amount"] += 100 * row.fetch("quantity") }
      changed_wire = M::CheckoutJWT.sign(checkout: changed_checkout, profile_ref: M::ScopedConstraints::MULTI_PROFILE_REF,
        signer: sign(merchant), public_key_pem: merchant.public_to_pem).jwt
      changed = fixture(context, checkout: changed_wire)
      persist(resign_path, changed, ids)
      mismatch = single(resign_path, race)
      assert(mismatch["acceptance_status"] == "conflict" && !mismatch["dispatched"] && effects(race).size == 1,
        "independently valid changed terms conflict under existing operation uniqueness")
      next_ids = ids("two")
      authorize(store, original, next_ids)
      persist(resign_path, original, next_ids)
      duplicated_closed = single(resign_path, race)
      assert(duplicated_closed["acceptance_status"] == "conflict" && !duplicated_closed["dispatched"] && effects(race).size == 1,
        "same exact FinalClosed remains consumed even under a distinct protected grant")
      # A genuinely separate Host-approved occurrence needs fresh authority.
      # The semantic terms stay equal, while the authenticated Direct signature
      # and disclosure salt are fresh; reusing the old exact wire is forbidden.
      fresh_occurrence = fixture(context)
      persist(resign_path, fresh_occurrence, next_ids)
      assert(single(resign_path, race)["dispatched"] && effects(race).size == 2, "separately Host-authorized occurrence with fresh authority may execute once")
      assert(!single(resign_path, race)["dispatched"] && effects(race).size == 2, "new occurrence also remains one-shot")
      @cases << {case: "resign_rekey_occurrence", distinct_authorized_occurrences: 2, external_starts: effects(race).size}
      # Trusted reconciliation saves the exact receipt against the FIRST wire.
      receipt = M::PaymentReceipt.sign(closed_sd_jwt: original.fetch(:verification).fetch(:closed_sd_jwt),
        issuer: "processor", payment_id: "payment", outcome: "Success", issued_at: NOW,
        psp_confirmation_id: "synthetic-psp", network_confirmation_id: "synthetic-network",
        signer: sign(merchant), public_key_pem: merchant.public_to_pem).jwt
      service = A::Service.new(store: store)
      wrong_reference = M::PaymentReceipt.sign(closed_sd_jwt: rebound.fetch(:verification).fetch(:closed_sd_jwt),
        issuer: "processor", payment_id: "payment", outcome: "Success", issued_at: NOW,
        psp_confirmation_id: "synthetic-psp", network_confirmation_id: "synthetic-network",
        signer: sign(merchant), public_key_pem: merchant.public_to_pem).jwt
      invalid_reconciliation = service.reconcile(**ids, receipt_jwt: wrong_reference, verified_at: NOW)
      assert(invalid_reconciliation.status == :rejected && service.lookup(**ids).receipt_jwt.nil?,
        "valid signature over replacement wire reference cannot finalize original attempt")
      finished = service.reconcile(**ids, receipt_jwt: receipt, verified_at: NOW)
      assert(finished.status == :receipt_success && finished.ticket.nil? && finished.receipt_jwt == receipt &&
        finished.closed_sd_jwt == original.fetch(:verification).fetch(:closed_sd_jwt), "reconcile preserves first wire and exact authenticated receipt")
      persist(resign_path, resigned, ids)
      again = single(resign_path, race)
      assert(again["status"] == "receipt_success" && !again["dispatched"] &&
        again["retained_receipt_sha256"] == Digest::SHA256.hexdigest(receipt) && effects(race).size == 2,
        "fresh process returns retained receipt without minting a dispatch ticket")
      unknown_dir = File.join(workspace, "explicit-unknown"); Dir.mkdir(unknown_dir)
      unknown_store = A::SQLiteStore.create(path: File.join(unknown_dir, "ledger.sqlite3"))
      authorize(unknown_store, original, ids)
      unknown_path = File.join(unknown_dir, "public.json"); persist(unknown_path, original, ids)
      assert(single(unknown_path, unknown_dir, "mark_unknown")["status"] == "unknown", "mock outcome recorded unknown")
      assert(!single(unknown_path, unknown_dir)["dispatched"] && effects(unknown_dir).size == 1, "unknown remains permanently non-dispatchable on restart")
      recovered = A::Service.new(store: unknown_store).reconcile(**ids, receipt_jwt: receipt, verified_at: NOW)
      assert(recovered.status == :receipt_success && recovered.ticket.nil? && recovered.receipt_jwt == receipt,
        "authentic receipt reconciles unknown without an execution ticket")
      @cases << {case: "receipt_reconciliation", original_wire_retained: true, explicit_unknown_effects: effects(unknown_dir).size}
    end
    puts JSON.generate(status: "PASS", checks: @checks, cases: @cases, original_closed_sha256: @wire_sha,
      runtime: {ruby: RUBY_VERSION, platform: RUBY_PLATFORM, sqlite3_gem: Gem.loaded_specs.fetch("sqlite3").version.to_s,
        sqlite: SQLite3::SQLITE_VERSION},
      scope: "independent process barrier and durable external mock counter; actual SIGKILL/restart; signed reauthorization and Checkout re-sign/rekey",
      limits: "single host/local SQLite and synthetic effects only; no distributed exactly-once, settlement or production durability claim")
  ensure
    # A failed assertion must not leave children blocked at a crash checkpoint.
    @live_workers.each do |worker|
      Process.kill("KILL", worker[0]) rescue nil
      Process.wait(worker[0]) rescue nil
      worker[1].close rescue nil
      worker[2].close rescue nil
    end
  end
end
ReplayProcessOracle.run
