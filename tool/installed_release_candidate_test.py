"""Later engineering install admission without GUI, mounts, or test hardware."""

from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import installed_release_candidate as installed
import package_dmg
import package_dmg_image as disk
from package_release import bytes_entry, DIR
from product_identity import expected_identity
from release_materials import encoded, sha
import release_signing as signing
from release_signed_runtime import LOCAL_APP

SOURCE = 'a'*40
VOLUME_UUID = '4D76C372-0009-4BDD-A631-CC8D667124A3'
OTHER_UUID = '0494ACB5-8779-446A-9DA3-306868999E96'


class InstallCandidateTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        self.refs = {}
        identity = self.identity = {'target': 'macos-arm64', 'productVersion': '0.1.0-rc.1',
                                    'appBuild': '10', 'appVersion': '0.1.0-rc.1+10',
                                    'apple': expected_identity('0.1.0-rc.1', 10)}
        app_signature = {**LOCAL_APP.record(), 'slices': {'arm64': {
            'identifier': LOCAL_APP.identifier, 'adhoc': True, 'team': None, 'timestamp': None,
            'authorityChain': [], 'signatureSlots': 1, 'entitlements': LOCAL_APP.entitlements,
            'runtime': True, 'cdhash': 'b'*40,
        }}}
        self.private = {
            'formatVersion': 2, 'signingProfile': signing.LOCAL_PROFILE, 'identity': identity,
            'payloadInventory': {}, 'signature': {'identity': signing.local_identity(), 'items': [app_signature]},
        }
        self.folder, filename, self.volume = package_dmg.volume_names(self.private)
        self.pin('signed_manifest', 'signed-product-info.json', encoded(self.private))
        self.pin('local_acceptance', 'signing-acceptance.json', b'local signatures checked')
        self.pin('dmg', filename, b'accepted image bytes')
        self.pin('checksums', 'SHA256SUMS', f"{self.refs['dmg']['sha256']}  {filename}\n".encode())
        self.pin('image_record', 'image-record.json', encoded({'mount': {'volumeUuid': VOLUME_UUID}}))
        self.extraction = self.root/'extracted image'
        policy_path = self.extraction/installed.POLICY_PATH
        policy_path.parent.mkdir(parents=True)
        policy = (Path(installed.__file__).parent/'release_signing_policy.json').read_bytes()
        policy_path.write_bytes(policy)
        self.public = {**self.private, 'payloadProfile': package_dmg.PUBLIC_PAYLOAD, 'compiledSource': SOURCE,
                       'privateSignedInfoSha256': self.refs['signed_manifest']['sha256']}
        self.manifest = {
            **package_dmg.SIGNATURE_POLICY, 'formatVersion': 1,
            'inventoryExclusions': [package_dmg.IMAGE_MANIFEST], 'candidatePath': self.folder,
            'identity': identity, 'upstream': {'sourceCommit': SOURCE},
            'localAcceptanceSha256': self.refs['local_acceptance']['sha256'],
            'image': {'filename': filename, 'volumeName': self.volume,
                      'format': disk.IMAGE_FORMAT, 'filesystem': disk.FILESYSTEM},
            'inventory': {'.': DIR, self.folder: DIR, f'{self.folder}/Meshchan.app': DIR,
                          installed.POLICY_PATH: bytes_entry(policy),
                          **{f'{self.folder}/{name}': bytes_entry(name.encode()) for name in installed.RUNTIME_FILES}},
        }
        self.refs['upstream_tool_snapshot'] = {'path': str(self.root), 'commit': SOURCE}
        self.chain = {'sourceCommit': SOURCE, 'product': identity, 'image': {
            'path': self.refs['dmg']['path'], 'sha256': self.refs['dmg']['sha256'],
            'size': len(b'accepted image bytes'), 'volumeName': self.volume,
            'format': disk.IMAGE_FORMAT, 'filesystem': disk.FILESYSTEM,
        }}

    def pin(self, key, name, data):
        path = self.root/name
        path.write_bytes(data)
        self.refs[key] = {'path': str(path), 'sha256': sha(data)}

    def select(self, *, public=True, receipt_uuid=VOLUME_UUID):
        acceptance = {'extraction': {'root': str(self.extraction)}, 'mount': {'volumeUuid': receipt_uuid}}
        if public:
            public_manifest_path = self.extraction/self.folder/package_dmg.SIGNED_MANIFEST
            public_manifest_path.parent.mkdir(exist_ok=True)
            public_manifest = encoded(self.public)
            public_manifest_path.write_bytes(public_manifest)
            self.manifest.update(payloadProfile=package_dmg.PUBLIC_PAYLOAD,
                                 privateSignedInfoSha256=self.refs['signed_manifest']['sha256'],
                                 signedInfoSha256=sha(public_manifest))
            acceptance.update(payloadProfile=package_dmg.PUBLIC_PAYLOAD, publicSignedInfoSha256=sha(public_manifest))
        else:
            self.manifest['signedInfoSha256'] = self.refs['signed_manifest']['sha256']
        self.pin('image_payload', package_dmg.IMAGE_MANIFEST, encoded(self.manifest))
        self.pin('dmg_acceptance', 'dmg-acceptance.json', encoded(acceptance))
        selection = {'formatVersion': 1, 'candidate': self.refs, 'inputRoots': [str(self.root)]}
        path = self.root/'selection.json'
        path.write_bytes(encoded(selection))
        return path, sha(encoded(selection))

    def admit(self, selection=None, *, source=SOURCE, build=10):
        selected = self.select() if selection is None else selection
        with patch.object(installed, 'verify_chain', return_value={'identities': self.chain}) as verify:
            result = installed.admit(*selected, expected_source=source, expected_build=build)
        self.assertEqual(verify.call_args.args[0], self.refs)
        self.assertEqual(verify.call_args.kwargs, {'live': True})
        return result

    def test_admits_public_projection_and_pins_the_new_install(self):
        result = self.admit()
        self.assertEqual(result.report['scope'], 'ENGINEERING_INPUT_ADMISSION')
        self.assertEqual(result.report['newProductRuntime'], 'NOT_RUN')
        self.assertEqual(result.signed_info, self.public)
        self.assertEqual(result.report['appCodeDirectoryHashes'], {'arm64': 'b'*40})
        self.assertEqual(result.report['runtimeImageSha256']['meshctl/bin/meshctl'], sha(b'meshctl/bin/meshctl'))
        self.assertEqual(result.mount_pins, {'volume_uuid': VOLUME_UUID,
                                             'manifest_sha256': self.refs['image_payload']['sha256']})

    def test_admits_older_full_image_shape_without_rebinding_its_bytes(self):
        result = self.admit(self.select(public=False))
        self.assertEqual(result.signed_info, self.private)
        self.assertIsNone(result.report['payloadProfile'])

    def test_wrong_source_build_and_historical_build_are_rejected(self):
        for expected_source, expected_build, error in (('c'*40, 10, 'compiled source'),
                                                       (SOURCE, 11, 'App build'),
                                                       (SOURCE, 8, 'historical sealed-archive')):
            with self.subTest(expected_build=expected_build), self.assertRaisesRegex(ValueError, error):
                self.admit(source=expected_source, build=expected_build)

    def test_external_selection_and_mount_uuid_are_both_pinned(self):
        selection = self.select(receipt_uuid=OTHER_UUID)
        with self.assertRaisesRegex(ValueError, 'matching volume UUID'):
            self.admit(selection)
        with self.assertRaisesRegex(ValueError, 'SHA-256 pin'):
            self.admit((selection[0], '1'*64))

    def test_public_manifest_must_match_private_selected_identity(self):
        self.public['privateSignedInfoSha256'] = '1'*64
        with self.assertRaisesRegex(ValueError, 'Public signed evidence privateSignedInfoSha256'):
            self.admit()

    def test_complete_guide_install_uses_the_admitted_manifest_and_policy(self):
        candidate = self.admit()
        vm, scratch = object(), object()
        destination = Path('/Users/guest/Applications/Meshchan Engineering Build 10')
        app = destination/self.folder/'Meshchan.app'
        with patch.object(installed.files, 'verify_installation', return_value={'status': 'PASS'}) as verify:
            report = candidate.verify_installation(vm, app, destination, scratch=scratch, unified=True)
        self.assertEqual(report, {'status': 'PASS'})
        verify.assert_called_once_with(vm, candidate.image_payload, self.refs['image_payload']['sha256'], app,
                                       destination, scratch=scratch, policy=candidate.policy,
                                       signed_info=candidate.signed_info, include_volume_materials=True, unified=True)

    def test_actual_download_asset_is_passed_through_and_compared_before_mount(self):
        result = self.admit()
        vm, baseline = SimpleNamespace(c={'user': 'guest'}), object()
        asset = result.download_asset
        download = {'sha256': asset['sha256'], 'file': {'size': asset['size'],
                                                     'path': '/Users/guest/Downloads/'+asset['filename']}}
        with patch.object(installed.files, 'verify_safari_download_receipt'), \
                patch.object(installed.files, 'observe_download_mount') as mount:
            result.observe_mount(vm, baseline, download)
            mount.assert_called_once_with(vm, baseline, download, self.volume, **result.mount_pins)
            with self.assertRaisesRegex(ValueError, 'Admitted download sha256'):
                result.observe_mount(vm, baseline, {**download, 'sha256': '1'*64})
            self.assertEqual(mount.call_count, 1)

    def test_only_the_guest_downloads_path_is_used_for_mount_and_detach(self):
        result = self.admit()
        vm, baseline = SimpleNamespace(c={'user': 'guest'}), object()
        asset = result.download_asset
        download = {'sha256': asset['sha256'], 'file': {'size': asset['size'],
                                                     'path': '/Users/other/Downloads/'+asset['filename']}}
        with patch.object(installed.files, 'verify_safari_download_receipt'), \
                patch.object(installed.files, 'observe_download_mount') as mount, \
                patch.object(installed.files, 'detach_download_mount') as detach:
            with self.assertRaisesRegex(ValueError, 'Admitted download file path'):
                result.observe_mount(vm, baseline, download)
            with self.assertRaisesRegex(ValueError, 'Admitted download file path'):
                result.detach_mount(vm, baseline, download, {'volumeName': self.volume})
            mount.assert_not_called()
            detach.assert_not_called()


if __name__ == '__main__':
    unittest.main()
