"""U1: bounded snapshot-to-object *data* verification, never a Git writer.

No CLI, filesystem, process, network, SDK import or signature verification.
Pins are caller-supplied expectations, not authenticated authority. The single
LF-preserving serializer is synthetic-tested; official AP2 compatibility and
Git database/reader behavior remain untested by this module's tests.
"""
from dataclasses import dataclass
import hashlib
import re
import unicodedata
import zlib


class Stop(ValueError):
    """Fail closed with a bounded code, never untrusted contents."""


def need(ok, code):
    if not ok:
        raise Stop(code)


@dataclass(frozen=True)
class Limits:
    compressed: int = 8 * 1024 * 1024
    expanded: int = 8 * 1024 * 1024
    file: int = 1024 * 1024
    entries: int = 1024
    path: int = 1024


@dataclass(frozen=True)
class Pin:
    oid: str
    size: int
    sha256: str


@dataclass(frozen=True)
class File:
    path: str
    mode: str
    pin: Pin


@dataclass(frozen=True)
class Tree:
    path: str  # Empty only for the root tree.
    pin: Pin


@dataclass(frozen=True)
class Commit:
    pin: Pin
    tree: str
    parents: tuple
    payload: bytes  # Exact unsigned verification payload, not reconstructed dates.
    signature: bytes


@dataclass(frozen=True)
class Spec:
    prefix: str
    archive_size: int
    archive_sha256: str
    files: tuple
    trees: tuple
    commit: Commit


@dataclass(frozen=True)
class ObjectData:
    kind: str
    oid: str
    payload: bytes
    sha256: str


@dataclass(frozen=True)
class SnapshotData:
    objects: tuple
    files: tuple
    shallow_boundary: str
    expanded_bytes: int
    authority: str = "CALLER_PINS_NOT_AUTHENTICATED"
    status: str = "PURE_DATA_MATCH_NOT_GIT_DATABASE_OR_RUNTIME_PROOF"


SERIALIZER = "LF_PRESERVING_GPGSIG_V1"
HEX40 = re.compile(r"[0-9a-f]{40}")
HEX64 = re.compile(r"[0-9a-f]{64}")


def digest(kind, raw):
    need(kind in ("blob", "tree", "commit") and type(raw) is bytes, "OBJECT_TYPE")
    return hashlib.sha1(kind.encode() + b" " + str(len(raw)).encode() + b"\0" + raw).hexdigest()


def limits_checked(limits):
    need(type(limits) is Limits, "LIMIT_TYPE")
    for key in ("compressed", "expanded", "file", "entries", "path"):
        value = getattr(limits, key)
        need(type(value) is int and 0 < value <= getattr(Limits(), key), "LIMIT_RANGE")


def pin_checked(pin, cap):
    need(type(pin) is Pin and type(pin.oid) is str and HEX40.fullmatch(pin.oid) and
         type(pin.sha256) is str and HEX64.fullmatch(pin.sha256) and
         type(pin.size) is int and 0 <= pin.size <= cap, "PIN")


def checked_object(kind, raw, pin, cap):
    pin_checked(pin, cap)
    need(type(raw) is bytes and len(raw) == pin.size and
         hashlib.sha256(raw).hexdigest() == pin.sha256 and digest(kind, raw) == pin.oid,
         "OBJECT_PIN_MISMATCH")
    return ObjectData(kind, pin.oid, raw, pin.sha256)


def safe_path(path, cap):
    need(type(path) is str and path and len(path) <= cap and
         len(path.encode("utf-8", "surrogatepass")) <= cap,
         "PATH")
    try:
        path.encode("utf-8", "strict")
    except UnicodeError:
        raise Stop("PATH_ENCODING") from None
    need(not path.startswith("/") and "\\" not in path and
         not any(ord(c) < 32 or ord(c) == 127 for c in path), "PATH")
    parts = path.split("/")
    need(all(p not in ("", ".", "..") and p.casefold() != ".git" and
             not p.endswith((".", " ")) for p in parts), "PATH")
    return unicodedata.normalize("NFC", path).casefold()


