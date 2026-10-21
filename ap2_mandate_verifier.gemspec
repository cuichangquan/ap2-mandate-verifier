# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "ap2_mandate_verifier"
  spec.version = "0.0.0"
  spec.summary = "Unreleased AP2 verifier input boundary; verification unavailable"
  spec.authors = ["AP2 Mandate Verifier contributors"]
  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_runtime_dependency "json", "= 2.18.0"
end
