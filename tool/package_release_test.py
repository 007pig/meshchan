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
                args = SimpleNamespace(command='package', vm_config=self.root/'vm.json',
                                       expected_build_info_sha256=self.pin)

                def run_command(name, argv, cwd):
                    if name == 'vm-app-runtime':
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

                    if change:
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
    def test_vm_receipt_hashes_the_manifest_bytes_used_for_its_app_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root/'package-info.json'
            data = encoded({'identity': {}, 'payloadInventory': {'Meshchan.app': package.DIR}})
            path.write_bytes(data)
            args = SimpleNamespace(package_info=path, app=root/'Meshchan.app',
                                   config=root/'vm.json', evidence=Path(os.path.relpath(root/'evidence')))
            host = SimpleNamespace(Product=Mock(side_effect=ValueError('test VM startup boundary')))
            with (patch.object(app_vm, 'load', return_value=host),
                  patch.object(app_vm, 'check_payload', side_effect=lambda *_: path.write_bytes(data+b'\n'))):
                with self.assertRaisesRegex(ValueError, 'test VM startup boundary'):
                    app_vm.run(args)
            host.Product.assert_called_once_with(str(args.config), args.evidence.absolute())
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

            app_vm.guest_inventory(SimpleNamespace(remote=local), str(guest), product_inventory(app))

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
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root/'package-info.json'
            path.write_bytes(encoded({'identity': {}, 'payloadInventory': {'Meshchan.app': package.DIR}}))
            args = SimpleNamespace(package_info=path, app=root/'Meshchan.app',
                                   config=root/'vm.json', evidence=root/'evidence')
            vm = SimpleNamespace(root='/Users/guest/private', c={'user': 'guest'},
                                 remote=Mock(return_value=SimpleNamespace(stdout='guest OS')))
            host = SimpleNamespace(Product=Mock(return_value=SimpleNamespace(vm=vm)))
            lock_error = ValueError('Could not inspect /Users/guest/private/active.lock')
            with (patch.object(app_vm, 'load', return_value=host),
                  patch.object(app_vm, 'check_payload'), patch.object(app_vm, 'require_ready_connection'),
                  patch.object(app_vm, 'guest_session', return_value='/private/session'),
                  patch.object(app_vm, 'start_guest', side_effect=ValueError('Startup failed')),
                  patch.object(app_vm, 'finish_guest', side_effect=lock_error)):
                with self.assertRaisesRegex(ValueError, r'Could not inspect \$GUEST_ROOT/active\.lock'):
                    app_vm.run(args)
            report = package.build.read(args.evidence/'runtime.json')
            self.assertEqual(report['status'], 'FAIL')
            self.assertEqual(report['error'], 'Startup failed')
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
