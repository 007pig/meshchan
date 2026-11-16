"""Keep generated mobile hosts without leaking unrelated template scaffolding."""
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import prepare_mobile_probe as prepare
from regression_1d10 import digest


class MobilePreparationTest(unittest.TestCase):
    def prepare_copy(self, existing_counter_path):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        base = Path(temporary.name).resolve()
        product, target = base / 'product', base / 'probe'
        test_name = 'widget_test.dart' if existing_counter_path else 'existing_test.dart'
        originals = {'pubspec.yaml': 'name: controlled_workspace\n', 'pubspec.lock': 'controlled lock\n',
                     'apps/meshchan_app/pubspec.yaml': 'name: meshchan_app\ndependencies:\n',
                     'apps/meshchan_app/lib/main.dart': 'class ProductApp {}\n',
                     'apps/meshchan_app/test/' + test_name: 'original product test\n',
                     'tool/mobile_probe.dart.txt': 'void main() {}\n'}
        for name, content in originals.items():
            path = product / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        manifest = {name: digest(product / name) for name in originals}
        def flutter_create(argv, **kwargs):
            app = target / 'apps/meshchan_app'
            generated = {'test/widget_test.dart': 'testWidgets(MyApp());\n',
                         'lib/main.dart': 'class MyApp {}\n',
                         'analysis_options.yaml': 'generated template analyzer settings\n',
                         '.idea/generated.iml': 'generated IDE file\n',
                         '.metadata': 'generated Flutter project metadata\n',
                         'android/host.txt': 'Android host\n', 'ios/host.txt': 'iOS host\n'}
            for name, content in generated.items():
                path = app / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            return subprocess.CompletedProcess(argv, 0)
        with patch.object(prepare, 'ROOT', product), patch.object(prepare, 'source_manifest', return_value=manifest), \
                patch.object(prepare.subprocess, 'run', side_effect=flutter_create), \
                patch('sys.argv', ['prepare_mobile_probe.py', '--destination', str(target), '--flutter', '/installed/flutter']), \
                redirect_stdout(io.StringIO()):
            prepare.main()
        return product, target, originals

    def test_new_counter_and_non_host_scaffolding_are_removed(self):
        product, target, originals = self.prepare_copy(False)
        app = target / 'apps/meshchan_app'
        for name in ('test/widget_test.dart', 'analysis_options.yaml', '.idea/generated.iml'):
            self.assertFalse((app / name).exists(), name)
        for name in ('android/host.txt', 'ios/host.txt', '.metadata'):
            self.assertTrue((app / name).is_file(), name)
        for name, content in originals.items():
            self.assertEqual((product / name).read_text(), content)
        self.assertEqual((app / 'lib/main.dart').read_text(), originals['apps/meshchan_app/lib/main.dart'])
        self.assertEqual((app / 'test/existing_test.dart').read_text(), 'original product test\n')
        self.assertEqual((target / 'pubspec.lock').read_bytes(), (product / 'pubspec.lock').read_bytes())

    def test_original_test_with_counter_filename_is_restored_and_preserved(self):
        _, target, _ = self.prepare_copy(True)
        path = 'apps/meshchan_app/test/widget_test.dart'
        self.assertEqual((target / path).read_text(), 'original product test\n')
        facts = json.loads((target / 'probe-source.json').read_text())
        self.assertTrue(facts['productMainUnchanged'])


if __name__ == '__main__':
    unittest.main()
