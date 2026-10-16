"""Issue 73: independent *metadata candidate* oracle, never runtime proof.

Caller must authenticate both InRelease signatures/index digests first.
Only the approved frozen indexes and candidate source are accepted here.
No candidate imports: separate line parser, fixed-point graph construction,
and Debian Policy 5.6.12 version ordering (candidate uses external dpkg).
Policy: https://www.debian.org/doc/debian-policy/ch-controlfields.html
        https://www.debian.org/doc/debian-policy/ch-relationships.html
The deliberately restricted dependency subset excludes alternatives,
virtual packages, conflicts, breaks, architecture selectors and profiles.
Either implementation rejecting is HOLD, even when both reject. This does
not prove first-reject equivalence or installed/OCI/ELF dependency closure.
"""
import hashlib
import json
import lzma
from pathlib import Path
import re
import resource
import signal
import subprocess
import sys
import tempfile

INPUTS = (("main", 8790396,
           "9e0b5aabb2465b3d2e7a7fe27f9913846277833f7a2826e7767acccff5b588c5"),
          ("security", 349200,
           "816aa77b2d8d70c7f17494007692511bc6848598909cff4ee8fc642231c40007"))
CANDIDATE_BLOB = "8fc9fe8090dd3228fbaf9b75c83d48014bb3c0a9"
ROOTS = ("python3.11", "python3.11-minimal",
         "libpython3.11-minimal", "libpython3.11-stdlib")
VERSIONS = (("3.11.2-6+deb12u8", "main"), ("3.11.2-6+deb12u9", "security"))
FIELDS = ("package", "version", "architecture", "filename", "size", "sha256",
          "depends", "pre-depends", "provides", "conflicts", "breaks")
STAGE = "PREFLIGHT"


class Hold(Exception):
    pass


def require(condition):
    if not condition:
        raise Hold()


def version_parts(value):
    require(0 < len(value) <= 128 and value.isascii())
    epoch, sep, tail = value.partition(":")
    if sep:
        require(epoch.isdigit())
        epoch = int(epoch)
    else:
        epoch, tail = 0, value
    upstream, dash, revision = tail.rpartition("-")
    if not dash:
        upstream, revision = tail, "0"
    require(re.fullmatch(r"[0-9][A-Za-z0-9.+~\-]*", upstream) is not None)
    require(re.fullmatch(r"[A-Za-z0-9.+~]+", revision) is not None)
    return epoch, upstream, revision


def part_order(left, right):
    # Policy's alternating non-digit lexical / digit numerical runs.
    def rank(char):
        if char == "~":
            return -1
        if not char or char.isdigit():
            return 0
        return ord(char) if char.isalpha() else ord(char) + 256
    while left or right:
        while (left and not left[0].isdigit()) or (right and not right[0].isdigit()):
            a, b = rank(left[:1]), rank(right[:1])
            if a != b:
                return (a > b) - (a < b)
            left, right = left[1:], right[1:]
        a = re.match(r"[0-9]*", left)[0]
        b = re.match(r"[0-9]*", right)[0]
        av, bv = int(a or "0"), int(b or "0")
        if av != bv:
            return (av > bv) - (av < bv)
        left, right = left[len(a):], right[len(b):]
    return 0


def compare(left, right):
    le, lu, lr = version_parts(left)
    re_, ru, rr = version_parts(right)
    return ((le > re_) - (le < re_)) or part_order(lu, ru) or part_order(lr, rr)


def check_record(fields):
    require(all(fields.get(k) for k in FIELDS[:6]))
    require(re.fullmatch(r"[a-z0-9][a-z0-9+.-]{1,127}", fields["package"]) is not None)
    version_parts(fields["version"])
    require(fields["architecture"] in ("amd64", "all"))
    filename = fields["filename"]
    require(re.fullmatch(r"pool/[A-Za-z0-9_+./~\-]{1,512}", filename) is not None)
    require(not any(p in ("", ".", "..") for p in filename.split("/")))
    require(re.fullmatch(r"[1-9][0-9]{0,19}", fields["size"]) is not None)
    require(re.fullmatch(r"[0-9a-f]{64}", fields["sha256"]) is not None)
    return fields


