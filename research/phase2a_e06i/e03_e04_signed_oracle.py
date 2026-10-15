"""E03/E04 original signed-Root oracle (SOURCE ONLY, NOT RUN).

Synthetic fixed-Issuer AP2 v0.2.0 only. No keys are generated, no network,
no imports from Ruby or the Ruby stage observer. Input has PUBLIC keys only.
Future use requires a separate Approval B, pinned execution environment and
an independently trusted source/runner. This module never grants Host ALLOW.

Proposed later CLI:
  python e03_e04_signed_oracle.py --fixture CASES.json --policy HOST.json \
    --report NEW_ORACLE.json
Fixture shape: {"ap2_commit": PINNED_AP2, "cases": {
    ID: {"root": ORIGINAL_ROOT_SDJWT, "terminal": ORIGINAL_TERMINAL_SDJWT}
}}
IDs are FULL, HIDDEN, UNKNOWN, DUPLICATE, EXTRA, DECOY.
The DECOY case can prove only *ambiguity/unresolved commitment*, not decoy
provenance. Terminal, Checkout, Host, Schema and source attestation remain
outside this O1/O3-only oracle.
"""
import argparse
import base64
import hashlib
import json
import os
import re
import stat
import sys

PINNED_AP2 = "b4587ac1d055888a73b4b21750973cffba961793"
CASES = ("FULL", "HIDDEN", "UNKNOWN", "DUPLICATE", "EXTRA", "DECOY")
EXPECTED = {
    "FULL": "FULL",
    "HIDDEN": "MISSING",
    "UNKNOWN": "UNKNOWN_SLOT",
    "DUPLICATE": "DUPLICATE",
    "EXTRA": "UNUSED",
    "DECOY": "MISSING",  # genuinely indistinguishable from withholding
}
ALLOWED = {
    ("delegate_payload", 0),
    ("delegate_payload", 0, "disclosed", "constraints", 1, "allowed", 0),
    ("delegate_payload", 0, "disclosed", "constraints", 0, "items", 0,
     "acceptable_items", 0),
}
B64 = re.compile(r"\A[A-Za-z0-9_-]+\Z", re.ASCII)
HEX = re.compile(r"\A[0-9a-f]{64}\Z", re.ASCII)


class Stop(Exception):
    pass


def demand(ok, reason):
    if not ok:
        raise Stop(reason)


def same_stat(a, b):
    return (stat.S_ISREG(a.st_mode) and stat.S_ISREG(b.st_mode) and
            all(getattr(a, k) == getattr(b, k) for k in
                ("st_dev", "st_ino", "st_mode", "st_nlink", "st_uid",
                 "st_gid", "st_size", "st_mtime_ns", "st_ctime_ns")))


def read_regular(path, cap):
    demand(isinstance(path, str) and 0 < len(path.encode()) <= 1024 and
           "\x00" not in path, "invalid_path")
    demand(hasattr(os, "O_NOFOLLOW") and hasattr(os, "O_NONBLOCK"),
           "safe_open_unavailable")
    before = os.lstat(path)
    demand(stat.S_ISREG(before.st_mode) and 1 <= before.st_size <= cap,
           "invalid_file_size_or_type")
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | getattr(os, "O_CLOEXEC", 0)
    fd = os.open(path, flags)
    try:
        opened = os.fstat(fd)
        demand(same_stat(before, opened), "input_changed")
        raw = os.read(fd, cap + 1)
        after = os.fstat(fd)
        demand(len(raw) == opened.st_size and same_stat(opened, after) and
               same_stat(after, os.lstat(path)), "input_changed")
        return raw
    finally:
        os.close(fd)


def strict_json(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            demand(key not in result, "ambiguous_json")
            result[key] = value
        return result

    def reject_constant(_):
        raise Stop("invalid_json_constant")

    try:
        obj = json.loads(raw, object_pairs_hook=unique,
                         parse_constant=reject_constant)
        json.dumps(obj, ensure_ascii=False).encode("utf-8", "strict")
        return obj
    except (ValueError, UnicodeError, RecursionError) as exc:
        raise Stop("invalid_json") from exc


def sha(data):
    return hashlib.sha256(data).hexdigest()


def b64url(raw):
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def decode64(part):
    demand(isinstance(part, str) and B64.fullmatch(part) is not None,
           "invalid_base64url")
    try:
        decoded = base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))
    except (ValueError, base64.binascii.Error) as exc:
        raise Stop("invalid_base64url") from exc
    demand(b64url(decoded) == part, "noncanonical_base64url")
    return decoded


