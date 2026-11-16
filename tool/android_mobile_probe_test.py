"""Guard the target identity and distinguish dependency success from support."""
import unittest

from run_android_mobile_probe import owned_receipt_path, require_owned_emulator, validate_report


class AndroidMobileProbeTest(unittest.TestCase):
    def test_receipt_discovery_accepts_code_cache_but_refuses_ambiguity_and_escape(self):
        self.assertEqual(owned_receipt_path('./code_cache/meshchan-mobile-report.json\n'),
                         'code_cache/meshchan-mobile-report.json')
        self.assertIsNone(owned_receipt_path(''))
        for output in ['../meshchan-mobile-report.json',
                       './cache/meshchan-mobile-report.json\n./code_cache/meshchan-mobile-report.json']:
            with self.assertRaises(ValueError):
                owned_receipt_path(output)

    def test_refuses_physical_other_avd_and_wrong_abi(self):
        for actual, expected, qemu, abi in [
                ('owned', 'owned', '0', 'arm64-v8a'),
                ('other', 'owned', '1', 'arm64-v8a'),
                ('owned', 'owned', '1', 'x86_64')]:
            with self.assertRaises(ValueError):
                require_owned_emulator(actual, expected, qemu, abi)

    def test_partial_or_wrong_platform_receipt_is_not_success(self):
        for report in [{'passed': True}, {'os': 'ios', 'passed': True},
                       {'passed': 1, 'storageCapability': 'SUPPORTED'}]:
            with self.assertRaises(ValueError):
                validate_report(report)


if __name__ == '__main__':
    unittest.main()
