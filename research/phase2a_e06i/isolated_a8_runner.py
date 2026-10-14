"""A8 offline supervised E06-I research runner. SOURCE ONLY; NOT EXECUTED.

Owner A8 permits this source and static Codex review, NOT Approval B.
This module is NOT a trusted bootstrap: its loaded bytes, Python/Ruby/gem
dependencies and OS snapshot immutability must be attested and protected by
a separately authorized external supervisor BEFORE any interpreter starts.
Self-reported commit IDs, Git status, this runner's own hashes or a JSON
manifest NEVER prove that trust boundary. Final conclusion is always HOLD.
No G6/G7, Host ALLOW, nonce CAS, real issuer trust or payment authority.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import tempfile

PINNED_AP2 = "b4587ac1d055888a73b4b21750973cffba961793"
HEX64 = re.compile(r"\A[0-9a-f]{64}\Z")
HEX40 = re.compile(r"\A[0-9a-f]{40}\Z")
IDS = ("IP01", "IP02", "IP03")
REQUIRED_VERIFIER = {
    "research/phase2a_e06i/isolated_a8_runner.py",
    "research/phase2a_e06i/observe_integrated.rb",
    "research/phase2a_e06i/independent_closed_schema_oracle.py",
    "research/phase2a_e06i/integrated_probe.rb",
    "research/phase2a_e06i/schema_gate.rb",
    "research/phase2a_e06i/isolated_root_closure.rb",
    "research/phase2a_e06i/isolated_host_policy.rb",
    "research/phase2a_e06i/isolated_host_snapshot.rb",
    "research/phase2a_e06i/isolated_g4_crypto.rb",
    "research/phase2a_e06i/isolated_checkout_shape.rb",
    "research/phase2a_dc01/independent_positive_oracle.py",
    "research/shared/strict_json_research.rb",
}
REQUIRED_SCHEMAS = {
    "code/sdk/schemas/ap2/open_checkout_mandate.json",
    "code/sdk/schemas/ap2/checkout_mandate.json",
    "code/sdk/schemas/ap2/types/merchant.json",
}
MAX_MANIFEST = 131_072
MAX_SOURCE_FILE = 262_144
MAX_SOURCE_FILES = 128
MAX_SOURCE_BYTES = 4_194_304


class Stop(Exception):
    pass


def demand(condition, reason):
    if not condition:
        raise Stop(reason)


def hex_digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_path(value):
    demand(isinstance(value, str) and
           1 <= len(os.fsencode(value)) <= 1024 and "\0" not in value,
           "INVALID_PATH")
    return Path(value)


def same_stat(a, b):
    return (stat.S_ISREG(a.st_mode) and stat.S_ISREG(b.st_mode) and
            all(getattr(a, part) == getattr(b, part) for part in
                ("st_dev", "st_ino", "st_mode", "st_nlink", "st_uid",
                 "st_gid", "st_size", "st_mtime_ns", "st_ctime_ns")))


def bounded_read(path, cap):
    """Read the SAME regular descriptor with a one-byte overflow sentinel."""
    path = safe_path(str(path))
    demand(hasattr(os, "O_NOFOLLOW") and hasattr(os, "O_NONBLOCK"),
           "SAFE_OPEN_UNAVAILABLE")
    actual = path.resolve(strict=True)
    before = path.lstat()
    demand(stat.S_ISREG(before.st_mode) and 1 <= before.st_size <= cap,
           "INPUT_SIZE_OR_TYPE")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK |
                 getattr(os, "O_CLOEXEC", 0))
    try:
        first = os.fstat(fd)
        demand(same_stat(before, first), "INPUT_CHANGED")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            data = stream.read(cap + 1)
        after = os.fstat(fd)
        demand(1 <= len(data) <= cap and len(data) == first.st_size and
               same_stat(first, after) and
               same_stat(after, path.lstat()) and
               path.resolve(strict=True) == actual, "INPUT_CHANGED")
        return data
    finally:
        os.close(fd)


def json_document(path, limit):
    data = bounded_read(path, limit)

    def unique(pairs):
        item = {}
        for k, value in pairs:
            demand(k not in item, "AMBIGUOUS_MANIFEST_JSON")
            item[k] = value
        return item

    obj = json.loads(data, object_pairs_hook=unique,
                     parse_constant=lambda _v: demand(
                         False, "NONFINITE_MANIFEST_JSON"))
    demand(type(obj) is dict, "INVALID_MANIFEST_OBJECT")
    return obj, data


def immutable_source_root(raw):
    root = safe_path(raw)
    demand(root.is_absolute() and not root.is_symlink(), "UNSAFE_SOURCE_ROOT")
    actual = root.resolve(strict=True)
    demand(actual.is_dir() and actual == root, "UNSAFE_SOURCE_ROOT")
    # This is a necessary local guard, NOT a substitute for pre-interpreter
    # independent OS attestation or protection against privileged remount.
    demand(hasattr(os, "ST_RDONLY") and
           (os.statvfs(actual).f_flag & os.ST_RDONLY) != 0,
           "OS_READ_ONLY_SNAPSHOT_NOT_PRESENT")
    return actual


def source_relative(root, name):
    demand(type(name) is str and len(name) <= 256, "INVALID_SOURCE_NAME")
    rel = Path(name)
    demand(not rel.is_absolute() and
           all(part not in ("", ".", "..") for part in rel.parts) and
           len(rel.parts) > 1, "SOURCE_TRAVERSAL")
    location = root
    for part in rel.parts:
        location = location / part
        demand(not location.is_symlink(), "SOURCE_SYMLINK")
    demand(location.resolve(strict=True).is_relative_to(root),
           "SOURCE_ESCAPES_SNAPSHOT")
    return location


def attest_snapshot_files(root, expected, required):
    """Check data against an EXTERNALLY REVIEWED digest list, not Git HEAD."""
    demand(type(expected) is dict and required <= set(expected) and
           1 <= len(expected) <= MAX_SOURCE_FILES, "SOURCE_MANIFEST_INCOMPLETE")
    total = 0
    for name in sorted(expected):
        digest = expected[name]
        demand(type(digest) is str and HEX64.fullmatch(digest) is not None,
               "INVALID_EXPECTED_SOURCE_HASH")
        file = source_relative(root, name)
        data = bounded_read(file, MAX_SOURCE_FILE)
        total += len(data)
        demand(total <= MAX_SOURCE_BYTES, "SOURCE_TREE_RESOURCE_LIMIT")
        demand(hex_digest(data) == digest, "SOURCE_HASH_MISMATCH")
    return total


def external_manifest!(path):
    manifest, data = json_document(path, MAX_MANIFEST)
    demand(set(manifest) == {"protocol", "verifier_commit_claim",
                            "ap2_commit_claim", "verifier_files",
                            "ap2_files", "bootstrap_status"},
           "INVALID_ATTESTATION_FIELDS")
    demand(manifest["protocol"] == "E06I_A8_UNTRUSTED_MANIFEST" and
           manifest["bootstrap_status"] == "EXTERNAL_ATTESTATION_REQUIRED" and
           type(manifest["verifier_commit_claim"]) is str and
           HEX40.fullmatch(manifest["verifier_commit_claim"]) and
           manifest["ap2_commit_claim"] == PINNED_AP2,
           "UNTRUSTED_ATTESTATION_CLAIMS")
    # An arbitrary author can make a matching manifest and filenames.
    # The caller must not treat this hash list as a signed/source authority.
    return manifest, hex_digest(data)


def child_command(command, seconds):
    """Future B ONLY: bounded logless process-group supervision, no shell."""
    demand(type(command) is list and 1 <= len(command) <= 24 and
           all(type(x) is str and 0 < len(x) <= 2048 for x in command),
           "UNSAFE_CHILD_COMMAND")
    env = {"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8",
           "PYTHONDONTWRITEBYTECODE": "1", "PYTHONNOUSERSITE": "1"}
    proc = subprocess.Popen(
        command, shell=False, stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        close_fds=True, start_new_session=True, env=env
    )
    try:
        return proc.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        raise Stop("CHILD_OS_WALL_CLOCK_EXCEEDED") from None
    finally:
        # Always terminate the entire process group, including subprocesses.
        # External B supervisor must separately hard-kill this runner itself.
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        # A returned waiter has already reaped; a timed-out waiter is
        # reaped explicitly. This does not guarantee arbitrary descendants
        # have vanished; the OS execution boundary MUST own that guarantee.
        if proc.poll() is None:
            proc.wait(timeout=3)


def exclusive_json(path, report):
    location = safe_path(path)
    raw = json.dumps(report, sort_keys=True, separators=(",", ":"),
                     ensure_ascii=True).encode("ascii") + b"\n"
    demand(0 < len(raw) <= 65_536 and hasattr(os, "O_NOFOLLOW"),
           "OUTPUT_RESOURCE_LIMIT")
    fd = os.open(location, os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                 os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "wb", closefd=False) as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(fd)
    finally:
        os.close(fd)


def run(args):
    source = immutable_source_root(args.verifier_root)
    upstream = immutable_source_root(args.upstream_root)
    # The runner must already have been loaded from an independently
    # attested immutable file in source. This identity assertion alone
    # cannot prove that it was so at Python import time.
    demand(Path(__file__).resolve(strict=True) ==
           source / "research/phase2a_e06i/isolated_a8_runner.py",
           "RUNNER_NOT_IN_SOURCE_SNAPSHOT")
    manifest, manifest_sha = external_manifest!(args.source_manifest)
    verifier_bytes_before = attest_snapshot_files(
        source, manifest["verifier_files"], REQUIRED_VERIFIER
    )
    upstream_bytes_before = attest_snapshot_files(
        upstream, manifest["ap2_files"], REQUIRED_SCHEMAS
    )
    # The external OS/supervisor must attest Ruby/Python/gem imports too;
    # hash matching alone is NOT evidence of complete interpreter closure.
    fixture = safe_path(args.fixture)
    policy = safe_path(args.policy)
    previous = safe_path(args.e01_report)
    fixture_sha = hex_digest(bounded_read(fixture, 512_000))
    policy_sha = hex_digest(bounded_read(policy, 16_384))
    prior_sha = hex_digest(bounded_read(previous, 256_000))
    result = {
        "case_id": "E06I_A8_OFFLINE_SUPERVISED_CANDIDATE",
        "status": "HOLD",
        "reason": "INDEPENDENT_BOOTSTRAP_NOT_ESTABLISHED",
        "external_source_authentication": "UNPROVEN",
        "phase2a_e03_e04_e06": "UNPROVEN",
        "approval_b": "NOT_GRANTED_BY_THIS_SOURCE",
        "pinned_ap2_sha_claim": PINNED_AP2,
        "verifier_commit_claim": manifest["verifier_commit_claim"],
        "source_manifest_sha256": manifest_sha,
        "source_file_bytes_checked": verifier_bytes_before,
        "ap2_file_bytes_checked": upstream_bytes_before,
        "fixture_sha256": fixture_sha, "policy_sha256": policy_sha,
        "e01_source_report_sha256": prior_sha,
        "ruby_stage_result": "NOT_RUN",
        "oracle_result": "NOT_RUN",
        "no_host_authority": True,
        "evidence": None,
    }
    # Until independent OS bootstrap + immutable imports and approved B are
    # proven, this is only an offline research candidate. A future B may
    # authorize running under that boundary; source inspection does not.
    demand(args.future_b_execution_ack == "EXTERNAL_B_APPROVAL_REQUIRED",
           "B_EXECUTION_GATE_MISSING")
    with tempfile.TemporaryDirectory(prefix="e06i-a8-") as tmp:
        oracle_path = str(Path(tmp) / "independent.json")
        ruby_path = str(Path(tmp) / "ruby.json")
        python_oracle = source / (
            "research/phase2a_e06i/independent_closed_schema_oracle.py")
        ruby_observer = source / "research/phase2a_e06i/observe_integrated.rb"
        independent = [
            str(Path(sys.executable).resolve()), "-I", "-B",
            str(python_oracle), "--fixture", str(fixture),
            "--policy", str(policy), "--e01-report", str(previous),
            "--upstream-root", str(upstream), "--report", oracle_path
        ]
        if child_command(independent, 10) != 0:
            raise Stop("INDEPENDENT_ORACLE_FAILED")
        oracle, oracle_raw = json_document(oracle_path, 65_536)
        demand(oracle.get("case_id") == "E06I_A7_INDEPENDENT_CLOSED_SCHEMA" and
               oracle.get("pinned_ap2_sha") == PINNED_AP2 and
               oracle.get("source_fixture_sha256") == fixture_sha and
               oracle.get("source_policy_sha256") == policy_sha and
               oracle.get("source_e01_report_sha256") == prior_sha and
               type(oracle.get("cases")) is dict and
               set(oracle["cases"]) == set(IDS),
               "INDEPENDENT_ORACLE_NOT_BOUND")
        result["oracle_result"] = "CLAIM_ONLY_VALIDATED_STRUCTURE"
        ruby_command = [
            args.ruby_binary, str(ruby_observer),
            "--fixture", str(fixture), "--policy", str(policy),
            "--e01-report", str(previous), "--independent-oracle",
            oracle_path, "--upstream-root", str(upstream),
            "--report", ruby_path
        ]
        # Ruby intentionally returns 1 on EVERY path: even perfect observed
        # signed stage matching is HOLD until independent bootstrap verified.
        ruby_status = child_command(ruby_command, 10)
        if ruby_status != 1:
            raise Stop("RUBY_RETURNED_UNEXPECTED_STATUS")
        ruby_report, _ = json_document(ruby_path, 65_536)
        demand(ruby_report.get("case_id") ==
               "E06I_A7_SIGNED_G5_REACHABILITY" and
               ruby_report.get("status") == "HOLD" and
               ruby_report.get("source_provenance") ==
               "UNVERIFIED_EXTERNAL_RUNNER" and
               ruby_report.get("source_independent_oracle_sha256") ==
               hex_digest(oracle_raw) and
               type(ruby_report.get("case_outcomes_match")) is bool and
               type(ruby_report.get("case_results")) is dict and
               set(ruby_report["case_results"]) == set(IDS),
               "RUBY_STAGE_REPORT_NOT_BOUND")
        result["ruby_stage_result"] = (
            "SYNTHETIC_CASES_MATCH_CLAIM" if
            ruby_report["case_outcomes_match"] else "STAGE_MISMATCH")
        result["original_case_wire_sha256"] = {
            case: {
                field: ruby_report["case_results"][case].get(field)
                for field in ("root_wire_sha256", "terminal_wire_sha256",
                              "checkout_wire_sha256")
            } for case in IDS
        }
    # Repeat all digest checks after interpreters exit; this cannot
    # retrospectively prove the files were immutable while imports ran.
    attest_snapshot_files(source, manifest["verifier_files"], REQUIRED_VERIFIER)
    attest_snapshot_files(upstream, manifest["ap2_files"], REQUIRED_SCHEMAS)
    demand(hex_digest(bounded_read(fixture, 512_000)) == fixture_sha and
           hex_digest(bounded_read(policy, 16_384)) == policy_sha and
           hex_digest(bounded_read(previous, 256_000)) == prior_sha,
           "INPUT_CHANGED_BETWEEN_PROCESSES")
    # ALWAYS HOLD, even if independent cases match. Only a separate trusted
    # and authorized external bootstrap can establish source provenance.
    exclusive_json(args.final_report, result)
    return False


def main():
    parser = argparse.ArgumentParser()
    for name in ("verifier-root", "upstream-root", "fixture", "policy",
                 "e01-report", "source-manifest", "ruby-binary",
                 "final-report", "future-b-execution-ack"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    run(argparse.Namespace(**vars(args)))
    raise SystemExit(1)


if __name__ == "__main__":
    try:
        main()
    except (Stop, OSError, ValueError, KeyError, TypeError,
            UnicodeError, json.JSONDecodeError, subprocess.SubprocessError):
        # Never emit raw signed JWT/nonce/keys, stacktraces or partial claims.
        print("E06-I A8: HOLD; no trusted source or run proof",
              file=sys.stderr)
        raise SystemExit(1) from None
