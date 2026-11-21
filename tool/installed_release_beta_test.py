from contextlib import closing
from copy import deepcopy
import io
import json
from pathlib import Path
import plistlib
import shlex
import shutil
import sqlite3
from subprocess import CompletedProcess, run
import sys
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import accept_installed_release as accept
import installed_release_beta as beta
from installed_release_beta import (DATABASE, LOCK, beta_inventory, capture_cli, capture_closed,
                                    capture_guest_closed, compare_cli, compare_sqlite,
                                    ownership, pinned, pinned_json, require_guest_storage_released,
                                    verify_archived_snapshot, verify_busy, verify_history_export, verify_shutdown)
from release_materials import digest


NORMAL_SHUTDOWN = {'runtime': 'meshchan.shutdown.1d3', 'quitPhase': 'ready',
                   'resourcesReleased': True, 'workerExited': True, 'workerWasSpawned': True,
                   'owner': 'released', 'error': None, 'maintenanceFailureCount': 0,
                   'pendingRequests': 0, 'receivePorts': 0}


class ClosedUpgradeTest(unittest.TestCase):
    def setUp(self):
        temp = self.enterContext(tempfile.TemporaryDirectory())
        self.root = Path(temp).resolve()
        self.source = self.root / 'owned source'
        self.source.mkdir()
        (self.source / LOCK).touch()
        with closing(sqlite3.connect(self.source / DATABASE)) as db:
            db.executescript((Path(__file__).resolve().parents[1] / 'packages/meshchan_core'
                              / 'lib/src/storage/schema.drift').read_text())
            db.execute('PRAGMA user_version=1')
            db.execute('INSERT INTO stored_drafts VALUES (?, ?, ?, ?, ?, ?)',
                       ('0' * 32, 'Older', '中文 🚀\nline two\n', 101, 103, 2))
            db.execute('INSERT INTO stored_profiles VALUES (?, ?, ?, ?, ?, ?)',
                       ('a' * 32, 'Preset', '/fixture/port', 'ping', '{"route":null}', 105))
            db.execute('INSERT INTO stored_settings VALUES (?, ?, ?)', (1, 'a' * 32, 1001))
            for number, version in [(1, '0.1.0-beta.1+5'), (2, '0.1.0-beta.1+4')]:
                db.execute('INSERT INTO stored_runs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                           (str(number) * 32, 'ping', version, None, '{}', 100, 101,
                            'settled', '{}', '{}', None, None, 1))
            db.commit()
        self.sha = digest(self.source / DATABASE)

    def project(self, name):
        return capture_closed(self.source, self.root / name, expected_main_sha256=self.sha)['database']

    def test_busy_source_is_never_read_or_copied(self):
        with ownership(self.source), self.assertRaisesRegex(ValueError, 'still owned'):
            self.project('blocked')
        self.assertFalse((self.root / 'blocked').exists())
        self.assertEqual(digest(self.source / DATABASE), self.sha)
        self.assertEqual(len(self.project('released')['history']), 2)

    def test_guest_release_check_observes_the_existing_lock_without_writing(self):
        home = self.root/'fixture home'
        data = home/'Library/Application Support/meshchan'
        data.mkdir(parents=True)
        lock = data/LOCK
        lock.write_bytes(b'existing lock')
        marker = data/'.meshchan.owner.json'
        marker.write_bytes(b'existing marker')
        lock_identity = lock.stat()

        def local_remote(command, **kwargs):
            arguments = shlex.split(command)
            self.assertEqual(arguments[3:], [beta.GUEST_STORAGE_PROBE, '--', 'testuser'])
            # Supply an isolated home in place of the VM account lookup.
            script = beta.GUEST_STORAGE_LOCK + '\nmy $lock = lock_default_storage(shift @ARGV);\n'
            return run([*arguments[:3], script, '--', str(home)], check=True, **kwargs)

        with ownership(data), self.assertRaisesRegex(ValueError, 'Directory still owned'):
            require_guest_storage_released(local_remote, 'testuser')
        require_guest_storage_released(local_remote, 'testuser')
        self.assertEqual({path.name for path in data.iterdir()}, {lock.name, marker.name})
        self.assertEqual(lock.stat().st_ino, lock_identity.st_ino)
        self.assertEqual(lock.read_bytes(), b'existing lock')
        self.assertEqual(marker.read_bytes(), b'existing marker')

        lock.unlink()
        with self.assertRaisesRegex(ValueError, 'Wrong ownership file'):
            require_guest_storage_released(local_remote, 'testuser')
        self.assertFalse(lock.exists())
        lock.symlink_to(marker)
        with self.assertRaisesRegex(ValueError, 'Wrong ownership file'):
            require_guest_storage_released(local_remote, 'testuser')
        self.assertTrue(lock.is_symlink())
        self.assertEqual(marker.read_bytes(), b'existing marker')

    def test_snapshot_keeps_present_sidecar_and_never_overwrites(self):
        journal = self.source / (DATABASE + '-journal')
        journal.touch()
        output = self.root / 'snapshot'
        result = capture_closed(self.source, output)
        self.assertEqual(set(result['files']), {DATABASE, journal.name})
        self.assertEqual((output / journal.name).read_bytes(), b'')
        self.assertEqual((output / DATABASE).stat().st_mode & 0o777, 0o400)
        with self.assertRaises(FileExistsError):
            capture_closed(self.source, output)
        self.assertEqual(digest(output / DATABASE), self.sha)

    def test_archived_snapshot_revalidates_actual_members_and_saved_rows(self):
        output = self.root / 'close evidence'
        recorded = capture_closed(self.source, output)
        self.assertEqual(verify_archived_snapshot(output, recorded), recorded)
        contradictory = deepcopy(recorded)
        contradictory['database']['drafts'][0]['body'] = 'not in these files'
        with self.assertRaisesRegex(ValueError, 'Archived SQLite projection differs'):
            verify_archived_snapshot(output, contradictory)
        unexpected = output / 'marker'
        unexpected.write_text('not a SQLite member')
        with self.assertRaisesRegex(ValueError, 'Archived SQLite member set differs'):
            verify_archived_snapshot(output, recorded)
        unexpected.unlink()
        sidecar = output / (DATABASE + '-journal')
        sidecar.touch()
        with self.assertRaisesRegex(ValueError, 'Archived SQLite member hashes differ'):
            verify_archived_snapshot(output, recorded)
        sidecar.unlink()
        retained = output / DATABASE
        retained.chmod(0o600)
        retained.write_bytes(b'modified')
        with self.assertRaisesRegex(ValueError, 'Archived SQLite member hashes differ'):
            verify_archived_snapshot(output, recorded)
        retained.unlink()
        with self.assertRaises(FileNotFoundError):
            verify_archived_snapshot(output, recorded)

    def test_hot_journal_recovers_only_in_disposable_projection_copy(self):
        source = self.source / DATABASE
        committed = 'a' * 1600
        with closing(sqlite3.connect(source)) as db:
            db.execute('DELETE FROM stored_drafts')
            db.executemany('INSERT INTO stored_drafts VALUES (?, ?, ?, ?, ?, ?)',
                           ((f'{number:032x}', 'Fixture', committed, 100, 100, 1)
                            for number in range(80)))
            db.commit()
        interrupted_transaction = """
import os
import sqlite3
import sys

db = sqlite3.connect(sys.argv[1])
db.execute('PRAGMA cache_size=5')
db.execute('BEGIN IMMEDIATE')
db.execute('UPDATE stored_drafts SET body=?', ('b' * 1600,))
os._exit(0)
"""
        run([sys.executable, '-B', '-c', interrupted_transaction, source], check=True, timeout=10)
        journal = self.source / (DATABASE + '-journal')
        with journal.open('rb') as stream:
            self.assertEqual(stream.read(8), bytes.fromhex('d9d505f920a163d7'))
        files = {file.name: digest(file) for file in (source, journal)}
        output = self.root / 'hot journal snapshot'
        report = capture_closed(self.source, output)
        self.assertEqual(len(report['database']['drafts']), 80)
        self.assertTrue(all(row['body'] == committed for row in report['database']['drafts']))
        self.assertEqual({name: digest(self.source / name) for name in files}, files)
        self.assertEqual({name: digest(output / name) for name in files}, files)

    def test_readable_snapshot_with_dangling_default_profile_is_rejected(self):
        source = self.source / DATABASE
        with closing(sqlite3.connect(source)) as db:
            db.execute('PRAGMA foreign_keys = OFF')
            db.execute('UPDATE stored_settings SET default_profile_id = ?', ('b' * 32,))
            db.commit()
        pin = digest(source)
        output = self.root / 'foreign key violation'
        with self.assertRaisesRegex(ValueError, 'SQLite foreign-key check failed'):
            capture_closed(self.source, output)
        self.assertEqual(digest(source), pin)
        self.assertEqual(digest(output / DATABASE), pin)

    def test_readable_snapshot_with_invalid_draft_revision_is_rejected(self):
        with closing(sqlite3.connect(self.source / DATABASE)) as db:
            db.execute('PRAGMA ignore_check_constraints = ON')
            db.execute('UPDATE stored_drafts SET revision = 0')
            db.commit()
        with self.assertRaisesRegex(ValueError, 'SQLite integrity check differs'):
            capture_closed(self.source, self.root / 'check violation')

    def test_sidecar_redirect_and_wrong_digest_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'digest differs'):
            capture_closed(self.source, self.root / 'wrong', expected_main_sha256='f' * 64)
        (self.source / (DATABASE + '-wal')).symlink_to(self.source / DATABASE)
        with self.assertRaisesRegex(ValueError, 'single-link regular'):
            self.project('redirected')
        self.assertFalse((self.root / 'redirected').exists())

    def test_selected_beta_copy_uses_its_members_and_binds_historical_paths(self):
        current = self.root / 'selected copy'
        historical = self.root / 'unavailable original'
        history = Path('hardware/run-09-rf-restart')
        retained = current / history / 'delivery-prepared-retained'
        metadata = retained / 'metadata'
        metadata.mkdir(parents=True)

        def record(path, value):
            path.write_text(json.dumps(value))
            return digest(path)

        def product(label, name, relative, data):
            file = retained / name / relative
            file.parent.mkdir(parents=True)
            file.write_bytes(data)
            return {label: {'path': str(historical / 'delivery-beta1-build5' / name),
                            'inventory': {relative: {'sha256': digest(file), 'size': len(data),
                                                     'mode': file.stat().st_mode & 0o777}}}}

        app = product('app', 'Meshchan.app', 'Contents/Info.plist', plistlib.dumps({
            'CFBundleIdentifier': 'org.meshchan.meshchan', 'CFBundleExecutable': 'Meshchan',
            'CFBundleShortVersionString': '0.1.0.1', 'CFBundleVersion': '5',
        }))
        cli = product('cli', 'meshctl', 'bin/meshctl', b'fixture')
        products = record(metadata / 'products.json', app | cli)
        handoff = {}
        for name in beta.NONBUILD_HANDOFF_CHANGES:
            file = retained / 'source' / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('prepared')
            handoff[name] = digest(file)
        handoff_pin = record(metadata / 'source-handoff.json', handoff)
        compilation = current / 'source-hw08-build5-input.json'
        added_note = 'docs/validation/phase-1d11-build5-gui-delay.md'
        compilation_pin = record(compilation, dict.fromkeys(handoff.keys() - {added_note}, 'compile'))
        shutil.copyfile(compilation, metadata / 'source-manifest.json')
        diff = metadata / 'source-compilation.diff'
        diff.write_text('retained diff')
        fixture = current / history / 'vm-source-closed-fixture'
        fixture.mkdir()
        shutil.copyfile(self.source / DATABASE, fixture / DATABASE)
        (fixture / LOCK).touch()
        close_pin = record(current / history / 'offline-host-verification.json', {
            'safeClosedFixtureForVm': str(historical / fixture.relative_to(current)),
            'actualShutdown': NORMAL_SHUTDOWN, 'osPidAbsent': True, 'allIndependentConsumersClosed': True,
        })
        summary = current / history / 'vm-offline/Release/exports/meshchan-beta5-summary-run09.json'
        summary.parent.mkdir(parents=True)
        versions = [beta.BETA_APP] * 6 + ['0.1.0-beta.1+4'] * 4 + ['0.1.0-beta.1+3'] * 2
        summary_pin = record(summary, {'diagnosticSummaryFormatVersion': 1,
                                       'runs': [{'appVersion': value} for value in versions]})
        self.assertFalse(historical.exists())
        with (patch.multiple(beta, PRODUCTS_PIN=products, INPUT_PIN=compilation_pin,
                             DIFF_PIN=digest(diff), HANDOFF_PIN=handoff_pin, CLOSE_PIN=close_pin,
                             DATABASE_PIN=self.sha, SUMMARY_PIN=summary_pin),
              patch.object(beta.subprocess, 'run') as codesign):
            report = beta.verify_beta(current)
            unexpected = record(metadata / 'source-handoff.json', handoff | {'tool/new.py': 'unexpected'})
            with patch.object(beta, 'HANDOFF_PIN', unexpected):
                with self.assertRaisesRegex(ValueError, 'unexpected compilation-input differences'):
                    beta.verify_beta(current)
        self.assertEqual(report['app'], str(retained / 'Meshchan.app'))
        self.assertEqual(report['cli'], str(retained / 'meshctl'))
        self.assertEqual(report['closedFixture'], str(fixture))
        self.assertIn(added_note, report['source']['nonbuildHandoffChanges'])
        self.assertEqual(codesign.call_count, 2)

    def mock_guest(self, *extra):
        stream = io.BytesIO()
        with tarfile.open(fileobj=stream, mode='w') as archive:
            archive.add(self.source / DATABASE, arcname=DATABASE)
            for name in extra:
                archive.add(self.source / DATABASE, arcname=name)
        return lambda script, **kwargs: CompletedProcess([script], 0, stream.getvalue(), b'')

    def test_guest_archive_only_accepts_the_expected_sqlite_members(self):
        output = self.root / 'guest snapshot'
        for unexpected in (DATABASE, 'unrelated.sqlite', '../meshchan.sqlite'):
            with self.subTest(member=unexpected), self.assertRaisesRegex(ValueError, 'archive member set'):
                capture_guest_closed(self.mock_guest(unexpected), 'testuser', 123,
                                     NORMAL_SHUTDOWN, output)
            self.assertFalse(output.exists())
        guest = capture_guest_closed(self.mock_guest(), 'testuser', 123, NORMAL_SHUTDOWN, output)
        self.assertEqual(guest['files'][DATABASE]['sha256'], self.sha)
        self.assertEqual(guest['database'], self.project('local comparison'))

    def test_guest_snapshot_can_retry_after_a_projection_failure(self):
        output = self.root / 'guest snapshot'
        remote = self.mock_guest()
        with patch.object(beta, 'project_archive', side_effect=OSError('projection unavailable')):
            with self.assertRaisesRegex(OSError, 'projection unavailable'):
                capture_guest_closed(remote, 'testuser', 123, NORMAL_SHUTDOWN, output)
        self.assertFalse(output.exists())
        self.assertEqual(list(self.root.iterdir()), [self.source])
        result = capture_guest_closed(remote, 'testuser', 123, NORMAL_SHUTDOWN, output)
        self.assertEqual(verify_archived_snapshot(output, result), result)

    def test_closed_command_recovers_when_snapshot_was_saved_before_summary_failed(self):
        evidence = self.root/'case'
        evidence.mkdir()
        layout = accept.path_layout('testuser', 'case')
        root = '/Users/testuser/utm-ui-isolation'
        session = root+'/package.ABCDEF01'
        launch = evidence/'launch-reopen.json'
        accept.write_new(launch, {'status': 'REQUESTED', 'method': 'LaunchServices', 'arguments': [],
                                  'app': layout['app'], 'guestSession': session,
                                  'systemProtection': accept.SYSTEM_PROTECTION})
        runtime = {'pid': 123, 'app': layout['app'], 'dataDirectory': layout['data'],
                   'guestSession': session, 'launchSha256': accept.digest(launch)}
        runtime_path = evidence/'runtime-reopen.json'
        accept.write_new(runtime_path, runtime)
        summary = evidence/'closed-reopen.json'
        original_write = accept.write_new

        def fail_summary(path, report):
            if path == summary:
                raise OSError('summary publication failed')
            original_write(path, report)

        argv = ['accept', 'closed', '--label', 'reopen', '--run', 'case',
                '--vm-config', 'unused', '--evidence', str(evidence)]
        vm = SimpleNamespace(root=root, c={'user': 'testuser'}, remote=self.mock_guest())
        with (patch.object(sys, 'argv', argv),
              patch.object(accept.guest, 'load', return_value=SimpleNamespace(VM=lambda _: vm)),
              patch.object(accept, 'checked_case', return_value=layout),
              patch.object(accept, 'require_detached_case'), patch.object(accept, 'require_unmounted'),
              patch.object(accept.guest, 'require_absent_pid'), patch.object(accept, 'require_launch_streams'),
              patch.object(accept, 'output', return_value=json.dumps(NORMAL_SHUTDOWN)),
              patch.object(vm, 'remote', wraps=vm.remote) as remote):
            with patch.object(accept, 'write_new', side_effect=fail_summary):
                with self.assertRaisesRegex(OSError, 'summary publication failed'):
                    accept.main()
            self.assertFalse(summary.exists())
            checkpoint = evidence/'closed-reopen/receipt.json'
            diverted = checkpoint.with_name('diverted.json')
            checkpoint.rename(diverted)
            checkpoint.symlink_to(diverted)
            with self.assertRaisesRegex(ValueError, 'single-link regular file'):
                accept.main()
            checkpoint.unlink()
            diverted.rename(checkpoint)
            accept.main()
            _, closed, database = accept.verify_case_close(vm, layout, evidence, 'reopen')
            self.assertEqual(database, self.project('local comparison'))
            self.assertEqual(closed['runtimeSha256'], accept.digest(runtime_path))
            runtime_path.write_text(json.dumps({**runtime, 'unexpectedChange': True}))
            with self.assertRaisesRegex(ValueError, 'runtimeSha256'):
                accept.verify_case_close(vm, layout, evidence, 'reopen')
            remote.assert_called_once()

    def test_guest_collection_checks_quit_and_pid_before_any_remote_command(self):
        def no_remote(*args, **kwargs):
            self.fail('Rejected collection called the guest')
        output = self.root / 'guest snapshot'
        with self.assertRaisesRegex(ValueError, 'observed application PID'):
            capture_guest_closed(no_remote, 'testuser', True, NORMAL_SHUTDOWN, output)
        with self.assertRaisesRegex(ValueError, 'shutdown receipt differs'):
            capture_guest_closed(no_remote, 'testuser', 123,
                                 dict(NORMAL_SHUTDOWN, owner='busy'), output)

    def test_full_projection_detects_unplanned_changes(self):
        original = self.project('base')
        mutations = {
            'rewritten old version': ('history', 0, 'app_version', '0.1.0-rc.1+8'),
            'lost source': ('history', 0, 'profile_id', 'a' * 32),
            'changed terminal result': ('history', 0, 'result_json', '{"new":true}'),
            'normalized content': ('drafts', 0, 'body', '中文 🚀\nline two'),
            'unexpected revision': ('drafts', 0, 'revision', 3),
            'changed profile': ('profiles', 0, 'parameters_json', '{}'),
            'reset setting': ('settings', 0, 'default_profile_id', None),
        }
        for name, (key, index, field, value) in mutations.items():
            with self.subTest(name=name):
                changed = deepcopy(original)
                changed[key][index][field] = value
                with self.assertRaisesRegex(ValueError, key + ' differs'):
                    compare_sqlite(original, changed)
        for changed_rows in [original['history'][1:], original['history'][::-1],
                             original['history'] + original['history'][:1]]:
            changed = dict(original, history=changed_rows)
            with self.assertRaisesRegex(ValueError, 'history differs'):
                compare_sqlite(original, changed)

    def test_only_declared_new_draft_and_history_limit_can_change(self):
        original = self.project('base')
        draft = {'id': 'c' * 32, 'title': 'Upgrade', 'body': '新 🍀\ntext\n',
                 'created_at_us': 120, 'updated_at_us': 120, 'revision': 1}
        changed = deepcopy(original)
        changed['drafts'].append(draft)
        changed['settings'][0]['diagnostic_history_limit'] = 1002
        compare_sqlite(original, changed, new_draft=draft, history_limit=1002)
        with self.assertRaisesRegex(ValueError, 'New draft revision differs'):
            compare_sqlite(original, changed, new_draft=dict(draft, revision=True), history_limit=1002)
        with self.assertRaisesRegex(ValueError, 'History retention'):
            compare_sqlite(original, changed, new_draft=draft, history_limit=1)
        with self.assertRaisesRegex(ValueError, 'drafts differs'):
            compare_sqlite(original, changed, new_draft=dict(draft, body='other'), history_limit=1002)

    def test_public_projection_compares_unicode_fields_and_date(self):
        before = {'drafts': [], 'settings': {'diagnosticHistoryLimit': 1001, 'defaultProfileId': None},
                  'profiles': [], 'history': {'items': [], 'details': []}, 'schemaVersion': 1,
                  'summary': {'diagnosticSummaryFormatVersion': 1, 'runs': []}}
        after = deepcopy(before)
        draft = {'id': 'c' * 32, 'title': 'Upgrade', 'body': '新 🍀\ntext\n',
                 'created_at_us': 120, 'updated_at_us': 120, 'revision': 1}
        date = '1970-01-01T00:00:00.000120Z'
        after['drafts'].append({'id': draft['id'], 'title': draft['title'], 'body': draft['body'],
                                'revision': 1, 'createdAt': date, 'updatedAt': date,
                                'bodyUtf8ByteLength': 14})
        after['settings']['diagnosticHistoryLimit'] = 1002
        compare_cli(before, after, new_draft=draft, history_limit=1002)
        after['drafts'][0]['updatedAt'] = '1970-01-01T00:00:00.000121Z'
        with self.assertRaisesRegex(ValueError, 'CLI projection drafts differs'):
            compare_cli(before, after, new_draft=draft, history_limit=1002)

    def test_history_export_must_match_nested_stored_values(self):
        database = self.project('history before SQL comparison')
        run = {'operation': 'ping', 'diagnosticSummaryFormatVersion': 1,
               'recordState': 'settled', 'recoveryReason': None,
               'preparedAt': '1970-01-01T00:00:00.000100Z',
               'logicalEndedAt': '1970-01-01T00:00:00.000101Z', 'recoveredAt': None,
               'configuration': {}, 'result': {}, 'cleanup': {}}
        runs = [dict(run, runId='2' * 32, appVersion='0.1.0-beta.1+4'),
                dict(run, runId='1' * 32, appVersion='0.1.0-beta.1+5')]
        public = {'summary': {'diagnosticSummaryFormatVersion': 1, 'runs': runs}}
        verify_history_export(public, database)
        runs[0]['result'] = {'reason': 'changed but same id'}
        with self.assertRaisesRegex(ValueError, 'CLI History export against closed SQLite differs'):
            verify_history_export(public, database)


