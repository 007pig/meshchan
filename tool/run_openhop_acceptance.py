#!/usr/bin/env python3
"""Run the explicitly authorized finite Direct matrix; default is validation only."""
import argparse
from contextlib import contextmanager
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def cleanup(record):
    value = (record.get('final') or {}).get('cleanup')
    return value.get('state') if isinstance(value, dict) else value


def send_attempts(record):
    final = record.get('final') or {}
    # Read-only operations cannot become RF sends because an older helper
    # projected a consuming-read failure under a misleading "send" key.
    if final.get('operation') in ('info', 'listen'):
        return 0
    result = final.get('result') or {}
    if 'responseAttempts' in result:
        return result['responseAttempts']
    return int((result.get('send') or {}).get('attempted') is True)


def initialization_failure(record):
    final = record.get('final') or {}
    failure = final.get('failure') or {}
    session = failure.get('session') or {}
    result = final.get('result') or {}
    return (record.get('actualExitCode') == 69 and cleanup(record) == 'succeeded'
            and not send_attempts(record)
            and not result.get('processedEntries', 0)
            and session.get('stage') in ('opening', 'initializing')
            and session.get('commandOpcode') in (None, 0x16, 1))


def local_acceptance(record):
    result = (record.get('final') or {}).get('result') or {}
    send = result.get('send') or result.get('lastSend') or {}
    return all(send.get(k) is True for k in
               ('localWriteCompleted', 'localOkObserved', 'deviceAcceptanceConfirmed'))


def exact_pong(record):
    result = (record.get('final') or {}).get('result') or {}
    return (record.get('actualExitCode') == 0 and cleanup(record) == 'succeeded'
            and result.get('roundTripSucceeded') is True
            and result.get('matchingPongObserved') is True
            and result.get('exactContentValidated') is True
            and type(result.get('applicationRttUs')) is int
            and local_acceptance(record))


_CASE_OPERATIONS = {
    'H1': ('send', 'listen'), 'H2': ('listen', 'send'),
    'H3': ('ping', 'respond'), 'H4': ('respond', 'ping'),
    'H5': ('ping', 'respond'), 'H6': ('ping', None),
    'H7': ('respond', 'ping'),
}
_CASE_LIMITS = {'H1': 1, 'H2': 1, 'H3': 2, 'H4': 2, 'H5': 2, 'H6': 1, 'H7': 3}


def case_send_limits(case_id):
    return {side: 0 if operation in (None, 'listen') else
            2 if case_id == 'H7' and side == 'A' else 1
            for side, operation in zip(('A', 'B'), _CASE_OPERATIONS[case_id])}


def validate_content_length(case_id, operation, arguments, reported):
    """Bind byte-count evidence to exactly one actual initiating content option."""
    values = dict(argument[2:].split('=', 1) for argument in arguments if '=' in argument)
    name = 'payload-hex' if operation == 'send' else 'content-hex'
    if (name in values) == ('text' in values):
        raise ValueError('Require exactly one actual content source.')
    if name in values:
        value = values[name]
        if not re.fullmatch(r'(?:[0-9a-fA-F]{2})*', value):
            raise ValueError('Content must use exact even-length ASCII hex.')
        length = len(value) // 2
    else:
        length = len(values['text'].encode('utf-8'))
    capacity = 165 if operation == 'send' else 131
    if type(reported) is not int or reported != length or length > capacity:
        raise ValueError('Recorded content count differs from actual content or Direct capacity.')
    if case_id == 'H5' and length != 131:
        raise ValueError('The fixed zero-hop Direct boundary case requires 131 content bytes.')
    if case_id == 'H4' and length != 0:
        raise ValueError('The fixed H4 round trip requires empty content.')
    return length


