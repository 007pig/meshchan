"""Regression tests for the Phase 1E.6 release boundary."""
from base64 import b64decode
from copy import deepcopy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import package_release as package
from release_materials import encoded, product_inventory, sha
import sign_release as signing


class SigningBoundaryTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()

    def test_parse_the_exact_pinned_bytes(self):
        raw = b'{"status": "PASS"}\n'
        (self.root/'receipt.json').write_bytes(raw)
        self.assertEqual(({'status': 'PASS'}, raw), signing.bound_json(self.root, 'receipt.json', sha(raw)))
        (self.root/'receipt.json').write_bytes(b'{"status":"PASS"}')
        with self.assertRaisesRegex(ValueError, 'Bound JSON SHA-256'):
            signing.bound_json(self.root, 'receipt.json', sha(raw))

    def test_receipt_must_be_an_object_and_not_a_symlink(self):
        raw = b'[1]'
        (self.root/'receipt.json').write_bytes(raw)
        with self.assertRaisesRegex(ValueError, 'Expected JSON object'):
            signing.bound_json(self.root, 'receipt.json', sha(raw))
        (self.root/'reference.json').symlink_to('receipt.json')
        with self.assertRaises(ValueError):
            signing.bound_json(self.root, 'reference.json', sha(raw))

    def test_package_cache_paths_are_read_from_the_pinned_configuration(self):
        config = self.root/'.dart_tool/package_config.json'
        config.parent.mkdir()
        accepted = encoded({'packages': [{'rootUri': '../accepted cache/'}]})
        config.write_bytes(accepted)
        info = {
            'materials': {'arguments': {'downloads': '/downloads', 'sdkSourceWorkspace': '/sdk-source'}},
            'toolchain': {'flutterPath': '/flutter', 'macosSdk': {'path': '/sdk'}},
        }
        caches = package.protected_caches(self.root, info, package_config_sha256=sha(accepted))
        self.assertIn(self.root/'accepted cache', caches)
        config.write_bytes(encoded({'packages': [{'rootUri': '../different cache/'}]}))
        with self.assertRaisesRegex(ValueError, 'Frozen workspace package configuration'):
            package.protected_caches(self.root, info, package_config_sha256=sha(accepted))

    def test_upstream_receipt_rejects_incomplete_or_mixed_inputs(self):
        source = {'sourceCheckout': '/candidate', 'sourceCommit': 'frozen',
                  'buildRun': 'build/phase-1e4/run-001', 'identity': {'appBuild': '8'}}
        original = {
            'formatVersion': 1, 'command': 'package', 'status': 'PASS',
            **dict.fromkeys(signing.UPSTREAM_GATES, 'PASS'), **source,
            'archive': {'sha256': 'archive-pin'}, 'packageInfo': {'sha256': 'manifest-pin'},
            'stage': '/package/stage/release',
        }
        current = {**original, 'command': 'check', 'originalPackageReceiptSha256': 'original-pin'}
        signing.matching_package_receipts(original, current, source, 'original-pin')
        for key, value in (
            ('status', 'INCOMPLETE'), ('vmAppStatus', 'NOT_RUN'), ('postRuntimeIntegrityStatus', 'FAIL'),
            ('buildRun', 'build/phase-1e4/run-002'), ('sourceCommit', 'drift'), ('formatVersion', True),
            ('originalPackageReceiptSha256', 'other-pin'), ('archive', {'sha256': 'other'}),
        ):
            with self.subTest(key=key), self.assertRaises(ValueError):
                signing.matching_package_receipts(original, {**current, key: value}, source, 'original-pin')

    def test_evidence_cannot_point_outside_selected_root(self):
        outside = self.root/'receipt.json'
        outside.write_bytes(b'{}')
        scope = self.root/'scope'
        scope.mkdir()
        with self.assertRaisesRegex(ValueError, 'outside its selected root'):
            signing.evidence_json(scope, {'path': str(outside), 'sha256': sha(b'{}')})

    def test_material_scope_rejects_payload_drift_even_with_a_new_manifest(self):
        library = self.root/'materials/lib.txt'
        library.parent.mkdir()
        library.write_text('accepted source')
        (self.root/'Meshchan.app').mkdir()
        (self.root/'Meshchan.app/runner').write_bytes(b'original program')
        expected = product_inventory(self.root)
        (self.root/'Meshchan.app/runner').write_bytes(b'resealed program')
        (self.root/'signed-product-info.json').write_bytes(encoded(product_inventory(self.root)))
        self.assertNotIn('signed-product-info.json', signing.signed_payload(self.root, expected))
        library.write_text('unrelated source')
        (self.root/'signed-product-info.json').write_bytes(encoded(product_inventory(self.root)))
        with self.assertRaisesRegex(ValueError, 'materials/lib.txt'):
            signing.signed_payload(self.root, expected)

    def test_vm_receipt_binds_current_guest_signed_manifest_and_strict_exit_types(self):
        relocated = self.root/'relocated products'
        path = self.root/'runtime.json'
        inventory = {'Meshchan.app': package.DIR}
        info = {'payloadInventory': inventory, 'identity': {'appBuild': '8'},
                'signature': {'identity': {'team': 'SIGNERTEAM'}}}
        manifest = encoded(info)
        candidate = {'guestRun': 'current-run', 'status': 'PASS'}
        report = {
            **candidate, 'status': 'PASS', 'app': str(relocated/'Meshchan.app'),
            'signedInfoSha256': sha(manifest), 'identity': info['identity'],
            'appInventorySha256': sha(encoded({'.': package.DIR})),
            'guestInventoryBefore': 'PASS', 'guestInventoryAfter': 'PASS', 'guestSignature': 'PASS',
            'guestSigningIdentity': info['signature']['identity'], 'guestSignatureAfter': 'PASS',
            'guestObserverTransfer': 'PASS', 'guestObserverAfter': 'PASS',
            'guestExecutorExit': 0, 'guestLockReleased': True,
        }
        path.write_bytes(encoded(report))
        candidate['receiptSha256'] = sha(encoded(report))
        with patch('release_signed_runtime.verify_vm_runtime_evidence') as verify_runtime:
            signing.vm_report(self.root, path, candidate, relocated, info, manifest)
        verify_runtime.assert_called_once_with(report, self.root, {'.': package.DIR})
        with self.assertRaisesRegex(ValueError, 'Signed VM entry status'):
            signing.vm_report(self.root, path, {**candidate, 'status': 'FAIL'}, relocated, info, manifest)
        for key, value in (('guestRun', 'old-run'), ('signedInfoSha256', 'old-pin'),
                           ('guestObserverAfter', 'NOT_RUN'), ('guestSigningIdentity', {'team': 'OTHER'}),
                           ('guestExecutorExit', False), ('guestExecutorExit', 0.0), ('guestLockReleased', 1)):
            wrong = deepcopy(report)
            wrong[key] = value
            path.write_bytes(encoded(wrong))
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                signing.vm_report(self.root, path, {**candidate, 'receiptSha256': sha(encoded(wrong))},
                                  relocated, info, manifest)
        with self.assertRaisesRegex(ValueError, 'Bound JSON SHA-256'):
            signing.vm_report(self.root, path, candidate, relocated, info, manifest)

    def test_no_identity_is_blocked_without_signing_commands(self):
        args = Mock(identity=None, expected_team=None)
        runner = Mock()
        runner.command.return_value = '     0 valid identities found\n'
        with self.assertRaisesRegex(signing.Blocked, 'No valid Developer ID Application'):
            signing.selection(args, Mock(), runner)
        runner.command.assert_called_once_with(
            'signing-identities', ['/usr/bin/security', 'find-identity', '-p', 'codesigning', '-v'])

    def test_replacement_cli_marker_must_match_the_bound_launcher_pid(self):
        from release_signed_replacement import APP_EMPTY, MARKER_START

        workspace = self.root/'user modified products'
        evidence = workspace/'evidence'
        evidence.mkdir(parents=True)
        marker = MARKER_START+'a'*32
        manifest = encoded({})
        fields = {'status': 'PASS', 'exitCode': 0}
        cli = {**fields, 'markerPid': 501, 'result': {'schemaVersion': 1, 'command': 'ports', 'ports': []}}
        for field, name, contents in (
            ('log', 'evidence/cli.log', encoded(cli['result'])),
            ('stderrLog', 'evidence/cli.stderr.log', f'{marker}:501\n'.encode()),
            ('pidReceipt', 'cli working directory/child.pid', b'502\n'),
        ):
            target = workspace/name
            target.parent.mkdir(exist_ok=True)
            target.write_bytes(contents)
            cli.update({field: name, field+'Sha256': sha(contents)})
        report = {
            'formatVersion': 1, 'status': 'PASS', 'signedInfoSha256': sha(manifest), 'identity': {},
            'signedRoot': str(self.root), 'finalIntegrity': 'PASS', 'marker': marker, 'cli': cli,
            'app': {**fields, 'guestExecutorExit': 0, 'guestLockReleased': True, 'pidAbsent': True,
                    'inventoryBefore': 'PASS', 'inventoryAfter': 'PASS', 'result': APP_EMPTY},
        }
        path = evidence/'replacement-receipt.json'
        path.write_bytes(encoded(report))
        result = {'status': 'PASS', 'receipt': str(path), 'receiptSha256': sha(encoded(report))}
        with self.assertRaisesRegex(ValueError, 'current-run libserialport invocation marker'):
            signing.replacement_report(workspace, result, self.root, {'identity': {}}, manifest, Mock(), (), Mock())

    def test_replacement_guest_evidence_binds_the_owned_run_and_refresh_transition(self):
        from release_signed_replacement import (
            APP_BINARY, APP_EMPTY, APP_LIBRARY, APP_NOT_REFRESHED, CLI_BINARY, CLI_LIBRARY, MARKER_START,
        )

        workspace = self.root/'replacement'
        copies = workspace/'user products'
        for name in (APP_BINARY, APP_LIBRARY, CLI_BINARY, CLI_LIBRARY):
            path = copies/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(name.encode())
        inventory = product_inventory(copies)
        manifest = encoded({})
        marker = MARKER_START+'a'*32
        guest_run = '20261121T010203Z-product-500'
        receipt_path = workspace/'evidence/replacement-receipt.json'
        fields = {'status': 'PASS', 'exitCode': 0}
        cli = {**fields, 'markerPid': 501, 'result': {'schemaVersion': 1, 'command': 'ports', 'ports': []}}
        for field, name, contents in (
            ('log', 'evidence/cli.log', encoded(cli['result'])),
            ('stderrLog', 'evidence/cli.stderr.log', f'{marker}:501\n'.encode()),
            ('pidReceipt', 'cli working directory/child.pid', b'501\n'),
        ):
            target = workspace/name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(contents)
            cli.update({field: name, field+'Sha256': sha(contents)})
        shutdown = {'runtime': 'meshchan.shutdown.1d3', 'owner': 'released', 'quitPhase': 'ready',
                    'resourcesReleased': True, 'workerExited': True, 'workerWasSpawned': True, 'error': None,
                    'pendingRequests': 0, 'receivePorts': 0, 'maintenanceFailureCount': 0}
        session = {'run': guest_run, 'lockIdentity': '10:49', 'products': {'Release': {
            'pid': 502, 'root': '/Users/tester/utm-ui-isolation/products/'+guest_run+'-Release',
            'sourceApp': str(copies/'Meshchan.app'), 'executableSha256': inventory[APP_BINARY]['sha256'],
        }}}
        snapshots = {'before': [{'value': APP_NOT_REFRESHED}], 'after': [{'value': APP_EMPTY}]}
        guest_files = {
            'session.json': encoded(session), 'refresh-state.json': encoded(snapshots),
            'Release/app.stdout': (json.dumps(shutdown)+'\n').encode(),
            'Release/app.stderr': f'{marker}:502\n'.encode(),
            'Release/app.pid': b'502\n', 'Release/app.exit': b'0\n',
            'Release/synthetic-ports.png': b64decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lZkAAAAASUVORK5CYII='),
        }
        expected_signatures = {CLI_BINARY: {'arm64': {'runtime': True}}}
        report = {
            'formatVersion': 1, 'status': 'PASS', 'signedInfoSha256': sha(manifest), 'identity': {},
            'signedRoot': str(self.root), 'finalIntegrity': 'PASS', 'marker': marker, 'cli': cli,
            'modifiedInventorySha256': sha(encoded(inventory)),
            'replacement': {
                'libraries': {name: {'signedReplacementSha256': inventory[name]['sha256']}
                              for name in (APP_LIBRARY, CLI_LIBRARY)},
                'localSignatures': expected_signatures,
            },
            'app': {**fields, 'guestExecutorExit': 0, 'guestLockReleased': True, 'pidAbsent': True,
                    'inventoryBefore': 'PASS', 'inventoryAfter': 'PASS', 'result': APP_EMPTY, 'pid': 502,
                    'guestRun': guest_run, 'guestLibrarySha256': inventory[APP_LIBRARY]['sha256'],
                    'appInventorySha256': sha(encoded(signing.inventory_part(inventory, 'Meshchan.app'))),
                    'shutdown': shutdown},
        }
        signer = Mock()
        signer.verify_transform.return_value = {'changedFiles': []}
        command = Mock()

        def verify(files):
            for name, contents in files.items():
                path = workspace/'evidence/app-vm'/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(contents)
            report['app']['evidence'] = {name: sha(contents) for name, contents in files.items()}
            raw = encoded(report)
            receipt_path.write_bytes(raw)
            reply = {'status': 'PASS', 'receipt': str(receipt_path), 'receiptSha256': sha(raw)}
            return signing.replacement_report(workspace, reply, self.root, {'identity': {}}, manifest, signer, (),
                                              command)

        with patch('release_signed_replacement.verify_local_signatures', return_value=expected_signatures) as observe:
            self.assertEqual(str(receipt_path), verify(guest_files)['path'])
            observe.assert_called_once_with(copies, (), command, prefix='replacement-final')
        for unexpected_runtime in (False, 1):
            stale_signatures = {CLI_BINARY: {'arm64': {'runtime': unexpected_runtime}}}
            with (self.subTest(runtime=unexpected_runtime),
                  patch('release_signed_replacement.verify_local_signatures', return_value=stale_signatures),
                  self.assertRaisesRegex(ValueError, 'User replacement local signature evidence')):
                verify(guest_files)

        def drift_during_verification(*_args, **_kwargs):
            (copies/CLI_BINARY).write_bytes(b'different local signature bytes')
            return expected_signatures

        with (patch('release_signed_replacement.verify_local_signatures', side_effect=drift_during_verification),
              self.assertRaisesRegex(ValueError, CLI_BINARY)):
            verify(guest_files)
        (copies/CLI_BINARY).write_bytes(CLI_BINARY.encode())
        stale = deepcopy(session)
        stale['products']['Release']['root'] = '/Users/tester/utm-ui-isolation/products/old-run-Release'
        wrong_root = deepcopy(session)
        wrong_root['products']['Release']['root'] = '/tmp/products/'+guest_run+'-Release'
        for name, contents, message in (
            ('session.json', encoded(stale), 'guest product path'),
            ('session.json', encoded(wrong_root), 'guest product path'),
            ('session.json', encoded({**session, 'lockIdentity': None}), 'guest lock identity'),
            ('refresh-state.json', encoded({**snapshots, 'before': [{'value': APP_EMPTY}]}), 'Refresh transition'),
            ('Release/synthetic-ports.png', b'', 'PNG framing'),
        ):
            with self.subTest(name=name, message=message), self.assertRaisesRegex(ValueError, message):
                verify({**guest_files, name: contents})

    def test_keychain_interaction_blocks_and_timestamp_failure_never_seals(self):
        signer, runner = Mock(), Mock()
        upstream = Mock(top='meshchan')
        for error, expected in (
            (b'User interaction is not allowed.', signing.Blocked),
            (b'The timestamp service is not available.', subprocess.CalledProcessError),
        ):
            signer.sign_products.side_effect = subprocess.CalledProcessError(1, 'codesign', stderr=error)
            record = {}
            with patch.object(signing, 'selection', return_value={}), patch.object(signing, 'copy_source'):
                with self.subTest(error=error), self.assertRaises(expected):
                    signing.sign(Mock(), upstream, self.root, self.root, runner, record, {}, signer, ())
            self.assertEqual('RUNNING', record['signatureStatus'])
            self.assertFalse((self.root/'signed').exists())
        signer.verify_signatures.assert_not_called()

    def test_sealing_uses_the_inventory_from_before_signature_verification(self):
        output = self.root
        product = output/'in-progress'/'Meshchan.app'/'runner'
        product.parent.mkdir(parents=True)
        product.write_bytes(b'current signed binary')
        signer, runner = Mock(), Mock()
        signer.discover_code.return_value = []
        signer.verify_signatures.return_value = []
        signer.verify_transform.return_value = {}
        runner.interrupted = None
        original = product_inventory(product.parent.parent)

        def mutate_after_verification(*args):
            product.write_bytes(b'unexpected new binary')
            return {}

        with (patch.object(signing, 'selection', return_value={}), patch.object(signing, 'copy_source'),
              patch.object(signing, 'source_payload', return_value=original),
              patch.object(signing, 'candidate_fields', return_value={}),
              patch.object(signing, 'native_report', side_effect=mutate_after_verification),
              patch.object(signing, 'require_original'),
              patch.object(signing, 'tool_identity', return_value={})):
            with self.assertRaisesRegex(ValueError, 'Meshchan.app/runner'):
                signing.sign(Mock(), Mock(top='fixture'), output, output, runner, {'environment': {}}, {}, signer, ())
        self.assertFalse((output/'signed').exists())

    def test_sealing_rejects_a_manifest_that_differs_from_the_produced_bytes(self):
        product = self.root/'in-progress'/'Meshchan.app'/'runner'
        product.parent.mkdir(parents=True)
        product.write_bytes(b'product')
        original = product_inventory(product.parent.parent)
        signer, runner = Mock(), Mock(interrupted=None)
        signer.discover_code.return_value = []
        signer.verify_signatures.return_value = []
        signer.verify_transform.return_value = {}
        write = signing.build.write

        def write_changed_manifest(path, value):
            write(path, {**value, 'signingEnvironment': {'architecture': 'unverified'}})

        with (patch.object(signing, 'selection', return_value={}), patch.object(signing, 'copy_source'),
              patch.object(signing, 'source_payload', return_value=original),
              patch.object(signing, 'candidate_fields', return_value={}),
              patch.object(signing, 'native_report', return_value={}), patch.object(signing, 'require_original'),
              patch.object(signing, 'tool_identity', return_value={}),
              patch.object(signing.build, 'write', side_effect=write_changed_manifest)):
            with self.assertRaisesRegex(ValueError, 'signed-product-info.json'):
                signing.sign(Mock(), Mock(top='fixture'), self.root, self.root, runner,
                             {'environment': {'architecture': 'arm64'}}, {}, signer, ())
        self.assertFalse((self.root/'signed').exists())

    def test_published_report_reference_binds_the_written_object(self):
        path = self.root/'prepared-inventory.json'
        value = {'file': {'size': 12}}
        reference = signing.publish_json(self.root, path, value)
        self.assertEqual({'path': path.name, 'sha256': sha(encoded(value))}, reference)
        write = signing.build.write

        def write_changed_report(destination, _value):
            write(destination, {'file': {'size': 34}})

        with patch.object(signing.build, 'write', side_effect=write_changed_report):
            with self.assertRaisesRegex(ValueError, 'Published prepared-inventory.json'):
                signing.publish_json(self.root, path, value)

    def test_preparation_fails_on_drift_and_keeps_receipts_in_owned_evidence(self):
        for change in ('prepared file', 'prepared evidence', 'evidence directory'):
            with self.subTest(change=change):
                output = self.root/change
                upstream = Mock(protected=(), provenance={}, info={'identity': {}})
                args = Mock(command='prepare', output=output)

                def create_copy(prepared, _upstream, _tools):
                    prepared.mkdir()
                    (prepared/'fixture').write_bytes(b'prepared bytes')
                    return product_inventory(prepared)

                def disturb_at_final_check(*args):
                    if change == 'prepared file':
                        (output/'prepared/fixture').write_bytes(b'changed bytes')
                    elif change == 'prepared evidence':
                        (output/'evidence/prepared-native.json').write_bytes(encoded({'foreign': True}))
                    else:
                        (output/'evidence').rename(output/'owned evidence')
                        (output/'evidence').mkdir()

                with (patch.object(signing, 'output_path', return_value=output),
                      patch.object(signing.platform, 'system', return_value='Darwin'),
                      patch.object(signing.platform, 'machine', return_value='arm64'),
                      patch.object(signing, 'read_upstream', return_value=upstream),
                      patch.object(signing, 'platform_identity', return_value={}),
                      patch.object(signing, 'tool_identity', return_value={}),
                      patch.object(signing, 'copy_source', side_effect=create_copy),
                      patch.object(signing, 'native_report', return_value={}),
                      patch.object(signing, 'require_original', side_effect=disturb_at_final_check),
                      patch('release_signing.discover_code', return_value=[])):
                    with self.assertRaisesRegex(ValueError, 'fixture|prepared-native.json|owned root'):
                        signing.run(args)
                if change != 'evidence directory':
                    receipt = json.loads((output/'evidence/signing-receipt.json').read_bytes())
                    self.assertEqual('FAIL', receipt['status'])
                else:
                    self.assertEqual([], list((output/'evidence').iterdir()))
                    self.assertTrue((output/'owned evidence/signing-receipt.json').is_file())

    def test_signing_new_run_rejects_symlink_and_existing_case_alias(self):
        parent = self.root/'build/phase-1e6'
        parent.mkdir(parents=True)
        (parent/'Run-One').mkdir()
        (parent/'shortcut').symlink_to(self.root, target_is_directory=True)
        with patch.object(signing, 'ROOT', self.root), patch.object(package, 'git', side_effect=['', 'ignored', '', 'ignored']):
            with self.assertRaisesRegex(ValueError, 'canonical path'):
                signing.output_path(parent/'shortcut', new=True)
            with self.assertRaisesRegex(ValueError, 'fresh output'):
                signing.output_path(parent/'Run-One', new=True)
            if (parent/'run-one').exists():
                with self.assertRaisesRegex(ValueError, 'fresh output'):
                    signing.output_path(parent/'run-one', new=True)


if __name__ == '__main__':
    unittest.main()
