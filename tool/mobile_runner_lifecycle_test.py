"""Exercise mobile runner polling and owned-process cleanup without devices."""
from contextlib import ExitStack, redirect_stdout
import io
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import run_android_mobile_probe as android
import run_mobile_simulator_probe as ios


def receipt(platform):
    return {'probe': 'meshchan.mobile.1d10', 'os': platform,
            'abi': platform + '_arm64', 'passed': True,
            'sqliteVersion': 'controlled test version',
            'sqliteLoadReadWriteClose': 'PASS', 'coreStorageRejection': 'PASS',
            'businessDirectoryAbsent': True, 'storageCapability': 'UNSUPPORTED',
            'serialEnumerationGuard': 'PASS'}


class AndroidCleanupTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.evidence = self.root / 'evidence'
        sdk = self.root / 'sdk'
        image = sdk / 'system-images/android-36/google_apis_playstore/arm64-v8a'
        image.mkdir(parents=True)
        (image / 'source.properties').write_text('controlled test image')
        java = self.root / 'java'
        java.mkdir()
        apk = self.root / 'probe.apk'
        apk.touch()
        self.argv = ['run_android_mobile_probe.py', '--apk', str(apk), '--sdk', str(sdk),
                     '--java-home', str(java), '--evidence', str(self.evidence)]
        self.child = Mock(pid=12345)
        self.child.poll.return_value = None
        self.child.wait.return_value = 0
        self.kill_failure = None
        self.cleanup_oserror = None
        self.process_receipt_failure = False
        self.recording_failure = None
        self.storage_full = False
        self.executed = []
        self.real_write_json = android.write_json
        self.report = receipt('android')

    def command(self, argv, **kwargs):
        self.executed.append(argv)
        output, code = '', 0
        if self.cleanup_oserror and argv[-3:] == ['am', 'force-stop', android.PROBE_ID]:
            raise OSError('controlled adb launch failure')
        if 'badging' in argv:
            output = "package: name='" + android.PROBE_ID + "'\n"
        elif argv[-3:] == ['emu', 'avd', 'name']:
            output = 'meshchan_1d10_' + self.root.name.replace('-', '_') + '\nOK\n'
        elif 'getprop' in argv:
            output = {'sys.boot_completed': '1', 'ro.kernel.qemu': '1',
                      'ro.product.cpu.abi': 'arm64-v8a', 'ro.build.version.sdk': '36',
                      'ro.build.version.release': '16'}[argv[-1]]
        elif 'find' in argv:
            output = './code_cache/meshchan-mobile-report.json\n'
        elif 'cat' in argv:
            output = json.dumps(self.report)
        elif argv[-2:] == ['emu', 'kill'] and self.kill_failure:
            if self.kill_failure == 'timeout':
                raise subprocess.TimeoutExpired(argv, 120, output='controlled adb timeout')
            code = 1
        return subprocess.CompletedProcess(argv, code, output, 'controlled error' if code else '')

    def write(self, path, value):
        if path.name == 'emulator-process.json' and self.process_receipt_failure:
            raise OSError('controlled process receipt failure')
        if self.storage_full and (path.name != 'commands.json' or
                                  value[-1]['name'].startswith('stop ')):
            raise OSError('controlled full evidence filesystem: ' + path.name)
        if path.name == self.recording_failure or (
                self.recording_failure == 'cleanup commands' and path.name == 'commands.json'
                and value[-1]['name'].startswith('stop ')):
            raise OSError('controlled evidence recording failure: ' + path.name)
        return self.real_write_json(path, value)

    def invoke(self):
        with ExitStack() as stack:
            stack.enter_context(patch.object(android.sys, 'argv', self.argv))
            stack.enter_context(patch.object(android.socket, 'socket'))
            stack.enter_context(patch.object(android.subprocess, 'run', side_effect=self.command))
            stack.enter_context(patch.object(android.subprocess, 'Popen', return_value=self.child))
            stack.enter_context(patch.object(android, 'write_json', side_effect=self.write))
            stack.enter_context(redirect_stdout(io.StringIO()))
            android.main()

    def timeout(self):
        return subprocess.TimeoutExpired('owned emulator', 60)

    def test_process_receipt_failure_is_guarded_after_spawn(self):
        self.process_receipt_failure = True
        with self.assertRaisesRegex(OSError, 'controlled process receipt failure'):
            self.invoke()
        self.child.terminate.assert_called_once_with()
        self.child.wait.assert_called_once()
        self.assertTrue(json.loads((self.evidence / 'emulator-exit.json').read_text())['processReaped'])
        self.assertFalse(any('install' in argv for argv in self.executed))

    def test_cleanup_poll_error_does_not_replace_process_receipt_failure(self):
        self.process_receipt_failure = True
        self.child.poll.side_effect = OSError('controlled cleanup poll failure')
        with self.assertRaisesRegex(OSError, 'controlled process receipt failure'):
            self.invoke()
        self.child.wait.assert_called_once()
        self.assertIn('controlled cleanup poll failure', (self.evidence / 'cleanup-errors.json').read_text())

    def test_cleanup_oserror_continues_remaining_command_and_reaping(self):
        self.cleanup_oserror = True
        with self.assertRaises(ExceptionGroup) as failed:
            self.invoke()
        self.assertTrue(any(argv[-2:] == ['emu', 'kill'] for argv in self.executed))
        self.child.wait.assert_called_once()
        self.assertTrue(any(isinstance(e, OSError) for e in failed.exception.exceptions))
        errors = json.loads((self.evidence / 'cleanup-errors.json').read_text())
        self.assertIn('controlled adb launch failure', errors[0])

    def test_cleanup_command_recording_errors_do_not_skip_reaping(self):
        self.recording_failure = 'cleanup commands'
        with self.assertRaises(ExceptionGroup):
            self.invoke()
        self.assertTrue(any(argv[-2:] == ['emu', 'kill'] for argv in self.executed))
        self.child.wait.assert_called_once()
        self.assertEqual(len(json.loads((self.evidence / 'cleanup-errors.json').read_text())), 2)

    def test_primary_probe_failure_survives_cleanup_oserror(self):
        self.report['passed'] = False
        self.cleanup_oserror = True
        with self.assertRaisesRegex(ValueError, 'Android dependency/API assertions failed'):
            self.invoke()
        self.child.wait.assert_called_once()
        self.assertTrue((self.evidence / 'cleanup-errors.json').exists())

    def test_unwritable_diagnostics_do_not_mask_primary_or_skip_reaping(self):
        self.storage_full = True
        with self.assertRaisesRegex(OSError, 'emulator-process.json') as failed:
            self.invoke()
        self.child.terminate.assert_called_once_with()
        self.child.wait.assert_called_once()
        self.assertIn('emulator-exit.json', '\n'.join(failed.exception.__notes__))
        self.assertIn('cleanup-errors.json', '\n'.join(failed.exception.__notes__))

    def test_exit_recording_failure_does_not_mask_primary_probe_failure(self):
        self.report['passed'] = False
        self.recording_failure = 'emulator-exit.json'
        with self.assertRaisesRegex(ValueError, 'Android dependency/API assertions failed'):
            self.invoke()
        self.assertIn('emulator-exit.json', (self.evidence / 'cleanup-errors.json').read_text())

    def test_adb_error_and_timeout_fall_back_to_terminate_and_reap(self):
        for failure in ('error', 'timeout'):
            with self.subTest(failure=failure):
                self.evidence = self.root / failure
                self.argv[-1] = str(self.evidence)
                self.child.reset_mock()
                self.kill_failure = failure
                self.child.wait.side_effect = [self.timeout(), -15]
                with self.assertRaises(ExceptionGroup) as failed:
                    self.invoke()
                self.child.terminate.assert_called_once_with()
                self.child.kill.assert_not_called()
                self.assertEqual(self.child.wait.call_count, 2)
                self.assertTrue(any(isinstance(e, subprocess.TimeoutExpired)
                                    for e in failed.exception.exceptions))
                exit_record = json.loads((self.evidence / 'emulator-exit.json').read_text())
                self.assertEqual(exit_record['exitCode'], -15)
                self.assertTrue(exit_record['processReaped'])
                errors = json.loads((self.evidence / 'cleanup-errors.json').read_text())
                self.assertIn('emu', errors[0])
                self.assertGreaterEqual(len(errors), 2)

    def test_stubborn_child_is_killed_and_reaped_with_errors_retained(self):
        self.kill_failure = 'error'
        self.child.wait.side_effect = [self.timeout(), self.timeout(), -9]
        with self.assertRaises(ExceptionGroup):
            self.invoke()
        self.child.terminate.assert_called_once_with()
        self.child.kill.assert_called_once_with()
        record = json.loads((self.evidence / 'emulator-exit.json').read_text())
        self.assertEqual(record['exitCode'], -9)
        self.assertTrue(record['processReaped'])
        self.assertEqual(len(json.loads((self.evidence / 'cleanup-errors.json').read_text())), 3)

    def test_unreaped_child_is_recorded_as_unconfirmed(self):
        self.kill_failure = 'timeout'
        self.child.wait.side_effect = [self.timeout(), self.timeout(), self.timeout()]
        with self.assertRaises(ExceptionGroup):
            self.invoke()
        record = json.loads((self.evidence / 'emulator-exit.json').read_text())
        self.assertIsNone(record['exitCode'])
        self.assertFalse(record['processReaped'])
        self.assertFalse(record['productQuitClaim'])
        self.assertEqual(len(json.loads((self.evidence / 'cleanup-errors.json').read_text())), 4)

    def test_original_probe_failure_survives_cleanup_failure(self):
        self.report['passed'] = False
        self.kill_failure = 'error'
        self.child.wait.side_effect = [self.timeout(), -15]
        with self.assertRaisesRegex(ValueError, 'Android dependency/API assertions failed'):
            self.invoke()
        self.child.terminate.assert_called_once_with()
        self.assertTrue((self.evidence / 'cleanup-errors.json').is_file())
        self.assertTrue(json.loads((self.evidence / 'emulator-exit.json').read_text())['processReaped'])

    def test_successful_adb_shutdown_needs_no_process_signal(self):
        self.invoke()
        self.child.terminate.assert_not_called()
        self.child.kill.assert_not_called()
        self.assertFalse((self.evidence / 'cleanup-errors.json').exists())
        self.assertTrue(json.loads((self.evidence / 'emulator-exit.json').read_text())['processReaped'])

    def test_adb_failure_is_not_a_pass_if_child_already_exited(self):
        self.kill_failure = 'error'
        self.child.wait.return_value = 0
        with self.assertRaises(ExceptionGroup):
            self.invoke()
        self.child.terminate.assert_not_called()
        self.child.kill.assert_not_called()
        self.assertEqual(json.loads((self.evidence / 'emulator-exit.json').read_text())['exitCode'], 0)
        self.assertEqual(len(json.loads((self.evidence / 'cleanup-errors.json').read_text())), 1)


