"""Focused Phase 1E.5 packaging fixtures."""
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import package_release as package
import package_release_vm as app_vm
from release_materials import digest, encoded, product_inventory, sha
from release_package_archive import (archive_members, check_payload, create_archive, extract_archive,
                                     metadata_observations, new_extraction_root, open_archive, prefixed)


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix='meshchan package test ')
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name).resolve()
        self.stage = self.root/'stage'/'Meshchan engineering'
        self.app = self.stage/'Meshchan.app'
        self.framework = self.app/'Contents/Frameworks/Test.framework'
        self.release = self.framework/'Versions/A'
        self.release.mkdir(parents=True)
        self.app.chmod(0o751)
        self.release.chmod(0o750)
        self.binary = self.release/'Test'
        self.binary.write_bytes(b'executable')
        self.binary.chmod(0o754)
        (self.framework/'Versions/Current').symlink_to('./A')
        (self.framework/'Test').symlink_to('Versions/Current/../A/Test')
        self.archive = self.root/'package input.tar'
        self.links = (self.stage.name+'/Meshchan.app',)
        self.expected = prefixed(self.stage.name, product_inventory(self.stage))
        self.sentinel = self.root/'sentinel'
        self.sentinel.write_bytes(b'keep')

    def test_framework_archive_preserves_raw_links_modes_and_independence(self):
        stamp = create_archive(self.archive, self.stage, self.expected)
        self.assertEqual(stamp, package.file_stamp(self.archive))
        target = self.root/'fresh external copy'
        with new_extraction_root(target) as fd, open_archive(self.archive) as stream:
            extract_archive(stream, fd, self.expected, self.links)
        check_payload(target/self.stage.name, product_inventory(self.stage))
        extracted = target/self.stage.name/self.binary.relative_to(self.stage)
        extracted.write_bytes(b'changed')
        self.assertEqual(self.binary.read_bytes(), b'executable')
        with self.assertRaisesRegex(ValueError, 'differs'):
            check_payload(target/self.stage.name, product_inventory(self.stage))

    def test_raw_link_change_and_mode_change_cannot_hide_behind_same_target(self):
        expected = product_inventory(self.app)
        link = self.framework/'Test'
        link.unlink()
        link.symlink_to('Versions/A/Test')
        with self.assertRaisesRegex(ValueError, 'Test'):
            check_payload(self.app, expected)
        link.unlink()
        link.symlink_to('Versions/Current/../A/Test')
        for path in (self.app, self.release, self.binary):
            old = path.stat().st_mode & 0o777
            with self.subTest(path=path):
                path.chmod(0o755)
                with self.assertRaisesRegex(ValueError, 'differs'):
                    check_payload(self.app, expected)
                path.chmod(old)

    def test_member_collisions_special_files_and_escape_are_rejected_before_writes(self):
        valid = self.stage.name
        for name, kind in (
            (str(self.sentinel), tarfile.REGTYPE), ('../sentinel', tarfile.REGTYPE),
            (valid, tarfile.DIRTYPE), (valid+'/Meshchan.app', tarfile.REGTYPE),
            (valid+'/Meshchan.app/pipe', tarfile.FIFOTYPE),
            (valid+'/Meshchan.app/hardlink', tarfile.LNKTYPE),
        ):
            with self.subTest(name=name, kind=kind):
                stream = io.BytesIO()
                expected = dict(self.expected)
                if name.endswith(('/pipe', '/hardlink')):
                    expected[name] = package.bytes_entry(b'') | {'mode': 0o644}
                with tarfile.open(fileobj=stream, mode='w:') as writer:
                    writer.add(self.stage, arcname=valid)
                    member = tarfile.TarInfo(name)
                    member.type = kind
                    member.linkname = '../sentinel' if kind == tarfile.LNKTYPE else ''
                    writer.addfile(member)
                stream.seek(0)
                target = self.root/'unsafe extraction'
                with new_extraction_root(target) as fd, self.assertRaises(ValueError):
                    extract_archive(stream, fd, expected, self.links)
                self.assertEqual(list(target.iterdir()), [])
                target.rmdir()
                self.assertEqual(self.sentinel.read_bytes(), b'keep')

    def test_raw_link_component_walk_rejects_dangling_escape_cycle_and_bad_access(self):
        link = self.framework/'Test'
        relative = self.stage.name+'/'+link.relative_to(self.stage).as_posix()
        for raw in ('missing/../Versions/A/Test', 'Versions/A/Test/../Test',
                    'Versions/A/Test/', 'Versions/Current/../../../../../../..',
                    '../../../../sentinel', str(self.sentinel), 'Test'):
            with self.subTest(raw=raw):
                link.unlink()
                link.symlink_to(raw)
                expected = self.expected | {relative: self.expected[relative] | {'symlink': raw}}
                stream = io.BytesIO()
                with tarfile.open(fileobj=stream, mode='w:') as writer:
                    writer.add(self.stage, arcname=self.stage.name)
                stream.seek(0)
                target = self.root/'unsafe link extraction'
                with new_extraction_root(target) as fd, self.assertRaises(ValueError):
                    extract_archive(stream, fd, expected, self.links)
                self.assertEqual(list(target.iterdir()), [])
                target.rmdir()

    def test_wrong_content_rejected_against_bound_inventory(self):
        self.binary.write_bytes(b'0123456789')
        stream = io.BytesIO()
        with tarfile.open(fileobj=stream, mode='w:') as writer:
            writer.add(self.stage, arcname=self.stage.name)
        stream.seek(0)
        with tarfile.open(fileobj=stream) as reader:
            with self.assertRaisesRegex(ValueError, 'file content'):
                archive_members(reader, self.expected, self.links)

    def test_appended_archive_rejected_before_writes(self):
        create_archive(self.archive, self.stage, self.expected)
        with self.archive.open('ab') as stream:
            with tarfile.open(fileobj=stream, mode='w:') as appended:
                member = tarfile.TarInfo('../sentinel')
                appended.addfile(member)
        target = self.root/'external extraction'
        with new_extraction_root(target) as fd, open_archive(self.archive) as stream:
            with self.assertRaisesRegex(ValueError, 'data after tar end'):
                extract_archive(stream, fd, self.expected, self.links)
        self.assertEqual(list(target.iterdir()), [])
        self.assertEqual(self.sentinel.read_bytes(), b'keep')

    def test_extraction_writes_remain_in_the_original_directory(self):
        create_archive(self.archive, self.stage, self.expected)
        destination = self.root/'fresh external copy'
        original = self.root/'original extraction directory'
        unrelated = self.root/'another directory'
        unrelated.mkdir()

        def rename_after_validation(*args):
            members = archive_members(*args)
            destination.rename(original)
            destination.symlink_to(unrelated, target_is_directory=True)
            return members

        with (new_extraction_root(destination) as fd, open_archive(self.archive) as stream,
              patch('release_package_archive.archive_members', side_effect=rename_after_validation)):
            extract_archive(stream, fd, self.expected, self.links)
        self.assertEqual(list(unrelated.iterdir()), [])
        check_payload(original/self.stage.name, product_inventory(self.stage))

    def test_extraction_root_creation_refuses_symlinked_ancestors(self):
        unrelated = self.root/'another directory'
        unrelated.mkdir()
        alias = self.root/'alias'
        alias.symlink_to(unrelated, target_is_directory=True)
        with self.assertRaises(OSError):
            with new_extraction_root(alias/'new extraction'):
                self.fail('Created an extraction root through an alias')
        self.assertEqual(list(unrelated.iterdir()), [])

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS metadata policy')
    def test_unhandled_resource_metadata_is_rejected(self):
        subprocess.run(['/usr/bin/xattr', '-w', 'org.meshchan.test', 'preserve', self.binary], check=True)
        with self.assertRaisesRegex(ValueError, 'extended attributes'):
            metadata_observations(self.app, product_inventory(self.app))


class PackageTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix='meshchan package fixture ')
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name).resolve()
        self.source = self.root/'frozen checkout'
        self.run_id = 'build/phase-1e4/run-001'
        self.run = self.source/self.run_id
        self.materials = self.run/'materials'
        self.materials.mkdir(parents=True)
        self.material = self.materials/'corresponding source.tar'
        self.material.write_bytes(b'accepted source archive')
        self.app, self.cli = package.build.product_paths(self.run)
        self.products = {}
        for label, directory, leaf in [('app', self.app, 'runner'), ('cli', self.cli, 'lib/libsqlite3.dylib')]:
            path = directory/leaf
            path.parent.mkdir(parents=True)
            path.write_bytes(label.encode())
            self.products[label] = product_inventory(directory)
        self.commit = 'a'*40
        self.index_paths = [self.run/name for name in package.INDEXES]
        self.index_paths[1].parent.mkdir()
        self.index_paths[2].write_bytes(encoded(self.products))
        self.index_paths[1].write_bytes(encoded({'sourceCommit': self.commit, 'steps': [],
            'candidateInventoriesSha256': digest(self.index_paths[2])}))
        self.manifest = self.materials/'materials-manifest.json'
        self.manifest.write_bytes(encoded({'sourceCommit': self.commit, 'openGates': [],
            'products': {'buildReceipt': {'sha256': digest(self.index_paths[1])}},
            'materials': {self.material.name: package.file_entry(self.material)}}))
        self.info = {
            'runIdentity': self.run_id, 'sourceCommit': self.commit, 'engineeringDirtyMode': False,
            'workingTree': [], 'recipeVersion': 55,
            'identity': {'productVersion': '0.1.0-rc.1', 'target': 'macos-arm64'},
            'evidence': {p.name: {'path': p.relative_to(self.source).as_posix(), 'sha256': digest(p)}
                         for p in self.index_paths[1:]},
            'materials': {'status': 'PASS', 'arguments': {'output': str(self.materials)},
                          'references': {self.manifest.name: {'path': self.manifest.relative_to(
                              self.source).as_posix(), 'sha256': digest(self.manifest)}}},
        }
        self.pin = self.write_index()

    def write_index(self):
        self.index_paths[0].write_bytes(encoded(self.info))
        return digest(self.index_paths[0])

    def snapshot(self):
        return package.snapshot(self.source, self.run, self.info, self.pin)

    def test_frozen_admission_and_external_digest(self):
        self.assertEqual(package.selected_info(self.source, self.run_id, self.pin)[0], self.run)
        self.info['engineeringDirtyMode'] = True
        with self.assertRaisesRegex(ValueError, 'frozen source'):
            package.selected_info(self.source, self.run_id, self.write_index())
        self.info['engineeringDirtyMode'] = False
        self.info['materials']['status'] = 'NOT_RUN'
        with self.assertRaisesRegex(ValueError, 'strict materials'):
            package.selected_info(self.source, self.run_id, self.write_index())
        with self.assertRaisesRegex(ValueError, 'SHA-256'):
            package.selected_info(self.source, self.run_id, self.pin)
        self.info['materials']['status'] = 'PASS'
        self.info['runIdentity'] = 'build/phase-1e4/run-002'
        with self.assertRaisesRegex(ValueError, 'Selected build run'):
            package.selected_info(self.source, self.run_id, self.write_index())

    def test_frozen_checker_and_helpers_must_match_recorded_bytes(self):
        folder = self.source/'tool'
        folder.mkdir()
        hashes = {}
        for name in package.build.HELPERS:
            path = folder/name
            path.write_text(name)
            hashes['tool/'+name] = digest(path)
        info = self.info | {'helperHashes': hashes}
        with patch.object(package, 'git', return_value=self.commit+'\n'):
            package.verify_frozen_helpers(self.source, info)
            (folder/'build_release.py').write_text('changed')
            with self.assertRaisesRegex(ValueError, 'Frozen helper tool/build_release.py'):
                package.verify_frozen_helpers(self.source, info)
        with patch.object(package, 'git', return_value='b'*40):
            with self.assertRaisesRegex(ValueError, 'checkout commit'):
                package.verify_frozen_helpers(self.source, info)

    def test_receipt_and_material_manifest_cannot_be_rebound_by_local_edit(self):
        self.snapshot()
        self.index_paths[1].write_bytes(b'{}')
        with self.assertRaisesRegex(ValueError, 'Bound file'):
            self.snapshot()
        self.info['evidence']['build-receipt.json']['sha256'] = digest(self.index_paths[1])
        self.pin = self.write_index()
        self.index_paths[1].write_bytes(encoded({'sourceCommit': self.commit, 'steps': [],
            'candidateInventoriesSha256': digest(self.index_paths[2])}))
        self.info['evidence']['build-receipt.json']['sha256'] = digest(self.index_paths[1])
        self.manifest.write_bytes(self.manifest.read_bytes().replace(b'accepted', b'forged')+b'\n')
        self.pin = self.write_index()
        with self.assertRaisesRegex(ValueError, 'materials-manifest.json'):
            self.snapshot()

    def test_snapshot_rejects_an_index_replaced_after_hashing(self):
        entry = package.file_entry
        for name, path in zip(package.INDEXES[1:], self.index_paths[1:]):
            with self.subTest(index=name):
                original = path.read_bytes()

                def replace_after_hash(candidate):
                    value = entry(candidate)
                    if candidate == path:
                        # JSON remains equivalent, but these are different bytes.
                        path.write_bytes(original+b'\n')
                    return value

                try:
                    with patch.object(package, 'file_entry', side_effect=replace_after_hash):
                        with self.assertRaisesRegex(ValueError, 'Parsed build index '+name):
                            self.snapshot()
                finally:
                    path.write_bytes(original)

    def test_relocated_validator_rejects_a_different_build_receipt_before_validation(self):
        accepted = digest(self.index_paths[1])
        self.index_paths[1].write_bytes(self.index_paths[1].read_bytes()+b'\n')
        result = subprocess.run(
            [sys.executable, '-B', '-c', package.VALIDATOR, accepted,
             self.index_paths[1], self.app, self.cli],
            cwd=package.ROOT, env=package.controlled_environment(),
            text=True, capture_output=True, timeout=10,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertIn('Native validator build receipt differs from the accepted SHA-256', result.stderr)

    def test_missing_app_cli_or_material_cannot_be_covered_by_a_partial_tree(self):
        for path in (self.app/'runner', self.cli/'lib/libsqlite3.dylib', self.material):
            with self.subTest(path=path):
                original = path.read_bytes()
                path.unlink()
                with self.assertRaises((ValueError, FileNotFoundError)):
                    self.snapshot()
                path.write_bytes(original)

    def test_material_extra_alias_and_hardlink_rejected(self):
        extra = self.materials/'extra'
        extra.touch()
        with self.assertRaisesRegex(ValueError, 'Unlisted material'):
            self.snapshot()
        extra.unlink()
        original = self.root/'external file'
        self.material.rename(original)
        self.material.symlink_to(original)
        with self.assertRaisesRegex(ValueError, 'Aliased or invalid'):
            self.snapshot()
        self.material.unlink()
        os.link(original, self.material)
        with self.assertRaisesRegex(ValueError, 'Aliased or invalid'):
            self.snapshot()

    def test_output_collisions_aliases_and_retry(self):
        base = self.root/'checkout'
        outputs = base/'build/phase-1e5'
        outputs.mkdir(parents=True)
        existing = outputs/'an existing run'
        existing.mkdir()
        alias = outputs/'alias'
        alias.symlink_to(existing)
        with patch.object(package, 'ROOT', base), patch.object(package, 'git', side_effect=['', 'ignored']*3):
            with self.assertRaisesRegex(ValueError, 'Preserve'):
                package.output_path(existing, True)
            self.assertEqual(package.output_path(existing, False), existing)
            with self.assertRaisesRegex(ValueError, 'symlink'):
                package.output_path(alias, True)
            self.assertEqual(package.output_path(outputs/'fresh run', True), outputs/'fresh run')
        for path in (self.source, self.source.parent, self.source/'inside'):
            with self.assertRaisesRegex(ValueError, 'overlaps'):
                package.disjoint(path, [self.source])

    def test_output_collisions_with_case_insensitive_alias(self):
        alias = self.source.with_name(self.source.name.upper())
        if not alias.exists():
            self.skipTest('Requires a case-insensitive filesystem')
        self.assertEqual(package.canonical(alias/'new'), alias/'new')
        for output, protected in ((alias/'new', self.source), (alias, self.source/'cache'/'new')):
            with self.assertRaisesRegex(ValueError, 'overlaps'):
                package.disjoint(output, [protected])

    def link_build(self, checkout, target):
        checkout.mkdir(exist_ok=True)
        subprocess.run([*package.GIT, 'init', '-q', checkout], check=True, capture_output=True)
        (checkout/'.gitignore').write_text('build/\n/build\n')
        logical = checkout/'build'
        if logical.exists():
            logical.rename(target)
        else:
            target.mkdir()
        logical.symlink_to(target, target_is_directory=True)
        return target

    def test_linked_package_and_frozen_build_run_with_separate_physical_outputs(self):
        self.info['toolchain'] = {'host': {'os': 'Darwin', 'architecture': 'arm64'}}
        self.pin = self.write_index()
        checkout = self.root/'packaging checkout'
        output_build = self.link_build(checkout, self.root/'packaging disk')
        source_build = self.link_build(self.source, self.root/'frozen build disk')
        physical_run = source_build/'phase-1e4/run-001'
        output = output_build/'phase-1e5/new package'
        args = SimpleNamespace(command='package', source_checkout=self.source, build_run=self.run_id,
                               expected_build_info_sha256=self.pin,
                               output=checkout/'build/phase-1e5/new package',
                               extract_root=self.root/'package extraction', vm_config=None, timeout=10)
        count = 0
        phases = ('check-inputs', 'check-products', 'materials-recheck', 'check-commit')

        def run_command(_runner, name, argv, cwd):
            nonlocal count
            self.assertEqual(cwd, self.source)
            if name == 'frozen-check':
                self.assertEqual(argv[argv.index('--output')+1], self.run_id)
                self.assertIn('--require-frozen', argv)
                count += 1
                for phase in phases:
                    folder = physical_run/'evidence'/f'{phase}-{count}'
                    folder.mkdir()
                    (folder/'build-receipt.json').write_text('{"status":"PASS"}\n')
                return json.dumps({'status': 'PASS', 'buildStatus': 'PASS',
                                   'materialsStatus': 'PASS', 'run': self.run_id})
            self.assertEqual(name, 'relocated-products')
            self.assertIn(physical_run/'evidence/build-receipt.json', argv)
            return '{"status":"PASS"}'

        with (patch.object(package, 'ROOT', checkout),
              patch.object(package.platform, 'system', return_value='Darwin'),
              patch.object(package.platform, 'machine', return_value='arm64'),
              patch.object(package, 'protected_caches', return_value=[]),
              patch.object(package, 'verify_frozen_helpers'),
              patch.object(package, 'tool_identity', return_value={'inputs': {}}),
              patch.object(package, 'validate_cli', return_value={'status': 'PASS'}),
              patch.object(package.build.Runner, 'command', autospec=True, side_effect=run_command)):
            for directory in (source_build, output_build):
                with self.subTest(directory=directory):
                    overlapping = SimpleNamespace(**(vars(args) | {'extract_root': directory/'extraction'}))
                    with self.assertRaisesRegex(ValueError, 'overlaps'):
                        package.run_package(overlapping)
                    self.assertFalse(output.exists())
                    self.assertFalse(overlapping.extract_root.exists())
            original = package.run_package(args)
            original_receipt = output/'evidence/package-receipt.json'
            pin = digest(original_receipt)
            checked = package.run_package(SimpleNamespace(**(vars(args) | {
                'command': 'check', 'package_run': output, 'extract_root': self.root/'check extraction',
                'expected_package_receipt_sha256': pin,
            })))

        self.assertEqual(count, 2)
        self.assertEqual(digest(original_receipt), pin)
        self.assertEqual(original['archive'], checked['archive'])
        self.assertEqual(original['packageInfo'], checked['packageInfo'])
        for record in (original, checked):
            self.assertEqual(record['status'], 'INCOMPLETE')
            self.assertEqual(record['buildRun'], self.run_id)
            self.assertTrue(Path(record['stage']).is_relative_to(output))
        for phase, ref in checked['frozenVerification']['ledgers'].items():
            self.assertEqual(ref['path'], f'{self.run_id}/evidence/{phase}-2/build-receipt.json')
            self.assertEqual(ref['sha256'], digest(self.source/ref['path']))

    def test_linked_package_rejects_nested_alias_and_tracked_build(self):
        checkout = self.root/'packaging checkout'
        physical = self.link_build(checkout, self.root/'packaging disk')
        phase = physical/'phase-1e5'
        phase.mkdir()
        existing = phase/'existing run'
        existing.mkdir()
        (phase/'alias').symlink_to(existing)
        with patch.object(package, 'ROOT', checkout):
            with self.assertRaisesRegex(ValueError, 'symlink'):
                package.output_path(checkout/'build/phase-1e5/alias', new=False)
            subprocess.run([*package.GIT, '-C', checkout, 'add', '-f', '--', 'build'],
                           check=True, capture_output=True)
            with self.assertRaisesRegex(ValueError, 'tracked source'):
                package.output_path(checkout/'build/phase-1e5/new run', new=True)

    def test_linked_build_rejects_git_metadata_paths_with_whitespace(self):
        for index, name in enumerate(('metadata ', 'metadata\nwith\rcarriage return')):
            with self.subTest(name=name):
                checkout = self.root/f'checkout {index}'
                metadata = self.root/name
                subprocess.run([*package.GIT, 'init', '-q', '--separate-git-dir', metadata, checkout],
                               env=package.controlled_environment(), check=True, capture_output=True)
                target = metadata/'release build'
                target.mkdir()
                (checkout/'build').symlink_to(target, target_is_directory=True)

                with self.assertRaisesRegex(ValueError, 'overlaps.*Git metadata'):
                    package.build_directory(checkout)
                self.assertEqual(package.git_metadata(checkout), [metadata, metadata])

    def test_linked_package_admission_accounts_for_checkout_case_aliases(self):
        checkout = self.root/'packaging checkout'
        physical = self.link_build(checkout, self.root/'packaging disk')
        local, tracked = checkout/'build', checkout/'BuIlD'
        local.unlink()
        tracked.symlink_to(physical, target_is_directory=True)
        subprocess.run([*package.GIT, '-C', checkout, 'add', '-f', '--', tracked.name],
                       check=True, capture_output=True)
        path = local/'phase-1e5/run'
        with patch.object(package, 'ROOT', checkout):
            if local.is_symlink():
                with self.assertRaisesRegex(ValueError, 'tracked source'):
                    package.output_path(path, new=True)
            else:
                local.symlink_to(physical, target_is_directory=True)
                self.assertEqual(package.output_path(path, new=True), physical/path.relative_to(local))

    def verify(self, command, name, initial, tools=None, receipt_pin=None):
        output = self.root/'packaging artifacts'
        evidence = output/'evidence'
        evidence.mkdir(parents=True, exist_ok=True)
        extract = self.root/name
        args = SimpleNamespace(command=command, vm_config=None, expected_build_info_sha256=self.pin,
                               expected_package_receipt_sha256=receipt_pin)
        runner = SimpleNamespace(interrupted=[], command=lambda *args, **kwargs: '{"status":"PASS"}')
        tools = {'inputs': {}} if tools is None else tools
        record = {'formatVersion': 1, 'command': command, 'sourceCheckout': str(self.source),
                  'buildRun': self.run_id, 'sourceCommit': self.commit, 'identity': self.info['identity'],
                  'packagingTool': tools}
        with patch.object(package, 'validate_cli', return_value={'status': 'PASS'}):
            package.verify_package(args, output, extract, evidence, runner, record, initial,
                                   tools, self.source, self.run, self.info)
        if command == 'package':
            package.build.write(evidence/'package-receipt.json', record)
        return output, record

    def test_forged_stage_and_manifest_fail_independent_check(self):
        initial = self.snapshot()
        output, record = self.verify('package', 'package extraction', initial)
        self.verify('check', 'fresh check', initial)
        stage = Path(record['stage'])
        (stage/'Meshchan.app/runner').write_bytes(b'tampered')
        manifest = stage/'package-info.json'
        forged = json.loads(manifest.read_bytes())
        forged['payloadInventory']['Meshchan.app/runner'] = package.file_entry(stage/'Meshchan.app/runner')
        manifest.write_bytes(encoded(forged))
        with self.assertRaisesRegex(ValueError, 'differs'):
            self.verify('check', 'another fresh check', initial)
        self.assertFalse((self.root/'another fresh check').exists())
        self.assertTrue((output/'evidence/package-receipt.json').exists())

    def test_archived_packager_can_be_rechecked_from_externally_pinned_receipt(self):
        initial = self.snapshot()
        tool = self.root/'packer.py'
        tool.write_bytes(b'validated original tool')

        def identity():
            return {'inputs': {tool.name: package.file_entry(tool)}}

        with patch.object(package, 'ROOT', self.root):
            output, original = self.verify('package', 'package extraction', initial, identity())
            receipt = output/'evidence/package-receipt.json'
            pin = digest(receipt)
            tool.write_bytes(b'reviewed tool')
            with self.assertRaisesRegex(ValueError, 'differs'):
                self.verify('check', 'unpinned check', initial, identity())
            _, checked = self.verify('check', 'pinned check', initial, identity(), pin)
            self.assertEqual(checked['archive'], original['archive'])
            self.assertEqual(checked['packageInfo'], original['packageInfo'])
            self.assertEqual(checked['packagingTool'], identity())
            self.assertEqual(checked['originalPackageReceiptSha256'], pin)
            receipt.write_bytes(receipt.read_bytes()+b'\n')
            with self.assertRaisesRegex(ValueError, 'receipt SHA-256'):
                self.verify('check', 'modified receipt', initial, identity(), pin)
            self.assertFalse((self.root/'modified receipt').exists())

    def test_check_rejects_malformed_original_receipt_version(self):
        initial = self.snapshot()
        output, record = self.verify('package', 'package extraction', initial)
        package.build.write(output/'evidence/package-receipt.json', record | {'formatVersion': True})
        with self.assertRaisesRegex(ValueError, 'Original package receipt formatVersion differs'):
            self.verify('check', 'fresh check', initial)
        self.assertFalse((self.root/'fresh check').exists())

    def test_copy_source_drift_is_detected(self):
        initial = self.snapshot()
        create = package.create_stage

        def mutate(*args):
            create(*args)
            self.material.write_bytes(b'changed during copy')

        with patch.object(package, 'create_stage', side_effect=mutate):
            with self.assertRaisesRegex(ValueError, 'Accepted material file bytes'):
                self.verify('package', 'unwritten extraction', initial)
        self.assertFalse((self.root/'unwritten extraction').exists())

    def test_archive_replaced_after_creation_even_with_same_bytes(self):
        initial = self.snapshot()

        def replace(path, *args):
            stamp = create_archive(path, *args)
            replacement = path.with_suffix('.replacement')
            replacement.write_bytes(path.read_bytes())
            replacement.replace(path)
            return stamp

        with patch.object(package, 'create_archive', side_effect=replace):
            with self.assertRaisesRegex(ValueError, 'Archive opened'):
                self.verify('package', 'archive replaced', initial)
        self.assertEqual(list((self.root/'archive replaced').iterdir()), [])

    def test_runtime_product_changes_are_rejected(self):
        initial = self.snapshot()

        def mutate(bundle, *args):
            (bundle/'lib/libsqlite3.dylib').unlink()
            return {'status': 'PASS'}

        with patch.object(package, 'validate_cli', side_effect=mutate):
            self.run_fixture_with_runtime_failure(initial)
        self.assertFalse((self.root/'runtime package/evidence/package-receipt.json').exists())

    def test_runtime_stage_ancestor_symlink_rejected_even_with_same_files(self):
        initial = self.snapshot()
        root = self.root/'runtime package'/'stage'

        def alias(*args):
            moved = root.rename(self.root/'external staging')
            root.symlink_to(moved, target_is_directory=True)
            return {'status': 'PASS'}

        with patch.object(package, 'validate_cli', side_effect=alias):
            self.run_fixture_with_runtime_failure(initial, 'symlink aliases')

    def test_runtime_replacement_of_extraction_root_is_rejected(self):
        initial = self.snapshot()
        root = self.root/'runtime extraction'

        def replace(*args):
            moved = root.rename(self.root/'original runtime extraction')
            package.shutil.copytree(moved, root, symlinks=True)
            return {'status': 'PASS'}

        with patch.object(package, 'validate_cli', side_effect=replace):
            self.run_fixture_with_runtime_failure(initial, 'differs from the owned root')

    def test_package_vm_gate_binds_the_receipt_to_the_extracted_app(self):
        initial = self.snapshot()
        run_id = '20261120T000000Z-product-42'
        cases = {
            'matching': {},
            'overlapping runtime state': None,
            'old extraction': {'app': '/tmp/earlier extraction/Meshchan.app'},
            'different manifest': {'packageInfoSha256': '1'*64},
            'different App inventory': {'appInventorySha256': '2'*64},
            'different guest run': {'guestRun': '20261120T000000Z-product-43'},
            'incomplete shutdown': {'guestExecutorExit': None},
            'boolean exit status': {'guestExecutorExit': False},
            'floating-point exit status': {'guestExecutorExit': 0.0},
            'unreleased guest lock': {'guestLockReleased': False},
            'numeric lock release': {'guestLockReleased': 1},
        }
        for case, change in cases.items():
            with self.subTest(case=case):
                output = self.root/case
                evidence = output/'evidence'
                evidence.mkdir(parents=True)
                extract = self.root/(case+' extraction')
                config = self.root/'vm.json'
                runtime_dir = self.source/'owned source sockets' if change is None else self.root/'private VM state'
                config_bytes = encoded({'runtime_dir': str(runtime_dir)})
                config.write_bytes(config_bytes)
                args = SimpleNamespace(command='package', vm_config=config,
                                       expected_build_info_sha256=self.pin)

                def run_command(name, argv, cwd):
                    if name == 'vm-app-runtime':
                        self.assertIsNotNone(change, 'An overlapping configuration launched guest work')
                        private_config, = [Path(value.removeprefix('--config=')) for value in argv
                                           if isinstance(value, str) and value.startswith('--config=')]
                        self.assertNotEqual(private_config, config)
                        self.assertEqual(private_config.read_bytes(), config_bytes)
                        self.assertEqual(private_config.stat().st_mode & 0o777, 0o600)
                        report = evidence/'vm-app/runtime.json'
                        report.parent.mkdir()
                        package.build.write(report, {
                            'status': 'PASS', 'guestRun': run_id, 'identity': self.info['identity'],
                            'app': str(argv[argv.index('--app')+1]),
                            'packageInfoSha256': digest(argv[argv.index('--package-info')+1]),
                            'appInventorySha256': sha(encoded(self.products['app'])),
                            'guestInventoryBefore': 'PASS', 'guestInventoryAfter': 'PASS',
                            'guestSignature': 'PASS', 'guestExecutorExit': 0, 'guestLockReleased': True,
                        } | change)
                        return json.dumps({'status': 'PASS', 'guestRun': run_id})
                    return '{"status":"PASS"}'

                runner = SimpleNamespace(interrupted=[], command=run_command)
                record = {}
                with patch.object(package, 'validate_cli', return_value={'status': 'PASS'}):
                    def verify():
                        package.verify_package(args, output, extract, evidence, runner, record, initial,
                                               {'inputs': {}}, self.source, self.run, self.info)

                    if change is None:
                        with self.assertRaisesRegex(ValueError, 'VM runtime_dir overlaps a selected release input'):
                            verify()
                        self.assertNotIn('vmAppReport', record)
                    elif change:
                        with self.assertRaisesRegex(ValueError, 'VM App receipt '+next(iter(change))):
                            verify()
                        self.assertNotEqual(record['vmAppStatus'], 'PASS')
                        self.assertNotIn('vmAppReport', record)
                    else:
                        verify()
                        self.assertEqual(record['vmAppStatus'], 'PASS')
                        self.assertEqual(record['vmAppReport']['sha256'], digest(evidence/'vm-app/runtime.json'))

    def test_cli_version_with_normal_line_ending_reaches_storage_check(self):
        runner = Mock()
        runner.command.side_effect = ['meshctl 0.1.0-rc.1\n', ValueError('test storage boundary')]
        with self.assertRaisesRegex(ValueError, 'test storage boundary'):
            package.validate_cli(self.cli, self.root, runner, '0.1.0-rc.1')
        self.assertEqual(runner.command.call_args.args[0], 'cli-write')

    def test_cli_runtime_rejects_malformed_report_field_types(self):
        body = 'Offline sample 中文\r\nsecond line\n'
        receipt = {'exitCode': 0, 'operationSucceeded': True, 'schemaVersion': 1,
                   'storageClose': {'state': 'closed'},
                   'draft': {'title': 'Packaging smoke', 'body': body, 'revision': 1,
                             'bodyUtf8ByteLength': len(body.encode())}}
        cases = (
            ('exitCode', receipt | {'exitCode': False}),
            ('operationSucceeded', receipt | {'operationSucceeded': 1}),
            ('schemaVersion', receipt | {'schemaVersion': True}),
            ('revision', receipt | {'draft': receipt['draft'] | {'revision': 1.0}}),
        )
        for field, invalid in cases:
            with self.subTest(field=field):
                runner = Mock()
                runner.command.side_effect = ['meshctl 0.1.0-rc.1\n', json.dumps(invalid)]
                with self.assertRaisesRegex(ValueError, field+' differs'):
                    package.validate_cli(self.cli, self.root, runner, '0.1.0-rc.1')
                self.assertEqual(runner.command.call_count, 2)

    def run_fixture_with_runtime_failure(self, initial, message='libsqlite3.dylib'):
        output = self.root/'runtime package'
        evidence = output/'evidence'
        evidence.mkdir(parents=True)
        args = SimpleNamespace(command='package', vm_config=None, expected_build_info_sha256=self.pin)
        runner = SimpleNamespace(interrupted=[], command=lambda *args, **kwargs: '{"status":"PASS"}')
        with self.assertRaisesRegex(ValueError, message):
            package.verify_package(args, output, self.root/'runtime extraction', evidence, runner, {},
                                   initial, {'inputs': {}}, self.source, self.run, self.info)

    def test_owned_runner_timeout_exit_and_interrupt_keep_evidence(self):
        evidence = self.root/'command evidence'
        evidence.mkdir()
        runner = package.build.Runner(self.root, evidence, {'steps': []}, package.controlled_environment(),
                                      timeout=0.5, show_progress=False)
        commands = [('failure', 'import sys; print("diagnostic", file=sys.stderr); sys.exit(7)',
                     subprocess.CalledProcessError),
                    ('deadline', 'import time; print("started", flush=True); time.sleep(30)', TimeoutError)]
        for name, code, error in commands:
            with self.subTest(name=name):
                with self.assertRaises(error):
                    runner.command(name, [sys.executable, '-c', code], self.root)
                step = runner.receipt['steps'][-1]
                self.assertTrue(step['processTree']['childReaped'])
                self.assertTrue(step['processTree']['exited'])
                self.assertNotEqual(step['exitCode'], 0)
                self.assertTrue((self.root/step['stderrLog']).exists())
        runner.interrupted = [signal.SIGTERM]
        with self.assertRaises(package.build.GateInterrupted):
            runner.command('interrupted', [sys.executable, '-c', 'raise SystemExit(0)'], self.root)
        self.assertIsNone(runner.receipt['steps'][-1]['logSha256'])


class AppVMTests(unittest.TestCase):
    def test_checked_vm_configuration_snapshots_exact_private_bytes_with_consumer_cwd(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            protected = root/'Pinned Product'
            protected.mkdir()
            consumer = root/'consumer'
            consumer.mkdir()
            config = consumer/'vm.json'
            data = b'{ "runtime_dir": "../separate VM state", "credentials_file": "private path.json" }\n'
            config.write_bytes(data)
            with (patch.dict(os.environ, {'TMPDIR': str(protected)}),
                  patch.object(tempfile, 'NamedTemporaryFile', wraps=tempfile.NamedTemporaryFile) as stage):
                staged = app_vm.checked_vm_configuration(Path('vm.json'), [protected], cwd=consumer)
                stage.assert_not_called()
                config.write_bytes(encoded({'runtime_dir': '../Pinned Product/child'}))
                with staged as snapshot:
                    stage.assert_called_once()
                    self.assertEqual(snapshot.read_bytes(), data)
                    self.assertEqual(snapshot.stat().st_mode & 0o777, 0o600)
                    self.assertFalse(snapshot.is_relative_to(protected))
            self.assertFalse(snapshot.exists())
            with self.assertRaisesRegex(ValueError, 'VM runtime_dir overlaps a selected release input'):
                app_vm.checked_vm_configuration(Path('vm.json'), [protected], cwd=consumer)
            alias = protected.with_name('pinned product')
            if alias.exists():
                config.write_bytes(encoded({'runtime_dir': '../pinned product/case alias child'}))
                with self.assertRaisesRegex(ValueError, 'VM runtime_dir overlaps a selected release input'):
                    app_vm.checked_vm_configuration(Path('vm.json'), [protected], cwd=consumer)

            state_parent = root/'deferred VM location'
            config.write_bytes(encoded({'runtime_dir': str(state_parent/'sockets')}))
            staged = app_vm.checked_vm_configuration(config, [protected])
            state_parent.symlink_to(protected, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'VM runtime_dir overlaps a selected release input'):
                with staged:
                    self.fail('A runtime path redirected into the protected tree must not be staged')

    def test_configured_vm_runtime_dir_cannot_chmod_the_selected_app(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            app = root/'Meshchan.app'
            app.mkdir()
            app.chmod(0o755)
            (app/'payload').write_bytes(b'Fixture App')
            manifest = root/'package-info.json'
            inventory = prefixed('Meshchan.app', product_inventory(app))
            arguments = self.vm_manifest_arguments(manifest, inventory, signed=False)
            known_hosts = root/'known_hosts'
            known_hosts.write_text('fixture file only\n')
            config = root/'vm.json'
            config.write_bytes(encoded({
                'host': 'fixture.invalid', 'user': 'tester', 'uuid': '01234567-89ab-cdef-0123-456789abcdef',
                'known_hosts': str(known_hosts), 'runtime_dir': str(app),
                'evidence_dir': str(root/'old evidence'), 'guest_root': '/Users/tester/utm-ui-isolation',
            }))
            evidence = root/'evidence'
            args = SimpleNamespace(app=app, evidence=evidence, config=config, **arguments)
            with patch.object(app_vm, 'require_ready_connection', side_effect=ValueError('Unexpected SSH preparation')) as ssh:
                with self.assertRaisesRegex(ValueError, 'VM runtime_dir overlaps a selected release input'):
                    app_vm.run(args)
            ssh.assert_not_called()
            self.assertEqual(app.stat().st_mode & 0o777, 0o755)

    def vm_manifest_arguments(self, path, inventory, *, signed):
        identity = {
            'productVersion': '0.1.0-rc.1', 'appVersion': '0.1.0-rc.1+8', 'appBuild': '8',
            'target': 'macos-arm64', 'apple': {'CFBundleIdentifier': 'org.meshchan.meshchan',
                                           'CFBundleVersion': '8', 'MeshchanProductVersion': '0.1.0-rc.1'},
        }
        info = {'formatVersion': 1, 'identity': identity, 'payloadInventory': inventory}
        if signed:
            public = {'sha1': 'a'*40, 'team': 'ABCDEFGHIJ', 'authority': 'Developer ID Application: Fixture'}
            info['signature'] = {'identity': public, 'items': []}
        data = encoded(info)
        path.write_bytes(data)
        if signed:
            return {'signed_info': path, 'expected_signed_info_sha256': sha(data)}
        return {'package_info': path}

    def test_vm_evidence_cannot_be_created_inside_the_app_or_pinned_full_product(self):
        for signed in (False, True):
            for cli_present in (False, True):
                with (self.subTest(signed=signed, cli_present=cli_present),
                      tempfile.TemporaryDirectory() as directory):
                    root = Path(directory).resolve()
                    candidate = root/'Pinned Candidate'
                    app = candidate/'Meshchan.app'
                    materials = candidate/'materials'
                    app.mkdir(parents=True)
                    materials.mkdir()
                    (app/'payload').write_bytes(b'Fixture App')
                    if cli_present:
                        (candidate/'meshctl').mkdir()
                    inventory = product_inventory(candidate) | {'meshctl': package.DIR}
                    manifest = candidate/('signed-product-info.json' if signed else 'package-info.json')
                    arguments = self.vm_manifest_arguments(manifest, inventory, signed=signed)
                    before = product_inventory(candidate)
                    destinations = [app/'guest evidence', materials/'guest evidence']
                    case_alias = root/'pinned candidate'/'materials'
                    if case_alias.exists():
                        destinations.append(case_alias/'case alias evidence')
                    host = SimpleNamespace(Product=Mock(side_effect=ValueError('Unexpected VM start')))
                    for evidence in destinations:
                        with self.subTest(evidence=evidence), patch.object(app_vm, 'load', return_value=host):
                            args = SimpleNamespace(app=app, evidence=evidence,
                                                   config=root/'vm.json', **arguments)
                            with self.assertRaisesRegex(ValueError, 'VM evidence overlaps a selected runtime input'):
                                app_vm.run(args)
                            self.assertFalse(evidence.exists())
                    host.Product.assert_not_called()
                    self.assertEqual(product_inventory(candidate), before)

    def test_vm_preflight_keeps_runtime_state_out_of_evidence_and_user_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            app = root/'Meshchan.app'
            app.mkdir()
            (app/'payload').write_bytes(b'Fixture App')
            manifest = root/'signed-product-info.json'
            arguments = self.vm_manifest_arguments(manifest, prefixed(app.name, product_inventory(app)), signed=True)
            config = root/'vm.json'
            home = root/'private home'
            user_data = home/app_vm.DEFAULT_DATA_SUBDIR
            output = root/'evidence'
            with patch.object(Path, 'home', return_value=home), patch.object(app_vm, 'require_ready_connection') as ssh:
                for evidence, runtime, error in (
                    (output, output/'private VM socket', 'VM runtime_dir overlaps a selected release input'),
                    (output, user_data/'private VM socket', 'VM runtime_dir overlaps a selected release input'),
                    (user_data/'evidence', root/'private VM socket', 'VM evidence overlaps a selected runtime input'),
                ):
                    with self.subTest(evidence=evidence, runtime=runtime):
                        config.write_bytes(encoded({'runtime_dir': str(runtime)}))
                        args = SimpleNamespace(app=app, evidence=evidence, config=config, **arguments)
                        with self.assertRaisesRegex(ValueError, error):
                            app_vm.run(args)
                        self.assertFalse(evidence.exists())
                ssh.assert_not_called()

    def test_vm_protects_original_and_relocated_cli_from_renamed_or_detached_app_evidence(self):
        for detached in (False, True):
            with self.subTest(detached=detached), tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve()
                candidate = root/'pinned signed candidate'
                (candidate/'meshctl').mkdir(parents=True)
                app_parent = root/'relocated products' if detached else candidate
                app = app_parent/'Renamed copy.app'
                app.mkdir(parents=True)
                app.chmod(package.DIR['mode'])
                (app/'payload').write_bytes(b'Fixture App')
                (app_parent/'meshctl').mkdir(exist_ok=True)
                manifest = candidate/'signed-product-info.json'
                inventory = prefixed('Meshchan.app', product_inventory(app)) | {'meshctl': package.DIR}
                arguments = self.vm_manifest_arguments(
                    manifest, inventory, signed=True)
                for parent in (candidate, app_parent):
                    evidence = parent/'meshctl'/'guest evidence'
                    args = SimpleNamespace(app=app, evidence=evidence, config=root/'vm.json', **arguments)
                    with self.assertRaisesRegex(ValueError, 'VM evidence overlaps a selected runtime input'):
                        app_vm.run(args)
                    self.assertFalse(evidence.exists())

    def test_detached_vm_manifest_and_app_allow_external_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            app = root/'relocated app'/'Detached.app'
            app.mkdir(parents=True)
            app.chmod(package.DIR['mode'])
            (app/'payload').write_bytes(b'Fixture App')
            before = product_inventory(app)
            manifest = root/'manifest-copy.json'
            arguments = self.vm_manifest_arguments(
                manifest, prefixed('Meshchan.app', before) | {'meshctl': package.DIR}, signed=True)
            evidence = root/'guest evidence'
            args = SimpleNamespace(app=app, evidence=evidence, config=root/'vm.json', **arguments)
            args.config.write_bytes(encoded({'runtime_dir': str(root/'private VM state')}))
            with patch.object(app_vm.subprocess, 'run', side_effect=OSError('test compiler boundary')):
                with self.assertRaisesRegex(ValueError, 'test compiler boundary'):
                    app_vm.run(args)
            receipt = json.loads((evidence/'runtime.json').read_bytes())
            self.assertEqual(receipt['signedInfoSha256'], digest(manifest))
            self.assertEqual(receipt['status'], 'FAIL')
            self.assertEqual(product_inventory(app), before)

    def test_vm_receipt_hashes_the_manifest_bytes_used_for_its_app_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root/'package-info.json'
            data = encoded({'identity': {}, 'payloadInventory': {'Meshchan.app': package.DIR}})
            path.write_bytes(data)
            config_data = encoded({'runtime_dir': str(root/'private VM state')})
            args = SimpleNamespace(package_info=path, app=root/'Meshchan.app',
                                   config=root/'vm.json', evidence=Path(os.path.relpath(root/'evidence')))
            args.config.write_bytes(config_data)

            def startup(config, evidence):
                self.assertEqual(evidence, args.evidence.absolute())
                self.assertEqual(Path(config).read_bytes(), config_data)
                self.assertNotEqual(Path(config), args.config)
                raise ValueError('test VM startup boundary')

            host = SimpleNamespace(Product=Mock(side_effect=startup))
            with (patch.object(app_vm, 'load', return_value=host),
                  patch.object(app_vm, 'check_payload', side_effect=lambda *_: path.write_bytes(data+b'\n'))):
                with self.assertRaisesRegex(ValueError, 'test VM startup boundary'):
                    app_vm.run(args)
            host.Product.assert_called_once()
            self.assertFalse(Path(host.Product.call_args.args[0]).exists())
            report = package.build.read(args.evidence/'runtime.json')
            self.assertEqual(report['packageInfoSha256'], sha(data))

    @unittest.skipUnless(sys.platform == 'darwin', 'Uses the macOS guest tar implementation')
    def test_guest_inventory_preserves_long_resource_names_and_link_targets(self):
        with tempfile.TemporaryDirectory(prefix='meshchan guest inventory ') as directory:
            guest = Path(directory)
            app = guest/'Meshchan.app'
            app.mkdir()
            resource = app/('resource-'+'x'*120)
            resource.write_bytes(b'asset')
            (app/'asset link').symlink_to(resource.name)

            def local(command, **kwargs):
                return subprocess.run(['/bin/bash', '-c', command], check=True, **kwargs)

            scratch = guest/'owned scratch'
            scratch.mkdir()
            with patch.object(app_vm.tempfile, 'TemporaryFile', wraps=tempfile.TemporaryFile) as spool:
                app_vm.guest_inventory(SimpleNamespace(remote=local), str(guest), product_inventory(app),
                                       scratch=scratch)
            spool.assert_called_once_with(dir=scratch)

    def test_guest_launch_passes_default_root_and_separate_session_argument(self):
        shared = '/Users/guest/utm-ui-isolation'
        session = shared+'/package.abcd1234'
        vm = SimpleNamespace(root=shared, c={'uuid': 'test-uuid'},
                             remote=Mock(return_value=SimpleNamespace(stdout=session+'\n')))
        self.assertEqual(app_vm.guest_session(vm), session)
        app_vm.start_guest(vm, session)
        command = vm.remote.call_args.args[0]
        self.assertIn('--args test-uuid product '+shared+' '+session, command)
        self.assertIn('shasum -a 256 < '+shared+'/product.sh', command)
        self.assertIn('test ! -e '+shared+'/active.lock', command)

    def test_guest_run_attestation_rejects_other_launch_and_stale_run(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = root/'active.lock'
            lock.mkdir()
            (lock/'pid').write_text('42\n')
            run = '20261120T000000Z-product-42'
            latest = root/'latest-run'
            latest.write_text(str(root/'runs'/run)+'\n')
            fake_ps = root/'ps'
            fake_stat = root/'stat'
            fake_stat.write_text("#!/bin/bash\necho '1:8273'\n")
            fake_stat.chmod(0o700)
            session = str(root/'package.abcd1234')
            other = str(root/'package.efgh5678')
            runner = f'/bin/bash {root}/product.sh test-uuid {root}'
            executor = f'{root}/UTMUIProbe.app/Contents/MacOS/UTMUIProbe test-uuid product {root}'

            def remote(script, **kwargs):
                script = script.replace('/bin/ps', app_vm.q(str(fake_ps)))
                script = script.replace('/usr/bin/stat', app_vm.q(str(fake_stat)))
                return subprocess.run(['/bin/bash', '-c', script],
                                      check=True, **kwargs)

            vm = SimpleNamespace(root=str(root), c={'uuid': 'test-uuid'}, remote=remote,
                                 runpath=lambda token: str(root/'runs'/token))
            for launch, expected in ((other, None), (session, {'run': run, 'lockIdentity': '1:8273'})):
                fake_ps.write_text(f"""#!/bin/bash
case "$*" in
  '-ww -p 42 -o command=') printf '%s\\n' {app_vm.q(runner)} ;;
  '-p 42 -o ppid=') echo '21' ;;
  '-ww -p 21 -o command=') printf '%s\\n' {app_vm.q(executor+' '+launch)} ;;
  *) exit 1 ;;
esac
""")
                fake_ps.chmod(0o700)
                self.assertEqual(app_vm.owned_guest_run(vm, session), expected)
            latest.write_text(str(root/'runs'/'20261120T000000Z-product-43')+'\n')
            self.assertIsNone(app_vm.owned_guest_run(vm, session))

    @unittest.skipUnless(sys.platform == 'darwin', 'Uses macOS stat for the guest lock')
    def test_guest_exit_requires_release_of_its_own_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = root/'active.lock'
            lock.mkdir()
            original = lock.stat()
            run_id = '20261120T000000Z-product-42'
            run_path = root/'runs'/run_id
            run_path.mkdir(parents=True)
            (run_path/'exit-code').write_text('0\n')

            def remote(command, **kwargs):
                return subprocess.run(['/bin/bash', '-c', command], check=True, **kwargs)

            vm = SimpleNamespace(root=str(root), remote=remote,
                                 runpath=lambda token: str(root/'runs'/token))
            product = SimpleNamespace(vm=vm, finish=Mock(), state={
                'run': run_id, 'lockIdentity': f'{original.st_dev}:{original.st_ino}',
            })
            with self.assertRaisesRegex(ValueError, 'did not release its test lock'):
                app_vm.finish_guest(product, '/private/session')
            archived = lock.rename(root/'prior lock')
            self.assertEqual(app_vm.finish_guest(product, '/private/session'), 0)
            lock.mkdir()
            self.assertEqual(app_vm.finish_guest(product, '/private/session'), 0)
            self.assertTrue(archived.is_dir() and lock.is_dir())

    def test_guest_exit_waits_for_a_complete_status_line(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            status = root/'exit-code'
            status.write_text('0')
            shell = '/bin/zsh' if sys.platform == 'darwin' else '/bin/bash'

            def remote(command, **kwargs):
                # Complete the executor's status file on the first retry.
                retry = f"sleep() {{ command -v cat >/dev/null || exit 127; printf '\\n' >> {app_vm.q(str(status))}; }}\n"
                return subprocess.run([shell, '-c', retry+command], check=True, **kwargs)

            vm = SimpleNamespace(root=str(root), remote=remote, runpath=lambda _: str(root))
            product = SimpleNamespace(vm=vm, finish=Mock(), state={'run': 'owned', 'lockIdentity': '1:2'})
            self.assertEqual(app_vm.finish_guest(product, '/private/session'), 0)
            self.assertEqual(status.read_text(), '0\n')

            status.write_text('0')
            with patch.object(vm, 'remote', side_effect=lambda command, **kwargs: subprocess.run(
                    [shell, '-c', 'sleep() { :; }\n'+command], check=True, **kwargs)):
                with self.assertRaisesRegex(ValueError, 'Timed out waiting for the guest executor exit receipt'):
                    app_vm.finish_guest(product, '/private/session')

    def test_vm_failure_receipt_preserves_startup_and_cleanup_errors(self):
        for interrupted in (False, True):
            with self.subTest(interrupted=interrupted), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                path = root/'package-info.json'
                path.write_bytes(encoded({'identity': {}, 'payloadInventory': {'Meshchan.app': package.DIR}}))
                args = SimpleNamespace(package_info=path, app=root/'Meshchan.app',
                                       config=root/'vm.json', evidence=root/'evidence')
                args.config.write_bytes(encoded({'runtime_dir': str(root/'private VM state')}))
                vm = SimpleNamespace(root='/Users/guest/private', c={'user': 'guest'},
                                     remote=Mock(return_value=SimpleNamespace(stdout='guest OS')))
                product = SimpleNamespace(vm=vm)
                host = SimpleNamespace(Product=Mock(return_value=product))
                receipt = args.evidence/'runtime.json'
                lock_error = ValueError('Could not inspect /Users/guest/private/active.lock')
                finish_error = KeyboardInterrupt('Fixture cleanup interrupt') if interrupted else lock_error

                def finish(*_):
                    # The outer runner may kill the local process while it
                    # waits for the guest. The first failure must already exist.
                    report = package.build.read(receipt)
                    self.assertEqual(report['status'], 'FAIL')
                    self.assertEqual(report['error'], 'Startup failed')
                    if complete.call_count == 1:
                        raise finish_error
                    self.assertIn('Fixture cleanup interrupt', report['cleanupError'])
                    return 0

                with (patch.object(app_vm, 'load', return_value=host),
                      patch.object(app_vm, 'check_payload'), patch.object(app_vm, 'require_ready_connection'),
                      patch.object(app_vm, 'guest_session', return_value='/private/session'),
                      patch.object(app_vm, 'start_guest', side_effect=ValueError('Startup failed')),
                      patch.object(app_vm, 'finish_guest', side_effect=finish) as complete):
                    expected = ('Fixture cleanup interrupt' if interrupted else
                                r'Could not inspect \$GUEST_ROOT/active\.lock')
                    with self.assertRaisesRegex(ValueError, expected) as caught:
                        app_vm.run(args)
                    self.assertIn('Startup failed', str(caught.exception))
                report = package.build.read(receipt)
                self.assertEqual(report['status'], 'FAIL')
                self.assertEqual(report['error'], 'Startup failed')
                self.assertEqual(complete.call_count, 2 if interrupted else 1)
                if interrupted:
                    self.assertIn('Fixture cleanup interrupt', report['cleanupError'])
                    self.assertEqual(report['guestExecutorExit'], 0)
                    self.assertIs(report['guestLockReleased'], True)
                else:
                    self.assertIn('Could not inspect $GUEST_ROOT/active.lock', report['cleanupError'])

    def test_interrupted_start_does_not_finish_an_unattested_guest(self):
        product = SimpleNamespace(state={}, finish=Mock())
        with patch.object(app_vm, 'record_guest_run', return_value=False):
            self.assertIsNone(app_vm.finish_guest(product, '/private/session'))
        product.finish.assert_not_called()

    def test_password_configuration_never_starts_a_persistent_child(self):
        vm = SimpleNamespace(c={'credentials_file': 'private'}, opts=['-o', 'ControlPath=owned'], target='guest')
        with patch.object(app_vm.subprocess, 'run', return_value=SimpleNamespace(returncode=1)) as run:
            with self.assertRaisesRegex(ValueError, 'Connect the test VM'):
                app_vm.require_ready_connection(vm)
            self.assertIn('-O', run.call_args.args[0])
            self.assertEqual(run.call_args.kwargs['timeout'], 10)
        with patch.object(app_vm.subprocess, 'run', return_value=SimpleNamespace(returncode=0)) as run:
            app_vm.require_ready_connection(vm)
        self.assertIn('ControlMaster=no', run.call_args.args[0])
        self.assertIn('ControlPersist=no', vm.opts)
        self.assertNotIn('credentials_file', vm.c)
        with patch.object(app_vm.subprocess, 'run') as run:
            app_vm.require_ready_connection(vm)
        run.assert_not_called()

    def test_guest_process_scan_distinguishes_live_and_absent_processes(self):
        def local(command, *, timeout):
            subprocess.run(['/bin/bash', '-c', command], check=True, timeout=timeout)

        vm = SimpleNamespace(remote=local)
        with self.assertRaises(subprocess.CalledProcessError):
            app_vm.require_absent_pid(vm, os.getpid())
        with subprocess.Popen(['/usr/bin/true']) as process:
            self.assertEqual(process.wait(timeout=5), 0)
        app_vm.require_absent_pid(vm, process.pid)


if __name__ == '__main__':
    unittest.main()
