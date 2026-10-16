"""Static/mock-only six-case report adapter, not an executable experiment.

Existing builder/Oracle/Ruby observer remain unchanged. Their intentional
HOLD/exit1 is accepted only with complete, bound, exact report contents.
No subprocess, socket, Docker, signing, installation or output-file backend.
Supplied reports and isolation receipts never attest their own provenance.
"""
import importlib.util
from pathlib import Path

# Load only this PR's pure local validator; never import the experiment code.
spec = importlib.util.spec_from_file_location(
    "p1r_static_prepare", Path(__file__).with_name("p1r_prepare.py"))
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)
need, sha, document = prepare.need, prepare.sha, prepare.document
CASES = prepare.CASES
CLASSES = dict(zip(CASES, ("FULL", "MISSING", "UNKNOWN_SLOT", "DUPLICATE", "UNUSED", "MISSING")))
STAGES = ["G0_PREAUTH_BOUNDS", "G1_HOST_TRUST_SNAPSHOT", "G2_ISSUER_ROOT_AUTHENTICITY",
          "G3_ROOT_ORIGINAL_SD_CLOSURE", "G4_AGENT_AND_MERCHANT_CRYPTO_BINDING",
          "G5_OFFICIAL_SCHEMA_AND_LOCAL_SHAPE"]


def public_policy(policy):
    for name in ("issuer_public_jwk", "expected_agent_public_jwk", "trusted_merchant_public_jwk"):
        key = policy.get(name)
        need(type(key) is dict and set(key) == {"kty", "crv", "x", "y"} and
             key["kty"] == "EC" and key["crv"] == "P-256" and
             all(type(key[k]) is str and 1 <= len(key[k]) <= 128 for k in key),
             "PUBLIC_POLICY_KEY_SHAPE")
    need(policy.get("tenant_scope") == "synthetic-e01s" and
         policy.get("profile_ref") == "e01s-fixed-a-v1", "SYNTHETIC_POLICY_ONLY")


def statuses(receipt):
    need(type(receipt) is dict and set(receipt) == {
        "builder_exit", "oracle_exit", "ruby_exit", "timed_out", "children_reaped",
        "builder_seconds", "oracle_seconds", "ruby_seconds", "batch_seconds"},
        "PROCESS_RECEIPT_SHAPE")
    need(all(type(receipt[k]) is int for k in ("builder_exit", "oracle_exit", "ruby_exit")) and
         receipt["builder_exit"] == 0 and receipt["oracle_exit"] == 1 and
         receipt["ruby_exit"] == 1 and receipt["timed_out"] is False and
         receipt["children_reaped"] is True, "PROCESS_FAILURE_OR_TIMEOUT")
    need(all(type(receipt[k]) in (int, float) and
             0 <= receipt[k] <= prepare.CEILINGS["child_seconds"]
             for k in ("builder_seconds", "oracle_seconds", "ruby_seconds")) and
         type(receipt["batch_seconds"]) in (int, float) and
         sum(receipt[k] for k in ("builder_seconds", "oracle_seconds", "ruby_seconds")) <=
         receipt["batch_seconds"] <= prepare.CEILINGS["batch_seconds"], "PROCESS_TIME_LIMIT")


