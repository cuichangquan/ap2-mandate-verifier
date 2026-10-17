"""Synthetic bytes only: no official AP2 payload, Git database or SDK run."""
import ast
from dataclasses import replace
import gzip
import hashlib
import io
from pathlib import Path
import tarfile
import unittest

import p1r_ap2_snapshot as m


def oid(kind, raw):
    # Independent test oracle; never call the implementation's digest/encoder.
    return hashlib.sha1((kind + " " + str(len(raw))).encode() + b"\0" + raw).hexdigest()


def pin(kind, raw):
    return m.Pin(oid(kind, raw), len(raw), hashlib.sha256(raw).hexdigest())


def sample():
    source = b"raise RuntimeError('SYNTHETIC_DATA_MUST_NOT_EXECUTE')\n"
    binary = b"\0\xff\0x"
    files = (m.File("a/run.py", "100755", pin("blob", source)),
             m.File("a.c", "100644", pin("blob", binary)),
             m.File("empty", "100644", pin("blob", b"")),
             m.File("dup", "100644", pin("blob", binary)))
    child = b"100755 run.py\0" + bytes.fromhex(files[0].pin.oid)
    child_pin = pin("tree", child)
    # Git order: a.c before directory a/, unlike an ordinary basename sort.
    root = (b"100644 a.c\0" + bytes.fromhex(files[1].pin.oid) +
            b"40000 a\0" + bytes.fromhex(child_pin.oid) +
            b"100644 dup\0" + bytes.fromhex(files[3].pin.oid) +
            b"100644 empty\0" + bytes.fromhex(files[2].pin.oid))
    root_pin = pin("tree", root)
    parent = "1" * 40
    headers = (b"tree " + root_pin.oid.encode() + b"\nparent " + parent.encode() +
               b"\nauthor Example <example@example.invalid> 123 -0700\n"
               b"committer Example <example@example.invalid> 124 +0530")
    message = b"message without final LF\n\nsecond paragraph"
    signature = b"-----BEGIN PGP SIGNATURE-----\n\nSYNTHETIC\n-----END PGP SIGNATURE-----\n"
    # Explicit expected raw bytes, including the final empty continuation line.
    raw_commit = (headers + b"\ngpgsig -----BEGIN PGP SIGNATURE-----\n \n SYNTHETIC\n"
                  b" -----END PGP SIGNATURE-----\n \n\n" + message)
    commit = m.Commit(pin("commit", raw_commit), root_pin.oid, (parent,),
                      headers + b"\n\n" + message, signature)
    spec = m.Spec("AP2-" + commit.pin.oid, 1, "0" * 64, files,
                  (m.Tree("", root_pin), m.Tree("a", child_pin)), commit)
    entries = [(spec.prefix + "/", b"", 0o755, tarfile.DIRTYPE, ""),
               (spec.prefix + "/a/", b"", 0o755, tarfile.DIRTYPE, ""),
               (spec.prefix + "/a/run.py", source, 0o755, tarfile.REGTYPE, ""),
               (spec.prefix + "/a.c", binary, 0o644, tarfile.REGTYPE, ""),
               (spec.prefix + "/empty", b"", 0o644, tarfile.REGTYPE, ""),
               (spec.prefix + "/dup", binary, 0o644, tarfile.REGTYPE, "")]
    return spec, entries, raw_commit


def tar_bytes(entries):
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode="w", format=tarfile.USTAR_FORMAT) as tf:
        for name, data, mode, kind, link in entries:
            info = tarfile.TarInfo(name)
            info.mode, info.type, info.linkname = mode, kind, link
            info.size = len(data)
            tf.addfile(info, io.BytesIO(data))
    return stream.getvalue()


def packed(spec, raw):
    archive = gzip.compress(raw, mtime=0)
    return archive, replace(spec, archive_size=len(archive),
                            archive_sha256=hashlib.sha256(archive).hexdigest())


