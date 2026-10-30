# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "ap2_mandate_verifier"
  spec.version = "0.2.1"
  spec.summary = "Fixed-profile AP2 verification for Ruby"
  spec.description = "Stateless verification of the fixed AP2 profile with immutable Evidence using verify_checkout and the retained verify_research API. Requires trusted Host inputs and the documented runtime; not Host authorization, payment permission or general AP2 conformance."
  spec.authors = ["AP2 Mandate Verifier contributors"]
  spec.license = "MIT"
  spec.homepage = "https://github.com/cuichangquan/ap2-mandate-verifier"
  spec.files = Dir["lib/**/*.rb"] + %w[README.md LICENSE docs/SUPPORT_CONTRACT.md]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = [">= 3.4.12", "< 4.1"]
  spec.add_runtime_dependency "json", "= 2.19.9"
  spec.add_runtime_dependency "jwt", "= 3.3.0"
  spec.add_runtime_dependency "base64", "= 0.3.0"
  spec.add_runtime_dependency "openssl", "= 4.0.2"
  spec.add_runtime_dependency "digest", "= 3.2.1"
end
