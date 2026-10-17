"""U2 synthetic local filesystem/Git tests; retain all fixtures and diagnostics.

Set AP2_U2_TEST_ROOT to a dedicated private directory and AP2_U2_GIT to an
existing Git binary. No SDK, transport, installer, Docker or Actions run.
"""
from dataclasses import replace
import hashlib
import json
import os
from pathlib import Path
import shlex
import sys
import unittest
from unittest.mock import patch, Mock
import uuid

import p1r_ap2_git_snapshot as m
import test_p1r_ap2_snapshot as fixtures


class GitSnapshotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not os.environ.get("AP2_U2_TEST_ROOT") or not os.environ.get("AP2_U2_GIT"):
            raise unittest.SkipTest("Dedicated private fixture root and existing Git are required")
        cls.parent = m.private_parent(Path(os.environ["AP2_U2_TEST_ROOT"]))
        cls.tool = m.inspect_git(os.environ["AP2_U2_GIT"])

    def setUp(self):
        self.directory = self.parent / (self._testMethodName + "-" + uuid.uuid4().hex[:8])
        self.directory.mkdir(mode=0o700)
        spec, entries, _ = fixtures.sample()
        self.archive, self.spec = fixtures.packed(spec, fixtures.tar_bytes(entries))

    def create(self, name="good", **kwargs):
        return m.materialize(self.archive, self.spec, self.directory, name, self.tool, **kwargs)

    def test_full_git_reader_and_loose_data(self):
        repo = self.create()
        result = m.verify_reader(repo)
        self.assertEqual(result['blob_paths_checked'], 4)
        self.assertEqual(result['inventory']['unique_objects'], 6)
        self.assertFalse(result['parent_history_verified'])
        self.assertFalse(result['os_network_isolation_attested'])
        self.assertEqual((repo.root / '.git/HEAD').read_text(), self.spec.commit.pin.oid + '\n')
        self.assertEqual((repo.root / '.git/shallow').read_text(), self.spec.commit.pin.oid + '\n')
        self.assertFalse((repo.root / '.git/objects/11').exists())
        (self.directory / 'reader-result.json').write_text(json.dumps(result, indent=2) + '\n')

    def test_permissions_freeze_still_reads_without_index_write(self):
        repo = self.create()
        before = (repo.root / '.git/index').read_bytes()
        m.freeze_permissions(repo)
        result = m.verify_reader(repo)
        self.assertEqual((repo.root / '.git/index').read_bytes(), before)
        self.assertEqual((repo.root / 'a/run.py').stat().st_mode & 0o777, 0o555)
        self.assertEqual((repo.root / 'empty').stat().st_mode & 0o777, 0o444)
        self.assertFalse(result['os_readonly_mount_attested'])

    def test_existing_destination_never_reused_or_removed(self):
        root = self.directory / 'existing'
        root.mkdir(mode=0o700)
        marker = root / 'keep'
        marker.write_bytes(b'preserve existing user data')
        with self.assertRaisesRegex(m.Stop, '^DESTINATION_EXISTS$'):
            self.create('existing')
        self.assertEqual(marker.read_bytes(), b'preserve existing user data')
        control = self.directory / 'another.control'
        control.mkdir(mode=0o700)
        with self.assertRaisesRegex(m.Stop, '^DESTINATION_EXISTS$'):
            self.create('another')
        self.assertFalse((self.directory / 'another').exists())

    def test_symlink_destination_and_parent_rejected(self):
        foreign = self.directory / 'foreign'
        foreign.mkdir(mode=0o700)
        alias = self.directory / 'alias'
        alias.symlink_to(foreign, target_is_directory=True)
        with self.assertRaisesRegex(m.Stop, '^DESTINATION_EXISTS$'):
            self.create('alias')
        with self.assertRaisesRegex(m.Stop, '^PARENT_PATH$'):
            m.materialize(self.archive, self.spec, alias, 'x', self.tool)
        self.assertFalse(list(foreign.iterdir()))

    def test_destination_name_and_nonprivate_parent(self):
        for name in ('../out', '/out', '.git', '', 'a/b', 'a\x00b', 'a' * 65):
            with self.subTest(name=name):
                with self.assertRaisesRegex(m.Stop, '^DESTINATION_NAME$'):
                    self.create(name)
        other = self.directory / 'nonprivate'
        other.mkdir(mode=0o755)
        with self.assertRaisesRegex(m.Stop, '^PARENT_PRIVATE$'):
            m.materialize(self.archive, self.spec, other, 'x', self.tool)

    def test_invalid_archive_no_filesystem_side_effect(self):
        with self.assertRaisesRegex(m.Stop, '^ARCHIVE_BYTES$'):
            m.materialize(self.archive + b'corrupt', self.spec, self.directory, 'x', self.tool)
        self.assertFalse(list(self.directory.iterdir()))

    def test_managed_write_reservation_and_cap(self):
        for cap in (True, 0, -1, m.MAX_WRITES + 1):
            with self.subTest(cap=cap):
                with self.assertRaisesRegex(m.Stop, '^WRITE_CAP$'):
                    self.create(write_cap=cap)
        with self.assertRaisesRegex(m.Stop, '^WRITE_RESERVATION$'):
            self.create(write_cap=m.MAX_OUTPUT)
        self.assertFalse(list(self.directory.iterdir()))

    def test_global_environment_cannot_inject_config_or_helpers(self):
        marker = self.directory / 'helper-executed'
        hook = self.directory / 'untrusted-helper'
        hook.write_text('#!/bin/sh\nprintf bad > ' + shlex.quote(str(marker)) + '\nexit 19\n')
        hook.chmod(0o700)
        config = self.directory / 'untrusted-config'
        config.write_text('[core]\n fsmonitor = ' + str(hook) + '\n hooksPath = ' + str(self.directory) + '\n')
        poison = {'HOME': str(self.directory), 'XDG_CONFIG_HOME': str(self.directory),
                  'GIT_CONFIG_GLOBAL': str(config), 'GIT_CONFIG_SYSTEM': str(config),
                  'GIT_CONFIG_COUNT': '1', 'GIT_CONFIG_KEY_0': 'core.fsmonitor',
                  'GIT_CONFIG_VALUE_0': str(hook), 'GIT_DIR': '/not-the-repository',
                  'GIT_OBJECT_DIRECTORY': '/not-the-objects',
                  'GIT_ALTERNATE_OBJECT_DIRECTORIES': '/not-the-objects',
                  'GIT_EXEC_PATH': str(self.directory), 'LD_PRELOAD': '/untrusted.so',
                  'http_proxy': 'http://127.0.0.1:9', 'GIT_PAGER': str(hook)}
        with patch.dict(os.environ, poison):
            repo = self.create()
            m.verify_reader(repo)
        self.assertFalse(marker.exists())
        self.assertIn('fsmonitor', config.read_text())

    def test_no_arbitrary_or_transport_git_commands(self):
        repo = self.create()
        commands = [('fetch', 'https://example.invalid/never'), ('clone', '/tmp/x'),
                    ('config', '--global', 'x.y', 'z'), ('checkout', 'HEAD'),
                    ('show', 'HEAD:a.c'), ('show', self.spec.commit.pin.oid + ':../x'),
                    ('cat-file', '-p', self.spec.commit.pin.oid),
                    ('read-tree', self.spec.commit.tree), ('update-index', '--refresh')]
        for args in commands:
            with self.subTest(args=args), patch.object(m, '_process', side_effect=AssertionError('must not start')):
                with self.assertRaisesRegex(m.Stop, '^GIT_COMMAND$'):
                    m.git(repo, args)

    def test_tool_path_hash_and_alias(self):
        repo = self.create()
        wrong = replace(repo.tool, sha256='0' * 64)
        with self.assertRaisesRegex(m.Stop, '^GIT_TOOL_CHANGED$'):
            m.verify_reader(replace(repo, tool=wrong))
        alias = repo.control / 'bin/git'
        alias.rename(repo.control / 'saved-git-alias')
        alias.symlink_to('/not-the-tool')
        with self.assertRaisesRegex(m.Stop, '^GIT_TOOL_ALIAS$'):
            m.audit(repo)
        external_alias = self.directory / 'git-alias'
        external_alias.symlink_to(self.tool.path)
        with self.assertRaisesRegex(m.Stop, '^GIT_TOOL_PATH$'):
            m.inspect_git(external_alias)

    def test_config_head_and_shallow_tamper(self):
        for name in ('config', 'HEAD', 'shallow'):
            with self.subTest(name=name):
                repo = self.create('change-' + name)
                path = repo.root / '.git' / name
                path.write_bytes(path.read_bytes() + b'\n')
                with self.assertRaisesRegex(m.Stop, '^CONTROL_CHANGED$'):
                    m.verify_reader(repo)

    def test_replace_alternates_promisor_and_extra_refs(self):
        for name in ('objects/info', 'objects/pack', 'refs/replace', 'config.worktree', 'commondir', 'index.lock'):
            with self.subTest(name=name):
                repo = self.create('indirection-' + name.replace('/', '-').replace('.', '-'))
                path = repo.root / '.git' / name
                if '/' in name:
                    path.mkdir(mode=0o700)
                else:
                    path.write_bytes(b'not allowed')
                with self.assertRaisesRegex(m.Stop, '^GIT_INDIRECTION$'):
                    m.audit(repo)
        repo = self.create('extra-ref')
        (repo.root / '.git/refs/heads/other').write_text(self.spec.commit.pin.oid + '\n')
        with self.assertRaisesRegex(m.Stop, '^HOOK_OR_REF$'):
            m.audit(repo)

    def test_hook_and_home_files_rejected_before_git(self):
        for area in ('hooks', 'home'):
            with self.subTest(area=area):
                repo = self.create('poison-' + area)
                where = repo.root / '.git/hooks' if area == 'hooks' else repo.control / 'home'
                (where / 'unexpected').write_bytes(b'not executable')
                with self.assertRaisesRegex(m.Stop, 'HOOK_OR_REF|HOME_NOT_EMPTY'):
                    m.verify_reader(repo)

    def test_worktree_mode_data_missing_and_extra(self):
        for kind in ('mode', 'data', 'missing', 'extra', 'symlink', 'hardlink'):
            with self.subTest(kind=kind):
                repo = self.create('worktree-' + kind)
                path = repo.root / 'a.c'
                if kind == 'mode':
                    path.chmod(0o755)
                elif kind == 'data':
                    path.chmod(0o600)  # Deliberate owner tamper, not target permission.
                    path.write_bytes(b'\0\xff\0Y')
                elif kind == 'missing':
                    path.rename(repo.control / 'saved-file')
                elif kind == 'extra':
                    (repo.root / 'extra').write_bytes(b'x')
                elif kind == 'symlink':
                    path.rename(repo.control / 'saved-file')
                    path.symlink_to(repo.control / 'saved-file')
                else:
                    os.link(path, repo.control / 'additional-hardlink')
                with self.assertRaises((m.Stop, OSError)):
                    m.audit(repo)

    def test_loose_object_index_and_extra_object_tamper(self):
        for kind in ('object', 'index', 'extra-object', 'extra-dir'):
            with self.subTest(kind=kind):
                repo = self.create('metadata-' + kind)
                if kind == 'object':
                    obj = repo.data.objects[0]
                    path = repo.root / '.git/objects' / obj.oid[:2] / obj.oid[2:]
                    path.chmod(0o600)
                    body = bytearray(path.read_bytes())
                    body[-1] ^= 1
                    path.write_bytes(bytes(body))
                elif kind == 'index':
                    path = repo.root / '.git/index'
                    body = bytearray(path.read_bytes())
                    body[12] ^= 1
                    path.write_bytes(bytes(body))
                elif kind == 'extra-object':
                    fanout = repo.root / '.git/objects/00'
                    fanout.mkdir(mode=0o700, exist_ok=True)
                    (fanout / ('0' * 38)).write_bytes(b'extra')
                else:
                    (repo.root / 'extra-dir').mkdir(mode=0o700)
                with self.assertRaises((m.Stop, OSError)):
                    m.verify_reader(repo)

    def test_missing_parent_only_valid_with_shallow_boundary(self):
        repo = self.create()
        m.verify_reader(repo)
        (repo.root / '.git/shallow').rename(repo.control / 'saved-shallow')
        with self.assertRaises((m.Stop, OSError)):
            m.verify_reader(repo)
        # Explicit read-only diagnostic, not a guard bypass for normal use.
        argv = [repo.tool.path, '--no-pager', '-C', str(repo.root),
                '-c', 'protocol.allow=never', 'fsck', '--full', '--strict', '--no-reflogs']
        code, out, err = m._process(argv, m.clean_env(repo.control / 'home', repo.control / 'bin'))
        self.assertNotEqual(code, 0)
        (self.directory / 'without-shallow-diagnostic.json').write_text(json.dumps(
            {'exit': code, 'stdout': out.decode(errors='replace'), 'stderr': err.decode(errors='replace')}, indent=2) + '\n')

    def test_partial_build_is_retained_on_write_failure(self):
        with patch.object(m, 'write_at', side_effect=OSError('synthetic write failure')):
            with self.assertRaises(OSError):
                self.create('partial')
        self.assertTrue((self.directory / 'partial/.git').is_dir())
        self.assertTrue((self.directory / 'partial.control').is_dir())

    def test_exclusive_writer_no_overwrite_or_symlink_follow(self):
        parent_fd = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            m.write_at(parent_fd, 'keep', b'original', 0o600)
            with self.assertRaises(FileExistsError):
                m.write_at(parent_fd, 'keep', b'changed', 0o600)
            (self.directory / 'alias').symlink_to(self.directory / 'keep')
            with self.assertRaises(FileExistsError):
                m.write_at(parent_fd, 'alias', b'changed', 0o600)
            self.assertEqual((self.directory / 'keep').read_bytes(), b'original')
        finally:
            os.close(parent_fd)

    def test_local_process_timeout_and_output_bounds(self):
        env = {'PATH': '/usr/bin:/bin', 'LANG': 'C'}
        for code, expected in [('import time; time.sleep(2)', 'GIT_TIMEOUT'),
                               ('import os; os.write(1,b"x"*4096)', 'GIT_OUTPUT_LIMIT'),
                               ('import os; os.write(2,b"x"*4096)', 'GIT_OUTPUT_LIMIT')]:
            with self.subTest(expected=expected):
                with self.assertRaisesRegex(m.Stop, '^' + expected + '$'):
                    m._process([sys.executable, '-I', '-S', '-B', '-c', code], env, timeout=0.2, cap=64)
        for timeout, cap in ((0, 64), (6, 64), (1, 0), (1, m.MAX_OUTPUT + 1)):
            with self.subTest(timeout=timeout, cap=cap):
                with self.assertRaisesRegex(m.Stop, '^PROCESS_LIMIT$'):
                    m._process([sys.executable, '-c', 'pass'], env, timeout, cap)

    def test_finalize_preserves_primary_and_attempts_all_descriptors(self):
        attempts = []
        def broken_close(fd):
            attempts.append(fd)
            raise OSError('synthetic close failure')
        primary = ValueError('primary retained')
        try:
            with patch.object(m.os, 'close', side_effect=broken_close), patch.object(m.os, 'fsync', side_effect=OSError('sync')):
                try:
                    raise primary
                finally:
                    m.finish_fds((101, 102, None), sync_fd=103, primary=primary)
        except ValueError as error:
            self.assertIs(error, primary)
            self.assertIn('FD_FINALIZATION_UNCERTAIN', error.__notes__)
        else:
            self.fail('primary missing')
        self.assertEqual(attempts, [101, 102])

    def test_finalize_no_primary_rejects_and_no_double_close(self):
        calls = []
        def broken(fd):
            calls.append(fd)
            if fd == 101:
                raise OSError('close uncertainty')
        with patch.object(m.os, 'close', side_effect=broken):
            with self.assertRaisesRegex(m.Stop, '^FD_FINALIZATION_UNCERTAIN$'):
                m.finish_fds((101, 102))
        self.assertEqual(calls, [101, 102])

    def test_nonsticky_writable_ancestor_and_sticky_exception(self):
        ancestor = self.directory / 'peer-writable'
        ancestor.mkdir(mode=0o700)
        ancestor.chmod(0o777)
        leaf = ancestor / 'private-leaf'
        leaf.mkdir(mode=0o700)
        with self.assertRaisesRegex(m.Stop, '^PARENT_RENAME_AUTHORITY$'):
            m.materialize(self.archive, self.spec, leaf, 'never-created', self.tool)
        self.assertFalse(list(leaf.iterdir()))
        ancestor.chmod(0o1777)  # Only this synthetic directory, no host policy change.
        parent, fd = m.open_private_parent(leaf)
        try:
            self.assertEqual(parent, leaf)
            self.assertEqual(os.fstat(fd).st_ino, leaf.stat().st_ino)
        finally:
            m.finish_fds((fd,))

    def test_opened_parent_fd_must_match_the_validated_entry(self):
        leaf = self.directory / 'private-leaf'
        other = self.directory / 'substitute'
        leaf.mkdir(mode=0o700)
        other.mkdir(mode=0o700)
        real_open = os.open
        def substitute(path, flags, *args, **kwargs):
            if os.fspath(path) == str(leaf):
                return real_open(other, flags)
            return real_open(path, flags, *args, **kwargs)
        with patch.object(m.os, 'open', side_effect=substitute):
            with self.assertRaisesRegex(m.Stop, '^PARENT_ENTRY_CHANGED$'):
                m.materialize(self.archive, self.spec, leaf, 'never-created', self.tool)
        self.assertFalse(list(leaf.iterdir()))
        self.assertFalse(list(other.iterdir()))

    def test_materialize_uses_retained_parent_without_unchecked_reopen(self):
        real_open, reopens = os.open, []
        def observe(path, flags, *args, **kwargs):
            if os.fspath(path) == str(self.directory):
                reopens.append(path)
                if len(reopens) > 1:
                    raise AssertionError('Unchecked parent reopen is forbidden')
            return real_open(path, flags, *args, **kwargs)
        with patch.object(m.os, 'open', side_effect=observe):
            # Guard calls also validate and bind; each must inspect its FD.
            with patch.object(m, 'git'):
                with self.assertRaises(FileNotFoundError):
                    self.create()
        self.assertEqual(len(reopens), 1)
        repo = self.create('normal')
        m.verify_reader(repo)

    def test_guard_rechecks_private_parent_permissions(self):
        repo = self.create()
        self.directory.chmod(0o777)  # Synthetic fixture only, never a host ancestor.
        with self.assertRaisesRegex(m.Stop, '^PARENT_PRIVATE$'):
            m.verify_reader(repo)

    def test_setup_home_bin_close_failure_uses_finalizer_at_callsite(self):
        real_mkdir, real_close = m.mkdir_at, os.close
        for selected in ('home', 'bin'):
            with self.subTest(selected=selected):
                target, target_closes = [], []
                def observe_mkdir(parent_fd, name):
                    fd = real_mkdir(parent_fd, name)
                    if name == selected:
                        target.append(fd)
                    return fd
                def uncertain_close(fd):
                    real_close(fd)
                    if target and fd == target[0]:
                        target_closes.append(fd)
                        raise OSError('synthetic interrupted setup close')
                with patch.object(m, 'mkdir_at', side_effect=observe_mkdir), patch.object(m.os, 'close', side_effect=uncertain_close):
                    with self.assertRaisesRegex(m.Stop, '^FD_FINALIZATION_UNCERTAIN$'):
                        self.create('close-' + selected)
                self.assertEqual(target_closes, [target[0]])
                self.assertTrue((self.directory / ('close-' + selected)).is_dir())
                self.assertTrue((self.directory / ('close-' + selected + '.control') / selected).is_dir())

    def test_materialize_final_sync_and_close_under_ambient_exception(self):
        for fault in ('fsync', 'close'):
            with self.subTest(fault=fault):
                parent_fd, final_closes = [], []
                real_parent, real_sync, real_close = m.open_private_parent, os.fsync, os.close
                def parent(path):
                    result = real_parent(path)
                    if not parent_fd:
                        parent_fd.append(result[1])
                    return result
                def sync(fd):
                    if fault == 'fsync' and parent_fd and fd == parent_fd[0]:
                        raise OSError('final sync')
                    real_sync(fd)
                def close(fd):
                    real_close(fd)
                    if parent_fd and fd == parent_fd[0]:
                        final_closes.append(fd)
                        if fault == 'close':
                            raise OSError('final close')
                ambient = ValueError('caller')
                try:
                    raise ambient
                except ValueError:
                    with patch.object(m, 'open_private_parent', side_effect=parent), patch.object(m.os, 'fsync', side_effect=sync), patch.object(m.os, 'close', side_effect=close):
                        with self.assertRaisesRegex(m.Stop, '^FD_FINALIZATION_UNCERTAIN$'):
                            self.create('final-' + fault)
                    self.assertFalse(hasattr(ambient, '__notes__'))
                self.assertEqual(final_closes, parent_fd)
                self.assertTrue((self.directory / ('final-' + fault) / '.git/index').is_file())

    def test_open_private_parent_local_error_with_close_failure(self):
        primary = KeyboardInterrupt('local stat')
        real_close = os.close
        def close(fd):
            real_close(fd)
            raise OSError('close')
        with patch.object(m.os, 'fstat', side_effect=primary), patch.object(m.os, 'close', side_effect=close) as closes:
            with self.assertRaises(KeyboardInterrupt) as caught:
                m.open_private_parent(self.directory)
        self.assertIs(caught.exception, primary)
        self.assertIn('FD_FINALIZATION_UNCERTAIN', primary.__notes__)
        self.assertEqual(closes.call_count, 1)

    def synthetic_tool(self):
        home = self.directory / 'synthetic-tool'
        home.mkdir(mode=0o700)
        tool = home / 'git'
        marker = home / 'unexpected-launch'
        tool.write_text('#!/bin/sh\ncase "$1" in\n--version) printf "git version synthetic\\n";;\n'
                        '*) printf bad > ' + shlex.quote(str(marker)) + ';;\nesac\n')
        tool.chmod(0o755)
        return tool, marker

    def test_tool_namespace_rejected_before_inspection_exec(self):
        path, marker = self.synthetic_tool()
        for mode in (0o777, 0o775, 0o1777):
            with self.subTest(mode=mode):
                path.parent.chmod(mode)
                with patch.object(m, '_process', side_effect=AssertionError('must not execute')):
                    with self.assertRaisesRegex(m.Stop, '^GIT_TOOL_NAMESPACE$'):
                        m.inspect_git(path)
                self.assertFalse(marker.exists())

    def test_hash_then_ancestor_replacement_blocked_at_launch(self):
        path, marker = self.synthetic_tool()
        tool = m.inspect_git(path)
        m.tool_checked(tool)  # The earlier hash succeeds.
        path.parent.chmod(0o777)  # Model a newly unsafe namespace, fixture only.
        path.rename(path.parent / 'kept-original')
        path.write_text('#!/bin/sh\nprintf replaced > ' + shlex.quote(str(marker)) + '\n')
        path.chmod(0o755)
        with patch.object(m.subprocess, 'Popen', side_effect=AssertionError('must not launch')):
            with self.assertRaisesRegex(m.Stop, '^GIT_TOOL_NAMESPACE$'):
                m._process([tool.path, 'probe'], m.clean_env(os.devnull, path.parent), git_tool=tool)
        self.assertFalse(marker.exists())

    def test_tool_same_hash_inode_substitution_is_detected(self):
        path, _ = self.synthetic_tool()
        tool = m.inspect_git(path)
        real_read = m.read_regular
        def swap_after_read(name, cap):
            body = real_read(name, cap)
            if os.fspath(name) == str(path):
                path.rename(path.parent / 'kept-original')
                path.write_bytes(body)
                path.chmod(0o755)
            return body
        with patch.object(m, 'read_regular', side_effect=swap_after_read):
            with self.assertRaisesRegex(m.Stop, '^GIT_TOOL_CHANGED$'):
                m.tool_checked(tool)

    def test_git_launch_sites_pass_the_verified_tool(self):
        repo = self.create()
        real = m._process
        calls = []
        def bound(argv, env, **kwargs):
            self.assertIs(kwargs.get('git_tool'), repo.tool)
            calls.append(argv)
            return real(argv, env, **kwargs)
        with patch.object(m, '_process', side_effect=bound):
            m.verify_reader(repo)
        self.assertGreater(len(calls), 8)
        with self.assertRaisesRegex(m.Stop, '^GIT_LAUNCH_PATH$'):
            m._process(['/bin/sh', '-c', 'exit 99'], {}, git_tool=repo.tool)

    def test_current_mac_xcode_namespace_is_rejected_without_execution(self):
        path = Path('/Applications/Xcode.app/Contents/Developer/usr/bin/git')
        if sys.platform != 'darwin' or not path.is_file() or not Path('/Applications').stat().st_mode & 0o022:
            self.skipTest('This host observation applies only to a writable Mac Applications namespace')
        with patch.object(m, '_process', side_effect=AssertionError('unsafe tool must not run')):
            with self.assertRaisesRegex(m.Stop, '^GIT_TOOL_NAMESPACE$'):
                m.inspect_git(path)