class IosReceiptTest(unittest.TestCase):
    def test_explicit_receipt_validation_rejects_missing_wrong_and_non_boolean_facts(self):
        ios.validate_report(receipt('ios'))
        invalid = [None, [], {'passed': True}]
        for field, value in [('passed', 1), ('os', 'android'), ('abi', 'ios_x64'),
                             ('businessDirectoryAbsent', 1), ('coreStorageRejection', 'FAIL'),
                             ('sqliteVersion', ''), ('storageCapability', 'SUPPORTED')]:
            report = receipt('ios')
            report[field] = value
            invalid.append(report)
        for report in invalid:
            with self.subTest(report=report), self.assertRaises(ValueError):
                ios.validate_report(report)

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        app = self.root / 'Probe.app'
        app.mkdir()
        (app / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'org.meshchan.probe.meshchanApp'}))
        self.container = self.root / 'container'
        (self.container / 'tmp').mkdir(parents=True)
        self.result_file = self.container / 'tmp/meshchan-mobile-report.json'
        self.evidence = self.root / 'evidence'
        self.argv = ['run_mobile_simulator_probe.py', '--app', str(app),
                     '--evidence', str(self.evidence), '--runtime', 'controlled-runtime']
        self.commands = []
        self.cleanup_oserror = False
        self.recording_failure = None
        self.real_write_json = ios.write_json

    def command(self, argv, **kwargs):
        self.commands.append(argv[4])
        if self.cleanup_oserror and argv[4] == 'terminate':
            raise OSError('controlled simctl launch failure')
        output = {'create': 'controlled-device\n',
                  'get_app_container': str(self.container) + '\n'}.get(argv[4], '')
        return subprocess.CompletedProcess(argv, 0, output, '')

    def write(self, path, value):
        if self.recording_failure == 'cleanup commands' and path.name == 'commands.json' and (
                self.commands[-1] in ('terminate', 'shutdown')):
            raise OSError('controlled simulator command recording failure')
        if self.recording_failure == 'all diagnostics' and (
                path.name in ('report.json', 'cleanup-errors.json') or
                (path.name == 'commands.json' and self.commands[-1] in ('terminate', 'shutdown'))):
            raise OSError('controlled full evidence filesystem: ' + path.name)
        return self.real_write_json(path, value)

    def invoke(self, clock, publication=None):
        with ExitStack() as stack:
            stack.enter_context(patch.object(ios.sys, 'argv', self.argv))
            stack.enter_context(patch.object(ios.subprocess, 'run', side_effect=self.command))
            stack.enter_context(patch.object(ios.time, 'monotonic', side_effect=clock))
            stack.enter_context(patch.object(ios, 'write_json', side_effect=self.write))
            sleeping = stack.enter_context(patch.object(ios.time, 'sleep', side_effect=publication))
            stack.enter_context(redirect_stdout(io.StringIO()))
            ios.main()
            return sleeping.call_count

    def test_empty_and_partial_receipts_are_observed_until_complete(self):
        self.result_file.write_text('')
        pending = iter(['{"probe":', json.dumps(receipt('ios'))])
        sleeps = self.invoke([0, 0, 1, 2], lambda _: self.result_file.write_text(next(pending)))
        self.assertEqual(sleeps, 2)
        self.assertTrue(json.loads((self.evidence / 'report.json').read_text())['passed'])
        self.assertEqual(self.commands.count('launch'), 1)
        self.assertEqual(self.commands[-2:], ['terminate', 'shutdown'])

    def test_partial_receipt_still_fails_at_original_deadline_and_cleans_up(self):
        self.result_file.write_text('{')
        with self.assertRaisesRegex(RuntimeError, 'No dependency/API report within observation period'):
            self.invoke([0, 0, 119.9, 120])
        self.assertFalse((self.evidence / 'report.json').exists())
        self.assertEqual(self.commands[-2:], ['terminate', 'shutdown'])

    def test_complete_failed_receipt_is_not_retried(self):
        report = receipt('ios')
        report['passed'] = False
        self.result_file.write_text(json.dumps(report))
        with self.assertRaisesRegex(ValueError, 'iOS dependency/API assertions failed'):
            self.invoke([0, 0], lambda _: self.fail('A complete failed report must not be retried'))
        self.assertEqual(json.loads((self.evidence / 'report.json').read_text()), report)
        self.assertEqual(self.commands[-2:], ['terminate', 'shutdown'])

    def test_cleanup_oserror_does_not_skip_simulator_shutdown(self):
        self.cleanup_oserror = True
        self.result_file.write_text(json.dumps(receipt('ios')))
        with self.assertRaises(ExceptionGroup):
            self.invoke([0, 0])
        self.assertEqual(self.commands[-2:], ['terminate', 'shutdown'])
        self.assertIn('controlled simctl launch failure', (self.evidence / 'cleanup-errors.json').read_text())

    def test_cleanup_recording_errors_do_not_skip_simulator_shutdown(self):
        self.recording_failure = 'cleanup commands'
        self.result_file.write_text(json.dumps(receipt('ios')))
        with self.assertRaises(ExceptionGroup):
            self.invoke([0, 0])
        self.assertEqual(self.commands[-2:], ['terminate', 'shutdown'])
        self.assertEqual(len(json.loads((self.evidence / 'cleanup-errors.json').read_text())), 2)

    def test_primary_observation_error_survives_cleanup_oserror(self):
        self.cleanup_oserror = True
        self.result_file.write_text('{')
        with self.assertRaisesRegex(RuntimeError, 'No dependency/API report'):
            self.invoke([0, 120])
        self.assertEqual(self.commands[-2:], ['terminate', 'shutdown'])

    def test_unwritable_diagnostics_preserve_primary_recording_error(self):
        self.recording_failure = 'all diagnostics'
        self.result_file.write_text(json.dumps(receipt('ios')))
        with self.assertRaisesRegex(OSError, 'report.json') as failed:
            self.invoke([0, 0])
        self.assertEqual(self.commands[-2:], ['terminate', 'shutdown'])
        self.assertIn('cleanup-errors.json', '\n'.join(failed.exception.__notes__))


if __name__ == '__main__':
    unittest.main()
