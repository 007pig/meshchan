"""Delivery regressions for child environments, cwd changes and SDK launchers."""
import contextlib
import io
import json
import os
from pathlib import Path
import sqlite3
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import candidate_common as c
import check_schema_compatibility as compatibility
import package_1c_candidate as pack
import smoke_cli


class DeliveryEnvironmentTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='meshchan-delivery-environment-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()

    def write(self, name, content='fixture'):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def test_checks_pass_prepared_environment_to_real_child(self):
        variable = 'MESHCHAN_TEST_CHILD_ENVIRONMENT'
        prepared = {**os.environ, variable: 'prepared'}
        with patch.dict(os.environ, {variable: 'inherited'}):
            checks = smoke_cli.Checks(env=prepared)
            with contextlib.redirect_stdout(io.StringIO()):
                result = checks.check('explicit child environment', [sys.executable, '-c',
                    f'import os; print(os.environ[{variable!r}])'], self.root, out='prepared')
        self.assertEqual(result, 'prepared\n')

    def test_compatibility_supplies_apple_first_environment(self):
        class ReachedChecks(Exception):
            pass
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode='w'):
            pass
        argv = ['compatibility', '--build-directory', str(self.root), '--dart', sys.executable]
        with patch.object(sys, 'argv', argv), \
                patch.dict(os.environ, {'PATH': '/synthetic/homebrew-compiler:/usr/bin'}), \
                patch.object(compatibility.subprocess, 'check_output', return_value=archive.getvalue()), \
                patch.object(compatibility.shutil, 'copy2'), \
                patch.object(compatibility, 'Checks', side_effect=ReachedChecks) as checks:
            with self.assertRaises(ReachedChecks):
                compatibility.main()
        prepared = checks.call_args.kwargs['env']
        self.assertEqual(prepared['PATH'].split(':')[:3], ['/usr/bin', '/bin', '/opt/homebrew/bin'])
        self.assertIn('/synthetic/homebrew-compiler', prepared['PATH'])

    def schema_fixture(self, directory):
        directory.mkdir()
        expected = {}
        with contextlib.closing(sqlite3.connect(directory / 'meshchan.sqlite')) as database, database:
            database.execute('PRAGMA user_version=1')
            for table in ('stored_drafts', 'stored_profiles', 'stored_settings', 'stored_runs'):
                database.execute('CREATE TABLE ' + table + ' (id INTEGER, value TEXT)')
                value = directory.name + ':' + table
                database.execute('INSERT INTO ' + table + ' VALUES (?, ?)', (1, value))
                expected[table] = [(1, value)]
        return expected

    def test_schema_rows_escape_special_paths_and_open_read_only(self):
        connect = sqlite3.connect
        connections = []
        def read_only_connection(*args, **kwargs):
            database = connect(*args, **kwargs)
            connections.append(database)
            with self.assertRaises(sqlite3.OperationalError):
                database.execute('CREATE TABLE unexpected_write (value TEXT)')
            return database
        try:
            for name in ('build#1', 'build%231', 'build?mode=rwc', 'build space 中文', 'build%25#?'):
                with self.subTest(name=name):
                    directory = self.root / name
                    expected = self.schema_fixture(directory)
                    before = {p.relative_to(self.root): p.read_bytes()
                              for p in self.root.rglob('*') if p.is_file()}
                    with patch.object(compatibility.sqlite3, 'connect', side_effect=read_only_connection):
                        self.assertEqual(compatibility.rows(directory), expected)
                    self.assertEqual({p.relative_to(self.root): p.read_bytes()
                                      for p in self.root.rglob('*') if p.is_file()}, before)
        finally:
            for database in connections:
                database.close()

    def test_schema_rows_missing_file_cannot_create_another_database(self):
        for name in ('missing#1', 'missing%231', 'missing?mode=rwc'):
            with self.subTest(name=name):
                directory = self.root / name
                directory.mkdir()
                before = set(self.root.rglob('*'))
                with self.assertRaises(sqlite3.OperationalError):
                    compatibility.rows(directory)
                self.assertEqual(set(self.root.rglob('*')), before)

    def test_compatibility_resolves_relative_executable_for_both_child_cwds(self):
        class ReachedProbes(Exception):
            pass
        dart = self.root / 'tools/dart'
        dart.parent.mkdir()
        dart.symlink_to(sys.executable)
        relative = os.path.relpath(dart, Path.cwd())
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode='w') as tar:
            folder = tarfile.TarInfo('apps/meshctl')
            folder.type = tarfile.DIRTYPE
            tar.addfile(folder)
        calls = []
        class ProbeChecks(smoke_cli.Checks):
            def check(inner, name, command, cwd, **kwargs):
                code, stdout, stderr = smoke_cli.run(
                    [command[0], '-c', 'print("resolved executable")'], cwd, env=inner.env)
                self.assertEqual((code, stdout, stderr), (0, 'resolved executable\n', ''))
                self.assertTrue(Path(command[0]).is_absolute())
                calls.append((Path(command[0]), Path(cwd)))
                if len(calls) == 2:
                    raise ReachedProbes
                return ''
        argv = ['compatibility', '--build-directory', str(self.root), '--dart', relative]
        with patch.object(sys, 'argv', argv), \
                patch.object(compatibility.subprocess, 'check_output', return_value=archive.getvalue()), \
                patch.object(compatibility.shutil, 'copy2'), patch.object(compatibility, 'Checks', ProbeChecks):
            with self.assertRaises(ReachedProbes):
                compatibility.main()
        self.assertEqual([path for path, _ in calls], [Path(sys.executable).resolve()] * 2)
        self.assertNotEqual(calls[0][1], calls[1][1])

    def test_compatibility_rejects_invalid_executable_before_build_work(self):
        empty = self.write('empty-dart', '')
        empty.chmod(0o755)
        not_executable = self.write('not-executable-dart')
        not_executable.chmod(0o644)
        for dart in (self.root / 'missing-dart', empty, not_executable, self.root):
            with self.subTest(dart=dart):
                build = self.root / 'unused build'
                argv = ['compatibility', '--build-directory', str(build), '--dart', str(dart)]
                with patch.object(sys, 'argv', argv), \
                        patch.object(compatibility.subprocess, 'check_output') as archive, \
                        contextlib.redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit) as stopped:
                        compatibility.main()
                self.assertEqual(stopped.exception.code, 2)
                archive.assert_not_called()
                self.assertFalse(build.exists())

    def test_relative_smoke_evidence_is_absolute_for_every_child_cwd(self):
        dart = self.write('dart')
        dart.chmod(0o755)
        bundle = self.root / 'bundle'
        bundle.mkdir()
        evidence = self.root / 'relative evidence'
        relative = os.path.relpath(evidence, Path.cwd())
        recorded_paths = []
        history_paths = []
        class CaptureChecks(smoke_cli.Checks):
            def check(inner, name, command, cwd, **kwargs):
                if '--recording-directory' in command:
                    recorded_paths.append((Path(command[command.index('--recording-directory') + 1]), Path(cwd)))
                return ''
        def capture_history(checks, label, prefix, cwd, data, *args):
            history_paths.append((Path(data), Path(cwd)))
        argv = ['smoke', '--dart', str(dart), '--cli-bundle', str(bundle),
            '--observation-bundle', str(bundle), '--datagram-acceptance-bundle', str(bundle),
            '--evidence-directory', relative]
        with patch.object(sys, 'argv', argv), patch.object(smoke_cli, 'Checks', CaptureChecks), \
                patch.object(smoke_cli, 'bundle_executable', return_value=dart), \
                patch.object(smoke_cli, 'business_checks'), \
                patch.object(smoke_cli, 'nonempty_history_checks', side_effect=capture_history), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(smoke_cli.main(), 0)
        self.assertEqual(len(recorded_paths), 2)
        self.assertEqual(len(history_paths), 3)
        for data, cwd in recorded_paths + history_paths:
            self.assertTrue(data.is_absolute(), f'{data} would change under child cwd {cwd}')
            self.assertEqual(data.parent, evidence.resolve())
        self.assertTrue((evidence / 'process-checks.json').is_file())

    def sdk_fixture(self):
        self.write('flutter/LICENSE', 'Flutter framework license\n')
        launcher = self.write('flutter/bin/dart', '#!/bin/sh\n# synthetic Flutter launcher; never executed\n')
        self.write('flutter/bin/internal/shared.sh')
        sdk = self.root / 'flutter/bin/cache/dart-sdk'
        self.write('flutter/bin/cache/dart-sdk/bin/dart', 'synthetic SDK executable')
        self.write('flutter/bin/cache/dart-sdk/version', '3.13.7\n')
        self.write('flutter/bin/cache/dart-sdk/lib/core/core.dart')
        self.write('flutter/bin/cache/dart-sdk/include/dart_api.h')
        self.write('flutter/bin/cache/dart-sdk/LICENSE', 'Dart SDK original license\n')
        self.write('flutter/bin/cache/LICENSE.dart_sdk_archive.md', 'Original SDK archive notice pointer\n')
        alias = self.root / 'bin/dart'
        alias.parent.mkdir()
        alias.symlink_to(launcher)
        return sdk, launcher, alias

    def material_fixture(self):
        packages = [
            {'name': 'meshctl', 'source': 'root', 'directDependencies': ['libserialport_plus', 'sqlite3']},
            {'name': 'libserialport_plus', 'source': 'hosted', 'version': '1.0.5', 'directDependencies': []},
            {'name': 'sqlite3', 'source': 'hosted', 'version': '3.9.1', 'directDependencies': []},
        ]
        config = []
        for package in packages:
            name = package['name']
            folder = self.root / 'packages' / name
            folder.mkdir(parents=True)
            config.append({'name': name, 'rootUri': folder.as_uri()})
            if name != 'meshctl':
                (folder / 'LICENSE').write_text('Original ' + name + ' notice')
        for name in ['src/libserialport/COPYING', 'src/libserialport/README', 'hook/build.dart', 'pubspec.yaml']:
            self.write('packages/libserialport_plus/' + name)
        for name in ['hook/build.dart', 'lib/src/hook/assets.dart', 'lib/src/hook/asset_hashes.dart',
                     'lib/src/hook/compile/description.dart', 'lib/src/hook/compile/used_symbols.dart']:
            self.write('packages/sqlite3/' + name)
        self.write('.dart_tool/package_config.json', json.dumps({'packages': config}))
        return {'packages': packages}

    def test_materials_use_actual_sdk_license_for_binary_launcher_and_symlink(self):
        sdk, launcher, alias = self.sdk_fixture()
        graph = self.material_fixture()
        for index, dart in enumerate((sdk / 'bin/dart', launcher, alias)):
            with self.subTest(dart=dart), patch.object(pack, 'ROOT', self.root):
                candidate = self.root / 'delivery' / str(index)
                result = pack.collect_materials(candidate, graph, dart)
                self.assertEqual((candidate / 'licenses/dart-sdk/LICENSE').read_bytes(), (sdk / 'LICENSE').read_bytes())
                self.assertNotEqual((candidate / 'licenses/dart-sdk/LICENSE').read_bytes(),
                                    (self.root / 'flutter/LICENSE').read_bytes())
                original = next(p for p in result['materials'] if p['file'] == 'licenses/dart-sdk/LICENSE')
                self.assertEqual(Path(original['originalPath']), sdk / 'LICENSE')
                self.assertEqual((candidate / 'licenses/dart-sdk/LICENSE.dart_sdk_archive.md').read_bytes(),
                                 (sdk.parent / 'LICENSE.dart_sdk_archive.md').read_bytes())

    def test_license_file_alone_does_not_identify_a_dart_sdk(self):
        sdk, launcher, alias = self.sdk_fixture()
        (sdk / 'lib/core/core.dart').unlink()
        for dart in (sdk / 'bin/dart', launcher, alias):
            with self.subTest(dart=dart), self.assertRaisesRegex(ValueError, 'Dart SDK'):
                c.dart_sdk_directory(dart)


if __name__ == '__main__':
    unittest.main()
