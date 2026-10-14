# frozen_string_literal: true
#
# E06-I/A. Research-only offline schema gate. NOT an AP2 verifier or authorization.
# The caller MUST authenticate the original Issuer/Agent/Merchant signed wires
# and finish the full SD-JWT commitment closure before calling check!.
#
# Approval A only: declaring this class is not a signed-fixture experiment or CI.
require "json"
require "digest"
require "uri"

module AP2E06ISchemaGate
  PINNED_AP2 = "b4587ac1d055888a73b4b21750973cffba961793"
  DRAFT = "https://json-schema.org/draft/2020-12/schema"
  MERCHANT_URI = "https://ap2-protocol.org/schemas/types/merchant.json"

  # Git blob digests of the original three files AT PINNED_AP2, not of
  # generated or locally modified schema copies.
  FILES = {
    "open" => {
      path: "open_checkout_mandate.json",
      id: "https://ap2-protocol.org/schemas/open_checkout_mandate",
      blob: "e3d9cafa7311d90612c7f908ae9b8821ddc8735a"
    },
    "closed" => {
      path: "checkout_mandate.json",
      id: "https://ap2-protocol.org/schemas/checkout_mandate.json",
      blob: "8755db60a1c6e15f49cfe6c9a5dee6838d2f379d"
    },
    "merchant" => {
      path: "types/merchant.json",
      id: MERCHANT_URI,
      blob: "2e44a4dc943c009af106e7103e9e30f4e556b98c"
    }
  }.freeze

  class Rejected < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  class Gate
    attr_reader :fingerprints

    def initialize(upstream_root:)
      raise Rejected, "verification_unavailable" unless
        upstream_root.is_a?(String) && !upstream_root.empty?
      # Load only the review-pinned library at the verification boundary.
      # Missing/other-version gems are reported as unavailable, not as a
      # startup exception or a schema-invalid signed Mandate verdict.
      begin
        gem "json_schemer", "= 2.5.0"
        require "json_schemer"
      rescue LoadError, Gem::LoadError
        raise Rejected, "verification_unavailable"
      end
      spec = Gem.loaded_specs["json_schemer"]
      raise Rejected, "verification_unavailable" unless
        spec && spec.version.to_s == "2.5.0"

      root = File.realpath(upstream_root)
      directory = File.join(root, "code/sdk/schemas/ap2")
      prefix = File.realpath(directory) + File::SEPARATOR
      schemas = {}
      fingerprints = {}

      FILES.each do |label, expected|
        pathname = File.join(directory, expected.fetch(:path))
        # The path is never trusted merely because a prior File.size passed.
        # Descriptor-scoped reads cap memory even if a peer grows the file.
        raw = bounded_pinned_schema_bytes!(pathname, prefix: prefix)
        git_blob = Digest::SHA1.hexdigest("blob #{raw.bytesize}\0".b + raw.b)
        raise Rejected, "verification_unavailable" unless
          git_blob == expected.fetch(:blob)
        schema = JSON.parse(raw)
        raise Rejected, "verification_unavailable" unless
          schema.is_a?(Hash) &&
          schema["$id"] == expected.fetch(:id) &&
          schema["$schema"] == DRAFT

        schemas[label] = schema
        fingerprints[label] = {
          "git_blob" => git_blob,
          "sha256" => Digest::SHA256.hexdigest(raw),
          "id" => expected.fetch(:id)
        }.freeze
      end

      # The sole network-looking URI resolves strictly from the already
      # SHA-verified merchant schema. No HTTP client or remote fallback.
      resolver = lambda do |uri|
        raise Rejected, "verification_unavailable" unless
          uri.to_s == MERCHANT_URI
        schemas.fetch("merchant")
      end

      @open = JSONSchemer.schema(schemas.fetch("open"), ref_resolver: resolver)
      @closed = JSONSchemer.schema(schemas.fetch("closed"), ref_resolver: resolver)
      @fingerprints = fingerprints.freeze
    rescue Rejected
      raise
    rescue StandardError
      # Missing checkout, damaged schema, unknown/ambiguous references, local
      # permissions, invalid JSON or unexpected library failure all STOP.
      raise Rejected, "verification_unavailable"
    end

    # No auth claims! Passing Ruby Schema means only schema-valid JSON.
    # Merchant nested objects are checked by the Open schema's $ref.
    def check!(open:, closed:)
      raise Rejected, "invalid_open_schema" unless
        open.is_a?(Hash) && @open.valid?(open)
      raise Rejected, "invalid_closed_schema" unless
        closed.is_a?(Hash) && @closed.valid?(closed)
      { "open" => "VALID", "closed" => "VALID", "merchant_ref" => "LOCAL_PINNED" }
    rescue Rejected
      raise
    rescue StandardError
      raise Rejected, "verification_unavailable"
    end

    private

    # Only the three allowlisted, SHA-pinned local Schema files reach here.
    # O_NOFOLLOW prevents leaf-symlink replacement; O_NONBLOCK prevents a
    # swapped FIFO from hanging before fstat establishes a regular file.
    # If the platform lacks these flags, fail closed (initialize rescues).
    # We do NOT rely on pathname File.size followed by unbounded File.binread.
    def bounded_pinned_schema_bytes!(pathname, prefix:)
      actual = File.realpath(pathname)
      before_path = File.lstat(pathname)
      raise Rejected, "verification_unavailable" unless
        actual.start_with?(prefix) &&
        before_path.file? && before_path.size.between?(1, 32_768)

      flags = File::RDONLY | File::NOFOLLOW | File::NONBLOCK
      File.open(pathname, flags) do |file|
        file.binmode
        before_fd = file.stat
        raise Rejected, "verification_unavailable" unless
          same_file_snapshot?(before_path, before_fd) &&
          File.realpath(pathname) == actual

        # This read is bounded *on the opened descriptor*, never by a
        # pathname size check. 32_769 is the single-byte overflow sentinel.
        raw = file.read(32_769)
        after_fd = file.stat
        after_path = File.lstat(pathname)
        raise Rejected, "verification_unavailable" unless
          raw.is_a?(String) && raw.bytesize.between?(1, 32_768) &&
          raw.bytesize == before_fd.size &&
          same_file_snapshot?(before_fd, after_fd) &&
          same_file_snapshot?(after_fd, after_path) &&
          File.realpath(pathname) == actual &&
          actual.start_with?(prefix)
        raw.b
      end
    end

    # Compare the opened inode with both pathname observations and recheck
    # stable metadata before accepting content. The fixed Git blob digest,
    # checked by the caller next, protects against equal-size byte mutation.
    def same_file_snapshot?(left, right)
      left.file? && right.file? &&
        left.dev == right.dev && left.ino == right.ino &&
        left.mode == right.mode && left.nlink == right.nlink &&
        left.uid == right.uid && left.gid == right.gid &&
        left.size == right.size && left.mtime == right.mtime &&
        left.ctime == right.ctime
    end
  end
end
