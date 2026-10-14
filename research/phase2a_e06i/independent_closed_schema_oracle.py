"""E06-I A7 independent E01-S signed Closed/merchant O4 oracle (SOURCE ONLY).

NOT RUN / no owner Approval B / no network / no signing or private keys.
Existing E01-S and DC01 public-only independent signed-wire predicates are
reused. An oracle result is NOT an authenticated Host or Ruby stage result.
"""
import argparse
import hashlib
import json
import os
import stat
import sys
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "phase2a_dc01"))
from independent_positive_oracle import (  # noqa: E402
    b64url, jws_payload, raw_commitment_graph, segments, strict_json,
)

PINNED_AP2 = "b4587ac1d055888a73b4b21750973cffba961793"
DRAFT = "https://json-schema.org/draft/2020-12/schema"
MERCHANT_URI = "https://ap2-protocol.org/schemas/types/merchant.json"
IDS = ("IP01", "IP02", "IP03")
ALLOWED = {
    "$/delegate_payload/0",
    "$/delegate_payload/0/disclosed/constraints/1/allowed/0",
    "$/delegate_payload/0/disclosed/constraints/0/items/0/acceptable_items/0",
}
EXTRA = "$/delegate_payload/0/disclosed/constraints/1"
SCHEMAS = {
    "open": ("open_checkout_mandate.json",
             "https://ap2-protocol.org/schemas/open_checkout_mandate",
             "e3d9cafa7311d90612c7f908ae9b8821ddc8735a"),
    "closed": ("checkout_mandate.json",
               "https://ap2-protocol.org/schemas/checkout_mandate.json",
               "8755db60a1c6e15f49cfe6c9a5dee6838d2f379d"),
    "merchant": ("types/merchant.json", MERCHANT_URI,
                 "2e44a4dc943c009af106e7103e9e30f4e556b98c"),
}


class Stop(Exception):
    pass


def demand(ok, reason):
    if not ok:
        raise Stop(reason)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=True).encode("ascii")


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def snapshot_equal(a, b):
    return (stat.S_ISREG(a.st_mode) and stat.S_ISREG(b.st_mode) and
            all(getattr(a, key) == getattr(b, key) for key in
                ("st_dev", "st_ino", "st_mode", "st_nlink", "st_uid",
                 "st_gid", "st_size", "st_mtime_ns", "st_ctime_ns")))


def bounded_file(path, limit, *, directory=None):
    """No path-size-to-unbounded-read race; descriptor is same before/after."""
    path = Path(path)
    demand(0 < len(str(path).encode("utf-8")) <= 1024, "bad_file_path")
    if directory is not None:
        parent = Path(directory).resolve(strict=True)
        actual = path.resolve(strict=True)
        demand(parent == actual.parent or parent in actual.parents,
               "schema_path_outside_pin")
    else:
        actual = path.resolve(strict=True)
    demand(hasattr(os, "O_NOFOLLOW") and hasattr(os, "O_NONBLOCK"),
           "safe_file_flags_unavailable")
    path_stat = path.lstat()
    demand(stat.S_ISREG(path_stat.st_mode) and 1 <= path_stat.st_size <= limit,
           "input_file_type_or_size")
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
    flags |= getattr(os, "O_CLOEXEC", 0)
    fd = os.open(path, flags)
    try:
        before = os.fstat(fd)
        demand(snapshot_equal(path_stat, before), "input_file_changed")
        with os.fdopen(fd, "rb", closefd=False) as f:
            raw = f.read(limit + 1)
        after = os.fstat(fd)
        demand(1 <= len(raw) <= limit and len(raw) == before.st_size and
               snapshot_equal(before, after) and
               snapshot_equal(after, path.lstat()) and
               path.resolve(strict=True) == actual, "input_file_raced")
        return raw
    finally:
        os.close(fd)


def expect_public(key):
    demand(type(key) is dict and set(key) == {"crv", "kty", "x", "y"} and
           key["kty"] == "EC" and key["crv"] == "P-256" and
           all(type(key[n]) is str and 1 <= len(key[n]) <= 128
               for n in ("x", "y")), "invalid_public_key")


def thumbprint(key):
    expect_public(key)
    return b64url(hashlib.sha256(canonical(key)).digest())


def load_schemas(root):
    directory = Path(root).resolve(strict=True) / "code/sdk/schemas/ap2"
    directory = directory.resolve(strict=True)
    schemas, fingerprints = {}, {}
    for label, (relative, identifier, blob) in SCHEMAS.items():
        raw = bounded_file(directory / relative, 32_768, directory=directory)
        calculated = hashlib.sha1(
            f"blob {len(raw)}\0".encode("ascii") + raw
        ).hexdigest()
        demand(calculated == blob, "pinned_schema_blob_changed")
        parsed = strict_json(raw)
        demand(type(parsed) is dict and
               parsed.get("$id") == identifier and
               parsed.get("$schema") == DRAFT, "schema_identity_changed")
        schemas[label] = parsed
        fingerprints[label] = {
            "git_blob": calculated, "sha256": sha(raw), "id": identifier
        }

    def no_remote(_uri):
        raise Stop("unallowlisted_schema_ref")

    # No network fetch: only the three local, digest-pinned resources exist.
    registry = Registry(retrieve=no_remote)
    for label in ("open", "closed", "merchant"):
        registry = registry.with_resource(
            SCHEMAS[label][1], Resource.from_contents(schemas[label])
        )
    return {
        label: Draft202012Validator(schemas[label], registry=registry)
        for label in ("open", "closed", "merchant")
    }, fingerprints


