"""Offline regression tests for finite RF plan validation and accounting."""
import copy
import contextlib
import hashlib
import io
import json
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import DEFAULT, Mock, patch

import run_openhop_acceptance as acceptance


class AcceptancePlanTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='meshchan-plan-test-')
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.root = Path(__file__).resolve().parents[1]
        data = {
            'sameChannelKeyConfirmed': True, 'radioCompatibleConfirmed': True,
            'clientSlotsAvailable': True, 'sharedQueueConsumptionAccepted': True,
            'aSendChannel': 1, 'aReceiveChannel': 1, 'bSendChannel': 3, 'bReceiveChannel': 3,
            'aPort': '/dev/synthetic-never-opened', 'baseUrl': 'http://127.0.0.1:1/',
            'companionName': 'synthetic', 'endpointLabel': 'synthetic',
            'jwt': {'env': 'SYNTHETIC_NEVER_READ'}, 'idleTimeoutSeconds': 120,
            'session': {'commandSeconds': 5, 'initializationSeconds': 15,
                        'startupDelayMilliseconds': 0, 'taskSeconds': 90},
        }
        source = self.folder / 'input.json'
        source.write_text(json.dumps(data))
        output = self.folder / 'generated'
        subprocess.run([sys.executable, str(self.root / 'tool/prepare_openhop_acceptance.py'),
                        '--input', str(source), '--output', str(output),
                        '--candidate', str(self.folder / 'candidate')], check=True, capture_output=True, text=True)
        self.plan = json.loads((output / 'plan.json').read_text())

    def case(self, case_id):
        return next(c for c in self.plan['cases'] if c['id'] == case_id)

    def change_b(self, case_id, change):
        path = Path(self.case(case_id)['bArgv'][4])
        config = json.loads(path.read_text())
        change(config)
        path.write_text(json.dumps(config))

    def test_generated_product_commands_use_isolated_absolute_business_directories(self):
        directories = []
        for case in self.plan['cases']:
            argv = case['aArgv']
            if case['id'] == 'H0':
                self.assertEqual(argv[1], 'info')
                continue
            self.assertTrue(argv[1].startswith('--data-dir='))
            directory = Path(argv[1].split('=', 1)[1])
            self.assertTrue(directory.is_absolute())
            self.assertTrue(directory.is_relative_to(self.folder / 'generated' / 'cli-data'))
            self.assertFalse(directory.exists())
            directories.append(directory)
        self.assertEqual(len(set(directories)), 7)
        acceptance.validate_plan(self.plan)

    def test_retained_legacy_product_arguments_remain_readable(self):
        for case in self.plan['cases']:
            case['aArgv'] = [v for v in case['aArgv'] if not v.startswith('--data-dir=')]
        acceptance.validate_plan(self.plan)

    def test_invalid_business_directory_is_rejected_before_execution(self):
        for directory in ('', ' ', 'relative', '/tmp/bad\0path'):
            with self.subTest(directory=directory):
                self.case('H2')['aArgv'][1] = '--data-dir=' + directory
                with self.assertRaises(ValueError):
                    acceptance.validate_plan(self.plan, 'H2')

    def test_generated_matrix_and_b15_followups_have_derived_limits(self):
        cases, limits = acceptance.validate_plan(self.plan)
        self.assertEqual([c['id'] for c in cases], list(acceptance._CASE_OPERATIONS))
        self.assertEqual(sum(sum(s.values()) for s in limits.values()), 12)
        self.assertEqual(limits['H7'], {'A': 2, 'B': 1})
        for case_id in ('H2', 'H7'):
            self.change_b(case_id, lambda cfg: cfg['session'].update(commandSeconds=15))
            _, selected = acceptance.validate_plan(self.plan, case_id)
            self.assertEqual(list(selected), [case_id])
            self.assertEqual(selected[case_id], limits[case_id])

    def test_content_counts_follow_the_actual_a_or_b_initiator(self):
        original = copy.deepcopy(self.plan)
        for case_id in acceptance._CASE_OPERATIONS:
            with self.subTest(case_id=case_id):
                self.plan = copy.deepcopy(original)
                case = self.case(case_id)
                a_operation, _ = acceptance._CASE_OPERATIONS[case_id]
                path = None
                if a_operation in ('send', 'ping'):
                    arguments = case['aArgv']
                else:
                    path = Path(case['bArgv'][4])
                    saved = path.read_bytes()
                    config = json.loads(saved)
                    arguments = config['datagramArguments']
                option = '--payload-hex=' if case_id in ('H1', 'H2') else '--content-hex='
                index = next(i for i, value in enumerate(arguments) if value.startswith(option))
                arguments[index] = option + '00'
                if path is not None:
                    path.write_text(json.dumps(config))
                try:
                    with self.assertRaises(ValueError):
                        acceptance.validate_plan(self.plan)
                finally:
                    if path is not None:
                        path.write_bytes(saved)

    def test_h5_cannot_shrink_the_boundary_by_editing_both_count_and_content(self):
        case = self.case('H5')
        case['contentBytes'] = 1
        case['aArgv'] = ['--content-hex=00' if value.startswith('--content-hex=') else value
                         for value in case['aArgv']]
        with self.assertRaises(ValueError):
            acceptance.validate_plan(self.plan)

    def test_h4_cannot_replace_the_empty_boundary_with_one_byte(self):
        self.case('H4')['contentBytes'] = 1
        self.change_b('H4', lambda cfg: cfg.update(datagramArguments=[
            '--content-hex=00' if arg == '--content-hex=' else arg
            for arg in cfg['datagramArguments']]))
        with self.assertRaises(ValueError):
            acceptance.validate_plan(self.plan)

    def test_h4_evaluation_requires_the_empty_content_boundary(self):
        send = {key: True for key in ('attempted', 'localWriteCompleted', 'localOkObserved', 'deviceAcceptanceConfirmed')}
        a = {'actualExitCode': 0, 'final': {'cleanup': {'state': 'succeeded'},
             'result': {'responseAttempts': 1, 'localResponsesConfirmed': 1, 'lastSend': send}}}
        b = {'actualExitCode': 0, 'final': {'cleanup': {'state': 'succeeded'},
             'result': {'send': send, 'roundTripSucceeded': True, 'matchingPongObserved': True,
                        'exactContentValidated': True, 'applicationRttUs': 1}}}
        self.assertTrue(acceptance.evaluate('H4', a, b, content_bytes=0))
        self.assertFalse(acceptance.evaluate('H4', a, b, content_bytes=1))

    def test_text_counts_utf8_bytes_and_hex_syntax_is_exact(self):
        case = self.case('H2')
        case['contentBytes'] = 6
        self.change_b('H2', lambda cfg: cfg.update(datagramArguments=[
            value for value in cfg['datagramArguments'] if not value.startswith('--payload-hex=')
        ] + ['--text=é💡']))
        cases, _ = acceptance.validate_plan(self.plan, 'H2')
        self.assertEqual(cases[0]['validatedContentBytes'], 6)
        case['contentBytes'] = 2
        with self.assertRaises(ValueError):
            acceptance.validate_plan(self.plan, 'H2')
        case['contentBytes'] = 1
        for value in ('0', '00 11', '0x00'):
            with self.subTest(value=value):
                self.change_b('H2', lambda cfg: cfg.update(datagramArguments=[
                    arg for arg in cfg['datagramArguments']
                    if not arg.startswith(('--text=', '--payload-hex='))
                ] + ['--payload-hex=' + value]))
                with self.assertRaises(ValueError):
                    acceptance.validate_plan(self.plan, 'H2')

    def test_oversized_or_implicit_a_responder_limits_reject_before_execution(self):
        original = copy.deepcopy(self.plan)
        for replacement in ('--max-responses=99', None, '--max-responses=1'):
            with self.subTest(replacement=replacement):
                self.plan = copy.deepcopy(original)
                args = self.case('H7')['aArgv']
                args.remove('--max-responses=2')
                if replacement is not None:
                    args.append(replacement)
                with self.assertRaises(ValueError):
                    acceptance.validate_plan(self.plan, 'H7')
        # Exercise the CLI --execute gate with a missing executable as a sentinel:
        # invalid arguments must be rejected before creating output or spawning it.
        self.plan = copy.deepcopy(original)
        self.case('H7')['aArgv'].append('--max-responses=99')
        path = self.folder / 'invalid.json'
        path.write_text(json.dumps(self.plan))
        destination = self.folder / 'must-not-exist'
        run = subprocess.run([sys.executable, str(self.root / 'tool/run_openhop_acceptance.py'),
                              '--plan', str(path), '--output', str(destination),
                              '--only-case', 'H7', '--execute'], capture_output=True, text=True)
        self.assertEqual(run.returncode, 2)
        self.assertFalse(destination.exists())
        self.assertNotIn('Traceback', run.stderr)

    def test_b_responder_limit_is_read_from_the_actual_config(self):
        self.change_b('H3', lambda cfg: cfg.update(datagramArguments=[
            '--max-responses=99' if arg == '--max-responses=1' else arg
            for arg in cfg['datagramArguments']]))
        with self.assertRaises(ValueError):
            acceptance.validate_plan(self.plan)

    def test_missing_evaluation_metadata_rejects_before_any_process(self):
        original = copy.deepcopy(self.plan)
        for field in ('contentBytes', 'expectedAExit', 'expectedBExit'):
            for execute in (False, True):
                with self.subTest(field=field, execute=execute):
                    self.plan = copy.deepcopy(original)
                    self.case('H2').pop(field)
                    plan = self.folder / 'missing-metadata.json'
                    plan.write_text(json.dumps(self.plan))
                    output = self.folder / ('must-not-exist-' + field + str(execute))
                    argv = ['driver', '--plan', str(plan), '--output', str(output), '--only-case', 'H2']
                    if execute:
                        argv.append('--execute')
                    with patch.object(sys, 'argv', argv), patch.object(acceptance, 'Run') as run, \
                            contextlib.redirect_stderr(io.StringIO()):
                        with self.assertRaises(SystemExit) as caught:
                            acceptance.main()
                    self.assertEqual(caught.exception.code, 2)
                    run.assert_not_called()
                    self.assertFalse(output.exists())

    def test_invalid_evaluation_metadata_types_and_exits_reject(self):
        original = copy.deepcopy(self.plan)
        for field, value in [('contentBytes', True), ('contentBytes', -1), ('contentBytes', 166),
                             ('contentBytes', 15.0), ('contentBytes', '15'), ('contentBytes', None),
                             ('expectedAExit', False), ('expectedAExit', 69),
                             ('expectedBExit', False), ('expectedBExit', None)]:
            with self.subTest(field=field, value=value):
                self.plan = copy.deepcopy(original)
                self.case('H2')[field] = value
                with self.assertRaises(ValueError):
                    acceptance.validate_plan(self.plan, 'H2')

    def test_roles_and_unexpected_b_responder_cannot_change_send_allocation(self):
        original = copy.deepcopy(self.plan)
        for side in ('aArgv', 'bArgv'):
            with self.subTest(side=side):
                self.plan = copy.deepcopy(original)
                args = self.case('H2')[side]
                args[2 if side == 'aArgv' else 5] = 'respond'
                with self.assertRaises(ValueError):
                    acceptance.validate_plan(self.plan, 'H2')
        self.plan = copy.deepcopy(original)
        self.case('H6')['bArgv'] = copy.deepcopy(self.case('H7')['bArgv'])
        with self.assertRaises(ValueError):
            acceptance.validate_plan(self.plan)

    def test_duplicate_limits_and_non_direct_routes_reject(self):
        self.case('H7')['aArgv'].append('--max-responses=2')
        with self.assertRaises(ValueError):
            acceptance.validate_plan(self.plan, 'H7')
        self.plan = copy.deepcopy(self.plan)
        self.case('H7')['aArgv'].pop()
        self.change_b('H7', lambda cfg: cfg.update(datagramArguments=[
            '--path-hex=01' if arg == '--path-hex=' else arg
            for arg in cfg['datagramArguments']]))
        with self.assertRaises(ValueError):
            acceptance.validate_plan(self.plan, 'H7')

    def test_legacy_read_failure_is_not_an_application_send(self):
        record = {'final': {'operation': 'listen', 'result': {
            'send': {'attempted': True, 'dispatched': True, 'localWriteCompleted': True}}}}
        self.assertEqual(acceptance.send_attempts(record), 0)
        record['final']['operation'] = 'send'
        self.assertEqual(acceptance.send_attempts(record), 1)
        record['final'] = {'operation': 'respond', 'result': {'responseAttempts': 2}}
        self.assertEqual(acceptance.send_attempts(record), 2)

    def test_decimal_and_hex_receive_channels_are_parsed_before_execution(self):
        original = copy.deepcopy(self.plan)
        for value, expected in [('01', 1), ('0001', 1), ('0x01', 1), ('0XFF', 255)]:
            with self.subTest(value=value):
                self.plan = copy.deepcopy(original)
                args = self.case('H2')['aArgv']
                args[args.index('--receive-channel=1')] = '--receive-channel=' + value
                cases, _ = acceptance.validate_plan(self.plan, 'H2')
                self.assertEqual(cases[0]['validatedAReceiveChannel'], expected)

    def test_invalid_receive_channels_reject_before_execution(self):
        original = copy.deepcopy(self.plan)
        for value in ('256', '-1', '0o1', '0b1', '1 ', ''):
            with self.subTest(value=value):
                self.plan = copy.deepcopy(original)
                args = self.case('H2')['aArgv']
                args[args.index('--receive-channel=1')] = '--receive-channel=' + value
                with self.assertRaises(ValueError):
                    acceptance.validate_plan(self.plan, 'H2')

    @staticmethod
    def probe_report():
        # The flat object emitted by openhop_idle_probe.dart, without a wrapper.
        return {'schemaVersion': 1, 'tool': 'openhop_idle_probe', 'status': 'PASS',
                'exitCode': 0, 'initializationCompleted': True,
                'requestedObservationMilliseconds': 95000, 'observedReadyMilliseconds': 95008,
                'verifiedIdleWindowLowerBoundSeconds': 95,
                'effectiveConfiguredIdleTimeoutSeconds': None, 'reason': 'duration',
                'cleanup': 'succeeded', 'failure': None, 'hostCommandOpcodes': [22, 1],
                'noHostCommandsDuringObservation': True, 'applicationDatagramsSent': 0,
                'queueReadCommandsSent': 0}

    def generate_from_probe(self, proof, output_name):
        evidence = self.folder / (output_name + '-probe.json')
        evidence.write_text(json.dumps(proof))
        data = json.loads((self.folder / 'input.json').read_text())
        data.pop('idleTimeoutSeconds')
        data.update(idleWindowLowerBoundSeconds=95, idleWindowEvidence=str(evidence))
        source = self.folder / (output_name + '-input.json')
        source.write_text(json.dumps(data))
        output = self.folder / output_name
        run = subprocess.run([sys.executable, str(self.root / 'tool/prepare_openhop_acceptance.py'),
                              '--input', str(source), '--output', str(output),
                              '--candidate', str(self.folder / 'candidate')], capture_output=True, text=True)
        return run, output

    def test_plan_generation_accepts_flat_probe_and_legacy_execution_wrapper(self):
        report = self.probe_report()
        for name, proof in [('flat', report), ('wrapped', {'actualExitCode': 0, 'report': report})]:
            with self.subTest(name=name):
                run, output = self.generate_from_probe(proof, name)
                self.assertEqual(run.returncode, 0, run.stderr)
                config = json.loads((output / 'H3-b.json').read_text())
                self.assertIsNone(config['idleTimeoutSeconds'])
                self.assertEqual(config['idleWindowLowerBoundSeconds'], 95)

    def test_failed_or_nonpassive_probe_rejects_before_creating_plan(self):
        for field, value in [('exitCode', 69), ('status', 'FAIL'), ('cleanup', 'pending'),
                             ('noHostCommandsDuringObservation', False),
                             ('verifiedIdleWindowLowerBoundSeconds', 94),
                             ('initializationCompleted', False), ('applicationDatagramsSent', 1),
                             ('queueReadCommandsSent', 1), ('verifiedIdleWindowLowerBoundSeconds', '95')]:
            with self.subTest(field=field):
                report = self.probe_report()
                report[field] = value
                run, output = self.generate_from_probe(report, 'invalid-' + field)
                self.assertEqual(run.returncode, 2)
                self.assertFalse(output.exists())
                self.assertNotIn('Traceback', run.stderr)
        run, output = self.generate_from_probe({'actualExitCode': 69, 'report': self.probe_report()}, 'wrapper-failed')
        self.assertEqual(run.returncode, 2)
        self.assertFalse(output.exists())


