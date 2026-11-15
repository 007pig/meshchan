"""Guest evidence collection must not copy a live owner's database."""
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import types
import unittest

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


if __name__ == '__main__':
    unittest.main()