def signed_cases(fixture, policy, e01_report, validators):
    demand(fixture.get("case_id") == "E01-S" and
           fixture.get("ap2_commit") == PINNED_AP2 and
           e01_report.get("case_id") == "E01-S" and
           e01_report.get("pinned_ap2_sha") == PINNED_AP2 and
           e01_report.get("O5_Ruby") == "NOT_RUN", "wrong_fixture_origin")
    demand(fixture.get("policy_digest") == policy.get("policy_digest") ==
           e01_report.get("policy_digest"), "host_policy_digest_mismatch")
    demand(type(policy.get("policy_digest")) is str and
           sha(canonical({k: v for k, v in policy.items()
                          if k != "policy_digest"})) ==
           policy["policy_digest"], "host_policy_not_frozen")
    demand(policy.get("tenant_scope") == "synthetic-e01s" and
           policy.get("profile_ref") == "e01s-fixed-a-v1" and
           policy.get("active") is True, "unsupported_synthetic_host")
    for section in ("roots", "terminals", "candidate_issuer_public_jwks",
                    "candidate_issuer_thumbprints"):
        demand(type(fixture.get(section)) is dict and
               set(fixture[section]) == set(IDS), "wrong_ip_case_set")
    demand(type(e01_report.get("oracles")) is dict and
           set(e01_report["oracles"]) == set(IDS), "missing_original_oracles")
    expect_public(policy["issuer_public_jwk"])
    expect_public(policy["expected_agent_public_jwk"])
    expect_public(policy["trusted_merchant_public_jwk"])
    expect_public(fixture["issuer_b_public_jwk"])
    demand(thumbprint(policy["issuer_public_jwk"]) ==
           policy.get("issuer_thumbprint"), "host_public_key_claim_mismatch")

    jwt = policy.get("host_checkout_jwt")
    demand(type(jwt) is str and 1 <= len(jwt.encode("ascii")) <= 16_384,
           "bad_checkout_jwt")
    merchant = jws_payload(
        jwt, policy["trusted_merchant_public_jwk"], expected_typ="JWT"
    )
    demand(type(merchant) is dict, "bad_merchant_signed_payload")
    out = {}
    for case_id in IDS:
        root, terminal = fixture["roots"][case_id], fixture["terminals"][case_id]
        signer = fixture["candidate_issuer_public_jwks"][case_id]
        expect_public(signer)
        demand(type(root) is str and type(terminal) is str and
               1 <= len(root.encode("ascii")) <= 32_768 and
               1 <= len(terminal.encode("ascii")) <= 32_768,
               "signed_wire_limit")
        expected_signer = (policy["issuer_public_jwk"]
                           if case_id != "IP02" else fixture["issuer_b_public_jwk"])
        demand(signer == expected_signer and
               thumbprint(signer) == fixture["candidate_issuer_thumbprints"][case_id],
               "issuer_public_origin_mismatch")
        original_jws, disclosures = segments(root)
        root_claim = jws_payload(original_jws, signer, expected_typ="example+sd-jwt")
        opened_root, graph = raw_commitment_graph(root_claim, disclosures)
        demand(type(opened_root) is dict and
               type(opened_root.get("delegate_payload")) is list and
               len(opened_root["delegate_payload"]) == 1,
               "root_profile_invalid")
        opened = opened_root["delegate_payload"][0]
        demand(type(opened) is dict and
               opened.get("cnf") == {"jwk": policy["expected_agent_public_jwk"]},
               "issuer_agent_mismatch")
        paths = [item["path"] for item in graph]
        demand(len(paths) == len(set(paths)) and
               all(item["kind"] == "array" for item in graph),
               "signed_commitment_graph_invalid")
        if case_id == "IP03":
            demand(EXTRA in paths and set(paths) != ALLOWED,
                   "missing_signed_unknown_path")
        else:
            demand(set(paths) == ALLOWED, "allowed_root_graph_changed")

        signed_terminal_jws, terminal_disclosures = segments(terminal)
        agent_signed = jws_payload(
            signed_terminal_jws, policy["expected_agent_public_jwk"],
            expected_typ="kb+sd-jwt"
        )
        demand(agent_signed.get("sd_hash") == b64url(hashlib.sha256(
            root.encode("ascii")).digest()) and
               agent_signed.get("aud") == policy.get("expected_aud") and
               agent_signed.get("nonce") == policy.get("expected_nonce"),
               "agent_did_not_sign_this_presentation")
        closed_root, closed_graph = raw_commitment_graph(
            agent_signed, terminal_disclosures
        )
        demand(len(closed_graph) == 1 and
               closed_graph[0]["path"] == "$/delegate_payload/0" and
               type(closed_root) is dict and
               type(closed_root.get("delegate_payload")) is list and
               len(closed_root["delegate_payload"]) == 1,
               "terminal_original_graph_invalid")
        closed = closed_root["delegate_payload"][0]
        demand(type(closed) is dict and
               closed.get("checkout_jwt") == jwt and
               closed.get("checkout_hash") == b64url(
                   hashlib.sha256(jwt.encode("ascii")).digest()
               ) and
               opened.get("iat") == closed.get("iat") and
               opened.get("exp") == closed.get("exp"),
               "closed_unsigned_or_unbound")
        demand(validators["open"].is_valid(opened), "official_open_invalid")
        demand(validators["closed"].is_valid(closed), "official_closed_invalid")
        # Force the nested Merchant to be checked against the pinned resource
        # INDEPENDENTLY of the Open schema's allowlist $ref resolution.
        allowed_merchants = opened["constraints"][1]["allowed"]
        demand(type(allowed_merchants) is list and
               len(allowed_merchants) == 1 and
               validators["merchant"].is_valid(allowed_merchants[0]),
               "nested_merchant_invalid")

        old = e01_report["oracles"][case_id]
        demand(type(old) is dict and
               old.get("O1_issuer_signature") == "VALID_WITH_CASE_SIGNER" and
               old.get("O2_agent_merchant_checkout_binding") == "VALID" and
               old.get("O3_original_root_disclosure_completeness") ==
               "VALID_WITH_ALL_DISCLOSURES" and
               old.get("O4_official_open_schema") == "VALID" and
               old.get("root_wire_sha256") == sha(root.encode("ascii")) and
               set(old.get("O3_signed_paths", [])) == set(paths),
               "e01_source_oracle_not_correlated")
        out[case_id] = {
            "root_wire_sha256": sha(root.encode("ascii")),
            "terminal_wire_sha256": sha(terminal.encode("ascii")),
            "checkout_wire_sha256": sha(jwt.encode("ascii")),
            "issuer_signed_root": "VALID_WITH_CASE_SIGNER",
            "agent_signed_terminal": "VALID",
            "merchant_signed_checkout": "VALID",
            "original_root_graph": "FULLY_DISCLOSED",
            "signed_root_paths": sorted(paths),
            "official_open_schema": "VALID",
            "official_closed_schema": "VALID",
            "nested_merchant_schema": "VALID",
        }
    return out


