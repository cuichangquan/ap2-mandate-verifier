"""U2 local Git materialization/reader checks, not a runtime bootstrap.

U1 remains unchanged. No acquisition, installer, SDK import, Git transport,
cleanup, mount, system configuration or live-workflow interface is provided.
New directories must be private and are preserved on every failure. Local
permissions/protocol guards do not attest OS network/readonly isolation.
"""
from dataclasses import dataclass
from contextlib import contextmanager
import hashlib
import os
from pathlib import Path
import re
import selectors
import signal
import stat
import subprocess
import sys
import time
import zlib

import p1r_ap2_snapshot as u1

Stop = u1.Stop
need = u1.need
MAX_OUTPUT = 2 * 1024 * 1024
MAX_WRITES = 32 * 1024 * 1024


def finish_fds(fds, sync_fd=None):
    """Attempt each finalization once; do not mask a primary operation error."""
    primary, failures = sys.exception(), []
    if sync_fd is not None:
        try:
            os.fsync(sync_fd)
        except BaseException as error:
            failures.append(error)
    for fd in fds:
        if fd is not None:
            try:
                os.close(fd)
            except BaseException as error:
                failures.append(error)
    if failures:
        if primary is not None:
            primary.add_note("FD_FINALIZATION_UNCERTAIN")
        else:
            raise Stop("FD_FINALIZATION_UNCERTAIN") from failures[0]


@contextmanager
def directory_chain(root_fd, parts):
    fds = []
    try:
        fds.append(os.dup(root_fd))
        for part in parts:
            fds.append(os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fds[-1]))
        yield fds[-1]
    finally:
        finish_fds(reversed(fds))


def read_regular(path, cap):
    flags = os.O_RDONLY | os.O_NOFOLLOW
    fd = os.open(path, flags)
    try:
        before = os.fstat(fd)
        need(stat.S_ISREG(before.st_mode) and before.st_nlink == 1 and
             before.st_size <= cap, "UNSAFE_FILE")
        raw = bytearray()
        while True:
            block = os.read(fd, min(65536, cap - len(raw) + 1))
            if not block:
                break
            need(len(raw) + len(block) <= cap, "FILE_LIMIT")
            raw.extend(block)
        after = os.fstat(fd)
        need((before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) ==
             (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns), "FILE_CHANGED")
        return bytes(raw)
    finally:
        finish_fds((fd,))


def _process(argv, env, timeout=5, cap=MAX_OUTPUT, *, git_tool=None):
    """Bounded local Git subprocess only; not the future U6 supervisor."""
    need(type(timeout) in (int, float) and 0 < timeout <= 5 and
         type(cap) is int and 0 < cap <= MAX_OUTPUT, "PROCESS_LIMIT")
    if git_tool is not None:
        need(type(git_tool) is GitTool and argv and argv[0] == git_tool.path, "GIT_LAUNCH_PATH")
        tool_checked(git_tool)  # Required by BOTH Git launch sites, before Popen.
    p = subprocess.Popen(argv, env=env, stdin=subprocess.DEVNULL,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         close_fds=True, start_new_session=True)
    output = [bytearray(), bytearray()]
    end = time.monotonic() + timeout
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(p.stdout, selectors.EVENT_READ, 0)
            selector.register(p.stderr, selectors.EVENT_READ, 1)
            while selector.get_map():
                left = end - time.monotonic()
                need(left > 0, "GIT_TIMEOUT")
                for key, _ in selector.select(min(left, 0.1)):
                    block = os.read(key.fileobj.fileno(), 65536)
                    if not block:
                        selector.unregister(key.fileobj)
                    else:
                        target = output[key.data]
                        need(len(target) + len(block) <= cap, "GIT_OUTPUT_LIMIT")
                        target.extend(block)
            need(end > time.monotonic(), "GIT_TIMEOUT")
            code = p.wait(timeout=max(0.001, end - time.monotonic()))
        return code, bytes(output[0]), bytes(output[1])
    except subprocess.TimeoutExpired:
        raise Stop("GIT_TIMEOUT") from None
    finally:
        primary, failures = sys.exception(), []
        if p.poll() is None:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            except BaseException as error:
                failures.append(error)
            try:
                p.wait(timeout=3)
            except BaseException as error:
                failures.append(error)
        for stream in (p.stdout, p.stderr):
            try:
                stream.close()
            except BaseException as error:
                failures.append(error)
        if failures:
            if primary is not None:
                primary.add_note("GIT_FINALIZATION_UNCERTAIN")
            else:
                raise Stop("GIT_FINALIZATION_UNCERTAIN") from failures[0]