def compare_mock_reports(*, fixture_raw, policy_raw, oracle_raw, ruby_raw, receipt):
    statuses(receipt)
    fixture = document(fixture_raw, 262144)
    policy = document(policy_raw, 16384)
    oracle = document(oracle_raw, 65536)
    ruby = document(ruby_raw, 65536)
    public_policy(policy)
    need(set(fixture) == {"ap2_commit", "cases"} and
         fixture["ap2_commit"] == prepare.AP2 and type(fixture["cases"]) is dict and
         set(fixture["cases"]) == set(CASES), "SIX_CASE_FIXTURE_SHAPE")
    need(set(oracle) == {"case_id", "pinned_ap2_sha", "fixture_sha256", "policy_sha256",
         "cases", "oracle_scope", "o2_agent_merchant", "o4_schema", "o5_ruby_stage",
         "host_authority", "e03_e04_exit_gate", "conclusion"}, "ORACLE_REPORT_SHAPE")
    need(oracle["case_id"] == "E03E04_A_SOURCE_ONLY_ORACLE" and
         oracle["pinned_ap2_sha"] == prepare.AP2 and
         oracle["fixture_sha256"] == sha(fixture_raw) and
         oracle["policy_sha256"] == sha(policy_raw) and
         oracle["oracle_scope"] == "O1_ISSUER_ONLY_O3_ORIGINAL_ROOT_GRAPH" and
         oracle["o2_agent_merchant"] == "NOT_CHECKED" and oracle["o4_schema"] == "NOT_CHECKED" and
         oracle["o5_ruby_stage"] == "NOT_RUN" and oracle["host_authority"] == "NOT_ESTABLISHED" and
         oracle["e03_e04_exit_gate"] == "UNPROVEN" and
         oracle["conclusion"] == "HOLD_NO_PHASE2B_OR_PAYMENT_AUTHORIZATION", "ORACLE_BINDING_OR_AUTHORITY")
    need(set(ruby) == {"case_id", "status", "stage_expectations_match", "source_provenance",
         "host_g1_authority", "o1_o3_oracle_source", "o2_o4_independent", "g6_g7",
         "pinned_ap2_sha", "fixture_sha256", "policy_sha256", "oracle_sha256", "cases",
         "e03_e04_exit_gate", "conclusion"}, "RUBY_REPORT_SHAPE")
    need(ruby["case_id"] == "E03E04_A_RUBY_G3_STAGE_OBSERVER" and ruby["status"] == "HOLD" and
         ruby["stage_expectations_match"] is True and ruby["pinned_ap2_sha"] == prepare.AP2 and
         ruby["fixture_sha256"] == sha(fixture_raw) and ruby["policy_sha256"] == sha(policy_raw) and
         ruby["oracle_sha256"] == sha(oracle_raw) and
         ruby["source_provenance"] == "UNVERIFIED_EXTERNAL_RUNNER" and
         ruby["host_g1_authority"] == "NOT_ESTABLISHED" and
         ruby["o1_o3_oracle_source"] == "EXTERNAL_UNATTESTED_CLAIM" and
         ruby["o2_o4_independent"] == "NOT_CHECKED" and ruby["g6_g7"] == "HOLD_NOT_WIRED" and
         ruby["e03_e04_exit_gate"] == "UNPROVEN" and
         ruby["conclusion"] == "NOT_A_PAYMENT_OR_PHASE2B_AUTHORIZATION", "RUBY_BINDING_OR_AUTHORITY")
    need(type(oracle["cases"]) is dict and type(ruby["cases"]) is dict and
         set(oracle["cases"]) == set(ruby["cases"]) == set(CASES), "SIX_CASE_REPORT_SET")
    compacts = {}
    for name in CASES:
        case, expected, observed = fixture["cases"][name], oracle["cases"][name], ruby["cases"][name]
        need(type(case) is dict and set(case) == {"root", "terminal"}, "CASE_WIRE_SHAPE")
        for key in ("root", "terminal"):
            value = case[key]
            need(type(value) is str and value.isascii() and 0 < len(value) <= 32768, "CASE_WIRE_LIMIT")
        root_hash, term_hash = sha(case["root"].encode()), sha(case["terminal"].encode())
        compacts[name] = case["root"].split("~", 1)[0]
        need(type(expected) is dict and set(expected) == {
             "issuer_signature", "root_wire_sha256", "terminal_wire_sha256",
             "graph_class", "expected_g3", "g1_authority"}, "ORACLE_CASE_SHAPE")
        need(expected["issuer_signature"] == "VALID_UNDER_SYNTHETIC_POLICY_KEY" and
             expected["root_wire_sha256"] == root_hash and expected["terminal_wire_sha256"] == term_hash and
             expected["graph_class"] == CLASSES[name] and expected["g1_authority"] == "NOT_ESTABLISHED" and
             expected["expected_g3"] == ("PASS_CONDITIONAL" if name == "FULL" else "REJECT"),
             "ORACLE_CASE_MISMATCH")
        need(type(observed) is dict and set(observed) == {
            "status", "first_reject_stage", "completed_stages", "reason_class",
            "matched_causal_stage", "root_wire_sha256"}, "RUBY_CASE_SHAPE")
        need(observed["root_wire_sha256"] == root_hash and observed["matched_causal_stage"] is True and
             observed["reason_class"] == "EXPECTED_STAGE" and
             observed["status"] == ("HOLD" if name == "FULL" else "REJECT") and
             observed["first_reject_stage"] == (None if name == "FULL" else STAGES[3]) and
             observed["completed_stages"] == (STAGES if name == "FULL" else STAGES[:3]),
             "CAUSAL_STAGE_MISMATCH")
    need(len({fixture["cases"][name]["root"] for name in CASES}) == len(CASES) and
         compacts["HIDDEN"] == compacts["EXTRA"] == compacts["FULL"] and
         len({compacts[name] for name in ("FULL", "UNKNOWN", "DUPLICATE", "DECOY")}) == 4,
         "SIGNED_VARIANT_IDENTITY")
    # This function only compares caller-supplied mock records. It performs
    # no signature check and proves neither execution nor external provenance.
    return {"status": "HOLD", "mock_report_consistency": True,
            "actual_six_case_execution": False, "source_runtime_attestation": "UNPROVEN",
            "independent_o2_o4": "NOT_CHECKED", "g6_g7": "HOLD_NOT_WIRED",
            "phase2_gate": "UNPROVEN", "phase2b": "HOLD"}