def bounded_tree(value, depth=0):
    demand(depth <= 24, "resource_depth")
    if isinstance(value, dict):
        demand(len(value) <= 32, "resource_object")
        for key, item in value.items():
            demand(isinstance(key, str), "invalid_object_key")
            bounded_tree(item, depth + 1)
    elif isinstance(value, list):
        demand(len(value) <= 16, "resource_array")
        for item in value:
            bounded_tree(item, depth + 1)


def original_signature(root, key):
    """O1 authenticates exact compact bytes, never a reserialized payload."""
    from jwcrypto import jws
    from jwcrypto.jwk import JWK

    demand(isinstance(root, str) and root.isascii() and
           1 <= len(root) <= 32768 and root.endswith("~"),
           "invalid_root_wire")
    pieces = root.split("~")
    demand(pieces[-1] == "" and 1 <= len(pieces[1:-1]) <= 16,
           "invalid_sd_segmentation")
    compact = pieces[0]
    token = compact.split(".")
    demand(len(token) == 3 and all(token), "invalid_compact_jws")
    header = strict_json(decode64(token[0]))
    payload = strict_json(decode64(token[1]))
    bounded_tree(payload)
    demand(isinstance(header, dict) and set(header) <= {"alg", "kid", "typ"}
           and header.get("alg") == "ES256" and
           header.get("typ") == "example+sd-jwt", "unsupported_jose")
    demand(isinstance(payload, dict) and
           set(payload) <= {"delegate_payload", "_sd_alg"} and
           payload.get("_sd_alg") in (None, "sha-256") and
           isinstance(payload.get("delegate_payload"), list) and
           len(payload["delegate_payload"]) == 1, "pre_g3_root_profile")
    demand(isinstance(key, dict) and set(key) == {"kty", "crv", "x", "y"} and
           key["kty"] == "EC" and key["crv"] == "P-256" and
           all(isinstance(key[k], str) and key[k] for k in ("x", "y")),
           "invalid_public_issuer_key")
    try:
        verifier = jws.JWS()
        verifier.deserialize(compact)
        verifier.verify(JWK.from_json(json.dumps(key, sort_keys=True)))
    except Exception as exc:
        raise Stop("invalid_original_issuer_signature") from exc
    return compact, payload, pieces[1:-1]


def inspect_graph(payload, disclosures):
    """Independent O3 scan of *all original signed* object/array commitments.

    Only original base64url Disclosure bytes are hashed. Unsupported/missing
    commitments never turn into permitted slots; all extra disclosures fail.
    This fixed profile supports array [salt, object] Disclosures only.
    """
    mapping = {}
    for part in disclosures:
        raw = decode64(part)
        demand(len(raw) <= 8192, "oversize_disclosure")
        item = strict_json(raw)
        bounded_tree(item)
        demand(isinstance(item, list) and len(item) == 2 and
               isinstance(item[0], str) and
               8 <= len(item[0].encode("utf-8")) <= 128 and
               isinstance(item[1], dict), "unsupported_disclosure")
        digest = b64url(hashlib.sha256(part.encode("ascii")).digest())
        demand(digest not in mapping, "duplicate_disclosure")
        mapping[digest] = item[1]

    seen, observed, problems = set(), [], []

    def consume(digest, path, depth):
        demand(isinstance(digest, str) and len(digest) == 43 and
               B64.fullmatch(digest) is not None, "invalid_signed_digest")
        observed.append(path)
        if path not in ALLOWED:
            problems.append("UNKNOWN_SLOT")
        if digest in seen:
            problems.append("DUPLICATE")
        seen.add(digest)
        if digest not in mapping:
            problems.append("MISSING")
            return
        visit(mapping[digest], path + ("disclosed",), depth + 1)

    def visit(value, path, depth):
        demand(depth <= 24, "resource_depth")
        if isinstance(value, list):
            demand(len(value) <= 16, "resource_array")
            for index, item in enumerate(value):
                here = path + (index,)
                if isinstance(item, dict) and "..." in item:
                    demand(set(item) == {"..."}, "malformed_array_marker")
                    consume(item["..."], here, depth)
                else:
                    visit(item, here, depth + 1)
        elif isinstance(value, dict):
            demand(len(value) <= 32, "resource_object")
            if "_sd" in value or "..." in value:
                problems.append("UNKNOWN_SLOT")
                if "_sd" in value:
                    sd = value["_sd"]
                    demand(isinstance(sd, list) and len(sd) <= 16, "invalid_object_sd")
                    for digest in sd:
                        # Object-property SD is outside this fixed profile.
                        consume(digest, path + ("_sd",), depth)
            for key, child in value.items():
                if key not in ("_sd", "..."):
                    visit(child, path + (key,), depth + 1)

    visit(payload, (), 0)
    if len(mapping) != len(seen):
        problems.append("UNUSED")
    if set(observed) != ALLOWED or len(observed) != len(ALLOWED):
        problems.append("PROFILE_MISMATCH")
    for priority in ("UNKNOWN_SLOT", "DUPLICATE", "MISSING", "UNUSED",
                     "PROFILE_MISMATCH"):
        if priority in problems:
            return priority
    return "FULL"


