# frozen_string_literal: true
# Independent process oracle: signed synthetic inputs; fsynced local mock effects.
# No real processor, settlement or distributed exactly-once claim.
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
def symbolize(value) = value.to_h { |key, item| [key.to_sym, item] }
def checkpoint(actual, expected)
  return unless actual == expected
  puts JSON.generate(checkpoint: actual)
  STDOUT.flush
  STDIN.read
end
if ARGV.first == "worker"
  STDOUT.sync = true
  data = JSON.parse(File.read(ARGV.fetch(1)))
  directory, phase = ARGV.values_at(2, 3)
  raw = symbolize(data.fetch("raw"))
  raw[:checkout_mode] = raw.fetch(:checkout_mode).to_sym
  raw[:checkout_inputs] = symbolize(raw.fetch(:checkout_inputs))
  scope = symbolize(data.fetch("scope"))
  store = A::LongSQLiteStore.new(path: File.join(directory, "ledger.sqlite3"))
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
      file.puts(JSON.generate(processor_key: execution.processor_key,
        amount: execution.payment.fetch("payment_amount").fetch("amount"),
        wire_sha256: Digest::SHA256.hexdigest(execution.closed_sd_jwt)))
      file.flush
      file.fsync
    end
    service.unknown(ticket: result.ticket) if phase == "unknown"
    if phase == "error"
      service.finish(ticket: result.ticket, receipt_jwt: data.fetch("error_receipt"), verified_at: raw.fetch(:verified_at))
    end
  end
  checkpoint("after_effect", phase)
  current = service.lookup(**scope)
  puts JSON.generate(status: result.status, retained_status: current.status,
    ticket: !result.ticket.nil?, dispatch: !execution.nil?)
  store.close
  exit 0
