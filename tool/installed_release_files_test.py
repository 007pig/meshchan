"""Tests for installed-release evidence and boundaries without a product launch."""
from datetime import datetime, timezone
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import installed_release_files as files
import installed_release_inputs as inputs
import package_dmg_image as disk
from release_materials import encoded, product_inventory, sha

DOWNLOAD = '/Users/meshchantest/Downloads/meshchan.dmg'
MOUNT = '/Volumes/Meshchan 0.1.0-rc.1 build 8'
URL = 'http://192.168.64.1:12345/meshchan.dmg'
START = '2026-11-21T12:00:00Z'
FINISH = '2026-11-21T12:01:00Z'
EVENT = '973278D0-079A-44F0-A318-058060AEF2FE'
TIME = datetime(2026, 11, 21, 12, 0, 30, tzinfo=timezone.utc)


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.xattr = f'0081;{int(TIME.timestamp()):x};Safari;{EVENT}'.encode()
        self.source = plistlib.dumps([URL], fmt=plistlib.FMT_BINARY)
        self.event = {'id': EVENT, 'agent': 'com.apple.Safari', 'url': URL,
                      'appleTime': (TIME-files.APPLE_EPOCH).total_seconds()}

    def check(self, *, xattr=None, source=None, events=None, start=START, finish=FINISH):
        return files.check_download_evidence(self.xattr if xattr is None else xattr,
                                             self.source if source is None else source,
                                             [self.event] if events is None else events,
                                             url=URL, started_at=start, finished_at=finish)

    def saved_receipt(self):
        attributes = {
            files.QUARANTINE: self.xattr,
            files.WHERE_FROM: self.source,
            files.DOWNLOADED_DATE: plistlib.dumps([TIME], fmt=plistlib.FMT_BINARY, aware_datetime=True),
        }
        metadata = {'.': {key: {'scope': files.SYSTEM_ATTRIBUTES[key], 'hex': value.hex()}
                          for key, value in attributes.items()}}
        return {
            'browser': 'Safari', 'sha256': 'c'*64, 'url': URL, 'startedAt': START, 'finishedAt': FINISH,
            'file': {'birthTime': int(TIME.timestamp())},
            'quarantine': self.xattr.decode('ascii'), 'whereFrom': [URL], 'event': dict(self.event),
            'downloadedDate': TIME.isoformat(),
            'metadata': {'extendedAttributes': metadata,
                         'ownershipAclAndFlags': f'-rw-r--r--@ 1 guest staff {DOWNLOAD}\n'},
        }

    def test_saved_download_must_correspond_to_its_raw_native_metadata(self):
        receipt = self.saved_receipt()
        files.verify_safari_download_receipt(receipt)
        cases = (
            ('does not contain', lambda row: row.update(url=URL.replace('meshchan.dmg', 'wrong.dmg'))),
            ('summary quarantine', lambda row: row.update(quarantine=row['quarantine'].replace('0081', '0083'))),
            ('summary downloadedDate', lambda row: row.update(downloadedDate=FINISH)),
            ('birth time', lambda row: row['file'].update(birthTime=True)),
            ('quarantine or browser source', lambda row: row['metadata']['extendedAttributes']['.'].pop(
                files.WHERE_FROM)),
            ('invalid native Safari', lambda row: row['metadata'].update(
                ownershipAclAndFlags='listing\n 0: group:everyone deny read\n')),
        )
        for message, change in cases:
            receipt = self.saved_receipt()
            change(receipt)
            with self.subTest(message=message), self.assertRaisesRegex(ValueError, f'(?i){message}'):
                files.verify_safari_download_receipt(receipt)
        receipt = self.saved_receipt()
        del receipt['downloadedDate']
        files.verify_safari_download_receipt(receipt)
        receipt = self.saved_receipt()
        del receipt['metadata']['extendedAttributes']['.'][files.DOWNLOADED_DATE]
        with self.assertRaisesRegex(ValueError, 'lacks its native attribute'):
            files.verify_safari_download_receipt(receipt)
        del receipt['downloadedDate']
        files.verify_safari_download_receipt(receipt)

    def test_matches_os_event_to_current_browser_window_and_exact_origin(self):
        report = self.check()
        self.assertEqual(report['event'], self.event)
        self.assertEqual(report['whereFrom'], [URL])
        self.assertIsNone(self.check(events=[{**self.event, 'url': None}])['event']['url'])

    def test_absent_system_event_rejects_a_self_reported_quarantine_attribute(self):
        with self.assertRaisesRegex(ValueError, 'Missing or repeated OS quarantine event'):
            self.check(events=[])
        with self.assertRaisesRegex(ValueError, 'Safari quarantine'):
            self.check(xattr=self.xattr.replace(b'Safari', b'curl'))
        with self.assertRaisesRegex(ValueError, 'agent'):
            self.check(events=[{**self.event, 'agent': 'com.apple.Terminal'}])
        with self.assertRaisesRegex(ValueError, 'timestamp'):
            self.check(start='2026-11-21T12:05:00Z', finish='2026-11-21T12:07:00Z')
        with self.assertRaisesRegex(ValueError, 'outside'):
            self.check(events=[{**self.event, 'appleTime': self.event['appleTime']-3600}])
        with self.assertRaisesRegex(ValueError, 'outside'):
            self.check(events=[{**self.event, 'appleTime': True}])

    def test_changed_source_and_url_are_detected(self):
        with self.assertRaisesRegex(ValueError, 'origins'):
            self.check(source=b'not a plist')
        with self.assertRaisesRegex(ValueError, 'origin metadata'):
            self.check(source=plistlib.dumps([URL+'-old']))
        with self.assertRaisesRegex(ValueError, 'event URL'):
            self.check(events=[{**self.event, 'url': URL+'-old'}])

    def test_download_normal_location_type_size_and_pin_are_required(self):
        vm = SimpleNamespace()
        root = '/Users/meshchantest'
        asset = {'filename': 'meshchan.dmg', 'size': 10, 'sha256': 'b'*64}
        options = {'expected_asset': asset, 'url': URL, 'started_at': START,
                   'finished_at': FINISH, 'user_home': root}
        with self.assertRaisesRegex(ValueError, 'path differs'):
            files.verify_safari_download(vm, '/Users/another/Downloads/meshchan.dmg', **options)
        with patch.object(files, 'guest_file_stamp', return_value={'size': 9, 'uid': 501}), \
                patch.object(files, 'remote_text', return_value='501'):
            with self.assertRaisesRegex(ValueError, 'size'):
                files.verify_safari_download(vm, DOWNLOAD, **options)
        stamp = {'size': 10, 'uid': 501, 'birthTime': int(TIME.timestamp())}
        with patch.object(files, 'guest_file_stamp', return_value=stamp), \
                patch.object(files, 'remote_text', side_effect=['501', 'a'*64]):
            with self.assertRaisesRegex(ValueError, 'trusted external digest'):
                files.verify_safari_download(vm, DOWNLOAD, **options)