def records(path):
    # Bounded line reader instead of candidate's bytewise stanza splitter.
    total = size = count = 0
    fields, seen, current = {}, set(), None
    with lzma.open(path, "rb") as stream:
        while True:
            line = stream.readline(16385)
            if not line:
                if size:
                    count += 1
                    require(count <= 120000)
                    yield check_record(fields)
                require(count > 0)
                return
            total += len(line)
            size += len(line)
            require(total <= 128 * 1024 * 1024 and size <= 16384)
            require(line.endswith(b"\n"))
            if line == b"\n":
                count += 1
                require(count <= 120000)
                yield check_record(fields)
                fields, seen, current, size = {}, set(), None, 0
                continue
            text = line[:-1].decode("utf-8", "strict")
            require(not any((ord(c) < 32 and c != "\t") or
                            127 <= ord(c) <= 159 or c in "\u2028\u2029" for c in text))
            if text[0] in " \t":
                require(current is not None and current not in FIELDS and text.strip(" \t"))
                continue
            name, colon, value = text.partition(":")
            require(colon and name and name[0] not in "#-")
            require(all(33 <= ord(c) <= 126 and c != ":" for c in name))
            current = name.lower()
            require(current not in seen)
            seen.add(current)
            if current in FIELDS:
                # Keep exact value bytes for the manifest. Noncanonical
                # whitespace is unsupported, rather than normalized away.
                require(value.startswith(" ") and value[1:] == value[1:].strip(" \t"))
                fields[current] = value[1:]


def expected_report(paths):
    global STAGE
    STAGE = "ORACLE_INDEX"
    inventory, names, counts = {}, {}, []
    for path, (origin, _, _) in zip(paths, INPUTS):
        count = 0
        for fields in records(path):
            count += 1
            key = tuple(fields[k] for k in FIELDS[:3])
            if key in inventory:
                require(inventory[key][0] == fields)
            else:
                inventory[key] = fields, origin
                names.setdefault(key[0], []).append(key)
        counts.append(count)
    STAGE = "ORACLE_GRAPH"
    candidates = []
    for version, origin in VERSIONS:
        selected = {(name, version, "amd64") for name in ROOTS}
        require(all(k in inventory and inventory[k][1] == origin for k in selected))
        processed, constraints, edges = set(), 0, 0
        # Independent fixed point over sorted frontiers, not candidate BFS.
        while selected != processed:
            require(len(selected) <= 512)
            require(len({k[0] for k in selected}) == len(selected))
            additions = set()
            for key in sorted(selected - processed):
                item = inventory[key][0]
                require(not any(item.get(f) for f in ("provides", "conflicts", "breaks")))
                relations = []
                for field in ("pre-depends", "depends"):
                    if item.get(field):
                        relations.extend(item[field].split(","))
                require(len(relations) <= 1024)
                edges += len(relations)
                require(edges <= 4096)
                for relation in relations:
                    # No OR, multiarch, virtual, profile or implicit choice.
                    parts = relation.strip().split()
                    require(len(parts) in (1, 3))
                    name = parts[0]
                    require(re.fullmatch(r"[a-z0-9][a-z0-9+.-]{1,127}", name) is not None)
                    op, wanted = None, None
                    if len(parts) == 3:
                        require(parts[1].startswith("(") and parts[2].endswith(")"))
                        op, wanted = parts[1][1:], parts[2][:-1]
                        require(op in ("<<", "<=", "=", ">=", ">>"))
                        version_parts(wanted)
                    matches = []
                    for option in names.get(name, ()):
                        constraints += 1
                        require(constraints <= 4096)
                        if op is None:
                            matches.append(option)
                        else:
                            order = compare(option[1], wanted)
                            if {"<<": order < 0, "<=": order <= 0, "=": order == 0,
                                ">=": order >= 0, ">>": order > 0}[op]:
                                matches.append(option)
                    require(len(matches) == 1)
                    additions.add(matches[0])
                processed.add(key)
            selected.update(additions)
        manifest = []
        for key in sorted(selected):
            item, archive = inventory[key]
            manifest.append([*key, archive, *[item.get(f, "") for f in
                             ("filename", "size", "sha256", "depends", "pre-depends")]])
        digest = hashlib.sha256(json.dumps(manifest, ensure_ascii=True,
                                          separators=(",", ":")).encode()).hexdigest()
        candidates.append({"version": version, "candidate_nodes": len(selected),
                           "graph_sha256": digest})
    return {"status": "CANDIDATE_ONLY_RUNTIME_UNPROVEN",
            "index_stanzas": counts, "candidates": candidates}


