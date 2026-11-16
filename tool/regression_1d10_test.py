"""Evidence safety and real subprocess failure propagation."""
import json
import os
from pathlib import Path
import tempfile
import unittest
import sys
import plistlib
from unittest.mock import patch

from check_schema_compatibility import database_files
from regression_1d10 import inventory, run_gate, source_manifest
from prepare_mobile_probe import main as prepare_mobile
from run_mobile_simulator_probe import probe_identifier


class RegressionEvidenceTest(unittest.TestCase):
    def test_simulator_runner_rejects_product_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.meshchan.meshchan'}))
            with self.assertRaises(ValueError):
                probe_identifier(app)

    def test_mobile_preparation_rejects_product_path_before_running_flutter(self):
        from regression_1d10 import ROOT
        with patch('sys.argv', ['prepare_mobile_probe.py', '--destination', str(ROOT),
                                '--flutter', '/missing/flutter']):
            with self.assertRaises(SystemExit) as rejected:
                prepare_mobile()
        self.assertEqual(rejected.exception.code, 2)

    def test_failed_child_is_recorded_and_evidence_cannot_be_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertFalse(run_gate(root, 'failure', [sys.executable, '-c',
                'print("failure evidence"); raise SystemExit(7)'], root, os.environ.copy()))
            record = json.loads((root / 'failure/result.json').read_text())
            self.assertEqual((record['status'], record['exitCode']), ('FAIL', 7))
            self.assertIn('failure evidence', (root / 'failure/output.log').read_text())
            with self.assertRaises(FileExistsError):
                run_gate(root, 'failure', [sys.executable, '-c', 'pass'], root, os.environ.copy())
            self.assertEqual(len((root / 'ledger.jsonl').read_text().splitlines()), 1)

    def test_bundle_inventory_records_symlinks_without_following_them(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'binary').write_bytes(b'complete bundle')
            (root / 'current').symlink_to('binary')
            result = inventory(root)
            self.assertEqual(result['current'], {'symlink': 'binary'})
            self.assertEqual(result['binary']['size'], 15)

    def test_manifest_includes_app_native_and_verification_inputs(self):
        result = source_manifest()
        for name in ('apps/meshchan_app/lib/main.dart',
                     'apps/meshchan_app/macos/Runner/AppDelegate.swift',
                     'apps/meshchan_app/macos/Runner/Base.lproj/MainMenu.xib',
                     '.github/workflows/ci.yml', 'pubspec.lock',
                     'tool/regression_1d10.py'):
            self.assertIn(name, result)

    def test_rejection_snapshot_detects_sidecar_creation_deletion_and_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'meshchan.sqlite').write_bytes(b'closed original')
            original = database_files(root)
            sidecar = root / 'meshchan.sqlite-wal'
            sidecar.write_bytes(b'first')
            created = database_files(root)
            self.assertNotEqual(original, created)
            sidecar.write_bytes(b'second')
            self.assertNotEqual(created, database_files(root))
            sidecar.unlink()
            self.assertEqual(original, database_files(root))


if __name__ == '__main__':
    unittest.main()
