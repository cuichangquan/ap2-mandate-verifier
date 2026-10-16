"""Static/mock-only six-case report adapter, not an executable experiment.

Existing builder/Oracle/Ruby observer remain unchanged. Their intentional
HOLD/exit1 is accepted only with complete, bound, exact report contents.
No subprocess, socket, Docker, signing, installation or output-file backend.
Supplied reports and isolation receipts never attest their own provenance.
"""
import base64
import re
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


POLICY_FIELDS = set("active alg allowed_sd_paths checkout_use_case expected_agent_public_jwk expected_aud expected_checkout_id expected_currency expected_merchant_id expected_nonce expected_total_minor freeze_epoch host_checkout_jwt issuer_public_jwk issuer_ref issuer_thumbprint not_after not_before policy_digest policy_version profile_ref tenant_scope trusted_merchant_public_jwk".split())
PINNED_PATHS = sorted(["$/delegate_payload/0", "$/delegate_payload/0/disclosed/constraints/1/allowed/0",
                       "$/delegate_payload/0/disclosed/constraints/0/items/0/acceptable_items/0"])


def b64(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def decode64(text):
    need(type(text) is str and 0 < len(text) <= 32768 and
         re.fullmatch(r"[A-Za-z0-9_-]+", text), "WIRE_BASE64")
    raw = base64.b64decode(text + "=" * (-len(text) % 4), altchars=b"-_", validate=True)
    need(b64(raw) == text, "WIRE_BASE64_CANONICAL")
    return raw


def bounded_tree(value, depth=0):
    need(depth <= 24, "JSON_DEPTH")
    if type(value) in (dict, list):
        need(len(value) <= (32 if type(value) is dict else 16), "JSON_WIDTH")
        for child in (value.values() if type(value) is dict else value):
            bounded_tree(child, depth + 1)
    return value


def strict_value(raw):
    # Parse one standalone value; never splice untrusted JSON into a wrapper.
    return bounded_tree(prepare.json_value(raw, 32768))


def inspect_compact(compact, typ, cap=32768):
    """Shared standalone JWS envelope for Root, Terminal and checkout."""
    need(type(compact) is str and compact.isascii() and 0 < len(compact) <= cap, "JWS_SIZE")
    jws = compact.split(".")
    need(len(jws) == 3 and len(decode64(jws[2])) == 64, "JWS_SHAPE")
    header, payload = strict_value(decode64(jws[0])), strict_value(decode64(jws[1]))
    need(type(payload) is dict, "SIGNED_PAYLOAD_OBJECT")
    need(type(header) is dict and set(header) <= {"alg", "kid", "typ"} and
         header.get("alg") == "ES256" and header.get("typ") == typ and
         ("kid" not in header or type(header["kid"]) is str), "JOSE_HEADER")
    return header, payload


def inspect_wire(wire, typ):
    """G0 envelope only, no decoded claim/disclosure truth or signature check."""
    need(type(wire) is str and wire.isascii() and 0 < len(wire) <= 32768, "SD_SIZE")
    parts = wire.split("~")
    need(3 <= len(parts) <= 18 and parts[-1] == "", "SD_SEGMENTS")
    inspect_compact(parts[0], typ)
    for disclosure in parts[1:-1]:
        strict_value(decode64(disclosure))
    return parts[0]


def public_policy(policy, raw):
    """Host.load! input shape/digest parity, not Host authority or signature proof."""
    need(set(policy) == POLICY_FIELDS and raw.isascii() and raw.strip() == prepare.wire(policy),
         "POLICY_CANONICAL_FIELDS")
    bounded_tree(policy)
    unsigned = {k: v for k, v in policy.items() if k != "policy_digest"}
    need(policy["policy_digest"] == sha(prepare.wire(unsigned)), "POLICY_DIGEST")
    for name in ("issuer_public_jwk", "expected_agent_public_jwk", "trusted_merchant_public_jwk"):
        key = policy[name]
        need(type(key) is dict and set(key) == {"kty", "crv", "x", "y"} and
             key["kty"] == "EC" and key["crv"] == "P-256" and
             all(type(key[k]) is str and key[k].isascii() and 1 <= len(key[k]) <= 128 for k in key), "PUBLIC_POLICY_KEY_SHAPE")
    import hashlib
    need(policy["issuer_thumbprint"] == b64(hashlib.sha256(prepare.wire(policy["issuer_public_jwk"])).digest()),
         "POLICY_THUMBPRINT")
    fixed = {"tenant_scope": "synthetic-e01s", "checkout_use_case": "checkout-research",
             "issuer_ref": "synthetic-e01s-issuer-A", "profile_ref": "e01s-fixed-a-v1",
             "alg": "ES256", "allowed_sd_paths": PINNED_PATHS}
    need(all(policy[k] == v for k, v in fixed.items()) and policy["active"] is True and
         type(policy["policy_version"]) is int and policy["policy_version"] == 1,
         "SYNTHETIC_POLICY_ONLY")
    epoch = policy["freeze_epoch"]
    need(type(epoch) is int and 61 <= epoch <= 4_102_444_800 - 3600 and type(policy["not_before"]) is int and type(policy["not_after"]) is int and
         policy["not_before"] == epoch - 60 and policy["not_after"] == epoch + 1200,
         "POLICY_VALIDITY_SHAPE")
    need(all(type(policy[k]) is str and policy[k] for k in
             ("expected_aud", "expected_nonce", "expected_checkout_id", "expected_merchant_id", "expected_currency")) and
         type(policy["expected_total_minor"]) is int and policy["expected_total_minor"] > 0 and
         type(policy["host_checkout_jwt"]) is str and 1 <= len(policy["host_checkout_jwt"]) <= 16384,
         "POLICY_CONTEXT")
    inspect_compact(policy["host_checkout_jwt"], "JWT", 16384)


def terminal_binding(root, terminal, policy):
    """Decode unverified signed claims to reject contradictory mock identities.

    This never verifies a signature, disclosure semantics or crypto eligibility.
    """
    import hashlib
    parts = terminal.split("~")
    need(len(parts) == 3 and parts[-1] == "" and parts[1], "TERMINAL_PARTS")
    header, claims = inspect_compact(parts[0], "kb+sd-jwt")
    need(type(claims) is dict, "TERMINAL_CLAIM_OBJECT")
    need(set(header) <= {"alg", "kid", "typ"} and
         ("kid" not in header or type(header["kid"]) is str) and
         header.get("alg") == "ES256" and header.get("typ") == "kb+sd-jwt", "TERMINAL_HEADER_SIGNATURE_SHAPE")
    need(set(claims) <= {"_sd_alg", "aud", "delegate_payload", "iat", "nonce", "sd_hash"} and
         claims.get("_sd_alg") in (None, "sha-256") and
         claims.get("sd_hash") == b64(hashlib.sha256(root.encode("ascii")).digest()) and
         claims.get("aud") == policy["expected_aud"] and claims.get("nonce") == policy["expected_nonce"] and
         type(claims.get("iat")) is int and claims["iat"] == policy["freeze_epoch"] and
         claims.get("delegate_payload") == [{"...": b64(hashlib.sha256(parts[1].encode("ascii")).digest())}],
         "TERMINAL_ROOT_POLICY_BINDING")
    decode64(parts[1])
    return header, {k: v for k, v in claims.items() if k != "sd_hash"}, parts[1]


def qualify_mock_inputs(fixture_raw, policy_raw):
    """Only explicit structural preconditions; crypto/runtime remain UNPROVEN."""
    fixture, policy = document(fixture_raw, 262144), document(policy_raw, 16384)
    public_policy(policy, policy_raw)
    need(set(fixture) == {"ap2_commit", "cases"} and fixture["ap2_commit"] == prepare.AP2 and
         type(fixture["cases"]) is dict and set(fixture["cases"]) == set(CASES), "SIX_CASE_FIXTURE_SHAPE")
    templates, compacts, roots, terminals = [], {}, [], []
    for name in CASES:
        case = fixture["cases"][name]
        need(type(case) is dict and set(case) == {"root", "terminal"}, "CASE_WIRE_SHAPE")
        need(all(type(case[k]) is str and case[k].isascii() and 0 < len(case[k]) <= 32768
                 for k in ("root", "terminal")), "CASE_WIRE_LIMIT")
        compacts[name] = inspect_wire(case["root"], "example+sd-jwt")
        inspect_wire(case["terminal"], "kb+sd-jwt")
        roots.append(case["root"])
        terminals.append(case["terminal"])
        templates.append(terminal_binding(case["root"], case["terminal"], policy))
    need(len(set(roots)) == len(CASES) and len(set(terminals)) == len(CASES) and
         all(t == templates[0] for t in templates) and
         compacts["HIDDEN"] == compacts["EXTRA"] == compacts["FULL"] and
         len({compacts[n] for n in ("FULL", "UNKNOWN", "DUPLICATE", "DECOY")}) == 4,
         "MOCK_CAUSAL_WIRE_IDENTITY")
    return fixture, policy


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
    fixture, policy = qualify_mock_inputs(fixture_raw, policy_raw)
    oracle = document(oracle_raw, 65536)
    ruby = document(ruby_raw, 65536)
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
    for name in CASES:
        case, expected, observed = fixture["cases"][name], oracle["cases"][name], ruby["cases"][name]
        need(type(case) is dict and set(case) == {"root", "terminal"}, "CASE_WIRE_SHAPE")
        for key in ("root", "terminal"):
            value = case[key]
            need(type(value) is str and value.isascii() and 0 < len(value) <= 32768, "CASE_WIRE_LIMIT")
        root_hash, term_hash = sha(case["root"].encode()), sha(case["terminal"].encode())
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
    # This function only compares caller-supplied mock records. It performs
    # no signature check and proves neither execution nor external provenance.
    return {"status": "HOLD", "mock_report_consistency": True,
            "input_preconditions": "POLICY_SHAPE_DIGEST_AND_UNVERIFIED_TERMINAL_BINDING_ONLY",
            "cryptographic_eligibility": "UNPROVEN",
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
            if operation == "builder":
                qualify_mock_inputs(outputs["fixture_raw"], outputs["policy_raw"])
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
