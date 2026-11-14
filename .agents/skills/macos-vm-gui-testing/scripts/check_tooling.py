#!/usr/bin/env python3
"""Offline checks for guest identity guards, review timeout and result validation."""
import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.dont_write_bytecode = True
import vm

class ToolingChecks(unittest.TestCase):
    def test_missing_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / 'config.json'
            config.write_text('{}')
            with self.assertRaisesRegex(ValueError, 'Missing configuration'):
                vm.VM(config)

    def test_invalid_stage(self):
        result = subprocess.run([sys.executable, str(vm.HERE / 'vm.py'), 'run', 'unknown'], capture_output=True)
        self.assertEqual(result.returncode, 2)

    def test_native_helpers_refuse_host(self):
        if BUILD is None:
            self.skipTest('Pass build directory to exercise native guards')
        for relative in ['bin/key-input', 'bin/place-window', 'pinyin-bin/ime-inspect', 'UTMUIProbe.app/Contents/MacOS/UTMUIProbe']:
            result = subprocess.run([str(Path(BUILD) / relative), 'reset'], capture_output=True)
            self.assertEqual(result.returncode, 65, relative)

    def test_guest_scripts_refuse_wrong_identity(self):
        for script in ['guest.sh', 'pinyin.sh', 'stop-guest.sh']:
            result = subprocess.run(['bash', str(vm.HERE / script), '00000000-0000-0000-0000-000000000000', 'baseline'], capture_output=True)
            self.assertEqual(result.returncode, 65, script)

    def test_remote_guard_covers_compound_commands(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'known_hosts').touch()
            config = {'host':'192.0.2.1', 'user':'test', 'uuid':'00000000-0000-0000-0000-000000000000', 'known_hosts':str(root / 'known_hosts'), 'runtime_dir':str(root / 'runtime'), 'evidence_dir':str(root / 'evidence'), 'guest_root':'/Users/test/probe'}
            (root / 'config.json').write_text(json.dumps(config))
            client = vm.VM(root / 'config.json')
            sentinel = root / 'MUST_NOT_EXIST'
            with patch.object(vm, 'call') as call:
                client.remote('true; touch ' + str(sentinel))
            command = call.call_args.args[0][-1]
            result = subprocess.run(['bash', '-c', command], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(sentinel.exists())
            with self.assertRaises(ValueError):
                client.runpath('../escape')

    def test_preedit_review_timeout_without_commit(self):
        source = (vm.HERE / 'pinyin.sh').read_text()
        function = source.split('review_gate() {',1)[1].split('\nsw_vers',1)[0]
        with tempfile.TemporaryDirectory() as tmp:
            # Accelerate the wait without changing its control flow.
            script = 'run="$1"\nsleep() { :; }\nreview_gate() {' + function + '\nreview_gate zhongwen\n'
            result = subprocess.run(['bash', '-c', script, 'test', tmp], capture_output=True)
            self.assertEqual(result.returncode, 78)
            self.assertTrue((Path(tmp) / 'ready-zhongwen').exists())
            self.assertFalse((Path(tmp) / 'commit-zhongwen').exists())
            self.assertFalse((Path(tmp) / 'actual.txt').exists())

    def test_independent_saved_text_verification(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / '20260101T000000Z-baseline-123'
            run.mkdir()
            (run / 'exit-code').write_text('0\n')
            (run / 'actual.txt').write_text(''.join(f'VM-baseline-{i:03d}\n' for i in range(1,4)))
            for name in ['start','middle','end']:
                (run / (name + '.png')).write_bytes(b'\x89PNG\r\n\x1a\n')
            for i in range(1,4):
                (run / f'focus-{i}.json').write_text('{"focusVerified":true}')
            with contextlib.redirect_stdout(io.StringIO()):
                vm.verify(run)
            (run / 'actual.txt').write_text('injected or missing content\n')
            with self.assertRaisesRegex(ValueError, 'Actual saved text'):
                vm.verify(run)
            (run / 'exit-code').write_text('143')
            with self.assertRaisesRegex(ValueError, 'interrupted'):
                vm.verify(run)

if __name__ == '__main__':
    BUILD = sys.argv[1] if len(sys.argv) > 1 else None
    # Keep build path for the native test; unittest receives no positional path.
    unittest.main(argv=[sys.argv[0]], verbosity=2)
