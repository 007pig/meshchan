from contextlib import redirect_stdout
import hashlib
import io
import os
from pathlib import Path
import shutil
import stat
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from release_materials import encoded, product_inventory, sha
from release_package_archive import archive_stamp
from release_retention_archive import restore_members, scanned_input, write_archive
import retain_release as retention
from retain_release import Mapping, bound_json, canonical, source_inventory


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
        with self.assertRaisesRegex(ValueError, 'Pinned JSON'):
            bound_json(path, pin)
        with self.assertRaisesRegex(ValueError, 'Duplicate JSON'):
            bound_json(path, hashlib.sha256(path.read_bytes()).hexdigest())
        alias = self.root/'alias'
        alias.symlink_to(path)
        with self.assertRaisesRegex(ValueError, 'without symlink'):
            canonical(alias)

    def test_single_file_root_keeps_original_mode(self):
        inventory, stamp = scanned_input(self.data)
        self.assertEqual(inventory['.']['mode'], 0o600)
        self.assertEqual(stamp['.'][1], self.data.stat().st_ino)

    def test_seal_and_check_publish_only_after_archive_round_trip(self):
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

        def check(data, chain, locate, *, sealing=False):
            return {'fixture': True}

        with patch.object(retention, 'destinations'), patch.object(retention, 'snapshot_verifier', snapshot), \
                patch.object(retention.release_retention_inputs, 'verify_chain', verify_chain), \
                patch.object(retention, 'ci_inputs', check), redirect_stdout(io.StringIO()):
            retention.retain(SimpleNamespace(selection=selection, selection_sha256=sha(raw),
                                             work=self.root/'seal log', destination=seal))
            receipt_pin = sha((seal/retention.RECEIPT).read_bytes())
            self.original.rename(self.root/'unavailable original')
            retention.verify(SimpleNamespace(command='check', retention=seal, receipt_sha256=receipt_pin,
                                             work=self.root/'check log'))
        self.assertTrue((self.root/'check log/verification.json').is_file())
        self.assertEqual(sha((seal/retention.RECEIPT).read_bytes()), receipt_pin)


if __name__ == '__main__':
    unittest.main()
