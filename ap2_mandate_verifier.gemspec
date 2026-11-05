# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "ap2_mandate_verifier"
  spec.version = "1.6.0"
  spec.summary = "Ruby SDK for supported AP2 Checkout and Payment Mandates"
  spec.description = "Framework-independent Ruby SDK for supported AP2 Checkout profiles: Merchant JWT signing, Direct and conditional Mandate issuance and presentation, full verification with immutable Evidence, Checkout Receipts, Direct and conditional Payment Mandates, and Payment Receipts. Adds selective Checkout/Payment, PISP/date constraints opt-in transactional Payment acceptance/idempotency support and explicit JPY/ON_DEMAND recurrence quotas. Requires independently trusted application inputs; verification does not grant purchase or payment permission."
  spec.authors = ["AP2 Mandate Verifier contributors"]
  spec.license = "MIT"
  spec.homepage = "https://github.com/cuichangquan/ap2-mandate-verifier"
  spec.files = Dir["lib/**/*.rb"] + %w[README.md LICENSE docs/SUPPORT_CONTRACT.md docs/DIAGNOSTICS.md docs/DIAGNOSTICS.ja.md docs/MERCHANT_SIGNING.md docs/MULTI_ITEM_CHECKOUT.md docs/BUYER_DIRECT_CHECKOUT.md]
  spec.files += %w[README.ja.md SECURITY.md docs/PUBLIC_API.md docs/INPUT_BUILDER.md docs/POST_RELEASE_MAINTENANCE.md docs/CONDITIONAL_CHECKOUT.md docs/RELEASE_100_CANDIDATE.md examples/conditional_checkout.rb]
  spec.files += %w[docs/PAYMENT.md docs/RELEASE_110_CANDIDATE.md examples/payment.rb]
  spec.files += %w[docs/SELECTIVE_PAYMENT.md docs/RELEASE_120_CANDIDATE.md examples/selective_payment.rb]
  spec.files += %w[docs/POST_RELEASE_110.md docs/evidence/1.1.0_publication.json]
  spec.files += %w[docs/SELECTIVE_CHECKOUT.md docs/RELEASE_130_CANDIDATE.md examples/selective_checkout.rb examples/selective_checkout_payment.rb]
  spec.files += %w[docs/PAYMENT_POLICY.md docs/RELEASE_140_CANDIDATE.md examples/payment_policy.rb]
  spec.files += %w[docs/PAYMENT_ACCEPTANCE.md docs/RELEASE_150_CANDIDATE.md examples/payment_acceptance.rb]
  spec.files += %w[docs/RECURRING_PAYMENT.md docs/RELEASE_160_CANDIDATE.md examples/recurring_payment.rb]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = [">= 3.4.12", "< 4.1"]
  spec.add_runtime_dependency "json", "= 2.19.9"
  spec.add_runtime_dependency "jwt", "= 3.3.0"
  spec.add_runtime_dependency "base64", "= 0.3.0"
  spec.add_runtime_dependency "openssl", "= 4.0.2"
  spec.add_runtime_dependency "digest", "= 3.2.1"
end