def header_change(raw, start, value, checksum=True):
    result = bytearray(raw)
    result[start:start + len(value)] = value
    if checksum:
        result[148:156] = b"        "
        result[148:156] = ("%06o\0 " % sum(result[:512])).encode()
    return bytes(result)


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.spec, self.entries, self.raw_commit = sample()
        self.raw = tar_bytes(self.entries)
        self.archive, self.spec = packed(self.spec, self.raw)

    def verify(self, raw=None, spec=None, limits=None):
        archive, spec = packed(spec or self.spec, self.raw if raw is None else raw)
        return m.verify_snapshot(archive, spec, limits or m.Limits())

    def rejects(self, raw, code, spec=None, limits=None):
        with self.assertRaisesRegex(m.Stop, "^" + code + "$"):
            self.verify(raw, spec, limits)

    def test_exact_object_data_and_no_execution(self):
        result = m.verify_snapshot(self.archive, self.spec)
        self.assertEqual(result.status, "PURE_DATA_MATCH_NOT_GIT_DATABASE_OR_RUNTIME_PROOF")
        self.assertEqual(result.authority, "CALLER_PINS_NOT_AUTHENTICATED")
        self.assertEqual(result.shallow_boundary, self.spec.commit.pin.oid)
        # Four paths share three unique blobs; two trees and one commit.
        self.assertEqual(len(result.objects), 6)
        self.assertEqual(len(result.files), 4)
        self.assertEqual([x.payload for x in result.objects if x.kind == "commit"], [self.raw_commit])
        self.assertIn(b"raise RuntimeError", b"".join(x.payload for x in result.objects))
        with self.assertRaises(AttributeError):
            result.status = "PASS"

    def test_single_serializer_exact_bytes(self):
        obj = m.commit_data(self.spec.commit)
        self.assertEqual(obj.payload, self.raw_commit)
        self.assertFalse(obj.payload.endswith(b"\n"))
        self.assertEqual(m.SERIALIZER, "LF_PRESERVING_GPGSIG_V1")

    def test_commit_mutations_have_no_fallback(self):
        c = self.spec.commit
        cases = [(replace(c, signature=c.signature[:-1]), "SIGNATURE_FORMAT"),
                 (replace(c, signature=c.signature.replace(b"\n", b"\r\n")), "SIGNATURE_FORMAT"),
                 (replace(c, signature=b"\0" + c.signature), "SIGNATURE_FORMAT"),
                 (replace(c, payload=c.payload + b"\n"), "OBJECT_PIN_MISMATCH"),
                 (replace(c, payload=c.payload.replace(b"message", b"changed")), "OBJECT_PIN_MISMATCH"),
                 (replace(c, parents=()), "COMMIT_HEADERS"),
                 (replace(c, parents=("2" * 40,)), "COMMIT_HEADERS"),
                 (replace(c, tree="2" * 40), "COMMIT_HEADERS"),
                 (replace(c, payload=c.payload.replace(b"-0700", b"-2500")), "COMMIT_TIMEZONE"),
                 (replace(c, payload=c.payload.replace(b"+0530", b"+0560")), "COMMIT_TIMEZONE"),
                 (replace(c, payload=c.payload.replace(b"\n\nmessage", b"\nencoding UTF-8\n\nmessage")), "COMMIT_HEADERS"),
                 (replace(c, payload=c.payload.replace(b"\n\nmessage", b"\ngpgsig fake\n\nmessage")), "COMMIT_HEADERS"),
                 (replace(c, parents=("1" * 40, "1" * 40)), "COMMIT_REFERENCES"),
                 (replace(c, payload=b"x" * 4097), "COMMIT_BYTES"),
                 (replace(c, signature=b"x" * 2049), "COMMIT_BYTES"),
                 (replace(c, payload=b"tree\x00bad"), "COMMIT_BYTES"),
                 (replace(c, payload=b"missing separator"), "COMMIT_BOUNDARY")]
        for changed, code in cases:
            with self.subTest(code=code, changed=cases.index((changed, code))):
                with self.assertRaisesRegex(m.Stop, "^" + code + "$"):
                    m.commit_data(changed)

    def test_commit_preserves_message_lf_and_nonascii(self):
        c = self.spec.commit
        raw = self.raw_commit + b"\n\xe6\x96\x87\n"
        changed = replace(c, payload=c.payload + b"\n\xe6\x96\x87\n", pin=pin("commit", raw))
        self.assertEqual(m.commit_data(changed).payload, raw)

    def test_commit_size_oid_and_sha_are_all_required(self):
        for field, value in [("size", 1), ("sha256", "0" * 64), ("oid", "0" * 40)]:
            with self.subTest(field=field):
                c = replace(self.spec.commit, pin=replace(self.spec.commit.pin, **{field: value}))
                with self.assertRaisesRegex(m.Stop, "OBJECT_PIN_MISMATCH"):
                    m.commit_data(c)

    def test_archive_pins_checked_before_decompression(self):
        for change in ({"archive_size": len(self.archive) - 1}, {"archive_sha256": "0" * 64}):
            with self.subTest(change=change):
                with self.assertRaisesRegex(m.Stop, "ARCHIVE_BYTES"):
                    m.verify_snapshot(self.archive, replace(self.spec, **change))

    def test_gzip_crc_truncation_trailing_and_multiple_member(self):
        broken = bytearray(self.archive)
        broken[-8] ^= 1
        for data, code in [(bytes(broken), "GZIP_FORMAT"), (self.archive[:-1], "GZIP_FRAMING"),
                           (self.archive + b"junk", "GZIP_FRAMING"),
                           (self.archive + self.archive, "GZIP_FRAMING")]:
            with self.subTest(code=code, size=len(data)):
                spec = replace(self.spec, archive_size=len(data), archive_sha256=hashlib.sha256(data).hexdigest())
                with self.assertRaisesRegex(m.Stop, "^" + code + "$"):
                    m.verify_snapshot(data, spec)

    def test_exact_expansion_and_entry_boundary(self):
        limits = m.Limits(compressed=len(self.archive), expanded=len(self.raw), entries=6)
        m.verify_snapshot(self.archive, self.spec, limits)
        self.rejects(self.raw, "EXPANSION_LIMIT", limits=replace(limits, expanded=len(self.raw) - 1))
        self.rejects(self.raw, "SPEC", limits=replace(limits, entries=5))

    def test_limits_cannot_be_raised_or_boolean(self):
        for key in ("compressed", "expanded", "file", "entries", "path"):
            for value in (True, 0, -1, getattr(m.Limits(), key) + 1):
                with self.subTest(key=key, value=value):
                    with self.assertRaisesRegex(m.Stop, "LIMIT_RANGE"):
                        m.verify_snapshot(self.archive, self.spec, replace(m.Limits(), **{key: value}))

    def test_compressed_file_and_path_caps(self):
        with self.assertRaisesRegex(m.Stop, "ARCHIVE_PIN"):
            m.verify_snapshot(self.archive, self.spec, m.Limits(compressed=len(self.archive) - 1))
        self.rejects(self.raw, "PIN", limits=m.Limits(file=1))
        self.rejects(self.raw, "PATH", limits=m.Limits(path=4))

    def test_unsafe_archive_names(self):
        suffixes = ["../escape", "a/../escape", "a//run.py", "./a/run.py", ".git/config",
                    ".GIT/config", "a\\run.py", "a/", "a./x", "a /x", "a/\x01x", "a//"]
        for suffix in suffixes:
            with self.subTest(suffix=suffix):
                entries = list(self.entries)
                entries[2] = (self.spec.prefix + "/" + suffix,) + entries[2][1:]
                self.rejects(tar_bytes(entries), "PATH")
        for name in ("/absolute", "foreign/a", "AP2-wrong/a"):
            with self.subTest(name=name):
                entries = list(self.entries)
                entries[2] = (name,) + entries[2][1:]
                self.rejects(tar_bytes(entries), "TAR_PREFIX")

    def test_manifest_alias_collisions_and_unsupported_modes(self):
        c = self.spec.files[1]
        for name in ("A.C", "a.c"):
            with self.subTest(name=name):
                self.rejects(self.raw, "PATH_COLLISION", spec=replace(self.spec, files=self.spec.files + (replace(c, path=name),)))
        for mode in ("120000", "160000", "040000", "100600", 100644):
            with self.subTest(mode=mode):
                self.rejects(self.raw, "FILE_MODE", spec=replace(self.spec, files=(replace(c, mode=mode),)))

    def test_normalization_alias_collision_and_surrogate_path(self):
        c = self.spec.files[1]
        spec = replace(self.spec, files=(replace(c, path="caf\xe9"), replace(c, path="cafe\u0301")))
        self.rejects(self.raw, "PATH_COLLISION", spec=spec)
        self.rejects(self.raw, "PATH_ENCODING", spec=replace(self.spec, files=(replace(c, path="bad\ud800"),)))

    def test_missing_root_and_parent_tree(self):
        self.rejects(self.raw, "ROOT_TREE", spec=replace(self.spec, trees=self.spec.trees[1:]))
        self.rejects(self.raw, "MISSING_PARENT_TREE", spec=replace(self.spec, trees=self.spec.trees[:1]))

    def test_pin_schema(self):
        c = self.spec.files[1]
        for change in ({"oid": "A" * 40}, {"sha256": "z" * 64}, {"size": True}, {"size": -1}):
            with self.subTest(change=change):
                bad = replace(c, pin=replace(c.pin, **change))
                self.rejects(self.raw, "PIN", spec=replace(self.spec, files=(bad,)))

    def test_duplicate_missing_extra_files_and_directories(self):
        for entries, code in [(self.entries + [self.entries[2]], "TAR_FILE"),
                              (self.entries + [self.entries[1]], "TAR_DIRECTORY"),
                              (self.entries[1:], "TAR_MISSING"),
                              (self.entries[:2] + self.entries[3:], "TAR_MISSING"),
                              (self.entries + [(self.spec.prefix + "/extra", b"", 0o644, tarfile.REGTYPE, "")], "TAR_FILE"),
                              (self.entries + [(self.spec.prefix + "/extra/", b"", 0o755, tarfile.DIRTYPE, "")], "TAR_DIRECTORY")]:
            with self.subTest(code=code, entries=len(entries)):
                self.rejects(tar_bytes(entries), code)

    def test_links_and_special_entries_rejected(self):
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.CHRTYPE, tarfile.BLKTYPE,
                     tarfile.FIFOTYPE, tarfile.GNUTYPE_SPARSE, tarfile.XHDTYPE, tarfile.GNUTYPE_LONGNAME):
            with self.subTest(kind=kind):
                entries = list(self.entries)
                entries[2] = (entries[2][0], b"", 0o644, kind, "")
                self.rejects(tar_bytes(entries), "TAR_ENTRY_TYPE")
        entries = list(self.entries)
        entries[2] = (entries[2][0], b"", 0o644, tarfile.SYMTYPE, "/etc/passwd")
        self.rejects(tar_bytes(entries), "TAR_MODE_OR_LINK")

    def test_file_mode_size_hash_and_data_mutations(self):
        entries = list(self.entries)
        entries[2] = (entries[2][0], entries[2][1], 0o644, tarfile.REGTYPE, "")
        self.rejects(tar_bytes(entries), "TAR_FILE_MODE")
        for data in (b"", self.entries[2][1] + b"x", b"X" + self.entries[2][1][1:]):
            with self.subTest(size=len(data)):
                entries = list(self.entries)
                entries[2] = (entries[2][0], data) + entries[2][2:]
                self.rejects(tar_bytes(entries), "OBJECT_PIN_MISMATCH")
        entries[2] = (entries[2][0], self.entries[2][1], 0o4755, tarfile.REGTYPE, "")
        self.rejects(tar_bytes(entries), "TAR_MODE_OR_LINK")

    def test_tree_hash_and_git_order_not_replaced(self):
        t = self.spec.trees[1]
        for changed in (replace(t.pin, sha256="0" * 64), replace(t.pin, size=0)):
            with self.subTest(pin=changed):
                self.rejects(self.raw, "OBJECT_PIN_MISMATCH", spec=replace(self.spec, trees=(self.spec.trees[0], replace(t, pin=changed))))
        # A wrong root expectation cannot be fixed by regenerating a new commit.
        badroot = replace(self.spec.trees[0], pin=replace(self.spec.trees[0].pin, oid="0" * 40))
        self.rejects(self.raw, "ROOT_TREE", spec=replace(self.spec, trees=(badroot, t)))

    def test_tar_checksum_numeric_string_and_magic(self):
        for start, value, recompute, code in [(0, b"X", False, "TAR_CHECKSUM"),
                                              (124, b"9" * 12, True, "TAR_NUMBER"),
                                              (100, b"\x80" + b"\0" * 7, True, "TAR_NUMBER"),
                                              (257, b"ustar ", True, "TAR_FORMAT"),
                                              (263, b"99", True, "TAR_FORMAT"),
                                              (500, b"x", True, "TAR_FORMAT"),
                                              (0, b"x\0hidden", True, "TAR_STRING"),
                                              (0, b"\xff", True, "TAR_ENCODING")]:
            with self.subTest(start=start, code=code):
                self.rejects(header_change(self.raw, start, value, recompute), code)

    def test_tar_truncation_padding_and_hidden_tail(self):
        self.rejects(self.raw[:-1], "TAR_ALIGNMENT")
        self.rejects(self.raw[:512], "TAR_END")
        # Binary file member occupies header at 2048 then four bytes of data.
        raw = bytearray(self.raw)
        raw[2564] = 1
        self.rejects(bytes(raw), "TAR_BODY")
        self.rejects(self.raw + b"x" * 512, "TAR_END")
        self.rejects(self.raw[:4096], "TAR_BODY")
        self.rejects(self.raw[:4608], "TAR_END")

    def test_one_global_commit_comment_only(self):
        value = b"comment=" + self.spec.commit.pin.oid.encode() + b"\n"
        size = len(value) + 3
        while len(str(size)) + 1 + len(value) != size:
            size = len(str(size)) + 1 + len(value)
        data = str(size).encode() + b" " + value
        g = ("pax_global_header", data, 0o644, tarfile.XGLTYPE, "")
        self.verify(tar_bytes([g] + self.entries))
        self.rejects(tar_bytes([g, g] + self.entries), "PAX_GLOBAL")
        self.rejects(tar_bytes(self.entries[:1] + [g] + self.entries[1:]), "PAX_GLOBAL")
        self.rejects(tar_bytes([replace_entry(g, data[:-2] + b"x\n")] + self.entries), "PAX_COMMENT")
        self.rejects(tar_bytes([replace_entry(g, b"9999 comment=bad\n")] + self.entries), "PAX_COMMENT")

    def test_physical_metadata_headers_count_toward_entry_cap(self):
        value = b"comment=" + self.spec.commit.pin.oid.encode() + b"\n"
        data = b"52 " + value
        self.assertEqual(len(data), 52)
        raw = tar_bytes([("pax_global_header", data, 0o644, tarfile.XGLTYPE, "")] + self.entries)
        self.rejects(raw, "ENTRY_LIMIT", limits=m.Limits(entries=6))

    def test_no_writer_or_execution_imports(self):
        # Source-level capability check complements behavior, not a sandbox.
        tree = ast.parse(Path(m.__file__).read_text())
        names = {n.module if isinstance(n, ast.ImportFrom) else n.names[0].name
                 for n in ast.walk(tree) if isinstance(n, (ast.Import, ast.ImportFrom))}
        self.assertEqual(names, {"dataclasses", "hashlib", "re", "unicodedata", "zlib"})
        calls = {n.func.id for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)}
        self.assertFalse(calls & {"open", "exec", "eval", "compile", "__import__"})

    def test_api_shapes_and_nonstring_paths(self):
        for spec, code in [(replace(self.spec, files=list(self.spec.files)), "SPEC"),
                           (replace(self.spec, files=(self.spec.trees[0],)), "SPEC"),
                           (replace(self.spec, trees=(self.spec.files[0],)), "SPEC"),
                           (replace(self.spec, files=(replace(self.spec.files[0], path=1),)), "PATH"),
                           (replace(self.spec, trees=(replace(self.spec.trees[0], path=None),)), "PATH"),
                           (replace(self.spec, prefix="wrong"), "ARCHIVE_PIN")]:
            with self.subTest(code=code, spec_index=code + str(type(spec.files))):
                self.rejects(self.raw, code, spec=spec)
        with self.assertRaisesRegex(m.Stop, "LIMIT_TYPE"):
            m.verify_snapshot(self.archive, self.spec, {})
        with self.assertRaisesRegex(m.Stop, "ARCHIVE_BYTES"):
            m.verify_snapshot(bytearray(self.archive), self.spec)
        with self.assertRaisesRegex(m.Stop, "ARCHIVE_PIN"):
            m.verify_snapshot(self.archive, replace(self.spec, archive_size=True))

    def test_object_budget_is_distinct_from_tar_budget(self):
        # A permitted archive can still exceed the aggregate object budget
        # because commit metadata is not stored in tar. Check the final gate
        # independently using a tiny synthetic snapshot with a long message.
        empty = pin("tree", b"")
        c = self.spec.commit
        payload = c.payload.replace(c.tree.encode(), empty.oid.encode())
        headers = payload.partition(b"\n\n")[0]
        message = b"x" * 3000
        raw_commit = headers + b"\ngpgsig " + c.signature.replace(b"\n", b"\n ") + b"\n\n" + message
        c = replace(c, tree=empty.oid, payload=headers + b"\n\n" + message,
                    pin=pin("commit", raw_commit))
        spec = replace(self.spec, commit=c, files=(), trees=(m.Tree("", empty),), prefix="AP2-" + c.pin.oid)
        # A manually bounded tar: one root header plus two EOF blocks.
        raw = tar_bytes([(spec.prefix + "/", b"", 0o755, tarfile.DIRTYPE, "")])[:1536]
        self.rejects(raw, "OBJECT_BUDGET", spec=spec, limits=m.Limits(expanded=1536))

    def test_many_independent_byte_tamper_cases(self):
        # Re-pin only archive transport to exercise inner content validation.
        for i in range(32):
            with self.subTest(byte=i):
                entries = list(self.entries)
                b = bytearray(entries[2][1])
                b[i] ^= 1
                entries[2] = (entries[2][0], bytes(b)) + entries[2][2:]
                self.rejects(tar_bytes(entries), "OBJECT_PIN_MISMATCH")


def replace_entry(entry, data):
    return (entry[0], data) + entry[2:]


if __name__ == "__main__":
    unittest.main(verbosity=2)
