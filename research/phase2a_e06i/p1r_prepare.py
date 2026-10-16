"""Static P1-R preparation contract checks; no acquisition/install/build backend.

Owner approval covers source and offline mock tests only. This module never
imports project execution code, starts a process, opens a socket or claims a tag.
Budget ceilings and supplied receipts are data, not execution authorization.
"""
import datetime as dt
import hashlib
import json
from pathlib import Path
import re

CASES = ("FULL", "HIDDEN", "UNKNOWN", "DUPLICATE", "EXTRA", "DECOY")
BASELINE = "017967a96d3f8d2735073e799a77de8eb6fcbba3"
AP2 = "b4587ac1d055888a73b4b21750973cffba961793"
ROLES = ("git_package_closure", "pip_bootstrap_wheel", "ruby_default_native_closure",
         "base_os_installed_inventory", "cpython_install_reconciliation",
         "ap2_git_objects_and_import_closure", "source_schema_manifest",
         "runtime_loader_import_manifest", "external_bootstrap_and_tools",
         "bounded_acquisition_and_offline_install_recipe")
CEILINGS = {"body_bytes": 268435456, "header_bytes": 8192, "disk_bytes": 8589934592,
            "memory_bytes": 2147483648, "scratch_bytes": 67108864,
            "job_seconds": 600, "child_seconds": 10, "batch_seconds": 90,
            "artifact_bytes": 1048576, "retention_days": 7, "cost_jpy": 0}


class Hold(ValueError):
    pass


def need(ok, code):
    if not ok:
        raise Hold(code)


def integer(value, minimum=0):
    return type(value) is int and minimum <= value <= 2**53


def wire(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=True,
                      allow_nan=False, separators=(",", ":")).encode()


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def document(raw, cap):
    need(type(raw) is bytes and 0 < len(raw) <= cap, "DOCUMENT_SIZE")
    def pairs(items):
        result = {}
        for key, value in items:
            need(key not in result, "DUPLICATE_JSON_KEY")
            result[key] = value
        return result
    def bad_constant(_):
        raise Hold("NONFINITE_JSON")
    try:
        result = json.loads(raw, object_pairs_hook=pairs, parse_constant=bad_constant)
        wire(result)
    except (UnicodeError, RecursionError, TypeError) as exc:
        raise Hold("DOCUMENT_ENCODING") from exc
    need(type(result) is dict, "DOCUMENT_OBJECT")
    return result


def future_pin(item):
    """Structural completeness only; never authenticates a caller's manifest."""
    return (type(item) is dict and item.get("status") == "FROZEN_REVIEW_REQUIRED" and
            type(item.get("version")) is str and bool(item["version"]) and
            type(item.get("sha256")) is str and
            re.fullmatch(r"[a-f0-9]{64}", item["sha256"]) is not None and
            integer(item.get("size"), 1) and type(item.get("source")) is str and
            item["source"].startswith("https://"))


def inspect_contract(contract, now):
    plan = contract["six_case_static_plan"]
    need(type(plan["schema_version"]) is int and plan["schema_version"] == 1 and
         plan["authority"] == "STATIC_IMPLEMENTATION_ONLY",
         "STATIC_AUTHORITY")
    need(plan["baseline_verifier_sha"] == BASELINE and plan["official_ap2_sha"] == AP2,
         "SOURCE_BASELINE")
    need(plan["cases"] == list(CASES) and plan["proposed_ceilings"] == CEILINGS and
         all(type(v) is int for v in plan["proposed_ceilings"].values()),
         "PLAN_OR_CEILING_MISMATCH")
    need(type(plan["execution_permissions"]) is dict and
         all(v is False for v in plan["execution_permissions"].values()) and
         set(plan["execution_permissions"]) == {
             "merge", "actions", "acquire", "install", "build", "docker",
             "signed_fixture", "six_case_experiment", "cost"},
         "EXECUTION_PERMISSION_NOT_FALSE")
    need(set(plan["unresolved_inputs"]) == set(ROLES), "INVENTORY_ROLE_SET")
    missing = [name for name in ROLES if not future_pin(plan["unresolved_inputs"][name])]
    for value in (contract["security_valid_until"], contract["saved_artifact"]["expires_at"]):
        expiry = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        need(now.tzinfo is not None and now < expiry, "RETAINED_INPUT_EXPIRED")
    # Even a structurally complete hypothetical inventory is not approved.
    return {"status": "STATIC_ONLY_EXECUTION_HOLD", "inventory_fields_complete": not missing,
            "inventory_complete": False, "inventory_authenticity": "UNPROVEN",
            "unresolved": missing, "execution_authorized": False,
            "installed_runtime_validated": False, "six_cases_executed": False,
            "phase2_gate": "UNPROVEN", "phase2b": "HOLD"}


class Budget:
    """Offline model of required future accounting, not an I/O implementation."""
    def __init__(self, ceilings, now):
        need(ceilings == CEILINGS and all(type(v) is int for v in ceilings.values()), "BUDGET_CEILINGS")
        self.used = 0
        self.started = now
        self.last = now
        need(type(now) in (int, float) and 0 <= now < 1e12, "BUDGET_CLOCK")

    def response(self, *, body_bytes, header_bytes, now):
        need(integer(body_bytes) and integer(header_bytes, 1), "BYTE_COUNT")
        need(header_bytes <= CEILINGS["header_bytes"], "HEADER_LIMIT")
        need(type(now) in (int, float) and self.last <= now <
             self.started + CEILINGS["job_seconds"], "JOB_DEADLINE")
        need(self.used + body_bytes <= CEILINGS["body_bytes"], "BODY_LIMIT")
        self.used += body_bytes
        self.last = now

    def storage(self, *, disk_bytes, scratch_bytes, artifact_bytes, memory_bytes):
        need(all(integer(x) for x in (disk_bytes, scratch_bytes, artifact_bytes, memory_bytes)), "STORAGE_COUNT")
        need(disk_bytes <= CEILINGS["disk_bytes"] and
             scratch_bytes <= CEILINGS["scratch_bytes"] and
             artifact_bytes <= CEILINGS["artifact_bytes"] and
             memory_bytes <= CEILINGS["memory_bytes"], "STORAGE_LIMIT")


def isolation_claim(receipt):
    required = {"network_none", "dns_disabled", "rootfs_readonly", "sources_readonly",
                "nonroot", "capabilities_dropped", "no_new_privileges",
                "bounded_scratch", "external_process_tree_watchdog"}
    need(type(receipt) is dict and set(receipt) == required and
         all(receipt[k] is True for k in required), "ISOLATION_CLAIM_INCOMPLETE")
    return {"claim_shape_matches": True, "os_isolation_established": False,
            "external_attestation": "UNPROVEN"}


def require_live_execution():
    # No environment flag, approval JSON or filled inventory unlocks this stage.
    raise Hold("STATIC_STAGE_NO_LIVE_BACKEND_OR_EXECUTION_APPROVAL")


if __name__ == "__main__":
    try:
        path = Path(__file__).with_name("p1r_input_contract.json")
        with path.open("rb") as stream:
            raw = stream.read(131073)
        result = inspect_contract(document(raw, 131072), dt.datetime.now(dt.timezone.utc))
        print(wire(result).decode())
    except Exception:
        print('{"status":"STATIC_ONLY_EXECUTION_HOLD","reason":"CONTRACT_REJECTED"}')
    raise SystemExit(78)