def _send_limit(operation, arguments, response_limit):
    """Bind this finite matrix's send allowance to canonical actual arguments."""
    common = {'port', 'json', 'verbose', 'timeout', 'init-timeout',
              'startup-delay', 'task-timeout'}
    business = {
        'send': {'send-channel', 'route-descriptor', 'path-hex', 'data-type', 'payload-hex', 'text'},
        'listen': {'receive-channel', 'max-entries', 'data-type', 'duration'},
        'ping': {'send-channel', 'route-descriptor', 'path-hex', 'receive-channel',
                 'max-entries', 'local-id', 'peer-id', 'content-hex', 'text', 'response-timeout'},
        'respond': {'send-channel', 'route-descriptor', 'path-hex', 'receive-channel',
                    'max-entries', 'local-id', 'peer-id', 'duration', 'max-responses'},
    }
    if not isinstance(arguments, list) or not all(isinstance(a, str) for a in arguments):
        raise ValueError('Require canonical option strings.')
    values = {}
    for argument in arguments:
        if argument in ('--json', '--verbose'):
            name, value = argument[2:], True
        else:
            match = re.fullmatch(r'--([a-z-]+)=(.*)', argument, re.DOTALL)
            if match is None:
                raise ValueError('Require canonical --name=value options.')
            name, value = match.groups()
        if name in values or name not in common | business[operation]:
            raise ValueError('Duplicate or unsupported matrix option.')
        values[name] = value
    if operation == 'listen':
        return 0
    route = values.get('route-descriptor')
    if not isinstance(route, str) or not re.fullmatch(r'(?:0+|0[xX]0+)', route) or values.get('path-hex') != '':
        raise ValueError('Require explicit zero-hop Direct and empty path.')
    if operation != 'respond':
        return 1
    responses = values.get('max-responses')
    if not isinstance(responses, str) or not re.fullmatch(r'[0-9]+', responses) or int(responses) != response_limit:
        raise ValueError('Responder limit differs from the finite case allocation.')
    return int(responses)


def _protocol_uint8_option(arguments, name):
    values = [a.split('=', 1)[1] for a in arguments if a.startswith('--' + name + '=')]
    if len(values) != 1:
        raise ValueError('Require one explicit protocol integer option.')
    value = values[0]
    if re.fullmatch(r'[0-9]+', value):
        number = int(value, 10)
    elif re.fullmatch(r'0[xX][0-9a-fA-F]+', value):
        number = int(value[2:], 16)
    else:
        raise ValueError('Protocol integer must use decimal or hexadecimal syntax.')
    if not 0 <= number <= 255:
        raise ValueError('Protocol integer must fit uint8.')
    return number


