"""Test the VM product harness with owned local fixtures."""
import importlib.util
import io
from pathlib import Path
import subprocess
import tarfile
import tempfile
import types
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    'meshchan_vm_host', Path(__file__).resolve().parents[1]
    / 'apps/meshchan_app/tool/macos_vm/host.py')
host = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(host)


class CollectionTest(unittest.TestCase):
    def test_fixture_is_collected_only_after_explicit_os_exit(self):
        for state, error in [('live', ''), ('closed', ''), ('unknown', ''), ('closed', 'ps denied')]:
            with self.subTest(state=state, error=error), tempfile.TemporaryDirectory() as directory:
                class VM:
                    def remote(self, command, **kwargs):
                        if command.startswith('if /bin/ps'):
                            return types.SimpleNamespace(stdout=state + '\n', stderr=error)
                        with tarfile.open(fileobj=kwargs['stdout'], mode='w') as archive:
                            names = ['app.stdout']
                            if '--exclude=fixture' not in command:
                                names.append('fixture/meshchan.sqlite')
                            for name in names:
                                info = tarfile.TarInfo(name)
                                info.size = 5
                                archive.addfile(info, io.BytesIO(b'owned'))
                        return types.SimpleNamespace(stdout='')

                product = host.Product.__new__(host.Product)
                product.out = Path(directory)
                product.vm = VM()
                product.state = {'products': {'Release': {'pid': 123, 'root': '/owned'}}}
                product.collect('Release')
                self.assertTrue((product.out / 'Release/app.stdout').is_file())
                self.assertEqual((product.out / 'Release/fixture/meshchan.sqlite').exists(),
                                 state == 'closed' and not error)


class JobTest(unittest.TestCase):
    def test_job_waits_for_complete_reply_without_resubmitting(self):
        for code in (0, 9):
            with self.subTest(code=code), tempfile.TemporaryDirectory(prefix='vm job ') as directory:
                replies = Path(directory)/'replies'
                replies.mkdir()
                status = replies/'42.exit'
                status.touch()
                (replies/'42.stdout').write_text('job result\n')
                (replies/'42.stderr').write_text('job diagnostic\n')
                sent = []

                def remote(command, **kwargs):
                    if 'input' in kwargs:
                        sent.append(kwargs['input'])
                        return
                    retry = f"sleep() {{ printf '%s\\n' {code} > {host.q(str(status))}; }}\n"
                    return subprocess.run(['/bin/bash', '-c', retry+command], check=True, **kwargs)

                product = host.Product.__new__(host.Product)
                product.vm = types.SimpleNamespace(remote=remote, runpath=lambda _: directory)
                product.state = {'run': 'owned'}
                with patch.object(host.time, 'time_ns', return_value=42):
                    if code == 0:
                        self.assertEqual(product.job('owned command'), 'job result\n')
                    else:
                        with self.assertRaisesRegex(ValueError, 'Guest command failed: job diagnostic'):
                            product.job('owned command')
                self.assertEqual(status.read_text(), f'{code}\n')
                self.assertEqual(sent, ['set -euo pipefail\nowned command\n'])


if __name__ == '__main__':
    unittest.main()
