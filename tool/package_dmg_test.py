"""Focused tests for local candidate layout, image identity, and mount ownership."""
from contextlib import chdir, contextmanager
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import package_dmg as dmg
import package_dmg_image as disk
import package_release as package
from release_materials import encoded, product_inventory, sha


class LayoutTests(unittest.TestCase):
    HOST_PATH = '/'+'/'.join(('Users', 'release-builder', 'local'))

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.candidate = self.root/'accepted candidate'
        self.candidate.mkdir()
        for name, value in {
            'Meshchan.app/Contents/MacOS/Meshchan': b'app',
            'meshctl/bin/meshctl': b'cli',
            'meshctl/lib/runtime.dylib': b'library',
            'materials/corresponding-source.tar': b'source',
            'provenance/build-info.json': b'build',
            'signed-product-info.json': b'signed manifest',
        }.items():
            path = self.candidate/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(value)
        (self.candidate/'Meshchan.app/Contents/MacOS/libexec').symlink_to('Meshchan')
        (self.candidate/'provenance/build-info.json').chmod(0o600)
        (self.candidate/'meshctl/bin/meshctl').chmod(0o755)
        (self.candidate/'meshctl/lib').chmod(0o700)
        self.inventory = product_inventory(self.candidate)
        self.info = {'identity': {'appBuild': '8', 'productVersion': '0.1.0-rc.1', 'target': 'macos-arm64'},
                     'upstream': {'sourceCommit': '1'*40}, 'signingTool': {'gitCommit': '2'*40}}
        self.args = SimpleNamespace(candidate_sha256='a'*64, acceptance_sha256='b'*64)
        self.tools = {'tool/helper.py': package.bytes_entry(b'helper')}
        self.contents = {'dmg-source/tool/helper.py': b'helper'}
        self.identity = {'gitCommit': 'c'*40, 'inputs': self.tools, 'workingTree': []}
        self.layout = dmg.layout(self.inventory, self.info, self.args, self.contents, self.identity)
        self.staging = self.root/'staging payload'
        dmg.stage(self.staging, self.candidate, self.layout)
        self.top = self.staging/self.layout.manifest['candidatePath']

    def expected(self, **changes):
        inputs = {'full': self.inventory, 'info': self.info, 'args': self.args,
                  'entries': self.tools, 'contents': self.contents, **changes}
        return dmg.mounted_layout(self.staging, **inputs)

    def test_complete_staging_preserves_modes_bytes_and_links(self):
        self.assertEqual(self.expected(), self.layout)
        self.assertEqual(product_inventory(self.top), self.inventory)
        self.assertEqual(self.layout.manifest['inventoryExclusions'], [dmg.IMAGE_MANIFEST])
        self.assertEqual(self.layout.manifest['image']['filename'],
                         'Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg')
        self.assertEqual(self.layout.manifest['signingProfile'], 'local-adhoc')
        self.assertEqual(self.layout.manifest['containerCodeSignature'], 'UNSIGNED')
        self.assertEqual(self.layout.manifest['productCodeSignature'], 'AD_HOC')
        self.assertEqual(self.layout.manifest['appleNotarization'], 'NOT_APPLICABLE')

    def test_missing_payload_and_unknown_hidden_entries_fail(self):
        for name in ('Meshchan.app/Contents/MacOS/libexec', 'meshctl/lib/runtime.dylib',
                     'materials/corresponding-source.tar'):
            with self.subTest(name=name):
                path = self.top/name
                removed = self.root/'removed'
                path.rename(removed)
                with self.assertRaisesRegex(ValueError, 'differs'):
                    dmg.check_layout(self.staging, self.layout)
                removed.rename(path)
        (self.staging/'.unknown').write_text('unexpected')
        with self.assertRaisesRegex(ValueError, r'\.unknown'):
            dmg.check_layout(self.staging, self.layout)
        self.assertEqual(product_inventory(self.candidate), self.inventory)

    def test_payload_bytes_root_mode_directory_mode_and_raw_link_are_checked(self):
        cli = self.top/'meshctl/bin/meshctl'
        cli.write_bytes(b'bad')
        with self.assertRaisesRegex(ValueError, 'meshctl/bin/meshctl'):
            dmg.check_layout(self.staging, self.layout)
        cli.write_bytes(b'cli')

        for path in (self.staging, self.top, self.top/'meshctl/lib'):
            mode = path.stat().st_mode
            path.chmod(0o755 if mode & 0o777 != 0o755 else 0o700)
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, 'differs'):
                dmg.check_layout(self.staging, self.layout)
            path.chmod(mode)

        link = self.top/'Meshchan.app/Contents/MacOS/libexec'
        link.unlink()
        link.symlink_to('./Meshchan')
        with self.assertRaisesRegex(ValueError, 'libexec'):
            dmg.check_layout(self.staging, self.layout)
        link.unlink()
        link.symlink_to(self.candidate/'Meshchan.app/Contents/MacOS/Meshchan')
        with self.assertRaisesRegex(ValueError, 'Absolute product symlink'):
            dmg.check_layout(self.staging, self.layout)
        self.assertEqual(product_inventory(self.candidate), self.inventory)

    def test_manifest_hash_recomputation_cannot_replace_upstream_inputs(self):
        for key in ('candidate_sha256', 'acceptance_sha256'):
            with self.subTest(pin=key):
                arg = SimpleNamespace(**{**vars(self.args), key: 'f'*64})
                with self.assertRaisesRegex(ValueError, 'payload manifest'):
                    self.expected(args=arg)
        with self.assertRaisesRegex(ValueError, 'DMG source inputs'):
            self.expected(entries={'tool/helper.py': package.bytes_entry(b'new tool')})
        record = self.staging/dmg.IMAGE_MANIFEST
        manifest = json.loads(record.read_bytes())
        del manifest['inventory'][self.layout.manifest['candidatePath']+'/materials/corresponding-source.tar']
        record.write_bytes(encoded(manifest))
        with self.assertRaisesRegex(ValueError, 'payload manifest'):
            self.expected()

    def test_source_file_mode_is_precise(self):
        path = self.staging/'dmg-source/tool/helper.py'
        path.chmod(0o600)
        with self.assertRaisesRegex(ValueError, 'dmg-source/tool/helper.py'):
            dmg.check_layout(self.staging, self.layout)

    def public_fixture(self, *, recipe=57):
        source = 'source-materials/archives/libserialport_plus-1.0.5.tar.gz'
        members = {
            source: b'original source archive',
            'licenses/meshchan/LICENSE': b'license',
            'rebuild/README.md': b'instructions',
            'THIRD_PARTY_NOTICES.md': b'notices',
            'evidence/serial/app-stdout.log': b'private test log',
        }
        material_entries = {}
        for name, data in members.items():
            path = self.candidate/'materials'/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            material_entries[name] = {'size': len(data), 'sha256': sha(data),
                                      'originalPath': self.HOST_PATH+'/'+name}
        # This is the fixture for the signed inventory's allowed subtrees.
        (self.candidate/'materials/corresponding-source.tar').unlink()
        diagnostics = self.candidate/'upstream-provenance'
        diagnostics.mkdir()
        (diagnostics/'package-check-receipt.json').write_text(self.HOST_PATH+'/case')
        materials = {
            **self.info['identity'], 'sourceCommit': '1'*40, 'lockSha256': '4'*64,
            'openGates': [], 'materials': material_entries,
            'native': {'meshctl': {'libserialport_plus': {
                'loader': ['\t'+dmg.CLI_SERIAL_INSTALL_NAME
                           +' (compatibility version 0.0.0, current version 0.0.0)',
                           self.HOST_PATH+'/private-tool.dylib'],
                'sections': {'16777228': {'__TEXT/__text': '6'*64}},
                'matches': [self.HOST_PATH+'/hook-output.dylib'],
            }}},
        }
        raw = encoded(materials)
        (self.candidate/dmg.MATERIAL_MANIFEST).write_bytes(raw)
        self.info.update({
            'formatVersion': 2, 'signingProfile': dmg.PROFILE,
            'signature': {'identity': {'adHoc': True}, 'items': []},
            'policy': {'path': 'tool/release_signing_policy.json', 'sha256': '9'*64},
            'inventoryExclusions': [dmg.SIGNED_MANIFEST],
        })
        self.info['upstream'].update({
            'materialsManifestSha256': sha(raw), 'buildRecipeVersion': recipe, 'buildInfoSha256': '5'*64,
            'sourceCheckout': self.HOST_PATH+'/source',
            'packageRun': self.HOST_PATH+'/packaging',
        })
        return source, raw, product_inventory(self.candidate)

    def test_public_image_uses_pinned_materials_and_does_not_copy_private_evidence(self):
        archive, raw, original = self.public_fixture()
        public = dmg.public_candidate(self.info, original, raw, self.args.candidate_sha256)
        public_layout = dmg.layout(original, self.info, self.args, self.contents, self.identity, public=public)
        staging = self.root/'public staging'
        dmg.stage(staging, self.candidate, public_layout, public=public)
        mounted = dmg.mounted_layout(staging, original, self.info, self.args, self.tools,
                                     self.contents, public=public)
        self.assertEqual(mounted, public_layout)
        self.assertEqual(mounted.manifest['signedInfoSha256'], sha(public.manifest))
        self.assertEqual(mounted.manifest['privateSignedInfoSha256'], self.args.candidate_sha256)
        self.assertEqual(mounted.manifest['payloadProfile'], dmg.PUBLIC_PAYLOAD)
        volume_readme = staging/'README-engineering.md'
        self.assertEqual(volume_readme.read_bytes(), dmg.PUBLIC_VOLUME_README)
        self.assertNotIn(b'accepted build and signing records', volume_readme.read_bytes())
        self.assertEqual(mounted.inventory[volume_readme.name], package.bytes_entry(dmg.PUBLIC_VOLUME_README))
        top = staging/mounted.manifest['candidatePath']
        self.assertEqual((top/'materials'/archive).read_bytes(), b'original source archive')
        self.assertEqual((top/'Meshchan.app/Contents/MacOS/Meshchan').read_bytes(), b'app')
        self.assertEqual((top/'meshctl/bin/meshctl').read_bytes(), b'cli')
        for name in ('materials/evidence', 'provenance', 'upstream-provenance'):
            self.assertFalse((top/name).exists())
            self.assertTrue((self.candidate/name).exists())
        for path in (top/dmg.SIGNED_MANIFEST, top/dmg.MATERIAL_MANIFEST, staging/dmg.IMAGE_MANIFEST):
            self.assertNotIn(self.HOST_PATH.encode(), path.read_bytes())
        materials = json.loads((top/dmg.MATERIAL_MANIFEST).read_bytes())
        self.assertEqual(materials['materials'][archive], {'size': 23, 'sha256': sha(b'original source archive')})
        original_serial = json.loads(raw)['native']['meshctl']['libserialport_plus']
        self.assertEqual(materials['native'], {'meshctl': {'libserialport_plus': {
            'loader': [original_serial['loader'][0].strip()], 'sections': original_serial['sections'],
        }}})
        self.assertEqual(product_inventory(self.candidate), original)
        with self.assertRaisesRegex(ValueError, 'payload manifest'):
            dmg.mounted_layout(staging, original, self.info, self.args, self.tools, self.contents)

    def test_historical_public_volume_readme_reconstructs_byte_for_byte(self):
        _, raw, original = self.public_fixture(recipe=56)
        public = dmg.public_candidate(self.info, original, raw, self.args.candidate_sha256)
        legacy = dmg.layout(original, self.info, self.args, self.contents, self.identity, public=public)
        staging = self.root/'historical public staging'
        dmg.stage(staging, self.candidate, legacy, public=public)
        self.assertEqual((staging/'README-engineering.md').read_bytes(), dmg.README)
        self.assertEqual(sha(dmg.README), '2c80047c788ab3d1314554c0a30e57980551aca77e981a066283b4581e2aee99')
        self.assertEqual(legacy.inventory['README-engineering.md'], package.bytes_entry(dmg.README))
        self.assertEqual(dmg.mounted_layout(staging, original, self.info, self.args, self.tools,
                                           self.contents, public=public), legacy)
        self.info['upstream']['buildRecipeVersion'] = 57
        private = dmg.layout(original, self.info, self.args, self.contents, self.identity)
        self.assertEqual(private.outliers['README-engineering.md'], dmg.README)
        with self.assertRaisesRegex(ValueError, 'payload manifest'):
            dmg.mounted_layout(staging, original, self.info, self.args, self.tools,
                               self.contents, public=public)

    def test_public_projection_rejects_unbound_material_bytes(self):
        archive, raw, original = self.public_fixture()
        with self.assertRaisesRegex(ValueError, 'material manifest bytes'):
            dmg.public_candidate(self.info, original, raw+b' ', self.args.candidate_sha256)
        key = 'materials/'+archive
        original[key] = {**original[key], 'sha256': '7'*64}
        with self.assertRaisesRegex(ValueError, 'Public material inventory'):
            dmg.public_candidate(self.info, original, raw, self.args.candidate_sha256)

    def test_retention_replays_both_pinned_v1_public_projections(self):
        _, raw, original = self.public_fixture()
        private_pin = self.args.candidate_sha256
        current = dmg.public_candidate(self.info, original, raw, private_pin)
        current_pin = sha(current.manifest)
        legacy_materials = json.loads(current.generated[dmg.MATERIAL_MANIFEST])
        del legacy_materials['native']
        legacy_bytes = encoded(legacy_materials)
        legacy_info = {**current.info, 'payloadInventory': {
            **current.info['payloadInventory'], dmg.MATERIAL_MANIFEST: package.bytes_entry(legacy_bytes),
        }}
        legacy_manifest = encoded(legacy_info)

        self.assertEqual(current, dmg.public_candidate(self.info, original, raw, private_pin,
                                                       retained_public_pin=current_pin))
        legacy = dmg.public_candidate(self.info, original, raw, private_pin,
                                      retained_public_pin=sha(legacy_manifest))
        self.assertEqual(legacy.manifest, legacy_manifest)
        self.assertEqual(legacy.generated[dmg.MATERIAL_MANIFEST], legacy_bytes)
        with self.assertRaisesRegex(ValueError, 'Retained public signed manifest pin'):
            dmg.public_candidate(self.info, original, raw, private_pin, retained_public_pin='0'*64)

    def test_public_serial_binding_rejects_paths_in_replacement_fields(self):
        _, raw, original = self.public_fixture()
        for invalid in ({'loader': [self.HOST_PATH+'/lib.dylib']},
                        {'sections': {'16777228': {self.HOST_PATH: '6'*64}}}):
            with self.subTest(invalid=invalid):
                materials = json.loads(raw)
                materials['native']['meshctl']['libserialport_plus'].update(invalid)
                tampered = encoded(materials)
                self.info['upstream']['materialsManifestSha256'] = sha(tampered)
                original[dmg.MATERIAL_MANIFEST] = package.bytes_entry(tampered)
                with self.assertRaisesRegex(ValueError, 'Public CLI serial binding'):
                    dmg.public_candidate(self.info, original, tampered, self.args.candidate_sha256)

    def test_image_checks_extracted_signatures_before_detach_and_detaches_on_failure(self):
        signatures = [{'path': 'Meshchan.app'}]
        info = {**self.info, 'signature': {'identity': {'adHoc': True}, 'items': signatures}}
        image = self.root/'image.dmg'
        image.write_bytes(b'fixture')
        stamp = package.file_stamp(image)
        evidence = self.root/'evidence'
        evidence.mkdir()
        runner = SimpleNamespace(command=object())
        policy = object()

        @contextmanager
        def mount_fixture(_runner, _image, _stamp, mount, _name, record):
            self.staging.rename(mount)
            try:
                yield mount
            finally:
                mount.rename(self.staging)
                record['detachStatus'] = 'PASS'

        for valid in (True, False):
            with self.subTest(valid=valid):
                record = {}
                workspace = self.root/str(valid)
                workspace.mkdir()
                mount = workspace/'readonly volume'
                extracted = workspace/'extracted payload'
                candidate = extracted/self.layout.manifest['candidatePath']

                def verify(root, selected_policy, identity, command, scratch):
                    self.assertEqual(root, candidate)
                    self.assertIs(selected_policy, policy)
                    self.assertEqual(identity, info['signature']['identity'])
                    self.assertIs(command, runner.command)
                    self.assertEqual(scratch, evidence)
                    self.assertEqual(product_inventory(root), self.inventory)
                    self.assertTrue(mount.is_dir())
                    self.assertNotIn('detachStatus', record)
                    return signatures if valid else []

                with (patch.object(disk, 'mounted_image', mount_fixture),
                      patch.object(disk, 'verify_image', return_value={}),
                      patch.object(dmg.signing, 'verify_signatures', side_effect=verify) as check):
                    def accept():
                        return dmg.accept_image(
                            image, stamp, workspace, evidence, self.inventory, info, self.args,
                            self.tools, self.contents, runner, record, policy=policy, expected=self.layout)
                    if valid:
                        self.assertEqual(accept()[3], signatures)
                        self.assertEqual(record['signatureStatus'], 'PASS')
                    else:
                        with self.assertRaisesRegex(ValueError, 'Ad hoc signatures after image extraction'):
                            accept()
                        self.assertNotIn('payloadManifest', record)
                check.assert_called_once()
                self.assertEqual(record['detachStatus'], 'PASS')
                self.assertFalse(mount.exists())

    def test_cli_runtime_writes_only_beside_the_extracted_payload(self):
        def write_fixture(bundle, workspace, runner, version):
            self.assertEqual(bundle, self.top/'meshctl')
            self.assertEqual(version, self.info['identity']['productVersion'])
            workspace.mkdir()
            (workspace/'draft.sqlite').write_bytes(b'owned runtime fixture')
            raise ValueError('End of CLI fixture')

        with patch.object(dmg.runtime, 'accept_cli', side_effect=write_fixture):
            with self.assertRaisesRegex(ValueError, 'End of CLI fixture'):
                dmg.bind_runtime(self.root/'run', self.root/'evidence', self.top, self.info,
                                 b'manifest', None, None, {}, workspace=self.root)
        dmg.check_layout(self.staging, self.layout)
        self.assertEqual((self.root/'cli workspace/draft.sqlite').read_bytes(), b'owned runtime fixture')

    def test_external_workspace_disallows_checkout_alias_or_overlap(self):
        config = self.root/'vm.json'
        config.write_text('{"runtime_dir":"/private/tmp/vm-runtime-for-fixture"}')
        output = self.root/'run'
        receipt = self.root/'acceptance.json'
        upstream = SimpleNamespace(protected=())
        checkout = self.root/'checkout'
        checkout.mkdir()
        candidate = checkout/'signing/signed/product'
        candidate.mkdir(parents=True)
        alias = self.root/'alias'
        alias.symlink_to(checkout)
        accepted_workspace = self.root/'accepted workspace'
        accepted_workspace.mkdir()
        with patch.object(dmg, 'ROOT', checkout):
            for workspace, message in ((alias, 'canonical'), (checkout, 'overlaps'),
                                       (accepted_workspace, 'overlaps')):
                args = SimpleNamespace(command='check', vm_config=config, workspace_parent=workspace)
                with self.subTest(workspace=workspace), self.assertRaisesRegex(ValueError, message):
                    dmg.protect_inputs(output, args, upstream, candidate, receipt, accepted_workspace, None)
            args.workspace_parent = self.root
            owned, _ = dmg.protect_inputs(output, args, upstream, candidate, receipt, accepted_workspace, None)
        self.assertIn('Meshchan DMG check ', owned.name)
        self.assertFalse(owned.exists())

    def test_vm_configuration_path_is_resolved_from_invocation_directory_once(self):
        config = self.root/'vm.json'
        config.write_text('{"runtime_dir":"ci-runtime"}')
        checkout = self.root/'checkout'
        checkout.mkdir()
        # A second same-name file under the checkout must never be selected.
        (checkout/config.name).write_text('{}')
        candidate = checkout/'signing/signed/product'
        candidate.mkdir(parents=True)
        args = SimpleNamespace(command='check', vm_config=Path(config.name), workspace_parent=self.root)
        with (patch.object(dmg, 'ROOT', checkout),
              chdir(self.root),
              patch.object(dmg, 'checked_vm_configuration') as checked):
            _, _ = dmg.protect_inputs(self.root/'out', args, SimpleNamespace(protected=()), candidate,
                                     self.root/'receipt', self.root/'local workspace', None)
        self.assertEqual(checked.call_args.args[0], config)
        self.assertIn(config, checked.call_args.args[1])

    def test_workspace_creation_failure_is_recorded_without_overwriting_existing_files(self):
        existing = self.root/'unavailable workspace'
        existing.mkdir()
        (existing/'owned-by-another-run').write_text('preserve')
        output = self.root/'fresh receipt run'
        args = SimpleNamespace(**vars(self.args), command='create', timeout=10, output=output,
                               candidate=self.candidate, acceptance_receipt=self.root/'acceptance.json')
        with (patch.object(dmg.platform, 'system', return_value='Darwin'),
              patch.object(dmg.platform, 'machine', return_value='arm64'),
              patch.object(dmg, 'output_path', return_value=output),
              patch.object(dmg, 'protect_inputs', return_value=(existing, None)),
              patch.object(dmg.sign_release, 'accepted_upstream'),
              patch.object(dmg.sign_release, 'manifest_inventory'),
              patch.object(dmg.sign_release, 'read_local_acceptance',
                           return_value=(self.info, b'manifest', {'workspace': str(self.root)}))):
            with self.assertRaises(FileExistsError):
                dmg.run(args)
        receipt = json.loads((output/'image-record.json').read_bytes())
        self.assertEqual(receipt['status'], 'FAIL')
        self.assertEqual(receipt['workspaceStatus'], 'FAIL')
        self.assertEqual(receipt['stageStatus'], 'NOT_RUN')
        self.assertIn('FileExistsError', receipt['error'])
        self.assertEqual((existing/'owned-by-another-run').read_text(), 'preserve')

    def test_host_tools_use_owned_tmpdir_instead_of_inheriting_protected_input(self):
        workspace = self.root/'workspace for run'
        output = self.root/'fresh receipt run'
        args = SimpleNamespace(**vars(self.args), command='create', timeout=10, output=output,
                               candidate=self.candidate, acceptance_receipt=self.root/'acceptance.json')

        def inspect_environment(runner):
            self.assertEqual(runner.env['TMPDIR'], str(workspace))
            self.assertTrue(workspace.is_dir())
            raise ValueError('End of temporary-path fixture')

        with (patch.dict(os.environ, {'TMPDIR': str(self.candidate)}),
              patch.object(dmg.platform, 'system', return_value='Darwin'),
              patch.object(dmg.platform, 'machine', return_value='arm64'),
              patch.object(dmg, 'output_path', return_value=output),
              patch.object(dmg, 'protect_inputs', return_value=(workspace, None)),
              patch.object(dmg, 'environment', side_effect=inspect_environment),
              patch.object(dmg.sign_release, 'accepted_upstream'),
              patch.object(dmg.sign_release, 'manifest_inventory'),
              patch.object(dmg.sign_release, 'read_local_acceptance',
                           return_value=(self.info, b'manifest', {'workspace': str(self.root)}))):
            with self.assertRaisesRegex(ValueError, 'temporary-path fixture'):
                dmg.run(args)
        self.assertEqual(product_inventory(self.candidate), self.inventory)

    def test_evidence_digests_are_rechecked(self):
        stdout = self.root/'step.log'
        stderr = self.root/'step.stderr.log'
        stdout.write_bytes(b'good')
        stderr.write_bytes(b'')
        ledger = {'steps': [{'log': stdout.name, 'logSha256': sha(b'good'),
                             'stderrLog': stderr.name, 'stderrLogSha256': sha(b'')}]}
        dmg.verify_process_logs(self.root, ledger)
        ledger['steps'].append(ledger['steps'][0])
        with self.assertRaisesRegex(ValueError, 'repeated process evidence'):
            dmg.verify_process_logs(self.root, ledger)
        ledger['steps'].pop()
        ledger['steps'][0]['logSha256'] = None
        with self.assertRaisesRegex(ValueError, 'Missing or repeated process evidence'):
            dmg.verify_process_logs(self.root, ledger)
        ledger['steps'][0]['logSha256'] = sha(b'good')
        stdout.write_bytes(b'bad')
        with self.assertRaisesRegex(ValueError, 'Process evidence'):
            dmg.verify_process_logs(self.root, ledger)