def commit_data(commit):
    """One encoder only: fold EVERY signature LF, preserving its final LF.

    No whitespace search/fallback and no normalization of payload or message.
    A different official encoding must STOP, then be independently reviewed.
    """
    need(type(commit) is Commit, "COMMIT_TYPE")
    pin_checked(commit.pin, 4096)
    need(type(commit.tree) is str and HEX40.fullmatch(commit.tree) and
         type(commit.parents) is tuple and len(commit.parents) <= 8 and
         all(type(p) is str and HEX40.fullmatch(p) for p in commit.parents) and
         len(set(commit.parents)) == len(commit.parents), "COMMIT_REFERENCES")
    p, s = commit.payload, commit.signature
    need(type(p) is bytes and 0 < len(p) <= 4096 and type(s) is bytes and
         0 < len(s) <= 2048 and b"\0" not in p and b"\r" not in p,
         "COMMIT_BYTES")
    need(s.startswith(b"-----BEGIN PGP SIGNATURE-----\n") and
         s.endswith(b"-----END PGP SIGNATURE-----\n") and
         all(c == 10 or 32 <= c < 127 for c in s), "SIGNATURE_FORMAT")
    headers, boundary, message = p.partition(b"\n\n")
    need(boundary, "COMMIT_BOUNDARY")
    lines = headers.split(b"\n")
    references = [b"tree " + commit.tree.encode()] + [b"parent " + x.encode() for x in commit.parents]
    need(len(lines) == len(references) + 2 and lines[:-2] == references, "COMMIT_HEADERS")
    for line, role in zip(lines[-2:], (b"author", b"committer")):
        need(len(line) <= 512 and
             re.fullmatch(role + rb" [^\x00-\x1f<>]+ <[^\x00-\x20<>]+> [0-9]{1,12} [+-][0-9]{4}", line),
             "COMMIT_IDENTITY")
        zone = line[-4:]
        need(int(zone[:2]) <= 23 and int(zone[2:]) <= 59, "COMMIT_TIMEZONE")
    raw = headers + b"\ngpgsig " + s.replace(b"\n", b"\n ") + b"\n\n" + message
    return checked_object("commit", raw, commit.pin, 4096)


def manifest_checked(spec, limits):
    need(type(spec) is Spec and type(spec.commit) is Commit and
         type(spec.files) is tuple and type(spec.trees) is tuple and
         len(spec.files) + len(spec.trees) <= limits.entries and
         all(type(x) is File for x in spec.files) and
         all(type(x) is Tree for x in spec.trees), "SPEC")
    pin_checked(spec.commit.pin, 4096)
    need(type(spec.prefix) is str and spec.prefix == "AP2-" + spec.commit.pin.oid and
         type(spec.archive_size) is int and 0 < spec.archive_size <= limits.compressed and
         type(spec.archive_sha256) is str and HEX64.fullmatch(spec.archive_sha256), "ARCHIVE_PIN")
    files, trees, aliases = {}, {}, set()
    for entry in spec.files + spec.trees:
        need(type(entry) in (File, Tree), "ENTRY_TYPE")
        is_file = type(entry) is File
        pin_checked(entry.pin, limits.file if is_file else limits.expanded)
        need(type(entry.path) is str, "PATH")
        if is_file:
            need(type(entry.mode) is str and entry.mode in ("100644", "100755"), "FILE_MODE")
        if not is_file and entry.path == "":
            alias = ""
        else:
            alias = safe_path(entry.path, limits.path)
        need(alias not in aliases, "PATH_COLLISION")
        aliases.add(alias)
        (files if is_file else trees)[entry.path] = entry
    need("" in trees and trees[""].pin.oid == spec.commit.tree, "ROOT_TREE")
    for path in tuple(files) + tuple(trees):
        if path:
            need(path.rpartition("/")[0] in trees, "MISSING_PARENT_TREE")
    return files, trees


def expanded_gzip(archive, spec, limits):
    need(type(archive) is bytes and len(archive) == spec.archive_size and
         hashlib.sha256(archive).hexdigest() == spec.archive_sha256, "ARCHIVE_BYTES")
    try:
        decoder = zlib.decompressobj(31)
        raw = decoder.decompress(archive, limits.expanded + 1)
    except zlib.error:
        raise Stop("GZIP_FORMAT") from None
    need(len(raw) <= limits.expanded, "EXPANSION_LIMIT")
    need(decoder.eof and not decoder.unconsumed_tail and not decoder.unused_data, "GZIP_FRAMING")
    return raw


def tar_string(raw):
    value, mark, rest = raw.partition(b"\0")
    need(not mark or not any(rest), "TAR_STRING")
    try:
        return value.decode("utf-8", "strict")
    except UnicodeError:
        raise Stop("TAR_ENCODING") from None


def octal(raw):
    value = raw.strip(b"\0 ")
    need(re.fullmatch(rb"[0-7]{1,12}", value), "TAR_NUMBER")
    return int(value, 8)


