"""Review regression checks for installed-release network and CLI observations."""

import json
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import installed_release_checks as checks
from release_materials import digest


UNCONNECTED = '\n0.000000\n000\n'
ROUTES = 'Routing tables\n\nInternet:\n127 127.0.0.1 lo0\n\nInternet6:\n::1 ::1 lo0\n'


class NetworkTest(unittest.TestCase):
    def observe(self, replies=None, route=ROUTES):
        replies = replies or {}
        calls = []

        class VM:
            def remote(self, command, **kwargs):
                argv = shlex.split(command)
                calls.append(argv)
                if argv[0] == '/usr/sbin/netstat':
                    if isinstance(route, BaseException):
                        raise route
                    return subprocess.CompletedProcess(argv, 0, route, '')
                result = replies.get(argv[-1])
                if isinstance(result, BaseException):
                    raise result
                if result is None:
                    raise subprocess.CalledProcessError(28, argv, UNCONNECTED, 'curl: (28) Connection timed out')
                return result

        return checks.observe_network(VM()), calls

    def test_direct_ipv4_and_ipv6_probes_require_verified_failures_and_route_capture(self):
        report, commands = self.observe()
        self.assertEqual(report['status'], 'PASS')
        checks.require_offline(report)
        self.assertEqual(report['guestRoutes'], ROUTES)
        for (family, address), command in zip(checks.PUBLIC_ENDPOINTS, commands[:-1], strict=True):
            self.assertEqual(command[:3], ['/usr/bin/curl', '--disable', f'-{family}'])
            self.assertEqual(command[3:5], ['--noproxy', '*'])
            self.assertEqual(command[-2:], [checks.CURL_DETAILS, checks.probe_url(family, address)])
            self.assertEqual(report['probes'][address]['exitCode'], 28)
        self.assertEqual(commands[-1], ['/usr/sbin/netstat', '-rn'])

    def test_partial_tcp_success_and_transport_failure_are_never_offline(self):
        target = 'https://1.1.1.1/'
        cases = (
            (subprocess.CompletedProcess([], 0, '1.1.1.1\n0.0123\n200\n', ''), 'REACHABLE'),
            (subprocess.CompletedProcess([], 0, '1.1.1.1\n0.0123\n200\nunexpected session output\n', ''),
             'REACHABLE'),
            (subprocess.CalledProcessError(28, [], '1.1.1.1\n0.0123\n000\n', 'curl: (28) TLS stalled'),
             'REACHABLE'),
            (subprocess.CalledProcessError(35, [], '\n0.0123\n000\n', 'curl: (35) TLS failed'), 'REACHABLE'),
            (subprocess.CalledProcessError(7, [], '', 'curl: (7) missing timing fields'), 'UNVERIFIED'),
            (subprocess.TimeoutExpired([], 12), 'UNVERIFIED'),
            (ValueError('SSH identity unavailable'), 'UNVERIFIED'),
        )
        for outcome, expected in cases:
            with self.subTest(expected=expected, outcome=outcome):
                report, _ = self.observe({target: outcome})
                self.assertEqual(report['status'], expected)
                with self.assertRaises(ValueError):
                    checks.require_offline({**report, 'status': 'PASS'})

    def test_transport_timeout_preserves_stdout_and_known_reachability(self):
        error = subprocess.TimeoutExpired('ssh', 12, output=b'1.1.1.1\n0.012345\n200\n',
                                         stderr=b'session ended while reading exit status\n')
        report, _ = self.observe({'https://1.1.1.1/': error})
        self.assertEqual(report['status'], 'REACHABLE')
        self.assertEqual(report['probes']['1.1.1.1'], {
            'target': 'https://1.1.1.1/', 'exitCode': None, 'transportError': 'TimeoutExpired',
            'stdout': error.stdout.decode(), 'stderr': error.stderr.decode(),
        })
        with self.assertRaisesRegex(ValueError, 'was reachable'):
            checks.require_offline(report)

    def test_interruption_keeps_partial_probes_and_cannot_pass_offline(self):
        positive = subprocess.CompletedProcess([], 0, '1.1.1.1\n0.012345\n200\n', '')
        for initial, status in ((positive, 'REACHABLE'), (None, 'UNVERIFIED')):
            with self.subTest(status=status):
                report, commands = self.observe({'https://1.1.1.1/': initial,
                                                 'https://8.8.8.8/': KeyboardInterrupt()})
                self.assertEqual((report['status'], report['interrupted']), (status, True))
                self.assertEqual(set(report['probes']), {'1.1.1.1'})
                self.assertIsNone(report['routeObservation'])
                self.assertEqual(len(commands), 2)
                with self.assertRaises(ValueError):
                    checks.require_offline({**report, 'status': 'PASS'})
        report, _ = self.observe(route=KeyboardInterrupt())
        self.assertTrue(report['interrupted'])
        self.assertEqual(len(report['probes']), 4)
        self.assertEqual(report['status'], 'UNVERIFIED')

    def test_offline_validator_requires_both_families_and_a_successful_route_capture(self):
        report, _ = self.observe(route='Routing tables\nInternet:\n')
        self.assertEqual(report['status'], 'UNVERIFIED')
        with self.assertRaises(ValueError):
            checks.require_offline(report)
        report, _ = self.observe()
        del report['probes']['2001:4860:4860::8888']
        with self.assertRaises(ValueError):
            checks.require_offline(report)
        with self.assertRaises(ValueError):
            checks.require_offline(None)

    def test_successful_route_or_blocked_probe_cannot_also_have_a_transport_error(self):
        for target in ('probe', 'route', 'route-diagnostic'):
            report, _ = self.observe()
            if target == 'probe':
                report['probes']['1.1.1.1']['transportError'] = 'TimeoutExpired'
            elif target == 'route':
                report['routeObservation']['transportError'] = 'TimeoutExpired'
            else:
                report['routeObservation']['stderr'] = 'netstat: route table read failed'
            with self.subTest(target=target), self.assertRaisesRegex(ValueError, 'could not be verified'):
                checks.require_offline(report)