def validate_plan(plan, only_case=None):
    """No processes/devices/secrets: inspect both actual roles and B config."""
    if not isinstance(plan, dict) or not isinstance(plan.get('cases'), list):
        raise ValueError('Require the fixed ordered Direct matrix.')
    cases = [c for c in plan['cases'] if c['id'] != 'H0']
    if [c['id'] for c in cases] != list(_CASE_OPERATIONS) or plan.get('maximumApplicationSendAttempts') != 12:
        raise ValueError('Require the original fixed matrix and declared ceiling.')
    if only_case is not None:
        if only_case not in ('H2', 'H7'):
            raise ValueError('Unsupported single-case follow-up.')
        cases = [c for c in cases if c['id'] == only_case]
    root = Path(__file__).resolve().parents[1]
    executable = None
    limits = {}
    validated = []
    for case in cases:
        case_id = case['id']
        # Evaluation and persisted accounting must never discover missing or
        # invalid plan metadata after either endpoint has already executed.
        if type(case.get('contentBytes')) is not int or not 0 <= case['contentBytes'] <= 165:
            raise ValueError('Require an explicit datagram content byte count in 0..165.')
        expected_a = 69 if case_id == 'H6' else 130 if case_id == 'H7' else 0
        if type(case.get('expectedAExit')) is not int or case['expectedAExit'] != expected_a:
            raise ValueError('A expected exit differs from the fixed case result.')
        if ('expectedBExit' not in case or
                (case_id == 'H6' and case['expectedBExit'] is not None) or
                (case_id != 'H6' and (type(case['expectedBExit']) is not int or case['expectedBExit'] != 0))):
            raise ValueError('B expected exit differs from the fixed case result.')
        a_operation, b_operation = _CASE_OPERATIONS[case_id]
        a = case['aArgv']
        if (not isinstance(a, list) or len(a) < 3 or not all(isinstance(v, str) for v in a)
                or a[1:3] != ['datagram', a_operation] or not Path(a[0]).is_absolute()
                or Path(a[0]).name != 'meshctl' or Path(a[0]).parent.name != 'bin'):
            raise ValueError('Require the expected native A operation.')
        if executable is not None and a[0] != executable:
            raise ValueError('Use one native candidate throughout the matrix.')
        executable = a[0]
        a_limit = _send_limit(a_operation, a[3:], 2 if case_id == 'H7' else 1)
        initiating_operation, initiating_arguments = a_operation, a[3:]
        receive = None if a_operation == 'send' else _protocol_uint8_option(a[3:], 'receive-channel')
        b = case.get('bArgv')
        b_limit = 0
        if b_operation is None:
            if b is not None:
                raise ValueError('H6 must not launch a B responder.')
        else:
            if (not isinstance(b, list) or len(b) != 6 or not all(isinstance(v, str) for v in b)
                    or b[0] != '/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart'
                    or b[1] != 'run' or Path(b[2]).resolve() != root / 'apps/meshctl/tool/openhop_peer.dart'
                    or b[3] != '--config' or not Path(b[4]).is_absolute() or b[5] != b_operation):
                raise ValueError('Require the expected source-only B operation.')
            content = Path(b[4]).read_bytes()
            if len(content) > 65536:
                raise ValueError('Peer configuration exceeds its input limit.')
            config = json.loads(content)
            b_limit = _send_limit(b_operation, config['datagramArguments'], 1)
            if b_operation in ('send', 'ping'):
                initiating_operation, initiating_arguments = b_operation, config['datagramArguments']
        content_bytes = validate_content_length(case_id, initiating_operation, initiating_arguments, case['contentBytes'])
        limits[case_id] = {'A': a_limit, 'B': b_limit}
        if a_limit + b_limit != _CASE_LIMITS[case_id]:
            raise ValueError('Actual operations exceed or differ from the case allocation.')
        validated.append({**case, 'validatedAReceiveChannel': receive, 'validatedContentBytes': content_bytes})
    return validated, limits


class PendingCleanup(Exception):
    pass