class DriverSettlementTest(unittest.TestCase):
    def setUp(self):
        self.fixture = AcceptancePlanTest('test_legacy_read_failure_is_not_an_application_send')
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.folder = self.fixture.folder
        self.hashes = {}
        for name in ('bin/meshctl', 'lib/liblibserialport_plus.dylib'):
            path = self.folder / 'candidate' / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(('synthetic ' + name).encode())
            self.hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()

    def drive_failure(self, mode):
        created = []
        class Process:
            def __init__(self, pid):
                self.pid, self.returncode = pid, None
            def poll(self):
                return self.returncode
        class FakeRun:
            def __init__(run, folder, label, argv, expected, env):
                run.label, run.argv, run.expected = label, argv, expected
                run.started = acceptance.utc()
                run.process = Process(900000 + len(created))
                run.wait_calls, run.record = 0, None
                created.append(run)
            def guarded_window(run):
                return True
            def snapshot(run):
                if run.record is not None:
                    return run.record
                is_a = run.label.startswith('A-')
                final = None if mode != 'failed' and not is_a else {
                    'operation': 'respond' if is_a else 'ping',
                    'cleanup': {'state': 'succeeded' if is_a else 'failed'},
                    'result': {'responseAttempts': 1} if is_a else {'send': {'attempted': True}},
                }
                record = {'label': run.label, 'argv': run.argv, 'pid': run.process.pid,
                          'startedUtc': run.started, 'endedUtc': None if run.process.poll() is None else acceptance.utc(),
                          'actualExitCode': run.process.poll(), 'final': final, 'events': [],
                          'cleanup': {'state': 'pending' if final is None else final['cleanup']['state']}}
                if run.process.poll() is not None:
                    run.record = record
                return record
            def wait(run):
                run.wait_calls += 1
                if run.label.startswith('A-'):
                    run.process.returncode = 0
                    return run.snapshot()
                if mode == 'failed':
                    run.process.returncode = 69
                if mode == 'error':
                    raise RuntimeError('PRIVATE_EXCEPTION_BODY')
                raise acceptance.PendingCleanup('Synthetic B cleanup not confirmed')
        plan_path = self.folder / 'execution-input.json'
        plan_path.write_text(json.dumps(self.fixture.plan))
        output = self.folder / 'H7-followup-results'
        original_read = Path.read_text
        baseline = self.fixture.root / 'build/phase-1b9/20261110T193252Z/hardware/execution-plan.json'
        def read(path, *args, **kwargs):
            if path == baseline:
                return json.dumps({'nativeHashes': self.hashes})
            return original_read(path, *args, **kwargs)
        with patch.object(Path, 'read_text', read), patch.object(acceptance, 'Run', FakeRun), \
                patch.object(sys, 'argv', ['driver', '--plan', str(plan_path), '--output', str(output), '--only-case', 'H7', '--execute']), \
                contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit) as caught:
                acceptance.main()
        self.assertEqual(caught.exception.code, 69)
        self.assertEqual([r.label for r in created], ['A-1', 'B-1'])
        self.assertGreater(created[0].wait_calls, 0)
        self.assertEqual(created[0].process.poll(), 0)
        self.assertNotIn('PRIVATE_EXCEPTION_BODY', (output / 'results.json').read_text())
        return json.loads((output / 'results.json').read_text()), json.loads((output / 'STOPPED.json').read_text())

    def test_failed_cleanup_settles_peer_and_retains_known_sends(self):
        result, stopped = self.drive_failure('failed')
        case = result['cases'][0]
        self.assertEqual(case['status'], 'FAIL')
        self.assertEqual(case['applicationSendAttempts'], 2)
        self.assertEqual(len(case['allInvocations']), 2)
        self.assertEqual(case['allInvocations'][1]['final']['cleanup']['state'], 'failed')
        self.assertEqual(stopped['activePids'], [])
        self.assertFalse(stopped['forcedTermination'])

    def test_pending_sender_keeps_unknown_count_and_reserved_budget(self):
        result, stopped = self.drive_failure('pending')
        case = result['cases'][0]
        self.assertEqual(case['status'], 'BLOCKED')
        self.assertIsNone(result['actualApplicationSendAttempts'])
        self.assertEqual(case['knownApplicationSendAttempts'], 1)
        self.assertEqual(case['applicationSendAttemptUpperBound'], 2)
        self.assertEqual(len(stopped['activePids']), 1)

    def test_unexpected_orchestration_error_also_settles_peer(self):
        result, _ = self.drive_failure('error')
        self.assertEqual(result['cases'][0]['orchestrationFailure'], 'RuntimeError')
        self.assertIsNone(result['actualApplicationSendAttempts'])

    def test_wait_preserves_pending_snapshot_and_rejects_cached_cleanup_failure(self):
        process = Mock(pid=900001)
        process.poll.return_value = None
        process.wait.side_effect = subprocess.TimeoutExpired('synthetic', 150)
        with patch.object(acceptance.subprocess, 'Popen', return_value=process):
            run = acceptance.Run(self.folder, 'B-1', ['synthetic'], 0, {})
        with self.assertRaises(acceptance.PendingCleanup):
            run.wait()
        pending = json.loads(run.metadata.read_text())
        self.assertIsNone(pending['actualExitCode'])
        self.assertIsNone(pending['endedUtc'])
        self.assertEqual(pending['cleanup']['state'], 'pending')
        process.poll.return_value = 69
        process.wait.side_effect = None
        run.stdout.write_text(json.dumps({'exitCode': 69, 'cleanup': {'state': 'failed'},
                                         'result': {'send': {'attempted': True}}}) + '\n')
        for _ in range(2):
            with self.assertRaises(acceptance.PendingCleanup):
                run.wait()
        self.assertTrue(run.record['final']['result']['send']['attempted'])

    def test_post_spawn_metadata_failure_keeps_the_process_owned(self):
        process = Mock(pid=900002)
        with patch.object(acceptance.subprocess, 'Popen', return_value=process), \
                patch.object(Path, 'write_text', side_effect=[0, OSError('synthetic metadata failure')]):
            run = acceptance.Run(self.folder, 'A-1', ['synthetic'], 0, {})
        self.assertIs(run.process, process)
        self.assertTrue(run.startup_observation_failure)

    def drive_completed_h2(self, evaluation_failure=None, failed_case=False,
                           settlement_interrupt=None, continue_cases=False):
        created = []
        class FakeRun:
            def __init__(run, folder, label, argv, expected, env):
                run.label, run.argv, run.started = label, argv, acceptance.utc()
                run.case_id = folder.name
                run.wait_calls = 0
                run.record = None
                run.process = Mock(pid=900001 + len(created))
                run.process.poll.return_value = None
                created.append(run)
            def guarded_window(run):
                return True
            def wait(run):
                run.wait_calls += 1
                if settlement_interrupt and run.label == 'A-1' and run.wait_calls == 1:
                    if settlement_interrupt == 'exception':
                        raise KeyboardInterrupt
                    signal.raise_signal(signal.SIGINT)
                    signal.raise_signal(signal.SIGINT)
                if run.record is not None:
                    return run.record
                run.process.poll.return_value = 0
                is_a = run.label.startswith('A-')
                operation = acceptance._CASE_OPERATIONS[run.case_id][0 if is_a else 1]
                result = ({} if operation == 'listen' else {'responseAttempts': 1}
                          if operation == 'respond' else {'send': {k: True for k in
                              ('attempted', 'localWriteCompleted', 'localOkObserved', 'deviceAcceptanceConfirmed')}})
                run.record = {'label': run.label, 'argv': run.argv, 'pid': run.process.pid,
                    'startedUtc': run.started, 'endedUtc': acceptance.utc(), 'actualExitCode': 0,
                    'final': {'operation': operation, 'cleanup': {'state': 'succeeded'}, 'result': result},
                    'events': [{'event': 'datagram', 'channelIndex': 1, 'dataType': 65535, 'payloadLength': 15}] if is_a else []}
                return run.record
        plan = self.folder / 'leading-zero-plan.json'
        plan.write_text(json.dumps(self.fixture.plan))
        output = self.folder / 'leading-zero-results'
        original_read = Path.read_text
        baseline = self.fixture.root / 'build/phase-1b9/20261110T193252Z/hardware/execution-plan.json'
        def read(path, *args, **kwargs):
            return json.dumps({'nativeHashes': self.hashes}) if path == baseline else original_read(path, *args, **kwargs)
        validate = acceptance.validate_plan
        def selected_cases(*args):
            cases, limits = validate(*args)
            if continue_cases:
                cases = [case for case in cases if case['id'] in ('H2', 'H4')]
                limits = {case['id']: limits[case['id']] for case in cases}
            return cases, limits
        argv = ['driver', '--plan', str(plan), '--output', str(output), '--execute']
        if not continue_cases:
            argv.extend(['--only-case', 'H2'])
        with patch.object(Path, 'read_text', read), patch.object(acceptance, 'Run', FakeRun), \
                patch.object(acceptance, 'validate_plan', side_effect=selected_cases), \
                patch.object(acceptance, 'evaluate', wraps=acceptance.evaluate,
                             side_effect=[False, True] if continue_cases else evaluation_failure,
                             return_value=False if failed_case else DEFAULT), \
                patch.object(sys, 'argv', argv), \
                contextlib.redirect_stdout(io.StringIO()):
            if evaluation_failure is None and not failed_case and not settlement_interrupt and not continue_cases:
                acceptance.main()
            else:
                try:
                    with self.assertRaises(SystemExit) as caught:
                        acceptance.main()
                except KeyboardInterrupt:
                    self.fail('KeyboardInterrupt escaped before settlement/accounting persisted.')
                self.assertEqual(caught.exception.code, 130 if settlement_interrupt else 69)
        result = json.loads((output / 'results.json').read_text())
        return result, output, created

    def test_leading_zero_channel_saves_successful_case_and_send_count(self):
        case = self.fixture.case('H2')
        case['aArgv'][case['aArgv'].index('--receive-channel=1')] = '--receive-channel=01'
        result, _, created = self.drive_completed_h2()
        self.assertEqual(result['cases'][0]['status'], 'PASS')
        self.assertEqual(result['actualApplicationSendAttempts'], 1)
        self.assertEqual(len(created), 2)

    def test_evaluation_failure_preserves_completed_send_and_both_invocations(self):
        result, output, created = self.drive_completed_h2(RuntimeError('PRIVATE_EXCEPTION_BODY'))
        case = result['cases'][0]
        self.assertEqual(case['status'], 'FAIL')
        self.assertEqual(case['evaluationFailure'], 'RuntimeError')
        self.assertIsNone(case['orchestrationFailure'])
        self.assertEqual(result['actualApplicationSendAttempts'], 1)
        self.assertEqual(case['knownApplicationSendAttempts'], 1)
        self.assertEqual(case['applicationSendAttemptUpperBound'], 1)
        self.assertEqual(len(case['allInvocations']), 2)
        self.assertTrue(all(r['actualExitCode'] == 0 for r in case['allInvocations']))
        self.assertEqual([r.label for r in created], ['A-1', 'B-1'])
        stopped = json.loads((output / 'STOPPED.json').read_text())
        self.assertEqual(stopped['evaluationFailure'], 'RuntimeError')
        self.assertEqual(stopped['applicationSendAttempts'], 1)
        self.assertEqual(stopped['activePids'], [])
        self.assertNotIn('PRIVATE_EXCEPTION_BODY', (output / 'results.json').read_text())
        self.assertNotIn('PRIVATE_EXCEPTION_BODY', (output / 'STOPPED.json').read_text())

    def test_interrupt_during_settlement_preserves_every_peer_and_cancellation(self):
        for mode in ('exception', 'signal'):
            with self.subTest(mode=mode):
                previous = signal.getsignal(signal.SIGINT)
                result, output, created = self.drive_completed_h2(settlement_interrupt=mode)
                self.assertIs(signal.getsignal(signal.SIGINT), previous)
                case = result['cases'][0]
                self.assertEqual(case['status'], 'FAIL')
                self.assertEqual(case['orchestrationFailure'], 'KeyboardInterrupt')
                self.assertFalse(case['cleanupIncomplete'])
                self.assertEqual(case['applicationSendAttempts'], 1)
                self.assertEqual(len(case['allInvocations']), 2)
                self.assertTrue(all(run.process.poll() == 0 for run in created))
                self.assertGreaterEqual(created[0].wait_calls, 2 if mode == 'exception' else 1)
                stopped = json.loads((output / 'STOPPED.json').read_text())
                self.assertEqual(stopped['activePids'], [])
                self.assertFalse(stopped['forcedTermination'])
                self.assertEqual(stopped['applicationSendAttempts'], 1)
                # Each mode has its own complete fixture output; retain both
                # before executing the next subcase with the same helper.
                output.rename(output.with_name('interrupt-' + mode))

    def test_failed_selected_case_returns_nonzero_after_clean_settlement(self):
        result, output, _ = self.drive_completed_h2(failed_case=True)
        self.assertEqual(result['cases'][0]['status'], 'FAIL')
        self.assertEqual(result['actualApplicationSendAttempts'], 1)
        self.assertFalse((output / 'STOPPED.json').exists())

    def test_a_later_pass_does_not_erase_an_earlier_case_failure_exit(self):
        result, output, created = self.drive_completed_h2(continue_cases=True)
        self.assertEqual([case['status'] for case in result['cases']], ['FAIL', 'PASS'])
        self.assertEqual([run.case_id for run in created], ['H2', 'H2', 'H4', 'H4'])
        self.assertEqual(result['actualApplicationSendAttempts'], 3)
        self.assertFalse((output / 'STOPPED.json').exists())


if __name__ == '__main__':
    unittest.main()
