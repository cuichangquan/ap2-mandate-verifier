"""Relocation-only checks using existing local Git objects; no verifier execution."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
BASE = "c8d81eab49e37a1236a355d42cf667aab552392d"
ARCHIVE = "research/stage11/archive/"


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], check=True,
                          capture_output=True, timeout=10).stdout


def original(name):
    return git("show", BASE + ":" + name)


def check(ok, why):
    if not ok:
        raise AssertionError(why)


def main():
    baseline = git("ls-tree", "-r", "--name-only", BASE).decode().splitlines()
    expected = sorted(n for n in baseline if "/" not in n and
                      ((n.startswith("STAGE11_") and n.endswith(".json") and
                        n != "STAGE11_MANIFEST.json") or
                       n in {"O1O3_REPORT.json", "O2O5_FINAL_REPORT.json", "O4_VERIFIED_REPORT.json"}))
    ledger = json.loads((ROOT / "docs/RESEARCH_PATH_MIGRATION.json").read_bytes())
    check(ledger["baseline_main"] == BASE, "baseline identity")
    rows = ledger["moved"]
    check(len(rows) == 30 and sorted(x["old_path"] for x in rows) == expected,
          "exact thirty original paths")
    for row in rows:
        old = row["old_path"]
        check(row["new_path"] == ARCHIVE + old, "exact destination")
        dest = ROOT / row["new_path"]
        check(dest.is_file() and not dest.is_symlink(), "regular destination")
        raw = dest.read_bytes()
        check(raw == original(old), "original Git blob bytes: " + old)
        check(len(raw) == row["bytes"] and hashlib.sha256(raw).hexdigest() == row["sha256"],
              "ledger bytes/SHA256: " + old)
        check(not (ROOT / old).exists() and not (ROOT / old).is_symlink(), "old path absent")

    substitutions = {
        "test/stage11_report_boundary_test.py": {
            "STAGE11_SNAPSHOT_GEM_REPLAY_6.json": 1,
            "STAGE11_SNAPSHOT_GEM_REPLAY_32.json": 2,
            "STAGE11_SNAPSHOT_O2O5_REPORT.json": 1},
        "test/stage11_io_test.py": {
            "STAGE11_IO_GEM_REPLAY_32.json": 1,
            "STAGE11_IO_O2O5_REPORT.json": 1}}
    for name, names in substitutions.items():
        raw = original(name)
        for old, count in names.items():
            quoted = ("'" + old + "'").encode()
            check(raw.count(quoted) == count, "original reference count")
            raw = raw.replace(quoted, ("'" + ARCHIVE + old + "'").encode())
        check((ROOT / name).read_bytes() == raw, "six path-only substitutions")

    payloads = [n for n in baseline if n.startswith("lib/") and n.endswith(".rb")]
    payloads += ["README.md", "LICENSE", "docs/SUPPORT_CONTRACT.md"]
    check(len(payloads) == 13, "fixed package whitelist")
    protected = payloads + ["ap2_mandate_verifier.gemspec"] + ledger["deferred_active_files"]
    for name in protected:
        check((ROOT / name).read_bytes() == original(name), "unchanged protected file: " + name)
    for name, digest in ledger["package13_and_gemspec_sha256_unchanged"].items():
        check(name in payloads + ["ap2_mandate_verifier.gemspec"], "package ledger whitelist")
        check(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, "package ledger SHA")
    print("PASS relocation-only: 30 original blobs/bytes/SHA/destinations, 6 reference substitutions, "
          "13 payloads+gemspec and 10 deferred files unchanged; no historical verifier revalidation")


if __name__ == "__main__":
    main()