def clean_env(home, bin_dir):
    return {"HOME": str(home), "XDG_CONFIG_HOME": str(home), "PATH": str(bin_dir),
            "LANG": "C", "LC_ALL": "C", "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_SYSTEM": os.devnull, "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_COUNT": "0", "GIT_ATTR_NOSYSTEM": "1",
            "GIT_NO_REPLACE_OBJECTS": "1", "GIT_NO_LAZY_FETCH": "1",
            "GIT_ALLOW_PROTOCOL": "", "GIT_TERMINAL_PROMPT": "0",
            "GIT_OPTIONAL_LOCKS": "0", "GIT_PAGER": ""}


@dataclass(frozen=True)
class GitTool:
    path: str
    sha256: str
    version: str


def tool_namespace(path):
    """Reject peer-renameable executable namespaces, not merely a bad hash.

    In this declared POSIX model every ancestor is root/euid-owned and has
    no group/other write bits; the file is likewise protected. Thus OTHER
    UIDs cannot replace any entry between verification and pathname exec.
    Same-UID/root writers, ACL grants and loader closure remain unproven.
    Sticky writable ancestors are deliberately rejected for executables.
    """
    path = _parent_path(path)
    current = Path("/")
    for component in path.parts[1:]:
        ancestor = current.lstat()
        need(stat.S_ISDIR(ancestor.st_mode) and ancestor.st_uid in (0, os.geteuid()) and
             not ancestor.st_mode & 0o022, "GIT_TOOL_NAMESPACE")
        current = current / component
        need(not stat.S_ISLNK(current.lstat().st_mode), "GIT_TOOL_PATH")
    st = current.lstat()
    need(stat.S_ISREG(st.st_mode) and st.st_nlink == 1 and st.st_mode & 0o111 and
         not st.st_mode & 0o022 and st.st_uid in (0, os.geteuid()), "GIT_TOOL_MODE")
    return (st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns, st.st_ctime_ns, st.st_mode, st.st_uid)


def inspect_git(path):
    path = Path(path)
    need(path.is_absolute() and path.resolve(strict=True) == path and
         not path.is_symlink(), "GIT_TOOL_PATH")
    before = tool_namespace(path)
    body = read_regular(path, 16 * 1024 * 1024)
    need(tool_namespace(path) == before, "GIT_TOOL_CHANGED")
    candidate = GitTool(str(path), hashlib.sha256(body).hexdigest(), "UNVERIFIED_VERSION")
    # Version has no repository/config lookup, network or source execution.
    code, stdout, _ = _process([str(path), "--version"], clean_env(os.devnull, path.parent),
                              cap=4096, git_tool=candidate)
    need(code == 0 and re.fullmatch(rb"git version [ -~]+\n", stdout), "GIT_VERSION")
    return GitTool(str(path), hashlib.sha256(body).hexdigest(), stdout.decode().strip())


def tool_checked(tool):
    need(type(tool) is GitTool and type(tool.path) is str, "GIT_TOOL_CHANGED")
    before = tool_namespace(tool.path)
    need(hashlib.sha256(read_regular(tool.path, 16 * 1024 * 1024)).hexdigest() == tool.sha256 and
         tool_namespace(tool.path) == before, "GIT_TOOL_CHANGED")


def _parent_path(parent):
    parent = Path(parent)
    need(parent.anchor == "/" and len(os.fsencode(parent)) <= 1024 and
         1 <= len(parent.parts[1:]) <= 32 and
         all(p not in ("", ".", "..") and "\0" not in p for p in parent.parts[1:]), "PARENT_PATH")
    return parent