class BetaAdmissionTest(unittest.TestCase):
    def test_json_is_parsed_from_the_authenticated_open(self):
        with tempfile.TemporaryDirectory() as path:
            file = Path(path).resolve() / 'metadata.json'
            file.write_text('{"version": 5}')
            pin = digest(file)
            with patch.object(Path, 'read_bytes', side_effect=AssertionError('Unexpected reopen')):
                self.assertEqual(pinned_json(file, pin), {'version': 5})
            file.write_text('{"version": 8}')
            with self.assertRaisesRegex(ValueError, 'SHA-256 pin'):
                pinned_json(file, pin)

    def test_inventory_rejects_missing_files_and_wrong_versions(self):
        with tempfile.TemporaryDirectory() as path:
            root = Path(path).resolve()
            file = root / 'metadata'
            file.write_text('build 5')
            pin = digest(file)
            inventory = {'metadata': {'sha256': pin, 'size': 7, 'mode': file.stat().st_mode & 0o777}}
            beta_inventory(root, inventory)
            pinned(file, pin)
            file.write_text('build 8')
            with self.assertRaisesRegex(ValueError, 'digest differs'):
                pinned(file, pin)
            with self.assertRaisesRegex(ValueError, 'inventory .* differs'):
                beta_inventory(root, inventory)
            file.unlink()
            (root / 'partial').touch()
            with self.assertRaisesRegex(ValueError, 'inventory .* differs'):
                beta_inventory(root, inventory)

    def test_busy_requires_real_exit_and_no_business_or_close_admission(self):
        envelope = {'schemaVersion': 1, 'command': 'draft', 'action': 'list',
                    'operationSucceeded': False, 'committed': False, 'exitCode': 69,
                    'reason': 'business_failure', 'additionalFailures': [], 'maintenance': None,
                    'storageClose': None, 'hostCleanup': 'succeeded',
                    'failure': {'domain': 'storage', 'source': 'open', 'code': 'data_directory_busy',
                                'cleanupUnconfirmed': False}}
        verify_busy(CompletedProcess([], 69, json.dumps(envelope), ''))
        with self.assertRaisesRegex(ValueError, 'process exit'):
            verify_busy(CompletedProcess([], 0, json.dumps(envelope), ''))
        for key, wrong in [('schemaVersion', True), ('committed', 0), ('items', []),
                           ('storageClose', {'state': 'closed', 'error': None})]:
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'envelope differs'):
                verify_busy(CompletedProcess([], 69, json.dumps(dict(envelope, **{key: wrong})), ''))

    def test_shutdown_requires_normal_release_and_worker_exit(self):
        verify_shutdown(NORMAL_SHUTDOWN)
        for field, value in [('quitPhase', 'forced'), ('workerExited', False),
                             ('resourcesReleased', 1), ('owner', 'busy'), ('pendingRequests', 1)]:
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'shutdown receipt differs'):
                verify_shutdown(dict(NORMAL_SHUTDOWN, **{field: value}))


