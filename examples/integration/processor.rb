# frozen_string_literal: true
gem "sqlite3", "= 2.10.2"
require "sqlite3"
module RubyIntegration
  # Separate mock processor ledger: a committed row IS the synthetic side effect.
  # This is not atomicity between an external PSP and an application's database.
  class Processor
    SCHEMA = "CREATE TABLE results (processor_key TEXT PRIMARY KEY, reference TEXT NOT NULL, receipt TEXT)"
    def self.create(path)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.fsync }
      db = SQLite3::Database.new(path, flags: SQLite3::Constants::Open::READWRITE)
      db.execute(SCHEMA)
      db.close
    end
    def initialize(path)
      @db = SQLite3::Database.new(path, flags: SQLite3::Constants::Open::READWRITE)
      raise "mock storage unavailable" unless @db.get_first_value("PRAGMA quick_check") == "ok" &&
        @db.get_first_value("SELECT sql FROM sqlite_master WHERE name='results'") == SCHEMA
      @db.busy_timeout = 5000
      @db.execute("PRAGMA synchronous=FULL")
    end
    def dispatch(execution, receipt:)
      @db.transaction(:immediate) do
        old = query(execution.processor_key)
        if old
          raise "mock reference conflict" unless old.fetch("reference") == execution.reference
        else
          @db.execute("INSERT INTO results VALUES (?,?,?)", [execution.processor_key, execution.reference, receipt])
        end
      end
    end
    def query(key)
      row = @db.get_first_row("SELECT reference,receipt FROM results WHERE processor_key=?", [key])
      row && {"reference" => row[0], "receipt" => row[1]}
    end
    def count = @db.get_first_value("SELECT count(*) FROM results")
    def close = @db.close
  end
end
