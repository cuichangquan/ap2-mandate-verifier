# frozen_string_literal: true
# Ruby-only synthetic application: no network, Rails, A2A or real payment.
require "ap2_mandate_verifier"
require "json"
require_relative "integration/inputs"
require_relative "integration/processor"
module RubyIntegration
  M = AP2MandateVerifier
  A = M::PaymentAcceptance
  NOW = 1_800_000_000 # Explicit virtual clock. NEVER use this clock in a real app.
  SCENARIOS = %w[success error pause-before-start expired-before-start crash-before-start crash-after-start crash-after-charge unknown delayed].freeze
  class App
    def self.init(directory)
      # Partial bootstrap is a STOP. Never delete/recreate an existing directory.
      Dir.mkdir(directory, 0o700)
      data = Inputs.bootstrap(now: NOW)
      File.open(File.join(directory, "app.json"), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.generate(data)); file.flush; file.fsync
      end
      store = A::SQLiteStore.create(path: File.join(directory, "acceptance.sqlite3"))
      store.authorize!(**data.fetch("scope").transform_keys(&:to_sym), mode: :conditional,
        profile_ref: M::Payment::PROFILE_REF, checkout: data.fetch("checkout"),
        payment: data.fetch("expected_payment"), receipt_context: data.fetch("receipt_context"))
      store.close
      Processor.create(File.join(directory, "processor.sqlite3"))
      File.open(directory, File::RDONLY) { |file| file.fsync }
      {event: "initialized", sdk_state: "not_reserved", mock_dispatches: 0}
    ensure
      store&.close rescue nil
    end
    def initialize(directory)
      @directory = directory
      @data = current_data
      @scope = @data.fetch("scope").transform_keys(&:to_sym)
      @store = A::SQLiteStore.new(path: File.join(directory, "acceptance.sqlite3"))
      @service = A::Service.new(store: @store)
      @processor = Processor.new(File.join(directory, "processor.sqlite3"))
    end
    def close
      @processor&.close
      @store&.close
    end
    def current_data
      path = File.join(@directory, "app.json")
      raise "application state unavailable" unless File.file?(path) && File.size(path) <= 131_072
      JSON.parse(File.binread(path))
    end
    def run(scenario)
      raise "unknown scenario" unless SCENARIOS.include?(scenario)
      inputs = Inputs.verification(current_data, now: NOW)
      # Educational check only: accept/start reverify raw CURRENT inputs themselves.
      raise "verification failed" unless M::Payment.verify(**inputs).verified?
      accepted = @service.accept(**@scope, mode: :conditional, verification_inputs: inputs)
      unless accepted.ticket
        require_existing!(accepted)
        return summary("no_new_ticket", accepted)
      end
      crash("reserved_before_start", accepted) if scenario == "crash-before-start"
      # Same-process interruption retains the opaque Ticket. Restart does not.
      if scenario == "pause-before-start"
        @store.close
        @store = A::SQLiteStore.new(path: File.join(@directory, "acceptance.sqlite3"))
        @service = A::Service.new(store: @store)
      end
      fresh = Inputs.verification(current_data, now: scenario == "expired-before-start" ? NOW + 61 : NOW)
      execution = @service.start(ticket: accepted.ticket, verification_inputs: fresh)
      return summary("start_blocked", @service.lookup(**@scope)) unless execution
      crash("started_before_dispatch", @service.lookup(**@scope)) if scenario == "crash-after-start"
      issued_at = scenario == "delayed" ? NOW + 120 : NOW
      receipt = unless scenario == "unknown"
        Inputs.receipt(@data, wire: execution.closed_sd_jwt, outcome: scenario == "error" ? "Error" : "Success", now: issued_at)
      end
      @processor.dispatch(execution, receipt: receipt)
      crash("processor_committed_before_finish", @service.lookup(**@scope)) if scenario == "crash-after-charge"
      if %w[unknown delayed].include?(scenario)
        return summary("awaiting_reconciliation", @service.unknown(ticket: accepted.ticket))
      end
      final = @service.finish(ticket: accepted.ticket, receipt_jwt: receipt, verified_at: NOW)
      raise "Receipt finalization failed" unless %i[receipt_success receipt_error].include?(final.status)
      summary("finished", final)
    end
    def retry(resigned: false)
      fresh = Inputs.verification(current_data, now: NOW)
      fresh[:closed_sd_jwt] = Inputs.resign(@data, now: NOW) if resigned
      previous = @service.lookup(**@scope)
      raise "no existing attempt" unless previous.processor_key
      result = @service.accept(**@scope, mode: :conditional, verification_inputs: fresh)
      raise "retry changed identity" if result.ticket || result.processor_key != previous.processor_key ||
        result.closed_sd_jwt != previous.closed_sd_jwt || result.reference != previous.reference
      summary(resigned ? "resigned_retry" : "exact_retry", result).merge(original_identity_preserved: true)
    end
    def recover
      original = @service.lookup(**@scope)
      require_existing!(original)
      saved = @processor.query(original.processor_key) # QUERY only, never dispatch.
      raise "processor reference mismatch" if saved && saved.fetch("reference") != original.reference
      receipt = saved && saved.fetch("receipt")
      unless receipt
        return summary("operator_reconciliation_required", original).merge(result: "unknown")
      end
      # Receipt window is independent of the expired Mandate/challenge.
      final = @service.reconcile(**@scope, receipt_jwt: receipt, verified_at: NOW + 120)
      raise "recovery changed identity" if final.ticket || (final.processor_key && final.processor_key != original.processor_key)
      raise "Receipt reconciliation failed" unless %i[receipt_success receipt_error].include?(final.status)
      summary("reconciled", final)
    end
    def require_existing!(result)
      raise "attempt unavailable or invalid" unless result.processor_key &&
        %i[pending unknown receipt_success receipt_error].include?(result.status)
    end
    def inspect_state
      result = @service.lookup(**@scope)
      require_existing!(result)
      summary("inspection", result)
    end
    def summary(event, result)
      raise "invalid result state" unless result.processor_key &&
        %i[reserved pending unknown receipt_success receipt_error].include?(result.status)
      value = {event: event, sdk_state: result.status, ticket: !result.ticket.nil?, mock_dispatches: @processor.count}
      if %i[receipt_success receipt_error].include?(result.status)
        value[:receipt_authentic] = true
        value[:reported_outcome] = result.status == :receipt_success ? "Success" : "Error"
      end
      value
    end
    def crash(event, result)
      puts JSON.generate(summary(event, result).merge(simulated_process_exit: 75))
      $stdout.flush
      Process.exit!(75) # No ensure/normal cleanup; next CLI is a different Ruby process.
    end
  end
  def self.cli(args)
    command, directory, option = args
    raise "invalid command" unless args.size.between?(2, 3) && directory &&
      %w[init run recover retry inspect].include?(command) &&
      (command == "run" || command == "retry" || option.nil?) &&
      (command != "retry" || option.nil? || option == "resigned")
    result = if command == "init"
      App.init(directory)
    else
      app = App.new(directory)
      case command
      when "run" then app.run(option || "success")
      when "retry" then app.retry(resigned: option == "resigned")
      when "recover" then app.recover
      when "inspect" then app.inspect_state
      end
    end
    feature = $LOADED_FEATURES.find { |path| path.end_with?("/ap2_mandate_verifier.rb") }
    spec = Gem.loaded_specs["ap2_mandate_verifier"]
    puts JSON.generate(result.merge(sdk_version: spec&.version&.to_s || "source",
      sdk_load: spec && feature.start_with?(spec.full_gem_path + "/") ? "installed_gem" : "repository_lib",
      ruby: RUBY_VERSION, fixture_clock: NOW))
  rescue StandardError, LoadError
    warn "STOP: invalid command or unavailable/inconsistent state; preserve all files and investigate."
    return 1
  ensure
    app&.close
  end
end
exit(RubyIntegration.cli(ARGV) || 0) if $PROGRAM_NAME == __FILE__
