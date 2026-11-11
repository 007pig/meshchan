#!/usr/bin/env python3
"""Generate reviewable finite H0-H7 commands/configurations; never perform I/O."""
import argparse
import json
import secrets
import shlex
from pathlib import Path


def validated_passive_report(proof, minimum_seconds):
    """Accept the probe's flat output and retained legacy execution wrappers."""
    if not isinstance(proof, dict):
        raise ValueError('Probe evidence must be an object.')
    wrapped = 'report' in proof
    if wrapped:
        if type(proof.get('actualExitCode')) is not int or proof['actualExitCode'] != 0:
            raise ValueError('Probe process did not exit successfully.')
        report = proof['report']
    else:
        report = proof
    if not isinstance(report, dict):
        raise ValueError('Probe report is missing.')
    exit_code = report.get('exitCode', 0 if wrapped else None)
    window = report.get('verifiedIdleWindowLowerBoundSeconds')
    if (type(exit_code) is not int or exit_code != 0 or report.get('status') != 'PASS'
            or report.get('cleanup') != 'succeeded'
            or report.get('noHostCommandsDuringObservation') is not True
            or type(window) is not int or window < minimum_seconds):
        raise ValueError('Probe must confirm successful passive observation and cleanup.')
    if ('initializationCompleted' in report and report['initializationCompleted'] is not True
            or any(report.get(key, 0) != 0 for key in ('applicationDatagramsSent', 'queueReadCommandsSent'))):
        raise ValueError('Probe must initialize without RF sends or queue reads.')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    args = parser.parse_args()
    data = json.loads(args.input.read_text())
    for field in ('sameChannelKeyConfirmed', 'radioCompatibleConfirmed',
                  'clientSlotsAvailable', 'sharedQueueConsumptionAccepted'):
        if data.get(field) is not True:
            parser.error('Confirm all radio, key, ownership, and queue prerequisites first.')
    for field in ('aSendChannel', 'aReceiveChannel', 'bSendChannel', 'bReceiveChannel'):
        value = data.get(field)
        if type(value) is not int or not 0 <= value <= 255:
            parser.error('All four local slots must be explicit uint8 values.')
    session = data['session']
    if session != {'commandSeconds': 5, 'initializationSeconds': 15,
                   'startupDelayMilliseconds': 0, 'taskSeconds': 90}:
        parser.error('This finite starting plan requires the documented 5/15/0/90 budgets.')
    exact_idle = data.get('idleTimeoutSeconds')
    observed_window = data.get('idleWindowLowerBoundSeconds')
    if type(exact_idle) is int and exact_idle >= 90 and observed_window is None:
        pass
    elif exact_idle is None and type(observed_window) is int and observed_window >= 90:
        try:
            proof = json.loads(Path(data['idleWindowEvidence']).read_text())
            validated_passive_report(proof, observed_window)
        except (OSError, ValueError, KeyError, TypeError):
            parser.error('Passive-window evidence must be an actual successful finite probe.')
    else:
        parser.error('Provide an exact timeout or verified passive window covering 90 seconds.')
    if not all(p.is_absolute() for p in (args.output, args.candidate)):
        parser.error('Use absolute output and candidate paths.')
    args.output.mkdir(parents=True, exist_ok=False)
    root = Path(__file__).resolve().parents[1]
    dart = '/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart'
    peer = root / 'apps/meshctl/tool/openhop_peer.dart'
    product = args.candidate / 'bin/meshctl'
    used = set()
    def identity():
        while True:
            value = secrets.randbelow(0xffffffff - 2) + 3
            if value not in used:
                used.add(value)
                return value
    def dump(name, obj):
        path = args.output / name
        path.write_text(json.dumps(obj, indent=2) + '\n')
        return path
    def peer_command(case, operation, params, payload=None):
        config = {k: data[k] for k in ('baseUrl', 'companionName', 'endpointLabel', 'jwt', 'session')}
        config['idleTimeoutSeconds'] = exact_idle
        config['session'] = dict(config['session'])
        if operation == 'ping':
            config['session']['taskSeconds'] = 60
        if observed_window is not None:
            config['idleWindowLowerBoundSeconds'] = observed_window
            config['idleWindowEvidence'] = data['idleWindowEvidence']
        config['datagramArguments'] = params
        if payload is not None:
            config['expectedPayloadHex'] = payload
        path = dump(case + '-b.json', config)
        return [dart, 'run', str(peer), '--config', str(path), operation]
    def common(side, op, ids, content):
        send = data[side + 'SendChannel']
        receive = data[side + 'ReceiveChannel']
        result = []
        if op != 'listen':
            result += [f'--send-channel={send}', '--route-descriptor=0', '--path-hex=']
        if op != 'send':
            result += [f'--receive-channel={receive}', '--max-entries=128']
        if op in ('ping', 'respond'):
            local, remote = ids if side == 'a' else ids[::-1]
            result += [f'--local-id={local}', f'--peer-id={remote}']
        if op in ('send', 'listen'):
            result += ['--data-type=65535']
        if op == 'send':
            result += ['--payload-hex=' + content]
        if op == 'ping':
            result += ['--content-hex=' + content, '--response-timeout=20']
        if op in ('listen', 'respond'):
            result += ['--duration=60']
        if op == 'respond':
            result += ['--max-responses=1']
        return result
    def a_command(op, params):
        return [str(product), 'datagram', op, '--port=' + data['aPort'], '--json',
                '--timeout=5', '--init-timeout=15', '--startup-delay=0',
                '--task-timeout=' + ('60' if op == 'ping' else '90'), *params]
    plan = []
    for case, a_op, b_op in [('H1', 'send', 'listen'), ('H2', 'listen', 'send'),
                             ('H3', 'ping', 'respond'), ('H4', 'respond', 'ping'),
                             ('H5', 'ping', 'respond'), ('H6', 'ping', None),
                             ('H7', 'respond', 'ping')]:
        ids = [identity(), identity()]
        content = (bytes([0, 0x11, 0x13, 0x3c, 0x3e, 0x80, 0xff]) + secrets.token_bytes(8)).hex()
        if case == 'H4':
            content = ''
        if case == 'H5':
            # Both actual starting routes are zero-hop Direct: min(165-34,165-34).
            content = (bytes([0, 0x11, 0x13, 0x3c, 0x3e, 0x80, 0xff]) + secrets.token_bytes(124)).hex()
        a_params = common('a', a_op, ids, content)
        if case == 'H7':
            a_params[a_params.index('--max-responses=1')] = '--max-responses=2'
        a_cmd = a_command(a_op, a_params)
        b_cmd = peer_command(case, b_op, common('b', b_op, ids, content),
                             content if b_op == 'listen' else None) if b_op else None
        plan.append({'id': case, 'status': 'NOT_RUN', 'aTestId': ids[0], 'bTestId': ids[1],
                     'contentBytes': len(content) // 2, 'aArgv': a_cmd, 'bArgv': b_cmd,
                     'expectedAExit': 69 if case == 'H6' else 130 if case == 'H7' else 0,
                     'expectedBExit': 0 if b_cmd else None,
                     'receiverFirst': 'B' if case in ('H1', 'H3', 'H5') else 'A',
                     'actualAExit': None, 'actualBExit': None})
    info = {k: data[k] for k in ('baseUrl', 'companionName', 'endpointLabel', 'jwt', 'session')}
    info['idleTimeoutSeconds'] = exact_idle
    if observed_window is not None:
        info['idleWindowLowerBoundSeconds'] = observed_window
    info_path = dump('H0-b.json', info)
    plan.insert(0, {'id': 'H0', 'status': 'NOT_RUN',
                   'aArgv': [str(product), 'info', '--port=' + data['aPort'], '--json'],
                   'bArgv': [dart, 'run', str(peer), '--config', str(info_path), 'info'],
                   'expectedAExit': 0, 'expectedBExit': 0, 'actualAExit': None, 'actualBExit': None})
    dump('plan.json', {'schemaVersion': 1, 'expectedApplicationDatagrams': 11,
                       'maximumApplicationSendAttempts': 12, 'cases': plan})
    lines = ['# Reviewable commands; do not execute until this finite matrix is authorized.',
             'export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"',
             '# Run receiver first; preserve final results and require actual cleanup.',
             '# B: await peer_reception_active (raw) / peer_session_ready (tasks).',
             '# A has no raw/respond ready event. A-start/process/sleep proves no readiness.',
             '# H7: after B exact PONG and while A is active, SIGINT that A PID only.',
             '# H6: all previous responders must have completed with successful cleanup.',
             '# Do not rerun cases or automatically reconnect after failure.']
    for case in plan:
        lines += ['\n# ' + case['id']]
        for side in ('a', 'b'):
            command = case.get(side + 'Argv')
            if command:
                lines += ['# ' + side.upper(), shlex.join(command)]
    (args.output / 'commands.txt').write_text('\n'.join(lines) + '\n')
    print(args.output)


if __name__ == '__main__':
    main()