class DetachCommandTests(unittest.TestCase):
    def test_native_detach_runs_even_with_unwritable_evidence(self):
        with tempfile.TemporaryDirectory(prefix='detach command test ') as directory:
            root = Path(directory).resolve()
            missing_evidence = root/'missing evidence'
            mount = root/'owned mount'
            argv = [disk.HDIUTIL, 'detach', str(mount)]
            runner = SimpleNamespace(receipt={'steps': []}, root=root, evidence=missing_evidence, env={}, timeout=9)
            result = subprocess.CompletedProcess(argv, 0, b'detached', b'')
            with patch.object(disk.subprocess, 'run', return_value=result) as command:
                with self.assertRaises(FileNotFoundError):
                    disk.detach_image(runner, mount)
            command.assert_called_once()
            self.assertEqual(command.call_args.args, (argv,))
            self.assertEqual(runner.receipt['steps'][0]['exitCode'], 0)
            self.assertIs(runner.receipt['steps'][0]['childReaped'], True)

    def test_native_detach_can_start_after_the_output_directory_disappears(self):
        with tempfile.TemporaryDirectory(prefix='detach after output loss ') as directory:
            root = Path(directory)
            output = root/'removed output'
            runner = SimpleNamespace(receipt={'steps': []}, root=output,
                                     evidence=output/'evidence', env={}, timeout=10)
            # Use a harmless real command to cover failure of subprocess launch's chdir.
            with patch.object(disk, 'HDIUTIL', '/usr/bin/true'):
                with self.assertRaises(FileNotFoundError):
                    disk.detach_image(runner, root/'owned mount')
            step = runner.receipt['steps'][0]
            self.assertEqual(step['cwd'], '/')
            self.assertEqual(step['exitCode'], 0)
            self.assertIs(step['childReaped'], True)


class MountTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='disk image fixtures ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.image = self.root/'pinned image.dmg'
        self.image.write_bytes(b'pinned image fixture')
        self.stamp = package.file_stamp(self.image)
        self.mount = self.root/'owned mount'
        self.whole = disk.Entity('/dev/disk42', None)
        self.volume = disk.Entity('/dev/disk42s1', self.mount)
        self.other = disk.AttachedImage(self.root/'other image.dmg', (disk.Entity('/dev/disk91', None),),
                                        False, 991)
        self.owned = disk.AttachedImage(self.image, (self.whole, self.volume), False, 1100)
        self.payload = plistlib.dumps({'system-entities': [
            {'dev-entry': self.volume.device, 'mount-point': str(self.mount)}, {'dev-entry': self.whole.device},
        ]}).decode()
        self.begun = False
        self.detached = False
        self.commands = []
        self.runner = SimpleNamespace(root=self.root, evidence=self.root, receipt={}, env={}, timeout=30,
                                      command=self.command)
        self.trace = {}
        self.read_snapshot = disk.image_snapshot
        for target, replacement in (('image_snapshot', self.snapshot), ('volume_information', lambda *_: {}),
                                    ('attach_image', self.attach), ('detach_image', self.detach),
                                    ('ATTACH_SETTLE_SECONDS', 0)):
            patcher = patch.object(disk, target, replacement)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = patch.object(disk.build, 'Runner', return_value=self.runner)
        patcher.start()
        self.addCleanup(patcher.stop)

    def snapshot(self, _runner):
        state = (self.other, self.owned) if self.begun and not self.detached else (self.other,)
        return disk.Snapshot('710', '710', state)

    def command(self, name, argv):
        self.commands.append((name, argv))
        if name == 'attach-image':
            self.begun = True
            return self.payload
        if name == 'detach-image':
            self.detached = True

    def attach(self, runner, mount, image, record):
        record['attachChildPid'] = 1111
        return runner.command('attach-image', [disk.HDIUTIL, 'attach', '-readonly', '-nobrowse', '-noautoopen',
                                               '-mount', 'required', '-mountpoint', mount, '-plist', image])

    def detach(self, runner, mount):
        return runner.command('detach-image', [disk.HDIUTIL, 'detach', mount])

    def inspect(self):
        return disk.mounted_image(self.runner, self.image, self.stamp, self.mount, 'Meshchan', self.trace)

    def test_owned_space_path_readonly_mount_then_normal_detach(self):
        with self.inspect() as path:
            self.assertEqual(path, self.mount)
            self.assertFalse(self.detached)
        self.assertEqual(self.trace['detachStatus'], 'PASS')
        self.assertEqual(self.trace['residualAttachments'], [])
        self.assertFalse(self.mount.exists())
        self.assertIn('-readonly', self.commands[0][1])
        self.assertIn('-nobrowse', self.commands[0][1])
        self.assertIn(self.mount, self.commands[0][1])
        self.assertEqual(self.commands[1], ('detach-image', [disk.HDIUTIL, 'detach', self.mount]))

    def test_existing_mount_is_preserved(self):
        self.begun = True
        with self.assertRaisesRegex(ValueError, 'already attached'), self.inspect():
            self.fail('Existing attachment must never be used')
        self.assertFalse(self.commands)
        self.assertFalse(self.detached)
        self.assertEqual(self.trace['existingAttachments'][0]['imageProcessPid'], 1100)

    def test_malformed_attach_plist_is_fail_closed_and_owned_mount_is_detached(self):
        for payload in ('invalid xml', '<plist><dict broken></plist>', plistlib.dumps({'system-entities': [1]}).decode()):
            with self.subTest(payload=payload):
                self.payload = payload
                with self.assertRaises(ValueError), self.inspect():
                    self.fail('Incomplete attach output must never be used')
                self.assertTrue(self.detached)
                self.begun = self.detached = False

    def test_interrupted_attach_detaches_only_corroborated_owned_device(self):
        def interrupted(name, argv):
            self.command(name, argv)
            if name == 'attach-image':
                raise KeyboardInterrupt
        self.runner.command = interrupted
        with self.assertRaises(KeyboardInterrupt), self.inspect():
            self.fail('Interrupted attachment must never be used')
        self.assertTrue(self.detached)
        self.assertEqual(self.commands[-1][1][-1], self.mount)

    def test_attach_interruption_with_delayed_partial_registration(self):
        partial = disk.AttachedImage(self.image, (self.whole,), False, 1100)
        state = [
            (self.other,),  # before attach
            (self.other,),  # failed CLI has exited; service still registering
            (self.other, partial),
            (self.other, self.owned),
            (self.other,),  # confirmed detached
        ]
        def interrupt(_runner, _mount, _image, record):
            record['attachChildPid'] = 1111
            raise KeyboardInterrupt
        with (patch.object(disk, 'image_snapshot', side_effect=lambda _: disk.Snapshot('710', '710', state.pop(0))),
              patch.object(disk, 'ATTACH_SETTLE_SECONDS', 5), patch.object(disk.time, 'sleep'),
              patch.object(disk, 'attach_image', side_effect=interrupt)):
            with self.assertRaises(KeyboardInterrupt), self.inspect():
                self.fail('A mount that finished after interruption must not be used')
        self.assertTrue(self.detached)
        self.assertEqual(self.trace['detachStatus'], 'PASS')
        self.assertEqual(self.trace['residualAttachments'], [])

    def test_premature_attach_failure_never_claims_a_mount(self):
        states = [(self.other,), (self.other, self.owned)]
        with (patch.object(disk, 'image_snapshot', side_effect=lambda _: disk.Snapshot('710', '710', states.pop(0))),
              patch.object(disk, 'attach_image', side_effect=OSError('Could not launch attach command'))):
            with self.assertRaisesRegex(ValueError, 'did not launch'), self.inspect():
                self.fail('A tool that never launched must never adopt or detach a mount')
        self.assertIn('Could not launch attach command', self.trace['attachError'])
        self.assertEqual(self.trace['residualAttachments'], [self.owned.describe()])
        self.assertFalse(self.detached)

    def test_mount_path_alias_is_detected_but_never_claimed(self):
        alias = self.root/'other name'
        alias.symlink_to(self.mount, target_is_directory=True)
        value = [{'dev-entry': self.volume.device, 'mount-point': str(alias)}, {'dev-entry': self.whole.device}]
        entities = disk.entities(value)
        self.assertIn(disk.Entity(self.volume.device, alias), entities)
        self.owned = disk.AttachedImage(self.image, entities, False, 1100)
        with self.assertRaisesRegex(ValueError, 'ownership'), self.inspect():
            self.fail('An alias is not the exact requested mount path')
        self.assertFalse(self.detached)
        self.assertEqual(self.trace['residualAttachments'], [self.owned.describe()])

    def test_wrong_image_or_mount_does_not_trigger_unowned_detach(self):
        bad = (disk.AttachedImage(self.other.path, (self.whole, self.volume), False, 1100),
               disk.AttachedImage(self.image, (self.whole, disk.Entity(self.volume.device, self.root/'other mount')),
                                  False, 1100))
        for image in bad:
            with self.subTest(image=image):
                self.owned = image
                self.begun = False
                with self.assertRaisesRegex(ValueError, 'ownership'), self.inspect():
                    self.fail('Unowned mount must never be used')
                self.assertFalse(self.detached)
                self.assertTrue(self.trace['residualAttachments'])
                self.mount.rmdir()

    def test_detach_failure_preserves_residual_and_fails(self):
        def refuse(name, argv):
            if name == 'detach-image':
                raise subprocess.CalledProcessError(1, argv)
            return self.command(name, argv)
        self.runner.command = refuse
        with self.assertRaises(subprocess.CalledProcessError), self.inspect():
            self.assertEqual(self.trace['attachStatus'], 'PASS')
        self.assertEqual(self.trace['detachStatus'], 'FAIL')
        self.assertTrue(self.trace['residualAttachments'])
        self.assertTrue(self.mount.exists())

    def test_cleanup_reobserves_transient_snapshot_errors_before_and_after_detach(self):
        before = disk.Snapshot('710', '710', (self.other,))
        attached = disk.Snapshot('710', '710', (self.other, self.owned))
        temporary = subprocess.CalledProcessError(1, [disk.HDIUTIL, 'info', '-plist'])
        with (patch.object(disk, 'image_snapshot',
                           side_effect=[before, attached, temporary, attached, temporary, before]),
              patch.object(disk.time, 'sleep')):
            with self.inspect():
                self.assertFalse(self.detached)
        self.assertTrue(self.detached)
        self.assertEqual(self.trace['detachStatus'], 'PASS')
        self.assertEqual(self.trace['residualAttachments'], [])

    def test_cleanup_matches_reordered_system_entities_from_hdiutil(self):
        def snapshot(*, reversed_order):
            rows = [{'dev-entry': self.whole.device},
                    {'dev-entry': self.volume.device, 'mount-point': str(self.mount)}]
            if reversed_order:
                rows.reverse()
            return SimpleNamespace(stdout=plistlib.dumps({
                'framework': '710', 'revision': '710', 'images': [{
                    'image-path': str(self.image), 'writeable': False, 'hdid-pid': self.owned.pid,
                    'system-entities': rows,
                }],
            }).decode())

        empty = SimpleNamespace(stdout=plistlib.dumps({
            'framework': '710', 'revision': '710', 'images': [],
        }).decode())
        with (patch.object(disk, 'image_snapshot', self.read_snapshot),
              patch.object(disk.subprocess, 'run',
                           side_effect=[empty, snapshot(reversed_order=False),
                                        snapshot(reversed_order=True), empty])):
            with self.inspect():
                self.assertFalse(self.detached)
        self.assertTrue(self.detached)
        self.assertEqual(self.trace['detachStatus'], 'PASS')

    def test_cleanup_with_unavailable_ownership_evidence_never_detaches(self):
        before = disk.Snapshot('710', '710', (self.other,))
        attached = disk.Snapshot('710', '710', (self.other, self.owned))
        persistent = ValueError('Invalid hdiutil info property list')
        with (patch.object(disk, 'image_snapshot',
                           side_effect=[before, attached, persistent, persistent]) as snapshot,
              patch.object(disk.time, 'sleep')):
            with self.assertRaisesRegex(ValueError, 'Invalid hdiutil info'), self.inspect():
                self.assertFalse(self.detached)
        self.assertEqual(snapshot.call_count, 4)
        self.assertFalse(self.detached)
        self.assertEqual(self.trace['detachStatus'], 'FAIL')

    def test_cleanup_never_detaches_a_replaced_image_process(self):
        def snapshot(runner):
            state = self.snapshot(runner)
            if self.trace.get('attachStatus') == 'PASS':
                replacement = disk.AttachedImage(self.image, self.owned.entities, False, self.owned.pid+1)
                return disk.Snapshot(state.framework, state.revision, (self.other, replacement))
            return state

        with patch.object(disk, 'image_snapshot', side_effect=snapshot):
            with self.assertRaisesRegex(ValueError, 'Selected attachment before detach'), self.inspect():
                self.assertFalse(self.detached)
        self.assertFalse(self.detached)
        self.assertEqual(self.trace['detachStatus'], 'FAIL')

    def test_cleanup_failure_preserves_original_attach_or_extraction_error(self):
        def refuse(name, argv):
            if name == 'detach-image':
                raise subprocess.CalledProcessError(1, argv)
            return self.command(name, argv)
        self.runner.command = refuse
        good_payload = self.payload
        self.payload = '<malformed>'
        with self.assertRaises(subprocess.CalledProcessError), self.inspect():
            self.fail('Malformed attach output must fail')
        self.assertIn('Invalid hdiutil attach', self.trace['attachError'])
        self.assertIn('CalledProcessError', self.trace['detachError'])
        self.mount.rmdir()
        self.begun = False
        self.payload = good_payload
        with self.assertRaises(subprocess.CalledProcessError), self.inspect():
            raise ValueError('Wrong extracted payload')
        self.assertIn('Wrong extracted payload', self.trace['extractionError'])
        self.assertIn('CalledProcessError', self.trace['detachError'])

    def test_detach_command_failure_refreshes_actual_residual_status(self):
        def detach_then_error(name, argv):
            self.command(name, argv)
            if name == 'detach-image':
                raise subprocess.CalledProcessError(1, argv)
        self.runner.command = detach_then_error
        with self.assertRaises(subprocess.CalledProcessError), self.inspect():
            self.assertEqual(self.trace['attachStatus'], 'PASS')
        self.assertEqual(self.trace['detachStatus'], 'FAIL')
        self.assertEqual(self.trace['residualAttachments'], [])

    def test_cleanup_preserves_a_concurrent_attachment_of_the_same_image(self):
        parallel = disk.AttachedImage(
            self.image, (disk.Entity('/dev/disk99', None), disk.Entity('/dev/disk99s1', self.root/'their mount')),
            False, 9001)
        states = [(self.other,), (self.other, self.owned), (self.other, self.owned, parallel),
                  (self.other, parallel)]
        with patch.object(disk, 'image_snapshot', side_effect=lambda _: disk.Snapshot('710', '710', states.pop(0))):
            with self.assertRaisesRegex(ValueError, 'remains registered'), self.inspect():
                self.assertEqual(self.trace['attachStatus'], 'PASS')
        self.assertEqual(self.commands[-1][1][-1], self.mount)
        self.assertEqual(self.trace['residualAttachments'], [parallel.describe()])

    def test_changed_or_replaced_image_never_attaches(self):
        self.image.write_bytes(b'corrupt image fixture')
        with self.assertRaisesRegex(ValueError, 'Disk image file identity'), self.inspect():
            self.fail('Changed bytes must never be mounted')
        replacement = self.root/'outside'
        replacement.write_bytes(b'pinned image fixture')
        replacement.replace(self.image)
        with self.assertRaisesRegex(ValueError, 'Disk image file identity'), self.inspect():
            self.fail('Another inode must never be mounted')
        self.assertFalse(self.commands)

    def test_unrelated_reused_device_is_never_detached(self):
        self.other = disk.AttachedImage(self.other.path, (self.whole,), False, 991)
        with self.assertRaisesRegex(ValueError, 'ownership'), self.inspect():
            self.fail('A preexisting device must never be reused')
        self.assertFalse(self.detached)

    def test_wrong_partition_or_duplicate_device_across_snapshot_is_never_detached(self):
        wrong_partition = disk.Entity('/dev/disk9s1', self.mount)
        self.owned = disk.AttachedImage(self.image, (self.whole, wrong_partition), False, 1100)
        with self.assertRaisesRegex(ValueError, 'ownership'), self.inspect():
            self.fail('A different whole disk must not be claimed')
        self.assertFalse(self.detached)
        self.mount.rmdir()
        duplicate = disk.AttachedImage(self.other.path, (self.whole,), False, 991)
        self.owned = disk.AttachedImage(self.image, (self.whole, self.volume), False, 1100)
        state = [(self.other,), (duplicate, self.owned), (duplicate, self.owned)]
        with patch.object(disk, 'image_snapshot', side_effect=lambda _: disk.Snapshot('710', '710', state.pop(0))):
            with self.assertRaisesRegex(ValueError, 'ownership'), self.inspect():
                self.fail('A device shared by two reported images must not be claimed')
        self.assertFalse(self.detached)

    def test_disappeared_attachment_is_not_an_accepted_detach(self):
        with self.assertRaisesRegex(ValueError, 'disappeared before normal detach'), self.inspect():
            self.begun = False
        self.assertEqual(self.trace['detachStatus'], 'FAIL')
        self.assertFalse(self.detached)

    def test_unrelated_remote_backing_image_still_counts_as_preexisting(self):
        value = {'framework': '710', 'revision': '710', 'images': [
            {'image-path': 'https://example.invalid/remote.dmg', 'writeable': False, 'hdid-pid': 1024,
             'system-entities': [{'dev-entry': '/dev/disk99'}]},
        ]}
        run = SimpleNamespace(stdout=plistlib.dumps(value).decode())
        # Recover the parser implementation masked by the fixture snapshot.
        with patch.object(disk.subprocess, 'run', return_value=run):
            snapshot = self.read_snapshot(self.runner)
        self.assertIn('/dev/disk99', snapshot.devices)
        self.assertFalse(snapshot.related(self.image, self.stamp[1], self.mount))


if __name__ == '__main__':
    unittest.main()
