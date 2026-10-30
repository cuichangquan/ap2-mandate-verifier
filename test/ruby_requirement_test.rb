# frozen_string_literal: true
require "rubygems"
spec = Gem::Specification.load(File.expand_path("../ap2_mandate_verifier.gemspec", __dir__))
expected = {"3.4.11"=>false, "3.4.12"=>true, "3.4.13"=>true,
            "4.0.0"=>true, "4.0.9"=>true, "4.1.0"=>false, "5.0.0"=>false}
expected.each do |version, allowed|
  raise "Ruby installation interval: #{version}" unless spec.required_ruby_version.satisfied_by?(Gem::Version.new(version)) == allowed
end
puts "PASS #{expected.size} Ruby installation metadata cases; installation interval is not formal support"
