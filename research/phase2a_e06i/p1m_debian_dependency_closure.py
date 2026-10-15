"""P1-M research only: bounded *candidate* Debian dependency graph.

Caller MUST verify both InRelease signatures, signed index sizes/SHA256, and
xz integrity before invoking this parser. This program is NOT its own trust
anchor; neither a zero exit nor a closed graph attests the installed OCI/ELF
or runtime import paths. No downloads, installers, container, or fixture.
"""
import argparse
from collections import deque
import hashlib
import json
import lzma
import re
import subprocess
import sys

MAX_DECOMPRESSED = 128 * 1024 * 1024
MAX_STANZA = 16384
MAX_PACKAGES = 120000
MAX_NODES = 512
MAX_CHECKS = 4096
MAX_REPORT = 4096
ROOTS = ("python3.11", "python3.11-minimal",
         "libpython3.11-minimal", "libpython3.11-stdlib")
NAME = re.compile(r"[a-z0-9][a-z0-9+.-]{0,127}\Z")
VERSION = re.compile(r"[0-9][A-Za-z0-9.+:~\-]{0,127}\Z")
REL = re.compile(r"([a-z0-9][a-z0-9+.-]{0,127})"
                 r"(?: \((<<|<=|=|>=|>>) ([0-9A-Za-z.+:~\-]{1,128})\))?\Z")
FILENAME = re.compile(r"pool/[a-zA-Z0-9_+./-]{1,512}\Z")
SHA = re.compile(r"[a-f0-9]{64}\Z")
KEYS = frozenset(("Package", "Version", "Architecture", "Depends",
                  "Pre-Depends", "Provides", "Conflicts", "Breaks",
                  "Filename", "Size", "SHA256"))

class Hold(Exception):
    pass

def demand(ok, reason):
    if not ok:
        raise Hold(reason)

def paragraphs(path):
    # Bounded decompression and stanza handling; never read an unbounded line.
    total = 0
    stanza = bytearray()
    with lzma.open(path, "rb") as stream:
        while True:
            chunk = stream.read(65536)
            if not chunk:
                break
            total += len(chunk)
            demand(total <= MAX_DECOMPRESSED, "DECOMPRESSED_LIMIT")
            for byte in chunk:
                stanza.append(byte)
                demand(len(stanza) <= MAX_STANZA, "STANZA_LIMIT")
                if byte == 10 and stanza.endswith(b"\n\n"):
                    yield bytes(stanza)
                    stanza.clear()
    if stanza:
        demand(stanza.endswith(b"\n"), "UNTERMINATED_STANZA")
        yield bytes(stanza)

def record(raw):
    try:
        lines = raw.decode("utf-8", "strict").splitlines()
    except UnicodeError as exc:
        raise Hold("INVALID_UTF8") from exc
    fields = {}
    current = None
    for line in lines:
        if not line:
            continue
        if line[0] in (" ", "\t"):
            demand(current not in KEYS, "CONTINUED_SECURITY_FIELD")
            continue
        demand(": " in line, "MALFORMED_FIELD")
        key, value = line.split(": ", 1)
        current = key
        if key in KEYS:
            demand(key not in fields and len(value) <= 1024,
                   "DUPLICATE_OR_OVERSIZE_FIELD")
            fields[key] = value
    for key in ("Package", "Version", "Architecture", "Filename", "Size", "SHA256"):
        demand(key in fields, "MISSING_REQUIRED_FIELD")
    name, version, arch = (fields[k] for k in ("Package", "Version", "Architecture"))
    demand(NAME.fullmatch(name) and VERSION.fullmatch(version), "INVALID_IDENTITY")
    demand(arch in ("amd64", "all"), "INVALID_ARCH")
    filename = fields["Filename"]
    demand(FILENAME.fullmatch(filename) and ".." not in filename.split("/"),
           "INVALID_FILENAME")
    demand(fields["Size"].isascii() and fields["Size"].isdigit()
           and 0 < int(fields["Size"]) <= 1024 * 1024 * 1024, "INVALID_SIZE")
    demand(SHA.fullmatch(fields["SHA256"]), "INVALID_SHA")
    return fields

def load(path, origin, inventory):
    n = 0
    for raw in paragraphs(path):
        if not raw.strip():
            continue
        n += 1
        demand(n <= MAX_PACKAGES, "PACKAGE_LIMIT")
        item = record(raw)
        key = (item["Package"], item["Version"], item["Architecture"])
        prev = inventory.get(key)
        if prev:
            # Same tuple in two archives must refer to the SAME exact artifact.
            demand(all(prev[0].get(k) == item.get(k) for k in KEYS),
                   "DUPLICATE_CONFLICT")
        else:
            inventory[key] = (item, origin)
    demand(n > 0, "EMPTY_INDEX")
    return n

def edges(item):
    for field in ("Pre-Depends", "Depends"):
        text = item.get(field, "")
        demand(len(text) <= 1024, "DEPENDENCY_LIMIT")
        if not text:
            continue
        for group in text.split(","):
            # Do not silently choose OR alternatives, architecture selectors,
            # virtual Provides or build profiles; they require an OS baseline.
            demand("|" not in group and "[" not in group and "]" not in group,
                   "UNRESOLVED_ALTERNATIVE_OR_PROFILE")
            match = REL.fullmatch(group.strip())
            demand(match is not None, "UNSUPPORTED_DEPENDENCY")
            name, operator, version = match.groups()
            demand(operator is None or VERSION.fullmatch(version),
                   "INVALID_CONSTRAINT")
            yield field, name, operator, version

