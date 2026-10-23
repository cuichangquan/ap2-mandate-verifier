"""Bounded relocation/pin inventory checks, not a verifier/Oracle execution."""
import ast
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
BASE = "a8befd0b2aa79334cb843efd382a7b32a21de47f"


def old(name):
    return subprocess.run(["git", "-C", str(ROOT), "show", BASE + ":" + name],
                          capture_output=True, check=True, timeout=10).stdout


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def literal(source, name):
    for node in ast.parse(source).body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == name for t in node.targets):
            return ast.literal_eval(node.value)
    raise AssertionError("missing literal " + name)


def main():
    inventory = json.loads((ROOT / "docs/RESEARCH_COMPLETE_LAYOUT.json").read_bytes())
    assert inventory["base_commit"] == BASE
    assert len(inventory["moves"]) == 79
    changed = inventory["modified_moved_sources"]
    for row in inventory["moves"]:
        raw = old(row["old_path"])
        assert len(raw) == row["bytes"] and sha(raw) == row["sha256"]
        path = ROOT / row["new_path"]
        assert path.is_file() and not path.is_symlink()
        current = path.read_bytes()
        if row["new_path"] in changed:
            assert path.suffix in {".rb", ".py"} and sha(current) == changed[row["new_path"]]
        else:
            assert current == raw, row["new_path"]
        assert not (ROOT / row["old_path"]).exists()
    for name in ["packaging_candidate", "security_json", "stage15", "stage15_linux", "stage18_linux_package"]:
        assert not (ROOT / name).exists() and (ROOT / "research" / name).is_dir()
    before = old("test/stage11_identity.py")
    after = (ROOT / "test/stage11_identity.py").read_bytes()
    for key in ["PINS", "LOCKS", "PYTHON", "DEPENDENCIES"]:
        assert literal(before, key) == literal(after, key), key
    for name, digest in literal(after, "PINS").items():
        assert sha((ROOT / "research/stage11/inputs" / name).read_bytes()) == digest
    for name, digest in literal(after, "LOCKS").items():
        assert sha((ROOT / "research/stage11/dependencies" / name).read_bytes()) == digest
    protected = json.loads((ROOT / "docs/RESEARCH_PATH_MIGRATION.json").read_bytes())["package13_and_gemspec_sha256_unchanged"]
    assert len(protected) == 14
    for name, digest in protected.items():
        assert (ROOT / name).read_bytes() == old(name) and sha(old(name)) == digest
    for folder, field in [("stage15_linux", "captured_sources"), ("stage18_linux_package", "files_sha256")]:
        root = ROOT / "research" / folder
        manifest = json.loads((root / "CURRENT_MANIFEST.json").read_bytes())
        assert manifest["historical_manifest_sha256"] == sha((root / "MANIFEST.json").read_bytes())
        assert manifest["validation_status"].startswith("NOT_RUN")
        for name, digest in manifest[field].items():
            assert sha((ROOT / name).read_bytes()) == digest, name
        for name, digest in manifest.get("captured_inputs", {}).items():
            assert sha((ROOT / name).read_bytes()) == digest
        workflow = ROOT / ".github/workflows" / ("stage15-linux-once.yml" if folder == "stage15_linux" else "stage18-linux-package.yml")
        assert sha((root / "CURRENT_MANIFEST.json").read_bytes()) in workflow.read_text()
    adapter = ROOT / "research/stage15/compare.py"
    security = (ROOT / "research/security_json/compare.py").read_bytes()
    assert literal(security, "CURRENT_ADAPTER_SHA") == sha(adapter.read_bytes())
    print("PASS layout:79 original inventories, immutable data/history,6 inputs/locks,5 directories,logical pins,14 protected files,2 current manifests; no Oracle/Verifier run")


if __name__ == "__main__":
    main()