class CliGuest:
    root = '/Users/guest/utm-ui-isolation'
    session = root+'/package.ABCDEF01'
    executable = '/Users/guest/Library/Application Support/meshchan-engineering/test/Meshchan/meshctl/bin/meshctl'
    library = executable.removesuffix('/bin/meshctl')+'/lib/libsqlite3.dylib'
    observer = session+'/release-image-probe'

    def __init__(self):
        self.cli_stamp = {'path': self.executable, 'device': 16777231, 'inode': 12, 'sha256': 'a'*64}
        self.library_stamp = {'path': self.library, 'device': 16777231, 'inode': 13, 'sha256': 'b'*64}
        self.files = {self.executable: self.cli_stamp, self.library: self.library_stamp}
        self.mapping = {'observerPid': 81, 'pid': 82, 'exitCode': 0,
                        'mapping': {'address': '0x10a200000', 'device': 16777231, 'inode': 13}}
        self.body = {'schemaVersion': 1, 'command': 'draft', 'action': 'list', 'exitCode': 0,
                     'operationSucceeded': True, 'reason': 'completed', 'committed': None, 'failure': None,
                     'hostCleanup': 'succeeded', 'additionalFailures': [],
                     'storageClose': {'state': 'closed', 'error': None}, 'items': [], 'nextCursor': None}
        self.owned_child = 81
        self.launch_error = None
        self.launched = False
        self.changed_after = None
        self.live_pids = set()
        self.hash_reads = []
        self.absent = []
        self.launch_command = []

    def stamp(self, _, path):
        observed = {key: value for key, value in self.files[str(path)].items() if key != 'sha256'}
        if self.launched and self.changed_after == str(path):
            observed['inode'] += 1
        return observed

    def remote(self, command, **kwargs):
        if command.startswith('set -e\nset -C\n'):
            self.upload = kwargs['stdin'].read()
            return subprocess.CompletedProcess(command, 0)
        if '/bin/ps -axo pid=' in command:
            pid = int(command.partition('-v pid=')[2].partition(' ')[0])
            if pid in self.live_pids:
                raise subprocess.CalledProcessError(1, command)
            self.absent.append(pid)
            return subprocess.CompletedProcess(command, 0)
        argv = shlex.split(command)
        if argv[0] == '/usr/bin/mktemp':
            return subprocess.CompletedProcess(command, 0, self.session+'\n', '')
        if argv[0] == '/usr/bin/codesign':
            return subprocess.CompletedProcess(command, 0)
        if argv[0] == '/usr/bin/shasum':
            self.hash_reads.append(argv[-1])
            return subprocess.CompletedProcess(command, 0, self.files[argv[-1]]['sha256']+'  '+argv[-1]+'\n', '')
        if argv[0] == '/bin/bash':
            self.launch_command = argv
            self.launched = True
            if self.launch_error is not None:
                raise self.launch_error
            return subprocess.CompletedProcess(command, 0)
        if argv[0] == '/bin/cat':
            suffix = argv[-1].removeprefix(self.session+'/cli-mapping')
            values = {'.exit': '0\n', '.pid': str(self.owned_child), '.stdout': json.dumps(self.body),
                      '.stderr': '', '.image.json': json.dumps(self.mapping).encode('utf-8')}
            return subprocess.CompletedProcess(command, 0, values[suffix], '')
        raise AssertionError(f'Unexpected guest command: {command}')


