# frozen_string_literal: true

module AP2MandateVerifier
  module PaymentAcceptance
    # Protected Host authority and period state share the occurrence transaction.
    # An external registry feed must synchronize into this ledger before use.
    class LongSQLiteStore < RecurringSQLiteStore
      SCHEMA_VERSION = 3
      MAX_CONTRACT = 524_288
      SCHEDULE_POLICY = "host.utc_calendar_month_windows.1".freeze
      SCHEMA = RecurringSQLiteStore::SCHEMA.merge(
        "ap2_long_state" => "CREATE TABLE ap2_long_state (series_key TEXT PRIMARY KEY REFERENCES ap2_series(series_key), root_reference TEXT NOT NULL, epoch INTEGER NOT NULL CHECK(epoch>0), authority TEXT NOT NULL, authority_active INTEGER NOT NULL CHECK(authority_active IN (0,1)))",
        "ap2_long_roots" => "CREATE TABLE ap2_long_roots (tenant TEXT NOT NULL, root_reference TEXT NOT NULL, series_key TEXT NOT NULL REFERENCES ap2_series(series_key), contract TEXT NOT NULL, active INTEGER NOT NULL CHECK(active IN (0,1)), PRIMARY KEY(tenant,root_reference))",
        "ap2_long_periods" => "CREATE TABLE ap2_long_periods (series_key TEXT NOT NULL REFERENCES ap2_series(series_key), period_id TEXT NOT NULL, not_before INTEGER NOT NULL, not_after INTEGER NOT NULL, PRIMARY KEY(series_key,period_id))"
      ).transform_values(&:freeze).freeze
      INDEXES = (RecurringSQLiteStore::INDEXES + [
        ["sqlite_autoindex_ap2_long_state_1", "ap2_long_state"],
        ["sqlite_autoindex_ap2_long_roots_1", "ap2_long_roots"],
        ["sqlite_autoindex_ap2_long_periods_1", "ap2_long_periods"]
      ]).map(&:freeze).freeze

      def authorize_series!(tenant_id:, merchant_id:, approval_id:, payment_open:, checkout_open:,
                            trust_json:, selection_json:, verified_at:, periods:, schedule_policy_id:)
        ids = series_ids!(tenant_id, merchant_id, approval_id)
        pair = approved_pair!(ids, payment_open, checkout_open, trust_json, selection_json, verified_at)
        windows = periods!(periods, pair, schedule_policy_id)
        contract = pair_contract(pair).merge("schedule_policy_id" => schedule_policy_id, "periods" => windows,
          "agreement_not_before" => pair.fetch(:not_before), "agreement_not_after" => pair.fetch(:not_after))
        encoded = encode_contract!(contract)
        transaction do
          key = series_key(ids)
          old = @db.get_first_value("SELECT CASE WHEN length(CAST(contract AS BLOB))<=#{MAX_CONTRACT} THEN contract END FROM ap2_series WHERE series_key=?", [key])
          if old
            raise Conflict unless old == encoded
            next true # Never reactivate, reset, or rotate via enrollment.
          end
          begin
            @db.execute("INSERT INTO ap2_series(series_key,tenant,merchant,approval,root_reference,contract) VALUES (?,?,?,?,?,?)",
              [key, *ids, pair.fetch(:reference), encoded])
            insert_root!(ids, key, pair)
            @db.execute("INSERT INTO ap2_long_state(series_key,root_reference,epoch,authority,authority_active) VALUES (?,?,1,?,1)",
              [key, pair.fetch(:reference), PaymentAcceptance.canonical(pair.fetch(:authority_binding))])
            windows.each do |window|
              @db.execute("INSERT INTO ap2_long_periods(series_key,period_id,not_before,not_after) VALUES (?,?,?,?)",
                [key, *window.values_at("id", "not_before", "not_after")])
            end
          rescue SQLite3::ConstraintException
            raise Conflict
          end
          true
        end
      end

      # Protected backend CAS, not a request-driven 'current' flag.
      def update_authority!(tenant_id:, merchant_id:, approval_id:, expected_epoch:, trust_json:, selection_json:, verified_at:)
        expected_epoch!(expected_epoch)
        ids = series_ids!(tenant_id, merchant_id, approval_id)
        context = LongPayment.current_authority!(trust_json: trust_json, selection_json: selection_json,
          merchant_id: merchant_id, verified_at: verified_at)
        raise Invalid unless context.fetch(:tenant_id) == tenant_id
        transaction do
          agreement, active = series_row!(ids)
          state, root = current_root!(ids, expected_epoch)
          raise Invalid unless active == 1 && root.fetch("active") == 1 && verified_at < agreement.fetch("agreement_not_after")
          raise Conflict unless root.fetch("root_key_fingerprints") == context.fetch(:root_key_fingerprints) &&
            agreement.fetch("authority_principals") == context.fetch(:authority_principals)
          authority = PaymentAcceptance.canonical(context.fetch(:authority_binding))
          next state.fetch("epoch") if state.fetch("authority_active") == 1 && state.fetch("authority") == authority
          @db.execute("UPDATE ap2_long_state SET authority=?,authority_active=1,epoch=epoch+1 WHERE series_key=? AND epoch=?",
            [authority, series_key(ids), expected_epoch])
          raise Conflict unless @db.changes == 1
          expected_epoch + 1
        end
      end

      def invalidate_authority!(tenant_id:, merchant_id:, approval_id:, expected_epoch:)
        expected_epoch!(expected_epoch)
        ids = series_ids!(tenant_id, merchant_id, approval_id)
        transaction do
          current_root!(ids, expected_epoch)
          @db.execute("UPDATE ap2_long_state SET authority_active=0,epoch=epoch+1 WHERE series_key=? AND epoch=?", [series_key(ids), expected_epoch])
          raise Conflict unless @db.changes == 1
          expected_epoch + 1
        end
      end

      def replace_root!(tenant_id:, merchant_id:, approval_id:, expected_epoch:, expected_root_reference:,
                        payment_open:, checkout_open:, trust_json:, selection_json:, verified_at:)
        expected_epoch!(expected_epoch)
        ids = series_ids!(tenant_id, merchant_id, approval_id)
        pair = approved_pair!(ids, payment_open, checkout_open, trust_json, selection_json, verified_at)
        transaction do
          agreement, active = series_row!(ids)
          state, = current_root!(ids, expected_epoch)
          raise Invalid unless active == 1
          raise Conflict unless state.fetch("root_reference") == expected_root_reference &&
            agreement.fetch("economic_contract") == pair.fetch(:economic_contract) &&
            agreement.fetch("authority_principals") == pair.fetch(:authority_principals) &&
            pair.fetch(:not_after) <= agreement.fetch("agreement_not_after") &&
            verified_at < agreement.fetch("agreement_not_after")
          # Alias tombstones are never deleted/reused, even after key revocation.
          insert_root!(ids, series_key(ids), pair)
          @db.execute("UPDATE ap2_long_roots SET active=0 WHERE tenant=? AND root_reference=?", [ids[0], expected_root_reference])
          @db.execute("UPDATE ap2_long_state SET root_reference=?,epoch=epoch+1,authority=?,authority_active=1 WHERE series_key=? AND epoch=?",
            [pair.fetch(:reference), PaymentAcceptance.canonical(pair.fetch(:authority_binding)), series_key(ids), expected_epoch])
          raise Conflict unless @db.changes == 1
          expected_epoch + 1
        end
      end

      def revoke_root!(tenant_id:, merchant_id:, approval_id:, expected_epoch:)
        expected_epoch!(expected_epoch)
        ids = series_ids!(tenant_id, merchant_id, approval_id)
        transaction do
          state, = current_root!(ids, expected_epoch)
          @db.execute("UPDATE ap2_long_roots SET active=0 WHERE tenant=? AND root_reference=?", [ids[0], state.fetch("root_reference")])
          @db.execute("UPDATE ap2_long_state SET authority_active=0,epoch=epoch+1 WHERE series_key=? AND epoch=?", [series_key(ids), expected_epoch])
          raise Conflict unless @db.changes == 1
          expected_epoch + 1
        end
      end

      def usage(tenant_id:, merchant_id:, approval_id:)
        ids = series_ids!(tenant_id, merchant_id, approval_id)
        transaction do
          contract, active, uses, spent = series_row!(ids)
          state, root = current_root!(ids)
          {currency: "JPY", reserved_occurrences: uses, reserved_amount: spent,
            max_occurrences: contract.fetch("max_occurrences"), budget_max: contract.fetch("budget_max"), active: active == 1,
            epoch: state.fetch("epoch"), root_reference: state.fetch("root_reference").dup.freeze,
            authority_active: state.fetch("authority_active") == 1 && root.fetch("active") == 1}.freeze
        end
      end

      def start_long!(ticket:, verified_at:, instruction:, signed_wires:, authority_binding:, valid_until:)
        CheckoutReceipt.send(:epoch!, valid_until)
        start_record!(ticket: ticket, verified_at: verified_at, instruction: instruction, signed_wires: signed_wires,
          authority: PaymentAcceptance.copy!(authority_binding), fresh_valid_until: valid_until)
      end

      private
      def expected_epoch!(value)
        raise Invalid unless value.instance_of?(Integer) && value.between?(1, 9_007_199_254_740_000)
      end
      def approved_pair!(ids, payment, checkout, trust, selection, now)
        pair = LongPayment.approved_pair!(payment_open: payment, checkout_open: checkout,
          trust_json: trust, selection_json: selection, merchant_id: ids[1], verified_at: now)
        raise Invalid unless pair.fetch(:tenant_id) == ids[0]
        pair
      end
      def pair_contract(pair)
        {"profile_ref" => LongPayment::PROFILE_REF, "root_reference" => pair.fetch(:reference),
          "economic_contract" => pair.fetch(:economic_contract), "opening" => pair.fetch(:opening),
          "max_occurrences" => pair.fetch(:max_occurrences), "budget_max" => pair.fetch(:budget_max), "currency" => pair.fetch(:currency),
          "authority_principals" => pair.fetch(:authority_principals),
          "root_key_fingerprints" => pair.fetch(:root_key_fingerprints), "not_before" => pair.fetch(:not_before), "not_after" => pair.fetch(:not_after)}
      end
      def encode_contract!(contract)
        value = PaymentAcceptance.canonical(contract)
        raise Invalid if value.bytesize > MAX_CONTRACT
        value
      end
      def periods!(source, pair, policy)
        raise Invalid unless policy == SCHEDULE_POLICY
        list = PaymentAcceptance.copy!(source)
        raise Invalid unless list.instance_of?(Array) && list.size.between?(1, 24)
        months = []
        list = list.map do |value|
          raise Invalid unless value.instance_of?(Hash) && value.size == 3
          item = value.transform_keys { |key| key.instance_of?(Symbol) ? key.to_s : key }
          raise Invalid unless item.keys.sort == %w[id not_after not_before]
          CheckoutReceipt.send(:text!, item["id"], 256)
          %w[not_before not_after].each { |field| CheckoutReceipt.send(:epoch!, item[field]) }
          raise Invalid unless pair.fetch(:not_before) <= item["not_before"] && item["not_before"] < item["not_after"] && item["not_after"] <= pair.fetch(:not_after)
          start = Time.at(item.fetch("not_before")).utc
          finish = start.month == 12 ? Time.utc(start.year + 1, 1, 1).to_i : Time.utc(start.year, start.month + 1, 1).to_i
          raise Invalid unless item.fetch("not_after") <= finish
          months << [start.year, start.month]
          item
        end.sort_by { |value| value.fetch("not_before") }
        raise Invalid unless months.uniq.size == months.size && list.map { |value| value.fetch("id") }.uniq.size == list.size &&
          list.each_cons(2).all? { |left,right| left.fetch("not_after") <= right.fetch("not_before") }
        list
      end
      def insert_root!(ids, key, pair)
        @db.execute("INSERT INTO ap2_long_roots(tenant,root_reference,series_key,contract,active) VALUES (?,?,?,?,1)",
          [ids[0], pair.fetch(:reference), key, encode_contract!(pair_contract(pair))])
      rescue SQLite3::ConstraintException
        raise Conflict
      end
      def series_row!(ids)
        row = @db.get_first_row("SELECT CASE WHEN length(CAST(contract AS BLOB))<=#{MAX_CONTRACT} THEN contract END,active,uses,spent FROM ap2_series WHERE series_key=?", [series_key(ids)])
        raise Invalid unless row
        contract = decode!(row[0], MAX_CONTRACT)
        raise Unavailable unless [row[2],row[3]].all? { |n| n.instance_of?(Integer) && n >= 0 } &&
          row[2] <= contract.fetch("max_occurrences") && row[3] <= contract.fetch("budget_max")
        [contract, *row.drop(1)]
      end
      def current_root!(ids, expected = nil)
        row = @db.get_first_row("SELECT root_reference,epoch,CASE WHEN length(CAST(authority AS BLOB))<=32768 THEN authority END,authority_active FROM ap2_long_state WHERE series_key=?", [series_key(ids)])
        raise Invalid unless row
        raise Unavailable unless row[1].instance_of?(Integer) && row[1].between?(1, 9_007_199_254_740_000) && [0,1].include?(row[3])
        raise Conflict if !expected.nil? && (!expected.instance_of?(Integer) || row[1] != expected)
        state = {"root_reference" => row[0], "epoch" => row[1], "authority" => InputValidator.snapshot!(row[2], max_bytes: 32768), "authority_active" => row[3]}
        root = @db.get_first_row("SELECT CASE WHEN length(CAST(contract AS BLOB))<=#{MAX_CONTRACT} THEN contract END,active FROM ap2_long_roots WHERE tenant=? AND root_reference=? AND series_key=?",
          [ids[0], row[0], series_key(ids)])
        raise Unavailable unless root && [0,1].include?(root[1])
        [state, decode!(root[0], MAX_CONTRACT).merge("active" => root[1])]
      end
      def approval_policy!(profile)
        raise Invalid unless LongPayment.profile?(profile)
      end
      def period!(ids, at, occurrence)
        CheckoutReceipt.send(:epoch!, at)
        rows = @db.execute("SELECT period_id,not_before,not_after FROM ap2_long_periods WHERE series_key=? AND not_before<=? AND ?<not_after", [series_key(ids), at, at])
        raise Invalid unless rows.size == 1 && rows[0][0] == occurrence
        rows[0]
      end
      def validate_reservation!(scope, record)
        approval_policy!(record.fetch("profile_ref"))
        ids = scope_series(scope)
        agreement, active = series_row!(ids)
        state, root = current_root!(ids)
        raise Invalid unless active == 1 && root.fetch("active") == 1 && state.fetch("authority_active") == 1 &&
          PaymentAcceptance.canonical(record.fetch("authority_binding")) == state.fetch("authority")
        wire = record.fetch("signed_wires").fetch("payment").fetch("open_sd_jwt")
        raise Conflict unless Payment.send(:digest, wire.split("~",2).first) == state.fetch("root_reference")
        period = period!(ids, record.fetch("accepted_at"), scope.fetch("occurrence_id"))
        amount = record.fetch("payment").fetch("payment_amount")
        raise Invalid unless amount.fetch("currency") == "JPY" && amount.fetch("amount").instance_of?(Integer) && amount.fetch("amount") > 0
        record["accepted_epoch"] = state.fetch("epoch")
        record["valid_until"] = [record.fetch("valid_until"), period[2], agreement.fetch("agreement_not_after"), root.fetch("not_after")].min
      end
      def validate_start!(record, at)
        ids = scope_series(record.fetch("scope"))
        agreement, active = series_row!(ids)
        state, root = current_root!(ids)
        raise Invalid unless active == 1 && root.fetch("active") == 1 && state.fetch("authority_active") == 1 &&
          state.fetch("epoch") == record.fetch("accepted_epoch") && at < agreement.fetch("agreement_not_after") && at < root.fetch("not_after")
        period!(ids, at, record.fetch("scope").fetch("occurrence_id"))
      end
      def validate_current_authority!(record, _at, authority)
        state, = current_root!(scope_series(record.fetch("scope")))
        raise Invalid unless authority && PaymentAcceptance.canonical(authority) == state.fetch("authority") &&
          PaymentAcceptance.canonical(record.fetch("authority_binding")) == state.fetch("authority")
      end

      %i[authorize_series! update_authority! invalidate_authority! replace_root! revoke_root! usage start_long!].each do |name|
        implementation = instance_method(name)
        required = implementation.parameters.map(&:last).freeze
        define_method(name) do |**arguments|
          if name == :start_long!
            ticket = arguments.fetch(:ticket)
            raise Invalid unless ticket.instance_of?(Ticket)
            arguments = PaymentAcceptance.copy!(arguments.reject { |key,_| key == :ticket }).merge(ticket: ticket)
          else
            arguments = PaymentAcceptance.copy!(arguments)
          end
          raise Invalid unless arguments.keys.sort == required.sort
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
