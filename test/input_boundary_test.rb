# frozen_string_literal: true

# No test gems, network, filesystem writes, child processes, or AP2 fixtures.
require_relative "../lib/ap2_mandate_verifier"
require "json"

raise "unexpected Ruby version" unless RUBY_VERSION == "4.0.1"
raise "unexpected JSON version" unless JSON::VERSION == "2.19.9"

module BoundaryTest
  @cases = 0
  def self.assert(value, message = "boundary assertion failed (no input values logged)")
    raise message unless value
  end

  def self.expect(wire, status, code)
    result = AP2MandateVerifier.verify(presentation_json: wire)
    assert(result.status == status && result.code == code,
           "case #{@cases + 1}: expected #{status}/#{code}, got #{result.status}/#{result.code}")
    assert(result.success? == false && result.evidence.nil? && result.frozen?)
    assert(result.rejected? == (status == :rejected))
    assert(result.unverified? == (status == :unverified))
    assert(result.unavailable? == (status == :unavailable))
    @cases += 1
  end

  # Independently specified JSON literals and boundary arithmetic; expected
  # results are not obtained from another call to the candidate parser.
  ["{}", "[]", "null", "true", "0", '"text"', '{"amount":12.5}',
   '{"a":{"x":1},"b":{"x":2}}', '{"a":1,"A":2}',
   '{"text":"日本語"}', '{"json_class":"Object"}',
   " \n{}\t\r", '{"a":[{"b":false}]}',
   '{"url":"https://example.invalid/a/*b*/"}',
   '{"text":"escaped \\" quote / remains a string"}',
   '{"text":"slash \\\\"}'].each do |wire|
    expect(wire, :unverified, :verification_not_implemented)
  end

  ["", " ", "{", '{}{}', '{} trailing', '{"a":1,}', '[1,]',
   '{a:1}', '{"a":NaN}', 'Infinity', '-Infinity', '1e999',
   '{"n":1e999}', '01', '+1', '/*comment*/{}', "\xEF\xBB\xBF{}".b,
   '"\\uD800"', '"\\x41"', "{\"a\":\"\x00\"}",
   "//comment\n{}", '{"a":/*comment*/1}', '{}//comment',
   " \xEF\xBB\xBF{}".b, "{}\xEF\xBB\xBF".b].each do |wire|
    expect(wire, :rejected, :invalid_json)
  end

  ['{"a":1,"a":2}', '{"a":null,"a":null}',
   '{"a":1,"\\u0061":2}', '{"outer":{"x":1,"x":2}}',
   '[{"x":1,"x":2}]', '{"a/b":1,"a\\/b":2}',
   '{"日本":1,"\\u65e5\\u672c":2}'].each do |wire|
    expect(wire, :rejected, :duplicate_key)
  end

  [nil, {}, [], 1, Class.new(String).new("{}")].each do |wire|
    expect(wire, :rejected, :invalid_input_type)
  end
  ["\xFF".b, "\xC0\xAF".b, "{\x00}\x00".b.force_encoding("UTF-16LE")].each do |wire|
    # UTF-16LE bytes here are valid UTF-8 containing NUL, hence JSON-invalid.
    expected = wire.encoding == Encoding::UTF_16LE ? :invalid_json : :invalid_encoding
    expect(wire, :rejected, expected)
  end
  expect("{}".b, :unverified, :verification_not_implemented)

  # 131072 is fixed independently, including multibyte byte counting.
  max = 131_072
  expect('"' + "a" * (max - 2) + '"', :unverified, :verification_not_implemented)
  expect('"' + "a" * (max - 1) + '"', :rejected, :input_too_large)
  expect('"' + "é" * (max / 2) + '"', :rejected, :input_too_large)
  expect("[" * 24 + "0" + "]" * 24, :unverified, :verification_not_implemented)
  expect("[" * 25 + "0" + "]" * 25, :rejected, :input_too_deep)
  expect('{"a":' * 24 + "0" + "}" * 24, :unverified, :verification_not_implemented)
  expect('{"a":' * 25 + "0" + "}" * 25, :rejected, :input_too_deep)
  expect('[{"a":' * 12 + "0" + "}]" * 12, :unverified, :verification_not_implemented)
  expect('[{"a":' * 13 + "0" + "}]" * 13, :rejected, :input_too_deep)

  # Runtime fault injection checks classification; ensure restores methods.
  def self.with_check_failure(error)
    validator = AP2MandateVerifier::InputValidator.singleton_class
    original = validator.instance_method(:check!)
    validator.define_method(:check!) { |_wire| raise error, "sensitive text" }
    yield
  ensure
    validator.define_method(:check!, original)
  end
  with_check_failure(LoadError) do
    expect("{}", :unavailable, :json_dependency_unavailable)
  end
  with_check_failure(RuntimeError) do
    expect("{}", :unavailable, :input_check_unavailable)
  end

  # A dependency version mismatch must not parse otherwise valid input.
  original_version = JSON::VERSION
  begin
    JSON.send(:remove_const, :VERSION)
    JSON.const_set(:VERSION, "unreviewed")
    expect("{}", :unavailable, :json_dependency_unavailable)
  ensure
    JSON.send(:remove_const, :VERSION)
    JSON.const_set(:VERSION, original_version)
  end

  source = +'{"a":1}'
  before = source.dup
  expect(source, :unverified, :verification_not_implemented)
  assert(source == before && !source.frozen?)
  # Exact mutable Strings may carry singleton methods too. No input-provided
  # type/length/slice override may run or replace the original bytes.
  callbacks = 0
  [[+"{", :rejected, :invalid_json],
   ["x" * (max + 1), :rejected, :input_too_large],
   [+"{}", :unverified, :verification_not_implemented],
   [Object.new, :rejected, :invalid_input_type],
   [Class.new(String).new("{}"), :rejected, :invalid_input_type]].each do |wire, status, code|
    wire.define_singleton_method(:instance_of?) { |_klass| callbacks += 1; true }
    wire.define_singleton_method(:bytesize) { callbacks += 1; 2 }
    wire.define_singleton_method(:byteslice) { |*_args| callbacks += 1; "{}" }
    expect(wire, status, code)
    assert(callbacks.zero?)
  end
  [[:success, :verification_not_implemented], [:rejected, :verification_not_implemented],
   [:unverified, :invalid_json], [:unavailable, :invalid_json]].each do |status, code|
    rejected = false
    begin
      AP2MandateVerifier::Result.new(status: status, code: code)
    rescue ArgumentError
      rejected = true
    end
    assert(rejected)
    @cases += 1
  end

  puts "PASS #{@cases} cases; Ruby #{RUBY_VERSION}; JSON #{JSON::VERSION}"
end