class CleanupTests(unittest.TestCase):
    """Faults use fake descriptors/processes; never launch a child or network."""

    def ambient_call(self, operation):
        ambient = ValueError('caller exception is not an operation failure')
        try:
            raise ambient
        except ValueError:
            try:
                return operation()
            finally:
                self.assertFalse(hasattr(ambient, '__notes__'))

    def test_fd_finalization_ignores_ambient_and_attempts_all_once(self):
        for fault in ('close', 'fsync', 'both'):
            with self.subTest(fault=fault), patch.object(m.os, 'close') as close, patch.object(m.os, 'fsync') as sync:
                if fault in ('close', 'both'):
                    close.side_effect = OSError('close')
                if fault in ('fsync', 'both'):
                    sync.side_effect = OSError('sync')
                with self.assertRaisesRegex(m.Stop, '^FD_FINALIZATION_UNCERTAIN$'):
                    self.ambient_call(lambda: m.finish_fds((101, None, 102), sync_fd=103))
                self.assertEqual(close.call_args_list, [unittest.mock.call(101), unittest.mock.call(102)])
                sync.assert_called_once_with(103)
        self.ambient_call(lambda: m.finish_fds(()))

    def test_read_success_and_local_primary_are_distinct_from_ambient(self):
        for fault in ('none', 'close', 'read_and_close'):
            with self.subTest(fault=fault), patch.object(m.os, 'open', return_value=101), patch.object(m.os, 'fstat') as st, patch.object(m.os, 'read') as read, patch.object(m.os, 'close') as close:
                st.return_value = Mock(st_mode=0o100600, st_nlink=1, st_size=2, st_dev=1, st_ino=2, st_mtime_ns=3)
                primary = KeyboardInterrupt('local read')
                read.side_effect = primary if fault == 'read_and_close' else [b'ok', b'']
                if fault != 'none':
                    close.side_effect = OSError('close')
                if fault == 'none':
                    self.assertEqual(self.ambient_call(lambda: m.read_regular('fake', 8)), b'ok')
                elif fault == 'close':
                    with self.assertRaisesRegex(m.Stop, '^FD_FINALIZATION_UNCERTAIN$'):
                        self.ambient_call(lambda: m.read_regular('fake', 8))
                else:
                    with self.assertRaises(KeyboardInterrupt) as caught:
                        self.ambient_call(lambda: m.read_regular('fake', 8))
                    self.assertIs(caught.exception, primary)
                    self.assertIn('FD_FINALIZATION_UNCERTAIN', primary.__notes__)
                close.assert_called_once_with(101)

    def test_directory_chain_body_acquisition_and_success_cleanup(self):
        for fault in ('none', 'body', 'open'):
            with self.subTest(fault=fault), patch.object(m.os, 'dup', return_value=101), patch.object(m.os, 'open', return_value=102) as op, patch.object(m.os, 'close', side_effect=OSError('close')) as close:
                primary = ValueError('local directory')
                if fault == 'open':
                    op.side_effect = primary
                def operation():
                    with m.directory_chain(100, ('part',)):
                        if fault == 'body':
                            raise primary
                with self.assertRaises(m.Stop if fault == 'none' else ValueError) as caught:
                    self.ambient_call(operation)
                if fault != 'none':
                    self.assertIs(caught.exception, primary)
                    self.assertIn('FD_FINALIZATION_UNCERTAIN', primary.__notes__)
                expected = [101] if fault == 'open' else [102, 101]
                self.assertEqual([c.args[0] for c in close.call_args_list], expected)

    def test_process_success_close_and_local_errors_with_fake_popen(self):
        for fault in ('none', 'close', 'body', 'timeout', 'poll'):
            with self.subTest(fault=fault), patch.object(m.subprocess, 'Popen') as popen, patch.object(m.selectors, 'DefaultSelector') as selector, patch.object(m.os, 'killpg') as kill:
                p = popen.return_value
                p.poll.return_value = 0
                p.wait.return_value = 0
                selector.return_value.__enter__.return_value.get_map.return_value = {}
                primary = KeyboardInterrupt('local process')
                if fault == 'body':
                    selector.return_value.__enter__.side_effect = primary
                elif fault == 'timeout':
                    p.wait.side_effect = m.subprocess.TimeoutExpired('fake', 1)
                elif fault == 'poll':
                    p.poll.side_effect = OSError('poll')
                if fault != 'none':
                    p.stdout.close.side_effect = OSError('close')
                if fault == 'none':
                    self.assertEqual(self.ambient_call(lambda: m._process(['fake'], {})), (0, b'', b''))
                else:
                    with self.assertRaises(KeyboardInterrupt if fault == 'body' else m.Stop) as caught:
                        self.ambient_call(lambda: m._process(['fake'], {}))
                    if fault == 'body':
                        self.assertIs(caught.exception, primary)
                    self.assertEqual(str(caught.exception), 'GIT_TIMEOUT' if fault == 'timeout' else 'local process' if fault == 'body' else 'GIT_FINALIZATION_UNCERTAIN')
                    if fault in ('body', 'timeout'):
                        self.assertIn('GIT_FINALIZATION_UNCERTAIN', caught.exception.__notes__)
                p.stdout.close.assert_called_once()
                p.stderr.close.assert_called_once()
                self.assertEqual(kill.call_count, int(fault == 'poll'))

    def test_write_nested_cleanup_preserves_local_error(self):
        for fault in ('close', 'write'):
            with self.subTest(fault=fault), patch.object(m.os, 'dup', return_value=101), patch.object(m.os, 'open', return_value=102), patch.object(m.os, 'fstat', return_value=Mock(st_mode=0o100600, st_nlink=1, st_uid=os.geteuid())), patch.object(m.os, 'write', return_value=2) as write, patch.object(m.os, 'fchmod'), patch.object(m.os, 'fsync'), patch.object(m.os, 'close', side_effect=OSError('close')) as close:
                primary = ValueError('write')
                if fault == 'write':
                    write.side_effect = primary
                with self.assertRaises(m.Stop if fault == 'close' else ValueError) as caught:
                    self.ambient_call(lambda: m.write_at(100, 'file', b'ok', 0o600))
                if fault == 'write':
                    self.assertIs(caught.exception, primary)
                self.assertIn('FD_FINALIZATION_UNCERTAIN', caught.exception.__notes__)
                self.assertEqual([c.args[0] for c in close.call_args_list], [102, 101])


if __name__ == '__main__':
    unittest.main(verbosity=2)
