# frozen_string_literal: true

module AP2MandateVerifier
  # Explicit, narrower operational-plan profile. No scheduling or QWAC proof.
  module PaymentPolicy
    PROFILE_REF = "ap2.payment.pisp_execution.complete.1".freeze
    SELECTIVE_PROFILE_REF = "ap2.payment.pisp_execution.selective.1".freeze
    FIELDS = %w[pisp execution_date].freeze
    TYPES = %w[payment.allowed_pisps payment.execution_date].freeze
    def self.enabled?(profile)
      [PROFILE_REF, SELECTIVE_PROFILE_REF].include?(profile)
    end
    def self.recurring?(profile) = defined?(RecurringPayment) && RecurringPayment.profile?(profile)
    def self.long?(profile) = defined?(LongPayment) && LongPayment.profile?(profile)
    def self.marked?(profile) = enabled?(profile) || recurring?(profile) || long?(profile)
    def self.profile!(value, selective: false)
      profile = InputValidator.snapshot!(value, max_bytes: 256)
      old, current = selective ? [SelectivePayment::PROFILE_REF, SELECTIVE_PROFILE_REF] : [Payment::PROFILE_REF, PROFILE_REF]
      recurring = defined?(RecurringPayment) && (selective ? RecurringPayment::SELECTIVE_PROFILE_REF : RecurringPayment::PROFILE_REF)
      long = defined?(LongPayment) && !selective && LongPayment::PROFILE_REF
      raise Payment::Invalid unless [old, current, recurring, long].compact.include?(profile)
      profile
    end
    def self.candidate_policy!(profile, policy)
      raise Payment::Invalid unless marked?(profile) ? policy == :independent : policy.nil?
    end
    def self.fields(profile) = Payment::FIELDS + (enabled?(profile) ? FIELDS : [])
    def self.pisp!(value)
      Payment.send(:exact!, value, %w[brand_name domain_name legal_name])
      %w[legal_name brand_name].each { |f| Payment.send(:text!, value[f], 512) }
      domain = value["domain_name"]
      raise Payment::Invalid unless domain.instance_of?(String) && domain.bytesize.between?(1, 253) && domain.ascii_only? &&
        domain.split(".", -1).all? { |label| label.bytesize.between?(1, 63) && label.match?(/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/) }
    end
    # Exact decimal arithmetic; no permissive DateTime parsing/normalization.
    def self.instant!(source)
      value = InputValidator.snapshot!(source, max_bytes: 40)
      m = /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:\d{2})\z/.match(value)
      raise Payment::Invalid unless m
      y, month, day, hour, minute, second = m.captures.first(6).map(&:to_i)
      leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
      days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
      raise Payment::Invalid unless y.between?(1, 9999) && month.between?(1, 12) && day.between?(1, days[month - 1]) &&
        hour.between?(0, 23) && minute.between?(0, 59) && second.between?(0, 59) && m[8] != "-00:00"
      offset = 0
      unless m[8] == "Z"
        oh, om = m[8][1..].split(":").map(&:to_i)
        raise Payment::Invalid unless oh <= 23 && om <= 59
        offset = (oh * 3600 + om * 60) * (m[8][0] == "-" ? -1 : 1)
      end
      # Gregorian days relative to 0001-01-01, with fractional seconds exact.
      before = y - 1
      count = before * 365 + before / 4 - before / 100 + before / 400 + days.first(month - 1).sum + day - 1
      fraction = m[7] ? Rational(m[7].to_i, 10**m[7].size) : 0
      count * 86400 + hour * 3600 + minute * 60 + second - offset + fraction
    end
    def self.details!(value)
      pisp!(value.fetch("pisp")); instant!(value.fetch("execution_date"))
    end
    def self.constraints!(opening)
      cs = opening.fetch("constraints")
      raise Payment::Invalid unless cs.instance_of?(Array) && cs.size.between?(5, 6) && cs.all? { |c| c.instance_of?(Hash) }
      extra = cs.select { |c| TYPES.include?(c["type"]) }
      raise Payment::Invalid unless extra.size.between?(1, 2) && extra.map { |c| c["type"] }.uniq.size == extra.size
      extra.each do |c|
        if c["type"] == TYPES[0]
          Payment.send(:exact!, c, %w[type allowed])
          list = c["allowed"]
          raise Payment::Invalid unless list.instance_of?(Array) && list.size.between?(1, 8) && list.uniq.size == list.size
          list.each { |p| pisp!(p) }
        else
          raise Payment::Invalid unless (c.keys - %w[type not_before not_after]).empty? &&
            c.key?("type") && (c.key?("not_before") || c.key?("not_after"))
          lower = instant!(c["not_before"]) if c.key?("not_before")
          upper = instant!(c["not_after"]) if c.key?("not_after")
          raise Payment::Invalid if lower && upper && lower > upper
        end
      end
      pisp!(opening["pisp"]) if opening.key?("pisp")
      instant!(opening["execution_date"]) if opening.key?("execution_date")
      # Reject already contradictory fixed plans before any signer effects.
      extra.each do |c|
        if c["type"] == TYPES[0] && opening.key?("pisp")
          raise Payment::Invalid unless c["allowed"].include?(opening["pisp"])
        elsif c["type"] == TYPES[1] && opening.key?("execution_date")
          instant = instant!(opening["execution_date"])
          raise Payment::Invalid if c.key?("not_before") && instant < instant!(c["not_before"])
          raise Payment::Invalid if c.key?("not_after") && instant > instant!(c["not_after"])
        end
      end
      opening.reject { |k,_| FIELDS.include?(k) }.merge("constraints" => cs.reject { |c| TYPES.include?(c["type"]) })
    end
    def self.conditions!(opening, closed)
      details!(closed)
      FIELDS.each { |f| raise Payment::Invalid if opening.key?(f) && opening[f] != closed[f] }
      opening.fetch("constraints").each do |c|
        if c["type"] == TYPES[0]
          raise Payment::Invalid unless c["allowed"].include?(closed["pisp"])
        elsif c["type"] == TYPES[1]
          instant = instant!(closed["execution_date"])
          raise Payment::Invalid if c.key?("not_before") && instant < instant!(c["not_before"])
          raise Payment::Invalid if c.key?("not_after") && instant > instant!(c["not_after"])
        end
      end
    end
    # Never fills either expected context from claims or expected_payment.
    def self.context!(profile, trusted_pisp, execution_at)
      unless enabled?(profile)
        raise Payment::Invalid unless trusted_pisp.nil? && execution_at.nil?
        return nil
      end
      pisp = InputBuilder.send(:copy!, trusted_pisp)
      pisp!(pisp)
      [ResearchEvidence.send(:copy_frozen, pisp), instant!(execution_at)].freeze
    end
    def self.bind_context!(value, context)
      raise Payment::Invalid unless value.fetch("pisp") == context[0] && instant!(value.fetch("execution_date")) == context[1]
    end
  end
end
