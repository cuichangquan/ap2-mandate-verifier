# frozen_string_literal: true
require_relative "runtime_dependencies"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__)) unless ENV["AP2_INSTALLED"] == "1"
require "ap2_mandate_verifier"
require "tmpdir"
require "stringio"
require_relative "../examples/conditional_checkout"

module PaymentAcceptanceTest
  M = AP2MandateVerifier
  A = M::PaymentAcceptance
  NOW = 1_800_000_000
  @count = 0
  def self.assert(value, label)
    @count += 1
    raise "payment acceptance: #{label}" unless value
  end
  def self.copy(value) = Marshal.load(Marshal.dump(value))
  def self.unavailable
    yield
    raise "expected unavailable"
  rescue A::Unavailable => error
    assert(error.cause.nil? && error.message == "payment acceptance storage unavailable", "fixed unavailable")
  end
  def self.conflict
    yield
    raise "expected conflict"
  rescue A::Conflict
    assert(true, "protected authorization conflict")
  end
  old = $stdout
  begin
    $stdout = StringIO.new
    state = ConditionalCheckoutExample.run
  ensure
    $stdout = old
  end
  provider, agent, merchant = state.fetch(:keys)
  signer = ->(key) { M::CheckoutJWT.es256_signer(private_key: key) }
  checkout = state.fetch(:closed).checkout_jwt
  details = M::Payment.details(checkout_jwt: checkout, trusted_merchant_public_key_pem: merchant.public_to_pem,
    expected_merchant_id: "shop", payment_instrument: {"id" => "card", "type" => "card"})
  buyer = M::Buyer.issue_closed(checkout_jwt: checkout, approved_checkout_jwt: checkout,
    trusted_merchant_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop", issued_at: NOW,
    expires_at: NOW + 60, signer: signer.call(provider), public_key_pem: provider.public_to_pem)
  payment = M::Payment.issue_direct(payment: details, approved_payment: details, issued_at: NOW,
    expires_at: NOW + 120, signer: signer.call(provider), public_key_pem: provider.public_to_pem)
  raw = {closed_sd_jwt: payment.closed_sd_jwt, checkout_mode: :direct, expected_payment: details,
    trusted_provider_public_key_pem: provider.public_to_pem, verified_at: NOW,
    checkout_inputs: {closed_sd_jwt: buyer.closed_sd_jwt, trusted_provider_public_key_pem: provider.public_to_pem,
      trusted_merchant_public_key_pem: merchant.public_to_pem, expected_checkout_jwt: checkout,
      expected_merchant_id: "shop", verified_at: NOW}}
  scope = {tenant_id: "tenant", merchant_id: "shop", operation_id: "operation", approval_id: "approval", occurrence_id: "one", order_id: "office-1"}
  receipt_context = {trusted_public_key_pem: merchant.public_to_pem, expected_issuer: "shop", expected_payment_id: "payment",
    not_before: NOW, not_after: NOW + 600}
  receipt = ->(wire, outcome, time = NOW) do
    fields = outcome == "Success" ? {psp_confirmation_id: "psp", network_confirmation_id: "network"} : {error: "declined", error_description: "Synthetic decline"}
    M::PaymentReceipt.sign(closed_sd_jwt: wire, issuer: "shop", outcome: outcome, payment_id: "payment", issued_at: time,
      signer: signer.call(merchant), public_key_pem: merchant.public_to_pem, **fields).jwt
  end
  Dir.mktmpdir("ap2-acceptance-") do |directory|
    assert(!Gem.loaded_specs.key?("sqlite3"), "normal SDK require does not load optional driver")
    path = File.join(directory, "ledger.sqlite3")
    unavailable { A::SQLiteStore.new(path: path) }
    assert(!File.exist?(path), "missing ledger never recreated")
    store = A::SQLiteStore.create(path: path)
    unavailable { A::SQLiteStore.create(path: path) }
    service = A::Service.new(store: store)
    accept = ->(context = scope, inputs = raw) { service.accept(**context, mode: :direct, verification_inputs: inputs) }
    assert(accept.call.status == :rejected, "random received occurrence cannot grant")
    authorization = scope.merge(mode: :direct, profile_ref: M::Payment::PROFILE_REF, checkout: state.fetch(:checkout), payment: details, receipt_context: receipt_context)
    assert(store.authorize!(**authorization), "trusted Host enrollment")
    assert(store.authorize!(**authorization), "exact enrollment idempotent")
    conflict { store.authorize!(**authorization.merge(operation_id: "remapped")) }
    conflict { store.authorize!(**authorization.merge(payment: details.merge("payment_instrument" => {"id" => "other", "type" => "card"}))) }
    first = accept.call
    assert(first.status == :reserved && first.ticket, "one new reservation")
    assert(!first.inspect.include?(payment.closed_sd_jwt) && !first.ticket.inspect.include?("fence"), "capability inspection redacted")
    replay = accept.call
    assert(replay.status == :pending && replay.ticket.nil? && replay.closed_sd_jwt == payment.closed_sd_jwt, "replay no new fence")
    changed = copy(raw); changed[:expected_payment]["payment_instrument"]["id"] = "other"
    assert(accept.call(scope, changed).status == :rejected, "raw verifier result cannot be bypassed")
    expired = copy(raw); expired[:verified_at] = NOW + 60; expired[:checkout_inputs][:verified_at] = NOW + 60
    assert(service.start(ticket: first.ticket, verification_inputs: expired).nil?, "Checkout expiry before Payment expiry rejects start")
    fresh_wrong = copy(raw); fresh_wrong[:checkout_inputs][:trusted_merchant_public_key_pem] = OpenSSL::PKey::EC.generate("prime256v1").public_to_pem
    assert(service.start(ticket: first.ticket, verification_inputs: fresh_wrong).nil?, "fresh current trust required")
    swap = M::Payment.issue_direct(payment: details, approved_payment: details, issued_at: NOW, expires_at: NOW + 120,
      signer: signer.call(provider), public_key_pem: provider.public_to_pem)
    swap_args = copy(raw).merge(closed_sd_jwt: swap.closed_sd_jwt)
    assert(M::Payment.verify(**swap_args).verified?, "fresh swapped proof is cryptographically valid")
    assert(service.start(ticket: first.ticket, verification_inputs: swap_args).nil?, "dispatch requires exact first signed proof despite equivalent re-sign")
    execution = service.start(ticket: first.ticket, verification_inputs: raw)
    assert(execution && execution.closed_sd_jwt == payment.closed_sd_jwt && execution.processor_key.bytesize == 64, "first start only")
    assert(service.start(ticket: first.ticket, verification_inputs: raw).nil?, "no duplicate start")
    assert(!execution.inspect.include?(execution.processor_key), "execution inspect redacted")
    assert(replay.processor_key == execution.processor_key && replay.signed_wires.frozen? && replay.signed_wires["payment"].frozen?, "read-only reconciliation key and first proof")
    assert(service.unknown(ticket: first.ticket).status == :unknown, "uncertain external attempt held")
    assert(accept.call.status == :unknown && accept.call.ticket.nil?, "unknown never reacquires")
    assert(service.start(ticket: first.ticket, verification_inputs: raw).nil?, "old fence cannot restart unknown")
    assert(service.reconcile(**scope, receipt_jwt: "bad", verified_at: NOW).status == :rejected, "invalid receipt cannot reconcile")
    success = receipt.call(payment.closed_sd_jwt, "Success", NOW + 121)
    assert(service.reconcile(**scope, receipt_jwt: success, verified_at: NOW + 121).status == :receipt_success, "delayed receipt after Mandate expiry reconciles")
    completed = service.lookup(**scope)
    assert(completed.ticket.nil? && completed.receipt_jwt == success && completed.closed_sd_jwt == payment.closed_sd_jwt, "lookup original receipt and wire")
    assert(service.reconcile(**scope, receipt_jwt: success, verified_at: NOW + 121).status == :receipt_success, "same final receipt idempotent")
    assert(service.finish(ticket: first.ticket, receipt_jwt: receipt.call(payment.closed_sd_jwt, "Error"), verified_at: NOW).status == :conflict, "conflicting authentic outcome cannot overwrite")
    # Freshly signed Payment can verify, but never gets a second reservation or
    # changes the first final wire to which receipts are bound.
    resigned = M::Payment.issue_direct(payment: details, approved_payment: details, issued_at: NOW,
      expires_at: NOW + 120, signer: signer.call(provider), public_key_pem: provider.public_to_pem)
    alternate = copy(raw); alternate[:closed_sd_jwt] = resigned.closed_sd_jwt
    replay = accept.call(scope, alternate)
    assert(replay.status == :receipt_success && replay.closed_sd_jwt == payment.closed_sd_jwt && replay.ticket.nil?, "re-sign retry pinned to first original")
    assert(service.reconcile(**scope, receipt_jwt: receipt.call(resigned.closed_sd_jwt, "Success"), verified_at: NOW).status == :rejected, "Receipt cannot rebind to retry wire")
    second_scope = scope.merge(operation_id: "operation-2", occurrence_id: "two")
    assert(accept.call(second_scope).status == :rejected, "new occurrence needs distinct Host grant")
    store.authorize!(**authorization.merge(second_scope))
    assert(accept.call(second_scope).status == :conflict, "exact final Closed cannot map to a second authorized occurrence")
    second = accept.call(second_scope, alternate)
    assert(second.status == :reserved, "fresh final Closed allowed for separately approved occurrence")
    store.revoke!(**second_scope)
    assert(service.start(ticket: second.ticket, verification_inputs: alternate).nil?, "revocation atomically blocks start")
    assert(accept.call(second_scope).status == :rejected, "revoked approval cannot reserve")
    other_path = File.join(directory, "other.sqlite3")
    other = A::SQLiteStore.create(path: other_path)
    assert(A::Service.new(store: other).start(ticket: first.ticket, verification_inputs: raw).nil?, "cross store ticket rejected")
    other.close
    store.close
    reopened = A::SQLiteStore.new(path: path)
    assert(A::Service.new(store: reopened).lookup(**scope).status == :receipt_success, "durable reopen preserves final state")
    reopened.close
    File.write(File.join(directory, "corrupt.sqlite3"), "invalid")
    unavailable { A::SQLiteStore.new(path: File.join(directory, "corrupt.sqlite3")) }
    # A structurally valid SQLite database with the wrong constraints is NOT a
    # compatible ledger. SQLite quick_check alone cannot prove this invariant.
    ["missing_unique", "extra_column", "trigger", "two_identities"].each do |kind|
      bad_path = File.join(directory, "#{kind}.sqlite3")
      bad_store = A::SQLiteStore.create(path: bad_path); bad_store.close
      db = SQLite3::Database.new(bad_path)
      case kind
      when "missing_unique"
        db.execute("DROP TABLE ap2_attempts"); db.execute("DROP TABLE ap2_approvals")
        db.execute(A::SQLiteStore::SCHEMA.fetch("ap2_approvals").sub(", UNIQUE(tenant,merchant,approval,occurrence)", ""))
        db.execute(A::SQLiteStore::SCHEMA.fetch("ap2_attempts"))
      when "extra_column" then db.execute("ALTER TABLE ap2_approvals ADD COLUMN extra TEXT")
      when "trigger" then db.execute("CREATE TRIGGER unexpected AFTER INSERT ON ap2_store BEGIN SELECT 1; END")
      when "two_identities" then db.execute("INSERT INTO ap2_store SELECT identity FROM ap2_store")
      end
      assert(db.get_first_value("PRAGMA quick_check") == "ok", "wrong schema remains valid SQLite")
      db.close
      unavailable { A::SQLiteStore.new(path: bad_path) }
    end
    # Every supported conditional/selective profile still goes through its
    # complete raw verification pipeline, not a supplied Verification object.
    host_raw = M::InputBuilder.inputs(**state.fetch(:host_inputs), saved_challenge: state.fetch(:saved), terminal_jws: state.fetch(:closed).terminal_jws,
      expected_challenge_issuer_id: "host", clock_source_id: "clock", verified_at: NOW)
    all_path = File.join(directory, "all-modes.sqlite3")
    all_store = A::SQLiteStore.create(path: all_path)
    all_service = A::Service.new(store: all_store)
    standing = nil
    [false, true].each do |policy|
      planned = policy ? details.merge("pisp" => {"legal_name" => "Provider", "brand_name" => "Brand", "domain_name" => "pisp.example"}, "execution_date" => "2028-01-01T00:00:00Z") : details
      base = [{"type" => "payment.amount_range", "currency" => "USD", "max" => 300},
        {"type" => "payment.allowed_payees", "allowed" => [details["payee"]]},
        {"type" => "payment.allowed_payment_instruments", "allowed" => [details["payment_instrument"]]}]
      base += [{"type" => "payment.allowed_pisps", "allowed" => [planned["pisp"]]},
        {"type" => "payment.execution_date", "not_before" => planned["execution_date"]}] if policy
      [:conditional, :selective, :direct].each do |mode|
        profile = if mode == :selective
          policy ? M::PaymentPolicy::SELECTIVE_PROFILE_REF : M::SelectivePayment::PROFILE_REF
        else
          policy ? M::PaymentPolicy::PROFILE_REF : M::Payment::PROFILE_REF
        end
        if mode == :direct
          closed = M::Payment.issue_direct(payment: planned, approved_payment: planned, issued_at: NOW, expires_at: NOW + 120,
            signer: signer.call(provider), public_key_pem: provider.public_to_pem, profile_ref: profile)
          args = copy(raw).merge(closed_sd_jwt: closed.closed_sd_jwt, expected_payment: planned, profile_ref: profile)
        else
          api = mode == :selective ? M::SelectivePayment : M::Payment
          issue = {open_checkout_sd_jwt: state.fetch(:opening).root_presentation, constraints: base, fixed: {},
            agent_public_key_pem: agent.public_to_pem, issued_at: NOW, expires_at: NOW + 120,
            signer: signer.call(provider), public_key_pem: provider.public_to_pem, profile_ref: profile}
          issue[:candidate_policy] = :independent if policy
          issue.merge!(approved_combinations: [[0,0]], selective: :both) if mode == :selective
          root = api.issue_open(**issue)
          root = api.select(open_sd_jwt: root, payee_index: 0, instrument_index: 0, profile_ref: profile) if mode == :selective
          open_key = mode == :selective ? :open_presentation : :open_sd_jwt
          closed = api.issue_closed(**{open_key => root}, payment: planned, trusted_provider_public_key_pem: provider.public_to_pem,
            agent_public_key_pem: agent.public_to_pem, audience: "merchant-host", nonce: "synthetic-one-use-nonce", verified_at: NOW,
            signer: signer.call(agent), profile_ref: profile)
          args = {open_key => root, closed_sd_jwt: closed.closed_sd_jwt, checkout_inputs: host_raw, expected_payment: planned,
            trusted_provider_public_key_pem: provider.public_to_pem, expected_agent_public_key_pem: agent.public_to_pem,
            expected_audience: "merchant-host", expected_nonce: "synthetic-one-use-nonce", verified_at: NOW, profile_ref: profile}
          args[:checkout_mode] = :conditional if mode == :conditional
        end
        args.merge!(trusted_pisp: planned["pisp"], execution_at: planned["execution_date"]) if policy
        standing = {root: root, first_closed: closed.closed_sd_jwt} if !policy && mode == :conditional
        model_scope = scope.merge(operation_id: "#{policy}-#{mode}", occurrence_id: "#{policy}-#{mode}")
        all_store.authorize!(**model_scope, mode: mode, profile_ref: profile, checkout: state.fetch(:checkout), payment: planned, receipt_context: receipt_context)
        wrong_tenant = model_scope.merge(tenant_id: "different")
        if mode != :direct
          all_store.authorize!(**wrong_tenant, mode: mode, profile_ref: profile, checkout: state.fetch(:checkout), payment: planned, receipt_context: receipt_context)
          assert(all_service.accept(**wrong_tenant, mode: mode, verification_inputs: args).status == :rejected, "conditional tenant must match genuine Host")
        end
        claimed = all_service.accept(**model_scope, mode: mode, verification_inputs: args)
        assert(claimed.status == :reserved, "#{policy}-#{mode} raw acceptance")
        if mode == :conditional && !policy
          expired_host = copy(args); expired_host[:verified_at] = NOW + 60; expired_host[:checkout_inputs][:verified_at] = NOW + 60
          assert(M.verify_checkout(**expired_host[:checkout_inputs]).code == :challenge_time_mismatch, "current challenge expires before Payment")
          assert(all_service.start(ticket: claimed.ticket, verification_inputs: expired_host).nil?, "fresh challenge expiry blocks execution")
          order_changed = copy(args)
          host_body = JSON.parse(order_changed[:checkout_inputs][:host_json]); host_body["binding"]["order_version"] = "2"
          order_changed[:checkout_inputs][:host_json] = JSON.generate(host_body)
          assert(all_service.start(ticket: claimed.ticket, verification_inputs: order_changed).nil?, "current order version mismatch blocks execution")
          revoked = copy(args)
          trust_body = JSON.parse(revoked[:checkout_inputs][:trust_json]); registry = JSON.parse(trust_body["snapshot"]["body"])
          registry["records"].find { |r| r["role"] == "Merchant" }["active"] = false
          trust_body["snapshot"]["body"] = JSON.generate(registry)
          new_hash = Digest::SHA256.hexdigest(trust_body["snapshot"]["body"])
          trust_body["snapshot"]["content_hash"] = new_hash
          selected = JSON.parse(revoked[:checkout_inputs][:selection_json]); selected["trust_content_hash"] = new_hash
          revoked[:checkout_inputs][:trust_json] = JSON.generate(trust_body); revoked[:checkout_inputs][:selection_json] = JSON.generate(selected)
          assert(M.verify_checkout(**revoked[:checkout_inputs]).code == :inactive_trust_key, "current registry revocation reaches exact key gate")
          assert(all_service.start(ticket: claimed.ticket, verification_inputs: revoked).nil?, "fresh trust revocation blocks execution")
        end
        assert(all_service.start(ticket: claimed.ticket, verification_inputs: args), "#{policy}-#{mode} fresh full start")
        receipt_profile = profile == M::SelectivePayment::PROFILE_REF ? M::Payment::PROFILE_REF : profile
        jwt = M::PaymentReceipt.sign(closed_sd_jwt: closed.closed_sd_jwt, profile_ref: receipt_profile, issuer: "shop", outcome: "Error", payment_id: "payment",
          issued_at: NOW, error: "declined", error_description: "Synthetic", signer: signer.call(merchant), public_key_pem: merchant.public_to_pem).jwt
        assert(all_service.finish(ticket: claimed.ticket, receipt_jwt: jwt, verified_at: NOW).status == :receipt_error, "#{policy}-#{mode} pinned Receipt")
      end
    end
    next_cart = copy(state.fetch(:checkout)); next_cart["id"] = "office-2"
    next_jwt = M::CheckoutJWT.sign(checkout: next_cart, signer: signer.call(merchant), public_key_pem: merchant.public_to_pem,
      profile_ref: M::ScopedConstraints::MULTI_PROFILE_REF).jwt
    next_checkout_closed = M::ConditionalCheckout.issue_closed(root_presentation: state.fetch(:opening).root_presentation, checkout_jwt: next_jwt,
      trusted_issuer_public_key_pem: provider.public_to_pem, agent_public_key_pem: agent.public_to_pem,
      trusted_merchant_public_key_pem: merchant.public_to_pem, expected_merchant_id: "shop", audience: "merchant-host", nonce: "next-nonce",
      verified_at: NOW, signer: signer.call(agent))
    next_host = state.fetch(:host_inputs).merge(host_checkout_jws: next_jwt, order: state.fetch(:host_inputs).fetch(:order).merge("order_id" => "office-2"))
    saved = M::InputBuilder.prepare(**next_host, challenge_id: "next-challenge", nonce: "next-nonce", issuer_id: "host", not_before: NOW, not_after: NOW + 60)
    next_raw_checkout = M::InputBuilder.inputs(**next_host, saved_challenge: saved, terminal_jws: next_checkout_closed.terminal_jws,
      expected_challenge_issuer_id: "host", clock_source_id: "clock", verified_at: NOW)
    next_details = M::Payment.details(checkout_jwt: next_jwt, trusted_merchant_public_key_pem: merchant.public_to_pem,
      expected_merchant_id: "shop", payment_instrument: details.fetch("payment_instrument"))
    next_payment = M::Payment.issue_closed(open_sd_jwt: standing.fetch(:root), payment: next_details,
      trusted_provider_public_key_pem: provider.public_to_pem, agent_public_key_pem: agent.public_to_pem,
      audience: "merchant-host", nonce: "next-nonce", verified_at: NOW, signer: signer.call(agent))
    next_args = {open_sd_jwt: standing.fetch(:root), closed_sd_jwt: next_payment.closed_sd_jwt, checkout_mode: :conditional,
      checkout_inputs: next_raw_checkout, expected_payment: next_details, trusted_provider_public_key_pem: provider.public_to_pem,
      expected_agent_public_key_pem: agent.public_to_pem, expected_audience: "merchant-host", expected_nonce: "next-nonce", verified_at: NOW}
    next_scope = scope.merge(operation_id: "standing-next", occurrence_id: "standing-next", order_id: "office-2")
    all_store.authorize!(**next_scope, mode: :conditional, profile_ref: M::Payment::PROFILE_REF, checkout: next_cart, payment: next_details, receipt_context: receipt_context)
    reused_open = all_service.accept(**next_scope, mode: :conditional, verification_inputs: next_args)
    assert(reused_open.status == :reserved && next_payment.open_sd_jwt == standing.fetch(:root) && next_payment.closed_sd_jwt != standing.fetch(:first_closed), "standing Open reusable through new authorized transaction and fresh Closed")
    assert(all_service.start(ticket: reused_open.ticket, verification_inputs: next_args), "new standing-Open transaction starts once")
    # A storage exception after a durable commit cannot leak a capability.
    uncertain_scope = scope.merge(operation_id: "uncertain", occurrence_id: "uncertain")
    uncertain_payment = M::Payment.issue_direct(payment: details, approved_payment: details, issued_at: NOW, expires_at: NOW + 120,
      signer: signer.call(provider), public_key_pem: provider.public_to_pem)
    uncertain_raw = copy(raw).merge(closed_sd_jwt: uncertain_payment.closed_sd_jwt)
    all_store.authorize!(**authorization.merge(uncertain_scope))
    proxy = Object.new
    proxy.define_singleton_method(:reserve!) do |**arguments|
      all_store.reserve!(**arguments)
      raise A::Unavailable
    end
    uncertain = A::Service.new(store: proxy).accept(**uncertain_scope, mode: :direct, verification_inputs: uncertain_raw)
    assert(uncertain.status == :unavailable && uncertain.ticket.nil?, "uncertain reservation commit returns no ticket")
    assert(all_service.accept(**uncertain_scope, mode: :direct, verification_inputs: uncertain_raw).status == :pending, "uncertain commit remains reserved without takeover")
    assert(all_service.accept(**uncertain_scope, mode: :direct, verification_inputs: M::Payment.verify(**raw)).status == :rejected, "self asserted Verification object rejected")
    assert(!all_store.inspect.include?(all_path) && !all_service.inspect.include?(all_path), "storage/service inspection redacted")
    assert(all_service.lookup(**scope.merge(secret: "SECRET")).status == :rejected, "unknown scope keys fixed failure")
    assert(all_service.accept(**scope, mode: :direct, verification_inputs: raw, SECRET: true).status == :rejected, "unknown public keywords fixed failure")
    unavailable { A::SQLiteStore.new(SECRET: "SECRET-PATH") }
    # Bounded corrupted rows fail closed without returning their payload.
    damaged_db = SQLite3::Database.new(all_path)
    damaged_db.execute("UPDATE ap2_attempts SET record=? WHERE operation_key=?", ["x" * 1_048_577, A.key(uncertain_scope.transform_keys(&:to_s))])
    damaged_db.close
    bad_row = all_service.lookup(**uncertain_scope)
    assert(bad_row.status == :unavailable && bad_row.ticket.nil?, "oversized persistent row unavailable")
    all_store.close
  end
  puts "payment acceptance: #{@count} assertions passed"
end