def main():
    parser = argparse.ArgumentParser()
    for arg in ("fixture", "policy", "e01-report", "upstream-root", "report"):
        parser.add_argument("--" + arg, required=True)
    args = parser.parse_args()
    files = {
        "fixture": bounded_file(args.fixture, 512_000),
        "policy": bounded_file(args.policy, 16_384),
        "e01": bounded_file(args.e01_report, 256_000),
    }
    fixture, policy, earlier = (
        strict_json(files["fixture"]), strict_json(files["policy"]),
        strict_json(files["e01"])
    )
    demand(all(type(x) is dict for x in (fixture, policy, earlier)),
           "non_object_research_input")
    validators, fingerprints = load_schemas(args.upstream_root)
    cases = signed_cases(fixture, policy, earlier, validators)
    report = {
        "case_id": "E06I_A7_INDEPENDENT_CLOSED_SCHEMA",
        "pinned_ap2_sha": PINNED_AP2,
        "source_fixture_sha256": sha(files["fixture"]),
        "source_policy_sha256": sha(files["policy"]),
        "source_e01_report_sha256": sha(files["e01"]),
        "schema_fingerprints": fingerprints,
        "cases": cases,
        "host_authority": "NONE_SYNTHETIC_ONLY",
        "ruby_stage_result": "NOT_RUN",
        "conclusion": "O1_O4_SYNTHETIC_ONLY_NOT_E06_GATE_PASS",
    }
    encoded = canonical(report) + b"\n"
    demand(len(encoded) <= 65_536, "report_size_limit")
    demand(0 < len(os.fsencode(args.report)) <= 1024 and
           hasattr(os, "O_NOFOLLOW"), "output_path_unavailable")
    fd = os.open(args.report, os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                 os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "wb", closefd=False) as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(fd)
    finally:
        os.close(fd)


if __name__ == "__main__":
    try:
        main()
    except (Stop, ValueError, TypeError, KeyError, OSError,
            UnicodeError, ImportError) as err:
        # No token contents, keys, nonce or full signed wire in errors.
        print("E06-I A7 independent oracle: RED/HOLD; no report accepted",
              file=sys.stderr)
        raise SystemExit(1) from None