class Run:
    def __init__(self, folder, label, argv, expected, env):
        self.folder = folder
        self.label = label
        self.argv = argv
        self.started = utc()
        self.origin = time.monotonic()
        self.expected = expected
        self.stdout = folder / (label + '.stdout.jsonl')
        self.stderr = folder / (label + '.stderr.txt')
        self.metadata = folder / (label + '.process.json')
        self.metadata.write_text(json.dumps({'argv': argv, 'startedUtc': self.started,
                                            'expectedExitCode': expected}, indent=2) + '\n')
        with self.stdout.open('x') as output, self.stderr.open('x') as error:
            self.process = subprocess.Popen(argv, stdout=output, stderr=error, env=env)
        self.record = None
        self.startup_observation_failure = False
        try:
            self.metadata.write_text(json.dumps({'argv': argv, 'startedUtc': self.started,
                                                'pid': self.process.pid,
                                                'expectedExitCode': expected}, indent=2) + '\n')
        except OSError:
            # Return the created process to its owner before reporting this
            # failure, so the case's finally block can still settle it.
            self.startup_observation_failure = True

    def events(self):
        result = []
        for line in self.stdout.read_text().splitlines():
            try:
                event = json.loads(line)
                if isinstance(event, dict):
                    result.append(event)
            except json.JSONDecodeError:
                pass
        return result

    def wait(self):
        if self.record is None:
            try:
                self.process.wait(timeout=max(1, 150 - (time.monotonic() - self.origin)))
            except subprocess.TimeoutExpired:
                self.snapshot()
                raise PendingCleanup('Process still active; no next conflicting connection: ' + str(self.process.pid))
        record = self.snapshot()
        if record['actualExitCode'] is None or cleanup(record) != 'succeeded':
            raise PendingCleanup('Cleanup not confirmed for ' + self.label)
        return record

    def snapshot(self):
        """Preserve observations even if the process/cleanup has not settled."""
        if self.record is not None:
            return self.record
        code = self.process.poll()
        events = self.events()
        final = next((e for e in reversed(events) if 'exitCode' in e and 'cleanup' in e), None)
        record = {'label': self.label, 'argv': self.argv, 'pid': self.process.pid,
            'startedUtc': self.started, 'endedUtc': utc() if code is not None else None,
            'observedUtc': utc(), 'expectedExitCode': self.expected,
            'actualExitCode': code, 'final': final, 'events': events,
            'stdoutFile': self.stdout.name, 'stderrFile': self.stderr.name,
            'cleanup': {'state': cleanup({'final': final}) or 'pending'},
            'forcedTermination': False}
        if code is not None:
            self.record = record
        self.metadata.write_text(json.dumps(record, indent=2) + '\n')
        return record

    def wait_event(self, name):
        deadline = self.origin + 25
        while time.monotonic() < deadline:
            if any(e.get('event') == name for e in self.events()):
                return True
            if self.process.poll() is not None:
                return False
            time.sleep(0.05)
        return False

    def guarded_window(self):
        # This is scheduling only, never a claimed A ready event. A's actual
        # datagram/PONG plus final stage determine readiness/evidence afterward.
        deadline = self.origin + 20
        while time.monotonic() < deadline:
            if self.process.poll() is not None or 'Error:' in self.stderr.read_text():
                return False
            time.sleep(0.05)
        return self.process.poll() is None


def evaluate(case, a, b, signaled=False, content_bytes=None, a_receive_channel=None):
    def okay(r):
        return r is not None and r['actualExitCode'] == 0 and cleanup(r) == 'succeeded'
    ar = ((a or {}).get('final') or {}).get('result') or {}
    br = ((b or {}).get('final') or {}).get('result') or {}
    if case == 'H1':
        return okay(a) and okay(b) and local_acceptance(a) and br.get('exactPayloadMatched') is True
    if case == 'H2':
        return (okay(a) and okay(b) and local_acceptance(b)
                and any(e.get('event') == 'datagram'
                        and e.get('channelIndex') == a_receive_channel
                        and e.get('dataType') == 65535
                        and e.get('payloadLength') == content_bytes
                        for e in a.get('events', [])))
    if case in ('H3', 'H5'):
        return (exact_pong(a or {}) and okay(b) and br.get('responseAttempts') == 1
                and br.get('localResponsesConfirmed') == 1 and local_acceptance(b))
    if case == 'H4':
        return (content_bytes == 0 and exact_pong(b or {}) and okay(a) and ar.get('responseAttempts') == 1
                and ar.get('localResponsesConfirmed') == 1 and local_acceptance(a))
    if case == 'H6':
        return (a is not None and a['actualExitCode'] == 69 and cleanup(a) == 'succeeded'
                and ar.get('reason') == 'responseTimeout' and local_acceptance(a)
                and ar.get('applicationRttUs') is None and ar.get('roundTripSucceeded') is False)
    if case == 'H7':
        return (signaled and exact_pong(b or {}) and a is not None
                and a['actualExitCode'] == 130 and cleanup(a) == 'succeeded'
                and a['final'].get('reason') == 'sigint' and ar.get('reason') == 'canceled'
                and ar.get('responseAttempts') == 1 and ar.get('localResponsesConfirmed') == 1
                and local_acceptance(a) and ar.get('lastSend', {}).get('pendingAtTermination') is False)
    return False


