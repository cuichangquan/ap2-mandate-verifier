# frozen_string_literal: true

# P1-10i: research-only Authority reference guard. NOT a public API or
# authenticated Host proof protocol. The guard directly reads a trusted
# separate Host PostgreSQL for synthetic independent state evidence.
require "pg"
require "json"
require "uri"
require "digest"

STDOUT.sync = true
abort "research guard disabled" unless ENV["P110I_RESEARCH_ONLY"] == "enabled"
scenario = ARGV.fetch(0)
abort "invalid synthetic scenario" unless %w[h01 h02 h03 h04 h05 h06].include?(scenario)
raw = STDIN.read(4097)
abort "invalid research envelope size" unless raw.bytesize.between?(1, 4096)
proof = JSON.parse(raw)
abort "not a JSON object" unless proof.is_a?(Hash)
auth_url = ENV.fetch("P110G_AUTH_URL")
host_url = ENV.fetch("P110G_HOST_URL")
{
  auth_url => "ap2g_authority",
  host_url => "ap2g_host"
}.each do |url, database|
  parsed = URI.parse(url)
  abort "nonresearch URL" unless parsed.host == "127.0.0.1" && parsed.path == "/#{database}"
end

class GuardStop < StandardError
  attr_reader :status
  def initialize(status)
    @status = status
    super(status)
  end
end

def stop!(status)
  raise GuardStop, status
end

def count(db, sql, params)
  Integer(db.exec_params(sql, params).first.fetch("n"))
end