def open_private_parent(parent):
    """Validate the whole rename namespace; bind/retain its leaf descriptor.

    Ancestors need metadata/search, not directory-content read access. From
    root down, trusted ownership and rename permissions make each next entry
    stable against OTHER UIDs; sticky ancestors protect trusted-owned entries.
    Do not reopen the validated leaf later by pathname. Hostile same-UID/root
    writers and ACL isolation remain outside this local POSIX permission model.
    """
    parent = _parent_path(parent)
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    ancestor_path = Path("/")
    ancestor = ancestor_path.lstat()
    for component in parent.parts[1:]:
        need(stat.S_ISDIR(ancestor.st_mode) and
             ancestor.st_uid in (0, os.geteuid()), "PARENT_OWNER")
        if ancestor.st_mode & 0o022:
            need(ancestor.st_mode & stat.S_ISVTX, "PARENT_RENAME_AUTHORITY")
        ancestor_path = ancestor_path / component
        child = ancestor_path.lstat()
        need(stat.S_ISDIR(child.st_mode) and child.st_uid in (0, os.geteuid()), "PARENT_PATH")
        ancestor = child
    need(ancestor.st_uid == os.geteuid() and stat.S_IMODE(ancestor.st_mode) == 0o700, "PARENT_PRIVATE")
    fd = os.open(parent, flags)
    owned = [fd]
    try:
        leaf, current = os.fstat(fd), parent.lstat()
        need(stat.S_ISDIR(leaf.st_mode) and leaf.st_uid == os.geteuid() and
             stat.S_IMODE(leaf.st_mode) == 0o700 and
             (ancestor.st_dev, ancestor.st_ino) == (leaf.st_dev, leaf.st_ino) ==
             (current.st_dev, current.st_ino), "PARENT_ENTRY_CHANGED")
        owned = []  # Caller owns the one validated descriptor, even on close error.
        return parent, fd
    finally:
        finish_fds(reversed(owned))


def private_parent(parent):
    parent, fd = open_private_parent(parent)
    finish_fds((fd,))
    return parent


def mkdir_at(parent_fd, name):
    os.mkdir(name, 0o700, dir_fd=parent_fd)  # Existing names never reused.
    return os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)


def write_at(root_fd, relative, raw, mode):
    """Exclusive descriptor-relative writes into newly created directories."""
    need(type(raw) is bytes and len(raw) <= MAX_OUTPUT and mode in (0o444, 0o555, 0o600), "WRITE_LIMIT")
    parts = relative.split("/")
    need(all(p not in ("", ".", "..") and "\0" not in p for p in parts), "WRITE_PATH")
    with directory_chain(root_fd, parts[:-1]) as directory:
        fd = os.open(parts[-1], os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                     0o600, dir_fd=directory)
        try:
            st = os.fstat(fd)
            need(stat.S_ISREG(st.st_mode) and st.st_nlink == 1 and st.st_uid == os.geteuid(), "WRITE_FILE")
            offset = 0
            while offset < len(raw):
                n = os.write(fd, raw[offset:offset + 65536])
                need(n > 0, "SHORT_WRITE")
                offset += n
            os.fchmod(fd, mode)
            os.fsync(fd)
        finally:
            finish_fds((fd,))
        os.fsync(directory)


def config_bytes(root):
    hooks = str(root / ".git/hooks").replace("\\", "\\\\").replace('"', '\\"')
    need(not any(ord(c) < 32 for c in hooks), "CONFIG_PATH")
    return ("[core]\n\trepositoryformatversion = 0\n\tbare = false\n"
            "\tfilemode = true\n\tignorecase = false\n\tprecomposeunicode = false\n"
            "\tautocrlf = false\n\tsymlinks = false\n\tfsmonitor = false\n"
            "\tuntrackedCache = false\n\tsparseCheckout = false\n"
            "\tattributesFile = /dev/null\n\texcludesFile = /dev/null\n"
            "\tlogallrefupdates = false\n\thooksPath = \"" + hooks + "\"\n"
            "[protocol]\n\tallow = never\n[index]\n\tversion = 2\n"
            "[diff]\n\tautoRefreshIndex = false\n").encode()


@dataclass(frozen=True)
class Repository:
    root: Path
    control: Path
    tool: GitTool
    spec: u1.Spec
    data: u1.SnapshotData
    expected: tuple  # relative path, physical-file SHA256, bytes, executable bit
    directories: tuple