def archive_files(raw, spec, files, trees, limits):
    """Strict POSIX ustar subset, plus one bounded global commit comment.

    Parses physical headers itself: extended/sparse headers cannot bypass
    entry, metadata, path or decompressed-byte limits via tarfile internals.
    """
    need(len(raw) % 512 == 0, "TAR_ALIGNMENT")
    offset, count, global_seen = 0, 0, False
    seen_files, seen_dirs, result = set(), set(), {}
    while offset + 512 <= len(raw):
        h = raw[offset:offset + 512]
        offset += 512
        if h == bytes(512):
            need(offset + 512 <= len(raw) and not any(raw[offset:]), "TAR_END")
            break
        count += 1
        need(count <= limits.entries, "ENTRY_LIMIT")
        need(octal(h[148:156]) == sum(h[:148]) + 8 * 32 + sum(h[156:]), "TAR_CHECKSUM")
        need(h[257:263] == b"ustar\0" and h[263:265] == b"00" and
             not any(h[500:]), "TAR_FORMAT")
        name, prefix = tar_string(h[:100]), tar_string(h[345:500])
        name = prefix + "/" + name if prefix else name
        mode, size = octal(h[100:108]), octal(h[124:136])
        need(mode <= 0o777 and not tar_string(h[157:257]), "TAR_MODE_OR_LINK")
        end = offset + size
        padded = end + (-size % 512)
        need(end <= len(raw) and padded <= len(raw) and not any(raw[end:padded]), "TAR_BODY")
        data = raw[offset:end]
        offset = padded
        kind = h[156:157]
        if kind == b"g":
            need(not global_seen and not seen_files and not seen_dirs and size <= 4096, "PAX_GLOBAL")
            # Exactly one length-prefixed comment record, no alternate paths.
            length, sep, value = data.partition(b" ")
            need(sep and re.fullmatch(rb"[1-9][0-9]{0,3}", length) and
                 int(length) == len(data) and
                 value == b"comment=" + spec.commit.pin.oid.encode() + b"\n", "PAX_COMMENT")
            global_seen = True
            continue
        need(kind in (b"0", b"\0", b"5"), "TAR_ENTRY_TYPE")
        if kind == b"5" and name.endswith("/"):
            name = name[:-1]
        if name == spec.prefix:
            path = ""
        else:
            need(name.startswith(spec.prefix + "/"), "TAR_PREFIX")
            path = name[len(spec.prefix) + 1:]
            safe_path(path, limits.path)
        if kind == b"5":
            need(size == 0 and path in trees and path not in seen_dirs, "TAR_DIRECTORY")
            seen_dirs.add(path)
        else:
            need(path in files and path not in seen_files and size <= limits.file, "TAR_FILE")
            entry = files[path]
            need(("100755" if mode & 0o111 else "100644") == entry.mode, "TAR_FILE_MODE")
            obj = checked_object("blob", data, entry.pin, limits.file)
            if obj.oid in result:
                need(result[obj.oid] == obj, "OBJECT_COLLISION")
            result[obj.oid] = obj
            seen_files.add(path)
    else:
        raise Stop("TAR_END")
    need(seen_files == set(files) and seen_dirs == set(trees), "TAR_MISSING")
    return result


def verify_snapshot(archive, spec, limits=Limits()):
    """Return immutable object payloads only. No writer or Git invocation."""
    limits_checked(limits)
    files, trees = manifest_checked(spec, limits)
    commit = commit_data(spec.commit)
    raw = expanded_gzip(archive, spec, limits)
    objects = archive_files(raw, spec, files, trees, limits)
    children = {path: [] for path in trees}
    for path, entry in files.items():
        parent, _, name = path.rpartition("/")
        children[parent].append((name.encode("utf-8"), entry.mode, entry.pin.oid, False))
    for path, entry in trees.items():
        if path:
            parent, _, name = path.rpartition("/")
            children[parent].append((name.encode("utf-8"), "40000", entry.pin.oid, True))
    for path, entry in trees.items():
        entries = sorted(children[path], key=lambda x: x[0] + (b"/" if x[3] else b""))
        body = b"".join(mode.encode() + b" " + name + b"\0" + bytes.fromhex(oid)
                        for name, mode, oid, _ in entries)
        obj = checked_object("tree", body, entry.pin, limits.expanded)
        need(obj.oid not in objects or objects[obj.oid] == obj, "OBJECT_COLLISION")
        objects[obj.oid] = obj
    need(commit.oid not in objects or objects[commit.oid] == commit, "OBJECT_COLLISION")
    objects[commit.oid] = commit
    need(sum(len(x.payload) for x in objects.values()) <= limits.expanded, "OBJECT_BUDGET")
    return SnapshotData(tuple(objects[k] for k in sorted(objects)), spec.files,
                        commit.oid, len(raw))
