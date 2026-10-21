# frozen_string_literal: true

module AP2MandateVerifier
  # JSON syntax boundary only. Parsed data is never promoted to trusted data.
  module InputValidator
    MAX_BYTES = 131_072
    MAX_DEPTH = 24 # Root container counts as depth one, matching JSON.parse.
    JSON_VERSION = "2.18.0"
    CORE_INSTANCE_OF = Object.instance_method(:instance_of?)
    CORE_BYTESIZE = String.instance_method(:bytesize)
    CORE_BYTESLICE = String.instance_method(:byteslice)

    class Invalid < StandardError
      attr_reader :code
      def initialize(code)
        @code = code
        super(code.to_s)
      end
    end

    class Unavailable < StandardError
      attr_reader :code
      def initialize(code)
        @code = code
        super(code.to_s)
      end
    end

    def self.check!(source)
      parse!(source)
      nil
    rescue Unavailable => error
      error.code
    end

    # Returns untrusted JSON values only, for subsequent signature checks.
    def self.parse!(source)
      wire = snapshot!(source)
      reject_extensions!(wire)
      require "json"
      raise Unavailable, :json_dependency_unavailable unless JSON::VERSION == JSON_VERSION
      begin
        value = JSON.parse(wire, create_additions: false, symbolize_names: false,
                           max_nesting: MAX_DEPTH, allow_nan: false,
                           allow_duplicate_key: false, allow_trailing_comma: false)
      rescue JSON::NestingError
        raise Invalid, :input_too_deep
      rescue JSON::ParserError => error
        raise Invalid, :duplicate_key if error.message.start_with?("duplicate key ")
        raise Invalid, :invalid_json
      end
      check_numbers!(value)
      value
    end

    def self.snapshot!(source, max_bytes: MAX_BYTES)
      # Even exact Strings can have singleton overrides. Never dispatch to
      # caller methods during type/size checks or original-byte copying.
      raise Invalid, :invalid_input_type unless CORE_INSTANCE_OF.bind_call(source, String)
      raise Invalid, :input_too_large if CORE_BYTESIZE.bind_call(source) > max_bytes
      # Bounded, detached snapshot; never dup an unbounded mutable source.
      wire = CORE_BYTESLICE.bind_call(source, 0, max_bytes + 1)
      raise Invalid, :input_too_large if wire.bytesize > max_bytes
      wire.force_encoding(Encoding::UTF_8)
      raise Invalid, :invalid_encoding unless wire.valid_encoding?
      wire.freeze
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
    private_constant :CORE_INSTANCE_OF, :CORE_BYTESIZE, :CORE_BYTESLICE
  end
end