class CliMappingTest(unittest.TestCase):
    def observe(self, vm, scratch):
        def prepare_binary(args, **kwargs):
            if str(args[0]) == '/usr/bin/xcrun':
                binary = Path(args[args.index('-o')+1])
                binary.write_bytes(b'native observer fixture')
            else:
                self.assertEqual(args[:4], ['/usr/bin/codesign', '--force', '--sign', '-'])
                binary = args[-1]
                binary.write_bytes(binary.read_bytes()+b' and local signature')
                vm.files[vm.observer] = {'path': vm.observer, 'device': 17, 'inode': 44, 'sha256': digest(binary)}

        with (patch.object(checks.subprocess, 'run', side_effect=prepare_binary) as command,
              patch.object(checks.files, 'guest_file_stamp', side_effect=vm.stamp)):
            report = checks.observe_cli_mapping(vm, vm.executable, vm.library, scratch=scratch,
                                                cli_stamp=vm.cli_stamp, library_stamp=vm.library_stamp)
        self.assertIn('arm64', command.call_args_list[0].args[0])
        return report

    def test_binds_real_child_observer_and_installed_vnode_without_data_override(self):
        vm = CliGuest()
        with tempfile.TemporaryDirectory() as scratch:
            report = self.observe(vm, scratch)
            attempt = Path(scratch)/report['attemptEvidence']
            stored = json.loads((attempt/'result.json').read_text())
        self.assertEqual(stored, report)
        self.assertEqual(report['status'], 'PASS')
        self.assertEqual(report['argv'], [vm.executable, 'draft', 'list', '--json'])
        self.assertEqual(report['cwd'], vm.session)
        self.assertEqual(report['sqliteMapping']['mapping'], vm.mapping['mapping'])
        self.assertEqual(report['observerSha256'], vm.files[vm.observer]['sha256'])
        self.assertEqual(vm.upload, b'native observer fixture and local signature')
        script = vm.launch_command[2]
        self.assertIn('cd '+shlex.quote(vm.session), script)
        self.assertIn(shlex.quote(vm.library)+' '+shlex.quote(vm.executable)+' draft list --json', script)
        self.assertIn('HOME="$HOME"', script)
        self.assertNotIn('--data-dir', script)
        self.assertEqual(vm.absent, [81, 82])
        self.assertEqual(vm.hash_reads, list(vm.files)*2)

    def test_wrong_mapping_unreleased_storage_or_changed_files_fail_closed(self):
        cases = (
            ('SQLite vnode', lambda vm: vm.mapping['mapping'].update(inode=35)),
            ('observerPid', lambda vm: vm.mapping.update(observerPid=90)),
            ('storage close', lambda vm: vm.body['storageClose'].update(state='failed')),
            ('draft list row', lambda vm: vm.body.update(items=[None])),
            ('draft list cursor', lambda vm: vm.body.update(nextCursor='wrong')),
            ('file identity changed', lambda vm: setattr(vm, 'changed_after', vm.library)),
            ('file identity changed', lambda vm: setattr(vm, 'changed_after', vm.executable)),
        )
        for message, mutate in cases:
            vm = CliGuest()
            mutate(vm)
            with self.subTest(message=message), tempfile.TemporaryDirectory() as scratch:
                with self.assertRaisesRegex(ValueError, message):
                    self.observe(vm, scratch)

    def test_rejects_a_library_outside_the_installed_cli_before_launch(self):
        vm = CliGuest()
        with tempfile.TemporaryDirectory() as scratch, self.assertRaisesRegex(ValueError, 'bundled SQLite'):
            checks.observe_cli_mapping(vm, vm.executable, '/tmp/libsqlite3.dylib', scratch=scratch,
                                       cli_stamp=vm.cli_stamp, library_stamp=vm.library_stamp)
        self.assertFalse(vm.launched)

    def test_both_observer_and_cli_must_be_absent_after_the_reported_exit(self):
        for pid in (81, 82):
            vm = CliGuest()
            vm.live_pids.add(pid)
            with self.subTest(pid=pid), tempfile.TemporaryDirectory() as scratch:
                with self.assertRaises(subprocess.CalledProcessError):
                    self.observe(vm, scratch)

    def test_interrupted_or_failed_observer_keeps_the_exact_guest_log_location(self):
        failures = (
            (KeyboardInterrupt(), 'INTERRUPTED'),
            (subprocess.TimeoutExpired('ssh', 30), 'FAIL'),
            (subprocess.CalledProcessError(124, 'ssh'), 'FAIL'),
        )
        for error, status in failures:
            vm = CliGuest()
            vm.launch_error = error
            with self.subTest(error=error), tempfile.TemporaryDirectory() as scratch:
                with self.assertRaises(type(error)):
                    self.observe(vm, scratch)
                attempt, = Path(scratch).glob('cli-mapping-attempt-package.*')
                started = json.loads((attempt/'started.json').read_text())
                failure = json.loads((attempt/'result.json').read_text())
                self.assertEqual(started['guestLogPrefix'], vm.session+'/cli-mapping')
                self.assertEqual(started['argv'], [vm.executable, 'draft', 'list', '--json'])
                self.assertEqual(failure['guestSession'], vm.session)
                self.assertEqual(failure['status'], status)
                self.assertEqual(failure['errorType'], type(error).__name__)
                if isinstance(error, subprocess.CalledProcessError):
                    self.assertEqual(failure['commandExitCode'], 124)

    def test_saved_mapping_rebinds_attempt_raw_vnode_and_frozen_cli(self):
        vm = CliGuest()
        arguments = {'expected_cli': vm.executable, 'expected_library': vm.library,
                     'cli_sha': vm.cli_stamp['sha256'], 'library_sha': vm.library_stamp['sha256'],
                     'guest_root': vm.root}
        with tempfile.TemporaryDirectory() as scratch:
            report = self.observe(vm, scratch)
            checks.verify_cli_mapping_receipt(scratch, report, **arguments)
            with self.assertRaisesRegex(ValueError, 'owned guest session'):
                checks.verify_cli_mapping_receipt(scratch, {'status': 'PASS'}, **arguments)
            with self.assertRaisesRegex(ValueError, 'CLI image observation argv'):
                checks.verify_cli_mapping_receipt(scratch, report, **{**arguments, 'expected_cli': '/wrong/meshctl'})
            with self.assertRaisesRegex(ValueError, 'original attempt result'):
                checks.verify_cli_mapping_receipt(scratch, {**report, 'rawObservation': '{}'}, **arguments)
            attempt = Path(scratch)/report['attemptEvidence']/'result.json'
            wrong = {**report, 'libraryFile': {**report['libraryFile'], 'inode': 99}}
            attempt.write_text(json.dumps(wrong))
            with self.assertRaisesRegex(ValueError, 'SQLite vnode'):
                checks.verify_cli_mapping_receipt(scratch, wrong, **arguments)
            wrong = {**report, 'stdout': {**report['stdout'], 'items': [None]}}
            attempt.write_text(json.dumps(wrong))
            with self.assertRaisesRegex(ValueError, 'draft list row'):
                checks.verify_cli_mapping_receipt(scratch, wrong, **arguments)


if __name__ == '__main__':
    unittest.main()