def orchestrate_mock_reports(port, cleanup):
    """Sequence only injected mock operations; no executable process adapter.

    Caller-supplied timing/reaping claims cannot establish OS enforcement.
    No retry, live command, signer or external input resolution exists here.
    """
    outputs, receipt = {}, {}
    try:
        for operation, expected_exit, cap in (("builder", 0, 278528),
                                              ("oracle", 1, 65536), ("ruby", 1, 65536)):
            request = {"operation": operation, "inputs": dict(outputs), "retry": 0,
                       "network": "none", "timeout_seconds": 10, "output_cap": cap}
            result = port(request)
            need(type(result) is dict and set(result) ==
                 {"exit", "seconds", "timed_out", "children_reaped", "outputs"}, "MOCK_PORT_SHAPE")
            need(type(result["exit"]) is int and result["exit"] == expected_exit and
                 result["timed_out"] is False and result["children_reaped"] is True and
                 type(result["seconds"]) in (int, float) and
                 0 <= result["seconds"] <= 10, "MOCK_PORT_FAILURE")
            names = {"fixture_raw": 262144, "policy_raw": 16384} if operation == "builder" else {
                operation + "_raw": cap}
            need(type(result["outputs"]) is dict and set(result["outputs"]) == set(names),
                 "MOCK_OUTPUT_SHAPE")
            for name, limit in names.items():
                raw = result["outputs"][name]
                need(type(raw) is bytes and 0 < len(raw) <= limit, "MOCK_OUTPUT_BOUND")
                document(raw, limit)
                outputs[name] = raw
            receipt[operation + "_exit"] = result["exit"]
            receipt[operation + "_seconds"] = result["seconds"]
        receipt.update(timed_out=False, children_reaped=True,
                       batch_seconds=sum(receipt[k + "_seconds"] for k in ("builder", "oracle", "ruby")))
        report = compare_mock_reports(**outputs, receipt=receipt)
    except BaseException as primary:
        try:
            need(cleanup() is True, "MOCK_CLEANUP_FAILURE")
        except BaseException:
            primary.add_note("MOCK_CLEANUP_UNCERTAIN")
        raise
    else:
        need(cleanup() is True, "MOCK_CLEANUP_FAILURE")
    return report


if __name__ == "__main__":
    print('{"status":"STATIC_ONLY_EXECUTION_HOLD","reason":"NO_LIVE_RUNNER_BACKEND"}')
    raise SystemExit(78)
