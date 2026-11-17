"""Compiled-report identity must match the independently requested candidate."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('runtime_checker', Path(__file__).resolve().parents[1] /
    'apps/meshchan_app/tool/check_macos_runtime.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class MacOSRuntimeVersionTest(unittest.TestCase):
    def test_compiled_version_missing_wrong_or_resource_failure_is_rejected(self):
        report = {'passed': True, 'appVersion': '0.1.0-rc.1+6', 'receivePorts': 0,
                  'pendingRequests': 0, 'phases': ['opening', 'ready', 'closing', 'closed']}
        shutdown = [{'resourcesReleased': True, 'workerExited': True}]
        checker.validate_runtime_report(0, [report], shutdown, '0.1.0-rc.1', 6)
        for version in (None, '0.1.0+6', '0.1.0-rc.1+5', '0.1.0-beta.1+5'):
            with self.assertRaisesRegex(RuntimeError, 'Compiled App version mismatch'):
                checker.validate_runtime_report(0, [{**report, 'appVersion': version}], shutdown, '0.1.0-rc.1', 6)
        with self.assertRaises(RuntimeError):
            checker.validate_runtime_report(0, [report], [], '0.1.0-rc.1', 6)
        with self.assertRaises(RuntimeError):
            checker.validate_runtime_report(0, [{**report, 'receivePorts': 1}], shutdown, '0.1.0-rc.1', 6)


if __name__ == '__main__':
    unittest.main()