@contextmanager
def deferred_sigint():
    """Keep finite peers and evidence writes owned until cancellation is saved."""
    interruption = {'requested': False}
    previous = signal.getsignal(signal.SIGINT)
    def requested(signum, frame):
        interruption['requested'] = True
    signal.signal(signal.SIGINT, requested)
    try:
        yield interruption
    finally:
        signal.signal(signal.SIGINT, previous)


def settle_runs(runs):
    """Wait every started peer, including peers following a failed cleanup."""
    records, issues, interrupted = [], [], False
    for run in runs:
        while True:
            try:
                record = run.wait()
                break
            except KeyboardInterrupt:
                # Resume observing the same peer with its original deadline;
                # this is not a new process, connection or application attempt.
                interrupted = True
            except Exception as error:
                issues.append({'label': run.label, 'kind': type(error).__name__})
                while True:
                    try:
                        record = run.snapshot()
                        break
                    except KeyboardInterrupt:
                        interrupted = True
                    except Exception as observation_error:
                        record = {'label': run.label, 'argv': run.argv, 'pid': run.process.pid,
                                  'startedUtc': run.started, 'endedUtc': None, 'actualExitCode': None,
                                  'final': None, 'events': [], 'cleanup': {'state': 'pending'},
                                  'observationFailure': type(observation_error).__name__}
                        break
                break
        records.append(record)
        if record['actualExitCode'] is None or cleanup(record) != 'succeeded':
            if not any(i['label'] == run.label for i in issues):
                issues.append({'label': run.label, 'kind': 'CleanupNotConfirmed'})
    return records, issues, interrupted


