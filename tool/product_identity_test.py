"""Independent mapping, override, source-template and actual-product negatives."""
import base64
import contextlib
import io
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import candidate_common as c
import check_product_version
from product_identity import (apple_short_version, check_app, check_source_identity,
                              check_xcode_environment)


class ProductIdentityTest(unittest.TestCase):
    def test_xcode_version_checks_use_the_supplied_interpreter(self):
        project = c.ROOT/'apps/meshchan_app/macos/Runner.xcodeproj/project.pbxproj'
        scripts = [json.loads(value) for value in re.findall(r'shellScript = ("(?:[^"\\]|\\.)*");', project.read_text())
                   if 'check_product_version.py' in value]
        self.assertEqual(len(scripts), 2)
        with tempfile.TemporaryDirectory(prefix='version phase with spaces ') as directory:
            root = Path(directory)
            macos = root/'apps/meshchan_app/macos'
            (macos/'Flutter/ephemeral').mkdir(parents=True)
            checker = root/'tool/check_product_version.py'
            checker.parent.mkdir()
            checker.write_text("from pathlib import Path\nPath('checker.log').write_text('fallback')\n")
            interpreter = root/'selected bin/python3'
            interpreter.parent.mkdir()
            interpreter.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > checker.log\n')
            interpreter.chmod(0o755)
            flutter = root/'flutter sdk'
            assemble = flutter/'packages/flutter_tools/bin/macos_assemble.sh'
            assemble.parent.mkdir(parents=True)
            assemble.write_text('#!/bin/sh\ntouch assemble.log\n')
            assemble.chmod(0o755)
            env = {'PROJECT_DIR': str(macos), 'PRODUCT_NAME': 'Meshchan', 'FLUTTER_ROOT': str(flutter),
                   'PATH': str(Path(sys.executable).parent)+os.pathsep+os.defpath}
            checker_log, assemble_log = macos/'checker.log', macos/'assemble.log'
            for index, script in enumerate(scripts):
                for setting in ('selected', 'missing', 'fallback'):
                    with self.subTest(phase=index, setting=setting):
                        checker_log.unlink(missing_ok=True)
                        assemble_log.unlink(missing_ok=True)
                        phase_env = env.copy()
                        if setting != 'fallback':
                            phase_env['MESHCHAN_BUILD_PYTHON'] = str(interpreter if setting == 'selected'
                                                                      else root/'missing interpreter')
                        phase = subprocess.run(['/bin/sh', '-c', script], cwd=macos, env=phase_env,
                                               text=True, capture_output=True)
                        if setting == 'missing':
                            self.assertNotEqual(phase.returncode, 0)
                            self.assertFalse(checker_log.exists())
                            self.assertFalse(assemble_log.exists())
                        else:
                            self.assertEqual(phase.returncode, 0, phase.stderr)
                            self.assertTrue(assemble_log.is_file())
                            if setting == 'fallback':
                                self.assertEqual(checker_log.read_text(), 'fallback')
                            else:
                                path, flag = checker_log.read_text().splitlines()
                                self.assertEqual(Path(path).resolve(), checker.resolve())
                                self.assertEqual(flag, '--xcode-environment')

    def test_semver_mapping_and_rejections(self):
        for version in ('0.1.0-rc.1', '0.1.0-beta.1', '0.1.0'):
            self.assertEqual(apple_short_version(version), '0.1.0')
        self.assertEqual(apple_short_version('12.30.4-alpha-2.0'), '12.30.4')
        for version in ('', '0.1', '0.1.0.1', '01.1.0', '0.1.0-01', '0.1.0-rc..1',
                        '0.1.0-', '0.1.0+6', '0.1.0-rc.1\n', ' 0.1.0', 'anything'):
            with self.assertRaises(ValueError, msg=version):
                apple_short_version(version)

    def test_source_template_and_explicit_build_progression(self):
        app_build = 10
        self.assertEqual(check_source_identity(c.ROOT, '0.1.0-rc.1', app_build)['CFBundleVersion'], '10')
        for build in (0, -1, True, '6', 9):
            with self.assertRaises(ValueError):
                check_source_identity(c.ROOT, '0.1.0-rc.1', build)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runner = 'apps/meshchan_app/macos/Runner'
            for name in ('Info.plist', 'Configs/AppInfo.xcconfig', 'Configs/Version.xcconfig'):
                target = root / runner / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(c.ROOT / runner / name, target)
            for name, before, after in [('Info.plist', '$(MESHCHAN_APPLE_SHORT_VERSION)', '$(FLUTTER_BUILD_NAME)'),
                                        ('Configs/AppInfo.xcconfig', 'org.meshchan.meshchan', 'org.other'),
                                        ('Configs/Version.xcconfig', '0.1.0-rc.1', '0.1.0')]:
                path = root / runner / name
                original = path.read_text()
                path.write_text(original.replace(before, after))
                with self.assertRaises(ValueError):
                    check_source_identity(root, '0.1.0-rc.1', app_build)
                path.write_text(original)

    def test_actual_app_missing_incomplete_and_each_wrong_or_missing_field(self):
        # Explicit expected values independent of production constants.
        expected = {'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '6',
                    'CFBundleIdentifier': 'org.meshchan.meshchan', 'CFBundleName': 'Meshchan',
                    'MeshchanProductVersion': '0.1.0-rc.1'}
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'Meshchan.app'
            with self.assertRaises(ValueError):
                check_app(app, '0.1.0-rc.1', 6)
            binary = app / 'Contents/MacOS/Meshchan'
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'fixture')
            binary.chmod(0o755)
            with self.assertRaises(OSError):
                check_app(app, '0.1.0-rc.1', 6)
            plist = app / 'Contents/Info.plist'
            plist.write_bytes(plistlib.dumps(expected))
            self.assertEqual(check_app(app, '0.1.0-rc.1', 6), expected)
            binary.write_bytes(b'')
            with self.assertRaisesRegex(ValueError, 'incomplete App executable'):
                check_app(app, '0.1.0-rc.1', 6)
            binary.write_bytes(b'fixture')
            for key in expected:
                for changed in ({**expected, key: 'wrong'}, {k: v for k, v in expected.items() if k != key}):
                    plist.write_bytes(plistlib.dumps(changed))
                    with self.assertRaisesRegex(ValueError, key):
                        check_app(app, '0.1.0-rc.1', 6)
            plist.write_bytes(plistlib.dumps({**expected, 'CFBundleVersion': 6}))
            with self.assertRaisesRegex(ValueError, 'CFBundleVersion'):
                check_app(app, '0.1.0-rc.1', 6)

    def test_raw_inputs_and_conflicting_overrides_fail_before_normalization(self):
        def encoded(*values):
            return ','.join(base64.b64encode(v.encode()).decode() for v in values)
        env = {'BUILD_NAME': '0.1.0-rc.1', 'BUILD_NUMBER': '6',
               'DART_DEFINES': encoded('FLUTTER_BUILD_NAME=0.1.0-rc.1', 'FLUTTER_BUILD_NUMBER=6')}
        check_xcode_environment(env, '0.1.0-rc.1', 6)
        for changed in ({**env, 'BUILD_NAME': '0.1.0'}, {**env, 'BUILD_NAME': '0.1.0-invalid..1'},
                        {**env, 'BUILD_NUMBER': '06'}, {**env, 'BUILD_NUMBER': '7'},
                        {**env, 'DART_DEFINES': '%%%bad'},
                        {**env, 'DART_DEFINES': encoded('FLUTTER_BUILD_NAME=0.1.0')},
                        {**env, 'DART_DEFINES': env['DART_DEFINES'] + ',' + encoded('FLUTTER_BUILD_NUMBER=7')},
                        {**env, 'MESHCHAN_PRODUCT_VERSION': '0.1.0'}):
            with self.assertRaises(ValueError):
                check_xcode_environment(changed, '0.1.0-rc.1', 6)
        check_xcode_environment({'DART_DEFINES': env['DART_DEFINES']}, '0.1.0-rc.1', 6)
        with self.assertRaises(ValueError):
            check_xcode_environment({k: v for k, v in env.items() if k != 'DART_DEFINES'}, '0.1.0-rc.1', 6)

    def test_requested_missing_app_is_a_failing_command_not_source_pass(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()) as output, \
                contextlib.redirect_stderr(io.StringIO()), patch('sys.argv', ['check', '--expected-version',
                '0.1.0-rc.1', '--app-build', '6', '--app', directory + '/missing.app']):
            self.assertEqual(check_product_version.main(), 1)
            self.assertEqual(output.getvalue(), '')


if __name__ == '__main__':
    unittest.main()
