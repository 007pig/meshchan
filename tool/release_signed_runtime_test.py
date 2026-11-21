"""Focused regression checks for relocated signed runtime evidence."""
from contextlib import closing
import copy
import json
import os
from pathlib import Path
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import build_release as build
import package_release_vm as guest
import release_signed_runtime as runtime
import release_signing as signing


def local_manifest(inventory=None):
    item = signing.CodeItem('Meshchan.app', 'Meshchan.app/'+runtime.APP_EXECUTABLE, 'app',
                            'org.meshchan.meshchan', True, signing_profile=signing.LOCAL_PROFILE)
    signature = {**item.record(), 'slices': {
        'arm64': {'identifier': item.identifier, 'adhoc': True, 'team': None, 'timestamp': None,
                  'authorityChain': [], 'signatureSlots': 1, 'entitlements': item.entitlements,
                  'runtime': True, 'cdhash': 'a'*40}}}
    return {
        'formatVersion': 2, 'signingProfile': signing.LOCAL_PROFILE,
        'identity': {'target': 'macos-arm64', 'productVersion': '0.1.0-rc.1', 'appBuild': '8',
                     'appVersion': '0.1.0-rc.1+8', 'apple': {
                         'CFBundleIdentifier': item.identifier, 'CFBundleVersion': '8',
                         'CFBundleShortVersionString': '0.1.0', 'CFBundleName': 'Meshchan',
                         'MeshchanProductVersion': '0.1.0-rc.1'}},
        'payloadInventory': {} if inventory is None else inventory,
        'signature': {'identity': signing.local_identity(), 'items': [signature]},
    }


class SignedRuntimeTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix='signed-runtime-test-')
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.info = {
            'formatVersion': 1,
            'identity': {'target': 'macos-arm64', 'productVersion': '0.1.0-rc.1',
                         'appBuild': '8', 'appVersion': '0.1.0-rc.1+8',
                         'apple': {'CFBundleIdentifier': 'org.meshchan.meshchan',
                                   'CFBundleVersion': '8', 'MeshchanProductVersion': '0.1.0-rc.1'}},
            'payloadInventory': {},
            'signature': {'identity': {'sha1': 'a'*40, 'team': 'ABCD123456',
                                       'authority': 'Developer ID Application: Release Engineering'},
                          'items': []},
        }

    def read_signed(self, info, digest=None):
        path = self.root/'signed-product-info.json'
        raw = build.encoded(info)
        path.write_bytes(raw)
        return runtime.signed_info(path, digest or build.sha(raw))

    def test_signed_info_requires_exact_bytes_and_developer_identity(self):
        self.assertEqual(self.read_signed(self.info), self.info)
        with self.assertRaisesRegex(ValueError, 'expected SHA-256'):
            self.read_signed(self.info, 'a'*64)
        with self.assertRaisesRegex(ValueError, 'inventory is missing'):
            self.read_signed({key: value for key, value in self.info.items() if key != 'signature'})
        with self.assertRaisesRegex(ValueError, 'formatVersion'):
            self.read_signed({**self.info, 'formatVersion': True})
        public = self.info['signature']['identity']
        public['team'] = 'ABCD";BAD'
        with self.assertRaisesRegex(ValueError, 'Developer ID'):
            self.read_signed(self.info)

    def test_guest_requirement_binds_explicit_local_code_hash(self):
        info = local_manifest()
        self.assertEqual(self.read_signed(info), info)
        self.assertEqual(runtime.app_requirements(info), [
            ('arm64', 'identifier "org.meshchan.meshchan" and cdhash H"'+'a'*40+'"')])
        for bad in (
            {key: value for key, value in info.items() if key != 'signingProfile'},
            {**info, 'formatVersion': 1},
            {**info, 'signingProfile': signing.DEVELOPER_PROFILE},
            {**info, 'signature': self.info['signature']},
            {**self.info, 'signingProfile': signing.LOCAL_PROFILE},
        ):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                self.read_signed(bad)
        for key, value in (('cdhash', 'bad syntax'), ('signatureSlots', True), ('adhoc', 1),
                           ('team', 'ABCD123456'), ('timestamp', 'now')):
            with self.subTest(key=key), self.assertRaises(ValueError):
                modified = copy.deepcopy(info)
                modified['signature']['items'][0]['slices']['arm64'][key] = value
                self.read_signed(modified)
        info['identity']['apple']['CFBundleShortVersionString'] = '0.1.0.1'
        with self.assertRaisesRegex(ValueError, 'CFBundleShortVersionString'):
            self.read_signed(info)

    def test_local_app_checks_actual_architectures_and_code_identity(self):
        app = self.root/'Renamed Meshchan.app'
        info = local_manifest()
        expected = info['signature']['items'][0]['slices']['arm64']
        with (patch.object(runtime, 'check_app') as identify,
              patch.object(runtime, 'macho_layout', return_value={'slices': {'arm64': {}}}) as layout,
              patch.object(runtime, 'display_signature', return_value=expected) as display):
            runtime.verify_local_app(app, info)
            identify.assert_called_once_with(app, '0.1.0-rc.1', 8)
            layout.assert_called_once_with(app/runtime.APP_EXECUTABLE)
            self.assertEqual(display.call_args.args[1].path, app.name)
            display.return_value = {**expected, 'adhoc': False}
            with self.assertRaisesRegex(ValueError, 'ad hoc signature'):
                runtime.verify_local_app(app, info)
            display.return_value = {**expected, 'cdhash': 'b'*40}
            with self.assertRaisesRegex(ValueError, 'CodeDirectory hash'):
                runtime.verify_local_app(app, info)
            display.reset_mock()
            layout.return_value['slices']['x86_64'] = {}
            with self.assertRaisesRegex(ValueError, 'signature architectures'):
                runtime.verify_local_app(app, info)
            display.assert_not_called()

    def test_observation_requires_owned_pid_real_exit_and_executable_mapping(self):
        mapping = {'inode': 99, 'device': 20, 'address': '0x10000000'}
        observed = {'observerPid': 601, 'pid': 602, 'exitCode': 0, 'mapping': mapping}

        def validate(receipt):
            return runtime.image_report(build.encoded(receipt), '/copy/bin/meshctl',
                                        '/copy/lib/libsqlite3.dylib', 'a'*64, 'b'*64, 0, observer_pid=601)

        self.assertEqual(validate(observed)['pid'], 602)
        self.assertEqual(validate(observed)['observerPid'], 601)
        self.assertEqual(validate(observed)['librarySha256'], 'b'*64)
        for fields, label in (({'pid': True}, 'owned product PID'),
                              ({'pid': 601}, 'distinct owned image observer PID'),
                              ({'observerPid': 604}, 'observerPid'),
                              ({'observerPid': True}, 'observerPid'),
                              ({'exitCode': False}, 'exitCode'),
                              ({'mapping': None}, 'No executable SQLite mapping'),
                              ({'differentSession': 'synthetic'}, 'Malformed live SQLite'),
                              ({'mapping': {**mapping, 'device': True}}, 'Malformed live SQLite')):
            with self.subTest(fields=fields), self.assertRaisesRegex(ValueError, label):
                validate({**observed, **fields})

    def test_app_shutdown_requires_observed_released_owner_and_typed_counts(self):
        counts = {'receivePorts': 0, 'pendingRequests': 0}
        base = {**counts, 'resourcesReleased': True, 'workerExited': True, 'error': None}
        row = {**base, 'mode': 'read', 'phases': ['opening', 'ready', 'closing', 'closed'],
               'draft': {'id': 'owned-fixture', 'revision': 1, 'bodyUtf8Bytes': len(runtime.APP_BODY.encode())}}
        shutdown = {**base, 'workerWasSpawned': True, 'owner': 'released', 'quitPhase': 'closed'}
        runtime.validate_app_shutdown(row, shutdown, 'read')
        for field, value in (('resourcesReleased', 1), ('receivePorts', False),
                             ('workerWasSpawned', False), ('owner', 'held')):
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, field):
                runtime.validate_app_shutdown(row, {**shutdown, field: value}, 'read')
        del shutdown['error']
        with self.assertRaisesRegex(ValueError, 'error field'):
            runtime.validate_app_shutdown(row, shutdown, 'read')

    def test_database_verifies_the_bound_bytes_and_exact_column_types(self):
        with closing(sqlite3.connect(':memory:')) as conn:
            conn.execute('create table stored_drafts (id, title, body, revision)')
            conn.execute("insert into stored_drafts values ('one', 'title', 'body', 1)")
            data = conn.serialize()
            conn.execute('update stored_drafts set revision = 1.0')
            with self.assertRaisesRegex(ValueError, 'revision'):
                runtime.validate_database(conn.serialize(), {'id': 'one'}, 'title', 'body')
        self.assertEqual(runtime.validate_database(data, {'id': 'one'}, 'title', 'body'),
                         [('one', 'title', 'body', 1)])
        with self.assertRaisesRegex(ValueError, 'Closed SQLite evidence could not be read'):
            runtime.validate_database(b'not a SQLite database', {'id': 'one'}, 'title', 'body')

    def test_formal_launch_uses_observer_without_loader_environment(self):
        args = ['/guest/products with spaces/Meshchan.app/Contents/MacOS/Meshchan',
                '--data-dir=/fixture with spaces']
        command = guest.runtime_command(args, '/workspace with spaces', '/workspace/run',
                                        '/workspace/image observer', '/guest/lib/sqlite3')
        self.assertIn("'/workspace/image observer' /workspace/run.image.json /guest/lib/sqlite3 "
                      "'/guest/products with spaces/Meshchan.app/Contents/MacOS/Meshchan'", command)
        self.assertNotIn('DYLD_', command)
        self.assertIn('DYLD_PRINT_LIBRARIES=1', guest.runtime_command(args, '/workspace', '/workspace/run'))

    def test_cli_observer_pid_comes_from_the_reaped_runner_group_leader(self):
        observer = {'pid': 610, 'ppid': os.getpid(), 'pgid': 610, 'exitObserved': True, 'state': 'Z'}
        descendant = {'pid': 611, 'ppid': 610, 'pgid': 610, 'exitObserved': True}
        tree = {'exited': True, 'childReaped': True, 'members': [descendant, observer]}
        self.assertEqual(runtime.cli_observer_pid({'processTree': tree}), 610)
        with self.assertRaisesRegex(ValueError, 'owned runner process'):
            runtime.cli_observer_pid({'processTree': {**tree, 'members': [descendant]}})
        with self.assertRaisesRegex(ValueError, 'exitObserved'):
            runtime.cli_observer_pid({'processTree': {**tree, 'members': [{**observer, 'exitObserved': 1}]}})

    def test_cli_replay_rechecks_pinned_process_argv_exit_pid_and_output(self):
        bundle = self.root/'relocated products/meshctl'
        workspace = self.root/'CLI workspace'
        exe, lib = bundle/'bin/meshctl', bundle/build.CLI_SQLITE_LIBRARY
        observer = workspace/'release-image-probe'
        data = workspace/'owned signed CLI data'
        database = data/'meshchan.sqlite'
        for path in (exe, lib, observer):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(path.name.encode())
        database.parent.mkdir()
        with closing(sqlite3.connect(database)) as conn:
            conn.execute('create table stored_drafts(id, title, body, revision)')
            conn.execute('insert into stored_drafts values (?, ?, ?, ?)',
                         ('owned', runtime.CLI_TITLE, runtime.CLI_BODY, 1))
            conn.commit()
        rows = []
        steps = []

        def add_step(name, argv, output, members=None):
            log = self.root/(name+'.log')
            log.write_bytes(output)
            steps.append({'name': 'signed-cli-'+name, 'argv': list(map(str, argv)),
                          'cwd': str(workspace), 'exitCode': 0, 'log': log.name, 'logSha256': build.sha(output),
                          'processTree': {'childReaped': True, 'exited': True, 'members': members or []}})

        add_step('version', [exe, '--version'], b'meshctl 0.1.0-rc.1\n')
        for index, action in enumerate(('create', 'show')):
            observer_pid, product_pid = 200+index*2, 201+index*2
            image = workspace/(action+'-image.json')
            mapping = {'observerPid': observer_pid, 'pid': product_pid, 'exitCode': 0,
                       'mapping': {'device': lib.stat().st_dev & 0xffffffff, 'inode': lib.stat().st_ino,
                                   'address': '0xdeadbeef'}}
            image.write_bytes(build.encoded(mapping))
            observed = runtime.image_report(image.read_bytes(), exe, lib, runtime.digest(exe), runtime.digest(lib),
                                            0, observer_pid=observer_pid)
            select = (['--title', runtime.CLI_TITLE, '--body', runtime.CLI_BODY] if action == 'create'
                      else ['--id', 'owned'])
            argv = [exe, '--data-dir', data, 'draft', action, *select, '--json']
            result = {'exitCode': 0, 'operationSucceeded': True, 'schemaVersion': 1, 'command': 'draft',
                      'action': action, 'hostCleanup': 'succeeded',
                      'storageClose': {'state': 'closed', 'error': None},
                      'draft': {'title': runtime.CLI_TITLE, 'body': runtime.CLI_BODY, 'revision': 1, 'id': 'owned',
                                'bodyUtf8ByteLength': len(runtime.CLI_BODY.encode())}}
            members = [{'pid': observer_pid, 'ppid': 100, 'pgid': observer_pid, 'exitObserved': True},
                       {'pid': product_pid, 'ppid': observer_pid, 'pgid': observer_pid, 'exitObserved': True}]
            add_step(action, [observer, image, lib, *argv], build.encoded(result), members)
            rows.append({'name': action, 'argv': list(map(str, argv)), 'cwd': str(workspace), 'pid': product_pid,
                         'pidAbsentAfterNormalExit': True, 'sqliteMapping': observed, 'report': result})
        report = {'status': 'PASS', 'bundle': str(bundle), 'versionOutput': 'meshctl 0.1.0-rc.1',
                  'processes': rows, 'database': str(database), 'databaseSha256': runtime.digest(database),
                  'storedDrafts': [['owned', runtime.CLI_TITLE, runtime.CLI_BODY, 1]],
                  'observerSha256': runtime.digest(observer)}

        def verify():
            runtime.verify_cli_runtime_evidence(report, bundle, workspace, '0.1.0-rc.1',
                                                ledger={'steps': steps}, evidence_root=self.root)

        verify()
        for key, val in (('argv', ['/elsewhere/bin/meshctl']), ('exitCode', False)):
            with self.subTest(key=key), patch.dict(steps[1], {key: val}), self.assertRaisesRegex(ValueError, key):
                verify()
        with (patch.dict(steps[1]['processTree']['members'][1], {'pid': 999}),
              self.assertRaisesRegex(ValueError, 'different product process')):
            verify()
        with (patch.dict(steps[1]['processTree']['members'][0], {'pid': 999, 'pgid': 999}),
              self.assertRaisesRegex(ValueError, 'observerPid')):
            verify()
        with (patch.dict(rows[0]['report']['storageClose'], {'state': 'different'}),
              self.assertRaisesRegex(ValueError, 'Observed CLI output')):
            verify()
        with self.assertRaisesRegex(ValueError, 'storage close omitted its error field'):
            runtime.verified_cli_draft({**rows[0]['report'], 'storageClose': {'state': 'closed'}}, 'create')
        (self.root/'create.log').write_bytes(b'{}')
        with self.assertRaisesRegex(ValueError, 'Owned process log'):
            verify()

    def test_independent_vm_evidence_rejects_stale_or_type_confused_processes(self):
        report = {'guestSession': 'package.fixture0', 'guestRun': '20261120T200000Z-product-1324',
                  'identity': self.info['identity'], 'processes': []}
        owner = self.root/'session.json'
        owner.write_bytes(build.encoded({'run': report['guestRun'], 'lockIdentity': '5:8', 'products': {}}))
        observer = self.root/'release-image-probe'
        observer.write_bytes(b'attested test image observer')
        report.update(guestOwnershipSha256=build.digest(owner), observerSha256=build.digest(observer))
        guest_root = '$GUEST_ROOT/package.fixture0/'+runtime.APP_PHASE_DIRECTORY
        app = guest_root+'/Meshchan.app'
        report['guestApp'] = app
        executable, library = app+'/'+runtime.APP_EXECUTABLE, app+'/'+runtime.APP_SQLITE
        inventory = {runtime.APP_EXECUTABLE: {'sha256': '1'*64}, runtime.APP_SQLITE: {'sha256': '2'*64}}
        cwd = guest_root+'/runtime workspace'
        fixture = cwd+'/'+runtime.APP_FIXTURE
        closed = {'receivePorts': 0, 'pendingRequests': 0, 'resourcesReleased': True,
                  'workerExited': True, 'error': None}
        draft = {'id': 'test-draft', 'revision': 1, 'bodyUtf8Bytes': len(runtime.APP_BODY.encode())}
        database = self.root/'vm-fixture.sqlite'
        with closing(sqlite3.connect(database)) as conn:
            conn.execute('create table stored_drafts (id, title, body, revision)')
            conn.execute('insert into stored_drafts values (?, ?, ?, ?)',
                         (draft['id'], runtime.APP_TITLE, runtime.APP_BODY, 1))
            conn.commit()
        report['guestDatabaseSha256'] = build.digest(database)
        report['storedDrafts'] = [[draft['id'], runtime.APP_TITLE, runtime.APP_BODY, 1]]
        for mode, pid in (('write', 500), ('read', 600)):
            raw = build.encoded({'exitCode': 0, 'pid': pid, 'observerPid': pid-1, 'mapping': {
                'inode': 200, 'device': 30, 'address': '0x1000'}})
            (self.root/(mode+'-image.json')).write_bytes(raw)
            observed = runtime.image_report(raw, executable, library, '1'*64, '2'*64, 0, observer_pid=pid-1)
            stdout = '\n'.join(map(json.dumps, (
                {**closed, 'verification': 'meshchan.runtime.1d3', 'passed': True, 'mode': mode,
                 'appVersion': self.info['identity']['appVersion'],
                 'phases': ['opening', 'ready', 'stopping', 'closing', 'closed'], 'draft': draft},
                {**closed, 'runtime': 'meshchan.shutdown.1d3', 'workerWasSpawned': True,
                 'owner': 'released', 'quitPhase': 'closed'},
            )))
            report['processes'].append({
                'cwd': cwd, 'exitCode': 0, 'pid': pid, 'observerPid': pid-1,
                'pidAbsentAfterNormalExit': True, 'sqliteLoadedFrom': library, 'sqliteMapping': observed,
                'argv': [executable, '--meshchan-runtime='+mode, '--data-dir='+fixture, '--runtime-exit'],
                'draft': draft, 'stdout': stdout,
            })
        runtime.verify_vm_runtime_evidence(report, self.root, inventory)
        changed = {**report, 'guestRun': '20261120T200001Z-product-1325'}
        with self.assertRaisesRegex(ValueError, 'ownership run'):
            runtime.verify_vm_runtime_evidence(changed, self.root, inventory)
        changed = {**report, 'observerSha256': 'a'*64}
        with self.assertRaisesRegex(ValueError, 'observerSha256'):
            runtime.verify_vm_runtime_evidence(changed, self.root, inventory)
        changed = {**report, 'storedDrafts': [[draft['id'], runtime.APP_TITLE, runtime.APP_BODY, True]]}
        with self.assertRaisesRegex(ValueError, 'SQLite receipt'):
            runtime.verify_vm_runtime_evidence(changed, self.root, inventory)
        changed = copy.deepcopy(report)
        changed['processes'][1]['observerPid'] = report['processes'][0]['pid']
        with self.assertRaisesRegex(ValueError, 'observerPid'):
            runtime.verify_vm_runtime_evidence(changed, self.root, inventory)
        changed = copy.deepcopy(report)
        changed['processes'][0]['exitCode'] = False
        with self.assertRaisesRegex(ValueError, 'exitCode'):
            runtime.verify_vm_runtime_evidence(changed, self.root, inventory)
        write_image, read_image = self.root/'write-image.json', self.root/'read-image.json'
        first, second = write_image.read_bytes(), read_image.read_bytes()
        wrong_vnode = json.loads(second)
        wrong_vnode['mapping']['inode'] += 1
        replacement = build.encoded(wrong_vnode)
        read_image.write_bytes(replacement)
        changed = copy.deepcopy(report)
        changed['processes'][1]['sqliteMapping'] = runtime.image_report(
            replacement, executable, library, '1'*64, '2'*64, 0, observer_pid=599)
        with self.assertRaisesRegex(ValueError, 'SQLite vnode after process reopen'):
            runtime.verify_vm_runtime_evidence(changed, self.root, inventory)
        write_image.write_bytes(second)
        read_image.write_bytes(first)
        changed = copy.deepcopy(report)
        for row, swapped in zip(changed['processes'], reversed(report['processes'])):
            row.update(pid=swapped['pid'], sqliteMapping=swapped['sqliteMapping'])
        # Both product PIDs, the hashes and the vnode can agree with the
        # swapped receipts, but the independently recorded observers cannot.
        with self.assertRaisesRegex(ValueError, 'observerPid'):
            runtime.verify_vm_runtime_evidence(changed, self.root, inventory)

    def test_cleanup_of_failed_product_requires_attested_run(self):
        vm = Mock(root='/guest/root')
        vm.runpath.return_value = '/guest/run'
        vm.remote.side_effect = [None, SimpleNamespace(stdout='0\n'), SimpleNamespace(stdout='released\n')]
        product = Mock(vm=vm, state={'run': 'current', 'lockIdentity': '5:9'})
        with patch.object(guest, 'owned_guest_run', return_value={'run': 'old', 'lockIdentity': '5:8'}):
            with self.assertRaisesRegex(ValueError, 'attest'):
                guest.finish_guest(product, '/guest/session', check_product_shutdown=False)
            vm.remote.assert_not_called()
        with patch.object(guest, 'owned_guest_run', return_value=dict(product.state)):
            self.assertEqual(guest.finish_guest(product, '/guest/session', check_product_shutdown=False), 0)
        product.finish.assert_not_called()
        self.assertEqual(vm.remote.call_args_list[0].args[0], '/usr/bin/touch /guest/run/finish')

    @unittest.skipUnless(sys.platform == 'darwin', 'The native observer uses macOS libproc')
    def test_native_observer_checks_real_executable_vnode_not_file_presence(self):
        observer = self.root/'observer'
        source = self.root/'library.c'
        source.write_text('int fixture_marker(void) { return 6; }\n')
        library = self.root/'libfixture.dylib'
        unrelated = self.root/'libunrelated.dylib'
        program = self.root/'program.c'
        program.write_text('#include <time.h>\nextern int fixture_marker(void);\n'
                           'int main(void) {\n'
                           '    const struct timespec delay = {.tv_nsec = 100000000};\n'
                           '    const int result = fixture_marker();\n'
                           '    nanosleep(&delay, 0);\n'
                           '    return result != 6;\n'
                           '}\n')
        executable = self.root/'program'
        clang = ['/usr/bin/xcrun', '--sdk', 'macosx', 'clang']
        subprocess.run(runtime.image_probe_command(observer), check=True, timeout=60)
        for output in (library, unrelated):
            subprocess.run([*clang, '-dynamiclib', source, '-o', output], check=True, timeout=30)
        subprocess.run([*clang, program, library, '-o', executable], check=True, timeout=30)
        for expected in (library, unrelated):
            receipt = self.root/(expected.stem+'.json')
            with subprocess.Popen([observer, receipt, expected, executable]) as process:
                self.assertEqual(process.wait(timeout=10), 0)
            observation = json.loads(receipt.read_bytes())
            self.assertEqual(observation['exitCode'], 0)
            self.assertEqual(observation['observerPid'], process.pid)
            self.assertGreater(observation['pid'], 1)
            runtime.require_absent_pid(observation['pid'])
            if expected == library:
                self.assertEqual(observation['mapping']['inode'], library.stat().st_ino)
                self.assertEqual(observation['mapping']['device'], library.stat().st_dev & 0xFFFFFFFF)
            else:
                self.assertIsNone(observation['mapping'])

    @unittest.skipUnless(sys.platform == 'darwin', 'The native observer uses macOS libproc')
    def test_interrupted_native_observer_reaps_its_child(self):
        observer = self.root/'observer'
        subprocess.run(runtime.image_probe_command(observer), check=True, timeout=60)
        executable = self.root/'waiter'
        source = self.root/'waiter.c'
        source.write_text('#include <stdio.h>\n#include <unistd.h>\n'
                          'int main(void) {\n'
                          '  alarm(10);\n'
                          '  printf("%d\\n", getpid());\n'
                          '  fflush(stdout);\n'
                          '  for (;;) pause();\n'
                          '}\n')
        subprocess.run(['/usr/bin/xcrun', '--sdk', 'macosx', 'clang', source, '-o', executable],
                       check=True, timeout=30)
        receipt = self.root/'interrupted.json'
        output = self.root/'pid.txt'
        with output.open('wb') as stream, subprocess.Popen(
                [observer, receipt, source, executable], stdout=stream) as process:
            try:
                deadline = time.monotonic()+5
                while not (data := output.read_bytes()).endswith(b'\n'):
                    if process.poll() is not None or time.monotonic() >= deadline:
                        self.fail('Native observer did not launch the owned child')
                    time.sleep(0.01)
            finally:
                if process.poll() is None:
                    process.terminate()
                self.assertEqual(process.wait(timeout=5), 128+signal.SIGTERM)
        runtime.require_absent_pid(int(data))
        self.assertEqual(receipt.read_bytes(), b'')


if __name__ == '__main__':
    unittest.main()
