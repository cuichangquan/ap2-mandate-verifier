"""Static P1-R preparation contract checks; no acquisition/install/build backend.

Owner approval covers source and offline mock tests only. This module never
imports project execution code, starts a process, opens a socket or claims a tag.
Budget ceilings and supplied receipts are data, not execution authorization.
"""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import stat
from urllib.parse import urlsplit

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


def json_value(raw, cap):
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
        result = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs, parse_constant=bad_constant)
        wire(result)
    except (UnicodeError, RecursionError, TypeError) as exc:
        raise Hold("DOCUMENT_ENCODING") from exc
    return result


def document(raw, cap):
    result = json_value(raw, cap)
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


ARTIFACT_KINDS = {"base_layer", "debian_package", "pip_bootstrap", "python_wheel",
                  "ruby_gem", "git_object_pack", "source_file"}
INSTALL_ORDER = ("base_layer", "debian_package", "git_object_pack", "pip_bootstrap",
                 "python_wheel", "ruby_gem", "source_file")


def artifact_spec(item, allowed_urls):
    """A complete descriptor is required before an injected I/O call."""
    need(type(item) is dict and set(item) == {"name", "kind", "url", "size", "sha256"},
         "ARTIFACT_DESCRIPTOR")
    need(type(item["name"]) is str and re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9_.-]{0,127}",
         item["name"]) and item["name"] not in (".", ".."), "ARTIFACT_NAME")
    need(type(item["kind"]) is str and item["kind"] in ARTIFACT_KINDS and integer(item["size"], 1) and
         item["size"] <= CEILINGS["body_bytes"] and type(item["sha256"]) is str and
         re.fullmatch(r"[a-f0-9]{64}", item["sha256"]), "ARTIFACT_PIN")
    need(type(item["url"]) is str and item["url"] in allowed_urls, "ARTIFACT_URL_NOT_FROZEN")
    u = urlsplit(item["url"])
    need(u.scheme == "https" and u.hostname and u.username is None and u.password is None and
         u.port is None and not u.fragment and not u.query and
         all(32 < ord(c) < 127 for c in item["url"]), "ARTIFACT_URL")


def acquire_with_transport(item, allowed_urls, transport, budget, clock):
    """Non-live acquisition engine against an explicitly supplied transport port.

    No default HTTP implementation exists. A later live port MUST enforce
    the supplied caps while receiving bytes, not merely return capped claims.
    Tests provide only in-memory responses. No redirect/auth fallback here.
    """
    artifact_spec(item, allowed_urls)
    need(item["size"] <= CEILINGS["body_bytes"] - budget.used, "BODY_RESERVATION")
    now = clock()
    budget.response(body_bytes=0, header_bytes=1, now=now)
    spec = {"method": "GET", "url": item["url"], "body_cap": item["size"],
            "header_cap": CEILINGS["header_bytes"],
            "deadline": budget.started + CEILINGS["job_seconds"],
            "follow_redirects": 0, "retry": 0, "credentials": None}
    response = transport(spec)  # One attempt, limits passed BEFORE I/O.
    need(type(response) is dict and set(response) == {"status", "headers", "chunks"},
         "TRANSPORT_RESPONSE")
    header = response["headers"]
    need(type(header) is bytes and 0 < len(header) <= CEILINGS["header_bytes"],
         "HEADER_LIMIT")
    # This port supplies bounded raw HTTP/1.1 headers and decoded body chunks.
    lines = header.split(b"\r\n")
    need(header.endswith(b"\r\n\r\n") and
         re.fullmatch(rb"HTTP/1\.[01] 200 [^\r\n]*", lines[0]) and
         type(response["status"]) is int and response["status"] == 200,
         "TRANSPORT_STATUS_OR_REDIRECT")
    fields = {}
    for line in lines[1:-2]:
        name, colon, value = line.partition(b":")
        need(colon and re.fullmatch(rb"[A-Za-z0-9-]+", name), "TRANSPORT_HEADER")
        name, value = name.lower(), value.strip()
        need(name not in fields and all(c >= 32 and c != 127 for c in value), "TRANSPORT_HEADER")
        fields[name] = value
    need(fields.get(b"content-encoding", b"identity") == b"identity" and
         fields.get(b"content-length") == str(item["size"]).encode() and
         b"transfer-encoding" not in fields, "TRANSPORT_FRAMING")
    budget.response(body_bytes=0, header_bytes=len(header), now=clock())
    raw = bytearray()
    for index, chunk in enumerate(response["chunks"]):
        need(index < 65536 and type(chunk) is bytes and chunk, "BODY_CHUNK")
        # The future transport must enforce this before physical receipt;
        # the engine additionally rejects a nonconforming injected port.
        need(len(raw) + len(chunk) <= item["size"], "ARTIFACT_SIZE")
        budget.response(body_bytes=len(chunk), header_bytes=len(header), now=clock())
        raw.extend(chunk)
    need(len(raw) == item["size"] and sha(raw) == item["sha256"], "ARTIFACT_SIZE_OR_HASH")
    return bytes(raw)


