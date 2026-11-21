import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import installed_release_inputs as inputs
import package_dmg
from release_materials import product_inventory
from release_retention_archive import regular_entry
from retain_release import METADATA


def write(path, data):
    path.write_bytes(data)
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    return write(path, json.dumps(value, sort_keys=True).encode())


class RCInputTests(unittest.TestCase):
    def setUp(self):
        self.archive = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        self.seal = self.archive/'RC1 Build 8 - 1E.8'
        self.evidence = self.archive/'RC1 Build 8 - restore evidence'
        self.assets = self.archive/'RC1 Build 8 - engineering assets'
        self.restored = self.archive/'RC1 Build 8 - restored'/'inputs'
        self.verifier = self.seal/'verifier'
        for folder in (self.verifier, self.evidence, self.assets, self.restored):
            folder.mkdir(parents=True)
        self.archived_script = self.verifier/'untrusted.py'
        write(self.archived_script, b'raise RuntimeError("Never execute the archived verifier")\n')
        write(self.seal/'retained.tar', b'pinned archive bytes')
        self.archive_entry, _ = regular_entry(self.seal/'retained.tar')
        self.dmg = self.assets/inputs.DMG_FILENAME
        self.sums = self.assets/'SHA256SUMS'
        self.dmg_bytes = b'accepted image bytes'
        self.pins = dict(inputs.CANDIDATE_PINS)
        self.pins['dmg'] = write(self.dmg, self.dmg_bytes)
        self.pins['checksums'] = write(self.sums, f'{self.pins["dmg"]}  {self.dmg.name}\n'.encode())
        self.reported_image = self.restored/('001-'+self.dmg.name)
        write(self.reported_image, self.dmg_bytes)
        self.signed = self.restored/'003-signed-product-info.json'
        self.image_manifest = self.restored/'002-image-payload.json'
        self.pins['image_payload'] = write_json(self.image_manifest, package_dmg.SIGNATURE_POLICY)
        write_json(self.signed, {})
        mapping = {}

        def retained(name, file):
            key = f'/historical/{name}'
            mapping[key] = str(file.relative_to(self.restored.parent))
            return key

        local_refs = {
            'dmg': retained(self.dmg.name, self.reported_image),
            'image_payload': retained('image-payload.json', self.image_manifest),
            'signed_manifest': retained('signed-product-info.json', self.signed),
        }
        refs = {key: {'path': local_refs.get(key, f'/historical/{key}'), 'sha256': digest}
                for key, digest in self.pins.items()}
        selection_path = self.restored/'000-selection.json'
        self.chain = {
            'sourceCommit': inputs.PRODUCT_COMMIT, 'buildRecipeVersion': 55,
            'image': {'size': len(self.dmg_bytes), 'sha256': self.pins['dmg']},
        }
        self.manifest = {
            'formatVersion': 1, 'metadata': METADATA, 'verifier': product_inventory(self.verifier),
            'mapping': mapping, 'selectionPath': retained('selection.json', selection_path),
            'selectionSha256': write_json(selection_path, {'candidate': refs}),
            'identities': {'acceptance': self.chain},
        }
        self.seal_pin = self.write_seal()
        self.restore = {
            'status': 'PASS', 'operation': 'restore', 'receiptSha256': self.seal_pin,
            'archive': self.archive_entry, 'historicalAcceptance': 'MATCHED',
            'newProductRuntime': 'NOT_RUN', 'restoredDmg': str(self.reported_image),
            'imageStructure': {'status': 'PASS', 'format': 'UDZO', 'filesystem': 'HFS+',
                               'containerSignature': 'UNSIGNED'},
        }
        self.transfer = {
            'status': 'PASS', 'path': str(self.dmg), 'size': len(self.dmg_bytes),
            'sha256': self.pins['dmg'], 'originalChecksumsSha256': self.pins['checksums'],
            'verifiedRestoreMember': str(self.reported_image),
        }

    def write_seal(self):
        manifest_pin = write_json(self.seal/'retention-manifest.json', self.manifest)
        return write_json(self.seal/'retention-receipt.json', {
            'formatVersion': 1, 'status': 'SEALED', 'manifestSha256': manifest_pin,
            'archive': self.archive_entry,
        })

    def checked(self, archive=None):
        archive = archive if archive is not None else self.archive
        evidence = archive/self.evidence.name
        restore_pin = write_json(evidence/'verification.json', self.restore)
        transfer_pin = write_json(evidence/'handoff-assets.json', self.transfer)
        with patch.multiple(inputs, DMG_SIZE=len(self.dmg_bytes), DMG_SHA256=self.pins['dmg'],
                            CHECKSUM_SHA256=self.pins['checksums'], CANDIDATE_PINS=self.pins,
                            SEAL_SHA256=self.seal_pin, RESTORE_SHA256=restore_pin, TRANSFER_SHA256=transfer_pin), \
                patch.object(inputs, 'verify_chain', return_value={'identities': self.chain}), \
                patch.object(inputs, 'signed_info', return_value={}):
            return inputs.verify_rc_inputs(archive)

    def test_durable_restore_and_engineering_asset_are_distinct_bound_paths(self):
        result = self.checked()
        self.assertEqual(result.dmg, self.dmg)
        self.assertEqual(result.checksums, self.sums)
        self.assertEqual(result.report['restoredDmg'], str(self.reported_image))
        self.assertEqual(result.report['newProductRuntime'], 'NOT_RUN')

    def test_selected_archive_copy_uses_relative_members_without_opening_historical_paths(self):
        copy = self.archive/'private copy'
        copy.mkdir()
        for directory in (self.seal, self.evidence, self.assets, self.restored.parent):
            directory.rename(copy/directory.name)
        self.assertFalse(self.reported_image.exists())
        result = self.checked(copy)
        self.assertEqual(result.dmg, copy/self.assets.name/self.dmg.name)
        self.assertEqual(result.report['restoredDmg'],
                         str(copy/self.restored.parent.name/'inputs'/self.reported_image.name))
        self.assertEqual(json.loads((copy/self.evidence.name/'verification.json').read_text()),
                         self.restore)

    def test_same_size_altered_download_and_wrong_checksum_fail(self):
        write(self.dmg, b'X' * len(self.dmg_bytes))
        with self.assertRaisesRegex(ValueError, 'Build 8 engineering DMG sha256'):
            self.checked()
        write(self.dmg, self.dmg_bytes)
        write(self.sums, b'other checksum\n')
        with self.assertRaisesRegex(ValueError, 'Original SHA256SUMS sha256'):
            self.checked()

    def test_original_receipt_requires_external_pin(self):
        write_json(self.seal/'retention-receipt.json', {'status': 'SEALED'})
        with self.assertRaisesRegex(ValueError, 'SHA-256 pin'):
            self.checked()

    def test_archived_verifier_and_archive_are_authenticated(self):
        script = self.archived_script.read_bytes()
        write(self.archived_script, b'raise RuntimeError("Modified verifier")\n')
        with self.assertRaisesRegex(ValueError, 'untrusted.py'):
            self.checked()
        write(self.archived_script, script)
        write(self.seal/'retained.tar', b'different archive')
        with self.assertRaisesRegex(ValueError, 'Durable seal archive'):
            self.checked()

    def test_restore_must_bind_dmg_and_remain_historical(self):
        self.restore['newProductRuntime'] = 'PASS'
        with self.assertRaisesRegex(ValueError, 'Independent restore newProductRuntime'):
            self.checked()
        self.restore['newProductRuntime'] = 'NOT_RUN'
        wrong = self.reported_image.with_name('wrong.dmg')
        write(wrong, self.dmg_bytes)
        self.restore['restoredDmg'] = str(wrong)
        with self.assertRaisesRegex(ValueError, 'does not match the selected DMG member'):
            self.checked()

    def test_wrong_local_signing_profile_fails_even_with_matching_manifest_pin(self):
        modified = dict(package_dmg.SIGNATURE_POLICY, signingProfile='developer-id')
        self.pins['image_payload'] = write_json(self.image_manifest, modified)
        selection = self.restored/'000-selection.json'
        selected = json.loads(selection.read_bytes())
        selected['candidate']['image_payload']['sha256'] = self.pins['image_payload']
        self.manifest['selectionSha256'] = write_json(selection, selected)
        self.seal_pin = self.write_seal()
        self.restore['receiptSha256'] = self.seal_pin
        with self.assertRaisesRegex(ValueError, 'Engineering image signature policy signingProfile'):
            self.checked()


if __name__ == '__main__':
    unittest.main()