def snapshot(*rows):
    result = plistlib.dumps({'framework': 'DiskImages2', 'revision': '1', 'images': list(rows)}).decode()
    return files.parse_mount_snapshot(result)


def image_row(path=DOWNLOAD, number=12, mount=MOUNT):
    return {'image-path': path, 'writeable': False, 'hdid-pid': 2345,
            'system-entities': [{'dev-entry': f'/dev/disk{number}'},
                                {'dev-entry': f'/dev/disk{number}s1', 'mount-point': mount}]}


class MountTests(unittest.TestCase):
    def setUp(self):
        self.vm = object()
        self.stamp = {'path': DOWNLOAD, 'device': 50, 'inode': 9}
        self.download = {'file': self.stamp, 'sha256': 'a'*64}
        self.volume = 'Meshchan 0.1.0-rc.1 build 8'
        self.details = {'BusProtocol': 'Disk Image', 'DeviceNode': '/dev/disk12s1',
                        'ParentWholeDisk': 'disk12', 'MountPoint': MOUNT,
                        'FilesystemType': 'hfs', 'FilesystemName': disk.FILESYSTEM,
                        'VolumeName': self.volume, 'Writable': False, 'WritableVolume': False,
                        'WritableMedia': False, 'VolumeUUID': inputs.DMG_VOLUME_UUID}
        self.manifest_hash = inputs.CANDIDATE_PINS['image_payload']

    def test_exact_download_and_new_read_only_device(self):
        before = snapshot(image_row(path='/Users/test/unrelated.dmg', number=20, mount='/Volumes/unrelated'))
        current = snapshot(image_row())
        after = snapshot(image_row(path='/Users/test/other.dmg', number=22, mount='/Volumes/other'),
                         image_row())
        with patch.object(files, 'guest_file_stamp', return_value=self.stamp), \
                patch.object(files, 'mount_snapshot', side_effect=[current, after]), \
                patch.object(files, 'remote_text', side_effect=[
                    plistlib.dumps(self.details).decode(), '501 20 40755', self.manifest_hash]) as read:
            report = files.observe_download_mount(self.vm, before, self.download, self.volume)
        self.assertTrue(report['readOnly'])
        self.assertEqual(report['volumeDevice'], '/dev/disk12s1')
        read.assert_any_call(self.vm, ['/usr/bin/shasum', '-a', '256', Path(MOUNT)/files.VOLUME_MANIFEST])

    def test_changes_during_volume_observation_do_not_eject(self):
        current = snapshot(image_row())
        changed = (
            (snapshot(image_row(path='/Users/test/other.dmg')), self.stamp),
            (current, {**self.stamp, 'inode': 10}),
        )
        for after, stamp in changed:
            with self.subTest(after=after, stamp=stamp), \
                    patch.object(files, 'guest_file_stamp', side_effect=[self.stamp, self.stamp, stamp]), \
                    patch.object(files, 'mount_snapshot', side_effect=[current, after]), \
                    patch.object(files, 'remote_text', side_effect=[
                        plistlib.dumps(self.details).decode(), '501 20 40755', self.manifest_hash]) as read:
                with self.assertRaisesRegex(ValueError, 'changed during mount inspection'):
                    files.detach_download_mount(self.vm, snapshot(), self.download,
                                                 {'volumeName': self.volume})
                self.assertEqual(read.call_count, 3)

    def test_successful_native_commands_still_need_valid_mount_identity_fields(self):
        missing_uuid = dict(self.details)
        del missing_uuid['VolumeUUID']
        cases = (
            (missing_uuid, '501 20 40755', 'valid volume UUID'),
            ({**self.details, 'VolumeUUID': 'not-a-uuid'}, '501 20 40755', 'valid volume UUID'),
            ({**self.details, 'VolumeUUID': '4D76C372-0009-4BDD-A631-CC8D667124A3'},
             '501 20 40755', 'UUID differs from the accepted engineering image'),
            (self.details, 'invalid-owner', 'valid directory ownership'),
            (self.details, '501 20 100755', 'valid directory ownership'),
        )
        for details, owner, message in cases:
            with self.subTest(owner=owner, message=message), \
                    patch.object(files, 'guest_file_stamp', return_value=self.stamp), \
                    patch.object(files, 'mount_snapshot', return_value=snapshot(image_row())), \
                    patch.object(files, 'remote_text', side_effect=[plistlib.dumps(details).decode(), owner]):
                with self.assertRaisesRegex(ValueError, message):
                    files.observe_download_mount(self.vm, snapshot(), self.download, self.volume)

    def test_mount_with_the_expected_uuid_still_requires_the_pinned_payload_manifest(self):
        with patch.object(files, 'guest_file_stamp', return_value=self.stamp), \
                patch.object(files, 'mount_snapshot', return_value=snapshot(image_row())), \
                patch.object(files, 'remote_text', side_effect=[
                    plistlib.dumps(self.details).decode(), '501 20 40755', '0'*64]):
            with self.assertRaisesRegex(ValueError, 'payload manifest differs'):
                files.observe_download_mount(self.vm, snapshot(), self.download, self.volume)

    def test_later_candidate_mount_and_detach_use_the_volume_after_download_verification(self):
        before = snapshot()
        mounted = snapshot(image_row())
        pins = {'volume_uuid': '4D76C372-0009-4BDD-A631-CC8D667124A3', 'manifest_sha256': 'b'*64}
        details = {**self.details, 'VolumeUUID': pins['volume_uuid']}
        volume = Path(MOUNT)
        replies = {
            (disk.DISKUTIL, 'info', '-plist', volume): plistlib.dumps(details).decode(),
            ('/usr/bin/stat', '-f', '%u %g %p', volume): '501 20 40755',
            ('/usr/bin/shasum', '-a', '256', volume/files.VOLUME_MANIFEST): pins['manifest_sha256'],
            (disk.HDIUTIL, 'detach', volume): 'detached',
        }

        def ssh_read(vm, argv, **options):
            if argv[-1] == Path(DOWNLOAD):
                raise PermissionError('Raw Downloads file reads require the GUI executor')
            return replies[tuple(argv)]

        with patch.object(files, 'guest_file_stamp', return_value=self.stamp), \
                patch.object(files, 'mount_snapshot', side_effect=[mounted]*4+[before]), \
                patch.object(files, 'remote_text', side_effect=ssh_read):
            report = files.observe_download_mount(self.vm, before, self.download, self.volume, **pins)
            detached = files.detach_download_mount(self.vm, before, self.download, report, **pins)
        self.assertEqual(report['volumeUuid'], pins['volume_uuid'])
        self.assertEqual(detached['attachment'], report['attachment'])
        self.assertEqual(detached['status'], 'PASS')

    def test_wrong_attachment_and_reused_device_do_not_eject(self):
        before = snapshot(image_row(path='/Users/test/unrelated.dmg', mount='/Volumes/unrelated'))
        current = snapshot(image_row())
        with patch.object(files, 'guest_file_stamp', return_value=self.stamp), \
                patch.object(files, 'mount_snapshot', return_value=current), \
                patch.object(files, 'remote_text') as execute:
            with self.assertRaisesRegex(ValueError, 'ownership'):
                files.detach_download_mount(self.vm, before, self.download,
                                             {'volumeName': self.volume, 'mountPoint': MOUNT})
            execute.assert_not_called()
        with patch.object(files, 'guest_file_stamp', return_value=self.stamp), \
                patch.object(files, 'mount_snapshot', return_value=before):
            with self.assertRaisesRegex(ValueError, 'exact download'):
                files.observe_download_mount(self.vm, snapshot(), self.download, self.volume)

    def test_residual_owned_mount_is_a_failed_detach(self):
        selected = {'volumeName': self.volume, 'mountPoint': MOUNT,
                    'attachment': snapshot(image_row()).images[0].describe()}
        with patch.object(files, 'observe_download_mount', return_value=selected), \
                patch.object(files, 'remote_text', return_value='detached'), \
                patch.object(files, 'mount_snapshot', return_value=snapshot(image_row())):
            with self.assertRaisesRegex(ValueError, 'remains attached'):
                files.detach_download_mount(self.vm, snapshot(), self.download, selected)


class FileTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == 'darwin', 'Uses the native macOS stat format')
    def test_same_second_in_place_rewrite_changes_file_identity(self):
        class LocalTransport:
            def remote(self, command, **kwargs):
                return subprocess.run(command, shell=True, check=True, **kwargs)

        epoch_ns = int(TIME.timestamp()) * 1_000_000_000
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch).resolve()/'download.dmg'
            path.write_bytes(b'byte1')
            os.utime(path, ns=(epoch_ns, epoch_ns+150_000_000))
            before = files.guest_file_stamp(LocalTransport(), path)
            path.write_bytes(b'byte2')
            os.utime(path, ns=(epoch_ns, epoch_ns+810_000_000))
            after = files.guest_file_stamp(LocalTransport(), path)
        self.assertEqual(before['inode'], after['inode'])
        self.assertEqual(before['size'], after['size'])
        self.assertEqual(before['modifiedTime'], after['modifiedTime'])
        self.assertEqual(before['modifiedTimeNs'], epoch_ns+150_000_000)
        self.assertEqual(after['modifiedTimeNs'], epoch_ns+810_000_000)
        self.assertNotEqual(before, after)

    def test_wrong_user_and_staged_bundle_paths_cannot_count_as_installed(self):
        vm = SimpleNamespace(c={'user': 'test'})
        app = '/Users/test/Applications/Meshchan.app'
        materials = '/Users/test/Library/Application Support/meshchan-engineering/verified-run'
        paths = [('/private/tmp/Applications/Meshchan.app', materials),
                 ('/Users/other/Applications/Meshchan.app', materials), (app, '/private/tmp/verified-run')]
        for target, ancillary in paths:
            with self.subTest(target=target, ancillary=ancillary), \
                    self.assertRaisesRegex(ValueError, 'verified guest account'):
                files.verify_installation(vm, b'', '', target, ancillary, scratch=None, policy=[], signed_info={})

    def test_exact_image_layout_keeps_all_materials_and_no_second_app(self):
        entry = {'mode': 0o755, 'type': 'directory'}
        candidate = 'Meshchan-0.1.0-rc.1-macos-arm64'
        raw = encoded({'formatVersion': 1, 'signingProfile': 'local-adhoc', 'candidatePath': candidate,
                       'inventoryExclusions': ['image-payload.json'], 'inventory': {
                           '.': entry, candidate: entry, candidate+'/Meshchan.app': entry,
                           candidate+'/Meshchan.app/Contents': entry, 'dmg-source': entry,
                           candidate+'/meshctl': entry, candidate+'/materials': entry}})
        name, app, materials = files.installation_layout(raw, sha(raw))
        self.assertEqual(name, candidate)
        self.assertEqual(set(app), {'.', 'Contents'})
        self.assertEqual(set(materials), {'.', candidate, candidate+'/meshctl', candidate+'/materials',
                                          'dmg-source', 'image-payload.json'})
        _, _, flat = files.installation_layout(raw, sha(raw), include_volume_materials=False)
        self.assertEqual(set(flat), {'.', 'meshctl', 'materials'})
        with self.assertRaisesRegex(ValueError, 'trusted handoff'):
            files.installation_layout(raw + b'\n', sha(raw))

    def test_install_report_records_exact_cli_executable_in_both_layouts(self):
        vm = SimpleNamespace(c={'user': 'test'})
        app = '/Users/test/Applications/Meshchan.app'
        materials = '/Users/test/Library/Application Support/meshchan-engineering/verified-run'
        candidate = 'Meshchan-0.1.0-rc.1-macos-arm64'
        cli = 'meshctl/bin/meshctl'
        identity = {'apple': {'CFBundleIdentifier': 'org.meshchan.meshchan'}}
        signed_info = {'identity': identity, 'signature': {'items': [{'binary': cli}]}}
        raw = encoded({'formatVersion': 1, 'signingProfile': 'local-adhoc', 'candidatePath': candidate,
                       'identity': identity, 'signedInfoSha256': sha(encoded(signed_info)),
                       'inventoryExclusions': ['image-payload.json'],
                       'inventory': {path: {'mode': 0o755, 'type': 'directory'}
                                     for path in ('.', candidate, candidate+'/Meshchan.app')}})
        with patch.object(files, 'verify_guest_tree', return_value={}) as tree, \
                patch.object(files, 'verify_guest_signatures', return_value={}), \
                patch.object(files, 'remote_text', return_value=plistlib.dumps(identity['apple']).decode()):
            for full, prefix in ((True, f'{candidate}/'), (False, '')):
                with self.subTest(full=full):
                    report = files.verify_installation(vm, raw, sha(raw), app, materials, scratch=None,
                                                       policy=[], signed_info=signed_info,
                                                       include_volume_materials=full)
                    self.assertEqual(report['layout']['cli'], f'{materials}/{prefix}{cli}')
                    self.assertEqual(tree.call_args.kwargs['quarantine_paths'], [f'{prefix}{cli}'])
                    self.assertEqual(tree.call_args.kwargs['link_roots'], (f'{prefix}meshctl',))

    def test_complete_guide_install_checks_the_pinned_volume_and_app_metadata(self):
        vm = SimpleNamespace(c={'user': 'test'})
        candidate = 'Meshchan-0.1.0-rc.1-macos-arm64'
        destination = Path('/Users/test/Applications/Meshchan Engineering Build 10')
        product = destination/candidate
        app, cli = product/files.APP, 'meshctl/bin/meshctl'
        app_prefix = f'{candidate}/{files.APP}'
        identity = {'apple': {'CFBundleIdentifier': 'org.meshchan.meshchan'}}
        signed_info = {'identity': identity, 'signature': {'items': [{'binary': cli}]}}
        directory = {'mode': 0o755, 'type': 'directory'}
        readme = files.bytes_entry(b'Meshchan')
        inventory = {name: directory for name in ('.', candidate, app_prefix, app_prefix+'/Contents',
                                                   f'{candidate}/meshctl', f'{candidate}/meshctl/bin', 'dmg-source')}
        inventory.update({'README-engineering.md': readme, f'{candidate}/{cli}': files.bytes_entry(b'cli')})
        raw = encoded({'formatVersion': 1, 'signingProfile': 'local-adhoc', 'candidatePath': candidate,
                       'identity': identity, 'signedInfoSha256': sha(encoded(signed_info)),
                       'inventoryExclusions': [files.VOLUME_MANIFEST], 'inventory': inventory})
        info = plistlib.dumps(identity['apple']).decode()
        app_inventory = {'.': directory, 'Contents': directory}
        app_metadata = {'extendedAttributes': {'.': {files.QUARANTINE: {
            'scope': files.SYSTEM_ATTRIBUTES[files.QUARANTINE], 'hex': '30313833',
        }}}, 'ownershipAclAndFlags': 'root listing'}
        options = {'scratch': None, 'policy': [], 'signed_info': signed_info, 'unified': True}
        with patch.object(files, 'verify_guest_tree', return_value={'entries': len(inventory)+1}) as tree, \
                patch.object(files, 'observe_metadata', return_value=app_metadata) as metadata, \
                patch.object(files, 'verify_guest_signatures', return_value={}) as signatures, \
                patch.object(files, 'remote_text', return_value=info):
            report = files.verify_installation(vm, raw, sha(raw), app, destination, **options)
            tree.assert_called_once_with(vm, destination, {**inventory, files.VOLUME_MANIFEST: files.bytes_entry(raw)},
                                         scratch=None, link_roots=(app_prefix, f'{candidate}/meshctl'),
                                         quarantine_paths=[f'{candidate}/{cli}'])
            metadata.assert_called_once_with(vm, app, known_paths=app_inventory, quarantine_paths=())
            signatures.assert_called_once_with(vm, app, product, [], signed_info)
            self.assertEqual(report['app']['inventorySha256'], sha(encoded(app_inventory)))
            self.assertEqual(report['app']['metadata'], app_metadata)
            self.assertEqual(report['layout'], {'app': str(app), 'cli': str(product/cli),
                                                'candidateMaterials': str(product),
                                                'volumeMaterials': str(destination)})
        for target, root, full, error in (
                (destination/'another-candidate'/files.APP, destination, True, 'pinned candidate'),
                (app, Path('/Volumes/Meshchan'), True, 'verified guest account'),
                (app, Path('/private/tmp/staged'), True, 'verified guest account'),
                (app, Path('/Users/other/Applications/staged'), True, 'verified guest account'),
                (app, destination, False, 'complete installation')):
            with self.subTest(target=target, root=root, full=full), self.assertRaisesRegex(ValueError, error):
                files.verify_installation(vm, raw, sha(raw), target, root, include_volume_materials=full, **options)

    def test_changes_to_metadata_are_separate_from_sealed_bundle_bytes(self):
        path = Path('/Users/test/Applications/Meshchan.app')
        accepted = f'{path}: com.apple.quarantine\n{path}/Contents: com.apple.provenance\n'
        with patch.object(files, 'remote_text', side_effect=[accepted, 'AB', 'listing']):
            metadata = files.observe_metadata(object(), path, known_paths={'.', 'Contents'})
        self.assertEqual(metadata['extendedAttributes']['.'][files.QUARANTINE]['hex'], 'ab')
        self.assertIn('com.apple.provenance', metadata['extendedAttributes']['Contents'])
        for attr, child in [('com.apple.ResourceFork', 'Contents'), ('com.apple.provenance', 'unknown')]:
            with self.subTest(attr=attr, child=child), \
                    patch.object(files, 'remote_text', return_value=f'{path/child}: {attr}\n'):
                with self.assertRaisesRegex(ValueError, 'Unexpected installed extended attribute'):
                    files.observe_metadata(object(), path, known_paths={'.', 'Contents'})

    def test_raw_quarantine_is_recorded_for_selected_nested_cli_code(self):
        path = Path('/Users/test/Library/Application Support/meshchan-engineering/verified-run')
        cli, other = 'candidate/meshctl/bin/meshctl', 'candidate/LICENSE'
        listings = f'{path/cli}: {files.QUARANTINE}\n{path/other}: {files.QUARANTINE}\n'
        vm = object()
        with patch.object(files, 'remote_text', side_effect=[listings, '41', 'ls output']) as read:
            metadata = files.observe_metadata(vm, path, known_paths={'.', cli, other}, quarantine_paths=[cli])
        attributes = metadata['extendedAttributes']
        self.assertEqual(attributes[cli][files.QUARANTINE]['hex'], '41')
        self.assertEqual(attributes[other][files.QUARANTINE], files.SYSTEM_ATTRIBUTES[files.QUARANTINE])
        self.assertEqual(read.call_args_list[1].args,
                         (vm, ['/usr/bin/xattr', '-p', '-s', '-x', files.QUARANTINE, path/cli]))

    @unittest.skipUnless(sys.platform == 'darwin', 'Uses macOS BSD tar and metadata commands')
    def test_real_read_only_tree_checks_bytes_execute_mode_and_extra_hidden_files(self):
        class LocalTransport:
            def remote(self, command, **kwargs):
                return subprocess.run(command, shell=True, check=True, **kwargs)

        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch).resolve()/'test app'
            root.mkdir()
            binary = root/'exec'
            binary.write_bytes(b'mach-o contents')
            binary.chmod(0o755)
            (root/'linked').symlink_to('exec')
            inventory = product_inventory(root)
            report = files.verify_guest_tree(LocalTransport(), root, inventory, scratch=scratch)
            self.assertEqual(report['inventorySha256'], sha(encoded(inventory)))
            binary.write_bytes(b'bad')
            with self.assertRaisesRegex(ValueError, 'Unexpected archive size'):
                files.verify_guest_tree(LocalTransport(), root, inventory, scratch=scratch)
            binary.write_bytes(b'mach-o contents')
            binary.chmod(0o644)
            with self.assertRaisesRegex(ValueError, 'Unexpected archive type, mode or metadata'):
                files.verify_guest_tree(LocalTransport(), root, inventory, scratch=scratch)
            binary.chmod(0o755)
            (root/'.extra').touch()
            with self.assertRaisesRegex(ValueError, r'\.extra'):
                files.verify_guest_tree(LocalTransport(), root, inventory, scratch=scratch)

    @unittest.skipUnless(sys.platform == 'darwin', 'Uses macOS BSD tar and metadata commands')
    def test_real_tree_allows_a_cli_link_only_within_the_pinned_cli_root(self):
        class LocalTransport:
            def remote(self, command, **kwargs):
                return subprocess.run(command, shell=True, check=True, **kwargs)

        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch).resolve()/'installed materials'
            cli = root/'candidate/meshctl'
            cli.mkdir(parents=True)
            (cli/'binary').write_bytes(b'bundled CLI')
            (cli/'alias').symlink_to('binary')
            link_roots = ('candidate/meshctl',)
            inventory = product_inventory(root)
            report = files.verify_guest_tree(LocalTransport(), root, inventory, scratch=scratch,
                                             link_roots=link_roots)
            self.assertEqual(report['inventorySha256'], sha(encoded(inventory)))
            (root/'material-alias').symlink_to('candidate/meshctl/binary')
            with self.assertRaisesRegex(ValueError, 'Unexpected archive symlink: .*material-alias'):
                files.verify_guest_tree(LocalTransport(), root, product_inventory(root), scratch=scratch,
                                        link_roots=link_roots)
            (root/'material-alias').unlink()
            (cli.parent/'material').write_bytes(b'release material')
            (cli/'outside').symlink_to('../material')
            with self.assertRaisesRegex(ValueError, 'Archive link escapes its product: .*meshctl/outside'):
                files.verify_guest_tree(LocalTransport(), root, product_inventory(root), scratch=scratch,
                                        link_roots=link_roots)


class DeploymentTests(unittest.TestCase):
    def test_version_comes_from_the_macos_arm64_load_command(self):
        output = ('Mach header\nLoad command 0\n      cmd LC_BUILD_VERSION\n'
                  '  cmdsize 32\n platform 1\n    minos 14.0\n      sdk 14.4\n')
        self.assertEqual(files.deployment_command(output), {'command': 'LC_BUILD_VERSION',
                                                            'minimum': '14.0', 'sdk': '14.4'})
        with self.assertRaisesRegex(ValueError, 'identify macOS'):
            files.deployment_command(output.replace('platform 1', 'platform 2'))
        with self.assertRaisesRegex(ValueError, 'Expected one macOS deployment'):
            files.deployment_command(output+output.replace('command 0', 'command 1'))
        self.assertLess(files.os_version('13.9'), files.os_version('14.0'))


if __name__ == '__main__':
    unittest.main()