def guard(repo):
    need(type(repo) is Repository and repo.root.resolve(strict=True) == repo.root and
         not repo.root.is_symlink(), "REPOSITORY_PATH")
    private_parent(repo.root.parent)
    for directory in (repo.root, repo.root / ".git", repo.root / ".git/objects",
                      repo.root / ".git/hooks", repo.root / ".git/refs",
                      repo.root / ".git/refs/heads", repo.root / ".git/refs/tags",
                      repo.root / ".git/info", repo.control, repo.control / "home", repo.control / "bin"):
        st = directory.lstat()
        need(stat.S_ISDIR(st.st_mode) and not stat.S_ISLNK(st.st_mode) and
             st.st_uid == os.geteuid() and not st.st_mode & 0o022, "CONTROL_DIRECTORY")
    need(not any((repo.control / "home").iterdir()), "HOME_NOT_EMPTY")
    alias = repo.control / "bin/git"
    need(set(p.name for p in (repo.control / "bin").iterdir()) == {"git"} and
         alias.is_symlink() and os.readlink(alias) == repo.tool.path, "GIT_TOOL_ALIAS")
    for name, expected in (("config", config_bytes(repo.root)),
                           ("HEAD", (repo.spec.commit.pin.oid + "\n").encode()),
                           ("shallow", (repo.spec.commit.pin.oid + "\n").encode())):
        need(read_regular(repo.root / ".git" / name, 8192) == expected, "CONTROL_CHANGED")
    forbidden = ("commondir", "gitdir", "config.worktree", "shallow.lock", "index.lock",
                 "objects/info", "objects/pack", "info/grafts", "info/attributes", "refs/replace")
    need(not any(os.path.lexists(repo.root / ".git" / x) for x in forbidden), "GIT_INDIRECTION")
    need(not any((repo.root / ".git/hooks").iterdir()) and
         not any((repo.root / ".git/refs/heads").iterdir()) and
         not any((repo.root / ".git/refs/tags").iterdir()), "HOOK_OR_REF")


def git(repo, args, writing_index=False):
    """Closed command set; no arbitrary Git command or caller options."""
    need(type(args) is tuple and all(type(a) is str for a in args), "GIT_ARGUMENTS")
    fixed = {("rev-parse", "--show-toplevel"), ("rev-parse", "HEAD"),
             ("rev-parse", "--is-shallow-repository"), ("ls-files", "--stage", "-z"),
             ("ls-files", "-v", "-z"), ("ls-tree", "-r", "-z", repo.spec.commit.pin.oid),
             ("fsck", "--full", "--strict", "--no-reflogs"),
             ("diff", "--no-ext-diff", "--no-textconv", "--quiet", "HEAD", "--"),
             ("diff", "--cached", "--no-ext-diff", "--no-textconv", "--quiet", "HEAD", "--")}
    object_args = {repo.spec.commit.pin.oid + ":" + f.path for f in repo.spec.files}
    read_object = ((len(args) == 3 and args[:2] == ("cat-file", "-s") and args[2] in object_args) or
                   (len(args) == 2 and args[0] == "show" and args[1] in object_args))
    need(args in fixed or read_object or
         (writing_index is True and args in (("read-tree", repo.spec.commit.tree),
                                            ("update-index", "--refresh"))), "GIT_COMMAND")
    guard(repo)
    env = clean_env(repo.control / "home", repo.control / "bin")
    command = [repo.tool.path, "--no-pager", "--no-replace-objects", "-C", str(repo.root),
               "-c", "core.fsmonitor=false", "-c", "diff.external=", "-c", "protocol.allow=never"]
    code, out, err = _process(command + list(args), env, git_tool=repo.tool)
    need(code == 0, "GIT_EXIT")
    # Unexpected warnings/errors must not be hidden by a successful exit.
    need(not err, "GIT_DIAGNOSTIC")
    return out