def stage_verified(dirfd, item, raw):
    """Stage verified bytes with exclusive descriptor-relative writes.

    The caller must externally provision the private namespace. This checks
    only its open directory descriptor; it does not attest OS isolation.
    """
    need(type(raw) is bytes and len(raw) == item["size"] and sha(raw) == item["sha256"],
         "STAGE_PIN")
    need(re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9_.-]{0,127}", item["name"]), "STAGE_NAME")
    parent = os.fstat(dirfd)
    need(stat.S_ISDIR(parent.st_mode) and parent.st_uid == os.geteuid() and
         parent.st_mode & 0o077 == 0, "STAGE_NAMESPACE")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    fd = os.open(item["name"], flags, 0o600, dir_fd=dirfd)
    created, closed = None, False
    try:
        created = os.fstat(fd)
        need(stat.S_ISREG(created.st_mode) and created.st_nlink == 1, "STAGE_FILE")
        done = 0
        while done < len(raw):
            n = os.write(fd, raw[done:])
            need(n > 0, "STAGE_WRITE")
            done += n
        os.fchmod(fd, 0o400)
        os.fsync(fd)
        # Set before close: a close error must never retry a potentially reused fd.
        closed = True
        os.close(fd)
        os.fsync(dirfd)
    except BaseException as primary:
        try:
            current = os.stat(item["name"], dir_fd=dirfd, follow_symlinks=False)
            if created is None or (current.st_dev, current.st_ino) == (created.st_dev, created.st_ino):
                os.unlink(item["name"], dir_fd=dirfd)
                os.fsync(dirfd)
            else:
                primary.add_note("STAGE_CLEANUP_IDENTITY_CHANGED")
        except BaseException:
            primary.add_note("STAGE_CLEANUP_UNCERTAIN")
        if not closed:
            try:
                os.close(fd)
            except BaseException:
                primary.add_note("STAGE_CLOSE_UNCERTAIN")
        raise
    return {"name": item["name"], "size": len(raw), "sha256": sha(raw)}


def preparation_model(contract, artifacts, allowed_urls, transport, stage, offline_step, clock, now):
    """Full non-live orchestration; ports are mocks, receipts are not proof.

    Missing real inventories stop before any port call. Installation/build
    adapters and bounded real Git/OCI transport still need frozen recipes,
    independent review and explicit execution approval. No such port ships.
    """
    checked = inspect_contract(contract, now)
    need(checked["inventory_fields_complete"], "PREPARATION_INPUTS_UNRESOLVED")
    need(type(artifacts) is list and 0 < len(artifacts) <= 512, "ARTIFACT_SET")
    for item in artifacts:
        artifact_spec(item, allowed_urls)
    need(len({x["name"] for x in artifacts}) == len(artifacts), "ARTIFACT_DUPLICATE")
    need(sum(x["size"] for x in artifacts) <= CEILINGS["body_bytes"], "BODY_RESERVATION")
    budget = Budget(CEILINGS, clock())
    staged = []
    try:
        for item in artifacts:
            raw = acquire_with_transport(item, allowed_urls, transport, budget, clock)
            observed = stage(item, raw)
            need(observed == {"name": item["name"], "size": item["size"], "sha256": item["sha256"]},
                 "STAGING_RECEIPT")
            staged.append(observed)
        # All downloads/staging finish before the first offline install operation.
        for kind in INSTALL_ORDER:
            selected = [x["name"] for x in artifacts if x["kind"] == kind]
            if selected:
                receipt = offline_step({"operation": kind, "inputs": selected,
                                        "network": "none", "retry": 0})
                need(receipt == {"completed": True, "network_attempts": 0}, "OFFLINE_STEP_FAILURE")
        for operation in ("freeze_image", "runtime_inventory"):
            need(offline_step({"operation": operation, "network": "none", "retry": 0}) ==
                 {"completed": True, "network_attempts": 0}, "PREPARATION_FINALIZATION")
    except BaseException as primary:
        try:
            need(offline_step({"operation": "cleanup", "network": "none", "retry": 0}) ==
                 {"completed": True, "network_attempts": 0}, "PREPARATION_CLEANUP_FAILURE")
        except BaseException:
            primary.add_note("PREPARATION_CLEANUP_UNCERTAIN")
        raise
    else:
        need(offline_step({"operation": "cleanup", "network": "none", "retry": 0}) ==
             {"completed": True, "network_attempts": 0}, "PREPARATION_CLEANUP_FAILURE")
    return {"status": "MOCK_PREPARATION_SEQUENCE_MATCH", "staged": staged,
            "modeled_body_bytes": budget.used, "actual_acquisition_install_build": False,
            "inventory_complete": False, "runtime_validated": False,
            "execution_authorized": False, "phase2_gate": "UNPROVEN"}


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
