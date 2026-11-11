"""Synthetic archive-provenance regressions; never execute native files."""
import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import revise_dev_candidate as revision


class ArchiveSourceTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='meshchan-original-test-')
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.original = self.folder / 'delivery/synthetic-dev2'
        self.original.mkdir(parents=True)
        self.write_bundle(b'original')
        self.old_hashes = dict(self.info['nativeHashes'])
        archive = self.original.with_name('synthetic-dev2.tar.gz')
        with tarfile.open(archive, 'w:gz') as tar:
            tar.add(self.original, arcname=self.original.name)
        self.verification = {'status': 'PASS', 'archive': str(archive),
                             'archiveSha256': revision.digest(archive),
                             'testedNativeHashesVerified': self.old_hashes,
                             'memberChecksumsVerified': len(self.sums),
                             'exactFileLayoutVerified': True, 'executePermissionVerified': True}
        self.write_bundle(b'regenerated')
        self.new_hashes = dict(self.info['nativeHashes'])

    def write_bundle(self, marker):
        for name in ('bin/meshctl', 'lib/liblibserialport_plus.dylib'):
            path = self.original / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(marker + b' ' + name.encode())
            path.chmod(0o755)
        (self.original / 'README.md').write_bytes(marker + b' documentation')
        notice = self.original / 'licenses/example/LICENSE'
        notice.parent.mkdir(parents=True, exist_ok=True)
        notice.write_bytes(marker + b' original notice')
        self.info = {'buildId': 'synthetic-dev2', 'version': '0.1.0-dev.2',
                     'nativeHashes': {name: revision.digest(self.original / name)
                                      for name in ('bin/meshctl', 'lib/liblibserialport_plus.dylib')},
                     'productCompilationInputHashes': {}, 'peerCompilationInputHashes': {}}
        (self.original / 'build-info.json').write_text(json.dumps(self.info))
        self.sums = {str(p.relative_to(self.original)): revision.digest(p)
                     for p in self.original.rglob('*') if p.is_file() and p.name != 'SHA256SUMS'}
        (self.original / 'SHA256SUMS').write_text(''.join(v + '  ' + k + '\n' for k, v in sorted(self.sums.items())))

    def test_verified_archive_wins_over_regenerated_delivery_directory(self):
        with revision.verified_original_bundle(self.verification) as original:
            self.assertEqual(json.loads((original / 'build-info.json').read_text())['nativeHashes'], self.old_hashes)
            self.assertEqual(revision.digest(original / 'bin/meshctl'), self.old_hashes['bin/meshctl'])
            self.assertEqual((original / 'README.md').read_bytes(), b'original documentation')
            self.assertEqual((original / 'licenses/example/LICENSE').read_bytes(), b'original original notice')
            self.assertEqual((original / 'bin/meshctl').stat().st_mode & 0o777, 0o755)
            extracted = original.parent
        self.assertFalse(extracted.exists())
        self.assertEqual(revision.digest(self.original / 'bin/meshctl'), self.new_hashes['bin/meshctl'])

    def test_regenerated_rf_hashes_cannot_create_a_metadata_only_revision(self):
        (self.folder / 'archive-verification.json').write_text(json.dumps(self.verification))
        rf = self.folder / 'rf.json'
        rf.write_text(json.dumps({'buildId': 'synthetic-dev2', 'nativeHashes': self.new_hashes,
                                  'actualApplicationSendAttempts': 0, 'authorizedApplicationSendAttemptCeiling': 12}))
        summary = self.folder / 'summary.md'
        summary.write_text('Synthetic acceptance')
        original_mkdtemp = tempfile.mkdtemp
        def local_mkdtemp(suffix=None, prefix=None, dir=None):
            return original_mkdtemp(suffix=suffix, prefix=prefix, dir=str(self.folder))
        with patch.object(sys, 'argv', ['revise', '--build-directory', str(self.folder),
                                      '--rf-summary', str(rf), '--acceptance-summary', str(summary)]), \
                patch.object(tempfile, 'mkdtemp', local_mkdtemp), \
                patch.object(subprocess, 'run', side_effect=AssertionError('Native files must not execute')) as native_run, \
                contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as caught:
                revision.main()
        self.assertEqual(caught.exception.code, 2)
        native_run.assert_not_called()
        self.assertEqual(list((self.folder / 'delivery').glob('synthetic-dev2-rf-*')), [])

    def test_original_native_verification_is_an_independent_binding(self):
        changed = {**self.verification, 'testedNativeHashesVerified': self.new_hashes}
        with self.assertRaises(ValueError):
            with revision.verified_original_bundle(changed):
                self.fail('Mismatched verified native hashes were accepted.')

    def test_changed_archive_bytes_reject_before_extraction(self):
        path = Path(self.verification['archive'])
        path.write_bytes(path.read_bytes() + b'changed')
        with self.assertRaises(ValueError):
            with revision.verified_original_bundle(self.verification):
                self.fail('Changed original archive was accepted.')


if __name__ == '__main__':
    unittest.main()