def attempt_accounting(records, case_id, limits):
    known, upper, complete = 0, 0, True
    for record in records:
        side = record['label'][0]
        operation = _CASE_OPERATIONS[case_id][0 if side == 'A' else 1]
        final = record.get('final') or {}
        result = final.get('result') or {}
        session = (final.get('failure') or {}).get('session') or {}
        if operation in ('info', 'listen'):
            count = 0
        elif type(result.get('responseAttempts')) is int:
            count = result['responseAttempts']
        elif type((result.get('send') or {}).get('attempted')) is bool:
            count = int(result['send']['attempted'])
        elif session.get('stage') in ('opening', 'initializing') and session.get('commandOpcode') in (None, 0x16, 1):
            count = 0
        else:
            count = None
        if count is None or count < 0:
            complete = False
            upper += limits[side]
        else:
            known += count
            upper += count
    return {'applicationSendAttempts': known if complete else None,
            'knownApplicationSendAttempts': known,
            'applicationSendAttemptUpperBound': upper,
            'applicationSendAttemptsKnown': complete}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--only-case', choices=['H2', 'H7'])
    args = parser.parse_args()
    try:
        plan = json.loads(args.plan.read_text())
        cases, limits = validate_plan(plan, args.only_case)
    except (ValueError, KeyError, TypeError, OSError):
        parser.error('Invalid plan or peer configuration; check evaluation metadata, operations, Direct routes, and response limits.')
    allocation = sum(sum(side.values()) for side in limits.values())
    if not args.execute:
        print(json.dumps({'validated': True, 'deviceOrNetworkAccess': False,
                          'cases': [c['id'] for c in cases], 'maximumRfAttempts': allocation,
                          'applicationSendLimits': limits}))
        return
    args.output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, PATH='/opt/homebrew/share/flutter/bin:/usr/bin:' + os.environ['PATH'])
    root = Path(__file__).resolve().parents[1]
    baseline = json.loads((root/'build/phase-1b9/20261110T193252Z/hardware/execution-plan.json').read_text())
    executable = Path(cases[0]['aArgv'][0])
    candidate = executable.parent.parent
    actual = {name: hashlib.sha256((candidate/name).read_bytes()).hexdigest()
              for name in baseline['nativeHashes']}
    if actual != baseline['nativeHashes']:
        parser.error('Candidate native hashes changed; do not run against untested bytes.')
    manifest = {'createdUtc': utc(), 'nativeHashes': actual, 'plan': str(args.plan),
        'authorization': 'User requested continuation of real matrix and confirmed separate local modem. Initialization-only retries allowed under prior multiple-attempt instruction.',
        'maxInitializationInvocationsPerSide': 3, 'retryAfterAnyRfAttempt': False,
        'aReceiverSchedulingGuardSeconds': 20,
        'aReadinessEvidence': 'No A ready event exists; guard is scheduling only. Actual receive/PONG plus final reason/stage establish the result.',
        'rfAttemptCeiling': allocation, 'validatedApplicationSendLimits': limits, 'cases': cases,
        'sourceHashes': {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                         for p in sorted((root/'apps/meshctl/tool').rglob('*.dart'))},
        'driverSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (args.output/'execution-plan.json').write_text(json.dumps(manifest, indent=2)+'\n')
    # SIGINT stays deferred through peer settlement and evidence persistence.
    # New peers are refused once requested; already-owned finite peers retain
    # their original budgets and actual cleanup observations.
    with deferred_sigint() as interruption:
        code = execute_cases(args.output, cases, limits, allocation, env, interruption)
        if interruption['requested']:
            code = 130
    if code:
        raise SystemExit(code)


def execute_cases(output, cases, limits, allocation, env, interruption):
    results = []
    failed = False
    all_runs = []
    for case in cases:
        case_dir = output/case['id'];case_dir.mkdir()
        started = utc()
        runs = []
        def start(side, attempt):
            if interruption['requested']:
                raise KeyboardInterrupt
            run = Run(case_dir, side+'-'+str(attempt), case[side.lower()+'Argv'],
                      case['expected'+side+'Exit'], env)
            runs.append(run);all_runs.append(run)
            if getattr(run, 'startup_observation_failure', False):
                raise PendingCleanup('Process metadata not confirmed for ' + run.label)
            return run
        def sender(side, peer=None):
            for attempt in range(1,4):
                if peer is not None and peer.process.poll() is not None:
                    return None
                run = start(side,attempt);record = run.wait()
                if not initialization_failure(record):
                    return run
            return run
        def a_receiver():
            for attempt in range(1,4):
                run = start('A',attempt)
                if run.guarded_window():
                    return run
                if not initialization_failure(run.wait()):
                    return run
            return run
        a = b = None
        signaled = False
        error_kind = None
        stop_exit = 69
        try:
            if case['id'] in ('H1','H3','H5'):
                for attempt in range(1,4):
                    b = start('B',attempt)
                    name = 'peer_reception_active' if case['id']=='H1' else 'peer_session_ready'
                    if b.wait_event(name):
                        break
                    if not initialization_failure(b.wait()):
                        break
                if b.process.poll() is None and any(e.get('event')==name for e in b.events()):
                    a = sender('A',b)
            elif case['id'] in ('H2','H4','H7'):
                a = a_receiver()
                if a.process.poll() is None:
                    b = sender('B',a)
                    if case['id']=='H7' and b is not None and exact_pong(b.wait()):
                        if interruption['requested']:
                            raise KeyboardInterrupt
                        if a.process.poll() is None:
                            (case_dir/'signal-precondition.json').write_text(json.dumps({
                                'signalUtc':utc(),'bExactPongAndCleanupConfirmed':True,
                                'aStillActive':True,'aPid':a.process.pid},indent=2)+'\n')
                            try:
                                a.process.send_signal(signal.SIGINT);signaled=True
                            except ProcessLookupError:
                                signaled=False
            elif case['id']=='H6':
                assert all(r.process.poll() is not None for r in all_runs)
                a = sender('A')
        except (Exception, KeyboardInterrupt) as error:
            error_kind = type(error).__name__
            if isinstance(error, KeyboardInterrupt):
                interruption['requested'] = True
                stop_exit = 130
        finally:
            # A failed peer must not skip another finite peer's actual settlement.
            # No signals, new connection, resend, or forced termination is added.
            settled, cleanup_issues, settlement_interrupted = settle_runs(runs)
            interruption['requested'] |= settlement_interrupted
        if interruption['requested']:
            error_kind = error_kind or 'KeyboardInterrupt'
            stop_exit = 130
        ar = next((r for r in reversed(settled) if r['label'].startswith('A-')), None)
        br = next((r for r in reversed(settled) if r['label'].startswith('B-')), None)
        accounting = attempt_accounting(settled, case['id'], limits[case['id']])
        receive = case['validatedAReceiveChannel']
        evaluation_failure = None
        try:
            passed = not error_kind and not cleanup_issues and evaluate(case['id'], ar, br, signaled, case['contentBytes'], receive)
        except (Exception, KeyboardInterrupt) as error:
            # Final records and send facts are already settled. A faulty
            # evaluator must not prevent their persistence or allow a next case.
            evaluation_failure = type(error).__name__
            passed = False
            if isinstance(error, KeyboardInterrupt):
                interruption['requested'] = True
                stop_exit = 130
        if interruption['requested']:
            error_kind = error_kind or 'KeyboardInterrupt'
            stop_exit = 130
            passed = False
        unresolved = not accounting['applicationSendAttemptsKnown'] or any(r['actualExitCode'] is None for r in settled)
        budget_exceeded = accounting['applicationSendAttemptUpperBound'] > _CASE_LIMITS[case['id']]
        entry = {'id':case['id'],'status':'BLOCKED' if unresolved else 'PASS' if passed and not budget_exceeded else 'FAIL',
            'startedUtc':started,'endedUtc':None if unresolved else utc(),
            'expectedAExit':case['expectedAExit'],'actualAExit':None if ar is None else ar['actualExitCode'],
            'expectedBExit':case['expectedBExit'],'actualBExit':None if br is None else br['actualExitCode'],
            **accounting,'allInvocations':settled,'cleanupIncomplete':bool(cleanup_issues),
            'cleanupIssues':cleanup_issues,'orchestrationFailure':error_kind,
            'evaluationFailure':evaluation_failure,'interrupted':interruption['requested'],
            'signalAfterExactPong':signaled,'contentBytes':case['contentBytes']}
        results.append(entry)
        failed |= entry['status'] != 'PASS'
        known = sum(r['knownApplicationSendAttempts'] for r in results)
        upper = sum(r['applicationSendAttemptUpperBound'] for r in results)
        count_known = all(r['applicationSendAttemptsKnown'] for r in results)
        (output/'results.json').write_text(json.dumps({'cases':results,
            'actualApplicationSendAttempts':known if count_known else None,
            'knownApplicationSendAttempts':known,'applicationSendAttemptUpperBound':upper,
            'maximumApplicationSendAttempts':allocation},indent=2)+'\n')
        stopping = bool(error_kind or evaluation_failure or cleanup_issues or unresolved or budget_exceeded or upper > allocation)
        if stopping:
            (output/'STOPPED.json').write_text(json.dumps({'caseId':case['id'],
                'status':entry['status'],'orchestrationFailure':error_kind,
                'evaluationFailure':evaluation_failure,'interrupted':interruption['requested'],
                'cleanupIssues':cleanup_issues,**accounting,
                'activePids':[r['pid'] for r in settled if r['actualExitCode'] is None],
                'forcedTermination':False,'recordedUtc':utc()},indent=2)+'\n')
        print(json.dumps({k:v for k,v in entry.items() if k!='allInvocations'}),flush=True)
        if stopping:
            raise SystemExit(stop_exit)
    return 130 if interruption['requested'] else 69 if failed else 0


if __name__ == '__main__':
    main()
