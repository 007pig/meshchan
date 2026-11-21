"""Exercise closed fixture staging and the two business comparison modes."""

from contextlib import closing
from copy import deepcopy
import json
import os
from pathlib import Path, PurePosixPath
import pwd
import sqlite3
from subprocess import CalledProcessError, CompletedProcess, TimeoutExpired, run
import sys
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import installed_release_beta as beta
import installed_release_workflow as workflow
from release_materials import digest


class BetaStageTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        self.source = self.root/'source'
        self.source.mkdir()
        self.evidence = self.root/'evidence'
        self.evidence.mkdir()
        self.fixture = self.source/'fixture'
        self.fixture.mkdir()
        (self.fixture/beta.LOCK).touch()
        (self.fixture/'.meshchan.owner.json').write_text('{"pid":123}')
        schema = Path(__file__).resolve().parents[1]/'packages/meshchan_core/lib/src/storage/schema.drift'
        with closing(sqlite3.connect(self.fixture/beta.DATABASE)) as db:
            db.executescript(schema.read_text())
            db.execute('PRAGMA user_version=1')
        db_pin = digest(self.fixture/beta.DATABASE)
        products = {}
        for label, name, leaf in (('app', workflow.APP, 'Contents/MacOS/Meshchan'),
                                  ('cli', workflow.CLI, workflow.CLI_BINARY)):
            main = self.source/name/leaf
            main.parent.mkdir(parents=True)
            main.write_text(label)
            main.chmod(0o755)
            products[label] = {'inventory': {
                leaf: {'size': len(label), 'mode': 0o755, 'sha256': digest(main)},
            }}
        manifest = self.source/'products.json'
        manifest.write_text(json.dumps(products))
        manifest_pin = digest(manifest)
        self.enterContext(patch.multiple(beta, DATABASE_PIN=db_pin, PRODUCTS_PIN=manifest_pin))
        self.admitted = {
            'app': str(self.source/workflow.APP), 'cli': str(self.source/workflow.CLI),
            'closedFixture': str(self.fixture), 'closedDatabaseSha256': db_pin,
            'productsManifest': {'path': str(manifest), 'sha256': manifest_pin},
        }
        home = PurePosixPath('/Users/testuser')
        self.layout = {
            'home': str(home), 'app': str(home/'Applications/Meshchan.app'),
            'data': str(home/'Library/Application Support/meshchan'),
        }
        self.guest_cli = home/'Library/Application Support/meshchan-engineering/beta-reference/test/meshctl'

    def test_transfer_contains_complete_products_and_only_writable_sqlite_members(self):
        def receive(script, *, stdin, capture_output, timeout):
            self.assertTrue(capture_output)
            run(['/bin/sh', '-n'], input=script, text=True, check=True)
            self.assertIn('/usr/bin/tar -xpkf', script)
            self.assertIn('/usr/bin/codesign --verify --deep --strict', script)
            with tarfile.open(fileobj=stdin, mode='r:') as archive:
                files = {member.name: member for member in archive if member.isfile()}
                self.assertEqual(set(files),
                                 {'Meshchan.app/Contents/MacOS/Meshchan', 'meshctl/bin/meshctl',
                                  'data/meshchan.sqlite'})
                self.assertEqual(files['data/meshchan.sqlite'].mode, 0o600)
                self.assertEqual(files['meshctl/bin/meshctl'].mode, 0o755)
                for name, value in [('Meshchan.app/Contents/MacOS/Meshchan', b'app'),
                                    ('meshctl/bin/meshctl', b'cli')]:
                    with archive.extractfile(files[name]) as stream:
                        self.assertEqual(stream.read(), value)
            return CompletedProcess([], 0, b'Beta staged\n', b'')

        vm = SimpleNamespace(c={'user': 'testuser'}, remote=receive)
        result = workflow.stage_beta(vm, self.layout, self.guest_cli, self.admitted, self.evidence)
        self.assertEqual(result['app'], self.layout['app'])
        self.assertEqual(result['cli'], str(self.guest_cli/'bin/meshctl'))
        self.assertEqual(result['dataDirectory'], self.layout['data'])
        self.assertEqual(result['sourceClosedSnapshot']['files'][beta.DATABASE]['sha256'], beta.DATABASE_PIN)
        self.assertEqual(digest(self.evidence/workflow.BETA_SOURCE_SNAPSHOT/beta.DATABASE), beta.DATABASE_PIN)
        self.assertEqual(digest(self.fixture/beta.DATABASE), beta.DATABASE_PIN)

    def test_source_product_drift_stops_before_transferring(self):
        (self.source/workflow.CLI/workflow.CLI_BINARY).write_text('other')
        vm = SimpleNamespace(c={'user': 'testuser'}, remote=lambda *a, **k: self.fail('unexpected upload'))
        with self.assertRaisesRegex(ValueError, 'Beta product inventory'):
            workflow.stage_beta(vm, self.layout, self.guest_cli, self.admitted, self.evidence)
        with self.assertRaisesRegex(ValueError, 'exact owned Beta guest destinations'):
            workflow.stage_beta(vm, self.layout, 'meshctl', self.admitted, self.evidence)

    def test_retry_reuses_only_the_authorized_readonly_source_snapshot(self):
        outcome = [CalledProcessError(1, [], b'', b'Guest rejected the attempt'),
                   CompletedProcess([], 0, b'Beta staged\n', b'')]

        def receive(*_args, **kwargs):
            if 'stdin' not in kwargs:
                return CompletedProcess([], 0, b'', b'')
            next_outcome = outcome.pop(0)
            if isinstance(next_outcome, CalledProcessError):
                raise next_outcome
            return next_outcome

        vm = SimpleNamespace(c={'user': 'testuser'}, remote=receive)
        with self.assertRaisesRegex(ValueError, 'Guest Beta transfer exit 1\nGuest rejected the attempt'):
            workflow.stage_beta(vm, self.layout, self.guest_cli, self.admitted, self.evidence)
        captured = self.evidence/workflow.BETA_SOURCE_SNAPSHOT/beta.DATABASE
        inode = captured.stat().st_ino
        with patch.object(beta, 'capture_closed', side_effect=AssertionError('Unexpected recapture')):
            report = workflow.stage_beta(vm, self.layout, self.guest_cli, self.admitted, self.evidence)
        self.assertEqual(report['status'], 'PASS')
        self.assertEqual(captured.stat().st_ino, inode)
        captured.chmod(0o600)
        with self.assertRaisesRegex(ValueError, 'intact read-only Beta source database'):
            workflow.stage_beta(vm, self.layout, self.guest_cli, self.admitted, self.evidence)

    def test_failed_local_capture_does_not_leave_a_canonical_snapshot(self):
        def incomplete(_source, output, **_kwargs):
            output.mkdir(mode=0o700)
            (output/beta.DATABASE).write_bytes(b'partial')
            raise OSError('Injected local copy interruption')

        vm = SimpleNamespace(c={'user': 'testuser'}, remote=lambda *a, **k: self.fail('unexpected upload'))
        with patch.object(beta, 'capture_closed', side_effect=incomplete):
            with self.assertRaisesRegex(OSError, 'Injected local copy interruption'):
                workflow.stage_beta(vm, self.layout, self.guest_cli, self.admitted, self.evidence)
        self.assertEqual(list(self.evidence.iterdir()), [])
        vm.remote = lambda *_args, **_kwargs: CompletedProcess([], 0, b'Beta staged\n', b'')
        report = workflow.stage_beta(vm, self.layout, self.guest_cli, self.admitted, self.evidence)
        self.assertEqual(report['status'], 'PASS')
        self.assertEqual(digest(self.evidence/workflow.BETA_SOURCE_SNAPSHOT/beta.DATABASE), beta.DATABASE_PIN)

    def test_lost_successful_reply_recovers_the_original_complete_stage(self):
        attempt_path = self.evidence/workflow.BETA_STAGE_ATTEMPT/'receipt.json'
        marker_reads = []
        uploads = []

        def receive(script, *, capture_output, timeout, stdin=None):
            self.assertTrue(capture_output)
            if stdin is not None:
                self.assertTrue(attempt_path.is_file())
                uploads.append(script)
                raise TimeoutExpired('ssh', timeout)
            marker_reads.append(script)
            return CompletedProcess([], 0, attempt_path.read_bytes(), b'')

        vm = SimpleNamespace(c={'user': 'testuser'}, remote=receive)
        with self.assertRaises(TimeoutExpired):
            workflow.stage_beta(vm, self.layout, self.guest_cli, self.admitted, self.evidence)
        attempt = json.loads(attempt_path.read_bytes())
        with patch.object(workflow, 'verify_guest_tree') as verify:
            report = workflow.stage_beta(vm, self.layout, self.guest_cli, self.admitted, self.evidence)
        self.assertEqual([call.args[1] for call in verify.call_args_list],
                         [PurePosixPath(self.layout['app']), self.guest_cli, PurePosixPath(self.layout['data'])])
        self.assertEqual(report['transferArchive'], attempt['transferArchive'])
        self.assertEqual(report['stageNonce'], attempt['nonce'])
        self.assertEqual(len(uploads), 1)
        self.assertEqual(len(marker_reads), 2)
        self.assertIn(str(self.guest_cli.parent/workflow.BETA_STAGE_COMMIT), uploads[0])
        self.assertIn(str(self.guest_cli.parent/workflow.BETA_STAGE_COMMIT/'receipt.json'), marker_reads[0])

    def test_retry_refuses_different_guest_receipt_and_altered_destinations(self):
        attempt_path = self.evidence/workflow.BETA_STAGE_ATTEMPT/'receipt.json'
        vm = SimpleNamespace(c={'user': 'testuser'}, remote=lambda *a, **k: CompletedProcess(
            [], 0, b'Beta staged\n', b''))
        workflow.stage_beta(vm, self.layout, self.guest_cli, self.admitted, self.evidence)

        def reply(*_args, **kwargs):
            self.assertNotIn('stdin', kwargs)
            return CompletedProcess([], 0, payload, b'')

        vm.remote = reply
        saved = json.loads(attempt_path.read_bytes())
        payload = workflow.receipt_bytes({**saved, 'nonce': '9' * 32})
        with patch.object(workflow, 'verify_guest_tree') as verify:
            with self.assertRaisesRegex(ValueError, 'marker differs'):
                workflow.stage_beta(vm, self.layout, self.guest_cli, self.admitted, self.evidence)
            verify.assert_not_called()
        payload = attempt_path.read_bytes()
        error = ValueError('Archived product content changed')
        with patch.object(workflow, 'verify_guest_tree', side_effect=error):
            with self.assertRaisesRegex(ValueError, 'product content changed'):
                workflow.stage_beta(vm, self.layout, self.guest_cli, self.admitted, self.evidence)

    def test_reference_cli_isolated_from_archive_and_default_data(self):
        snapshot = self.evidence/workflow.BETA_SOURCE_SNAPSHOT
        beta.capture_closed(self.fixture, snapshot)

        def invoke_capture(invoke):
            result = invoke('draft', 'list', '--json')
            return {'drafts': json.loads(result.stdout)}

        def invoke_cli(argv, *, cwd, env, capture_output, text, timeout):
            cli, flag, work, *args = argv
            self.assertEqual((cli, flag), (self.source/workflow.CLI/workflow.CLI_BINARY, '--data-dir'))
            self.assertTrue(work.is_relative_to(cwd))
            self.assertFalse(work.is_relative_to(self.evidence))
            self.assertEqual(args, ['draft', 'list', '--json'])
            database = work/beta.DATABASE
            self.assertEqual(digest(database), beta.DATABASE_PIN)
            self.assertEqual(database.stat().st_mode & 0o777, 0o600)
            database.write_bytes(b'owned changes')
            return CompletedProcess(argv, 0, '[]', '')

        with (patch.object(beta, 'capture_cli', side_effect=invoke_capture),
              patch.object(workflow.subprocess, 'run', side_effect=invoke_cli)):
            self.assertEqual(workflow.project_beta_reference(self.admitted, snapshot), {'drafts': []})
        self.assertEqual(digest(snapshot/beta.DATABASE), beta.DATABASE_PIN)

    def test_sidecars_added_after_historical_admission_are_rejected(self):
        name = beta.DATABASE + '-journal'
        (self.fixture/name).touch()
        vm = SimpleNamespace(c={'user': 'testuser'}, remote=lambda *a, **k: self.fail('unexpected upload'))
        with self.assertRaisesRegex(ValueError, 'Historical Beta SQLite member set'):
            workflow.stage_beta(vm, self.layout, self.guest_cli, self.admitted, self.evidence)
        snapshot = self.evidence/workflow.BETA_SOURCE_SNAPSHOT
        self.assertFalse(snapshot.exists())
        beta.capture_closed(self.fixture, snapshot)
        with self.assertRaisesRegex(ValueError, 'Historical Beta SQLite member set'):
            workflow.project_beta_reference(self.admitted, snapshot)

    @unittest.skipUnless(sys.platform == 'darwin', 'native macOS extraction guard')
    def test_guest_script_refuses_even_dangling_destinations_before_copying(self):
        home = self.root/pwd.getpwuid(os.getuid()).pw_name
        support = home/'Library/Application Support'
        support.mkdir(parents=True)
        targets = {workflow.APP: home/'Applications/Meshchan.app',
                   workflow.CLI: support/'meshchan-engineering/beta-reference/test/meshctl',
                   workflow.ARCHIVE_DATA: support/'meshchan'}
        targets[workflow.ARCHIVE_DATA].symlink_to(support/'unknown')
        commands = workflow.guest_stage_script(home, targets, {}, {}, {'nonce': 'test'})
        result = run(['/bin/sh', '-c', commands], input=b'', capture_output=True,
                     env=dict(os.environ, HOME=str(home)))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'Beta stage destination is occupied:', result.stderr)
        self.assertTrue(targets[workflow.ARCHIVE_DATA].is_symlink())
        self.assertFalse(targets[workflow.APP].parent.exists())
        self.assertFalse(targets[workflow.CLI].parent.exists())

    @unittest.skipUnless(sys.platform == 'darwin', 'native macOS extraction guard')
    def test_guard_and_unsigned_archive_fail_before_public_directory_creation(self):
        home = self.root/pwd.getpwuid(os.getuid()).pw_name
        support = home/'Library/Application Support'
        support.mkdir(parents=True)
        targets = {workflow.APP: home/'Applications/Meshchan.app',
                   workflow.CLI: support/'meshchan-engineering/beta-reference/test/meshctl',
                   workflow.ARCHIVE_DATA: support/'meshchan'}
        unknown = self.root/'unknown'
        unknown.mkdir()
        (unknown/'retained').write_text('unchanged')
        alias = support/'meshchan-engineering'
        alias.symlink_to(unknown)
        commands = workflow.guest_stage_script(home, targets, {}, {}, {'nonce': 'test'})
        env = dict(os.environ, HOME=str(home))
        denied = run(['/bin/sh', '-c', commands], env=env, input=b'', capture_output=True)
        self.assertNotEqual(denied.returncode, 0)
        self.assertFalse(targets[workflow.APP].parent.exists())
        self.assertEqual((unknown/'retained').read_text(), 'unchanged')
        alias.unlink()

        archive = self.root/'unsigned.tar'
        with tarfile.open(archive, mode='w') as output:
            for name in targets:
                folder = self.root/name
                folder.mkdir()
                (folder/'unsigned').write_text('fixture')
                output.add(folder, arcname=name)
        with archive.open('rb') as content:
            denied = run(['/bin/sh', '-c', commands], env=env, stdin=content, capture_output=True)
        self.assertNotEqual(denied.returncode, 0)
        self.assertIn(b'/.meshchan-beta-stage.', denied.stderr)
        self.assertIn(b'/Meshchan.app:', denied.stderr)
        self.assertTrue(all(not target.exists() for target in targets.values()))
        self.assertFalse(targets[workflow.APP].parent.exists())
        self.assertFalse(targets[workflow.CLI].parent.exists())
        self.assertEqual(list(home.glob('.meshchan-beta-stage.*')), [])

    @unittest.skipUnless(sys.platform == 'darwin', 'native macOS exclusive publication')
    def test_late_destination_collision_rolls_back_owned_moves(self):
        scratch = self.root/'scratch'
        scratch.mkdir()
        for source_name in ('first', 'second', 'third'):
            (scratch/source_name).mkdir()
            (scratch/source_name/'owned').write_text(source_name)
        first = self.root/'first-destination'
        occupied = self.root/'occupied'
        unneeded = self.root/'not reached'
        occupied.mkdir()
        (occupied/'existing').write_text('untouched')
        plan = json.dumps([('first', str(first)), ('second', str(occupied)), ('third', str(unneeded))])
        result = run(['/usr/bin/osascript', '-l', 'JavaScript', '-e', workflow.PUBLISH_BETA, scratch, plan],
                     capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Could not exclusively publish', result.stderr)
        self.assertFalse(first.exists())
        self.assertFalse(unneeded.exists())
        self.assertEqual(list(occupied.iterdir()), [occupied/'existing'])
        self.assertEqual((occupied/'existing').read_text(), 'untouched')
        self.assertEqual((scratch/'first/owned').read_text(), 'first')
        self.assertEqual((scratch/'second/owned').read_text(), 'second')


class BusinessComparisonTest(unittest.TestCase):
    def setUp(self):
        self.title, self.body = '离线 🌱', 'First line\n第二行 🙂\n'
        self.draft = {'id': 'a' * 32, 'title': self.title, 'body': self.body, 'revision': 1,
                      'created_at_us': 120, 'updated_at_us': 120}
        self.old_db = deepcopy(workflow.EMPTY_DATABASE)
        self.old_public = deepcopy(workflow.EMPTY_PUBLIC)
        self.after_db = deepcopy(self.old_db)
        self.after_db['drafts'].append(self.draft.copy())
        self.after_db['settings'][0]['diagnostic_history_limit'] = 1002
        self.after_public = deepcopy(self.old_public)
        date = '1970-01-01T00:00:00.000120Z'
        self.after_public['drafts'].append({
            'id': self.draft['id'], 'title': self.title, 'body': self.body, 'revision': 1,
            'createdAt': date, 'updatedAt': date, 'bodyUtf8ByteLength': len(self.body.encode()),
        })
        self.after_public['settings']['diagnosticHistoryLimit'] = 1002

    def compare(self, *, baseline=None, reopened=None, after=None):
        return workflow.compare_business(
            self.old_public, self.after_public if after is None else after,
            self.after_db, self.after_db if reopened is None else reopened, title=self.title,
            body=self.body, history_limit=1002, beta_baseline=baseline)

    def test_clean_checks_public_and_both_closed_snapshots(self):
        self.assertEqual(self.compare()['newDraft'], self.draft)
        changed = deepcopy(self.after_db)
        changed['drafts'][0]['body'] = self.body.rstrip()
        with self.assertRaisesRegex(ValueError, 'Closed database drafts'):
            self.compare(reopened=changed)
        changed = deepcopy(self.after_public)
        changed['drafts'][0]['bodyUtf8ByteLength'] += 1
        with self.assertRaisesRegex(ValueError, 'CLI projection drafts'):
            self.compare(after=changed)
        self.old_public['drafts'].append({'id': 'b' * 32})
        with self.assertRaisesRegex(ValueError, 'Public projection before'):
            self.compare()

    def test_beta_requires_original_rows_and_exact_declared_new_content(self):
        old = dict(self.draft, id='1' * 32, title='Old draft')
        old_public = dict(self.after_public['drafts'][0], id=old['id'], title=old['title'])
        self.old_db['drafts'].append(old)
        self.old_public['drafts'].append(old_public)
        self.after_db['drafts'].insert(0, old.copy())
        self.after_public['drafts'].insert(0, old_public.copy())
        baseline = {'public': self.old_public, 'snapshot': {'database': self.old_db}}
        self.assertEqual(self.compare(baseline=baseline)['draftsBefore'], 1)
        self.after_db['drafts'][0]['title'] = 'Changed old draft'
        with self.assertRaisesRegex(ValueError, 'Closed database drafts'):
            self.compare(baseline=baseline)


if __name__ == '__main__':
    unittest.main()