def run(fixture_path, policy_path, report_path):
    fixture_raw = read_regular(fixture_path, 262144)
    policy_raw = read_regular(policy_path, 16384)
    fixture = strict_json(fixture_raw)
    policy = strict_json(policy_raw)
    demand(isinstance(fixture, dict) and
           set(fixture) == {"ap2_commit", "cases"} and
           fixture["ap2_commit"] == PINNED_AP2 and
           isinstance(fixture["cases"], dict) and
           set(fixture["cases"]) == set(CASES), "unsupported_fixture")
    demand(isinstance(policy, dict) and
           isinstance(policy.get("issuer_public_jwk"), dict) and
           policy.get("tenant_scope") == "synthetic-e01s" and
           policy.get("profile_ref") == "e01s-fixed-a-v1" and
           isinstance(policy.get("policy_digest"), str) and
           HEX.fullmatch(policy["policy_digest"]) is not None,
           "untrusted_policy_claim")
    key = policy["issuer_public_jwk"]
    demand(set(key) == {"crv", "kty", "x", "y"}, "private_or_unknown_jwk")
    result = {}
    jws_original = {}
    for case_id in CASES:
        case = fixture["cases"][case_id]
        demand(isinstance(case, dict) and set(case) == {"root", "terminal"} and
               isinstance(case["terminal"], str) and
               case["terminal"].isascii() and
               1 <= len(case["terminal"]) <= 32768, "invalid_case")
        compact, payload, disclosures = original_signature(case["root"], key)
        observed = inspect_graph(payload, disclosures)
        demand(observed == EXPECTED[case_id], "independent_case_mismatch")
        jws_original[case_id] = compact
        result[case_id] = {
            "issuer_signature": "VALID_UNDER_SYNTHETIC_POLICY_KEY",
            "root_wire_sha256": sha(case["root"].encode("ascii")),
            "terminal_wire_sha256": sha(case["terminal"].encode("ascii")),
            "graph_class": observed,
            "expected_g3": "PASS_CONDITIONAL" if case_id == "FULL" else "REJECT",
            "g1_authority": "NOT_ESTABLISHED",
        }
    demand(jws_original["HIDDEN"] == jws_original["FULL"] and
           jws_original["UNKNOWN"] != jws_original["FULL"] and
           jws_original["DECOY"] != jws_original["FULL"],
           "not_independent_signed_variants")

    report = {
        "case_id": "E03E04_A_SOURCE_ONLY_ORACLE",
        "pinned_ap2_sha": PINNED_AP2,
        "fixture_sha256": sha(fixture_raw),
        "policy_sha256": sha(policy_raw),
        "cases": result,
        "oracle_scope": "O1_ISSUER_ONLY_O3_ORIGINAL_ROOT_GRAPH",
        "o2_agent_merchant": "NOT_CHECKED",
        "o4_schema": "NOT_CHECKED",
        "o5_ruby_stage": "NOT_RUN",
        "host_authority": "NOT_ESTABLISHED",
        "e03_e04_exit_gate": "UNPROVEN",
        "conclusion": "HOLD_NO_PHASE2B_OR_PAYMENT_AUTHORIZATION",
    }
    encoded = (json.dumps(report, sort_keys=True, separators=(",", ":")) + "\n").encode()
    demand(len(encoded) <= 65536 and
           isinstance(report_path, str) and len(report_path.encode()) <= 1024 and
           "\x00" not in report_path and hasattr(os, "O_NOFOLLOW"),
           "invalid_report")
    fd = os.open(report_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                 os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
    except Exception:
        raise
    return False  # Deliberate HOLD; never report gate PASS as exit status 0.


if __name__ == "__main__":
    try:
        parser = argparse.ArgumentParser()
        parser.add_argument("--fixture", required=True)
        parser.add_argument("--policy", required=True)
        parser.add_argument("--report", required=True)
        arguments = parser.parse_args()
        run(arguments.fixture, arguments.policy, arguments.report)
        print("E03/E04 O1/O3: HOLD; no integrated or Host proof")
        sys.exit(1)
    except Exception:
        # Never print original wires/UIDs/keys/paths/exception contents.
        print("E03/E04 O1/O3: RED/HOLD", file=sys.stderr)
        sys.exit(1)
