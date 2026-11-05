# frozen_string_literal: true

module AP2MandateVerifier
  module PaymentAcceptance
    # Explicit new database, never an automatic rewrite/reset of a v1.5 ledger.
    # Quotas are charged on durable reservation, not on an untrusted Receipt.
    class RecurringSQLiteStore < SQLiteStore
      SCHEMA_VERSION = 2
      SCHEMA = SQLiteStore::SCHEMA.merge(
        "ap2_series" => "CREATE TABLE ap2_series (series_key TEXT PRIMARY KEY, tenant TEXT NOT NULL, merchant TEXT NOT NULL, approval TEXT NOT NULL, root_reference TEXT NOT NULL, contract TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1)), uses INTEGER NOT NULL DEFAULT 0 CHECK(uses>=0), spent INTEGER NOT NULL DEFAULT 0 CHECK(spent>=0), UNIQUE(tenant,root_reference), UNIQUE(tenant,approval))"
      ).freeze
      INDEXES = (SQLiteStore::INDEXES + [
        ["sqlite_autoindex_ap2_series_1", "ap2_series"],
        ["sqlite_autoindex_ap2_series_2", "ap2_series"],
        ["sqlite_autoindex_ap2_series_3", "ap2_series"]
      ]).map(&:freeze).freeze

      def authorize_series!(tenant_id:, merchant_id:, approval_id:, open_sd_jwt:, profile_ref:,
                            trusted_provider_public_key_pem:, expected_agent_public_key_pem:, verified_at:)
        ids = series_ids!(tenant_id, merchant_id, approval_id)
        checked = RecurringPayment.approved_open!(open_sd_jwt: open_sd_jwt, profile_ref: profile_ref,
          trusted_provider_public_key_pem: trusted_provider_public_key_pem,
          expected_agent_public_key_pem: expected_agent_public_key_pem, verified_at: verified_at)
        contract = PaymentAcceptance.canonical({"profile_ref" => profile_ref, "root_reference" => checked.fetch(:reference),
          "opening" => checked.fetch(:opening), "max_occurrences" => checked.fetch(:max_occurrences),
          "budget_max" => checked.fetch(:budget_max), "currency" => checked.fetch(:currency)})
        raise Invalid if contract.bytesize > 131_072
        transaction do
          key = series_key(ids)
          old = @db.get_first_row("SELECT CASE WHEN length(CAST(contract AS BLOB))<=131072 THEN contract END FROM ap2_series WHERE series_key=?", [key])
          raise Conflict if old && old[0] != contract
          unless old
            begin
              @db.execute("INSERT INTO ap2_series(series_key,tenant,merchant,approval,root_reference,contract) VALUES (?,?,?,?,?,?)",
                [key, *ids, checked.fetch(:reference), contract])
            rescue SQLite3::ConstraintException
              raise Conflict
            end
          end
          true # Existing revoked grants are never reactivated or counters reset.
        end
      end

      def revoke_series!(tenant_id:, merchant_id:, approval_id:)
        ids = series_ids!(tenant_id, merchant_id, approval_id)
        transaction do
          @db.execute("UPDATE ap2_series SET active=0 WHERE series_key=?", [series_key(ids)])
          raise Invalid unless @db.changes == 1
          true
        end
      end

      def usage(tenant_id:, merchant_id:, approval_id:)
        ids = series_ids!(tenant_id, merchant_id, approval_id)
        transaction do
          contract, active, uses, spent = series_row!(ids)
          {currency: "JPY", reserved_occurrences: uses, reserved_amount: spent,
            max_occurrences: contract.fetch("max_occurrences"), budget_max: contract.fetch("budget_max"), active: active == 1}.freeze
        end
      end

      private
      def series_ids!(tenant, merchant, approval)
        [tenant, merchant, approval].map { |v| InputValidator.snapshot!(v, max_bytes: 256).tap { |s| CheckoutReceipt.send(:text!, s, 256) } }.freeze
      end
      def series_key(ids) = PaymentAcceptance.digest(PaymentAcceptance.canonical(ids))
      def scope_series(scope) = series_ids!(*scope.values_at("tenant_id", "merchant_id", "approval_id"))
      def series_row!(ids)
        row = @db.get_first_row("SELECT CASE WHEN length(CAST(contract AS BLOB))<=131072 THEN contract END,active,uses,spent FROM ap2_series WHERE series_key=?", [series_key(ids)])
        raise Invalid unless row
        contract = decode!(row[0], 131_072)
        raise Unavailable unless [row[2], row[3]].all? { |v| v.instance_of?(Integer) && v >= 0 } &&
          row[2] <= contract.fetch("max_occurrences") && row[3] <= contract.fetch("budget_max")
        [contract, *row.drop(1)]
      end
      def approval_policy!(profile)
        raise Invalid unless RecurringPayment.profile?(profile)
      end
      def validate_reservation!(scope, record)
        approval_policy!(record.fetch("profile_ref"))
        contract, active = series_row!(scope_series(scope))
        raise Invalid unless active == 1 && contract.fetch("profile_ref") == record.fetch("profile_ref")
        wires = record.fetch("signed_wires").fetch("payment")
        open_wire = wires["open_sd_jwt"] || wires["open_presentation"]
        raise Invalid unless open_wire.instance_of?(String) # Bounded wire was verified by Service.
        # Local series identity uses base64url(SHA256(original issuer JWT)).
        # AP2 Checkout/Receipt references retain their existing exact-wire semantics.
        root_reference = Payment.send(:digest, open_wire.split("~", 2).first)
        raise Conflict unless root_reference == contract.fetch("root_reference")
        amount = record.fetch("payment").fetch("payment_amount")
        raise Invalid unless amount.fetch("currency") == "JPY" && amount.fetch("amount").instance_of?(Integer) && amount.fetch("amount") > 0
      end
      def charge_reservation!(scope, record)
        ids = scope_series(scope)
        contract, active, uses, spent = series_row!(ids)
        amount = record.fetch("payment").fetch("payment_amount").fetch("amount")
        raise Invalid unless active == 1 && uses < contract.fetch("max_occurrences") && spent + amount <= contract.fetch("budget_max")
        @db.execute("UPDATE ap2_series SET uses=uses+1,spent=spent+? WHERE series_key=? AND active=1 AND uses=? AND spent=?",
          [amount, series_key(ids), uses, spent])
        raise Unavailable unless @db.changes == 1
      end
      def validate_start!(record, verified_at)
        contract, active = series_row!(scope_series(record.fetch("scope")))
        raise Invalid unless active == 1 && verified_at < contract.fetch("opening").fetch("exp")
      end

      %i[authorize_series! revoke_series! usage].each do |name|
        implementation = instance_method(name)
        required = implementation.parameters.map(&:last).freeze
        define_method(name) do |**arguments|
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
