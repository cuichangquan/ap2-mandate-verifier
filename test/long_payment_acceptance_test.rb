# frozen_string_literal: true
require_relative "runtime_dependencies"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__)) unless ENV["AP2_INSTALLED"] == "1"
require "ap2_mandate_verifier"
require_relative "../examples/long_payment_acceptance"

module LongPaymentAcceptanceTest
  E = LongPaymentAcceptanceExample
  W = LongPaymentExample
  M = AP2MandateVerifier
  A = M::PaymentAcceptance
  L = M::LongPayment
  @checks = 0
  def self.assert(value, label)
    @checks += 1
    raise "long acceptance: #{label}" unless value
  end
  def self.raises(type)
    yield
    raise "expected fixed failure"
  rescue type => error
    assert(error.cause.nil? && !error.message.include?("eyJ"), "fixed failure/no signed data")
  end
  def self.usage(store, f) = store.usage(**f.fetch(:series_scope))
  def self.enroll(store, f, period, **opts)
    item = E.occurrence(f, period: period, **opts)
    store.authorize!(**item.fetch(:authorization))
    item
  end
  def self.accept(service, item) = service.accept(**item.fetch(:scope), mode: :conditional, verification_inputs: item.fetch(:raw))
  def self.reserve(store, f, period, **opts)
    item = enroll(store, f, period, **opts)
    [item, accept(A::Service.new(store: store), item)]
  end
  Dir.mktmpdir do |dir|
    f = E.build(max_occurrences: 3, budget_max: 100000)
    path = File.join(dir, "long.sqlite3")
    store = A::LongSQLiteStore.create(path: path)
    assert(E.enroll_series(store, f), "pair enrollment")
    assert(E.enroll_series(store, f) && usage(store,f)[:epoch] == 1, "idempotent enrollment no generation reset")
    assert(E.refresh_authority(store,f,"2028-01") == 1, "identical protected authority refresh idempotent")
    service = A::Service.new(store: store)
    jan, first = reserve(store,f,"2028-01")
    assert(first.ticket && first.status == :reserved, "first reserve")
    retry_item = E.occurrence(f,period:"2028-01")
    assert(retry_item[:raw][:closed_sd_jwt] != jan[:raw][:closed_sd_jwt], "fresh re-signing")
    replay = accept(service,retry_item)
    assert(replay.status == :pending && replay.ticket.nil? && replay.closed_sd_jwt == first.closed_sd_jwt, "re-sign retry retains original and charges once")
    raises(A::Conflict) { store.authorize!(**retry_item[:authorization].merge(operation_id:"random-client-id")) }
    execution = service.start(ticket:first.ticket,verification_inputs:jan[:raw])
    assert(execution && service.start(ticket:first.ticket,verification_inputs:jan[:raw]).nil?, "one fenced start")
    assert(execution.valid_until <= W.now("2028-01")+120 && execution.valid_until < W::EXP,"execution deadline exposed and short despite long content")
    assert(service.unknown(ticket:first.ticket).status == :unknown, "unknown retained")
    feb, second = reserve(store,f,"2028-02")
    assert(second.ticket && usage(store,f).values_at(:reserved_occurrences,:reserved_amount) == [2,80000], "next period under same roots")
    mar, third = reserve(store,f,"2028-03")
    assert(L.verify(**mar[:raw]).verified? && usage(store,f)[:reserved_occurrences] < 3, "overbudget wire/period valid and count available")
    assert(third.status == :rejected && !third.ticket && usage(store,f)[:reserved_amount] == 80000, "budget-only rejection unchanged")
    assert(service.reconcile(**jan[:scope],receipt_jwt:jan[:error_receipt],verified_at:W.now("2028-02")).status == :receipt_error, "late Error original reference")
    assert(usage(store,f)[:reserved_amount] == 80000 && accept(service,mar).status == :rejected, "Error never refunds budget")

    # Invalidate between raw verification and start. Epoch state is authoritative
    # even when the caller still holds a previously valid registry snapshot.
    assert(store.invalidate_authority!(**f[:series_scope],expected_epoch:1) == 2, "authority generation invalidation")
    assert(!usage(store,f)[:authority_active], "authority suspended")
    assert(L.verify(**feb[:raw]).verified? && service.start(ticket:second.ticket,verification_inputs:feb[:raw]).nil?, "valid old wire cannot bypass protected current epoch")
    assert(accept(service,feb).status == :rejected, "suspended authority rejects new acceptance")
    raises(A::Conflict) { store.invalidate_authority!(**f[:series_scope],expected_epoch:1) }
    raises(A::Invalid) { store.invalidate_authority!(**f[:series_scope],expected_epoch:nil) }
    assert(E.refresh_authority(store,f,"2028-02") == 3, "protected refresh resumes only current root authority")
    assert(service.start(ticket:second.ticket,verification_inputs:feb[:raw]).nil?, "old generation Ticket never revives")
    assert(usage(store,f)[:reserved_amount] == 80000, "generation changes retain allowance")
    store.close
    raises(A::Unavailable) { A::SQLiteStore.new(path:path) }
    raises(A::Unavailable) { A::RecurringSQLiteStore.new(path:path) }
    store = A::LongSQLiteStore.new(path:path)
    assert(usage(store,f).values_at(:epoch,:reserved_occurrences,:reserved_amount) == [3,2,80000], "restart retains authority and quota")
    store.close

    # Independent inclusive budget and count controls.
    boundary = A::LongSQLiteStore.create(path:File.join(dir,"boundary")); E.enroll_series(boundary,f)
    ["2028-01","2028-02"].each { |period| assert(reserve(boundary,f,period)[1].ticket,"boundary prefix") }
    assert(reserve(boundary,f,"2028-03",amount:20000)[1].ticket && usage(boundary,f)[:reserved_amount] == 100000,"inclusive100000 cap")
    boundary.close
    count_f = E.build(max_occurrences:2,budget_max:200000)
    count_store = A::LongSQLiteStore.create(path:File.join(dir,"count")); E.enroll_series(count_store,count_f)
    %w[2028-01 2028-02].each { |period| assert(reserve(count_store,count_f,period)[1].ticket,"count prefix") }
    assert(reserve(count_store,count_f,"2028-03")[1].status == :rejected && usage(count_store,count_f)[:reserved_amount]+40000 <= 200000,"count-only rejection")
    count_store.close

    # Fresh Host authority can shorten a challenge without changing any signed
    # Checkout/Payment bytes. Both the handle and persisted deadline must shrink.
    narrow = A::LongSQLiteStore.create(path:File.join(dir,"narrow")); E.enroll_series(narrow,f)
    narrow_item, narrow_result = reserve(narrow,f,"2028-01")
    fresh_raw = Marshal.load(Marshal.dump(narrow_item[:raw]))
    host = JSON.parse(fresh_raw[:checkout_inputs][:host_json])
    host["challenge"]["not_after"] = W.now("2028-01")+10
    fresh_raw[:checkout_inputs][:host_json] = JSON.generate(host)
    assert(L.verify(**fresh_raw).verified?,"narrowed challenge positive current-time control")
    assert(fresh_raw[:closed_sd_jwt] == narrow_item[:raw][:closed_sd_jwt] && fresh_raw[:checkout_inputs][:terminal_jws] == narrow_item[:raw][:checkout_inputs][:terminal_jws],"all signed wires unchanged in narrowed control")
    narrow_execution = A::Service.new(store:narrow).start(ticket:narrow_result.ticket,verification_inputs:fresh_raw)
    assert(narrow_execution && narrow_execution.valid_until == W.now("2028-01")+10,"fresh deadline intersects returned capability")
    db = SQLite3::Database.new(File.join(dir,"narrow")); stored_deadline = JSON.parse(db.get_first_value("SELECT record FROM ap2_attempts"))["valid_until"];db.close
    assert(stored_deadline == W.now("2028-01")+10,"fresh deadline persisted atomically with processing CAS")
    narrow.close

    # First-attempt wrong period cannot hide behind duplicate tombstones.
    wrong = A::LongSQLiteStore.create(path:File.join(dir,"wrong")); E.enroll_series(wrong,f)
    item = E.occurrence(f,period:"2028-01")
    item[:scope] = item[:scope].merge(occurrence_id:"2028-02")
    item[:authorization] = item[:authorization].merge(occurrence_id:"2028-02")
    wrong.authorize!(**item[:authorization])
    assert(L.verify(**item[:raw]).verified?,"wrong-label raw wire control")
    assert(accept(A::Service.new(store:wrong),item).status == :rejected && usage(wrong,f)[:reserved_occurrences] == 0,"trusted time selects period, not received ID")
    wrong.close

    rotation = A::LongSQLiteStore.create(path:File.join(dir,"rotation")); E.enroll_series(rotation,f)
    original, original_result = reserve(rotation,f,"2028-01")
    rotate_service = A::Service.new(store:rotation)
    assert(rotate_service.start(ticket:original_result.ticket,verification_inputs:original[:raw]),"pre-rotation first start")
    rotate_service.unknown(ticket:original_result.ticket)
    provider, agent = Array.new(2) { OpenSSL::PKey::EC.generate("prime256v1") }
    replacement = f.merge(wire:f[:wire].rotate(provider:provider,agent:agent,issued_at:W::PERIODS.fetch("2028-02")[0],
      authority:{snapshot_id:"long-registry-2",policy_version:"long-authority-2"}))
    new_item = E.occurrence(replacement,period:"2028-02")
    rotation.authorize!(**new_item[:authorization])
    assert(L.verify(**new_item[:raw]).verified? && accept(rotate_service,new_item).status == :rejected,"new signed root requires protected alias authorization")
    old_root = usage(rotation,f)[:root_reference]
    # Valid new signatures must not authorize altered approved economics/window.
    changed_candidates = W::REQUIREMENTS.map { |row| row.merge("acceptable_items" => row.fetch("acceptable_items") + [{"id"=>"extra", "title"=>"Unapproved extra"}]) }
    [f.merge(wire: W::Fixture.new(provider:f[:wire].provider,agent:f[:wire].agent,merchant:f[:wire].merchant,
        max_occurrences:3,budget:100000,requirements:changed_candidates)),
     f.merge(wire: W::Fixture.new(provider:f[:wire].provider,agent:f[:wire].agent,merchant:f[:wire].merchant,
        max_occurrences:3,budget:200000)),
     f.merge(wire: W::Fixture.new(provider:f[:wire].provider,agent:f[:wire].agent,merchant:f[:wire].merchant,
        max_occurrences:3,budget:100000,expires_at:W::EXP+86400))].each do |modified|
      assert(L.verify(**E.occurrence(modified,period:"2028-02")[:raw]).verified?,"modified signed pair raw control")
      raises(A::Conflict) { E.replace_root(rotation,f,modified,"2028-02") }
      assert(usage(rotation,f)[:root_reference] == old_root && usage(rotation,f)[:reserved_amount] == 40000,"failed change keeps original consent and usage")
    end
    # A currently trusted different Issuer identity with the same key is still
    # a different authority principal, even when all signed economics match.
    principal_fixture = f.merge(wire: W::Fixture.new(provider:f[:wire].provider,agent:f[:wire].agent,merchant:f[:wire].merchant,max_occurrences:3,budget:100000))
    principal_args = E.pair_arguments(principal_fixture,"2028-02")
    selection = JSON.parse(principal_args[:selection_json])
    snapshot = JSON.parse(JSON.parse(principal_args[:trust_json]).fetch("snapshot").fetch("body"))
    snapshot["records"].each { |row| row.select! { |key,_| M::InputBuilder::RECORD_FIELDS.include?(key) }; row["identity"]="successor-issuer" if row["role"]=="Issuer" }
    selection["Issuer"]["identity"]="successor-issuer"
    trust = M::InputBuilder.trust(snapshot:snapshot,tenant_id:"long-tenant",issuer:selection["Issuer"],agent:selection["Agent"],merchant:selection["Merchant"],
      verified_at:W.now("2028-02"),profile_ref:L::CHECKOUT_PROFILE_REF)
    principal_args = principal_args.merge(trust_json:trust.trust_json,selection_json:trust.selection_json)
    assert(L.approved_pair!(**principal_args,merchant_id:"shop")[:economic_contract] == L.approved_pair!(**E.pair_arguments(f,"2028-02"),merchant_id:"shop")[:economic_contract],"principal-change economics control")
    raises(A::Conflict) { rotation.replace_root!(**f[:series_scope],expected_epoch:1,expected_root_reference:old_root,**principal_args) }
    assert(E.replace_root(rotation,f,replacement,"2028-02") == 2,"Issuer and Agent rotate with CAS")
    assert(usage(rotation,f).values_at(:reserved_occurrences,:reserved_amount) == [1,40000] && usage(rotation,f)[:root_reference] != old_root,"rotation preserves history and changes active root")
    assert(accept(rotate_service,original).status == :rejected,"old root/registry cannot reauthorize")
    renewed = accept(rotate_service,new_item)
    assert(renewed.ticket && rotate_service.start(ticket:renewed.ticket,verification_inputs:new_item[:raw]),"new keys current root accepted")
    rotate_service.unknown(ticket:renewed.ticket)
    assert(usage(rotation,f).values_at(:reserved_occurrences,:reserved_amount) == [2,80000],"new root cannot reset budget")
    assert(rotate_service.reconcile(**original[:scope],receipt_jwt:original[:payment_receipt],verified_at:W.now("2028-02")).status == :receipt_success,"old original Receipt reconciliation after rotation")
    raises(A::Conflict) { E.replace_root(rotation,f,replacement,"2028-02") }
    assert(rotation.revoke_root!(**f[:series_scope],expected_epoch:2) == 3,"root revocation advances epoch")
    assert(accept(rotate_service,new_item).status == :rejected,"revoked root cannot receive Ticket")
    raises(A::Conflict) do
      rotation.authorize_series!(**f[:series_scope].merge(approval_id:"client-reset-id"),**E.pair_arguments(replacement,"2028-02"),
        periods:E.periods.drop(1),schedule_policy_id:A::LongSQLiteStore::SCHEDULE_POLICY)
    end
    rotation.revoke_series!(**f[:series_scope])
    assert(!usage(rotation,f)[:active] && usage(rotation,f)[:reserved_amount] == 80000,"permanent agreement revoke retains allowance")
    raises(A::Invalid) do
      next_fixture = replacement.merge(wire:replacement[:wire].rotate(provider:OpenSSL::PKey::EC.generate("prime256v1"),agent:OpenSSL::PKey::EC.generate("prime256v1"),
        issued_at:W::PERIODS.fetch("2028-03")[0],authority:{snapshot_id:"long-registry-3",policy_version:"long-authority-3"}))
      E.replace_root(rotation,f,next_fixture,"2028-03")
    end
    rotation.close

    # Malformed schedules are rejected before creating a series or allowance.
    schedule_store = A::LongSQLiteStore.create(path:File.join(dir,"schedule"))
    periods = E.periods
    bad_schedules = [periods.take(2).map { |v| v.merge(id:"duplicate") },
      [{id:"a",not_before:W::T0,not_after:W::T0+86400},{id:"b",not_before:W::T0+86400,not_after:W::T0+172800}],
      [{id:"span",not_before:W::T0,not_after:W::PERIODS["2028-03"][0]}],
      [{id:"past",not_before:W::T0-1,not_after:W::T0+1}],
      [{id:"empty",not_before:W::T0,not_after:W::T0}]]
    bad_schedules.each do |windows|
      raises(A::Invalid) { schedule_store.authorize_series!(**f[:series_scope],**E.pair_arguments(f,"2028-01"),periods:windows,schedule_policy_id:A::LongSQLiteStore::SCHEDULE_POLICY) }
    end
    raises(A::Invalid) { schedule_store.authorize_series!(**f[:series_scope],**E.pair_arguments(f,"2028-01"),periods:periods,schedule_policy_id:"unregistered") }
    assert(E.enroll_series(schedule_store,f) && usage(schedule_store,f)[:reserved_occurrences] == 0,"bad schedule never partially enrolls or charges")
    schedule_store.close

    # No schema1/schema2 route may accept a long profile without its authority ledger.
    [A::SQLiteStore,A::RecurringSQLiteStore].each_with_index do |klass,index|
      old = klass.create(path:File.join(dir,"old#{index}"))
      raises(A::Invalid) { old.authorize!(**original[:authorization]) }
      assert(accept(A::Service.new(store:old),original).status == :rejected,"old adapter fails closed for long profile")
      old.close
    end
  end
  puts "long payment acceptance: #{@checks} assertions passed"
end
