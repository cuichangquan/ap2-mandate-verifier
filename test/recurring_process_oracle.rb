# frozen_string_literal: true
# Independent process/quota oracle. All effects are fsynced local mock records.
require_relative "runtime_dependencies"
require "tmpdir"
require "timeout"
require "rbconfig"
require "stringio"
if ENV["AP2_INSTALLED"] == "1"
  gem "ap2_mandate_verifier", "= #{ENV.fetch('AP2_GEM_VERSION')}"
  require "ap2_mandate_verifier"
  installed = File.realpath(Gem.loaded_specs.fetch("ap2_mandate_verifier").full_gem_path + "/lib")
  source = File.realpath(File.join(__dir__, "../lib"))
  features = $LOADED_FEATURES.select { |f| f.match?(%r{/ap2_mandate_verifier(?:/|\.rb\z)}) }
  raise "source overlay" unless installed != source && !features.empty? && features.all? { |f| File.realpath(f).start_with?(installed + "/") }
else
  $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
  require "ap2_mandate_verifier"
end
M = AP2MandateVerifier
A = M::PaymentAcceptance
NOW = 1_800_000_000

def symbolize(hash) = hash.to_h { |k, v| [k.to_sym, v] }
def checkpoint(phase, expected)
  return unless phase == expected
  puts JSON.generate(checkpoint: phase)
  STDOUT.flush
  STDIN.read
end
if ARGV.first == "worker"
  STDOUT.sync = true
  data = JSON.parse(File.read(ARGV.fetch(1)))
  raw = symbolize(data.fetch("raw"))
  raw[:checkout_mode] = raw.fetch(:checkout_mode).to_sym
  raw[:checkout_inputs] = symbolize(raw.fetch(:checkout_inputs))
  scope = symbolize(data.fetch("scope"))
  directory, phase = ARGV.values_at(2, 3)
  store = A::RecurringSQLiteStore.new(path: File.join(directory, "ledger.sqlite3"))
  service = A::Service.new(store: store)
  puts JSON.generate(ready: true)
  STDIN.gets
  checkpoint("before_accept", phase)
  result = service.accept(**scope, mode: :conditional, verification_inputs: raw)
  checkpoint("after_reserve", phase)
  execution = result.ticket && service.start(ticket: result.ticket, verification_inputs: raw)
  checkpoint("after_start", phase)
  if execution
    File.open(File.join(directory, "mock-effects.jsonl"), File::WRONLY | File::CREAT | File::APPEND, 0o600) do |file|
      file.flock(File::LOCK_EX)
      file.puts(JSON.generate(processor_key: execution.processor_key, amount: execution.payment.fetch("payment_amount").fetch("amount"),
        wire_sha256: Digest::SHA256.hexdigest(execution.closed_sd_jwt)))
      file.flush; file.fsync
    end
    service.unknown(ticket: result.ticket) if phase == "unknown"
    service.finish(ticket: result.ticket, receipt_jwt: data.fetch("error_receipt"), verified_at: NOW) if phase == "error"
  end
  checkpoint("after_effect", phase)
  current = service.lookup(**scope)
  puts JSON.generate(status: result.status, retained_status: current.status, ticket: !result.ticket.nil?, dispatch: !execution.nil?)
  store.close
  exit 0
end