auth = PG.connect(auth_url)
host = PG.connect(host_url)
begin
  [[auth, "ap2g_authority"], [host, "ap2g_host"]].each do |db, name|
    stop!("UNPROVEN") unless db.exec("SELECT current_database()").first.values.first == name
    stop!("UNPROVEN") unless db.exec("SHOW server_version").first.values.first.start_with?("16.")
  end
  stop!("UNPROVEN") if auth.exec("SELECT system_identifier::text FROM pg_control_system()").first.values.first ==
                       host.exec("SELECT system_identifier::text FROM pg_control_system()").first.values.first

  auth.exec("BEGIN")
  auth.exec("SET LOCAL statement_timeout = '9s'")
  auth.exec("SET LOCAL lock_timeout = '6s'")
  expected_id = "reservation_#{scenario}"
  r = auth.exec_params("SELECT * FROM authority_reservations WHERE reservation_id=$1 FOR UPDATE", [expected_id]).first
  stop!("REJECT") unless r && r.fetch("revoke_requested") == "t"

  # This is only an ALLOWLIST check on claimed metadata, NOT host signature
  # or authenticated remote identity. Authenticity is instead simulated
  # through this guarded process's independent, trusted Host DB connection.
  bindings = {
    "host_service_id" => "trusted_synthetic_host",
    "audience" => "synthetic_authority",
    "authority_id" => r.fetch("authority_id"),
    "tenant_id" => r.fetch("tenant_id"),
    "scope" => r.fetch("scope"),
    "reservation_id" => r.fetch("reservation_id"),
    "operation_id" => r.fetch("operation_id"),
    "checkout_id" => r.fetch("checkout_id"),
    "epoch" => Integer(r.fetch("epoch")),
    "nonce_digest" => "synthetic-nonce-digest"
  }
  stop!("REJECT") unless bindings.all? { |key, value| proof[key] == value }
  stop!("REJECT") unless proof["decision_id"].is_a?(String) &&
    /\Adecision_h0[1-6]_1\z/.match?(proof["decision_id"]) &&
    proof["decision_id"] == "decision_#{scenario}_1"
  stop!("REJECT") unless %w[ABORTED COMMITTED].include?(proof["decision"])
  # Fixed-field digest is ONLY a repeat-message fingerprint; not a
  # cryptographic authentication/Host integrity proof.
  stable = (bindings.keys + %w[decision_id decision]).sort.to_h { |key| [key, proof.fetch(key)] }
  digest = Digest::SHA256.hexdigest(JSON.generate(stable))
  old = auth.exec_params(
    "SELECT decision_id,proof_digest,decision FROM authority_proof_receipts WHERE reservation_id=$1",
    [expected_id]
  ).first
  if old
    if old.fetch("decision_id") == proof.fetch("decision_id") &&
       old.fetch("decision") == proof.fetch("decision") &&
       old.fetch("proof_digest") == digest &&
       r.fetch("revoke_effective") == "t"
      auth.exec("COMMIT")
      puts JSON.generate(outcome: "IDEMPOTENT", effective: true)
      exit 0
    end
    stop!("CONFLICT")
  end
  stop!("UNPROVEN") unless r.fetch("state") == "RESERVED" && r.fetch("revoke_effective") == "f"

  # In a REAL external Host these reads cannot be assumed available,
  # authenticated, serializable or anti-rollback. Here they are the explicit
  # lab-only trusted Host observation seam, NOT distributed atomicity.
  h = host.exec_params(<<~SQL, [proof.fetch("checkout_id"), expected_id, proof.fetch("operation_id")]).first
    SELECT * FROM host_checkouts
     WHERE checkout_id=$1 AND reservation_id=$2 AND operation_id=$3
  SQL
  stop!("UNPROVEN") unless h &&
    h.fetch("tenant_id") == r.fetch("tenant_id") &&
    Integer(h.fetch("epoch")) == Integer(proof.fetch("epoch")) &&
    h.fetch("nonce_digest") == proof.fetch("nonce_digest") &&
    Integer(h.fetch("checkout_version")) == 1

  kind = proof.fetch("decision") == "ABORTED" ? "ABORT_DURABLE" : "C_DURABLE"
  event_count = count(host, <<~SQL, [expected_id, proof.fetch("operation_id"), kind])
    SELECT count(*) AS n FROM host_events WHERE reservation_id=$1 AND operation_id=$2 AND kind=$3
  SQL
  stop!("UNPROVEN") unless event_count == 1
  operations = count(host, "SELECT count(*) AS n FROM host_operations WHERE checkout_id=$1", [h.fetch("checkout_id")])
  outbox = count(host, <<~SQL, [h.fetch("checkout_id")])
    SELECT count(*) AS n FROM host_outbox JOIN host_operations USING(operation_id)
     WHERE checkout_id=$1
  SQL
  if proof.fetch("decision") == "ABORTED"
    stop!("UNPROVEN") unless h.fetch("status") == "ABORTED" &&
      h.fetch("nonce_state") == "ISSUED" && operations == 0 && outbox == 0
  else
    stop!("UNPROVEN") unless h.fetch("status") == "COMMITTED" &&
      h.fetch("nonce_state") == "CONSUMED" && operations == 1 && outbox == 1
  end

  auth.exec_params(<<~SQL, [expected_id, proof.fetch("decision_id"), digest, proof.fetch("decision")])
    INSERT INTO authority_proof_receipts(reservation_id,decision_id,proof_digest,decision)
    VALUES ($1,$2,$3,$4)
  SQL
  final_state = proof.fetch("decision") == "ABORTED" ? "FINALIZED_ABORT" : "FINALIZED_COMMIT"
  changed = auth.exec_params(<<~SQL, [final_state, expected_id])
    UPDATE authority_reservations SET state=$1,revoke_effective=true
    WHERE reservation_id=$2 AND revoke_requested=true AND state='RESERVED'
      AND revoke_effective=false RETURNING reservation_id
  SQL
  stop!("UNPROVEN") unless changed.ntuples == 1
  event = proof.fetch("decision") == "ABORTED" ? "R_EFFECTIVE_ABORT" : "R_EFFECTIVE_COMMIT"
  auth.exec_params("INSERT INTO authority_events(reservation_id,kind) VALUES ($1,$2)", [expected_id,event])
  auth.exec("COMMIT")
  puts JSON.generate(outcome: "EFFECTIVE", effective: true)
rescue GuardStop => e
  auth.exec("ROLLBACK") rescue nil
  puts JSON.generate(outcome: e.status, effective: false)
rescue StandardError => e
  auth.exec("ROLLBACK") rescue nil
  warn "P110I_GUARD_ERROR:#{e.class}" # no raw input/SQL/URI leakage
  puts JSON.generate(outcome: "ERROR", effective: false)
  exit 2
ensure
  auth.close unless auth.finished?
  host.close unless host.finished?
end
