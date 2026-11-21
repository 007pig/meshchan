"""Focused tests for the release-signed replacement evidence contract."""

from pathlib import Path
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

import release_signed_replacement as replacement
from release_materials import digest, encoded, product_inventory, sha


class ReplacementEvidenceTest(unittest.TestCase):
    MARKER = replacement.MARKER_START + '1'*32
    PORTS = {'schemaVersion': 1, 'command': 'ports', 'ports': []}

    def test_cli_requires_exact_schema_and_current_marker(self):
        valid = replacement.verify_cli_output(json.dumps(self.PORTS), self.MARKER+':517\n', self.MARKER)
        self.assertEqual(valid['markerPid'], 517)
        self.assertEqual(valid['result'], self.PORTS)
        for bad_stdout in ({**self.PORTS, 'schemaVersion': True}, {**self.PORTS, 'ports': ['usb']},
                           {**self.PORTS, 'command': 'info'}):
            with self.subTest(bad_stdout=bad_stdout), self.assertRaises(ValueError):
                replacement.verify_cli_output(json.dumps(bad_stdout), self.MARKER+':517\n', self.MARKER)
        stale = self.MARKER.replace('1', '2')+':517\n'
        for bad_stderr in (stale, self.MARKER+':517\n'+self.MARKER+':518\n',
                           self.MARKER+':517\n'+stale,
                           'previous log '+self.MARKER+':517\n'):
            with self.subTest(bad_stderr=bad_stderr), self.assertRaisesRegex(ValueError, 'current-run'):
                replacement.verify_cli_output(json.dumps(self.PORTS), bad_stderr, self.MARKER)
        with self.assertRaisesRegex(ValueError, 'current-run'):
            replacement.require_marker(self.MARKER+':517\n', self.MARKER, 518)
        with self.assertRaisesRegex(ValueError, 'current-run'):
            replacement.verify_cli_output(json.dumps(self.PORTS), self.MARKER+':517\n', self.MARKER, pid=518)

    def test_app_shutdown_rejects_wrong_types_and_repeated_receipts(self):
        close = {'runtime': 'meshchan.shutdown.1d3', 'owner': 'released', 'quitPhase': 'ready',
                 'resourcesReleased': True, 'workerExited': True, 'workerWasSpawned': True,
                 'pendingRequests': 0, 'receivePorts': 0, 'error': None, 'maintenanceFailureCount': 0}
        self.assertEqual(replacement.verify_shutdown(json.dumps(close)), close)
        for field, bad in [('workerExited', 1), ('resourcesReleased', 'true'), ('owner', 'unknown'),
                          ('pendingRequests', False), ('receivePorts', None), ('quitPhase', 'starting'),
                          ('error', 'storage_failed'), ('maintenanceFailureCount', 1)]:
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'normal storage'):
                replacement.verify_shutdown(json.dumps({**close, field: bad}))
        with self.assertRaisesRegex(ValueError, 'one current App'):
            replacement.verify_shutdown((json.dumps(close)+'\n')*2)

    def test_synthetic_patch_is_exact_and_does_not_reapply(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)/'serialport.c'
            before = b'#include "libserialport_internal.h"\r\n'+replacement.LIST_FUNCTION+b'\r\n original();\r\n}\r\n'
            source.write_bytes(before)
            result = replacement.patch_source(source, self.MARKER)
            body = source.read_bytes()
            self.assertEqual(result['sourceSha256'], sha(before))
            self.assertEqual(result['patchedSourceSha256'], sha(body))
            self.assertIn(self.MARKER.encode(), body)
            self.assertLess(body.index(b'return *list_ptr'), body.index(b'original();'))
            with self.assertRaisesRegex(ValueError, 'shipped libserialport'):
                replacement.patch_source(source, self.MARKER)
            with self.assertRaisesRegex(ValueError, 'Invalid synthetic'):
                replacement.patch_source(source, '"arbitrary code"')
            source.write_bytes(before.replace(replacement.LIST_FUNCTION, b'unexpected declaration'))
            with self.assertRaisesRegex(ValueError, 'shipped libserialport'):
                replacement.patch_source(source, self.MARKER)

    def test_local_entitlements_are_scoped_to_runtime_roles(self):
        self.assertEqual(replacement.local_entitlements(replacement.APP),
                         {replacement.LOCAL_LIBRARY_VALIDATION: True})
        self.assertEqual(replacement.local_entitlements(replacement.CLI_BINARY),
                         {replacement.LOCAL_LIBRARY_VALIDATION: True,
                          replacement.UNSIGNED_EXECUTABLE_MEMORY: True})
        for path in (replacement.CLI_LIBRARY, replacement.APP_LIBRARY, replacement.APP_FRAMEWORK):
            self.assertEqual(replacement.local_entitlements(path), {})

    def test_actual_local_signature_requires_runtime_and_exact_role_entitlements(self):
        policy = replacement.signing.load_policy(replacement.signing.DEFAULT_POLICY)
        observations = {item.path: {'adhoc': True, 'runtime': item.runtime, 'identifier': item.identifier,
                                     'team': 'not set', 'timestamp': None,
                                     'entitlements': replacement.local_entitlements(item.path)}
                        for item in replacement.local_signing_items(policy)}
        graph = [{'path': item.path, 'architectures': ['arm64']} for item in policy]
        copies = Path('/private/tmp/owned test products')

        def display(_root, item, _architecture, _command, _name):
            return observations[item.path]

        command = mock.Mock()
        with (mock.patch.object(replacement.signing, 'discover_code', return_value=graph),
              mock.patch.object(replacement.signing, 'display_signature', side_effect=display)):
            checked = replacement.verify_local_signatures(copies, policy, command, prefix='replacement-final')
            self.assertTrue(checked[replacement.CLI_BINARY]['arm64']['runtime'])
            self.assertTrue(all(call.args[0].startswith('replacement-final-verify-')
                                for call in command.call_args_list))
            for changed_path, field, value in (
                (replacement.CLI_BINARY, 'runtime', False),
                (replacement.CLI_BINARY, 'entitlements', {}),
                (replacement.APP_FRAMEWORK, 'entitlements', replacement.local_entitlements(replacement.APP)),
            ):
                with self.subTest(changed_path=changed_path, field=field), \
                        mock.patch.dict(observations[changed_path], {field: value}):
                    with self.assertRaisesRegex(ValueError, 'Local signing policy mismatch'):
                        replacement.verify_local_signatures(copies, policy, command)

    def test_archive_binding_checks_actual_bytes_and_accepted_index(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            materials = root/'materials'
            relative = 'source-materials/archives/libserialport_plus-1.0.5.tar.gz'
            archive = materials/relative
            archive.parent.mkdir(parents=True)
            archive.write_bytes(b'archive')
            manifest = materials/'materials-manifest.json'
            record = {'sha256': digest(archive), 'size': archive.stat().st_size}
            manifest.write_bytes(encoded({'materials': {relative: record}}))
            inventory = product_inventory(root)
            observed, public = replacement.serial_archive(root, inventory)
            self.assertEqual(observed, archive)
            self.assertEqual(public['sha256'], digest(archive))
            archive.write_bytes(b'changes')
            with self.assertRaisesRegex(ValueError, 'pinned release materials'):
                replacement.serial_archive(root, inventory)
            manifest.write_bytes(encoded({'materials': {}}))
            with self.assertRaisesRegex(ValueError, 'manifest changed'):
                replacement.serial_archive(root, inventory)

    @unittest.skipUnless(Path('/usr/bin/xattr').is_file(), 'macOS metadata required')
    def test_original_payload_rejects_unexpected_metadata_without_content_change(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root/'product'
            artifact.write_bytes(b'unchanged contents')
            expected = product_inventory(root)
            replacement.original_payload(root, expected)
            subprocess.run(['/usr/bin/xattr', '-w', 'com.apple.quarantine',
                            '0081;00000000;MeshchanTest;', artifact], check=True, timeout=5)
            self.assertEqual(product_inventory(root), expected)
            with self.assertRaisesRegex(ValueError, 'Unsupported extended attributes'):
                replacement.original_payload(root, expected)

    def test_rebuild_rejects_wrong_install_name_in_one_slice_before_replacing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original, copies, source = (root/name for name in ('original', 'copies', 'source'))
            source.mkdir()
            for folder in (original, copies):
                target = folder/replacement.APP_LIBRARY
                target.parent.mkdir(parents=True)
                target.write_bytes(b'original file')
            install_name = '@rpath/libserialport_plus.framework/libserialport_plus'
            checked = []

            def command(label, argv):
                if label.endswith('architectures'):
                    return 'arm64 x86_64\n'
                if label.endswith('compile'):
                    argv[-1].write_bytes(b'rebuilt bytes')
                    return ''
                self.assertEqual(argv[:2], ['/usr/bin/otool', '-arch'])
                checked.append(label)
                name = '@rpath/unexpected.dylib' if label.endswith('rebuilt-id-x86_64') else install_name
                return f'{argv[-1]}:\n{name}\n'

            with self.assertRaisesRegex(ValueError, 'install name for x86_64'):
                replacement.replace_library(original, copies, replacement.APP_LIBRARY, source,
                                            '/usr/bin/clang', '/sdk', command, 'app-library')
            self.assertEqual(checked, ['app-library-source-id-arm64', 'app-library-source-id-x86_64',
                                       'app-library-rebuilt-id-arm64', 'app-library-rebuilt-id-x86_64'])
            self.assertEqual((copies/replacement.APP_LIBRARY).read_bytes(), b'original file')

    def test_execution_rejects_changes_after_the_verified_copy_cut(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            original = root/'signed'
            output = root/'replacement output'
            original.mkdir()
            (original/'example').write_text('payload')
            manifest = original/replacement.MANIFEST
            expected = product_inventory(original)
            manifest.write_bytes(encoded({'formatVersion': 1, 'identity': {}, 'payloadInventory': expected,
                                          'signature': {'identity': {'sha1': 'a'*40, 'team': 'EXAMPLE123'}}}))
            manifest.chmod(0o600)

            def prepare(_root, _original_inventory, copies, *_arguments):
                copies.mkdir()
                resource = copies/'resource'
                resource.write_text('checked')
                verified = product_inventory(copies)
                resource.write_text('changed after the transform check')
                return {'verifiedInventory': verified}

            with mock.patch.object(replacement.signing, 'verify_signatures'), \
                    mock.patch.object(replacement, 'serial_archive', return_value=(None, {'sha256': '0'*64})), \
                    mock.patch.object(replacement, 'prepare_copies', side_effect=prepare), \
                    mock.patch.object(replacement, 'run_cli') as run_cli:
                with self.assertRaisesRegex(ValueError, 'differs at resource'):
                    replacement.run(original, output, signed_info_sha256=digest(manifest))
            run_cli.assert_not_called()

    def test_checkout_case_alias_cannot_admit_output_inside_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            checkout = root/'CanonicalCheckout'
            tool = checkout/'tool'
            tool.mkdir(parents=True)
            output = root/'CANONICALCHECKOUT'/'tool'/'new output'
            if not output.parent.is_dir() or not output.parent.samefile(tool):
                self.skipTest('Case-insensitive checkout required')
            with mock.patch.object(replacement.build, 'ROOT', checkout):
                with self.assertRaisesRegex(ValueError, 'ignored build subdirectory'):
                    replacement.run(root/'signed', output, signed_info_sha256='0'*64)
            self.assertFalse((tool/'new output').exists())

    def test_vm_runtime_directory_cannot_write_inside_selected_replacement_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            original = root/'signed'
            original.mkdir()
            (original/'example').write_text('payload')
            manifest = original/replacement.MANIFEST
            replacement.build.write(manifest, {'formatVersion': 1, 'identity': {},
                                               'payloadInventory': product_inventory(original)})
            output = root/'replacement output'
            checkout = root/'checkout'
            checkout.mkdir()
            config = root/'vm-config.json'
            with (mock.patch.object(replacement.build, 'ROOT', checkout),
                  mock.patch.object(replacement.signing, 'verify_signatures') as verify):
                for protected in (original, output, checkout):
                    with self.subTest(protected=protected):
                        config.write_bytes(encoded({'runtime_dir': os.path.relpath(protected/'socket state')}))
                        with self.assertRaisesRegex(ValueError, 'overlaps'):
                            replacement.run(original, output, signed_info_sha256=digest(manifest), vm_config=config)
                        self.assertFalse((protected/'socket state').exists())
            verify.assert_not_called()
            self.assertFalse(output.exists())

    def test_cli_pass_with_later_integrity_failure_stays_failed(self):
        for changed in (replacement.APP_LIBRARY, replacement.MANIFEST):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve()
                original = root/'signed'
                output = root/'replacement output'
                original.mkdir()
                (original/'example').write_text('payload')
                manifest = original/replacement.MANIFEST
                manifest.write_bytes(encoded({'formatVersion': 1, 'identity': {},
                                              'payloadInventory': product_inventory(original),
                                              'signature': {'identity': {'sha1': 'a'*40, 'team': 'EXAMPLE123'}}}))
                manifest.chmod(0o600)

                def prepare(_root, _original_inventory, copies, *_arguments):
                    libraries = {}
                    for name in (replacement.CLI_LIBRARY, replacement.APP_LIBRARY):
                        library = copies/name
                        library.parent.mkdir(parents=True, exist_ok=True)
                        library.write_bytes(b'verified library')
                        libraries[name] = {'signedReplacementSha256': digest(library)}
                    return {'verifiedInventory': product_inventory(copies), 'libraries': libraries}

                def run_cli(copies, *_arguments):
                    if changed == replacement.APP_LIBRARY:
                        (copies/changed).write_bytes(b'unexpected library')
                    else:
                        manifest.chmod(0o644)
                    return {'exitCode': 0}

                with mock.patch.object(replacement.signing, 'verify_signatures'), \
                        mock.patch.object(replacement, 'serial_archive', return_value=(None, {'sha256': '0'*64})), \
                        mock.patch.object(replacement, 'prepare_copies', side_effect=prepare), \
                        mock.patch.object(replacement, 'run_cli', side_effect=run_cli):
                    with self.assertRaisesRegex(ValueError, 'differs at ' + re.escape(changed)):
                        replacement.run(original, output, signed_info_sha256=digest(manifest))
                receipt = json.loads((output/'evidence/replacement-receipt.json').read_bytes())
                self.assertEqual(receipt['status'], 'FAIL')
                self.assertEqual(receipt['cli']['status'], 'PASS')
                self.assertNotIn('finalIntegrity', receipt)

    def test_replacement_never_runs_without_formal_signature_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory).resolve()
            original = parent/'signed'
            output = parent/'replacement output'
            original.mkdir()
            (original/'example').write_text('payload')
            inventory = product_inventory(original)
            manifest = original/replacement.MANIFEST
            manifest.write_bytes(encoded({'formatVersion': 1, 'identity': {}, 'payloadInventory': inventory,
                                          'signature': {'identity': {'sha1': 'a'*40, 'team': 'EXAMPLE123'}}}))
            manifest.chmod(0o644)
            with self.assertRaisesRegex(ValueError, 'selected SHA-256'):
                replacement.run(original, output, signed_info_sha256='0'*64)
            with self.assertRaisesRegex(ValueError, 'differs at signed-product-info\\.json'):
                replacement.run(original, output, signed_info_sha256=digest(manifest))
            self.assertFalse(output.exists())
            manifest.chmod(0o600)
            with mock.patch.object(replacement.signing, 'verify_signatures',
                                   side_effect=ValueError('Developer ID signature mismatch')), \
                    mock.patch.object(replacement, 'prepare_copies') as prepare:
                with self.assertRaisesRegex(ValueError, 'Developer ID signature mismatch'):
                    replacement.run(original, output, signed_info_sha256=digest(manifest))
            prepare.assert_not_called()
            receipt = json.loads((output/'evidence/replacement-receipt.json').read_bytes())
            self.assertEqual(receipt['status'], 'FAIL')
            self.assertEqual(receipt['cli']['status'], 'NOT_RUN')
            self.assertEqual(receipt['app']['status'], 'NOT_RUN')
            self.assertFalse((output/'user products').exists())

    def test_modified_app_inventory_is_checked_before_guest_start(self):
        with tempfile.TemporaryDirectory() as directory:
            copies = Path(directory)
            app = copies/replacement.APP
            library = app/replacement.APP_LIBRARY.removeprefix(replacement.APP+'/')
            library.parent.mkdir(parents=True)
            library.write_bytes(b'replacement')
            resource = app/'resource'
            resource.write_text('prepared')
            expected = product_inventory(app)
            resource.write_text('changed after preparation')
            with mock.patch.object(replacement.vm_steps, 'load') as load_vm:
                with self.assertRaisesRegex(ValueError, 'differs at resource'):
                    replacement.run_app(copies, copies/'evidence', copies/'vm-config.json', self.MARKER,
                                        digest(library), app_inventory=expected)
            load_vm.assert_not_called()

    def test_vm_configuration_snapshot_is_removed_before_guest_connection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            app = root/replacement.APP
            library = app/replacement.APP_LIBRARY.removeprefix(replacement.APP+'/')
            library.parent.mkdir(parents=True)
            library.write_bytes(b'replacement')
            inventory = product_inventory(app)
            config = root/'vm-config.json'
            config_data = encoded({'runtime_dir': str(root/'private VM socket state')})
            config.write_bytes(config_data)
            configuration = replacement.vm_steps.checked_vm_configuration(config, (app, root/'evidence'))
            read_snapshots = []

            def product(config_path, _evidence):
                snapshot = Path(config_path)
                self.assertNotEqual(snapshot, config)
                self.assertEqual(snapshot.stat().st_mode & 0o777, 0o600)
                self.assertEqual(snapshot.read_bytes(), config_data)
                read_snapshots.append(snapshot)
                return SimpleNamespace(vm=object())

            def connect(_vm):
                self.assertEqual(len(read_snapshots), 1)
                self.assertFalse(read_snapshots[0].exists())
                raise ValueError('stop at connection boundary')

            host = SimpleNamespace(Product=product)
            with (mock.patch.object(replacement.vm_steps, 'load', return_value=host),
                  mock.patch.object(replacement.vm_steps, 'require_ready_connection', side_effect=connect)):
                with self.assertRaisesRegex(ValueError, 'stop at connection boundary'):
                    replacement.run_app(root, root/'evidence', config, self.MARKER, digest(library),
                                        app_inventory=inventory, configuration=configuration)
            self.assertEqual(config.read_bytes(), config_data)

    def test_guest_supervisor_publishes_failure_before_launch(self):
        with tempfile.TemporaryDirectory(prefix='meshchan app supervisor ') as directory:
            root = Path(directory)
            result = subprocess.run(['/bin/bash', '-eu', '-c', replacement.watch_app(str(root))],
                                    capture_output=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root/'app.pid').exists())
            self.assertEqual(replacement.read_owned_exit((root/'app.exit').read_text()), result.returncode)

    def test_lost_cancel_reply_preserves_the_claim_and_late_watcher_cannot_start(self):
        with tempfile.TemporaryDirectory(prefix='meshchan app supervisor ') as directory:
            root = Path(directory)

            def remote(command, **arguments):
                result = subprocess.run(['/bin/bash', '-eu', '-c', command], check=True, **arguments)
                if vm.remote.call_count == 1:
                    raise ValueError('The successful SSH reply was lost')
                return result

            vm = SimpleNamespace(remote=mock.Mock(side_effect=remote))
            self.assertTrue(replacement.cancel_app_launch(vm, str(root)))
            self.assertEqual(vm.remote.call_count, 2)
            claim = root/replacement.APP_LAUNCH_CLAIM
            self.assertEqual(os.readlink(claim), replacement.HOST_CANCELLED)
            finish = root/'executor.finish'
            result = subprocess.run(['/bin/bash', '-eu', '-c', replacement.watch_app(str(root), str(finish))],
                                    capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 75)
            self.assertEqual(os.readlink(claim), replacement.HOST_CANCELLED)
            for path in ('app.pid', 'app.exit', 'executor.finish'):
                self.assertFalse((root/path).exists())

    def test_interruption_after_claim_before_return_finishes_only_its_executor(self):
        with tempfile.TemporaryDirectory(prefix='meshchan app supervisor ') as directory:
            root = Path(directory)
            finish = root/'executor.finish'
            link = root/'interrupt after linking'
            link.write_text('#!/bin/bash\n/bin/ln "$@" || exit\nkill -TERM "$PPID"\n')
            link.chmod(0o755)
            command = replacement.watch_app(str(root), str(finish)).replace(
                '/bin/ln -sn', shlex.quote(str(link))+' -sn', 1)
            result = subprocess.run(['/bin/bash', '-eu', '-c', command], capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 143)
            claim = root/replacement.APP_LAUNCH_CLAIM
            self.assertRegex(os.readlink(claim), r'^guest-watcher:[0-9a-f]{32}:[1-9][0-9]*$')
            self.assertFalse((root/'app.pid').exists())
            self.assertEqual(replacement.read_owned_exit((root/'app.exit').read_text()), 143)
            self.assertTrue(finish.is_file())

    def test_uncertain_submission_uses_claim_to_choose_cleanup_and_preserves_errors(self):
        with tempfile.TemporaryDirectory() as directory:
            copies = Path(directory)
            app = copies/replacement.APP
            library = app/replacement.APP_LIBRARY.removeprefix(replacement.APP+'/')
            library.parent.mkdir(parents=True)
            library.write_bytes(b'replacement')
            inventory = product_inventory(app)
            shared = '/Users/guest/utm-ui-isolation'
            session = shared+'/package.abcd1234'
            run_id = '20261121T000000Z-product-25'
            for cancellation in (True, False, ValueError('Unable to read the launch owner')):
                with self.subTest(cancellation=cancellation):
                    failure = ValueError('SSH submission reply lost')
                    failure_receipt = copies/'failure.json'
                    failure_receipt.unlink(missing_ok=True)

                    def persist_failure(error):
                        replacement.build.write(failure_receipt, {'status': 'FAIL', 'error': str(error)})

                    def resolve_claim(_vm, _root):
                        self.assertEqual(json.loads(failure_receipt.read_bytes()),
                                         {'status': 'FAIL', 'error': str(failure)})
                        if isinstance(cancellation, Exception):
                            raise cancellation
                        return cancellation

                    vm = mock.Mock(root=shared, runpath=mock.Mock(return_value=shared+'/runs/'+run_id))
                    product = mock.Mock(vm=vm, state={'run': run_id, 'products': {}})
                    product.job.side_effect = failure
                    host = SimpleNamespace(Product=mock.Mock(return_value=product))
                    methods = {
                        'load': mock.Mock(return_value=host),
                        'require_ready_connection': mock.Mock(),
                        'guest_session': mock.Mock(return_value=session),
                        'start_guest': mock.Mock(),
                        'record_guest_run': mock.Mock(return_value=True),
                        'guest_inventory': mock.Mock(),
                        'require_absent_pid': mock.Mock(),
                        'finish_guest': mock.Mock(return_value=0),
                        'confirm_guest_exit': mock.Mock(return_value=0),
                    }
                    claim = mock.Mock(side_effect=resolve_claim)
                    with (mock.patch.multiple(replacement.vm_steps, **methods),
                          mock.patch.object(replacement, 'cancel_app_launch', claim),
                          mock.patch.object(replacement, 'guest_read', side_effect=['143\n', '602\n']) as read):
                        with self.assertRaisesRegex(ValueError, 'SSH submission reply lost') as raised:
                            replacement.run_app(copies, copies/'evidence', copies/'vm-config.json', self.MARKER,
                                                digest(library), app_inventory=inventory,
                                                on_failure=persist_failure)
                    claim.assert_called_once_with(vm, shared+'/products/'+run_id+'-Release')
                    if cancellation is True:
                        methods['finish_guest'].assert_called_once_with(
                            product, session, check_product_shutdown=False)
                        methods['confirm_guest_exit'].assert_not_called()
                        read.assert_not_called()
                    elif cancellation is False:
                        methods['require_absent_pid'].assert_called_once_with(vm, 602)
                        methods['confirm_guest_exit'].assert_called_once_with(product)
                        methods['finish_guest'].assert_not_called()
                    else:
                        self.assertIn('Unable to read the launch owner', str(raised.exception))
                        methods['finish_guest'].assert_not_called()
                        methods['confirm_guest_exit'].assert_not_called()

    def test_guest_supervisor_reaps_its_child_before_publishing_interrupt(self):
        with tempfile.TemporaryDirectory(prefix='meshchan app supervisor ') as directory:
            root = Path(directory)
            (root/'cwd').mkdir()
            executable = root/replacement.APP_BINARY
            executable.parent.mkdir(parents=True)
            executable.write_text('#!/bin/sh\nexec /bin/sleep 30\n')
            executable.chmod(0o755)
            finish = root/'executor.finish'
            command = replacement.watch_app(str(root), str(finish))
            with subprocess.Popen(['/bin/bash', '-eu', '-c', command],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as supervisor:
                receipt = root/'app.pid'
                try:
                    raw_pid = replacement.wait_for(lambda: receipt.read_text() if receipt.exists() else None,
                                                   5, 'Fixture child PID unavailable')
                    pid = replacement.read_owned_pid(raw_pid)
                    vm = SimpleNamespace(remote=lambda command, **arguments: subprocess.run(
                        ['/bin/bash', '-eu', '-c', command], check=True, **arguments))
                    self.assertFalse(replacement.cancel_app_launch(vm, str(root)))
                    claim = root/replacement.APP_LAUNCH_CLAIM
                    owner = os.readlink(claim)
                    self.assertRegex(owner, rf'^guest-watcher:[0-9a-f]{{32}}:{supervisor.pid}$')
                    duplicate = subprocess.run(['/bin/bash', '-eu', '-c', command],
                                               capture_output=True, timeout=5)
                    self.assertEqual(duplicate.returncode, 75)
                    self.assertEqual(os.readlink(claim), owner)
                    self.assertFalse(finish.exists())
                    self.assertFalse((root/'app.exit').exists())
                finally:
                    supervisor.terminate()
                    status = supervisor.wait(timeout=5)
            self.assertEqual(status, 143)
            self.assertEqual(replacement.read_owned_exit((root/'app.exit').read_text()), status)
            self.assertTrue(finish.is_file())
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)

    def test_legacy_vm_runtime_reaps_its_child_after_repeated_interrupts(self):
        with tempfile.TemporaryDirectory(prefix='meshchan VM runtime ') as directory:
            root = Path(directory)
            script = ('from pathlib import Path; import os, signal, time; '
                      'signal.signal(signal.SIGTERM, lambda *_: Path("term").touch()); '
                      'print(os.getpid(), flush=True); time.sleep(5)')
            prefix = root/'runtime'
            command = replacement.vm_steps.runtime_command(
                [sys.executable, '-B', '-c', script], str(root), str(prefix))
            with subprocess.Popen(['/bin/bash', '-eu', '-c', command], stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL) as supervisor:
                try:
                    stdout = root/'runtime.stdout'
                    raw_pid = replacement.wait_for(lambda: stdout.read_text() if stdout.exists() else None,
                                                   4, 'Fixture child PID unavailable')
                    pid = replacement.read_owned_pid(raw_pid)
                    supervisor.terminate()
                    replacement.wait_for(lambda: (root/'term').exists(), 3, 'Child did not receive first TERM')
                    supervisor.terminate()
                    self.assertEqual(supervisor.wait(timeout=4), 143)
                    with self.assertRaises(ProcessLookupError):
                        os.kill(pid, 0)
                finally:
                    if supervisor.poll() is None:
                        supervisor.kill()
                        supervisor.wait(timeout=5)
            self.assertFalse((root/'runtime.exit').exists())

    def test_interruption_after_fork_before_pid_assignment_reaps_the_owned_child(self):
        for wrapper, variable, signum, code in (('runtime', 'pid', 'TERM', 143),
                                                 ('replacement', 'child', 'HUP', 129)):
            with (self.subTest(wrapper=wrapper),
                  tempfile.TemporaryDirectory(prefix='meshchan launch handoff ') as directory):
                root = Path(directory)
                finish = root/'executor.finish'
                if wrapper == 'runtime':
                    command = replacement.vm_steps.runtime_command(
                        ['/bin/sleep', '5'], str(root), str(root/'runtime'))
                else:
                    (root/'cwd').mkdir()
                    executable = root/replacement.APP_BINARY
                    executable.parent.mkdir(parents=True)
                    executable.write_text('#!/bin/sh\nexec /bin/sleep 5\n')
                    executable.chmod(0o755)
                    command = replacement.watch_app(str(root), str(finish))
                handoff = '\n'+variable+'=$!\n'
                self.assertIn(handoff, command)
                forked = root/'forked.pid'
                command = command.replace(
                    handoff, f'\nprintf "%s\\n" "$!" > {shlex.quote(str(forked))}\n'
                             f'kill -{signum} "$$"\n'+handoff, 1)
                result = subprocess.run(['/bin/bash', '-eu', '-c', command],
                                        capture_output=True, timeout=5)
                self.assertEqual(result.returncode, code)
                pid = replacement.read_owned_pid(forked.read_text())
                with self.assertRaises(ProcessLookupError):
                    os.kill(pid, 0)
                if wrapper == 'replacement':
                    self.assertFalse((root/'app.pid').exists())
                    self.assertEqual(replacement.read_owned_exit((root/'app.exit').read_text()), code)
                    self.assertTrue(finish.is_file())
                else:
                    self.assertFalse((root/'runtime.pid').exists())
                    self.assertFalse((root/'runtime.exit').exists())


if __name__ == '__main__':
    unittest.main()