require_relative "../examples/recurring_payment"
module RecurringProcessOracle
  @checks = 0
  @live = []
  @cases = []
  def self.assert(value, why)
    @checks += 1
    raise "recurring process oracle: #{why}" unless value
  end
  def self.quiet
    previous = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = previous
  end
  def self.item(fixture, id)
    value = RecurringPaymentExample.occurrence(fixture, id)
    assert(M::RecurringPayment.verify(**value.fetch(:raw)).verified?, "raw signed candidate independently verifies before quota")
    value
  end
  def self.prepare(directory, fixture)
    Dir.mkdir(directory)
    store = A::RecurringSQLiteStore.create(path: File.join(directory, "ledger.sqlite3"))
    RecurringPaymentExample.enroll_series(store, fixture)
    store
  end
  def self.enroll(store, directory, fixture, identity)
    value = item(fixture, identity)
    store.authorize!(**value.fetch(:authorization))
    # Only synthetic public raw verifier input and authenticated Host scope cross
    # the process boundary. No fixture keys or caller-made proofs are serialized.
    path = File.join(directory, "public-#{identity}.json")
    merchant = fixture.fetch(:state).fetch(:keys).last
    error = M::PaymentReceipt.sign(closed_sd_jwt: value.fetch(:raw).fetch(:closed_sd_jwt),
      profile_ref: M::RecurringPayment::PROFILE_REF, issuer: "processor", payment_id: "payment-#{identity}",
      outcome: "Error", error: "synthetic_decline", error_description: "Simulated rejection", issued_at: NOW,
      signer: M::CheckoutJWT.es256_signer(private_key: merchant), public_key_pem: merchant.public_to_pem).jwt
    File.write(path, JSON.generate(scope: value.fetch(:scope), raw: value.fetch(:raw), error_receipt: error), mode: "w", perm: 0o600)
    [path, value]
  end
  def self.worker(path, directory, phase = "none")
    parent_read, child_write = IO.pipe
    child_read, parent_write = IO.pipe
    pid = Process.spawn(RbConfig.ruby, File.expand_path(__FILE__), "worker", path, directory, phase, in: child_read, out: child_write)
    child_read.close; child_write.close
    value = [pid, parent_read, parent_write]
    @live << value
    value
  end
  def self.line(worker)
    Timeout.timeout(20) { JSON.parse(worker[1].gets || raise("worker exited early")) }
  end
  def self.wait(worker, killed: false)
    _, status = Timeout.timeout(20) { Process.wait2(worker[0]) }
    assert(killed ? status.signaled? && status.termsig == Signal.list.fetch("KILL") : status.success?, "worker exit status")
    worker[1].close; worker[2].close; @live.delete(worker)
  end
  def self.release(worker)
    worker[2].puts("go"); worker[2].flush
  end
  def self.once(path, directory, phase = "none")
    w = worker(path, directory, phase)
    assert(line(w)["ready"], "fresh worker ready")
    release(w)
    value = line(w)
    wait(w)
    value
  end
  def self.effects(directory)
    path = File.join(directory, "mock-effects.jsonl")
    File.exist?(path) ? File.readlines(path).map { |line| JSON.parse(line) } : []
  end
  def self.usage(store, fixture, count, amount)
    value = store.usage(**fixture.fetch(:series_scope))
    assert(value[:currency] == "JPY" && value[:reserved_occurrences] == count && value[:reserved_amount] == amount,
      "durable usage equals independently expected reservations; observed=#{JSON.generate(value)}")
  end
  def self.isolated_limit_race(workspace, label, max_count, max_budget)
    isolated_fixture = quiet { RecurringPaymentExample.build(max_occurrences: max_count, budget_max: max_budget) }
    directory = File.join(workspace, label)
    store = prepare(directory, isolated_fixture)
    paths = (1..8).map { |i| enroll(store, directory, isolated_fixture, "#{label}-#{i}").first }
    workers = paths.map { |path| worker(path, directory) }
    workers.each { |w| assert(line(w)["ready"], "isolated quota race process barrier") }
    workers.each { |w| release(w) }
    outcomes = workers.map { |w| line(w) }
    workers.each { |w| wait(w) }
    assert(outcomes.count { |r| r["ticket"] } == 2 && outcomes.count { |r| r["dispatch"] } == 2,
      "#{label} independently constrains eight contenders to two starts")
    assert(effects(directory).size == 2 && effects(directory).sum { |row| row.fetch("amount") } == 600,
      "#{label} external counter matches independently expected charge")
    usage(store, isolated_fixture, 2, 600)
    store.close
    @cases << {case: label, workers: 8, max_count: max_count, budget_jpy: max_budget, effects: 2}
  end
  def self.run
    fixture = quiet { RecurringPaymentExample.build(max_occurrences: 2, budget_max: 600) }
    Dir.mktmpdir("ap2-recurring-oracle-") do |workspace|
      race = File.join(workspace, "race")
      store = prepare(race, fixture)
      paths = (1..8).map { |i| enroll(store, race, fixture, i).first }
      workers = paths.map { |path| worker(path, race) }
      workers.each { |w| assert(line(w)["ready"], "eight independently authorized processes reach barrier") }
      workers.each { |w| release(w) }
      results = workers.map { |w| line(w) }
      workers.each { |w| wait(w) }
      assert(results.count { |r| r["ticket"] } == 2 && results.count { |r| r["dispatch"] } == 2, "shared cap permits exactly two tickets/dispatches")
      assert(effects(race).size == 2 && effects(race).sum { |row| row.fetch("amount") } == 600, "external mock sees two starts totaling600JPY")
      assert(effects(race).map { |row| row.fetch("processor_key") }.uniq.size == 2, "distinct one-shot processor keys")
      usage(store, fixture, 2, 600)
      paths.each { |path| assert(!once(path, race)["dispatch"], "retry or overquota candidate never dispatches again") }
      usage(store, fixture, 2, 600)
      store.close
      reopened = A::RecurringSQLiteStore.new(path: File.join(race, "ledger.sqlite3"))
      usage(reopened, fixture, 2, 600)
      @cases << {case: "eight_distinct_occurrences", admitted: 2, effects: 2, total_jpy: 600}
      # Paired controls prevent either limit from hiding a missing implementation
      # of the other: count-only has excess budget, budget-only has excess count.
      isolated_limit_race(workspace, "count_only_race", 2, 2400)
      isolated_limit_race(workspace, "budget_only_race", 8, 600)

      %w[before_accept after_reserve after_start after_effect unknown error].each do |phase|
        directory = File.join(workspace, phase)
        local = prepare(directory, fixture)
        path, = enroll(local, directory, fixture, phase)
        if %w[unknown error].include?(phase)
          outcome = once(path, directory, phase)
          assert(outcome["retained_status"] == (phase == "unknown" ? "unknown" : "receipt_error"), "explicit outcome retained")
        else
          w = worker(path, directory, phase)
          assert(line(w)["ready"], "crash worker ready")
          release(w)
          assert(line(w)["checkpoint"] == phase, "worker reached requested true SIGKILL boundary")
          Process.kill("KILL", w[0]); wait(w, killed: true)
        end
        before = effects(directory).size
        first_count = phase == "before_accept" ? 0 : 1
        usage(local, fixture, first_count, first_count * 300)
        retry_result = once(path, directory)
        assert(retry_result["dispatch"] == (phase == "before_accept"), "only an unreserved occurrence may start after restart")
        assert(effects(directory).size == (phase == "before_accept" ? 1 : before), "no repeat external effect after reservation/unknown/Error")
        usage(local, fixture, 1, 300)
        next_path, = enroll(local, directory, fixture, "next-#{phase}")
        third_path, = enroll(local, directory, fixture, "third-#{phase}")
        assert(once(next_path, directory)["dispatch"], "one distinct remaining occurrence fits retained quota")
        assert(!once(third_path, directory)["dispatch"], "crash/unknown/Error never refunds capacity")
        usage(local, fixture, 2, 600)
        @cases << {case: phase, prior_effects: before, retained_reservations: 2, retained_jpy: 600}
        local.close
      end

      # Force a real database failure AFTER the quota increment but before its
      # encompassing transaction can commit. Expectations do not call quota code.
      rollback_dir = File.join(workspace, "rollback")
      rollback = prepare(rollback_dir, fixture)
      _, candidate = enroll(rollback, rollback_dir, fixture, "rollback")
      fault = SQLite3::Database.new(File.join(rollback_dir, "ledger.sqlite3"))
      fault.execute("CREATE TRIGGER abort_mock_claim AFTER INSERT ON ap2_attempts BEGIN SELECT RAISE(ABORT,'synthetic atomic rollback'); END")
      service = A::Service.new(store: rollback)
      failure = service.accept(**candidate.fetch(:scope), mode: :conditional, verification_inputs: candidate.fetch(:raw))
      assert(failure.ticket.nil? && %i[unavailable conflict rejected].include?(failure.status),
        "failed transaction returns no execution capability; status=#{failure.status}")
      assert(fault.get_first_value("SELECT COUNT(*) FROM ap2_attempts") == 0 &&
        fault.get_first_row("SELECT uses,spent FROM ap2_series") == [0, 0], "independent SQL observes count+amount+claim rolled back together")
      fault.execute("DROP TRIGGER abort_mock_claim"); fault.close
      usage(rollback, fixture, 0, 0)
      assert(service.accept(**candidate.fetch(:scope), mode: :conditional, verification_inputs: candidate.fetch(:raw)).ticket,
        "clean retry after complete rollback may reserve once")
      usage(rollback, fixture, 1, 300)
      @cases << {case: "transaction_rollback", status: failure.status, failed_attempt_rows: 0, failed_uses: 0, failed_spent: 0}

      # Protected series identity, rather than caller labels or new signatures,
      # owns the quota. The already full series must not become new capacity.
      begin
        RecurringPaymentExample.enroll_series(reopened, fixture.merge(series_scope: fixture.fetch(:series_scope).merge(approval_id: "new-label")))
      rescue A::Conflict
        assert(true, "same original signed Open cannot reset quota under another approval label")
      else
        assert(false, "root alias unexpectedly enrolled")
      end
      provider = fixture.fetch(:state).fetch(:keys).first
      parts = fixture.fetch(:open).split("~", -1)
      claims = JSON.parse(Base64.urlsafe_decode64(parts.first.split(".")[1]))
      parts[0] = JWT.encode(claims, provider, "ES256", {"typ" => "example+sd-jwt"})
      resigned = fixture.merge(open: parts.join("~"))
      assert(resigned[:open] != fixture[:open], "re-signing creates a different original JWT")
      begin
        RecurringPaymentExample.enroll_series(reopened, resigned)
      rescue A::Conflict
        assert(true, "same protected series rejects signed-root replacement")
      else
        assert(false, "re-signed root unexpectedly reset contract")
      end
      _, crossed = enroll(reopened, race, resigned, "resigned-root")
      mismatch = A::Service.new(store: reopened).accept(**crossed.fetch(:scope), mode: :conditional, verification_inputs: crossed.fetch(:raw))
      assert(mismatch.status == :conflict && mismatch.ticket.nil?, "genuine re-signed authority still fails pinned series boundary")
      usage(reopened, fixture, 2, 600)
      other = quiet { RecurringPaymentExample.build(max_occurrences: 2, budget_max: 600) }
      other[:series_scope] = other.fetch(:series_scope).merge(approval_id: "separate-series")
      RecurringPaymentExample.enroll_series(reopened, other)
      other_path, other_item = enroll(reopened, race, other, "other-series")
      assert(once(other_path, race)["dispatch"], "distinct authenticated series has its own capacity")
      usage(reopened, fixture, 2, 600); usage(reopened, other, 1, 300)
      tenant_mismatch = other_item.fetch(:scope).merge(tenant_id: "unrelated-tenant")
      denied = A::Service.new(store: reopened).accept(**tenant_mismatch, mode: :conditional, verification_inputs: other_item.fetch(:raw))
      assert(denied.ticket.nil? && denied.status == :rejected, "caller tenant cannot replace verified Host tenant")
      usage(reopened, other, 1, 300)
      @cases << {case: "series_root_tenant_binding", original_reserved: 2, independent_series_reserved: 1}
      reopened.close; rollback.close
    end
    puts JSON.generate(status: "PASS", checks: @checks, cases: @cases,
      original_open_sha256: Digest::SHA256.hexdigest(fixture.fetch(:open)),
      runtime: {ruby: RUBY_VERSION, platform: RUBY_PLATFORM, sqlite3_gem: Gem.loaded_specs.fetch("sqlite3").version.to_s, sqlite: SQLite3::SQLITE_VERSION},
      scope: "independent processes; actual SIGKILL; fsynced external mock starts; atomic SQLite fault rollback; protected series binding",
      limits: "JPY integer ON_DEMAND complete profile only; synthetic single-host effects, no calendar recurrence, settlement or distributed exactly-once claim")
  ensure
    @live.each do |w|
      Process.kill("KILL", w[0]) rescue nil
      Process.wait(w[0]) rescue nil
      w[1].close rescue nil
      w[2].close rescue nil
    end
  end
end
RecurringProcessOracle.run
