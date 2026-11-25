"""Check the isolated BLE generator's source, path, and signing boundaries."""

import io
import json
import plistlib
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

import prepare_ble_probe as probe


class BleProbePreparationTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.product = self.base / 'product'
        self.product.mkdir()

    def test_refuses_product_ancestors_existing_directories_and_symlink_aliases(self):
        external = self.base / 'external'
        external.mkdir()
        marker = external / 'owned-by-user'
        marker.write_text('preserve')
        inward = self.base / 'inward'
        inward.symlink_to(self.product, target_is_directory=True)
        outward = self.product / 'outward'
        outward.symlink_to(external, target_is_directory=True)
        dangling = self.base / 'dangling'
        dangling.symlink_to(self.base / 'absent', target_is_directory=True)
        for path in (self.base, self.product, self.product / 'build', external,
                     inward / 'new', outward / 'new', dangling):
            with self.subTest(path=path), self.assertRaises(ValueError):
                probe.external_destination(self.product, path)
        target = self.base / 'new'
        self.assertEqual(probe.external_destination(self.product, target), target)
        self.assertFalse(target.exists())
        self.assertEqual(marker.read_text(), 'preserve')

    def test_materializes_selected_git_bytes_and_only_removes_workspace_line(self):
        manifest = (b'name: meshcore_link\r\nresolution: workspace\r\n\r\n'
                    b'environment:\r\n  sdk: ^3.13.0\r\n'
                    b'dependencies:\r\n  libserialport_plus: ^1.0.5\r\n')
        pkg = self.product / probe.LINK
        sources = {
            pkg / 'pubspec.yaml': manifest,
            pkg / 'lib/meshcore_link.dart': b"export 'src/session.dart';\n",
            pkg / 'lib/src/session.dart': b'class Session {}\n',
            self.product / 'LICENSE': b'GPL fixture\n',
            self.product / 'COPYRIGHT': b'Copyright fixture\n',
            self.product / 'pubspec.lock': b'product lock\n',
        }
        for path, contents in sources.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(contents)
        subprocess.run(['git', 'init', '--quiet'], cwd=self.product, check=True)
        subprocess.run(['git', '-c', 'core.autocrlf=false', 'add', '.'],
                       cwd=self.product, check=True)
        subprocess.run(['git', '-c', 'user.name=Probe Test', '-c',
                        'user.email=probe@example.invalid', '-c', 'commit.gpgsign=false',
                        'commit', '--quiet', '-m', 'snapshot'], cwd=self.product, check=True)
        modified = pkg / 'lib/src/session.dart'
        modified.write_bytes(b'class Uncommitted {}\n')
        (pkg / 'lib/other.dart').write_text('untracked fixture')

        vendor = self.base / 'external/vendor/meshcore_link'
        files = probe.copy_meshcore(self.product, 'HEAD', vendor)
        self.assertEqual((vendor / 'lib/src/session.dart').read_bytes(), sources[modified])
        self.assertEqual((vendor / 'pubspec.yaml').read_bytes(),
                         manifest.replace(b'resolution: workspace\r\n', b''))
        self.assertEqual((vendor / 'LICENSE').read_bytes(), sources[self.product / 'LICENSE'])
        self.assertFalse((vendor / 'lib/other.dart').exists())
        record = files[str(modified.relative_to(self.product))]
        self.assertEqual(record['sourceSha256'], record['vendorSha256'])
        self.assertNotEqual(record['sourceSha256'], record['worktreeSha256'])
        manifest_record = files[str(probe.LINK / 'pubspec.yaml')]
        self.assertNotEqual(manifest_record['sourceSha256'], manifest_record['vendorSha256'])
        self.assertEqual(manifest_record['sourceSha256'], manifest_record['worktreeSha256'])
        self.assertEqual((pkg / 'pubspec.yaml').read_bytes(), manifest)
        self.assertEqual((self.product / 'pubspec.lock').read_bytes(), b'product lock\n')
        self.assertEqual(modified.read_bytes(), b'class Uncommitted {}\n')

    def test_rejects_missing_or_ambiguous_workspace_transform(self):
        for manifest in (b'name: fixture\n', b'resolution: workspace\nresolution: workspace\n'):
            with self.subTest(manifest=manifest), self.assertRaises(ValueError):
                probe.remove_workspace_resolution(manifest)

    def test_rejects_wrong_release_archive_before_extraction(self):
        archive = self.base / 'darwin.tar.gz'
        archive.write_bytes(b'corrupted release fixture')
        with self.assertRaisesRegex(ValueError, 'pinned SHA-256'):
            probe.read_darwin_archive(archive)

    def test_darwin_snapshot_binds_ordered_patches_and_final_bytes(self):
        archive = io.BytesIO()
        inputs = {'LICENSE': b'MIT fixture\n', 'pubspec.yaml': b'name: fixture\n',
                  'lifecycle.swift': b'let stage = "upstream"\n'}
        with tarfile.open(fileobj=archive, mode='w:gz') as output:
            for name, content in inputs.items():
                member = tarfile.TarInfo(name)
                member.size = len(content)
                output.addfile(member, io.BytesIO(content))
        observation = self.base / 'observe.patch'
        lifecycle = self.base / 'lifecycle.patch'
        for patch, before, after in (
            (observation, 'upstream', 'observed'),
            (lifecycle, 'observed', 'settled'),
        ):
            patch.write_text('--- a/lifecycle.swift\n+++ b/lifecycle.swift\n'
                             '@@ -1 +1 @@\n'
                             f'-let stage = "{before}"\n+let stage = "{after}"\n')

        vendor = self.base / 'vendor'
        receipt = probe.copy_darwin(archive.getvalue(), vendor, observation, lifecycle)
        self.assertEqual(receipt['observationPatchSha256'], probe.digest(observation))
        self.assertEqual(receipt['lifecyclePatchSha256'], probe.digest(lifecycle))
        self.assertEqual(receipt['originalFiles']['lifecycle.swift'],
                         probe.sha256(inputs['lifecycle.swift']))
        self.assertEqual(receipt['patchedFiles']['lifecycle.swift'],
                         probe.sha256(b'let stage = "settled"\n'))
        self.assertEqual((vendor / 'LICENSE').read_bytes(), inputs['LICENSE'])

    def test_resolution_checks_the_private_paths_versions_and_unchanged_lock(self):
        host = self.base / 'external/host'
        dart_tool = host / '.dart_tool'
        dart_tool.mkdir(parents=True)
        lock = (probe.ROOT / probe.TEMPLATE / 'pubspec.lock').read_bytes()
        lock_path = host / 'pubspec.lock'
        lock_path.write_bytes(lock)
        packages = [{'name': name, 'version': probe.BLE_VERSION}
                    for name in (*probe.HOSTED_PINS, probe.DARWIN)]
        graph = dart_tool / 'package_graph.json'
        graph.write_text(json.dumps({'packages': packages}))
        config = dart_tool / 'package_config.json'
        private_paths = [{'name': name, 'rootUri': f'../../vendor/{name}'}
                         for name in (probe.DARWIN, 'meshcore_link')]
        config.write_text(json.dumps({'packages': private_paths}))
        result = probe.verify_resolution(host, self.product, lock)
        self.assertEqual(result['lockSha256'], probe.sha256(lock))

        lock_path.write_bytes(lock + b'\n')
        with self.assertRaisesRegex(ValueError, 'changed the supplied lockfile'):
            probe.verify_resolution(host, self.product, lock)
        lock_path.write_bytes(lock)

        packages[-1]['version'] = '6.2.2'
        graph.write_text(json.dumps({'packages': packages}))
        with self.assertRaisesRegex(ValueError, 'in the resolved probe graph'):
            probe.verify_resolution(host, self.product, lock)
        packages[-1]['version'] = probe.BLE_VERSION
        graph.write_text(json.dumps({'packages': packages}))

        private_paths[1]['rootUri'] = (self.product / probe.LINK).as_uri()
        config.write_text(json.dumps({'packages': private_paths}))
        with self.assertRaisesRegex(ValueError, 'live product checkout'):
            probe.verify_resolution(host, self.product, lock)

    def test_generated_macos_configuration_is_local_and_nonsandboxed(self):
        host = self.base / 'host'
        runner = host / 'macos/Runner'
        (runner / 'Configs').mkdir(parents=True)
        (runner / 'Info.plist').write_bytes(plistlib.dumps({'CFBundlePackageType': 'APPL'}))
        project = host / 'macos/Runner.xcodeproj/project.pbxproj'
        project.parent.mkdir()
        project.write_text('CODE_SIGN_STYLE = Automatic;\n')
        probe.configure_macos(host)
        info = plistlib.loads((runner / 'Info.plist').read_bytes())
        self.assertEqual(info['CFBundleDisplayName'], probe.DISPLAY_NAME)
        self.assertEqual(info['NSBluetoothAlwaysUsageDescription'], probe.PURPOSE)
        self.assertEqual(info['CFBundlePackageType'], 'APPL')
        config = (runner / 'Configs/AppInfo.xcconfig').read_text()
        self.assertIn(f'PRODUCT_BUNDLE_IDENTIFIER = {probe.BUNDLE_ID}\n', config)
        self.assertIn('CODE_SIGN_IDENTITY = -\n', config)
        self.assertIn('CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO\n', config)
        self.assertEqual(project.read_text(), 'CODE_SIGN_STYLE = Manual;\n')
        self.assertEqual(plistlib.loads((runner / 'Release.entitlements').read_bytes()), {})
        self.assertEqual(plistlib.loads((runner / 'DebugProfile.entitlements').read_bytes()),
                         {'com.apple.security.cs.allow-jit': True})


if __name__ == '__main__':
    unittest.main()
