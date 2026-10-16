"""Offline replay of the approved saved artifact, not fresh Debian acquisition.

The workflow alone obtains the fixed ZIP from GitHub. This program never
downloads data and never installs tools. Raw inputs are never re-uploaded.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import zipfile

ZIP_SIZE = 9375348
ZIP_SHA = "5e9d3309d65861b90d90bbd39109db0c4493ac37471fd08962c40c3aa6471c37"
FILES = {
    "main.InRelease": (151075, "77737fa4b34f2693e982cc9ee35736816c35a7778fc2d326cc1bbf5b301fe1aa"),
    "security.InRelease": (34770, "9e5050b09604010af7190f3e8391739d9fc7dc11616d1a25e90c7e25565e4f92"),
    "main.Packages.xz": (8790396, "9e0b5aabb2465b3d2e7a7fe27f9913846277833f7a2826e7767acccff5b588c5"),
    "security.Packages.xz": (349200, "816aa77b2d8d70c7f17494007692511bc6848598909cff4ee8fc642231c40007"),
    "main.asc": (11861, "c2a9a16fde95e037bafd0fa6b7e31f41b4ff1e85851de5558f19a2a2f0e955e2"),
    "security.asc": (11873, "74f81645b4e3156d1e9a88c8dd9259271b89c7099d64af89a2a6996b592faa1f"),
    "stable.asc": (461, "521e9f6a9f9b92ee8d5ce74345e8cfd04028dae9db6f571259d584b293549824"),
    "trixie.asc": (11861, "6f1d277429dd7ffedcc6f8688a7ad9a458859b1139ffa026d1eeaadcbffb0da7"),
    "bullseye_security.asc": (11873, "716e79393c724d14ecba8be46e99ecbe1b689f67ceff3cb3cab28f6e69e8b8b8"),
}
SOURCE_BLOB = "a98595437ccd119618fd412337bd3a845f6eda45"
BASH_SHA = "dfb21efd9ddf935a97cf5c4791c97f90bf2d8363b5be5db7ad19a95735513e1c"
CANDIDATE_BLOB = "1e3514be72367caed910ad31de9d7a9e4d0f5cb9"
ORACLE_BLOB = "4fa800d55753a89addd5447425d9fa1c73f6ef0b"


def need(ok):
    if not ok:
        raise ValueError("saved artifact replay rejected")


def bounded(path, limit):
    with path.open("rb") as stream:
        raw = stream.read(limit + 1)
    need(len(raw) <= limit)
    return raw


def git_blob(raw):
    return hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()


def extract_saved(zip_path, dest):
    raw = bounded(zip_path, ZIP_SIZE)
    need(len(raw) == ZIP_SIZE and hashlib.sha256(raw).hexdigest() == ZIP_SHA)
    dest.mkdir(mode=0o700)
    names = set(FILES) | {"SHA256SUMS.txt"}
    with zipfile.ZipFile(zip_path) as archive:
        entries = archive.infolist()
        need(len(entries) == 10 and {e.filename for e in entries} == names)
        need(sum(e.file_size for e in entries) <= 16 * 1024 * 1024)
        for entry in entries:
            need(not entry.is_dir() and not stat.S_ISLNK(entry.external_attr >> 16))
            need(not (entry.flag_bits & 1) and entry.compress_type in (0, 8))
            limit = FILES[entry.filename][0] if entry.filename in FILES else 4096
            need(entry.file_size <= limit and entry.compress_size <= ZIP_SIZE)
            with archive.open(entry) as stream:
                data = stream.read(limit + 1)
                need(len(data) == entry.file_size and not stream.read(1))
            # Exact allowlisted basenames only; never zipfile.extract().
            if entry.filename in FILES:
                size, digest = FILES[entry.filename]
                need(len(data) == size and hashlib.sha256(data).hexdigest() == digest)
            target = dest / entry.filename
            with target.open("xb") as out:
                out.write(data)
            target.chmod(0o400)
    seen = set()
    for line in (dest / "SHA256SUMS.txt").read_text("ascii").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  \./([A-Za-z0-9_.-]+)", line)
        need(match is not None)
        digest, name = match.groups()
        need(name in FILES and name not in seen and digest == FILES[name][1])
        seen.add(name)
    need(seen == set(FILES))


def signature_script(source, candidate):
    raw = bounded(source, 128 * 1024)
    need(git_blob(raw) == SOURCE_BLOB)
    marker = b"        run: |\n"
    need(raw.count(marker) == 1)
    lines = raw.split(marker, 1)[1].splitlines(keepends=True)
    need(all(line == b"\n" or line.startswith(b"          ") for line in lines))
    original = b"".join(line[10:] if line.startswith(b"          ") else line for line in lines)
    need(hashlib.sha256(original).hexdigest() == BASH_SHA)
    begin = b"cat > \"$work/p1m_debian_dependency_closure.py\" <<'P1M_PYTHON'\n"
    end = b"\nP1M_PYTHON\n"
    need(original.count(begin) == original.count(end) == 1)
    need(original.split(begin, 1)[1].split(end, 1)[0] + b"\n" == candidate)
    # Remove the entire network transport, not merely a conditional bypass.
    start = b"# Only approved HTTPS metadata sources."
    keys = b"# Debian official published primary key fingerprints are pinned here."
    finish = b"# P1-M source-only: no checkout, new URLs, install or network fallback."
    need(all(original.count(m) == 1 for m in (start, keys, finish)))
    offline = '''budget=$((16 * 1024 * 1024))
used=0
fetch() {
  local name bytes
  case "$1" in
    https://ftp-master.debian.org/keys/archive-key-12.asc) name=main.asc ;;
    https://ftp-master.debian.org/keys/archive-key-12-security.asc) name=security.asc ;;
    https://ftp-master.debian.org/keys/release-12.asc) name=stable.asc ;;
    https://ftp-master.debian.org/keys/archive-key-13.asc) name=trixie.asc ;;
    https://ftp-master.debian.org/keys/archive-key-11-security.asc) name=bullseye_security.asc ;;
    https://snapshot.debian.org/archive/debian/20261014T000000Z/dists/bookworm/InRelease) name=main.InRelease ;;
    https://snapshot.debian.org/archive/debian-security/20261014T000000Z/dists/bookworm-security/InRelease) name=security.InRelease ;;
    https://snapshot.debian.org/archive/debian/20261014T000000Z/dists/bookworm/main/binary-amd64/Packages.xz) name=main.Packages.xz ;;
    https://snapshot.debian.org/archive/debian-security/20261014T000000Z/dists/bookworm-security/main/binary-amd64/Packages.xz) name=security.Packages.xz ;;
    *) stop "saved input role not approved" ;;
  esac
  cp -- "$P1M_SAVED/$name" "$2" || stop "saved input unavailable"
  bytes=$(stat -c '%s' "$2")
  used=$((used + bytes))
  [ "$used" -le "$budget" ] || stop "saved body budget"
}
'''
    script = original.split(start, 1)[0] + offline.encode() + original.split(keys, 1)[1].split(finish, 1)[0]
    # The network function is gone. No curl invocation survives in this script.
    need(b"curl --" not in script)
    return script


def main():
    need(len(sys.argv) == 3 and sys.platform.startswith("linux"))
    zip_path, repo = map(Path, sys.argv[1:])
    base = repo / "research/phase2a_e06i"
    candidate = bounded(base / "p1m_debian_dependency_closure.py", 32768)
    oracle = bounded(base / "p1m_independent_oracle.py", 32768)
    need(git_blob(candidate) == CANDIDATE_BLOB and git_blob(oracle) == ORACLE_BLOB)
    need(Path("/usr/bin/dpkg").is_file())
    with tempfile.TemporaryDirectory(prefix="p1m-saved-") as tmp:
        work = Path(tmp)
        saved = work / "originals"
        extract_saved(zip_path, saved)
        print("SAVED_ARTIFACT=VERIFIED ORIGINAL_RUN=38851173209 FRESH_DEBIAN_FETCH=NONE", flush=True)
        script = work / "verify-signatures.sh"
        script.write_bytes(signature_script(repo / ".github/workflows/phase2a-p1-h4-metadata.yml", candidate))
        env = dict(os.environ, P1M_SAVED=str(saved))
        subprocess.run(["bash", str(script)], env=env, stdin=subprocess.DEVNULL, check=True, timeout=90)
        print("SAVED_SIGNATURES_AND_RUNTIME_VALID_UNTIL=VERIFIED", flush=True)
        subprocess.run([sys.executable, "-I", "-B", str(base / "p1m_independent_oracle.py"),
                        str(base / "p1m_debian_dependency_closure.py"),
                        str(saved / "main.Packages.xz"), str(saved / "security.Packages.xz")],
                       stdin=subprocess.DEVNULL, check=True, timeout=210)
        print("REPLAY_SCOPE=CANDIDATE_ONLY_RUNTIME_UNPROVEN", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("SAVED_REPLAY=STOP/HOLD", file=sys.stderr)
        sys.exit(1)
