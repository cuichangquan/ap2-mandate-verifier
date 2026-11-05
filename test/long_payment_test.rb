# frozen_string_literal: true
require_relative "runtime_dependencies"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__)) unless ENV["AP2_INSTALLED"] == "1"
require "ap2_mandate_verifier"
require_relative "../examples/long_payment"

module LongPaymentTest
  M = AP2MandateVerifier
  L = M::LongPayment
  E = LongPaymentExample
  @count = 0
  def self.assert(value,label)
    @count += 1
    raise "long payment: #{label}" unless value
  end
  def self.invalid
    yield
    raise "long profile unexpectedly accepted"
  rescue L::Invalid, M::ConditionalCheckout::Invalid, M::Payment::Invalid, M::PaymentReceipt::Invalid, M::CheckoutReceipt::Invalid => error
    assert(error.cause.nil? && !error.message.include?("SECRET"),"redacted invalid")
  end
  def self.copy(value) = Marshal.load(Marshal.dump(value))
  def self.payload(wire) = M::Payment.send(:jwt_payload!,wire.split("~",2).first,nil)
  def self.content(wire)
    outer=payload(wire);pointer=outer.fetch("delegate_payload").first
    return pointer unless pointer.key?("...")
    leaf=wire.split("~")[1..].find { |d| M::Payment.send(:digest,d)==pointer["..."] }
    M::Buyer.send(:decode_disclosure!,leaf,2)[1]
  end
  def self.terminal(value,key) = M::MerchantSignature.sign!(value,E.signer(key),key.public_to_pem,typ:"kb+sd-jwt")+"~"
  def self.resign_root(wire,key)
    parts=wire.split("~",-1);outer=payload(wire)
    i=parts.index { |d| M::Payment.send(:digest,d)==outer["delegate_payload"][0]["..."] }
    d=M::Buyer.send(:decode_disclosure!,parts[i],2)
    yield(d[1],outer)
    parts[i]=M::Buyer.send(:encode,d);outer["delegate_payload"][0]["..."]=M::Payment.send(:digest,parts[i])
    parts[0]=M::MerchantSignature.sign!(outer,E.signer(key),key.public_to_pem,typ:"example+sd-jwt")
    parts.join("~")
  end
  def self.pair(fixture,month)
    inputs=month.fetch(:verify_inputs).fetch(:checkout_inputs)
    L.approved_pair!(payment_open:fixture.payment_open,checkout_open:fixture.checkout_open,trust_json:inputs[:trust_json],selection_json:inputs[:selection_json],
      merchant_id:"shop",verified_at:month[:now])
  end
  fixture=E::Fixture.new(amount:8000,budget:100000)
  months=E::PERIODS.keys.map { |period| fixture.month(period) }
  assert(E::EXP-E::T0==366*86400,"leap-year content interval")
  bindings=[]
  months.each do |month|
    args=month[:verify_inputs]
    assert(L.verify(**args).verified?,"all12 current-month wire verification")
    assert(args[:open_sd_jwt]==fixture.payment_open && args[:checkout_inputs][:root_presentation]==fixture.checkout_open,"exact shared Open pair")
    [month[:checkout_closed],month[:payment_closed]].each do |wire|
      assert(content(wire).values_at("iat","exp")==[E::T0,E::EXP],"shared content time unchanged")
      assert(payload(wire)["iat"]==month[:now],"outer KB time fresh separately")
    end
    authority=L.authority!(checkout_inputs:args[:checkout_inputs],provider_key:fixture.provider.public_to_pem,agent_key:fixture.agent.public_to_pem,
      merchant_id:"shop",verified_at:month[:now])
    bindings<<authority[:authority_binding]
    assert(authority[:root_key_fingerprints]["issuer"]==Digest::SHA256.hexdigest(fixture.provider.public_to_pem),"current issuer fingerprint")
    assert(authority[:tenant_id]=="long-tenant" && authority[:authority_principals]["Agent"]["identity"]=="agent","authenticated tenant/principals")
    month[:receipts].each do |receipt|
      common={jwt:receipt[:jwt],trusted_public_key_pem:receipt[:key],expected_issuer:"processor",not_before:month[:now]-1,not_after:month[:now]+120,verified_at:month[:now]}
      result=if receipt[:kind]=="checkout"
        M::CheckoutReceipt.verify(**common,closed_sd_jwt:month[:checkout_closed],profile_ref:L::CHECKOUT_PROFILE_REF)
      else
        M::PaymentReceipt.verify(**common,closed_sd_jwt:month[:payment_closed],profile_ref:L::PROFILE_REF,expected_payment_id:"payment-#{month[:period]}")
      end
      assert(result.verified?,"both original-wire receipts")
    end
  end
  assert(bindings.uniq.size==1,"whole-agreement authority stable across current month clocks")
  january,february=months.first(2)
  initial=pair(fixture,january)
  assert(initial[:opening].frozen? && initial[:checkout_opening].frozen? && initial[:authority_principals].frozen?,"immutable approved pair")
  assert(initial.values_at(:not_before,:not_after,:max_occurrences,:budget_max,:currency)==[E::T0,E::EXP,12,100000,"JPY"],"pair bounds and finite limits")
  assert(initial[:reference]==M::Payment.send(:digest,fixture.payment_open.split("~",2).first) && initial[:checkout_reference]==M::Payment.send(:digest,fixture.checkout_open),"separate JWS series identity and exact Checkout reference")
  renewed=E::Fixture.new(amount:8000,budget:100000,provider:fixture.provider,agent:fixture.agent,merchant:fixture.merchant,issued_at:february[:now]-60)
  renewed_pair=pair(renewed,renewed.month("2028-02"))
  assert(renewed_pair[:economic_contract]==initial[:economic_contract] && renewed_pair[:reference]!=initial[:reference],"time/root renewal preserves complete economics")
  changed=E::Fixture.new(amount:8000,budget:100001,provider:fixture.provider,agent:fixture.agent,merchant:fixture.merchant)
  assert(pair(changed,changed.month("2028-01"))[:economic_contract]!=initial[:economic_contract],"changed budget changes economics")
  requirements=copy(E::REQUIREMENTS);requirements[0]["acceptable_items"]<<{"id"=>"another","title"=>"Another product"}
  widened=E::Fixture.new(amount:8000,budget:100000,provider:fixture.provider,agent:fixture.agent,merchant:fixture.merchant,requirements:requirements)
  assert(pair(widened,widened.month("2028-01"))[:economic_contract]!=initial[:economic_contract],"hidden full Checkout candidate economics cannot disappear in rotation")
  new_merchant=OpenSSL::PKey::EC.generate("prime256v1")
  merchant_month=fixture.month("2028-02",merchant:new_merchant,authority:{snapshot_id:"merchant-rotation",policy_version:"2"})
  merchant_pair=pair(fixture,merchant_month)
  assert(merchant_pair[:economic_contract]==initial[:economic_contract] && merchant_pair[:root_key_fingerprints]==initial[:root_key_fingerprints] &&
    merchant_pair[:authority_binding]!=initial[:authority_binding],"Merchant authority changes without issuer/Agent root-key changes")
  # A valid current Checkout plus a separately genuine Payment signed by a
  # retired Issuer or Agent must not bypass the current-authority comparison.
  [:issuer,:agent].each do |role|
    replacement=OpenSSL::PKey::EC.generate("prime256v1")
    current=E::Fixture.new(amount:8000,budget:100000,provider:role==:issuer ? replacement : fixture.provider,
      agent:role==:agent ? replacement : fixture.agent,merchant:fixture.merchant)
    month=current.month("2028-02")
    cs=content(current.payment_open)["constraints"].reject { |c| c["type"]=="payment.reference" }
    retired_open=L.issue_open(open_checkout_sd_jwt:current.checkout_open,constraints:cs,fixed:{},candidate_policy: :independent,
      agent_public_key_pem:fixture.agent.public_to_pem,issued_at:E::T0,expires_at:E::EXP,signer:E.signer(fixture.provider),public_key_pem:fixture.provider.public_to_pem)
    retired_closed=L.issue_closed(open_sd_jwt:retired_open,payment:month[:expected_payment],trusted_provider_public_key_pem:fixture.provider.public_to_pem,
      agent_public_key_pem:fixture.agent.public_to_pem,audience:"payment-host",nonce:"payment-nonce-2028-02-8000",verified_at:month[:now],signer:E.signer(fixture.agent))
    args=copy(month[:verify_inputs]).merge(open_sd_jwt:retired_open,closed_sd_jwt:retired_closed.closed_sd_jwt,
      trusted_provider_public_key_pem:fixture.provider.public_to_pem,expected_agent_public_key_pem:fixture.agent.public_to_pem)
    assert(M.verify_checkout(**args[:checkout_inputs]).success?,"current Checkout is fully genuine during retired key control")
    assert(M::RootSignature.verified_payload!(retired_open.split("~",2).first,fixture.provider.public_to_pem)["ap2_profile"]==L::PROFILE_REF,"retired-key Payment root signature itself is genuine")
    assert(!L.verify(**args).verified? && !M::Payment.verify(**args).verified?,"retired Issuer/Agent cannot bypass wrapper through Payment API")
  end
  # Signed content-time changes are rejected while the current Checkout stays
  # valid; proof-age is independent from the long content interval.
  [->(v){v["delegate_payload"][0]["iat"]+=1},->(v){v["delegate_payload"][0]["exp"]-=1},
   ->(v){v["iat"]=E::T0},->(v){v["iat"]=february[:now]+1}].each do |change|
    claims=payload(february[:payment_closed]);change.call(claims)
    args=copy(february[:verify_inputs]).merge(closed_sd_jwt:terminal(claims,fixture.agent))
    assert(M.verify_checkout(**args[:checkout_inputs]).success? && !L.verify(**args).verified?,"signed shared-time/stale/future negative")
  end
  [300,301].each do |age|
    claims=payload(february[:payment_closed]);claims["iat"]=february[:now]-age
    assert(L.verify(**copy(february[:verify_inputs]).merge(closed_sd_jwt:terminal(claims,fixture.agent))).verified? == (age==300),"strict300second proof boundary")
  end
  [->(o,_){o["constraints"].reject!{|c|c["type"]=="payment.budget"}},
   ->(o,_){o["constraints"].find{|c|c["type"]=="payment.agent_recurrence"}["frequency"]="ON_DEMAND"},
   ->(o,_){o["constraints"].find{|c|c["type"]=="payment.budget"}["max"]=100000.0},
   ->(o,_){o["constraints"][0]["currency"]="USD"},
   ->(o,_){o["constraints"].find{|c|c["type"]=="payment.budget"}["_sd"]=["A"*43]},
   ->(_,p){p["ap2_profile"]=M::Payment::PROFILE_REF}].each do |change|
    altered=resign_root(fixture.payment_open,fixture.provider,&change)
    invalid { L.approved_open!(open_sd_jwt:altered,trusted_provider_public_key_pem:fixture.provider.public_to_pem,
      expected_agent_public_key_pem:fixture.agent.public_to_pem,verified_at:january[:now]) }
  end
  assert(!M::Payment.verify(**january[:verify_inputs].merge(profile_ref:M::Payment::PROFILE_REF)).verified?,"old Payment default rejects long marker")
  assert(!M::RecurringPayment.verify(**january[:verify_inputs].merge(profile_ref:M::RecurringPayment::PROFILE_REF)).verified?,"old ON_DEMAND profile does not acquire long time semantics")
  begin
    M::RootDisclosures.verified_root!(fixture.checkout_open,fixture.provider.public_to_pem,profile_ref:M::ScopedConstraints::MULTI_PROFILE_REF)
    raise "old Checkout admitted long root"
  rescue M::RootSignature::Rejected
    assert(true,"old Checkout marker grammar unchanged")
  end
  # Full semantic authority principals are returned separately from keys, so a
  # protected store can reject an identity takeover despite equal economics.
  inputs=january[:verify_inputs][:checkout_inputs]
  trust=JSON.parse(inputs[:trust_json]);snapshot=JSON.parse(trust["snapshot"]["body"])
  snapshot["records"].find{|r|r["role"]=="Issuer"}["identity"]="another-principal"
  trust["snapshot"]["body"]=JSON.generate(snapshot);trust["snapshot"]["content_hash"]=Digest::SHA256.hexdigest(trust["snapshot"]["body"])
  selection=JSON.parse(inputs[:selection_json]);selection["Issuer"]["identity"]="another-principal";selection["trust_content_hash"]=trust["snapshot"]["content_hash"]
  principal_pair=L.approved_pair!(payment_open:fixture.payment_open,checkout_open:fixture.checkout_open,trust_json:JSON.generate(trust),selection_json:JSON.generate(selection),
    merchant_id:"shop",verified_at:january[:now])
  assert(principal_pair[:economic_contract]==initial[:economic_contract] && principal_pair[:authority_principals]!=initial[:authority_principals],"identity takeover remains visible despite equal economics")
  calls=0;effect=->(_){calls+=1;raise "unexpected signer"}
  checkout_issue={merchant:E::SELLER,requirements:E::REQUIREMENTS,agent_public_key_pem:fixture.agent.public_to_pem,issued_at:E::T0,
    signer:effect,public_key_pem:fixture.provider.public_to_pem}
  invalid { L.issue_checkout_open(**checkout_issue,expires_at:E::T0+L::MAX_CONTENT_LIFETIME+1) }
  invalid { M::ConditionalCheckout.issue_open(**checkout_issue,expires_at:E::T0+7201) }
  legacy_checkout=M::ConditionalCheckout.issue_open(**checkout_issue.merge(signer:E.signer(fixture.provider)),expires_at:E::T0+7200)
  legacy_constraints=content(fixture.payment_open)["constraints"].reject{|c| %w[payment.agent_recurrence payment.budget payment.reference].include?(c["type"])}
  legacy_issue={open_checkout_sd_jwt:legacy_checkout.root_presentation,constraints:legacy_constraints,fixed:{},agent_public_key_pem:fixture.agent.public_to_pem,
    issued_at:E::T0,signer:effect,public_key_pem:fixture.provider.public_to_pem}
  invalid { M::Payment.issue_open(**legacy_issue,expires_at:E::T0+601) }
  assert(M::Payment.issue_open(**legacy_issue.merge(signer:E.signer(fixture.provider)),expires_at:E::T0+600).frozen?,"legacy600second positive control remains usable")
  invalid { M::Payment.issue_direct(payment:january[:expected_payment],approved_payment:january[:expected_payment],issued_at:E::T0,expires_at:E::T0+60,
    signer:effect,public_key_pem:fixture.provider.public_to_pem,profile_ref:L::PROFILE_REF) }
  assert(calls==0,"unsupported lifetime/direct profile rejected before signer")
  assert(M::Payment::MAX_LIFETIME==600,"legacy lifetime constant unchanged")
  # All trusted context/key bytes and the clock are detached before key parsing.
  live=copy(january[:verify_inputs][:checkout_inputs]);live_provider=fixture.provider.public_to_pem.dup;live_agent=fixture.agent.public_to_pem.dup
  live_merchant="shop".dup
  original=M::RootSignature.method(:public_jwk!)
  M::RootSignature.define_singleton_method(:public_jwk!) do |pem|
    live[:trust_json].replace("SECRET");live[:selection_json].replace("SECRET");live[:verified_at]=0
    live_provider.replace(new_merchant.public_to_pem);live_agent.replace(new_merchant.public_to_pem);live_merchant.replace("SECRET")
    original.call(pem)
  end
  begin
    stable=L.authority!(checkout_inputs:live,provider_key:live_provider,agent_key:live_agent,merchant_id:live_merchant,verified_at:january[:now])
    assert(stable[:authority_binding]==initial[:authority_binding],"authority helper consumes only detached original context")
  ensure
    M::RootSignature.define_singleton_method(:public_jwk!,original)
  end
  callback=false; hostile=copy(january[:verify_inputs][:checkout_inputs])
  hostile.define_singleton_method(:[]) { |_| callback=true; raise "unexpected caller callback" }
  invalid { L.authority!(checkout_inputs:hostile,provider_key:fixture.provider.public_to_pem,agent_key:fixture.agent.public_to_pem,merchant_id:"shop",verified_at:january[:now]) }
  assert(!callback,"context snapshot never invokes hostile singleton accessors")
  invalid { L.current_authority!(SECRET: "SECRET") }
  puts "long payment: #{@count} assertions passed"
end