class PublicProjectionTest(unittest.TestCase):
    def setUp(self):
        old = '2026-11-21T19:52:03.100000Z'
        recent = '2026-11-21T19:52:03.100001Z'
        first, second = '1' * 32, '2' * 32
        draft = {'title': '中文', 'body': '🍀\n文', 'createdAt': old, 'bodyUtf8ByteLength': 8,
                 'revision': 1, 'updatedAt': recent}
        profile = {'name': 'Fixture', 'operation': 'ping', 'updatedAt': recent,
                   'portHint': None, 'parameters': {'route': None}}
        run = {'appVersion': '0.1.0-beta.1+5', 'operation': 'ping', 'preparedAt': recent,
               'logicalEndedAt': recent, 'recoveredAt': None, 'configuration': {'route': None},
               'diagnosticSummaryFormatVersion': 1, 'recordState': 'settled', 'recoveryReason': None}
        self.rows = {'draft': [dict(draft, id=second), dict(draft, id=first)],
                     'profile': [dict(profile, id=first)],
                     'history': [dict(run, runId=first)]}
        self.summary = {'diagnosticSummaryFormatVersion': 1, 'exportedAt': recent,
                        'runs': deepcopy(self.rows['history'])}
        self.pages = {
            'draft': [{k: v for k, v in row.items() if k != 'body'} for row in self.rows['draft']],
            'profile': [{k: v for k, v in profile.items() if k not in {'parameters', 'portHint'}}
                        | {'id': first}],
            'history': [{k: v for k, v in run.items() if k != 'configuration'} | {'runId': first}],
        }

    def invoke(self, command, action, *args):
        value = {'schemaVersion': 1, 'command': command, 'action': action, 'operationSucceeded': True,
                 'reason': 'completed', 'exitCode': 0, 'failure': None,
                 'storageClose': {'state': 'closed', 'error': None},
                 'hostCleanup': 'succeeded', 'additionalFailures': [],
                 'maintenance': {'unacknowledgedFailure': None, 'unacknowledgedFailureCount': 0,
                                 'latest': {'deletedCount': 0}}}
        if action == 'export':
            value.update({'event': 'metadata', 'nextCursor': None})
            return CompletedProcess(args, 0, json.dumps(self.summary), json.dumps(value))
        value['committed'] = None
        if action == 'list':
            value.update({'items': self.pages[command], 'nextCursor': None})
        elif command == 'settings':
            value['settings'] = {'defaultProfileId': None, 'diagnosticHistoryLimit': 1001}
        else:
            inner, field = ('run', 'runId') if command == 'history' else (command, 'id')
            value[inner] = next(row for row in self.rows[command] if row[field] == args[1])
        return CompletedProcess(args, 0, json.dumps(value), '')

    def test_cross_checks_list_fields_and_order_against_show(self):
        report = capture_cli(self.invoke)
        self.assertEqual(report['drafts'], self.rows['draft'][::-1])
        self.assertEqual(report['history']['items'], self.pages['history'])
        mutations = [
            ('draft', [dict(self.pages['draft'][0], title='wrong'),
                       self.pages['draft'][1]]),
            ('draft', self.pages['draft'][::-1]),
            ('profile', [dict(self.pages['profile'][0], name='wrong')]),
            ('history', [dict(self.pages['history'][0], appVersion='0.1.0-rc.1+8')]),
        ]
        for command, bad_page in mutations:
            with self.subTest(command=command), patch.dict(self.pages, {command: bad_page}):
                with self.assertRaisesRegex(ValueError, command + ' list/show fields and order'):
                    capture_cli(self.invoke)

    def test_export_receipt_binds_shared_values_beyond_the_run_id(self):
        self.summary['runs'][0]['appVersion'] = '0.1.0-rc.1+8'
        with self.assertRaisesRegex(ValueError, 'CLI History detail/export identity'):
            capture_cli(self.invoke)
        del self.summary['exportedAt']
        with self.assertRaisesRegex(ValueError, 'CLI diagnostic summary envelope fields'):
            capture_cli(self.invoke)


if __name__ == '__main__':
    unittest.main()
