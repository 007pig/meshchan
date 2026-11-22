import io
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest

from audit_release_payload import FIRST_PARTY, MANIFEST, PROFILE, audit
from release_materials import digest, product_inventory


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

    def source(self, *members):
        target = self.folder / FIRST_PARTY
        target.parent.mkdir(parents=True, exist_ok=True)
        with tarfile.open(target, 'w:gz') as archive:
            for name, data in members:
                member = tarfile.TarInfo(name)
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))

    def seal(self):
        manifest = self.root / MANIFEST
        manifest.unlink(missing_ok=True)
        manifest.write_text(json.dumps({'payloadProfile': PROFILE,
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

    def test_reject_shared_hardlink(self):
        os.link(self.cli, self.cli.with_name('shared'))
        with self.assertRaisesRegex(ValueError, 'shared hard link'):
            self.check()


if __name__ == '__main__':
    unittest.main()
