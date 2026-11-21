"""Targeted acceptance failures and offline evidence resolution for Phase 1E.8."""
from contextlib import closing
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

import package_dmg as dmg
import release_retention_inputs as retention
import release_signed_runtime as runtime
from release_materials import encoded, sha


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='Retained evidence ')
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.original = Path('/previous owned workspace')
        self.lookups = []

    def locate(self, original):
        self.lookups.append(original)
        return self.root/original.relative_to(self.original)

    def write(self, original, raw):
        target = self.locate(original)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        return sha(raw)

    def test_pinned_bytes_are_checked_before_parsing(self):
        reader = retention.RetainedRead(self.locate, live=False)
        receipt = self.original/'acceptance.json'
        correct = self.write(receipt, b'{"status":"PASS"}')
        self.write(receipt, b'{"status":"PASS","status":"FAIL"}')
        ref = {'path': 'acceptance.json', 'sha256': correct}
        with self.assertRaisesRegex(ValueError, 'SHA-256'):
            reader.report(self.original, ref, receipt)
        ref['sha256'] = sha(b'{"status":"PASS","status":"FAIL"}')
        with self.assertRaisesRegex(ValueError, '[Dd]uplicate'):
            reader.report(self.original, ref, receipt)

    def test_create_or_sign_is_not_independent_acceptance(self):
        info = {'identity': {'appBuild': '8', 'productVersion': '0.1.0-rc.1', 'target': 'macos-arm64'}}
        _, filename, _ = dmg.volume_names(info)
        asset = self.original/'create'/filename
        acceptance = self.original/'check/dmg-acceptance.json'
        for command, status in (('create', 'CREATED'), ('sign', 'SIGNED'), ('check', 'RUNNING')):
            with self.subTest(command=command, status=status):
                digest = self.write(acceptance, encoded({'formatVersion': 1, 'command': command, 'status': status}))
                reader = retention.RetainedRead(self.locate, live=False)
                with self.assertRaisesRegex(ValueError, 'independent DMG acceptance'):
                    retention.accepted_image(reader, {'dmg': (asset, '0'*64), 'dmg_acceptance': (acceptance, digest)},
                                             info, {})
                self.assertNotIn(asset, self.lookups)

    def test_evidence_references_reject_aliases_and_scope_escape(self):
        reader = retention.RetainedRead(self.locate, live=False)
        target = self.original/'owned/evidence.json'
        for alias in ('../evidence.json', './owned/evidence.json', 'owned//evidence.json',
                      str(self.original/'other/evidence.json')):
            with self.subTest(alias=alias):
                with self.assertRaises(ValueError):
                    reader.reference(self.original, {'path': alias, 'sha256': '0'*64}, target,
                                     scope=self.original/'owned')
        self.assertEqual(self.lookups, [])

    def test_locator_cannot_follow_aliased_evidence_ancestor(self):
        original = self.original/'alias/local.json'
        (self.root/'alias').symlink_to('/unavailable original checkout')
        reader = retention.RetainedRead(self.locate, live=False)
        with self.assertRaisesRegex(ValueError, 'Aliased evidence ancestor'):
            reader.bytes(original, '0'*64)

    def test_historical_tool_identity_checks_presence_bytes_and_mode(self):
        name = 'tool/old_snapshot.py'
        origin = self.original/'source'
        path = origin/name
        pin = self.write(path, b'historical data')
        target = self.locate(path)
        target.chmod(0o600)
        tool = {
            'gitCommit': 'a'*40, 'workingTree': [],
            'inputs': {name: {'type': 'file', 'size': len(b'historical data'), 'mode': 0o600, 'sha256': pin}},
        }
        reader = retention.RetainedRead(self.locate, live=False)
        retention.verify_tool_snapshot(reader, origin, tool, [name])
        target.chmod(0o644)
        with self.assertRaisesRegex(ValueError, 'mode differs'):
            retention.verify_tool_snapshot(reader, origin, tool, [name])
        target.chmod(0o600)
        target.write_bytes(b'changed snapshot')
        with self.assertRaisesRegex(ValueError, 'size differs|sha256 differs'):
            retention.verify_tool_snapshot(reader, origin, tool, [name])
        target.unlink()
        with self.assertRaises(FileNotFoundError):
            retention.verify_tool_snapshot(reader, origin, tool, [name])

    def fixture_cli(self):
        bundle = self.original/'relocated products/meshctl'
        workspace = self.original/'cli workspace'
        executable, library = bundle/'bin/meshctl', bundle/'lib/libsqlite3.dylib'
        observer = workspace/'release-image-probe'
        data = workspace/'owned signed CLI data'
        version = 'meshctl 0.1.0-rc.1'
        ex_pin = self.write(executable, b'signed executable')
        lib_pin = self.write(library, b'signed library')
        obs_pin = self.write(observer, b'observer')
        row = ('a'*32, runtime.CLI_TITLE, runtime.CLI_BODY, 1)
        with closing(sqlite3.connect(':memory:')) as database:
            database.execute('create table stored_drafts (id, title, body, revision)')
            database.execute('insert into stored_drafts values (?, ?, ?, ?)', row)
            database.commit()
            database_pin = self.write(data/'meshchan.sqlite', database.serialize())
        cli = {'status': 'PASS', 'bundle': str(bundle), 'database': str(data/'meshchan.sqlite'),
               'databaseSha256': database_pin, 'observerSha256': obs_pin, 'versionOutput': version,
               'storedDrafts': [row], 'processes': []}
        ledger = {'steps': [{'name': 'signed-cli-version', 'cwd': str(workspace),
                             'argv': [str(executable), '--version']}]}
        logs = {'signed-cli-version': {'log': version.encode()}}
        draft = {'id': row[0], 'title': row[1], 'body': row[2], 'revision': 1,
                 'bodyUtf8ByteLength': len(row[2].encode())}
        for offset, action in enumerate(('create', 'show')):
            image = workspace/(action+'-image.json')
            pid = 101 + offset*10
            observer_pid = pid+1
            observation = encoded({'pid': pid, 'observerPid': observer_pid, 'exitCode': 0,
                                   'mapping': {'address': '0xdeadbeef', 'device': 1, 'inode': 2}})
            self.write(image, observation)
            options = ['--title', row[1], '--body', row[2]] if action == 'create' else ['--id', row[0]]
            command = list(map(str, [executable, '--data-dir', data, 'draft', action, *options, '--json']))
            result = {'exitCode': 0, 'operationSucceeded': True, 'schemaVersion': 1,
                      'command': 'draft', 'action': action, 'hostCleanup': 'succeeded', 'draft': draft,
                      'storageClose': {'state': 'closed', 'error': None}}
            mapping = runtime.image_report(observation, executable, library, ex_pin, lib_pin, 0,
                                           observer_pid=observer_pid)
            cli['processes'].append({'report': result, 'name': action, 'pid': pid, 'cwd': str(workspace),
                                     'argv': command, 'pidAbsentAfterNormalExit': True, 'sqliteMapping': mapping})
            ledger['steps'].append({
                'name': 'signed-cli-'+action, 'cwd': str(workspace),
                'argv': [str(observer), str(image), str(library), *command],
                'processTree': {'exited': True, 'childReaped': True,
                                'members': [{'pid': observer_pid, 'pgid': observer_pid,
                                             'ppid': 2, 'exitObserved': True}]},
            })
            logs['signed-cli-'+action] = {'log': json.dumps(result).encode()}
        self.lookups.clear()
        return cli, bundle, workspace, {'productVersion': '0.1.0-rc.1'}, ledger, logs

    def test_recovered_cli_validates_historical_vnode_without_requiring_current_inode(self):
        fixture = self.fixture_cli()
        retention.verify_cli(retention.RetainedRead(self.locate, live=False), *fixture)
        with self.assertRaisesRegex(ValueError, 'Original SQLite vnode'):
            retention.verify_cli(retention.RetainedRead(self.locate, live=True), *fixture)
        self.assertTrue(all(path.is_relative_to(self.original) for path in self.lookups))

    def test_recovered_cli_requires_database_and_both_observer_reports(self):
        fixture = self.fixture_cli()
        for original in (self.original/'cli workspace/show-image.json',
                         self.original/'cli workspace/owned signed CLI data/meshchan.sqlite'):
            with self.subTest(original=original):
                target = self.locate(original)
                raw = target.read_bytes()
                target.unlink()
                with self.assertRaises(FileNotFoundError):
                    retention.verify_cli(retention.RetainedRead(self.locate, live=False), *fixture)
                target.write_bytes(raw)


if __name__ == '__main__':
    unittest.main()