def satisfies(actual, op, wanted, state):
    if op is None:
        return True
    demand(state[0] < MAX_CHECKS, "VERSION_CHECK_LIMIT")
    state[0] += 1
    # dpkg's Debian-policy version ordering is authoritative; no shell.
    args = ["/usr/bin/dpkg", "--compare-versions", actual, op, wanted]
    try:
        proc = subprocess.run(args, stdin=subprocess.DEVNULL,
                              stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL,
                              timeout=2, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Hold("DPKG_COMPARATOR_UNAVAILABLE") from exc
    demand(proc.returncode in (0, 1), "DPKG_COMPARATOR_FAILURE")
    return proc.returncode == 0

def graph(inventory, root_version):
    roots = []
    root_origin = ("main" if root_version.endswith("deb12u8")
                   else "security" if root_version.endswith("deb12u9")
                   else None)
    demand(root_origin is not None, "UNAPPROVED_ROOT_VERSION")
    for name in ROOTS:
        options = [(k, v) for k, v in inventory.items()
                   if k[0] == name and k[1] == root_version and k[2] == "amd64"
                   and v[1] == root_origin]
        demand(len(options) == 1, "ROOT_MISSING_OR_AMBIGUOUS")
        roots.append(options[0][0])
    selected = set()
    queue = deque(roots)
    constraints = [0]
    while queue:
        key = queue.popleft()
        if key in selected:
            continue
        demand(len(selected) < MAX_NODES, "GRAPH_NODE_LIMIT")
        selected.add(key)
        item = inventory[key][0]
        # Provides/Conflicts/Breaks require an authenticated dpkg baseline;
        # never report a uniquely resolved graph without those semantics.
        demand(not any(item.get(k) for k in ("Provides", "Conflicts", "Breaks")),
               "BASELINE_OR_VIRTUAL_SEMANTICS_UNKNOWN")
        for _, name, op, required in edges(item):
            choices = [k for k in inventory if k[0] == name
                       and k[2] in ("amd64", "all")
                       and satisfies(k[1], op, required, constraints)]
            demand(choices, "DEPENDENCY_UNAVAILABLE")
            demand(len(choices) == 1, "DEPENDENCY_AMBIGUOUS")
            queue.append(choices[0])
    # Candidate graph only; installed base and shared-object paths unknown.
    # Bind candidate nodes to signed-index archive file metadata as trace
    # evidence only; does not authenticate downloaded/installed .deb bytes.
    manifest = [[*key, inventory[key][1],
                 *[inventory[key][0].get(field, "") for field in
                   ("Filename", "Size", "SHA256", "Depends", "Pre-Depends")]]
                for key in sorted(selected)]
    digest = hashlib.sha256(json.dumps(manifest, separators=(",", ":"),
                                      ensure_ascii=True).encode()).hexdigest()
    return len(selected), digest

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--main", required=True)
    ap.add_argument("--security", required=True)
    args = ap.parse_args()
    inventory = {}
    counts = (load(args.main, "main", inventory),
              load(args.security, "security", inventory))
    output = []
    for version in ("3.11.2-6+deb12u8", "3.11.2-6+deb12u9"):
        nodes, digest = graph(inventory, version)
        output.append({"version": version, "candidate_nodes": nodes,
                       "graph_sha256": digest})
    result = json.dumps({"status": "CANDIDATE_ONLY_RUNTIME_UNPROVEN",
                         "index_stanzas": counts, "candidates": output},
                        sort_keys=True, separators=(",", ":"))
    demand(len(result) <= MAX_REPORT, "REPORT_LIMIT")
    print("P1M_DEPENDENCY_GRAPH=" + result)
    print("P1M_RUNTIME_LOAD_PATHS=UNVERIFIED/HOLD")

if __name__ == "__main__":
    try:
        main()
    except (Hold, OSError, ValueError, lzma.LZMAError) as exc:
        code = str(exc)
        # Only known internally generated labels; avoid printing raw paths.
        known = ("DECOMPRESSED_LIMIT", "STANZA_LIMIT", "PACKAGE_LIMIT",
                 "INVALID_UTF8", "MALFORMED_FIELD", "DUPLICATE_OR_OVERSIZE_FIELD",
                 "MISSING_REQUIRED_FIELD", "INVALID_IDENTITY", "INVALID_ARCH",
                 "INVALID_FILENAME", "INVALID_SIZE", "INVALID_SHA",
                 "DUPLICATE_CONFLICT", "EMPTY_INDEX", "DEPENDENCY_LIMIT",
                 "UNRESOLVED_ALTERNATIVE_OR_PROFILE", "UNSUPPORTED_DEPENDENCY",
                 "INVALID_CONSTRAINT", "VERSION_CHECK_LIMIT",
                 "DPKG_COMPARATOR_UNAVAILABLE", "DPKG_COMPARATOR_FAILURE",
                 "ROOT_MISSING_OR_AMBIGUOUS", "UNAPPROVED_ROOT_VERSION",
                 "GRAPH_NODE_LIMIT",
                 "DEPENDENCY_UNAVAILABLE", "DEPENDENCY_AMBIGUOUS", "REPORT_LIMIT",
                 "UNTERMINATED_STANZA", "CONTINUED_SECURITY_FIELD",
                 "BASELINE_OR_VIRTUAL_SEMANTICS_UNKNOWN")
        print("P1M_STATUS=STOP/HOLD:" + (code if code in known else "PARSE_ERROR"),
              file=sys.stderr)
        sys.exit(1)
