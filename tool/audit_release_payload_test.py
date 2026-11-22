import gzip
import io
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from audit_release_payload import FIRST_PARTY, MANIFEST, PROFILE, audit
from release_materials import digest, product_inventory, source_archive


class PayloadAuditTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        self.folder = self.root / 'Meshchan-fixture'
        self.app = self.write('Meshchan.app/Contents/MacOS/Meshchan', b'\xcf\xfa\xed\xfeclean')
        self.cli = self.write('meshctl/bin/meshctl', b'\xcf\xfa\xed\xfepackage:meshctl/entry.dart')
        self.source(('lib/app.dart', b'void main() {}'))

    def write(self, name, data):
        target = self.folder / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        return target

    def source(self, *members, pax_headers=None):
        target = self.folder / FIRST_PARTY
        target.parent.mkdir(parents=True, exist_ok=True)
        with tarfile.open(target, 'w:gz', pax_headers=pax_headers) as archive:
            for name, data in members:
                member = tarfile.TarInfo(name)
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))

    def seal(self, *, candidate=None):
        manifest = self.root / MANIFEST
        manifest.unlink(missing_ok=True)
        manifest.write_text(json.dumps({'payloadProfile': PROFILE,
                                        'candidatePath': candidate or self.folder.name,
                                        'inventory': product_inventory(self.root)}))
        return digest(manifest)

    def check(self, digest=None):
        return audit(self.root, ['/Users/local-builder'],
                     image_inventory_sha256=self.seal() if digest is None else digest)

    def test_clean_image(self):
        result = self.check()
        self.assertEqual('PASS', result['status'])
        self.assertEqual(2, len(result['machOFiles']))
        self.assertEqual(1, result['firstPartyArchiveEntries'])

    def test_findings_cover_binary_json_logs_and_compressed_first_party_source(self):
        self.app.write_bytes(self.app.read_bytes() + b'\0/Users/another-builder/work/object.o\0')
        self.cli.write_bytes(self.cli.read_bytes() + b'\0file:///tmp/build/bin/meshctl.dart\0')
        self.write('materials/info.json', b'{"source":"file:///Users/local-builder/private/location"}')
        self.write('materials/evidence/app-stderr.log', b'synthetic test')
        self.source(('lib/app.dart', b'prefix ' + bytes(1024 * 1024 - 10) +
                     b'/Users/local-builder/hidden'))
        result = self.check()
        self.assertEqual('FAIL', result['status'])
        self.assertEqual(['nativeImageLocalPath'],
                         result['findings'][self.app.relative_to(self.root).as_posix()])
        self.assertEqual(['nativeImageLocalPath'],
                         result['findings'][self.cli.relative_to(self.root).as_posix()])
        self.assertIn('Meshchan-fixture/materials/info.json', result['findings'])
        self.assertIn('Meshchan-fixture/materials/evidence/app-stderr.log', result['findings'])
        self.assertIn(f'Meshchan-fixture/{FIRST_PARTY}:lib/app.dart', result['findings'])
        self.assertNotIn('another-builder', json.dumps(result))

    def test_reject_changed_file_after_inventory(self):
        pin = self.seal()
        self.cli.write_bytes(self.cli.read_bytes() + b'changed')
        with self.assertRaisesRegex(ValueError, 'inventory differs'):
            self.check(pin)

    def test_finds_percent_encoded_and_json_escaped_private_paths(self):
        self.write('materials/receipt.json',
                   br'{"source":"file:\/\/\/Volumes\/Build%20Work%20%c3%a9"}')
        self.source(('lib/app.dart', b'file:///Volumes/Build%20Work%20%C3%A9/private'))
        result = audit(self.root, ['/Volumes/Build Work é'], image_inventory_sha256=self.seal())
        self.assertEqual('FAIL', result['status'])
        self.assertEqual({f'{self.folder.name}/materials/receipt.json': ['localBuildPath'],
                          f'{self.folder.name}/{FIRST_PARTY}:lib/app.dart': ['localBuildPath']}, result['findings'])

    def test_finds_macos_temporary_paths_in_files_and_first_party_source(self):
        # Keep the assembled fixture out of the corresponding-source audit.
        temporary = b'/var/folders/f0/' + b'0123456789abcdef/T/review-output'
        self.write('materials/receipt.json', b'{"cwd":"' + temporary.replace(b'/', b'\\/') + b'"}')
        self.write('materials/guide.md', b'The template uses /var/folders/.../T/.')
        self.source(('docs/development.md', b'Build output: `/private' + temporary + b'`.'))
        result = self.check()
        self.assertEqual('FAIL', result['status'])
        self.assertEqual({f'{self.folder.name}/materials/receipt.json': ['localBuildPath'],
                          f'{self.folder.name}/{FIRST_PARTY}:docs/development.md': ['localBuildPath']},
                         result['findings'])

    def test_exact_private_path_at_eof_and_distinct_prefixed_name(self):
        self.write('materials/path.txt', b'/Users/local-builder')
        self.write('materials/other.txt', b'/Users/local-builder-example/private')
        self.assertEqual({f'{self.folder.name}/materials/path.txt': ['localBuildPath']}, self.check()['findings'])

    def test_reject_changed_file_after_computing_observed_inventory(self):
        pin = self.seal()

        def inventory_then_change(root):
            inventory = product_inventory(root)
            self.cli.write_bytes(self.cli.read_bytes() + b'changed')
            return inventory

        with patch('audit_release_payload.product_inventory', side_effect=inventory_then_change):
            with self.assertRaisesRegex(ValueError, 'file changed during audit'):
                self.check(pin)

    def test_reject_candidate_path_that_disagrees_with_inventory(self):
        pin = self.seal(candidate='Meshchan-other')
        with self.assertRaisesRegex(ValueError, 'candidate path does not match'):
            self.check(pin)

    def test_audit_scans_native_toolchain_and_temporary_paths(self):
        self.app.write_bytes(self.app.read_bytes() + b'\0/opt/homebrew/sdk/object.o\0')
        self.cli.write_bytes(self.cli.read_bytes() + b'\0/var/folders/token/T/session/snapshot.aot\0')
        self.source(('lib/object.o', b'\xcf\xfa\xed\xfe\0/Volumes/build-sdk/object.o\0'))
        result = self.check()
        self.assertEqual('FAIL', result['status'])
        self.assertEqual({'nativeImageLocalPath'},
                         {reason for reasons in result['findings'].values() for reason in reasons})
        self.assertEqual(3, len(result['findings']))

    def test_reject_wrong_inventory_digest(self):
        self.seal()
        with self.assertRaisesRegex(ValueError, 'independent digest'):
            self.check('0' * 64)

    def test_reject_escaping_symlink_and_source_member(self):
        alias = self.cli.with_name('elsewhere')
        alias.symlink_to('../../outside')
        with self.assertRaises(ValueError):
            self.check()
        alias.unlink()
        self.source(('../outside', b'escape'))
        with self.assertRaisesRegex(ValueError, 'Unsafe'):
            self.check()

    def test_accepts_internal_relative_links_from_the_source_archive_producer(self):
        checkout = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        (checkout/'lib/src').mkdir(parents=True)
        (checkout/'lib/source.dart').write_text('void main() {}')
        (checkout/'lib/src/alias.dart').symlink_to('../source.dart')
        archive, _ = source_archive(checkout, ['lib/source.dart', 'lib/src/alias.dart'])
        self.write(FIRST_PARTY, archive)
        result = self.check()
        self.assertEqual('PASS', result['status'])
        self.assertEqual(2, result['firstPartyArchiveEntries'])

    def test_rejects_symlink_from_source_archive_that_escapes_its_root(self):
        with tarfile.open(self.folder / FIRST_PARTY, 'w:gz') as archive:
            member = tarfile.TarInfo('lib/alias.dart')
            member.type = tarfile.SYMTYPE
            member.linkname = '../../outside.dart'
            archive.addfile(member)
        with self.assertRaisesRegex(ValueError, 'escapes its product'):
            self.check()

    def test_reject_shared_hardlink(self):
        os.link(self.cli, self.cli.with_name('shared'))
        with self.assertRaisesRegex(ValueError, 'shared hard link'):
            self.check()

    def test_reject_data_hidden_after_source_archive(self):
        with gzip.open(self.folder / FIRST_PARTY, 'ab') as stream:
            stream.write(b'test log with /Users/local-builder/hidden')
        with self.assertRaisesRegex(ValueError, 'Unexpected data after the first-party source archive'):
            self.check()

    def test_reject_private_source_archive_pax_metadata(self):
        self.source(('lib/app.dart', b'void main() {}'),
                    pax_headers={'comment': '/Users/local-builder/private'})
        with self.assertRaisesRegex(ValueError, 'Unexpected first-party source archive metadata'):
            self.check()


if __name__ == '__main__':
    unittest.main()