end
require_relative "../examples/long_payment_acceptance"
module LongPaymentProcessOracle
  @checks = 0
  @live = []
  @cases = []
  def self.assert(value, why)
    @checks += 1
    raise "long process oracle: #{why}" unless value
  end
  def self.quiet
    prior = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = prior
  end
  def self.worker(path, directory, phase = "none")
    parent_read, child_write = IO.pipe
    child_read, parent_write = IO.pipe
    pid = Process.spawn(RbConfig.ruby, File.expand_path(__FILE__), "worker", path, directory, phase, in: child_read, out: child_write)
    child_read.close
    child_write.close
    value = [pid, parent_read, parent_write]
    @live << value
    value
  end
  def self.line(worker) = Timeout.timeout(30) { JSON.parse(worker[1].gets || raise("worker exited early")) }
  def self.release(worker)
    worker[2].puts("go")
    worker[2].flush
  end
  def self.wait(worker, killed: false)
    _, status = Timeout.timeout(30) { Process.wait2(worker[0]) }
    assert(killed ? status.signaled? && status.termsig == Signal.list.fetch("KILL") : status.success?, "worker exit status")
    worker[1].close
    worker[2].close
    @live.delete(worker)
  end
  def self.once(path, directory, phase = "none")
    w = worker(path, directory, phase)
    assert(line(w)["ready"], "fresh independent process ready")
    release(w)
    result = line(w)
    wait(w)
    result
  end
  def self.effects(directory)
    path = File.join(directory, "mock-effects.jsonl")
    File.exist?(path) ? File.readlines(path).map { |line| JSON.parse(line) } : []
  end
  def self.parallel(paths, directory)
    workers = paths.map { |path| worker(path, directory) }
    workers.each { |w| assert(line(w)["ready"], "all independent workers reached process barrier") }
    workers.each { |w| release(w) }
    result = workers.map { |w| line(w) }
    workers.each { |w| wait(w) }
    result
  end
  # Fixture adapters below only construct signed public input and authenticated
  # Host authorization. Expected cardinality/amount/period rules are literal in
  # the oracle; they never call the implementation's decision/calculation code.
  def self.build(max_occurrences: 12, budget_max: 480000)
    quiet { LongPaymentAcceptanceExample.build(max_occurrences: max_occurrences, budget_max: budget_max) }
  end
  def self.prepare(directory, fixture)
    Dir.mkdir(directory)
    store = A::LongSQLiteStore.create(path: File.join(directory, "ledger.sqlite3"))
    LongPaymentAcceptanceExample.enroll_series(store, fixture)
    store
  end
  def self.item(fixture, period, id)
    LongPaymentAcceptanceExample.occurrence(fixture, period: period, id: id)
  end
  def self.enroll(store, directory, fixture, period, id)
    value = item(fixture, period, id)
    assert(M::LongPayment.verify(**value.fetch(:raw)).verified?, "candidate cryptographically verifies independently of ledger")
    store.authorize!(**value.fetch(:authorization))
    path = File.join(directory, "public-#{id}.json")
    File.write(path, JSON.generate(scope: value.fetch(:scope), raw: value.fetch(:raw),
      error_receipt: value.fetch(:error_receipt)), mode: "w", perm: 0o600)
    [path, value]
  end
  def self.usage(store, fixture, count, amount)
    actual = store.usage(**fixture.fetch(:series_scope))
    assert(actual[:currency] == "JPY" && actual[:reserved_occurrences] == count && actual[:reserved_amount] == amount,
      "durable independent expected quota #{count}/#{amount}; observed=#{JSON.generate(actual)}")
  end
  def self.race(workspace, label, periods, max_count, budget, expected)
    fixture = build(max_occurrences: max_count, budget_max: budget)
    directory = File.join(workspace, label)
    store = prepare(directory, fixture)
    paths = if periods.uniq.size == 1
      path, = enroll(store, directory, fixture, periods.first, "#{label}-first")
      Array.new(periods.size, path)
    else
      periods.each_with_index.map { |period, i| enroll(store, directory, fixture, period, "#{label}-#{i}").first }
    end
    results = parallel(paths, directory)
    assert(results.count { |result| result["ticket"] } == expected, "#{label} independent Ticket cardinality")
    assert(results.count { |result| result["dispatch"] } == expected, "#{label} independent START cardinality")
    observed = effects(directory)
    assert(observed.size == expected && observed.sum { |effect| effect.fetch("amount") } == expected * 40000,
      "#{label} fsynced external counter independently matches quota")
    assert(observed.map { |effect| effect.fetch("processor_key") }.uniq.size == expected, "processor keys unique")
    paths.each { |path| assert(!once(path, directory)["dispatch"], "retry cannot dispatch again") }
    if periods.uniq.size == 1
      alternate = item(fixture, periods.first, "#{label}-new-operation")
      begin
        store.authorize!(**alternate.fetch(:authorization))
      rescue A::Conflict
        assert(true, "new operation identifier cannot obtain another protected grant in consumed period")
      else
        assert(false, "duplicate protected period grant unexpectedly created")
      end
    end
    usage(store, fixture, expected, expected * 40000)
    store.close
    reopened = A::LongSQLiteStore.new(path: File.join(directory, "ledger.sqlite3"))
    usage(reopened, fixture, expected, expected * 40000)
    reopened.close
    @cases << {case: label, workers: paths.size, starts: expected, spent: expected * 40000}
  end
  def self.authority_controls(workspace)
    fixture = build(max_occurrences: 3, budget_max: 120000)
    directory = File.join(workspace, "rotation")
    store = prepare(directory, fixture)
    service = A::Service.new(store: store)
    _, january = enroll(store, directory, fixture, "2028-01", "prior-key")
    prior = service.accept(**january.fetch(:scope), mode: :conditional, verification_inputs: january.fetch(:raw))
    assert(prior.ticket, "original authority reserves before rotation")
    provider, agent = Array.new(2) { OpenSSL::PKey::EC.generate("prime256v1") }
    replacement = fixture.merge(wire: fixture.fetch(:wire).rotate(provider: provider, agent: agent,
      issued_at: LongPaymentExample::PERIODS.fetch("2028-02")[0], authority: {snapshot_id: "rotated-registry-2"}))
    _, february = enroll(store, directory, replacement, "2028-02", "new-key")
    unapproved = service.accept(**february.fetch(:scope), mode: :conditional, verification_inputs: february.fetch(:raw))
    assert(unapproved.ticket.nil? && %i[conflict rejected].include?(unapproved.status), "new cryptographically valid Root cannot self-authorize rotation")
    usage(store, fixture, 1, 40000)
    LongPaymentAcceptanceExample.replace_root(store, fixture, replacement, "2028-02")
    assert(service.start(ticket: prior.ticket, verification_inputs: january.fetch(:raw)).nil?, "prior epoch Ticket cannot start after issuer+Agent rotation")
    current = service.accept(**february.fetch(:scope), mode: :conditional, verification_inputs: february.fetch(:raw))
    assert(current.ticket && service.start(ticket: current.ticket, verification_inputs: february.fetch(:raw)), "authorized replacement issuer+Agent can start within retained quota")
    service.unknown(ticket: current.ticket)
    usage(store, fixture, 2, 80000)
    _, march = enroll(store, directory, replacement, "2028-03", "revoked-root")
    pending = service.accept(**march.fetch(:scope), mode: :conditional, verification_inputs: march.fetch(:raw))
    assert(pending.ticket, "current replacement reserves before revocation")
    epoch = store.usage(**fixture.fetch(:series_scope)).fetch(:epoch)
    store.revoke_root!(**fixture.fetch(:series_scope), expected_epoch: epoch)
    assert(service.start(ticket: pending.ticket, verification_inputs: march.fetch(:raw)).nil?, "revoked current Root cannot start pending Ticket")
    usage(store, fixture, 3, 120000)
    assert(!store.usage(**fixture.fetch(:series_scope)).fetch(:authority_active), "revoked authority is durable and inactive")
    store.close
    @cases << {case: "protected_combined_issuer_agent_rotation", retained_count: 3, retained_spent: 120000,
      old_ticket_start: false, unapproved_new_root_ticket: false, approved_replacement_start: true, revoked_root_start: false,
      execution_observation: "in-process capability control; no external effect performed"}

    fixture = build(max_occurrences: 2, budget_max: 80000)
    directory = File.join(workspace, "authority_and_late_receipt")
    store = prepare(directory, fixture)
    service = A::Service.new(store: store)
    _, first = enroll(store, directory, fixture, "2028-01", "late-receipt")
    result = service.accept(**first.fetch(:scope), mode: :conditional, verification_inputs: first.fetch(:raw))
    assert(result.ticket && service.start(ticket: result.ticket, verification_inputs: first.fetch(:raw)), "historical attempt started under original trust")
    service.unknown(ticket: result.ticket)
    _, second = enroll(store, directory, fixture, "2028-02", "feed-invalidated")
    pending = service.accept(**second.fetch(:scope), mode: :conditional, verification_inputs: second.fetch(:raw))
    assert(pending.ticket, "second attempt reserved before external-feed invalidation")
    epoch = store.usage(**fixture.fetch(:series_scope)).fetch(:epoch)
    store.invalidate_authority!(**fixture.fetch(:series_scope), expected_epoch: epoch)
    assert(service.start(ticket: pending.ticket, verification_inputs: second.fetch(:raw)).nil?, "protected feed invalidation blocks otherwise valid fresh start")
    store.revoke_series!(**fixture.fetch(:series_scope))
    late = LongPaymentExample::EXP + 1
    wrong_key = OpenSSL::PKey::EC.generate("prime256v1")
    wrong = M::PaymentReceipt.sign(closed_sd_jwt: first.fetch(:raw).fetch(:closed_sd_jwt), profile_ref: M::LongPayment::PROFILE_REF,
      issuer: "processor", payment_id: "payment-2028-01", outcome: "Success", issued_at: first.fetch(:raw).fetch(:verified_at),
      psp_confirmation_id: "synthetic", network_confirmation_id: "synthetic", signer: LongPaymentExample.signer(wrong_key), public_key_pem: wrong_key.public_to_pem)
    bad = service.reconcile(**first.fetch(:scope), receipt_jwt: wrong.jwt, verified_at: late)
    assert(bad.status == :rejected && bad.ticket.nil?, "new signer cannot replace pinned historical Receipt trust")
    good = service.reconcile(**first.fetch(:scope), receipt_jwt: first.fetch(:payment_receipt), verified_at: late)
    assert(good.status == :receipt_success && good.ticket.nil?, "valid original Receipt may record historical outcome after authority expiry/revocation without Ticket")
    usage(store, fixture, 2, 80000)
    assert(service.start(ticket: pending.ticket, verification_inputs: second.fetch(:raw)).nil?, "Receipt reconciliation never reauthorizes reserved effect")
    store.close
    @cases << {case: "feed_revocation_and_late_receipt", invalidated_pending_start: false, changed_receipt_key: false,
      original_late_receipt: "receipt_success", returned_ticket: false, retained_count: 2, retained_spent: 80000,
      execution_observation: "in-process capability control; no external effect performed"}
  end
  def self.run
    fixture = build(max_occurrences: 2, budget_max: 80000)
    Dir.mktmpdir("ap2-long-oracle-") do |workspace|
      race(workspace, "same_period", Array.new(8, "2028-01"), 12, 480000, 1)
      periods = (1..8).map { |month| format("2028-%02d", month) }
      race(workspace, "count_only", periods, 2, 480000, 2)
      race(workspace, "budget_only", periods, 12, 80000, 2)
      mislabeled_dir = File.join(workspace, "mislabeled_period")
      mislabeled_store = prepare(mislabeled_dir, fixture)
      mislabeled = item(fixture, "2028-01", "wrong-window-label")
      assert(M::LongPayment.verify(**mislabeled.fetch(:raw)).verified?, "January signed candidate cryptographically valid before window check")
      wrong_scope = mislabeled.fetch(:scope).merge(occurrence_id: "2028-02")
      wrong_authorization = mislabeled.fetch(:authorization).merge(occurrence_id: "2028-02")
      mislabeled_store.authorize!(**wrong_authorization)
      wrong = A::Service.new(store: mislabeled_store).accept(**wrong_scope, mode: :conditional,
        verification_inputs: mislabeled.fetch(:raw))
      assert(wrong.ticket.nil? && wrong.status == :rejected, "first genuinely signed January candidate cannot consume February by caller label")
      usage(mislabeled_store, fixture, 0, 0)
      mislabeled_store.close
      @cases << {case: "period_derived_from_trusted_clock", cryptographic_precheck: true, ticket: false, spent: 0}
      annual = build
      annual_dir = File.join(workspace, "twelve_windows")
      annual_store = prepare(annual_dir, annual)
      original_roots = nil
      (1..12).each do |month|
        period = format("2028-%02d", month)
        path, value = enroll(annual_store, annual_dir, annual, period, "month-#{month}")
        raw = value.fetch(:raw)
        roots = [raw.fetch(:open_sd_jwt), raw.fetch(:checkout_inputs).fetch(:root_presentation)].map do |wire|
          Digest::SHA256.hexdigest(wire.split("~").first)
        end
        original_roots ||= roots
        assert(roots == original_roots, "same two originally signed Open JWTs preserved for all twelve controlled clocks")
        assert(once(path, annual_dir, "unknown")["dispatch"], "one first dispatch in each explicit calendar window")
        usage(annual_store, annual, month, month * 40000)
      end
      assert(effects(annual_dir).size == 12 && effects(annual_dir).sum { |row| row.fetch("amount") } == 480000,
        "twelve-window independent fsynced counter exactly480000JPY")
      repeated = item(annual, "2028-12", "second-december")
      begin
        annual_store.authorize!(**repeated.fetch(:authorization))
      rescue A::Conflict
        assert(true, "new identifier cannot acquire thirteenth protected occurrence in consumed window")
      else
        assert(false, "thirteenth duplicate grant unexpectedly authorized")
      end
      usage(annual_store, annual, 12, 480000)
      annual_store.close
      @cases << {case: "twelve_controlled_windows", starts: 12, spent: 480000, original_root_sha256: original_roots}
      %w[before_accept after_reserve after_start after_effect unknown error].each do |phase|
        directory = File.join(workspace, phase)
        store = prepare(directory, fixture)
        path, = enroll(store, directory, fixture, "2028-01", phase)
        if %w[unknown error].include?(phase)
          result = once(path, directory, phase)
          assert(result["retained_status"] == (phase == "unknown" ? "unknown" : "receipt_error"), "explicit outcome durable")
        else
          w = worker(path, directory, phase)
          assert(line(w)["ready"], "crash process ready")
          release(w)
          assert(line(w)["checkpoint"] == phase, "actual kill after requested phase")
          Process.kill("KILL", w[0])
          wait(w, killed: true)
        end
        before = effects(directory).size
        prior_count = phase == "before_accept" ? 0 : 1
        usage(store, fixture, prior_count, prior_count * 40000)
        retry_result = once(path, directory)
        assert(retry_result["dispatch"] == (phase == "before_accept"), "only previously unreserved occurrence may dispatch")
        assert(effects(directory).size == (phase == "before_accept" ? 1 : before), "no repeated external effect after reservation")
        usage(store, fixture, 1, 40000)
        next_path, = enroll(store, directory, fixture, "2028-02", "next-#{phase}")
        third_path, = enroll(store, directory, fixture, "2028-03", "third-#{phase}")
        assert(once(next_path, directory)["dispatch"], "one remaining distinct period fits retained quota")
        assert(!once(third_path, directory)["dispatch"], "crash/unknown/Error never refunds quota")
        usage(store, fixture, 2, 80000)
        store.close
        @cases << {case: phase, observed_effects_before_restart: before, retained_count: 2, retained_spent: 80000}
      end
      directory = File.join(workspace, "rollback")
      store = prepare(directory, fixture)
      _, candidate = enroll(store, directory, fixture, "2028-01", "rollback")
      fault = SQLite3::Database.new(File.join(directory, "ledger.sqlite3"))
      fault.execute("CREATE TRIGGER abort_mock_claim AFTER INSERT ON ap2_attempts BEGIN SELECT RAISE(ABORT,'synthetic atomic rollback'); END")
      service = A::Service.new(store: store)
      failure = service.accept(**candidate.fetch(:scope), mode: :conditional, verification_inputs: candidate.fetch(:raw))
      assert(failure.ticket.nil? && %i[unavailable conflict rejected].include?(failure.status), "failed transaction returns no capability")
      usage(store, fixture, 0, 0)
      assert(fault.get_first_value("SELECT COUNT(*) FROM ap2_attempts") == 0, "independent SQL sees complete rollback")
      fault.execute("DROP TRIGGER abort_mock_claim")
      fault.close
      assert(service.accept(**candidate.fetch(:scope), mode: :conditional, verification_inputs: candidate.fetch(:raw)).ticket,
        "complete rollback permits a clean first reservation")
      usage(store, fixture, 1, 40000)
      store.close
      @cases << {case: "transaction_rollback", failed_ticket: false, rolled_back_count: 0, rolled_back_spent: 0}
      authority_controls(workspace)
    end
    puts JSON.generate(status: "PASS", checks: @checks, cases: @cases,
      runtime: {ruby: RUBY_VERSION, platform: RUBY_PLATFORM, sqlite3_gem: Gem.loaded_specs.fetch("sqlite3").version.to_s, sqlite: SQLite3::SQLITE_VERSION},
      scope: "independent processes, actual SIGKILL, fsynced local effects, atomic rollback, fixed Host periods",
      limitations: "synthetic single-host mock effects; no real payment, settlement or distributed exactly-once proof")
  ensure
    @live.each do |w|
      Process.kill("KILL", w[0]) rescue nil
      Process.wait(w[0]) rescue nil
      w[1].close rescue nil
      w[2].close rescue nil
    end
  end
end
LongPaymentProcessOracle.run
