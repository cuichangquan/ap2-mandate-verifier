# frozen_string_literal: true
# Installed SDK only. Synthetic wire fixtures; no storage or payment execution.
require "ap2_mandate_verifier"
require "openssl"

module LongPaymentExample
  M = AP2MandateVerifier
  L = M::LongPayment
  T0 = Time.utc(2028, 1, 1).to_i
  EXP = Time.utc(2029, 1, 1).to_i
  PERIODS = (1..12).to_h do |month|
    finish = month == 12 ? Time.utc(2029,1,1).to_i : Time.utc(2028,month+1,1).to_i
    [format("2028-%02d",month), [Time.utc(2028,month,1).to_i,finish].freeze]
  end.freeze
  SELLER = {"id" => "shop", "name" => "Synthetic Long Shop"}.freeze
  REQUIREMENTS = [{"id" => "monthly", "quantity" => 1,
    "acceptable_items" => [{"id" => "long-item", "title" => "Monthly supplies"}]}].freeze
  def self.now(period) = PERIODS.fetch(period)[0] + 3600
  def self.signer(key) = M::CheckoutJWT.es256_signer(private_key: key)
  def self.totals(n) = %w[subtotal total].map { |kind| {"type" => kind, "amount" => n} }
  def self.cart(period, amount = 40000)
    raise "unknown synthetic period/amount" unless PERIODS.key?(period) && amount.instance_of?(Integer) && amount.between?(1,100000)
    {"id" => "long-#{period}-#{amount}", "merchant" => SELLER, "status" => "ready_for_complete", "currency" => "JPY", "links" => [],
      "line_items" => [{"id" => "row-1", "quantity" => 1, "item" => {"id" => "long-item", "title" => "Monthly supplies", "price" => amount}, "totals" => totals(amount)}], "totals" => totals(amount)}
  end
  def self.inputs(period:, checkout_open:, payment_open:, checkout_jwt:, checkout_closed:, payment_closed:,
                  provider:, agent:, merchant:, amount: 40000, authority: {})
    at = now(period)
    raise "unknown synthetic authority option" unless (authority.keys - %i[snapshot_id policy_version not_before not_after issuer agent merchant]).empty?
    start = authority.fetch(:not_before,T0-1); finish = authority.fetch(:not_after,EXP)
    keys = [authority.fetch(:issuer,provider),authority.fetch(:agent,agent),authority.fetch(:merchant,merchant)]
    records = %w[Issuer Agent Merchant].zip(keys).map do |role,key|
      {"role" => role,"identity" => role == "Merchant" ? "shop" : role.downcase,"tenant_id" => "long-tenant","purpose" => "checkout",
        "key_ref" => role.downcase,"public_key_pem" => key,"active" => true,"not_before" => start,"not_after" => finish}
    end
    selectors = records.to_h { |r| [r["role"].downcase.to_sym,r.slice("identity","purpose","key_ref")] }
    trust = M::InputBuilder.trust(snapshot: {"id" => authority.fetch(:snapshot_id,"long-registry-1"),"policy_version" => authority.fetch(:policy_version,"long-authority-1"),
      "active" => true,"not_before" => start,"not_after" => finish,"records" => records},tenant_id:"long-tenant",verified_at:at,
      profile_ref:L::CHECKOUT_PROFILE_REF,**selectors)
    value = cart(period,amount)
    order = {"tenant_id" => "long-tenant","buyer_account_id" => "synthetic-buyer","order_id" => value.fetch("id"),"merchant_id" => "shop",
      "audience" => "merchant-host","order_version" => "1","currency" => "JPY","expected_total" => amount}
    host = {trust:trust,order:order,root_presentation:checkout_open,host_checkout_jws:checkout_jwt}
    saved = M::InputBuilder.prepare(**host,challenge_id:"challenge-#{period}-#{amount}",nonce:"checkout-nonce-#{period}-#{amount}",issuer_id:"host",
      not_before:at-1,not_after:at+120)
    raw = M::InputBuilder.inputs(**host,saved_challenge:saved,terminal_jws:checkout_closed.delete_suffix("~"),expected_challenge_issuer_id:"host",
      clock_source_id:"synthetic-clock-#{period}",verified_at:at)
    payment = L.details(checkout_jwt:checkout_jwt,trusted_merchant_public_key_pem:merchant,expected_merchant_id:"shop",payment_instrument:{"id"=>"synthetic-card","type"=>"card"})
    {open_sd_jwt:payment_open,closed_sd_jwt:payment_closed,checkout_mode: :conditional,checkout_inputs:raw,expected_payment:payment,
      trusted_provider_public_key_pem:provider,expected_agent_public_key_pem:agent,expected_audience:"payment-host",
      expected_nonce:"payment-nonce-#{period}-#{amount}",verified_at:at,profile_ref:L::PROFILE_REF}
  end
  class Fixture
    attr_reader :provider,:agent,:merchant,:checkout_open,:payment_open,:issued_at,:expires_at
    def initialize(max_occurrences:12,budget:480000,amount:40000,provider:nil,agent:nil,merchant:nil,
                   issued_at:T0,expires_at:EXP,requirements:REQUIREMENTS,seller:SELLER,fixed:{},authority:{})
      @provider,@agent,@merchant = [provider,agent,merchant].map { |key| key || OpenSSL::PKey::EC.generate("prime256v1") }
      @issued_at,@expires_at,@amount = issued_at,expires_at,amount
      @max_occurrences,@budget,@requirements,@seller,@fixed,@authority = max_occurrences,budget,requirements,seller,fixed,authority
      @checkout_open = L.issue_checkout_open(merchant:seller,requirements:requirements,agent_public_key_pem:@agent.public_to_pem,
        issued_at:issued_at,expires_at:expires_at,signer:LongPaymentExample.signer(@provider),public_key_pem:@provider.public_to_pem).root_presentation
      cs = [{"type"=>"payment.amount_range","currency"=>"JPY","min"=>1,"max"=>100000},
        {"type"=>"payment.allowed_payees","allowed"=>[seller]},
        {"type"=>"payment.allowed_payment_instruments","allowed"=>[{"id"=>"synthetic-card","type"=>"card"}]},
        {"type"=>"payment.agent_recurrence","frequency"=>"MONTHLY","max_occurrences"=>max_occurrences},
        {"type"=>"payment.budget","currency"=>"JPY","max"=>budget}]
      @payment_open = L.issue_open(open_checkout_sd_jwt:@checkout_open,constraints:cs,fixed:fixed,candidate_policy: :independent,
        agent_public_key_pem:@agent.public_to_pem,issued_at:issued_at,expires_at:expires_at,
        signer:LongPaymentExample.signer(@provider),public_key_pem:@provider.public_to_pem)
    end
    def month(period, amount = nil, **options)
      raise "unknown synthetic month option" unless (options.keys - %i[amount authority merchant]).empty?
      value = options.fetch(:amount,amount || @amount); at = LongPaymentExample.now(period)
      merchant = options.fetch(:merchant,@merchant)
      cart = LongPaymentExample.cart(period,value)
      jwt = M::CheckoutJWT.sign(checkout:cart,profile_ref:L::CHECKOUT_PROFILE_REF,signer:LongPaymentExample.signer(merchant),public_key_pem:merchant.public_to_pem).jwt
      closed_checkout = L.issue_checkout_closed(root_presentation:@checkout_open,checkout_jwt:jwt,trusted_issuer_public_key_pem:@provider.public_to_pem,
        agent_public_key_pem:@agent.public_to_pem,trusted_merchant_public_key_pem:merchant.public_to_pem,expected_merchant_id:"shop",audience:"merchant-host",
        nonce:"checkout-nonce-#{period}-#{value}",verified_at:at,signer:LongPaymentExample.signer(@agent))
      payment = L.details(checkout_jwt:jwt,trusted_merchant_public_key_pem:merchant.public_to_pem,expected_merchant_id:"shop",payment_instrument:{"id"=>"synthetic-card","type"=>"card"})
      closed_payment = L.issue_closed(open_sd_jwt:@payment_open,payment:payment,trusted_provider_public_key_pem:@provider.public_to_pem,
        agent_public_key_pem:@agent.public_to_pem,audience:"payment-host",nonce:"payment-nonce-#{period}-#{value}",verified_at:at,signer:LongPaymentExample.signer(@agent))
      verify = LongPaymentExample.inputs(period:period,checkout_open:@checkout_open,payment_open:@payment_open,checkout_jwt:jwt,
        checkout_closed:closed_checkout.closed_sd_jwt,payment_closed:closed_payment.closed_sd_jwt,provider:@provider.public_to_pem,
        agent:@agent.public_to_pem,merchant:merchant.public_to_pem,amount:value,authority:options.fetch(:authority,@authority))
      raise "synthetic long wire verification failed" unless L.verify(**verify).verified?
      receipts = [{kind:"checkout",key:merchant.public_to_pem,jwt:M::CheckoutReceipt.sign(closed_sd_jwt:closed_checkout.closed_sd_jwt,profile_ref:L::CHECKOUT_PROFILE_REF,
        issuer:"processor",outcome:"Success",order_id:cart.fetch("id"),issued_at:at,signer:LongPaymentExample.signer(merchant),public_key_pem:merchant.public_to_pem).jwt},
        {kind:"payment",key:merchant.public_to_pem,jwt:M::PaymentReceipt.sign(closed_sd_jwt:closed_payment.closed_sd_jwt,profile_ref:L::PROFILE_REF,
          issuer:"processor",outcome:"Success",payment_id:"payment-#{period}",issued_at:at,psp_confirmation_id:"synthetic-psp",network_confirmation_id:"synthetic-net",
          signer:LongPaymentExample.signer(merchant),public_key_pem:merchant.public_to_pem).jwt}]
      {period:period,now:at,amount:value,cart:cart,checkout_jwt:jwt,checkout_closed:closed_checkout.closed_sd_jwt,payment_closed:closed_payment.closed_sd_jwt,
        expected_payment:payment,verify_inputs:verify,receipts:receipts}
    end
    def rotate(provider:,agent:,merchant:@merchant,issued_at:,authority:)
      self.class.new(provider:provider,agent:agent,merchant:merchant,issued_at:issued_at,expires_at:@expires_at,max_occurrences:@max_occurrences,budget:@budget,
        amount:@amount,requirements:@requirements,seller:@seller,fixed:@fixed,authority:authority)
    end
    def public_fixture
      months = PERIODS.keys.select { |period| @issued_at <= LongPaymentExample.now(period) && LongPaymentExample.now(period) < @expires_at }.map { |period| month(period) }
      {t0:@issued_at,exp:@expires_at,checkout_open:@checkout_open,payment_open:@payment_open,provider:@provider.public_to_pem,agent:@agent.public_to_pem,
        merchant:@merchant.public_to_pem,profiles:{checkout:L::CHECKOUT_PROFILE_REF,payment:L::PROFILE_REF},periods:PERIODS,months:months}
    end
  end
  def self.run
    fixture = Fixture.new
    months = PERIODS.keys.map { |period| fixture.month(period) }
    raise "changed long Open" unless months.all? { |m| m[:verify_inputs][:open_sd_jwt] == fixture.payment_open && m[:verify_inputs][:checkout_inputs][:root_presentation] == fixture.checkout_open }
    puts "Long wire: all 12 leap-year months verified with the same complete Open Checkout and Open Payment"
    puts "Shared content iat/exp preserved; outer proof, current trust, challenge and order verified freshly"
    puts "Wire verification reserves no occurrence or budget; protected Host period/authority storage is required"
    puts "Synthetic only; no payment, settlement or generic MONTHLY calendar conformance is established"
    fixture
  end
end
LongPaymentExample.run if $PROGRAM_NAME == __FILE__
