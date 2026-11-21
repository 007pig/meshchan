from contextlib import contextmanager, redirect_stdout
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from release_materials import encoded, product_inventory, sha
from release_package_archive import archive_stamp
from release_retention_archive import regular_entry, restore_members, scanned_input, write_archive
import retain_release as retention
from retain_release import Mapping, bound_json, canonical, source_inventory
from verify_retention_bootstrap import enclosing_checkout


class RetentionArchiveTests(unittest.TestCase):
    def setUp(self):
        work = tempfile.TemporaryDirectory(prefix='Meshchan archive test ')
        self.addCleanup(work.cleanup)
        self.root = Path(work.name).resolve()
        self.original = self.root/'original input'
        self.original.mkdir(mode=0o700)
        self.data = self.original/'.runtime.sqlite'
        self.data.write_bytes(b'owned SQLite fixture')
        self.data.chmod(0o600)
        (self.original/'script').write_bytes(b'#!/bin/sh\n')
        (self.original/'script').chmod(0o755)
        (self.original/'link').symlink_to('./script')
        self.mapping = {str(self.original): 'inputs/0001-original input'}
        self.target = self.root/'fresh restore'
        self.archive = self.root/'evidence.tar'
        self.members, self.stamps = source_inventory(self.mapping)

    def write(self):
        return write_archive(self.archive, self.mapping, self.members, self.stamps)

    def restore(self, seal):
        return restore_members(self.archive, self.target, seal, self.members, self.mapping.values())

    def test_restores_hidden_modes_and_link_without_original_root(self):
        pin = self.write()
        relocated = self.root/'temporarily unavailable'
        self.original.rename(relocated)
        self.restore(pin)
        locate = Mapping(self.mapping, self.target)
        database = locate(self.data)
        self.assertEqual(database.read_bytes(), (relocated/self.data.name).read_bytes())
        self.assertEqual(stat.S_IMODE(database.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(locate(self.original/'script').stat().st_mode), 0o755)
        self.assertEqual(str((database.parent/'link').readlink()), 'script')
        self.assertEqual(os.readlink(database.parent/'link'), './script')
        self.assertNotEqual(database.stat().st_ino, (relocated/self.data.name).stat().st_ino)
        with self.assertRaises(FileNotFoundError):
            locate(self.original/'missing')

    def test_missing_mapping_never_opens_original(self):
        with self.assertRaisesRegex(ValueError, 'absent from retained'):
            Mapping({}, self.target)(self.data)

    def test_existing_targets_and_retries_are_untouched(self):
        pin = self.write()
        with self.assertRaises(FileExistsError):
            self.write()
        self.target.mkdir()
        marker = self.target/'marker'
        marker.write_bytes(b'existing data')
        with self.assertRaises(FileExistsError):
            self.restore(pin)
        self.assertEqual(marker.read_bytes(), b'existing data')

    def test_input_replacement_is_detected_even_if_bytes_match(self):
        original = self.data.read_bytes()
        self.data.rename(self.original/'moved')
        self.data.write_bytes(original)
        self.data.chmod(0o600)
        with self.assertRaisesRegex(ValueError, 'changed before archiving'):
            self.write()
        self.assertFalse(self.target.exists())

    def test_regular_input_changing_as_its_digest_is_read_fails(self):
        def changed_during_read(stream):
            result = archive_stamp(stream)
            with self.data.open('ab') as output:
                output.write(b' concurrent update')
            return result

        with patch('release_retention_archive.archive_stamp', side_effect=changed_during_read):
            with self.assertRaisesRegex(ValueError, 'Input changed while being read'):
                regular_entry(self.data)

    def test_archive_changed_during_pin_verification_creates_no_output(self):
        pin = self.write()

        def changed_during_read(stream):
            result = archive_stamp(stream)
            self.archive.chmod(0o600)
            return result

        with patch('release_retention_archive.archive_stamp', side_effect=changed_during_read):
            with self.assertRaisesRegex(ValueError, 'archive changed while checking its pin'):
                self.restore(pin)
        self.assertFalse(self.target.exists())

    def test_external_digest_rejects_mutation_before_extraction(self):
        pin = self.write()
        self.archive.chmod(0o600)
        with self.archive.open('r+b') as stream:
            stream.seek(128)
            stream.write(b'corrupt')
        self.archive.chmod(0o400)
        with self.assertRaisesRegex(ValueError, 'external receipt'):
            self.restore(pin)
        self.assertFalse(self.target.exists())

    def test_truncated_archive_rejected_even_with_separate_matching_archive_pin(self):
        self.write()
        raw = self.archive.read_bytes()
        self.archive.chmod(0o600)
        self.archive.write_bytes(raw[:256])
        with self.archive.open('rb') as stream:
            pin, _ = archive_stamp(stream)
        with self.assertRaises((tarfile.TarError, ValueError)):
            self.restore(pin)
        self.assertEqual(list(self.target.iterdir()), [])

    def test_unsafe_members_fail_before_writing(self):
        for name, target in (('../outside', None), ('/outside', None), ('inputs', None),
                             ('inputs/0001-original input/link', '../../outside')):
            with self.subTest(name=name, target=target):
                with tarfile.open(self.archive, 'w') as stream:
                    member = tarfile.TarInfo(name)
                    if target is None:
                        member.size = 1
                        stream.addfile(member, io.BytesIO(b'x'))
                    else:
                        member.type = tarfile.SYMTYPE
                        member.linkname = target
                        member.mode = self.members[name]['mode']
                        stream.addfile(member)
                with self.archive.open('rb') as stream:
                    pin, _ = archive_stamp(stream)
                with self.assertRaisesRegex(ValueError, 'archive'):
                    self.restore(pin)
                self.assertEqual(list(self.target.iterdir()), [])
                self.target.rmdir()

    def test_repeated_members_and_internal_link_escape_are_rejected(self):
        self.write()
        data = self.archive.read_bytes()
        for duplicate in (False, True):
            with self.subTest(duplicate=duplicate):
                self.archive.chmod(0o600)
                with tarfile.open(fileobj=io.BytesIO(data)) as original, tarfile.open(self.archive, 'w') as result:
                    for member in original:
                        if member.issym() and not duplicate:
                            member.linkname = '../../outside'
                            self.members[member.name]['symlink'] = member.linkname
                        stream = original.extractfile(member) if member.isfile() else None
                        result.addfile(member, stream)
                        if member.issym() and duplicate:
                            result.addfile(member)
                with self.archive.open('rb') as stream:
                    pin, _ = archive_stamp(stream)
                expected = 'repeated' if duplicate else 'escapes'
                with self.assertRaisesRegex(ValueError, expected):
                    self.restore(pin)
                self.assertEqual(list(self.target.iterdir()), [])
                self.target.rmdir()
                self.members['inputs/0001-original input/link']['symlink'] = './script'

    def test_external_json_pin_and_type(self):
        path = self.root/'selection.json'
        raw = encoded({'formatVersion': 1})
        path.write_bytes(raw)
        pin = hashlib.sha256(raw).hexdigest()
        value, observed = bound_json(path, pin)
        self.assertEqual(observed, raw)
        self.assertEqual(value, {'formatVersion': 1})
        path.write_bytes(b'{"status":"FAIL","status":"PASS"}')
        with self.assertRaisesRegex(ValueError, 'SHA-256 pin'):
            bound_json(path, pin)
        with self.assertRaisesRegex(ValueError, 'Duplicate JSON'):
            bound_json(path, hashlib.sha256(path.read_bytes()).hexdigest())
        alias = self.root/'alias'
        alias.symlink_to(path)
        with self.assertRaisesRegex(ValueError, 'without symlink'):
            canonical(alias)

    def test_wrong_pinned_document_is_not_buffered(self):
        class DigestOnlyReader(io.BufferedReader):
            def read(self, *args, **kwargs):
                raise AssertionError('Incorrectly pinned data was buffered')

        path = self.root/'incorrect input'
        path.write_bytes(b'an archive selected in place of the JSON document')
        with patch('verify_retention_bootstrap.os.fdopen',
                   side_effect=lambda fd, mode: DigestOnlyReader(io.FileIO(fd, mode))):
            with self.assertRaisesRegex(ValueError, 'SHA-256 pin'):
                bound_json(path, '0'*64)

    def test_image_probe_timeout_keeps_partial_diagnostics(self):
        command = ['hdiutil', 'verify']
        timeout = subprocess.TimeoutExpired(command, 300, output=b'verification started', stderr=b'partial diagnostic')
        with patch.object(retention.subprocess, 'run', side_effect=timeout):
            with self.assertRaises(subprocess.TimeoutExpired):
                retention.ImageProbe(self.root).command('verify-image', command)
        self.assertEqual((self.root/'verify-image.stdout').read_bytes(), b'verification started')
        self.assertEqual((self.root/'verify-image.stderr').read_bytes(), b'partial diagnostic')

    def test_single_file_root_keeps_original_mode(self):
        inventory, stamp = scanned_input(self.data)
        self.assertEqual(inventory['.']['mode'], 0o600)
        self.assertEqual(stamp['.'][1], self.data.stat().st_ino)

    @contextmanager
    def seal_fixture(self):
        selection = self.root/'selection.json'
        candidate = {key: {'path': str(self.data), 'sha256': sha(self.data.read_bytes())}
                     for key in retention.CANDIDATE_FIELDS}
        raw = encoded({'formatVersion': 1, 'candidate': candidate, 'inputRoots': [str(self.original)],
                       'retentionSource': 'fixture', 'ci': {}})
        selection.write_bytes(raw)
        seal = self.root/'sealed fixture'

        def verify_chain(selected, locate, *, live=False):
            self.assertEqual(locate(selected['dmg']['path']).read_bytes(), b'owned SQLite fixture')
            return {'roots': [self.original], 'identities': {}}

        def snapshot(work, source):
            base = work/retention.VERIFIER
            (base/'tool').mkdir(parents=True)
            shutil.copy(retention.ROOT/'tool/retain_release.py', base/'tool')
            return product_inventory(base)

        def check(data, chain, locate, *, sealing=False, verifier=None):
            return {'fixture': True}

        with patch.object(retention, 'destinations'), patch.object(retention, 'snapshot_verifier', snapshot), \
                patch.object(retention.release_retention_inputs, 'verify_chain', verify_chain), \
                patch.object(retention, 'ci_inputs', check), redirect_stdout(io.StringIO()):
            yield SimpleNamespace(selection=selection, selection_sha256=sha(raw),
                                  work=self.root/'seal log', destination=seal)

    def test_seal_and_check_publish_only_after_archive_round_trip(self):
        with self.seal_fixture() as args:
            retention.retain(args)
            seal = args.destination
            receipt_pin = sha((seal/retention.RECEIPT).read_bytes())
            self.original.rename(self.root/'unavailable original')
            retention.verify(SimpleNamespace(command='check', retention=seal, receipt_sha256=receipt_pin,
                                             work=self.root/'check log'))
        self.assertTrue((self.root/'check log/verification.json').is_file())
        self.assertEqual(sha((seal/retention.RECEIPT).read_bytes()), receipt_pin)

    def test_seal_publication_does_not_replace_existing_empty_destination(self):
        with self.seal_fixture() as args:
            args.destination.mkdir()
            previous = args.destination.stat()
            with self.assertRaises(FileExistsError):
                retention.retain(args)
            self.assertTrue(os.path.samestat(previous, args.destination.stat()))
            self.assertEqual(list(args.destination.iterdir()), [])
            self.assertTrue((args.work/'failed.json').is_file())

    def test_seal_report_failure_does_not_publish_destination(self):
        real_record = retention.record_progress

        def record(work, name, result):
            if name == 'prepared.json':
                raise OSError('unable to persist the external record')
            real_record(work, name, result)

        with self.seal_fixture() as args, patch.object(retention, 'record_progress', record):
            with self.assertRaisesRegex(OSError, 'unable to persist'):
                retention.retain(args)
            self.assertFalse(args.destination.exists())
            staged = json.loads((args.work/'staging.json').read_bytes())
            failure = json.loads((args.work/'failed.json').read_bytes())
            self.assertEqual(staged['stagingDirectory'], failure['stagingDirectory'])
            self.assertTrue(Path(staged['stagingDirectory']).is_dir())

    def test_check_cleanup_failure_writes_no_pass_report(self):
        real_temporary = tempfile.TemporaryDirectory

        @contextmanager
        def failing_cleanup(*args, **kwargs):
            with real_temporary(*args, **kwargs) as temporary:
                yield temporary
            raise OSError('unable to remove scratch extraction')

        with self.seal_fixture() as args:
            retention.retain(args)
            seal = args.destination
            pin = sha((seal/retention.RECEIPT).read_bytes())
            work = self.root/'check cleanup'
            with patch.object(retention.tempfile, 'TemporaryDirectory', failing_cleanup), \
                    self.assertRaisesRegex(OSError, 'unable to remove scratch extraction'):
                retention.verify(SimpleNamespace(command='check', retention=seal,
                                                 receipt_sha256=pin, work=work))
            self.assertFalse((work/'verification.json').exists())
            self.assertTrue((work/'failed.json').is_file())

    def test_post_extraction_data_change_is_detected(self):
        real_extract = retention.extract_and_verify

        def changed_output(*args):
            dmg, *identities = real_extract(*args)
            dmg.write_bytes(b'changed after successful extraction')
            return dmg, *identities

        with self.seal_fixture() as args:
            retention.retain(args)
            seal = args.destination
            pin = sha((seal/retention.RECEIPT).read_bytes())
            work = self.root/'check mutated output'
            with patch.object(retention, 'extract_and_verify', changed_output), \
                    self.assertRaisesRegex(ValueError, 'differs at'):
                retention.verify(SimpleNamespace(command='check', retention=seal,
                                                 receipt_sha256=pin, work=work))
            self.assertFalse((work/'verification.json').exists())
            self.assertTrue((work/'failed.json').is_file())

    def test_reported_historical_tool_commit_must_match_inventory(self):
        entry = {'type': 'file', 'size': 7, 'sha256': 'a'*64, 'mode': 0o700}
        with patch.object(retention, 'committed_blob', return_value=(b'', {**entry, 'mode': 0o755})):
            retention.require_committed_inputs('a'*40, {'helper.sh': entry}, 'Package verifier')
        with patch.object(retention, 'committed_blob', return_value=(b'', {**entry, 'sha256': 'b'*64})):
            with self.assertRaisesRegex(ValueError, 'does not match its claimed Git source'):
                retention.require_committed_inputs('b'*40, {'helper.sh': entry}, 'Package verifier')

    def test_private_checkout_modes_match_git_executable_classes(self):
        name = 'checkout-tool.py'
        path = self.root/name
        raw = b'import sys\n'
        path.write_bytes(raw)
        entry = {'type': 'file', 'size': len(raw), 'sha256': sha(raw)}
        with patch.object(retention, 'ROOT', self.root):
            path.chmod(0o600)
            retention.require_checkout_file(name, {**entry, 'mode': 0o644})
            path.chmod(0o700)
            retention.require_checkout_file(name, {**entry, 'mode': 0o755})
            with self.assertRaisesRegex(ValueError, 'checkout file differs'):
                retention.require_checkout_file(name, {**entry, 'mode': 0o644})
            path.write_bytes(b'changed\n')
            with self.assertRaisesRegex(ValueError, 'checkout file differs'):
                retention.require_checkout_file(name, {**entry, 'mode': 0o755})

    def test_checkout_outputs_are_rejected_even_with_external_verifier(self):
        checkout = self.root/'another checkout'
        checkout.mkdir()
        (checkout/'.git').write_text('gitdir: /checkout metadata')
        legitimate_parent = checkout/'build/phase-1e8'
        legitimate_parent.mkdir(parents=True)
        work = legitimate_parent/'new validation'
        with patch.object(retention, 'require_product_disjoint'):
            retention.destinations(work, {})
            with self.assertRaisesRegex(ValueError, 'outside a Git checkout'):
                retention.destinations(work, {'Restore directory': checkout/'new restore'})
            with self.assertRaisesRegex(ValueError, 'fresh child'):
                retention.destinations(checkout/'new work', {})

    def test_home_dotfiles_repo_allows_an_independent_archive(self):
        (self.root/'.git').mkdir()
        with patch.object(Path, 'home', return_value=self.root):
            self.assertIsNone(enclosing_checkout(self.root/'private archive/restore'))


if __name__ == '__main__':
    unittest.main()
