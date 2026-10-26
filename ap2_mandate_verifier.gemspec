# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "ap2_mandate_verifier"
  spec.version = "0.1.0"
  spec.summary = "Fixed-profile AP2 verification stable candidate"
  spec.description = "Stateless fixed-profile verification and immutable research Evidence; not Host authorization or payment permission. Unpublished stable candidate; fixed profile and trusted Host preconditions apply. Publication requires separate Owner approval."
  spec.authors = ["AP2 Mandate Verifier contributors"]
  spec.license = "MIT"
  spec.homepage = "https://github.com/cuichangquan/ap2-mandate-verifier"
  spec.files = Dir["lib/**/*.rb"] + %w[README.md LICENSE docs/SUPPORT_CONTRACT.md]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = "= 4.0.9"
  spec.add_runtime_dependency "json", "= 2.19.9"
  spec.add_runtime_dependency "jwt", "= 3.3.0"
  spec.add_runtime_dependency "base64", "= 0.3.0"
  spec.add_runtime_dependency "openssl", "= 4.0.2"
  spec.add_runtime_dependency "digest", "= 3.2.1"
end
