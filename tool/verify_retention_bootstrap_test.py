import hashlib
import io
import json
from contextlib import redirect_stderr
from pathlib import Path
import stat
from subprocess import CompletedProcess
import tempfile
import unittest
from unittest.mock import patch

from verify_retention_bootstrap import main, stage_verifier


class RetentionBootstrapTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='Meshchan bootstrap test ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.seal = self.root/'sealed object'
        self.tool = self.seal/'verifier/tool/retain_release.py'
        self.tool.parent.mkdir(parents=True)
        self.tool.write_text('print("Verified entry point")\n')
        verifier = {
            name: {'type': 'directory', 'mode': stat.S_IMODE(path.stat().st_mode)}
            for name, path in (('.', self.tool.parent.parent), ('tool', self.tool.parent))
        }
        raw = self.tool.read_bytes()
        verifier['tool/retain_release.py'] = {
            'type': 'file', 'mode': stat.S_IMODE(self.tool.stat().st_mode),
            'size': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(),
        }
        manifest = json.dumps({'formatVersion': 1, 'verifier': verifier}).encode()
        (self.seal/'retention-manifest.json').write_bytes(manifest)
        receipt = json.dumps({'formatVersion': 1, 'status': 'SEALED',
                              'manifestSha256': hashlib.sha256(manifest).hexdigest()}).encode()
        (self.seal/'retention-receipt.json').write_bytes(receipt)
        self.pin = hashlib.sha256(receipt).hexdigest()
        self.args = ['check', '--retention', str(self.seal), '--receipt-sha256', self.pin,
                     '--work', str(self.root/'fresh work')]

    def test_stages_independent_verified_bytes(self):
        staging = self.root/'private copy'
        staging.mkdir()
        original = self.tool.read_bytes()
        copied = stage_verifier(self.seal, self.pin, staging)
        self.tool.unlink()
        self.assertEqual(copied.read_bytes(), original)

    def test_executes_only_after_authentication_and_preserves_status(self):
        def run(command, check):
            self.assertFalse(check)
            self.assertEqual(command[1:5], ['-I', '-S', '-B', '-c'])
            copy = Path(command[6])
            self.assertEqual(copy.read_bytes(), self.tool.read_bytes())
            self.assertNotEqual(copy, self.tool)
            self.assertEqual(command[7:], self.args)
            return CompletedProcess(command, 3)

        with patch('verify_retention_bootstrap.subprocess.run', side_effect=run) as launch:
            self.assertEqual(main(self.args), 3)
            launch.assert_called_once()

    def test_rejects_bad_pin_manifest_modified_code_and_extra_members(self):
        for corruption in ('receipt', 'manifest', 'verifier', 'extra'):
            with self.subTest(corruption=corruption), redirect_stderr(io.StringIO()) as errors, \
                    patch('verify_retention_bootstrap.subprocess.run') as launch:
                targets = {
                    'receipt': self.seal/'retention-receipt.json',
                    'manifest': self.seal/'retention-manifest.json',
                    'verifier': self.tool,
                    'extra': self.tool.parent/'unexpected.py',
                }
                file = targets[corruption]
                previous = None if corruption == 'extra' else file.read_bytes()
                file.write_bytes(b'changed\n')
                try:
                    self.assertEqual(main(self.args), 1)
                    self.assertIn('Retention bootstrap failed:', errors.getvalue())
                    launch.assert_not_called()
                finally:
                    if previous is None:
                        file.unlink()
                    else:
                        file.write_bytes(previous)

    def test_holds_legacy_verifier_to_checkout_boundary(self):
        checkout = self.root/'old checkout'
        checkout.mkdir()
        (checkout/'.git').mkdir()
        args = ['restore', *self.args[1:], '--destination', str(checkout/'new restore')]
        with redirect_stderr(io.StringIO()) as errors, patch('verify_retention_bootstrap.subprocess.run') as launch:
            self.assertEqual(main(args), 1)
            self.assertIn('outside a Git checkout', errors.getvalue())
            launch.assert_not_called()


if __name__ == '__main__':
    unittest.main()