def materialize(archive, spec, parent, name, tool, write_cap=MAX_WRITES):
    """Verify U1 again, then create an exclusive local snapshot. Never cleanup."""
    data = u1.verify_snapshot(archive, spec)
    need(type(name) is str and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", name), "DESTINATION_NAME")
    need(type(write_cap) is int and 0 < write_cap <= MAX_WRITES, "WRITE_CAP")
    tool_checked(tool)
    parent = _parent_path(parent)
    root, control = parent / name, parent / (name + ".control")
    need(not os.path.lexists(root) and not os.path.lexists(control), "DESTINATION_EXISTS")
    blobs = {x.oid: x.payload for x in data.objects if x.kind == "blob"}
    # Final tracked-file modes precede index stat-cache initialization. Later
    # chmod of tracked files, even to the same mode, would change their ctime.
    contents = {f.path: (blobs[f.pin.oid], 0o555 if f.mode == "100755" else 0o444) for f in spec.files}
    contents.update({".git/config": (config_bytes(root), 0o600),
                     ".git/HEAD": ((spec.commit.pin.oid + "\n").encode(), 0o600),
                     ".git/shallow": ((spec.commit.pin.oid + "\n").encode(), 0o600)})
    directories = {t.path for t in spec.trees if t.path} | {
        ".git", ".git/objects", ".git/refs", ".git/refs/heads", ".git/refs/tags", ".git/info", ".git/hooks"}
    for obj in data.objects:
        envelope = obj.kind.encode() + b" " + str(len(obj.payload)).encode() + b"\0" + obj.payload
        name_in_repo = ".git/objects/" + obj.oid[:2] + "/" + obj.oid[2:]
        directories.add(".git/objects/" + obj.oid[:2])
        contents[name_in_repo] = (zlib.compress(envelope), 0o444)
    # Managed-write reservation, not an OS hard disk quota; index reserve2MiB.
    need(sum(len(raw) for raw, _ in contents.values()) + MAX_OUTPUT <= write_cap, "WRITE_RESERVATION")
    parent, parent_fd = open_private_parent(parent)
    root_fd = control_fd = None
    try:
        root_fd = mkdir_at(parent_fd, name)
        control_fd = mkdir_at(parent_fd, name + ".control")
        for sub in ("home", "bin"):
            fd = mkdir_at(control_fd, sub)
            finish_fds((fd,))
        os.symlink(tool.path, control / "bin/git")  # Only this explicit tool alias, outside repo.
        for directory in sorted(directories, key=lambda s: (s.count("/"), s)):
            parts = directory.split("/")
            with directory_chain(root_fd, parts[:-1]) as fd:
                new = mkdir_at(fd, parts[-1])
                finish_fds((new,))
        for relative, (raw, mode) in sorted(contents.items()):
            write_at(root_fd, relative, raw, mode)
        repo = Repository(root, control, tool, spec, data, (), tuple(sorted(directories)))
        git(repo, ("read-tree", spec.commit.tree), writing_index=True)
        git(repo, ("update-index", "--refresh"), writing_index=True)
        index = read_regular(root / ".git/index", MAX_OUTPUT)
        contents[".git/index"] = (index, 0o600)
        expected = tuple((path, hashlib.sha256(raw).hexdigest(), len(raw), bool(mode & 0o111))
                         for path, (raw, mode) in sorted(contents.items()))
        repo = Repository(root, control, tool, spec, data, expected, tuple(sorted(directories)))
        audit(repo)
        return repo
    finally:
        finish_fds((root_fd, control_fd, parent_fd), sync_fd=parent_fd)


def audit(repo):
    """Check all regular-file bytes and no links/extra files/objects/refs."""
    guard(repo)
    expected = {p: (h, n, x) for p, h, n, x in repo.expected}
    seen_files, seen_dirs = set(), set()
    for base, dirs, files in os.walk(repo.root, followlinks=False):
        for name in dirs + files:
            path = Path(base) / name
            relative = path.relative_to(repo.root).as_posix()
            st = path.lstat()
            need(st.st_uid == os.geteuid() and not st.st_mode & 0o022, "SNAPSHOT_OWNER_MODE")
            need(not stat.S_ISLNK(st.st_mode), "SNAPSHOT_SYMLINK")
            if stat.S_ISDIR(st.st_mode):
                need(relative in repo.directories, "EXTRA_DIRECTORY")
                seen_dirs.add(relative)
            else:
                need(stat.S_ISREG(st.st_mode) and st.st_nlink == 1 and relative in expected, "EXTRA_FILE")
                h, size, executable = expected[relative]
                raw = read_regular(path, size)
                need(len(raw) == size and hashlib.sha256(raw).hexdigest() == h and
                     bool(st.st_mode & 0o111) == executable, "SNAPSHOT_FILE_MISMATCH")
                seen_files.add(relative)
    need(seen_files == set(expected) and seen_dirs == set(repo.directories), "SNAPSHOT_MISSING")
    for obj in repo.data.objects:
        raw = read_regular(repo.root / ".git/objects" / obj.oid[:2] / obj.oid[2:], MAX_OUTPUT)
        decoder = zlib.decompressobj()
        want = obj.kind.encode() + b" " + str(len(obj.payload)).encode() + b"\0" + obj.payload
        try:
            unpacked = decoder.decompress(raw, len(want) + 1)
        except zlib.error:
            raise Stop("LOOSE_OBJECT_FORMAT") from None
        need(decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail and unpacked == want,
             "LOOSE_OBJECT_MISMATCH")
    return {"regular_files": len(seen_files), "directories": len(seen_dirs),
            "unique_objects": len(repo.data.objects), "regular_file_bytes": sum(n for _, n, _ in expected.values())}


def verify_reader(repo, all_blobs=True):
    need(type(all_blobs) is bool, "READER_OPTION")
    tool_checked(repo.tool)
    before = audit(repo)
    need(git(repo, ("rev-parse", "--show-toplevel")).decode().strip() == str(repo.root), "TOPLEVEL")
    need(git(repo, ("rev-parse", "HEAD")).decode().strip() == repo.spec.commit.pin.oid, "HEAD")
    need(git(repo, ("rev-parse", "--is-shallow-repository")) == b"true\n", "SHALLOW")
    index = git(repo, ("ls-files", "--stage", "-z")).split(b"\0")
    expected_index = {f.mode.encode() + b" " + f.pin.oid.encode() + b" 0\t" + f.path.encode() for f in repo.spec.files}
    need(index[-1] == b"" and len(index) - 1 == len(expected_index) and set(index[:-1]) == expected_index,
         "INDEX_MISMATCH")
    flags = git(repo, ("ls-files", "-v", "-z")).split(b"\0")
    need(flags[-1] == b"" and set(flags[:-1]) == {b"H " + f.path.encode() for f in repo.spec.files}, "INDEX_FLAGS")
    tree = git(repo, ("ls-tree", "-r", "-z", repo.spec.commit.pin.oid)).split(b"\0")
    expected_tree = {f.mode.encode() + b" blob " + f.pin.oid.encode() + b"\t" + f.path.encode() for f in repo.spec.files}
    need(tree[-1] == b"" and set(tree[:-1]) == expected_tree and len(tree) - 1 == len(expected_tree), "TREE_MISMATCH")
    for args in (("diff", "--no-ext-diff", "--no-textconv", "--quiet", "HEAD", "--"),
                 ("diff", "--cached", "--no-ext-diff", "--no-textconv", "--quiet", "HEAD", "--"),
                 ("fsck", "--full", "--strict", "--no-reflogs")):
        git(repo, args)
    checked = 0
    if all_blobs:
        for f in repo.spec.files:
            obj = repo.spec.commit.pin.oid + ":" + f.path
            need(git(repo, ("cat-file", "-s", obj)) == str(f.pin.size).encode() + b"\n", "BLOB_SIZE")
            body = git(repo, ("show", obj))
            u1.checked_object("blob", body, f.pin, u1.Limits().file)
            checked += 1
    after = audit(repo)
    need(before == after, "READER_MUTATION")
    tool_checked(repo.tool)
    return {"status": "LOCAL_GIT_READER_MATCH_RUNTIME_UNPROVEN", "git": repo.tool.__dict__,
            "root": str(repo.root), "files_in_index_and_tree": len(repo.spec.files),
            "blob_paths_checked": checked, "shallow_boundary": repo.spec.commit.pin.oid,
            "parent_history_verified": False, "sdk_executed": False,
            "os_network_isolation_attested": False, "os_readonly_mount_attested": False,
            "inventory": after}


def freeze_permissions(repo):
    """Private path chmod only; owner can undo it. Not an OS readonly mount."""
    audit(repo)
    for relative, _, _, executable in repo.expected:
        path = repo.root / relative
        mode = 0o555 if executable else 0o444
        if path.lstat().st_mode & 0o777 != mode:
            os.chmod(path, mode, follow_symlinks=False)
    for relative in sorted(repo.directories, key=lambda x: -x.count("/")):
        os.chmod(repo.root / relative, 0o555, follow_symlinks=False)
    os.chmod(repo.root, 0o555, follow_symlinks=False)
    return audit(repo)
