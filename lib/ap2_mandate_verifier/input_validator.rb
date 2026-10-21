# frozen_string_literal: true

module AP2MandateVerifier
  # JSON syntax boundary only. Parsed data is never promoted to trusted data.
  module InputValidator
    MAX_BYTES = 131_072
    MAX_DEPTH = 24 # Root container counts as depth one, matching JSON.parse.
    JSON_VERSION = "2.18.0"

    class Invalid < StandardError
      attr_reader :code
      def initialize(code)
        @code = code
        super(code.to_s)
      end
    end

    def self.check!(source)
      # Exact String avoids caller-defined conversion and overridden methods.
      raise Invalid, :invalid_input_type unless source.instance_of?(String)
      raise Invalid, :input_too_large if source.bytesize > MAX_BYTES
      # Bounded, detached snapshot; never dup an unbounded mutable source.
      wire = source.byteslice(0, MAX_BYTES + 1)
      raise Invalid, :input_too_large if wire.bytesize > MAX_BYTES
      wire.force_encoding(Encoding::UTF_8)
      raise Invalid, :invalid_encoding unless wire.valid_encoding?
      wire.freeze
      reject_extensions!(wire)

      require "json"
      return :json_dependency_unavailable unless JSON::VERSION == JSON_VERSION

      begin
        value = JSON.parse(wire, create_additions: false, symbolize_names: false,
                           max_nesting: MAX_DEPTH, allow_nan: false,
                           allow_duplicate_key: false, allow_trailing_comma: false)
      rescue JSON::NestingError
        raise Invalid, :input_too_deep
      rescue JSON::ParserError => error
        # Version-pinned native parser detects decoded duplicates. Never emit
        # its message: it includes the untrusted key. A changed diagnostic
        # can only lose the specific code, never turn rejection into success.
        raise Invalid, :duplicate_key if error.message.start_with?("duplicate key ")
        raise Invalid, :invalid_json
      end
      # A syntactically finite exponent can overflow the native Float parser.
      check_numbers!(value)
      nil
    end

    # JSON 2.18 accepts comments and a BOM. Reject both without interpreting
    # string contents; ordinary '/' and Unicode inside strings remain valid.
    def self.reject_extensions!(wire)
      quoted = false
      escaped = false
      wire.each_byte do |byte|
        if quoted
          if escaped
            escaped = false
          elsif byte == 92
            escaped = true
          elsif byte == 34
            quoted = false
          end
        elsif byte == 34
          quoted = true
        elsif byte == 47 || byte >= 128
          raise Invalid, :invalid_json
        end
      end
    end

    def self.check_numbers!(value)
      case value
      when Hash
        value.each_value { |child| check_numbers!(child) }
      when Array
        value.each { |child| check_numbers!(child) }
      when Float
        raise Invalid, :invalid_json unless value.finite?
      end
    end
    private_class_method :check_numbers!, :reject_extensions!
  end
end