def bounded_bytes(path, limit):
    with path.open("rb") as stream:
        data = stream.read(limit + 1)
    require(len(data) <= limit)
    return data


def main():
    global STAGE
    require(len(sys.argv) == 4)
    candidate, *paths = map(Path, sys.argv[1:])
    resource.setrlimit(resource.RLIMIT_AS, (1024 * 1024 * 1024,) * 2)
    resource.setrlimit(resource.RLIMIT_FSIZE, (8192,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (150,) * 2)
    signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(Hold()))
    signal.alarm(180)
    code = bounded_bytes(candidate, 32768)
    blob = b"blob " + str(len(code)).encode() + b"\0" + code
    require(hashlib.sha1(blob).hexdigest() == CANDIDATE_BLOB)
    for path, (_, size, digest) in zip(paths, INPUTS):
        raw = bounded_bytes(path, size)
        require(len(raw) == size and hashlib.sha256(raw).hexdigest() == digest)
    del raw, code, blob
    STAGE = "CANDIDATE"
    # Execute once, never import; private regular files cap output on disk.
    # Do not echo candidate stderr, paths, JSON values or tracebacks.
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        result = subprocess.run([sys.executable, "-I", "-B", str(candidate),
                                 "--main", str(paths[0]), "--security", str(paths[1])],
                                stdin=subprocess.DEVNULL, stdout=out, stderr=err,
                                timeout=120, check=False)
        out.seek(0)
        err.seek(0)
        stdout, stderr = out.read(8193), err.read(8193)
    require(len(stdout) <= 8192 and len(stderr) <= 8192)
    candidate_ok = result.returncode == 0 and not stderr
    print("P1M_CANDIDATE_EXIT=" + ("ZERO" if candidate_ok else "NONZERO_OR_STDERR"), flush=True)
    rejection = re.fullmatch(rb"P1M_STATUS=STOP/HOLD:([A-Z_]{1,64})\n", stderr)
    if rejection and not candidate_ok:
        print("P1M_CANDIDATE_REJECT=" + rejection[1].decode("ascii"), flush=True)
    # Oracle derives expected results from indexes, even if candidate failed.
    expected = expected_report(paths)
    STAGE = "COMPARISON"
    require(candidate_ok)
    wire = ("P1M_DEPENDENCY_GRAPH=" + json.dumps(expected, sort_keys=True,
            separators=(",", ":")) + "\nP1M_RUNTIME_LOAD_PATHS=UNVERIFIED/HOLD\n").encode()
    require(stdout == wire)
    print("P1M_ORACLE=METADATA_CANDIDATE_MATCH")
    print(wire.decode(), end="")
    print("P1M_ORACLE_RUNTIME=UNVERIFIED/HOLD")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # STAGE is internal, never derived from an exception/input value.
        print("P1M_ORACLE=STOP/HOLD STAGE=" + STAGE, file=sys.stderr)
        sys.exit(1)
