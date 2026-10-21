# frozen_string_literal: true

module AP2MandateVerifier
  # Pinned AP2 b4587ac1 / DC04 exact-three-array-commitments profile only.
  # Whole original Root graph, including all disclosed subtrees, is inspected.
  module RootDisclosures
    MAX_DISCLOSURES = 16
    MAX_SEGMENT_BYTES = 8_192
    PATHS = [
      ["delegate_payload", 0],
      ["delegate_payload", 0, "disclosed", "constraints", 1, "allowed", 0],
      ["delegate_payload", 0, "disclosed", "constraints", 0, "items", 0, "acceptable_items", 0]
    ].map { |path| path.map { |part| part.freeze }.freeze }.freeze

    class Rejected < RootSignature::Rejected; end

    def self.check!(source, issuer_pem)
      verified_root!(source, issuer_pem)
      nil
    end

    # Internal handoff only: signature and entire closure are verified first.
    # AP2 semantics, constraints and Host authorization remain unvalidated.
    def self.verified_root!(source, issuer_pem)
      wire = InputValidator.snapshot!(source)
      raise Rejected, :invalid_root_presentation unless wire.ascii_only? && wire.end_with?("~")
      parts = wire.split("~", -1)
      raise Rejected, :invalid_root_presentation unless parts.size.between?(3, MAX_DISCLOSURES + 2) &&
        parts.last == "" && !parts.first.empty? && parts[1...-1].none?(&:empty?)
      # No disclosure decode, digest graph or trusted claims before signature.
      payload = RootSignature.verified_payload!(parts.first, issuer_pem)
      raise Rejected, :unsupported_disclosure_profile unless
        (payload.keys - %w[delegate_payload _sd_alg]).empty? &&
        (!payload.key?("_sd_alg") || payload["_sd_alg"] == "sha-256") &&
        payload["delegate_payload"].instance_of?(Array) && payload["delegate_payload"].size == 1
      require "digest"
      mapping = {}
      parts[1...-1].each do |part|
        raise Rejected, :disclosure_limit_exceeded if part.bytesize > MAX_SEGMENT_BYTES
        decoded = InputValidator.parse!(decode!(part))
        raise Rejected, :unsupported_disclosure_profile unless decoded.instance_of?(Array) &&
          decoded.size == 2 && decoded[0].instance_of?(String) &&
          decoded[0].bytesize.between?(8, 128) && decoded[1].instance_of?(Hash)
        digest = Base64.urlsafe_encode64(Digest::SHA256.digest(part), padding: false)
        raise Rejected, :duplicate_disclosure if mapping.key?(digest)
        mapping[digest] = decoded[1]
      end
      used = {}
      observed = []
      budget = [0]
      resolved = walk!(payload, [], mapping, used, observed, budget, 1)
      raise Rejected, :unsupported_disclosure_profile unless observed.sort_by(&:to_s) == PATHS.sort_by(&:to_s)
      raise Rejected, :extra_disclosure unless used.size == mapping.size
      resolved
    end

    def self.walk!(value, path, mapping, used, observed, budget, depth)
      budget[0] += 1
      raise Rejected, :disclosure_limit_exceeded if budget[0] > 2_048 ||
        (depth > 24 && (value.instance_of?(Hash) || value.instance_of?(Array)))
      case value
      when Hash
        raise Rejected, :unsupported_disclosure_profile if value.key?("_sd") || value.key?("...") ||
          (path != [] && value.key?("_sd_alg"))
        raise Rejected, :disclosure_limit_exceeded if value.size > 32
        value.to_h { |key, child| [key, walk!(child, path + [key], mapping, used, observed, budget, depth + 1)] }
      when Array
        raise Rejected, :disclosure_limit_exceeded if value.size > 16
        value.each_with_index.map do |item, index|
          here = path + [index]
          if item.instance_of?(Hash) && item.key?("...")
            raise Rejected, :unsupported_disclosure_profile unless item.keys == ["..."] && PATHS.include?(here)
            digest = item["..."]
            raise Rejected, :invalid_disclosure unless digest.instance_of?(String) &&
              digest.bytesize == 43 && decode!(digest).bytesize == 32
            raise Rejected, :duplicate_commitment if used.key?(digest)
            raise Rejected, :missing_disclosure unless mapping.key?(digest)
            used[digest] = true
            observed << here
            walk!(mapping.fetch(digest), here + ["disclosed"], mapping, used, observed, budget, depth + 1)
          else
            walk!(item, here, mapping, used, observed, budget, depth + 1)
          end
        end
      else
        value
      end
    end

    def self.decode!(part)
      raise Rejected, :invalid_disclosure unless part.match?(/\A[A-Za-z0-9_-]+\z/)
      raw = Base64.urlsafe_decode64(part + "=" * (-part.bytesize % 4))
      raise Rejected, :invalid_disclosure unless Base64.urlsafe_encode64(raw, padding: false) == part
      raw
    rescue ArgumentError
      raise Rejected, :invalid_disclosure
    end
    private_class_method :walk!, :decode!
  end
end
