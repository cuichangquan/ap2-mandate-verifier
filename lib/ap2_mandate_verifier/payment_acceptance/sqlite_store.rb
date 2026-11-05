# frozen_string_literal: true

module AP2MandateVerifier
  module PaymentAcceptance
    # Optional local durable reference. Production adapters must preserve the
    # same protected-authorization + claim transaction and CAS guarantees.
    class SQLiteStore
      SCHEMA_VERSION = 1
      DRIVER_VERSION = "2.10.2".freeze
      RECEIPT_FIELDS = %w[trusted_public_key_pem expected_issuer expected_payment_id not_before not_after].freeze
      SCHEMA = {
        "ap2_store" => "CREATE TABLE ap2_store (identity TEXT NOT NULL)",
        "ap2_approvals" => "CREATE TABLE ap2_approvals (operation_key TEXT PRIMARY KEY, tenant TEXT NOT NULL, merchant TEXT NOT NULL, approval TEXT NOT NULL, occurrence TEXT NOT NULL, scope TEXT NOT NULL, instruction TEXT NOT NULL, receipt_context TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1)), UNIQUE(tenant,merchant,approval,occurrence))",
        "ap2_attempts" => "CREATE TABLE ap2_attempts (operation_key TEXT PRIMARY KEY REFERENCES ap2_approvals(operation_key), tenant TEXT NOT NULL, merchant TEXT NOT NULL, closed_reference TEXT NOT NULL, fence TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN ('reserved','processing','unknown','receipt_success','receipt_error')), record TEXT NOT NULL, UNIQUE(tenant,merchant,closed_reference))"
      }.transform_values(&:freeze).freeze
      INDEXES = [
        ["sqlite_autoindex_ap2_approvals_1", "ap2_approvals"],
        ["sqlite_autoindex_ap2_approvals_2", "ap2_approvals"],
        ["sqlite_autoindex_ap2_attempts_1", "ap2_attempts"],
        ["sqlite_autoindex_ap2_attempts_2", "ap2_attempts"]
      ].map(&:freeze).freeze
      def self.create(**arguments)
        raise Unavailable unless arguments.keys == [:path]
        path = arguments.fetch(:path)
        dependencies!
        checked = path!(path)
        File.open(checked, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.fsync }
        value = allocate
        value.send(:setup!, checked, true)
        value
      rescue StandardError, LoadError
        raise Unavailable.new, cause: nil
      end
      def self.dependencies!
        gem "sqlite3", "= #{DRIVER_VERSION}"
        require "sqlite3"
        raise Unavailable unless Gem.loaded_specs.fetch("sqlite3").version.to_s == DRIVER_VERSION
      end
      def self.path!(path)
        checked = InputValidator.snapshot!(path, max_bytes: 4096)
        raise Invalid if checked.empty? || checked == ":memory:" || checked.include?("\0") || checked.start_with?("file:")
        checked
      end
      private_class_method :dependencies!, :path!
      def initialize(**arguments)
        raise Unavailable unless arguments.keys == [:path]
        setup!(self.class.send(:path!, arguments.fetch(:path)), false)
      rescue StandardError, LoadError
        raise Unavailable.new, cause: nil
      end
      def inspect = "#<AP2MandateVerifier::PaymentAcceptance::SQLiteStore>"
      def setup!(path, creating)
        self.class.send(:dependencies!)
        @path = path
        @db = SQLite3::Database.new(@path, flags: SQLite3::Constants::Open::READWRITE)
        @db.busy_timeout = 5000
        unless creating
          raise Unavailable unless @db.get_first_value("PRAGMA user_version") == self.class::SCHEMA_VERSION && @db.execute("PRAGMA quick_check") == [["ok"]]
          expected = self.class::SCHEMA.map { |name,sql| ["table", name, name, sql] } +
            self.class::INDEXES.map { |name,table| ["index", name, table, nil] }
          actual = @db.execute("SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name")
          raise Unavailable unless actual == expected.sort_by { |row| row.first(2) }
          identities = @db.execute("SELECT identity FROM ap2_store")
          raise Unavailable unless identities.size == 1 && identities[0].size == 1
          @store_id = identities[0][0]
          raise Unavailable unless @store_id.instance_of?(String) && @store_id.match?(/\A[0-9a-f]{64}\z/)
        end
        @db.execute("PRAGMA journal_mode=DELETE")
        @db.execute("PRAGMA synchronous=FULL")
        @db.execute("PRAGMA foreign_keys=ON")
        raise Unavailable unless @db.get_first_value("PRAGMA journal_mode") == "delete" &&
          @db.get_first_value("PRAGMA synchronous") == 2 && @db.get_first_value("PRAGMA foreign_keys") == 1
        if creating
          require "securerandom"
          @store_id = SecureRandom.hex(32)
          @db.execute("BEGIN IMMEDIATE")
          self.class::SCHEMA.each_value { |sql| @db.execute(sql) }
          @db.execute("INSERT INTO ap2_store(identity) VALUES (?)", [@store_id])
          @db.execute("PRAGMA user_version=#{self.class::SCHEMA_VERSION}")
          @db.execute("COMMIT")
        end
        @mutex = Mutex.new
      rescue StandardError, LoadError
        @db&.close rescue nil
        raise Unavailable.new, cause: nil
      end
      private :setup!

      # Only a protected Host approval backend may enroll this immutable grant.
      # A received ID/flag never enrolls or alters an approved occurrence.
      def authorize!(tenant_id:, merchant_id:, operation_id:, approval_id:, occurrence_id:, order_id:,
                     mode:, profile_ref:, checkout:, payment:, receipt_context:)
        scope = PaymentAcceptance.scope!({"tenant_id" => tenant_id, "merchant_id" => merchant_id,
          "operation_id" => operation_id, "approval_id" => approval_id, "occurrence_id" => occurrence_id, "order_id" => order_id})
        profile = PaymentAcceptance.profile!(mode, profile_ref)
        approval_policy!(profile)
        cart = InputBuilder.send(:copy!, checkout)
        raise Invalid unless cart["id"] == scope["order_id"] && cart.dig("merchant", "id") == scope["merchant_id"]
        instruction = PaymentAcceptance.instruction!(mode, profile, cart, payment)
        context = PaymentAcceptance.copy!(receipt_context).transform_keys(&:to_s)
        raise Invalid unless context.keys.sort == RECEIPT_FIELDS.sort
        RootSignature.public_jwk!(context["trusted_public_key_pem"])
        %w[expected_issuer expected_payment_id].each { |f| CheckoutReceipt.send(:text!, context[f], 512) }
        %w[not_before not_after].each { |f| CheckoutReceipt.send(:epoch!, context[f]) }
        raise Invalid unless context["not_before"] <= context["not_after"]
        row = [PaymentAcceptance.canonical(scope), instruction, PaymentAcceptance.canonical(context)]
        transaction do
          alias_key = @db.get_first_value("SELECT operation_key FROM ap2_approvals WHERE tenant=? AND merchant=? AND approval=? AND occurrence=?",
            scope.values_at("tenant_id", "merchant_id", "approval_id", "occurrence_id"))
          raise Conflict if alias_key && alias_key != PaymentAcceptance.key(scope)
          old = @db.get_first_row("SELECT CASE WHEN length(CAST(scope AS BLOB))<=131072 THEN scope END,CASE WHEN length(CAST(instruction AS BLOB))<=131072 THEN instruction END,CASE WHEN length(CAST(receipt_context AS BLOB))<=8192 THEN receipt_context END FROM ap2_approvals WHERE operation_key=?", [PaymentAcceptance.key(scope)])
          check_grant!(old) if old
          raise Conflict if old && old != row
          unless old
            begin
              @db.execute("INSERT INTO ap2_approvals(operation_key,tenant,merchant,approval,occurrence,scope,instruction,receipt_context) VALUES (?,?,?,?,?,?,?,?)",
                [PaymentAcceptance.key(scope), *scope.values_at("tenant_id", "merchant_id", "approval_id", "occurrence_id"), *row])
            rescue SQLite3::ConstraintException
              raise Conflict
            end
          end
          true
        end
      end

      def reserve!(scope:, instruction:, record:)
        transaction do
          key = PaymentAcceptance.key(scope)
          grant = @db.get_first_row("SELECT CASE WHEN length(CAST(scope AS BLOB))<=131072 THEN scope END,CASE WHEN length(CAST(instruction AS BLOB))<=131072 THEN instruction END,CASE WHEN length(CAST(receipt_context AS BLOB))<=8192 THEN receipt_context END,active FROM ap2_approvals WHERE operation_key=?", [key])
          raise Invalid unless grant
          check_grant!(grant)
          raise Invalid unless grant[3] == 1
          raise Conflict unless grant[0] == PaymentAcceptance.canonical(scope) && grant[1] == instruction
          validate_reservation!(scope, record)
          old = load_record(key)
          if old
            raise Conflict unless old["instruction"] == instruction
            next PaymentAcceptance.result(old)
          end
          reused = @db.get_first_value("SELECT operation_key FROM ap2_attempts WHERE tenant=? AND merchant=? AND closed_reference=?",
            [scope.fetch("tenant_id"), scope.fetch("merchant_id"), record.fetch("reference")])
          raise Conflict if reused
          charge_reservation!(scope, record)
          require "securerandom"
          fence = SecureRandom.hex(32)
          value = record.merge("state" => "reserved", "processor_key" => SecureRandom.hex(32),
            "receipt_context" => decode!(grant[2], 8192))
          raise Invalid if JSON.generate(value).bytesize > 1_048_576
          begin
            @db.execute("INSERT INTO ap2_attempts(operation_key,tenant,merchant,closed_reference,fence,state,record) VALUES (?,?,?,?,?,?,?)",
              [key, scope.fetch("tenant_id"), scope.fetch("merchant_id"), record.fetch("reference"), fence, "reserved", JSON.generate(value)])
          rescue SQLite3::ConstraintException
            raise Conflict
          end
          # Returned only after COMMIT succeeds. A commit error is unavailable,
          # even if SQLite may have persisted the row; no capability is returned.
          Result.send(:new, :reserved, value, Ticket.send(:new, @store_id + key, fence))
        end
      end

      def start!(ticket:, verified_at:, instruction:, signed_wires:)
        key, fence = ticket_parts!(ticket)
        transaction do
          row = @db.get_first_row("SELECT state,CASE WHEN length(CAST(record AS BLOB))<=1048576 THEN record ELSE NULL END FROM ap2_attempts WHERE operation_key=? AND fence=?", [key, fence])
          raise Invalid unless row
          next nil unless row[0] == "reserved"
          record = decode!(row[1], 1_048_576)
          raise Unavailable unless record["state"] == row[0]
          grant = @db.get_first_row("SELECT active,CASE WHEN length(CAST(instruction AS BLOB))<=131072 THEN instruction END FROM ap2_approvals WHERE operation_key=?", [key])
          raise Invalid unless grant && grant[0] == 1 && grant[1] == instruction &&
            record["instruction"] == instruction && record["signed_wires"] == signed_wires
          next nil unless verified_at >= record["accepted_at"] && verified_at < record["valid_until"]
          validate_start!(record, verified_at)
          record["state"] = "processing"
          record["started_at"] = verified_at
          @db.execute("UPDATE ap2_attempts SET state='processing',record=? WHERE operation_key=? AND fence=? AND state='reserved'", [JSON.generate(record), key, fence])
          raise Unavailable unless @db.changes == 1
          record
        end
      end

      def ticket_record!(ticket:)
        key, fence = ticket_parts!(ticket)
        transaction do
          row = @db.get_first_row("SELECT CASE WHEN length(CAST(record AS BLOB))<=1048576 THEN record ELSE NULL END FROM ap2_attempts WHERE operation_key=? AND fence=?", [key, fence])
          raise Invalid unless row
          decode!(row[0], 1_048_576)
        end
      end

      def lookup_record!(scope:)
        transaction do
          record = load_record(PaymentAcceptance.key(scope))
          raise Conflict if record && record["scope"] != scope
          record
        end
      end

      def unknown!(ticket:)
        key, fence = ticket_parts!(ticket)
        transaction do
          record = load_record(key, fence)
          raise Invalid unless record
          if record["state"] == "processing"
            record["state"] = "unknown"
            save(key, record)
          elsif record["state"] != "unknown"
            raise Invalid
          end
          PaymentAcceptance.result(record)
        end
      end

      def finish!(scope:, ticket:, receipt_jwt:, status:)
        raise Invalid unless %w[receipt_success receipt_error].include?(status)
        key = PaymentAcceptance.key(scope)
        fence = ticket_parts!(ticket)[1] if ticket
        raise Invalid if ticket && ticket_parts!(ticket)[0] != key
        transaction do
          record = load_record(key, fence)
          raise Invalid unless record && record["scope"] == scope
          if %w[receipt_success receipt_error].include?(record["state"])
            raise Conflict unless record["receipt_jwt"] == receipt_jwt && record["state"] == status
          else
            raise Invalid unless %w[processing unknown].include?(record["state"])
            record["state"], record["receipt_jwt"] = status, receipt_jwt
            save(key, record)
          end
          PaymentAcceptance.result(record)
        end
      end

      def close
        @mutex.synchronize { @db.close }
      rescue StandardError
        raise Unavailable.new, cause: nil
      end

      def revoke!(**scope)
        scope = PaymentAcceptance.scope_keywords!(scope)
        transaction do
          @db.execute("UPDATE ap2_approvals SET active=0 WHERE operation_key=? AND scope=?", [PaymentAcceptance.key(scope), PaymentAcceptance.canonical(scope)])
          raise Invalid unless @db.changes == 1
          true
        end
      end

      private
      # Extension hooks execute inside the SAME SQLite transaction as reservation/start.
      # The old schema must never accept a profile requiring an absent quota ledger.
      def approval_policy!(profile)
        raise Invalid if RecurringPayment.profile?(profile)
      end
      def validate_reservation!(_scope, record) = approval_policy!(record.fetch("profile_ref"))
      def charge_reservation!(_scope, _record); end
      def validate_start!(_record, _verified_at); end
      def ticket_parts!(ticket)
        raise Invalid unless ticket.instance_of?(Ticket)
        key = ticket.send(:key)
        raise Invalid unless key.start_with?(@store_id) && key.bytesize == 128
        [key[64,64], ticket.send(:fence)]
      end
      def load_record(key, fence = nil)
        sql = "SELECT state,CASE WHEN length(CAST(record AS BLOB))<=1048576 THEN record ELSE NULL END FROM ap2_attempts WHERE operation_key=?"
        args = [key]
        if fence
          sql += " AND fence=?"; args << fence
        end
        row = @db.get_first_row(sql, args)
        if row
          record = decode!(row[1], 1_048_576)
          raise Unavailable unless record["state"] == row[0]
          record
        end
      end
      def save(key, record)
        raise Unavailable if JSON.generate(record).bytesize > 1_048_576
        @db.execute("UPDATE ap2_attempts SET state=?,record=? WHERE operation_key=?", [record.fetch("state"), JSON.generate(record), key])
        raise Unavailable unless @db.changes == 1
      end
      def check_grant!(row)
        [131_072,131_072,8192].each_with_index { |limit,i| InputValidator.snapshot!(row[i], max_bytes: limit) }
      end
      def decode!(source, max)
        wire = InputValidator.snapshot!(source, max_bytes: max)
        InputValidator.send(:reject_extensions!, wire)
        raise Unavailable unless JSON::VERSION == InputValidator::JSON_VERSION
        JSON.parse(wire, create_additions: false, symbolize_names: false, max_nesting: 24,
          allow_nan: false, allow_duplicate_key: false, allow_trailing_comma: false)
      rescue StandardError
        raise Unavailable.new, cause: nil
      end
      def transaction
        @mutex.synchronize do
          @db.execute("BEGIN IMMEDIATE")
          begin
            value = yield
            @db.execute("COMMIT")
            value
          rescue StandardError
            @db.execute("ROLLBACK") rescue nil
            raise
          end
        end
      rescue Invalid, Conflict
        raise
      rescue StandardError
        raise Unavailable.new, cause: nil
      end

      %i[authorize! reserve! start! ticket_record! lookup_record! unknown! finish! close revoke!].each do |name|
        implementation = instance_method(name)
        required = implementation.parameters.filter_map { |kind, key| key if kind == :keyreq }.freeze
        allowed = implementation.parameters.filter_map { |kind, key| key if %i[keyreq key].include?(kind) }.freeze
        rest = implementation.parameters.any? { |kind,_| kind == :keyrest }
        define_method(name) do |**arguments|
          raise Invalid unless (required - arguments.keys).empty? && (rest || (arguments.keys - allowed).empty?)
          implementation.bind_call(self, **arguments)
        rescue Conflict
          raise Conflict.new("payment acceptance conflict"), cause: nil
        rescue Unavailable
          raise Unavailable.new, cause: nil
        rescue StandardError, LoadError
          raise Invalid.new, cause: nil
        end
        public name
      end
    end
  end
end
